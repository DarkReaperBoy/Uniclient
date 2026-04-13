# Mumble Protocol Specification

Complete reverse-engineered spec for the Mumble VoIP protocol. Sources: official
Mumble.proto, MumbleUDP.proto, MumbleProtocol.h, CryptStateOCB2.cpp,
PacketDataStream.h, ACL.h, and docs/dev/network-protocol/ from
mumble-voip/mumble (GitHub master branch).

---

## 1. Architecture Overview

Mumble uses two communication channels:

1. **TCP control channel** -- TLS-encrypted, carries protobuf messages for
   authentication, channel/user state, text messages, permissions, etc.
2. **UDP voice channel** -- OCB-AES128-encrypted, carries low-latency audio
   data and ping packets.

Both channels are **mandatory encrypted**. TCP uses TLSv1.2+ (AES256-SHA).
UDP uses OCB2-AES128 with keys exchanged via the TCP `CryptSetup` message.

If UDP is unavailable (NAT, firewall), voice packets are **tunneled through
TCP** using the `UDPTunnel` message type (type ID 1).

Default port: **64738** (both TCP and UDP).

---

## 2. TCP Control Protocol

### 2.1 Connection Setup

1. Client opens TCP socket to server:port (default 64738)
2. TLS handshake (TLSv1.2+, client certificate optional but recommended)
3. Both sides send `Version` message
4. Client sends `Authenticate` message (username, password, tokens, opus support)
5. Server sends `CryptSetup` (OCB-AES128 key + nonces for UDP)
6. Server sends `ChannelState` for every channel (first pass: no links)
7. Server sends `ChannelState` updates for channel links
8. Server sends `UserState` for every connected user
9. Server sends `ServerSync` (session ID, max bandwidth, welcome text, permissions)
10. Server sends `ServerConfig` (max bandwidth, welcome text, allow HTML, message limits)
11. Connection is now synchronized -- client is visible to others

### 2.2 Message Framing

Every TCP message has a 6-byte header:

```
+--------+--------+--------+--------+--------+--------+--------+---
| Type (2 bytes, big-endian uint16) | Length (4 bytes, big-endian uint32) | Payload...
+--------+--------+--------+--------+--------+--------+--------+---
```

- **Type**: 2-byte big-endian unsigned integer identifying the protobuf message type
- **Length**: 4-byte big-endian unsigned integer, byte count of the payload
- **Payload**: protobuf-encoded message (except UDPTunnel which is raw audio data)

### 2.3 TCP Message Type IDs

All 27 message types with their numeric IDs:

| ID | Message               | Direction       | Description |
|----|-----------------------|-----------------|-------------|
| 0  | Version               | Both            | Version exchange (major/minor/patch, release, OS) |
| 1  | UDPTunnel             | Both            | Raw UDP voice packet tunneled over TCP |
| 2  | Authenticate          | Client->Server  | Login credentials (username, password, tokens, opus flag) |
| 3  | Ping                  | Both            | Keep-alive + stats (good/late/lost/resync, UDP/TCP ping avg/var) |
| 4  | Reject                | Server->Client  | Connection rejected (reason enum + text) |
| 5  | ServerSync            | Server->Client  | Login complete (session ID, max bandwidth, welcome, permissions) |
| 6  | ChannelRemove         | Both            | Remove a channel by ID |
| 7  | ChannelState          | Both            | Create/update channel (name, parent, links, description, position, temporary, max_users) |
| 8  | UserRemove            | Both            | User leaving or kicked/banned |
| 9  | UserState             | Both            | User properties (channel, mute, deaf, name, comment, texture, recording, priority speaker, listening channels) |
| 10 | BanList               | Both            | Query or set server ban list (IP, mask, hash, reason, duration) |
| 11 | TextMessage           | Both            | Send text to users/channels/trees (HTML allowed if server permits) |
| 12 | PermissionDenied      | Server->Client  | Operation denied (type enum, permission bits, channel, reason) |
| 13 | ACL                   | Both            | Query or set channel ACLs (groups + ACL entries) |
| 14 | QueryUsers            | Both            | Resolve user IDs <-> names |
| 15 | CryptSetup            | Both            | OCB-AES128 key exchange (key + client_nonce + server_nonce) or resync |
| 16 | ContextActionModify   | Server->Client  | Add/remove custom context menu actions |
| 17 | ContextAction         | Client->Server  | Trigger a context action (targets user session or channel ID) |
| 18 | UserList              | Both            | List registered users (ID, name, last_seen, last_channel) |
| 19 | VoiceTarget           | Client->Server  | Register whisper target (users, channels, groups, links, children) |
| 20 | PermissionQuery       | Both            | Query/receive channel permissions |
| 21 | CodecVersion          | Server->Client  | Server-selected codec (CELT alpha/beta versions, prefer_alpha, opus flag) |
| 22 | UserStats             | Both            | Detailed user statistics (certs, bandwidth, ping, codec versions, address, uptime) |
| 23 | RequestBlob           | Client->Server  | Request large blobs (user textures, comments, channel descriptions by hash) |
| 24 | ServerConfig          | Server->Client  | Server config (max bandwidth, welcome text, allow HTML, message/image length limits, max users, recording_allowed) |
| 25 | SuggestConfig         | Server->Client  | Server suggestions (version, positional audio, push-to-talk) |
| 26 | PluginDataTransmission| Both            | Plugin data relay between clients (sender, receivers, data, dataID) |

### 2.4 Keep-Alive

Client MUST send `Ping` messages. Server disconnects after **30 seconds** of
no ping. Ping interval is typically 15-20 seconds.

---

## 3. All Protobuf Messages (Mumble.proto)

