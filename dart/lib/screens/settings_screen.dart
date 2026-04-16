import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../theme/theme.dart';
import '../utils/debug.dart';

/// Settings screen — theme, notifications, cache, account management.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppConfig _config;
  bool _configLoaded = false;

  /// Per-platform accent color overrides (platform name → hex string).
  /// UI-only — not persisted to the engine.
  final Map<String, String> _platformThemes = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_configLoaded) {
      _refreshConfig();
      _configLoaded = true;
    }
  }

  void _refreshConfig() {
    try {
      final engine = context.read<EngineService>();
      setState(() {
        _config = engine.getConfig();
      });
    } catch (_) {
      // Engine not initialized — use AppState's cached config.
      setState(() {
        _config = context.read<AppState>().config;
      });
    }
  }

  void _updateAndRefresh({
    String? theme,
    String? accentColor,
    double? fontScale,
    String? language,
    String? downloadDir,
    int? maxCacheSize,
    bool? sendReadReceipts,
    bool? sendTyping,
    bool? notifyDms,
    bool? notifyGroups,
    bool? notifyMentionsOnly,
  }) {
    final engine = context.read<EngineService>();
    engine.updateConfig(
      theme: theme,
      accentColor: accentColor,
      fontScale: fontScale,
      language: language,
      downloadDir: downloadDir,
      maxCacheSize: maxCacheSize,
      sendReadReceipts: sendReadReceipts,
      sendTyping: sendTyping,
      notifyDms: notifyDms,
      notifyGroups: notifyGroups,
      notifyMentionsOnly: notifyMentionsOnly,
    );
    // If theme changed, also update AppState so the app-wide ThemeMode reacts.
    if (theme != null) {
      context.read<AppState>().updateTheme(theme);
    }
    _refreshConfig();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
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
          // -- Appearance --
          const _SectionTitle(title: 'Appearance'),
          _SettingTile(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: _config.theme == 'dark' ? 'Dark' : _config.theme == 'light' ? 'Light' : 'System',
            onTap: () => _showThemePicker(context),
          ),
          _SettingTile(
            icon: Icons.text_fields,
            title: 'Font Scale',
            subtitle: '${(_config.fontScale * 100).round()}%',
            onTap: () => _showFontScalePicker(context),
          ),
          _SettingTile(
            icon: Icons.language,
            title: 'Language',
            subtitle: _config.language == 'en' ? 'English' : _languageLabel(_config.language),
            onTap: () => _showLanguagePicker(context),
          ),

          const SizedBox(height: 16),

          // -- Accent Color --
          const _SectionTitle(title: 'Accent Color'),
          _AccentColorPicker(
            selected: _config.accentColor,
            onSelect: (hex) {
              setState(() {
                _config = AppConfig(
                  theme: _config.theme,
                  accentColor: hex,
                  fontScale: _config.fontScale,
                  language: _config.language,
                  downloadDir: _config.downloadDir,
                  maxCacheSize: _config.maxCacheSize,
                  sendReadReceipts: _config.sendReadReceipts,
                  sendTyping: _config.sendTyping,
                  notifyDms: _config.notifyDms,
                  notifyGroups: _config.notifyGroups,
                  notifyMentionsOnly: _config.notifyMentionsOnly,
                );
              });
              _updateAndRefresh(accentColor: hex);
            },
          ),

          const SizedBox(height: 16),

          // -- Platform Themes --
          const _SectionTitle(title: 'Platform Themes'),
          if (appState.platforms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'No connected platforms yet.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                ),
              ),
            )
          else
            for (final platform in appState.platforms)
              _PlatformThemeTile(
                platform: platform,
                overrideHex: _platformThemes[platform],
                onSelect: (hex) {
                  setState(() {
                    if (hex == null) {
                      _platformThemes.remove(platform);
                    } else {
                      _platformThemes[platform] = hex;
                    }
                  });
                },
              ),

          const SizedBox(height: 16),

          // -- Privacy --
          const _SectionTitle(title: 'Privacy'),
          _SettingSwitch(
            icon: Icons.done_all,
            title: 'Send read receipts',
            value: _config.sendReadReceipts,
            onChanged: (v) {
              setState(() {
                _config = AppConfig(
                  theme: _config.theme,
                  accentColor: _config.accentColor,
                  fontScale: _config.fontScale,
                  language: _config.language,
                  downloadDir: _config.downloadDir,
                  maxCacheSize: _config.maxCacheSize,
                  sendReadReceipts: v,
                  sendTyping: _config.sendTyping,
                  notifyDms: _config.notifyDms,
                  notifyGroups: _config.notifyGroups,
                  notifyMentionsOnly: _config.notifyMentionsOnly,
                );
              });
              _updateAndRefresh(sendReadReceipts: v);
            },
          ),
          _SettingSwitch(
            icon: Icons.edit_note,
            title: 'Send typing indicator',
            value: _config.sendTyping,
            onChanged: (v) {
              setState(() {
                _config = AppConfig(
                  theme: _config.theme,
                  accentColor: _config.accentColor,
                  fontScale: _config.fontScale,
                  language: _config.language,
                  downloadDir: _config.downloadDir,
                  maxCacheSize: _config.maxCacheSize,
                  sendReadReceipts: _config.sendReadReceipts,
                  sendTyping: v,
                  notifyDms: _config.notifyDms,
                  notifyGroups: _config.notifyGroups,
                  notifyMentionsOnly: _config.notifyMentionsOnly,
                );
              });
              _updateAndRefresh(sendTyping: v);
            },
          ),

          const SizedBox(height: 16),

          // -- Notifications --
          const _SectionTitle(title: 'Notifications'),
          _SettingSwitch(
            icon: Icons.chat_bubble_outline,
            title: 'Direct messages',
            value: _config.notifyDms,
            onChanged: (v) {
              setState(() {
                _config = AppConfig(
                  theme: _config.theme,
                  accentColor: _config.accentColor,
                  fontScale: _config.fontScale,
                  language: _config.language,
                  downloadDir: _config.downloadDir,
                  maxCacheSize: _config.maxCacheSize,
                  sendReadReceipts: _config.sendReadReceipts,
                  sendTyping: _config.sendTyping,
                  notifyDms: v,
                  notifyGroups: _config.notifyGroups,
                  notifyMentionsOnly: _config.notifyMentionsOnly,
                );
              });
              _updateAndRefresh(notifyDms: v);
            },
          ),
          _SettingSwitch(
            icon: Icons.group_outlined,
            title: 'Group messages',
            value: _config.notifyGroups,
            onChanged: (v) {
              setState(() {
                _config = AppConfig(
                  theme: _config.theme,
                  accentColor: _config.accentColor,
                  fontScale: _config.fontScale,
                  language: _config.language,
                  downloadDir: _config.downloadDir,
                  maxCacheSize: _config.maxCacheSize,
                  sendReadReceipts: _config.sendReadReceipts,
                  sendTyping: _config.sendTyping,
                  notifyDms: _config.notifyDms,
                  notifyGroups: v,
                  notifyMentionsOnly: _config.notifyMentionsOnly,
                );
              });
              _updateAndRefresh(notifyGroups: v);
            },
          ),
          _SettingSwitch(
            icon: Icons.alternate_email,
            title: 'Mentions only',
            value: _config.notifyMentionsOnly,
            onChanged: (v) {
              setState(() {
                _config = AppConfig(
                  theme: _config.theme,
                  accentColor: _config.accentColor,
                  fontScale: _config.fontScale,
                  language: _config.language,
                  downloadDir: _config.downloadDir,
                  maxCacheSize: _config.maxCacheSize,
                  sendReadReceipts: _config.sendReadReceipts,
                  sendTyping: _config.sendTyping,
                  notifyDms: _config.notifyDms,
                  notifyGroups: _config.notifyGroups,
                  notifyMentionsOnly: v,
                );
              });
              _updateAndRefresh(notifyMentionsOnly: v);
            },
          ),

          const SizedBox(height: 16),

          // -- Download Location --
          const _SectionTitle(title: 'Download Location'),
          _SettingTile(
            icon: Icons.folder_outlined,
            title: 'Save files to',
            subtitle: _config.downloadDir.isNotEmpty ? _config.downloadDir : 'Default',
            onTap: () => _showDownloadDirDialog(context),
          ),

          const SizedBox(height: 16),

          // -- Storage --
          const _SectionTitle(title: 'Storage'),
          _SettingTile(
            icon: Icons.sd_storage_outlined,
            title: 'Max cache size',
            subtitle: _formatBytes(_config.maxCacheSize),
            onTap: () => _showMaxCacheSizePicker(context),
          ),
          _SettingTile(
            icon: Icons.storage,
            title: 'Cache size',
            subtitle: _formatBytes(context.read<EngineService>().getCacheSize()),
            onTap: () => _confirmClearCache(context),
          ),
          _SettingTile(
            icon: Icons.delete_sweep_outlined,
            title: 'Clear cache',
            subtitle: 'Remove downloaded media',
            onTap: () => _confirmClearCache(context),
          ),

          const SizedBox(height: 16),

          // -- Accounts --
          const _SectionTitle(title: 'Accounts'),
          for (final account in appState.accounts)
            _SettingTile(
              icon: Icons.account_circle_outlined,
              title: account.displayName.isNotEmpty ? account.displayName : account.platform,
              subtitle: '${account.platform} — ${_connLabel(appState.connStateFor(account.id))}',
              onTap: () {
                final connState = appState.connStateFor(account.id);
                // No action on tap — accounts connect automatically
              },
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                onPressed: () => _confirmRemoveAccount(context, appState, account.id, account.platform),
                splashRadius: 18,
              ),
            ),

          const SizedBox(height: 16),

          // -- Developer --
          const _SectionTitle(title: 'Developer'),
          _DebugToggle(),

          const SizedBox(height: 32),

          // -- About --
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

  void _showThemePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final entry in {'dark': 'Dark', 'light': 'Light', 'system': 'System'}.entries)
            SimpleDialogOption(
              onPressed: () {
                _updateAndRefresh(theme: entry.key);
                Navigator.pop(ctx);
              },
              child: Text(entry.value),
            ),
        ],
      ),
    );
  }

  void _showFontScalePicker(BuildContext context) {
    double currentScale = _config.fontScale;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Font Scale'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(currentScale * 100).round()}%',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Slider(
                value: currentScale,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                label: '${(currentScale * 100).round()}%',
                onChanged: (v) {
                  setDialogState(() => currentScale = v);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('50%', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  Text('200%', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _updateAndRefresh(fontScale: currentScale);
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  static const _languages = <String, String>{
    'en': 'English',
    'fa': 'فارسی (Persian)',
    'ar': 'العربية (Arabic)',
    'ru': 'Русский (Russian)',
    'tr': 'Türkçe (Turkish)',
    'de': 'Deutsch (German)',
    'fr': 'Français (French)',
    'es': 'Español (Spanish)',
    'pt': 'Português (Portuguese)',
    'zh': '中文 (Chinese)',
    'ja': '日本語 (Japanese)',
    'ko': '한국어 (Korean)',
  };

  String _languageLabel(String code) => _languages[code] ?? code;

  void _showLanguagePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Language'),
        children: [
          for (final entry in _languages.entries)
            SimpleDialogOption(
              onPressed: () {
                _updateAndRefresh(language: entry.key);
                Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Expanded(child: Text(entry.value)),
                  if (_config.language == entry.key)
                    const Icon(Icons.check, size: 18, color: AppColors.accent),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showMaxCacheSizePicker(BuildContext context) {
    final options = <int, String>{
      256 * 1024 * 1024: '256 MB',
      512 * 1024 * 1024: '512 MB',
      1024 * 1024 * 1024: '1 GB',
      2 * 1024 * 1024 * 1024: '2 GB',
      5 * 1024 * 1024 * 1024: '5 GB',
    };
    final currentSize = _config.maxCacheSize;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Max Cache Size'),
        children: [
          for (final entry in options.entries)
            SimpleDialogOption(
              onPressed: () {
                _updateAndRefresh(maxCacheSize: entry.key);
                Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Expanded(child: Text(entry.value)),
                  if (currentSize == entry.key)
                    const Icon(Icons.check, size: 18, color: AppColors.accent),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showDownloadDirDialog(BuildContext context) {
    final controller = TextEditingController(text: _config.downloadDir);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the directory path where downloaded files will be saved.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Directory path',
                hintText: '/home/user/Downloads',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (_) {
                _applyDownloadDir(ctx, controller.text.trim());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _applyDownloadDir(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _applyDownloadDir(BuildContext ctx, String path) {
    if (path.isEmpty) return;
    Navigator.pop(ctx);
    setState(() {
      _config = AppConfig(
        theme: _config.theme,
        accentColor: _config.accentColor,
        fontScale: _config.fontScale,
        language: _config.language,
        downloadDir: path,
        maxCacheSize: _config.maxCacheSize,
        sendReadReceipts: _config.sendReadReceipts,
        sendTyping: _config.sendTyping,
        notifyDms: _config.notifyDms,
        notifyGroups: _config.notifyGroups,
        notifyMentionsOnly: _config.notifyMentionsOnly,
      );
    });
    _updateAndRefresh(downloadDir: path);
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
              // Refresh to update displayed cache size.
              _refreshConfig();
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

  String _connLabel(ConnState state) => switch (state) {
    ConnState.connected => 'Connected',
    ConnState.connecting => 'Connecting...',
    ConnState.unstable => 'Unstable',
    ConnState.disconnected => 'Disconnected',
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

class _AccentColorPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  static const _presets = [
    ('#4F6EF7', 'Blue-Indigo'),
    ('#7C3AED', 'Purple'),
    ('#EC4899', 'Pink'),
    ('#EF4444', 'Red'),
    ('#F97316', 'Orange'),
    ('#F59E0B', 'Amber'),
    ('#22C55E', 'Green'),
    ('#14B8A6', 'Teal'),
    ('#06B6D4', 'Cyan'),
    ('#0EA5E9', 'Sky'),
    ('#64748B', 'Slate'),
    ('#F43F5E', 'Rose'),
  ];

  const _AccentColorPicker({required this.selected, required this.onSelect});

  static Color _parse(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSelected = selected.toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _presets.map((entry) {
          final hex = entry.$1;
          final label = entry.$2;
          final isSelected = hex.toUpperCase() == normalizedSelected ||
              hex.toLowerCase() == selected.toLowerCase();
          final color = _parse(hex);
          return Tooltip(
            message: label,
            child: GestureDetector(
              onTap: () => onSelect(hex),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withAlpha(128), blurRadius: 6, spreadRadius: 1)]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// A list tile for a single platform that shows its accent override as a
/// colored dot and opens a picker dialog on tap.
class _PlatformThemeTile extends StatelessWidget {
  final String platform;

  /// Hex string of the current override, or null if using the app default.
  final String? overrideHex;

  /// Called with a hex string to set an override, or null to clear it.
  final ValueChanged<String?> onSelect;

  const _PlatformThemeTile({
    required this.platform,
    required this.overrideHex,
    required this.onSelect,
  });

  static Color _parse(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final color = overrideHex != null ? _parse(overrideHex!) : null;

    return ListTile(
      leading: const Icon(Icons.color_lens_outlined, size: 22),
      title: Text(platform, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        overrideHex ?? 'Default',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? Colors.transparent,
          border: Border.all(
            color: color != null ? color : Colors.grey,
            width: color != null ? 0 : 1.5,
          ),
        ),
        child: color == null
            ? const Icon(Icons.block, size: 12, color: Colors.grey)
            : null,
      ),
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => _showPicker(context),
    );
  }

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _PlatformColorPickerDialog(
        platform: platform,
        currentHex: overrideHex,
        onSelect: (hex) {
          onSelect(hex);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

/// Dialog for picking (or clearing) a per-platform accent color.
class _PlatformColorPickerDialog extends StatelessWidget {
  final String platform;
  final String? currentHex;
  final ValueChanged<String?> onSelect;

  static const _presets = _AccentColorPicker._presets;

  const _PlatformColorPickerDialog({
    required this.platform,
    required this.currentHex,
    required this.onSelect,
  });

  static Color _parse(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final normalizedCurrent = currentHex?.toUpperCase();

    return AlertDialog(
      title: Text('$platform theme'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pick an accent color for this platform:',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _presets.map((entry) {
              final hex = entry.$1;
              final label = entry.$2;
              final isSelected = normalizedCurrent != null &&
                  hex.toUpperCase() == normalizedCurrent;
              final color = _parse(hex);
              return Tooltip(
                message: label,
                child: GestureDetector(
                  onTap: () => onSelect(hex),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                      boxShadow: isSelected
                          ? [BoxShadow(
                              color: color.withAlpha(128),
                              blurRadius: 6,
                              spreadRadius: 1,
                            )]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (currentHex != null)
          TextButton(
            onPressed: () => onSelect(null),
            child: const Text('Use Default'),
          ),
      ],
    );
  }
}

class _DebugToggle extends StatefulWidget {
  @override
  State<_DebugToggle> createState() => _DebugToggleState();
}

class _DebugToggleState extends State<_DebugToggle> {
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.bug_report, size: 22),
      title: const Text('Debug mode', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        Debug.enabled ? 'Logging to terminal' : 'Off',
        style: const TextStyle(fontSize: 12),
      ),
      value: Debug.enabled,
      onChanged: (v) {
        setState(() => Debug.enabled = v);
        Debug.log('DEBUG', 'Debug mode ${v ? 'ENABLED' : 'DISABLED'}');
      },
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      activeThumbColor: AppColors.accent,
    );
  }
}
