import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../models/engine_models.dart';
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

  void _openTypeSubPage(BuildContext context, _NotifType type) {
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

class _NotificationTypeSubPageState extends State<_NotificationTypeSubPage> {
  bool _enabled = true;
  bool _soundEnabled = true;
  String _toneName = 'Default';
  int _volume = 100;
  final List<_NotifException> _exceptions = [];

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final tones = ['Default', 'No sound'];
    var selectedTone = _toneName;

    showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: Text('Notification Sound',
                  style: TextStyle(
                      color: textColor, fontWeight: FontWeight.w600)),
              contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
              content: SizedBox(
                width: 364,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tone in tones)
                      InkWell(
                        onTap: () =>
                            setDialogState(() => selectedTone = tone),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          child: Row(
                            children: [
                              Radio<String>(
                                value: tone,
                                groupValue: selectedTone,
                                onChanged: (v) => setDialogState(
                                    () => selectedTone = v ?? selectedTone),
                                activeColor: accentColor,
                              ),
                              const SizedBox(width: 8),
                              Text(tone,
                                  style: TextStyle(
                                      fontSize: 14, color: textColor)),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(24, 12, 24, 8),
                      child: Text(
                        'Right click on any short voice note or MP3 file in chat and select "Save for Notifications".',
                        style: TextStyle(fontSize: 13, color: subtextColor),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: accentColor)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(selectedTone),
                  child: Text('Save', style: TextStyle(color: accentColor)),
                ),
              ],
            );
          },
        );
      },
    ).then((result) {
      if (result != null) {
        setState(() => _toneName = result);
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
  final VoidCallback? onTap;
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
    this.onTap,
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

  const _ExceptionRow({
    required this.exception,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.accentColor,
    required this.isDark,
    required this.onRemove,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    final muteStatusColor = exception.isMuted
        ? const Color(0xFFDD4B39)
        : const Color(0xFF4CAF50);
    final removeColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);

    return InkWell(
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
