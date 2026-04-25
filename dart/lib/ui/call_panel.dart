import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum CallPanelState { incoming, connecting, active, ended }

class CallPanelInfo {
  final String callerId;
  final String callerName;
  final String callerAvatarUrl;
  final bool isVideo;
  final CallPanelState state;

  const CallPanelInfo({
    required this.callerId,
    required this.callerName,
    this.callerAvatarUrl = '',
    this.isVideo = false,
    this.state = CallPanelState.incoming,
  });
}

class CallPanel extends StatefulWidget {
  final CallPanelInfo info;
  final VoidCallback? onDecline;
  final VoidCallback? onAccept;
  final VoidCallback? onHangup;
  final VoidCallback? onClose;

  const CallPanel({
    super.key,
    required this.info,
    this.onDecline,
    this.onAccept,
    this.onHangup,
    this.onClose,
  });

  static const defaultWidth = 720.0;
  static const defaultHeight = 540.0;
  static const minWidth = 380.0;
  static const minHeight = 520.0;

  @override
  State<CallPanel> createState() => _CallPanelState();
}

class _CallPanelState extends State<CallPanel> with TickerProviderStateMixin {
  List<Color>? _dominantColors;
  late AnimationController _rippleController;
  Timer? _durationTimer;
  int _durationSeconds = 0;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _extractDominantColors();
    if (widget.info.state == CallPanelState.active) {
      _startDurationTimer();
    }
  }

  @override
  void didUpdateWidget(CallPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.callerAvatarUrl != widget.info.callerAvatarUrl ||
        oldWidget.info.callerId != widget.info.callerId) {
      _extractDominantColors();
    }
    if (widget.info.state == CallPanelState.active &&
        oldWidget.info.state != CallPanelState.active) {
      _startDurationTimer();
    }
    if (widget.info.state != CallPanelState.active) {
      _durationTimer?.cancel();
      _durationTimer = null;
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationSeconds = 0;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSeconds++);
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _extractDominantColors() {
    final url = widget.info.callerAvatarUrl;
    if (url.isNotEmpty) {
      _loadImageColors(url);
    } else {
      _setFallbackColors();
    }
  }

  void _setFallbackColors() {
    final id = widget.info.callerId;
    final hash = id.hashCode.abs();
    final hue = (hash % 360).toDouble();
    setState(() {
      _dominantColors = [
        HSLColor.fromAHSL(1.0, hue, 0.5, 0.25).toColor(),
        HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.6, 0.15).toColor(),
      ];
    });
  }

  Future<void> _loadImageColors(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        _setFallbackColors();
        return;
      }
      final provider = FileImage(file);
      final completer = Completer<ui.Image>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (error, _) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final image = await completer.future;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null || !mounted) {
        _setFallbackColors();
        return;
      }

      final pixels = byteData.buffer.asUint8List();
      int totalR = 0, totalG = 0, totalB = 0;
      int darkR = 0, darkG = 0, darkB = 0;
      int darkCount = 0;
      final pixelCount = pixels.length ~/ 4;
      final step = math.max(1, pixelCount ~/ 200);

      for (int i = 0; i < pixels.length; i += step * 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        totalR += r;
        totalG += g;
        totalB += b;
        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        if (luminance < 128) {
          darkR += r;
          darkG += g;
          darkB += b;
          darkCount++;
        }
      }

      final samples = pixelCount ~/ step;
      if (samples == 0) {
        _setFallbackColors();
        return;
      }

      final avgColor = Color.fromARGB(
        255,
        (totalR ~/ samples).clamp(0, 255),
        (totalG ~/ samples).clamp(0, 255),
        (totalB ~/ samples).clamp(0, 255),
      );

      Color darkColor;
      if (darkCount > 0) {
        darkColor = Color.fromARGB(
          255,
          (darkR ~/ darkCount).clamp(0, 255),
          (darkG ~/ darkCount).clamp(0, 255),
          (darkB ~/ darkCount).clamp(0, 255),
        );
      } else {
        final hsl = HSLColor.fromColor(avgColor);
        darkColor = hsl.withLightness((hsl.lightness * 0.4).clamp(0.0, 1.0)).toColor();
      }

      if (mounted) {
        setState(() {
          _dominantColors = [
            _darkenColor(avgColor, 0.6),
            _darkenColor(darkColor, 0.7),
          ];
        });
      }
    } catch (_) {
      _setFallbackColors();
    }
  }

  static Color _darkenColor(Color c, double factor) {
    return Color.fromARGB(
      c.alpha,
      (c.red * factor).round().clamp(0, 255),
      (c.green * factor).round().clamp(0, 255),
      (c.blue * factor).round().clamp(0, 255),
    );
  }

  Widget _buildUserpic(double size) {
    final url = widget.info.callerAvatarUrl;
    if (url.isNotEmpty) {
      final file = File(url);
      if (file.existsSync()) {
        return ClipOval(
          child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
        );
      }
    }
    final id = widget.info.callerId;
    final hash = id.hashCode.abs();
    final hue = (hash % 360).toDouble();
    final name = widget.info.callerName;
    final initials = name.isNotEmpty
        ? name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join()
        : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: HSLColor.fromAHSL(1.0, hue, 0.5, 0.45).toColor(),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildIncomingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        _buildUserpic(160),
        const SizedBox(height: 20),
        Text(
          widget.info.callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          widget.info.isVideo ? 'Incoming video call...' : 'Incoming call...',
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallActionButton(
              icon: Icons.call_end,
              label: 'Decline',
              backgroundColor: const Color(0xFFE53935),
              onTap: widget.onDecline,
            ),
            const SizedBox(width: 80),
            _AnswerButton(
              rippleController: _rippleController,
              onTap: widget.onAccept,
              isVideo: widget.info.isVideo,
            ),
          ],
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildConnectingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        _buildUserpic(160),
        const SizedBox(height: 20),
        Text(
          widget.info.callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Connecting...',
          style: TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        _CallActionButton(
          icon: Icons.call_end,
          label: 'End Call',
          backgroundColor: const Color(0xFFE53935),
          onTap: widget.onHangup,
          size: 64,
          iconSize: 32,
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildActiveState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        _buildUserpic(160),
        const SizedBox(height: 20),
        Text(
          widget.info.callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _formatDuration(_durationSeconds),
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CallControlButton(
                icon: Icons.screen_share_outlined,
                label: 'Screencast',
                onTap: () {},
              ),
              _CallControlButton(
                icon: Icons.videocam_outlined,
                label: 'Camera',
                onTap: () {},
              ),
              _CallActionButton(
                icon: Icons.call_end,
                label: 'End Call',
                backgroundColor: const Color(0xFFE53935),
                onTap: widget.onHangup,
              ),
              _CallControlButton(
                icon: Icons.mic_off_outlined,
                label: 'Mute',
                onTap: () {},
              ),
              _CallControlButton(
                icon: Icons.person_add_outlined,
                label: 'Add People',
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildEndedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        _buildUserpic(160),
        const SizedBox(height: 20),
        Text(
          widget.info.callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Call ended',
          style: TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        TextButton(
          onPressed: widget.onClose,
          child: const Text(
            'Close',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _dominantColors ?? [const Color(0xFF1a1a2e), const Color(0xFF0f0f1a)];

    Widget content;
    switch (widget.info.state) {
      case CallPanelState.incoming:
        content = _buildIncomingState();
        break;
      case CallPanelState.connecting:
        content = _buildConnectingState();
        break;
      case CallPanelState.active:
        content = _buildActiveState();
        break;
      case CallPanelState.ended:
        content = _buildEndedState();
        break;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: CallPanel.minWidth,
        minHeight: CallPanel.minHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: content,
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    this.onTap,
    this.size = 56,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final AnimationController rippleController;
  final VoidCallback? onTap;
  final bool isVideo;

  const _AnswerButton({
    required this.rippleController,
    this.onTap,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedBuilder(
            animation: rippleController,
            builder: (context, child) {
              return CustomPaint(
                painter: _RippleRingPainter(
                  progress: rippleController.value,
                  color: const Color(0xFF4CAF50),
                ),
                child: child,
              );
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo ? Icons.videocam : Icons.call,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isVideo ? 'Answer Video' : 'Answer',
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _RippleRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RippleRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final phaseOffset = i / 3.0;
      final p = (progress + phaseOffset) % 1.0;
      final radius = baseRadius + p * 24;
      final opacity = (1.0 - p) * 0.4;
      if (opacity <= 0) continue;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RippleRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

void showCallPanel(BuildContext context, CallPanelInfo info) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) {
      return Center(
        child: SizedBox(
          width: CallPanel.defaultWidth,
          height: CallPanel.defaultHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CallPanel(
              info: info,
              onClose: () => Navigator.of(ctx).pop(),
              onDecline: () => Navigator.of(ctx).pop(),
              onAccept: () {},
              onHangup: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    },
  );
}
