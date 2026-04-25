import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Advanced settings page (§14.7). Opened from Settings → Advanced row.
/// Build order per §14.7.0: 11 sections separated by skip+divider+skip.
class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

enum _UpdateState { idle, checking, latest, failed }

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
  bool _askDownloadPath = false;
  _UpdateState _updateState = _UpdateState.idle;

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
      _buildDataAndStorage(isDark),            // 2. Data and Storage
      _buildAutoMediaDownload(isDark),         // 3. Automatic Media Download
      _buildWindowTitle(isDark, appState),     // 4. Window Title
      _buildWindowCloseBehavior(isDark),       // 5. Window Close (Linux only)
      _buildSystemIntegration(isDark, appState), // 6. System Integration
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

  static const _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  String get _stateLabel => switch (_updateState) {
        _UpdateState.idle => 'UniClient v$_appVersion',
        _UpdateState.checking => 'Checking for updates...',
        _UpdateState.latest => 'You have the latest version installed',
        _UpdateState.failed => 'Update check failed',
      };

  void _checkForUpdates() {
    setState(() => _updateState = _UpdateState.checking);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _updateState = _UpdateState.latest);
    });
  }

  List<Widget> _buildSoftwareUpdate(bool isDark) {
    final appState = context.watch<AppState>();
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
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
    ];
  }

  // §14.7.8 top: shown only when NOT auto-updating.
  List<Widget> _buildSoftwareUpdateTop(bool isDark) {
    final appState = context.watch<AppState>();
    if (appState.autoUpdateEnabled) return const [];
    return _buildSoftwareUpdate(isDark);
  }

  // §14.7.1: Connection Type, Download Path, Local Storage, Downloads, Ask path toggle.
  List<Widget> _buildDataAndStorage(bool isDark) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _AdvancedIconButtonRow(
        icon: Icons.settings_ethernet,
        label: 'Connection type',
        rightLabel: 'Using TCP',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      if (!_askDownloadPath)
        _AdvancedIconButtonRow(
          icon: Icons.folder_open,
          label: 'Download path',
          rightLabel: 'Default folder',
          textColor: textColor,
          subtextColor: subtextColor,
          iconColor: iconColor,
          hoverBg: hoverBg,
          onTap: () {},
        ),
      _AdvancedIconButtonRow(
        icon: Icons.storage,
        label: 'Manage local storage',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _AdvancedIconButtonRow(
        icon: Icons.download,
        label: 'Recent Downloads',
        textColor: textColor,
        subtextColor: subtextColor,
        iconColor: iconColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _AdvancedToggleRow(
        label: 'Ask download path for each file',
        value: _askDownloadPath,
        onChanged: (v) => setState(() => _askDownloadPath = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
    ];
  }

  // §14.7.2: Private/Groups/Channels auto-download buttons.
  List<Widget> _buildAutoMediaDownload(bool isDark) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final multiAccount = appState.accounts.length > 1;

    return [
      _AdvancedCheckboxRow(
        label: 'Show chat name in the window title',
        value: appState.showChatNameInTitle,
        onChanged: (v) => appState.setShowChatNameInTitle(v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
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
          label: 'Use system window frame',
          value: appState.nativeWindowFrame,
          onChanged: (v) => appState.setNativeWindowFrame(v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
    ];
  }

  // §14.7.4: Run in Background / Close to Taskbar / Quit radios. Linux/BSD only.
  List<Widget> _buildWindowCloseBehavior(bool isDark) {
    if (!Platform.isLinux) return const [];
    final appState = context.read<AppState>();
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    const labels = ['Run in background', 'Close to the taskbar', 'Quit Telegram'];
    return [
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

  // §14.7.5: Tray/taskbar icons, monochrome, launch at startup, start minimized.
  List<Widget> _buildSystemIntegration(bool isDark, AppState appState) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _AdvancedCheckboxRow(
        label: 'Show tray icon',
        value: appState.showTrayIcon,
        onChanged: (v) {
          if (!appState.setShowTrayIcon(v)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('At least one of tray icon or taskbar icon must be enabled.'),
                duration: Duration(seconds: 2),
              ),
            );
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('At least one of tray icon or taskbar icon must be enabled.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
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
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: appState.launchAtStartup
            ? _AdvancedCheckboxRow(
                label: 'Start minimized',
                value: appState.startMinimized,
                onChanged: (v) => appState.setStartMinimized(v),
                textColor: textColor,
                accentColor: accentColor,
                hoverBg: hoverBg,
              )
            : const SizedBox.shrink(),
      ),
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
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
        onChanged: (v) => appState.setHardwareAccelVideo(v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      if (!Platform.isMacOS)
        _AdvancedToggleRow(
          label: Platform.isWindows
              ? 'Use ANGLE graphics backend'
              : 'Disable OpenGL',
          value: appState.openGlDisabled,
          onChanged: (v) {
            appState.setOpenGlDisabled(v);
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

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
                  'Restart required',
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
                      child: Text('OK',
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
      _AdvancedToggleRow(
        label: Platform.isLinux || Platform.isMacOS
            ? 'Use system spellchecker'
            : 'Enable spellchecker',
        value: appState.spellcheckerEnabled,
        onChanged: (v) => appState.setSpellcheckerEnabled(v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      if (appState.spellcheckerEnabled) ...[
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
          rightLabel: '0',
          textColor: textColor,
          subtextColor: subtextColor,
          iconColor: iconColor,
          hoverBg: hoverBg,
          onTap: () {},
        ),
      ],
    ];
  }

  // §14.7.9: Screen reader mode toggle (shown only when reader detected).
  List<Widget> _buildScreenReader(bool isDark) => const [];

  // §14.7.8 bottom: shown only when auto-updating.
  List<Widget> _buildSoftwareUpdateBottom(bool isDark) {
    final appState = context.watch<AppState>();
    if (!appState.autoUpdateEnabled) return const [];
    return _buildSoftwareUpdate(isDark);
  }

  // §14.7.11: Export Telegram Data, Experimental Settings.
  List<Widget> _buildExportData(bool isDark) => const [];
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
        padding: const EdgeInsets.only(left: 20, top: 10, right: 22, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (rightLabel != null)
              Text(
                rightLabel!,
                style: TextStyle(fontSize: 14, color: subtextColor),
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
        padding: const EdgeInsets.only(left: 22, right: 22, top: 10, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: textColor),
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
        padding: const EdgeInsets.only(left: 22, right: 22, top: 10, bottom: 8),
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
                style: TextStyle(fontSize: 15, color: textColor),
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
        padding: const EdgeInsets.only(left: 22, right: 22, top: 10, bottom: 8),
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
                style: TextStyle(fontSize: 15, color: textColor),
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
                    onPressed: () => Navigator.of(context).pop(),
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

class PowerSavingBox extends StatefulWidget {
  const PowerSavingBox();

  @override
  State<PowerSavingBox> createState() => _PowerSavingBoxState();
}

class _PowerSavingBoxState extends State<PowerSavingBox> {
  late int _flags;

  @override
  void initState() {
    super.initState();
    _flags = context.read<AppState>().powerSavingFlags;
  }

  bool _flag(int bit) => _flags & bit != 0;

  void _toggle(int bit) {
    setState(() {
      _flags = _flags ^ bit;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final headerColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

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

  Widget _iconToggle(String label, IconData icon, int flag,
      Color textColor, Color iconColor, Color accentColor) {
    final on = !_flag(flag);
    return InkWell(
      onTap: () => _toggle(flag),
      child: Padding(
        padding: const EdgeInsets.only(left: 20, top: 8, right: 22, bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 13),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: textColor)),
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
        padding: const EdgeInsets.only(left: 22, top: 8, right: 22, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: textColor)),
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
