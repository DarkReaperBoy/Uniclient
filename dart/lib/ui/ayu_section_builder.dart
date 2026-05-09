import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/telegram_palette.dart';

import 'ayu_toggle.dart';

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
      padding: const EdgeInsets.fromLTRB(22, 7, 10, 9),
      child: Text(title,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: _accentColor)),
    ));
  }

  void addSettingToggle({
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool showBetaBadge = false,
  }) {
    _children.add(_AyuSettingToggle(
      label: label,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
      isDark: isDark,
      useMaterial: useMaterial,
      showBetaBadge: showBetaBadge,
    ));
  }

  void addSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    _children.add(_AyuSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      valueLabel: valueLabel,
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
  }) {
    _children.add(_AyuCollapsibleToggle(
      label: label,
      isExpanded: isExpanded,
      isDark: isDark,
      useMaterial: useMaterial,
      children: children,
      onMasterToggle: onMasterToggle,
      masterValue: masterValue,
    ));
  }

  void addBetaBadge(String text) {
    // No-op: AyuGram has no standalone badge row. Use showBetaBadge on toggle rows instead.
  }

  void addSectionDivider() {
    _children.add(Column(
      children: [
        const SizedBox(height: 7),
        Container(height: 1, color: _dividerColor),
        const SizedBox(height: 7),
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

class _AyuSettingToggle extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final bool useMaterial;
  final bool showBetaBadge;

  const _AyuSettingToggle({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
    this.useMaterial = false,
    this.showBetaBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
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
                        const SizedBox(width: 6),
                        Builder(builder: (context) {
                          final badgeColor = context.palette.windowBgActive;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('BETA',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
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

class _AyuSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const _AyuSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = context.palette.windowBgActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87)),
              ),
              Text(valueLabel,
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
                  isDark ? const Color(0xFF2B3C4C) : const Color(0xFFD5D5D5),
              thumbColor: accentColor,
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
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
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
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
    final bgColor = isDark ? const Color(0xFF1B2836) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(label,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
        contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: items.entries.map((e) => RadioListTile<int>(
            title: Text(e.value,
                style: TextStyle(fontSize: 14, color: textColor)),
            value: e.key,
            groupValue: value,
            activeColor: accentColor,
            onChanged: (v) {
              if (v != null) {
                onChanged(v);
                Navigator.of(ctx).pop();
              }
            },
          )).toList(),
        ),
      ),
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

  const _AyuCollapsibleToggle({
    required this.label,
    required this.isExpanded,
    required this.isDark,
    this.useMaterial = false,
    required this.children,
    this.onMasterToggle,
    this.masterValue,
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
    final allChecked = widget.children.every((c) => c.value);
    final toggleValue = widget.masterValue ?? allChecked;
    final accentColor = widget.isDark
        ? const Color(0xFF6AB2F2)
        : const Color(0xFF3390EC);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(widget.label,
                          style: TextStyle(
                              fontSize: 14,
                              color: widget.isDark
                                  ? Colors.white
                                  : Colors.black87)),
                      if (!hasMaster && checkedCount > 0) ...[
                        const SizedBox(width: 8),
                        Text('$checkedCount/$totalCount',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: accentColor)),
                      ],
                    ],
                  ),
                ),
                if (hasMaster) ...[
                  const SizedBox(width: 12),
                  AyuToggle(
                    value: toggleValue,
                    onChanged: (v) {
                      for (final child in widget.children) {
                        if (!child.isLocked && child.value != v) {
                          child.onChanged(v);
                        }
                      }
                      widget.onMasterToggle!(v);
                    },
                    isMaterial: widget.useMaterial,
                  ),
                ] else
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: accentColor,
                  ),
              ],
            ),
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

  const _NestedCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isDark,
    this.isLocked = false,
    this.onLockToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (HardwareKeyboard.instance.isShiftPressed && onLockToggle != null) {
          onLockToggle!(!isLocked);
        } else if (!isLocked) {
          onChanged(!value);
        }
      },
      child: Opacity(
        opacity: isLocked ? 0.4 : 1.0,
        child: Padding(
          padding:
              const EdgeInsets.only(left: 44, right: 22, top: 6, bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: value,
                  onChanged: isLocked
                      ? null
                      : (v) => onChanged(v ?? false),
                  activeColor: isDark
                      ? const Color(0xFF6AB2F2)
                      : const Color(0xFF3390EC),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF5A6A78)
                        : const Color(0xFFCBCBCB),
                    width: 2,
                  ),
                ),
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

Scaffold ayuSettingsScaffold({
  required BuildContext context,
  required String title,
  required List<Widget> children,
  List<Widget>? actions,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(
      backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
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
