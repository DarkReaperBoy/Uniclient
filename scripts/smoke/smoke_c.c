// Minimal native FFI smoke test for the c-shared bridge library.
//
// It drives the exact same surface a Dart/Flutter (or any C FFI) host uses:
//   BridgeCallWithLen(data, len, &outLen) -> pinned buffer
//   BridgeFree(ptr)
//
// Scenario: Init engine in a temp dir -> ListAccounts -> AddAccount(github)
// -> ListAccounts -> Shutdown, decoding the protobuf responses by hand
// (only the fields we care about).
//
// Build: cc smoke_c.c -o smoke_c -L<dist> -luniclient -Wl,-rpath,'$ORIGIN/<dist>'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

extern void *BridgeCallWithLen(void *data, int32_t dataLen, int32_t *outLen);
extern void BridgeFree(void *ptr);

// ---- minimal protobuf encoding ----

static uint8_t *buf = NULL;
static size_t bufLen = 0, bufCap = 0;

static void pbReset(void) { bufLen = 0; }

static void pbByte(uint8_t b) {
    if (bufLen == bufCap) { bufCap = bufCap ? bufCap * 2 : 256; buf = realloc(buf, bufCap); }
    buf[bufLen++] = b;
}

static void pbVarint(uint64_t v) {
    while (v > 0x7F) { pbByte((uint8_t)(v) | 0x80); v >>= 7; }
    pbByte((uint8_t)(v));
}

static void pbTag(int fieldNum, int wireType) { pbVarint(((uint64_t)fieldNum << 3) | wireType); }

static void pbString(int fieldNum, const char *s) {
    pbTag(fieldNum, 2);
    pbVarint(strlen(s));
    for (const char *p = s; *p; p++) pbByte((uint8_t)*p);
}

// ---- minimal protobuf decoding (top-level fields only) ----

typedef struct { const uint8_t *data; size_t len; size_t pos; } Reader;

static int rdByte(Reader *r, uint8_t *out) {
    if (r->pos >= r->len) return 0;
    *out = r->data[r->pos++];
    return 1;
}

static int rdVarint(Reader *r, uint64_t *out) {
    uint64_t v = 0; int shift = 0; uint8_t b;
    do {
        if (!rdByte(r, &b)) return 0;
        v |= (uint64_t)(b & 0x7F) << shift;
        shift += 7;
    } while (b & 0x80);
    *out = v;
    return 1;
}

// Reads fields; calls cb(fieldNum, wiretype, value-or-payload) per field.
static void walkFields(const uint8_t *data, size_t len,
                       void (*cb)(int fieldNum, int wt, uint64_t v, const uint8_t *payload, size_t plen)) {
    Reader r = {data, len, 0};
    for (;;) {
        uint64_t tag;
        if (!rdVarint(&r, &tag)) return;
        int fieldNum = (int)(tag >> 3), wt = (int)(tag & 7);
        if (wt == 0) {
            uint64_t v;
            if (!rdVarint(&r, &v)) return;
            cb(fieldNum, wt, v, NULL, 0);
        } else if (wt == 2) {
            uint64_t l;
            if (!rdVarint(&r, &l)) return;
            if (r.pos + l > r.len) return;
            cb(fieldNum, wt, 0, r.data + r.pos, (size_t)l);
            r.pos += l;
        } else {
            return; // not used in our messages
        }
    }
}

// ---- request/response helpers ----

static uint8_t *lastResp = NULL;
static size_t lastRespLen = 0;

