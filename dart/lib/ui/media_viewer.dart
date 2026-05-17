import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import 'emoji_panel.dart';
import 'info_panel.dart';
import 'photo_crop_editor.dart';
import 'shell.dart';
import 'telegram_toast.dart';
import 'telegram_tooltip.dart';

enum _MediaViewerMode { windowed, maximized, fullscreen }

const _kMinWidth = 480.0;
const _kMinHeight = 360.0;
const _kDefaultWidth = 800.0;
const _kDefaultHeight = 600.0;
const _kDefaultX = 160.0;
const _kDefaultY = 120.0;
const _kTitleBarHeight = 32.0;
const _kTitleButtonWidth = 44.0;
const _kTitleButtonHeight = 32.0;
const _kMediaviewBg = Color(0xFF0E0E0E);
const _kGradientTopHeight = 80.0;
const _kGradientBottomHeight = 120.0;
const _kDocBubbleWidth = 340.0;
const _kDocBubbleHeight = 116.0;
const _kDocIconSize = 80.0;
const _kMediaviewFileBg = Color(0xFF1B2836);
const _kMaxDisplayImageSize = 4096.0;
const _kMinZoomLevel = -7;
const _kMaxZoomLevel = 7;
const _kZoomAnimDuration = Duration(milliseconds: 200);
const _kSwipeThreshold = 80.0;
const _kPreloadAhead = 3;
const _kMediaviewControlFg = Color(0xFFFFFFFF);
const _kMediaviewCaptionBg = Color(0xC8000000);
const _kMediaviewCaptionFg = Color(0xFFFFFFFF);
const _kMediaviewCaptionLinkFg = Color(0xFF71BAF7);
const _kMediaviewCaptionRadius = 6.0;
const _kMediaviewCaptionPadding = EdgeInsets.fromLTRB(11, 6, 11, 6);
const _kMediaviewCaptionMargin = 11.0;
const _kMediaviewCaptionMaxWidth = 600.0;

const _kMediaviewSaveMsgBg = Color(0xB2000000);
const _kMediaviewSaveMsgFg = Color(0xFFFFFFFF);
const _kSaveToastPadding = EdgeInsets.fromLTRB(55, 19, 29, 20);
const _kSaveToastFadeIn = Duration(milliseconds: 200);
const _kSaveToastHold = Duration(seconds: 2);
const _kSaveToastFadeOut = Duration(milliseconds: 2500);

const _kThumbStripHeight = 80.0;
const _kThumbWidth = 56.0;
const _kThumbWidthMax = 160.0;
const _kThumbStripPaddingH = 14.0;
const _kThumbGap = 3.0;
const _kThumbGapCurrent = 12.0;
const _kThumbAnimDuration = Duration(milliseconds: 150);

const _kPipDefaultSize = 320.0;
const _kPipMinimalSize = 120.0;
const _kPipBorderSkip = 20.0;
const _kPipBorderSnapArea = 16.0;
const _kPipResizeArea = 10.0;
const _kPipTrackHeight = 2.0;
const _kPipTrackHeightHover = 4.0;
const _kPipControlsHeight = 36.0;
const _kPipSnapDuration = Duration(milliseconds: 150);
const _kMediaTransitionDuration = Duration(milliseconds: 200);
const _kRadialBg = Color(0x54000000);
const _kRadialFg = Color(0xFFFFFFFF);

const _kChapterToastShowing = Duration(milliseconds: 200);
const _kChapterToastShown = Duration(milliseconds: 1500);

class _VideoChapter {
  final double position;
  final String label;
  const _VideoChapter(this.position, this.label);
}

final _kTimestampPattern = RegExp(r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})');

List<_VideoChapter> _parseChapters(String text, int durationMs) {
  if (text.isEmpty || durationMs <= 0) return const [];
  final lines = text.split('\n');
  final chapters = <_VideoChapter>[];
  for (final line in lines) {
    final m = _kTimestampPattern.firstMatch(line);
    if (m == null) continue;
    final h = int.tryParse(m.group(1) ?? '0') ?? 0;
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    final sec = int.tryParse(m.group(3) ?? '0') ?? 0;
    final ms = ((h * 3600) + (min * 60) + sec) * 1000;
    if (ms > durationMs) continue;
    final label = line.substring(m.end).trim().replaceFirst(RegExp(r'^[-–—:.\s]+'), '');
    if (label.isEmpty) continue;
    chapters.add(_VideoChapter(ms / durationMs, label));
  }
  if (chapters.length < 2) return const [];
  chapters.sort((a, b) => a.position.compareTo(b.position));
  return chapters;
}

class PipData {
  final Player player;
  final VideoController videoController;
  final List<StreamSubscription> playerSubs;
  final CachedMessage message;
  final List<CachedMessage> mediaMessages;
  final double volume;
  final double playbackSpeed;
  final Duration position;
  final Duration duration;
  final bool isPlaying;

  PipData({
    required this.player,
    required this.videoController,
    required this.playerSubs,
    required this.message,
    required this.mediaMessages,
    required this.volume,
    required this.playbackSpeed,
    required this.position,
    required this.duration,
    required this.isPlaying,
  });
}

class PipManager extends ChangeNotifier {
  static final PipManager instance = PipManager._();
  PipManager._();

  PipData? _data;
  _PipWidgetState? _activeState;

  bool get isActive => _data != null;
  PipData? get data => _data;

  void activate({
    required Player player,
    required VideoController videoController,
    required List<StreamSubscription> playerSubs,
    required CachedMessage message,
    required List<CachedMessage> mediaMessages,
    required double volume,
    required double playbackSpeed,
    required Duration position,
    required Duration duration,
    required bool isPlaying,
  }) {
    dismiss();
    _data = PipData(
      player: player,
      videoController: videoController,
      playerSubs: playerSubs,
      message: message,
      mediaMessages: mediaMessages,
      volume: volume,
      playbackSpeed: playbackSpeed,
      position: position,
      duration: duration,
      isPlaying: isPlaying,
    );
    notifyListeners();
  }

  void dismiss() {
    _activeState?._disposePlayer();
    _activeState = null;
    _data = null;
    notifyListeners();
  }

  void _enlarge(BuildContext context) {
    final state = _activeState;
    if (state == null) return;
    final msg = state.widget.message;
    final msgs = state.widget.mediaMessages;
    final pos = state._position;

    state._disposePlayer();
    _activeState = null;
    _data = null;
    notifyListeners();

    MediaViewer.open(context, message: msg, allMessages: msgs, resumePosition: pos);
  }
}

class MediaViewer extends StatefulWidget {
  final CachedMessage initialMessage;
  final List<CachedMessage> mediaMessages;
  final Duration? resumePosition;
  final Rect? sourceRect;

  static _MediaViewerState? _activeInstance;
  static bool get isOpen => _activeInstance != null;

  static void toggleMode() => _activeInstance?._cycleMode();
  static void rotate() => _activeInstance?._rotate();
  static void flipH() => _activeInstance?._flipHorizontal();
  static void flipV() => _activeInstance?._flipVertical();
  static void save() => _activeInstance?._saveMediaToDownloads(_activeInstance!._currentMessage);
  static void copyMedia() => _activeInstance?._copyImageToClipboard(_activeInstance!._currentMessage);
  static void enterPip() => _activeInstance?._enterPip();
  static void close() => _activeInstance?._close();
  static void testSpeedBoostOn() {
    final inst = _activeInstance;
    if (inst == null) return;
    inst._spaceBoostTimer?.cancel();
    inst.setState(() => inst._spaceBoostActive = true);
  }
  static void testSpeedBoostOff() {
    final inst = _activeInstance;
    if (inst == null) return;
    inst._spaceBoostTimer?.cancel();
    inst.setState(() => inst._spaceBoostActive = false);
  }

  const MediaViewer({
    super.key,
    required this.initialMessage,
    required this.mediaMessages,
    this.resumePosition,
    this.sourceRect,
  });

  static void open(
    BuildContext context, {
    required CachedMessage message,
    required List<CachedMessage> allMessages,
    Duration? resumePosition,
    Rect? sourceRect,
  }) {
    PipManager.instance.dismiss();
    final mediaMessages = allMessages
        .where((m) =>
            (m.mediaLocalPath.isNotEmpty || m.mediaType == 8 || m.mediaType == 3) &&
            (m.mediaType >= 1 && m.mediaType <= 8))
        .toList();
    if (mediaMessages.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _MediaViewerTransition(
            animation: animation,
            sourceRect: sourceRect,
            child: MediaViewer(
              initialMessage: message,
              mediaMessages: mediaMessages,
              resumePosition: resumePosition,
              sourceRect: sourceRect,
            ),
          );
        },
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerTransition extends StatelessWidget {
  final Animation<double> animation;
  final Rect? sourceRect;
  final Widget child;

  const _MediaViewerTransition({
    required this.animation,
    required this.child,
    this.sourceRect,
  });

  @override
  Widget build(BuildContext context) {
    if (sourceRect == null) {
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.linear)),
        child: child,
      );
    }

    final screen = MediaQuery.sizeOf(context);
    final destRect = Rect.fromLTWH(0, 0, screen.width, screen.height);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final rect = Rect.lerp(sourceRect!, destRect, t)!;
        final opacity = t.clamp(0.0, 1.0);

