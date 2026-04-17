# ZeroC Ice Wire Protocol Notes (for Mumble admin)

Pure-Go Ice client implementation notes for talking to Murmur's Ice RPC interface. See also: `research/mumble_protocol.md` for the Mumble client protocol.

## Protocol Version

Murmur 1.5.857 ships with Ice 3.7.10. Server requires:
- Protocol version: 1.0
- Encoding version: 1.0 (NOT 1.1 — server rejects 1.1 in the message header)

## Message Header (14 bytes, all messages)

```
Offset  Size  Field
0-3     4     Magic: "IceP" (0x49 0x63 0x65 0x50)
4       1     Protocol major (1)
5       1     Protocol minor (0)
6       1     Encoding major (1)
7       1     Encoding minor (0)
8       1     Message type: 0=Request, 2=Reply, 3=ValidateConnection, 4=CloseConnection
9       1     Compression: 0=none
10-13   4     Total message size (LE int32, includes this 14-byte header)
```

## Connection Flow

1. TCP connect to Murmur Ice port (default 6502, from `ice="tcp -h 127.0.0.1 -p 6502"` in murmur.ini)
2. Client sends ValidateConnection (14 bytes, no body)
3. Server replies with ValidateConnection
4. Client sends Request messages, server sends Reply messages
5. Client sends CloseConnection when done

## Request Body (after header)

```
requestId     : int32 LE (sequential, non-zero for two-way calls)
identity.name : string (size-prefixed)
identity.cat  : string (size-prefixed)
facet         : StringSeq (size + strings, usually size=0)
operation     : string (method name)
mode          : byte (0=Normal, 2=Idempotent)
context       : Dict<string,string> (size + key/value string pairs)
params        : Encapsulation
```

## Reply Body

```
requestId   : int32 LE
replyStatus : byte (0=OK, 1=UserException, 2=ObjectNotExist, 4=OpNotExist, 5=UnknownLocal)
result      : Encapsulation (for OK) or exception string (for errors)
```

## Encapsulation Format (CRITICAL)

```
size           : int32 LE (includes ALL 6 header bytes: 4 size + 2 encoding ver)
encodingMajor  : byte (1)
encodingMinor  : byte (0)
payload        : bytes
```

**SIZE COMES FIRST, THEN ENCODING VERSION.** Getting this wrong causes `UnmarshalOutOfBoundsException`.
Empty encapsulation = `06 00 00 00 01 00` (size=6, encoding 1.0, no payload).

## String/Size Encoding

- Size < 255: 1 byte
- Size >= 255: byte 0xFF + int32 LE
- String = size + UTF-8 bytes (NOT null-terminated)

## Murmur Servant Identities

- Meta: {name: "Meta", category: ""}
- Server N: {name: "N", category: "s"} — e.g., server 1 = {name: "1", category: "s"}

Server servants are registered via a `ServerLocator` with category "s".

## Authentication

Pass `icesecretwrite` from murmur.ini as a context entry:
```
context = {"secret": "<icesecretwrite value>"}
```

## Tested Methods (Server servant)

All tested against Murmur 1.5.857 + Ice 3.7.10:

| Method | Mode | Params | Returns |
|--------|------|--------|---------|
| getUptime | idempotent | (none) | int (seconds) |
| getLog | idempotent | int first, int last | LogEntry[] (int ts + string txt) |
| setConf | idempotent | string key, string value | void |
| updateCertificate | idempotent | string cert, string key, string passphrase | void |
| redirectWhisperGroup | idempotent | int session, string source, string target | void |
| addContextCallback | normal | int session, string action, string text, proxy cb, int ctx | void |
| removeContextCallback | normal | proxy cb | void |

## Callback Proxy Encoding

For `addContextCallback`, the callback proxy is encoded as:
```
identity.name     : string
identity.category : string
facet             : StringSeq (size=0)
mode              : byte (0=twoway)
secure            : byte (0=false)
proto version     : 2 bytes (1, 0)
encoding version  : 2 bytes (1, 0)
endpoint count    : size (1)
endpoint type     : int16 LE (1=TCP)
endpoint data     : Encapsulation {host: string, port: int32, timeout: int32(-1), compress: byte(0)}
```
No adapter ID when endpoint count > 0 (direct binding).

## NixOS Setup

```nix
# murmur package: nixpkgs#murmur (v1.5.857)
# Has Ice compiled in: -Dice:BOOL=TRUE
# Ice 3.7.10 bundled
```

murmur.ini for testing:
```ini
ice="tcp -h 127.0.0.1 -p 6502"
icesecretread=testsecret
icesecretwrite=testsecret
```

Start: `mumble-server -ini murmur.ini -fg`
