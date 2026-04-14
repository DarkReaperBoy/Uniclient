# Protobuf Type Audit — All 4,051 Exported Methods

Audit date: 2026-04-14. Pre-Step 13 verification of which method signatures are
protobuf-compatible and which need fixing or special handling.

## Summary

- **~3,400 methods**: Clean signatures (string, int, bool, base.go types). No changes needed.
- **~250 methods**: Fixable — return `map[string]interface{}` / `map[string]string` / unexported structs for known shapes. Define proper Go structs → clean proto.
- **~200 methods**: Telegram `tg.*` pass-throughs — fixable via TL schema → proto codegen tool. Worth it (primary platform).
- **~205 methods**: Truly untyped — GitHub `json.RawMessage` (~200) + `RawAPI`/`RawExec` (~5). Use `bytes` in proto. Not worth typing (secondary platform / untyped by design).

## Fixable Methods by Core

### Bale (~80 methods)
User API methods (`UserHTTPPost`, `UserSendRaw`, `UserForwardMessages`, etc.) return
`map[string]interface{}` for predictable JSON shapes. Bot API methods like `GetChat`,
`GetChatAdministrators`, `GetChatMember`, `GetOngoingCalls`, `GetStickerSet` also return
raw maps. `PromoteChatMember` takes `map[string]bool` for permissions.
`SendMessageWithKeyboard` takes `[][]map[string]string` for inline keyboards.

### TeamSpeak (~55 methods)
All ServerQuery responses return `[]map[string]string` or `map[string]string` with known
field sets. Examples: `ChannelListExtended`, `ClientListExtended`, `ServerGroupPermList`,
`BanListPaginated`, `PermissionList`, `FTGetFileList`, `WhoAmI`, `ServerInfo`, etc.
`ServerCreate`/`ClientUpdate`/`EditChannel`/`ServerEdit` take `map[string]string` params
with known keys.

### XMPP (~40 methods)
Methods returning `*xmppIQ` (raw IQ stanza): `DiscoInfo`, `DiscoItems`, `GetVCard4`,
`GetInbox`, `GetMAMPreferences`, `GetPubSubItems`, `SearchUsersXMPP`, `ExecuteCommand`,
`FetchOMEMODeviceList`, `FetchOMEMOBundle`, etc. These parse known XML stanza types —
should return typed structs. Also `GetVCard`/`GetMUCConfig` return `map[string]string`
with known keys.

### Rubika (~30 methods)
`GetGroupInfo`, `GetChannelInfo`, `GetObjectByUsername`, `GetGroupAllMembers`, `GetAvatars`,
`GetMyStickerSets`, `LoginDisableTwoStep`, `SearchGlobalMessages`, `GetUserInfo`, etc.
All return `map[string]interface{}` for known JSON shapes. Bot methods (`BotGetUpdates`,
`BotGetChat`, `BotGetMe`, `BotCheckJoin`) similarly return known shapes.

### Matrix (~30 of ~55 untyped methods)
Known shapes: `GetURLPreview`, `GetTurnServer`, `GetDeviceInfo`, `GetCapabilities`,
`GetLoginFlows`, `GetPushers`, `GetTags`, `WhoisUser`, `GetVersions`, `GetDirectChats`,
`GetRoomSummary`, `GetMediaConfigAuth`, etc. Some (`SlidingSync`, `SetAccountData`,
`UploadCrossSigningKeys`) are genuinely freeform.

### Mumble (~8 methods)
Unexported structs that need exporting: `mumbleBanEntry`, `mumbleACLMsg`, `mumbleACLGroup`,
`mumbleACLEntry`, `mumbleVoiceTargetEntry`, `mumbleServerConfigMsg`, `MumbleVoicePacket`
(already exported), `MumbleCodecVersionEvent`, `MumbleContextActionEvent`,
`MumblePermissionDeniedEvent`, `MumbleRejectEvent`, `MumbleSuggestConfigEvent`.

### DeltaChat (~7 methods)
Unexported structs: `dcWebxdcUpdate`, `dcLocation`, `dcTransport`.
Exported structs needing proto messages: `DeltaChatWebxdcInfo`, `DeltaChatStorageReport`,
`DeltaChatProviderInfo`, `DeltaChatQuotaInfo`.

### IRC (6 struct types)
Already-exported structs needing proto messages: `IRCWhoEntry`, `IRCWhowasEntry`,
`IRCUserhostEntry`, `IRCListEntry`, `IRCServerInfo`, `IRCBanEntry`.

## Telegram `tg.*` pass-throughs (~200) — FIXABLE via TL schema codegen

All `Account*`, `Channels*`, `Messages*`, `Phone*`, `Photos*`, `Stats*`, `Stickers*`,
`Stories*`, `Upload*`, `Users*` raw methods take and return gotd/td library types.
gotd generates its Go structs from Telegram's TL schema (machine-readable). We can write
a TL schema → proto codegen tool that generates matching proto messages for every gotd
type used in TelegramCore method signatures. When gotd updates, re-run the tool.
**Decision:** Build the codegen tool. Full type safety for all 200 methods. Worth it
because Telegram is the primary platform and the GUI will use these.

## Truly Untyped Methods (~205) — `bytes` in proto

### GitHub `json.RawMessage` (~200)
Every platform-specific GitHub method returns `(json.RawMessage, error)`. GitHub REST
returns arbitrary JSON per endpoint. OpenAPI → proto codegen is possible but not worth it:
GitHub is a secondary platform, GUI uses Core interface not raw REST endpoints, and
GitHub's OpenAPI spec is massive and changes constantly.
**Decision:** `bytes` field in proto. Acceptable tradeoff.

### Other inherently untyped (~5)
- `RawAPI` (Rubika) — untyped by design
- `RawExec` (TeamSpeak) — arbitrary ServerQuery commands
- `UserHTTPPost`/`UserSendRaw` (Bale) — raw API passthrough
**Decision:** `bytes` field. Correct by design — these exist for untyped passthrough.

## Non-Type Issues (handled in codegen)

| Issue | Count | Proto solution |
|---|---|---|
| `func(...)` callbacks | ~35 | Event port + `Update` messages |
| `io.Reader` in FileUpload | 10 | `string file_path` |
| `uint32`/`float32`/`[]uint32` | ~50 | Direct proto types |
| `[3]float32` (3D audio) | 3 | `repeated float` (length 3) |
| `[]int16` (PCM audio) | 3 | `bytes` (raw PCM) |
| Variadic `...string` | 5 | `repeated string` |
| `time.Duration`/`time.Time` | 3 | `int64` millis |
| `byte` mode chars | 3 | `uint32` |
| `<-chan struct{}` | 2 | Event port |
| `map[string][]string` | 3 | Custom proto message |
| `map[string]bool` | 2 | `map<string,bool>` |
| `map[int]map[string]string` | 2 | `map<int32, KVMap>` |
| No-error returns | ~10 | Wrap in response message |
