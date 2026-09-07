// Minimal js/wasm smoke test for the bridge module, run under Node.
//
// It drives the exact same surface a browser frontend uses:
//   globalThis.bridgeCall(Uint8Array) -> Uint8Array
//
// Scenario: Init engine in a temp dir -> ListAccounts -> AddAccount(github)
// -> ListAccounts -> Shutdown, with hand-rolled protobuf encode/decode.
//
// Run: node smoke_wasm.mjs <path-to-uniclient.wasm> <tmpdir>
import { readFileSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";

const wasmPath = process.argv[2] || "../../dist/uniclient.wasm";
const dir = process.argv[3] || "/tmp/uniclient-wasm-smoke";

// ---- load the module with the official Go wasm bootstrap ----
const go = new Go(); // provided by wasm_exec.js
const wasmBytes = readFileSync(wasmPath);
const { instance } = await WebAssembly.instantiate(wasmBytes, go.importObject);
// Run to completion of main(): it registers bridgeCall and blocks forever,
// so detach the goroutine runtime instead of awaiting it.
go.run(instance);
if (typeof globalThis.bridgeCall !== "function") {
  console.error("FATAL: globalThis.bridgeCall was not registered by the wasm module");
  process.exit(1);
}

// ---- minimal protobuf encode ----
class Writer {
  constructor() { this.buf = []; }
  byte(b) { this.buf.push(b & 0xff); }
  varint(v) { v = BigInt(v); while (v > 0x7fn) { this.byte(Number(v & 0x7fn) | 0x80); v >>= 7n; } this.byte(Number(v)); }
  tag(field, wt) { this.varint((BigInt(field) << 3n) | BigInt(wt)); }
  str(field, s) {
    this.tag(field, 2);
    const bytes = Array.from(new TextEncoder().encode(s));
    this.varint(bytes.length);
    for (const b of bytes) this.byte(b);
  }
  bytes(field, arr) {
    this.tag(field, 2);
    this.varint(arr.length);
    for (const b of arr) this.byte(b);
  }
  finish() { return new Uint8Array(this.buf); }
}

// ---- minimal protobuf decode ----
function* fields(data) {
  let pos = 0;
  const varint = () => {
    let v = 0n, shift = 0n;
    for (;;) {
      if (pos >= data.length) throw new Error("truncated varint");
      const b = data[pos++];
      v |= BigInt(b & 0x7f) << shift;
      if ((b & 0x80) === 0) return v;
      shift += 7n;
    }
  };
  while (pos < data.length) {
    const tag = varint();
    const fieldNum = Number(tag >> 3n), wt = Number(tag & 7n);
    if (wt === 0) {
      yield { fieldNum, wt, value: varint() };
    } else if (wt === 2) {
      const len = Number(varint());
      yield { fieldNum, wt, payload: data.subarray(pos, pos + len) };
      pos += len;
    } else {
      throw new Error(`unsupported wire type ${wt}`);
    }
  }
}

// ---- bridge helpers ----
// bridgeCall returns a Promise: js/wasm is single-threaded, so the Go side
// must dispatch on its own goroutine to let fs callbacks run on the event
// loop (see go/cmd/bridge/main_js.go).
async function call(coreId, method, payload) {
  const w = new Writer();
  w.str(1, coreId);
  w.str(2, method);
  if (payload && payload.length > 0) w.bytes(3, Array.from(payload));
  const resp = await globalThis.bridgeCall(w.finish());
  if (!resp || resp.length === 0) throw new Error(`bridgeCall(${method}) returned empty`);
  let ok = null, error = "", respPayload = null;
  for (const f of fields(resp)) {
    if (f.fieldNum === 1 && f.wt === 0) ok = f.value === 1n;
    if (f.fieldNum === 2 && f.wt === 2) error = new TextDecoder().decode(f.payload);
    if (f.fieldNum === 4 && f.wt === 2) respPayload = f.payload;
  }
  if (ok !== true) throw new Error(`${method} failed: ${error}`);
  // The engine layer nests its own ok/error inside the payload
  // (EngineInitResponse, etc.) — surface those too.
  if (respPayload && method === "Init") {
    let innerOk = null, innerErr = "";
    for (const f of fields(respPayload)) {
      if (f.fieldNum === 1 && f.wt === 0) innerOk = f.value === 1n;
      if (f.fieldNum === 2 && f.wt === 2) innerErr = new TextDecoder().decode(f.payload);
    }
    if (innerOk === false) throw new Error(`Init failed: ${innerErr}`);
  }
  return respPayload;
}

// ---- scenario ----
rmSync(dir, { recursive: true, force: true });
for (const d of ["cfg", "cache", "dl"]) mkdirSync(join(dir, d), { recursive: true });

// 1. Init
const initReq = new Writer();
initReq.str(1, join(dir, "cfg"));
initReq.str(2, join(dir, "cache"));
initReq.str(3, join(dir, "dl"));
initReq.str(4, "smoke");
await call("__engine", "Init", initReq.finish());
console.log("Init: OK");

// 2. ListAccounts (empty)
let p = await call("__engine", "ListAccounts", null);
if (p && p.length > 0) throw new Error(`fresh engine has accounts: ${p.length} bytes`);
console.log("ListAccounts (fresh): OK, empty");

// 3. AddAccount(github)
const addReq = new Writer();
addReq.str(1, "github");
addReq.tag(2, 0); addReq.varint(0); // test_mode = false
p = await call("__engine", "AddAccount", addReq.finish());
let accountId = "";
if (p) {
  for (const f of fields(p)) {
    if (f.fieldNum === 1 && f.wt === 2) accountId = new TextDecoder().decode(f.payload);
  }
}
if (!accountId) throw new Error("AddAccount returned no account id");
console.log(`AddAccount: OK (${accountId})`);

// 4. ListAccounts (one github account)
p = await call("__engine", "ListAccounts", null);
let platforms = [];
if (p) {
  for (const f of fields(p)) {
    if (f.fieldNum === 1 && f.wt === 2) {
      for (const a of fields(f.payload)) {
        if (a.fieldNum === 2 && a.wt === 2) platforms.push(new TextDecoder().decode(a.payload));
      }
    }
  }
}
if (platforms.length !== 1 || platforms[0] !== "github") {
  throw new Error(`expected exactly 1 github account, got: ${JSON.stringify(platforms)}`);
}
console.log("ListAccounts (after add): OK, [github]");

// 5. Shutdown
await call("__engine", "Shutdown", null);
console.log("Shutdown: OK");

console.log("SMOKE TEST PASSED");
