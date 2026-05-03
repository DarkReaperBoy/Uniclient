import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_toggle.dart';
import 'confirm_box.dart';
import 'ghost_settings_page.dart';
import 'settings_style.dart';

class AyuGramSettingsScreen extends StatefulWidget {
  const AyuGramSettingsScreen({super.key});

  @override
  State<AyuGramSettingsScreen> createState() => _AyuGramSettingsScreenState();
}

class _AyuGramSettingsScreenState extends State<AyuGramSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = isDark
        ? const Color(0xFF101921)
        : const Color(0xFFE0E0E0);
    final sectionLabelColor = isDark
        ? const Color(0xFF6AB2F2)
        : const Color(0xFF3390EC);
    final subtitleColor = isDark
        ? const Color(0xFF6D7F8F)
        : const Color(0xFF999999);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: const Text('AyuGram Preferences',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── AyuGram category: Ghost Mode + Spy + Other (§51.4) ──
          _NavRow(
            icon: Icons.visibility_off,
            iconBg: const Color(0xFF6B72D5),
            label: 'AyuGram',
            subtitle: appState.ghostModeEnabled ? 'Ghost Mode active' : null,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                settingsPageRoute(
                  ChangeNotifierProvider.value(
                    value: appState,
                    child: const GhostSettingsPage(),
                  ),
                ),
              );
            },
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          _ToggleRow(
            label: 'Show message seconds',
            subtitle: 'Display seconds in read timestamps (HH:mm:ss)',
            value: appState.showMessageSeconds,
            onChanged: (v) => appState.setShowMessageSeconds(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _DropdownRow(
            label: 'Read receipts in context menu',
            value: appState.showViewsPanelInContextMenu,
            items: const {
              0: 'Always visible',
              1: 'Hidden',
              2: 'Visible with Ctrl/Shift',
            },
            onChanged: (v) => appState.setShowViewsPanelInContextMenu(v),
            isDark: isDark,
          ),
          _DropdownRow(
            label: 'Repeat Message in context menu',
            value: appState.showRepeatMessageInContextMenu,
            items: const {
              0: 'Always visible',
              1: 'Hidden',
              2: 'Visible with Ctrl/Shift',
            },
            onChanged: (v) => appState.setShowRepeatMessageInContextMenu(v),
            isDark: isDark,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Spy Essentials section (§52.1) ──
          _SectionLabel(label: 'Spy Essentials', color: sectionLabelColor),
          _ToggleRow(
            label: 'Save deleted messages',
            subtitle: 'Preserve messages that others delete',
            value: appState.saveDeletedMessages,
            onChanged: (v) => appState.setSaveDeletedMessages(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Save messages history',
            subtitle: 'Keep pre-edit text of edited messages',
            value: appState.saveMessagesHistory,
            onChanged: (v) => appState.setSaveMessagesHistory(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Save for bots',
            subtitle: 'Also save deleted/edited messages from bots',
            value: appState.saveForBots,
            onChanged: (v) => appState.setSaveForBots(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Semi-transparent deleted messages',
            subtitle: 'Reduce opacity for deleted messages (beta)',
            value: appState.semiTransparentDeleted,
            onChanged: (v) => appState.setSemiTransparentDeleted(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Replace marks with icons',
            subtitle: 'Use icons instead of text for deleted/edited status',
            value: appState.replaceMarksWithIcons,
            onChanged: (v) => appState.setReplaceMarksWithIcons(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _MarkButtonRow(
            label: 'Deleted mark',
            currentValue: appState.deletedMark,
            defaultValue: '\u{1F9F9}',
            onSaved: (v) => appState.setDeletedMark(v),
            isDark: isDark,
          ),
          _MarkButtonRow(
            label: 'Edited mark',
            currentValue: appState.editedMark,
            defaultValue: '',
            onSaved: (v) => appState.setEditedMark(v),
            isDark: isDark,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Messages section ──
          _SectionLabel(label: 'Messages', color: sectionLabelColor),
          _WideMultiplierSlider(
            value: appState.wideMultiplier,
            onChanged: (v) => appState.setWideMultiplier(v),
            isDark: isDark,
          ),
          _SliderRow(
            label: 'Bubble corner radius',
            value: appState.bubbleRadius,
            min: 0,
            max: 16,
            divisions: 16,
            valueLabel: '${appState.bubbleRadius}',
            onChanged: (v) => appState.setBubbleRadius(v.round()),
            isDark: isDark,
          ),
          _BubblePreview(
            radius: appState.bubbleRadius.toDouble(),
            showTail: !appState.removeTail,
            isDark: isDark,
          ),
          _ToggleRow(
            label: 'Remove message tail',
            subtitle: 'Clean rounded rectangles without tail accent',
            value: appState.removeTail,
            onChanged: (v) => appState.setRemoveTail(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Simple quotes and replies',
            subtitle: 'Uniform reply bar style without colorful accents',
            value: appState.simpleQuotes,
            onChanged: (v) => appState.setSimpleQuotes(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Appearance section ──
          _SectionLabel(label: 'Appearance', color: sectionLabelColor),
          _ToggleRow(
            label: 'Material Design switches',
            subtitle: 'Use Material-style toggle switches throughout',
            value: appState.materialSwitches,
            onChanged: (v) => appState.setMaterialSwitches(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _AvatarCornersSection(
            corners: appState.avatarCorners,
            singleCornerRadius: appState.singleCornerRadius,
            onCornersChanged: (v) => appState.setAvatarCorners(v),
            onSingleCornerRadiusChanged: (v) => appState.setSingleCornerRadius(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Disable custom backgrounds',
            subtitle: 'Force global wallpaper on all chats',
            value: appState.disableCustomBackgrounds,
            onChanged: (v) => appState.setDisableCustomBackgrounds(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Drawer Elements section (§50.3) ──
          _SectionLabel(label: 'Drawer Elements', color: sectionLabelColor),
          _ToggleRow(
            label: 'Show Night Mode toggle',
            subtitle: 'Display theme toggle in hamburger menu',
            value: appState.showDrawerThemeToggle,
            onChanged: (v) => appState.setShowDrawerThemeToggle(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Ghost Mode',
            subtitle: 'Show Ghost Mode toggle in drawer',
            value: appState.showGhostToggleInDrawer,
            onChanged: (v) => appState.setShowGhostToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Read Receipts (LRead)',
            subtitle: 'Show Read Receipts toggle in drawer',
            value: appState.showLReadToggleInDrawer,
            onChanged: (v) => appState.setShowLReadToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Story Reads (SRead)',
            subtitle: 'Show Story Reads toggle in drawer',
            value: appState.showSReadToggleInDrawer,
            onChanged: (v) => appState.setShowSReadToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Streamer Mode',
            subtitle: 'Show Streamer Mode toggle in drawer',
            value: appState.showStreamerToggleInDrawer,
            onChanged: (v) => appState.setShowStreamerToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Tray Elements section (§50.3) ──
          _SectionLabel(label: 'Tray Elements', color: sectionLabelColor),
          _ToggleRow(
            label: 'Streamer Mode',
            subtitle: 'Show Streamer Mode toggle in system tray menu',
            value: appState.showStreamerToggleInTray,
            onChanged: (v) => appState.setShowStreamerToggleInTray(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
            child: Text(
              'These settings are specific to AyuGram/UniClient and may '
              'differ from the standard Telegram Desktop experience.',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _WideMultiplierSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const _WideMultiplierSlider({
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<_WideMultiplierSlider> createState() => _WideMultiplierSliderState();
}

class _WideMultiplierSliderState extends State<_WideMultiplierSlider> {
  late double _localValue;
  double _committedValue = -1;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
    _committedValue = widget.value;
  }

  @override
  void didUpdateWidget(_WideMultiplierSlider old) {
    super.didUpdateWidget(old);
    if ((old.value - widget.value).abs() > 0.001) {
      _localValue = widget.value;
      _committedValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF40A7E3);
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subtitleColor = widget.isDark
        ? const Color(0xFF6D7F8F)
        : const Color(0xFF999999);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Wide Messages Multiplier',
                    style: TextStyle(fontSize: 14, color: textColor)),
              ),
              Text(_localValue.toStringAsFixed(2),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF40A7E3))),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: widget.isDark
                  ? const Color(0xFF2B3C4C)
                  : const Color(0xFFD5D5D5),
              thumbColor: accentColor,
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: _localValue,
              min: 1.0,
              max: 4.0,
              divisions: 60,
              onChanged: (v) {
                setState(() => _localValue = v);
              },
              onChangeEnd: (v) {
                final snapped = (v * 20).round() / 20.0;
                if ((snapped - _committedValue).abs() < 0.001) return;
                showConfirmBox(
                  context,
                  title: 'Restart Required',
                  text: 'Some settings will be applied after restarting.',
                  confirmText: 'Apply',
                  cancelText: 'Cancel',
                  onConfirm: () {
                    _committedValue = snapped;
                    widget.onChanged(snapped);
                  },
                  onCancel: () {
                    setState(() => _localValue = _committedValue);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Change message width for better display on wide monitors.',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Text(label,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: color)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final bool useMaterial;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
    this.useMaterial = false,
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
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87)),
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

class _SliderRow extends StatelessWidget {
  final String label;
  final int value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const _SliderRow({
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
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF40A7E3))),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF40A7E3),
              inactiveTrackColor: isDark
                  ? const Color(0xFF2B3C4C)
                  : const Color(0xFFD5D5D5),
              thumbColor: const Color(0xFF40A7E3),
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: value.toDouble(),
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

class _BubblePreview extends StatelessWidget {
  final double radius;
  final bool showTail;
  final bool isDark;

  const _BubblePreview({
    required this.radius,
    required this.showTail,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final tailRadius = showTail ? (radius * 6 / 16).clamp(0.0, 6.0) : radius;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Row(
        children: [
          // Incoming bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF182533)
                  : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
                bottomLeft: Radius.circular(tailRadius),
                bottomRight: Radius.circular(radius),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.transparent
                      : const Color(0x18000000),
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text('Hello!',
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87)),
          ),
          const Spacer(),
          // Outgoing bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2B5278)
                  : const Color(0xFFEFFEDE),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
                bottomLeft: Radius.circular(radius),
                bottomRight: Radius.circular(tailRadius),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.transparent
                      : const Color(0x18000000),
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text('Hi there!',
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87)),
          ),
        ],
      ),
    );
  }
}

class _AvatarCornersSection extends StatelessWidget {
  final int corners;
  final bool singleCornerRadius;
  final ValueChanged<int> onCornersChanged;
  final ValueChanged<bool> onSingleCornerRadiusChanged;
  final bool isDark;
  final bool useMaterial;

  const _AvatarCornersSection({
    required this.corners,
    required this.singleCornerRadius,
    required this.onCornersChanged,
    required this.onSingleCornerRadiusChanged,
    required this.isDark,
    required this.useMaterial,
  });

  static const _kMax = 23;

  String get _badgeText {
    if (corners == 0) return 'SQUARE';
    if (corners >= _kMax) return 'CIRCLE';
    return '$corners';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
          child: Row(
            children: [
              Text('Avatar Corners',
                  style: TextStyle(fontSize: 14, color: textColor)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_badgeText,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
        _AvatarCornersPreview(corners: corners, isDark: isDark),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: isDark
                  ? const Color(0xFF2B3C4C)
                  : const Color(0xFFD5D5D5),
              thumbColor: accentColor,
              overlayColor: const Color(0x2940A7E3),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: corners.toDouble(),
              min: 0,
              max: _kMax.toDouble(),
              divisions: _kMax,
              onChanged: (v) => onCornersChanged(v.round()),
            ),
          ),
        ),
        _ToggleRow(
          label: 'Single corner radius',
          subtitle: 'Forums will have the same avatar shape as chats',
          value: singleCornerRadius,
          onChanged: onSingleCornerRadiusChanged,
          isDark: isDark,
          useMaterial: useMaterial,
        ),
      ],
    );
  }
}

class _AvatarCornersPreview extends StatelessWidget {
  final int corners;
  final bool isDark;

  const _AvatarCornersPreview({required this.corners, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const photoSize = 46.0;
    final avatarRadius = photoSize / 2 * (corners / 23.0);
    final bgColor = isDark ? const Color(0xFF182533) : const Color(0xFFF1F1F1);
    final nameColor = isDark ? Colors.white : Colors.black87;
    final previewColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    const rowHeight = 62.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Container(
        height: rowHeight,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: photoSize,
              height: photoSize,
              decoration: BoxDecoration(
                color: const Color(0xFF8544D6),
                borderRadius: BorderRadius.circular(avatarRadius),
              ),
              child: Center(
                child: Text('A',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.9))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('AyuGram Releases',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: nameColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('Preview of avatar corners',
                      style: TextStyle(fontSize: 13, color: previewColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String? subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.iconBg,
    required this.label,
    this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              child: Icon(icon, color: Colors.white, size: SettingsStyle.iconInner),
            ),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: SettingsStyle.buttonFontSize,
                          color: textColor)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12,
                              color: subtextColor)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark ? const Color(0xFF5A6A78) : const Color(0xFFCBCBCB)),
          ],
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final int value;
  final Map<int, String> items;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          DropdownButton<int>(
            value: value,
            underline: const SizedBox.shrink(),
            dropdownColor: isDark ? const Color(0xFF1B2836) : Colors.white,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC),
            ),
            items: items.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _MarkButtonRow extends StatelessWidget {
  final String label;
  final String currentValue;
  final String defaultValue;
  final ValueChanged<String> onSaved;
  final bool isDark;

  const _MarkButtonRow({
    required this.label,
    required this.currentValue,
    required this.defaultValue,
    required this.onSaved,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = currentValue.isEmpty ? '(default)' : currentValue;
    return InkWell(
      onTap: () => _showEditMarkBox(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            Text(displayValue,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFF6AB2F2)
                        : const Color(0xFF3390EC))),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark
                    ? const Color(0xFF5A6A78)
                    : const Color(0xFFCBCBCB)),
          ],
        ),
      ),
    );
  }

  void _showEditMarkBox(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _EditMarkBox(
        title: label,
        currentValue: currentValue,
        defaultValue: defaultValue,
        onSaved: onSaved,
      ),
    );
  }
}

class _EditMarkBox extends StatefulWidget {
  final String title;
  final String currentValue;
  final String defaultValue;
  final ValueChanged<String> onSaved;

  const _EditMarkBox({
    required this.title,
    required this.currentValue,
    required this.defaultValue,
    required this.onSaved,
  });

  @override
  State<_EditMarkBox> createState() => _EditMarkBoxState();
}

class _EditMarkBoxState extends State<_EditMarkBox> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1B2836) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor)),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF3B4A59)
                            : const Color(0xFFDDDDDD)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: accentColor, width: 2),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _resetToDefault,
                    child: Text('Reset to default',
                        style: TextStyle(fontSize: 13, color: accentColor)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(fontSize: 13, color: accentColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _save,
                    child: Text('Save',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accentColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    widget.onSaved(_controller.text);
    Navigator.of(context).pop();
  }

  void _resetToDefault() {
    _controller.text = widget.defaultValue;
  }
}

