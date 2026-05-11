import 'package:flutter/material.dart';

/// Skeleton loading animation matching AyuGram Desktop's SkeletonAnimation.
///
/// A horizontal gradient sweeps across placeholder shapes (rounded rects)
/// with [kSlideDuration] ms sweep left-to-right, then [kWaitDuration] ms pause.
///
/// AyuGram ref: ui/effects/skeleton_animation.cpp
/// The gradient modulates opacity directly: edges at kBaseAlpha (more visible),
/// center at kGradientAlpha (less visible = darker center effect).

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
    final radius = widget.borderRadius ?? widget.height / 2;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _SkeletonBarPainter(
            progress: _controller.value,
            subTextFg: subTextFg,
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
  final Color subTextFg;
  final double borderRadius;

  _SkeletonBarPainter({
    required this.progress,
    required this.subTextFg,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    final baseColor = subTextFg.withValues(alpha: subTextFg.a * kBaseAlpha);

    // AyuGram: gradient active during first half (slide), plain fill during second half (wait).
    final period = progress * kFullDuration;
    final gradientActive = period < kSlideDuration;

    final paint = Paint();
    if (gradientActive) {
      final sweepProgress = period / kSlideDuration;
      // AyuGram: gradient spans full textWidth, sweeps from (left - width) to (left + width).
      final gradientWidth = size.width;
      final gradientStart = -gradientWidth + sweepProgress * (size.width + gradientWidth);
      final centerColor = subTextFg.withValues(alpha: subTextFg.a * kGradientAlpha);
      final gradient = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [baseColor, centerColor, baseColor],
        stops: const [0.0, 0.5, 1.0],
      );
      final gradientRect = Rect.fromLTWH(gradientStart, 0, gradientWidth, size.height);
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        Offset.zero & size,
        paint..shader = gradient.createShader(gradientRect),
      );
      canvas.restore();
    } else {
      canvas.drawRRect(rrect, paint..color = baseColor);
    }
  }

  @override
  bool shouldRepaint(_SkeletonBarPainter old) => old.progress != progress;
}

/// Multi-line skeleton placeholder.
///
/// AyuGram's SkeletonAnimation uses _label->countLineWidths() to get real text
/// layout widths. In Flutter, pass explicit [lineWidths] from the parent widget
/// that knows the expected text layout. When [lineWidths] is null, uses
/// proportional fallback widths (last line shorter).
class SkeletonMultiLinePlaceholder extends StatefulWidget {
  final int lineCount;
  final double lineHeight;
  final double lineSpacing;
  final double maxWidth;
  final List<double>? lineWidths;

  const SkeletonMultiLinePlaceholder({
    super.key,
    this.lineCount = 3,
    this.lineHeight = 10,
    this.lineSpacing = 8,
    this.maxWidth = 200,
    this.lineWidths,
  });

  @override
  State<SkeletonMultiLinePlaceholder> createState() => _SkeletonMultiLinePlaceholderState();
}

class _SkeletonMultiLinePlaceholderState extends State<SkeletonMultiLinePlaceholder>
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

  List<double> get _effectiveWidths {
    if (widget.lineWidths != null) return widget.lineWidths!;
    return List.generate(widget.lineCount, (i) {
      if (i == widget.lineCount - 1) return widget.maxWidth * 0.6;
      return widget.maxWidth;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subTextFg = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final radius = widget.lineHeight / 2;
    final widths = _effectiveWidths;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widths.length; i++) ...[
              if (i > 0) SizedBox(height: widget.lineSpacing),
              CustomPaint(
                painter: _SkeletonBarPainter(
                  progress: _controller.value,
                  subTextFg: subTextFg,
                  borderRadius: radius,
                ),
                size: Size(widths[i], widget.lineHeight),
              ),
            ],
          ],
        );
      },
    );
  }
}
