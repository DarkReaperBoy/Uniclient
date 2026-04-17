# TeamSpeak 3 UDP Client Protocol

Reverse-engineered from tsproto (Rust reference implementation) and verified against avanor-gaming.de:9987.
Updated 2026-04-09: rewritten for real UDP client protocol (replaces old ServerQuery doc).

## Overview

TS3 uses a custom UDP binary protocol on port 9987 (default). This is the **real client protocol**, not the ServerQuery TCP interface (port 10011). Our implementation connects as a native TS3 voice client.

Reference implementation: [tsproto](https://github.com/ReSpeak/tsproto) (Rust)

## Packet Structure

### Client to Server (C2S)
```
MAC(8) + PId(2) + CId(2) + PT(1) + Data(...)
```
- MAC: 8-byte EAX MAC tag (or `TS3INIT1` for init packets)
- PId: packet ID (sequence number)
- CId: client ID (0 during init)
- PT: packet type byte (type in lower 4 bits, flags in upper 4 bits)

### Server to Client (S2C)
```
MAC(8) + PId(2) + PT(1) + Data(...)
```
- No CId field (server doesn't include it in S2C packets)

### Packet Types (lower 4 bits)
| Value | Type |
|-------|------|
| 0x00 | Voice |
| 0x01 | VoiceWhisper |
| 0x02 | Command |
| 0x03 | CommandLow |
| 0x04 | Ping |
| 0x05 | Pong |
| 0x06 | ACK |
| 0x07 | ACKLow |
| 0x08 | Init |

### Flags (upper 4 bits)
| Bit | Flag |
|-----|------|
| 0x10 | Fragmented (FR) |
| 0x20 | Newprotocol |
| 0x40 | Compressed |
| 0x80 | Unencrypted |

## 5-Step Init Handshake

### Init0 (C->S)
```
Header: MAC="TS3INIT1" PId=101 CId=0 PT=0x88
Data: version(4) + step=0(1) + timestamp(4) + random0(4) + reserved(8)
```
- version: `1466672534 - 1356998400 = 109674134` (0x068AACA6)
- timestamp: current Unix time

### Init1 (S->C)
```
Data: step=1(1) + random1(16) + random0_reversed(4)
```
- Server echoes back random0 reversed, plus its own random1

### Init2 (C->S)
```
Data: version(4) + step=2(1) + random1(16) + random0_reversed(4)
```

### Init3 (S->C)
```
Data: step=3(1) + x(100) + n(64) + level(4) + random2(100)
```
- RSA puzzle: find `y` such that `y^(2^level) mod n == x`
- level is typically 1000000 (fast)

### Init4 (C->S)
```
Data: version(4) + step=4(1) + x(100) + n(64) + level(4) + random2(100) + y(100) + clientek_command(...)
```
- y: RSA puzzle solution (PKCS1v15 decrypt x with n, verify with SHA-1)
- clientek_command: `clientek` command with client's ECDH public key (omega) and hashcash proof

## Encryption

### AES-128-EAX
- 128-bit key, 128-bit nonce, 8-byte truncated MAC tag
- Key/nonce derived from shared secret (ECDH output) via SHA-512:
  - `SHA512("b9dfaa7bee6ac57ac7b65f1094a1c155e747327bc2fe5d51c512023fe54a280201004e90ad1daaae1075d53b7d571c30e063b5a62a4a017bb394833aa0983e6e" + shared_iv)`
  - First 32 bytes -> temp key material
  - Further derivation per packet type and direction

### FAKE_KEY / FAKE_NONCE
Used for the first encrypted commands (clientek, initivexpand2) before real key exchange:
- FAKE_KEY: `0x63, 0x3A, 0x5C, 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73, 0x5C, 0x73, 0x79, 0x73, 0x74, 0x65` ("c:\windows\syste")
- FAKE_NONCE: `0x6D, 0x5C, 0x66, 0x69, 0x72, 0x65, 0x77, 0x61, 0x6C, 0x6C, 0x33, 0x32, 0x2E, 0x63, 0x70, 0x6C` ("m\firewall32.cpl")

### Shared MAC
8-byte MAC for unencrypted packets, derived from shared IV:
```
SHA1(shared_iv[0:26])[:8]
```

## Identity & Hashcash

### P-256 Identity
- Client generates a P-256 (secp256r1) ECDSA keypair
- Public key exported as `omega` parameter (base64 of ASN.1 DER)
- Private scalar `d`, public point `(x, y)` stored in session

### Hashcash Proof-of-Work
- Server requires minimum security level 8 (trailing zero bits in SHA-1)
- Hash: `SHA1(omega_base64 + counter_string)`
- Count trailing zero bits per byte (LSB first): `0x00` = 8 bits, then check next byte
- Client iterates counter from 0 until sufficient level found
- Counter saved in session as `key_offset` to avoid recomputation

## Command Format

TS3 commands use a key=value text format:
```
command_name key1=value1 key2=value2|key1=value3 key2=value4
```
- Pipe `|` separates multiple entries (e.g., channellist returns all channels pipe-separated)
- Escape sequences: `\\` -> `\`, `\/` -> `/`, `\s` -> space, `\p` -> `|`, `\a` -> BEL, `\b` -> BS, `\f` -> FF, `\n` -> LF, `\r` -> CR, `\t` -> TAB, `\v` -> VT

### Key Commands
| Command | Direction | Purpose |
|---------|-----------|---------|
| `clientek` | C->S | Client ECDH public key + proof |
| `initivexpand2` | S->C | Server ECDH key + shared IV |
| `clientinit` | C->S | Client name, version, platform |
| `initserver` | S->C | Server info (welcome message, server ID, client ID) |
| `channellist` | S->C | All channels (automatic after connect) |
| `channellistfinished` | S->C | End of channel list |
| `notifyclienterenterview` | S->C | Client joined (includes us + all online clients) |
| `sendtextmessage` | C->S | Send text message |
| `notifytextmessage` | S->C | Received text message |
| `clientdisconnect` | C->S | Graceful disconnect |

### sendtextmessage targets
- `targetmode=3` -- server chat
- `targetmode=2` -- channel chat (current channel)
- `targetmode=1` -- private message (specify `target=clid`)

## QuickLZ Level 1

Compressed packets use QuickLZ Level 1 compression. Header format:

### Header
```
Byte 0: flags (bit 0 = compressed, bit 2 = header length flag)
```
- If `flags & 0x02 != 0`: **long header** (9 bytes): compressed_size(4) + decompressed_size(4) at offsets 1 and 5
- Otherwise: **short header** (3 bytes): compressed_size(1) + decompressed_size(1) at offsets 1 and 2

### Decompression Algorithm
- Control word: 32-bit shift register, consumed 1 bit at a time
- Bit = 1: back-reference (match copy from earlier output)
  - 2-byte ref: `((next[0]>>4) + 3)` length, `((next[0]&0x0f)<<8 | next[1])` offset
  - 3-byte ref: `next[2]` length, `((next[0]&0x0f)<<8 | next[1])` offset
- Bit = 0: literal byte copy
- Hash table (4096 entries) for fast lookups: `hash = ((v >> 12) ^ v) & 0xFFF` on 24-bit values
- Byte-by-byte copy for overlapping matches (required for RLE patterns)

## Packet Reordering

UDP packets may arrive out of order. Implementation must:
1. Buffer received packets in a `recvQueue` keyed by packet ID
2. Track `nextRecvID` -- the next expected sequential packet ID
3. After receiving any packet, drain the queue in order starting from `nextRecvID`
4. Only process commands when all preceding packets have been received

## Fragment Reassembly

Large commands are split across multiple packets:
1. **First fragment**: FR flag set, may also have Compressed flag
2. **Middle fragments**: NO flags (0x00)
3. **Last fragment**: FR flag set again

Decompression happens AFTER full reassembly, not per-fragment.

## Connection Lifecycle

1. Init0->Init4 handshake (UDP)
2. clientek (FAKE encrypted) -- send ECDH public key
3. initivexpand2 (FAKE encrypted) -- receive server ECDH key, derive shared secret
4. Switch to real AES-128-EAX encryption
5. clientinit -- send client name/version/platform
6. Receive: initserver, channellist (all channels), notifyclienterenterview (all online clients), channellistfinished
7. Connection established -- send/receive commands, voice
8. clientdisconnect to close

## Core Interface Mapping

| Core Method | Implementation | Notes |
|-------------|---------------|-------|
| Authenticate | Full UDP handshake + clientinit | Identity key + hashcash |
| GetDialogs | Cached channellist data | From handshake, not queryable |
| GetMembers | Cached notifyclienterenterview | Online clients from handshake |
| SendMessage | sendtextmessage (mode 1/2/3) | Server, channel, or private |
| GetProfile | Cached client info | From notifyclienterenterview |
| Close | clientdisconnect | Graceful UDP disconnect |

### Full Implementation
All commands and notifications listed below are implemented (189 methods). Voice packet transport (send/receive, whisper, group whisper) is implemented with EAX encryption. Opus codec encode/decode is the only remaining piece.

### Not Supported by TS3 Protocol
- EditMessage/DeleteMessage (TS3 has no concept of editing/deleting sent messages)
- ReactToMessage/PinMessage (TS3 has no reactions or pinned messages)

## Quirks & Gotchas

<!-- Discovered 2026-04-09 -->
- **Server command pIDs start at 1** after handshake. The initivexpand2 command is pID 0 (received during init, before receive loop starts). The next server command (initserver) arrives as pID 1. Fixed 2026-04-13: was incorrectly set to 2, causing initserver to be stuck in the reorder queue.
- **channellist is NOT a queryable command** in client protocol -- it's automatically sent during connection setup. Use cached data from handshake.
- **Unencrypted ACKs** (type 0x86 = Unencrypted|ACK) must not be decrypted -- check the Unencrypted flag before AES-EAX decrypt.
- **Error 519** ("could not validate client identity") means the hashcash proof-of-work level is too low or key_offset is wrong. Recompute if session doesn't have it.
- **Error 521** ("too many clones") means another client with the same identity is connected. Wait for server timeout (~30s) before reconnecting.
- **Pipe-separated entries**: `tsParseCommand` returns a single map and loses multi-entry data. Use raw split on `|` for channellist and similar bulk commands.
- **Command/response routing**: when a background command loop (`tsCommandLoop`) is running and `tsExec` needs to send a command and wait for response, route via a separate `execCh` channel to prevent both competing for the same `cmdCh`.

## Voice Packet Structure

Voice packets are EAX encrypted just like command packets, using the same key/nonce derivation. They are **NOT acknowledged** — fire and forget over UDP.

### Normal Voice C2S (packet type 0x00)
```
PacketCounter(2) + Codec(1) + AudioData(...)
```
- PacketCounter: big-endian uint16, same as the header packet ID
- Codec: codec type byte (see below)
- AudioData: encoded audio frame (Opus, CELT, etc.)

### Normal Voice S2C (packet type 0x00)
```
PacketCounter(2) + ClientID(2) + Codec(1) + AudioData(...)
```
- ClientID: big-endian uint16, the sending client's transient ID
- Server adds ClientID field so receivers know who's speaking

### Voice Whisper C2S (packet type 0x01)
```
PacketCounter(2) + Codec(1) + ChannelCount(1) + ClientCount(1) + ChannelIDs(8*N) + ClientIDs(2*M) + AudioData(...)
```
- ChannelCount (N): number of target channels
- ClientCount (M): number of target clients
- ChannelIDs: N x big-endian uint64
- ClientIDs: M x big-endian uint16

### Voice Whisper S2C (packet type 0x01)
```
PacketCounter(2) + ClientID(2) + Codec(1) + AudioData(...)
```
- Same as normal voice S2C — server strips whisper target info

### Group Whisper C2S (packet type 0x01 with Newprotocol flag)
```
PacketCounter(2) + Codec(1) + GroupWhisperType(1) + GroupWhisperTarget(1) + TargetID(8) + AudioData(...)
```
- GroupWhisperType: 0=ServerGroup, 1=ChannelGroup, 2=ChannelCommander, 3=AllClients
- GroupWhisperTarget: 0=AllChannels, 1=CurrentChannel, 2=ParentChannel, 3=AllParentChannels, 4=ChannelFamily, 5=CompleteChannelFamily, 6=Subchannels

### Codec Types
| Value | Codec | Sample Rate | Notes |
|-------|-------|-------------|-------|
| 0 | Speex Narrowband | 8 kHz | Mono |
| 1 | Speex Wideband | 16 kHz | Mono |
| 2 | Speex Ultra-wideband | 32 kHz | Mono |
| 3 | CELT Mono | 48 kHz | Mono |
| 4 | Opus Voice | 48 kHz | Mono, voice-optimized (default) |
| 5 | Opus Music | 48 kHz | Stereo, music-optimized |

### Server Flag (incoming voice)
When the COMPRESSED flag is set on an incoming voice packet, the last byte is a "server flag" (values 0x01-0x07) used for decoder session tracking. The first ~5 packets of a new voice session include this flag. Not all new voice sessions change this flag.

### Encryption
Voice packets use the same AES-128-EAX encryption as command packets:
- Key/nonce derived via `tsCreateKeyNonce(pktType, pID, genID, direction, sharedIV)`
- Direction: 0x31 for C2S, 0x30 for S2C
- MAC tag: 8-byte truncated
- Meta (additional authenticated data): PId(2) + CId(2) + PT(1) for C2S, PId(2) + PT(1) for S2C

## Complete Command Reference

### Client Commands (C2S)

| Command | Parameters | Description |
|---------|-----------|-------------|
| `clientinit` | client_nickname, client_version, client_platform, client_input_hardware, client_output_hardware, client_default_channel, client_default_channel_password, client_server_password, client_meta_data, client_version_sign, client_key_offset, client_nickname_phonetic, client_default_token, hwid | Initial client registration |
| `clientupdate` | client_nickname, client_input_muted, client_output_muted, client_input_hardware, client_output_hardware, client_is_channel_commander, client_badges, client_flag_avatar, client_talk_request, client_talk_request_msg, client_description, client_is_recording, client_away, client_away_message, client_nickname_phonetic, client_meta_data | Update own properties |
| `clientdisconnect` | reasonid, reasonmsg | Disconnect from server |
| `clientmove` | clid, cid, cpw | Move client to channel |
| `clientkick` | clid, reasonid (4=channel, 5=server), reasonmsg | Kick client |
| `clientpoke` | clid, msg | Poke client with message |
| `clientinfo` | clid | Get detailed client info |
| `clientlist` | -uid, -away, -voice, -times, -groups, -info, -icon, -country | List online clients |
| `clientdblist` | | List all known clients (database) |
| `clientdbinfo` | cldbid | Get persistent client info |
| `clientedit` | clid, properties... | Edit client properties |
| `clientgetdbidfromuid` | cluid | Get database ID from UID |
| `clientgetids` | cluid | Get online client IDs from UID |
| `clientgetnamefromuid` | cluid | Get name from UID |
| `clientgetnamefromdbid` | cldbid | Get name from database ID |
| `clientchatclosed` | clid | Notify chat window closed |
| `sendtextmessage` | targetmode (1/2/3), target, msg | Send text message |
| `channellist` | -topic, -flags, -voice, -limits, -icon | List channels |
| `channelinfo` | cid | Get channel details |
| `channelcreate` | channel_name, channel_description, pid, channel_codec, channel_codec_quality, channel_flag_permanent, channel_flag_semi_permanent, channel_flag_default, channel_password, channel_maxclients, channel_order, channel_topic, channel_needed_talk_power | Create channel |
| `channeledit` | cid, properties... | Edit channel |
| `channeldelete` | cid, force | Delete channel |
| `channelmove` | cid, cpid, order | Move channel |
| `channelsubscribe` | cid | Subscribe to channel updates |
| `channelsubscribeall` | | Subscribe to all channels |
| `channelunsubscribe` | cid | Unsubscribe from channel |
| `channelunsubscribeall` | | Unsubscribe from all |
| `channelfind` | pattern | Find channel by name |
| `channelgetdescription` | cid | Get channel description |
| `channeladdperm` | cid, permid/permsid, permvalue | Add channel permission |
| `channeldelperm` | cid, permid/permsid | Remove channel permission |
| `channelpermlist` | cid | List channel permissions |
| `channelclientaddperm` | cid, cldbid, permid, permvalue | Add client-channel permission |
| `channelclientdelperm` | cid, cldbid, permid | Remove client-channel permission |
| `servergrouplist` | | List server groups |
| `servergroupadd` | name | Create server group |
| `servergroupdel` | sgid, force | Delete server group |
| `servergroupaddclient` | sgid, cldbid | Add client to server group |
| `servergroupdelclient` | sgid, cldbid | Remove client from server group |
| `servergroupclientlist` | sgid | List group members |
| `servergrouppermlist` | sgid | List group permissions |
| `servergroupsbyclientid` | cldbid | List groups for client |
| `channelgrouplist` | | List channel groups |
| `setclientchannelgroup` | cgid, cid, cldbid | Set client's channel group |
| `banclient` | clid, banreason | Ban online client |
| `banadd` | ip/uid/name, banreason, time | Add ban rule |
| `bandel` | banid | Delete ban |
| `bandelall` | | Delete all bans |
| `banlist` | | List all bans |
| `ftinitupload` | clientftfid, name, cid, cpw, size, overwrite, resume | Init file upload |
| `ftinitdownload` | clientftfid, name, cid, cpw, seekpos | Init file download |
| `ftgetfilelist` | cid, cpw, path | List files in channel |
| `ftgetfileinfo` | cid, cpw, name | Get file info |
| `ftdeletefile` | cid, cpw, name | Delete file |
| `ftcreatedir` | cid, cpw, dirname | Create directory |
| `ftrenamefile` | cid, cpw, oldname, newname, tcid, tcpw | Rename/move file |
| `ftstop` | serverftfid, delete | Stop file transfer |
| `complainadd` | tcldbid, message | File complaint |
| `complaindel` | tcldbid, fcldbid | Delete complaint |
| `complaindelall` | tcldbid | Delete all complaints |
| `complainlist` | tcldbid | List complaints |
| `messageadd` | cluid, subject, message | Send offline message |
| `messagedel` | msgid | Delete offline message |
| `messageget` | msgid | Read offline message |
| `messagelist` | | List offline messages |
| `messageupdateflag` | msgid, flag | Mark message read/unread |
| `plugincmd` | name, data, targetmode | Send plugin command |
| `permissionlist` | | List all permissions |
| `permfind` | permid | Find permission usage |
| `permget` | permid | Get permission value |
| `permoverview` | cid, cldbid | Permission overview |
| `privilegekeyadd` | tokentype, tokenid1, tokenid2 | Create privilege key |
| `privilegekeydelete` | token | Delete privilege key |
| `privilegekeylist` | | List privilege keys |
| `privilegekeyuse` | token | Use privilege key |
| `serverinfo` | | Get server info |
| `serveredit` | properties... | Edit server properties |
| `servernotifyregister` | event, id | Register for notifications |
| `servernotifyunregister` | | Unregister notifications |
| `setconnectioninfo` | connection_ping, connection_ping_deviation, bandwidth stats... | Report connection statistics |
| `whoami` | | Get own connection info |
| `version` | | Get server version |
| `custominfo` | cldbid | Get custom client properties |
| `customsearch` | ident, pattern | Search custom properties |
| `customset` | cldbid, ident, value | Set custom property |
| `customdelete` | cldbid, ident | Delete custom property |

### Server Notifications (S2C)

| Notification | Fields | Description |
|-------------|--------|-------------|
| `notifytextmessage` | targetmode, msg, invokerid, invokername, invokeruid | Text message received |
| `notifycliententerview` | cfid, ctid, clid, client_nickname, client_unique_identifier, client_type, ... | Client joined/connected |
| `notifyclientleftview` | cfid, ctid, clid, reasonid, reasonmsg, invokerid | Client left/disconnected |
| `notifyclientmoved` | ctid, clid, reasonid, invokerid | Client moved channels |
| `notifyclientupdated` | clid, properties... | Client properties changed |
| `notifyclientpoke` | invokerid, invokername, invokeruid, msg | Client poked |
| `notifyclientchatcomposing` | clid, cluid | Client typing indicator |
| `notifyclientchatclosed` | clid, cluid | Client closed chat |
| `notifychannelcreated` | cid, channel_name, ... | Channel created |
| `notifychanneldeleted` | cid | Channel deleted |
| `notifychanneledited` | cid, properties... | Channel edited |
| `notifychannelmoved` | cid, cpid, order | Channel moved |
| `notifychanneldescriptionchanged` | cid | Channel description changed |
| `notifychannelpasswordchanged` | cid | Channel password changed |
| `notifychannelsubscribed` | cid | Channel subscribed |
| `notifychannelunsubscribed` | cid | Channel unsubscribed |
| `notifyserveredited` | properties... | Server properties edited |
| `notifyserverupdated` | properties... | Server updated |
| `notifyservergroupclientadded` | sgid, clid, cluid, invokername | Client added to group |
| `notifyservergroupclientdeleted` | sgid, clid, cluid, invokername | Client removed from group |
| `notifytokenused` | token, clid, cldbid, tokentype | Privilege key used |
| `notifyconnectioninfo` | connection stats... | Connection info response |
| `notifyconnectioninforequest` | | Server requests connection info |
| `notifyclientchannelgroupchanged` | cgid, cid, clid | Client channel group changed |
| `notifyclientneededpermissions` | permid, permvalue | Required permissions list |
| `notifyplugincommand` | name, data, invokerid | Plugin command received |

## Error Codes

| ID | Hex | Description |
|----|-----|-------------|
| 0 | 0x0000 | OK |
| 1 | 0x0001 | Undefined |
| 2 | 0x0002 | Not implemented |
| 256 | 0x0100 | Command not found |
| 512 | 0x0200 | Client invalid ID |
| 513 | 0x0201 | Nickname in use |
| 519 | 0x0207 | Could not validate client identity |
| 521 | 0x0209 | Too many clones connected |
| 524 | 0x020c | Client is flooding |
| 768 | 0x0300 | Channel invalid ID |
| 770 | 0x0302 | Already in channel |
| 771 | 0x0303 | Channel name in use |
| 1281 | 0x0501 | Database empty result |
| 1282 | 0x0502 | Database duplicate entry |
| 2568 | 0x0a08 | Insufficient client permissions |

## Sources

- [tsproto](https://github.com/ReSpeak/tsproto) -- Rust reference implementation (packet codec, algorithms, connection handling)
- [tsproto-packets](https://github.com/ReSpeak/tsproto/tree/master/tsproto-packets) -- packet parsing/serialization
- [tsclientlib](https://github.com/ReSpeak/tsclientlib/) -- higher-level Rust client library (connection lifecycle, audio, file transfer)
- [TS3AudioBot/TSLib](https://github.com/Splamy/TS3AudioBot/tree/master) -- C# full client implementation (voice packets, commands, notifications)
- [ts3j](https://github.com/Manevolent/ts3j/tree/master) -- Java UDP client (voice, whisper, bans, permissions, file transfer)
- [tsdeclarations/ts3protocol.md](https://github.com/ReSpeak/tsdeclarations/blob/master/ts3protocol.md) -- community protocol documentation
- QuickLZ spec: http://www.quicklz.com (Level 1 format documentation)
- Live testing against avanor-gaming.de:9987 (public TS3 server)

## Implementation Quirks (discovered 2026-04-09)

### Voice packets must NOT use Newprotocol flag
Normal voice (type 0x00) and whisper (type 0x01) packets must **NOT** have the `Newprotocol` flag (0x20) set. Only COMMAND (0x02) and COMMAND_LOW (0x03) use this flag. Setting it on voice causes EAX decryption to fail server-side because the flag byte is part of the associated data (meta) in the EAX cipher — the server computes a different MAC and silently drops the packet. Confirmed by reading ts3j's `AbstractTeamspeakClientSocket.java` lines 285-360. Group whisper IS the exception — it uses packet type 0x01 WITH Newprotocol flag.

### Server omits `error id=0 msg=ok` on successful commands
Some servers (including avanor-gaming.de) do not send the `error id=0 msg=ok` response after successful data commands like `whoami`, `serverinfo`, `channellist`. The data response arrives but no error terminator follows. Implementation must use a data timeout (500ms after last data line) rather than waiting indefinitely for `error`. Void commands (like `clientmove`) may return nothing at all — use a 2s overall deadline.

### Multi-line command splitting
TS3 sends multiple commands per packet separated by `\n\r` (0x0A 0x0D). Split on `\n` and trim `\r` to handle both `\n\r` and bare `\n` separators. Each line is an independent command (notification or response).

### channel_needed_talk_power silently blocks voice
Channels with `channel_needed_talk_power > 0` silently drop all voice packets from clients without sufficient talk power. No error is returned — packets are simply not forwarded. The default lobby channel on many servers has `channel_needed_talk_power = 100001`, effectively blocking all voice. Move to a channel with `channel_needed_talk_power = 0` (like "Just Talking" / casual channels) for voice to work.

### Voice body counter = header packet ID
The 2-byte PacketCounter at the start of the voice body MUST match the packet header's PId field. This is confirmed by ts3j's `PacketBody0Voice.java`. Using a separate counter causes the server to reject or misroute packets.
