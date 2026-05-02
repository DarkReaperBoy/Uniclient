import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
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
          // ── Ghost essentials (§51.2.1) ──
          _SectionLabel(label: 'Ghost essentials', color: sectionLabelColor),
          _GhostMasterToggle(
            label: 'Ghost Mode',
            value: appState.ghostModeEnabled,
            onChanged: (v) => appState.setGhostModeEnabled(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: appState.ghostModeEnabled
                ? Column(
                    children: [
                      _LockableToggleRow(
                        label: "Don't Read Messages",
                        subtitle: 'Block read receipts from being sent',
                        value: !appState.sendReadMessages,
                        locked: appState.sendReadMessagesLocked,
                        onChanged: (v) => appState.setSendReadMessages(!v),
                        onLock: () => appState.toggleLock('sendReadMessages'),
                        isDark: isDark,
                      ),
                      _LockableToggleRow(
                        label: "Don't Read Stories",
                        subtitle: 'Block story view confirmations',
                        value: !appState.sendReadStories,
                        locked: appState.sendReadStoriesLocked,
                        onChanged: (v) => appState.setSendReadStories(!v),
                        onLock: () => appState.toggleLock('sendReadStories'),
                        isDark: isDark,
                      ),
                      _LockableToggleRow(
                        label: "Don't Send Online",
                        subtitle: 'Never report online status to the server',
                        value: !appState.sendOnlinePackets,
                        locked: appState.sendOnlinePacketsLocked,
                        onChanged: (v) => appState.setSendOnlinePackets(!v),
                        onLock: () => appState.toggleLock('sendOnlinePackets'),
                        isDark: isDark,
                      ),
                      _LockableToggleRow(
                        label: "Don't Send Typing",
                        subtitle: 'Block typing and upload progress indicators',
                        value: !appState.sendUploadProgress,
                        locked: appState.sendUploadProgressLocked,
                        onChanged: (v) => appState.setSendUploadProgress(!v),
                        onLock: () => appState.toggleLock('sendUploadProgress'),
                        isDark: isDark,
                      ),
                      _LockableToggleRow(
                        label: 'Go Offline Automatically',
                        subtitle: 'Immediately go offline after any online appearance',
                        value: appState.sendOfflinePacketAfterOnline,
                        locked: appState.sendOfflinePacketAfterOnlineLocked,
                        onChanged: (v) => appState.setSendOfflinePacketAfterOnline(v),
                        onLock: () => appState.toggleLock('sendOfflinePacketAfterOnline'),
                        isDark: isDark,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          _ToggleRow(
            label: 'Read on Interact',
            subtitle: 'Automatically marks a message as read when you send a reply, react, or forward',
            value: appState.markReadAfterAction,
            onChanged: (v) => appState.setMarkReadAfterAction(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text(
              'Shift+click or long-press any option to lock it from changing when toggling Ghost Mode.',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ),
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
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Messages section ──
          _SectionLabel(label: 'Messages', color: sectionLabelColor),
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
          _ToggleRow(
            label: 'Semi-transparent deleted messages',
            subtitle: 'Reduce opacity for deleted messages (beta)',
            value: appState.semiTransparentDeleted,
            onChanged: (v) => appState.setSemiTransparentDeleted(v),
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
          _SliderRow(
            label: 'Avatar corner radius',
            value: appState.avatarCornerRadius,
            min: 0,
            max: 50,
            divisions: 50,
            valueLabel: appState.avatarCornerRadius == 50
                ? 'Circle'
                : appState.avatarCornerRadius == 0
                    ? 'Square'
                    : '${appState.avatarCornerRadius}',
            onChanged: (v) => appState.setAvatarCornerRadius(v.round()),
            isDark: isDark,
          ),
          _AvatarPreview(
            cornerRadius: appState.avatarCornerRadius,
            isDark: isDark,
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
            if (useMaterial)
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xFF40A7E3),
              )
            else
              _TelegramToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _TelegramToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _TelegramToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: value
              ? const Color(0xFF40A7E3)
              : isDark
                  ? const Color(0xFF5A6A78)
                  : const Color(0xFFCBCBCB),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
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

class _AvatarPreview extends StatelessWidget {
  final int cornerRadius;
  final bool isDark;

  const _AvatarPreview({required this.cornerRadius, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final fraction = cornerRadius / 50.0;
    final actualRadius = 23.0 * fraction; // 46px diameter → 23px max radius = circle

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final color in [
            const Color(0xFF5E97F6),
            const Color(0xFFEB4D3D),
            const Color(0xFF8BC34A),
          ]) ...[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(actualRadius),
              ),
              child: const Center(
                child: Icon(Icons.person, color: Colors.white, size: 24),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

class _GhostMasterToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final bool useMaterial;

  const _GhostMasterToggle({
    required this.label,
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
            Icon(
              Icons.visibility_off,
              size: 20,
              color: value ? const Color(0xFF40A7E3) : (isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            const SizedBox(width: 12),
            if (useMaterial)
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xFF40A7E3),
              )
            else
              _TelegramToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _LockableToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final bool locked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onLock;
  final bool isDark;

  const _LockableToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.locked,
    required this.onChanged,
    required this.onLock,
    required this.isDark,
  });

  void _handleTap() {
    if (HardwareKeyboard.instance.isShiftPressed) {
      onLock();
    } else if (!locked) {
      onChanged(!value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLock,
      child: InkWell(
        onTap: _handleTap,
        child: Opacity(
          opacity: locked ? 0.4 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: value,
                    onChanged: locked ? null : (v) => onChanged(v ?? false),
                    activeColor: const Color(0xFF40A7E3),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF5A6A78) : const Color(0xFFCBCBCB),
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                                    color: isDark ? Colors.white : Colors.black87)),
                          ),
                          if (locked) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.lock, size: 14,
                              color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999)),
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
              ],
            ),
          ),
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
