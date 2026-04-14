import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../bridge/engine_service.dart';
import '../theme/theme.dart';

/// Settings screen — theme, notifications, cache, account management.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final config = appState.config;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ──
          const _SectionTitle(title: 'Appearance'),
          _SettingTile(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: config.theme == 'dark' ? 'Dark' : config.theme == 'light' ? 'Light' : 'System',
            onTap: () => _showThemePicker(context, appState),
          ),
          _SettingTile(
            icon: Icons.text_fields,
            title: 'Font Scale',
            subtitle: '${(config.fontScale * 100).round()}%',
            onTap: () => _showFontScalePicker(context),
          ),
          _SettingTile(
            icon: Icons.language,
            title: 'Language',
            subtitle: config.language == 'en' ? 'English' : config.language,
            onTap: () {},
          ),

          const SizedBox(height: 16),

          // ── Privacy ──
          const _SectionTitle(title: 'Privacy'),
          _SettingSwitch(
            icon: Icons.done_all,
            title: 'Send read receipts',
            value: config.sendReadReceipts,
            onChanged: (v) {},
          ),
          _SettingSwitch(
            icon: Icons.edit_note,
            title: 'Send typing indicator',
            value: config.sendTyping,
            onChanged: (v) {},
          ),

          const SizedBox(height: 16),

          // ── Notifications ──
          const _SectionTitle(title: 'Notifications'),
          _SettingSwitch(
            icon: Icons.chat_bubble_outline,
            title: 'Direct messages',
            value: config.notifyDms,
            onChanged: (v) {},
          ),
          _SettingSwitch(
            icon: Icons.group_outlined,
            title: 'Group messages',
            value: config.notifyGroups,
            onChanged: (v) {},
          ),
          _SettingSwitch(
            icon: Icons.alternate_email,
            title: 'Mentions only',
            value: config.notifyMentionsOnly,
            onChanged: (v) {},
          ),

          const SizedBox(height: 16),

          // ── Storage ──
          const _SectionTitle(title: 'Storage'),
          _SettingTile(
            icon: Icons.folder_outlined,
            title: 'Download directory',
            subtitle: config.downloadDir.isNotEmpty ? config.downloadDir : 'Default',
            onTap: () {},
          ),
          _SettingTile(
            icon: Icons.storage,
            title: 'Cache size',
            subtitle: _formatBytes(context.read<EngineService>().getCacheSize()),
            onTap: () {},
          ),
          _SettingTile(
            icon: Icons.delete_sweep_outlined,
            title: 'Clear cache',
            subtitle: 'Remove downloaded media',
            onTap: () => _confirmClearCache(context),
          ),

          const SizedBox(height: 16),

          // ── Accounts ──
          const _SectionTitle(title: 'Accounts'),
          for (final account in appState.accounts)
            _SettingTile(
              icon: Icons.account_circle_outlined,
              title: account.displayName.isNotEmpty ? account.displayName : account.platform,
              subtitle: '${account.platform} — ${_connLabel(appState.connStateFor(account.id))}',
              onTap: () {},
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                onPressed: () => _confirmRemoveAccount(context, appState, account.id, account.platform),
                splashRadius: 18,
              ),
            ),

          const SizedBox(height: 32),

          // ── About ──
          Center(
            child: Text(
              'UniClient v0.1.0',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showThemePicker(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final entry in {'dark': 'Dark', 'light': 'Light', 'system': 'System'}.entries)
            SimpleDialogOption(
              onPressed: () {
                appState.updateTheme(entry.key);
                Navigator.pop(ctx);
              },
              child: Text(entry.value),
            ),
        ],
      ),
    );
  }

  void _showFontScalePicker(BuildContext context) {
    // Placeholder — would show a slider
  }

  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text('This will remove all downloaded media files. Messages will not be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<EngineService>().clearCache();
              Navigator.pop(ctx);
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveAccount(BuildContext context, AppState appState, String accountId, String platform) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $platform account?'),
        content: const Text('This will remove the account and all cached data. You can add it back later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              appState.removeAccount(accountId);
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _connLabel(dynamic state) => switch (state.toString()) {
    'ConnState.connected' => 'Connected',
    'ConnState.connecting' => 'Connecting...',
    'ConnState.unstable' => 'Unstable',
    'ConnState.authRequired' => 'Auth required',
    _ => 'Disconnected',
  };
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Color(0xFF4F6EF7),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      activeThumbColor: AppColors.accent,
    );
  }
}
