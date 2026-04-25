import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'settings_style.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  bool _allAccountsNotify = true;
  bool _desktopNotify = true;
  bool _flashBounce = true;
  bool _allowSound = true;
  int _volume = 100;
  bool _previewName = true;
  bool _previewText = true;

  bool _privateChatsNotify = true;
  bool _groupsNotify = true;
  bool _channelsNotify = true;
  bool _reactionsNotify = true;

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
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final sectionTitleColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);

    final sections = <List<Widget>>[
      _buildMultiAccountSection(appState, isDark, sectionTitleColor, textColor,
          subtextColor, accentColor, hoverBg),
      _buildGlobalSettings(isDark, sectionTitleColor, textColor, subtextColor,
          accentColor, hoverBg),
      _buildNotificationsForChats(isDark, sectionTitleColor, textColor,
          subtextColor, accentColor, hoverBg),
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
          'Notifications and Sounds',
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

  /// §15.1: Shown only when 2+ accounts are logged in.
  List<Widget> _buildMultiAccountSection(
    AppState appState,
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    if (appState.accounts.length < 2) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Text(
          'Show notifications from',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _NotifToggleRow(
        label: 'All accounts',
        value: _allAccountsNotify,
        onChanged: (v) => setState(() => _allAccountsNotify = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
        child: Text(
          'Turn this off if you want to receive notifications only from the account you are currently using.',
          style: TextStyle(
            fontSize: 13,
            color: subtextColor,
          ),
        ),
      ),
    ];
  }

  /// §15.2: Desktop notifications, flash/bounce, allow sound toggles.
  List<Widget> _buildGlobalSettings(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Text(
          'Global settings',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _NotifIconToggleRow(
        icon: Icons.notifications,
        iconColor: iconColor,
        label: 'Desktop notifications',
        value: _desktopNotify,
        onChanged: (v) => setState(() => _desktopNotify = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: _desktopNotify
            ? _NotificationPreview(
                showName: _previewName,
                showText: _previewText,
                onNameChanged: (v) => setState(() {
                  _previewName = v;
                  if (!v) _previewText = false;
                }),
                onTextChanged: (v) => setState(() {
                  _previewText = v;
                  if (v) _previewName = true;
                }),
                isDark: isDark,
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
      _NotifIconToggleRow(
        icon: Icons.flash_on,
        iconColor: iconColor,
        label: 'Draw attention to the window',
        value: _flashBounce,
        onChanged: (v) => setState(() => _flashBounce = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      _NotifIconToggleRow(
        icon: Icons.volume_up,
        iconColor: iconColor,
        label: 'Allow sound',
        value: _allowSound,
        onChanged: (v) => setState(() => _allowSound = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: _allowSound
            ? _VolumeSliderSection(
                volume: _volume,
                onChanged: (v) => setState(() => _volume = v),
                accentColor: accentColor,
                isDark: isDark,
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    ];
  }

  List<Widget> _buildNotificationsForChats(
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
          'Notifications for chats',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _SplitToggleRow(
        icon: Icons.person,
        label: 'Private chats',
        value: _privateChatsNotify,
        onToggle: (v) => setState(() => _privateChatsNotify = v),
        textColor: textColor,
        subtextColor: subtextColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
        isDark: isDark,
      ),
      _SplitToggleRow(
        icon: Icons.group,
        label: 'Groups',
        value: _groupsNotify,
        onToggle: (v) => setState(() => _groupsNotify = v),
        textColor: textColor,
        subtextColor: subtextColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
        isDark: isDark,
      ),
      _SplitToggleRow(
        icon: Icons.campaign,
        label: 'Channels',
        value: _channelsNotify,
        onToggle: (v) => setState(() => _channelsNotify = v),
        textColor: textColor,
        subtextColor: subtextColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
        isDark: isDark,
      ),
      _SplitToggleRow(
        icon: Icons.add_reaction_outlined,
        label: 'Reactions',
        value: _reactionsNotify,
        onToggle: (v) => setState(() => _reactionsNotify = v),
        textColor: textColor,
        subtextColor: subtextColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
        isDark: isDark,
      ),
    ];
  }
}

class _NotifToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color textColor;
  final Color accentColor;
  final Color hoverBg;

  const _NotifToggleRow({
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
                style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize, color: textColor),
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

class _VolumeSliderSection extends StatelessWidget {
  final int volume;
  final ValueChanged<int> onChanged;
  final Color accentColor;
  final bool isDark;

  const _VolumeSliderSection({
    required this.volume,
    required this.onChanged,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = accentColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          child: Text(
            'Volume',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 7, 21, 4),
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7.5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: accentColor,
                    inactiveTrackColor: isDark
                        ? const Color(0xFF3E546A)
                        : const Color(0xFFD4DEE6),
                    thumbColor: accentColor,
                    overlayColor: accentColor.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: volume.toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    onChanged: (v) => onChanged(v.round()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: Text(
                  '$volume%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    color: labelColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotifIconToggleRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color textColor;
  final Color accentColor;
  final Color hoverBg;

  const _NotifIconToggleRow({
    required this.icon,
    required this.iconColor,
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
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize, color: textColor),
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

class _SplitToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onToggle;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final Color hoverBg;
  final bool isDark;
  final int exceptionCount;

  const _SplitToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onToggle,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.hoverBg,
    required this.isDark,
    this.exceptionCount = 0,
  });

  String get _statusText {
    if (exceptionCount == 0) return 'Click here to change';
    final state = value ? 'On' : 'Off';
    final exc = exceptionCount == 1 ? '1 exception' : '$exceptionCount exceptions';
    return '$state, $exc';
  }

  void _handleToggle(BuildContext context, bool newValue) {
    if (exceptionCount > 0) {
      showDialog<void>(
        context: context,
        builder: (ctx) {
          final dialogBg =
              isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
          final dialogText =
              isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
          return AlertDialog(
            backgroundColor: dialogBg,
            title: Text('Notifications',
                style: TextStyle(color: dialogText, fontWeight: FontWeight.w600)),
            content: Text(
              'Please note that $exceptionCount chat(s) are listed as exceptions and won\'t be affected.',
              style: TextStyle(color: dialogText, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('View exceptions',
                    style: TextStyle(color: accentColor)),
              ),
              TextButton(
                onPressed: () {
                  onToggle(newValue);
                  Navigator.of(ctx).pop();
                },
                child: Text('OK', style: TextStyle(color: accentColor)),
              ),
            ],
          );
        },
      );
    } else {
      onToggle(newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final separatorColor = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);
    final iconColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    const double rowHeight = 40;
    const double toggleAreaWidth = 70;

    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              hoverColor: hoverBg,
              splashColor: hoverBg.withValues(alpha: 0.5),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                child: Row(
                  children: [
                    Icon(icon, size: 24, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _statusText,
                            style: TextStyle(
                              fontSize: 11,
                              color: subtextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: rowHeight - 8,
            color: separatorColor,
          ),
          SizedBox(
            width: toggleAreaWidth,
            height: rowHeight,
            child: InkWell(
              hoverColor: hoverBg,
              splashColor: hoverBg.withValues(alpha: 0.5),
              onTap: () => _handleToggle(context, !value),
              child: Center(
                child: SizedBox(
                  width: 36,
                  height: 20,
                  child: Switch(
                    value: value,
                    onChanged: (v) => _handleToggle(context, v),
                    activeColor: accentColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationPreview extends StatelessWidget {
  final bool showName;
  final bool showText;
  final ValueChanged<bool> onNameChanged;
  final ValueChanged<bool> onTextChanged;
  final bool isDark;

  const _NotificationPreview({
    required this.showName,
    required this.showText,
    required this.onNameChanged,
    required this.onTextChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final wallpaperBg =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFDBDDC0);
    final bubbleBg =
        isDark ? const Color(0xFF182533) : const Color(0xFFFFFFFF);
    final titleColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final textColor =
        isDark ? const Color(0xFFAAAAAA) : const Color(0xFF555555);
    final serviceBg =
        isDark ? const Color(0x7F000000) : const Color(0x54000000);

    final displayTitle = showName ? 'Dino Rex' : 'UniClient';
    final displayText =
        showText ? 'It\'s morning in Tokyo \u{1F60E}' : 'You have a new message';

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 12),
      child: Container(
        decoration: BoxDecoration(
          color: wallpaperBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: bubbleBg,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: showName
                            ? const Color(0xFF4CAF50)
                            : isDark
                                ? const Color(0xFF5288C1)
                                : const Color(0xFF40A7E3),
                      ),
                      child: Center(
                        child: showName
                            ? const Text(
                                '\u{1F996}',
                                style: TextStyle(fontSize: 18),
                              )
                            : Icon(
                                Icons.chat_bubble,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            displayText,
                            style: TextStyle(
                              fontSize: 13,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ServiceCheckboxPill(
                    label: 'Name',
                    checked: showName,
                    onTap: () => onNameChanged(!showName),
                    serviceBg: serviceBg,
                  ),
                  const SizedBox(width: 12),
                  _ServiceCheckboxPill(
                    label: 'Text',
                    checked: showText,
                    onTap: () => onTextChanged(!showText),
                    serviceBg: serviceBg,
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

class _ServiceCheckboxPill extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;
  final Color serviceBg;

  const _ServiceCheckboxPill({
    required this.label,
    required this.checked,
    required this.onTap,
    required this.serviceBg,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: checked ? serviceBg : serviceBg.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(
                checked ? Icons.check_box : Icons.check_box_outline_blank,
                key: ValueKey(checked),
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
