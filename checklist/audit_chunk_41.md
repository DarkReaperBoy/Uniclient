# call_screen — Group Call Panel + Minimised Call Bar

- [ ] [CRITICAL] "End for all" button calls identical `onLeave()` as "Leave" — no engine discard call; AyuGram calls `MTPphone_DiscardGroupCall` for end-for-all vs `MTPphone_LeaveGroupCall` for leave — `call_screen.dart:1211-1215` ← `calls_group_call.cpp:2180,2247`

- [ ] [CRITICAL] All three group call menu items (Sound, Invite members, Settings) are stubs that only call `Navigator.pop(ctx)` with no real action; AyuGram menu opens JoinAs selector, recording toggle, `Box(SettingsBox, strong)`, and a real screen-share toggle — `call_screen.dart:1163-1179` ← `calls_group_menu.cpp:519-620`

- [ ] [CRITICAL] `toggleCamera` always passes hardcoded `true`, never toggles off; AyuGram calls `toggleCameraSharing(!_call->isSharingCamera())` deriving the new state from current state — `call_screen.dart:1122` ← `calls_panel.cpp:423`

- [ ] [CRITICAL] `toggleScreenSharing` discards the selected source ID and `_shareAudio` flag, calls `engine.toggleScreenSharing(accountId, callId, true)` with no capture source; AyuGram's `GroupCall::toggleScreenSharing(std::optional<QString> uniqueId, bool withAudio)` requires the actual source device ID and audio flag to wire the capture pipeline — `call_screen.dart:1127-1133` ← `calls_group_call.cpp:920-936`

- [ ] [CRITICAL] KDE window enumeration calls `org.kde.KWin.queryWindowInfo` which does not exist in KWin's D-Bus interface; the call always throws, is swallowed by `catch (_) {}`, and returns an empty list — the "Windows" tab in the screen-share chooser is permanently empty; AyuGram uses `tgcalls::DesktopCaptureSource` from the tgcalls library — `call_screen.dart:2133` ← `desktop_capture_choose_source.cpp`

- [ ] [CRITICAL] Default panel width is `720.0` (RTMP width) for all calls; AyuGram sets `groupCallWidth: 380px` for standard group calls and only uses `groupCallWidthRtmp: 720px` when `isRtmp` — the dialog opens >89% wider than spec for normal calls — `call_screen.dart:57` ← `calls.style:groupCallWidth` + `calls_group_panel.cpp:1788-1797`

- [ ] [MAJOR] `_ScreenSourceThumb` shows a generic `Icons.monitor` / `Icons.web_asset` placeholder instead of a real live preview of the window/screen; AyuGram renders actual capture thumbnails via `tgcalls::DesktopCaptureSource::captureImage()` — `call_screen.dart:2504-2510` ← `desktop_capture_choose_source.cpp`

- [ ] [MAJOR] `_LinearBlobsPainter.shouldRepaint` unconditionally returns `true`, forcing a full canvas repaint every animation frame (60 fps) regardless of whether `blobRadii` or `level` changed — `call_screen.dart:1632` ← `calls_top_bar.cpp` (LinearBlobs animation)

- [ ] [MAJOR] `_SpeakerBlobAvatarState._onTick` and `_BigMuteButtonState._onTick` both call `setState(() {})` on every animation tick, rebuilding the full widget subtree at 60 fps; the animated region should be isolated behind a `RepaintBoundary` with the painter's own `shouldRepaint` gating canvas work — `call_screen.dart:500,790` ← `calls_group_panel.cpp` (blob tick pattern)

- [ ] [MAJOR] `_shareAudio` checkbox value is captured in the screen-share chooser UI but never forwarded when starting screen sharing; `engine.toggleScreenSharing` is called without it, so audio capture is always disabled regardless of user choice; AyuGram passes `withAudio` as the second parameter — `call_screen.dart:2095,1132` ← `calls_group_call.cpp:921`
