import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:uniclient/utils/mpv_player.dart';

import '../bridge/engine_service.dart';
import '../utils/power_save_blocker.dart';
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

/// One independent mixer track — Song or Voice — mirroring AyuGram's separate
/// `_songTracks` / `_audioTracks` (media_audio.cpp:577-583). Each owns its own
/// media_kit [Player] and full playback state, so a music track and a
/// voice/round-video message can be loaded at the same time and coexist: playing
/// a voice while music is playing no longer destroys the music (it keeps its
/// player and state and the bar restores it once the voice finishes).
class _AudioTrack {
  /// True for the music track (Type::Song), false for voice + round-video
  /// (Type::Voice). Fixed per track, mirroring the mixer's separate arrays.
  final bool isSong;
  _AudioTrack(this.isSong);

  Player? player;
  String msgId = '';
  String chatId = '';
  String performer = '';
  String title = '';
  int msgTimestamp = 0;
  String accountId = '';
  String docId = '';
  int accessHash = 0;
  List<int> fileRef = const [];
  // Whether this (voice) track is a round-video message (mediaType 5). Selects
  // the display-sleep blocker, mirroring AyuGram's
  // `data->current.audio()->isVideoMessage()` gate (media_player_instance.cpp:640-641).
  bool isRoundVideo = false;
  // Whether the loaded track is speed-changeable. Mirrors
  // AudioMsgId::changeablePlaybackSpeed (data_audio_msg_id.cpp:28-30): always
  // true for voice / round-video, but for a music file only when its
  // duration() >= kMinLengthForChangeablePlaybackSpeed (1 minute). A music file
  // shorter than that always plays at 1.0× regardless of audioPlaybackSpeed.
  bool changeableSpeed = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  // Reached the end of its media (mirrors State::StoppedAtEnd). The track stays
  // LOADED (msgId kept) so the bar persists for replay; pressing play seeks back
  // to 0 first.
  bool finished = false;
  final List<StreamSubscription> subs = [];
  // Listen tracking (music only — reportMusicListen is Song-only).
  DateTime? listenStartTime;
  int accumulatedMs = 0;
  Timer? pauseTimer;
  // Whether this track was paused BY a call (so only the track the call paused
  // auto-resumes when the call ends — AyuGram's data->resumeOnCallEnd).
  bool resumeAfterCall = false;

  bool get hasTrack => msgId.isNotEmpty;
}

class AudioService extends ChangeNotifier {
  final EngineService _engine;

  AudioService(this._engine) {
    _subscribeToCallState();
  }

  // ── Two independent mixer tracks (AyuGram _songTracks / _audioTracks). A
  // Song and a Voice/round-video can be loaded simultaneously and play at once;
  // the player bar shows whichever is the active display type (see [_shown]). ──
  final _AudioTrack _song = _AudioTrack(true);
  final _AudioTrack _voice = _AudioTrack(false);
  // Which track the player bar shows. A voice/round-video claims the bar while
  // it is the active track; once it finishes/stops the bar falls back to a
  // still-loaded song. Mirrors Widget::_type driven by checkForTypeChange +
  // tracksFinished→setType(Song) (media_player_widget.cpp:188-194,592-604).
  bool _displayVoice = false;
  // Whether the voice track is currently ducking the song. AyuGram calls
  // suppressSong() when a Voice track starts (media_audio.cpp:728-730) and
  // unsuppressSong() when it stops/finishes (:549,563), dipping the song to
  // kSuppressRatioSong while a voice plays over it.
  bool _voiceSuppressingSong = false;

  // ── OS power-save blockers (AyuGram Instance::updatePowerSaveBlocker,
  // media_player_instance.cpp:634-658, toggled from emitUpdate :1284 on every
  // state update). App-suspension is blocked while ANY track plays so a
  // sleeping laptop never silently stops playback; display-sleep is blocked
  // only while a round-video message plays so the screen stays awake for it.
  // The blockers hold an XDG Desktop Portal inhibition (Linux); no-op
  // elsewhere. ──
  final PowerSaveBlocker _appSuspendBlocker = PowerSaveBlocker(
      PowerSaveBlockType.preventAppSuspension, 'Audio playback is active');
  final PowerSaveBlocker _displaySleepBlocker = PowerSaveBlocker(
      PowerSaveBlockType.preventDisplaySleep, 'Video playback is active');

