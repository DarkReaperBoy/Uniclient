# TeamSpeak 3 — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 4)
**Current:** 328 methods, ~7,200 lines. Real TS3 UDP client protocol + ServerQuery.
**Confirmed working:** 38 extended + 55 Core (all pass on Docker TS3 3.13.7, Step 2). 80 new methods added (Step 4), not yet tested.
**Remaining:** 0 methods — 100% protocol coverage.

All methods implemented. ServerQuery commands, notification handlers, audio, and client SDK features fully covered.

---

## Step 4 — Newly Implemented (80 methods) — NEEDS TESTING

### Server Instance Management (6)
- [x] HostInfo, InstanceInfo, InstanceEdit, BindingList, ServerProcessStop, ServerIdGetByPort

### Password Verification (2)
- [x] VerifyServerPassword, VerifyChannelPassword

### Ban Enhancements (3)
- [x] BanClientDBID, BanAddMyTSID, BanListPaginated

### Newer ServerQuery Commands (2)
- [x] ClientAddServerGroup, ClientDelServerGroup

### Server Notification Handlers (13)
- [x] HandleServerEdited, HandleServerUpdated, HandleChannelEdited, HandleChannelCreated
- [x] HandleChannelDeleted, HandleChannelMoved, HandleChannelDescriptionChanged
- [x] HandleChannelPasswordChanged, HandleClientUpdated, HandleTokenUsed
- [x] HandleTalkStatusChange, HandleConnectStatusChange, HandleCurrentServerConnectionChanged

### Extended List Flags (3)
- [x] ClientListExtended, ChannelListExtended, ServerListExtended

### 3D Audio Positioning (4)
- [x] Set3DListenerAttributes, SetChannel3DAttributes, Set3DWaveAttributes, System3DSettings

### Audio Device Management (9)
- [x] GetPlaybackDeviceList, GetCaptureDeviceList, GetPlaybackModeList, GetCaptureModeList
- [x] OpenPlaybackDevice, OpenCaptureDevice, ClosePlaybackDevice, CloseCaptureDevice, ActivateCaptureDevice

### Audio Preprocessing (6)
- [x] GetPreProcessorInfo, GetPreProcessorConfig, SetPreProcessorConfig
- [x] GetPlaybackConfig, SetPlaybackConfig, SetClientVolumeModifier

### Wave File Playback (4)
- [x] PlayWaveFile, PlayWaveFileHandle, PauseWaveFileHandle, CloseWaveFileHandle

### Custom Audio Devices (4)
- [x] RegisterCustomDevice, UnregisterCustomDevice, ProcessCustomCaptureData, AcquireCustomPlaybackData

### Voice Recording (2)
- [x] StartVoiceRecording, StopVoiceRecording

### Whisper List Management (3)
- [x] SetWhisperList, IsWhispering, IsReceivingWhisper

### Talk Power (1)
- [x] SetIsTalker

### Client Operations (6)
- [x] RequestClientsMove, RequestClientsKickFromChannel, RequestClientsKickFromServer
- [x] RequestMuteClientsTemporary, RequestUnmuteClientsTemporary, RequestClientEditDescription

### Avatar Retrieval (1)
- [x] GetAvatar

### Channel Info Request (2)
- [x] ChannelInfoRequest, RequestInfoUpdate

### Snapshot Enhancements (2)
- [x] ServerSnapshotDeployKeepFiles, ServerSnapshotPassword

### Bookmarks & Profiles (3)
- [x] GetBookmarkList, CreateBookmark, GetProfileList

### Permission Enhancements (2)
- [x] PermissionListNew, PermCommandsPermSID

### Legacy Codec Support (1)
- [x] DecodeLegacyCodec
