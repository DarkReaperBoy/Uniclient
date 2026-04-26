import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'settings_style.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _scrollController = ScrollController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _reloadPrivacyData();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _reloadPrivacyData() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);
    final sectionTitleColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final sections = <List<Widget>>[
      _buildSecuritySection(isDark, sectionTitleColor, textColor, subtextColor,
          accentColor, hoverBg),
      _buildPrivacySection(isDark, sectionTitleColor, textColor, subtextColor,
          accentColor, hoverBg),
      _buildArchiveAndMuteSection(
          isDark, textColor, subtextColor, accentColor, hoverBg),
      _buildBotsAndWebsitesSection(isDark, textColor, subtextColor, hoverBg),
      _buildConfirmationExtensionsSection(isDark, textColor, subtextColor,
          accentColor, hoverBg),
      _buildTopPeersSection(isDark, textColor, subtextColor, accentColor,
          hoverBg),
      _buildSelfDestructionSection(isDark, textColor, subtextColor, hoverBg),
    ];

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
          'Privacy and Security',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: Scrollbar(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.zero,
          children: children,
        ),
      ),
    );
  }

  List<Widget> _buildSecuritySection(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
        child: Text(
          'Security',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _PrivacyIconRow(
        icon: Icons.lock_outline,
        label: 'Two-Step Verification',
        rightLabel: 'Off',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyIconRow(
        icon: Icons.timer_outlined,
        label: 'Auto-Delete Messages',
        rightLabel: 'Off',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyIconRow(
        icon: Icons.lock,
        label: 'Passcode Lock',
        rightLabel: 'Off',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyIconRow(
        icon: Icons.block,
        label: 'Blocked Users',
        rightLabel: 'None',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyIconRow(
        icon: Icons.devices,
        label: 'Active Sessions',
        rightLabel: '1',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
    ];
  }

  List<Widget> _buildPrivacySection(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Text(
          'Privacy',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _PrivacyRow(
        label: 'Phone Number',
        rightLabel: 'My Contacts',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Last Seen & Online',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Profile Photo',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Forwarded Messages',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Calls',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Voice Messages',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Messages',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Birthday',
        rightLabel: 'Contacts',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Gifts',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Bio',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyRow(
        label: 'Groups & Channels',
        rightLabel: 'Everyone',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
    ];
  }

  List<Widget> _buildArchiveAndMuteSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [];
  }

  List<Widget> _buildBotsAndWebsitesSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color hoverBg,
  ) {
    return [];
  }

  List<Widget> _buildConfirmationExtensionsSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [];
  }

  List<Widget> _buildTopPeersSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [];
  }

  List<Widget> _buildSelfDestructionSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color hoverBg,
  ) {
    return [];
  }
}

class _PrivacyIconRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String rightLabel;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _PrivacyIconRow({
    required this.icon,
    required this.label,
    required this.rightLabel,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.onTap,
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
            Icon(icon, size: 24, color: subtextColor),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: SettingsStyle.buttonFontSize,
                  color: textColor,
                ),
              ),
            ),
            Text(
              rightLabel,
              style: TextStyle(
                fontSize: 14,
                color: subtextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  final String label;
  final String rightLabel;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _PrivacyRow({
    required this.label,
    required this.rightLabel,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.noIconPadding,
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
            Text(
              rightLabel,
              style: TextStyle(
                fontSize: 14,
                color: subtextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
