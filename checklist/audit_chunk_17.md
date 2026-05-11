# audio_service — Backend Wiring & Metadata Issues

## Listen Duration Tracking Missing

- [ ] [CRITICAL] No music listen tracker — `audio_service.dart:5-121` has no mechanism to track how long audio was listened to or report it back to the backend. AyuGram's `MusicListenTracker` (`media_player_listen_tracker.h:20-38`, `media_player_listen_tracker.cpp:27-96`) tracks play start/stop times, accumulates listened duration in milliseconds, and reports via `messages.reportMusicListen()` API when: (1) 3+ seconds listened, (2) audio finishes, or (3) 60s pause timeout expires. The Dart AudioService has no analytics/tracking layer at all — playback is purely local, no backend notification of what was listened. Backend support exists (`telegram.go:` has `MessagesReportMusicListen` method) but is NOT exposed through the bridge (`dispatch_gen.go:` "Skipped: MessagesReportMusicListen"). Without bridge exposure and Dart integration, listen tracking is impossible. `audio_service.dart:5-121` ← `AyuGram/media/player/media_player_listen_tracker.cpp:59-96`

## Audio Metadata Dead Code

- [ ] [MAJOR] Audio metadata parameters never populated by callers — `audio_service.dart:34-39` accepts optional `performer`, `title`, `chatId` parameters and stores them in fields `_currentPerformer` (line 12), `_currentTitle` (line 13), `_currentChatId` (line 11); getters exist (lines 22-24) but are never called in any UI code. Meanwhile, callers in `message_bubble.dart:4108,4118,4497` pass only `filePath`, `msgId`, `msgTimestamp` — never populate the optional metadata fields even though `Message` class has `audioPerformer`, `audioTitle`, `senderName` fields. Dead code pattern: metadata accepted, stored, but never displayed or used. `audio_service.dart:12-14` ← `message_bubble.dart:4108`

## No Error Handling for File Open

- [ ] [MAJOR] File open has no error handling — `audio_service.dart:84` `await player.open(Media(filePath));` has no try-catch, no error callback, no fallback. If file doesn't exist, is corrupted, or fails to load (e.g. format unsupported), there is no user feedback or recovery. AyuGram's player wraps open() with error checks and UI feedback. The Dart code will silently fail and leave the player in an undefined state — `audio_service.dart:84` ← (AyuGram does error handling but no specific single file to cite; see `media_player_instance.cpp` for patterns)

## Confusing Toggle Pattern in Keyboard Shortcuts

- [ ] [MAJOR] Ambiguous playVoice('', currentMsgId) toggle pattern — `keyboard_shortcuts.dart:1218,1224,1230` calls `audio.playVoice('', audio.currentMsgId)` to toggle play/pause in media play/pause/playpause handlers. While this works due to the check `if (_currentMsgId == msgId && _player != null)` on `audio_service.dart:40` that re-uses the existing player, passing empty filePath is semantically confusing and could lead to bugs if someone calls playVoice() with empty filePath for any other reason. A dedicated `togglePlayback()` or `pauseResume()` method would be clearer and safer. `keyboard_shortcuts.dart:1218` ← (no specific AyuGram reference; Dart design issue)