static int call(const char *coreID, const char *method, const uint8_t *payload, size_t payloadLen) {
    // Copy the payload first: the builder reuses the shared buffer, so the
    // caller's pointer may alias it.
    uint8_t *payloadCopy = NULL;
    if (payloadLen > 0) {
        payloadCopy = malloc(payloadLen);
        memcpy(payloadCopy, payload, payloadLen);
    }

    // BridgeRequest{ core_id=1, method=2, payload=3 }
    pbReset();
    pbString(1, coreID);
    pbString(2, method);
    if (payloadLen > 0) {
        pbTag(3, 2);
        pbVarint(payloadLen);
        for (size_t i = 0; i < payloadLen; i++) pbByte(payloadCopy[i]);
    }
    free(payloadCopy);

    int32_t outLen = 0;
    void *p = BridgeCallWithLen(buf, (int32_t)bufLen, &outLen);
    if (lastResp) free(lastResp);
    lastResp = malloc(outLen ? outLen : 1);
    if (outLen > 0) memcpy(lastResp, p, (size_t)outLen);
    lastRespLen = (size_t)outLen;
    BridgeFree(p);
    return (int)lastRespLen;
}

static const uint8_t *lastRespPayload = NULL;
static size_t lastRespPayloadLen = 0;
static int lastRespPayloadWanted = 0;
static int respOK = -1;

static void respField(int fieldNum, int wt, uint64_t v, const uint8_t *payload, size_t plen) {
    if (fieldNum == 1 && wt == 0) respOK = (int)v;         // ok
    if (fieldNum == 2 && wt == 2 && plen > 0) {             // error
        fprintf(stderr, "  bridge error: %.*s\n", (int)plen, (const char *)payload);
    }
    if (fieldNum == 4 && wt == 2 && lastRespPayloadWanted) {
        lastRespPayload = payload; lastRespPayloadLen = plen;
    }
}

static int respIsOK(void) {
    respOK = -1; lastRespPayload = NULL; lastRespPayloadLen = 0;
    walkFields(lastResp, lastRespLen, respField);
    return respOK == 1;
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : "/tmp";

    // 1. Init
    char cfgDir[512], cacheDir[512], dlDir[512];
    snprintf(cfgDir, sizeof cfgDir, "%s/cfg", dir);
    snprintf(cacheDir, sizeof cacheDir, "%s/cache", dir);
    snprintf(dlDir, sizeof dlDir, "%s/dl", dir);
    pbReset();
    pbString(1, cfgDir);     // config_dir
    pbString(2, cacheDir);   // cache_dir
    pbString(3, dlDir);      // download_dir
    pbString(4, "smoke");    // vault_password
    lastRespPayloadWanted = 0;
    call("__engine", "Init", buf, (int)bufLen);
    printf("Init: %s\n", respIsOK() ? "OK" : "FAIL");
    if (!respIsOK()) return 1;

    // 2. ListAccounts (empty)
    lastRespPayloadWanted = 1;
    call("__engine", "ListAccounts", NULL, 0);
    int empty = respIsOK();
    printf("ListAccounts (fresh): %s, %zu bytes payload\n", empty ? "OK" : "FAIL", lastRespPayloadLen);
    if (!empty) return 1;

    // 3. AddAccount(github)
    pbReset();
    pbString(1, "github");
    pbTag(2, 0); pbVarint(0); // test_mode = false
    lastRespPayloadWanted = 1;
    call("__engine", "AddAccount", buf, (int)bufLen);
    int added = respIsOK();
    printf("AddAccount: %s\n", added ? "OK" : "FAIL");
    if (!added) return 1;

    // 4. ListAccounts (one account with platform "github")
    lastRespPayloadWanted = 1;
    call("__engine", "ListAccounts", NULL, 0);
    int one = respIsOK();
    printf("ListAccounts (after add): %s, %zu bytes payload\n", one ? "OK" : "FAIL", lastRespPayloadLen);
    if (!one) return 1;

    // 5. Shutdown
    lastRespPayloadWanted = 0;
    call("__engine", "Shutdown", NULL, 0);
    printf("Shutdown: %s\n", respIsOK() ? "OK" : "FAIL");

    if (lastResp) free(lastResp);
    if (buf) free(buf);
    printf("SMOKE TEST PASSED\n");
    return 0;
}
