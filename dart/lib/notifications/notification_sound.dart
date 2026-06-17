import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:uniclient/utils/mpv_player.dart';

import '../utils/debug.dart';
import 'notification_types.dart';

class NotificationSoundPlayer {
  Player? _player;
  String? _defaultSoundPath;

  // Called right as the alert sound starts, with the sound's length, so the
  // host can suppress other in-app audio for that duration — mirrors AyuGram
  // mixer()->suppressAll(track->getLengthMs()) (notifications_manager.cpp:776).
  // Wired to AudioService.duckFor in main.dart.
  Future<void> Function(Duration length)? onDuck;

  // Fired once the bundled default sound has been extracted to disk and
  // `defaultSoundPath` is populated. On first launch the extraction is async
  // (rootBundle.load suspends), so any consumer that cached an empty path at
  // init — notably the native manager's `sound-file` hint — must re-read it
  // here. AyuGram has the path ready synchronously via getSoundPath("msg_incoming")
  // (notifications_manager.cpp:1030-1037); this callback closes our async gap.
  void Function()? onDefaultSoundReady;

  void init() {
    _player = createPlayer();
    // Notification sounds are audio-only; assert no video track so libmpv never
    // opens its own output window for a sound file that happens to carry cover art.
    _player!.setVideoTrack(VideoTrack.no());
    // Extraction is async on the very first launch (the temp file isn't written
    // yet), so re-sync consumers once it lands — otherwise the native OS sound
    // hint stays empty for the whole session and the system default beep plays.
    _ensureDefaultSound().then((_) => onDefaultSoundReady?.call());
    Debug.log('NOTIF', 'Sound player init');
  }

  String? get defaultSoundPath => _defaultSoundPath;

  // Extracts the bundled real Telegram notification sound (msg_incoming.mp3) to a
  // temp file and caches its path. Mirrors AyuGram getSoundPath("msg_incoming")
  // which reads the embedded :/sounds/msg_incoming.mp3 resource.
  // (notifications_manager.cpp:995-1003, core_settings.cpp:1250)
  Future<void> _ensureDefaultSound() async {
    if (_defaultSoundPath != null) return;
    final path = '${Directory.systemTemp.path}/uniclient_msg_incoming.mp3';
    final file = File(path);
    if (!file.existsSync()) {
      final bytes = await rootBundle.load('assets/sounds/msg_incoming.mp3');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }
    _defaultSoundPath = path;
  }

  Future<void> play({
    required NotificationSettings settings,
    required NotificationData data,
  }) async {
    if (!settings.allowSound) return;
    if (data.soundNone) return;

    final player = _player;
    if (player == null) return;

    String soundPath;
    if (data.soundDocumentPath.isNotEmpty &&
        File(data.soundDocumentPath).existsSync()) {
      soundPath = data.soundDocumentPath;
    } else {
      await _ensureDefaultSound();
      final p = _defaultSoundPath;
      if (p == null) return;
      soundPath = p;
    }

    // Per-chat ringtone volume OVERRIDES the global volume when set (>0), matching
    // AyuGram AL_GAIN = (volumeOverride > 0) ? volumeOverride : notificationsVolume()/100.
    // (media_audio_track.cpp:155-160) — NOT a multiplier of the two.
    final vol = (data.perChatVolume > 0 ? data.perChatVolume : settings.volume)
        .clamp(0, 100)
        .toDouble();

    await player.setVolume(vol);
    // Load & demux WITHOUT auto-playing so the real track length is known before
    // playback starts. media_kit/libmpv reports `duration` asynchronously after
    // demuxing the file, so it is still ~Duration.zero synchronously right after
    // open() — unlike AyuGram's Track::fillFromFile which decodes inline and has
    // getLengthMs() ready immediately (notifications_manager.cpp:1036).
    await player.open(Media(soundPath), play: false);

    // Resolve the sound's real length the way AyuGram reads track->getLengthMs():
    // prefer the parsed duration, waiting briefly for libmpv to report it, and
    // only fall back to a fixed window if it genuinely never arrives (e.g. an
    // unparseable file). Without this wait the duration is always ~zero and the
    // duck window collapses to the 1800 ms guess, under-suppressing ringtones
    // longer than that.
    final duck = onDuck;
    var length = player.state.duration;
    if (duck != null && length < const Duration(milliseconds: 200)) {
      length = await player.stream.duration
          .firstWhere((d) => d >= const Duration(milliseconds: 200),
              orElse: () => player.state.duration)
          .timeout(const Duration(seconds: 1),
              onTimeout: () => player.state.duration);
    }
    if (length < const Duration(milliseconds: 200)) {
      length = const Duration(milliseconds: 1800);
    }

    await player.play();

    // Suppress other in-app audio (voice/music) for the sound's real length so
    // the alert doesn't overlap playing media at full volume — AyuGram
    // suppressAll(track->getLengthMs()) (notifications_manager.cpp:776).
    if (duck != null) {
      await duck(length);
    }
    Debug.log('NOTIF',
        'Sound played: vol=${vol.toInt()}%, duck=${length.inMilliseconds}ms');
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
