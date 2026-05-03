import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/app_state.dart';
import 'ayu_section_builder.dart';

class AyuOtherPage extends StatelessWidget {
  const AyuOtherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip();

    // --- Drawer Elements (§54.8) ---
    b.addSectionTitle('Drawer Elements');
    b.addSettingToggle(
      label: 'My Profile',
      subtitle: 'Show My Profile in drawer',
      value: appState.showMyProfileInDrawer,
      onChanged: (v) => appState.setShowMyProfileInDrawer(v),
    );
    if (appState.menuBots.isNotEmpty)
      b.addSettingToggle(
        label: 'Bots',
        subtitle: 'Show menu bots in drawer',
        value: appState.showBotsInDrawer,
        onChanged: (v) => appState.setShowBotsInDrawer(v),
      );
    b.addSettingToggle(
      label: 'New Group',
      subtitle: 'Show New Group in drawer',
      value: appState.showNewGroupInDrawer,
      onChanged: (v) => appState.setShowNewGroupInDrawer(v),
    );
    b.addSettingToggle(
      label: 'New Channel',
      subtitle: 'Show New Channel in drawer',
      value: appState.showNewChannelInDrawer,
      onChanged: (v) => appState.setShowNewChannelInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Contacts',
      subtitle: 'Show Contacts in drawer',
      value: appState.showContactsInDrawer,
      onChanged: (v) => appState.setShowContactsInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Calls',
      subtitle: 'Show Calls in drawer',
      value: appState.showCallsInDrawer,
      onChanged: (v) => appState.setShowCallsInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Saved Messages',
      subtitle: 'Show Saved Messages in drawer',
      value: appState.showSavedMessagesInDrawer,
      onChanged: (v) => appState.setShowSavedMessagesInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Night Mode',
      subtitle: 'Show Night Mode toggle in drawer',
      value: appState.showDrawerThemeToggle,
      onChanged: (v) => appState.setShowDrawerThemeToggle(v),
    );
    b.addSettingToggle(
      label: 'Ghost Mode',
      subtitle: 'Show Ghost Mode toggle in drawer',
      value: appState.showGhostToggleInDrawer,
      onChanged: (v) => appState.setShowGhostToggleInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Read Receipts (LRead)',
      subtitle: 'Show Read Receipts toggle in drawer',
      value: appState.showLReadToggleInDrawer,
      onChanged: (v) => appState.setShowLReadToggleInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Story Reads (SRead)',
      subtitle: 'Show Story Reads toggle in drawer',
      value: appState.showSReadToggleInDrawer,
      onChanged: (v) => appState.setShowSReadToggleInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Streamer Mode',
      subtitle: 'Show Streamer Mode toggle in drawer',
      value: appState.showStreamerToggleInDrawer,
      onChanged: (v) => appState.setShowStreamerToggleInDrawer(v),
    );

    b.addSectionDivider();

    // --- Tray Elements (§54.8) ---
    b.addSectionTitle('Tray Elements');
    b.addSettingToggle(
      label: 'Ghost Mode',
      subtitle: 'Show Ghost Mode toggle in system tray menu',
      value: appState.showGhostToggleInTray,
      onChanged: (v) => appState.setShowGhostToggleInTray(v),
    );
    b.addSettingToggle(
      label: 'Streamer Mode',
      subtitle: 'Show Streamer Mode toggle in system tray menu',
      value: appState.showStreamerToggleInTray,
      onChanged: (v) => appState.setShowStreamerToggleInTray(v),
    );

    b.addSectionDivider();

