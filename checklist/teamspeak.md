# TeamSpeak 3 — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 248 methods, ~5,900 lines. Real TS3 UDP client protocol + ServerQuery.
**Confirmed working:** 38 extended + 55 Core (all pass on Docker TS3 3.13.7, Step 2).
**Remaining:** ~80 items listed below.

Only features NOT yet implemented are listed.

---

## Server Instance Management (6 commands)

- [ ] HostInfo — Display host info (uptime, timestamp, total virtual servers)
- [ ] InstanceInfo — Display instance configuration (DB revision, FT port, etc.)
- [ ] InstanceEdit — Modify instance configuration
- [ ] BindingList — List bound IP addresses
- [ ] ServerProcessStop — Shut down entire TS3 server process
- [ ] ServerIdGetByPort — Look up virtual server DB ID by UDP port

## Password Verification (2 commands)

- [ ] VerifyServerPassword — Check if password matches virtual server
- [ ] VerifyChannelPassword — Check if password matches channel

## Ban Enhancements (3 commands)

- [ ] BanClientDBID — Ban by database ID (vs online client ID)
- [ ] BanAddMyTSID — Ban by myTeamSpeak ID (server 3.5.0+)
- [ ] BanListPaginated — `banlist` with -start/-duration/-count pagination (3.8.0+)

## Newer ServerQuery Commands (2 commands, 3.9.0+)

- [ ] ClientAddServerGroup — Add server groups to client (alternative to ServerGroupAddClient)
- [ ] ClientDelServerGroup — Remove server groups from client

## Server Notifications — Missing Events (13 events)

- [ ] HandleServerEdited — `notifyserveredited` — Server properties modified
- [ ] HandleServerUpdated — `notifyserverupdated` — Server properties periodic update
- [ ] HandleChannelEdited — `notifychanneledited` — Channel properties edited
- [ ] HandleChannelCreated — `notifychannelcreated` — New channel created
- [ ] HandleChannelDeleted — `notifychanneldeleted` — Channel deleted
- [ ] HandleChannelMoved — `notifychannelmoved` — Channel moved
- [ ] HandleChannelDescriptionChanged — `notifychanneldescriptionchanged`
- [ ] HandleChannelPasswordChanged — `notifychannelpasswordchanged`
- [ ] HandleClientUpdated — `notifyclientupdated` — Client properties changed
- [ ] HandleTokenUsed — `notifytokenused` — Privilege key used
- [ ] HandleTalkStatusChange — `notifytalkstatuschange` — Client talking state
- [ ] HandleConnectStatusChange — `notifyconnectstatuschange`
- [ ] HandleCurrentServerConnectionChanged — `notifycurrentserverconnectionchanged`

## Extended List Flags (3 enhancements)

- [ ] ClientListExtended — `clientlist` with -uid/-away/-voice/-times/-groups/-info/-icon/-country/-ip/-badges
- [ ] ChannelListExtended — `channellist` with -topic/-flags/-voice/-limits/-icon/-secondsempty/-banners
- [ ] ServerListExtended — `serverlist` with -uid/-short/-all/-onlyoffline

## 3D Audio Positioning (4 methods)

- [ ] Set3DListenerAttributes — Set listener position/orientation in 3D space
- [ ] SetChannel3DAttributes — Position a client in 3D space
- [ ] Set3DWaveAttributes — Position a wave file sound in 3D
- [ ] System3DSettings — Configure distance factor and rolloff scale

## Audio Device Management (8 methods)

- [ ] GetPlaybackDeviceList — List available playback devices
- [ ] GetCaptureDeviceList — List available capture devices
- [ ] GetPlaybackModeList / GetCaptureModeList — List modes
- [ ] OpenPlaybackDevice / OpenCaptureDevice — Open specific devices
- [ ] ClosePlaybackDevice / CloseCaptureDevice — Close devices
- [ ] ActivateCaptureDevice — Activate audio capture

## Audio Preprocessing (5 methods)

- [ ] GetPreProcessorInfo — Query voice activity level
- [ ] GetPreProcessorConfig / SetPreProcessorConfig — AGC, denoise, VAD settings
- [ ] GetPlaybackConfig / SetPlaybackConfig — Playback settings
- [ ] SetClientVolumeModifier — Per-client volume adjustment

## Wave File Playback (4 methods)

- [ ] PlayWaveFile — Play local wave file through audio pipeline
- [ ] PlayWaveFileHandle — Play with handle for control
- [ ] PauseWaveFileHandle — Pause wave playback
- [ ] CloseWaveFileHandle — Stop and close wave playback

## Custom Audio Devices (4 methods)

- [ ] RegisterCustomDevice — Register custom audio I/O device
- [ ] UnregisterCustomDevice — Unregister custom device
- [ ] ProcessCustomCaptureData — Feed raw PCM as capture input
- [ ] AcquireCustomPlaybackData — Read mixed playback output as PCM

## Voice Recording (2 methods)

- [ ] StartVoiceRecording — Start recording voice to file
- [ ] StopVoiceRecording — Stop recording

## Whisper List Management (3 methods)

- [ ] SetWhisperList — Set persistent whisper list on server (channels + clients)
- [ ] IsWhispering — Check if client is currently whispering
- [ ] IsReceivingWhisper — Check if receiving whisper from a client

## Talk Power (1 method)

- [ ] SetIsTalker — Grant/revoke talker status to another client

## Client Operations (6 methods)

- [ ] RequestClientsMove — Move multiple clients at once
- [ ] RequestClientsKickFromChannel — Kick multiple from channel
- [ ] RequestClientsKickFromServer — Kick multiple from server
- [ ] RequestMuteClientsTemporary — Temporarily mute multiple clients
- [ ] RequestUnmuteClientsTemporary — Temporarily unmute multiple
- [ ] RequestClientEditDescription — Set another client's description

## Avatar Retrieval (1 method)

- [ ] GetAvatar — Download another client's avatar

## Channel Info Request (2 methods)

- [ ] ChannelInfoRequest — Request full channel info (vs cached)
- [ ] RequestInfoUpdate — Force refresh server/channel/client info

## Snapshot Enhancements (2 methods)

- [ ] ServerSnapshotDeployKeepFiles — Deploy with -keepfiles flag (3.10.0+)
- [ ] ServerSnapshotPassword — Snapshot with password parameter (3.10.0+)

## Bookmarks & Profiles (3 methods)

- [ ] GetBookmarkList — Retrieve saved server bookmarks
- [ ] CreateBookmark — Create a new server bookmark
- [ ] GetProfileList — List audio/identity profiles

## Permission Enhancements (2 methods)

- [ ] PermissionListNew — `permissionlist -new` format (3.0.7+)
- [ ] PermCommandsPermSID — String-based permission references with `-permsid` flag

## Legacy Codec Support (1 method)

- [ ] DecodeLegacyCodec — Handle receiving Speex/CELT audio from older clients
