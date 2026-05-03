import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_appearance_page.dart';
import 'ayu_chats_page.dart';
import 'ayu_filters_page.dart';
import 'ayu_general_page.dart';
import 'ayu_other_page.dart';
import 'ghost_settings_page.dart';
import 'settings_style.dart';

class AyuGramSettingsScreen extends StatelessWidget {
  const AyuGramSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final sectionLabelColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final subtitleColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final textColor = isDark ? Colors.white : Colors.black87;

    final iconColors = [
      const Color(0xFF40A7E3), const Color(0xFF5288C1),
      const Color(0xFF5865F2), const Color(0xFF1DB954),
      const Color(0xFF6B72D5), const Color(0xFF808080),
      const Color(0xFFE67E22), const Color(0xFFCC3333),
      const Color(0xFF008080), const Color(0xFFFF69B4),
      const Color(0xFFDA70D6), const Color(0xFF4169E1),
    ];
    final selectedIcon =
        appState.appIcon.isEmpty ? 'default' : appState.appIcon;
    final iconIndex = [
      'default', 'alt', 'discord', 'spotify', 'extera', 'nothing',
      'bard', 'yaplus', 'win95', 'chibi', 'chibi2', 'extera2',
    ].indexOf(selectedIcon).clamp(0, 11);
    final logoColor = iconColors[iconIndex];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: const SizedBox.shrink(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Logo widget (§54.17)
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: logoColor,
                borderRadius: BorderRadius.circular(48),
              ),
              child: Center(
                child: Text(
                  selectedIcon == 'default'
                      ? 'U'
                      : selectedIcon[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Version title (§54.17)
          Center(
            child: Text(
              'AyuGram Desktop v5.12.3',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Tagline (§54.17)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Telegram Desktop fork focused on customization '
              'and ToS-breaking features.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: subtitleColor),
            ),
          ),

          const SizedBox(height: 8),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // Categories section (§54.17)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
            child: Text('Categories',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: sectionLabelColor)),
          ),

          _CategoryButton(
            icon: Icons.emoji_emotions,
            iconBg: const Color(0xFF6B72D5),
            label: 'AyuGram',
            subtitle: appState.ghostModeEnabled ? 'Ghost Mode active' : null,
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const GhostSettingsPage()),
          ),
          _CategoryButton(
            icon: Icons.filter_alt,
            iconBg: const Color(0xFF5288C1),
            label: 'Filters',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const AyuFiltersPage()),
          ),
          _CategoryButton(
            icon: Icons.visibility,
            iconBg: const Color(0xFF40A7E3),
            label: 'General',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const AyuGeneralPage()),
          ),
          _CategoryButton(
            icon: Icons.palette,
            iconBg: const Color(0xFFE67E22),
            label: 'Appearance',
            isDark: isDark,
            onTap: () =>
                _pushPage(context, appState, const AyuAppearancePage()),
          ),
          _CategoryButton(
            icon: Icons.chat_bubble,
            iconBg: const Color(0xFF4DC920),
            label: 'Chats',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const AyuChatsPage()),
          ),
          _CategoryButton(
            icon: Icons.star,
            iconBg: const Color(0xFFCC3333),
            label: 'Other',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const AyuOtherPage()),
          ),

          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),

          // Links section (§54.17)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
            child: Text('Links',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: sectionLabelColor)),
          ),

          _LinkButton(
            icon: Icons.campaign,
            label: 'Channel',
            rightLabel: '@ayugram',
            isDark: isDark,
          ),
          _LinkButton(
            icon: Icons.forum,
            label: 'Chats',
            rightLabel: '@ayugramchat',
            isDark: isDark,
          ),
          _LinkButton(
            icon: Icons.translate,
            label: 'Translate',
            rightLabel: 'Crowdin',
            isDark: isDark,
          ),
          _LinkButton(
            icon: Icons.description,
            label: 'Documentation',
            rightLabel: 'docs.ayugram.one',
            isDark: isDark,
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _pushPage(BuildContext context, AppState appState, Widget page) {
    Navigator.of(context).push(
      settingsPageRoute(
        ChangeNotifierProvider.value(
          value: appState,
          child: page,
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String? subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryButton({
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
    final subtextColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
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
                borderRadius:
                    BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              child: Icon(icon,
                  color: Colors.white, size: SettingsStyle.iconInner),
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
                          style:
                              TextStyle(fontSize: 12, color: subtextColor)),
                    ),
                ],
              ),
            ),
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
}

class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String rightLabel;
  final bool isDark;

  const _LinkButton({
    required this.icon,
    required this.label,
    required this.rightLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final iconColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: SettingsStyle.buttonFontSize,
                      color: textColor)),
            ),
            Text(rightLabel,
                style: TextStyle(fontSize: 13, color: accentColor)),
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
}