  // ── Pause-on-call (AyuGram Instance subscribes to currentCallValue +
  // currentGroupCallValue and pauses/resumes the player for the call's
  // duration — media_player_instance.cpp:188-200 & 1089-1110). ──
  StreamSubscription? _callStateSub;
  StreamSubscription? _groupCallStateSub;
  bool _oneToOneCallActive = false;
  bool _groupCallActive = false;
  bool _callActive = false;

  // Playback speed & auto-advance settings, synced from AppState (mirror
  // AyuGram voicePlaybackSpeed/audioPlaybackSpeed + playerRepeatMode +
  // OptionDisableAutoplayNext). Speeds default to 1.0 (normal speed).
  double _voicePlaybackSpeed = 1.0; // voice & video messages
  double _audioPlaybackSpeed = 1.0; // music tracks
  AudioRepeatMode _repeatMode = AudioRepeatMode.none;
  AudioOrderMode _orderMode = AudioOrderMode.defaultOrder;
  bool _autoplayNextDisabled = false;
  // Song playback volume 0..1, synced from AppState.songVolume and applied to
  // the media_kit player (0..100). Mirrors AyuGram mixer()->setSongVolume
  // (media_player_volume_controller.cpp:78-83). Default kDefaultVolume = 0.9.
  double _songVolume = 0.9;

  // Music files shorter than this play at 1.0× regardless of audioPlaybackSpeed
  // (AyuGram kMinLengthForChangeablePlaybackSpeed = 1 minute,
  // data_audio_msg_id.cpp:14).
  static const _kMinChangeableSpeedSec = 60;

  // ── Shuffle bookkeeping (mirrors AyuGram Instance::ShuffleData,
  // media_player_instance.cpp:93-109). The shuffle order is not pre-committed:
  // each forward move picks a random not-yet-played track, recording it in
  // _shufflePlayed so "previous" walks the real listen history, and (with
  // repeat-all) exhausted tracks are recycled back into the non-played pool
  // keeping the last [_kRememberShuffledOrderItems] so they don't replay
  // immediately. Validated against the playlist signature [_shuffleSig].
  // Shuffle is Song-only (nextInPlaylist gates on isSong), so a single shared
  // shuffle state suffices even with two tracks loaded. ──
  static const _kRememberShuffledOrderItems = 16; // instance.cpp:53
  final math.Random _shuffleRng = math.Random();
  String _shuffleSig = '';
  List<String> _shufflePlaylist = const [];
  List<String> _shufflePlayed = <String>[];
  List<String> _shuffleNonPlayed = <String>[];
  int _shuffleIndex = 0; // index in _shufflePlayed of the current track

  static const _pauseTimeoutSec = 60;
  static const _minListenMs = 3000;

  // AyuGram SaveLastPlaybackPosition selects the minimum length by
  // document->isVideoFile() (media_player_instance.cpp:128-130, constants
  // :55-56): only a real video FILE uses the 60s threshold; music, voice
  // messages, AND round-video messages all use the 20-minute music threshold.
  // No full video files flow through this service (videos play in the media
  // viewer), so isVideoFile() is always false here → the music threshold
  // always applies.
  static const _kMinLengthSavePosMusicSec = 20 * 60;
  static const _kPositionNotifyThrottleMs = 250;
  static const _kMaxSavedPositions = 256;
  final Map<String, Duration> _savedPositions = {};
  String _configDir = '';
  Timer? _positionSaveTimer;
  Timer? _positionNotifyTimer;
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// The track currently displayed in the player bar. A voice/round-video owns
  /// the bar while active; otherwise a still-loaded song reclaims it (mirrors
  /// Widget::_type + checkForTypeChange, media_player_widget.cpp:592-604).
  _AudioTrack get _shown {
    if (_displayVoice && _voice.hasTrack) return _voice;
    if (_song.hasTrack) return _song;
    return _voice;
  }