### 3.1 Version (ID 0)
```protobuf
message Version {
    optional uint32 version_v1 = 1;    // Legacy: major<<16 | minor<<8 | patch
    optional uint64 version_v2 = 5;    // New: major<<48 | minor<<32 | patch<<16
    optional string release = 2;       // Client release name (e.g. "1.5.517")
    optional string os = 3;            // OS name (e.g. "Linux", "Windows")
    optional string os_version = 4;    // OS version string
}
```

**Version encoding:**
- Legacy v1 (uint32): `major (2 bytes) | minor (1 byte) | patch (1 byte)`
  - Example: 1.2.4 = `0x00010204`
- New v2 (uint64): `major (16 bits) << 48 | minor (16 bits) << 32 | patch (16 bits) << 16`
  - Example: 1.5.0 = `0x0001000500000000`

Protobuf-based UDP protocol introduced at version **1.5.0**. Versions >= 1.5.0
use protobuf UDP, versions < 1.5.0 use legacy UDP format.

### 3.2 UDPTunnel (ID 1)
```protobuf
message UDPTunnel {
    required bytes packet = 1;     // Raw UDP audio/ping packet (NOT protobuf-decoded)
}
```
The payload is a raw voice packet (same format as UDP), written verbatim into TCP.

### 3.3 Authenticate (ID 2)
```protobuf
message Authenticate {
    optional string username = 1;       // UTF-8 username
    optional string password = 2;       // Server or user password
    repeated string tokens = 3;         // ACL access tokens
    repeated int32 celt_versions = 4;   // Supported CELT bitstream versions
    optional bool opus = 5 [default = false];  // Client supports Opus
    optional int32 client_type = 6 [default = 0]; // 0=REGULAR, 1=BOT
}
```

### 3.4 Ping (ID 3)
```protobuf
message Ping {
    optional uint64 timestamp = 1;      // Client timestamp (echoed back)
    optional uint32 good = 2;           // Good packets received
    optional uint32 late = 3;           // Late packets received
    optional uint32 lost = 4;           // Packets never received
    optional uint32 resync = 5;         // Nonce resyncs
    optional uint32 udp_packets = 6;    // Total UDP packets received
    optional uint32 tcp_packets = 7;    // Total TCP packets received
    optional float udp_ping_avg = 8;    // UDP ping average (ms)
    optional float udp_ping_var = 9;    // UDP ping variance
    optional float tcp_ping_avg = 10;   // TCP ping average (ms)
    optional float tcp_ping_var = 11;   // TCP ping variance
}
```

### 3.5 Reject (ID 4)
```protobuf
message Reject {
    enum RejectType {
        None = 0;              // Unknown reason
        WrongVersion = 1;      // Incompatible version
        InvalidUsername = 2;   // Invalid username
        WrongUserPW = 3;       // Wrong user password
        WrongServerPW = 4;     // Wrong server password
        UsernameInUse = 5;     // Username already taken
        ServerFull = 6;        // Server is full
        NoCertificate = 7;     // Certificate required
        AuthenticatorFail = 8; // Authenticator failure
        NoNewConnections = 9;  // Server not accepting connections
    }
    optional RejectType type = 1;
    optional string reason = 2;
}
```

### 3.6 ServerSync (ID 5)
```protobuf
message ServerSync {
    optional uint32 session = 1;        // Client's session ID
    optional uint32 max_bandwidth = 2;  // Max bandwidth (bytes/sec)
    optional string welcome_text = 3;   // Server welcome message (HTML)
    optional uint64 permissions = 4;    // Root channel permissions (uint64 due to legacy bug, never exceeds uint32)
}
```

### 3.7 ChannelRemove (ID 6)
```protobuf
message ChannelRemove {
    required uint32 channel_id = 1;
}
```

### 3.8 ChannelState (ID 7)
```protobuf
message ChannelState {
    optional uint32 channel_id = 1;         // Unique channel ID (0 = root)
    optional uint32 parent = 2;             // Parent channel ID
    optional string name = 3;               // UTF-8 channel name
    repeated uint32 links = 4;              // Linked channel IDs
    optional string description = 5;        // Description (if < 128 bytes)
    repeated uint32 links_add = 6;          // Channel IDs to add as links
    repeated uint32 links_remove = 7;       // Channel IDs to remove from links
    optional bool temporary = 8 [default = false]; // Temporary channel
    optional int32 position = 9 [default = 0];     // Sort position weight
    optional bytes description_hash = 10;   // SHA1 of description (if >= 128 bytes)
    optional uint32 max_users = 11;         // Max users (0 = server default)
    optional bool is_enter_restricted = 12; // Has ACL denying ENTER
    optional bool can_enter = 13;           // Receiver can enter this channel
}
```

### 3.9 UserRemove (ID 8)
```protobuf
message UserRemove {
    required uint32 session = 1;         // User being removed
    optional uint32 actor = 2;           // Who initiated removal
    optional string reason = 3;          // Kick/ban reason
    optional bool ban = 4;               // Ban the user
    optional bool ban_certificate = 5;   // Ban by certificate
    optional bool ban_ip = 6;            // Ban by IP address
}
```

### 3.10 UserState (ID 9)
```protobuf
message UserState {
    message VolumeAdjustment {
        optional uint32 listening_channel = 1;
        optional float volume_adjustment = 2;
    }
    optional uint32 session = 1;              // Session ID (changes per connection)
    optional uint32 actor = 2;                // Who is updating
    optional string name = 3;                 // UTF-8 username
    optional uint32 user_id = 4;              // Registered user ID
    optional uint32 channel_id = 5;           // Current channel
    optional bool mute = 6;                   // Server muted
    optional bool deaf = 7;                   // Server deafened
    optional bool suppress = 8;               // Suppressed (not muted)
    optional bool self_mute = 9;              // Self-muted
    optional bool self_deaf = 10;             // Self-deafened
    optional bytes texture = 11;              // Avatar (if < 128 bytes)
    optional bytes plugin_context = 12;       // Positional audio plugin context (NOT sent to other clients)
    optional string plugin_identity = 13;     // Plugin identity (NOT sent to other clients)
    optional string comment = 14;             // User comment (if < 128 bytes)
    optional string hash = 15;                // Certificate hash
    optional bytes comment_hash = 16;         // SHA1 of comment (if >= 128 bytes)
    optional bytes texture_hash = 17;         // SHA1 of texture (if >= 128 bytes)
    optional bool priority_speaker = 18;      // Priority speaker flag
    optional bool recording = 19;             // Currently recording
    repeated string temporary_access_tokens = 20;  // Temporary ACL tokens
    repeated uint32 listening_channel_add = 21;     // Start listening to channels
    repeated uint32 listening_channel_remove = 22;  // Stop listening to channels
    repeated VolumeAdjustment listening_volume_adjustment = 23; // Per-channel volume
}
```

