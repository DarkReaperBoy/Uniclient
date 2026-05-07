import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Spec §35.33: Reusable skeleton loading animation system.
///
/// Provides a horizontal glare sweep over placeholder shapes (rounded rects,
/// circles) with the following cycle: [kSlideDuration] ms sweep left-to-right,
/// then [kWaitDuration] ms pause, repeating.
///
/// Used for FlatLabel loading placeholders (chat list loading, profile info
/// loading, credits loading, etc.).

const int kSlideDuration = 1000;
const int kWaitDuration = 1000;
const int kFullDuration = kSlideDuration + kWaitDuration;
const double kBaseAlpha = 0.5;
const double kGradientAlpha = 0.2;

class SkeletonTextPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final double? borderRadius;

  const SkeletonTextPlaceholder({
    super.key,
    required this.width,
    this.height = 10,
    this.borderRadius,
  });

  @override
  State<SkeletonTextPlaceholder> createState() => _SkeletonTextPlaceholderState();
}

class _SkeletonTextPlaceholderState extends State<SkeletonTextPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kFullDuration),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subTextFg = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final baseColor = subTextFg.withValues(alpha: kBaseAlpha);
    final glareColor = subTextFg.withValues(alpha: kGradientAlpha);
    final radius = widget.borderRadius ?? widget.height / 2;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _SkeletonBarPainter(
            progress: _controller.value,
            baseColor: baseColor,
            glareColor: glareColor,
            borderRadius: radius,
          ),
          size: Size(widget.width, widget.height),
        );
      },
    );
  }
}

class _SkeletonBarPainter extends CustomPainter {
  final double progress;
  final Color baseColor;
  final Color glareColor;
  final double borderRadius;

  _SkeletonBarPainter({
    required this.progress,
    required this.baseColor,
    required this.glareColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    canvas.drawRRect(rrect, Paint()..color = baseColor);

    final sweepPhase = progress < 0.5 ? progress / 0.5 : -1.0;
    if (sweepPhase >= 0) {
      final glareX = sweepPhase * size.width;
      final glareWidth = size.width * 0.4;
      final gradient = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          glareColor.withValues(alpha: 0),
          glareColor,
          glareColor.withValues(alpha: 0),
        ],
      );
      final glareRect = Rect.fromLTWH(
        glareX - glareWidth / 2,
        0,
        glareWidth,
        size.height,
      );
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(glareRect, Paint()..shader = gradient.createShader(glareRect));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SkeletonBarPainter old) => old.progress != progress;
}

class SkeletonMultiLinePlaceholder extends StatefulWidget {
  final int lineCount;
  final double lineHeight;
  final double lineSpacing;
  final double maxWidth;
  final int? seed;

  const SkeletonMultiLinePlaceholder({
    super.key,
    this.lineCount = 3,
    this.lineHeight = 10,
    this.lineSpacing = 8,
    this.maxWidth = 200,
    this.seed,
  });

  @override
  State<SkeletonMultiLinePlaceholder> createState() => _SkeletonMultiLinePlaceholderState();
}

class _SkeletonMultiLinePlaceholderState extends State<SkeletonMultiLinePlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<double> _lineWidths;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kFullDuration),
    )..repeat();
    final rng = math.Random(widget.seed);
    _lineWidths = List.generate(
      widget.lineCount,
      (_) => widget.maxWidth / 4 + rng.nextDouble() * (widget.maxWidth / 2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subTextFg = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final baseColor = subTextFg.withValues(alpha: kBaseAlpha);
    final glareColor = subTextFg.withValues(alpha: kGradientAlpha);
    final radius = widget.lineHeight / 2;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.lineCount; i++) ...[
              if (i > 0) SizedBox(height: widget.lineSpacing),
              CustomPaint(
                painter: _SkeletonBarPainter(
                  progress: _controller.value,
                  baseColor: baseColor,
                  glareColor: glareColor,
                  borderRadius: radius,
                ),
                size: Size(_lineWidths[i], widget.lineHeight),
              ),
            ],
          ],
        );
      },
    );
  }
}
