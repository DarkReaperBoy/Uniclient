import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/telegram_palette.dart';

import 'ayu_toggle.dart';
import 'confirm_box.dart';

class AyuSectionBuilder {
  final List<Widget> _children = [];
  final bool isDark;
  final bool useMaterial;

  AyuSectionBuilder({required this.isDark, this.useMaterial = false});

  void addSectionTitle(String title) {
    // AyuGram has no separate "section title" — every header is a
    // defaultSubsectionTitle: font(boxFontSize=14 semibold), textFg
    // windowActiveTextFg, defaultSubsectionTitlePadding = margins(22,7,10,9).
    // Match it 1:1 (settings.style / layers.style:148-154). Use the palette's
    // windowActiveTextFg (#168acd light / #6ab3f3 dark) — NOT windowBgActive
    // (#3390ec), which is a different, brighter blue.
    _children.add(Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 7, 10, 9),
        child: Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.palette.windowActiveTextFg)),
      ),
    ));
  }

  void addSubsectionTitle(String title) {
    // defaultSubsectionTitle = font(boxFontSize=14 semibold), textFg
    // windowActiveTextFg, defaultSubsectionTitlePadding = margins(22,7,10,9)
    // (layers.style:148-154).
    _children.add(Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 7, 10, 9),
        child: Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.palette.windowActiveTextFg)),
      ),
    ));
  }

  void addSettingToggle({
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool showBetaBadge = false,
    IconData? icon,
  }) {
    _children.add(_AyuSettingToggle(
      label: label,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
      isDark: isDark,
      useMaterial: useMaterial,
      showBetaBadge: showBetaBadge,
      icon: icon,
    ));
  }

  void addSlider({
    required String label,
    required int steps,
    required int current,
    required int Function(int) indexToValue,
    required String Function(int) formatLabel,
    // Nullable to mirror AyuGram's `.onChanged = nullptr`: when null the slider
    // only live-updates its own value label during a drag (local setState) and
    // never fires a per-frame persist callback. Persistence belongs in
    // onFinalChanged, which fires once on release (ayu_builder.cpp:223-244).
    ValueChanged<int>? onChanged,
    ValueChanged<int>? onFinalChanged,
    bool showTitle = true,
  }) {
    _children.add(_AyuSlider(
      label: label,
      steps: steps,
      current: current,
      indexToValue: indexToValue,
      formatLabel: formatLabel,
      onChanged: onChanged,
      onFinalChanged: onFinalChanged,
      isDark: isDark,
      showTitle: showTitle,
    ));
  }

  void addChooseButton({
    required String label,
    required int value,
    required Map<int, String> items,
    required ValueChanged<int> onChanged,
    IconData? icon,
  }) {
    _children.add(_AyuChooseButton(
      label: label,
      value: value,
      items: items,
      onChanged: onChanged,
      isDark: isDark,
      icon: icon,
    ));
  }

  void addCollapsibleToggle({
    required String label,
    required bool isExpanded,
    required List<AyuNestedCheckboxItem> children,
    ValueChanged<bool>? onMasterToggle,
    bool? masterValue,
    bool toggledWhenAll = true,
  }) {
    _children.add(_AyuCollapsibleToggle(
      label: label,
      isExpanded: isExpanded,
      isDark: isDark,
      useMaterial: useMaterial,
      children: children,
      onMasterToggle: onMasterToggle,
      masterValue: masterValue,
      toggledWhenAll: toggledWhenAll,
    ));
  }

  void addBetaBadge(String text, {required String labelText, bool hasIcon = false}) {
    if (_children.isEmpty) return;
    final lastWidget = _children.removeLast();
    _children.add(_BetaBadgeOverlay(
      badge: text,
      isDark: isDark,
      labelText: labelText,
      hasIcon: hasIcon,
      child: lastWidget,
    ));
  }

  void addSectionDivider() {
    // AyuGram addSectionDivider() = addSkip + addDivider + addSkip
    // (ayu_builder.cpp:263-267). addSkip = defaultVerticalListSkip (6px);
    // addDivider = BoxContentDivider of boxDividerHeight (8px) filled with
    // boxDividerBg (windowBgOver) — a full-bleed band, not a 1px line.
    _children.add(Column(
      children: [
        const SizedBox(height: 6),
        Builder(
          builder: (context) => Container(
              height: 8, width: double.infinity, color: context.palette.boxDividerBg),
        ),
        const SizedBox(height: 6),
      ],
    ));
  }

  void addSkip([double height = 7]) {
    _children.add(SizedBox(height: height));
  }

  void addDescription(String text) {
    // Divider-text label metrics (no bar): defaultTextStyle (14px),
    // windowSubTextFg, defaultBoxDividerLabelPadding = margins(22,8,22,16)
    // (widgets.style:693-699).
    _children.add(Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
        child: Text(text,
            style: TextStyle(
                fontSize: 14, color: context.palette.windowSubTextFg)),
      ),
    ));
  }

  void addDividerText(String text) {
    // AyuGram Ui::AddDividerText -> DividerLabel: the label sits ON a
    // boxDividerBg band (defaultDividerBar) with defaultTextStyle (14px),
    // windowSubTextFg, defaultBoxDividerLabelPadding = margins(22,8,22,16)
    // (vertical_list.cpp:50-67, widgets.style:687-703).
    _children.add(Builder(
      builder: (context) {
        final p = context.palette;
        return Container(
          width: double.infinity,
          color: p.boxDividerBg,
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Text(text,
              style: TextStyle(fontSize: 14, color: p.windowSubTextFg)),
        );
      },
    ));
  }

  void addWidget(Widget widget) {
    _children.add(widget);
  }

  List<Widget> build() => List.unmodifiable(_children);
}