### 3.11 BanList (ID 10)
```protobuf
message BanList {
    message BanEntry {
        required bytes address = 1;     // Banned IP address
        required uint32 mask = 2;       // Subnet mask length
        optional string name = 3;       // Username (informational)
        optional string hash = 4;       // Certificate hash
        optional string reason = 5;     // Ban reason
        optional string start = 6;      // Ban start time
        optional uint32 duration = 7;   // Duration in seconds
    }
    repeated BanEntry bans = 1;
    optional bool query = 2 [default = false]; // True=query, False=replace
}
```

### 3.12 TextMessage (ID 11)
```protobuf
message TextMessage {
    optional uint32 actor = 1;          // Sender session
    repeated uint32 session = 2;        // Target user sessions
    repeated uint32 channel_id = 3;     // Target channels
    repeated uint32 tree_id = 4;        // Target channel trees (recursive)
    required string message = 5;        // UTF-8 text (HTML if allowed)
}
```

Text messages support HTML if the server allows it (`ServerConfig.allow_html`).
Rich content: bold, italic, links, images (inline base64 or URLs).
Maximum length controlled by `ServerConfig.message_length` and
`ServerConfig.image_message_length`.

### 3.13 PermissionDenied (ID 12)
```protobuf
message PermissionDenied {
    enum DenyType {
        Text = 0;               // Other reason (see reason field)
        Permission = 1;         // Permission denied
        SuperUser = 2;          // Cannot modify SuperUser
        ChannelName = 3;        // Invalid channel name
        TextTooLong = 4;        // Text message too long
        H9K = 5;                // Easter egg ("flux capacitor spelled wrong")
        TemporaryChannel = 6;   // Not permitted in temp channel
        MissingCertificate = 7; // Operation requires certificate
        UserName = 8;           // Invalid username
        ChannelFull = 9;        // Channel is full
        NestingLimit = 10;      // Channels nested too deeply
        ChannelCountLimit = 11; // Max channel count reached
        ChannelListenerLimit = 12; // Max listeners for channel
        UserListenerLimit = 13;    // Max listener proxies for user
    }
    optional uint32 permission = 1;     // Denied permission bits
    optional uint32 channel_id = 2;     // Channel where denied
    optional uint32 session = 3;        // User who was denied
    optional string reason = 4;         // Text reason
    optional DenyType type = 5;         // Denial type
    optional string name = 6;           // Invalid name (when type=UserName)
}
```

### 3.14 ACL (ID 13)
```protobuf
message ACL {
    message ChanGroup {
        required string name = 1;            // Group name
        optional bool inherited = 2 [default = true];    // Read-only: inherited from parent
        optional bool inherit = 3 [default = true];      // Members are inherited
        optional bool inheritable = 4 [default = true];  // Can be inherited by subchannels
        repeated uint32 add = 5;             // Users added to group (by user_id)
        repeated uint32 remove = 6;          // Users removed from group
        repeated uint32 inherited_members = 7; // Inherited user IDs
    }
    message ChanACL {
        optional bool apply_here = 1 [default = true];  // Applies to this channel
        optional bool apply_subs = 2 [default = true];  // Applies to subchannels
        optional bool inherited = 3 [default = true];   // Inherited from parent
        optional uint32 user_id = 4;          // User affected (by registered ID)
        optional string group = 5;            // Group affected (by name)
        optional uint32 grant = 6;            // Permission bits granted
        optional uint32 deny = 7;             // Permission bits denied
    }
    required uint32 channel_id = 1;
    optional bool inherit_acls = 2 [default = true]; // Inherit parent ACLs
    repeated ChanGroup groups = 3;
    repeated ChanACL acls = 4;
    optional bool query = 5 [default = false]; // True=query, False=set
}
```

### 3.15 QueryUsers (ID 14)
```protobuf
message QueryUsers {
    repeated uint32 ids = 1;       // User IDs to resolve
    repeated string names = 2;     // User names (same order)
}
```

### 3.16 CryptSetup (ID 15)
```protobuf
message CryptSetup {
    optional bytes key = 1;           // 16-byte AES-128 key
    optional bytes client_nonce = 2;  // 16-byte client IV/nonce
    optional bytes server_nonce = 3;  // 16-byte server IV/nonce
}
```

- Server sends full `CryptSetup` (all 3 fields) after authentication
- Either side may send empty `CryptSetup` to request nonce resync
- Resync: send with only `client_nonce` or `server_nonce` filled

### 3.17 ContextActionModify (ID 16)
```protobuf
message ContextActionModify {
    enum Context {
        Server = 0x01;   // Applicable to server
        Channel = 0x02;  // Can target channel
        User = 0x04;     // Can target user
    }
    enum Operation {
        Add = 0;
        Remove = 1;
    }
    required string action = 1;       // Action identifier
    optional string text = 2;         // Display name
    optional uint32 context = 3;      // Context flags (OR-combined)
    optional Operation operation = 4; // Add or Remove
}
```

### 3.18 ContextAction (ID 17)
```protobuf
message ContextAction {
    optional uint32 session = 1;       // Target user session
    optional uint32 channel_id = 2;    // Target channel
    required string action = 3;        // Action identifier
}
```

