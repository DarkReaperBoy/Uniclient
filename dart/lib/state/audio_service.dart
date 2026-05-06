import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class AudioService extends ChangeNotifier {
  Player? _player;
  String _currentMsgId = '';
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String _currentChatId = '';
  String _currentPerformer = '';
  String _currentTitle = '';
  int _currentMsgTimestamp = 0;
  final List<StreamSubscription> _subs = [];

  String get currentMsgId => _currentMsgId;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get duration => _duration;
  String get currentChatId => _currentChatId;
  String get currentPerformer => _currentPerformer;
  String get currentTitle => _currentTitle;
  int get currentMsgTimestamp => _currentMsgTimestamp;

  double get progress =>
      _duration.inMilliseconds > 0
          ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

  bool isPlayingMsg(String msgId) => _currentMsgId == msgId && _playing;
  bool isActiveMsg(String msgId) => _currentMsgId == msgId;

  Future<void> playVoice(String filePath, String msgId, {
    String chatId = '',
    String performer = '',
    String title = '',
    int msgTimestamp = 0,
  }) async {
    if (_currentMsgId == msgId && _player != null) {
      if (_playing) {
        await _player!.pause();
      } else {
        await _player!.play();
      }
      return;
    }

    await stop();

    final player = Player();
    _player = player;
    _currentMsgId = msgId;
    _currentChatId = chatId;
    _currentPerformer = performer;
    _currentTitle = title;
    _currentMsgTimestamp = msgTimestamp;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;

    _subs.add(player.stream.playing.listen((v) {
      if (_player != player) return;
      _playing = v;
      notifyListeners();
    }));
    _subs.add(player.stream.position.listen((v) {
      if (_player != player) return;
      _position = v;
      notifyListeners();
    }));
    _subs.add(player.stream.duration.listen((v) {
      if (_player != player) return;
      _duration = v;
      notifyListeners();
    }));
    _subs.add(player.stream.completed.listen((v) {
      if (_player != player || !v) return;
      _playing = false;
      _position = Duration.zero;
      notifyListeners();
    }));

    await player.open(Media(filePath));
  }

  Future<void> seek(double fraction) async {
    if (_player == null || _duration.inMilliseconds == 0) return;
    final target = Duration(
      milliseconds: (fraction.clamp(0.0, 1.0) * _duration.inMilliseconds).round(),
    );
    await _player!.seek(target);
  }

  Future<void> stop() async {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final old = _player;
    _player = null;
    _currentMsgId = '';
    _currentChatId = '';
    _currentPerformer = '';
    _currentTitle = '';
    _currentMsgTimestamp = 0;
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    if (old != null) {
      await old.dispose();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
