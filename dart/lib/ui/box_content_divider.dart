import 'package:flutter/material.dart';

import '../theme/telegram_palette.dart';

/// Faithful port of AyuGram's `Ui::BoxContentDivider` painted with
/// `st::defaultDividerBar`: a full-bleed band `st::boxDividerHeight` (8px) tall
/// filled with `boxDividerBg` (= windowBgOver, the gray box divider), capped by
/// the `box_divider_top` / `box_divider_bottom` shadow gradients at the top and
/// bottom edges, each tinted `boxDividerFg` (= windowShadowFg, opaque black).
///
/// The two shadow icons are 1x5px mask PNGs (5px tall at @1x); their gray value
/// equals the rendered alpha over the opaque-black `boxDividerFg`, so they read
/// as a soft inset gradient — NOT a crisp hairline. Top edge peaks ~6% black and
/// fades over ~3px (`15 -> 8 -> 3 -> 0 -> 0`); the bottom edge is much fainter,
/// only ~1% black on the very last pixel (`0 -> 0 -> 0 -> 0 -> 3`). This top-vs-
/// bottom asymmetry matches AyuGram exactly.
///
/// Replaces the 1px `Container(height: 1, color: dividerColor)` hairlines that
/// the settings port otherwise uses for section separators.
///
/// Refs: lib_ui/ui/widgets/widgets.style:684-691 (boxDividerTop/Bottom icons /
/// boxDividerHeight / defaultDividerBar), lib_ui/ui/widgets/box_content_divider.cpp:29-57
/// (paintTop/paintBottom fill `_st.top/bottom.height()` rects with the icons),
/// lib_ui/icons/box_divider_top.png + box_divider_bottom.png (1x5 masks),
/// lib_ui/ui/colors.palette:146-147 (boxDividerBg / boxDividerFg = windowShadowFg).
class BoxContentDivider extends StatelessWidget {
  /// Band height. AyuGram `st::boxDividerHeight` = 8px.
  final double height;

  /// Paint the top shadow gradient (RectPart::Top in the C++).
  final bool top;

  /// Paint the bottom shadow gradient (RectPart::Bottom in the C++).
  final bool bottom;

  const BoxContentDivider({
    super.key,
    this.height = 8,
    this.top = true,
    this.bottom = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _BoxContentDividerPainter(
        bg: p.boxDividerBg,
        // boxDividerFg = windowShadowFg, opaque black; the icon masks supply the
        // per-pixel alpha. Tinting the mask with this color is exactly what
        // AyuGram does (`icon {{ "box_divider_top", boxDividerFg }}`).
        fg: p.boxDividerFg,
        top: top,
        bottom: bottom,
      ),
    );
  }
}

class _BoxContentDividerPainter extends CustomPainter {
  final Color bg;
  final Color fg;
  final bool top;
  final bool bottom;

  /// box_divider_top.png 1x5 mask: gray value per row (top edge -> inward).
  /// The value is the alpha over the opaque-black `fg`.
  static const List<int> _topProfile = [15, 8, 3, 0, 0];

  /// box_divider_bottom.png 1x5 mask: gray value per row (top of band -> bottom
  /// edge). Only the very last pixel carries a faint ~1% shadow.
  static const List<int> _bottomProfile = [0, 0, 0, 0, 3];

  /// Icon height = `st::boxDividerTop/Bottom` source mask height (5px @1x).
  static const double _bandHeight = 5;

  const _BoxContentDividerPainter({
    required this.bg,
    required this.fg,
    required this.top,
    required this.bottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // p.fillRect(e->rect(), _st.bg) — the dominant 8px gray band.
    final fill = Paint()
      ..color = bg
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), fill);

    final shadow = Paint()..isAntiAlias = false;
    if (top) {
      // paintTop: fill rect(0, 0, width, top.height()) with the top mask.
      _paintBand(canvas, shadow, w, 0, _topProfile);
    }
    if (bottom) {
      // paintBottom: fill rect(0, height - bottom.height(), width, bottom.height()).
      _paintBand(canvas, shadow, w, h - _bandHeight, _bottomProfile);
    }
  }

  void _paintBand(
    Canvas canvas,
    Paint shadow,
    double w,
    double bandTop,
    List<int> profile,
  ) {
    for (var i = 0; i < profile.length; i++) {
      final value = profile[i];
      if (value == 0) continue;
      // Mask gray value -> alpha, scaled by fg's own alpha (1.0 for opaque
      // black so value passes through unchanged; honours non-opaque themes).
      // value <= 15 so the product never leaves the 0..255 range.
      final alpha = (fg.a * value).round();
      shadow.color = fg.withAlpha(alpha);
      canvas.drawRect(Rect.fromLTWH(0, bandTop + i, w, 1), shadow);
    }
  }

  @override
  bool shouldRepaint(covariant _BoxContentDividerPainter old) =>
      old.bg != bg || old.fg != fg || old.top != top || old.bottom != bottom;
}
