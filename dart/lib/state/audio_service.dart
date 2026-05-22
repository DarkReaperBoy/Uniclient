import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../bridge/engine_service.dart';

class AudioService extends ChangeNotifier {
  final EngineService _engine;

  AudioService(this._engine);

  Player? _player;
  String _currentMsgId = '';
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String _currentChatId = '';
  String _currentPerformer = '';
  String _currentTitle = '';
  int _currentMsgTimestamp = 0;
  String _currentAccountId = '';
  String _currentDocId = '';
  int _currentAccessHash = 0;
  List<int> _currentFileRef = const [];
  bool _isSong = false;
  final List<StreamSubscription> _subs = [];

  DateTime? _listenStartTime;
  int _accumulatedMs = 0;
  Timer? _pauseTimer;
  static const _pauseTimeoutSec = 60;
  static const _minListenMs = 3000;

  static const _kMinLengthSavePosMusicSec = 20 * 60;
  static const _kMinLengthSavePosVideoSec = 60;
  static const _kPositionNotifyThrottleMs = 250;
  static const _kMaxSavedPositions = 256;
  final Map<String, Duration> _savedPositions = {};
  String _configDir = '';
  Timer? _positionSaveTimer;
  Timer? _positionNotifyTimer;
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);

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

  void setConfigDir(String dir) {
    _configDir = dir;
    _loadSavedPositions();
  }

  void _loadSavedPositions() {
    if (_configDir.isEmpty || kIsWeb) return;
    try {
      final file = File('$_configDir/audio_positions.json');
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _savedPositions.clear();
        final entries = data.entries.toList();
        final start = entries.length > _kMaxSavedPositions
            ? entries.length - _kMaxSavedPositions
            : 0;
        for (var i = start; i < entries.length; i++) {
          _savedPositions[entries[i].key] = Duration(milliseconds: entries[i].value as int);
        }
      }
    } catch (_) {}
  }

  void _persistSavedPositions() {
    if (_configDir.isEmpty || kIsWeb) return;
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(const Duration(milliseconds: 500), () {
      try {
        final data = <String, int>{};
        for (final entry in _savedPositions.entries) {
          data[entry.key] = entry.value.inMilliseconds;
        }
        File('$_configDir/audio_positions.json')
            .writeAsStringSync(jsonEncode(data));
      } catch (_) {}
    });
  }

  void _schedulePositionNotify() {
    if (_positionNotifyTimer?.isActive == true) return;
    final elapsed = DateTime.now().difference(_lastPositionNotify).inMilliseconds;
    if (elapsed >= _kPositionNotifyThrottleMs) {
      _lastPositionNotify = DateTime.now();
      notifyListeners();
    } else {
      _positionNotifyTimer = Timer(
        Duration(milliseconds: _kPositionNotifyThrottleMs - elapsed),
        () {
          _lastPositionNotify = DateTime.now();
          notifyListeners();
        },
      );
    }
  }

  void togglePlayback() {
    if (_player == null) return;
    if (_playing) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  Future<void> playVoice(String filePath, String msgId, {
    String chatId = '',
    String performer = '',
    String title = '',
    int msgTimestamp = 0,
    String accountId = '',
    String docId = '',
    int accessHash = 0,
    List<int> fileRef = const [],
    bool isSong = false,
  }) async {
    if (_currentMsgId == msgId && _player != null) {
      togglePlayback();
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
    _currentAccountId = accountId;
    _currentDocId = docId;
    _currentAccessHash = accessHash;
    _currentFileRef = fileRef;
    _isSong = isSong;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
    _accumulatedMs = 0;
    _listenStartTime = null;

    _subs.add(player.stream.playing.listen((v) {
      if (_player != player) return;
      final wasPlaying = _playing;
      _playing = v;
      if (v && !wasPlaying) {
        _listenStartTime = DateTime.now();
        _pauseTimer?.cancel();
      } else if (!v && wasPlaying) {
        _accumulateListenTime();
        _startPauseTimer();
      }
      notifyListeners();
    }));
    _subs.add(player.stream.position.listen((v) {
      if (_player != player) return;
      _position = v;
      _schedulePositionNotify();
    }));
    _subs.add(player.stream.duration.listen((v) {
      if (_player != player) return;
      _duration = v;
      notifyListeners();
    }));
    _subs.add(player.stream.completed.listen((v) {
      if (_player != player || !v) return;
      _accumulateListenTime();
      _reportListenIfNeeded();
      _accumulatedMs = 0;
      _playing = false;
      _position = Duration.zero;
      notifyListeners();
    }));

    try {
      await player.open(Media(filePath));
      final savedPos = _savedPositions[_currentDocId];
      if (savedPos != null && savedPos > Duration.zero) {
        await player.seek(savedPos);
        _savedPositions.remove(_currentDocId);
        _persistSavedPositions();
      }
    } catch (e) {
      debugPrint('AudioService: failed to open $filePath: $e');
      await stop();
    }
  }

  void Function()? onPreviousTrack;
  void Function()? onNextTrack;

  void previous() {
    if (_player == null) return;
    if (_position.inSeconds > 3) {
      _player!.seek(Duration.zero);
    } else if (onPreviousTrack != null) {
      onPreviousTrack!();
    } else {
      _player!.seek(Duration.zero);
    }
  }

  void next() {
    if (onNextTrack != null) {
      onNextTrack!();
    } else {
      stop();
    }
  }

  Future<void> seek(double fraction) async {
    if (_player == null || _duration.inMilliseconds == 0) return;
    final target = Duration(
      milliseconds: (fraction.clamp(0.0, 1.0) * _duration.inMilliseconds).round(),
    );
    await _player!.seek(target);
  }

  Future<void> stop() async {
    _savePositionIfNeeded();
    _accumulateListenTime();
    _reportListenIfNeeded();
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _listenStartTime = null;
    _accumulatedMs = 0;

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
    _currentAccountId = '';
    _currentDocId = '';
    _currentAccessHash = 0;
    _currentFileRef = const [];
    _isSong = false;
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    if (old != null) {
      await old.dispose();
    }
    notifyListeners();
  }

  void _accumulateListenTime() {
    if (_listenStartTime != null) {
      _accumulatedMs += DateTime.now().difference(_listenStartTime!).inMilliseconds;
      _listenStartTime = null;
    }
  }

  void _startPauseTimer() {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(const Duration(seconds: _pauseTimeoutSec), () {
      _reportListenIfNeeded();
    });
  }

  void _savePositionIfNeeded() {
    if (_currentDocId.isEmpty || _position <= Duration.zero) return;
    final totalSec = _duration.inSeconds;
    final minSec = _isSong ? _kMinLengthSavePosMusicSec : _kMinLengthSavePosVideoSec;
    if (totalSec >= minSec) {
      _savedPositions[_currentDocId] = _position;
      while (_savedPositions.length > _kMaxSavedPositions) {
        _savedPositions.remove(_savedPositions.keys.first);
      }
      _persistSavedPositions();
    }
  }

  Future<void> _reportListenIfNeeded() async {
    if (!_isSong) {
      _accumulatedMs = 0;
      return;
    }
    if (_accumulatedMs < _minListenMs) return;
    if (_currentAccountId.isEmpty || _currentDocId.isEmpty) return;
    if (_currentAccessHash == 0 && _currentFileRef.isEmpty) return;

    final docIdInt = int.tryParse(_currentDocId);
    if (docIdInt == null) return;

    final duration = (_accumulatedMs / 1000).round();
    _accumulatedMs = 0;

    final accountId = _currentAccountId;
    final accessHash = _currentAccessHash;
    final usedFileRef = List<int>.from(_currentFileRef);
    final chatId = _currentChatId;
    final msgId = _currentMsgId;

    Future<void> send(List<int> fileRef) async {
      await _engine.reportMusicListen(
        accountId,
        docIdInt,
        accessHash,
        fileRef,
        duration,
      );
    }

    try {
      await send(usedFileRef);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('FILE_REFERENCE_')) {
        try {
          final newRef = await _engine.refreshDocumentFileRef(
            accountId, docIdInt, chatId, msgId,
          );
          if (newRef.isNotEmpty && !_listEquals(newRef, usedFileRef)) {
            _currentFileRef = newRef;
            await send(newRef);
          }
        } catch (_) {}
      } else {
        debugPrint('AudioService: reportMusicListen failed: $e');
      }
    }
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _positionNotifyTimer?.cancel();
    _positionSaveTimer?.cancel();
    _pauseTimer?.cancel();
    _savePositionIfNeeded();
    _accumulateListenTime();
    _reportListenIfNeeded();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final old = _player;
    _player = null;
    _playing = false;
    if (old != null) {
      old.dispose().catchError((_) {});
    }
    super.dispose();
  }
}