class AyuNestedCheckboxItem {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool Function()? lockGetter;
  final ValueChanged<bool>? lockSetter;

  const AyuNestedCheckboxItem({
    required this.label,
    required this.value,
    required this.onChanged,
    this.lockGetter,
    this.lockSetter,
  });

  bool get isLocked => lockGetter?.call() ?? false;
}

class _BetaBadgeOverlay extends StatefulWidget {
  final String badge;
  final bool isDark;
  final Widget child;
  final String? labelText;
  final bool hasIcon;

  const _BetaBadgeOverlay({
    required this.badge,
    required this.isDark,
    required this.child,
    this.labelText,
    this.hasIcon = false,
  });

  @override
  State<_BetaBadgeOverlay> createState() => _BetaBadgeOverlayState();
}

class _BetaBadgeOverlayState extends State<_BetaBadgeOverlay> {
  TextPainter? _textPainter;
  double _leftOffset = 26;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateOffset();
  }

  @override
  void didUpdateWidget(_BetaBadgeOverlay old) {
    super.didUpdateWidget(old);
    if (old.labelText != widget.labelText) _updateOffset();
  }

  void _updateOffset() {
    _textPainter?.dispose();
    if (widget.labelText != null) {
      final scaledSize = MediaQuery.textScalerOf(context).scale(14);
      _textPainter = TextPainter(
        text: TextSpan(
          text: widget.labelText,
          style: TextStyle(fontSize: scaledSize),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      // AddBetaBadge positions x = st.padding.left() + parent->fullTextWidth()
      // + settingsPremiumNewBadgePosition.x() (=4). padding.left() is 22px for
      // settingsButtonNoIcon, 60px for settingsButton (icon variant)
      // (settings.style:15,26; settings_ayu_utils.cpp:69-72).
      _leftOffset = (widget.hasIcon ? 60 : 22) + _textPainter!.width + 4;
    } else {
      _textPainter = null;
      _leftOffset = widget.hasIcon ? 60 : 26;
    }
  }

  @override
  void dispose() {
    _textPainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: _leftOffset,
          top: 0,
          bottom: 0,
          // AyuGram's badge is WA_TransparentForMouseEvents
          // (settings_ayu_utils.cpp:56) — taps fall through to the row below.
          child: IgnorePointer(
            child: Align(
            alignment: Alignment.centerLeft,
            child: Builder(builder: (context) {
              final p = context.palette;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: p.windowBgActive,
                  borderRadius: BorderRadius.circular(4),
                ),
                // settingsPremiumNewBadge.textFg = windowFgActive — theme
                // dependent, not hardcoded white (settings.style:144-149).
                child: Text(widget.badge,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: p.windowFgActive)),
              );
            }),
            ),
          ),
        ),
      ],
    );
  }
}

