import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../bridge/engine_service.dart';
import 'package:uniclient/utils/debug.dart';

/// Playlist repeat mode for the media player (mirrors AyuGram RepeatMode:
/// None / One / All — media_player_button.h).
enum AudioRepeatMode { none, one, all }

/// Playlist order mode for the media player (mirrors AyuGram OrderMode:
/// Default / Reverse / Shuffle — media_player_button.h). Like AyuGram, order
/// and repeat-all apply ONLY to music tracks (Type::Song); voice/round-video
/// messages always walk the playlist in default order with no repeat-all
/// (Instance::order/repeat return Default/None for Type::Voice,
/// media_player_instance.cpp:1198-1215).
enum AudioOrderMode { defaultOrder, reverse, shuffle }

class AudioService extends ChangeNotifier {
  final EngineService _engine;

  AudioService(this._engine) {
    _subscribeToCallState();
  }

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

  // ── Pause-on-call (AyuGram Instance subscribes to currentCallValue +
  // currentGroupCallValue and pauses/resumes the player for the call's
  // duration — media_player_instance.cpp:188-200 & 1089-1110). ──
  StreamSubscription? _callStateSub;
  StreamSubscription? _groupCallStateSub;
  bool _oneToOneCallActive = false;
  bool _groupCallActive = false;
  bool _callActive = false;
  // Whether the current track was paused BY a call (so we only auto-resume the
  // track the call paused — AyuGram's data->resumeOnCallEnd).
  bool _resumeAfterCall = false;

  // Playback speed & auto-advance settings, synced from AppState (mirror
  // AyuGram voicePlaybackSpeed/audioPlaybackSpeed + playerRepeatMode +
  // OptionDisableAutoplayNext). Speeds default to 1.0 (normal speed).
  double _voicePlaybackSpeed = 1.0; // voice & video messages
  double _audioPlaybackSpeed = 1.0; // music tracks
  AudioRepeatMode _repeatMode = AudioRepeatMode.none;
  AudioOrderMode _orderMode = AudioOrderMode.defaultOrder;
  bool _autoplayNextDisabled = false;

  // ── Shuffle bookkeeping (mirrors AyuGram Instance::ShuffleData,
  // media_player_instance.cpp:93-109). The shuffle order is not pre-committed:
  // each forward move picks a random not-yet-played track, recording it in
  // _shufflePlayed so "previous" walks the real listen history, and (with
  // repeat-all) exhausted tracks are recycled back into the non-played pool
  // keeping the last [_kRememberShuffledOrderItems] so they don't replay
  // immediately. Validated against the playlist signature [_shuffleSig]. ──
  static const _kRememberShuffledOrderItems = 16; // instance.cpp:53
  final math.Random _shuffleRng = math.Random();
  String _shuffleSig = '';
  List<String> _shufflePlaylist = const [];
  List<String> _shufflePlayed = <String>[];
  List<String> _shuffleNonPlayed = <String>[];
  int _shuffleIndex = 0; // index in _shufflePlayed of the current track

  DateTime? _listenStartTime;
  int _accumulatedMs = 0;
  Timer? _pauseTimer;
  static const _pauseTimeoutSec = 60;
  static const _minListenMs = 3000;

  // AyuGram SaveLastPlaybackPosition selects the minimum length by
  // document->isVideoFile() (media_player_instance.cpp:128-130, constants
  // :55-56): only a real video FILE uses the 60s threshold; music, voice
  // messages, AND round-video messages all use the 20-minute music threshold.
  // No full video files flow through this service (videos play in the media
  // viewer), so isVideoFile() is always false here → the music threshold
  // always applies. Keyed off _isSong before, which wrongly gave voice/
  // round-video messages the 60s threshold.
  static const _kMinLengthSavePosMusicSec = 20 * 60;
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

  /// Whether the current track is a music file (true) versus a voice or
  /// round-video message (false). Selects which chat-media playlist the
  /// auto-advance walks (music vs voice+round), mirroring AyuGram's separate
  /// MusicFile / RoundVoiceFile shared-media overviews.
  bool get currentIsSong => _isSong;

