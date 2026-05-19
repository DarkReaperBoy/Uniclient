import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../theme/telegram_palette.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../utils/spell_service.dart';
import 'chat_export.dart';
import 'settings_style.dart';
import 'telegram_toast.dart';

void showProxiesDialog(BuildContext context) {
  showDialog(context: context, builder: (_) => const _ProxiesBox());
}

/// Advanced settings page (§14.7). Opened from Settings → Advanced row.
/// Build order per §14.7.0: 11 sections separated by skip+divider+skip.
class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

enum _UpdateState { idle, checking, latest, available, failed }

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
  _UpdateState _updateState = _UpdateState.idle;
  String _latestVersion = '';
  bool _screenReaderDetected = false;
  bool _downloadingUpdate = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _detectScreenReader();
  }

  Future<void> _detectScreenReader() async {
    if (kIsWeb) return;
    var detected = false;
    if (Platform.isLinux) {
      try {
        final result = await Process.run('pgrep', ['-x', 'orca']);
        if (result.exitCode == 0) detected = true;
      } catch (_) {}
      if (!detected) {
        try {
          final result = await Process.run('gdbus', [
            'call', '--session',
            '--dest', 'org.a11y.Bus',
            '--object-path', '/org/a11y/bus',
            '--method', 'org.freedesktop.DBus.Properties.Get',
            'org.a11y.Status', 'IsEnabled',
          ]);
          final out = (result.stdout as String).trim();
          if (out.contains('true')) detected = true;
        } catch (_) {}
      }
    } else if (Platform.isMacOS) {
      try {
        final result = await Process.run('defaults', ['read', 'com.apple.universalaccess', 'voiceOverOnOffKey']);
        if ((result.stdout as String).trim() == '1') detected = true;
      } catch (_) {}
    } else if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', ['-Command',
          '(Get-ItemProperty HKCU:\\Software\\Microsoft\\Narrator\\NoRoam -Name RunningState -ErrorAction SilentlyContinue).RunningState']);
        if ((result.stdout as String).trim() == '1') detected = true;
      } catch (_) {}
    }
    if (mounted && detected != _screenReaderDetected) {
      setState(() => _screenReaderDetected = detected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = context.watch<AppState>();

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);

    // §14.7.0: 11 sections in spec order.
    final sections = <List<Widget>>[
      _buildSoftwareUpdateTop(isDark),        // 1. Update (non-auto only)
      _buildDataAndStorage(isDark, appState),   // 2. Data and Storage
      _buildAutoMediaDownload(isDark),         // 3. Automatic Media Download
      if (kIsWeb) const <Widget>[] else _buildWindowTitle(isDark, appState),     // 4. Window Title (desktop-only)
      if (kIsWeb) const <Widget>[] else _buildWindowCloseBehavior(isDark),       // 5. Window Close (Linux only)
      if (kIsWeb) const <Widget>[] else _buildSystemIntegration(isDark, appState), // 6. System Integration (desktop-only, §13.5)
      _buildPerformance(isDark),               // 7. Performance
      _buildSpellchecker(isDark),              // 8. Spellchecker
      _buildScreenReader(isDark),              // 9. Screen Reader
      _buildSoftwareUpdateBottom(isDark),      // 10. Update (auto only)
      _buildExportData(isDark),                // 11. Export Data
    ];

    // Interleave skip(7)+divider(1)+skip(7) between non-empty sections.
    final children = <Widget>[];
    var first = true;
    for (final section in sections) {
      if (section.isEmpty) continue;
      if (!first) {
        children.add(const SizedBox(height: 7));
        children.add(Container(height: 1, color: dividerColor));
        children.add(const SizedBox(height: 7));
      }
      children.addAll(section);
      first = false;
    }
    if (children.isNotEmpty) {
      children.add(const SizedBox(height: 32));
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Advanced',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: children,
      ),
    );
  }

  static void _openWithSystem(String pathOrUrl) {
    if (Platform.isMacOS) {
      Process.run('open', [pathOrUrl]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', pathOrUrl]);
    } else {
      Process.run('xdg-open', [pathOrUrl]);
    }
  }

  static const _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  String _connectionTypeLabel(AppState appState) {
    final activeId = appState.activeAccountId;
    final connState = appState.connStateFor(activeId);
    if (appState.proxyMode == 1) {
      return connState == ConnState.connected
          ? 'Connected via system proxy'
          : 'Using system proxy';
    }
    if (appState.proxyMode == 2) {
      final type = appState.selectedProxyType;
      if (connState == ConnState.connected) {
        return type.isNotEmpty ? 'Connected via $type proxy' : 'Connected via proxy';
      }
      if (connState == ConnState.connecting) {
        return type.isNotEmpty ? 'Connecting via $type proxy...' : 'Connecting via proxy...';
      }
      return type.isNotEmpty ? 'Proxy: $type' : 'Using proxy';
    }
    return switch (connState) {
      ConnState.connected => 'Connected via TCP',
      ConnState.connecting => 'Connecting...',
      ConnState.unstable => 'Connection unstable',
      ConnState.disconnected => 'Waiting for network...',
    };
  }

  static const _angleBackendLabels = [
    'Auto',
    'Direct3D 11',
    'Direct3D 9',
    'Direct3D 11 on 12',
    'OpenGL (ANGLE disabled)',
  ];

  String get _stateLabel => switch (_updateState) {
        _UpdateState.idle => 'UniClient v$_appVersion',
        _UpdateState.checking => 'Checking for updates...',
        _UpdateState.latest => 'You have the latest version installed',
        _UpdateState.available => 'New version available: $_latestVersion',
        _UpdateState.failed => 'Update check failed',
      };

  void _checkForUpdates() async {
    setState(() => _updateState = _UpdateState.checking);
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/DarkReaperBoy/uniclient/releases/latest'),
      );
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'UniClient/$_appVersion');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String?) ?? '';
        final remoteVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
        client.close();
        if (!mounted) return;
        if (remoteVersion.isNotEmpty && remoteVersion != _appVersion) {
          setState(() {
            _latestVersion = remoteVersion;
            _updateState = _UpdateState.available;
          });
        } else {
          setState(() => _updateState = _UpdateState.latest);
        }
      } else {
        client.close();
        if (mounted) setState(() => _updateState = _UpdateState.failed);
      }
    } catch (_) {
      if (mounted) setState(() => _updateState = _UpdateState.failed);
    }
  }

  Future<void> _downloadAndApplyUpdate(bool isDark) async {
    setState(() { _downloadingUpdate = true; _downloadProgress = 0; });
    try {
      final exePath = Platform.resolvedExecutable;
      final tmpPath = '$exePath.update';

      final client = HttpClient();
      final arch = Platform.version.contains('x86_64') || Platform.version.contains('x64') ? 'x64' : 'arm64';
      final assetName = Platform.isLinux ? 'uniclient-linux-$arch' : 'uniclient';
      final url = 'https://github.com/DarkReaperBoy/uniclient/releases/download/v$_latestVersion/$assetName';

      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'UniClient/$_appVersion');
      final response = await request.close();

      if (response.statusCode == 302 || response.statusCode == 301) {
        client.close();
        if (mounted) {
          setState(() => _downloadingUpdate = false);
          _openWithSystem('https://github.com/DarkReaperBoy/uniclient/releases/tag/v$_latestVersion');
        }
        return;
      }

      if (response.statusCode != 200) {
        client.close();
        if (mounted) {
          setState(() => _downloadingUpdate = false);
          showTelegramToast(context, 'Download failed (HTTP ${response.statusCode}). Opening releases page...');
          _openWithSystem('https://github.com/DarkReaperBoy/uniclient/releases/tag/v$_latestVersion');
        }
        return;
      }

      final totalBytes = response.contentLength;
      var downloadedBytes = 0;
      final file = File(tmpPath);
      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() => _downloadProgress = downloadedBytes / totalBytes);
        }
      }
      await sink.close();
      client.close();

      await Process.run('chmod', ['+x', tmpPath]);
      await File(tmpPath).rename(exePath);

      if (mounted) {
        setState(() => _downloadingUpdate = false);
        _showRestartDialog(context, isDark);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadingUpdate = false);
        showTelegramToast(context, 'Update failed: $e');
      }
    }
  }

  List<Widget> _buildSoftwareUpdate(bool isDark) {
    final appState = context.watch<AppState>();
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _SubsectionTitle(title: 'Software Update', color: accentColor),
      InkWell(
        onTap: () => appState.setAutoUpdateEnabled(!appState.autoUpdateEnabled),
        hoverColor: hoverBg,
        splashColor: hoverBg.withValues(alpha: 0.5),
        child: Padding(
          padding:
              const EdgeInsets.only(left: 22, right: 22, top: 10, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic updates',
                      style: TextStyle(fontSize: 15, color: textColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _stateLabel,
                      style: TextStyle(fontSize: 13, color: subtextColor),
                    ),
                  ],
                ),
              ),
              Switch(
                value: appState.autoUpdateEnabled,
                onChanged: (v) => appState.setAutoUpdateEnabled(v),
                activeColor: accentColor,
              ),
            ],
          ),
        ),
      ),
      if (_updateState != _UpdateState.checking)
        _AdvancedToggleRow(
          label: 'Install beta versions',
          value: appState.installBetaVersions,
          onChanged: (v) => appState.setInstallBetaVersions(v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
      InkWell(
        onTap: _updateState == _UpdateState.checking ? null : _checkForUpdates,
        hoverColor: hoverBg,
        splashColor: hoverBg.withValues(alpha: 0.5),
        child: Padding(
          padding:
              const EdgeInsets.only(left: 22, right: 22, top: 10, bottom: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Check for updates',
              style: TextStyle(
                fontSize: 15,
                color: _updateState == _UpdateState.checking
                    ? subtextColor
                    : textColor,
              ),
            ),
          ),
        ),
      ),
      if (_updateState == _UpdateState.available)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _downloadingUpdate ? null : () => _downloadAndApplyUpdate(isDark),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: _downloadingUpdate
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        const SizedBox(width: 8),
                        Text('Downloading... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    )
                  : const Text(
                      'Update UniClient',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ),
    ];
  }

  // §14.7.8 top: shown only when NOT auto-updating.
  List<Widget> _buildSoftwareUpdateTop(bool isDark) {
    final appState = context.watch<AppState>();
    if (appState.autoUpdateEnabled) return const [];
    return _buildSoftwareUpdate(isDark);
  }

  // §14.7.1: Connection Type, Download Path, Local Storage, Downloads, Ask path toggle.
  List<Widget> _buildDataAndStorage(bool isDark, AppState appState) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _SubsectionTitle(title: 'Data and Storage', color: accentColor),
      _AdvancedIconButtonRow(
        icon: Icons.settings_ethernet,
        label: 'Connection type',
        rightLabel: _connectionTypeLabel(appState),
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () => showDialog(
          context: context,
          builder: (_) => const _ProxiesBox(),
        ),
      ),
      if (!appState.askDownloadPath)
        _AdvancedIconButtonRow(
          icon: Icons.folder_open,
          label: 'Download path',
          rightLabel: appState.downloadPathLabel,
          textColor: textColor,
          subtextColor: subtextColor,
          iconColor: iconColor,
          hoverBg: hoverBg,
          onTap: () => _showDownloadPathDialog(context, appState, isDark),
        ),
      _AdvancedIconButtonRow(
        icon: Icons.storage,
        label: 'Manage local storage',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () => showDialog(
          context: context,
          builder: (_) => const _LocalStorageBox(),
        ),
      ),
      _AdvancedIconButtonRow(
        icon: Icons.download,
        label: 'Recent Downloads',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () => showDialog(
          context: context,
          builder: (_) => const _RecentDownloadsBox(),
        ),
      ),
      _AdvancedToggleRow(
        label: 'Ask download path for each file',
        value: appState.askDownloadPath,
        onChanged: (v) => appState.setAskDownloadPath(v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
    ];
  }

  void _showDownloadPathDialog(BuildContext context, AppState appState, bool isDark) {
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Download path', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
          contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DownloadPathOption(
                label: 'Default folder',
                subtitle: _defaultDownloadDir(),
                selected: appState.downloadPathMode == 0,
                accentColor: accentColor,
                textColor: textColor,
                subtextColor: subtextColor,
                isDark: isDark,
                onTap: () {
                  appState.setDownloadPathMode(0);
                  Navigator.of(ctx).pop();
                },
              ),
              _DownloadPathOption(
                label: 'Temp folder',
                subtitle: Directory.systemTemp.path,
                selected: appState.downloadPathMode == 1,
                accentColor: accentColor,
                textColor: textColor,
                subtextColor: subtextColor,
                isDark: isDark,
                onTap: () {
                  appState.setDownloadPathMode(1);
                  Navigator.of(ctx).pop();
                },
              ),
              _DownloadPathOption(
                label: appState.downloadPathMode == 2 && appState.customDownloadPath.isNotEmpty
                    ? appState.customDownloadPath
                    : 'Custom folder...',
                subtitle: appState.downloadPathMode == 2 ? appState.customDownloadPath : null,
                selected: appState.downloadPathMode == 2,
                accentColor: accentColor,
                textColor: textColor,
                subtextColor: subtextColor,
                isDark: isDark,
                onTap: () async {
                  final path = await FilePicker.platform.getDirectoryPath();
                  if (path != null && ctx.mounted) {
                    appState.setDownloadPathMode(2, path);
                    Navigator.of(ctx).pop();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: accentColor)),
            ),
          ],
        );
      },
    );
  }

  static String _defaultDownloadDir() {
    if (Platform.isMacOS) {
      return '${Platform.environment['HOME'] ?? '/tmp'}/Downloads/uniclient';
    } else if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default'}\\Downloads\\uniclient';
    }
    return '${Platform.environment['HOME'] ?? '/tmp'}/Downloads/uniclient';
  }

  // §14.7.2: Private/Groups/Channels auto-download buttons.
  List<Widget> _buildAutoMediaDownload(bool isDark) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _SubsectionTitle(title: 'Automatic Media Download', color: accentColor),
      _AdvancedIconButtonRow(
        icon: Icons.person,
        label: 'In private chats',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () => _openAutoDownloadBox(context, 'In private chats'),
      ),
      _AdvancedIconButtonRow(
        icon: Icons.group,
        label: 'In groups',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () => _openAutoDownloadBox(context, 'In groups'),
      ),
      _AdvancedIconButtonRow(
        icon: Icons.campaign,
        label: 'In channels',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () => _openAutoDownloadBox(context, 'In channels'),
      ),
    ];
  }

  void _openAutoDownloadBox(BuildContext context, String source) {
    showDialog(
      context: context,
      builder: (_) => _AutoDownloadBox(source: source),
    );
  }

  // §14.7.3: Chat name / Account name / Unread count checkboxes, native frame toggle.
  List<Widget> _buildWindowTitle(bool isDark, AppState appState) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final multiAccount = appState.accounts.length > 1;

    return [
      _SubsectionTitle(title: 'Window Title', color: accentColor),
      _AdvancedCheckboxRow(
        label: 'Show chat name in the window title',
        value: appState.showChatNameInTitle,
        onChanged: (v) => appState.setShowChatNameInTitle(v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      AnimatedSize(
        duration: appState.animDuration(const Duration(milliseconds: 200)),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: multiAccount
            ? _AdvancedCheckboxRow(
                label: 'Show account name in the window title',
                value: appState.showAccountNameInTitle,
                onChanged: (v) => appState.setShowAccountNameInTitle(v),
                textColor: textColor,
                accentColor: accentColor,
                hoverBg: hoverBg,
              )
            : const SizedBox.shrink(),
      ),
      _AdvancedCheckboxRow(
        label: 'Show total unread count in the window title',
        value: appState.showUnreadCountInTitle,
        onChanged: (v) => appState.setShowUnreadCountInTitle(v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      if (Platform.isLinux)
        _AdvancedToggleRow(
          label: Platform.environment['WAYLAND_DISPLAY'] != null
              ? 'Use Qt window frame'
              : 'Use system window frame',
          value: appState.nativeWindowFrame,
          onChanged: (v) => appState.setNativeWindowFrame(v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
    ];
  }

  // §14.7.4: Run in Background / Close to Taskbar / Quit radios. Linux/BSD only.
  // Only shown when tray icon is supported and enabled (matching AyuGram's TrayIconSupported guard).
  List<Widget> _buildWindowCloseBehavior(bool isDark) {
    if (!Platform.isLinux) return const [];
    final appState = context.read<AppState>();
    if (!appState.showTrayIcon) return const [];
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    const labels = ['Run in background', 'Close to the taskbar', 'Quit'];
    return [
      _SubsectionTitle(title: 'When Closing Window', color: accentColor),
      for (var i = 0; i < labels.length; i++)
        _AdvancedRadioRow(
          label: labels[i],
          selected: appState.windowCloseBehavior == i,
          onTap: () => appState.setWindowCloseBehavior(i),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
    ];
  }

  // §14.7.5: Tray/taskbar icons, monochrome, launch at startup, start minimized, native frame.
  List<Widget> _buildSystemIntegration(bool isDark, AppState appState) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final hasPasscode = appState.hasLocalPasscode;
    final startMinimizedDisabled = hasPasscode;

    return [
      _SubsectionTitle(title: 'System Integration', color: accentColor),
      _AdvancedCheckboxRow(
        label: 'Show tray icon',
        value: appState.showTrayIcon,
        onChanged: (v) {
          if (!appState.setShowTrayIcon(v)) {
            showTelegramToast(context, 'At least one of tray icon or taskbar icon must be enabled.');
          }
        },
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      _AdvancedCheckboxRow(
        label: 'Show taskbar icon',
        value: appState.showTaskbarIcon,
        onChanged: (v) {
          if (!appState.setShowTaskbarIcon(v)) {
            showTelegramToast(context, 'At least one of tray icon or taskbar icon must be enabled.');
          }
        },
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      AnimatedSize(
        duration: appState.animDuration(const Duration(milliseconds: 200)),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: appState.showTrayIcon
            ? _AdvancedCheckboxRow(
                label: 'Use monochrome tray icon',
                value: appState.monochromeTrayIcon,
                onChanged: (v) => appState.setMonochromeTrayIcon(v),
                textColor: textColor,
                accentColor: accentColor,
                hoverBg: hoverBg,
              )
            : const SizedBox.shrink(),
      ),
      _AdvancedCheckboxRow(
        label: 'Launch at system startup',
        value: appState.launchAtStartup,
        onChanged: (v) => appState.setLaunchAtStartup(v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      AnimatedSize(
        duration: appState.animDuration(const Duration(milliseconds: 200)),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: appState.launchAtStartup
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AdvancedCheckboxRow(
                    label: 'Start minimized',
                    value: startMinimizedDisabled ? false : appState.startMinimized,
                    onChanged: startMinimizedDisabled
                        ? (_) {}
                        : (v) => appState.setStartMinimized(v),
                    textColor: startMinimizedDisabled
                        ? textColor.withValues(alpha: 0.5)
                        : textColor,
                    accentColor: accentColor,
                    hoverBg: hoverBg,
                  ),
                  if (startMinimizedDisabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(58, 0, 22, 4),
                      child: Text(
                        'Disabled when a local passcode is set.',
                        style: TextStyle(fontSize: 12, color: subtextColor),
                      ),
                    ),
                ],
              )
            : const SizedBox.shrink(),
      ),
      if (Platform.isWindows)
        _AdvancedCheckboxRow(
          label: 'Add to "Send to" menu',
          value: appState.addToSendToMenu,
          onChanged: (v) => appState.setAddToSendToMenu(v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
      if (Platform.isMacOS) ...[
        _AdvancedCheckboxRow(
          label: 'Warn before quitting by keyboard shortcut',
          value: appState.warnBeforeQuit,
          onChanged: (v) => appState.setWarnBeforeQuit(v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
        _AdvancedCheckboxRow(
          label: 'Use system text replacements',
          value: appState.systemTextReplacements,
          onChanged: (v) => appState.setSystemTextReplacements(v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
        _AdvancedCheckboxRow(
          label: 'Round dock icon',
          value: appState.roundDockIcon,
          onChanged: (v) => appState.setRoundDockIcon(v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
      ],
    ];
  }

  // §14.7.6: Power Saving button, hardware video accel, OpenGL/ANGLE toggle.
  List<Widget> _buildPerformance(bool isDark) {
    final appState = context.read<AppState>();
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _SubsectionTitle(title: 'Performance', color: accentColor),
      _AdvancedIconButtonRow(
        icon: Icons.battery_saver,
        label: 'Power Saving',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () => showDialog(
          context: context,
          builder: (_) => ChangeNotifierProvider.value(
            value: appState,
            child: const PowerSavingBox(),
          ),
        ),
      ),
      _AdvancedToggleRow(
        label: 'Enable hardware acceleration for video',
        value: appState.hardwareAccelVideo,
        onChanged: (v) {
          appState.setHardwareAccelVideo(v);
          _showRestartDialog(context, isDark);
        },
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      if (Platform.isWindows)
        _AdvancedIconButtonRow(
          icon: Icons.display_settings,
          label: 'ANGLE graphics backend',
          rightLabel: _angleBackendLabels[appState.angleBackendIndex.clamp(0, 4)],
          textColor: textColor,
          subtextColor: subtextColor,
          iconColor: iconColor,
          hoverBg: hoverBg,
          onTap: () => _showAngleBackendDialog(context, appState, isDark),
        ),
      if (!Platform.isMacOS && !Platform.isWindows)
        _AdvancedToggleRow(
          label: 'Enable OpenGL',
          value: !appState.openGlDisabled,
          onChanged: (v) {
            appState.setOpenGlDisabled(!v);
            _showRestartDialog(context, isDark);
          },
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
    ];
  }

  void _showRestartDialog(BuildContext context, bool isDark) {
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        context.palette.windowBgActive;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Restart now?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please restart the application for this change to take effect.',
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel',
                          style: TextStyle(color: accentColor, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _restartApp(),
                      child: Text('Restart',
                          style: TextStyle(color: accentColor, fontSize: 14)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _restartApp() {
    final exe = Platform.resolvedExecutable;
    final args = Platform.executableArguments;
    final appState = context.read<AppState>();
    final env = Map<String, String>.from(Platform.environment);
    if (appState.openGlDisabled) {
      env['LIBGL_ALWAYS_SOFTWARE'] = '1';
    } else {
      env.remove('LIBGL_ALWAYS_SOFTWARE');
    }
    if (!appState.hardwareAccelVideo) {
      env['UNICLIENT_NO_HW_VIDEO'] = '1';
    } else {
      env.remove('UNICLIENT_NO_HW_VIDEO');
    }
    Process.start(exe, args, mode: ProcessStartMode.detached, environment: env).then((_) {
      exit(0);
    }).catchError((_) {
      exit(0);
    });
  }

  void _showAngleBackendDialog(BuildContext context, AppState appState, bool isDark) {
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    showDialog(
      context: context,
      builder: (ctx) {
        var selected = appState.angleBackendIndex;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => Dialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                      child: Text(
                        'ANGLE graphics backend',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                    for (var i = 0; i < _angleBackendLabels.length; i++)
                      InkWell(
                        onTap: () => setDialogState(() => selected = i),
                        hoverColor: hoverBg,
                        child: Padding(
                          padding: SettingsStyle.sendTypePadding,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Radio<int>(
                                  value: i,
                                  groupValue: selected,
                                  onChanged: (v) =>
                                      setDialogState(() => selected = v!),
                                  activeColor: accentColor,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  _angleBackendLabels[i],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text('Cancel',
                                style: TextStyle(color: accentColor, fontSize: 14)),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              if (selected != appState.angleBackendIndex) {
                                appState.setAngleBackendIndex(selected);
                                _showRestartDialog(context, isDark);
                              }
                            },
                            child: Text('Save',
                                style: TextStyle(color: accentColor, fontSize: 14)),
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
      },
    );
  }

  // §14.7.7: System/custom toggle, auto-download dictionaries, Manage Dictionaries.
  List<Widget> _buildSpellchecker(bool isDark) {
    final appState = context.read<AppState>();
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final isSystem = Platform.isLinux || Platform.isMacOS;

    return [
      _SubsectionTitle(title: 'Spellchecker', color: accentColor),
      _AdvancedToggleRow(
        label: isSystem ? 'Use system spellchecker' : 'Enable spellchecker',
        value: appState.spellcheckerEnabled,
        onChanged: (v) => appState.setSpellcheckerEnabled(v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      if (appState.spellcheckerEnabled && !isSystem) ...[
        _AdvancedToggleRow(
          label: 'Auto-download dictionaries',
          value: appState.spellcheckerAutoDownload,
          onChanged: (v) => appState.setSpellcheckerAutoDownload(v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
        _AdvancedIconButtonRow(
          icon: Icons.library_books,
          label: 'Manage Dictionaries',
          rightLabel: _getDictionaryCountLabel(),
          textColor: textColor,
          subtextColor: subtextColor,
          iconColor: iconColor,
          hoverBg: hoverBg,
          onTap: () => _showManageDictionariesDialog(context, isDark),
        ),
      ],
    ];
  }

  String _getDictionaryCountLabel() {
    if (Platform.isLinux) {
      try {
        final dir = Directory('/usr/share/hunspell');
        if (dir.existsSync()) {
          final count = dir.listSync()
              .where((f) => f.path.endsWith('.dic'))
              .length;
          return '$count';
        }
      } catch (_) {}
      return 'System';
    }
    return 'System';
  }

  void _showManageDictionariesDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (_) => _ManageDictionariesBox(isDark: isDark),
    );
  }

  List<Widget> _buildScreenReader(bool isDark) {
    final appState = context.read<AppState>();
    if (!_screenReaderDetected || appState.screenReaderOptimized) return const [];
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _SubsectionTitle(title: 'Screen Reader', color: accentColor),
      _AdvancedToggleRow(
        label: 'Disable screen reader optimization',
        value: !appState.screenReaderOptimized,
        onChanged: (v) {
          appState.setScreenReaderOptimized(!v);
          SemanticsService.announce('Screen reader optimization ${!v ? "disabled" : "enabled"}', TextDirection.ltr);
        },
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
    ];
  }

  // §14.7.8 bottom: shown only when auto-updating.
  List<Widget> _buildSoftwareUpdateBottom(bool isDark) {
    final appState = context.watch<AppState>();
    if (!appState.autoUpdateEnabled) return const [];
    return _buildSoftwareUpdate(isDark);
  }

  List<Widget> _buildExportData(bool isDark) {
    final appState = context.read<AppState>();
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _SubsectionTitle(title: 'Export Data', color: accentColor),
      _AdvancedIconButtonRow(
        icon: Icons.file_upload_outlined,
        label: 'Export Telegram Data',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () {
          final accountId = appState.activeAccountId;
          final nav = Navigator.of(context);
          final overlay = nav.overlay;
          nav.popUntil((route) => route.isFirst);
          Future.delayed(const Duration(milliseconds: 300), () {
            if (overlay == null) return;
            showExportPanelWithOverlay(
              overlay,
              ExportTarget(mode: ExportMode.full, accountId: accountId),
            );
          });
        },
      ),
      _AdvancedIconButtonRow(
        icon: Icons.science_outlined,
        label: 'Experimental Settings',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () => showDialog(
          context: context,
          builder: (_) => ChangeNotifierProvider.value(
            value: appState,
            child: const ExperimentalSettingsBox(),
          ),
        ),
      ),
    ];
  }
}

class _SubsectionTitle extends StatelessWidget {
  final String title;
  final Color color;

  const _SubsectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 7, 10, 9),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// settingsButton style row: 24px icon at 20px left, label at 60px, optional right-label.
class _AdvancedIconButtonRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? rightLabel;
  final Color textColor;
  final Color subtextColor;
  final Color iconColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _AdvancedIconButtonRow({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.subtextColor,
    required this.iconColor,
    required this.hoverBg,
    required this.onTap,
    this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (rightLabel != null)
              Text(
                rightLabel!,
                style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: subtextColor),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color textColor;
  final Color accentColor;
  final Color hoverBg;

  const _AdvancedToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.textColor,
    required this.accentColor,
    required this.hoverBg,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.noIconPadding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: textColor),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: accentColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedCheckboxRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color textColor;
  final Color accentColor;
  final Color hoverBg;

  const _AdvancedCheckboxRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.textColor,
    required this.accentColor,
    required this.hoverBg,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.checkboxPadding,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedRadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color textColor;
  final Color accentColor;
  final Color hoverBg;

  const _AdvancedRadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.textColor,
    required this.accentColor,
    required this.hoverBg,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.sendTypePadding,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Radio<bool>(
                value: true,
                groupValue: selected,
                onChanged: (_) => onTap(),
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoDownloadBox extends StatefulWidget {
  final String source;

  const _AutoDownloadBox({required this.source});

  @override
  State<_AutoDownloadBox> createState() => _AutoDownloadBoxState();
}

class _AutoDownloadBoxState extends State<_AutoDownloadBox> {
  bool _photos = true;
  bool _files = false;
  double _downloadLimit = 10;

  bool _videoMessages = true;
  bool _videos = true;
  bool _gifs = true;
  double _autoPlayLimit = 50;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final settings = appState.getAutoDownloadForSource(widget.source);
    _photos = settings['photos'] as bool? ?? true;
    _files = settings['files'] as bool? ?? false;
    _downloadLimit = (settings['downloadLimit'] as num?)?.toDouble() ?? 10;
    _videoMessages = settings['videoMessages'] as bool? ?? true;
    _videos = settings['videos'] as bool? ?? true;
    _gifs = settings['gifs'] as bool? ?? true;
    _autoPlayLimit = (settings['autoPlayLimit'] as num?)?.toDouble() ?? 50;
  }

  void _save() {
    final appState = context.read<AppState>();
    appState.setAutoDownloadSettings(widget.source, {
      'photos': _photos,
      'files': _files,
      'downloadLimit': _downloadLimit,
      'videoMessages': _videoMessages,
      'videos': _videos,
      'gifs': _gifs,
      'autoPlayLimit': _autoPlayLimit,
    });
    Navigator.of(context).pop();
  }

  static const _sizeSteps = <double>[
    0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500,
    1024, 1536, 2048, 3072, 4096, 5120, 7168, 8192,
  ];

  int _sizeToIndex(double mb) {
    for (var i = 0; i < _sizeSteps.length; i++) {
      if (_sizeSteps[i] >= mb) return i;
    }
    return _sizeSteps.length - 1;
  }

  double _indexToSize(int i) => _sizeSteps[i.clamp(0, _sizeSteps.length - 1)];

  String _formatSize(double mb) {
    if (mb >= 1024) {
      final gb = mb / 1024;
      return gb == gb.roundToDouble()
          ? '${gb.round()} GB'
          : '${gb.toStringAsFixed(1)} GB';
    }
    return mb == mb.roundToDouble()
        ? '${mb.round()} MB'
        : '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Text(
                widget.source,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Automatically download',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _toggleRow('Photos', _photos, (v) => setState(() => _photos = v),
                textColor, accentColor),
            _toggleRow('Files', _files, (v) => setState(() => _files = v),
                textColor, accentColor),
            _sizeSlider(
              'Size limit',
              _downloadLimit,
              (v) => setState(() => _downloadLimit = v),
              textColor,
              subtextColor,
              accentColor,
            ),
            const SizedBox(height: 4),
            Divider(height: 1, color: dividerColor, indent: 22, endIndent: 22),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Auto-play media',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _toggleRow('Video messages', _videoMessages,
                (v) => setState(() => _videoMessages = v), textColor, accentColor),
            _toggleRow('Videos', _videos,
                (v) => setState(() => _videos = v), textColor, accentColor),
            _toggleRow('GIFs', _gifs,
                (v) => setState(() => _gifs = v), textColor, accentColor),
            _sizeSlider(
              'Size limit',
              _autoPlayLimit,
              (v) => setState(() => _autoPlayLimit = v),
              textColor,
              subtextColor,
              accentColor,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(color: accentColor, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _save,
                    child: Text('Save',
                        style: TextStyle(color: accentColor, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged,
      Color textColor, Color accentColor) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: textColor)),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: accentColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sizeSlider(String label, double currentMb,
      ValueChanged<double> onChanged, Color textColor, Color subtextColor,
      Color accentColor) {
    final idx = _sizeToIndex(currentMb);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(fontSize: 13, color: subtextColor)),
              const Spacer(),
              Text(_formatSize(currentMb),
                  style: TextStyle(fontSize: 13, color: accentColor)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              activeTrackColor: accentColor,
              inactiveTrackColor: accentColor.withValues(alpha: 0.24),
              thumbColor: accentColor,
              overlayColor: accentColor.withValues(alpha: 0.12),
              trackHeight: 2,
            ),
            child: Slider(
              value: idx.toDouble(),
              min: 0,
              max: (_sizeSteps.length - 1).toDouble(),
              divisions: _sizeSteps.length - 1,
              onChanged: (v) => onChanged(_indexToSize(v.round())),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalStorageBox extends StatefulWidget {
  const _LocalStorageBox();

  @override
  State<_LocalStorageBox> createState() => _LocalStorageBoxState();
}

class _LocalStorageBoxState extends State<_LocalStorageBox> {
  int _totalSizeIdx = 9;
  int _mediaSizeIdx = 8;
  int _timeLimitIdx = 15;
  bool _scanning = true;

  static const _totalSizeSteps = <int>[
    200, 500, 1024, 2048, 3072, 4096, 5120, 6144,
    7168, 8192, 10240, 15360, 20480, 25600, 30720, 40960, 51200, 0,
  ];

  static const _mediaSizeSteps = <int>[
    100, 200, 500, 1024, 1536, 2048, 3072, 4096,
    5120, 6144, 7168, 8192, 10240, 15360, 20480, 25600, 30720, 51200,
  ];

  static const _timeLimitLabels = <String>[
    '1 week', '2 weeks', '3 weeks',
    '1 month', '2 months', '3 months', '4 months', '5 months',
    '6 months', '7 months', '8 months', '9 months', '10 months',
    '11 months', '12 months', 'Forever',
  ];

  static const _tagNames = [
    'Images', 'Stickers', 'Voice Messages',
    'Video Messages', 'Animations', 'Media Cache',
  ];

  static const _imageExts = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};
  static const _stickerExts = {'.tgs', '.webm'};
  static const _voiceExts = {'.ogg', '.oga'};
  static const _videoMsgExts = {'.mp4'};
  static const _animExts = {'.gif', '.lottie'};

  final _tagSizes = List<int>.filled(6, 0);

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _totalSizeIdx = _findClosestIdx(_totalSizeSteps, appState.localStorageTotalLimit);
    _mediaSizeIdx = _findClosestIdx(_mediaSizeSteps, appState.localStorageMediaLimit);
    _timeLimitIdx = appState.localStorageTimeLimit.clamp(0, _timeLimitLabels.length - 1);
    _scanCacheDir();
  }

  int _findClosestIdx(List<int> steps, int value) {
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] >= value || steps[i] == 0) return i;
    }
    return steps.length - 1;
  }

  Future<void> _scanCacheDir() async {
    final appState = context.read<AppState>();

    int engineCacheSize = 0;
    try {
      engineCacheSize = appState.engine.getCacheSize();
    } catch (_) {}

    final cacheDir = appState.cacheDir;
    if (cacheDir.isEmpty) {
      if (mounted) {
        setState(() {
          if (engineCacheSize > 0) _tagSizes[5] = engineCacheSize;
          _scanning = false;
        });
      }
      return;
    }
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      if (mounted) {
        setState(() {
          if (engineCacheSize > 0) _tagSizes[5] = engineCacheSize;
          _scanning = false;
        });
      }
      return;
    }
    final sizes = List<int>.filled(6, 0);
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final size = await entity.length();
        final ext = entity.path.split('.').last.toLowerCase();
        final dotExt = '.$ext';
        if (_imageExts.contains(dotExt)) {
          sizes[0] += size;
        } else if (_stickerExts.contains(dotExt)) {
          sizes[1] += size;
        } else if (_voiceExts.contains(dotExt)) {
          sizes[2] += size;
        } else if (_videoMsgExts.contains(dotExt) && entity.path.contains('video_message')) {
          sizes[3] += size;
        } else if (_animExts.contains(dotExt)) {
          sizes[4] += size;
        } else {
          sizes[5] += size;
        }
      }
    } catch (_) {}
    final fileScanTotal = sizes.fold(0, (a, b) => a + b);
    if (engineCacheSize > fileScanTotal) {
      sizes[5] += engineCacheSize - fileScanTotal;
    }
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < 6; i++) _tagSizes[i] = sizes[i];
      _scanning = false;
    });
  }

  void _clearTag(int tagIdx) async {
    final appState = context.read<AppState>();
    final cacheDir = appState.cacheDir;
    if (cacheDir.isEmpty) return;
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return;

    final extsForTag = switch (tagIdx) {
      0 => _imageExts,
      1 => _stickerExts,
      2 => _voiceExts,
      3 => _videoMsgExts,
      4 => _animExts,
      _ => <String>{},
    };

    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final ext = '.${entity.path.split('.').last.toLowerCase()}';
        if (tagIdx == 5) {
          if (!_imageExts.contains(ext) && !_stickerExts.contains(ext) &&
              !_voiceExts.contains(ext) && !_animExts.contains(ext) &&
              !(ext == '.mp4' && entity.path.contains('video_message'))) {
            await entity.delete();
          }
        } else if (tagIdx == 3) {
          if (ext == '.mp4' && entity.path.contains('video_message')) {
            await entity.delete();
          }
        } else if (extsForTag.contains(ext)) {
          await entity.delete();
        }
      }
    } catch (_) {}
    try {
      appState.engine.clearCache(accountId: appState.activeAccountId);
    } catch (_) {}
    if (mounted) setState(() => _tagSizes[tagIdx] = 0);
  }

  void _clearAll() async {
    final appState = context.read<AppState>();
    try {
      appState.engine.clearCache();
    } catch (_) {}
    final cacheDir = appState.cacheDir;
    if (cacheDir.isNotEmpty) {
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        try {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) await entity.delete();
          }
        } catch (_) {}
      }
    }
    if (mounted) {
      setState(() {
        for (var i = 0; i < _tagSizes.length; i++) _tagSizes[i] = 0;
      });
    }
  }

  void _saveAndClose() {
    final appState = context.read<AppState>();
    appState.setLocalStorageLimits(
      totalLimit: _totalSizeSteps[_totalSizeIdx],
      mediaLimit: _mediaSizeSteps[_mediaSizeIdx],
      timeLimit: _timeLimitIdx,
    );
    Navigator.of(context).pop();
  }

  String _formatMb(int mb) {
    if (mb == 0) return '∞';
    if (mb >= 1024) {
      final gb = mb / 1024;
      return gb == gb.roundToDouble()
          ? '${gb.round()} GB'
          : '${gb.toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }

  int get _totalDataSize => _tagSizes.fold(0, (a, b) => a + b);

  String _formatBytes(int bytes) {
    if (bytes == 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final clearColor =
        context.palette.windowBgActive;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Text(
                'Local Storage',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            _summaryRow(textColor, subtextColor, clearColor),
            Divider(height: 1, color: dividerColor, indent: 22, endIndent: 22),
            const SizedBox(height: 8),
            _sliderSection(
              'Total size limit',
              _totalSizeIdx,
              _totalSizeSteps.length - 1,
              _formatMb(_totalSizeSteps[_totalSizeIdx]),
              (v) {
                setState(() {
                  _totalSizeIdx = v;
                  if (_totalSizeSteps[v] != 0 &&
                      (_mediaSizeSteps[_mediaSizeIdx] == 0 ||
                          _mediaSizeSteps[_mediaSizeIdx] > _totalSizeSteps[v])) {
                    for (var i = _mediaSizeSteps.length - 1; i >= 0; i--) {
                      if (_mediaSizeSteps[i] <= _totalSizeSteps[v]) {
                        _mediaSizeIdx = i;
                        break;
                      }
                    }
                  }
                });
              },
              textColor,
              subtextColor,
              accentColor,
            ),
            _sliderSection(
              'Media cache size limit',
              _mediaSizeIdx,
              _mediaSizeSteps.length - 1,
              _formatMb(_mediaSizeSteps[_mediaSizeIdx]),
              (v) {
                setState(() {
                  if (_totalSizeSteps[_totalSizeIdx] != 0 &&
                      _mediaSizeSteps[v] > _totalSizeSteps[_totalSizeIdx]) {
                    return;
                  }
                  _mediaSizeIdx = v;
                });
              },
              textColor,
              subtextColor,
              accentColor,
            ),
            _sliderSection(
              'Keep media',
              _timeLimitIdx,
              _timeLimitLabels.length - 1,
              _timeLimitLabels[_timeLimitIdx],
              (v) => setState(() => _timeLimitIdx = v),
              textColor,
              subtextColor,
              accentColor,
            ),
            Divider(height: 1, color: dividerColor, indent: 22, endIndent: 22),
            const SizedBox(height: 4),
            for (var i = 0; i < _tagNames.length; i++)
              _tagRow(i, textColor, subtextColor, clearColor),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saveAndClose,
                    child: Text('OK',
                        style: TextStyle(color: accentColor, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(Color textColor, Color subtextColor, Color clearColor) {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('All data',
                      style: TextStyle(fontSize: 14, color: textColor)),
                  Text(_formatBytes(_totalDataSize),
                      style: TextStyle(fontSize: 12, color: subtextColor)),
                ],
              ),
            ),
            TextButton(
              onPressed: _totalDataSize > 0 ? _clearAll : null,
              child: Text('Clear All',
                  style: TextStyle(
                    fontSize: 13,
                    color: _totalDataSize > 0
                        ? clearColor
                        : clearColor.withValues(alpha: 0.4),
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderSection(
    String label,
    int index,
    int max,
    String valueLabel,
    ValueChanged<int> onChanged,
    Color textColor,
    Color subtextColor,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(fontSize: 13, color: subtextColor)),
              const Spacer(),
              Text(valueLabel,
                  style: TextStyle(fontSize: 13, color: accentColor)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              activeTrackColor: accentColor,
              inactiveTrackColor: accentColor.withValues(alpha: 0.24),
              thumbColor: accentColor,
              overlayColor: accentColor.withValues(alpha: 0.12),
              trackHeight: 2,
            ),
            child: Slider(
              value: index.toDouble(),
              min: 0,
              max: max.toDouble(),
              divisions: max,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagRow(int tagIdx, Color textColor, Color subtextColor, Color clearColor) {
    final size = _tagSizes[tagIdx];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              child: Text(_tagNames[tagIdx],
                  style: TextStyle(fontSize: 14, color: textColor)),
            ),
            Text(_formatBytes(size),
                style: TextStyle(fontSize: 12, color: subtextColor)),
            if (size > 0) ...[
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _clearTag(tagIdx),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('Clear',
                      style: TextStyle(fontSize: 13, color: clearColor)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManageDictionariesBox extends StatefulWidget {
  final bool isDark;
  const _ManageDictionariesBox({required this.isDark});

  @override
  State<_ManageDictionariesBox> createState() => _ManageDictionariesBoxState();
}

class _ManageDictionariesBoxState extends State<_ManageDictionariesBox> {
  List<_DictEntry> _installed = [];
  List<_DictAvailable> _available = [];
  bool _scanning = true;
  String? _downloading;

  @override
  void initState() {
    super.initState();
    _scanDictionaries();
  }

  Future<void> _scanDictionaries() async {
    final appState = context.read<AppState>();
    final enabled = appState.enabledDictionaries;
    final installed = <_DictEntry>[];
    final installedCodes = <String>{};

    final systemDirs = <String>[
      if (Platform.isLinux) ...['/usr/share/hunspell', '/usr/share/myspell/dicts'],
    ];
    final allDirs = [...systemDirs, UniSpellCheckService.dictsDir];

    for (final dirPath in allDirs) {
      try {
        final d = Directory(dirPath);
        if (!d.existsSync()) continue;
        for (final f in d.listSync()) {
          if (!f.path.endsWith('.dic')) continue;
          final code = f.path.split('/').last.replaceAll('.dic', '');
          if (installedCodes.contains(code)) continue;
          installedCodes.add(code);
          final affPath = f.path.replaceAll('.dic', '.aff');
          final isLocal = f.path.startsWith(UniSpellCheckService.dictsDir);
          installed.add(_DictEntry(
            code: code,
            label: _langLabel(code),
            hasAff: File(affPath).existsSync(),
            path: f.path,
            enabled: enabled.isEmpty || enabled.contains(code),
            isLocal: isLocal,
          ));
        }
      } catch (_) {}
    }
    installed.sort((a, b) => a.label.compareTo(b.label));

    final available = <_DictAvailable>[];
    for (final entry in UniSpellCheckService.downloadManifest.entries) {
      if (!installedCodes.contains(entry.key)) {
        available.add(_DictAvailable(code: entry.key, label: entry.value.label));
      }
    }
    available.sort((a, b) => a.label.compareTo(b.label));

    if (mounted) setState(() { _installed = installed; _available = available; _scanning = false; });
  }

  Future<void> _downloadDict(String code) async {
    setState(() => _downloading = code);
    final ok = await UniSpellCheckService.downloadDictionary(code);
    if (!mounted) return;
    if (ok) {
      final appState = context.read<AppState>();
      if (appState.enabledDictionaries.isNotEmpty && !appState.enabledDictionaries.contains(code)) {
        appState.toggleDictionary(code);
      }
      await UniSpellCheckService.instance.loadDictionaries(appState.enabledDictionaries);
      await _scanDictionaries();
    }
    if (mounted) setState(() => _downloading = null);
  }

  Future<void> _deleteDict(String code) async {
    await UniSpellCheckService.deleteDictionary(code);
    if (!mounted) return;
    final appState = context.read<AppState>();
    await UniSpellCheckService.instance.loadDictionaries(appState.enabledDictionaries);
    await _scanDictionaries();
  }

  static String _langLabel(String code) {
    final manifest = UniSpellCheckService.downloadManifest[code];
    if (manifest != null) return manifest.label;
    const labels = {
      'en_AU': 'English (AU)', 'de_AT': 'German (Austria)', 'de_CH': 'German (Swiss)',
      'fi_FI': 'Finnish', 'fa_IR': 'Persian', 'ja_JP': 'Japanese',
      'ko_KR': 'Korean', 'zh_CN': 'Chinese (Simplified)',
    };
    return labels[code] ?? code.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Text(
                'Manage Dictionaries',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
              ),
            ),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else ...[
              if (_installed.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                  child: Text('Installed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accentColor)),
                ),
                Divider(height: 1, color: dividerColor),
                Flexible(
                  flex: 2,
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _installed.length,
                    itemBuilder: (_, i) {
                      final d = _installed[i];
                      return InkWell(
                        onTap: () {
                          setState(() => d.enabled = !d.enabled);
                          final appState = context.read<AppState>();
                          appState.toggleDictionary(d.code);
                          UniSpellCheckService.instance.loadDictionaries(appState.enabledDictionaries);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22, height: 22,
                                child: Checkbox(
                                  value: d.enabled,
                                  onChanged: (v) {
                                    setState(() => d.enabled = v ?? true);
                                    final appState = context.read<AppState>();
                                    appState.toggleDictionary(d.code);
                                    UniSpellCheckService.instance.loadDictionaries(appState.enabledDictionaries);
                                  },
                                  activeColor: accentColor,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.label, style: TextStyle(fontSize: 14, color: textColor)),
                                    Text(d.code, style: TextStyle(fontSize: 12, color: subtextColor)),
                                  ],
                                ),
                              ),
                              if (d.isLocal)
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 18, color: subtextColor),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: () => _deleteDict(d.code),
                                  tooltip: 'Remove dictionary',
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (_available.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                  child: Text('Available for download', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accentColor)),
                ),
                Divider(height: 1, color: dividerColor),
                Flexible(
                  flex: 3,
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _available.length,
                    itemBuilder: (_, i) {
                      final d = _available[i];
                      final isDownloading = _downloading == d.code;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.label, style: TextStyle(fontSize: 14, color: textColor)),
                                  Text(d.code, style: TextStyle(fontSize: 12, color: subtextColor)),
                                ],
                              ),
                            ),
                            if (isDownloading)
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            else
                              IconButton(
                                icon: Icon(Icons.download, size: 18, color: accentColor),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: () => _downloadDict(d.code),
                                tooltip: 'Download dictionary',
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (_installed.isEmpty && _available.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                  child: Text(
                    'No dictionaries available.',
                    style: TextStyle(fontSize: 14, color: subtextColor),
                  ),
                ),
            ],
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close', style: TextStyle(color: accentColor, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DictEntry {
  final String code;
  final String label;
  final bool hasAff;
  final String path;
  final bool isLocal;
  bool enabled;
  _DictEntry({required this.code, required this.label, required this.hasAff, required this.path, this.enabled = true, this.isLocal = false});
}

class _DictAvailable {
  final String code;
  final String label;
  _DictAvailable({required this.code, required this.label});
}

class PowerSavingBox extends StatefulWidget {
  const PowerSavingBox();

  @override
  State<PowerSavingBox> createState() => _PowerSavingBoxState();
}

class _PowerSavingBoxState extends State<PowerSavingBox> {
  late int _flags;
  late bool _autoEnabled;
  bool _hasBattery = false;
  bool _osPowerSaver = false;
  final GlobalKey _controlsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _flags = appState.powerSavingFlags;
    _autoEnabled = appState.autoPowerSaving;
    _detectBattery();
  }

  Future<void> _detectBattery() async {
    if (!Platform.isLinux) return;
    try {
      final psDir = Directory('/sys/class/power_supply');
      if (!psDir.existsSync()) return;
      for (final entry in psDir.listSync()) {
        final typeFile = File('${entry.path}/type');
        if (typeFile.existsSync()) {
          final type = typeFile.readAsStringSync().trim();
          if (type == 'Battery') {
            if (!mounted) return;
            setState(() => _hasBattery = true);
            _checkPowerSaverMode();
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _checkPowerSaverMode() async {
    if (!Platform.isLinux) return;
    var detected = false;
    try {
      final result = await Process.run('powerprofilesctl', ['get']);
      final profile = (result.stdout as String).trim();
      if (profile == 'power-saver') detected = true;
    } catch (_) {}
    if (!detected) {
      try {
        final result = await Process.run('gdbus', [
          'call', '--system',
          '--dest', 'org.freedesktop.UPower',
          '--object-path', '/org/freedesktop/UPower',
          '--method', 'org.freedesktop.DBus.Properties.Get',
          'org.freedesktop.UPower', 'OnBattery',
        ]);
        final out = (result.stdout as String).trim();
        if (out.contains('true')) detected = true;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _osPowerSaver = detected);
    if (_autoEnabled && detected) {
      _applyAutoFlags();
    }
  }

  void _applyAutoFlags() {
    final appState = context.read<AppState>();
    const allFlags = 0xFFFF;
    setState(() => _flags = allFlags);
    appState.setPowerSaving(allFlags, true);
  }

  bool get _overlayActive => _autoEnabled && _osPowerSaver;

  bool _flag(int bit) => _flags & bit != 0;

  void _toggle(int bit) {
    setState(() {
      _flags = _flags ^ bit;
    });
  }

  void _showForceDisabledToast() {
    showTelegramToast(context, 'Turn off your device\'s power saving mode to change these settings',
        duration: const Duration(milliseconds: 3000));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        context.palette.windowBgActive;
    final headerColor =
        context.palette.windowBgActive;
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final overlayColor = bgColor.withAlpha(96);

    final screenHeight = MediaQuery.of(context).size.height;
    final maxDialogHeight = screenHeight - 48;
    return Dialog(
      backgroundColor: bgColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 364, maxHeight: maxDialogHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Text(
                'Power Saving',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasBattery) ...[
                      _autoToggle(textColor, accentColor),
                      const SizedBox(height: 8),
                    ],
                    Stack(
                      children: [
                        Column(
                          key: _controlsKey,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header('Stickers', headerColor),
                            _iconToggle('Stickers in Panel', Icons.sticky_note_2,
                                AppState.kPowerSavingStickersPanel, textColor, iconColor, accentColor),
                            _plainToggle('Stickers in Messages',
                                AppState.kPowerSavingStickersChat, textColor, accentColor),
                            const SizedBox(height: 8),
                            _header('Emoji', headerColor),
                            _iconToggle('Emoji in Panel', Icons.emoji_emotions,
                                AppState.kPowerSavingEmojiPanel, textColor, iconColor, accentColor),
                            _plainToggle('Emoji Reactions',
                                AppState.kPowerSavingEmojiReactions, textColor, accentColor),
                            _plainToggle('Emoji in Messages',
                                AppState.kPowerSavingEmojiChat, textColor, accentColor),
                            _plainToggle('Emoji Status',
                                AppState.kPowerSavingEmojiStatus, textColor, accentColor),
                            const SizedBox(height: 8),
                            _header('Chat', headerColor),
                            _iconToggle('Chat Background', Icons.chat_bubble_outline,
                                AppState.kPowerSavingChatBackground, textColor, iconColor, accentColor),
                            _plainToggle('Spoiler Effect',
                                AppState.kPowerSavingChatSpoiler, textColor, accentColor),
                            _plainToggle('Message Effects',
                                AppState.kPowerSavingChatEffects, textColor, accentColor),
                            const SizedBox(height: 8),
                            _iconToggle('Calls', Icons.phone,
                                AppState.kPowerSavingCalls, textColor, iconColor, accentColor),
                            _iconToggle('Interface Animations', Icons.play_circle_outline,
                                AppState.kPowerSavingAnimations, textColor, iconColor, accentColor),
                            const SizedBox(height: 8),
                          ],
                        ),
                        if (_overlayActive)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _showForceDisabledToast,
                              child: ColoredBox(color: overlayColor),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(color: accentColor, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final appState = context.read<AppState>();
                      if (_autoEnabled != appState.autoPowerSaving) {
                        appState.setAutoPowerSaving(_autoEnabled);
                      }
                      final old = appState.powerSavingFlags;
                      final changed = old ^ _flags;
                      for (var bit = 0; bit < 12; bit++) {
                        if (changed & (1 << bit) != 0) {
                          appState.setPowerSaving(1 << bit, _flags & (1 << bit) != 0);
                        }
                      }
                      Navigator.of(context).pop();
                    },
                    child: Text('Save',
                        style: TextStyle(color: accentColor, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _autoToggle(Color textColor, Color accentColor) {
    return InkWell(
      onTap: () => setState(() => _autoEnabled = !_autoEnabled),
      child: Padding(
        padding: _psPlainPad,
        child: Row(
          children: [
            Expanded(
              child: Text('Automatic Power Saving',
                  style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: textColor)),
            ),
            Switch(
              value: _autoEnabled,
              onChanged: (v) => setState(() => _autoEnabled = v),
              activeColor: accentColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  static const _psIconPad = EdgeInsets.fromLTRB(20, 8, 22, 8);
  static const double _psIconGap = 13;
  static const _psPlainPad = EdgeInsets.fromLTRB(22, 8, 22, 8);

  Widget _iconToggle(String label, IconData icon, int flag,
      Color textColor, Color iconColor, Color accentColor) {
    final on = !_flag(flag);
    return InkWell(
      onTap: () => _toggle(flag),
      child: Padding(
        padding: _psIconPad,
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: _psIconGap),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: textColor)),
            ),
            Switch(
              value: on,
              onChanged: (_) => _toggle(flag),
              activeColor: accentColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _plainToggle(String label, int flag, Color textColor, Color accentColor) {
    final on = !_flag(flag);
    return InkWell(
      onTap: () => _toggle(flag),
      child: Padding(
        padding: _psPlainPad,
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: textColor)),
            ),
            Switch(
              value: on,
              onChanged: (_) => _toggle(flag),
              activeColor: accentColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

// §17.2.1 ProxiesBox — 364px dialog for proxy management.
enum _ProxyType { http, socks5, mtproto }

enum _ProxyMode { disabled, system, custom }

enum _ProxyStatus { online, available, checking, unavailable }

class _ProxyEntry {
  _ProxyType type;
  String host;
  int port;
  String username;
  String password;
  String secret;
  _ProxyStatus status;
  int pingMs;
  bool deleted;

  _ProxyEntry({
    required this.type,
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
    this.secret = '',
    this.status = _ProxyStatus.checking,
    this.pingMs = 0,
    this.deleted = false,
  });

  String get typeLabel => switch (type) {
        _ProxyType.http => 'HTTP',
        _ProxyType.socks5 => 'SOCKS5',
        _ProxyType.mtproto => 'MTPROTO',
      };

  String get title => '$typeLabel $host:$port';

  bool get supportsCalls => type != _ProxyType.mtproto;

  bool get isShareable => !deleted;
}

class _ProxiesBox extends StatefulWidget {
  const _ProxiesBox();

  @override
  State<_ProxiesBox> createState() => _ProxiesBoxState();
}

class _ProxiesBoxState extends State<_ProxiesBox> {
  _ProxyMode _mode = _ProxyMode.disabled;
  bool _ipv6 = false;
  bool _proxyForCalls = false;
  bool _rotationEnabled = false;
  int _rotationTimeout = 60;
  final List<_ProxyEntry> _proxies = [];
  int _selectedIndex = -1;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _mode = _ProxyMode.values[appState.proxyMode.clamp(0, 2)];
    _ipv6 = appState.proxyIpv6;
    _proxyForCalls = appState.proxyForCalls;
    _rotationEnabled = appState.proxyRotationEnabled;
    _rotationTimeout = appState.proxyRotationTimeout;
    for (final m in appState.proxyList) {
      _proxies.add(_ProxyEntry(
        type: _ProxyType.values.firstWhere(
          (t) => t.name == (m['type'] as String? ?? 'socks5'),
          orElse: () => _ProxyType.socks5,
        ),
        host: m['host'] as String? ?? '',
        port: m['port'] as int? ?? 0,
        username: m['username'] as String? ?? '',
        password: m['password'] as String? ?? '',
        secret: m['secret'] as String? ?? '',
      ));
    }
    if (_proxies.isNotEmpty && _mode == _ProxyMode.custom) {
      _selectedIndex = 0;
    }
    _checkAllProxies();
  }

  void _syncToAppState() {
    final appState = context.read<AppState>();
    final proxyType = (_mode == _ProxyMode.custom &&
            _selectedIndex >= 0 &&
            _selectedIndex < _proxies.length)
        ? _proxies[_selectedIndex].typeLabel
        : '';
    appState.setProxyMode(_mode.index, proxyType);
    appState.setProxyIpv6(_ipv6);
    appState.setProxyForCalls(_proxyForCalls);
    appState.setProxyList(_proxies
        .where((p) => !p.deleted)
        .map((p) => {
              'type': p.type.name,
              'host': p.host,
              'port': p.port,
              'username': p.username,
              'password': p.password,
              'secret': p.secret,
            })
        .toList());
  }

  Future<void> _checkAllProxies() async {
    for (var i = 0; i < _proxies.length; i++) {
      if (_proxies[i].deleted) continue;
      _checkProxy(i);
    }
  }

  Future<void> _checkProxy(int index) async {
    if (index < 0 || index >= _proxies.length) return;
    final proxy = _proxies[index];
    try {
      final appState = context.read<AppState>();
      final result = await appState.engine.callGeneric(
        appState.activeAccountId,
        'CheckProxy',
        {
          'host': proxy.host,
          'port': proxy.port,
          'proxy_type': proxy.type.name,
          'username': proxy.username,
          'password': proxy.password,
          'secret': proxy.secret,
        },
      );
      if (!mounted) return;
      if (result != null && result['ok'] == true) {
        final isActive = _mode == _ProxyMode.custom && _selectedIndex == index;
        setState(() {
          proxy.status = isActive ? _ProxyStatus.online : _ProxyStatus.available;
          proxy.pingMs = (result['ping_ms'] as num?)?.toInt() ?? 0;
        });
      } else {
        setState(() => proxy.status = _ProxyStatus.unavailable);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => proxy.status = _ProxyStatus.unavailable);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (!ctrl) return;
    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      _copyAllProxies();
    } else if (event.logicalKey == LogicalKeyboardKey.keyV) {
      _importFromClipboard();
    }
  }

  void _copyAllProxies() {
    if (_proxies.isEmpty) return;
    final urls =
        _proxies.where((p) => !p.deleted).map(_proxyToUrl).join('\n');
    if (urls.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: urls));
      showTelegramToast(context, 'Proxy URLs copied to clipboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final hasShareable = _proxies.any((p) => p.isShareable);
    final showCallsToggle =
        _mode == _ProxyMode.custom &&
        _selectedIndex >= 0 &&
        _selectedIndex < _proxies.length &&
        _proxies[_selectedIndex].supportsCalls;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title bar with menu toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Connection type',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: subtextColor, size: 20),
                    onSelected: (v) {
                      if (v == 'import') _importFromClipboard();
                      if (v == 'delete_all') _deleteAllProxies();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'import',
                        child: Text('Import from clipboard',
                            style: TextStyle(fontSize: 14, color: textColor)),
                      ),
                      PopupMenuItem(
                        value: 'delete_all',
                        child: Text('Delete all',
                            style: TextStyle(
                                fontSize: 14, color: theme.colorScheme.error)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // IPv6 checkbox
            InkWell(
              onTap: () {
                setState(() => _ipv6 = !_ipv6);
                _syncToAppState();
              },
              hoverColor: hoverBg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: _ipv6,
                        onChanged: (v) {
                          setState(() => _ipv6 = v ?? false);
                          _syncToAppState();
                        },
                        activeColor: accentColor,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Try connecting through IPv6',
                        style: TextStyle(fontSize: 14, color: textColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Radio group: Disabled / System / Custom
            _proxyRadio('Disabled', _ProxyMode.disabled, textColor, accentColor,
                hoverBg),
            _proxyRadio('Use system settings', _ProxyMode.system, textColor,
                accentColor, hoverBg),
            _proxyRadio('Use custom proxy', _ProxyMode.custom, textColor,
                accentColor, hoverBg),

            // "Use proxy for calls" toggle (conditional)
            AnimatedSize(
              duration: context.read<AppState>().animDuration(const Duration(milliseconds: 200)),
              curve: Curves.easeOutCubic,
              child: showCallsToggle
                  ? InkWell(
                      onTap: () {
                          setState(() => _proxyForCalls = !_proxyForCalls);
                          _syncToAppState();
                        },
                      hoverColor: hoverBg,
                      child: Padding(
                        padding: SettingsStyle.noIconPadding,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Use proxy for calls',
                                style:
                                    TextStyle(fontSize: 14, color: textColor),
                              ),
                            ),
                            Switch(
                              value: _proxyForCalls,
                              onChanged: (v) {
                                  setState(() => _proxyForCalls = v);
                                  _syncToAppState();
                              },
                              activeColor: accentColor,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Proxy rotation toggle (visible when multiple proxies exist)
            if (_mode == _ProxyMode.custom && _proxies.length > 1) ...[
              InkWell(
                onTap: () {
                  setState(() => _rotationEnabled = !_rotationEnabled);
                  context.read<AppState>().setProxyRotationEnabled(_rotationEnabled);
                },
                hoverColor: hoverBg,
                child: Padding(
                  padding: SettingsStyle.noIconPadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Rotate proxies', style: TextStyle(fontSize: 14, color: textColor)),
                      ),
                      Switch(
                        value: _rotationEnabled,
                        onChanged: (v) {
                          setState(() => _rotationEnabled = v);
                          context.read<AppState>().setProxyRotationEnabled(v);
                        },
                        activeColor: accentColor,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ),
              if (_rotationEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                  child: Row(
                    children: [
                      Text('Timeout: ${_rotationTimeout}s', style: TextStyle(fontSize: 13, color: subtextColor)),
                      Expanded(
                        child: Slider(
                          value: _rotationTimeout.toDouble(),
                          min: 10,
                          max: 300,
                          divisions: 29,
                          onChanged: (v) {
                            setState(() => _rotationTimeout = v.round());
                            context.read<AppState>().setProxyRotationTimeout(v.round());
                          },
                          activeColor: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            // Divider text
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: Text(
                'You can add several proxy servers to be used if the previous one is unavailable.',
                style: TextStyle(fontSize: 13, color: subtextColor),
              ),
            ),

            // Share list button (visible when shareable entries exist)
            if (hasShareable)
              InkWell(
                onTap: _shareList,
                hoverColor: hoverBg,
                child: Padding(
                  padding: SettingsStyle.iconRowPadding,
                  child: Row(
                    children: [
                      Icon(Icons.share, size: 24, color: subtextColor),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Share proxy list',
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Divider(height: 1, color: dividerColor, indent: 0, endIndent: 0),

            // Proxy list or empty state
            if (_proxies.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                child: Center(
                  child: Text(
                    'You have no saved proxies yet.',
                    style: TextStyle(fontSize: 14, color: subtextColor),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _proxies.length,
                  itemBuilder: (ctx, i) => _buildProxyRow(i, isDark),
                ),
              ),

            const SizedBox(height: 4),

            // Add proxy button
            InkWell(
              onTap: _addProxy,
              hoverColor: hoverBg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline,
                        size: 24, color: accentColor),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Add proxy',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
    );
  }

  void _setMode(_ProxyMode mode) {
    setState(() => _mode = mode);
    _syncToAppState();
  }

  Widget _proxyRadio(String label, _ProxyMode mode, Color textColor,
      Color accentColor, Color hoverBg) {
    return InkWell(
      onTap: () => _setMode(mode),
      hoverColor: hoverBg,
      child: Padding(
        padding: SettingsStyle.sendTypePadding,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Radio<_ProxyMode>(
                value: mode,
                groupValue: _mode,
                onChanged: (v) => _setMode(v!),
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyRow(int index, bool isDark) {
    final proxy = _proxies[index];
    final theme = Theme.of(context);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final statusColor = switch (proxy.status) {
      _ProxyStatus.online => const Color(0xFF4CAF50),
      _ProxyStatus.available => accentColor,
      _ProxyStatus.checking => subtextColor,
      _ProxyStatus.unavailable => theme.colorScheme.error,
    };
    final statusText = switch (proxy.status) {
      _ProxyStatus.online => 'Online',
      _ProxyStatus.available => '${proxy.pingMs} ms',
      _ProxyStatus.checking => 'Checking...',
      _ProxyStatus.unavailable => 'Unavailable',
    };

    final isSelected = _mode == _ProxyMode.custom && _selectedIndex == index;
    final opacity = proxy.deleted ? 0.4 : 1.0;

    return Opacity(
      opacity: opacity,
      child: InkWell(
        onTap: () {
          if (proxy.deleted) return;
          setState(() {
            _selectedIndex = index;
            _mode = _ProxyMode.custom;
          });
          _syncToAppState();
        },
        hoverColor: hoverBg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 8, 8),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Radio<int>(
                  value: index,
                  groupValue:
                      _mode == _ProxyMode.custom ? _selectedIndex : -1,
                  onChanged: proxy.deleted
                      ? null
                      : (v) {
                          setState(() {
                            _selectedIndex = v!;
                            _mode = _ProxyMode.custom;
                          });
                          _syncToAppState();
                        },
                  activeColor: accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proxy.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(fontSize: 13, color: statusColor),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: subtextColor, size: 20),
                onSelected: (v) => _onProxyAction(index, v),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20, color: subtextColor),
                        const SizedBox(width: 12),
                        Text('Edit',
                            style: TextStyle(fontSize: 14, color: textColor)),
                      ],
                    ),
                  ),
                  if (proxy.isShareable) ...[
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share, size: 20, color: subtextColor),
                          const SizedBox(width: 12),
                          Text('Share',
                              style:
                                  TextStyle(fontSize: 14, color: textColor)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'qr',
                      child: Row(
                        children: [
                          Icon(Icons.qr_code, size: 20, color: subtextColor),
                          const SizedBox(width: 12),
                          Text('QR Code',
                              style:
                                  TextStyle(fontSize: 14, color: textColor)),
                        ],
                      ),
                    ),
                  ],
                  PopupMenuItem(
                    value: proxy.deleted ? 'restore' : 'delete',
                    child: Row(
                      children: [
                        Icon(
                          proxy.deleted ? Icons.restore : Icons.delete,
                          size: 20,
                          color: proxy.deleted
                              ? subtextColor
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          proxy.deleted ? 'Restore' : 'Delete',
                          style: TextStyle(
                            fontSize: 14,
                            color: proxy.deleted
                                ? textColor
                                : theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onProxyAction(int index, String action) {
    switch (action) {
      case 'edit':
        _editProxy(index);
      case 'share':
        final p = _proxies[index];
        Clipboard.setData(ClipboardData(text: _proxyToUrl(p)));
        showTelegramToast(context, 'Proxy link copied to clipboard');
      case 'qr':
        final p = _proxies[index];
        _showQrDialog(p);
      case 'delete':
        setState(() => _proxies[index].deleted = true);
        _syncToAppState();
      case 'restore':
        setState(() => _proxies[index].deleted = false);
        _syncToAppState();
    }
  }

  String _proxyToUrl(_ProxyEntry p) {
    final scheme = switch (p.type) {
      _ProxyType.socks5 => 'tg://socks?server=${p.host}&port=${p.port}',
      _ProxyType.http =>
        'tg://proxy?server=${p.host}&port=${p.port}&type=http',
      _ProxyType.mtproto =>
        'tg://proxy?server=${p.host}&port=${p.port}&secret=${p.secret}',
    };
    return scheme;
  }

  void _showQrDialog(_ProxyEntry proxy) {
    final url = _proxyToUrl(proxy);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Proxy QR Code'),
        content: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                url,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.of(context).pop();
            },
            child: const Text('Copy Link'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _addProxy() async {
    final result = await showDialog<_ProxyEntry>(
      context: context,
      builder: (_) => const _EditProxyDialog(),
    );
    if (result != null && mounted) {
      setState(() {
        _proxies.add(result);
        _selectedIndex = _proxies.length - 1;
        _mode = _ProxyMode.custom;
      });
      _syncToAppState();
      _checkProxy(_proxies.length - 1);
    }
  }

  void _editProxy(int index) async {
    final result = await showDialog<_ProxyEntry>(
      context: context,
      builder: (_) => _EditProxyDialog(existing: _proxies[index]),
    );
    if (result != null && mounted) {
      setState(() => _proxies[index] = result);
      _syncToAppState();
      _checkProxy(index);
    }
  }

  void _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || !mounted) return;
    final text = data!.text!;
    final urls = RegExp(r'tg://(?:socks|proxy)\?[^\s]+').allMatches(text);
    var added = 0;
    for (final match in urls) {
      final parsed = _parseProxyUrl(match.group(0)!);
      if (parsed != null) {
        _proxies.add(parsed);
        added++;
      }
    }
    if (added > 0 && mounted) {
      setState(() {
        _selectedIndex = _proxies.length - 1;
        _mode = _ProxyMode.custom;
      });
      _syncToAppState();
      showTelegramToast(context, 'Imported $added proxy(ies)');
    } else if (mounted) {
      showTelegramToast(context, 'No valid proxy URLs found');
    }
  }

  _ProxyEntry? _parseProxyUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.queryParameters['server'] ?? '';
    final port = int.tryParse(uri.queryParameters['port'] ?? '') ?? 0;
    if (host.isEmpty || port == 0) return null;

    if (uri.host == 'socks' || url.contains('tg://socks')) {
      return _ProxyEntry(type: _ProxyType.socks5, host: host, port: port);
    }
    final secret = uri.queryParameters['secret'] ?? '';
    if (secret.isNotEmpty) {
      return _ProxyEntry(
          type: _ProxyType.mtproto, host: host, port: port, secret: secret);
    }
    return _ProxyEntry(type: _ProxyType.http, host: host, port: port);
  }

  void _deleteAllProxies() {
    if (_proxies.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all proxies?'),
        content: const Text('This will remove all proxy entries.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _proxies.clear();
                _selectedIndex = -1;
                if (_mode == _ProxyMode.custom) _mode = _ProxyMode.disabled;
              });
              _syncToAppState();
            },
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _shareList() {
    final urls =
        _proxies.where((p) => p.isShareable).map(_proxyToUrl).join('\n');
    Clipboard.setData(ClipboardData(text: urls));
    showTelegramToast(context, 'Proxy list copied to clipboard');
  }
}

// §17.2.1 Edit Proxy Dialog — 364px dialog.
class _EditProxyDialog extends StatefulWidget {
  final _ProxyEntry? existing;

  const _EditProxyDialog({this.existing});

  @override
  State<_EditProxyDialog> createState() => _EditProxyDialogState();
}

class _EditProxyDialogState extends State<_EditProxyDialog> {
  _ProxyType _type = _ProxyType.socks5;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _secretCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? _ProxyType.socks5;
    _hostCtrl = TextEditingController(text: e?.host ?? '');
    _portCtrl =
        TextEditingController(text: e != null && e.port > 0 ? '${e.port}' : '');
    _userCtrl = TextEditingController(text: e?.username ?? '');
    _passCtrl = TextEditingController(text: e?.password ?? '');
    _secretCtrl = TextEditingController(text: e?.secret ?? '');
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  void _onHostChanged(String value) {
    // Smart paste: "host:port" auto-split
    if (value.contains(':') && _portCtrl.text.isEmpty) {
      final parts = value.split(':');
      if (parts.length == 2) {
        final port = int.tryParse(parts[1]);
        if (port != null && port > 0 && port <= 65535) {
          _hostCtrl.text = parts[0];
          _hostCtrl.selection =
              TextSelection.collapsed(offset: parts[0].length);
          _portCtrl.text = parts[1];
        }
      }
    }
  }

  void _save() {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 0;
    if (host.isEmpty || port <= 0 || port > 65535) {
      showTelegramToast(context, 'Please enter a valid host and port');
      return;
    }
    Navigator.of(context).pop(_ProxyEntry(
      type: _type,
      host: host,
      port: port,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text.trim(),
      secret: _secretCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final fieldBg = isDark ? const Color(0xFF17212B) : const Color(0xFFF5F5F5);
    final isEditing = widget.existing != null;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
              child: Text(
                isEditing ? 'Edit proxy' : 'Add proxy',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),

            // Type radio group
            _typeRadio('SOCKS5', _ProxyType.socks5, textColor, accentColor,
                hoverBg),
            _typeRadio(
                'HTTP', _ProxyType.http, textColor, accentColor, hoverBg),
            _typeRadio('MTPROTO', _ProxyType.mtproto, textColor, accentColor,
                hoverBg),
            const SizedBox(height: 8),

            // Host + Port row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _hostCtrl,
                      onChanged: _onHostChanged,
                      decoration: InputDecoration(
                        hintText: 'Hostname',
                        hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                        filled: true,
                        fillColor: fieldBg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 55,
                    child: TextField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        hintText: 'Port',
                        hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                        filled: true,
                        fillColor: fieldBg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Credentials (HTTP/SOCKS5) or Secret (MTPROTO)
            if (_type != _ProxyType.mtproto) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: TextField(
                  controller: _userCtrl,
                  decoration: InputDecoration(
                    hintText: 'Username (optional)',
                    hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                    filled: true,
                    fillColor: fieldBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password (optional)',
                    hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                    filled: true,
                    fillColor: fieldBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: TextField(
                  controller: _secretCtrl,
                  decoration: InputDecoration(
                    hintText: 'Secret',
                    hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                    filled: true,
                    fillColor: fieldBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                child: Text(
                  'This proxy may display a sponsored channel in your chat list. This is done by the proxy provider, not by Telegram.',
                  style: TextStyle(fontSize: 13, color: subtextColor),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Save / Cancel buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(color: accentColor, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _save,
                    child: Text(isEditing ? 'Save' : 'Add',
                        style: TextStyle(color: accentColor, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeRadio(String label, _ProxyType type, Color textColor,
      Color accentColor, Color hoverBg) {
    return InkWell(
      onTap: () => setState(() => _type = type),
      hoverColor: hoverBg,
      child: Padding(
        padding: SettingsStyle.sendTypePadding,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Radio<_ProxyType>(
                value: type,
                groupValue: _type,
                onChanged: (v) => setState(() => _type = v!),
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentDownloadsBox extends StatefulWidget {
  const _RecentDownloadsBox();

  @override
  State<_RecentDownloadsBox> createState() => _RecentDownloadsBoxState();
}

class _RecentDownloadsBoxState extends State<_RecentDownloadsBox> {
  String _search = '';
  String _filter = 'all';
  static const _filterLabels = {
    'all': 'All',
    'image': 'Photos',
    'video': 'Videos',
    'audio': 'Music',
    'file': 'Files',
  };
  static const _imageExts = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'};
  static const _videoExts = {'.mp4', '.avi', '.mkv', '.webm', '.mov'};
  static const _audioExts = {'.mp3', '.ogg', '.oga', '.flac', '.wav', '.m4a', '.aac'};

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  String _fileCategory(String name) {
    final dotExt = name.contains('.') ? '.${name.split('.').last.toLowerCase()}' : '';
    if (_imageExts.contains(dotExt)) return 'image';
    if (_videoExts.contains(dotExt)) return 'video';
    if (_audioExts.contains(dotExt)) return 'audio';
    return 'file';
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> downloads) {
    var result = downloads;
    if (_filter != 'all') {
      result = result.where((dl) {
        final name = dl['name'] as String? ?? '';
        return _fileCategory(name) == _filter;
      }).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      result = result.where((dl) {
        final name = (dl['name'] as String? ?? '').toLowerCase();
        return name.contains(q);
      }).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final appState = context.watch<AppState>();
    final allDownloads = appState.recentDownloads;
    final downloads = _filtered(allDownloads);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 0),
              child: Row(
                children: [
                  Text(
                    'Downloads',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  if (allDownloads.isNotEmpty)
                    TextButton(
                      onPressed: () => appState.clearRecentDownloads(),
                      child: Text(
                        'Clear all',
                        style: TextStyle(fontSize: 13, color: accentColor),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: TextStyle(fontSize: 13, color: textColor),
                decoration: InputDecoration(
                  hintText: 'Search downloads...',
                  hintStyle: TextStyle(fontSize: 13, color: subtextColor),
                  prefixIcon: Icon(Icons.search, size: 18, color: subtextColor),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accentColor),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: _filterLabels.entries.map((e) {
                  final sel = _filter == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(e.value, style: TextStyle(
                        fontSize: 12,
                        color: sel ? Colors.white : subtextColor,
                      )),
                      selected: sel,
                      selectedColor: accentColor,
                      backgroundColor: isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
                      onSelected: (_) => setState(() => _filter = e.key),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            Divider(height: 1, color: dividerColor),
            if (downloads.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 22),
                child: Column(
                  children: [
                    Icon(Icons.download_done, size: 48, color: subtextColor),
                    const SizedBox(height: 12),
                    Text(
                      allDownloads.isEmpty ? 'No downloads yet' : 'No matching downloads',
                      style: TextStyle(fontSize: 14, color: subtextColor),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: downloads.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 56,
                    color: dividerColor,
                  ),
                  itemBuilder: (ctx, i) {
                    final dl = downloads[i];
                    final name = dl['name'] as String? ?? '';
                    final path = dl['path'] as String? ?? '';
                    final size = dl['size'] as int? ?? 0;
                    final ts = dl['timestamp'] as int? ?? 0;
                    final ext = name.contains('.')
                        ? name.split('.').last.toUpperCase()
                        : '';
                    final cat = _fileCategory(name);
                    final catIcon = switch (cat) {
                      'image' => Icons.image,
                      'video' => Icons.videocam,
                      'audio' => Icons.audiotrack,
                      _ => Icons.insert_drive_file,
                    };

                    return InkWell(
                      hoverColor: hoverBg,
                      onTap: () {
                        _AdvancedSettingsScreenState._openWithSystem(path);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: ext.isNotEmpty
                                  ? Text(
                                      ext.length > 4 ? ext.substring(0, 4) : ext,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: accentColor,
                                      ),
                                    )
                                  : Icon(catIcon, size: 18, color: accentColor),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: textColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_formatSize(size)} · ${_formatDate(ts)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: subtextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.folder_open, size: 16, color: subtextColor),
                              onPressed: () {
                                final dir = path.substring(0, path.lastIndexOf(Platform.pathSeparator));
                                if (dir.isNotEmpty) _AdvancedSettingsScreenState._openWithSystem(dir);
                              },
                              splashRadius: 16,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              tooltip: 'Show in folder',
                            ),
                            IconButton(
                              icon: Icon(Icons.close, size: 16, color: subtextColor),
                              onPressed: () {
                                final realIdx = allDownloads.indexOf(dl);
                                if (realIdx >= 0) appState.removeRecentDownload(realIdx);
                              },
                              splashRadius: 16,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              tooltip: 'Remove',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 12, 6),
              child: Row(
                children: [
                  Text(
                    '${allDownloads.length} file${allDownloads.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: subtextColor),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Close',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadPathOption extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final Color accentColor;
  final Color textColor;
  final Color subtextColor;
  final bool isDark;
  final VoidCallback onTap;

  const _DownloadPathOption({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.textColor,
    required this.subtextColor,
    required this.isDark,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? accentColor : subtextColor,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 14, color: textColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle != label)
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: subtextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _experimentalFlagDefs = <(String, String)>[
  ('tabbed_emoji_panel', 'Use tabbed emoji/sticker panel'),
  ('forum_chat_list', 'Show forum topics in chat list'),
  ('dialogs_mute_icon', 'Show mute icon in dialogs'),
  ('fractional_scaling', 'Enable fractional scaling'),
  ('profile_in_context', 'Show profile preview in context menus'),
  ('peer_id_display', 'Show peer IDs and channel info'),
  ('large_bubble_radius', 'Use large message bubble radius'),
  ('autoplay_gifs', 'Autoplay GIFs and stickers'),
  ('webview_debug', 'Enable webview debugging'),
  ('notification_custom', 'Custom notification sounds'),
  ('freetype_rendering', 'Use FreeType font rendering'),
  ('ipv6_preferred', 'Prefer IPv6 connections'),
  ('smooth_scrolling', 'Use smooth scrolling'),
  ('message_draft_visible', 'Show message drafts in dialogs'),
];

const _flagsPrefix = 'tdesktop-flags:';

class ExperimentalSettingsBox extends StatefulWidget {
  const ExperimentalSettingsBox({super.key});

  @override
  State<ExperimentalSettingsBox> createState() =>
      _ExperimentalSettingsBoxState();
}

class _ExperimentalSettingsBoxState extends State<ExperimentalSettingsBox> {
  late Map<String, bool> _flags;

  @override
  void initState() {
    super.initState();
    _flags = Map<String, bool>.from(context.read<AppState>().experimentalFlags);
  }

  bool _flag(String key) => _flags[key] == true;

  bool get _changed {
    for (final (key, _) in _experimentalFlagDefs) {
      if (_flag(key)) return true;
    }
    return false;
  }

  void _toggle(String key) {
    setState(() {
      if (_flags[key] == true) {
        _flags.remove(key);
      } else {
        _flags[key] = true;
      }
    });
  }

  void _reset() {
    setState(() => _flags.clear());
  }

  void _export() {
    final nonDefault = <String, bool>{};
    for (final (key, _) in _experimentalFlagDefs) {
      if (_flag(key)) nonDefault[key] = true;
    }
    if (nonDefault.isEmpty) {
      _toast('No flags changed from default.');
      return;
    }
    try {
      final jsonBytes = utf8.encode(jsonEncode(nonDefault));
      final compressed = zlib.encode(jsonBytes);
      final encoded = base64Url.encode(compressed);
      Clipboard.setData(ClipboardData(text: '$_flagsPrefix$encoded'));
      _toast('Flags exported to clipboard.');
    } catch (_) {
      _toast('Failed to export flags.');
    }
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!text.startsWith(_flagsPrefix)) {
      _toast('Clipboard does not contain valid flags data.');
      return;
    }
    try {
      final encoded = text.substring(_flagsPrefix.length);
      final compressed = base64Url.decode(encoded);
      final jsonBytes = zlib.decode(compressed);
      final decoded =
          jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
      setState(() {
        _flags.clear();
        for (final entry in decoded.entries) {
          if (entry.value == true) _flags[entry.key] = true;
        }
      });
      _toast('Flags imported successfully.');
    } catch (_) {
      _toast('Failed to import flags — invalid data.');
    }
  }

  void _toast(String msg) {
    showTelegramToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final warningColor =
        isDark ? const Color(0xFFE8A64A) : const Color(0xFFD4850C);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Experimental Settings',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (_changed)
                    TextButton(
                      onPressed: _reset,
                      child: Text(
                        'Reset',
                        style: TextStyle(fontSize: 13, color: accentColor),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
              child: Text(
                'These settings are experimental and may change or be removed in future updates. Use at your own risk.',
                style: TextStyle(fontSize: 13, color: warningColor),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (key, label) in _experimentalFlagDefs)
                      _flagToggle(key, label, textColor, accentColor, isDark),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _export,
                    child: Text(
                      'Export',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _import,
                    child: Text(
                      'Import',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: 14, color: subtextColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      context.read<AppState>().setExperimentalFlags(_flags);
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Save',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flagToggle(
    String key,
    String label,
    Color textColor,
    Color accentColor,
    bool isDark,
  ) {
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    return InkWell(
      onTap: () => _toggle(key),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: SettingsStyle.buttonFontSize,
                  color: textColor,
                ),
              ),
            ),
            Switch(
              value: _flag(key),
              onChanged: (_) => _toggle(key),
              activeColor: accentColor,
            ),
          ],
        ),
      ),
    );
  }
}
