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

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
  bool _askDownloadPath = false;

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

  // §14.7.8 top: shown only when NOT auto-updating.
  List<Widget> _buildSoftwareUpdateTop(bool isDark) => const [];

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
  List<Widget> _buildAutoMediaDownload(bool isDark) => const [];

  // §14.7.3: Chat name / Account name / Unread count checkboxes, native frame toggle.
  List<Widget> _buildWindowTitle(bool isDark, AppState appState) => const [];

  // §14.7.4: Run in Background / Close to Taskbar / Quit radios. Linux/BSD only.
  List<Widget> _buildWindowCloseBehavior(bool isDark) {
    if (!Platform.isLinux) return const [];
    return const [];
  }

  // §14.7.5: Tray/taskbar icons, monochrome, launch at startup, start minimized.
  List<Widget> _buildSystemIntegration(bool isDark, AppState appState) {
    if (!Platform.isLinux) return const [];
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return [
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

  // §14.7.6: Power Saving button, hardware video accel, OpenGL/ANGLE toggle.
  List<Widget> _buildPerformance(bool isDark) => const [];

  // §14.7.7: System/custom toggle, auto-download dictionaries, Manage Dictionaries.
  List<Widget> _buildSpellchecker(bool isDark) => const [];

  // §14.7.9: Screen reader mode toggle (shown only when reader detected).
  List<Widget> _buildScreenReader(bool isDark) => const [];

  // §14.7.8 bottom: shown only when auto-updating.
  List<Widget> _buildSoftwareUpdateBottom(bool isDark) => const [];

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
