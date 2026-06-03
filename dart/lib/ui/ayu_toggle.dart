import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';

class AyuToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isMaterial;

  const AyuToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.isMaterial = true,
  });

  @override
  State<AyuToggle> createState() => _AyuToggleState();
}

class _AyuToggleState extends State<AyuToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // CurvedAnimation applies easeOutCubic to the DIRECTION OF TRAVEL (see initState).
  late final CurvedAnimation _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // AyuGram switches BOTH duration and curve on isMaterialSwitches():
      // material → _duration (150ms, widgets.style:879) + easeOutCubic;
      // non-material → defaultToggleDuration (=universalDuration=120ms,
      // basic.style:131) + linear (checkbox.cpp:61-62). The duration is
      // switched here; the curve is applied via the CurvedAnimation below.
      duration: Duration(milliseconds: widget.isMaterial ? 150 : 120),
      value: widget.value ? 1.0 : 0.0,
    );
    // AyuGram applies easeOutCubic to the DIRECTION OF TRAVEL: every toggle is a
    // fresh start(from, to, easeOutCubic) (checkbox.cpp:57-62), computed as
    // _cur = from + delta·((dt-1)³+1) (animation_value.h:85-87 +
    // animation_value.cpp:94-104). So OFF (from=1→0) traces (1-dt)³ —
    // decelerating into off — and ON (from=0→1) traces 1-(1-dt)³. A
    // CurvedAnimation with reverseCurve=easeOutCubic.flipped reproduces both:
    // forward → easeOutCubic, reverse → flip → (1-dt)³ in time. (Driving a
    // linear controller with reverse() and applying easeOutCubic.transform() to
    // its 1→0 value instead gives 1-dt³ — an inverted, accelerating OFF.)
    // Non-material is linear/symmetric, so build() reads the raw value for it.
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic.flipped,
    );
  }

  @override
  void didUpdateWidget(AyuToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // materialSwitches is a live, user-toggleable setting; mirror AyuGram's
    // per-animation-start duration read by re-deriving it when isMaterial flips.
    if (oldWidget.isMaterial != widget.isMaterial) {
      _controller.duration =
          Duration(milliseconds: widget.isMaterial ? 150 : 120);
    }
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  // AyuGram defaultToggle style (widgets.style:874-890)
  static const _border = 2.0;
  static const _diameter = 14.0;
  static const _width = 14.0;
  static const _matShift = -2.0;
  static const _animPadding = 2.0;

  // Non-material defaults (widgets.style:871-873)
  static const _defDiameter = 16.0;
  static const _defShift = 1.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isMat = widget.isMaterial;

    final switchDiam = isMat ? _diameter : _defDiameter;
    final switchShift = isMat ? _matShift : _defShift;

    final totalW = 2 * _border + switchDiam + _width;
    final totalH = 2 * _border + switchDiam;

    return GestureDetector(
      onTap: () => widget.onChanged?.call(!widget.value),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Material: easeOutCubic applied in the direction of travel by the
          // CurvedAnimation (forward → easeOutCubic, reverse → flipped).
          // Non-material: raw linear controller value (symmetric, no curve).
          final t = isMat ? _animation.value : _controller.value;

          final fgColor =
              Color.lerp(palette.checkboxFg, palette.windowBgActive, t)!;

          return SizedBox(
            width: totalW,
            height: totalH,
            child: CustomPaint(
              painter: _TogglePainter(
                t: t,
                isMaterial: isMat,
                switchDiam: switchDiam,
                switchShift: switchShift,
                fgColor: fgColor,
                bgColor: palette.windowBg,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TogglePainter extends CustomPainter {
  final double t;
  final bool isMaterial;
  final double switchDiam;
  final double switchShift;
  final Color fgColor;
  final Color bgColor;

  static const _border = _AyuToggleState._border;
  static const _width = _AyuToggleState._width;
  static const _animPadding = _AyuToggleState._animPadding;

  _TogglePainter({
    required this.t,
    required this.isMaterial,
    required this.switchDiam,
    required this.switchShift,
    required this.fgColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final fullWidth = switchDiam + _width;
    final innerDiam = switchDiam - 2 * switchShift;
    final innerRadius = innerDiam / 2;

    // Track background (rounded rect)
    final trackRect = RRect.fromLTRBR(
      _border + switchShift,
      _border + switchShift,
      _border + switchShift + fullWidth - 2 * switchShift,
      _border + switchShift + innerDiam,
      Radius.circular(innerRadius),
    );
    canvas.drawRRect(trackRect, Paint()..color = fgColor);

    // Thumb position
    final toggleLeft = _border + (fullWidth - switchDiam) * t;
    var thumbRect =
        Rect.fromLTWH(toggleLeft, _border, switchDiam, switchDiam);

    // Material animPadding: thumb shrinks during animation
    if (isMaterial) {
      final anim = _animPadding * (1 - t);
      thumbRect = thumbRect.deflate(anim / 2);
    }

    // Thumb fill
    canvas.drawOval(thumbRect, Paint()..color = bgColor);

    // Thumb border
    canvas.drawOval(
      thumbRect,
      Paint()
        ..color = fgColor
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = _border,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_TogglePainter old) =>
      t != old.t || fgColor != old.fgColor || bgColor != old.bgColor;
}
