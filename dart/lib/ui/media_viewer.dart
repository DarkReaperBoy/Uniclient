import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';

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

  static _MediaViewerState? _activeInstance;

  static void toggleMode() => _activeInstance?._cycleMode();
  static void rotate() => _activeInstance?._rotate();
  static void flipH() => _activeInstance?._flipHorizontal();
  static void flipV() => _activeInstance?._flipVertical();
  static void save() => _activeInstance?._saveMediaToDownloads(_activeInstance!._currentMessage);
  static void copyMedia() => _activeInstance?._copyImageToClipboard(_activeInstance!._currentMessage);
  static void enterPip() => _activeInstance?._enterPip();

  const MediaViewer({
    super.key,
    required this.initialMessage,
    required this.mediaMessages,
    this.resumePosition,
  });

  static void open(
    BuildContext context, {
    required CachedMessage message,
    required List<CachedMessage> allMessages,
    Duration? resumePosition,
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
          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.linear)),
            child: MediaViewer(
              initialMessage: message,
              mediaMessages: mediaMessages,
              resumePosition: resumePosition,
            ),
          );
        },
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
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
  double _volume = 0.8;
  double _lastVolume = 0.8;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;
  bool _autoPausedForCall = false;
  ChatState? _chatStateRef;
  int? _activeQualitySeq;
  bool _qualityDownloading = false;

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
    )..addListener(() {
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
    _autoHideTimer?.cancel();
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
          if (mounted && !_isSeeking) setState(() => _position = pos);
        }),
        player.stream.duration.listen((dur) {
          if (mounted) setState(() => _duration = dur);
        }),
        player.stream.completed.listen((completed) {
          if (completed && msg.mediaType == 7) {
            player.seek(Duration.zero);
            player.play();
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
    _position = Duration.zero;
    _duration = Duration.zero;
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
    return math.pow(2.0, 3.0 * level / 7.0).toDouble();
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
          _goToPrev();
        } else if (event.scrollDelta.dy < 0) {
          _goToNext();
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

  void _seekToPercent(int percent) {
    if (!_isVideo || _player == null || _duration == Duration.zero) return;
    final target = _duration * (percent / 100.0);
    _player!.seek(target);
    _showControls();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
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
        if (_isVideo) {
          _seekToPercent(0);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit1:
      case LogicalKeyboardKey.numpad1:
        if (!ctrl && _isVideo) { _seekToPercent(10); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit2:
      case LogicalKeyboardKey.numpad2:
        if (!ctrl && _isVideo) { _seekToPercent(20); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit3:
      case LogicalKeyboardKey.numpad3:
        if (!ctrl && _isVideo) { _seekToPercent(30); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit4:
      case LogicalKeyboardKey.numpad4:
        if (!ctrl && _isVideo) { _seekToPercent(40); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit5:
      case LogicalKeyboardKey.numpad5:
        if (!ctrl && _isVideo) { _seekToPercent(50); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit6:
      case LogicalKeyboardKey.numpad6:
        if (!ctrl && _isVideo) { _seekToPercent(60); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit7:
      case LogicalKeyboardKey.numpad7:
        if (!ctrl && _isVideo) { _seekToPercent(70); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit8:
      case LogicalKeyboardKey.numpad8:
        if (!ctrl && _isVideo) { _seekToPercent(80); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.digit9:
      case LogicalKeyboardKey.numpad9:
        if (!ctrl && _isVideo) { _seekToPercent(90); return KeyEventResult.handled; }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
        if (alt) return KeyEventResult.ignored;
        if (_isVideo && _player != null) {
          _player!.seek(_position - const Duration(seconds: 5));
          _showControls();
          return KeyEventResult.handled;
        }
        _goToPrev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (alt) return KeyEventResult.ignored;
        if (_isVideo && _player != null) {
          _player!.seek(_position + const Duration(seconds: 5));
          _showControls();
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
          _togglePlayPause();
          _showControls();
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
                        child: _buildContent(msg, screenSize),
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
                              child: _buildContent(msg, Size(w, h - _kTitleBarHeight)),
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

    return Opacity(
      opacity: _controlsOpacity,
      child: IgnorePointer(
        ignoring: _controlsAnim.isDismissed,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            constraints: const BoxConstraints(maxWidth: 480),
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(10),
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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final dateStr =
        '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';

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
        child: SelectableText(
          text,
          style: const TextStyle(
            color: _kMediaviewCaptionFg,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  void _onSenderTap(CachedMessage msg) {
    Navigator.of(context).pop();
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
    final downloadsDir =
        Directory('${Platform.environment['HOME'] ?? '/tmp'}/Downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    final fileName = msg.mediaFileName.isNotEmpty
        ? msg.mediaFileName
        : sourceFile.uri.pathSegments.last;
    var destPath = '${downloadsDir.path}/$fileName';
    var counter = 1;
    while (await File(destPath).exists()) {
      final ext =
          fileName.contains('.') ? '.${fileName.split('.').last}' : '';
      final base = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      destPath = '${downloadsDir.path}/${base}_($counter)$ext';
      counter++;
    }
    await sourceFile.copy(destPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to ${destPath.split('/').last}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2C3A),
        title: const Text('Forward to...', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.builder(
            itemCount: chats.length,
            itemBuilder: (_, i) {
              final chat = chats[i];
              return ListTile(
                title: Text(chat.title,
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  chatState.forwardMessages([msg.msgId], chat.chatId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Forwarded to ${chat.title}'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
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
    final bytes = await file.readAsBytes();
    await Clipboard.setData(ClipboardData(text: msg.mediaLocalPath));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Image path copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showMoreMenu(BuildContext btnContext, CachedMessage msg) {
    final RenderBox button = btnContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(btnContext).overlay!.context.findRenderObject()
            as RenderBox;
    final Offset pos = button.localToGlobal(Offset.zero, ancestor: overlay);

    final items = <PopupMenuEntry<String>>[
      _darkMenuItem('show_in_chat', Icons.chat_bubble_outline, 'Show in Chat'),
      if (_isPhoto && msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('copy_image', Icons.copy, 'Copy Image'),
      if (msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('forward', Icons.forward, 'Forward'),
      if (msg.isOutgoing)
        _darkMenuItem('delete', Icons.delete_outline, 'Delete',
            isDestructive: true),
      if (msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('save_as', Icons.save_alt, 'Save As\u2026'),
    ];

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
      switch (value) {
        case 'show_in_chat':
          _showInChat(msg);
        case 'copy_image':
          _copyImageToClipboard(msg);
        case 'forward':
          _forwardMedia(msg);
        case 'delete':
          _deleteMedia(msg);
        case 'save_as':
          _saveMediaToDownloads(msg);
      }
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
    final items = <PopupMenuEntry<String>>[
      _darkMenuItem('show_in_chat', Icons.chat_bubble_outline, 'Show in Chat'),
      if (_isPhoto && msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('copy_image', Icons.copy, 'Copy Image'),
      if (msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('forward', Icons.forward, 'Forward'),
      if (msg.isOutgoing)
        _darkMenuItem('delete', Icons.delete_outline, 'Delete',
            isDestructive: true),
      if (msg.mediaLocalPath.isNotEmpty)
        _darkMenuItem('save_as', Icons.save_alt, 'Save As\u2026'),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: const Color(0xE6222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'show_in_chat':
          _showInChat(msg);
        case 'copy_image':
          _copyImageToClipboard(msg);
        case 'forward':
          _forwardMedia(msg);
        case 'delete':
          _deleteMedia(msg);
        case 'save_as':
          _saveMediaToDownloads(msg);
      }
    });
  }

  Widget _buildToolbar(CachedMessage msg) {
    final hasContent = msg.mediaLocalPath.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
}

class _PlaybackSlider extends StatefulWidget {
  final double value;
  final double trackHeight;
  final double handleSize;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;

  const _PlaybackSlider({
    required this.value,
    required this.trackHeight,
    required this.handleSize,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChanged,
    this.onChangeEnd,
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

  _SliderPainter({
    required this.value,
    required this.trackHeight,
    required this.handleSize,
    required this.activeColor,
    required this.inactiveColor,
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

    canvas.drawCircle(Offset(handleX, cy), handleSize / 2, activePaint);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      value != old.value ||
      trackHeight != old.trackHeight ||
      handleSize != old.handleSize ||
      activeColor != old.activeColor ||
      inactiveColor != old.inactiveColor;
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

  @override
  void initState() {
    super.initState();
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
        final startIdx = math.max(0, widget.currentIndex - widget.maxSideThumbs);
        final endIdx = math.min(widget.messages.length - 1, widget.currentIndex + widget.maxSideThumbs);

        final children = <Widget>[];
        for (int i = startIdx; i <= endIdx; i++) {
          final isCurrent = i == widget.currentIndex;
          final targetW = isCurrent ? _kThumbWidthMax : _kThumbWidth;

          if (i > startIdx) {
            final prevIsCurrent = (i - 1) == widget.currentIndex;
            final gap = (isCurrent || prevIsCurrent) ? _kThumbGapCurrent : _kThumbGap;
            children.add(SizedBox(width: gap));
          }

          children.add(
            _ThumbItem(
              message: widget.messages[i],
              width: targetW,
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
    return Tooltip(
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
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white54,
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

  late final AnimationController _snapAnim;
  double _snapFromX = 0, _snapFromY = 0;
  double _snapToX = 0, _snapToY = 0;

  List<StreamSubscription> _playerSubs = [];

  @override
  void initState() {
    super.initState();
    PipManager.instance._activeState = this;

    _width = _kPipDefaultSize;
    _height = _kPipDefaultSize;
    _x = _kPipBorderSkip;
    _y = _kPipBorderSkip;

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
    ];

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
    final right = screen.width - _width;
    final bottom = screen.height - _height;

    if ((x - _kPipBorderSkip).abs() < _kPipBorderSnapArea) {
      sx = _kPipBorderSkip;
    } else if ((x - right + _kPipBorderSkip).abs() < _kPipBorderSnapArea) {
      sx = right - _kPipBorderSkip;
    }

    if ((y - _kPipBorderSkip).abs() < _kPipBorderSnapArea) {
      sy = _kPipBorderSkip;
    } else if ((y - bottom + _kPipBorderSkip).abs() < _kPipBorderSnapArea) {
      sy = bottom - _kPipBorderSkip;
    }

    sx = sx.clamp(_kPipBorderSkip, right - _kPipBorderSkip);
    sy = sy.clamp(_kPipBorderSkip, bottom - _kPipBorderSkip);
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
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
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
    return Tooltip(
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