class _AyuSettingToggle extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final bool useMaterial;
  final bool showBetaBadge;
  final IconData? icon;

  const _AyuSettingToggle({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
    this.useMaterial = false,
    this.showBetaBadge = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(left: 22, right: 22, top: 10, bottom: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20,
                  color: isDark
                      ? const Color(0xFF8A9AA5)
                      : const Color(0xFF737373)),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 14,
                                color:
                                    isDark ? Colors.white : Colors.black87)),
                      ),
                      if (showBetaBadge) ...[
                        const SizedBox(width: 4),
                        Builder(builder: (context) {
                          final p = context.palette;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: p.windowBgActive,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            // settingsPremiumNewBadge.textFg = windowFgActive
                            // (settings.style:148), not hardcoded white.
                            child: Text('BETA',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: p.windowFgActive)),
                          );
                        }),
                      ],
                    ],
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF6D7F8F)
                                  : const Color(0xFF999999))),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AyuToggle(
              value: value,
              onChanged: onChanged,
              isMaterial: useMaterial,
            ),
          ],
        ),
      ),
    );
  }
}

class _AyuSlider extends StatefulWidget {
  final String label;
  final int steps;
  final int current;
  final int Function(int) indexToValue;
  final String Function(int) formatLabel;
  final ValueChanged<int>? onChanged;
  final ValueChanged<int>? onFinalChanged;
  final bool isDark;
  final bool showTitle;

  const _AyuSlider({
    required this.label,
    required this.steps,
    required this.current,
    required this.indexToValue,
    required this.formatLabel,
    this.onChanged,
    this.onFinalChanged,
    required this.isDark,
    this.showTitle = true,
  });

  @override
  State<_AyuSlider> createState() => _AyuSliderState();
}