  /// Resolve the track holding [msgId] (Song or Voice), or null. A message is
  /// either music or voice, so the two tracks never share a msgId.
  _AudioTrack? _trackFor(String msgId) {
    if (msgId.isEmpty) return null;
    if (_song.msgId == msgId) return _song;
    if (_voice.msgId == msgId) return _voice;
    return null;
  }

  bool get _anyPlaying => _song.playing || _voice.playing;

  // ── Public getters reflect the DISPLAYED track (for the player bar). ──
  String get currentMsgId => _shown.msgId;
  bool get playing => _shown.playing;
  Duration get position => _shown.position;
  Duration get duration => _shown.duration;
  String get currentChatId => _shown.chatId;
  String get currentPerformer => _shown.performer;
  String get currentTitle => _shown.title;
  int get currentMsgTimestamp => _shown.msgTimestamp;

  /// Whether the displayed track is a music file (true) versus a voice or
  /// round-video message (false). Selects which chat-media playlist the
  /// auto-advance walks (music vs voice+round), mirroring AyuGram's separate
  /// MusicFile / RoundVoiceFile shared-media overviews.
  bool get currentIsSong => _shown.isSong;

  /// Whether the displayed track's speed is changeable — drives the player
  /// bar's speed control visibility (AyuGram hasPlaybackSpeedControl →
  /// `_speedToggle->setVisible`, media_player_widget.cpp:606-614). A music file
  /// shorter than 1 minute is not changeable, so its (no-op) speed control is
  /// hidden rather than shown as a control that does nothing.
  bool get currentChangeableSpeed => _shown.changeableSpeed;

  double get voicePlaybackSpeed => _voicePlaybackSpeed;
  double get audioPlaybackSpeed => _audioPlaybackSpeed;
  AudioRepeatMode get repeatMode => _repeatMode;
  AudioOrderMode get orderMode => _orderMode;
  bool get autoplayNextDisabled => _autoplayNextDisabled;
  double get songVolume => _songVolume;

  /// Account id the displayed track was opened from. Used by the player bar to
  /// decide whether the song is "from another session" (a different account
  /// than the one currently viewed) — AyuGram only jumps-to-message for songs
  /// from another session (media_player_widget.cpp:482-483).
  String get currentAccountId => _shown.accountId;

  double get progress => _progressOf(_shown);

  static double _progressOf(_AudioTrack t) =>
      t.duration.inMilliseconds > 0
          ? (t.position.inMilliseconds / t.duration.inMilliseconds)
              .clamp(0.0, 1.0)
          : 0.0;

  // ── Per-message queries (a bubble passes its own msgId; resolves whichever
  // track currently holds it, so a music bubble and a voice bubble both read
  // their own track even when both are loaded). ──
  bool isActiveMsg(String msgId) => _trackFor(msgId) != null;
  bool isPlayingMsg(String msgId) {
    final t = _trackFor(msgId);
    return t != null && t.playing;
  }

  Duration positionFor(String msgId) =>
      _trackFor(msgId)?.position ?? Duration.zero;
  Duration durationFor(String msgId) =>
      _trackFor(msgId)?.duration ?? Duration.zero;
  double progressFor(String msgId) {
    final t = _trackFor(msgId);
    return t == null ? 0.0 : _progressOf(t);
  }

  /// Playback speed for [t] — music (songs) use [audioPlaybackSpeed];
  /// voice/video messages use [voicePlaybackSpeed]; a non-speed-changeable
  /// track (e.g. a music file < 1 minute) always plays at 1.0×. Mirrors
  /// LookupPlaybackSpeed (media_player_instance.cpp:65-74) which returns 1.0
  /// when `!audioId.changeablePlaybackSpeed()`.
  double _speedFor(_AudioTrack t) {
    if (!t.changeableSpeed) return 1.0;
    return t.isSong ? _audioPlaybackSpeed : _voicePlaybackSpeed;
  }

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

  /// Play/pause the displayed track (player bar play button + media shortcut).
  void togglePlayback() => _toggleTrack(_shown);