### 3.19 UserList (ID 18)
```protobuf
message UserList {
    message User {
        required uint32 user_id = 1;
        optional string name = 2;
        optional string last_seen = 3;
        optional uint32 last_channel = 4;
    }
    repeated User users = 1;
}
```

### 3.20 VoiceTarget (ID 19)
```protobuf
message VoiceTarget {
    message Target {
        repeated uint32 session = 1;    // Target user sessions
        optional uint32 channel_id = 2; // Target channel
        optional string group = 3;      // Target ACL group
        optional bool links = 4 [default = false];    // Follow linked channels
        optional bool children = 5 [default = false];  // Include child channels
    }
    optional uint32 id = 1;        // Target ID (1-30; 0=normal, 31=loopback)
    repeated Target targets = 2;   // Target specifications
}
```

### 3.21 PermissionQuery (ID 20)
```protobuf
message PermissionQuery {
    optional uint32 channel_id = 1;
    optional uint32 permissions = 2;
    optional bool flush = 3 [default = false]; // Drop all cached permissions
}
```

### 3.22 CodecVersion (ID 21)
```protobuf
message CodecVersion {
    required int32 alpha = 1;         // CELT Alpha bitstream version
    required int32 beta = 2;          // CELT Beta bitstream version
    required bool prefer_alpha = 3 [default = true];  // Prefer Alpha over Beta
    optional bool opus = 4 [default = false];          // Use Opus
}
```

### 3.23 UserStats (ID 22)
```protobuf
message UserStats {
    message Stats {
        optional uint32 good = 1;
        optional uint32 late = 2;
        optional uint32 lost = 3;
        optional uint32 resync = 4;
    }
    message RollingStats {
        optional uint32 time_window = 1;
        optional Stats from_client = 2;
        optional Stats from_server = 3;
    }
    optional uint32 session = 1;            // Target user session
    optional bool stats_only = 2 [default = false]; // Only mutable stats
    repeated bytes certificates = 3;        // DER certificate chain
    optional Stats from_client = 4;         // Packet stats from client
    optional Stats from_server = 5;         // Packet stats from server
    optional uint32 udp_packets = 6;
    optional uint32 tcp_packets = 7;
    optional float udp_ping_avg = 8;
    optional float udp_ping_var = 9;
    optional float tcp_ping_avg = 10;
    optional float tcp_ping_var = 11;
    optional Version version = 12;          // Client version info
    repeated int32 celt_versions = 13;      // Supported CELT versions
    optional bytes address = 14;            // Client IP address
    optional uint32 bandwidth = 15;         // Bandwidth in use
    optional uint32 onlinesecs = 16;        // Connection duration
    optional uint32 idlesecs = 17;          // Idle duration
    optional bool strong_certificate = 18 [default = false];
    optional bool opus = 19 [default = false];
    optional RollingStats rolling_stats = 20;
}
```

### 3.24 RequestBlob (ID 23)
```protobuf
message RequestBlob {
    repeated uint32 session_texture = 1;       // User textures to fetch
    repeated uint32 session_comment = 2;       // User comments to fetch
    repeated uint32 channel_description = 3;   // Channel descriptions to fetch
}
```

When texture/comment/description >= 128 bytes, only the SHA1 hash is sent in
UserState/ChannelState. Client must use RequestBlob to fetch the full data.

### 3.25 ServerConfig (ID 24)
```protobuf
message ServerConfig {
    optional uint32 max_bandwidth = 1;          // Max bandwidth (bytes/sec)
    optional string welcome_text = 2;           // Server welcome message (HTML)
    optional bool allow_html = 3;               // HTML allowed in text messages
    optional uint32 message_length = 4;         // Max text message length
    optional uint32 image_message_length = 5;   // Max image message length
    optional uint32 max_users = 6;              // Max users on server
    optional bool recording_allowed = 7;        // Recording feature allowed
}
```

### 3.26 SuggestConfig (ID 25)
```protobuf
message SuggestConfig {
    optional uint32 version_v1 = 1;     // Suggested version (legacy format)
    optional uint64 version_v2 = 4;     // Suggested version (new format)
    optional bool positional = 2;       // Suggest positional audio
    optional bool push_to_talk = 3;     // Suggest push-to-talk
}
```

### 3.27 PluginDataTransmission (ID 26)
```protobuf
message PluginDataTransmission {
    optional uint32 senderSession = 1;            // Sender session ID
    repeated uint32 receiverSessions = 2 [packed = true]; // Receiver sessions
    optional bytes data = 3;                      // Plugin data payload
    optional string dataID = 4;                   // Plugin data identifier
}
```

---

## 4. UDP Voice Protocol

### 4.1 Two Protocol Versions

Mumble has **two** UDP protocol formats:

1. **Legacy format** (< 1.5.0): Custom binary encoding with PacketDataStream varints
2. **Protobuf format** (>= 1.5.0): Protobuf-encoded messages (`MumbleUDP.proto`)

Both are wrapped in OCB-AES128 encryption (see Section 5).

### 4.2 Legacy UDP Packet Format (< 1.5.0)

After decryption, the first byte is a header:

```
+---+---+---+---+---+---+---+---+
| 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
+---+---+---+---+---+---+---+---+
|   type (3)    |  target (5)   |
+---------------+---------------+
```

**Audio packet types** (3 most significant bits):

| Type | Bits      | Codec           |
|------|-----------|-----------------|
| 0    | `000xxxxx` | CELT Alpha (0.7.0) |
| 1    | `001xxxxx` | Ping            |
| 2    | `010xxxxx` | Speex           |
| 3    | `011xxxxx` | CELT Beta (0.11.0) |
| 4    | `100xxxxx` | Opus            |
| 5-7  |           | Unused/Reserved |

**Target** (5 least significant bits):

