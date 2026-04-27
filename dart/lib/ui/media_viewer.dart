import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';

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

class MediaViewer extends StatefulWidget {
  final CachedMessage initialMessage;
  final List<CachedMessage> mediaMessages;

  static _MediaViewerState? _activeInstance;

  static void toggleMode() => _activeInstance?._cycleMode();

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
            m.mediaLocalPath.isNotEmpty &&
            (m.mediaType == 1 || m.mediaType == 2 || m.mediaType == 7))
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
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late final FocusNode _focusNode;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  bool _isFitToScreen = true;

  bool _controlsVisible = true;

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
    _loadViewerPrefs();
    _initVideoIfNeeded();
  }

  @override
  void dispose() {
    if (MediaViewer._activeInstance == this) {
      MediaViewer._activeInstance = null;
    }
    _disposePlayer();
    _focusNode.dispose();
    super.dispose();
  }

  CachedMessage get _currentMessage => widget.mediaMessages[_currentIndex];
  bool get _isVideo => _currentMessage.mediaType == 2;
  bool get _isGif => _currentMessage.mediaType == 7;

  void _initVideoIfNeeded() {
    final msg = _currentMessage;
    if ((msg.mediaType == 2 || msg.mediaType == 7) &&
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

      player.setVolume(msg.mediaType == 7 ? 0.0 : _volume * 100.0);
      player.setPlaylistMode(
          msg.mediaType == 7 ? PlaylistMode.single : PlaylistMode.none);
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
  }

  void _goToNext() {
    if (!_hasNext) return;
    _disposePlayer();
    setState(() {
      _currentIndex--;
      _resetZoom();
    });
    _initVideoIfNeeded();
  }

  void _resetZoom() {
    _scale = 1.0;
    _offset = Offset.zero;
    _isFitToScreen = true;
  }

  void _toggleFitToScreen() {
    setState(() {
      if (_isFitToScreen) {
        _scale = 2.0;
        _isFitToScreen = false;
      } else {
        _resetZoom();
      }
    });
  }

  void _togglePlayPause() {
    final player = _player;
    if (player == null) return;
    player.playOrPause();
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

    return GestureDetector(
      onTap: () {
        if (_isVideo || _isGif) {
          _togglePlayPause();
        } else {
          setState(() => _controlsVisible = !_controlsVisible);
        }
      },
      onScaleStart: (details) {
        _baseScale = _scale;
        _baseOffset = _offset;
      },
      onScaleUpdate: (details) {
        setState(() {
          _scale = (_baseScale * details.scale).clamp(0.5, 8.0);
          if (_scale > 1.0) {
            _offset = _baseOffset + details.focalPointDelta;
            _isFitToScreen = false;
          }
        });
      },
      onScaleEnd: (_) {
        if (_scale <= 1.0) setState(() => _resetZoom());
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF0E0E0E)),

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
                  ..translate(_offset.dx, _offset.dy)
                  ..scale(_scale),
                child: _buildContent(msg, screenSize),
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
                child: _NavArea(icon: Icons.chevron_left, onTap: _goToPrev),
              ),
            if (_hasNext)
              Positioned(
                right: 0,
                top: titleBarOffset,
                bottom: 0,
                width: 90,
                child: _NavArea(icon: Icons.chevron_right, onTap: _goToNext),
              ),
            Positioned(
              left: 14,
              bottom: (_isVideo ? 86 : 14),
              child: _buildFooter(msg, photoIndex, totalPhotos),
            ),
            if (!_showTitleBar)
              Positioned(
                top: 8,
                left: 8,
                child: _ViewerButton(
                  icon: Icons.close,
                  onTap: _close,
                  tooltip: 'Close',
                ),
              ),
            Positioned(
              bottom: (_isVideo ? 86 : 14),
              right: 14,
              child: _buildToolbar(msg),
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

    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onTap: () {
          if (_isVideo || _isGif) {
            _togglePlayPause();
          } else {
            setState(() => _controlsVisible = !_controlsVisible);
          }
        },
        onScaleStart: (details) {
          _baseScale = _scale;
          _baseOffset = _offset;
        },
        onScaleUpdate: (details) {
          setState(() {
            _scale = (_baseScale * details.scale).clamp(0.5, 8.0);
            if (_scale > 1.0) {
              _offset = _baseOffset + details.focalPointDelta;
              _isFitToScreen = false;
            }
          });
        },
        onScaleEnd: (_) {
          if (_scale <= 1.0) setState(() => _resetZoom());
        },
        child: Container(
          width: w,
          height: h,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E0E),
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(color: Color(0x80000000), blurRadius: 20, spreadRadius: 2),
            ],
          ),
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
                      ..translate(_offset.dx, _offset.dy)
                      ..scale(_scale),
                    child: _buildContent(msg, Size(w, h - _kTitleBarHeight)),
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
                    child: _NavArea(icon: Icons.chevron_left, onTap: _goToPrev),
                  ),
                if (_hasNext)
                  Positioned(
                    right: 0,
                    top: _kTitleBarHeight,
                    bottom: 0,
                    width: 90,
                    child: _NavArea(icon: Icons.chevron_right, onTap: _goToNext),
                  ),
                Positioned(
                  left: 14,
                  bottom: (_isVideo ? 86 : 14),
                  child: _buildFooter(msg, photoIndex, totalPhotos),
                ),
                Positioned(
                  bottom: (_isVideo ? 86 : 14),
                  right: 14,
                  child: _buildToolbar(msg),
                ),
              ],

              if (_isVideo && _player != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildVideoControls(),
                ),

              // Bottom-right resize handle
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
    if ((msg.mediaType == 2 || msg.mediaType == 7) &&
        _videoController != null) {
      return Video(
        controller: _videoController!,
        width: screenSize.width,
        height: screenSize.height,
        fit: BoxFit.contain,
        controls: NoVideoControls,
      );
    }
    if (msg.mediaLocalPath.isNotEmpty) {
      final file = File(msg.mediaLocalPath);
      return Image.file(
        file,
        fit: BoxFit.contain,
        width: screenSize.width,
        height: screenSize.height,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, error, __) => _buildErrorPlaceholder(error),
      );
    }
    return _buildErrorPlaceholder(null);
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

    return AnimatedOpacity(
      opacity: _controlsVisible ? 1.0 : 0.0,
      duration: Duration(milliseconds: _controlsVisible ? 200 : 600),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
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

  Widget _buildFooter(CachedMessage msg, int photoIndex, int totalPhotos) {
    final typeLabel = switch (msg.mediaType) {
      1 => 'Photo',
      2 => 'Video',
      7 => 'GIF',
      _ => 'Media',
    };
    final dt = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final dateStr =
        '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          totalPhotos > 1 ? '$typeLabel $photoIndex of $totalPhotos' : typeLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg.senderName.isNotEmpty) ...[
              Text(
                msg.senderName,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Text(
                ' \u2022 ',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
            Text(
              dateStr,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToolbar(CachedMessage msg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewerButton(
          icon: _isFitToScreen ? Icons.zoom_in : Icons.zoom_out,
          onTap: _toggleFitToScreen,
          tooltip: _isFitToScreen ? 'Zoom in' : 'Fit to screen',
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
