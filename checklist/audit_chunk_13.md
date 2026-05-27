# notification_sound — Fixed: Missing player.play() call

- [x] **CRITICAL** Notification sound never plays — `notification_sound.dart:56` was missing `await player.play()` to start playback. The media_kit library does NOT auto-play after open() (confirmed by media_viewer.dart lines 610, 2359, 2378, 4679 and chat_view.dart line 10370 which all call `player.play()` explicitly after opening). Result: notifications were silent. ← **FIXED** at line 57