| Target | Meaning |
|--------|---------|
| 0      | Normal talking |
| 1-30   | Whisper target ID (registered via VoiceTarget) |
| 31     | Server loopback |

When **receiving** whispered audio from server: target 1 = whisper to channel,
target 2 = direct whisper to user.

#### 4.2.1 Legacy Ping Packet

```
| Header (0x20) | Timestamp (varint) |
```

#### 4.2.2 Legacy Audio Packet -- Incoming (from server)

```
| Header (1 byte) | Session ID (varint) | Sequence Number (varint) | Audio Payload | [Position (3x float32LE)] |
```

#### 4.2.3 Legacy Audio Packet -- Outgoing (to server)

```
| Header (1 byte) | Sequence Number (varint) | Audio Payload | [Position (3x float32LE)] |
```

Server infers session from the connection.

#### 4.2.4 Audio Payload -- CELT/Speex

Multiple frames, each prefixed with a 1-byte header:
```
| bit7=continuation | bits[6:0]=length | frame data (length bytes) |
```
- Continuation bit (0x80) is set for all frames except the last
- Length 0 with no continuation = end of voice transmission

#### 4.2.5 Audio Payload -- Opus

Single frame with varint header:
```
| varint header | opus data |
```
- Lower 13 bits = data length (max 8191 bytes)
- Bit 13 (mask 0x2000) = terminator flag (end of transmission)

### 4.3 Protobuf UDP Format (>= 1.5.0)

After decryption, the first byte determines message type:

| First Byte | Type |
|------------|------|
| Byte where `(byte >> 5) < 5` | Legacy format (backwards compat) |
| Protobuf tag byte | New protobuf format |

**New UDP message types** (from MumbleUDP.proto):

| ID | Message |
|----|---------|
| 0  | Audio   |
| 1  | Ping    |

The protobuf messages are prefixed with a 2-byte header:
- Byte 0: `(type << 5) | 0` with high bits distinguishing from legacy
- Actually: for protobuf UDP, messages are serialized with a type prefix byte

#### 4.3.1 MumbleUDP.Audio
```protobuf
message Audio {
    oneof Header {
        uint32 target = 1;          // Client->Server: whisper target (0=normal, 31=loopback)
        uint32 context = 2;         // Server->Client: audio context (0=normal, 1=shout, 2=whisper, 3=listen)
    }
    uint32 sender_session = 3;     // Sender's session (set by server, not required from client)
    uint64 frame_number = 4;       // Frame sequence number
    bytes opus_data = 5;           // Opus encoded audio
    repeated float positional_data = 6;  // [X, Y, Z] position (meters)
    float volume_adjustment = 7;   // Server-applied volume (0 = unset)
    bool is_terminator = 16;       // End of transmission
}
```

Note: Field indices 8-15 are reserved for future use (single-byte encoding).

#### 4.3.2 MumbleUDP.Ping
```protobuf
message Ping {
    uint64 timestamp = 1;                     // Client timestamp
    bool request_extended_information = 2;     // Request server details
    uint64 server_version_v2 = 3;             // Server version (new format)
    uint32 user_count = 4;                    // Connected users
    uint32 max_user_count = 5;                // Max users
    uint32 max_bandwidth_per_user = 6;        // Max bandwidth per user
}
```

### 4.4 Sequence Numbers

The sequence number identifies the position of audio frames in the stream.
It may increment by more than 1 between packets if a packet contains multiple
frames (CELT/Speex) -- this lets the receiver detect how many frames were lost.

### 4.5 Maximum Packet Size

Max UDP packet size: **1024 bytes** (including encryption overhead).
Effective max payload after 4-byte crypto header: **1020 bytes**.

---

## 5. Cryptography

### 5.1 OCB2-AES128 (UDP Encryption)

All UDP packets are encrypted with OCB2-AES128.

**Key material** (from CryptSetup message):
- `key`: 16 bytes (AES-128 key)
- `client_nonce`: 16 bytes (client's encrypt IV / server's decrypt IV)
- `server_nonce`: 16 bytes (server's encrypt IV / client's decrypt IV)

**Encrypted packet layout:**

```
+------+------+------+------+---------------------------+
| IV   | Tag  | Tag  | Tag  | Encrypted Payload         |
| [0]  | [0]  | [1]  | [2]  | (OCB2 ciphertext)         |
+------+------+------+------+---------------------------+
  1 byte  1 byte 1 byte 1 byte   N bytes
```

Total: `4 + N` bytes, where N = plaintext length.

**Encryption process:**
1. Increment the 16-byte encrypt IV (little-endian counter, increment byte[0] first, carry)
2. OCB2-AES128 encrypt plaintext with the current IV, producing ciphertext + 16-byte tag
3. Output: `encrypt_iv[0]` (1 byte) + `tag[0..2]` (3 bytes) + ciphertext

**Decryption process:**
1. Read `iv_byte = packet[0]`, `tag_check = packet[1..3]`, ciphertext = `packet[4..]`
2. Reconstruct the full 16-byte IV from the single IV byte + current decrypt IV state
3. Handle reordering: check if packet is in-order, late (within 30 packets), or lost
4. OCB2-AES128 decrypt with reconstructed IV
5. Verify `tag[0..2]` matches computed tag
6. On failure: restore previous IV state and return error

**IV reconstruction from single byte:**
- If `(decrypt_iv[0] + 1) & 0xFF == iv_byte`: in order, update IV
- Compute `diff = iv_byte - decrypt_iv[0]` (with wrap-around handling)
- Late packet (within 30): temporarily adjust IV, try decrypt, restore
- Lost packets: update IV, account for gaps
- Replay detection: `decrypt_history[iv_byte]` tracks seen packets

**Nonce resync:**
- Send empty CryptSetup to request resync
- Send CryptSetup with only client_nonce or server_nonce to resync that side

### 5.2 TLS (TCP Encryption)

