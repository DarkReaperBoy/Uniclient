import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../models/engine_models.dart';
import 'popup_menu.dart';
import 'settings_style.dart';
import 'telegram_toast.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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

  // §15.8 Events
  bool _contactJoinedTelegram = true;
  bool _pinnedMessages = true;

  // §15.9 Calls
  bool _acceptCallsOnDevice = true;

  // §15.10 Badge Counter
  bool _includeMutedChats = true;
  bool _includeMutedInFolders = true;
  bool _countUnreadMessages = true;

  // §15.11 System Integration (Native Notifications)
  bool _useNativeNotifications = true;
  int _selectedDisplayIndex = 0; // 0 = Default
  _ScreenCorner _selectedCorner = _ScreenCorner.bottomRight;
  int _notificationCount = 3;

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

    final chatState = context.watch<ChatState>();

    final sections = <List<Widget>>[
      _buildMultiAccountSection(appState, isDark, sectionTitleColor, textColor,
          subtextColor, accentColor, hoverBg),
      _buildGlobalSettings(isDark, sectionTitleColor, textColor, subtextColor,
          accentColor, hoverBg),
      _buildNotificationsForChats(isDark, sectionTitleColor, textColor,
          subtextColor, accentColor, hoverBg),
      _buildEventsSection(isDark, sectionTitleColor, textColor, accentColor,
          hoverBg),
      _buildCallsSection(isDark, sectionTitleColor, textColor, accentColor,
          hoverBg),
      _buildBadgeCounterSection(isDark, sectionTitleColor, textColor,
          accentColor, hoverBg, chatState.hasFolders),
      _buildSystemIntegrationSection(isDark, sectionTitleColor, textColor,
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
        duration: const Duration(milliseconds: 300),
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

  void _openTypeSubPage(BuildContext context, _NotifType type) {
    if (type == _NotifType.reactions) {
      Navigator.of(context).push(
        settingsPageRoute(const _ReactionsSubPage()),
      );
      return;
    }
    Navigator.of(context).push(
      settingsPageRoute(
        _NotificationTypeSubPage(type: type),
      ),
    );
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
        onTap: () => _openTypeSubPage(context, _NotifType.privateChats),
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
        onTap: () => _openTypeSubPage(context, _NotifType.groups),
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
        onTap: () => _openTypeSubPage(context, _NotifType.channels),
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
        onTap: () => _openTypeSubPage(context, _NotifType.reactions),
        textColor: textColor,
        subtextColor: subtextColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
        isDark: isDark,
      ),
    ];
  }

  List<Widget> _buildEventsSection(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color accentColor,
    Color hoverBg,
  ) {
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Text(
          'Events',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _NotifIconToggleRow(
        icon: Icons.person_add,
        iconColor: iconColor,
        label: 'Contact joined Telegram',
        value: _contactJoinedTelegram,
        onChanged: (v) => setState(() => _contactJoinedTelegram = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      _NotifIconToggleRow(
        icon: Icons.push_pin,
        iconColor: iconColor,
        label: 'Pinned messages',
        value: _pinnedMessages,
        onChanged: (v) => setState(() => _pinnedMessages = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
    ];
  }

  List<Widget> _buildCallsSection(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color accentColor,
    Color hoverBg,
  ) {
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Text(
          'Calls',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _NotifIconToggleRow(
        icon: Icons.call,
        iconColor: iconColor,
        label: 'Accept calls on this device',
        value: _acceptCallsOnDevice,
        onChanged: (v) => setState(() => _acceptCallsOnDevice = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
    ];
  }

  List<Widget> _buildBadgeCounterSection(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color accentColor,
    Color hoverBg,
    bool hasFolders,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Text(
          'Badge Counter',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _NoIconToggleRow(
        label: 'Include muted chats in unread count',
        value: _includeMutedChats,
        onChanged: (v) => setState(() => _includeMutedChats = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      if (hasFolders)
        _NoIconToggleRow(
          label: 'Include muted chats in folder counters',
          value: _includeMutedInFolders,
          onChanged: (v) => setState(() => _includeMutedInFolders = v),
          textColor: textColor,
          accentColor: accentColor,
          hoverBg: hoverBg,
        ),
      _NoIconToggleRow(
        label: 'Count unread messages',
        value: _countUnreadMessages,
        onChanged: (v) => setState(() => _countUnreadMessages = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
    ];
  }

  /// §15.11 System Integration (Native Notifications)
  List<Widget> _buildSystemIntegrationSection(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    final isWindows = !kIsWeb && Platform.isWindows;
    final displays = ui.PlatformDispatcher.instance.displays.toList();
    final hasMultipleDisplays = displays.length > 1;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Text(
          'System Integration',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _NoIconToggleRow(
        label: 'Use native notifications',
        value: _useNativeNotifications,
        onChanged: (v) => setState(() => _useNativeNotifications = v),
        textColor: textColor,
        accentColor: accentColor,
        hoverBg: hoverBg,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: !_useNativeNotifications
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isWindows)
                    _NoIconToggleRow(
                      label: 'Respect system Focus mode',
                      value: false,
                      onChanged: (_) {},
                      textColor: textColor,
                      accentColor: accentColor,
                      hoverBg: hoverBg,
                    ),
                  if (hasMultipleDisplays) ...[
                    const SizedBox(height: 7),
                    Container(
                      height: 1,
                      color: isDark
                          ? const Color(0xFF101921)
                          : const Color(0xFFF1F1F1),
                    ),
                    const SizedBox(height: 7),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
                      child: Text(
                        'Notification display',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: sectionTitleColor,
                        ),
                      ),
                    ),
                    _DisplayRadioRow(
                      label: 'Default',
                      value: 0,
                      groupValue: _selectedDisplayIndex,
                      onChanged: (v) =>
                          setState(() => _selectedDisplayIndex = v ?? 0),
                      textColor: textColor,
                      accentColor: accentColor,
                      hoverBg: hoverBg,
                    ),
                    for (var i = 0; i < displays.length; i++)
                      _DisplayRadioRow(
                        label:
                            'Display ${i + 1} (${displays[i].size.width.toInt()}\u00D7${displays[i].size.height.toInt()})',
                        value: i + 1,
                        groupValue: _selectedDisplayIndex,
                        onChanged: (v) =>
                            setState(() => _selectedDisplayIndex = v ?? 0),
                        textColor: textColor,
                        accentColor: accentColor,
                        hoverBg: hoverBg,
                      ),
                  ],
                  const SizedBox(height: 7),
                  Container(
                    height: 1,
                    color: isDark
                        ? const Color(0xFF101921)
                        : const Color(0xFFF1F1F1),
                  ),
                  const SizedBox(height: 7),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
                    child: Text(
                      'Notification position',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: sectionTitleColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  _NotificationMonitorWidget(
                    selectedCorner: _selectedCorner,
                    barCount: _notificationCount,
                    isDark: isDark,
                    onCornerChanged: (corner) =>
                        setState(() => _selectedCorner = corner),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
                    child: Text(
                      'Notification count',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: sectionTitleColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _NotificationCountSlider(
                    count: _notificationCount,
                    isDark: isDark,
                    accentColor: accentColor,
                    onChanged: (count) =>
                        setState(() => _notificationCount = count),
                  ),
                ],
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    ];
  }
}

enum _ScreenCorner { topLeft, topCenter, topRight, bottomRight, bottomLeft }

bool _isTopCorner(_ScreenCorner c) =>
    c == _ScreenCorner.topLeft ||
    c == _ScreenCorner.topRight ||
    c == _ScreenCorner.topCenter;

bool _isLeftCorner(_ScreenCorner c) =>
    c == _ScreenCorner.topLeft || c == _ScreenCorner.bottomLeft;

class _NotificationMonitorWidget extends StatefulWidget {
  final _ScreenCorner selectedCorner;
  final int barCount;
  final bool isDark;
  final ValueChanged<_ScreenCorner> onCornerChanged;

  const _NotificationMonitorWidget({
    required this.selectedCorner,
    required this.barCount,
    required this.isDark,
    required this.onCornerChanged,
  });

  @override
  State<_NotificationMonitorWidget> createState() =>
      _NotificationMonitorWidgetState();
}

class _NotificationMonitorWidgetState
    extends State<_NotificationMonitorWidget> with TickerProviderStateMixin {
  _ScreenCorner? _hoverCorner;
  _ScreenCorner? _pressCorner;
  late List<AnimationController> _barControllers;
  int _oldCount = 0;

  static const _screenW = 280.0;
  static const _screenH = 160.0;
  static const _barW = 64.0;
  static const _barH = 16.0;
  static const _barSkip = 5.0;
  static const _barTopSkip = 5.0;
  static const _barBottomSkip = 5.0;
  static const _barMargin = 2.0;
  static const _maxBars = 5;
  static const _inactiveOpacity = 0.5;
  static const _bezelPad = 16.0;
  static const _bezelBottom = 28.0;
  static const _bezelRadius = 8.0;
  static const _standW = 60.0;
  static const _standH = 10.0;

  @override
  void initState() {
    super.initState();
    _oldCount = widget.barCount;
    _barControllers = List.generate(_maxBars, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 150),
        value: i < widget.barCount ? 1.0 : 0.0,
      );
      return ctrl;
    });
  }

  @override
  void didUpdateWidget(covariant _NotificationMonitorWidget old) {
    super.didUpdateWidget(old);
    if (old.barCount != widget.barCount) {
      for (var i = 0; i < _maxBars; i++) {
        if (i < widget.barCount) {
          _barControllers[i].forward();
        } else {
          _barControllers[i].reverse();
        }
      }
      _oldCount = widget.barCount;
    }
  }

  @override
  void dispose() {
    for (final c in _barControllers) {
      c.dispose();
    }
    super.dispose();
  }

  _ScreenCorner? _hitTest(Offset pos, Rect screenRect) {
    if (!screenRect.contains(pos)) return null;
    final dx = pos.dx - screenRect.left;
    final dy = pos.dy - screenRect.top;
    final colW = screenRect.width / 3;
    final rowH = screenRect.height / 3;
    final col = (dx / colW).floor().clamp(0, 2);
    final row = (dy / rowH).floor().clamp(0, 2);
    if (row == 0) {
      if (col == 0) return _ScreenCorner.topLeft;
      if (col == 1) return _ScreenCorner.topCenter;
      return _ScreenCorner.topRight;
    }
    if (row == 2) {
      if (col == 0) return _ScreenCorner.bottomLeft;
      if (col == 2) return _ScreenCorner.bottomRight;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final totalW = _screenW + _bezelPad * 2;
    final totalH = _screenH + _bezelPad + _bezelBottom;

    return Center(
      child: MouseRegion(
        cursor: _hoverCorner != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onHover: (e) {
          final screenRect = Rect.fromLTWH(
            _bezelPad,
            _bezelPad,
            _screenW,
            _screenH,
          );
          final corner = _hitTest(e.localPosition, screenRect);
          if (corner != _hoverCorner) {
            setState(() => _hoverCorner = corner);
          }
        },
        onExit: (_) {
          if (_hoverCorner != null) {
            setState(() => _hoverCorner = null);
          }
        },
        child: GestureDetector(
          onTapDown: (d) {
            final screenRect = Rect.fromLTWH(
              _bezelPad,
              _bezelPad,
              _screenW,
              _screenH,
            );
            _pressCorner = _hitTest(d.localPosition, screenRect);
          },
          onTapUp: (d) {
            final screenRect = Rect.fromLTWH(
              _bezelPad,
              _bezelPad,
              _screenW,
              _screenH,
            );
            final upCorner = _hitTest(d.localPosition, screenRect);
            if (upCorner != null &&
                upCorner == _pressCorner &&
                upCorner != widget.selectedCorner) {
              widget.onCornerChanged(upCorner);
            }
            _pressCorner = null;
          },
          child: AnimatedBuilder(
            animation: Listenable.merge(_barControllers),
            builder: (context, _) {
              return CustomPaint(
                size: Size(totalW, totalH),
                painter: _MonitorPainter(
                  selectedCorner: widget.selectedCorner,
                  hoverCorner: _hoverCorner,
                  barOpacities: _barControllers.map((c) => c.value).toList(),
                  isDark: widget.isDark,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MonitorPainter extends CustomPainter {
  final _ScreenCorner selectedCorner;
  final _ScreenCorner? hoverCorner;
  final List<double> barOpacities;
  final bool isDark;

  _MonitorPainter({
    required this.selectedCorner,
    required this.hoverCorner,
    required this.barOpacities,
    required this.isDark,
  });

  static const _screenW = 280.0;
  static const _screenH = 160.0;
  static const _barW = 64.0;
  static const _barH = 16.0;
  static const _barSkip = 5.0;
  static const _barTopSkip = 5.0;
  static const _barBottomSkip = 5.0;
  static const _barMargin = 2.0;
  static const _bezelPad = 16.0;
  static const _bezelBottom = 28.0;
  static const _bezelRadius = 8.0;
  static const _standW = 60.0;
  static const _standH = 10.0;
  static const _inactiveOpacity = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final monitorFg = isDark ? const Color(0xFF3E546A) : const Color(0xFFBBBBBB);
    final screenBg = isDark ? const Color(0xFF0E1621) : const Color(0xFFE8E8E8);
    final barColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverHighlight =
        isDark ? const Color(0xFF1A2633) : const Color(0xFFD8D8D8);

    final monitorRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, _screenW + _bezelPad * 2, _screenH + _bezelPad + _bezelBottom - 8),
      Radius.circular(_bezelRadius),
    );
    canvas.drawRRect(monitorRect, Paint()..color = monitorFg);

    final screenRect = Rect.fromLTWH(_bezelPad, _bezelPad, _screenW, _screenH);
    canvas.drawRect(screenRect, Paint()..color = screenBg);

    final standRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        (size.width - _standW) / 2,
        monitorRect.height - 2,
        _standW,
        _standH,
      ),
      bottomLeft: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(standRect, Paint()..color = monitorFg);

    if (hoverCorner != null) {
      final hRect = _cornerHitRect(hoverCorner!, screenRect);
      canvas.drawRect(hRect, Paint()..color = hoverHighlight);
    }

    for (final corner in _ScreenCorner.values) {
      if (corner == selectedCorner) {
        _drawSelectedBars(canvas, corner, screenRect, barColor);
      } else {
        _drawInactiveBar(canvas, corner, screenRect, barColor);
      }
    }
  }

  Rect _cornerHitRect(_ScreenCorner corner, Rect screen) {
    final colW = screen.width / 3;
    final rowH = screen.height / 3;
    switch (corner) {
      case _ScreenCorner.topLeft:
        return Rect.fromLTWH(screen.left, screen.top, colW, rowH);
      case _ScreenCorner.topCenter:
        return Rect.fromLTWH(screen.left + colW, screen.top, colW, rowH);
      case _ScreenCorner.topRight:
        return Rect.fromLTWH(screen.left + colW * 2, screen.top, colW, rowH);
      case _ScreenCorner.bottomLeft:
        return Rect.fromLTWH(screen.left, screen.top + rowH * 2, colW, rowH);
      case _ScreenCorner.bottomRight:
        return Rect.fromLTWH(
            screen.left + colW * 2, screen.top + rowH * 2, colW, rowH);
    }
  }

  Offset _barOrigin(_ScreenCorner corner, Rect screen, int index) {
    final isLeft = _isLeftCorner(corner);
    final isTop = _isTopCorner(corner);
    final isCenter = corner == _ScreenCorner.topCenter;

    double x;
    if (isCenter) {
      x = screen.left + screen.width / 2 - _barW / 2;
    } else if (isLeft) {
      x = screen.left + _barSkip;
    } else {
      x = screen.right - _barSkip - _barW;
    }

    double y;
    if (isTop) {
      y = screen.top + _barTopSkip + index * (_barH + _barMargin);
    } else {
      y = screen.bottom -
          _barBottomSkip -
          _barH -
          index * (_barH + _barMargin);
    }
    return Offset(x, y);
  }

  void _drawSelectedBars(
      Canvas canvas, _ScreenCorner corner, Rect screen, Color barColor) {
    final barPaint = Paint();
    for (var i = 0; i < barOpacities.length; i++) {
      final opacity = barOpacities[i];
      if (opacity <= 0.0) continue;
      final origin = _barOrigin(corner, screen, i);
      barPaint.color = barColor.withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx, origin.dy, _barW, _barH),
          const Radius.circular(3),
        ),
        barPaint,
      );
    }
  }

  void _drawInactiveBar(
      Canvas canvas, _ScreenCorner corner, Rect screen, Color barColor) {
    final origin = _barOrigin(corner, screen, 0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy, _barW, _barH),
        const Radius.circular(3),
      ),
      Paint()..color = barColor.withValues(alpha: _inactiveOpacity),
    );
  }

  @override
  bool shouldRepaint(covariant _MonitorPainter old) => true;
}

class _NotificationCountSlider extends StatelessWidget {
  final int count;
  final bool isDark;
  final Color accentColor;
  final ValueChanged<int> onChanged;

  const _NotificationCountSlider({
    required this.count,
    required this.isDark,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final activeBg =
        isDark ? const Color(0xFF2B5278) : const Color(0xFF419FD9);
    final inactiveBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: List.generate(5, (i) {
          final n = i + 1;
          final isActive = n == count;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(n),
              child: Container(
                height: 36,
                margin: EdgeInsets.only(right: i < 4 ? 2 : 0),
                decoration: BoxDecoration(
                  color: isActive ? activeBg : inactiveBg,
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0
                        ? const Radius.circular(6)
                        : Radius.zero,
                    right: i == 4
                        ? const Radius.circular(6)
                        : Radius.zero,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : subtextColor,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DisplayRadioRow extends StatelessWidget {
  final String label;
  final int value;
  final int groupValue;
  final ValueChanged<int?> onChanged;
  final Color textColor;
  final Color accentColor;
  final Color hoverBg;

  const _DisplayRadioRow({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.textColor,
    required this.accentColor,
    required this.hoverBg,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Radio<int>(
                  value: value,
                  groupValue: groupValue,
                  onChanged: onChanged,
                  activeColor: accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NotifType { privateChats, groups, channels, reactions }

extension _NotifTypeExt on _NotifType {
  String get title {
    switch (this) {
      case _NotifType.privateChats:
        return 'Private chats';
      case _NotifType.groups:
        return 'Groups';
      case _NotifType.channels:
        return 'Channels';
      case _NotifType.reactions:
        return 'Reactions';
    }
  }

  String get volumeSubtitle {
    switch (this) {
      case _NotifType.privateChats:
        return 'Volume for private chats';
      case _NotifType.groups:
        return 'Volume for groups';
      case _NotifType.channels:
        return 'Volume for channels';
      case _NotifType.reactions:
        return 'Volume for reactions';
    }
  }
}

class _NotificationTypeSubPage extends StatefulWidget {
  final _NotifType type;

  const _NotificationTypeSubPage({required this.type});

  @override
  State<_NotificationTypeSubPage> createState() =>
      _NotificationTypeSubPageState();
}

class _NotifException {
  final String chatId;
  final String accountId;
  final String name;
  final String avatarPath;
  final bool isMuted;

  const _NotifException({
    required this.chatId,
    required this.accountId,
    required this.name,
    this.avatarPath = '',
    this.isMuted = true,
  });
}

class _MuteDuration {
  final String label;
  final int seconds;
  const _MuteDuration(this.label, this.seconds);
}

const _kMutePresets = <_MuteDuration>[
  _MuteDuration('15 minutes', 900),
  _MuteDuration('30 minutes', 1800),
  _MuteDuration('1 hour', 3600),
  _MuteDuration('2 hours', 7200),
  _MuteDuration('3 hours', 10800),
  _MuteDuration('4 hours', 14400),
  _MuteDuration('8 hours', 28800),
  _MuteDuration('12 hours', 43200),
  _MuteDuration('1 day', 86400),
  _MuteDuration('2 days', 172800),
  _MuteDuration('3 days', 259200),
  _MuteDuration('1 week', 604800),
  _MuteDuration('2 weeks', 1209600),
  _MuteDuration('1 month', 2592000),
];

String _compactDuration(int seconds) {
  if (seconds < 3600) return '${seconds ~/ 60}m';
  if (seconds < 86400) return '${seconds ~/ 3600}h';
  if (seconds < 604800) return '${seconds ~/ 86400}d';
  if (seconds < 2592000) return '${seconds ~/ 604800}w';
  return '${seconds ~/ 2592000}mo';
}

class _CustomTone {
  final int id;
  final String name;
  const _CustomTone({required this.id, required this.name});
}

class _NotificationTypeSubPageState extends State<_NotificationTypeSubPage> {
  bool _enabled = true;
  bool _soundEnabled = true;
  String _toneName = 'Default';
  int _selectedToneId = -1; // -1 = Default, -2 = No sound, >0 = custom
  int _volume = 100;
  final List<_CustomTone> _customTones = [];
  int _nextToneId = 1;
  final List<_NotifException> _exceptions = [];
  final List<int> _recentMuteDurations = [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

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
          widget.type.title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _NotifIconToggleRow(
            icon: Icons.notifications,
            iconColor: iconColor,
            label: 'Enable notifications',
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            textColor: textColor,
            accentColor: accentColor,
            hoverBg: hoverBg,
            onSecondaryTap: (pos) {
              _showMuteMenu(context, pos, isMuted: !_enabled);
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _enabled
                ? Column(
                    children: [
                      const SizedBox(height: 7),
                      Container(height: 1, color: dividerColor),
                      const SizedBox(height: 7),
                      _NotifIconToggleRow(
                        icon: Icons.volume_up,
                        iconColor: iconColor,
                        label: 'Sound',
                        value: _soundEnabled,
                        onChanged: (v) => setState(() => _soundEnabled = v),
                        textColor: textColor,
                        accentColor: accentColor,
                        hoverBg: hoverBg,
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: _soundEnabled
                            ? Column(
                                children: [
                                  _ToneRow(
                                    toneName: _toneName,
                                    textColor: textColor,
                                    subtextColor: subtextColor,
                                    iconColor: iconColor,
                                    hoverBg: hoverBg,
                                    accentColor: accentColor,
                                    isDark: isDark,
                                    onTap: () => _showRingtonesBox(context),
                                  ),
                                  _VolumeSliderSection(
                                    volume: _volume,
                                    onChanged: (v) =>
                                        setState(() => _volume = v),
                                    accentColor: accentColor,
                                    isDark: isDark,
                                    subtitle: widget.type.volumeSubtitle,
                                  ),
                                ],
                              )
                            : const SizedBox(
                                width: double.infinity, height: 0),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
            child: Text(
              'Exceptions',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sectionTitleColor,
              ),
            ),
          ),
          _AddExceptionButton(
            accentColor: accentColor,
            hoverBg: hoverBg,
            onTap: () => _showPeerPicker(context),
          ),
          for (final exc in _exceptions)
            _ExceptionRow(
              exception: exc,
              textColor: textColor,
              subtextColor: subtextColor,
              hoverBg: hoverBg,
              accentColor: accentColor,
              isDark: isDark,
              onRemove: () => setState(() =>
                  _exceptions.removeWhere((e) => e.chatId == exc.chatId)),
              onToggleMute: () {
                setState(() {
                  final idx = _exceptions.indexOf(exc);
                  if (idx >= 0) {
                    _exceptions[idx] = _NotifException(
                      chatId: exc.chatId,
                      accountId: exc.accountId,
                      name: exc.name,
                      avatarPath: exc.avatarPath,
                      isMuted: !exc.isMuted,
                    );
                  }
                });
              },
              onSecondaryTap: (pos) {
                _showMuteMenu(context, pos, isMuted: exc.isMuted);
              },
            ),
          if (_exceptions.length > 1)
            _DeleteAllExceptionsButton(
              hoverBg: hoverBg,
              isDark: isDark,
              onTap: () => _showDeleteAllConfirmation(context),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showPeerPicker(BuildContext context) {
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final existingIds = _exceptions.map((e) => e.chatId).toSet();
    final activeId = appState.activeAccountId;
    final allChats = chatState.chatsForAccount(activeId);
    final availableChats =
        allChats.where((c) => !existingIds.contains(c.chatId)).toList();
    var searchQuery = '';

    showDialog<ChatInfo>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            final filtered = searchQuery.isEmpty
                ? availableChats
                : availableChats
                    .where((c) => c.title
                        .toLowerCase()
                        .contains(searchQuery.toLowerCase()))
                    .toList();
            return AlertDialog(
              backgroundColor: bgColor,
              title: Text('Add an exception',
                  style: TextStyle(
                      color: textColor, fontWeight: FontWeight.w600)),
              contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
              content: SizedBox(
                width: 364,
                height: 400,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          hintStyle:
                              TextStyle(color: subtextColor, fontSize: 14),
                          prefixIcon:
                              Icon(Icons.search, color: subtextColor, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: subtextColor.withValues(alpha: 0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: subtextColor.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: accentColor),
                          ),
                        ),
                        onChanged: (v) =>
                            setDialogState(() => searchQuery = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text('No chats available',
                                  style: TextStyle(
                                      color: subtextColor, fontSize: 14)),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (itemCtx, i) {
                                final chat = filtered[i];
                                return InkWell(
                                  hoverColor: hoverBg,
                                  onTap: () {
                                    Navigator.of(dialogCtx).pop(chat);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        _PeerAvatar(
                                            name: chat.title,
                                            avatarPath: chat.avatarPath,
                                            size: 36),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            chat.title,
                                            style: TextStyle(
                                                fontSize: 14,
                                                color: textColor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text('Cancel', style: TextStyle(color: accentColor)),
                ),
              ],
            );
          },
        );
      },
    ).then((chat) {
      if (chat != null) {
        setState(() {
          _exceptions.add(_NotifException(
            chatId: chat.chatId,
            accountId: chat.accountId,
            name: chat.title,
            avatarPath: chat.avatarPath,
            isMuted: true,
          ));
        });
      }
    });
  }

  void _showDeleteAllConfirmation(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg =
        isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
    final dialogText =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final errorColor = const Color(0xFFDD4B39);

    showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: dialogBg,
          title: Text('Delete all exceptions',
              style:
                  TextStyle(color: dialogText, fontWeight: FontWeight.w600)),
          content: Text(
            'Are you sure you want to delete all ${_exceptions.length} exceptions?',
            style: TextStyle(color: dialogText, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: accentColor)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Delete', style: TextStyle(color: errorColor)),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() => _exceptions.clear());
      }
    });
  }

  void _showRingtonesBox(BuildContext context) {
    showDialog<_RingtonesResult>(
      context: context,
      builder: (ctx) => _RingtonesBoxDialog(
        selectedToneId: _selectedToneId,
        customTones: List.of(_customTones),
        volume: _volume,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    ).then((result) {
      if (result == null) return;
      setState(() {
        _selectedToneId = result.selectedToneId;
        _volume = result.volume;
        _customTones
          ..clear()
          ..addAll(result.customTones);
        if (result.selectedToneId == -1) {
          _toneName = 'Default';
        } else if (result.selectedToneId == -2) {
          _toneName = 'No sound';
        } else {
          final tone = result.customTones.where(
              (t) => t.id == result.selectedToneId);
          _toneName = tone.isNotEmpty ? tone.first.name : 'Default';
        }
        if (_nextToneId <= result.customTones.length) {
          _nextToneId = result.customTones.fold<int>(0,
              (m, t) => t.id > m ? t.id : m) + 1;
        }
      });
    });
  }

  void _addRecentDuration(int seconds) {
    _recentMuteDurations.remove(seconds);
    _recentMuteDurations.insert(0, seconds);
    if (_recentMuteDurations.length > 2) {
      _recentMuteDurations.removeRange(2, _recentMuteDurations.length);
    }
  }

  void _showMuteMenu(BuildContext context, Offset position,
      {bool isMuted = false}) {
    final greenColor = const Color(0xFF4CAF50);

    final items = <TelegramMenuItem<String>>[
      const TelegramMenuItem<String>(
        value: 'select_tone',
        icon: Icon(Icons.music_note, size: 20),
        label: 'Select tone',
      ),
      TelegramMenuItem<String>(
        value: 'toggle_sound',
        icon: Icon(
            _soundEnabled ? Icons.volume_off : Icons.volume_up,
            size: 20),
        label: _soundEnabled ? 'Disable sound' : 'Enable sound',
      ),
      if (_recentMuteDurations.isNotEmpty) ...[
        const TelegramMenuItem<String>.separator(),
        for (final dur in _recentMuteDurations)
          TelegramMenuItem<String>(
            value: 'recent_$dur',
            icon: const Icon(Icons.access_time, size: 20),
            label: 'Mute for ${_compactDuration(dur)}',
          ),
      ],
      const TelegramMenuItem<String>.separator(),
      const TelegramMenuItem<String>(
        value: 'mute_for',
        icon: Icon(Icons.timer_outlined, size: 20),
        label: 'Mute for\u2026',
      ),
      const TelegramMenuItem<String>.separator(),
      if (isMuted)
        TelegramMenuItem<String>(
          value: 'unmute',
          icon: const Icon(Icons.notifications, size: 20),
          label: 'Unmute',
          labelColor: greenColor,
          iconColor: greenColor,
        )
      else
        const TelegramMenuItem<String>(
          value: 'mute_forever',
          icon: Icon(Icons.notifications_off, size: 20),
          label: 'Mute forever',
          isAttention: true,
        ),
    ];

    showTelegramMenu<String>(
      context: context,
      position: position,
      items: items,
    ).then((value) {
      if (value == null) return;
      if (value == 'select_tone') {
        _showRingtonesBox(context);
      } else if (value == 'toggle_sound') {
        setState(() => _soundEnabled = !_soundEnabled);
      } else if (value.startsWith('recent_')) {
        final seconds = int.tryParse(value.substring(7));
        if (seconds != null) {
          _addRecentDuration(seconds);
          setState(() => _enabled = false);
        }
      } else if (value == 'mute_for') {
        _showMuteDurationPicker(context);
      } else if (value == 'mute_forever') {
        setState(() => _enabled = false);
      } else if (value == 'unmute') {
        setState(() => _enabled = true);
      }
    });
  }

  void _showMuteDurationPicker(BuildContext context) {
    showDialog<int>(
      context: context,
      builder: (ctx) => _MuteDurationPickerDialog(
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    ).then((seconds) {
      if (seconds != null) {
        _addRecentDuration(seconds);
        setState(() => _enabled = false);
      }
    });
  }
}

class _MuteDurationPickerDialog extends StatefulWidget {
  final bool isDark;

  const _MuteDurationPickerDialog({required this.isDark});

  @override
  State<_MuteDurationPickerDialog> createState() =>
      _MuteDurationPickerDialogState();
}

class _MuteDurationPickerDialogState
    extends State<_MuteDurationPickerDialog> {
  late final FixedExtentScrollController _scrollController;
  int _selectedIndex = 2;

  @override
  void initState() {
    super.initState();
    _scrollController =
        FixedExtentScrollController(initialItem: _selectedIndex);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
    final textColor =
        widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        widget.isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final highlightColor =
        widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return AlertDialog(
      backgroundColor: bgColor,
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Mute for\u2026',
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 17),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: subtextColor, size: 20),
            color: bgColor,
            onSelected: (value) {
              if (value == 'custom') {
                Navigator.of(context).pop();
                _showCustomDurationInput(context);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'custom',
                child: Text('Custom',
                    style: TextStyle(color: textColor, fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      content: SizedBox(
        width: 300,
        height: 200,
        child: Stack(
          children: [
            Center(
              child: Container(
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: highlightColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            ListWheelScrollView.useDelegate(
              controller: _scrollController,
              itemExtent: 40,
              perspective: 0.005,
              diameterRatio: 1.5,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                setState(() => _selectedIndex = index);
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: _kMutePresets.length,
                builder: (context, index) {
                  final isSelected = index == _selectedIndex;
                  return Center(
                    child: Text(
                      _kMutePresets[index].label,
                      style: TextStyle(
                        fontSize: isSelected ? 17 : 15,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected ? accentColor : subtextColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: accentColor)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context)
                .pop(_kMutePresets[_selectedIndex].seconds);
          },
          child: Text('Mute', style: TextStyle(color: accentColor)),
        ),
      ],
    );
  }

  void _showCustomDurationInput(BuildContext parentContext) {
    final bgColor =
        widget.isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
    final textColor =
        widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        widget.isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final hoursCtrl = TextEditingController(text: '0');
    final minutesCtrl = TextEditingController(text: '30');

    showDialog<int>(
      context: parentContext,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Custom duration',
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 17)),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: hoursCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: textColor, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Hours',
                    labelStyle: TextStyle(color: subtextColor),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color:
                                subtextColor.withValues(alpha: 0.3))),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: accentColor)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: textColor, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Minutes',
                    labelStyle: TextStyle(color: subtextColor),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color:
                                subtextColor.withValues(alpha: 0.3))),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: accentColor)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('Cancel', style: TextStyle(color: accentColor)),
            ),
            TextButton(
              onPressed: () {
                final h = int.tryParse(hoursCtrl.text) ?? 0;
                final m = int.tryParse(minutesCtrl.text) ?? 0;
                final total = h * 3600 + m * 60;
                if (total > 0) Navigator.of(ctx).pop(total);
              },
              child: Text('Mute', style: TextStyle(color: accentColor)),
            ),
          ],
        );
      },
    ).then((seconds) {
      if (seconds != null) {
        final pageState = parentContext
            .findAncestorStateOfType<_NotificationTypeSubPageState>();
        if (pageState != null && pageState.mounted) {
          pageState._addRecentDuration(seconds);
          pageState.setState(() => pageState._enabled = false);
        }
      }
    });
  }
}

class _ToneRow extends StatelessWidget {
  final String toneName;
  final Color textColor;
  final Color subtextColor;
  final Color iconColor;
  final Color hoverBg;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _ToneRow({
    required this.toneName,
    required this.textColor,
    required this.subtextColor,
    required this.iconColor,
    required this.hoverBg,
    required this.accentColor,
    required this.isDark,
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
            Icon(Icons.music_note, size: 24, color: iconColor),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Text(
                'Notification tone',
                style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize, color: textColor),
              ),
            ),
            Text(
              toneName,
              style: TextStyle(fontSize: 14, color: subtextColor),
            ),
          ],
        ),
      ),
    );
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
  final String? subtitle;

  const _VolumeSliderSection({
    required this.volume,
    required this.onChanged,
    required this.accentColor,
    required this.isDark,
    this.subtitle,
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
            subtitle ?? 'Volume',
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
  final void Function(Offset globalPosition)? onSecondaryTap;

  const _NotifIconToggleRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.textColor,
    required this.accentColor,
    required this.hoverBg,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton && onSecondaryTap != null) {
          onSecondaryTap!(event.position);
        }
      },
      child: InkWell(
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
                      fontSize: SettingsStyle.buttonFontSize,
                      color: textColor),
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
      ),
    );
  }
}

class _NoIconToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color textColor;
  final Color accentColor;
  final Color hoverBg;

  const _NoIconToggleRow({
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

class _SplitToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTap;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final Color hoverBg;
  final bool isDark;
  final int exceptionCount;
  final String? statusOverride;

  const _SplitToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onToggle,
    this.onTap,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.hoverBg,
    required this.isDark,
    this.exceptionCount = 0,
    this.statusOverride,
  });

  String get _statusText {
    if (statusOverride != null) return statusOverride!;
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
              onTap: onTap ?? () {},
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

enum _ReactionsFrom { everyone, contacts }

class _ReactionsSubPage extends StatefulWidget {
  const _ReactionsSubPage();

  @override
  State<_ReactionsSubPage> createState() => _ReactionsSubPageState();
}

class _ReactionsSubPageState extends State<_ReactionsSubPage> {
  bool _reactionsEnabled = true;
  _ReactionsFrom _reactionsFrom = _ReactionsFrom.everyone;
  bool _pollVotesEnabled = true;
  _ReactionsFrom _pollVotesFrom = _ReactionsFrom.everyone;
  bool _showSenderName = true;

  void _showFromDialog(
    BuildContext context, {
    required String title,
    required _ReactionsFrom current,
    required ValueChanged<_ReactionsFrom> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    showDialog<_ReactionsFrom>(
      context: context,
      builder: (ctx) {
        var selected = current;
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
              contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<_ReactionsFrom>(
                    title: Text('From everyone',
                        style: TextStyle(color: textColor, fontSize: 14)),
                    value: _ReactionsFrom.everyone,
                    groupValue: selected,
                    activeColor: accentColor,
                    onChanged: (v) {
                      setDialogState(() => selected = v!);
                    },
                  ),
                  RadioListTile<_ReactionsFrom>(
                    title: Text('From my contacts',
                        style: TextStyle(color: textColor, fontSize: 14)),
                    value: _ReactionsFrom.contacts,
                    groupValue: selected,
                    activeColor: accentColor,
                    onChanged: (v) {
                      setDialogState(() => selected = v!);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: accentColor)),
                ),
                TextButton(
                  onPressed: () {
                    onChanged(selected);
                    Navigator.of(ctx).pop();
                  },
                  child: Text('OK', style: TextStyle(color: accentColor)),
                ),
              ],
            );
          },
        );
      },
    );
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
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final sectionTitleColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

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
          'Notifications for reactions',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
            child: Text(
              'Notify me about',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sectionTitleColor,
              ),
            ),
          ),
          _SplitToggleRow(
            icon: Icons.mark_unread_chat_alt,
            label: 'Reactions to my messages',
            value: _reactionsEnabled,
            onToggle: (v) => setState(() => _reactionsEnabled = v),
            onTap: _reactionsEnabled
                ? () => _showFromDialog(
                      context,
                      title: 'Notify about reactions from',
                      current: _reactionsFrom,
                      onChanged: (v) =>
                          setState(() => _reactionsFrom = v),
                    )
                : null,
            statusOverride: _reactionsEnabled
                ? (_reactionsFrom == _ReactionsFrom.everyone
                    ? 'From everyone'
                    : 'From my contacts')
                : 'Disabled',
            textColor: textColor,
            subtextColor: subtextColor,
            accentColor: accentColor,
            hoverBg: hoverBg,
            isDark: isDark,
          ),
          _SplitToggleRow(
            icon: Icons.poll,
            label: 'Votes in my polls',
            value: _pollVotesEnabled,
            onToggle: (v) => setState(() => _pollVotesEnabled = v),
            onTap: _pollVotesEnabled
                ? () => _showFromDialog(
                      context,
                      title: 'Notify about votes from',
                      current: _pollVotesFrom,
                      onChanged: (v) =>
                          setState(() => _pollVotesFrom = v),
                    )
                : null,
            statusOverride: _pollVotesEnabled
                ? (_pollVotesFrom == _ReactionsFrom.everyone
                    ? 'From everyone'
                    : 'From my contacts')
                : 'Disabled',
            textColor: textColor,
            subtextColor: subtextColor,
            accentColor: accentColor,
            hoverBg: hoverBg,
            isDark: isDark,
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
            child: Text(
              'Settings',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sectionTitleColor,
              ),
            ),
          ),
          _NotifIconToggleRow(
            icon: Icons.person,
            iconColor: iconColor,
            label: 'Show sender\'s name',
            value: _showSenderName,
            onChanged: (v) => setState(() => _showSenderName = v),
            textColor: textColor,
            accentColor: accentColor,
            hoverBg: hoverBg,
          ),
          const SizedBox(height: 32),
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

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 150),
      builder: (ctx, opacity, child) => Opacity(opacity: opacity, child: child),
      child: Padding(
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
    ),
    );
  }
}

class _AddExceptionButton extends StatelessWidget {
  final Color accentColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _AddExceptionButton({
    required this.accentColor,
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
            Icon(Icons.person_add, size: 24, color: accentColor),
            const SizedBox(width: SettingsStyle.iconGap),
            Text(
              'Add an exception',
              style: TextStyle(
                fontSize: SettingsStyle.buttonFontSize,
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExceptionRow extends StatelessWidget {
  final _NotifException exception;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onRemove;
  final VoidCallback onToggleMute;
  final void Function(Offset globalPosition)? onSecondaryTap;

  const _ExceptionRow({
    required this.exception,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.accentColor,
    required this.isDark,
    required this.onRemove,
    required this.onToggleMute,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final muteStatusColor = exception.isMuted
        ? const Color(0xFFDD4B39)
        : const Color(0xFF4CAF50);
    final removeColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);

    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton && onSecondaryTap != null) {
          onSecondaryTap!(event.position);
        }
      },
      child: InkWell(
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      onTap: onToggleMute,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 22, 6),
        child: Row(
          children: [
            _PeerAvatar(
              name: exception.name,
              avatarPath: exception.avatarPath,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exception.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    exception.isMuted ? 'Muted' : 'Unmuted',
                    style: TextStyle(
                      fontSize: 12,
                      color: muteStatusColor,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: Text(
                'Remove',
                style: TextStyle(
                  fontSize: 14,
                  color: removeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _DeleteAllExceptionsButton extends StatelessWidget {
  final Color hoverBg;
  final bool isDark;
  final VoidCallback onTap;

  const _DeleteAllExceptionsButton({
    required this.hoverBg,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const errorColor = Color(0xFFDD4B39);
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            const Icon(Icons.delete_outline, size: 24, color: errorColor),
            const SizedBox(width: SettingsStyle.iconGap),
            const Text(
              'Delete all exceptions',
              style: TextStyle(
                fontSize: SettingsStyle.buttonFontSize,
                color: errorColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  final String name;
  final String avatarPath;
  final double size;

  const _PeerAvatar({
    required this.name,
    required this.avatarPath,
    required this.size,
  });

  static const _fallbackColors = [
    Color(0xFFE17076),
    Color(0xFF7BC862),
    Color(0xFFE5CA77),
    Color(0xFF65AADD),
    Color(0xFFA695E7),
    Color(0xFFEE7AAE),
    Color(0xFF6EC9CB),
  ];

  @override
  Widget build(BuildContext context) {
    if (avatarPath.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(),
        ),
      );
    }
    return _fallbackAvatar();
  }

  Widget _fallbackAvatar() {
    final colorIdx = name.isEmpty ? 0 : name.codeUnitAt(0) % _fallbackColors.length;
    final initials = name.isEmpty
        ? '?'
        : name
            .split(' ')
            .where((s) => s.isNotEmpty)
            .take(2)
            .map((s) => s[0].toUpperCase())
            .join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _fallbackColors[colorIdx],
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.4,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
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

class _RingtonesResult {
  final int selectedToneId;
  final List<_CustomTone> customTones;
  final int volume;
  const _RingtonesResult({
    required this.selectedToneId,
    required this.customTones,
    required this.volume,
  });
}

class _RingtonesBoxDialog extends StatefulWidget {
  final int selectedToneId;
  final List<_CustomTone> customTones;
  final int volume;
  final bool isDark;

  const _RingtonesBoxDialog({
    required this.selectedToneId,
    required this.customTones,
    required this.volume,
    required this.isDark,
  });

  @override
  State<_RingtonesBoxDialog> createState() => _RingtonesBoxDialogState();
}

class _RingtonesBoxDialogState extends State<_RingtonesBoxDialog> {
  static const _kDefaultValue = -1;
  static const _kNoSoundValue = -2;
  static const _kMaxTones = 100;
  static const _kMaxSizeBytes = 100 * 1024;
  static const _kMaxDurationSec = 5;

  late int _selectedId;
  late List<_CustomTone> _tones;
  late int _volume;
  int _nextId = 1;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedToneId;
    _tones = List.of(widget.customTones);
    _volume = widget.volume;
    if (_tones.isNotEmpty) {
      _nextId = _tones.fold<int>(0, (m, t) => t.id > m ? t.id : m) + 1;
    }
  }

  Color get _bgColor =>
      widget.isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
  Color get _textColor =>
      widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
  Color get _subtextColor =>
      widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
  Color get _accentColor =>
      widget.isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
  Color get _sectionTitleColor =>
      widget.isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
  Color get _dividerColor =>
      widget.isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);
  Color get _hoverBg =>
      widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  void _onUploadSound() async {
    if (_tones.length >= _kMaxTones) {
      if (!mounted) return;
      showTelegramToast(context, 'You can upload at most $_kMaxTones notification sounds.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final file = result.files.first;
    final bytes = file.size;

    if (bytes > _kMaxSizeBytes) {
      showTelegramToast(context, 'The file is too large (${_formatSize(bytes)}). '
          'Maximum allowed size is ${_formatSize(_kMaxSizeBytes)}.');
      return;
    }

    final name = (file.name.endsWith('.mp3')
            ? file.name.substring(0, file.name.length - 4)
            : file.name)
        .trim();
    final displayName = name.isEmpty ? 'Audio file' : name;

    setState(() {
      final tone = _CustomTone(id: _nextId, name: displayName);
      _tones.add(tone);
      _selectedId = _nextId;
      _nextId++;
    });
  }

  void _deleteTone(int id) {
    setState(() {
      _tones.removeWhere((t) => t.id == id);
      if (_selectedId == id) {
        _selectedId = _kDefaultValue;
      }
    });
  }

  void _showDeleteMenu(BuildContext context, Offset position, int toneId) {
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: const [
        TelegramMenuItem<String>(
          value: 'delete',
          icon: Icon(Icons.delete_outline, size: 20, color: Color(0xFFDD4B39)),
          label: 'Delete',
          isAttention: true,
        ),
      ],
    ).then((value) {
      if (value == 'delete') _deleteTone(toneId);
    });
  }

  Widget _buildRadioRow(int value, String label, {bool isCustom = false}) {
    final isSelected = _selectedId == value;
    return Listener(
      onPointerDown: (event) {
        if (isCustom &&
            event.buttons == kSecondaryMouseButton) {
          _showDeleteMenu(context, event.position, value);
        }
      },
      child: InkWell(
        onTap: () => setState(() => _selectedId = value),
        hoverColor: _hoverBg,
        splashColor: _hoverBg.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Radio<int>(
                    value: value,
                    groupValue: _selectedId,
                    onChanged: (v) =>
                        setState(() => _selectedId = v ?? _selectedId),
                    activeColor: _accentColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: _textColor,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showVolume = _selectedId != _kNoSoundValue;

    return AlertDialog(
      backgroundColor: _bgColor,
      title: Text(
        'Notification Sound',
        style: TextStyle(
          color: _textColor,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 364,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(
                'Cloud',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _sectionTitleColor,
                ),
              ),
            ),
            _buildRadioRow(_kDefaultValue, 'Default'),
            _buildRadioRow(_kNoSoundValue, 'No sound'),
            if (_tones.isNotEmpty) ...[
              for (final tone in _tones)
                _buildRadioRow(tone.id, tone.name, isCustom: true),
            ],
            const SizedBox(height: 4),
            InkWell(
              onTap: _onUploadSound,
              hoverColor: _hoverBg,
              splashColor: _hoverBg.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(25, 10, 22, 8),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _accentColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, size: 14, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Upload Sound',
                      style: TextStyle(
                        fontSize: 14,
                        color: _accentColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: showVolume
                  ? _VolumeSliderSection(
                      volume: _volume,
                      onChanged: (v) => setState(() => _volume = v),
                      accentColor: _accentColor,
                      isDark: widget.isDark,
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
            const SizedBox(height: 7),
            Container(height: 1, color: _dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                'Right click on any short voice note or MP3 file '
                'in chat and select "Save for Notifications".',
                style: TextStyle(fontSize: 13, color: _subtextColor),
              ),
            ),
            const SizedBox(height: 7),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: _accentColor)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(_RingtonesResult(
              selectedToneId: _selectedId,
              customTones: List.of(_tones),
              volume: _volume,
            ));
          },
          child: Text('Save', style: TextStyle(color: _accentColor)),
        ),
      ],
    );
  }
}