        return Stack(
          children: [
            Opacity(
              opacity: opacity,
              child: Container(color: _kMediaviewBg),
            ),
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: ClipRect(
                child: Opacity(
                  opacity: opacity,
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MediaViewerState extends State<MediaViewer>
    with TickerProviderStateMixin {
  late int _currentIndex;
  late final FocusNode _focusNode;

  int _zoomLevel = 0;
  double _currentScale = 1.0;
  Offset _panOffset = Offset.zero;

  late final AnimationController _zoomAnimCtrl;
  double _zoomFrom = 1.0;
  double _zoomTo = 1.0;

  int _rotationQuarters = 0;
  late final AnimationController _rotationAnimCtrl;
  double _displayRotation = 0.0;
  double _rotationFrom = 0.0;
  double _rotationTo = 0.0;
  bool _flipH = false;
  bool _flipV = false;

  bool _isPinching = false;
  double _pinchBaseScale = 1.0;
  Offset _panGestureStart = Offset.zero;
  double _swipeHorizontalDelta = 0.0;
  bool _swipeNavigated = false;

  late final AnimationController _controlsAnim;
  Timer? _autoHideTimer;

  Player? _player;
  VideoController? _videoController;
  List<StreamSubscription> _playerSubs = [];
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 0.9;
  double _lastVolume = 0.9;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;
  bool _autoPausedForCall = false;
  Timer? _spaceBoostTimer;
  bool _spaceBoostActive = false;
  double _preBoostSpeed = 1.0;
  DateTime? _lastFrameStep;
  ChatState? _chatStateRef;
  int? _activeQualitySeq;
  bool _qualityDownloading = false;
  bool _isBuffering = false;
  late final AnimationController _bufferSpinCtrl;

  late final AnimationController _saveToastAnim;
  Timer? _saveToastHoldTimer;
  String _saveToastPath = '';

  List<_VideoChapter> _chapters = const [];
  int _lastChapterIndex = -1;
  late final AnimationController _chapterToastAnim;
  Timer? _chapterToastTimer;
  String _chapterToastText = '';
  int _chapterToastDirection = 0;
  late final TapGestureRecognizer _downloadsLinkRecognizer;

  _MediaViewerMode _mode = _MediaViewerMode.fullscreen;
  double _windowedWidth = _kDefaultWidth;
  double _windowedHeight = _kDefaultHeight;
  double _windowedX = _kDefaultX;
  double _windowedY = _kDefaultY;
  bool _isDraggingWindow = false;
  Offset _dragStart = Offset.zero;
  bool _isResizingWindow = false;
  Offset _resizeStart = Offset.zero;
  double _resizeStartW = 0;
  double _resizeStartH = 0;

  @override
  void initState() {
    super.initState();
    MediaViewer._activeInstance = this;
    _focusNode = FocusNode();
    _currentIndex = widget.mediaMessages.indexWhere(
      (m) => m.msgId == widget.initialMessage.msgId,
    );
    if (_currentIndex < 0) _currentIndex = 0;
    _controlsAnim = AnimationController(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 600),
      value: 1.0,
      vsync: this,
    )..addStatusListener((_) {
        if (mounted) setState(() {});
      });
    _zoomAnimCtrl = AnimationController(
      duration: _kZoomAnimDuration,
      vsync: this,
    )..addListener(() {
        if (mounted) {
          setState(() {
            _currentScale = _zoomFrom + (_zoomTo - _zoomFrom) * Curves.easeOutCubic.transform(_zoomAnimCtrl.value);
          });
        }
      });
    _rotationAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..addListener(() {
        if (mounted) {
          setState(() {
            _displayRotation = _rotationFrom +
                (_rotationTo - _rotationFrom) *
                    Curves.easeOutCubic.transform(_rotationAnimCtrl.value);
          });
        }
      });
    _bufferSpinCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _saveToastAnim = AnimationController(
      duration: _kSaveToastFadeIn,
      reverseDuration: _kSaveToastFadeOut,
      vsync: this,
    );
    _chapterToastAnim = AnimationController(
      duration: _kChapterToastShowing,
      reverseDuration: _kChapterToastShowing,
      vsync: this,
    );
    _downloadsLinkRecognizer = TapGestureRecognizer()
      ..onTap = () => Process.run('xdg-open', [_saveToastPath]);
    _loadViewerPrefs();
    _initVideoIfNeeded();
    _scheduleAutoHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _preloadNearby();
        try {
          _chatStateRef = context.read<ChatState>();
          _chatStateRef!.addListener(_onCallStateChanged);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    if (MediaViewer._activeInstance == this) {
      MediaViewer._activeInstance = null;
    }
    _chatStateRef?.removeListener(_onCallStateChanged);
    _chatStateRef = null;
    _disposePlayer();
    _spaceBoostTimer?.cancel();
    _autoHideTimer?.cancel();
    _saveToastHoldTimer?.cancel();
    _chapterToastTimer?.cancel();
    _downloadsLinkRecognizer.dispose();
    _saveToastAnim.dispose();
    _chapterToastAnim.dispose();
    _bufferSpinCtrl.dispose();
    _rotationAnimCtrl.dispose();
    _zoomAnimCtrl.dispose();
    _controlsAnim.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    final callActive = _chatStateRef?.activeGroupCall != null;
    if (callActive && _isPlaying && !_autoPausedForCall) {
      _autoPausedForCall = true;
      _player?.pause();
    } else if (!callActive && _autoPausedForCall) {
      _autoPausedForCall = false;
      _player?.play();
    }
  }

  CachedMessage get _currentMessage => widget.mediaMessages[_currentIndex];
  bool get _isVideo => _currentMessage.mediaType == 2 || _currentMessage.mediaType == 5;
  bool get _isGif => _currentMessage.mediaType == 7;
  bool get _isDocument => _currentMessage.mediaType == 8 || _currentMessage.mediaType == 3;
  bool get _hasStrip => widget.mediaMessages.length > 1;
  double get _stripOffset => _hasStrip ? _kThumbStripHeight + 4 : 0;

  bool get _isVideoNote => _currentMessage.mediaType == 5;
  bool get _isPhoto => !_isVideo && !_isGif && !_isDocument;

  void _preloadNearby() {
    for (int offset = 1; offset <= _kPreloadAhead; offset++) {
      final prevIdx = _currentIndex + offset;
      final nextIdx = _currentIndex - offset;
      for (final idx in [prevIdx, nextIdx]) {
        if (idx < 0 || idx >= widget.mediaMessages.length) continue;
        final msg = widget.mediaMessages[idx];
        if (msg.mediaLocalPath.isEmpty) continue;
        if (msg.mediaType == 2 || msg.mediaType == 5 || msg.mediaType == 7) continue;
        final file = File(msg.mediaLocalPath);
        if (!file.existsSync()) continue;
        precacheImage(FileImage(file), context);
      }
    }
  }

  void _initVideoIfNeeded() {
    final msg = _currentMessage;
    if ((msg.mediaType == 2 || msg.mediaType == 5 || msg.mediaType == 7) &&
        msg.mediaLocalPath.isNotEmpty) {
      _disposePlayer();
      final player = Player();
      _player = player;
      _videoController = VideoController(player);

      _playerSubs = [
        player.stream.playing.listen((playing) {
          if (mounted) setState(() => _isPlaying = playing);
        }),
        player.stream.position.listen((pos) {
          if (mounted && !_isSeeking) {
            setState(() => _position = pos);
            _detectChapterChange(pos);
          }
        }),
        player.stream.duration.listen((dur) {
          if (mounted) {
            setState(() => _duration = dur);
            if (dur.inMilliseconds > 0 && _chapters.isEmpty) {
              _chapters = _parseChapters(msg.contentText, dur.inMilliseconds);
            }
          }
        }),
        player.stream.completed.listen((completed) {
          if (completed && msg.mediaType == 7) {
            player.seek(Duration.zero);
            player.play();
          }
        }),
        player.stream.buffering.listen((buffering) {
          if (mounted) {
            setState(() => _isBuffering = buffering);
            if (buffering) {
              _bufferSpinCtrl.repeat();
            } else {
              _bufferSpinCtrl.stop();
            }
          }
        }),
      ];

      final isMuted = msg.mediaType == 7;
      player.setVolume(isMuted ? 0.0 : _volume * 100.0);
      player.setPlaylistMode(
          (msg.mediaType == 7 || msg.mediaType == 5) ? PlaylistMode.single : PlaylistMode.none);
      player.open(Media(msg.mediaLocalPath));
      if (widget.resumePosition != null && widget.resumePosition! > Duration.zero) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _player != null) {
            _player!.seek(widget.resumePosition!);
          }
        });
      }
    }
  }

  String get _prefsPath {
    try {
      final appState = context.read<AppState>();
      final dir = appState.configDir;
      return dir.isEmpty ? '' : '$dir/media_viewer_prefs.json';
    } catch (_) {
      return '';
    }
  }

  void _loadViewerPrefs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final path = _prefsPath;
      if (path.isEmpty) return;
      try {
        final file = File(path);
        if (!file.existsSync()) return;
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        setState(() {
          final modeIdx = data['mode'] as int? ?? 2;
          _mode = _MediaViewerMode.values[modeIdx.clamp(0, 2)];
          _windowedWidth = (data['width'] as num?)?.toDouble() ?? _kDefaultWidth;
          _windowedHeight = (data['height'] as num?)?.toDouble() ?? _kDefaultHeight;
          _windowedX = (data['x'] as num?)?.toDouble() ?? _kDefaultX;
          _windowedY = (data['y'] as num?)?.toDouble() ?? _kDefaultY;
        });
      } catch (_) {}
    });
  }

  void _saveViewerPrefs() {
    final path = _prefsPath;
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(jsonEncode({
        'mode': _mode.index,
        'width': _windowedWidth,
        'height': _windowedHeight,
        'x': _windowedX,
        'y': _windowedY,
      }));
    } catch (_) {}
  }

  void _setMode(_MediaViewerMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _saveViewerPrefs();
  }

  void _cycleMode() {
    switch (_mode) {
      case _MediaViewerMode.fullscreen:
        _setMode(_MediaViewerMode.windowed);
      case _MediaViewerMode.maximized:
        _setMode(_MediaViewerMode.fullscreen);
      case _MediaViewerMode.windowed:
        _setMode(_MediaViewerMode.maximized);
    }
  }

  void _disposePlayer() {
    for (final sub in _playerSubs) {
      sub.cancel();
    }
    _playerSubs = [];
    _player?.dispose();
    _player = null;
    _videoController = null;
    _isPlaying = false;
    _isBuffering = false;
    _bufferSpinCtrl.stop();
    _position = Duration.zero;
    _duration = Duration.zero;
    _chapters = const [];
    _lastChapterIndex = -1;
  }

  bool get _hasPrev => _currentIndex < widget.mediaMessages.length - 1;
  bool get _hasNext => _currentIndex > 0;

  void _goToPrev() {
    if (!_hasPrev) return;
    _disposePlayer();
    setState(() {
      _currentIndex++;
      _resetZoom();
      _activeQualitySeq = null;
      _qualityDownloading = false;
    });
    _initVideoIfNeeded();
    _preloadNearby();
  }

  void _goToNext() {
    if (!_hasNext) return;
    _disposePlayer();
    setState(() {
      _currentIndex--;
      _resetZoom();
      _activeQualitySeq = null;
      _qualityDownloading = false;
    });
    _initVideoIfNeeded();
    _preloadNearby();
  }

  void _goToIndex(int index) {
    if (index == _currentIndex) return;
    if (index < 0 || index >= widget.mediaMessages.length) return;
    _disposePlayer();
    setState(() {
      _currentIndex = index;
      _resetZoom();
      _activeQualitySeq = null;
      _qualityDownloading = false;
    });
    _initVideoIfNeeded();
    _preloadNearby();
  }

  Widget _buildGalleryStrip() {
    if (widget.mediaMessages.length <= 1) return const SizedBox.shrink();
    return _GalleryThumbsStrip(
      messages: widget.mediaMessages,
      currentIndex: _currentIndex,
      onTap: _goToIndex,
    );
  }

  static double _scaleForLevel(int level) {
    if (level >= 0) return (level + 1).toDouble();
    return 1.0 / (-level + 1);
  }

  static int _nearestLevel(double scale) {
    if (scale <= _scaleForLevel(_kMinZoomLevel)) return _kMinZoomLevel;
    if (scale >= _scaleForLevel(_kMaxZoomLevel)) return _kMaxZoomLevel;
    int best = 0;
    double bestDiff = (scale - 1.0).abs();
    for (int l = _kMinZoomLevel; l <= _kMaxZoomLevel; l++) {
      final diff = (scale - _scaleForLevel(l)).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = l;
      }
    }
    return best;
  }

  bool get _isZoomedIn => _currentScale > 1.001;

  void _animateZoomTo(int level, {Offset? focalPoint, Size? viewport}) {
    final newScale = _scaleForLevel(level);
    if (focalPoint != null && viewport != null && _currentScale > 0.001) {
      final ratio = newScale / _currentScale;
      final center = Offset(viewport.width / 2, viewport.height / 2);
      final fp = focalPoint - center;
      _panOffset = _panOffset * ratio - fp * (ratio - 1);
    }
    if (level == 0) _panOffset = Offset.zero;
    _zoomLevel = level;
    _zoomFrom = _currentScale;
    _zoomTo = newScale;
    _zoomAnimCtrl.forward(from: 0.0);
  }

  void _zoomIn({Offset? focalPoint, Size? viewport}) {
    if (_zoomLevel >= _kMaxZoomLevel) return;
    _animateZoomTo(_zoomLevel + 1, focalPoint: focalPoint, viewport: viewport);
  }

  void _zoomOut({Offset? focalPoint, Size? viewport}) {
    if (_zoomLevel <= _kMinZoomLevel) return;
    _animateZoomTo(_zoomLevel - 1, focalPoint: focalPoint, viewport: viewport);
  }

  void _resetZoom() {
    _zoomLevel = 0;
    _currentScale = 1.0;
    _panOffset = Offset.zero;
    _zoomAnimCtrl.reset();
    _rotationQuarters = 0;
    _displayRotation = 0.0;
    _rotationAnimCtrl.reset();
    _flipH = false;
    _flipV = false;
  }

  void _rotate() {
    _rotationQuarters--;
    _rotationFrom = _displayRotation;
    _rotationTo = _rotationQuarters.toDouble();
    _rotationAnimCtrl.forward(from: 0.0);
  }

  void _flipHorizontal() {
    if (!_isPhoto) return;
    setState(() => _flipH = !_flipH);
  }

  void _flipVertical() {
    if (!_isPhoto) return;
    setState(() => _flipV = !_flipV);
  }

  Offset _clampPan(Offset pan, Size viewport) {
    if (_currentScale <= 1.0) return Offset.zero;
    final maxX = (viewport.width * (_currentScale - 1)) / 2;
    final maxY = (viewport.height * (_currentScale - 1)) / 2;
    return Offset(pan.dx.clamp(-maxX, maxX), pan.dy.clamp(-maxY, maxY));
  }

  void _handlePointerSignal(PointerSignalEvent event, Size viewport) {
    if (event is PointerScrollEvent) {
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      if (ctrl) {
        if (event.scrollDelta.dy < 0) {
          _zoomIn(focalPoint: event.localPosition, viewport: viewport);
        } else if (event.scrollDelta.dy > 0) {
          _zoomOut(focalPoint: event.localPosition, viewport: viewport);
        }
      } else {
        if (event.scrollDelta.dy > 0) {
          _goToNext();
        } else if (event.scrollDelta.dy < 0) {
          _goToPrev();
        }
      }
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons & 4 != 0) {
      setState(() => _resetZoom());
    }
  }

  void _togglePlayPause() {
    final player = _player;
    if (player == null) return;
    _autoPausedForCall = false;
    player.playOrPause();
  }

  double get _controlsOpacity => _controlsAnim.value;
  bool get _controlsVisible => !_controlsAnim.isDismissed;

  void _showControls() {
    _cancelAutoHide();
    _controlsAnim.forward();
    _scheduleAutoHide();
  }

  void _hideControls() {
    _cancelAutoHide();
    _controlsAnim.reverse();
  }

  void _toggleControls() {
    if (_controlsAnim.isCompleted ||
        _controlsAnim.status == AnimationStatus.forward) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _scheduleAutoHide() {
    _cancelAutoHide();
    _autoHideTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) _controlsAnim.reverse();
    });
  }

  void _cancelAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  void _onPointerActivity() {
    if (!_controlsAnim.isCompleted) _controlsAnim.forward();
    _scheduleAutoHide();
  }

  void _close() {
    _disposePlayer();
    Navigator.of(context).pop();
  }

  void _enterPip() {
    if (_player == null || _videoController == null) return;
    if (!_isVideo && !_isGif) return;

    final player = _player!;
    final vc = _videoController!;
    final subs = List<StreamSubscription>.from(_playerSubs);

    _player = null;
    _videoController = null;
    _playerSubs = [];

    PipManager.instance.activate(
      player: player,
      videoController: vc,
      playerSubs: subs,
      message: _currentMessage,
      mediaMessages: widget.mediaMessages,
      volume: _volume,
      playbackSpeed: _playbackSpeed,
      position: _position,
      duration: _duration,
      isPlaying: _isPlaying,
    );

    Navigator.of(context).pop();
  }

  void _navigateChapter(int direction) {
    if (_chapters.isEmpty || _duration.inMilliseconds <= 0) return;
    final progress = _position.inMilliseconds / _duration.inMilliseconds;
    _VideoChapter? target;
    if (direction > 0) {
      for (final ch in _chapters) {
        if (ch.position > progress + 0.001) { target = ch; break; }
      }
    } else {
      for (int i = _chapters.length - 1; i >= 0; i--) {
        if (_chapters[i].position < progress - 0.01) { target = _chapters[i]; break; }
      }
      if (target == null) {
        _player?.seek(Duration.zero);
        _showControls();
        return;
      }
    }
    if (target == null) return;
    final ms = (target.position * _duration.inMilliseconds).round();
    _player?.seek(Duration(milliseconds: ms));
    _showControls();
    _showChapterToast(target.label, direction);
  }

  void _showChapterToast(String name, int direction) {
    if (name.isEmpty) return;
    _chapterToastTimer?.cancel();
    setState(() {
      _chapterToastText = name;
      _chapterToastDirection = direction;
    });
    _chapterToastAnim.forward(from: _chapterToastAnim.value);
    _chapterToastTimer = Timer(_kChapterToastShown, () {
      if (mounted) _chapterToastAnim.reverse();
    });
  }

  void _detectChapterChange(Duration pos) {
    if (_chapters.isEmpty || _duration.inMilliseconds <= 0) return;
    final progress = pos.inMilliseconds / _duration.inMilliseconds;
    var index = -1;
    for (var i = _chapters.length - 1; i >= 0; i--) {
      if (_chapters[i].position <= progress) {
        index = i;
        break;
      }
    }
    if (index == _lastChapterIndex) return;
    final previous = _lastChapterIndex;
    _lastChapterIndex = index;
    if (index >= 0) {
      _showChapterToast(
        _chapters[index].label,
        (index > previous) ? 1 : -1,
      );
    }
  }

  void _seekToPercent(int percent) {
    if (!_isVideo || _player == null || _duration == Duration.zero) return;
    final target = _duration * (percent / 100.0);
    _player!.seek(target);
    _showControls();
  }

  void _frameStep(int direction) {
    if (!_isVideo || _player == null || _isPlaying) return;
    final now = DateTime.now();
    if (_lastFrameStep != null &&
        now.difference(_lastFrameStep!).inMilliseconds < 150) return;
    _lastFrameStep = now;
    const frameDuration = Duration(microseconds: 33333); // 30fps fallback
    final target = _position + frameDuration * direction;
    if (target < Duration.zero) return;
    if (_duration > Duration.zero && target > _duration) return;
    _player!.seek(target);
    _showControls();
  }

  void _startSpeedBoost() {
    if (!_isVideo || _player == null) return;
    _spaceBoostTimer?.cancel();
    setState(() => _spaceBoostActive = false);
    _spaceBoostTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _spaceBoostActive = true);
      _preBoostSpeed = _playbackSpeed;
      _setSpeed(2.0);
      if (!_isPlaying) _player?.play();
    });
  }

  void _endSpeedBoost() {
    final wasBoostPending = _spaceBoostTimer?.isActive ?? false;
    _spaceBoostTimer?.cancel();
    _spaceBoostTimer = null;
    if (_spaceBoostActive) {
      setState(() => _spaceBoostActive = false);
      _setSpeed(_preBoostSpeed);
      return;
    }
    if (wasBoostPending && (_isVideo || _isGif)) {
      _togglePlayPause();
      _showControls();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _endSpeedBoost();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        if (_mode == _MediaViewerMode.fullscreen) {
          _setMode(_MediaViewerMode.maximized);
        } else {
          _close();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f11:
        _setMode(_mode == _MediaViewerMode.fullscreen
            ? _MediaViewerMode.maximized
            : _MediaViewerMode.fullscreen);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        if (ctrl) {
          _setMode(_mode == _MediaViewerMode.fullscreen
              ? _MediaViewerMode.maximized
              : _MediaViewerMode.fullscreen);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        if (ctrl) {
          _zoomIn();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        if (ctrl) {
          _zoomOut();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        if (ctrl) {
          if (_isZoomedIn) {
            _animateZoomTo(0);
          } else {
            _animateZoomTo(3);
          }
          return KeyEventResult.handled;
        }
        if (_isVideo && _mode == _MediaViewerMode.fullscreen) {
          _seekToPercent(0);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit1:
      case LogicalKeyboardKey.numpad1:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(10); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit2:
      case LogicalKeyboardKey.numpad2:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(20); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit3:
      case LogicalKeyboardKey.numpad3:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(30); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit4:
      case LogicalKeyboardKey.numpad4:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(40); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit5:
      case LogicalKeyboardKey.numpad5:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(50); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit6:
      case LogicalKeyboardKey.numpad6:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(60); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit7:
      case LogicalKeyboardKey.numpad7:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(70); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit8:
      case LogicalKeyboardKey.numpad8:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(80); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit9:
      case LogicalKeyboardKey.numpad9:
        if (!ctrl && _isVideo && _mode == _MediaViewerMode.fullscreen) { _seekToPercent(90); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
        if (alt && _chapters.isNotEmpty) {
          _navigateChapter(-1);
          return KeyEventResult.handled;
        }
        _goToPrev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (alt && _chapters.isNotEmpty) {
          _navigateChapter(1);
          return KeyEventResult.handled;
        }
        _goToNext();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        if (alt || ctrl) {
          _setMode(_mode == _MediaViewerMode.fullscreen
              ? _MediaViewerMode.maximized
              : _MediaViewerMode.fullscreen);
          return KeyEventResult.handled;
        }
        if (_isVideo || _isGif) {
          _togglePlayPause();
          _showControls();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.space:
        if (_isVideo || _isGif) {
          if (event is KeyDownEvent) {
            _startSpeedBoost();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyK:
        if (_isVideo || _isGif) {
          _togglePlayPause();
          _showControls();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyJ:
        if (_isVideo && _player != null) {
          final target = _position - const Duration(seconds: 10);
          _player!.seek(target < Duration.zero ? Duration.zero : target);
          _showControls();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyL:
        if (_isVideo && _player != null) {
          _player!.seek(_position + const Duration(seconds: 10));
          _showControls();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.period:
        if (!ctrl) {
          _frameStep(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.comma:
        if (!ctrl) {
          _frameStep(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyS:
        if (ctrl) {
          _saveMediaToDownloads(_currentMessage);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyC:
        if (ctrl) {
          _copyImageToClipboard(_currentMessage);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyH:
        _flipHorizontal();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyV:
        _flipVertical();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyP:
        _enterPip();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  String _formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _showTitleBar => _effectiveMode != _MediaViewerMode.fullscreen;

  _MediaViewerMode get _effectiveMode {
    final screenSize = MediaQuery.sizeOf(context);
    if (_mode == _MediaViewerMode.windowed &&
        (screenSize.width < _kMinWidth || screenSize.height < _kMinHeight)) {
      return _MediaViewerMode.fullscreen;
    }
    return _mode;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final mode = _effectiveMode;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xE6000000)),
            if (mode == _MediaViewerMode.windowed)
              _buildWindowedViewer(screenSize)
            else
              _buildFullViewer(screenSize),
          ],
        ),
      ),
    );
  }

  Widget _buildFullViewer(Size screenSize) {
    final msg = _currentMessage;
    final photoIndex = widget.mediaMessages.length - _currentIndex;
    final totalPhotos = widget.mediaMessages.length;
    final titleBarOffset = _showTitleBar ? _kTitleBarHeight : 0.0;

    final contentViewport = Size(
      screenSize.width,
      screenSize.height - titleBarOffset,
    );
    final clampedPan = _clampPan(_panOffset, contentViewport);

    return Listener(
      onPointerHover: (_) => _onPointerActivity(),
      onPointerSignal: (e) => _handlePointerSignal(e, contentViewport),
      onPointerDown: _handlePointerDown,
      child: MouseRegion(
        cursor: (_mode == _MediaViewerMode.fullscreen && !_controlsVisible)
            ? SystemMouseCursors.none
            : _isZoomedIn
                ? SystemMouseCursors.move
                : SystemMouseCursors.basic,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () {
                if (_isZoomedIn) return;
                if (_isVideo || _isGif) {
                  _togglePlayPause();
                  _showControls();
                } else {
                  _toggleControls();
                }
              },
              onDoubleTap: () {
                if (_isVideo) {
                  _setMode(_mode == _MediaViewerMode.fullscreen
                      ? _MediaViewerMode.maximized
                      : _MediaViewerMode.fullscreen);
                } else if (!_isZoomedIn) {
                  _animateZoomTo(2);
                } else {
                  _animateZoomTo(0);
                }
              },
              onSecondaryTapDown: (details) =>
                  _showViewerContextMenu(details, _currentMessage),
              onScaleStart: (details) {
                _isPinching = details.pointerCount >= 2;
                _pinchBaseScale = _currentScale;
                _panGestureStart = _panOffset;
                _swipeHorizontalDelta = 0.0;
                _swipeNavigated = false;
              },
              onScaleUpdate: (details) {
                setState(() {
                  if (_isPinching || details.scale != 1.0) {
                    _isPinching = true;
                    _currentScale = (_pinchBaseScale * details.scale)
                        .clamp(_scaleForLevel(_kMinZoomLevel), _scaleForLevel(_kMaxZoomLevel));
                    _zoomLevel = _nearestLevel(_currentScale);
                  }
                  if (_isZoomedIn) {
                    _panOffset = _clampPan(
                      _panGestureStart + details.focalPointDelta,
                      contentViewport,
                    );
                  } else if (!_isPinching && !_swipeNavigated) {
                    _swipeHorizontalDelta += details.focalPointDelta.dx;
                    if (_swipeHorizontalDelta > _kSwipeThreshold) {
                      _swipeNavigated = true;
                      _goToPrev();
                    } else if (_swipeHorizontalDelta < -_kSwipeThreshold) {
                      _swipeNavigated = true;
                      _goToNext();
                    }
                  }
                });
              },
              onScaleEnd: (_) {
                _swipeHorizontalDelta = 0.0;
                _swipeNavigated = false;
                if (_isPinching) {
                  _isPinching = false;
                  final level = _nearestLevel(_currentScale);
                  if (level <= 0) {
                    _animateZoomTo(0);
                  } else {
                    _zoomLevel = level;
                  }
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: _kMediaviewBg),
                  if (_showTitleBar) _buildTitleBar(),
                  Positioned(
                    top: titleBarOffset,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..translate(clampedPan.dx, clampedPan.dy)
                          ..scale(_currentScale)
                          ..rotateZ(_displayRotation * math.pi / 2)
                          ..scale(_flipH ? -1.0 : 1.0, _flipV ? -1.0 : 1.0),
                        child: AnimatedSwitcher(
                          duration: _kMediaTransitionDuration,
                          switchInCurve: Curves.linear,
                          switchOutCurve: Curves.linear,
                          child: KeyedSubtree(
                            key: ValueKey(_currentIndex),
                            child: _buildContent(msg, screenSize),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              top: titleBarOffset,
              left: 0,
              right: 0,
              height: _kGradientTopHeight,
              child: IgnorePointer(
                child: Opacity(
                  opacity: _controlsOpacity,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x80000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: _kGradientBottomHeight,
              child: IgnorePointer(
                child: Opacity(
                  opacity: _controlsOpacity,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0x80000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_controlsVisible) ...[
              if (_hasPrev)
                Positioned(
                  left: 0,
                  top: titleBarOffset,
                  bottom: 0,
                  width: 90,
                  child: Opacity(
                    opacity: _controlsOpacity,
                    child: _NavArea(icon: Icons.chevron_left, onTap: _goToPrev),
                  ),
                ),
              if (_hasNext)
                Positioned(
                  right: 0,
                  top: titleBarOffset,
                  bottom: 0,
                  width: 90,
                  child: Opacity(
                    opacity: _controlsOpacity,
                    child: _NavArea(icon: Icons.chevron_right, onTap: _goToNext),
                  ),
                ),
              Positioned(
                left: 14,
                bottom: (_isVideo ? 86 : 8) + _stripOffset,
                right: 0,
                child: Opacity(
                  opacity: _controlsOpacity,
                  child: _buildFooter(msg, photoIndex, totalPhotos),
                ),
              ),
              if (_buildCaption(msg, contentViewport.height) case final caption?)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: (_isVideo ? 138 : 60) + _kMediaviewCaptionMargin + _stripOffset,
                  child: Opacity(
                    opacity: _controlsOpacity,
                    child: Center(child: caption),
                  ),
                ),
              if (!_showTitleBar)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Opacity(
                    opacity: _controlsOpacity,
                    child: _ViewerButton(
                      icon: Icons.close,
                      onTap: _close,
                      tooltip: 'Close',
                    ),
                  ),
                ),
              Positioned(
                bottom: (_isVideo ? 86 : 14) + _stripOffset,
                right: 14,
                child: Opacity(
                  opacity: _controlsOpacity,
                  child: _buildToolbar(msg),
                ),
              ),
            ],

            if (_hasStrip)
              Positioned(
                left: 0,
                right: 0,
                bottom: _isVideo ? 86 : 4,
                child: Opacity(
                  opacity: _controlsOpacity,
                  child: _buildGalleryStrip(),
                ),
              ),

            if (_isVideo && _player != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildVideoControls(),
              ),

            _buildSaveToast(),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: _SpeedBoostOverlay(active: _spaceBoostActive),
              ),
            ),
            _buildChapterToast(),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowedViewer(Size screenSize) {
    final msg = _currentMessage;
    final photoIndex = widget.mediaMessages.length - _currentIndex;
    final totalPhotos = widget.mediaMessages.length;

    final w = _windowedWidth.clamp(_kMinWidth, screenSize.width);
    final h = _windowedHeight.clamp(_kMinHeight, screenSize.height);
    final x = _windowedX.clamp(0.0, (screenSize.width - w).clamp(0.0, double.infinity));
    final y = _windowedY.clamp(0.0, (screenSize.height - h).clamp(0.0, double.infinity));

    final windowContentViewport = Size(w, h - _kTitleBarHeight);
    final clampedPan = _clampPan(_panOffset, windowContentViewport);

    return Positioned(
      left: x,
      top: y,
      child: Listener(
        onPointerHover: (_) => _onPointerActivity(),
        onPointerSignal: (e) => _handlePointerSignal(e, windowContentViewport),
        onPointerDown: _handlePointerDown,
        child: MouseRegion(
          cursor: _isZoomedIn
              ? SystemMouseCursors.move
              : SystemMouseCursors.basic,
          child: Container(
              width: w,
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _kMediaviewBg,
                borderRadius: BorderRadius.circular(2),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 20,
                      spreadRadius: 2),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (_isZoomedIn) return;
                      if (_isVideo || _isGif) {
                        _togglePlayPause();
                        _showControls();
                      } else {
                        _toggleControls();
                      }
                    },
                    onDoubleTap: () {
                      if (_isVideo) {
                        _setMode(_MediaViewerMode.fullscreen);
                      } else if (!_isZoomedIn) {
                        _animateZoomTo(2);
                      } else {
                        _animateZoomTo(0);
                      }
                    },
                    onSecondaryTapDown: (details) =>
                        _showViewerContextMenu(details, _currentMessage),
                    onScaleStart: (details) {
                      _isPinching = details.pointerCount >= 2;
                      _pinchBaseScale = _currentScale;
                      _panGestureStart = _panOffset;
                      _swipeHorizontalDelta = 0.0;
                      _swipeNavigated = false;
                    },
                    onScaleUpdate: (details) {
                      setState(() {
                        if (_isPinching || details.scale != 1.0) {
                          _isPinching = true;
                          _currentScale = (_pinchBaseScale * details.scale)
                              .clamp(_scaleForLevel(_kMinZoomLevel), _scaleForLevel(_kMaxZoomLevel));
                          _zoomLevel = _nearestLevel(_currentScale);
                        }
                        if (_isZoomedIn) {
                          _panOffset = _clampPan(
                            _panGestureStart + details.focalPointDelta,
                            windowContentViewport,
                          );
                        } else if (!_isPinching && !_swipeNavigated) {
                          _swipeHorizontalDelta += details.focalPointDelta.dx;
                          if (_swipeHorizontalDelta > _kSwipeThreshold) {
                            _swipeNavigated = true;
                            _goToPrev();
                          } else if (_swipeHorizontalDelta < -_kSwipeThreshold) {
                            _swipeNavigated = true;
                            _goToNext();
                          }
                        }
                      });
                    },
                    onScaleEnd: (_) {
                      _swipeHorizontalDelta = 0.0;
                      _swipeNavigated = false;
                      if (_isPinching) {
                        _isPinching = false;
                        final level = _nearestLevel(_currentScale);
                        if (level <= 0) {
                          _animateZoomTo(0);
                        } else {
                          _zoomLevel = level;
                        }
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildTitleBar(),
                        Positioned(
                          top: _kTitleBarHeight,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Center(
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..translate(clampedPan.dx, clampedPan.dy)
                                ..scale(_currentScale)
                                ..rotateZ(_displayRotation * math.pi / 2)
                                ..scale(_flipH ? -1.0 : 1.0, _flipV ? -1.0 : 1.0),
                              child: AnimatedSwitcher(
                                duration: _kMediaTransitionDuration,
                                switchInCurve: Curves.linear,
                                switchOutCurve: Curves.linear,
                                child: KeyedSubtree(
                                  key: ValueKey(_currentIndex),
                                  child: _buildContent(msg, Size(w, h - _kTitleBarHeight)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Positioned(
                  top: _kTitleBarHeight,
                  left: 0,
                  right: 0,
                  height: _kGradientTopHeight,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _controlsOpacity,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x80000000), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: _kGradientBottomHeight,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _controlsOpacity,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0x80000000), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (_controlsVisible) ...[
                  if (_hasPrev)
                    Positioned(
                      left: 0,
                      top: _kTitleBarHeight,
                      bottom: 0,
                      width: 90,
                      child: Opacity(
                        opacity: _controlsOpacity,
                        child: _NavArea(
                            icon: Icons.chevron_left, onTap: _goToPrev),
                      ),
                    ),
                  if (_hasNext)
                    Positioned(
                      right: 0,
                      top: _kTitleBarHeight,
                      bottom: 0,
                      width: 90,
                      child: Opacity(
                        opacity: _controlsOpacity,
                        child: _NavArea(
                            icon: Icons.chevron_right, onTap: _goToNext),
                      ),
                    ),
                  Positioned(
                    left: 14,
                    bottom: (_isVideo ? 86 : 14) + _stripOffset,
                    child: Opacity(
                      opacity: _controlsOpacity,
                      child: _buildFooter(msg, photoIndex, totalPhotos),
                    ),
                  ),
                  if (_buildCaption(msg, windowContentViewport.height) case final caption?)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: (_isVideo ? 138 : 60) + _kMediaviewCaptionMargin + _stripOffset,
                      child: Opacity(
                        opacity: _controlsOpacity,
                        child: Center(child: caption),
                      ),
                    ),
                  Positioned(
                    bottom: (_isVideo ? 86 : 14) + _stripOffset,
                    right: 14,
                    child: Opacity(
                      opacity: _controlsOpacity,
                      child: _buildToolbar(msg),
                    ),
                  ),
                ],

                if (_hasStrip)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: _isVideo ? 86 : 4,
                    child: Opacity(
                      opacity: _controlsOpacity,
                      child: _buildGalleryStrip(),
                    ),
                  ),

                if (_isVideo && _player != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildVideoControls(),
                  ),

              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onPanStart: (d) {
                    _isResizingWindow = true;
                    _resizeStart = d.globalPosition;
                    _resizeStartW = w;
                    _resizeStartH = h;
                  },
                  onPanUpdate: (d) {
                    if (!_isResizingWindow) return;
                    final dx = d.globalPosition.dx - _resizeStart.dx;
                    final dy = d.globalPosition.dy - _resizeStart.dy;
                    setState(() {
                      _windowedWidth = (_resizeStartW + dx).clamp(_kMinWidth, screenSize.width);
                      _windowedHeight = (_resizeStartH + dy).clamp(_kMinHeight, screenSize.height);
                    });
                  },
                  onPanEnd: (_) {
                    _isResizingWindow = false;
                    _saveViewerPrefs();
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: Container(
                      width: 16,
                      height: 16,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),

              _buildSaveToast(),
              _buildChapterToast(),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildTitleBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: _kTitleBarHeight,
      child: GestureDetector(
        onPanStart: _mode == _MediaViewerMode.windowed
            ? (d) {
                _isDraggingWindow = true;
                _dragStart = d.globalPosition - Offset(_windowedX, _windowedY);
              }
            : null,
        onPanUpdate: _mode == _MediaViewerMode.windowed
            ? (d) {
                if (!_isDraggingWindow) return;
                setState(() {
                  _windowedX = d.globalPosition.dx - _dragStart.dx;
                  _windowedY = d.globalPosition.dy - _dragStart.dy;
                });
              }
            : null,
        onPanEnd: _mode == _MediaViewerMode.windowed
            ? (_) {
                _isDraggingWindow = false;
                _saveViewerPrefs();
              }
            : null,
        onDoubleTap: _cycleMode,
        child: Container(
          height: _kTitleBarHeight,
          color: const Color(0xFF1A1A1A),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Text(
                'Media viewer',
                style: TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              _TitleBarButton(
                icon: Icons.minimize,
                onTap: () => _setMode(_MediaViewerMode.windowed),
                isActive: _mode == _MediaViewerMode.windowed,
              ),
              _TitleBarButton(
                icon: _mode == _MediaViewerMode.maximized
                    ? Icons.filter_none
                    : Icons.crop_square,
                onTap: () => _setMode(
                  _mode == _MediaViewerMode.maximized
                      ? _MediaViewerMode.windowed
                      : _MediaViewerMode.maximized,
                ),
                isActive: _mode == _MediaViewerMode.maximized,
              ),
              _TitleBarButton(
                icon: Icons.close,
                onTap: _close,
                isClose: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(CachedMessage msg, Size screenSize) {
    if ((msg.mediaType == 2 || msg.mediaType == 5 || msg.mediaType == 7) &&
        _videoController != null) {
      Widget videoWidget = Video(
        controller: _videoController!,
        width: screenSize.width,
        height: screenSize.height,
        fit: BoxFit.contain,
        controls: NoVideoControls,
      );
      if (msg.mediaType == 5) {
        final dim = screenSize.width < screenSize.height
            ? screenSize.width * 0.6
            : screenSize.height * 0.6;
        final clampedDim = dim.clamp(120.0, 360.0);
        videoWidget = ClipOval(
          child: SizedBox(
            width: clampedDim,
            height: clampedDim,
            child: Video(
              controller: _videoController!,
              width: clampedDim,
              height: clampedDim,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
          ),
        );
      }
      if (_isBuffering) {
        videoWidget = Stack(
          alignment: Alignment.center,
          children: [
            videoWidget,
            AnimatedBuilder(
              animation: _bufferSpinCtrl,
              builder: (context, _) => _RadialSpinner(animation: _bufferSpinCtrl),
            ),
          ],
        );
      }
      return videoWidget;
    }

    if (msg.mediaType == 8 || msg.mediaType == 3) {
      return _buildDocumentBubble(msg);
    }

    if (msg.mediaLocalPath.isNotEmpty && (msg.mediaType == 1 || msg.mediaType == 6)) {
      return _ProgressivePhoto(
        message: msg,
        maxWidth: screenSize.width,
        maxHeight: screenSize.height,
      );
    }

    if (msg.mediaLocalPath.isNotEmpty) {
      return Image.file(
        File(msg.mediaLocalPath),
        fit: BoxFit.contain,
        width: screenSize.width,
        height: screenSize.height,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, error, __) => _buildErrorPlaceholder(error),
      );
    }
    return _buildErrorPlaceholder(null);
  }

  Widget _buildDocumentBubble(CachedMessage msg) {
    final fileName = msg.mediaFileName.isNotEmpty ? msg.mediaFileName : 'File';
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : '';
    final sizeStr = _formatFileSize(msg.mediaFileSize);
    final isAudio = msg.mediaType == 3;

    return Container(
      width: _kDocBubbleWidth,
      height: _kDocBubbleHeight,
      decoration: BoxDecoration(
        color: _kMediaviewFileBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: _kDocIconSize,
            height: _kDocIconSize,
            margin: const EdgeInsets.only(left: 18),
            decoration: BoxDecoration(
              color: _docExtColor(ext),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isAudio ? Icons.music_note : Icons.insert_drive_file,
                  color: Colors.white,
                  size: 36,
                ),
                if (ext.isNotEmpty && ext.length <= 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      ext,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (sizeStr.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        sizeStr,
                        style: const TextStyle(
                          color: Color(0xFF8899AA),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _docExtColor(String ext) {
    return switch (ext) {
      'PDF' => const Color(0xFFE25454),
      'DOC' || 'DOCX' || 'RTF' || 'ODT' => const Color(0xFF5CA7EB),
      'XLS' || 'XLSX' || 'CSV' || 'ODS' => const Color(0xFF3ABB5B),
      'ZIP' || 'RAR' || '7Z' || 'TAR' || 'GZ' => const Color(0xFFE8A63A),
      'APK' || 'EXE' || 'MSI' || 'DMG' => const Color(0xFFA071E0),
      'MP3' || 'FLAC' || 'OGG' || 'WAV' || 'AAC' || 'M4A' => const Color(0xFFEB6ECA),
      _ => const Color(0xFF5CA7EB),
    };
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildErrorPlaceholder(Object? error) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image, color: Colors.white54, size: 64),
        const SizedBox(height: 8),
        Text(
          error != null ? 'Failed to load image' : 'No image available',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }

  IconData get _volumeIcon {
    if (_volume <= 0) return Icons.volume_off;
    if (_volume < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  void _toggleMute() {
    setState(() {
      if (_volume > 0) {
        _lastVolume = _volume;
        _volume = 0;
      } else {
        _volume = _lastVolume > 0 ? _lastVolume : 0.8;
      }
      _player?.setVolume(_volume * 100.0);
    });
  }

  void _setVolume(double v) {
    setState(() {
      _volume = v.clamp(0.0, 1.0);
      if (_volume > 0) _lastVolume = _volume;
      _player?.setVolume(_volume * 100.0);
    });
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _player?.setRate(speed);
  }

  void _showSpeedMenu(BuildContext ctx, Offset globalPos) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    showMenu<double>(
      context: ctx,
      position: RelativeRect.fromLTRB(
        globalPos.dx - 40,
        globalPos.dy - speeds.length * 40.0,
        globalPos.dx + 40,
        globalPos.dy,
      ),
      color: const Color(0xE6000000),
      items: speeds.map((s) {
        final label = s == 1.0 ? 'Normal' : '${s}x';
        return PopupMenuItem<double>(
          value: s,
          height: 36,
          child: Text(
            label,
            style: TextStyle(
              color: s == _playbackSpeed
                  ? const Color(0xFF64B5F6)
                  : Colors.white,
              fontSize: 13,
              fontWeight:
                  s == _playbackSpeed ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    ).then((v) {
      if (v != null) _setSpeed(v);
    });
  }

  String get _speedLabel =>
      _playbackSpeed == 1.0 ? '1x' : '${_playbackSpeed}x';

  List<VideoQuality> get _availableQualities => _currentMessage.altQualities;

  String get _qualityLabel {
    if (_activeQualitySeq != null) {
      final q = _availableQualities.where((q) => q.seq == _activeQualitySeq).firstOrNull;
      if (q != null) return q.label;
    }
    final h = _currentMessage.mediaHeight;
    if (h > 0) return '${h}p';
    return 'Auto';
  }

  void _showQualityMenu(BuildContext ctx, Offset globalPos) {
    final msg = _currentMessage;
    final qualities = _availableQualities;
    if (qualities.isEmpty) return;

    final originalHeight = msg.mediaHeight;
    final items = <PopupMenuEntry<int?>>[];
    items.add(PopupMenuItem<int?>(
      value: null,
      height: 36,
      child: Text(
        originalHeight > 0 ? '${originalHeight}p (original)' : 'Original',
        style: TextStyle(
          color: _activeQualitySeq == null ? const Color(0xFF64B5F6) : Colors.white,
          fontSize: 13,
          fontWeight: _activeQualitySeq == null ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ));
    for (final q in qualities) {
      final sizeLabel = q.size > 0 ? ' (${_formatFileSize(q.size)})' : '';
      items.add(PopupMenuItem<int?>(
        value: q.seq,
        height: 36,
        child: Text(
          '${q.label}$sizeLabel',
          style: TextStyle(
            color: _activeQualitySeq == q.seq ? const Color(0xFF64B5F6) : Colors.white,
            fontSize: 13,
            fontWeight: _activeQualitySeq == q.seq ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ));
    }

    showMenu<int?>(
      context: ctx,
      position: RelativeRect.fromLTRB(
        globalPos.dx - 60,
        globalPos.dy - items.length * 40.0,
        globalPos.dx + 60,
        globalPos.dy,
      ),
      color: const Color(0xE6000000),
      items: items,
    ).then((seq) {
      if (seq == null && _activeQualitySeq == null) return;
      _switchQuality(seq);
    });
  }

  void _switchQuality(int? seq) {
    if (seq == _activeQualitySeq) return;
    final msg = _currentMessage;

    if (seq == null) {
      final savedPos = _position;
      final wasPlaying = _isPlaying;
      setState(() {
        _activeQualitySeq = null;
        _qualityDownloading = false;
      });
      _disposePlayer();
      _initVideoIfNeeded();
      Future.delayed(const Duration(milliseconds: 100), () {
        _player?.seek(savedPos);
        if (wasPlaying) _player?.play();
      });
      return;
    }

    final chatState = _chatStateRef;
    if (chatState == null) return;

    final existing = chatState.getAltQualityPath(msg.msgId, seq);
    if (existing != null && File(existing).existsSync()) {
      _applyQualitySwitch(seq, existing);
      return;
    }

    setState(() => _qualityDownloading = true);
    chatState.requestAltQualityDownload(msg, seq);

    void listener() {
      final path = chatState.getAltQualityPath(msg.msgId, seq);
      if (path != null && path.isNotEmpty) {
        chatState.removeListener(listener);
        if (mounted) _applyQualitySwitch(seq, path);
      }
    }
    chatState.addListener(listener);
  }

  void _applyQualitySwitch(int seq, String path) {
    final savedPos = _position;
    final wasPlaying = _isPlaying;
    setState(() {
      _activeQualitySeq = seq;
      _qualityDownloading = false;
    });
    _disposePlayer();
    final player = Player();
    _player = player;
    _videoController = VideoController(player);
    _playerSubs = [
      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),
      player.stream.position.listen((pos) {
        if (mounted && !_isSeeking) setState(() => _position = pos);
      }),
      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      }),
    ];
    player.setVolume(_volume * 100.0);
    player.setRate(_playbackSpeed);
    player.open(Media(path));
    Future.delayed(const Duration(milliseconds: 100), () {
      player.seek(savedPos);
      if (wasPlaying) player.play();
    });
  }

  Widget _buildVideoControls() {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = _duration - _position;

    return AnimatedBuilder(
      animation: _controlsAnim,
      builder: (context, child) => Opacity(
        opacity: _controlsAnim.value,
        child: IgnorePointer(
          ignoring: _controlsAnim.isDismissed,
          child: child,
        ),
      ),
      child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            constraints: const BoxConstraints(maxWidth: 480),
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 2),
                SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: _ControlButton(
                          icon: _volumeIcon,
                          size: 32,
                          onTap: _toggleMute,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 75,
                        child: _PlaybackSlider(
                          value: _volume,
                          trackHeight: 3,
                          handleSize: 10,
                          activeColor: const Color(0xFFC7C7C7),
                          inactiveColor: const Color(0xFF404040),
                          onChanged: _setVolume,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(_position),
                        style: const TextStyle(
                          color: Color(0xFFC7C7C7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PlaybackSlider(
                          value: progress,
                          trackHeight: 3,
                          handleSize: 12,
                          activeColor: const Color(0xFFC7C7C7),
                          inactiveColor: const Color(0xFF252525),
                          chapters: _chapters.map((c) => c.position).toList(),
                          onChanged: (v) {
                            if (_duration.inMilliseconds == 0) return;
                            setState(() {
                              _isSeeking = true;
                              _position = Duration(
                                milliseconds:
                                    (v * _duration.inMilliseconds).round(),
                              );
                            });
                            _player?.seek(_position);
                          },
                          onChangeEnd: () =>
                              setState(() => _isSeeking = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '-${_formatTime(remaining)}',
                        style: const TextStyle(
                          color: Color(0xFFC7C7C7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      const Spacer(),
                      _ControlButton(
                        icon: _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 40,
                        onTap: _togglePlayPause,
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTapDown: (d) =>
                            _showSpeedMenu(context, d.globalPosition),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            child: Text(
                              _speedLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_availableQualities.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTapDown: (d) =>
                              _showQualityMenu(context, d.globalPosition),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.center,
                              child: _qualityDownloading
                                  ? const SizedBox(
                                      width: 14, height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _qualityLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      _ControlButton(
                        icon: Icons.picture_in_picture_alt,
                        size: 32,
                        onTap: _enterPip,
                      ),
                      const SizedBox(width: 4),
                      _ControlButton(
                        icon: _mode == _MediaViewerMode.fullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        size: 32,
                        onTap: () => _setMode(
                          _mode == _MediaViewerMode.fullscreen
                              ? _MediaViewerMode.maximized
                              : _MediaViewerMode.fullscreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }

  String _middleElide(String text, double maxWidth, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    if (tp.width <= maxWidth) return text;
    const ellipsis = '\u2026';
    int lo = 1, hi = text.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      final half = mid ~/ 2;
      final candidate = '${text.substring(0, half)}$ellipsis${text.substring(text.length - (mid - half))}';
      final check = TextPainter(
        text: TextSpan(text: candidate, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      if (check.width <= maxWidth) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final keep = (lo - 1).clamp(2, text.length - 1);
    final half = keep ~/ 2;
    return '${text.substring(0, half)}$ellipsis${text.substring(text.length - (keep - half))}';
  }

  Widget _buildFooter(CachedMessage msg, int photoIndex, int totalPhotos) {
    final typeLabel = switch (msg.mediaType) {
      1 => 'Photo',
      2 => 'Video',
      3 => 'Audio',
      5 => 'Video message',
      6 => 'Sticker',
      7 => 'GIF',
      8 => msg.mediaFileName.isNotEmpty ? msg.mediaFileName : 'File',
      _ => 'Media',
    };
    final headerText = totalPhotos > 1
        ? '$typeLabel $photoIndex of $totalPhotos'
        : typeLabel;

    final dt = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final timePart = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    String datePart;
    if (msgDay == today) {
      datePart = 'Today at $timePart';
    } else if (msgDay == yesterday) {
      datePart = 'Yesterday at $timePart';
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      datePart = '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $timePart';
    }
    final dcPart = msg.dcId > 0 ? ', DC${msg.dcId}' : '';
    final dateStr = '$datePart$dcPart';

    const headerStyle = TextStyle(
      color: _kMediaviewControlFg,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    const infoStyle = TextStyle(
      color: _kMediaviewControlFg,
      fontSize: 13,
    );
    const separatorStyle = TextStyle(
      color: _kMediaviewControlFg,
      fontSize: 13,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeaderWidth = constraints.maxWidth > 0
            ? constraints.maxWidth / 3
            : 300.0;
        final displayHeader = _middleElide(headerText, maxHeaderWidth, headerStyle);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(displayHeader, style: headerStyle, maxLines: 1),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.senderName.isNotEmpty) ...[
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _onSenderTap(msg),
                      child: Text(msg.senderName, style: infoStyle),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Text('\u2022', style: separatorStyle),
                  ),
                ],
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _onDateTap(msg),
                    child: Text(dateStr, style: infoStyle),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget? _buildCaption(CachedMessage msg, double maxUsedHeight) {
    final text = msg.contentText;
    if (text.isEmpty) return null;

    final maxCaptionHeight = maxUsedHeight / 4;

    return Container(
      constraints: BoxConstraints(
        maxWidth: _kMediaviewCaptionMaxWidth,
        maxHeight: maxCaptionHeight,
      ),
      decoration: BoxDecoration(
        color: _kMediaviewCaptionBg,
        borderRadius: BorderRadius.circular(_kMediaviewCaptionRadius),
      ),
      padding: _kMediaviewCaptionPadding,
      child: SingleChildScrollView(
        child: _buildCaptionRichText(text, msg.contentRich),
      ),
    );
  }

  Widget _buildCaptionRichText(String text, String entitiesJson) {
    const baseStyle = TextStyle(
      color: _kMediaviewCaptionFg,
      fontSize: 14,
      height: 1.35,
    );
    if (entitiesJson.isEmpty) {
      return SelectableText(text, style: baseStyle);
    }
    List<_CaptionEntity> entities;
    try {
      final list = jsonDecode(entitiesJson) as List;
      entities = list.map((e) => _CaptionEntity.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return SelectableText(text, style: baseStyle);
    }
    if (entities.isEmpty) {
      return SelectableText(text, style: baseStyle);
    }
    entities.sort((a, b) => a.offset.compareTo(b.offset));
    final spans = _buildCaptionSpans(text, entities, baseStyle);
    return SelectableText.rich(
      TextSpan(children: spans),
      style: baseStyle,
    );
  }

  void _onSenderTap(CachedMessage msg) {
    final chatState = context.read<ChatState>();
    Navigator.of(context).pop();
    if (msg.senderId.isNotEmpty) {
      chatState.openChatById(msg.senderId);
      UniClientShell.toggleInfoRequest?.call();
    }
  }

  void _onDateTap(CachedMessage msg) {
    final chatState = context.read<ChatState>();
    Navigator.of(context).pop();
    chatState.jumpToMessage(msg.timestamp);
  }

  void _saveMediaToDownloads(CachedMessage msg) async {
    if (msg.mediaLocalPath.isEmpty) return;
    final sourceFile = File(msg.mediaLocalPath);
    if (!await sourceFile.exists()) return;
    final fileName = msg.mediaFileName.isNotEmpty
        ? msg.mediaFileName
        : sourceFile.uri.pathSegments.last;

    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || !mounted) return;

    var destPath = '$dirPath/$fileName';
    var counter = 1;
    while (await File(destPath).exists()) {
      final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
      final base = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      destPath = '$dirPath/${base}_($counter)$ext';
      counter++;
    }
    await sourceFile.copy(destPath);
    if (!mounted) return;
    _showSaveToast(dirPath);
  }

  void _showSaveToast(String downloadsPath) {
    _saveToastHoldTimer?.cancel();
    _saveToastPath = downloadsPath;
    _saveToastAnim.forward(from: 0.0).then((_) {
      if (!mounted) return;
      _saveToastHoldTimer = Timer(_kSaveToastHold, () {
        if (mounted) _saveToastAnim.reverse();
      });
    });
  }

  Widget _buildSaveToast() {
    return AnimatedBuilder(
      animation: _saveToastAnim,
      builder: (context, child) {
        if (_saveToastAnim.value == 0.0) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: _saveToastAnim.status == AnimationStatus.reverse,
            child: Center(
              child: Opacity(
                opacity: _saveToastAnim.value,
                child: Container(
                  decoration: BoxDecoration(
                    color: _kMediaviewSaveMsgBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: _kSaveToastPadding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: Icon(Icons.check_circle, color: _kMediaviewSaveMsgFg, size: 24),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Media saved to '),
                            TextSpan(
                              text: 'Downloads',
                              style: const TextStyle(decoration: TextDecoration.underline),
                              recognizer: _downloadsLinkRecognizer,
                            ),
                          ],
                        ),
                        style: const TextStyle(
                          color: _kMediaviewSaveMsgFg,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChapterToast() {
    return AnimatedBuilder(
      animation: _chapterToastAnim,
      builder: (context, child) {
        if (_chapterToastAnim.value == 0.0) return const SizedBox.shrink();
        return Center(
          child: IgnorePointer(
            child: Opacity(
              opacity: _chapterToastAnim.value,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _kMediaviewSaveMsgBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_chapterToastDirection < 0)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.chevron_left, color: _kMediaviewSaveMsgFg, size: 18),
                      ),
                    Text(
                      _chapterToastText,
                      style: const TextStyle(color: _kMediaviewSaveMsgFg, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    if (_chapterToastDirection > 0)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.chevron_right, color: _kMediaviewSaveMsgFg, size: 18),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInChat(CachedMessage msg) {
    final chatState = context.read<ChatState>();
    Navigator.of(context).pop();
    chatState.jumpToMessage(msg.timestamp);
  }

  void _forwardMedia(CachedMessage msg) {
    final chatState = context.read<ChatState>();
    final chats = chatState.chats;
    if (chats.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        final selectedChatIds = <String>{};
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = searchQuery.isEmpty
                ? chats
                : chats.where((c) => c.title.toLowerCase().contains(searchQuery.toLowerCase())).toList();
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2C3A),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Forward to...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (selectedChatIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: selectedChatIds.map((id) {
                          final chat = chats.firstWhere((c) => c.chatId == id);
                          return Chip(
                            label: Text(chat.title, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            backgroundColor: const Color(0xFF3390EC),
                            deleteIconColor: Colors.white70,
                            onDeleted: () => setDialogState(() => selectedChatIds.remove(id)),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ),
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Search chats...',
                      hintStyle: TextStyle(color: Colors.white38),
                      prefixIcon: Icon(Icons.search, color: Colors.white38, size: 20),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                height: 380,
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final chat = filtered[i];
                    final selected = selectedChatIds.contains(chat.chatId);
                    return ListTile(
                      dense: true,
                      leading: selected
                          ? const Icon(Icons.check_circle, color: Color(0xFF3390EC), size: 20)
                          : const Icon(Icons.circle_outlined, color: Colors.white38, size: 20),
                      title: Text(chat.title, style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        setDialogState(() {
                          if (selected) {
                            selectedChatIds.remove(chat.chatId);
                          } else {
                            selectedChatIds.add(chat.chatId);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: selectedChatIds.isEmpty ? null : () {
                    Navigator.of(ctx).pop();
                    for (final chatId in selectedChatIds) {
                      chatState.forwardMessages([msg.msgId], chatId);
                    }
                    final count = selectedChatIds.length;
                    showTelegramToast(context, 'Forwarded to $count chat${count > 1 ? 's' : ''}');
                  },
                  child: Text('Send${selectedChatIds.isNotEmpty ? ' (${selectedChatIds.length})' : ''}'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteMedia(CachedMessage msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2C3A),
        title: const Text('Delete', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this media?',
            style: TextStyle(color: Color(0xFFAABBCC))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final chatState = context.read<ChatState>();
              chatState.deleteMessage(msg.msgId);
              if (widget.mediaMessages.length <= 1) {
                Navigator.of(context).pop();
              } else {
                setState(() {
                  if (_currentIndex > 0) {
                    _currentIndex--;
                  }
                });
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _copyImageToClipboard(CachedMessage msg) async {
    if (msg.mediaLocalPath.isEmpty) return;
    final file = File(msg.mediaLocalPath);
    if (!await file.exists()) return;
    final ext = msg.mediaLocalPath.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
    final bytes = await file.readAsBytes();
    bool ok = false;
    // Try wl-copy (Wayland) first
    try {
      final proc = await Process.start('wl-copy', ['--type', mimeType]);
      proc.stdin.add(bytes);
      await proc.stdin.close();
      ok = (await proc.exitCode) == 0;
    } catch (_) {}
    // Fall back to xclip (X11)
    if (!ok) {
      try {
        final result = await Process.run('xclip',
            ['-selection', 'clipboard', '-t', mimeType, '-i', msg.mediaLocalPath]);
        ok = result.exitCode == 0;
      } catch (_) {}
    }
    if (!mounted) return;
    showTelegramToast(context, ok ? 'Image copied to clipboard' : 'Failed to copy image');
  }

  void _copyVideoFrame(CachedMessage msg) async {
    if (msg.mediaLocalPath.isEmpty || _player == null) return;
    try {
      final screenshot = await _player!.screenshot();
      if (screenshot == null || screenshot.isEmpty) {
        if (mounted) showTelegramToast(context, 'Failed to capture frame');
        return;
      }
      bool ok = false;
      // Try wl-copy (Wayland) first
      try {
        final proc = await Process.start('wl-copy', ['--type', 'image/png']);
        proc.stdin.add(screenshot);
        await proc.stdin.close();
        ok = (await proc.exitCode) == 0;
      } catch (_) {}
      // Fall back to xclip
      if (!ok) {
        try {
          final tmpFile = File('/tmp/uniclient_frame.png');
          await tmpFile.writeAsBytes(screenshot);
          final result = await Process.run('xclip',
              ['-selection', 'clipboard', '-t', 'image/png', '-i', tmpFile.path]);
          ok = result.exitCode == 0;
          tmpFile.deleteSync();
        } catch (_) {}
      }
      if (!mounted) return;
      showTelegramToast(context, ok ? 'Frame copied to clipboard' : 'Failed to copy frame');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed to capture frame');
    }
  }

  void _showInFolder(CachedMessage msg) {
    if (msg.mediaLocalPath.isEmpty) return;
    final dir = File(msg.mediaLocalPath).parent.path;
    Process.run('xdg-open', [dir]);
  }

  void _shareAtTime(CachedMessage msg) {
    if (!_isVideo || _player == null || _duration == Duration.zero) return;
    final timeRef = _formatTime(_position);
    final fileName = msg.mediaFileName.isNotEmpty ? msg.mediaFileName : 'Video';
    final shareText = '$fileName at $timeRef';

    final chatState = context.read<ChatState>();
    final chats = chatState.chats;
    if (chats.isEmpty) {
      Clipboard.setData(ClipboardData(text: shareText));
      if (mounted) showTelegramToast(context, 'Time reference copied');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = searchQuery.isEmpty
                ? chats
                : chats.where((c) => c.title.toLowerCase().contains(searchQuery.toLowerCase())).toList();
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2C3A),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Share time reference', style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(shareText, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Search chats...',
                      hintStyle: TextStyle(color: Colors.white38),
                      prefixIcon: Icon(Icons.search, color: Colors.white38, size: 20),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v),
                  ),
                ],
              ),
              content: SizedBox(
                width: 300,
                height: 350,
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final chat = filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(chat.title, style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        chatState.openChatById(chat.chatId);
                        chatState.sendMessage(shareText);
                        showTelegramToast(context, 'Sent to ${chat.title}');
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: shareText));
                    Navigator.of(ctx).pop();
                    showTelegramToast(context, 'Time reference copied');
                  },
                  child: const Text('Copy to Clipboard'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAllMedia(CachedMessage msg) {
    Navigator.of(context).pop();
    UniClientShell.toggleInfoRequest?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InfoPanel.pushSharedMediaRequest?.call();
    });
  }

  void _cancelDownload(CachedMessage msg) {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isNotEmpty) {
      engine.cancelDownload(accountId, msg.chatId, msg.msgId);
    }
    showTelegramToast(context, 'Download cancelled');
  }


  void _setAsUserpic(CachedMessage msg) async {
    if (msg.mediaLocalPath.isEmpty) return;
    final file = File(msg.mediaLocalPath);
    if (!await file.exists()) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    try {
      await engine.uploadProfilePhoto(accountId, msg.mediaLocalPath);
      if (mounted) showTelegramToast(context, 'Profile photo updated');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed to set profile photo');
    }
  }

  void _reportUserpic(CachedMessage msg) async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report Photo'),
        content: const Text('Are you sure you want to report this photo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final msgId = int.tryParse(msg.msgId) ?? 0;
      await engine.reportMessage(accountId, msg.chatId, [msgId]);
      if (mounted) showTelegramToast(context, 'Report sent');
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed to send report');
    }
  }

  void _viewStatistics(CachedMessage msg) async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    Map<String, dynamic> stats = {};
    try {
      final msgId = int.tryParse(msg.msgId) ?? 0;
      stats = await engine.getMessageStats(accountId, msg.chatId, msgId);
    } catch (_) {}

    if (!mounted) return;

    final views = stats['views'] as int? ?? msg.views;
    final forwards = stats['forwards'] as int? ?? msg.forwards;
    final reactions = stats['reactions'] as int? ??
        (msg.reactions.isNotEmpty ? msg.reactions.fold<int>(0, (sum, r) => sum + r.count) : 0);
    final publicShares = stats['public_shares'] as int? ?? 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Statistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 16),
              _statRow(Icons.visibility_outlined, 'Views', views > 0 ? '$views' : '—', textColor, subtextColor),
              const SizedBox(height: 12),
              _statRow(Icons.share_outlined, 'Forwards', forwards > 0 ? '$forwards' : '—', textColor, subtextColor),
              if (publicShares > 0) ...[
                const SizedBox(height: 12),
                _statRow(Icons.public, 'Public Shares', '$publicShares', textColor, subtextColor),
              ],
              const SizedBox(height: 12),
              _statRow(Icons.favorite_border, 'Reactions', reactions > 0 ? '$reactions' : '—', textColor, subtextColor),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  static Widget _statRow(IconData icon, String label, String value, Color textColor, Color subtextColor) {
    return Row(
      children: [
        Icon(icon, size: 20, color: subtextColor),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14, color: textColor)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
      ],
    );
  }

  bool get _isSelfMedia {
    try {
      final appState = context.read<AppState>();
      final selfId = appState.activeAccount?.selfUserId ?? '';
      return selfId.isNotEmpty && selfId == _currentMessage.senderId;
    } catch (_) {
      return false;
    }
  }

  bool get _isChannelPost => _currentMessage.views > 0;

  List<PopupMenuEntry<String>> _buildMediaMenuItems(CachedMessage msg) {
    return <PopupMenuEntry<String>>[
      if (msg.mediaDownloadState == 1)
        _darkMenuItem('cancel_download', Icons.cancel_outlined, 'Cancel Download'),
      if (msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('show_in_chat', Icons.chat_bubble_outline, 'Show in Chat'),
      if (msg.mediaLocalPath.isNotEmpty && File(msg.mediaLocalPath).existsSync())
        _darkMenuItem('show_in_folder', Icons.folder_open, 'Show in Folder'),
      if (_isPhoto && msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('copy_image', Icons.copy, 'Copy Image'),
      if (_isVideo && msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('copy_frame', Icons.content_copy, 'Copy Frame'),
      if (msg.mediaLocalPath.isNotEmpty && !msg.noForwards)
        _darkMenuItem('forward', Icons.forward, 'Forward'),
      if (_isVideo && _player != null && _duration > Duration.zero)
        _darkMenuItem('share_at_time', Icons.access_time, 'Share at Time'),
      if (_isSelfMedia && _isPhoto && msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('set_as_userpic', Icons.account_circle_outlined, 'Set as Profile Photo'),
      if (!_isSelfMedia && _isPhoto && msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('report_userpic', Icons.flag_outlined, 'Report Photo'),
      if (_isChannelPost)
        _darkMenuItem('view_statistics', Icons.bar_chart, 'View Statistics'),
      if (msg.isOutgoing)
        _darkMenuItem('delete', Icons.delete_outline, 'Delete',
            isDestructive: true),
      if (msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('save_as', Icons.save_alt, 'Save As\u2026'),
      if (msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('show_all', Icons.photo_library, 'Show All Photos'),
    ];
  }

  void _handleMenuAction(String action, CachedMessage msg) {
    switch (action) {
      case 'cancel_download':
        _cancelDownload(msg);
      case 'show_in_chat':
        _showInChat(msg);
      case 'show_in_folder':
        _showInFolder(msg);
      case 'copy_image':
        _copyImageToClipboard(msg);
      case 'copy_frame':
        _copyVideoFrame(msg);
      case 'forward':
        _forwardMedia(msg);
      case 'share_at_time':
        _shareAtTime(msg);
      case 'set_as_userpic':
        _setAsUserpic(msg);
      case 'report_userpic':
        _reportUserpic(msg);
      case 'view_statistics':
        _viewStatistics(msg);
      case 'delete':
        _deleteMedia(msg);
      case 'save_as':
        _saveMediaToDownloads(msg);
      case 'show_all':
        _showAllMedia(msg);
    }
  }

  void _showMoreMenu(BuildContext btnContext, CachedMessage msg) {
    final RenderBox button = btnContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(btnContext).overlay!.context.findRenderObject()
            as RenderBox;
    final Offset pos = button.localToGlobal(Offset.zero, ancestor: overlay);

    final items = _buildMediaMenuItems(msg);

    showMenu<String>(
      context: btnContext,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy - (items.length * 48.0),
        pos.dx + button.size.width,
        pos.dy,
      ),
      color: const Color(0xE6222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: items,
    ).then((value) {
      if (value == null) return;
      _handleMenuAction(value, msg);
    });
  }

  PopupMenuItem<String> _darkMenuItem(
      String value, IconData icon, String label,
      {bool isDestructive = false}) {
    final color = isDestructive ? const Color(0xFFE53935) : const Color(0xFFDDDDDD);
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  void _showViewerContextMenu(TapDownDetails details, CachedMessage msg) {
    final pos = details.globalPosition;
    final items = _buildMediaMenuItems(msg);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: const Color(0xE6222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: items,
    ).then((value) {
      if (value == null) return;
      _handleMenuAction(value, msg);
    });
  }



  void _recognizeText(CachedMessage msg) async {
    if (msg.mediaLocalPath.isEmpty) return;
    final result = await Process.run('which', ['tesseract']);
    if (result.exitCode != 0) {
      if (mounted) showTelegramToast(context, 'Install tesseract-ocr for text recognition');
      return;
    }
    if (mounted) showTelegramToast(context, 'Recognizing text…');
    final ocr = await Process.run('tesseract', [msg.mediaLocalPath, 'stdout']);
    if (!mounted) return;
    final text = (ocr.stdout as String).trim();
    if (text.isEmpty) {
      showTelegramToast(context, 'No text found in image');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    showTelegramToast(context, 'Text copied to clipboard');
  }

  Widget _buildToolbar(CachedMessage msg) {
    final hasContent = msg.mediaLocalPath.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isPhoto && hasContent)
          _ViewerButton(
            icon: Icons.text_fields,
            onTap: () => _recognizeText(msg),
            tooltip: 'Recognize Text',
          ),
        if (_isPhoto && hasContent)
          _ViewerButton(
            icon: Icons.edit,
            onTap: () => _openDrawEditor(msg),
            tooltip: 'Draw',
          ),
        if (hasContent)
          _ViewerButton(
            icon: Icons.save_alt,
            onTap: () => _saveMediaToDownloads(msg),
            tooltip: 'Save (Ctrl+S)',
          ),
        _ViewerButton(
          icon: Icons.rotate_left,
          onTap: _rotate,
          tooltip: 'Rotate',
        ),
        Builder(
          builder: (btnCtx) => _ViewerButton(
            icon: Icons.more_horiz,
            onTap: () => _showMoreMenu(btnCtx, msg),
            tooltip: 'More',
          ),
        ),
      ],
    );
  }

  void _openDrawEditor(CachedMessage msg) async {
    if (msg.mediaLocalPath.isEmpty) return;
    final file = File(msg.mediaLocalPath);
    if (!await file.exists()) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoCropEditor(
          imageFile: file,
          purpose: PhotoEditorPurpose.edit,
          onDone: (editedFile) async {
            final dirPath = await FilePicker.platform.getDirectoryPath();
            if (dirPath == null) return;
            final fileName = msg.mediaFileName.isNotEmpty
                ? msg.mediaFileName
                : 'edited_photo.png';
            final destPath = '$dirPath/$fileName';
            try {
              await editedFile.copy(destPath);
              if (mounted) showTelegramToast(context, 'Photo saved to $dirPath');
            } catch (e) {
              if (mounted) showTelegramToast(context, 'Failed to save photo');
            }
          },
        ),
      ),
    );
  }
}

class _CaptionEntity {
  final String type;
  final int offset;
  final int length;
  final String url;

  const _CaptionEntity({required this.type, required this.offset, required this.length, this.url = ''});

  factory _CaptionEntity.fromJson(Map<String, dynamic> j) => _CaptionEntity(
    type: j['type'] as String? ?? '',
    offset: j['offset'] as int? ?? 0,
    length: j['length'] as int? ?? 0,
    url: j['url'] as String? ?? '',
  );
}

List<InlineSpan> _buildCaptionSpans(String text, List<_CaptionEntity> entities, TextStyle baseStyle) {
  final spans = <InlineSpan>[];
  int cursor = 0;
  for (final e in entities) {
    if (e.offset > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, e.offset.clamp(0, text.length))));
    }
    final end = (e.offset + e.length).clamp(0, text.length);
    final seg = text.substring(e.offset.clamp(0, text.length), end);
    switch (e.type) {
      case 'bold':
        spans.add(TextSpan(text: seg, style: const TextStyle(fontWeight: FontWeight.bold)));
      case 'italic':
        spans.add(TextSpan(text: seg, style: const TextStyle(fontStyle: FontStyle.italic)));
      case 'underline':
        spans.add(TextSpan(text: seg, style: const TextStyle(decoration: TextDecoration.underline)));
      case 'strikethrough':
        spans.add(TextSpan(text: seg, style: const TextStyle(decoration: TextDecoration.lineThrough)));
      case 'code': case 'pre':
        spans.add(TextSpan(text: seg, style: const TextStyle(fontFamily: 'monospace', backgroundColor: Color(0x33FFFFFF))));
      case 'text_url':
        spans.add(TextSpan(
          text: seg,
          style: const TextStyle(color: _kMediaviewCaptionLinkFg, decoration: TextDecoration.underline, decorationColor: _kMediaviewCaptionLinkFg),
          recognizer: TapGestureRecognizer()..onTap = () { if (e.url.isNotEmpty) url_launcher.launchUrl(Uri.parse(e.url)); },
        ));
      case 'url':
        spans.add(TextSpan(
          text: seg,
          style: const TextStyle(color: _kMediaviewCaptionLinkFg, decoration: TextDecoration.underline, decorationColor: _kMediaviewCaptionLinkFg),
          recognizer: TapGestureRecognizer()..onTap = () { url_launcher.launchUrl(Uri.parse(seg)); },
        ));
      case 'mention': case 'text_mention':
        spans.add(TextSpan(
          text: seg,
          style: const TextStyle(color: _kMediaviewCaptionLinkFg),
        ));
      case 'spoiler':
        spans.add(TextSpan(text: seg, style: const TextStyle(backgroundColor: Color(0xFFAAAAAA), color: Color(0xFFAAAAAA))));
      default:
        spans.add(TextSpan(text: seg));
    }
    cursor = end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}

class _PlaybackSlider extends StatefulWidget {
  final double value;
  final double trackHeight;
  final double handleSize;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;
  final List<double> chapters;

  const _PlaybackSlider({
    required this.value,
    required this.trackHeight,
    required this.handleSize,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChanged,
    this.onChangeEnd,
    this.chapters = const [],
  });

  @override
  State<_PlaybackSlider> createState() => _PlaybackSliderState();
}

class _PlaybackSliderState extends State<_PlaybackSlider> {
  bool _hovering = false;
  bool _dragging = false;

  double _ratioFromLocal(double localX, double totalWidth) {
    final pad = widget.handleSize / 2;
    final trackWidth = totalWidth - widget.handleSize;
    if (trackWidth <= 0) return 0;
    return ((localX - pad) / trackWidth).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          widget.onChanged(_ratioFromLocal(d.localPosition.dx, box.size.width));
        },
        onHorizontalDragStart: (d) {
          _dragging = true;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          widget.onChanged(_ratioFromLocal(d.localPosition.dx, box.size.width));
        },
        onHorizontalDragUpdate: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          widget.onChanged(_ratioFromLocal(d.localPosition.dx, box.size.width));
        },
        onHorizontalDragEnd: (_) {
          _dragging = false;
          widget.onChangeEnd?.call();
        },
        child: CustomPaint(
          painter: _SliderPainter(
            value: widget.value,
            trackHeight: widget.trackHeight,
            handleSize: (_hovering || _dragging)
                ? widget.handleSize
                : widget.handleSize * 0.7,
            activeColor: widget.activeColor,
            inactiveColor: widget.inactiveColor,
            chapters: widget.chapters,
          ),
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  final double value;
  final double trackHeight;
  final double handleSize;
  final Color activeColor;
  final Color inactiveColor;
  final List<double> chapters;

  _SliderPainter({
    required this.value,
    required this.trackHeight,
    required this.handleSize,
    required this.activeColor,
    required this.inactiveColor,
    this.chapters = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final pad = handleSize / 2;
    final trackWidth = size.width - handleSize;
    final trackLeft = pad;
    final trackRight = pad + trackWidth;
    final handleX = pad + trackWidth * value;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeCap = StrokeCap.round;
    final activePaint = Paint()
      ..color = activeColor
      ..strokeCap = StrokeCap.round;

    final trackRadius = trackHeight / 2;

    canvas.drawRRect(
      RRect.fromLTRBR(
        trackLeft, cy - trackRadius, trackRight, cy + trackRadius,
        Radius.circular(trackRadius),
      ),
      inactivePaint,
    );

    if (value > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          trackLeft, cy - trackRadius, handleX, cy + trackRadius,
          Radius.circular(trackRadius),
        ),
        activePaint,
      );
    }

    if (chapters.isNotEmpty) {
      final chapterPaint = Paint()
        ..color = const Color(0xAAFFFFFF)
        ..strokeWidth = 2;
      for (final ch in chapters) {
        final cx = pad + trackWidth * ch.clamp(0.0, 1.0);
        canvas.drawLine(Offset(cx, cy - 5), Offset(cx, cy + 5), chapterPaint);
      }
    }

    canvas.drawCircle(Offset(handleX, cy), handleSize / 2, activePaint);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      value != old.value ||
      trackHeight != old.trackHeight ||
      handleSize != old.handleSize ||
      activeColor != old.activeColor ||
      inactiveColor != old.inactiveColor ||
      chapters != old.chapters;
}

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovering
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Icon(widget.icon, color: Colors.white, size: widget.size * 0.6),
        ),
      ),
    );
  }
}

class _GalleryThumbsStrip extends StatelessWidget {
  final List<CachedMessage> messages;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GalleryThumbsStrip({
    required this.messages,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.length <= 1) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 2 * _kThumbStripPaddingH;
        final singleThumbSlot = _kThumbWidth + _kThumbGap;
        final maxSideThumbs = math.max(
          ((availableWidth / 2 - _kThumbWidthMax / 2 - _kThumbGapCurrent) / singleThumbSlot).floor(),
          1,
        );

        return SizedBox(
          height: _kThumbStripHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kThumbStripPaddingH),
              child: _ThumbRow(
                messages: messages,
                currentIndex: currentIndex,
                maxSideThumbs: maxSideThumbs,
                onTap: onTap,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThumbRow extends StatefulWidget {
  final List<CachedMessage> messages;
  final int currentIndex;
  final int maxSideThumbs;
  final ValueChanged<int> onTap;

  const _ThumbRow({
    required this.messages,
    required this.currentIndex,
    required this.maxSideThumbs,
    required this.onTap,
  });

  @override
  State<_ThumbRow> createState() => _ThumbRowState();
}

class _ThumbRowState extends State<_ThumbRow> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _prevIndex = 0;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: _kThumbAnimDuration,
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(_ThumbRow old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _prevIndex = old.currentIndex;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final startIdx = math.max(0, widget.currentIndex - widget.maxSideThumbs);
        final endIdx = math.min(widget.messages.length - 1, widget.currentIndex + widget.maxSideThumbs);

        final children = <Widget>[];
        for (int i = startIdx; i <= endIdx; i++) {
          final isCurrent = i == widget.currentIndex;
          final wasCurrent = i == _prevIndex;

          double width;
          if (isCurrent) {
            width = _kThumbWidth + (_kThumbWidthMax - _kThumbWidth) * t;
          } else if (wasCurrent) {
            width = _kThumbWidthMax - (_kThumbWidthMax - _kThumbWidth) * t;
          } else {
            width = _kThumbWidth;
          }

          if (i > startIdx) {
            final prevIsCurrent = (i - 1) == widget.currentIndex;
            final prevWasCurrent = (i - 1) == _prevIndex;
            final targetGap = (isCurrent || prevIsCurrent) ? _kThumbGapCurrent : _kThumbGap;
            final prevGap = (wasCurrent || prevWasCurrent) ? _kThumbGapCurrent : _kThumbGap;
            final gap = prevGap + (targetGap - prevGap) * t;
            children.add(SizedBox(width: gap));
          }

          children.add(
            _ThumbItem(
              message: widget.messages[i],
              width: width,
              isCurrent: isCurrent,
              onTap: () => widget.onTap(i),
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        );
      },
    );
  }
}

class _ThumbItem extends StatefulWidget {
  final CachedMessage message;
  final double width;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ThumbItem({
    required this.message,
    required this.width,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  State<_ThumbItem> createState() => _ThumbItemState();
}

class _ThumbItemState extends State<_ThumbItem> {
  Uint8List? _thumbBytes;
  String _lastB64 = '';

  @override
  void initState() {
    super.initState();
    _decodeThumb();
  }

  @override
  void didUpdateWidget(_ThumbItem old) {
    super.didUpdateWidget(old);
    if (widget.message.mediaThumbB64 != old.message.mediaThumbB64) {
      _decodeThumb();
    }
  }

  void _decodeThumb() {
    final b64 = widget.message.mediaThumbB64;
    if (b64.isNotEmpty && b64 != _lastB64) {
      try {
        _thumbBytes = base64Decode(b64);
        _lastB64 = b64;
      } catch (_) {
        _thumbBytes = null;
      }
    } else if (b64.isEmpty) {
      _thumbBytes = null;
      _lastB64 = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (widget.message.mediaLocalPath.isNotEmpty &&
        (widget.message.mediaType == 1 || widget.message.mediaType == 6)) {
      content = Image.file(
        File(widget.message.mediaLocalPath),
        fit: BoxFit.cover,
        width: widget.width,
        height: _kThumbStripHeight,
        cacheWidth: (widget.width * 2).toInt(),
        errorBuilder: (_, __, ___) => _thumbFallback(),
      );
    } else if (_thumbBytes != null) {
      content = Image.memory(
        _thumbBytes!,
        fit: BoxFit.cover,
        width: widget.width,
        height: _kThumbStripHeight,
        cacheWidth: (widget.width * 2).toInt(),
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      content = _placeholder();
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: _kThumbAnimDuration,
          width: widget.width,
          height: _kThumbStripHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.black26,
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _thumbFallback() {
    if (_thumbBytes != null) {
      return Image.memory(
        _thumbBytes!,
        fit: BoxFit.cover,
        width: widget.width,
        height: _kThumbStripHeight,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final iconData = switch (widget.message.mediaType) {
      2 || 5 => Icons.videocam,
      7 => Icons.gif,
      3 || 4 => Icons.audiotrack,
      8 => Icons.insert_drive_file,
      _ => Icons.image,
    };
    return Center(
      child: Icon(iconData, color: Colors.white38, size: 24),
    );
  }
}

class _SpeedBoostOverlay extends StatefulWidget {
  final bool active;
  const _SpeedBoostOverlay({required this.active});

  @override
  State<_SpeedBoostOverlay> createState() => _SpeedBoostOverlayState();
}

class _SpeedBoostOverlayState extends State<_SpeedBoostOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !widget.active) {
        setState(() => _visible = false);
      }
    });
    if (widget.active) {
      _visible = true;
      _anim.duration = const Duration(milliseconds: 150);
      _anim.forward();
    }
  }

  @override
  void didUpdateWidget(_SpeedBoostOverlay old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      setState(() => _visible = true);
      _anim.duration = const Duration(milliseconds: 150);
      _anim.forward();
    } else if (!widget.active && old.active) {
      _anim.duration = const Duration(milliseconds: 200);
      _anim.reverse();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final t = _anim.value;
        if (t <= 0) return const SizedBox.shrink();
        final scale = 0.6 + 0.4 * t;
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: t,
            child: child,
          ),
        );
      },
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xB2000000),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('2.0×', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              SizedBox(
                width: 16,
                height: 9,
                child: _SpeedBoostArrows(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedBoostArrows extends StatefulWidget {
  @override
  State<_SpeedBoostArrows> createState() => _SpeedBoostArrowsState();
}

class _SpeedBoostArrowsState extends State<_SpeedBoostArrows>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _phase = 0.0;
  Duration _lastTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = (_lastTime == Duration.zero)
        ? 0.016
        : (elapsed - _lastTime).inMicroseconds / 1000000.0;
    _lastTime = elapsed;
    _phase += dt * 1.5 * 2.0;
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArrowsPainter(phase: _phase),
    );
  }
}

class _ArrowsPainter extends CustomPainter {
  final double phase;
  _ArrowsPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    const arrowWidth = 7.0;
    const arrowHeight = 9.0;
    const arrowGap = 2.0;
    const arrowOverlap = 2.0;
    final arrowStep = arrowWidth + arrowGap - arrowOverlap; // 7
    final cy = size.height / 2.0;

    for (var i = 0; i < 2; i++) {
      final arrowPhase = phase + i * 0.17;
      final pulse = (math.sin(arrowPhase * math.pi) / 2.0) + 1.0;
      final alpha = (0.2 + 0.75 * pulse).clamp(0.0, 1.0);
      final ax = i * arrowStep;

      final path = Path()
        ..moveTo(ax, cy - arrowHeight / 2.0)
        ..lineTo(ax + arrowWidth, cy)
        ..lineTo(ax, cy + arrowHeight / 2.0)
        ..close();

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ArrowsPainter old) => old.phase != phase;
}


class _NavArea extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavArea({required this.icon, required this.onTap});

  @override
  State<_NavArea> createState() => _NavAreaState();
}

class _NavAreaState extends State<_NavArea> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: AnimatedOpacity(
            opacity: _hovering ? 1.0 : 0.3,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: _hovering ? 0.15 : 0.0),
              ),
              child: Icon(widget.icon, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _ViewerButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  State<_ViewerButton> createState() => _ViewerButtonState();
}

class _ViewerButtonState extends State<_ViewerButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return TelegramTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: 46,
            height: 54,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hovering
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.transparent,
                ),
                child: Icon(widget.icon, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  final bool isActive;

  const _TitleBarButton({
    required this.icon,
    required this.onTap,
    this.isClose = false,
    this.isActive = false,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    if (_hovering) {
      bgColor = widget.isClose
          ? const Color(0xFFE81123)
          : const Color(0x33FFFFFF);
    } else {
      bgColor = Colors.transparent;
    }
    final iconColor = _hovering && widget.isClose
        ? Colors.white
        : const Color(0xFFCCCCCC);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: _kTitleButtonWidth,
          height: _kTitleButtonHeight,
          color: bgColor,
          child: Center(
            child: Icon(widget.icon, color: iconColor, size: 18),
          ),
        ),
      ),
    );
  }
}

class _ProgressivePhoto extends StatefulWidget {
  final CachedMessage message;
  final double maxWidth;
  final double maxHeight;

  const _ProgressivePhoto({
    required this.message,
    required this.maxWidth,
    required this.maxHeight,
  });

  @override
  State<_ProgressivePhoto> createState() => _ProgressivePhotoState();
}

class _ProgressivePhotoState extends State<_ProgressivePhoto> {
  Uint8List? _thumbBytes;
  bool _fullImageReady = false;
  ImageProvider? _fullImageProvider;

  @override
  void initState() {
    super.initState();
    _decodeThumb();
    _preloadFull();
  }

  @override
  void didUpdateWidget(covariant _ProgressivePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.msgId != widget.message.msgId) {
      _fullImageReady = false;
      _fullImageProvider = null;
      _decodeThumb();
      _preloadFull();
    }
  }

  void _decodeThumb() {
    final b64 = widget.message.mediaThumbB64;
    if (b64.isNotEmpty) {
      try {
        _thumbBytes = base64Decode(b64);
      } catch (_) {
        _thumbBytes = null;
      }
    } else {
      _thumbBytes = null;
    }
  }

  void _preloadFull() {
    final path = widget.message.mediaLocalPath;
    if (path.isEmpty) return;
    final file = File(path);
    if (!file.existsSync()) return;
    final provider = FileImage(file);
    _fullImageProvider = provider;
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _fullImageReady = true);
        stream.removeListener(listener);
      },
      onError: (error, _) {
        if (mounted) setState(() => _fullImageReady = true);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  Size _fitSize() {
    final mw = widget.message.mediaWidth;
    final mh = widget.message.mediaHeight;
    if (mw <= 0 || mh <= 0) return Size(widget.maxWidth, widget.maxHeight);

    var w = mw.toDouble();
    var h = mh.toDouble();
    if (w > _kMaxDisplayImageSize) {
      h = h * _kMaxDisplayImageSize / w;
      w = _kMaxDisplayImageSize;
    }
    if (h > _kMaxDisplayImageSize) {
      w = w * _kMaxDisplayImageSize / h;
      h = _kMaxDisplayImageSize;
    }

    final scaleW = widget.maxWidth / w;
    final scaleH = widget.maxHeight / h;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    if (scale < 1.0) {
      w *= scale;
      h *= scale;
    }
    return Size(w, h);
  }

  @override
  Widget build(BuildContext context) {
    final size = _fitSize();

    if (_fullImageReady && _fullImageProvider != null) {
      return Image(
        image: _fullImageProvider!,
        width: size.width,
        height: size.height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildThumb(size),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        _buildThumb(size),
        if (!_fullImageReady && widget.message.mediaLocalPath.isNotEmpty)
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _kRadialBg,
            ),
            padding: const EdgeInsets.all(4),
            child: const CircularProgressIndicator(
              strokeWidth: 2.5,
              color: _kRadialFg,
            ),
          ),
      ],
    );
  }

  Widget _buildThumb(Size size) {
    if (_thumbBytes != null) {
      return Image.memory(
        _thumbBytes!,
        width: size.width,
        height: size.height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.low,
      );
    }
    return SizedBox(
      width: size.width,
      height: size.height,
      child: const Center(
        child: Icon(Icons.photo, color: Colors.white24, size: 64),
      ),
    );
  }
}

class PipOverlayWidget extends StatefulWidget {
  final Player player;
  final VideoController videoController;
  final List<StreamSubscription> playerSubs;
  final CachedMessage message;
  final List<CachedMessage> mediaMessages;
  final double initialVolume;
  final double initialSpeed;
  final Duration initialPosition;
  final Duration initialDuration;
  final bool initialPlaying;

  const PipOverlayWidget({
    super.key,
    required this.player,
    required this.videoController,
    required this.playerSubs,
    required this.message,
    required this.mediaMessages,
    required this.initialVolume,
    required this.initialSpeed,
    required this.initialPosition,
    required this.initialDuration,
    required this.initialPlaying,
  });

  @override
  State<PipOverlayWidget> createState() => _PipWidgetState();
}

class _PipWidgetState extends State<PipOverlayWidget>
    with TickerProviderStateMixin {
  late double _x;
  late double _y;
  late double _width;
  late double _height;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 0.8;
  bool _isSeeking = false;

  bool _isDragging = false;
  Offset _dragStart = Offset.zero;
  double _dragStartX = 0;
  double _dragStartY = 0;

  bool _isResizing = false;
  int _resizeEdge = 0;
  Offset _resizeStart = Offset.zero;
  double _resizeStartX = 0;
  double _resizeStartY = 0;
  double _resizeStartW = 0;
  double _resizeStartH = 0;

  bool _hovering = false;
  bool _trackHovering = false;
  bool _isBuffering = false;

  late final AnimationController _snapAnim;
  late final AnimationController _bufferSpinCtrl;
  double _snapFromX = 0, _snapFromY = 0;
  double _snapToX = 0, _snapToY = 0;

  List<StreamSubscription> _playerSubs = [];

  @override
  void initState() {
    super.initState();
    PipManager.instance._activeState = this;

    _width = _kPipDefaultSize;
    _height = _kPipDefaultSize;
    _x = 3 * _kPipBorderSkip; // 60px inner margin per spec
    _y = 3 * _kPipBorderSkip;

    _isPlaying = widget.initialPlaying;
    _position = widget.initialPosition;
    _duration = widget.initialDuration;
    _volume = widget.initialVolume;

    for (final sub in widget.playerSubs) {
      sub.cancel();
    }
    _playerSubs = [
      widget.player.stream.playing.listen((p) {
        if (mounted) setState(() => _isPlaying = p);
      }),
      widget.player.stream.position.listen((pos) {
        if (mounted && !_isSeeking) setState(() => _position = pos);
      }),
      widget.player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      }),
      widget.player.stream.buffering.listen((buffering) {
        if (mounted) {
          setState(() => _isBuffering = buffering);
          if (buffering) {
            _bufferSpinCtrl.repeat();
          } else {
            _bufferSpinCtrl.stop();
          }
        }
      }),
    ];

    _bufferSpinCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _snapAnim = AnimationController(
      duration: _kPipSnapDuration,
      vsync: this,
    )..addListener(() {
        final t = Curves.easeOutCirc.transform(_snapAnim.value);
        setState(() {
          _x = _snapFromX + (_snapToX - _snapFromX) * t;
          _y = _snapFromY + (_snapToY - _snapFromY) * t;
        });
      });

    _loadPipGeometry();
  }

  @override
  void dispose() {
    if (PipManager.instance._activeState == this) {
      PipManager.instance._activeState = null;
    }
    _bufferSpinCtrl.dispose();
    _snapAnim.dispose();
    for (final sub in _playerSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  void _disposePlayer() {
    for (final sub in _playerSubs) {
      sub.cancel();
    }
    _playerSubs = [];
    widget.player.dispose();
  }

  void _detachPlayer() {
    for (final sub in _playerSubs) {
      sub.cancel();
    }
    _playerSubs = [];
  }

  String get _prefsPath {
    try {
      final appState = context.read<AppState>();
      final dir = appState.configDir;
      return dir.isEmpty ? '' : '$dir/pip_geometry.json';
    } catch (_) {
      return '';
    }
  }

  void _loadPipGeometry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final path = _prefsPath;
      if (path.isEmpty) return;
      try {
        final file = File(path);
        if (!file.existsSync()) return;
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        setState(() {
          _x = (data['x'] as num?)?.toDouble() ?? _kPipBorderSkip;
          _y = (data['y'] as num?)?.toDouble() ?? _kPipBorderSkip;
          _width = (data['w'] as num?)?.toDouble() ?? _kPipDefaultSize;
          _height = (data['h'] as num?)?.toDouble() ?? _kPipDefaultSize;
        });
      } catch (_) {}
    });
  }

  void _savePipGeometry() {
    final path = _prefsPath;
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(jsonEncode({
        'x': _x, 'y': _y, 'w': _width, 'h': _height,
      }));
    } catch (_) {}
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      widget.player.pause();
    } else {
      widget.player.play();
    }
  }

  void _toggleMute() {
    if (_volume > 0) {
      setState(() => _volume = 0);
      widget.player.setVolume(0);
    } else {
      setState(() => _volume = 0.8);
      widget.player.setVolume(80);
    }
  }

  void _close() {
    _savePipGeometry();
    PipManager.instance.dismiss();
  }

  void _enlarge() {
    _savePipGeometry();
    PipManager.instance._enlarge(context);
  }

  Offset _snapPosition(double x, double y, Size screen) {
    double sx = x, sy = y;
    const snapMargin = _kPipBorderSkip;
    const maxSizeMargin = 3 * _kPipBorderSkip;

    if (x >= -_kPipBorderSnapArea && x < _kPipBorderSnapArea) {
      sx = snapMargin;
    } else if ((x + _width) >= screen.width - _kPipBorderSnapArea &&
        (x + _width) < screen.width + _kPipBorderSnapArea) {
      sx = screen.width - _width - snapMargin;
    }

    if (y >= -_kPipBorderSnapArea && y < _kPipBorderSnapArea) {
      sy = snapMargin;
    } else if ((y + _height) >= screen.height - _kPipBorderSnapArea &&
        (y + _height) < screen.height + _kPipBorderSnapArea) {
      sy = screen.height - _height - snapMargin;
    }

    final maxX = (screen.width - _width - snapMargin).clamp(0.0, double.infinity);
    final maxY = (screen.height - _height - snapMargin).clamp(0.0, double.infinity);
    sx = sx.clamp(snapMargin, maxX);
    sy = sy.clamp(snapMargin, maxY);
    return Offset(sx, sy);
  }

  int _hitTestEdge(Offset local) {
    int edge = 0;
    if (local.dx < _kPipResizeArea) edge |= 1;
    if (local.dx > _width - _kPipResizeArea) edge |= 2;
    if (local.dy < _kPipResizeArea) edge |= 4;
    if (local.dy > _height - _kPipResizeArea) edge |= 8;
    return edge;
  }

  MouseCursor _cursorForEdge(int edge) {
    if (edge == (1 | 4) || edge == (2 | 8)) return SystemMouseCursors.resizeUpLeftDownRight;
    if (edge == (2 | 4) || edge == (1 | 8)) return SystemMouseCursors.resizeUpRightDownLeft;
    if (edge == 1 || edge == 2) return SystemMouseCursors.resizeLeftRight;
    if (edge == 4 || edge == 8) return SystemMouseCursors.resizeUpDown;
    return SystemMouseCursors.basic;
  }

  String _formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Positioned(
      left: _x,
      top: _y,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() {
          _hovering = false;
          _trackHovering = false;
        }),
        child: GestureDetector(
          onPanStart: (d) {
            final local = d.localPosition;
            final edge = _hitTestEdge(local);
            if (edge != 0) {
              _isResizing = true;
              _resizeEdge = edge;
              _resizeStart = d.globalPosition;
              _resizeStartX = _x;
              _resizeStartY = _y;
              _resizeStartW = _width;
              _resizeStartH = _height;
            } else {
              _isDragging = true;
              _dragStart = d.globalPosition;
              _dragStartX = _x;
              _dragStartY = _y;
              _snapAnim.stop();
            }
          },
          onPanUpdate: (d) {
            if (_isResizing) {
              _handleResize(d.globalPosition, screen);
            } else if (_isDragging) {
              setState(() {
                _x = _dragStartX + (d.globalPosition.dx - _dragStart.dx);
                _y = _dragStartY + (d.globalPosition.dy - _dragStart.dy);
              });
            }
          },
          onPanEnd: (_) {
            if (_isDragging) {
              _isDragging = false;
              final snapped = _snapPosition(_x, _y, screen);
              if ((snapped.dx - _x).abs() > 0.5 ||
                  (snapped.dy - _y).abs() > 0.5) {
                _snapFromX = _x;
                _snapFromY = _y;
                _snapToX = snapped.dx;
                _snapToY = snapped.dy;
                _snapAnim.forward(from: 0);
              }
              _savePipGeometry();
            }
            if (_isResizing) {
              _isResizing = false;
              _savePipGeometry();
            }
          },
          child: Container(
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: widget.videoController,
                  fill: Colors.black,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                ),
                if (_isBuffering)
                  Center(
                    child: AnimatedBuilder(
                      animation: _bufferSpinCtrl,
                      builder: (context, _) => _RadialSpinner(animation: _bufferSpinCtrl),
                    ),
                  ),
                AnimatedOpacity(
                    opacity: _hovering ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Stack(
                      children: [
                        Container(color: const Color(0x44000000)),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PipButton(
                                icon: Icons.open_in_full,
                                onTap: _enlarge,
                                tooltip: 'Enlarge',
                              ),
                              const SizedBox(width: 2),
                              _PipButton(
                                icon: Icons.close,
                                onTap: _close,
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                        ),
                        Center(
                          child: GestureDetector(
                            onTap: _togglePlayPause,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0x66000000),
                              ),
                              child: Icon(
                                _isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: _PipButton(
                            icon: _volume > 0
                                ? Icons.volume_up
                                : Icons.volume_off,
                            onTap: _toggleMute,
                            tooltip: _volume > 0 ? 'Mute' : 'Unmute',
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _trackHovering = true),
                            onExit: (_) => setState(() => _trackHovering = false),
                            child: GestureDetector(
                              onTapDown: (d) {
                                final ratio = (d.localPosition.dx / _width).clamp(0.0, 1.0);
                                if (_duration.inMilliseconds == 0) return;
                                setState(() {
                                  _isSeeking = true;
                                  _position = Duration(
                                    milliseconds: (ratio * _duration.inMilliseconds).round(),
                                  );
                                });
                                widget.player.seek(_position);
                                setState(() => _isSeeking = false);
                              },
                              onHorizontalDragUpdate: (d) {
                                final ratio = (d.localPosition.dx / _width).clamp(0.0, 1.0);
                                if (_duration.inMilliseconds == 0) return;
                                setState(() {
                                  _isSeeking = true;
                                  _position = Duration(
                                    milliseconds: (ratio * _duration.inMilliseconds).round(),
                                  );
                                });
                                widget.player.seek(_position);
                              },
                              onHorizontalDragEnd: (_) =>
                                  setState(() => _isSeeking = false),
                              child: Container(
                                height: _trackHovering ? _kPipTrackHeightHover : _kPipTrackHeight,
                                color: Colors.transparent,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    height: _trackHovering ? _kPipTrackHeightHover : _kPipTrackHeight,
                                    child: Row(
                                      children: [
                                        Flexible(
                                          flex: (progress * 1000).round().clamp(0, 1000),
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(2),
                                                bottomLeft: Radius.circular(2),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Flexible(
                                          flex: ((1 - progress) * 1000).round().clamp(0, 1000),
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Color(0x66FFFFFF),
                                              borderRadius: BorderRadius.only(
                                                topRight: Radius.circular(2),
                                                bottomRight: Radius.circular(2),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleResize(Offset global, Size screen) {
    final dx = global.dx - _resizeStart.dx;
    final dy = global.dy - _resizeStart.dy;
    double newX = _resizeStartX;
    double newY = _resizeStartY;
    double newW = _resizeStartW;
    double newH = _resizeStartH;

    if (_resizeEdge & 1 != 0) {
      newW = (_resizeStartW - dx).clamp(_kPipMinimalSize, screen.width - _kPipBorderSkip * 2);
      newX = _resizeStartX + (_resizeStartW - newW);
    }
    if (_resizeEdge & 2 != 0) {
      newW = (_resizeStartW + dx).clamp(_kPipMinimalSize, screen.width - _resizeStartX - _kPipBorderSkip);
    }
    if (_resizeEdge & 4 != 0) {
      newH = (_resizeStartH - dy).clamp(_kPipMinimalSize, screen.height - _kPipBorderSkip * 2);
      newY = _resizeStartY + (_resizeStartH - newH);
    }
    if (_resizeEdge & 8 != 0) {
      newH = (_resizeStartH + dy).clamp(_kPipMinimalSize, screen.height - _resizeStartY - _kPipBorderSkip);
    }

    setState(() {
      _x = newX;
      _y = newY;
      _width = newW;
      _height = newH;
    });
  }
}

class _RadialSpinner extends StatelessWidget {
  final AnimationController animation;
  const _RadialSpinner({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _kRadialBg,
      ),
      padding: const EdgeInsets.all(4),
      child: CustomPaint(
        painter: _RadialSpinPainter(
          rotation: animation.value * 2 * math.pi,
        ),
      ),
    );
  }
}

class _RadialSpinPainter extends CustomPainter {
  final double rotation;
  _RadialSpinPainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - 2.5) / 2;
    final paint = Paint()
      ..color = _kRadialFg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      rotation - math.pi / 2,
      math.pi * 0.75,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RadialSpinPainter old) => old.rotation != rotation;
}

class _PipButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _PipButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  State<_PipButton> createState() => _PipButtonState();
}

class _PipButtonState extends State<_PipButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return TelegramTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovering
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.1),
            ),
            child: Icon(widget.icon, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Stories Viewer — §20.17
// Aspect-fit content in 540×960, 8px radius, sibling previews,
// controls always visible, no zoom/rotation, collapsible captions.
// ═══════════════════════════════════════════════════════════════════════

const _kStoriesMaxWidth = 540.0;
const _kStoriesMaxHeight = 960.0;
const _kStoriesRadius = 8.0;
const _kStoriesProgressHeight = 2.0;
const _kStoriesProgressGap = 4.0;
const _kStoriesProgressPadding = EdgeInsets.fromLTRB(8, 7, 8, 6);
const _kStoriesCaptionMaxLines = 2;
const _kStoriesCaptionPadding = EdgeInsets.fromLTRB(11, 6, 11, 6);
const _kStoriesCaptionMinWidth = 36.0;
const _kStoriesCaptionPullThreshold = 50.0;
const _kStoriesCaptionAnimDuration = Duration(milliseconds: 300);
const _kSiblingWidthRatio = 0.448;
const _kSiblingMinWidth = 200.0;
const _kSiblingFade = 0.5;
const _kSiblingFadeOver = 0.4;
const _kSiblingScaleOver = 0.05;
const _kSiblingUserpicRatio = 0.3;
const _kSiblingOutsidePart = 0.24;
const _kOpacityActive = 1.0;
const _kOpacityInactive = 0.4;
const _kHeaderOutsideHeight = 48.0;
const _kPhotoDuration = Duration(seconds: 5);
const _kFullContentFade = 0.6;
const _kGoodFadeDuration = Duration(milliseconds: 200);
const _kMaxSegmentsCount = 180;

// §32.7 Story Repost View
const _kStoryRepostBg = Color(0x40000000);
const _kStoryRepostSimpleRadius = 10.0;
const _kStoryRepostSimplePadding = EdgeInsets.fromLTRB(8, 2, 8, 2);
const _kStoryRepostQuoteBarWidth = 2.0;
const _kStoryRepostQuoteRadius = 4.0;
const _kStoryRepostQuotePadding = EdgeInsets.fromLTRB(8, 4, 8, 4);
const _kStoryRepostMaxWidth = 200.0;

// §32.5 Story Reply Compose
const _kStoryComposeBg = Color(0xFF2C333D);
const _kStoryComposeBgHover = Color(0xFF323A45);
const _kStoryComposeRadius = 21.0;
const _kStoryComposeFieldMinH = 36.0;
const _kStoryComposeFieldMaxH = 72.0;
const _kStoryComposeButtonSize = 42.0;
const _kStoryComposeGrayText = Color(0xFF8E9BA7);
const _kStoryComposeWhiteText = Color(0xFFFFFFFF);
const _kStoryComposeBlue = Color(0xFF4DB8FF);
const _kStoryComposeMinWidth = 280.0;
const _kStoryComposeBottomSkip = 6.0;
const _kStoryComposePadding = EdgeInsets.fromLTRB(1, 8, 1, 6);
const _kStoryComposeFieldLeft = 10.0;
const _kStoryComposeCommentsUnreadSize = 6.0;

// §32.13 Story Interactive Areas
const _kStoryAreaBg = Color(0x40000000);
const _kStoryAreaBgHover = Color(0x60000000);
const _kStoryAreaRadius = 10.0;
const _kStoryAreaLocationIcon = Icons.location_on;
const _kStoryAreaLinkIcon = Icons.link;
const _kStoryAreaChannelIcon = Icons.campaign;
const _kStoryWeatherFontSize = 14.0;
const _kStoryReactionBubbleSize = 48.0;

// §32.4 Story Reactions Panel
const _kStoryReactionsWidth = 210.0;
const _kStoryReactionsExpandedWidth = 420.0;
const _kStoryReactionsBottomSkip = 29.0;
const _kStoryLikeSize = 42.0;
const _kStoryReactionScaleOutDuration = Duration(milliseconds: 1000);
const _kStoryReactionScaleOutTarget = 0.7;
const _kStoryBubbleBigTailDiameter = 0.264;
const _kStoryBubbleBigTailOffset = 0.464;
const _kStoryBubbleBigTailRotation = -42.29;
const _kStoryBubbleSmallTailDiameter = 0.110;
const _kStoryBubbleSmallTailOffset = 0.697;
const _kStoryBubbleSmallTailRotation = -40.87;
const _kStoryReactionsFallback = ['❤️', '🔥', '👍', '😱', '🎉', '😢', '👏'];

class _ReactionBubblePainter extends CustomPainter {
  final Color color;

  _ReactionBubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = size.width / 2;
    canvas.drawCircle(Offset(r, r), r, paint);

    final bigR = size.width * _kStoryBubbleBigTailDiameter / 2;
    final bigDist = size.width * _kStoryBubbleBigTailOffset;
    const bigAngle = _kStoryBubbleBigTailRotation * math.pi / 180;
    canvas.drawCircle(
      Offset(r + bigDist * math.cos(bigAngle), r + bigDist * math.sin(bigAngle)),
      bigR,
      paint,
    );

    final smallR = size.width * _kStoryBubbleSmallTailDiameter / 2;
    final smallDist = size.width * _kStoryBubbleSmallTailOffset;
    const smallAngle = _kStoryBubbleSmallTailRotation * math.pi / 180;
    canvas.drawCircle(
      Offset(r + smallDist * math.cos(smallAngle), r + smallDist * math.sin(smallAngle)),
      smallR,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ReactionBubblePainter old) => old.color != color;
}

// §32.13 Story Interactive Areas
class _StoryInteractiveAreas extends StatelessWidget {
  final List<StoryMediaArea> areas;
  final double contentWidth;
  final double contentHeight;
  final ValueChanged<String> onReaction;
  final ValueChanged<String> onUrl;
  final void Function(int channelId, int msgId) onChannelPost;

  const _StoryInteractiveAreas({
    required this.areas,
    required this.contentWidth,
    required this.contentHeight,
    required this.onReaction,
    required this.onUrl,
    required this.onChannelPost,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final area in areas)
          _buildArea(context, area),
      ],
    );
  }

  Widget _buildArea(BuildContext context, StoryMediaArea area) {
    final c = area.coords;
    final cx = c.x / 100.0 * contentWidth;
    final cy = c.y / 100.0 * contentHeight;
    final aw = c.w / 100.0 * contentWidth;
    final ah = c.h / 100.0 * contentHeight;
    final left = cx - aw / 2;
    final top = cy - ah / 2;
    final radius = c.radius > 0
        ? c.radius / 100.0 * contentWidth
        : _kStoryAreaRadius;

    Widget child;
    switch (area.type) {
      case StoryMediaAreaType.venue:
      case StoryMediaAreaType.location:
        child = _LocationChip(area: area, radius: radius);
      case StoryMediaAreaType.reaction:
        child = _ReactionArea(area: area, onReaction: onReaction);
      case StoryMediaAreaType.channelPost:
        child = _ChannelPostChip(area: area, radius: radius, onTap: onChannelPost);
      case StoryMediaAreaType.url:
        child = _UrlChip(area: area, radius: radius, onTap: onUrl);
      case StoryMediaAreaType.weather:
        child = _WeatherChip(area: area, radius: radius);
      case StoryMediaAreaType.unknown:
        return const SizedBox.shrink();
    }

    Widget positioned = Positioned(
      left: left,
      top: top,
      width: aw,
      height: ah,
      child: c.rotation != 0
          ? Transform.rotate(
              angle: c.rotation * math.pi / 180,
              child: child,
            )
          : child,
    );
    return positioned;
  }
}

class _LocationChip extends StatefulWidget {
  final StoryMediaArea area;
  final double radius;
  const _LocationChip({required this.area, required this.radius});

  @override
  State<_LocationChip> createState() => _LocationChipState();
}

class _LocationChipState extends State<_LocationChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.area.title.isNotEmpty
        ? widget.area.title
        : widget.area.address.isNotEmpty
            ? widget.area.address
            : 'Location';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final lat = widget.area.lat;
          final lng = widget.area.lng;
          if (lat != 0 || lng != 0) {
            url_launcher.launchUrl(
              Uri.parse('https://maps.google.com/?q=$lat,$lng'),
              mode: url_launcher.LaunchMode.externalApplication,
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? _kStoryAreaBgHover : _kStoryAreaBg,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(_kStoryAreaLocationIcon, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionArea extends StatefulWidget {
  final StoryMediaArea area;
  final ValueChanged<String> onReaction;
  const _ReactionArea({required this.area, required this.onReaction});

  @override
  State<_ReactionArea> createState() => _ReactionAreaState();
}

class _ReactionAreaState extends State<_ReactionArea>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emoji = widget.area.reaction;
    if (emoji.isEmpty) return const SizedBox.shrink();

    final isCustomEmoji = emoji.startsWith('custom:');
    final dark = widget.area.dark;
    final flipped = widget.area.flipped;
    final bgColor = dark ? const Color(0x80000000) : const Color(0x40FFFFFF);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _scaleCtrl.forward(from: 0);
          widget.onReaction(emoji);
        },
        child: AnimatedBuilder(
          animation: _scaleAnim,
          builder: (context, child) {
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scale(
                  flipped ? -_scaleAnim.value : _scaleAnim.value,
                  _scaleAnim.value,
                ),
              child: child,
            );
          },
          child: CustomPaint(
            painter: _ReactionBubblePainter(
              color: _hovered
                  ? bgColor.withValues(alpha: bgColor.a / 255 + 0.15)
                  : bgColor,
            ),
            child: Center(
              child: isCustomEmoji
                  ? Icon(
                      Icons.emoji_emotions,
                      size: _kStoryReactionBubbleSize * 0.45,
                      color: dark ? Colors.white70 : Colors.black54,
                    )
                  : Text(
                      emoji,
                      style: TextStyle(fontSize: _kStoryReactionBubbleSize * 0.5),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelPostChip extends StatefulWidget {
  final StoryMediaArea area;
  final double radius;
  final void Function(int channelId, int msgId) onTap;
  const _ChannelPostChip({
    required this.area,
    required this.radius,
    required this.onTap,
  });

  @override
  State<_ChannelPostChip> createState() => _ChannelPostChipState();
}

class _ChannelPostChipState extends State<_ChannelPostChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onTap(widget.area.channelId, widget.area.msgId),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? _kStoryAreaBgHover : _kStoryAreaBg,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_kStoryAreaChannelIcon, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Flexible(
                child: Text(
                  'View Post',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrlChip extends StatefulWidget {
  final StoryMediaArea area;
  final double radius;
  final ValueChanged<String> onTap;
  const _UrlChip({
    required this.area,
    required this.radius,
    required this.onTap,
  });

  @override
  State<_UrlChip> createState() => _UrlChipState();
}

class _UrlChipState extends State<_UrlChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.area.url);
    final label = uri?.host ?? widget.area.url;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onTap(widget.area.url),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? _kStoryAreaBgHover : _kStoryAreaBg,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(_kStoryAreaLinkIcon, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  final StoryMediaArea area;
  final double radius;
  const _WeatherChip({required this.area, required this.radius});

  @override
  Widget build(BuildContext context) {
    final tempC = area.tempC;
    final tempStr = '${tempC.round()}°';
    final argb = area.color;
    final bgColor = Color(argb == 0 ? 0x60000000 : argb);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (area.emoji.isNotEmpty) ...[
            Text(
              area.emoji,
              style: const TextStyle(fontSize: _kStoryWeatherFontSize),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            tempStr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: _kStoryWeatherFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// §32.7 Story Repost View
class _StoryRepostView extends StatelessWidget {
  final StoryItem story;
  final bool useQuoteStyle;
  final VoidCallback? onTap;

  const _StoryRepostView({
    required this.story,
    this.useQuoteStyle = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!story.isRepost) return const SizedBox.shrink();

    final name = story.fwdFromName.isNotEmpty
        ? story.fwdFromName
        : 'Reposted Story';
    final subtitle = story.fwdModified ? 'Modified' : 'Reposted';

    if (useQuoteStyle) {
      return _buildQuoteVariant(name, subtitle);
    }
    return _buildSimpleVariant(name, subtitle);
  }

  Widget _buildSimpleVariant(String name, String subtitle) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: _kStoryRepostMaxWidth),
        padding: _kStoryRepostSimplePadding,
        decoration: BoxDecoration(
          color: _kStoryRepostBg,
          borderRadius: BorderRadius.circular(_kStoryRepostSimpleRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuoteVariant(String name, String subtitle) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: _kStoryRepostMaxWidth),
        padding: _kStoryRepostQuotePadding,
        decoration: BoxDecoration(
          color: _kStoryRepostBg,
          borderRadius: BorderRadius.circular(_kStoryRepostQuoteRadius),
          border: const Border(
            left: BorderSide(
              color: Colors.white70,
              width: _kStoryRepostQuoteBarWidth,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryReactionsPanel extends StatefulWidget {
  final ValueChanged<String> onReaction;
  final VoidCallback onLike;
  final bool isLiked;

  const _StoryReactionsPanel({
    required this.onReaction,
    required this.onLike,
    this.isLiked = false,
  });

  @override
  State<_StoryReactionsPanel> createState() => _StoryReactionsPanelState();
}

class _StoryReactionsPanelState extends State<_StoryReactionsPanel>
    with TickerProviderStateMixin {
  bool _expanded = false;
  int _hoveredIndex = -1;
  int _flyingIndex = -1;
  AnimationController? _flyController;
  late final AnimationController _expandController;
  late final Animation<double> _expandAnim;
  late final AnimationController _scaleOutController;
  late final Animation<double> _scaleOutAnim;
  bool _likeHovered = false;
  List<String> _reactions = List.from(_kStoryReactionsFallback);

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnim = CurvedAnimation(parent: _expandController, curve: Curves.easeOutCubic);
    _scaleOutController = AnimationController(
      vsync: this,
      duration: _kStoryReactionScaleOutDuration,
    );
    _scaleOutAnim = Tween<double>(begin: 1.0, end: _kStoryReactionScaleOutTarget)
        .animate(CurvedAnimation(parent: _scaleOutController, curve: Curves.easeOut));
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    try {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      final accountId = appState.activeAccountId;
      if (accountId.isEmpty) return;
      final reactions = await engine.getAvailableReactions(accountId);
      if (reactions.isNotEmpty && mounted) {
        setState(() => _reactions = reactions.length > 7 ? reactions.sublist(0, 7) : reactions);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _flyController?.dispose();
    _expandController.dispose();
    _scaleOutController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  void _triggerReaction(int index) {
    _flyController?.dispose();
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    setState(() => _flyingIndex = index);
    _scaleOutController.forward(from: 0.0);
    _flyController!.forward().then((_) {
      if (mounted) {
        widget.onReaction(_reactions[index]);
        setState(() {
          _flyingIndex = -1;
          _expanded = false;
        });
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedBuilder(
          animation: _expandAnim,
          builder: (context, child) {
            final w = _kStoryReactionsWidth +
                (_kStoryReactionsExpandedWidth - _kStoryReactionsWidth) * _expandAnim.value;
            if (_expandAnim.value == 0 && !_expanded) {
              return const SizedBox.shrink();
            }
            return Opacity(
              opacity: _expandAnim.value,
              child: Container(
                width: w,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_reactions.length, (i) {
                      final isFlying = _flyingIndex == i;
                      final isHovered = _hoveredIndex == i;
                      final baseScale = isFlying
                          ? _scaleOutAnim.value
                          : isHovered
                              ? 1.3
                              : 1.0;
                      return MouseRegion(
                        onEnter: (_) => setState(() => _hoveredIndex = i),
                        onExit: (_) => setState(() => _hoveredIndex = -1),
                        child: GestureDetector(
                          onTap: () => _triggerReaction(i),
                          child: AnimatedBuilder(
                            animation: _scaleOutController,
                            builder: (context, _) {
                              return Transform.scale(
                                scale: isFlying ? _scaleOutAnim.value : baseScale,
                                child: AnimatedScale(
                                  scale: isHovered && !isFlying ? 1.3 : 1.0,
                                  duration: const Duration(milliseconds: 150),
                                  child: SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Center(
                                      child: isFlying
                                          ? AnimatedBuilder(
                                              animation: _flyController!,
                                              builder: (context, _) {
                                                return Transform.translate(
                                                  offset: Offset(0, -40 * _flyController!.value),
                                                  child: Opacity(
                                                    opacity: 1.0 - _flyController!.value,
                                                    child: CustomPaint(
                                                      size: const Size(32, 32),
                                                      painter: _ReactionBubblePainter(
                                                        color: const Color(0x55FFFFFF),
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          _reactions[i],
                                                          style: const TextStyle(fontSize: 22),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            )
                                          : Text(
                                              _reactions[i],
                                              style: const TextStyle(fontSize: 22),
                                            ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        ),
        MouseRegion(
          onEnter: (_) => setState(() => _likeHovered = true),
          onExit: (_) => setState(() => _likeHovered = false),
          child: GestureDetector(
            onTap: widget.onLike,
            onLongPress: _toggleExpanded,
            child: SizedBox(
              width: _kStoryLikeSize,
              height: _kStoryLikeSize,
              child: Center(
                child: AnimatedScale(
                  scale: _likeHovered ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    widget.isLiked ? Icons.favorite : Icons.favorite_border,
                    color: widget.isLiked
                        ? const Color(0xFFFF3B30)
                        : Colors.white.withValues(alpha: _likeHovered ? 1.0 : 0.7),
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// §32.5 Story Reply Compose
class _StoryReplyCompose extends StatefulWidget {
  final VoidCallback onFocusChanged;
  final bool isLiked;
  final VoidCallback onLike;
  final void Function(String emoji) onReaction;
  final void Function(String text)? onSend;
  final void Function(List<String> paths)? onAttach;

  const _StoryReplyCompose({
    super.key,
    required this.onFocusChanged,
    required this.isLiked,
    required this.onLike,
    required this.onReaction,
    this.onSend,
    this.onAttach,
  });

  @override
  State<_StoryReplyCompose> createState() => _StoryReplyComposeState();
}

class _StoryReplyComposeState extends State<_StoryReplyCompose> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _attachHovered = false;
  bool _emojiHovered = false;
  bool _sendHovered = false;
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    _focusNode.addListener(() => widget.onFocusChanged());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get hasFocus => _focusNode.hasFocus;

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    _controller.clear();
  }

  void _handleAttach() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
    if (paths.isNotEmpty) widget.onAttach?.call(paths);
  }

  void _handleEmoji() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showEmojiPicker)
          Container(
            constraints: const BoxConstraints(maxHeight: 250, maxWidth: 360),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xE6222222),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: EmojiTabbedPanel(
              visible: true,
              onHide: () => setState(() => _showEmojiPicker = false),
              onEmojiSelected: _insertEmoji,
            ),
          ),
        Container(
          constraints: const BoxConstraints(minWidth: _kStoryComposeMinWidth),
          padding: _kStoryComposePadding,
          decoration: BoxDecoration(
            color: _kStoryComposeBg,
            borderRadius: BorderRadius.circular(_kStoryComposeRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildButton(
                icon: Icons.attach_file,
                hovered: _attachHovered,
                onHover: (h) => setState(() => _attachHovered = h),
                onTap: _handleAttach,
              ),
              const SizedBox(width: _kStoryComposeFieldLeft - 1),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: _kStoryComposeFieldMinH,
                    maxHeight: _kStoryComposeFieldMaxH,
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    style: const TextStyle(
                      color: _kStoryComposeWhiteText,
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Reply to story...',
                      hintStyle: TextStyle(
                        color: _kStoryComposeGrayText,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                      isDense: true,
                    ),
                    cursorColor: _kStoryComposeBlue,
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
              ),
              if (_hasText)
                _buildButton(
                  icon: Icons.send,
                  hovered: _sendHovered,
                  onHover: (h) => setState(() => _sendHovered = h),
                  onTap: _handleSend,
                  color: _kStoryComposeBlue,
                )
              else ...[
                _buildButton(
                  icon: Icons.emoji_emotions_outlined,
                  hovered: _emojiHovered,
                  onHover: (h) => setState(() => _emojiHovered = h),
                  onTap: _handleEmoji,
                ),
                _StoryReactionsPanel(
                  isLiked: widget.isLiked,
                  onLike: widget.onLike,
                  onReaction: widget.onReaction,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButton({
    required IconData icon,
    required bool hovered,
    required ValueChanged<bool> onHover,
    required VoidCallback onTap,
    Color? color,
  }) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _kStoryComposeButtonSize,
          height: _kStoryComposeButtonSize,
          child: Center(
            child: Icon(
              icon,
              color: color ?? Colors.white.withValues(alpha: hovered ? 1.0 : 0.7),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class StoriesViewer extends StatefulWidget {
  final List<StoryItem> stories;
  final int initialIndex;
  final String peerName;
  final String? peerAvatarPath;
  final bool isOwnStory;
  final String peerId;

  const StoriesViewer({
    super.key,
    required this.stories,
    this.initialIndex = 0,
    this.peerName = '',
    this.peerAvatarPath,
    this.isOwnStory = false,
    this.peerId = '',
  });

  static void open(
    BuildContext context, {
    required List<StoryItem> stories,
    int initialIndex = 0,
    String peerName = '',
    String? peerAvatarPath,
    bool isOwnStory = false,
    String peerId = '',
  }) {
    if (stories.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.linear)),
            child: StoriesViewer(
              stories: stories,
              initialIndex: initialIndex,
              peerName: peerName,
              peerAvatarPath: peerAvatarPath,
              isOwnStory: isOwnStory,
              peerId: peerId,
            ),
          );
        },
      ),
    );
  }

  @override
  State<StoriesViewer> createState() => _StoriesViewerState();
}

class _StoriesViewerState extends State<StoriesViewer>
    with TickerProviderStateMixin {
  late int _currentIndex;
  bool _captionExpanded = false;
  late final AnimationController _captionAnim;
  double _captionPullDy = 0.0;
  late final FocusNode _focusNode;
  bool _paused = false;
  bool _leftSiblingHovered = false;
  bool _rightSiblingHovered = false;
  bool _muted = false;
  bool _playHovered = false;
  bool _volumeHovered = false;
  bool _closeHovered = false;
  bool _stealthHovered = false;
  bool _liked = false;
  final GlobalKey<_StoryReplyComposeState> _composeKey = GlobalKey();
  bool _composeFocused = false;

  Player? _videoPlayer;
  VideoController? _videoController;
  final List<StreamSubscription> _playerSubs = [];
  Duration _videoPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  bool _videoPlaying = false;

  late final AnimationController _storyTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _focusNode = FocusNode();
    _captionAnim = AnimationController(
      vsync: this,
      duration: _kStoriesCaptionAnimDuration,
    );
    _storyTimer = AnimationController(
      vsync: this,
      duration: _kPhotoDuration,
    );
    _storyTimer.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goToNext();
      }
    });
    _loadStory();
  }

  @override
  void dispose() {
    _storyTimer.dispose();
    _captionAnim.dispose();
    _focusNode.dispose();
    _disposeVideo();
    super.dispose();
  }

  void _disposeVideo() {
    for (final sub in _playerSubs) { sub.cancel(); }
    _playerSubs.clear();
    _videoPlayer?.dispose();
    _videoPlayer = null;
    _videoController = null;
  }

  StoryItem get _current => widget.stories[_currentIndex];

  void _loadStory() {
    _disposeVideo();
    _captionExpanded = false;
    _captionAnim.value = 0.0;
    _captionPullDy = 0.0;
    _storyTimer.reset();

    if (_current.isVideo && _current.hasMedia) {
      final player = Player();
      final controller = VideoController(player);
      _videoPlayer = player;
      _videoController = controller;

      _playerSubs.add(player.stream.position.listen((p) {
        if (mounted) setState(() => _videoPosition = p);
      }));
      _playerSubs.add(player.stream.duration.listen((d) {
        if (mounted) setState(() => _videoDuration = d);
      }));
      _playerSubs.add(player.stream.playing.listen((p) {
        if (mounted) setState(() => _videoPlaying = p);
      }));
      _playerSubs.add(player.stream.completed.listen((c) {
        if (c && mounted) _goToNext();
      }));

      player.open(Media('file://${_current.localPath}'));
    } else {
      _storyTimer.forward();
    }
    if (mounted) setState(() {});
  }

  void _pausePlayback() {
    if (_paused) return;
    _paused = true;
    if (_current.isVideo && _videoPlayer != null) {
      _videoPlayer!.pause();
    } else {
      _storyTimer.stop();
    }
    setState(() {});
  }

  void _resumePlayback() {
    if (!_paused) return;
    _paused = false;
    if (_current.isVideo && _videoPlayer != null) {
      _videoPlayer!.play();
    } else {
      _storyTimer.forward();
    }
    setState(() {});
  }

  void _togglePause() {
    if (_paused) {
      _resumePlayback();
    } else {
      _pausePlayback();
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.stories.length - 1) {
      _paused = false;
      setState(() => _currentIndex++);
      _loadStory();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _goToPrev() {
    if (_currentIndex > 0) {
      _paused = false;
      setState(() => _currentIndex--);
      _loadStory();
    }
  }

  void _goToIndex(int idx) {
    if (idx < 0 || idx >= widget.stories.length || idx == _currentIndex) return;
    _paused = false;
    setState(() => _currentIndex = idx);
    _loadStory();
  }

  void _showViewsList(BuildContext context, StoryItem story) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => _StoryViewsListPopup(
        viewCount: story.views,
        storyId: story.id,
        position: offset,
      ),
    );
  }

  void _handleAreaReaction(String emoji) {
    setState(() => _liked = true);
    _sendStoryReaction(emoji);
  }

  void _handleAreaUrl(String url) {
    var u = url;
    if (!u.startsWith('http://') && !u.startsWith('https://') &&
        !u.startsWith('tg://')) {
      u = 'https://$u';
    }
    Process.run('xdg-open', [u]);
  }

  void _sendStoryReaction(String emoji) {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isNotEmpty && widget.peerId.isNotEmpty) {
      engine.reactToStory(accountId, widget.peerId, _current.id, emoji);
    }
  }

  void _activateStealthMode() {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isNotEmpty) {
      engine.activateStealthMode(accountId);
    }
  }

  void _handleAreaChannelPost(int channelId, int msgId) {
    final chatState = context.read<ChatState>();
    Navigator.of(context).pop();
    chatState.openChatById(channelId.toString());
    if (msgId > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        chatState.jumpToMessage(
          DateTime.now().millisecondsSinceEpoch,
          highlightMsgId: msgId.toString(),
        );
      });
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_composeFocused) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _composeKey.currentState?._focusNode.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        if (_captionExpanded) {
          _closeCaption();
          return KeyEventResult.handled;
        }
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _goToPrev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _goToNext();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _togglePause();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 61) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 12) return '${diff.inHours} hours ago';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today at $hh:$mm';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday at $hh:$mm';
    }
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year} at $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    double storyW = _kStoriesMaxWidth;
    double storyH = _kStoriesMaxHeight;
    final scale = math.min(
      (screenSize.width * 0.5) / storyW,
      (screenSize.height - 40) / storyH,
    ).clamp(0.3, 1.0);
    storyW *= scale;
    storyH *= scale;

    final headerOutside = screenSize.height > storyH + _kHeaderOutsideHeight + 40;

    final availSiblingW = math.max(0.0, (screenSize.width - storyW) / 2 - 8);
    final siblingMinW = math.min(_kSiblingMinWidth * scale, availSiblingW);
    final siblingW = (availSiblingW * _kSiblingWidthRatio)
        .clamp(siblingMinW, availSiblingW);
    final siblingH = storyH * 0.65;
    final showSiblings = siblingW >= 60;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(color: const Color(0xE6000000)),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (headerOutside) _buildOutsideHeader(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (showSiblings) ...[
                        _buildSiblingPreview(
                          isLeft: true,
                          width: siblingW,
                          height: siblingH,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _buildStoryCard(storyW, storyH, headerOutside: headerOutside),
                      if (showSiblings) ...[
                        const SizedBox(width: 8),
                        _buildSiblingPreview(
                          isLeft: false,
                          width: siblingW,
                          height: siblingH,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryCard(double w, double h, {required bool headerOutside}) {
    final story = _current;

    return SizedBox(
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kStoriesRadius),
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _captionAnim,
                builder: (context, child) {
                  final t = Curves.easeInOutSine.transform(_captionAnim.value);
                  final captionFade = 1.0 - (1.0 - _kFullContentFade) * t;
                  final opacity = _composeFocused
                      ? _kFullContentFade.clamp(0.0, captionFade)
                      : captionFade;
                  return Opacity(opacity: opacity, child: child);
                },
                child: _buildStoryContent(story, w, h),
              ),
              _buildProgressBar(w),
              if (!headerOutside) _buildHeader(story),
              if (story.isRepost) _buildRepostView(story),
              _buildNavTapZones(),
              if (story.mediaAreas.isNotEmpty)
                _StoryInteractiveAreas(
                  areas: story.mediaAreas,
                  contentWidth: w,
                  contentHeight: h,
                  onReaction: _handleAreaReaction,
                  onUrl: _handleAreaUrl,
                  onChannelPost: _handleAreaChannelPost,
                ),
              if (story.caption.isNotEmpty) _buildCaption(story, w),
              _buildFooter(story),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoryContent(StoryItem story, double w, double h) {
    if (story.isVideo && _videoController != null) {
      return Video(
        controller: _videoController!,
        fit: BoxFit.contain,
        width: w,
        height: h,
      );
    }

    if (story.hasMedia) {
      return Image.file(
        File(story.localPath),
        fit: BoxFit.contain,
        width: w,
        height: h,
        errorBuilder: (_, __, ___) => _buildThumbFallback(story),
      );
    }

    return _buildThumbFallback(story);
  }

  Widget _buildThumbFallback(StoryItem story) {
    if (story.thumbB64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(story.thumbB64),
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      } catch (_) {}
    }
    return const Center(
      child: Icon(Icons.image, color: Colors.white38, size: 64),
    );
  }

  Widget _buildOutsideHeader() {
    final story = _current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.peerAvatarPath != null && widget.peerAvatarPath!.isNotEmpty)
                  ClipOval(
                    child: Image.file(
                      File(widget.peerAvatarPath!),
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarFallback(28),
                    ),
                  )
                else
                  _avatarFallback(28),
                if (widget.isOwnStory)
                  _buildPrivacyBadge(story.privacy),
              ],
            ),
          ),
          const SizedBox(width: 22),
          Text(
            widget.peerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatDate(story.date),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
          Text(
            ' • ${_currentIndex + 1}/${widget.stories.length}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          _buildStoryControlButton(
            icon: _paused ? Icons.play_arrow : Icons.pause,
            onTap: _paused ? _resumePlayback : _pausePlayback,
            hovered: _playHovered,
            onHover: (v) => setState(() => _playHovered = v),
          ),
          if (_current.isVideo)
            _buildStoryControlButton(
              icon: _muted ? Icons.volume_off : Icons.volume_up,
              onTap: () {
                setState(() => _muted = !_muted);
                _videoPlayer?.setVolume(_muted ? 0.0 : 100.0);
              },
              hovered: _volumeHovered,
              onHover: (v) => setState(() => _volumeHovered = v),
            ),
        ],
      ),
    );
  }

  Widget _avatarFallback(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blueGrey,
      ),
      child: Icon(Icons.person, size: size * 0.6, color: Colors.white70),
    );
  }

  Widget _buildProgressBar(double width) {
    final count = widget.stories.length.clamp(0, _kMaxSegmentsCount);
    if (count == 0) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: _kStoriesProgressPadding,
        child: Row(
          children: List.generate(count, (i) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i < count - 1 ? _kStoriesProgressGap : 0,
                ),
                child: SizedBox(
                  height: _kStoriesProgressHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kStoriesProgressHeight / 2),
                    child: i < _currentIndex
                        ? Container(color: Colors.white.withValues(alpha: _kOpacityActive))
                        : i == _currentIndex
                            ? AnimatedBuilder(
                                animation: _current.isVideo && _videoDuration.inMilliseconds > 0
                                    ? AlwaysStoppedAnimation(
                                        _videoPosition.inMilliseconds /
                                            _videoDuration.inMilliseconds)
                                    : _storyTimer,
                                builder: (context, _) {
                                  final progress = _current.isVideo && _videoDuration.inMilliseconds > 0
                                      ? _videoPosition.inMilliseconds / _videoDuration.inMilliseconds
                                      : _storyTimer.value;
                                  return LinearProgressIndicator(
                                    value: progress.clamp(0.0, 1.0),
                                    backgroundColor: Colors.white.withValues(alpha: _kOpacityInactive),
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white.withValues(alpha: _kOpacityActive),
                                    ),
                                    minHeight: _kStoriesProgressHeight,
                                  );
                                },
                              )
                            : Container(color: Colors.white.withValues(alpha: _kOpacityInactive)),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildPrivacyBadge(StoryPrivacy privacy) {
    if (privacy == StoryPrivacy.public) return const SizedBox.shrink();
    final (IconData icon, Color color) = switch (privacy) {
      StoryPrivacy.closeFriends => (Icons.star, const Color(0xFF4DCC5E)),
      StoryPrivacy.contacts => (Icons.people, Colors.white),
      StoryPrivacy.selectedContacts => (Icons.person_outline, Colors.white),
      StoryPrivacy.public => (Icons.public, Colors.white),
    };
    return Positioned(
      right: -5,
      bottom: -4,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Icon(icon, size: 10, color: color),
      ),
    );
  }

  Widget _buildStoryControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool hovered,
    required ValueChanged<bool> onHover,
    bool disabled = false,
  }) {
    final opacity = disabled ? 0.45 : (hovered ? 1.0 : 0.65);
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(icon, color: Colors.white.withValues(alpha: opacity), size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(StoryItem story) {
    return Positioned(
      top: _kStoriesProgressPadding.top + _kStoriesProgressHeight + 4,
      left: 12,
      right: 12,
      bottom: null,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (widget.peerAvatarPath != null && widget.peerAvatarPath!.isNotEmpty)
                    ClipOval(
                      child: Image.file(
                        File(widget.peerAvatarPath!),
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(28),
                      ),
                    )
                  else
                    _avatarFallback(28),
                  if (widget.isOwnStory)
                    _buildPrivacyBadge(story.privacy),
                ],
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        _formatDate(story.date),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        ' • ${_currentIndex + 1}/${widget.stories.length}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _buildStoryControlButton(
              icon: _paused ? Icons.play_arrow : Icons.pause,
              onTap: _paused ? _resumePlayback : _pausePlayback,
              hovered: _playHovered,
              onHover: (v) => setState(() => _playHovered = v),
            ),
            if (_current.isVideo)
              _buildStoryControlButton(
                icon: _muted ? Icons.volume_off : Icons.volume_up,
                onTap: () {
                  setState(() => _muted = !_muted);
                  _videoPlayer?.setVolume(_muted ? 0.0 : 100.0);
                },
                hovered: _volumeHovered,
                onHover: (v) => setState(() => _volumeHovered = v),
              ),
            if (!widget.isOwnStory)
              _buildStoryControlButton(
                icon: Icons.visibility_off_outlined,
                onTap: () => showStoryStealthModeDialog(context, onActivate: _activateStealthMode),
                hovered: _stealthHovered,
                onHover: (v) => setState(() => _stealthHovered = v),
              ),
            _buildStoryControlButton(
              icon: Icons.close,
              onTap: () => Navigator.of(context).maybePop(),
              hovered: _closeHovered,
              onHover: (v) => setState(() => _closeHovered = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepostView(StoryItem story) {
    return Positioned(
      top: _kStoriesProgressPadding.top + _kStoriesProgressHeight + 48,
      left: 12,
      child: _StoryRepostView(
        story: story,
        useQuoteStyle: story.fwdModified,
      ),
    );
  }

  Widget _buildNavTapZones() {
    return Positioned.fill(
      child: GestureDetector(
        onLongPressStart: (_) => _pausePlayback(),
        onLongPressEnd: (_) => _resumePlayback(),
        behavior: HitTestBehavior.translucent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final thirdW = constraints.maxWidth / 3;
            return Row(
              children: [
                SizedBox(
                  width: thirdW,
                  child: GestureDetector(
                    onTap: _goToPrev,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: const SizedBox.expand(),
                ),
                SizedBox(
                  width: thirdW,
                  child: GestureDetector(
                    onTap: _goToNext,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _toggleCaption() {
    if (_captionExpanded) {
      _captionAnim.reverse(from: _captionAnim.value).then((_) {
        if (mounted) setState(() => _captionExpanded = false);
      });
      _storyTimer.forward();
    } else {
      setState(() => _captionExpanded = true);
      _captionAnim.forward(from: _captionAnim.value);
      _storyTimer.stop();
    }
  }

  void _closeCaption() {
    _captionAnim.reverse(from: _captionAnim.value).then((_) {
      if (mounted) setState(() {
        _captionExpanded = false;
        _captionPullDy = 0.0;
      });
    });
    _storyTimer.forward();
  }

  Widget _buildCaption(StoryItem story, double width) {
    final collapsedContent = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _kStoriesCaptionMinWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            story.caption,
            style: const TextStyle(color: _kMediaviewCaptionFg, fontSize: 14),
            maxLines: _kStoriesCaptionMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
          if (story.caption.length > 80)
            const Text(
              'Show more',
              style: TextStyle(
                color: _kMediaviewCaptionLinkFg,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );

    final expandedContent = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: width * 0.6,
        minWidth: _kStoriesCaptionMinWidth,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Text(
          story.caption,
          style: const TextStyle(color: _kMediaviewCaptionFg, fontSize: 14),
        ),
      ),
    );

    return Positioned(
      bottom: 48,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _captionAnim,
        builder: (context, _) {
          final pullFade = _captionPullDy > 0
              ? (1.0 - (_captionPullDy / (_kStoriesCaptionPullThreshold * 2)).clamp(0.0, 0.4))
              : 1.0;
          return Opacity(
            opacity: pullFade,
            child: Transform.translate(
              offset: Offset(0, _captionPullDy > 0 ? _captionPullDy * 0.3 : 0),
              child: GestureDetector(
                onTap: _toggleCaption,
                onVerticalDragUpdate: _captionExpanded
                    ? (d) => setState(() => _captionPullDy += d.delta.dy)
                    : null,
                onVerticalDragEnd: _captionExpanded
                    ? (d) {
                        if (_captionPullDy > _kStoriesCaptionPullThreshold) {
                          _closeCaption();
                        } else {
                          setState(() => _captionPullDy = 0.0);
                        }
                      }
                    : null,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: _kStoriesCaptionPadding,
                  decoration: BoxDecoration(
                    color: _kMediaviewCaptionBg,
                    borderRadius: BorderRadius.circular(_kMediaviewCaptionRadius),
                  ),
                  child: AnimatedCrossFade(
                    firstChild: collapsedContent,
                    secondChild: expandedContent,
                    crossFadeState: _captionExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: _kStoriesCaptionAnimDuration,
                    firstCurve: Curves.easeInOutSine,
                    secondCurve: Curves.easeInOutSine,
                    sizeCurve: Curves.easeInOutSine,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter(StoryItem story) {
    if (!widget.isOwnStory) {
      return Positioned(
        bottom: _kStoryComposeBottomSkip,
        left: 8,
        right: 8,
        child: _StoryReplyCompose(
          key: _composeKey,
          onFocusChanged: () {
            final focused = _composeKey.currentState?.hasFocus ?? false;
            if (focused != _composeFocused) {
              setState(() => _composeFocused = focused);
              if (focused) {
                _pausePlayback();
              } else {
                _resumePlayback();
              }
            }
          },
          isLiked: _liked,
          onLike: () {
            setState(() => _liked = !_liked);
            _sendStoryReaction(_liked ? '❤' : '');
          },
          onReaction: (emoji) {
            setState(() => _liked = true);
            _sendStoryReaction(emoji);
          },
          onSend: (text) {
            final engine = context.read<EngineService>();
            final appState = context.read<AppState>();
            final accountId = appState.activeAccountId;
            if (accountId.isNotEmpty && widget.peerId.isNotEmpty) {
              engine.sendMessage(accountId, widget.peerId, text,
                  replyToId: 'story:${_current.id}');
            }
          },
          onAttach: (paths) {
            final engine = context.read<EngineService>();
            final appState = context.read<AppState>();
            final accountId = appState.activeAccountId;
            if (accountId.isNotEmpty && widget.peerId.isNotEmpty) {
              for (final path in paths) {
                engine.uploadFile(accountId, widget.peerId, path);
              }
            }
          },
        ),
      );
    }
    return Positioned(
      bottom: _kStoryReactionsBottomSkip,
      left: 12,
      right: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Row(
              children: [
                if (story.views > 0)
                  GestureDetector(
                    onTap: () => _showViewsList(context, story),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StoryViewsAvatarStack(count: story.views),
                        const SizedBox(width: 6),
                        Text(
                          '${story.views}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                Text(
                  '${_currentIndex + 1}/${widget.stories.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StoryReactionsPanel(
            isLiked: _liked,
            onLike: () {
              setState(() => _liked = !_liked);
              _sendStoryReaction(_liked ? '❤' : '');
            },
            onReaction: (emoji) {
              setState(() => _liked = true);
              _sendStoryReaction(emoji);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSiblingPreview({
    required bool isLeft,
    required double width,
    required double height,
  }) {
    final idx = isLeft ? _currentIndex - 1 : _currentIndex + 1;
    if (idx < 0 || idx >= widget.stories.length) {
      return SizedBox(width: width);
    }

    final story = widget.stories[idx];
    final isHovered = isLeft ? _leftSiblingHovered : _rightSiblingHovered;
    final opacity = isHovered ? _kSiblingFadeOver : _kSiblingFade;
    final scaleVal = isHovered ? 1.0 + _kSiblingScaleOver : 1.0;
    final userpicSize = width * _kSiblingUserpicRatio;

    return MouseRegion(
      onEnter: (_) => setState(() {
        if (isLeft) _leftSiblingHovered = true; else _rightSiblingHovered = true;
      }),
      onExit: (_) => setState(() {
        if (isLeft) _leftSiblingHovered = false; else _rightSiblingHovered = false;
      }),
      child: GestureDetector(
        onTap: () => _goToIndex(idx),
        child: AnimatedScale(
          scale: scaleVal,
          duration: _kGoodFadeDuration,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: _kGoodFadeDuration,
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_kStoriesRadius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.black),
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: _buildPreviewContent(story, width, height),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.peerAvatarPath != null && widget.peerAvatarPath!.isNotEmpty)
                            ClipOval(
                              child: Image.file(
                                File(widget.peerAvatarPath!),
                                width: userpicSize,
                                height: userpicSize,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _avatarFallback(userpicSize),
                              ),
                            )
                          else
                            _avatarFallback(userpicSize),
                          const SizedBox(height: 8),
                          Text(
                            widget.peerName,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: isHovered ? 1.0 : 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent(StoryItem story, double w, double h) {
    if (story.hasMedia) {
      return Image.file(
        File(story.localPath),
        fit: BoxFit.cover,
        width: w,
        height: h,
        errorBuilder: (_, __, ___) => _buildPreviewThumb(story),
      );
    }
    return _buildPreviewThumb(story);
  }

  Widget _buildPreviewThumb(StoryItem story) {
    if (story.thumbB64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(story.thumbB64),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } catch (_) {}
    }
    return Center(
      child: Icon(
        story.isVideo ? Icons.videocam : Icons.image,
        color: Colors.white38,
        size: 24,
      ),
    );
  }
}

// ── §32.10 Story Stealth Mode Dialog ──

const _kStealthDialogWidth = 320.0;
const _kStealthLogoSize = 60.0;
const _kStealthLogoAdd = 12.0;
const _kStealthLogoRadius = 16.0;
const _kStealthButtonHeight = 42.0;
const _kStealthButtonPadding = EdgeInsets.all(10);
const _kStealthCountdownInterval = Duration(milliseconds: 250);
const _kStealthCloseRipple = 40.0;

enum _StealthButtonState { nonPremium, cooldown, ready }

Future<void> showStoryStealthModeDialog(
  BuildContext context, {
  bool? isPremium,
  DateTime? enabledTill,
  DateTime? cooldownTill,
  VoidCallback? onActivate,
}) {
  final resolvedPremium = isPremium ?? context.read<AppState>().activeAccount?.isPremium ?? false;
  return showDialog<void>(
    context: context,
    builder: (ctx) => _StealthModeDialog(
      isPremium: resolvedPremium,
      enabledTill: enabledTill,
      cooldownTill: cooldownTill,
      onActivate: onActivate,
    ),
  );
}

class _StealthModeDialog extends StatefulWidget {
  final bool isPremium;
  final DateTime? enabledTill;
  final DateTime? cooldownTill;
  final VoidCallback? onActivate;

  const _StealthModeDialog({
    this.isPremium = true,
    this.enabledTill,
    this.cooldownTill,
    this.onActivate,
  });

  @override
  State<_StealthModeDialog> createState() => _StealthModeDialogState();
}

class _StealthModeDialogState extends State<_StealthModeDialog> {
  Timer? _countdownTimer;
  late DateTime _now;
  bool _closeHovered = false;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _startCountdownIfNeeded();
  }

  void _startCountdownIfNeeded() {
    if (widget.cooldownTill != null && widget.cooldownTill!.isAfter(_now)) {
      _countdownTimer ??= Timer.periodic(_kStealthCountdownInterval, (_) {
        setState(() => _now = DateTime.now());
        if (_buttonState != _StealthButtonState.cooldown) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  _StealthButtonState get _buttonState {
    if (!widget.isPremium) return _StealthButtonState.nonPremium;
    if (widget.cooldownTill != null && widget.cooldownTill!.isAfter(_now)) {
      return _StealthButtonState.cooldown;
    }
    return _StealthButtonState.ready;
  }

  String _formatCountdown(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _onButtonTap() {
    final state = _buttonState;
    if (state == _StealthButtonState.nonPremium) {
      Navigator.of(context).pop();
      showTelegramToast(context, 'Stealth Mode is a Premium feature');
      return;
    }
    if (state == _StealthButtonState.cooldown) return;

    widget.onActivate?.call();
    Navigator.of(context).pop();
    showTelegramToast(context, 'Stealth Mode enabled');
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = PaletteProvider.of(context);
    final boxBg = palette.boxBg;
    final state = _buttonState;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _kStealthDialogWidth,
          decoration: BoxDecoration(
            color: boxBg,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 28),
                    Container(
                      width: _kStealthLogoSize + _kStealthLogoAdd * 2,
                      height: _kStealthLogoSize + _kStealthLogoAdd * 2,
                      decoration: BoxDecoration(
                        color: palette.windowBgActive,
                        borderRadius: BorderRadius.circular(_kStealthLogoRadius),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.visibility_off,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'View Stories Anonymously',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.windowBoldFg,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    _StealthFeatureRow(
                      icon: Icons.history,
                      title: 'Hide Recent Views',
                      description: 'The last 5 minutes of views will be hidden.',
                      accentColor: palette.windowActiveTextFg,
                      titleColor: palette.windowBoldFg,
                      descColor: palette.windowSubTextFg,
                    ),
                    const SizedBox(height: 12),
                    _StealthFeatureRow(
                      icon: Icons.update,
                      title: 'Hide Next Views',
                      description: 'Views in the next 25 minutes will be hidden.',
                      accentColor: palette.windowActiveTextFg,
                      titleColor: palette.windowBoldFg,
                      descColor: palette.windowSubTextFg,
                    ),
                    const SizedBox(height: 20),
                    _buildButton(state, palette),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _closeHovered = true),
                  onExit: (_) => setState(() => _closeHovered = false),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(
                      width: _kStealthCloseRipple,
                      height: _kStealthCloseRipple,
                      child: Center(
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: _closeHovered
                              ? palette.windowFg
                              : palette.windowSubTextFg,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(_StealthButtonState state, TelegramPalette palette) {
    final opacity = state == _StealthButtonState.cooldown ? 0.5 : 1.0;

    String label;
    IconData? icon;
    switch (state) {
      case _StealthButtonState.nonPremium:
        label = 'UNLOCK';
        icon = Icons.lock;
      case _StealthButtonState.cooldown:
        final remaining = widget.cooldownTill!.difference(_now);
        label = 'COOLDOWN IN ${_formatCountdown(remaining)}';
      case _StealthButtonState.ready:
        label = widget.onActivate != null ? 'ENABLE AND OPEN' : 'ENABLE';
    }

    return GestureDetector(
      onTap: _onButtonTap,
      child: Container(
        width: double.infinity,
        height: _kStealthButtonHeight,
        padding: _kStealthButtonPadding,
        decoration: BoxDecoration(
          color: palette.activeButtonBg.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: palette.activeButtonFg, size: 16),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.activeButtonFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StealthFeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final Color titleColor;
  final Color descColor;

  const _StealthFeatureRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.titleColor,
    required this.descColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: accentColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 10, maxHeight: 20),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 20),
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: descColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// §32.9: Stacked avatars for story view count
class _StoryViewsAvatarStack extends StatelessWidget {
  final int count;

  const _StoryViewsAvatarStack({required this.count});

  static const _kAvatarSize = 24.0;
  static const _kShift = 9.0;
  static const _kStroke = 4.0;
  static const _kMaxShow = 3;

  static const _colors = [
    Color(0xFF7765CB),
    Color(0xFF6EC47A),
    Color(0xFFE67985),
  ];

  @override
  Widget build(BuildContext context) {
    final showCount = count.clamp(0, _kMaxShow);
    if (showCount == 0) return const SizedBox.shrink();

    final totalW = _kAvatarSize + (_kShift * (showCount - 1));
    return SizedBox(
      width: totalW,
      height: _kAvatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(showCount, (i) {
          return Positioned(
            left: i * _kShift,
            child: Container(
              width: _kAvatarSize,
              height: _kAvatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _colors[i % _colors.length],
                border: Border.all(
                  color: Colors.black,
                  width: _kStroke / 2,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.person,
                  size: _kAvatarSize * 0.5,
                  color: Colors.white70,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// §32.9: "Who Viewed" popup
class _StoryViewsListPopup extends StatefulWidget {
  final int viewCount;
  final int storyId;
  final Offset position;

  const _StoryViewsListPopup({
    required this.viewCount,
    required this.storyId,
    required this.position,
  });

  @override
  State<_StoryViewsListPopup> createState() => _StoryViewsListPopupState();
}

class _StoryViewsListPopupState extends State<_StoryViewsListPopup> {
  static const _kWidth = 240.0;
  static const _kMaxHeight = 320.0;
  static const _kRadius = 7.0;
  static const _kRowHeight = 48.0;

  List<Map<String, dynamic>> _viewers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchViewers();
  }

  Future<void> _fetchViewers() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final viewers = await engine.getStoryViewers(accountId, widget.storyId);
      if (mounted) setState(() { _viewers = viewers; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _kAvatarColors = [
    Color(0xFF7765CB), Color(0xFF6EC47A), Color(0xFFE67985),
    Color(0xFFE6A96F), Color(0xFF6AADE6),
  ];

  String _formatViewerTime(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white54 : Colors.black45;

    final displayCount = _viewers.isNotEmpty ? _viewers.length : widget.viewCount;

    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(color: Colors.transparent),
        ),
        Positioned(
          left: widget.position.dx.clamp(16, MediaQuery.sizeOf(context).width - _kWidth - 16),
          bottom: MediaQuery.sizeOf(context).height - widget.position.dy + 8,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: _kWidth,
              constraints: const BoxConstraints(maxHeight: _kMaxHeight),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(_kRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          'Who Viewed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$displayCount',
                          style: TextStyle(
                            fontSize: 13,
                            color: subtextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                      )),
                    )
                  else if (_viewers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.viewCount > 0 ? '${widget.viewCount} viewers' : 'No viewers yet',
                        style: TextStyle(fontSize: 13, color: subtextColor),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _viewers.length,
                        itemBuilder: (ctx, i) {
                          final viewer = _viewers[i];
                          final name = (viewer['name'] as String?) ??
                              (viewer['first_name'] as String? ?? 'User ${i + 1}');
                          final timeStr = _formatViewerTime(
                            (viewer['date'] as int?) ?? 0,
                          );
                          return SizedBox(
                            height: _kRowHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _kAvatarColors[i % _kAvatarColors.length],
                                    ),
                                    child: Center(
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: const TextStyle(
                                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: textColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (timeStr.isNotEmpty)
                                          Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: subtextColor,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