TCP uses TLSv1.2+ with strong cipher suites. Client certificate is optional
but recommended for:
- Certificate-based authentication (automatic login)
- User registration
- Strong identity verification

---

## 6. Permission System

### 6.1 Permission Bits

All permission bits from `ACL.h`:

| Bit       | Hex        | Name              | Scope         | Description |
|-----------|------------|-------------------|---------------|-------------|
| 0         | `0x00001`  | Write             | Channel       | Full admin: edit ACLs, descriptions |
| 1         | `0x00002`  | Traverse          | Channel       | Move through channel (even without Enter) |
| 2         | `0x00004`  | Enter             | Channel       | Enter the channel |
| 3         | `0x00008`  | Speak             | Channel       | Transmit voice |
| 4         | `0x00010`  | MuteDeafen        | Channel       | Mute/deafen other users |
| 5         | `0x00020`  | Move              | Channel       | Move users in/out of channel |
| 6         | `0x00040`  | MakeChannel       | Channel       | Create sub-channels |
| 7         | `0x00080`  | LinkChannel       | Channel       | Link/unlink channels |
| 8         | `0x00100`  | Whisper           | Channel       | Whisper to this channel |
| 9         | `0x00200`  | TextMessage       | Channel       | Send text messages |
| 10        | `0x00400`  | MakeTempChannel   | Channel       | Create temporary channels |
| 11        | `0x00800`  | Listen            | Channel       | Listen to this channel (channel listener) |
| 16        | `0x10000`  | Kick              | Root only     | Kick users from server |
| 17        | `0x20000`  | Ban               | Root only     | Ban users from server |
| 18        | `0x40000`  | Register          | Root only     | Register other users |
| 19        | `0x80000`  | SelfRegister      | Root only     | Register self |
| 20        | `0x100000` | ResetUserContent  | Root only     | Reset user comments/avatars |
| 27        | `0x8000000`| Cached            | Internal      | Permission has been cached (internal flag) |

**All** = Write | Traverse | Enter | Speak | MuteDeafen | Move | MakeChannel |
LinkChannel | Whisper | TextMessage | MakeTempChannel | Listen | Kick | Ban |
Register | SelfRegister | ResetUserContent = `0x1F0FFF`

### 6.2 ACL Evaluation

- ACLs are evaluated top-to-bottom (first match)
- Each ACL entry can `grant` or `deny` permission bits
- ACLs can be inherited from parent channels (`inherit_acls`)
- ACLs can apply to current channel (`apply_here`) and/or subchannels (`apply_subs`)
- Groups: `all`, `auth` (authenticated), `in` (in channel), `out`, `sub`, and custom groups
- Tilde prefix (`~group`) = complement (everyone NOT in group)
- Hash prefix (`#group`) = inherited members only
- Dollar prefix (`$group`) = not inherited

### 6.3 Special Groups

- `all` -- all users
- `auth` -- authenticated users (any with a certificate)
- `in` -- users currently in the channel
- `out` -- users NOT in the channel  
- `sub` -- users in subchannels
- `~sub` -- users NOT in subchannels (complement)

---

## 7. Audio Codecs

### 7.1 Supported Codecs

| Codec       | Type ID | Version  | Notes |
|-------------|---------|----------|-------|
| CELT Alpha  | 0       | 0.7.0    | Legacy, bitstream never frozen |
| Speex       | 2       | -        | Low bitrate, legacy |
| CELT Beta   | 3       | 0.11.0   | Legacy, bitstream never frozen |
| Opus        | 4       | -        | **Preferred**, supported since Mumble 1.2.4 (2013) |

### 7.2 Codec Negotiation

Server sends `CodecVersion` to all clients whenever a user joins/leaves.
The server picks the codec supported by the most clients:

1. Collect CELT versions from all clients' `Authenticate.celt_versions`
2. If all clients support Opus (`Authenticate.opus = true`), use Opus
3. Otherwise, negotiate best CELT version (alpha preferred if `prefer_alpha`)
4. Clients that don't support the chosen codec can still send (but may not decode)

### 7.3 Audio Parameters

- Sample rate: 48000 Hz (Opus), 16000-32000 Hz (Speex), 48000 Hz (CELT)
- Channels: Mono (1 channel)
- Frame size: 10ms, 20ms, 40ms, or 60ms (typically 10ms or 20ms)
- Bandwidth: Configurable per-server (ServerConfig.max_bandwidth)
- Opus bitrate: Typically 40-96 kbps

---

## 8. Voice Targets / Whisper System

### 8.1 Registration

Client sends `VoiceTarget` message via TCP to register a whisper target:

- `id`: 1-30 (0 = normal talking, 31 = server loopback, both reserved)
- Each target can specify multiple sub-targets:
  - Specific users by session ID
  - A channel (optionally following links and/or including children)
  - An ACL group within a channel

### 8.2 Usage

After registration, set the target bits in the UDP voice packet header
(legacy: lower 5 bits; protobuf: `Audio.target` field) to the registered ID.

### 8.3 Audio Context (Server -> Client, protobuf only)

When the server relays audio, it sets the `Audio.context` field:
- 0 = Normal speech
- 1 = Shout (to channel)
- 2 = Whisper (direct to user)
- 3 = Received via channel listener

---

## 9. Positional Audio

### 9.1 Plugin Context & Identity

- `UserState.plugin_context`: Binary blob identifying the game/context.
  Only users with **identical** plugin_context receive each other's positional data.
  This field is NOT forwarded to other clients -- server uses it for matching only.
- `UserState.plugin_identity`: String identifying the user within the game.
  Also NOT forwarded to other clients.

### 9.2 Position Data

In audio packets (both legacy and protobuf), position is 3 floats:
- X, Y, Z coordinates in meters
- IEEE 754 float32, little-endian (legacy) or protobuf float encoding (protobuf)
- Only included if the user has an active positional plugin

---

## 10. Channel Features

