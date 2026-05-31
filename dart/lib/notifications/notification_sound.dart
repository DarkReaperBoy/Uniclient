import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../utils/debug.dart';
import 'notification_types.dart';

class NotificationSoundPlayer {
  Player? _player;
  String? _defaultSoundPath;

  void init() {
    _player = Player();
    _ensureDefaultSound();
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
    await player.open(Media(soundPath));
    await player.play();
    Debug.log('NOTIF', 'Sound played: vol=${vol.toInt()}%');
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
