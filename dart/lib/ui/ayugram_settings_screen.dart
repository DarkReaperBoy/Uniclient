import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../version.g.dart';
import '../theme/theme_tokens.dart';
import 'ayu_appearance_page.dart';
import 'ayu_chats_page.dart';
import 'ayu_filters_page.dart';
import 'ayu_general_page.dart';
import 'ayu_other_page.dart';
import 'box_content_divider.dart';
import 'ghost_settings_page.dart';
import 'settings_style.dart';

class AyuGramSettingsScreen extends StatelessWidget {
  const AyuGramSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sectionLabelColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final subtitleColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final textColor = isDark ? Colors.white : Colors.black87;

    final iconColors = [
      context.palette.windowBgActive, const Color(0xFF5288C1),
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
      body: Builder(builder: (_) {
        final _lvKids = <Widget>[
          Center(
            child: SizedBox(
              width: TgTokens.settingsCloudPasswordIconSize,
              height: TgTokens.settingsCloudPasswordIconSize,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Image.asset(
                  'assets/icons/ayu/$selectedIcon.png',
                  fit: BoxFit.contain,
                  cacheWidth: 200,
                  cacheHeight: 200,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: BoxDecoration(
                      color: logoColor,
                      borderRadius: BorderRadius.circular(
                          (TgTokens.settingsCloudPasswordIconSize - 10) / 2),
                    ),
                    child: Center(
                      child: Icon(
                        _iconForTheme(selectedIcon),
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Center(
            child: Text(
              'AyuGram Desktop v$appVersionString',
              style: TextStyle(
                fontSize: 16,
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

          const SizedBox(height: 32),
          const BoxContentDivider(),
          const SizedBox(height: 7),

          // Categories section (§54.17)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 9),
            child: Text('Categories',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: sectionLabelColor)),
          ),

          _FlatCategoryButton(
            // AyuGram = menuIconGroupReactions ("menu/group_reactions" = heart)
            icon: Icons.favorite_border,
            label: 'AyuGram',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const GhostSettingsPage()),
          ),
          _FlatCategoryButton(
            icon: Icons.label_outlined,
            label: 'Filters',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const AyuFiltersPage()),
          ),
          _FlatCategoryButton(
            // General = menuIconShowAll ("menu/all_media" = 2x2 grid)
            icon: Icons.grid_view_outlined,
            label: 'General',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const AyuGeneralPage()),
          ),
          _FlatCategoryButton(
            icon: Icons.palette,
            label: 'Appearance',
            isDark: isDark,
            onTap: () =>
                _pushPage(context, appState, const AyuAppearancePage()),
          ),
          _FlatCategoryButton(
            icon: Icons.chat_bubble,
            label: 'Chats',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const AyuChatsPage()),
          ),
          _FlatCategoryButton(
            // Other = menuIconFave ("menu/favorite" = star outline)
            icon: Icons.star_outline,
            label: 'Other',
            isDark: isDark,
            onTap: () => _pushPage(context, appState, const AyuOtherPage()),
          ),

          const SizedBox(height: 7),
          const BoxContentDivider(),
          const SizedBox(height: 7),

          // Links section (§54.17)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 9),
            child: Text('Links',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: sectionLabelColor)),
          ),

          _LinkButton(
            icon: Icons.campaign,
            label: 'Channel',
            rightLabel: '@ayugram',
            isDark: isDark,
            onTap: () => _navigateToPeer(context, 'ayugram'),
          ),
          _LinkButton(
            icon: Icons.forum,
            label: 'Chats',
            rightLabel: '@ayugramchat',
            isDark: isDark,
            onTap: () => _navigateToPeer(context, 'ayugramchat'),
          ),
          _LinkButton(
            icon: Icons.translate,
            label: 'Translate',
            rightLabel: 'Crowdin',
            isDark: isDark,
            onTap: () => _openUrl(context, 'https://translate.ayugram.one'),
          ),
          _LinkButton(
            icon: Icons.dns,
            label: 'Documentation',
            rightLabel: 'docs.ayugram.one',
            isDark: isDark,
            onTap: () => _openUrl(context, 'https://docs.ayugram.one'),
          ),

          const SizedBox(height: 24),
        ];
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      }),
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

  static IconData _iconForTheme(String theme) {
    return switch (theme) {
      'discord' => Icons.headphones,
      'spotify' => Icons.music_note,
      'extera' || 'extera2' => Icons.auto_awesome,
      'nothing' => Icons.circle_outlined,
      'bard' => Icons.auto_fix_high,
      'yaplus' => Icons.add_circle_outline,
      'win95' => Icons.window,
      'chibi' || 'chibi2' => Icons.face,
      'alt' => Icons.swap_horiz,
      _ => Icons.send,
    };
  }

  static Future<void> _openUrl(BuildContext context, String url) async {
    final launched =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  static void _navigateToPeer(BuildContext context, String username) {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) {
      _openUrl(context, 'https://t.me/$username');
      return;
    }
    final overlay = OverlayEntry(
      builder: (_) => const Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
    Overlay.of(context).insert(overlay);
    engine.resolveUsername(accountId, username).then((chatId) {
      overlay.remove();
      if (chatId != null && chatId.isNotEmpty && context.mounted) {
        final chatState = context.read<ChatState>();
        chatState.openChatById(chatId);
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        _openUrl(context, 'https://t.me/$username');
      }
    }).catchError((_) {
      overlay.remove();
      _openUrl(context, 'https://t.me/$username');
    });
  }

}

class _FlatCategoryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _FlatCategoryButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final iconColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    return InkWell(
      onTap: onTap,
      child: Padding(
        // AyuGram settingsButton: padding margins(60px,10,22,10), iconLeft 20px.
        // Outer left=20 puts the icon's left edge at 20px; the 40px box ends at
        // 60px so the label starts at 60px (settingsButton.padding.left).
        padding: const EdgeInsets.fromLTRB(20, 10, 22, 10),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(icon, size: 24, color: iconColor),
              ),
            ),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: SettingsStyle.buttonFontSize,
                      color: textColor)),
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
  final VoidCallback onTap;

  const _LinkButton({
    required this.icon,
    required this.label,
    required this.rightLabel,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final iconColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    return InkWell(
      onTap: onTap,
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