### 10.1 Channel Properties
- **Permanent channels**: Persist across server restarts
- **Temporary channels**: Created with `temporary=true`, removed when empty
- **Linked channels**: Audio from one linked channel is heard in all linked channels
- **Position**: Integer weight for sorting in channel list
- **Max users**: Per-channel user limit (0 = use server default)
- **Enter restrictions**: ACL-controlled, indicated by `is_enter_restricted`/`can_enter`
- **Description**: Rich text (HTML), large descriptions sent as SHA1 hash

### 10.2 Channel Operations
- **Create**: Client sends `ChannelState` with `parent` and `name` (needs MakeChannel permission)
- **Remove**: Client sends `ChannelRemove` (needs Write permission)
- **Move**: Client sends `ChannelState` with new `parent` (needs Write + MakeChannel)
- **Rename**: Client sends `ChannelState` with new `name`
- **Link**: Client sends `ChannelState` with `links_add` (needs LinkChannel on both)
- **Unlink**: Client sends `ChannelState` with `links_remove`
- **Set description**: Client sends `ChannelState` with `description`
- **Set max users**: Client sends `ChannelState` with `max_users`
- **Set position**: Client sends `ChannelState` with `position`

---

## 11. User Management

### 11.1 User Operations
- **Move user**: Send `UserState` with target `session` and new `channel_id` (needs Move)
- **Kick**: Send `UserRemove` with `session` and optional `reason`
- **Ban**: Send `UserRemove` with `session`, `ban=true`, optional `reason`
  - `ban_certificate=true`: Ban by certificate hash
  - `ban_ip=true`: Ban by IP address
- **Server mute**: Send `UserState` with `session` and `mute=true` (needs MuteDeafen)
- **Server deaf**: Send `UserState` with `session` and `deaf=true` (needs MuteDeafen)
- **Self mute**: Send `UserState` with own session and `self_mute=true`
- **Self deaf**: Send `UserState` with own session and `self_deaf=true`
- **Set comment**: Send `UserState` with `comment` (own user, or needs ResetUserContent for others)
- **Set avatar/texture**: Send `UserState` with `texture`
- **Priority speaker**: Send `UserState` with `priority_speaker=true` (needs MuteDeafen)
- **Recording**: Send `UserState` with `recording=true` (requires recording_allowed on server)

### 11.2 User Registration
- **Register self**: Send `UserState` with own session and `user_id=0` (needs SelfRegister)
- **Register other**: Send `UserState` with session and `user_id=0` (needs Register)
- **List registered**: Send empty `UserList` to query, server responds with full list
- **Unregister**: Send `UserList` with `users` containing only `user_id` (no name) to remove

### 11.3 Certificate-Based Auth
- Client presents TLS certificate during handshake
- Server matches certificate hash to registered user
- Automatic login without password
- `UserState.hash` = certificate hash (hex SHA1)

---

## 12. Ban List Management

- **Query**: Send `BanList` with `query=true`
- **Replace**: Send `BanList` with `query=false` and full `bans` list
- Each ban entry: IP address, subnet mask, optional name/hash/reason/start/duration
- Duration in seconds (0 = permanent)
- Requires Ban permission on root channel

---

## 13. Server Query (Unauthenticated UDP Ping)

Mumble servers respond to unauthenticated UDP pings for server discovery:

**Request format** (12 bytes):
```
| 0x00 0x00 0x00 0x00 | Ident (8 bytes) |
```
First 4 bytes are zero (request type), followed by 8 bytes of client-chosen identifier.

**Response format** (24 bytes):
```
| Version (4 bytes) | Ident (8 bytes) | Users (4 bytes BE) | MaxUsers (4 bytes BE) | Bandwidth (4 bytes BE) |
```
- Version: `major.minor.patch.0` (1 byte each)
- Ident: echoed back from request
- Users: current connected users (big-endian uint32)
- MaxUsers: max allowed users (big-endian uint32)
- Bandwidth: max allowed bandwidth per user in bytes/sec (big-endian uint32)

---

## 14. UDP Connectivity & Fallback

### 14.1 Connectivity Check
1. Client sends UDP Ping packet to server
2. Server echoes it back
3. If client receives response -> UDP is usable
4. If no response -> fall back to TCP tunnel

### 14.2 TCP Tunnel Mode
- Voice packets sent as `UDPTunnel` (type 1) messages over TCP
- Same audio packet format, just wrapped in TCP framing
- Server switches per-client: uses UDP for clients with UDP connectivity,
  TCP tunnel for others

### 14.3 Switching
- Client stops receiving UDP ping responses -> switch to TCP tunnel
- Client continues sending UDP pings even when tunneling
- When UDP pings start getting responses again -> switch back to UDP

---

## 15. Variable-Length Integer (Varint) Encoding

Used extensively in legacy UDP protocol for sequence numbers, session IDs, etc.

| Prefix Bits   | Encoded Bytes | Decoded Range |
|---------------|---------------|---------------|
| `0xxxxxxx`    | 1 byte        | 7-bit positive (0-127) |
| `10xxxxxx`    | 2 bytes       | 14-bit positive (0-16383) |
| `110xxxxx`    | 3 bytes       | 21-bit positive (0-2097151) |
| `1110xxxx`    | 4 bytes       | 28-bit positive (0-268435455) |
| `111100__`    | 5 bytes       | 32-bit positive (prefix + 4 byte int) |
| `111101__`    | 9 bytes       | 64-bit (prefix + 8 byte long) |
| `111110__`    | 1 + varint    | Negative: decode following varint, negate |
| `111111xx`    | 1 byte        | -1 to -4: `~(xx)` |

Encoding is big-endian (most significant bits first in multi-byte values).

---

## 16. Channel Listeners

Added in Mumble 1.4.0. Users can "listen" to channels they're not in:

