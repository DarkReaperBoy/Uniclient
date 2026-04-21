import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/engine_models.dart';

/// Full-screen media viewer overlay. Spec §20.
///
/// Opens with 200ms linear fade-in, closes with 600ms linear fade-out.
/// Background: near-black (`mediaviewBg`). Controls fade at `_controlsOpacity`.
/// Keyboard: Escape=close, Left/Right=prev/next, Ctrl+0=toggle fit/1:1.
class MediaViewer extends StatefulWidget {
  final CachedMessage initialMessage;
  final List<CachedMessage> mediaMessages;

  const MediaViewer({
    super.key,
    required this.initialMessage,
    required this.mediaMessages,
  });

  /// Open the media viewer with a fade transition (§20.19.1).
  static void open(
    BuildContext context, {
    required CachedMessage message,
    required List<CachedMessage> allMessages,
  }) {
    // Filter to visual media only (photo, video, gif — not sticker/videonote).
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
        // §20.19.1: 200ms linear fade-in.
        transitionDuration: const Duration(milliseconds: 200),
        // §20.19.1: 600ms linear fade-out.
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

  // Zoom and pan state (§20.4).
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  bool _isFitToScreen = true;

  // Controls visibility — auto-hide after 3s of no interaction.
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _currentIndex = widget.mediaMessages.indexWhere(
      (m) => m.msgId == widget.initialMessage.msgId,
    );
    if (_currentIndex < 0) _currentIndex = 0;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  CachedMessage get _currentMessage => widget.mediaMessages[_currentIndex];

  bool get _hasPrev => _currentIndex < widget.mediaMessages.length - 1;
  bool get _hasNext => _currentIndex > 0;

  void _goToPrev() {
    if (!_hasPrev) return;
    setState(() {
      _currentIndex++;
      _resetZoom();
    });
  }

  void _goToNext() {
    if (!_hasNext) return;
    setState(() {
      _currentIndex--;
      _resetZoom();
    });
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

  void _close() => Navigator.of(context).pop();

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _close();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _goToPrev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _goToNext();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
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
          setState(() => _controlsVisible = !_controlsVisible);
        },
        // §20.4: zoom/pan.
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
              // §20.2: background — mediaviewBg (near-black opaque).
              Container(color: const Color(0xFF000000)),

              // Main content — photo display.
              Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translate(_offset.dx, _offset.dy)
                    ..scale(_scale),
                  child: _buildContent(msg, screenSize),
                ),
              ),

              // Navigation arrows (§20.6).
              if (_controlsVisible) ...[
                // Left arrow (prev — older).
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
                // Right arrow (next — newer).
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

                // §20.7: Footer — "Photo N of M", sender, date.
                Positioned(
                  left: 14,
                  bottom: 14,
                  child: _buildFooter(msg, photoIndex, totalPhotos),
                ),

                // §20.8: Top-left close button.
                Positioned(
                  top: 8,
                  left: 8,
                  child: _ViewerButton(
                    icon: Icons.close,
                    onTap: _close,
                    tooltip: 'Close',
                  ),
                ),

                // §20.8: Bottom-right toolbar.
                Positioned(
                  bottom: 14,
                  right: 14,
                  child: _buildToolbar(msg),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(CachedMessage msg, Size screenSize) {
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

  Widget _buildFooter(CachedMessage msg, int photoIndex, int totalPhotos) {
    // §20.7: header + sender name + date.
    final typeLabel = switch (msg.mediaType) {
      1 => 'Photo',
      2 => 'Video',
      7 => 'GIF',
      _ => 'Media',
    };
    final dt = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final dateStr = '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Photo N of M" — §20.7 header: mediaviewThickFont (semibold).
        Text(
          totalPhotos > 1 ? '$typeLabel $photoIndex of $totalPhotos' : typeLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        // Sender name + date.
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
    // §20.8: right-to-left toolbar icons in 46x54px cells.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Zoom toggle (fit/1:1) — §20.4.
        _ViewerButton(
          icon: _isFitToScreen ? Icons.zoom_in : Icons.zoom_out,
          onTap: _toggleFitToScreen,
          tooltip: _isFitToScreen ? 'Zoom in' : 'Fit to screen',
        ),
      ],
    );
  }
}

/// Navigation area on left/right of viewer (§20.6: 90px wide).
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

/// Toolbar button for the media viewer (§20.8: 46x54px cells, 36px hover circle).
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