  double get voicePlaybackSpeed => _voicePlaybackSpeed;
  double get audioPlaybackSpeed => _audioPlaybackSpeed;
  AudioRepeatMode get repeatMode => _repeatMode;
  AudioOrderMode get orderMode => _orderMode;
  bool get autoplayNextDisabled => _autoplayNextDisabled;

  /// Playback speed for the current track — music (songs) use
  /// [audioPlaybackSpeed]; voice/video messages use [voicePlaybackSpeed].
  /// Mirrors LookupPlaybackSpeed (media_player_instance.cpp:65-74).
  double get _currentSpeed => _isSong ? _audioPlaybackSpeed : _voicePlaybackSpeed;

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
    } catch (e) {
      Debug.log('audio_service', 'final file = File(\'\$_configDir/audio_positions.json\'): $e');
    }
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
      } catch (e) {
        Debug.log('audio_service', 'final data = <String, int>: $e');
      }
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
    // A manual play/pause cancels any pending call-end auto-resume — AyuGram
    // clears data->resumeOnCallEnd on every play()/playPause()
    // (media_player_instance.cpp:809 & :1085). Without this, pausing a track
    // by hand during a call still auto-resumes it when the call ends.
    _resumeAfterCall = false;
    if (_playing) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  /// Update playback speeds (called when AppState settings change). Re-applies
  /// the relevant speed to the currently-playing track immediately, mirroring
  /// Instance::updatePlaybackSpeed (media_player_instance.cpp:1183-1189).
  void setPlaybackSpeeds({double? voice, double? audio}) {
    var changed = false;
    if (voice != null && voice != _voicePlaybackSpeed) {
      _voicePlaybackSpeed = voice;
      changed = true;
    }
    if (audio != null && audio != _audioPlaybackSpeed) {
      _audioPlaybackSpeed = audio;
      changed = true;
    }
    if (changed) {
      _player?.setRate(_currentSpeed);
      notifyListeners();
    }
  }

  void setRepeatMode(AudioRepeatMode mode) {
    if (_repeatMode == mode) return;
    _repeatMode = mode;
    notifyListeners();
  }

  /// Set the playlist order mode. Leaving Shuffle discards the shuffle history
  /// so re-entering it starts fresh, mirroring AyuGram's orderChanges handler
  /// (`mode == Shuffle ? validateShuffleData : shuffleData = nullptr`,
  /// media_player_instance.cpp:177-185).
  void setOrderMode(AudioOrderMode mode) {
    if (_orderMode == mode) return;
    _orderMode = mode;
    if (mode != AudioOrderMode.shuffle) _resetShuffle();
    notifyListeners();
  }

  void setAutoplayNextDisabled(bool value) {
    if (_autoplayNextDisabled == value) return;
    _autoplayNextDisabled = value;
    notifyListeners();
  }

  // ── Playlist advance (order + repeat-all + shuffle) ──────────────────────
  // ChatState owns the message list, so it supplies the ordered playlist of
  // msgIds (newest-first, as `_audioPlaylist` returns) and the current track;
  // this method applies the order/repeat/shuffle rules and returns the msgId to
  // play next, or null when playback should stop (no neighbour). Mirrors
  // AyuGram Instance::moveInPlaylist (media_player_instance.cpp:531-632).

  /// Pick the next track to play. [delta] is +1 for next / -1 for previous.
  /// Returns the chosen msgId, or null if there is no neighbour (stop).
  String? nextInPlaylist({
    required List<String> playlist,
    required String currentMsgId,
    required int delta,
    required bool isSong,
  }) {
    if (playlist.isEmpty || currentMsgId.isEmpty) return null;
    final curIdx = playlist.indexOf(currentMsgId);
    if (curIdx < 0) return null; // current track not in the loaded playlist

    // Order & repeat-all are music-only (AyuGram order()/repeat() return
    // Default/None for Type::Voice).
    final order = isSong ? _orderMode : AudioOrderMode.defaultOrder;
    final repeatAll = isSong && _repeatMode == AudioRepeatMode.all;

    if (order == AudioOrderMode.shuffle) {
      return _shuffleNext(playlist, currentMsgId, delta, repeatAll);
    }
    _resetShuffle(); // not shuffling — keep no stale history

    // Default: next (+1) advances to a newer message; our playlist is
    // newest-first so newer = lower index. Reverse flips the direction
    // (AyuGram: newIndex = index + (reverse ? -delta : delta), :609-610).
    final step = (order == AudioOrderMode.reverse) ? delta : -delta;
    var targetIdx = curIdx + step;
    if (targetIdx < 0 || targetIdx >= playlist.length) {
      if (!repeatAll) return null; // no neighbour → stop (StoppedAtEnd stays)
      // Modulo wrap-around — loops the playlist back at the ends (:617-618).
      targetIdx = (targetIdx % playlist.length + playlist.length) %
          playlist.length;
    }
    return playlist[targetIdx];
  }

  void _resetShuffle() {
    _shuffleSig = '';
    _shufflePlaylist = const [];
    _shufflePlayed = <String>[];
    _shuffleNonPlayed = <String>[];
    _shuffleIndex = 0;
  }

  /// Validate the shuffle bookkeeping against the current [playlist]/[current],
  /// rebuilding it when the playlist changed or the user jumped to a track that
  /// isn't where the shuffle cursor expects it (AyuGram validateShuffleData,
  /// media_player_instance.cpp:926-976).
  void _validateShuffle(List<String> playlist, String current) {
    final sig = playlist.join(',');
    if (sig != _shuffleSig) {
      _shuffleSig = sig;
      _shufflePlaylist = List<String>.from(playlist);
      _shufflePlayed = <String>[];
      _shuffleNonPlayed = List<String>.from(playlist);
      _shuffleIndex = 0;
      return;
    }
    // Same playlist. If `current` is neither the recorded track at the cursor
    // nor a just-picked pending track, the user started something else — start
    // the shuffle history over from this track.
    final atCursor = _shuffleIndex >= 0 &&
        _shuffleIndex < _shufflePlayed.length &&
        _shufflePlayed[_shuffleIndex] == current;
    final pendingPick = _shuffleIndex == _shufflePlayed.length;
    if (!atCursor && !pendingPick) {
      _shufflePlayed = <String>[];
      _shuffleNonPlayed = List<String>.from(playlist);
      _shuffleIndex = 0;
    }
  }

  /// Shuffle branch of the playlist advance — a faithful port of the
  /// OrderMode::Shuffle path in AyuGram moveInPlaylist (instance.cpp:565-607).
  String? _shuffleNext(
      List<String> playlist, String current, int delta, bool repeatAll) {
    _validateShuffle(playlist, current);
    final played = _shufflePlayed;
    final nonPlayed = _shuffleNonPlayed;

    // Record the current track at the end of the played list if not yet there.
    if (_shuffleIndex == played.length) {
      played.add(current);
      nonPlayed.remove(current);
    }
    if (repeatAll) {
      _ensureShuffleMove(delta);
    }
    // If we've run out of fresh tracks but the current one is the last played,
    // recycle it so previous→next stays consistent (instance.cpp:586-590).
    if (nonPlayed.isEmpty &&
        played.isNotEmpty &&
        _shuffleIndex + 1 == played.length) {
      nonPlayed.add(played.removeLast());
    }
    // Keep the cursor inside [0, played.length] — defensive against the
    // recycling above shrinking `played`.
    if (_shuffleIndex > played.length) _shuffleIndex = played.length;
    if (_shuffleIndex < 0) _shuffleIndex = 0;
    final shuffleCompleted = nonPlayed.isEmpty ||
        (nonPlayed.length == 1 && nonPlayed.first == current);

    if (delta < 0) {
      if (_shuffleIndex > 0 && _shuffleIndex - 1 < played.length) {
        _shuffleIndex--;
        return played[_shuffleIndex];
      }
      return null;
    } else if (_shuffleIndex + 1 < played.length) {
      _shuffleIndex++;
      return played[_shuffleIndex];
    }
    if (shuffleCompleted) return null;
    if (_shuffleIndex < played.length) _shuffleIndex++;
    if (nonPlayed.isEmpty) return null;
    final index = _shuffleRng.nextInt(nonPlayed.length);
    return nonPlayed[index]; // recorded into `played` on the next move
  }

  /// For repeat-all shuffle, free up already-played tracks back into the
  /// non-played pool so the shuffle can continue indefinitely while still
  /// remembering the most recent [_kRememberShuffledOrderItems]. Faithful port
  /// of AyuGram ensureShuffleMove (media_player_instance.cpp:660-700).
  void _ensureShuffleMove(int delta) {
    final played = _shufflePlayed;
    final nonPlayed = _shuffleNonPlayed;
    final playlistLen = _shufflePlaylist.length;
    if (delta < 0) {
      if (_shuffleIndex > 0) return;
      if (nonPlayed.length < 2) {
        final freeUp = math.max(
            played.length ~/ 2, playlistLen - _kRememberShuffledOrderItems);
        if (freeUp > 0 && freeUp <= played.length) {
          final from = played.length - freeUp;
          nonPlayed.addAll(played.sublist(from));
          played.removeRange(from, played.length);
        }
      }
      if (nonPlayed.isEmpty) return;
      final index = _shuffleRng.nextInt(nonPlayed.length);
      played.insert(0, nonPlayed[index]);
      nonPlayed.removeAt(index);
      _shuffleIndex++;
      if (nonPlayed.isEmpty && played.length > 1) {
        nonPlayed.add(played.removeLast());
      }
      return;
    } else if (_shuffleIndex + 1 < played.length) {
      return;
    } else if (nonPlayed.length < 2) {
      final freeUp = math.max(
          played.length ~/ 2, playlistLen - _kRememberShuffledOrderItems);
      if (freeUp > 0 && freeUp <= played.length) {
        nonPlayed.addAll(played.sublist(0, freeUp));
        played.removeRange(0, freeUp);
        _shuffleIndex -= freeUp;
        if (_shuffleIndex < 0) _shuffleIndex = 0;
      }
    }
  }

  // ── Notification-sound ducking (AyuGram mixer()->suppressAll(lengthMs) +
  // scheduleFaderCallback(), notifications_manager.cpp:776-777). When a
  // notification alert sound plays, all other app audio is suppressed for the
  // sound's length so the beep doesn't overlap a playing voice/music track at
  // full volume, then volume is restored. The notification player calls this
  // via NotificationSoundPlayer.onDuck. ──
  Timer? _duckTimer;
  bool _ducking = false;

  /// Suppress in-app media playback for [length] while a notification sound
  /// plays, then restore full volume. No-op when nothing is playing (there is
  /// nothing to suppress). Overlapping calls extend the suppression window.
  Future<void> duckFor(Duration length) async {
    final p = _player;
    if (p == null || !_playing) return;
    if (!_ducking) {
      _ducking = true;
      try {
        await p.setVolume(0);
      } catch (e) {
        Debug.log('audio_service', 'await p.setVolume(0): $e');
      }
    }
    _duckTimer?.cancel();
    _duckTimer = Timer(length, () async {
      _ducking = false;
      try {
        await _player?.setVolume(100);
      } catch (e) {
        Debug.log('audio_service', 'await _player?.setVolume(100): $e');
      }
    });
  }

  /// Subscribe to 1:1 and group call state so playback auto-pauses for the
  /// duration of a call and resumes when it ends — mirrors AyuGram combining
  /// currentCallValue() || currentGroupCallValue() (media_player_instance.cpp:188-200).
  void _subscribeToCallState() {
    _callStateSub = _engine.onCallState.listen((e) {
      _setCallActivity(oneToOne: _isCallStateOngoing(e.call.state));
    });
    _groupCallStateSub = _engine.onGroupCallState.listen((e) {
      // The engine emits group-call state for the local user's own call
      // session; info.active is false once the call ends (events.go:463).
      _setCallActivity(group: e.info.active);
    });
  }

  /// True while a 1:1 call occupies the audio device. Terminal states
  /// (ended/failed/busy) and the empty "no call" state release it.
  static bool _isCallStateOngoing(String rawState) {
    final s = rawState.toLowerCase();
    if (s.isEmpty) return false;
    return s != 'ended' && s != 'failed' && s != 'busy';
  }

  void _setCallActivity({bool? oneToOne, bool? group}) {
    if (oneToOne != null) _oneToOneCallActive = oneToOne;
    if (group != null) _groupCallActive = group;
    final anyCall = _oneToOneCallActive || _groupCallActive;
    if (anyCall == _callActive) return;
    _callActive = anyCall;
    if (anyCall) {
      _pauseForCall();
    } else {
      _resumeAfterCallEnd();
    }
  }

  /// AyuGram pauseOnCall (media_player_instance.cpp:1089-1101): only pause a
  /// track that is actually playing, and remember to resume it on call end.
  void _pauseForCall() {
    if (_player == null || !_playing) return;
    _resumeAfterCall = true;
    _player!.pause();
  }

  /// AyuGram resumeOnCall (:1103-1110): resume only the track the call paused.
  void _resumeAfterCallEnd() {
    if (!_resumeAfterCall) return;
    _resumeAfterCall = false;
    _player?.play();
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

    // AyuGram Instance::play marks voice / round-video messages as listened the
    // moment playback starts: `if (document->isVoiceMessage() ||
    // document->isVideoMessage()) document->owner().markMediaRead(document);`
    // (media_player_instance.cpp:829-831). This clears the unread-voice state
    // and sends the listened receipt to the sender. Music tracks (Type::Song)
    // are NOT marked, so gate on !isSong. The same-message toggle path above
    // returns early, so this only fires on a fresh play — matching C++
    // playPause(audioId) routing to playPause(type) (no re-mark) for the
    // current track vs play(audioId) for a new one. The engine's
    // ReadMessageContents → Telegram messages.readMessageContents is a no-op
    // for already-read messages, so re-playing a read voice message is safe.
    if (!isSong && accountId.isNotEmpty && chatId.isNotEmpty && msgId.isNotEmpty) {
      _engine.readMessageContents(accountId, chatId, msgId);
    }

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
      // Auto-advance on completion — mirrors AyuGram StoppedAtEnd handling
      // (media_player_instance.cpp:1300-1310):
      //   repeat-one (song only) → re-seek to 0 and replay the same track.
      //     repeat() returns RepeatMode::None for Type::Voice
      //     (media_player_instance.cpp:1198-1202), so a finished voice /
      //     round-video message NEVER repeat-ones — it advances like the
      //     repeat-ALL path, which is already _isSong-gated (:276).
      //   autoplay off  → stop (playback stays finished)
      //   otherwise     → move to the next track (next() stops if none queued)
      if (_isSong && _repeatMode == AudioRepeatMode.one) {
        final p = _player;
        if (p != null) {
          _position = Duration.zero;
          p.seek(Duration.zero);
          p.play();
        }
      } else if (_autoplayNextDisabled) {
        stop();
      } else {
        next();
      }
    }));

    try {
      await player.open(Media(filePath));
      // Apply playback speed (music → audioPlaybackSpeed, voice/video message →
      // voicePlaybackSpeed) — mirrors streamingOptions.speed = LookupPlaybackSpeed.
      if (_player == player) {
        await player.setRate(_currentSpeed);
      }
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
    // AyuGram's previous button calls moveInPlaylist(-1) unconditionally —
    // there is NO position guard (media_player_instance.cpp:1119-1124); the
    // button is simply disabled (previousAvailable()) when there is no previous
    // track. So previous() always moves to the previous track. The seek-to-zero
    // is only a fallback for when no previous-track callback is wired.
    if (onPreviousTrack != null) {
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
    // The track is gone — nothing left for a call-end to resume.
    _resumeAfterCall = false;
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
    // Music threshold (20min) for everything this service plays — see the
    // constant comment. Voice/round-video below 20min must NOT be saved.
    const minSec = _kMinLengthSavePosMusicSec;
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
        } catch (e) {
          Debug.log('audio_service', 'final newRef = await _engine.refreshDocumentFileRef(: $e');
        }
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
    _callStateSub?.cancel();
    _groupCallStateSub?.cancel();
    _positionNotifyTimer?.cancel();
    _positionSaveTimer?.cancel();
    _pauseTimer?.cancel();
    _duckTimer?.cancel();
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
