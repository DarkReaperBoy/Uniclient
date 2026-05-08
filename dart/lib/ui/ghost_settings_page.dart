import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import 'ayu_toggle.dart';
import 'settings_style.dart';
import 'telegram_toast.dart';

class GhostSettingsPage extends StatelessWidget {
  const GhostSettingsPage({super.key});

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
        title: const Text('AyuGram',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 7),
          // ── Ghost essentials (§51.2.1) ──
          _GhostEssentialsHeader(
            sectionLabelColor: sectionLabelColor,
            accounts: appState.accounts,
            useGlobal: appState.useGlobalGhostMode,
            activeAccount: appState.activeAccount,
            onScopeChanged: (bool global, String? userId) {
              if (global) {
                appState.setUseGlobalGhostMode(true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Switched to same settings for all accounts.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } else {
                appState.setUseGlobalGhostMode(false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Switched to individual settings for each account.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          _GhostMasterToggle(
            label: 'Ghost Mode',
            value: appState.ghostModeEnabled,
            onChanged: (v) {
              final before = appState.ghostModeEnabled;
              appState.setGhostModeEnabled(v);
              if (before != appState.ghostModeEnabled) {
                showTelegramToast(context, appState.ghostModeEnabled
                    ? 'Ghost Mode turned on'
                    : 'Ghost Mode turned off');
              }
            },
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
            value: appState.markReadAfterAction,
            onChanged: (v) => appState.setMarkReadAfterAction(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _DividerText(
            text: 'Automatically marks a message as read when you send a reply, react, or vote in a poll.',
            color: subtitleColor,
          ),
          _ToggleRow(
            label: 'Schedule Messages',
            value: appState.useScheduledMessages,
            onChanged: (v) => appState.setUseScheduledMessages(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _DividerText(
            text: 'Automatically schedules outgoing messages to send after ~12 seconds. Avoid using on unreliable networks.',
            color: subtitleColor,
          ),
          _ToggleRow(
            label: 'Send without Sound',
            value: appState.sendWithoutSound,
            onChanged: (v) => appState.setSendWithoutSound(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _DividerText(
            text: 'Sends outgoing messages without sound by default.',
            color: subtitleColor,
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Spy essentials (§51.4) ──
          _SectionLabel(label: 'Spy essentials', color: sectionLabelColor),
          _ToggleRow(
            label: 'Save Deleted Messages',
            value: appState.saveDeletedMessages,
            onChanged: (v) => appState.setSaveDeletedMessages(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Save Messages History',
            value: appState.saveMessagesHistory,
            onChanged: (v) => appState.setSaveMessagesHistory(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          Container(height: 1, color: dividerColor, margin: const EdgeInsets.symmetric(horizontal: 22)),
          _ToggleRow(
            label: 'Save for Bots',
            value: appState.saveForBots,
            onChanged: (v) => appState.setSaveForBots(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Other (§51.4) ──
          _SectionLabel(label: 'Other', color: sectionLabelColor),
          _ToggleRow(
            label: 'Local Premium',
            value: appState.localPremium,
            onChanged: (v) => appState.setLocalPremium(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Disable Ads',
            value: appState.disableAds,
            onChanged: (v) => appState.setDisableAds(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Drawer Elements (§50.3.3 / §50.8) ──
          _SectionLabel(label: 'Drawer Elements', color: sectionLabelColor),
          _ToggleRow(
            label: 'Ghost Mode',
            value: appState.showGhostToggleInDrawer,
            onChanged: (v) => appState.setShowGhostToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Read Receipts (LRead)',
            value: appState.showLReadToggleInDrawer,
            onChanged: (v) => appState.setShowLReadToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          _ToggleRow(
            label: 'Story Reads (SRead)',
            value: appState.showSReadToggleInDrawer,
            onChanged: (v) => appState.setShowSReadToggleInDrawer(v),
            isDark: isDark,
            useMaterial: appState.materialSwitches,
          ),
          if (Platform.isWindows || Platform.isMacOS)
            _ToggleRow(
              label: 'Streamer Mode',
              value: appState.showStreamerToggleInDrawer,
              onChanged: (v) => appState.setShowStreamerToggleInDrawer(v),
              isDark: isDark,
              useMaterial: appState.materialSwitches,
            ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // ── Tray Elements (§50.3.3 / §50.8) ──
          if (!Platform.isAndroid && !Platform.isIOS) ...[
            _SectionLabel(label: 'Tray Elements', color: sectionLabelColor),
            _ToggleRow(
              label: 'Ghost Mode',
              value: appState.showGhostToggleInTray,
              onChanged: (v) => appState.setShowGhostToggleInTray(v),
              isDark: isDark,
              useMaterial: appState.materialSwitches,
            ),
            if (Platform.isWindows || Platform.isMacOS)
              _ToggleRow(
                label: 'Streamer Mode',
                value: appState.showStreamerToggleInTray,
                onChanged: (v) => appState.setShowStreamerToggleInTray(v),
                isDark: isDark,
                useMaterial: appState.materialSwitches,
              ),
          ],
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

class _DividerText extends StatelessWidget {
  final String text;
  final Color color;
  const _DividerText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final bool useMaterial;

  const _ToggleRow({
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
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
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
              color: value ? context.palette.windowBgActive : (isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999)),
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
                    activeColor: context.palette.windowBgActive,
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

class _GhostEssentialsHeader extends StatelessWidget {
  final Color sectionLabelColor;
  final List<AccountInfo> accounts;
  final bool useGlobal;
  final AccountInfo? activeAccount;
  final void Function(bool global, String? userId) onScopeChanged;

  const _GhostEssentialsHeader({
    required this.sectionLabelColor,
    required this.accounts,
    required this.useGlobal,
    required this.activeAccount,
    required this.onScopeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showPicker = accounts.length > 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTextFg = isDark
        ? const Color(0xFF6AB2F2)
        : const Color(0xFF3390EC);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Row(
        children: [
          Text('Ghost essentials',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: sectionLabelColor)),
          if (showPicker) ...[
            const SizedBox(width: 8),
            _AccountPickerButton(
              accounts: accounts,
              useGlobal: useGlobal,
              activeAccount: activeAccount,
              activeTextFg: activeTextFg,
              onScopeChanged: onScopeChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountPickerButton extends StatelessWidget {
  final List<AccountInfo> accounts;
  final bool useGlobal;
  final AccountInfo? activeAccount;
  final Color activeTextFg;
  final void Function(bool global, String? userId) onScopeChanged;

  const _AccountPickerButton({
    required this.accounts,
    required this.useGlobal,
    required this.activeAccount,
    required this.activeTextFg,
    required this.onScopeChanged,
  });

  static String accountLabel(AccountInfo a) {
    if (a.displayName.isNotEmpty) return a.displayName;
    if (a.phone.isNotEmpty) return a.phone;
    final platformName = a.platform.isNotEmpty
        ? '${a.platform[0].toUpperCase()}${a.platform.substring(1)}'
        : 'Account';
    final shortId = a.id.length > 8 ? a.id.substring(a.id.length - 8) : a.id;
    return '$platformName ($shortId)';
  }

  String get _currentLabel {
    if (useGlobal) return 'Global';
    if (activeAccount != null) return accountLabel(activeAccount!);
    return 'Account';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currentLabel,
            style: TextStyle(
              fontSize: 14,
              color: activeTextFg,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: activeTextFg,
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);
    final Size buttonSize = button.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + buttonSize.height,
        offset.dx + buttonSize.width,
        offset.dy + buttonSize.height,
      ),
      color: isDark ? const Color(0xFF1B2836) : Colors.white,
      items: [
        PopupMenuItem<String>(
          value: 'global',
          child: Row(
            children: [
              _GlobalSettingsAvatar(),
              const SizedBox(width: 10),
              const Text('Global Settings'),
            ],
          ),
        ),
        ...accounts.map((a) => PopupMenuItem<String>(
          value: a.selfUserId,
          child: Row(
            children: [
              _AccountAvatar(account: a),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  accountLabel(a),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        )),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'global') {
        onScopeChanged(true, null);
      } else {
        onScopeChanged(false, value);
      }
    });
  }
}

class _GlobalSettingsAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
        ),
      ),
      child: const Center(
        child: Text(
          'GS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  final AccountInfo account;
  const _AccountAvatar({required this.account});

  @override
  Widget build(BuildContext context) {
    if (account.avatarPath.isNotEmpty) {
      final file = File(account.avatarPath);
      if (file.existsSync()) {
        return ClipOval(
          child: Image.file(file, width: 30, height: 30, fit: BoxFit.cover),
        );
      }
    }
    final palette = context.palette;
    final name = _AccountPickerButton.accountLabel(account);
    final initial = name.characters.first.toUpperCase();
    const colorRemap = [0, 7, 4, 1, 6, 3, 5];
    final numId = int.tryParse(account.selfUserId) ?? account.selfUserId.hashCode.abs();
    final avatarColor = palette.peerUserpicBg(colorRemap[numId.abs() % 7]);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