class _AyuSliderState extends State<_AyuSlider> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.current;
  }

  @override
  void didUpdateWidget(_AyuSlider old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _currentIndex = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Slider track/thumb FILL is windowBgActive (#40a7e3, the bright blue) — that
    // is the correct token for the slider itself and is left unchanged. Only the
    // value LABEL uses a different (active-text) blue, handled below.
    final accentColor = p.windowBgActive;
    final displayValue = widget.indexToValue(_currentIndex);
    final valueText = widget.formatLabel(displayValue);

    // settingsScaleLabel = FlatLabel(defaultFlatLabel){ textFg: windowActiveTextFg }
    // (settings.style:70-72). windowActiveTextFg is #168acd (the online/active-text
    // blue) — NOT windowBgActive #40a7e3 (the bright fill blue). This is the exact
    // wrong-blue this file's header (addSectionTitle) warns against.
    final labelStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: p.windowActiveTextFg,
    );

    // MakeSliderWithLabel (settings_common.cpp:580-615): a single row with the
    // slider on the LEFT (width = outer − labelArea) and the value label flush
    // RIGHT, vertically centred. The label is ALWAYS created; `showTitle` only
    // governs the separate title button above and the min-label-width reserve
    // (ayu_builder.cpp:193-207). minLabelWidth = font->width("8%%%") when a title
    // is shown (keeps the track width steady as the value text grows), else 0.
    final minLabelWidth =
        widget.showTitle ? _measureWidth('8%%%', labelStyle, context) : 0.0;
    final labelAreaWidth =
        math.max(_measureWidth(valueText, labelStyle, context), minLabelWidth);

    final slider = SliderTheme(
      data: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor:
            widget.isDark ? const Color(0xFF2B3C4C) : const Color(0xFFD5D5D5),
        thumbColor: accentColor,
        overlayColor: const Color(0x2940A7E3),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
      ),
      child: Slider(
        value: _currentIndex.toDouble(),
        min: 0,
        // AyuGram setPseudoDiscrete: sectionsCount = valuesCount - 1, so valid
        // indices are 0..steps-1 (continuous_sliders.h:186). Callers pass
        // steps = valuesCount, so subtract 1 here. Flutter renders `divisions: N`
        // + `max: N` as N+1 stops, hence steps-1 for both.
        max: (widget.steps - 1).toDouble(),
        divisions: widget.steps - 1,
        onChanged: (d) {
          final idx = d.round();
          // Live value-label update is local (setState on _currentIndex) and
          // always runs; the persist callback fires per-frame only when a caller
          // supplies one. A null onChanged means label-only live update —
          // AyuGram's `.onChanged = nullptr`.
          setState(() => _currentIndex = idx);
          widget.onChanged?.call(widget.indexToValue(idx));
        },
        onChangeEnd: widget.onFinalChanged == null
            ? null
            : (d) {
                widget.onFinalChanged!(widget.indexToValue(d.round()));
              },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The title is a SEPARATE full-width button ABOVE the slider, shown only
        // when showTitle — settingsButtonNoIcon, padding margins(22,10,22,8),
        // transparent to mouse (ayu_builder.cpp:193-199, settings.style:25-27).
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
            child: Text(widget.label,
                style: TextStyle(
                    fontSize: 14,
                    color: widget.isDark ? Colors.white : Colors.black87)),
          ),
        // recentStickersLimitPadding = margins(22,4,22,8) (ayu_styles.style:21).
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Row(
            children: [
              // slider->resizeToWidth(outer − right): the track fills the row
              // minus the reserved label area.
              Expanded(child: slider),
              // label->moveToRight(0, ...): flush right within its reserved area,
              // vertically centred against the slider row.
              SizedBox(
                width: labelAreaWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(valueText, style: labelStyle, maxLines: 1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Mirrors AyuGram's `font->width(text)` / `label->sizeValue().width()` so the
  // reserved label area is max(value width, minLabelWidth) — identical to
  // MakeSliderWithLabel's `std::max(size.width(), minLabelWidth)`.
  double _measureWidth(String text, TextStyle style, BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = tp.width;
    tp.dispose();
    return width;
  }
}

class _AyuChooseButton extends StatelessWidget {
  final String label;
  final int value;
  final Map<int, String> items;
  final ValueChanged<int> onChanged;
  final bool isDark;
  final IconData? icon;

  const _AyuChooseButton({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDark,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // AddButtonWithLabel's right label uses defaultSettingsRightLabel, whose
    // textFg is windowActiveTextFg (#168acd, the online/active-text blue) — NOT
    // windowBgActive #40a7e3 (the bright fill blue) (widgets.style:1514-1515,1526).
    final rightLabelColor = context.palette.windowActiveTextFg;
    final currentLabel = items[value] ?? '';
    return InkWell(
      onTap: () => _showChoiceDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20,
                  color: isDark
                      ? const Color(0xFF8A9AA5)
                      : const Color(0xFF737373)),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            const SizedBox(width: 12),
            Text(currentLabel,
                style: TextStyle(fontSize: 13, color: rightLabelColor)),
          ],
        ),
      ),
    );
  }

  void _showChoiceDialog(BuildContext context) {
    showTelegramBox(
      context: context,
      builder: (ctx) => _SingleChoiceBox(
        title: label,
        items: items,
        currentValue: value,
        onChanged: (v) {
          onChanged(v);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
}

class _SingleChoiceBox extends StatelessWidget {
  final String title;
  final Map<int, String> items;
  final int currentValue;
  final ValueChanged<int> onChanged;

  const _SingleChoiceBox({
    required this.title,
    required this.items,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TelegramBox(
      title: title,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items.entries.map((e) {
            final selected = e.key == currentValue;
            return InkWell(
              onTap: () => onChanged(e.key),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.value,
                          style: TextStyle(fontSize: 14, color: p.boxTextFg)),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? p.windowBgActive
                              : p.boxTextFg.withValues(alpha: 0.3),
                          width: selected ? 6 : 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _AyuCollapsibleToggle extends StatefulWidget {
  final String label;
  final bool isExpanded;
  final bool isDark;
  final bool useMaterial;
  final List<AyuNestedCheckboxItem> children;
  final ValueChanged<bool>? onMasterToggle;
  final bool? masterValue;
  final bool toggledWhenAll;

  const _AyuCollapsibleToggle({
    required this.label,
    required this.isExpanded,
    required this.isDark,
    this.useMaterial = false,
    required this.children,
    this.onMasterToggle,
    this.masterValue,
    this.toggledWhenAll = true,
  });

  @override
  State<_AyuCollapsibleToggle> createState() => _AyuCollapsibleToggleState();
}

class _AyuCollapsibleToggleState extends State<_AyuCollapsibleToggle> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.isExpanded;
  }

  @override
  void didUpdateWidget(_AyuCollapsibleToggle old) {
    super.didUpdateWidget(old);
    if (old.isExpanded != widget.isExpanded) _open = widget.isExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final checkedCount = widget.children.where((c) => c.value).length;
    final totalCount = widget.children.length;
    final hasMaster = widget.onMasterToggle != null;
    final lockedCount = widget.children.where((c) => c.isLocked).length;
    final canLockMore = lockedCount + 1 < widget.children.length;

    final bool toggleValue;
    if (widget.masterValue != null) {
      toggleValue = widget.masterValue!;
    } else if (widget.toggledWhenAll) {
      final unlocked = widget.children.where((c) => !c.isLocked).toList();
      toggleValue = unlocked.isNotEmpty && unlocked.every((c) => c.value);
    } else {
      toggleValue = widget.children.any((c) => !c.isLocked && c.value);
    }

    final textColor = widget.isDark ? Colors.white : Colors.black87;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 0),
          child: Row(
            children: [
              // Label + checked/total count + expand arrow — one tappable area.
              // AyuGram's AddInnerToggle places the arrow at
              // labelLeft + label->naturalWidth() (hugging the RIGHT edge of the
              // text, NOT flush right) and it coexists with the master toggle on
              // the far right (settings_ayu_utils.cpp:228-285). Flexible lets the
              // text take its natural width so the arrow hugs it, shrinking with
              // ellipsis only when the label is too long (matching the C++
              // min(labelLeft+naturalWidth, labelRight-arrowWidth) clamp).
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: widget.label,
                                  style: TextStyle(
                                      fontSize: 14, color: textColor),
                                ),
                                TextSpan(
                                  text: '  $checkedCount/$totalCount',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: textColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0.0,
                          // slideWrapDuration = 150ms; the arrow rotates in sync
                          // with the SlideWrap expand/collapse, easeOutCubic
                          // (settings_ayu_utils.cpp:296, basic.style:96).
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutCubic,
                          // permissionsExpandIcon = "info/edit/expand_arrow_small"
                          // (24×24) tinted windowBoldFg — a Telegram chevron, not
                          // a Material glyph (info.style:1314).
                          child: CustomPaint(
                            size: const Size(20, 20),
                            painter: _ExpandArrowPainter(
                                color: context.palette.windowBoldFg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasMaster) ...[
                // Separator: 1px wide, height = 2*toggle.border + toggle.diameter
                // = 2*2 + 14 = 18. powerSavingButtonNoIcon.toggle = infoProfileToggle
                // = Toggle(defaultToggle) → border 2px, diameter 14px (widgets.style
                // defaultToggle). Filled with textBgOver (= windowBgOver, inherited
                // from defaultSettingsButton) (settings_ayu_utils.cpp:170-171,182-186).
                Container(
                  width: 1,
                  height: 18,
                  color: context.palette.windowBgOver,
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final v = !toggleValue;
                    for (final child in widget.children) {
                      if (!child.isLocked && child.value != v) {
                        child.onChanged(v);
                      }
                    }
                    widget.onMasterToggle!(v);
                  },
                  // rightsButtonToggleWidth = 70px; the toggle is aligned flush
                  // right so it lines up with normal toggles in the list
                  // (settings_ayu_utils.cpp:175-188, boxes.style:587).
                  child: SizedBox(
                    width: 70,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IgnorePointer(
                        child: AyuToggle(
                          value: toggleValue,
                          onChanged: (_) {},
                          isMaterial: widget.useMaterial,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // AyuGram expands via Ui::SlideWrap (height + opacity, easeOutCubic,
        // slideWrapDuration = 150ms) — settings_ayu_utils.cpp:286-301.
        // AnimatedSize handles height; a 0->1 opacity tween fades the rows in
        // on expand (AnimatedSize alone only animates height).
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  builder: (_, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  child: Column(
                    children: widget.children
                        .map((item) => _NestedCheckbox(
                              label: item.label,
                              value: item.value,
                              onChanged: item.onChanged,
                              isDark: widget.isDark,
                              isLocked: item.isLocked,
                              onLockToggle: item.lockSetter,
                              canLock: !item.isLocked ? canLockMore : true,
                            ))
                        .toList(),
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

class _NestedCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final bool isLocked;
  final ValueChanged<bool>? onLockToggle;
  final bool canLock;

  const _NestedCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isDark,
    this.isLocked = false,
    this.onLockToggle,
    this.canLock = true,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = context.palette.windowBgActive;
    final borderColor = isDark
        ? const Color(0xFF5A6A78)
        : const Color(0xFFCBCBCB);
    return InkWell(
      onTap: () {
        if (HardwareKeyboard.instance.isShiftPressed && onLockToggle != null) {
          if (isLocked || canLock) {
            onLockToggle!(!isLocked);
          }
        } else if (!isLocked) {
          onChanged(!value);
        }
      },
      child: Opacity(
        opacity: isLocked ? 0.4 : 1.0,
        child: Padding(
          padding:
              const EdgeInsets.only(left: 57, right: 22, top: 8, bottom: 8),
          child: Row(
            children: [
              _TgCheckbox(
                value: value,
                activeColor: activeColor,
                borderColor: borderColor,
              ),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TgCheckbox extends StatelessWidget {
  final bool value;
  final Color activeColor;
  final Color borderColor;

  const _TgCheckbox({
    required this.value,
    required this.activeColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _TgCheckboxPainter(
          checked: value,
          activeColor: activeColor,
          borderColor: borderColor,
        ),
      ),
    );
  }
}

class _TgCheckboxPainter extends CustomPainter {
  final bool checked;
  final Color activeColor;
  final Color borderColor;

  _TgCheckboxPainter({
    required this.checked,
    required this.activeColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));

    if (checked) {
      final fillPaint = Paint()..color = activeColor;
      canvas.drawRRect(rrect, fillPaint);

      final checkPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path()
        ..moveTo(size.width * 0.25, size.height * 0.5)
        ..lineTo(size.width * 0.42, size.height * 0.67)
        ..lineTo(size.width * 0.75, size.height * 0.33);

      canvas.drawPath(path, checkPaint);
    } else {
      final borderPaint = Paint()
        ..color = borderColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(rrect.deflate(1), borderPaint);
    }
  }

  @override
  bool shouldRepaint(_TgCheckboxPainter old) =>
      old.checked != checked ||
      old.activeColor != activeColor ||
      old.borderColor != borderColor;
}

/// Telegram "info/edit/expand_arrow_small" — a thin downward chevron, replacing
/// Material's `Icons.expand_more`. Tinted windowBoldFg, rotated 180° on expand
/// by the parent AnimatedRotation (info.style:1314).
class _ExpandArrowPainter extends CustomPainter {
  final Color color;

  _ExpandArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const halfW = 4.5;
    const halfH = 2.25;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(cx - halfW, cy - halfH)
      ..lineTo(cx, cy + halfH)
      ..lineTo(cx + halfW, cy - halfH);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ExpandArrowPainter old) => old.color != color;
}

Scaffold ayuSettingsScaffold({
  required BuildContext context,
  required String title,
  required List<Widget> children,
  List<Widget>? actions,
}) {
  final p = context.palette;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(
      backgroundColor: p.titleBg,
      foregroundColor: isDark ? Colors.white : Colors.black87,
      elevation: 0,
      title: Text(title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: actions,
    ),
    body: ListView(
      padding: EdgeInsets.zero,
      children: children,
    ),
  );
}