  void _toggleTrack(_AudioTrack t) {
    if (t.player == null) return;
    // A manual play/pause cancels any pending call-end auto-resume — AyuGram
    // clears data->resumeOnCallEnd on every play()/playPause()
    // (media_player_instance.cpp:809 & :1085). Without this, pausing a track
    // by hand during a call still auto-resumes it when the call ends.
    t.resumeAfterCall = false;
    if (t.playing) {
      t.player!.pause();
    } else {
      // Restart a finished track from the beginning (StoppedAtEnd → play
      // re-seeks to 0), so the persisted finished bar replays cleanly.
      if (t.finished) {
        t.finished = false;
        t.position = Duration.zero;
        t.player!.seek(Duration.zero);
      }
      t.player!.play();
    }
  }

  /// Update playback speeds (called when AppState settings change). Re-applies
  /// the relevant speed to both loaded tracks immediately, mirroring
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
      _song.player?.setRate(_speedFor(_song));
      _voice.player?.setRate(_speedFor(_voice));
      notifyListeners();
    }
  }

  /// Apply the song playback volume (0..1) to both loaded tracks. Mirrors
  /// AyuGram's mixer()->setSongVolume (media_player_volume_controller.cpp:78-83).
  /// Effective per-track volume accounts for the active suppressions (a
  /// notification-sound duck on all audio, and a voice ducking the song) just
  /// like ComputeVolume = VolumeMultiplier* * getSongVolume (media_audio.cpp:251-262).
  void setSongVolume(double v) {
    final vol = v.clamp(0.0, 1.0).toDouble();
    if (_songVolume == vol) return;
    _songVolume = vol;
    _applyVolume(_song);
    _applyVolume(_voice);
    notifyListeners();
  }

  /// Effective media_kit volume (0..100) for [t]. The song dips to
  /// kSuppressRatioSong (0.05) while a voice plays over it and everything dips
  /// to kSuppressRatioAll (0.2) while a notification sound ducks; the song uses
  /// the min of the two (AyuGram accumulate_min, media_audio.cpp:1140). Voice
  /// uses the song volume too (ComputeVolume Voice = VolumeMultiplierAll *
  /// getSongVolume, media_audio.cpp:254-255).
  double _volumeFor(_AudioTrack t) {
    final all = _ducking ? _kSuppressRatioAll : 1.0;
    if (t.isSong) {
      final song = _voiceSuppressingSong ? _kSuppressRatioSong : 1.0;
      return _songVolume * 100 * math.min(song, all);
    }
    return _songVolume * 100 * all;
  }

  void _applyVolume(_AudioTrack t) {
    final p = t.player;
    if (p == null) return;
    try {
      p.setVolume(_volumeFor(t));
    } catch (e) {
      Debug.log('audio_service', '_applyVolume: $e');
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

  /// Suppression ratio applied to all in-app audio while a notification alert
  /// sound plays — dips other tracks to 20% of their CURRENT volume, NOT to
  /// silence, so the beep is foregrounded while the underlying music/voice
  /// stays faintly audible ("duck without interrupting"). Faithful mirror of
  /// AyuGram's `kSuppressRatioAll` (media_audio.cpp:35).
  static const _kSuppressRatioAll = 0.2;

  /// Suppression ratio applied to the SONG while a voice/round-video plays over
  /// it — dips the song to 5% so the voice is clearly foregrounded but the song
  /// keeps playing underneath (AyuGram `kSuppressRatioSong`, media_audio.cpp:36,
  /// driven by suppressSong()/unsuppressSong()).
  static const _kSuppressRatioSong = 0.05;

  /// Suppress in-app media playback for [length] while a notification sound
  /// plays, then restore full volume. No-op when nothing is playing (there is
  /// nothing to suppress). Overlapping calls extend the suppression window.
  Future<void> duckFor(Duration length) async {
    if (!_anyPlaying) return;
    if (!_ducking) {
      _ducking = true;
      _applyVolume(_song);
      _applyVolume(_voice);
    }
    _duckTimer?.cancel();
    _duckTimer = Timer(length, () {
      _ducking = false;
      // Restore to the user's song volume (each track's effective level),
      // equivalent to the fader lifting VolumeMultiplierAll back to 1.0
      // (media_audio.cpp:1114-1117).
      _applyVolume(_song);
      _applyVolume(_voice);
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
  /// Both tracks are paused independently so a coexisting song+voice both
  /// resume correctly.
  void _pauseForCall() {
    for (final t in [_song, _voice]) {
      if (t.player != null && t.playing) {
        t.resumeAfterCall = true;
        t.player!.pause();
      }
    }
  }

  /// AyuGram resumeOnCall (:1103-1110): resume only the tracks the call paused.
  void _resumeAfterCallEnd() {
    for (final t in [_song, _voice]) {
      if (t.resumeAfterCall) {
        t.resumeAfterCall = false;
        t.player?.play();
      }
    }
  }

  /// Toggle the OS power-save blockers from the current playback state — a port
  /// of AyuGram Instance::updatePowerSaveBlocker (media_player_instance.cpp:634-658),
  /// which it invokes on every state update from emitUpdate (:1284). App
  /// suspension is blocked while ANY track is actively playing; display sleep is
  /// additionally blocked only while the playing track is a round-video message
  /// (AyuGram's `isVideoMessage()` gate). Both calls are idempotent — the
  /// blocker only acts on a real transition.
  void _updatePowerSaveBlocker() {
    final block = _anyPlaying;
    final blockVideo = _voice.playing && _voice.isRoundVideo;
    _appSuspendBlocker.update(block);
    _displaySleepBlocker.update(blockVideo);
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
    bool isRoundVideo = false,
    int durationSeconds = 0,
  }) async {
    final t = isSong ? _song : _voice;
    if (t.msgId == msgId && t.player != null) {
      _toggleTrack(t);
      return;
    }

    // Tear down ONLY this track's player — the other type (song vs voice) keeps
    // its player and state so the two coexist (AyuGram independent mixer
    // tracks). Playing a voice over music no longer destroys the music.
    await _stopTrack(t, notify: false);

    final player = createPlayer();
    t.player = player;
    t.msgId = msgId;
    t.chatId = chatId;
    t.performer = performer;
    t.title = title;
    t.msgTimestamp = msgTimestamp;
    t.accountId = accountId;
    t.docId = docId;
    t.accessHash = accessHash;
    t.fileRef = fileRef;
    t.isRoundVideo = isRoundVideo;
    // changeablePlaybackSpeed (data_audio_msg_id.cpp:28-30): voice/round-video
    // always changeable; a music file only when its duration >= 1 minute.
    t.changeableSpeed = isSong ? (durationSeconds >= _kMinChangeableSpeedSec) : true;
    t.position = Duration.zero;
    t.duration = Duration.zero;
    t.playing = false;
    t.finished = false;
    t.accumulatedMs = 0;
    t.listenStartTime = null;

    if (!isSong) {
      // A voice/round-video claims the player bar (Widget switches to Voice)
      // and ducks any playing song under it (AyuGram suppressSong on Voice
      // start, media_audio.cpp:728-730).
      _displayVoice = true;
      _voiceSuppressingSong = true;
      _applyVolume(_song);
    } else {
      // A fresh song reclaims the bar only when no voice is currently the
      // active display (a voice in progress keeps the bar; the song plays in
      // the background and the bar restores it when the voice finishes).
      if (!(_voice.hasTrack && _voice.playing)) _displayVoice = false;
    }

    // Apply the persisted song volume (media_kit uses 0..100), accounting for
    // any active suppression. Mirrors AyuGram applying songVolume on play.
    _applyVolume(t);

    // AyuGram Instance::play marks voice / round-video messages as listened the
    // moment playback starts: `if (document->isVoiceMessage() ||
    // document->isVideoMessage()) document->owner().markMediaRead(document);`
    // (media_player_instance.cpp:829-831). This clears the unread-voice state
    // and sends the listened receipt to the sender. Music tracks (Type::Song)
    // are NOT marked, so gate on !isSong. The same-message toggle path above
    // returns early, so this only fires on a fresh play. The engine's
    // ReadMessageContents → Telegram messages.readMessageContents is a no-op
    // for already-read messages, so re-playing a read voice message is safe.
    if (!isSong && accountId.isNotEmpty && chatId.isNotEmpty && msgId.isNotEmpty) {
      _engine.readMessageContents(accountId, chatId, msgId);
    }

    _attachListeners(t, player);

    // Audio-only player: it is never paired with a VideoController, so force the
    // video track off. Otherwise libmpv decodes any embedded video stream — a
    // music file's cover-art "frame", or a round-video note — and can spawn its
    // OWN native output window (the "mpv window" users see when playing music).
    // media_kit defaults vid=no for VideoController-less players; we assert it
    // explicitly so a media_kit/libmpv update can't silently regress it. Round-
    // video *frames* render via the in-bubble VideoController; this player only
    // carries their audio.
    await player.setVideoTrack(VideoTrack.no());

    try {
      await player.open(Media(filePath));
      // Apply playback speed (music → audioPlaybackSpeed, voice/video message →
      // voicePlaybackSpeed, non-changeable → 1.0×) — mirrors
      // streamingOptions.speed = LookupPlaybackSpeed.
      if (t.player == player) {
        await player.setRate(_speedFor(t));
      }
      final savedPos = _savedPositions[t.docId];
      if (savedPos != null && savedPos > Duration.zero) {
        await player.seek(savedPos);
        _savedPositions.remove(t.docId);
        _persistSavedPositions();
      }
    } catch (e) {
      debugPrint('AudioService: failed to open $filePath: $e');
      await _stopTrack(t);
    }
  }

  void _attachListeners(_AudioTrack t, Player player) {
    t.subs.add(player.stream.playing.listen((v) {
      if (t.player != player) return;
      final wasPlaying = t.playing;
      t.playing = v;
      if (v) {
        t.finished = false;
        if (!wasPlaying) {
          t.listenStartTime = DateTime.now();
          t.pauseTimer?.cancel();
        }
      } else if (wasPlaying) {
        _accumulateListenTime(t);
        _startPauseTimer(t);
      }
      // AyuGram toggles the power-save blockers on every state update
      // (emitUpdate -> updatePowerSaveBlocker, media_player_instance.cpp:1284).
      _updatePowerSaveBlocker();
      notifyListeners();
    }));
    t.subs.add(player.stream.position.listen((v) {
      if (t.player != player) return;
      t.position = v;
      _schedulePositionNotify();
    }));
    t.subs.add(player.stream.duration.listen((v) {
      if (t.player != player) return;
      t.duration = v;
      notifyListeners();
    }));
    t.subs.add(player.stream.completed.listen((v) {
      if (t.player != player || !v) return;
      _onCompleted(t);
    }));
  }

  /// Handle a track reaching its end — a port of AyuGram's StoppedAtEnd path in
  /// emitUpdate (media_player_instance.cpp:1298-1312):
  ///   repeat-one (song only) → re-seek to 0 and replay the same track.
  ///   autoplay off           → finished=true; the track stays LOADED so the
  ///                            bar persists for replay (never stop()).
  ///   otherwise              → move to the next track; if none, finished=true
  ///                            (the track stays loaded, same as autoplay-off).
  void _onCompleted(_AudioTrack t) {
    _accumulateListenTime(t);
    _reportListenIfNeeded(t);
    t.accumulatedMs = 0;
    t.playing = false;
    t.position = Duration.zero;
    _updatePowerSaveBlocker();
    notifyListeners();

    // repeat() returns RepeatMode::None for Type::Voice
    // (media_player_instance.cpp:1198-1202), so a finished voice / round-video
    // message never repeat-ones — this branch is Song-gated.
    if (t.isSong && _repeatMode == AudioRepeatMode.one) {
      final p = t.player;
      if (p != null) {
        t.position = Duration.zero;
        p.seek(Duration.zero);
        p.play();
      }
      return;
    }
    if (_autoplayNextDisabled) {
      _finishTrack(t);
      return;
    }
    if (!_advance(t, 1)) {
      _finishTrack(t);
    }
    // else: a neighbour was started (same track type) — nothing more to do.
  }

  /// Leave [t] LOADED at its finished end (mirrors StoppedAtEnd with
  /// data->current kept), so its player bar persists for replay instead of
  /// vanishing. A finished voice hands the bar back to a still-loaded song and
  /// releases the song-ducking, mirroring Widget tracksFinished→setType(Song)
  /// + unsuppressSong (media_player_widget.cpp:182-195, media_audio.cpp:549).
  void _finishTrack(_AudioTrack t) {
    t.finished = true;
    if (!t.isSong) {
      _voiceSuppressingSong = false;
      _applyVolume(_song);
      if (_song.hasTrack) _displayVoice = false;
    }
    notifyListeners();
  }

  /// Resolve & start the neighbour in [delta] direction within [t]'s own
  /// playlist (ChatState walks the chat's music vs voice+round overview).
  /// Returns true if a neighbour exists (now playing or queued for download),
  /// false if there is none — in which case the caller leaves the track loaded
  /// & finished (mirrors `!moveInPlaylist(...)` → finished=true).
  bool _advance(_AudioTrack t, int delta) {
    final cb = onResolveNeighbour;
    if (cb == null || !t.hasTrack) return false;
    return cb(t.chatId, t.msgId, t.isSong, delta);
  }

  /// Wired by main.dart to ChatState: given the finishing/displayed track's
  /// context (chatId, msgId, isSong) and a direction, plays the playlist
  /// neighbour and returns whether one existed.
  bool Function(String chatId, String msgId, bool isSong, int delta)?
      onResolveNeighbour;

  void previous() {
    final t = _shown;
    if (t.player == null) return;
    // AyuGram's previous button calls moveInPlaylist(-1) unconditionally — there
    // is NO position guard (media_player_instance.cpp:1119-1124); the button is
    // simply disabled (previousAvailable()) when there is no previous track. The
    // seek-to-zero is only a fallback for when no neighbour resolver is wired.
    if (onResolveNeighbour != null) {
      _advance(t, -1);
    } else {
      t.player!.seek(Duration.zero);
    }
  }

  void next() {
    final t = _shown;
    if (!t.hasTrack) return;
    if (onResolveNeighbour != null) {
      _advance(t, 1);
    } else {
      stop();
    }
  }

  /// Seek the track holding [msgId] (a bubble passes its own id), or the
  /// displayed track when [msgId] is null (the player bar).
  Future<void> seek(double fraction, {String? msgId}) async {
    final t = msgId != null ? _trackFor(msgId) : _shown;
    if (t == null || t.player == null || t.duration.inMilliseconds == 0) return;
    final target = Duration(
      milliseconds: (fraction.clamp(0.0, 1.0) * t.duration.inMilliseconds).round(),
    );
    await t.player!.seek(target);
  }

  /// Player-bar close button + media-stop shortcut. Mirrors Widget::stopAndClose
  /// (media_player_widget.cpp:274-287): closing a voice while a song is still
  /// loaded just stops the voice and reveals the song; otherwise it closes the
  /// shown track entirely.
  Future<void> stop() async {
    if (_displayVoice && _voice.hasTrack && _song.hasTrack) {
      await _stopTrack(_voice, notify: false);
      _displayVoice = false;
      notifyListeners();
      return;
    }
    final shown = _shown;
    await _stopTrack(shown, notify: false);
    // Recompute the display: a remaining track reclaims the bar; if none, hide.
    if (!_song.hasTrack && _voice.hasTrack) {
      _displayVoice = true;
    } else if (!_voice.hasTrack) {
      _displayVoice = false;
    }
    notifyListeners();
  }

  /// Tear down a single track's player and clear its state, saving its position
  /// and reporting its listen time first. Releasing a voice un-ducks the song.
  Future<void> _stopTrack(_AudioTrack t, {bool notify = true}) async {
    _savePositionIfNeeded(t);
    _accumulateListenTime(t);
    _reportListenIfNeeded(t);
    t.pauseTimer?.cancel();
    t.pauseTimer = null;
    t.listenStartTime = null;
    t.accumulatedMs = 0;

    for (final s in t.subs) {
      s.cancel();
    }
    t.subs.clear();
    final old = t.player;
    t.player = null;
    t.msgId = '';
    t.chatId = '';
    t.performer = '';
    t.title = '';
    t.msgTimestamp = 0;
    t.accountId = '';
    t.docId = '';
    t.accessHash = 0;
    t.fileRef = const [];
    t.isRoundVideo = false;
    t.changeableSpeed = false;
    t.playing = false;
    t.finished = false;
    t.position = Duration.zero;
    t.duration = Duration.zero;
    // The track is gone — nothing left for a call-end to resume.
    t.resumeAfterCall = false;
    if (!t.isSong) {
      // A removed voice no longer ducks the song (AyuGram unsuppressSong on
      // Voice stop, media_audio.cpp:549,563).
      _voiceSuppressingSong = false;
      _applyVolume(_song);
    }
    // Subscriptions are cancelled above, so the playing-state listener won't
    // fire — release the power-save blockers explicitly (AyuGram releases them
    // via emitUpdate's Stopped state; here _stopTrack is that terminal state).
    _updatePowerSaveBlocker();
    if (old != null) {
      await old.dispose();
    }
    if (notify) notifyListeners();
  }

  void _accumulateListenTime(_AudioTrack t) {
    if (t.listenStartTime != null) {
      t.accumulatedMs += DateTime.now().difference(t.listenStartTime!).inMilliseconds;
      t.listenStartTime = null;
    }
  }

  void _startPauseTimer(_AudioTrack t) {
    t.pauseTimer?.cancel();
    t.pauseTimer = Timer(const Duration(seconds: _pauseTimeoutSec), () {
      _reportListenIfNeeded(t);
    });
  }

  void _savePositionIfNeeded(_AudioTrack t) {
    if (t.docId.isEmpty || t.position <= Duration.zero) return;
    final totalSec = t.duration.inSeconds;
    // Music threshold (20min) for everything this service plays — see the
    // constant comment. Voice/round-video below 20min must NOT be saved.
    const minSec = _kMinLengthSavePosMusicSec;
    if (totalSec >= minSec) {
      _savedPositions[t.docId] = t.position;
      while (_savedPositions.length > _kMaxSavedPositions) {
        _savedPositions.remove(_savedPositions.keys.first);
      }
      _persistSavedPositions();
    }
  }

  Future<void> _reportListenIfNeeded(_AudioTrack t) async {
    if (!t.isSong) {
      t.accumulatedMs = 0;
      return;
    }
    // AyuGram report() does `base::take(_listenedMs)` (always resets to 0)
    // BEFORE the `duration < kReportDurationSecondsMin` check
    // (media_player_listen_tracker.cpp:70-72). report() is the end of a listen
    // session (stop / track change / 60s pause-timeout), so the accumulator
    // must always reset here — even for a sub-threshold segment. Returning
    // without resetting would let a <3s segment carry across a 60s+ pause and
    // resume, inflating a later reportMusicListen duration that AyuGram would
    // have discarded.
    final accumulated = t.accumulatedMs;
    t.accumulatedMs = 0;
    if (accumulated < _minListenMs) return;
    if (t.accountId.isEmpty || t.docId.isEmpty) return;
    if (t.accessHash == 0 && t.fileRef.isEmpty) return;

    final docIdInt = int.tryParse(t.docId);
    if (docIdInt == null) return;

    final duration = (accumulated / 1000).round();

    final accountId = t.accountId;
    final accessHash = t.accessHash;
    final usedFileRef = List<int>.from(t.fileRef);
    final chatId = t.chatId;
    final msgId = t.msgId;

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
            t.fileRef = newRef;
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
    _duckTimer?.cancel();
    for (final t in [_song, _voice]) {
      t.pauseTimer?.cancel();
      _savePositionIfNeeded(t);
      _accumulateListenTime(t);
      _reportListenIfNeeded(t);
      for (final s in t.subs) {
        s.cancel();
      }
      t.subs.clear();
      final old = t.player;
      t.player = null;
      t.playing = false;
      if (old != null) {
        old.dispose().catchError((_) {});
      }
    }
    // Release any held power-save inhibition and close its D-Bus connection.
    _appSuspendBlocker.dispose().catchError((_) {});
    _displaySleepBlocker.dispose().catchError((_) {});
    super.dispose();
  }
}
