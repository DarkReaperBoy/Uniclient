import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/engine_models.dart';

class MediaViewer extends StatefulWidget {
  final CachedMessage initialMessage;
  final List<CachedMessage> mediaMessages;

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
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 0.8;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _currentIndex = widget.mediaMessages.indexWhere(
      (m) => m.msgId == widget.initialMessage.msgId,
    );
    if (_currentIndex < 0) _currentIndex = 0;
    _initVideoIfNeeded();
  }

  @override
  void dispose() {
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

      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });
      player.stream.position.listen((pos) {
        if (mounted && !_isSeeking) setState(() => _position = pos);
      });
      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });
      player.stream.completed.listen((completed) {
        if (completed && msg.mediaType == 7) {
          player.seek(Duration.zero);
          player.play();
        }
      });

      player.setVolume(msg.mediaType == 7 ? 0.0 : _volume * 100.0);
      player.setPlaylistMode(
          msg.mediaType == 7 ? PlaylistMode.single : PlaylistMode.none);
      player.open(Media(msg.mediaLocalPath));
    }
  }

  void _disposePlayer() {
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
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _close();
        return KeyEventResult.handled;
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

  @override
  Widget build(BuildContext context) {
    final msg = _currentMessage;
    final photoIndex = widget.mediaMessages.length - _currentIndex;
    final totalPhotos = widget.mediaMessages.length;
    final screenSize = MediaQuery.sizeOf(context);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
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
          if (_scale <= 1.0) {
            setState(() => _resetZoom());
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFF000000)),

              Center(
                child: Transform(
                  alignment: Alignment.center,
                  // ignore: deprecated_member_use
                  transform: Matrix4.identity()
                    ..translate(_offset.dx, _offset.dy) // ignore: deprecated_member_use
                    ..scale(_scale),
                  child: _buildContent(msg, screenSize),
                ),
              ),

              if (_controlsVisible) ...[
                if (_hasPrev)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 90,
                    child: _NavArea(
                      icon: Icons.chevron_left,
                      onTap: _goToPrev,
                    ),
                  ),
                if (_hasNext)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 90,
                    child: _NavArea(
                      icon: Icons.chevron_right,
                      onTap: _goToNext,
                    ),
                  ),

                Positioned(
                  left: 14,
                  bottom: (_isVideo ? 86 : 14),
                  child: _buildFooter(msg, photoIndex, totalPhotos),
                ),

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
                    icon: Icons.fullscreen,
                    size: 32,
                    onTap: () {},
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
