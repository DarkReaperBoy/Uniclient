import 'package:flutter/material.dart';

import '../theme/telegram_palette.dart';

/// Faithful port of AyuGram's `Ui::BoxContentDivider` painted with
/// `st::defaultDividerBar`: a full-bleed band `st::boxDividerHeight` (8px) tall
/// filled with `boxDividerBg` (= windowBgOver, the gray box divider), capped by a
/// 1px soft shadow hairline at the top and bottom — the `box_divider_top` /
/// `box_divider_bottom` shadow icons, tinted `boxDividerFg` (= windowShadowFg).
///
/// Replaces the 1px `Container(height: 1, color: dividerColor)` hairlines that
/// the settings port otherwise uses for section separators.
///
/// Refs: lib_ui/ui/widgets/widgets.style:686-691 (boxDividerHeight /
/// defaultDividerBar), lib_ui/ui/widgets/box_content_divider.cpp:29-57 (paint),
/// lib_ui/ui/colors.palette:146-147 (boxDividerBg / boxDividerFg).
class BoxContentDivider extends StatelessWidget {
  /// Band height. AyuGram `st::boxDividerHeight` = 8px.
  final double height;

  /// Paint the top shadow hairline (RectPart::Top in the C++).
  final bool top;

  /// Paint the bottom shadow hairline (RectPart::Bottom in the C++).
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
    // boxDividerFg aliases windowShadowFg in AyuGram and the box_divider_*.png
    // gradients are tinted with it; the palette's shadowFg carries the correct
    // low-alpha shadow value, so use it for the hairlines (the opaque
    // windowShadowFg/boxDividerFg field would render as a hard black line).
    final shadow = p.shadowFg;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.boxDividerBg,
        border: Border(
          top: top ? BorderSide(color: shadow, width: 1) : BorderSide.none,
          bottom:
              bottom ? BorderSide(color: shadow, width: 1) : BorderSide.none,
        ),
      ),
    );
  }
}
