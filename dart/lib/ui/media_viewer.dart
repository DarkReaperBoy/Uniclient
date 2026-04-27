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

class MediaViewer extends StatefulWidget {
  final CachedMessage initialMessage;
  final List<CachedMessage> mediaMessages;

  static _MediaViewerState? _activeInstance;

  static void toggleMode() => _activeInstance?._cycleMode();
  static void rotate() => _activeInstance?._rotate();
  static void flipH() => _activeInstance?._flipHorizontal();
  static void flipV() => _activeInstance?._flipVertical();

  const MediaViewer({
    super.key,
    required this.initialMessage,
    required this.mediaMessages,
  });

  static void open(
    BuildContext context, {
    required CachedMessage message,
    required List<CachedMessage> allMessages,
  }) {
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
  bool _isSeeking = false;

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
      if (mounted) _preloadNearby();
    });
  }

  @override
  void dispose() {
    if (MediaViewer._activeInstance == this) {
      MediaViewer._activeInstance = null;
    }
    _disposePlayer();
    _autoHideTimer?.cancel();
    _rotationAnimCtrl.dispose();
    _zoomAnimCtrl.dispose();
    _controlsAnim.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  CachedMessage get _currentMessage => widget.mediaMessages[_currentIndex];
  bool get _isVideo => _currentMessage.mediaType == 2 || _currentMessage.mediaType == 5;
  bool get _isGif => _currentMessage.mediaType == 7;
  bool get _isDocument => _currentMessage.mediaType == 8 || _currentMessage.mediaType == 3;

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
    });
    _initVideoIfNeeded();
    _preloadNearby();
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _close();
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
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
        if (_isVideo && _player != null) {
          _player!.seek(_position - const Duration(seconds: 5));
          return KeyEventResult.handled;
        }
        _goToPrev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (_isVideo && _player != null) {
          _player!.seek(_position + const Duration(seconds: 5));
          return KeyEventResult.handled;
        }
        _goToNext();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.enter:
        if (_isVideo || _isGif) {
          _togglePlayPause();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyH:
        _flipHorizontal();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyV:
        _flipVertical();
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
        cursor: _isZoomedIn
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
                } else {
                  _toggleControls();
                }
              },
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
                bottom: (_isVideo ? 86 : 8),
                right: 0,
                child: Opacity(
                  opacity: _controlsOpacity,
                  child: _buildFooter(msg, photoIndex, totalPhotos),
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
                bottom: (_isVideo ? 86 : 14),
                right: 14,
                child: Opacity(
                  opacity: _controlsOpacity,
                  child: _buildToolbar(msg),
                ),
              ),
            ],

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
                      } else {
                        _toggleControls();
                      }
                    },
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
                    bottom: (_isVideo ? 86 : 14),
                    child: Opacity(
                      opacity: _controlsOpacity,
                      child: _buildFooter(msg, photoIndex, totalPhotos),
                    ),
                  ),
                  Positioned(
                    bottom: (_isVideo ? 86 : 14),
                    right: 14,
                    child: Opacity(
                      opacity: _controlsOpacity,
                      child: _buildToolbar(msg),
                    ),
                  ),
                ],

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

  Widget _buildVideoControls() {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = _duration - _position;

    return Opacity(
      opacity: _controlsOpacity,
      child: IgnorePointer(
        ignoring: _controlsAnim.isDismissed,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
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
                    child: GestureDetector(
                      onHorizontalDragStart: (_) =>
                          setState(() => _isSeeking = true),
                      onHorizontalDragUpdate: (details) {
                        final box =
                            context.findRenderObject() as RenderBox?;
                        if (box == null || _duration.inMilliseconds == 0) {
                          return;
                        }
                      },
                      onHorizontalDragEnd: (_) =>
                          setState(() => _isSeeking = false),
                      onTapDown: (details) {
                        if (_duration.inMilliseconds == 0) return;
                        final box =
                            details.localPosition.dx;
                        final sliderWidth =
                            (context.findRenderObject() as RenderBox?)
                                    ?.size
                                    .width ??
                                400;
                        final ratio = (box / sliderWidth).clamp(0.0, 1.0);
                        _player?.seek(Duration(
                          milliseconds:
                              (ratio * _duration.inMilliseconds).round(),
                        ));
                      },
                      child: SizedBox(
                        height: 20,
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(1.5),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: const Color(0xFF252525),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFC7C7C7)),
                            ),
                          ),
                        ),
                      ),
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
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    icon: _volume > 0
                        ? Icons.volume_up
                        : Icons.volume_off,
                    size: 32,
                    onTap: () {
                      setState(() {
                        if (_volume > 0) {
                          _volume = 0;
                        } else {
                          _volume = 0.8;
                        }
                        _player?.setVolume(_volume * 100.0);
                      });
                    },
                  ),
                  const SizedBox(width: 16),
                  _ControlButton(
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 40,
                    onTap: _togglePlayPause,
                  ),
                  const SizedBox(width: 16),
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

  void _onSenderTap(CachedMessage msg) {
    Navigator.of(context).pop();
  }

  void _onDateTap(CachedMessage msg) {
    final chatState = context.read<ChatState>();
    Navigator.of(context).pop();
    chatState.jumpToMessage(msg.timestamp);
  }

  Widget _buildToolbar(CachedMessage msg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewerButton(
          icon: Icons.rotate_left,
          onTap: _rotate,
          tooltip: 'Rotate',
        ),
        if (_isZoomedIn)
          _ViewerButton(
            icon: Icons.fit_screen,
            onTap: () => _animateZoomTo(0),
            tooltip: 'Fit to screen (Ctrl+0)',
          )
        else
          _ViewerButton(
            icon: Icons.zoom_in,
            onTap: () => _animateZoomTo(3),
            tooltip: 'Zoom in (Ctrl++)',
          ),
      ],
    );
  }
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
