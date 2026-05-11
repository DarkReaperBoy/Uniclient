# call_panel — Audit Findings

- [ ] [CRITICAL] `_onScreenShareTap()` calls `engine.endCall()` to stop screen sharing — this terminates the entire call instead of stopping only screen capture — `call_panel.dart:229` ← `calls_panel.cpp:394-417` (`chooseSourceStop()` stops capture only; the call stays live)

- [ ] [CRITICAL] `_onScreenShareTap()` calls `engine.startCall(accountId, widget.info.callerId, video: true)` to start screen sharing — this initiates a brand-new call instead of activating screen capture on the existing one; the correct engine method `toggleScreenSharing()` exists at `engine_service.dart:1800` but is never called — `call_panel.dart:234` ← `calls_panel.cpp:394-417`

- [ ] [CRITICAL] The chosen screen-share source is never passed to the engine: `showScreenShareChooser` result is captured into `result` but only its null-ness is checked; the source ID is discarded and `startCall` is called unconditionally — `call_panel.dart:232-235` ← `calls_panel.cpp:410-413` (`chooseSourceAccepted(sourceId, audio)` receives the chosen source)

- [ ] [MAJOR] `_isMuted` and `_isCameraOn` are pure local state (lines 116-117) updated only on user tap; there is no subscription to engine mute/camera events so any state change triggered server-side or from another device is silently ignored — `call_panel.dart:116-117, 250-257` ← `calls_panel.cpp:739-758` (`_call->mutedValue()` stream drives button state reactively)

- [ ] [MAJOR] Device selector menu always shows only hardcoded `'Default Camera'` and `'Default Microphone'` strings (lines 118-119, 285-289, 295-296); no real device enumeration happens — AyuGram builds the menu from live `Webrtc::DeviceInfo` lists via the environment API — `call_panel.dart:278-300` ← `calls/ui/calls_device_menu.cpp:1-100` (`Selector` widget subscribes to `devices` producer from `Webrtc::Environment`)

- [ ] [MAJOR] `_onAddPeopleTap()` immediately calls `engine.createConferenceCall(accountId)` and shows a copy-link dialog; AyuGram shows `Group::PrepareInviteBox` which offers both "invite specific contacts" (migrates call, passes mute state and video capture) and "get shareable link" as separate options — `call_panel.dart:260-275` ← `calls_panel.cpp:425-457`

- [ ] [MAJOR] `_EncryptionFingerprint` uses a fixed-interval linear step carousel (each slot advances every `_kCarouselOneMs=100ms`); AyuGram uses a physics-based animation with per-slot speed, acceleration, and deceleration computed per frame — `call_panel.dart:1260-1266` ← `calls_emoji_fingerprint.cpp:100-250` (`state->update` kinematic solver)

- [ ] [MAJOR] Fingerprint tooltip text is generic `'This call is end-to-end encrypted'`; AyuGram localises it with the callee's name: `lng_call_fingerprint_tooltip(lt_user, call->user()->name())` — `call_panel.dart:1272` ← `calls_emoji_fingerprint.cpp` (`EmojiTooltipShower::tooltipText` / `tr::lng_call_fingerprint_tooltip`)

- [ ] [MAJOR] `_CallActionButton` circle is 56 px (64 px in connecting state); AyuGram `callAnswer`/`callHangup` icon circle (`bgSize`) is 44 px — 27% larger than spec — `call_panel.dart:906, 552-553` ← `calls.style:115` (`bgSize: 44px`)

- [ ] [MAJOR] `_CallControlButton` circle is 48 px; AyuGram `callButton.rippleAreaSize` is 44 px — `call_panel.dart:1057-1058` ← `calls.style:96` (`rippleAreaSize: 44px`)