- `UserState.listening_channel_add`: Start listening to channels
- `UserState.listening_channel_remove`: Stop listening
- `UserState.listening_volume_adjustment`: Per-channel volume for listened channels
- Requires Listen permission on target channel
- Audio from listened channels delivered with context=3 (LISTEN)

---

## 17. Plugin Data System

### 17.1 Plugin Data Relay

Plugins can send arbitrary data between clients via `PluginDataTransmission`:

- `senderSession`: Set by server (identifies sender)
- `receiverSessions`: Target client sessions (packed uint32)
- `data`: Arbitrary binary payload
- `dataID`: Plugin identifier string (plugins check this to decide whether to process)

### 17.2 Context Actions

Server-side plugins can register custom context menu actions:

1. Server sends `ContextActionModify` with `operation=Add`, `action` ID, display `text`, 
   and `context` flags (Server=0x01, Channel=0x02, User=0x04)
2. Client displays action in appropriate context menus
3. User triggers action -> client sends `ContextAction` with target session/channel
4. Server-side plugin handles the action

---

## 18. SRV Record Discovery

Clients can discover Mumble servers via DNS SRV records:

- Query: `_mumble._tcp.<hostname>`
- Falls back to direct hostname resolution if no SRV records

---

## 19. Connection Summary / State Machine

```
Client                                          Server
  |                                                |
  |--- TCP connect (port 64738) ------------------>|
  |<------------- TLS handshake ------------------>|
  |--- Version ---------------------------------->|
  |<----------------------------------- Version ---|
  |--- Authenticate (username, password, opus) -->|
  |<------------------------------- CryptSetup ---|
  |<--- ChannelState (for each channel, pass 1) --|
  |<--- ChannelState (links, pass 2) -------------|
  |<--- UserState (for each user) ----------------|
  |<------------------------------- ServerSync ---|
  |<------------------------------ ServerConfig ---|
  |<--- CodecVersion -----------------------------|
  |                                                |
  |  *** Connection synchronized ***               |
  |                                                |
  |--- UDP Ping --------------------------------->|  (start UDP check)
  |<--------------------------------- UDP Ping ---|
  |                                                |
  |--- Ping (TCP, every ~15s) ------------------>|  (keep-alive, mandatory)
  |<----------------------------------- Ping ---|
  |                                                |
  |=== Voice (UDP or TCP tunnel) ================>|
  |<============== Voice (UDP or TCP tunnel) ======|
```

---

## 20. Implementation Notes for Go Client

### 20.1 Key Implementation Points

1. **TLS**: Use `tls.Dial` with `InsecureSkipVerify` option (many servers use self-signed certs). Present client certificate for registration/auth.

2. **Message framing**: Read 6 bytes header (2 type + 4 length), then read `length` bytes payload. Parse all types except UDPTunnel as protobuf. UDPTunnel payload is raw audio.

3. **Protobuf**: Use `google.golang.org/protobuf` to generate Go code from `Mumble.proto` and `MumbleUDP.proto`.

4. **OCB2-AES128**: Must implement OCB2 mode (not standard Go crypto). Reference: `CryptStateOCB2.cpp` in Mumble source. Key=16 bytes, IV=16 bytes, tag truncated to 3 bytes.

5. **Varint**: Implement the Mumble-specific varint encoding (NOT standard protobuf varint). Reference: `PacketDataStream.h`.

6. **Opus**: Use an Opus encoder/decoder library (e.g., `hraban/opus` or `pion/opus`). 48kHz, mono, 10-60ms frames.

7. **Keep-alive**: Send TCP Ping every 15 seconds. Server disconnects after 30s without ping.

8. **UDP fallback**: Implement TCP tunnel first, add UDP later. Much simpler to debug.

9. **Version**: Send both `version_v1` and `version_v2`. Recommend advertising 1.5.x to get protobuf UDP support.

10. **Bot mode**: Set `Authenticate.client_type = 1` for bot connections.

### 20.2 Existing Go Libraries

- `layeh.com/gumble` -- Go Mumble client library (mature, legacy protocol only)
- `proto` files can be compiled with `protoc --go_out=. Mumble.proto MumbleUDP.proto`

---

## 21. Public Server List

Mumble maintains a public server directory at `https://publist.mumble.info/v1/list`.

**Format:** XML with `<server>` elements as direct children of root.

**Fields per server (XML attributes):**
- `name` — Server display name
- `ip` — Hostname or IP address
- `port` — Port number (usually 64738)
- `country` — Full country name
- `country_code` — ISO 2-letter country code
- `continent_code` — AS/EU/NA/OC/SA
- `region` — Geographic subdivision
- `url` — Associated website
- `ca` — Certificate authority flag (0 or 1)

**Example:**
```xml
<server name="Example Server" ca="0" continent_code="EU" country="Germany"
  country_code="DE" ip="mumble.example.com" port="64738"
  region="Berlin" url="https://example.com/" />
```

No authentication required. User-Agent header recommended.

---

## 22. Version Auto-Detection and Format Selection

Servers running Mumble 1.5+ use **protobuf UDP format** (1-byte type prefix + protobuf body).
Servers running Mumble < 1.5 use **legacy UDP format** (header byte with codec/target + varint session/seq + payload).

**Detection:** Check the server's `Version` message:
- `version_v2` field (uint64): `major = (v2 >> 48) & 0xFFFF`, `minor = (v2 >> 32) & 0xFFFF`
- `version_v1` field (uint32): `major = (v1 >> 16) & 0xFF`, `minor = (v1 >> 8) & 0xFF`
- If `major > 1` or `(major == 1 && minor >= 5)` → use protobuf format
- Otherwise → use legacy format

**TCP tunnel fallback:** When UDP is blocked (NAT/firewall), the `udpReady` flag stays false
(no UDP ping response received). Voice should automatically fall back to TCP tunnel
(`UDPTunnel` message type) using the same format as UDP would use.

Both formats must use the same version-appropriate encoding for TCP tunnel as for UDP.
