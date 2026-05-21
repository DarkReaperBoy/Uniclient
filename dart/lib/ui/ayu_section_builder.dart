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

  Color get _textColor => isDark ? Colors.white : Colors.black87;
  Color get _subtitleColor =>
      isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
  Color get _accentColor =>
      isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
  Color get _dividerColor =>
      isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);

  void addSectionTitle(String title) {
    _children.add(Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 10, 9),
      child: Text(title,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: _accentColor)),
    ));
  }

  void addSubsectionTitle(String title) {
    _children.add(Padding(
      padding: const EdgeInsets.fromLTRB(22, 7, 10, 9),
      child: Text(title,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: _accentColor)),
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
    required ValueChanged<int> onChanged,
  }) {
    _children.add(_AyuSlider(
      label: label,
      steps: steps,
      current: current,
      indexToValue: indexToValue,
      formatLabel: formatLabel,
      onChanged: onChanged,
      isDark: isDark,
    ));
  }

  void addChooseButton({
    required String label,
    required int value,
    required Map<int, String> items,
    required ValueChanged<int> onChanged,
  }) {
    _children.add(_AyuChooseButton(
      label: label,
      value: value,
      items: items,
      onChanged: onChanged,
      isDark: isDark,
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

  void addBetaBadge(String text, {required String labelText}) {
    if (_children.isEmpty) return;
    final lastWidget = _children.removeLast();
    _children.add(_BetaBadgeOverlay(
      badge: text,
      isDark: isDark,
      child: lastWidget,
      labelText: labelText,
    ));
  }

  void addSectionDivider() {
    _children.add(Column(
      children: [
        const SizedBox(height: 6),
        Container(height: 1, color: _dividerColor),
        const SizedBox(height: 6),
      ],
    ));
  }

  void addSkip([double height = 7]) {
    _children.add(SizedBox(height: height));
  }

  void addDescription(String text) {
    _children.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: _subtitleColor)),
    ));
  }

  void addDividerText(String text) {
    _children.add(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: _dividerColor),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 7, 22, 0),
          child: Text(text,
              style: TextStyle(fontSize: 12, color: _subtitleColor)),
        ),
      ],
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

  const _BetaBadgeOverlay({
    required this.badge,
    required this.isDark,
    required this.child,
    this.labelText,
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
      _leftOffset = 22 + _textPainter!.width + 4;
    } else {
      _textPainter = null;
      _leftOffset = 26;
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
          child: Align(
            alignment: Alignment.centerLeft,
            child: Builder(builder: (context) {
              final badgeColor = context.palette.windowBgActive;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(widget.badge,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              );
            }),
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
                          final badgeColor = context.palette.windowBgActive;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('BETA',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
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
  final ValueChanged<int> onChanged;
  final bool isDark;

  const _AyuSlider({
    required this.label,
    required this.steps,
    required this.current,
    required this.indexToValue,
    required this.formatLabel,
    required this.onChanged,
    required this.isDark,
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
    final accentColor = context.palette.windowBgActive;
    final displayValue = widget.indexToValue(_currentIndex);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label,
                    style: TextStyle(
                        fontSize: 14,
                        color: widget.isDark ? Colors.white : Colors.black87)),
              ),
              Text(widget.formatLabel(displayValue),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.palette.windowBgActive)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor:
                  widget.isDark ? const Color(0xFF2B3C4C) : const Color(0xFFD5D5D5),
              thumbColor: accentColor,
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: _currentIndex.toDouble(),
              min: 0,
              max: widget.steps.toDouble(),
              divisions: widget.steps,
              onChanged: (d) {
                final idx = d.round();
                setState(() => _currentIndex = idx);
                widget.onChanged(widget.indexToValue(idx));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AyuChooseButton extends StatelessWidget {
  final String label;
  final int value;
  final Map<int, String> items;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const _AyuChooseButton({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = context.palette.windowBgActive;
    final currentLabel = items[value] ?? '';
    return InkWell(
      onTap: () => _showChoiceDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            const SizedBox(width: 12),
            Text(currentLabel,
                style: TextStyle(fontSize: 13, color: accentColor)),
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
      toggleValue = widget.children
          .where((c) => !c.isLocked)
          .every((c) => c.value);
    } else {
      toggleValue = widget.children.any((c) => c.value);
    }

    final accentColor = context.palette.windowBgActive;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final dividerColor = widget.isDark
        ? const Color(0xFF2B3C4C)
        : const Color(0xFFD5D5D5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 0),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: widget.label,
                            style: TextStyle(fontSize: 14, color: textColor),
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
                ),
              ),
              if (hasMaster) ...[
                Container(
                  width: 1,
                  height: 18,
                  color: dividerColor,
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
                  child: SizedBox(
                    width: 70,
                    child: Center(
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
              ] else
                InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: AnimatedRotation(
                      turns: _open ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: accentColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: _open
              ? Column(
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
                )
              : const SizedBox.shrink(),
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
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

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
