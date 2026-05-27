import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import '../utils/debug.dart';
import 'notification_types.dart';

class NotificationSoundPlayer {
  Player? _player;
  String? _defaultSoundPath;

  static const _sampleRate = 44100;

  void init() {
    _player = Player();
    _defaultSoundPath = _ensureDefaultSound();
    Debug.log('NOTIF', 'Sound player init, default=$_defaultSoundPath');
  }

  String? get defaultSoundPath => _defaultSoundPath;

  String _ensureDefaultSound() {
    final path =
        '${Directory.systemTemp.path}/uniclient_msg_incoming.wav';
    final file = File(path);
    if (file.existsSync()) return path;
    file.writeAsBytesSync(_generateNotificationTone());
    return path;
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
      soundPath = _defaultSoundPath ?? _ensureDefaultSound();
    }

    final globalVol = settings.volume.clamp(0, 100) / 100.0;
    final chatVol = data.perChatVolume.clamp(0, 100) / 100.0;
    final vol = (globalVol * chatVol * 100).clamp(0.0, 100.0);

    await player.setVolume(vol);
    await player.open(Media(soundPath));
    await player.play();
    Debug.log('NOTIF', 'Sound played: vol=${vol.toInt()}%');
  }

  Uint8List _generateNotificationTone() {
    const freq1 = 523.25; // C5
    const freq2 = 783.99; // G5
    const dur1 = 0.08;
    const dur2 = 0.12;
    const gap = 0.02;
    const totalDur = dur1 + gap + dur2;
    const amp = 0.3;

    final n = (totalDur * _sampleRate).toInt();
    final pcm = Int16List(n);

    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      double s = 0;
      if (t < dur1) {
        s = sin(2 * pi * freq1 * t) * _env(t, dur1) * amp;
      } else if (t >= dur1 + gap) {
        final lt = t - dur1 - gap;
        s = sin(2 * pi * freq2 * lt) * _env(lt, dur2) * amp;
      }
      pcm[i] = (s * 32767).clamp(-32768, 32767).toInt();
    }

    return _encodeWav(pcm);
  }

  double _env(double t, double dur) {
    const fadeIn = 0.01;
    const fadeOut = 0.02;
    if (t < fadeIn) return t / fadeIn;
    if (t > dur - fadeOut) return (dur - t) / fadeOut;
    return 1.0;
  }

  Uint8List _encodeWav(Int16List pcm) {
    final dataSize = pcm.length * 2;
    final buf = ByteData(44 + dataSize);
    buf.setUint32(0, 0x52494646, Endian.big); // RIFF
    buf.setUint32(4, 36 + dataSize, Endian.little);
    buf.setUint32(8, 0x57415645, Endian.big); // WAVE
    buf.setUint32(12, 0x666D7420, Endian.big); // fmt
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little); // PCM
    buf.setUint16(22, 1, Endian.little); // mono
    buf.setUint32(24, _sampleRate, Endian.little);
    buf.setUint32(28, _sampleRate * 2, Endian.little);
    buf.setUint16(32, 2, Endian.little);
    buf.setUint16(34, 16, Endian.little);
    buf.setUint32(36, 0x64617461, Endian.big); // data
    buf.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      buf.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return buf.buffer.asUint8List();
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
