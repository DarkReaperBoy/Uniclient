import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';

// anim::easeOutCubic (animation_value.cpp:94-104): delta·((dt-1)³+1) = 1-(1-dt)³.
// This is the PURE cubic polynomial AbstractCheckView animates with
// (checkbox.cpp:62), NOT Flutter's bezier Curves.easeOutCubic
// (= Cubic(0.215,0.61,0.355,1)). Using the exact polynomial makes the
// direction-of-travel math come out exactly as AyuGram: ON (from=0→1) traces
// 1-(1-dt)³ and OFF (from=1→0) traces (1-dt)³ — both decelerating into their
// target. The bezier approximation does not yield (1-dt)³ for the off curve.
class _EaseOutCubic extends Curve {
  const _EaseOutCubic();

  @override
  double transformInternal(double t) {
    final inv = 1.0 - t;
    return 1.0 - inv * inv * inv;
  }
}

const _easeOutCubic = _EaseOutCubic();

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

  // Animation state captured at each (re)start, mirroring
  // Animations::Simple::startPrepared (animations.h:471-480):
  //   _from  = the LIVE interpolated value at the instant of the new start
  //            (_data->from = _data->value),
  //   _to    = the target (0 or 1),
  //   _curve = a FRESH transition (easeOutCubic for material, linear otherwise).
  // The controller always runs forward 0→1 over the FULL duration; direction is
  // encoded in (_from, _to). This is why we do NOT drive forward()/reverse() on
  // a CurvedAnimation: that would (a) scale the simulation duration by the
  // remaining fraction on an interruption (reverse from t=0.5 → ~75ms, not
  // 150ms) and (b) latch CurvedAnimation._curveDirection to the first direction,
  // applying the forward easeOutCubic to an interrupting reverse instead of the
  // true reverse (1-dt)³ — making the off-animation accelerate where AyuGram
  // decelerates. AyuGram instead restarts the timer fully (prepare() →
  // tracker.restart() since 150ms < kLongAnimationDuration=1000ms,
  // animations.h:430-440) from the live value. See checkbox.cpp:56-63.
  double _from = 0.0;
  double _to = 0.0;
  late Curve _curve;

  @override
  void initState() {
    super.initState();
    final v = widget.value ? 1.0 : 0.0;
    _from = v;
    _to = v;
    _curve = widget.isMaterial ? _easeOutCubic : Curves.linear;
    _controller = AnimationController(
      vsync: this,
      // AyuGram switches BOTH duration and curve on isMaterialSwitches():
      // material → _duration (150ms, widgets.style:879) + easeOutCubic;
      // non-material → defaultToggleDuration (=universalDuration=120ms,
      // basic.style:131) + linear (checkbox.cpp:61-62). Both are (re)captured
      // per-animation in _animateTo, exactly as AyuGram reads them per-setChecked.
      duration: Duration(milliseconds: widget.isMaterial ? 150 : 120),
      // Settled at the target: _currentValue() reads _to since transition(1)=1.
      value: 1.0,
    );
  }

  // Mirrors AbstractCheckView::currentAnimationValue() (checkbox.cpp:84-86): the
  // live interpolated value = from + delta·transition(dt). When idle the
  // controller sits at 1.0 and transition(1)=1, so this returns _to (= the
  // settled target), matching Simple::value() returning `final` when not animating.
  double _currentValue() {
    final dt = _controller.value;
    return _from + (_to - _from) * _curve.transform(dt);
  }

  // Mirrors AbstractCheckView::setChecked's animated branch (checkbox.cpp:56-63)
  // → Simple::start → startPrepared (animations.h:471-480): capture the live
  // value as `from`, animate to `to` over the FULL duration with a FRESH
  // transition, restarting the timer from 0. Reading widget.isMaterial here (not
  // in didUpdateWidget) matches AyuGram reading isMaterialSwitches() at the
  // moment of each setChecked — an in-flight animation keeps its captured
  // transition/duration even if the setting flips mid-animation.
  void _animateTo(bool checked) {
    final isMat = widget.isMaterial;
    _from = _currentValue();
    _to = checked ? 1.0 : 0.0;
    _curve = isMat ? _easeOutCubic : Curves.linear;
    _controller.duration = Duration(milliseconds: isMat ? 150 : 120);
    _controller.forward(from: 0.0);
  }

  @override
  void didUpdateWidget(AyuToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animateTo(widget.value);
    }
    // An isMaterial flip with no value change needs no special handling: the
    // geometry (diameter/shift/animPadding) is read live in build() and applied
    // by the painter — and _TogglePainter.shouldRepaint now includes those
    // fields, so an at-rest flip actually repaints (was the omitted-fields bug).
    // The next _animateTo re-derives duration + transition from widget.isMaterial.
    // This mirrors AyuGram: SwitchDiameter/SwitchShift are read per-paint
    // (checkbox.cpp:24-29, 114-119) while the transition is fixed per-setChecked,
    // so a mid-animation flip changes geometry immediately but never retroactively
    // alters the in-flight animation's curve/duration.
  }

  @override
  void dispose() {
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
    // RTL awareness: AyuGram mirrors both the track and thumb through
    // style::rtlrect (checkbox.cpp:118-119) using style::RightToLeft(); the
    // Flutter equivalent is the ambient Directionality. Target platforms (Bale,
    // Rubika) are Persian/RTL, so the switch must flip there.
    final isRtl = Directionality.maybeOf(context) == TextDirection.rtl;

    final switchDiam = isMat ? _diameter : _defDiameter;
    final switchShift = isMat ? _matShift : _defShift;

    final totalW = 2 * _border + switchDiam + _width;
    final totalH = 2 * _border + switchDiam;

    return GestureDetector(
      onTap: () => widget.onChanged?.call(!widget.value),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Live interpolated value = from + delta·transition(dt), restarted
          // fresh on every toggle (see _animateTo / _currentValue). Used for both
          // geometry and the track/border color lerp, exactly as AyuGram feeds
          // `toggled` to anim::brush/anim::pen (checkbox.cpp:120,132,135).
          final t = _currentValue();

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
                isRtl: isRtl,
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
  final bool isRtl;
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
    required this.isRtl,
    required this.fgColor,
    required this.bgColor,
  });

  // style::rtlrect (style_core_direction.h:47-48): in RTL the left edge x of a
  // rect of width w maps to outerw - x - w (here outerw = the painter width). In
  // LTR it is identity. Applied to both the track and the thumb so the whole
  // switch — and the thumb's travel direction — flips in RTL locales.
  double _rtlX(double x, double w, double outerW) =>
      isRtl ? outerW - x - w : x;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final fullWidth = switchDiam + _width;
    final innerDiam = switchDiam - 2 * switchShift;
    final innerRadius = innerDiam / 2;

    // Track background — bgRect via style::rtlrect (checkbox.cpp:118).
    final trackLeft = _border + switchShift;
    final trackW = fullWidth - 2 * switchShift;
    final trackX = _rtlX(trackLeft, trackW, size.width);
    final trackTop = _border + switchShift;
    final trackRect = RRect.fromLTRBR(
      trackX,
      trackTop,
      trackX + trackW,
      trackTop + innerDiam,
      Radius.circular(innerRadius),
    );
    canvas.drawRRect(trackRect, Paint()..color = fgColor);

    // Thumb — fgRect via style::rtlrect (checkbox.cpp:117,119). In LTR the thumb
    // travels left→right as t goes 0→1 (toggleLeft); rtlrect flips it right→left
    // in RTL so it ends on the leading (right) edge when on.
    final toggleLeft = _border + (fullWidth - switchDiam) * t;
    var thumbRect = Rect.fromLTWH(
      _rtlX(toggleLeft, switchDiam, size.width),
      _border,
      switchDiam,
      switchDiam,
    );

    // Material animPadding: the thumb shrinks during the animation
    // (checkbox.cpp:123-126). Symmetric, so RTL needs no extra handling.
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
      t != old.t ||
      fgColor != old.fgColor ||
      bgColor != old.bgColor ||
      // Paint-affecting geometry derived live from isMaterialSwitches
      // (checkbox.cpp:24-29): an at-rest material-switch flip (t/colors
      // unchanged) must still repaint the new diameter/shift/animPadding.
      isMaterial != old.isMaterial ||
      switchDiam != old.switchDiam ||
      switchShift != old.switchShift ||
      isRtl != old.isRtl;
}