    // --- Support / Donations (§54.15) ---
    b.addSectionTitle('Support');
    b.addWidget(_DonateButton(
      label: 'Boosty',
      iconChar: 'B',
      iconColor: const Color(0xFFF15F2C),
      isDark: isDark,
      onTap: () => Process.run('xdg-open', ['https://boosty.to/alexeyzavar']),
    ));
    b.addWidget(_DonateButton(
      label: 'TON',
      iconChar: '💎',
      iconColor: const Color(0xFF0098EA),
      isDark: isDark,
      onTap: () => _showDonateQr(
          context, 'TON', 'UQA4i8U3', const Color(0xFF0098EA), isDark),
    ));
    b.addWidget(_DonateButton(
      label: 'Bitcoin',
      iconChar: '₿',
      iconColor: const Color(0xFFF7931A),
      isDark: isDark,
      onTap: () => _showDonateQr(
          context, 'Bitcoin', 'bc1qdk6qq', const Color(0xFFF7931A), isDark),
    ));
    b.addWidget(_DonateButton(
      label: 'Ethereum',
      iconChar: 'Ξ',
      iconColor: const Color(0xFF627EEA),
      isDark: isDark,
      onTap: () => _showDonateQr(
          context, 'Ethereum', '0x405589', const Color(0xFF627EEA), isDark),
    ));
    b.addWidget(_DonateButton(
      label: 'Solana',
      iconChar: 'S',
      iconColor: const Color(0xFF9945FF),
      isDark: isDark,
      onTap: () => _showDonateQr(
          context, 'Solana', '8ZHQpPxp', const Color(0xFF9945FF), isDark),
    ));
    b.addWidget(_DonateButton(
      label: 'Tron',
      iconChar: 'T',
      iconColor: const Color(0xFFFF0013),
      isDark: isDark,
      onTap: () => _showDonateQr(
          context, 'Tron', 'TRpbajq3', const Color(0xFFFF0013), isDark),
    ));
    b.addSkip();
    b.addDescription(
        'You can support AyuGram development through donations. '
        'For questions, contact support.');
    b.addWidget(_ContactSupportLink(isDark: isDark));
    b.addSkip();

    b.addSectionDivider();

    // --- Other (§54.15) — Crash Reporting ---
    b.addSectionTitle('Other');
    b.addSettingToggle(
      label: 'Crash Reporting',
      subtitle: 'Send crash reports to developers',
      value: appState.crashReporting,
      onChanged: (v) => appState.setCrashReporting(v),
    );
    b.addSkip();
    b.addDescription('Help improve AyuGram by automatically sending '
        'crash reports when the app encounters an error.');

    b.addSectionDivider();

    // --- Utility Actions (§54.15) ---
    b.addWidget(_ActionButton(
      label: 'Register URL Scheme',
      icon: Icons.link,
      isDark: isDark,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Done'), duration: Duration(seconds: 2)),
        );
      },
    ));
    b.addWidget(_ActionButton(
      label: 'Reset Settings',
      icon: Icons.restore,
      isDark: isDark,
      onTap: () => _showResetConfirmation(context, appState),
    ));

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'Other',
      children: b.build(),
    );
  }

  static void _showDonateQr(BuildContext context, String name, String address,
      Color accentColor, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => _DonateQrBox(
        name: name,
        address: address,
        accentColor: accentColor,
        isDark: isDark,
      ),
    );
  }

  static void _showResetConfirmation(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B2836) : Colors.white,
        title: Text('Reset Settings',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600)),
        content: Text(
            'Are you sure you want to reset all AyuGram settings to defaults?\n\n'
            'This will reset ghost mode, appearance, filters, and all other AyuGram preferences.',
            style:
                TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(
                    color: isDark
                        ? const Color(0xFF6AB2F2)
                        : const Color(0xFF3390EC))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              appState.resetAyuSettings();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Done'), duration: Duration(seconds: 2)),
              );
            },
            child: Text('Reset',
                style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }
}

class _DonateButton extends StatelessWidget {
  final String label;
  final String iconChar;
  final Color iconColor;
  final bool isDark;
  final VoidCallback onTap;

  const _DonateButton({
    required this.label,
    required this.iconChar,
    required this.iconColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFFEEEEEE) : const Color(0xFF242B2C);
    const iconSize = 28.0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(iconSize / 4),
              ),
              alignment: Alignment.center,
              child: Text(
                iconChar,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: iconColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark
                    ? const Color(0xFF6D7F8F)
                    : const Color(0xFF999999)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconBgColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconBgColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: iconBgColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactSupportLink extends StatelessWidget {
  final bool isDark;

  const _ContactSupportLink({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final linkColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: GestureDetector(
        onTap: () => Process.run('xdg-open', ['tg://support']),
        child: Text('Contact support',
            style: TextStyle(fontSize: 12, color: linkColor)),
      ),
    );
  }
}

class _DonateQrBox extends StatelessWidget {
  final String name;
  final String address;
  final Color accentColor;
  final bool isDark;

  const _DonateQrBox({
    required this.name,
    required this.address,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1B2836) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: address,
                version: QrVersions.auto,
                size: 180,
                eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square, color: accentColor),
                dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              address,
              style: TextStyle(fontSize: 13, color: subtextColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close',
                      style: TextStyle(
                          color: isDark
                              ? const Color(0xFF6AB2F2)
                              : const Color(0xFF3390EC))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
