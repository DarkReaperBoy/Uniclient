import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import '../theme/theme.dart';
import 'confirm_box.dart';
import 'popup_menu.dart';
import 'settings_style.dart';
import 'telegram_toast.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  List<_ActiveGroupCallEntry> _activeGroupCalls = [];
  StreamSubscription<GroupCallStateEvent>? _groupCallSub;

  List<CallHistoryEntry> _callHistory = [];
  List<_CallGroup> _groupedCalls = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  static const _kFirstPage = 20;
  static const _kNextPage = 100;

  @override
  void initState() {
    super.initState();
    _loadActiveGroupCalls();
    _loadCallHistory();
    final engine = context.read<EngineService>();
    _groupCallSub = engine.onGroupCallState.listen(_onGroupCallEvent);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _groupCallSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMoreCallHistory();
    }
  }

  Future<void> _loadCallHistory() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    final entries = await engine.getCallHistory(accountId, limit: _kFirstPage);
    if (mounted) {
      setState(() {
        _callHistory = entries;
        _groupedCalls = _groupCallEntries(_callHistory);
        _isLoading = false;
        _hasMore = entries.length >= _kFirstPage;
      });
    }
  }

  Future<void> _loadMoreCallHistory() async {
    if (_callHistory.isEmpty) return;
    setState(() => _loadingMore = true);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    final lastMsgId = int.tryParse(_callHistory.last.msgId) ?? 0;
    final entries = await engine.getCallHistory(
      accountId,
      offsetId: lastMsgId,
      limit: _kNextPage,
    );
    if (mounted) {
      setState(() {
        _callHistory.addAll(entries);
        _groupedCalls = _groupCallEntries(_callHistory);
        _loadingMore = false;
        _hasMore = entries.length >= _kNextPage;
      });
    }
  }

  static String _callTypeKey(CallHistoryEntry e) {
    if (e.isOutgoing) return 'out';
    if (e.isMissed) return 'missed';
    return 'in';
  }

  static String _dateKey(int epochSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    return '${dt.year}-${dt.month}-${dt.day}';
  }

  static List<_CallGroup> _groupCallEntries(List<CallHistoryEntry> entries) {
    if (entries.isEmpty) return [];
    final groups = <_CallGroup>[];
    var current = [entries.first];
    for (var i = 1; i < entries.length; i++) {
      final prev = current.first;
      final e = entries[i];
      if (e.peerId == prev.peerId &&
          _dateKey(e.timestamp) == _dateKey(prev.timestamp) &&
          _callTypeKey(e) == _callTypeKey(prev)) {
        current.add(e);
      } else {
        groups.add(_CallGroup(current));
        current = [e];
      }
    }
    groups.add(_CallGroup(current));
    return groups;
  }

  Future<void> _loadActiveGroupCalls() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    final chats = engine.getChatList(accountId: accountId, limit: 20);
    final pinned = chats.where((c) => c.isPinned);
    final nonPinned = chats.where((c) => !c.isPinned);
    final candidates = [...pinned, ...nonPinned]
        .where((c) => c.type == ChatType.group || c.type == ChatType.channel)
        .take(20)
        .toList();

    final entries = <_ActiveGroupCallEntry>[];
    for (final chat in candidates) {
      try {
        final gc = await engine.getGroupCall(accountId, chat.chatId);
        if (gc != null && gc.active) {
          entries.add(_ActiveGroupCallEntry(chat: chat, callInfo: gc));
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _activeGroupCalls = entries);
    }
  }

  void _onGroupCallEvent(GroupCallStateEvent event) {
    _loadActiveGroupCalls();
  }

  void _showClearCallHistoryDialog() {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    bool revoke = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final p = ctx.palette;
            return AlertDialog(
              backgroundColor: p.boxBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text(
                'Clear Call History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: p.boxTitleFg,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete all call history?',
                    style: TextStyle(fontSize: 14, color: p.boxTextFg),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: revoke,
                          onChanged: (v) => setDialogState(() => revoke = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => revoke = !revoke),
                          child: Text(
                            'Also delete for other participants',
                            style: TextStyle(fontSize: 14, color: p.boxTextFg),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: p.windowBgActive),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await engine.clearCallHistory(accountId, revoke: revoke);
                      if (mounted) {
                        setState(() {
                          _callHistory.clear();
                          _groupedCalls.clear();
                        });
                      }
                    } catch (_) {}
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(color: p.attentionButtonFg),
                  ),
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
    final p = context.palette;

    final bgColor = p.boxBg;
    final textColor = p.boxTextFg;
    final subtextColor = p.boxTitleAdditionalFg;
    final dividerColor = p.boxDividerBg;
    final accentColor = p.windowBgActive;
    final menuIconColor = p.menuIconFg;
    final attentionColor = p.attentionButtonFg;

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
          'Calls',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: menuIconColor),
            color: p.boxBg,
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  Navigator.of(context).push(
                    settingsPageRoute(const _CallSettingsScreen()),
                  );
                case 'clear_all':
                  _showClearCallHistoryDialog();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20, color: menuIconColor),
                    const SizedBox(width: 12),
                    Text(
                      'Call Settings',
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ],
                ),
              ),
              if (_callHistory.isNotEmpty)
                PopupMenuItem<String>(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: attentionColor),
                      const SizedBox(width: 12),
                      Text(
                        'Clear All',
                        style: TextStyle(fontSize: 14, color: attentionColor),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _ActiveGroupCallsSection(
            entries: _activeGroupCalls,
            isDark: isDark,
            textColor: textColor,
            subtextColor: subtextColor,
            dividerColor: dividerColor,
            accentColor: accentColor,
            menuIconColor: menuIconColor,
          ),
          _CreateCallButton(
            accentColor: accentColor,
            textColor: textColor,
            subtextColor: subtextColor,
            dividerColor: dividerColor,
            isDark: isDark,
          ),
          Divider(height: 1, color: dividerColor),
          Expanded(
            child: _buildCallHistoryList(
              isDark: isDark,
              textColor: textColor,
              subtextColor: subtextColor,
              accentColor: accentColor,
              menuIconColor: menuIconColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallHistoryList({
    required bool isDark,
    required Color textColor,
    required Color subtextColor,
    required Color accentColor,
    required Color menuIconColor,
  }) {
    if (_isLoading) {
      return Center(
        child: Text(
          'Loading...',
          style: TextStyle(fontSize: 14, color: subtextColor),
        ),
      );
    }

    if (_callHistory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Your recent calls will appear here.',
            style: TextStyle(fontSize: 14, color: subtextColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _groupedCalls.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _groupedCalls.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )),
          );
        }
        return _CallHistoryRow(
          group: _groupedCalls[index],
          accountId: context.read<AppState>().activeAccountId,
          isDark: isDark,
          textColor: textColor,
          subtextColor: subtextColor,
          menuIconColor: menuIconColor,
          onDeleted: (group) {
            setState(() {
              for (final e in group.entries) {
                _callHistory.removeWhere((c) => c.msgId == e.msgId);
              }
              _groupedCalls = _groupCallEntries(_callHistory);
            });
          },
        );
      },
    );
  }
}

class _ActiveGroupCallEntry {
  final ChatInfo chat;
  final GroupCallInfo callInfo;
  const _ActiveGroupCallEntry({required this.chat, required this.callInfo});
}

class _ActiveGroupCallsSection extends StatelessWidget {
  final List<_ActiveGroupCallEntry> entries;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color dividerColor;
  final Color accentColor;
  final Color menuIconColor;

  const _ActiveGroupCallsSection({
    required this.entries,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.dividerColor,
    required this.accentColor,
    required this.menuIconColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: entries.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
                  child: Text(
                    'Active Group Calls',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
                for (final entry in entries)
                  _GroupCallRow(
                    entry: entry,
                    isDark: isDark,
                    textColor: textColor,
                    subtextColor: subtextColor,
                    menuIconColor: menuIconColor,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: dividerColor),
                ),
              ],
            ),
    );
  }
}

class _GroupCallRow extends StatefulWidget {
  final _ActiveGroupCallEntry entry;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color menuIconColor;

  const _GroupCallRow({
    required this.entry,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.menuIconColor,
  });

  @override
  State<_GroupCallRow> createState() => _GroupCallRowState();
}

class _GroupCallRowState extends State<_GroupCallRow> {
  bool _hovered = false;

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  String _chatTypeLabel(ChatInfo chat) {
    switch (chat.type) {
      case ChatType.channel:
        return 'channel';
      case ChatType.group:
        return 'group';
      default:
        return 'chat';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.entry.chat;
    final isChannel = chat.type == ChatType.channel;
    final hoverBg =
        widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
    final avatarColor = context.palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
    final initials = _getInitials(chat.title);
    final avatarCorner = context.watch<AppState>().avatarCorners;
    const avatarSize = 42.0;
    final avatarRadius = avatarSize / 2 * (avatarCorner / 23.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final chatState = context.read<ChatState>();
          chatState.openChat(chat);
          Navigator.of(context).pop();
        },
        child: Container(
          height: 56,
          color: _hovered ? hoverBg : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: chat.avatarPath.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(avatarRadius),
                        child: Image.file(
                          File(chat.avatarPath),
                          width: avatarSize,
                          height: avatarSize,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackAvatar(
                              avatarColor, initials, avatarSize, avatarRadius),
                        ),
                      )
                    : _fallbackAvatar(
                        avatarColor, initials, avatarSize, avatarRadius),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _chatTypeLabel(chat),
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.subtextColor,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (isChannel)
                SizedBox(
                  width: 40,
                  height: 56,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      final engine = context.read<EngineService>();
                      try {
                        await engine.joinGroupCall(
                            chat.accountId, chat.chatId);
                      } catch (_) {}
                    },
                    icon: Icon(
                      Icons.call,
                      size: 20,
                      color: _hovered
                          ? (widget.isDark
                              ? const Color(0xFFACBBC9)
                              : const Color(0xFF6A6A6A))
                          : widget.menuIconColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackAvatar(
      Color color, String initials, double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _CreateCallButton extends StatefulWidget {
  final Color accentColor;
  final Color textColor;
  final Color subtextColor;
  final Color dividerColor;
  final bool isDark;
  final bool highlightOnShow;

  const _CreateCallButton({
    required this.accentColor,
    required this.textColor,
    required this.subtextColor,
    required this.dividerColor,
    required this.isDark,
    this.highlightOnShow = false,
  });

  @override
  State<_CreateCallButton> createState() => _CreateCallButtonState();
}

class _CreateCallButtonState extends State<_CreateCallButton>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _highlightController;
  late final Animation<double> _highlightAnim;

  static const _confcallSizeLimit = 200;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _highlightAnim = CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeOutCubic,
    );
    if (widget.highlightOnShow) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _highlightController.forward();
      });
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  void _openCreateCallBox() {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();

    showDialog<bool>(
      context: context,
      builder: (ctx) => Provider<EngineService>.value(
        value: engine,
        child: ChangeNotifierProvider.value(
          value: appState,
          child: const _CreateCallBox(),
        ),
      ),
    ).then((created) {
      if (created == true && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hoverBg = widget.isDark
        ? const Color(0xFF202B36)
        : const Color(0xFFF1F1F1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _highlightAnim,
          builder: (context, child) {
            final highlightOpacity = _highlightAnim.value < 0.5
                ? _highlightAnim.value * 2
                : (1.0 - _highlightAnim.value) * 2;
            final highlightBg = highlightOpacity > 0
                ? widget.accentColor.withValues(alpha: 0.15 * highlightOpacity)
                : null;

            return MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openCreateCallBox,
                child: Container(
                  color: highlightBg ?? (_hovered ? hoverBg : Colors.transparent),
                  padding: const EdgeInsets.only(
                    left: 21, top: 11, right: 20, bottom: 9,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: widget.accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_call,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Create Call',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(left: 21, right: 20, top: 6, bottom: 8),
          child: Text(
            'You can create a group call for up to $_confcallSizeLimit participants.',
            style: TextStyle(
              fontSize: 13,
              color: widget.subtextColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _CreateCallBox extends StatefulWidget {
  final List<String> prioritize;
  final int discardedInviteMsgId;

  const _CreateCallBox({
    this.prioritize = const [],
    this.discardedInviteMsgId = 0,
  });

  @override
  State<_CreateCallBox> createState() => _CreateCallBoxState();
}

class _CreateCallBoxState extends State<_CreateCallBox> {
  List<ContactInfo>? _contacts;
  bool _loading = true;
  bool _creatingLink = false;
  final Set<String> _selectedIds = {};
  final Map<String, bool> _selectedVideo = {};
  bool _lastSelectWithVideo = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _confcallSizeLimit = 200;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    try {
      final contacts = await engine.getContacts(accountId);
      if (mounted) {
        setState(() {
          _contacts = contacts
              .where((c) => !c.isBot)
              .toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ContactInfo> get _filteredContacts {
    final all = _contacts ?? [];
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((c) =>
        c.displayName.toLowerCase().contains(q) ||
        c.username.toLowerCase().contains(q)).toList();
  }

  List<ContactInfo> get _prioritizedContacts {
    if (widget.prioritize.isEmpty || _contacts == null) return [];
    final pSet = widget.prioritize.toSet();
    return _contacts!.where((c) => pSet.contains(c.userId)).toList();
  }

  List<ContactInfo> get _mainContacts {
    final filtered = _filteredContacts;
    if (widget.prioritize.isEmpty) return filtered;
    final pSet = widget.prioritize.toSet();
    return filtered.where((c) => !pSet.contains(c.userId)).toList();
  }

  void _toggleContact(String userId, {bool? video}) {
    setState(() {
      if (_selectedIds.contains(userId)) {
        if (video != null) {
          _selectedVideo[userId] = video;
          _lastSelectWithVideo = video;
        } else {
          _selectedIds.remove(userId);
          _selectedVideo.remove(userId);
        }
      } else {
        if (_selectedIds.length >= _confcallSizeLimit) {
          showTelegramToast(context, "You can't add more participants to this call.");
          return;
        }
        _selectedIds.add(userId);
        final useVideo = video ?? _lastSelectWithVideo;
        _selectedVideo[userId] = useVideo;
        if (video != null) _lastSelectWithVideo = video;
      }
    });
  }

  Future<void> _createCall() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;

    try {
      if (_selectedIds.length == 1 && widget.discardedInviteMsgId == 0) {
        final userId = _selectedIds.first;
        final video = _selectedVideo[userId] ?? false;
        final permOk = await requestCallPermissions(context, video: video);
        if (!permOk || !mounted) return;
        await engine.startCall(accountId, userId, video: video);
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final result = await engine.createConferenceCall(accountId);
        if (result != null && result.inviteLink.isNotEmpty) {
          if (mounted) {
            Navigator.of(context).pop(true);
            _showLinkBox(context, result.inviteLink, initial: true);
          }
        } else if (result != null) {
          if (mounted) Navigator.of(context).pop(true);
        } else {
          if (mounted) {
            showTelegramToast(context, 'Failed to create conference call');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to start call: $e');
      }
    }
  }

  Future<void> _shareInviteLink() async {
    if (_creatingLink) return;
    setState(() => _creatingLink = true);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;

    try {
      final result = await engine.createConferenceCall(accountId);
      if (result != null && result.inviteLink.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pop(true);
          _showLinkBox(context, result.inviteLink, initial: true);
        }
      } else {
        if (mounted) {
          showTelegramToast(context, result == null ? 'Failed to create call' : 'No invite link returned');
        }
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, '$e');
      }
    } finally {
      if (mounted) setState(() => _creatingLink = false);
    }
  }

  void _showLinkBox(BuildContext ctx, String link, {bool initial = false}) {
    final engine = ctx.read<EngineService>();
    final appState = ctx.read<AppState>();
    showDialog(
      context: ctx,
      builder: (c) => Provider<EngineService>.value(
        value: engine,
        child: ChangeNotifierProvider.value(
          value: appState,
          child: _ConferenceCallLinkBox(link: link, initial: initial),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = p.boxBg;
    final textColor = p.boxTextFg;
    final subtextColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowBgActive;
    final dividerColor = p.boxDividerBg;
    final hoverBg = p.windowBgOver;

    final hasSelection = _selectedIds.isNotEmpty;
    final buttonLabel = hasSelection ? 'Start Call' : 'Create Call';
    final isReactivate = widget.discardedInviteMsgId != 0;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReactivate)
              _ReactivateHeader(
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                dividerColor: dividerColor,
              )
            else
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, top: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'New Call',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(fontSize: 14, color: subtextColor),
                    prefixIcon: Icon(Icons.search, size: 20, color: subtextColor),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF131C26) : const Color(0xFFF0F0F0),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Expanded(
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accentColor,
                        ),
                      ),
                    )
                  : _buildFullList(
                      isDark: isDark,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      accentColor: accentColor,
                      hoverBg: hoverBg,
                      dividerColor: dividerColor,
                      isReactivate: isReactivate,
                    ),
            ),
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Close',
                      style: TextStyle(fontSize: 14, color: subtextColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _createCall,
                    child: Text(
                      buttonLabel,
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
          ],
        ),
      ),
    );
  }

  Widget _buildFullList({
    required bool isDark,
    required Color textColor,
    required Color subtextColor,
    required Color accentColor,
    required Color hoverBg,
    required Color dividerColor,
    required bool isReactivate,
  }) {
    final prioritized = _prioritizedContacts;
    final main = _mainContacts;
    final showInviteLink = !isReactivate;

    if (main.isEmpty && prioritized.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'No contacts found' : 'No results',
          style: TextStyle(fontSize: 14, color: subtextColor),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: (showInviteLink ? 1 : 0) +
          (prioritized.isNotEmpty ? prioritized.length + 1 : 0) +
          main.length,
      itemBuilder: (context, index) {
        var offset = 0;

        if (showInviteLink) {
          if (index == 0) {
            return _InviteLinkButton(
              accentColor: accentColor,
              hoverBg: hoverBg,
              isLoading: _creatingLink,
              onTap: _shareInviteLink,
            );
          }
          offset = 1;
        }

        if (prioritized.isNotEmpty) {
          final pIndex = index - offset;
          if (pIndex < prioritized.length) {
            final contact = prioritized[pIndex];
            return _buildRow(contact, isDark, textColor, subtextColor, accentColor, hoverBg);
          }
          if (pIndex == prioritized.length) {
            return Divider(height: 1, color: dividerColor);
          }
          offset += prioritized.length + 1;
        }

        final mIndex = index - offset;
        if (mIndex < main.length) {
          return _buildRow(main[mIndex], isDark, textColor, subtextColor, accentColor, hoverBg);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildRow(
    ContactInfo contact,
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    final selected = _selectedIds.contains(contact.userId);
    final isVideo = _selectedVideo[contact.userId] ?? false;
    return _ConfInviteRow(
      contact: contact,
      selected: selected,
      isVideo: isVideo,
      isDark: isDark,
      textColor: textColor,
      subtextColor: subtextColor,
      accentColor: accentColor,
      hoverBg: hoverBg,
      onTap: () => _toggleContact(contact.userId),
      onVideoTap: () => _toggleContact(contact.userId, video: true),
      onAudioTap: () => _toggleContact(contact.userId, video: false),
    );
  }
}

class _InviteLinkButton extends StatefulWidget {
  final Color accentColor;
  final Color hoverBg;
  final bool isLoading;
  final VoidCallback onTap;

  const _InviteLinkButton({
    required this.accentColor,
    required this.hoverBg,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_InviteLinkButton> createState() => _InviteLinkButtonState();
}

class _InviteLinkButtonState extends State<_InviteLinkButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isLoading ? null : widget.onTap,
          child: Container(
            height: 40,
            color: _hovered ? widget.hoverBg : Colors.transparent,
            child: Stack(
              children: [
                Positioned(
                  left: 23,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(Icons.link, size: 24, color: widget.accentColor),
                  ),
                ),
                Positioned(
                  left: 74,
                  top: 0,
                  bottom: 0,
                  right: 8,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.accentColor,
                            ),
                          )
                        : Text(
                            'Invite via Link',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: widget.accentColor,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactivateHeader extends StatelessWidget {
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final Color dividerColor;

  const _ReactivateHeader({
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.dividerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 32),
        Icon(Icons.call, size: 48, color: accentColor),
        const SizedBox(height: 10),
        Text(
          'Call Ended',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Start a new call with the same participants or create a fresh one.',
            style: TextStyle(fontSize: 13, color: subtextColor),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }
}

class _ConferenceCallLinkBox extends StatelessWidget {
  final String link;
  final bool initial;

  const _ConferenceCallLinkBox({
    required this.link,
    this.initial = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = p.boxBg;
    final textColor = p.boxTextFg;
    final subtextColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowBgActive;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call, size: 48, color: accentColor),
              const SizedBox(height: 10),
              Text(
                'Call Link',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Share this link with people you want to join the call.',
                  style: TextStyle(fontSize: 13, color: subtextColor),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131C26) : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  link,
                  style: TextStyle(fontSize: 13, color: accentColor),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Copy link to clipboard
                          final data = ClipboardData(text: link);
                          Clipboard.setData(data);
                          showTelegramToast(context, 'Link copied to clipboard');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy Link'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share Link'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accentColor,
                          side: BorderSide(color: accentColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (initial) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Or', style: TextStyle(fontSize: 13, color: subtextColor)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Text(
                    'Join this call yourself',
                    style: TextStyle(
                      fontSize: 13,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfInviteRow extends StatefulWidget {
  final ContactInfo contact;
  final bool selected;
  final bool isVideo;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final Color hoverBg;
  final VoidCallback onTap;
  final VoidCallback onVideoTap;
  final VoidCallback onAudioTap;

  const _ConfInviteRow({
    required this.contact,
    required this.selected,
    required this.isVideo,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.hoverBg,
    required this.onTap,
    required this.onVideoTap,
    required this.onAudioTap,
  });

  @override
  State<_ConfInviteRow> createState() => _ConfInviteRowState();
}

class _ConfInviteRowState extends State<_ConfInviteRow> {
  bool _hovered = false;

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  String _lastSeenLabel(ContactInfo c) {
    if (c.isOnline) return 'online';
    if (c.lastSeenTs > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(c.lastSeenTs * 1000);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
      if (diff.inHours < 24) return 'last seen ${diff.inHours}h ago';
      return 'last seen ${diff.inDays}d ago';
    }
    return c.lastSeenKind.isNotEmpty ? 'last seen ${c.lastSeenKind}' : '';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contact;
    final numId = int.tryParse(c.userId) ?? c.userId.hashCode.abs();
    final avatarColor = context.palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
    final initials = _getInitials(c.displayName);
    final statusText = _lastSeenLabel(c);
    final statusColor = c.isOnline ? widget.accentColor : widget.subtextColor;
    final avatarCorner = context.watch<AppState>().avatarCorners;
    const avatarSize = 40.0;
    final avatarRadius = avatarSize / 2 * (avatarCorner / 23.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 52,
          color: _hovered ? widget.hoverBg : Colors.transparent,
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Row(
            children: [
              SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: c.avatarB64.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(avatarRadius),
                        child: Image.memory(
                          base64Decode(c.avatarB64),
                          width: avatarSize,
                          height: avatarSize,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackAvatar(
                              avatarColor, initials, avatarSize, avatarRadius),
                        ),
                      )
                    : _fallbackAvatar(avatarColor, initials, avatarSize, avatarRadius),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayName.isEmpty ? c.username : c.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (statusText.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        statusText,
                        style: TextStyle(fontSize: 12, color: statusColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 36,
                height: 52,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: widget.onVideoTap,
                  icon: Icon(
                    Icons.videocam,
                    size: 20,
                    color: widget.selected && widget.isVideo
                        ? widget.accentColor
                        : (widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999)),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                height: 52,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: widget.onAudioTap,
                  icon: Icon(
                    Icons.call,
                    size: 20,
                    color: widget.selected && !widget.isVideo
                        ? widget.accentColor
                        : (widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999)),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: widget.selected
                    ? Icon(Icons.check_circle, size: 22, color: widget.accentColor)
                    : Icon(Icons.radio_button_unchecked, size: 22,
                        color: widget.isDark ? const Color(0xFF3E546A) : const Color(0xFFD0D0D0)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackAvatar(Color color, String initials, double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _CallGroup {
  final List<CallHistoryEntry> entries;
  _CallGroup(this.entries);

  CallHistoryEntry get newest => entries.first;
  int get count => entries.length;
  String get peerId => newest.peerId;
  String get peerName => newest.peerName;
  String get avatarPath => newest.avatarPath;
  bool get isOutgoing => newest.isOutgoing;
  bool get isMissed => newest.isMissed;
  bool get isVideo => newest.isVideo;
  int get timestamp => newest.timestamp;
}

class _CallHistoryRow extends StatefulWidget {
  final _CallGroup group;
  final String accountId;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color menuIconColor;
  final void Function(_CallGroup group) onDeleted;

  const _CallHistoryRow({
    required this.group,
    required this.accountId,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.menuIconColor,
    required this.onDeleted,
  });

  @override
  State<_CallHistoryRow> createState() => _CallHistoryRowState();
}

class _CallHistoryRowState extends State<_CallHistoryRow> {
  bool _hovered = false;

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _formatTimestamp(int epochSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final callDay = DateTime(dt.year, dt.month, dt.day);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final timeFmt = '$h:$m';

    if (callDay == today) {
      return timeFmt;
    } else if (callDay == yesterday) {
      return 'yesterday at $timeFmt';
    } else {
      return '${_months[dt.month - 1]} ${dt.day} at $timeFmt';
    }
  }

  String _formatStatus(_CallGroup group) {
    final ts = _formatTimestamp(group.timestamp);
    if (group.count > 1) return '(${group.count}) $ts';
    return ts;
  }

  void _showContextMenu(BuildContext context, Offset position) async {
    final group = widget.group;
    final isDark = widget.isDark;
    final menuIconColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final attentionColor = isDark ? const Color(0xFFe85050) : const Color(0xFFdd4b39);

    final result = await showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'delete',
          icon: Icon(Icons.delete_outline, size: 20, color: attentionColor),
          label: 'Delete',
          labelColor: attentionColor,
          iconColor: attentionColor,
          isAttention: true,
        ),
        TelegramMenuItem(
          value: 'show_in_chat',
          icon: Icon(Icons.chat_bubble_outline, size: 20, color: menuIconColor),
          label: 'Show in Chat',
        ),
      ],
    );

    if (!mounted || result == null) return;

    switch (result) {
      case 'delete':
        final confirmResult = await showDeleteConfirmBox(
          context,
          mode: group.count > 1 ? DeleteBoxMode.bulkMessages : DeleteBoxMode.singleMessage,
          messageCount: group.count,
          peerName: group.peerName,
        );
        if (!mounted || !confirmResult.confirmed) return;
        final engine = context.read<EngineService>();
        for (final entry in group.entries) {
          try {
            await engine.deleteMessage(widget.accountId, group.peerId, entry.msgId);
          } catch (_) {}
        }
        widget.onDeleted(group);
        break;
      case 'show_in_chat':
        final chatState = context.read<ChatState>();
        chatState.openChatById(group.peerId);
        final newestTimestamp = group.newest.timestamp * 1000;
        Future.delayed(const Duration(milliseconds: 300), () {
          chatState.jumpToMessage(newestTimestamp);
        });
        Navigator.of(context).pop();
        break;
    }
  }

  void _startRedial(BuildContext context) async {
    final permOk = await requestCallPermissions(
      context,
      video: widget.group.isVideo,
    );
    if (!permOk || !context.mounted) return;
    final engine = context.read<EngineService>();
    final group = widget.group;
    await engine.startCall(widget.accountId, group.peerId, video: group.isVideo);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final hoverBg = widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final arrowColor = group.isMissed
        ? (widget.isDark ? const Color(0xFFe85050) : const Color(0xFFdd4b39))
        : (widget.isDark ? const Color(0xFF49ad55) : const Color(0xFF4dc920));

    final numIdG = int.tryParse(group.peerId) ?? group.peerId.hashCode.abs();
    final avatarColor = context.palette.peerUserpicBg(_colorRemap[numIdG.abs() % 7]);
    final initials = _getInitials(group.peerName);
    final avatarCorner = context.watch<AppState>().avatarCorners;
    const avatarSize = 42.0;
    final avatarRadius = avatarSize / 2 * (avatarCorner / 23.0);

    final redialIcon = group.isVideo ? Icons.videocam : Icons.call;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) => _showContextMenu(context, details.globalPosition),
        child: Container(
          height: 56,
          color: _hovered ? hoverBg : Colors.transparent,
          padding: const EdgeInsets.only(left: 16, right: 12),
          child: Row(
            children: [
              SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: group.avatarPath.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(avatarRadius),
                        child: Image.file(
                          File(group.avatarPath),
                          width: avatarSize,
                          height: avatarSize,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackAvatar(
                              avatarColor, initials, avatarSize, avatarRadius),
                        ),
                      )
                    : _fallbackAvatar(avatarColor, initials, avatarSize, avatarRadius),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.peerName.isEmpty ? 'Unknown' : group.peerName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Transform.translate(
                          offset: const Offset(-2, 1),
                          child: Icon(
                            group.isOutgoing
                                ? Icons.call_made
                                : Icons.call_received,
                            size: 16,
                            color: arrowColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _formatStatus(group),
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.subtextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 40,
                height: 56,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _startRedial(context),
                  icon: Icon(
                    redialIcon,
                    size: 20,
                    color: _hovered
                        ? (widget.isDark
                            ? const Color(0xFFACBBC9)
                            : const Color(0xFF6A6A6A))
                        : widget.menuIconColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackAvatar(Color color, String initials, double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// §34.14 Call Settings Screen
// ---------------------------------------------------------------------------

class _CallSettingsScreen extends StatefulWidget {
  const _CallSettingsScreen();

  @override
  State<_CallSettingsScreen> createState() => _CallSettingsScreenState();
}

class _CallSettingsScreenState extends State<_CallSettingsScreen> {
  String _outputDevice = 'Default';
  String _inputDevice = 'Default';
  String _cameraDevice = 'Default';
  bool _useSameDevices = true;
  bool _acceptCalls = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = p.boxBg;
    final textColor = p.boxTextFg;
    final subtextColor = p.boxTitleAdditionalFg;
    final dividerColor = p.boxDividerBg;
    final accentColor = p.windowBgActive;

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
          'Call Settings',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: ListView(
        children: [
          // --- Output section ---
          _CallSettingsSectionHeader(label: 'Output', color: accentColor),
          _CallSettingsDeviceRow(
            icon: Icons.volume_up,
            label: _outputDevice,
            textColor: textColor,
            subtextColor: subtextColor,
            isDark: isDark,
            onTap: () => _showDevicePicker(
              title: 'Output Device',
              current: _outputDevice,
              onSelected: (d) => setState(() => _outputDevice = d),
            ),
          ),
          Divider(height: 1, color: dividerColor, indent: 60),

          // --- Input section ---
          _CallSettingsSectionHeader(label: 'Input', color: accentColor),
          _CallSettingsDeviceRow(
            icon: Icons.mic,
            label: _inputDevice,
            textColor: textColor,
            subtextColor: subtextColor,
            isDark: isDark,
            onTap: () => _showDevicePicker(
              title: 'Input Device',
              current: _inputDevice,
              onSelected: (d) => setState(() => _inputDevice = d),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(60, 8, 22, 12),
            child: _InputLevelMeter(isDark: isDark, accentColor: accentColor),
          ),
          Divider(height: 1, color: dividerColor, indent: 60),

          // --- Call Devices section ---
          _CallSettingsSectionHeader(label: 'Call Devices', color: accentColor),
          _CallSettingsToggleRow(
            label: 'Use same devices for calls',
            value: _useSameDevices,
            textColor: textColor,
            accentColor: accentColor,
            isDark: isDark,
            onChanged: (v) => setState(() => _useSameDevices = v),
          ),
          _CallSettingsInfoLabel(
            text: 'When enabled, calls use the same speaker and microphone '
                'as the rest of the app.',
            color: subtextColor,
          ),
          Divider(height: 1, color: dividerColor, indent: 60),

          // --- Camera section ---
          _CallSettingsSectionHeader(label: 'Camera', color: accentColor),
          _CallSettingsDeviceRow(
            icon: Icons.videocam,
            label: _cameraDevice,
            textColor: textColor,
            subtextColor: subtextColor,
            isDark: isDark,
            onTap: () => _showDevicePicker(
              title: 'Camera',
              current: _cameraDevice,
              onSelected: (d) => setState(() => _cameraDevice = d),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: _CameraPreviewPlaceholder(isDark: isDark),
          ),
          Divider(height: 1, color: dividerColor, indent: 60),

          // --- Other section ---
          _CallSettingsSectionHeader(label: 'Other', color: accentColor),
          _CallSettingsToggleRow(
            label: 'Accept incoming calls on this device',
            value: _acceptCalls,
            textColor: textColor,
            accentColor: accentColor,
            isDark: isDark,
            onChanged: (v) => setState(() => _acceptCalls = v),
          ),
          _CallSettingsInfoLabel(
            text: 'When disabled, incoming calls will not ring on this device.',
            color: subtextColor,
          ),
          const SizedBox(height: 8),
          _CallSettingsActionRow(
            icon: Icons.settings,
            label: 'Open system sound preferences',
            textColor: textColor,
            isDark: isDark,
            onTap: () {},
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showDevicePicker({
    required String title,
    required String current,
    required ValueChanged<String> onSelected,
  }) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final accentColor = p.windowBgActive;
    final bgColor = p.boxBg;
    final devices = ['Default'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final device in devices)
              RadioListTile<String>(
                value: device,
                groupValue: current,
                activeColor: accentColor,
                title: Text(
                  device,
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
                onChanged: (v) {
                  if (v != null) {
                    onSelected(v);
                    Navigator.of(ctx).pop();
                  }
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: accentColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallSettingsSectionHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _CallSettingsSectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _CallSettingsDeviceRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color textColor;
  final Color subtextColor;
  final bool isDark;
  final VoidCallback onTap;

  const _CallSettingsDeviceRow({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.subtextColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_CallSettingsDeviceRow> createState() => _CallSettingsDeviceRowState();
}

class _CallSettingsDeviceRowState extends State<_CallSettingsDeviceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg =
        widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? hoverBg : Colors.transparent,
          padding: SettingsStyle.iconRowPadding,
          child: Row(
            children: [
              Icon(widget.icon, size: 24, color: widget.subtextColor),
              const SizedBox(width: SettingsStyle.iconGap),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    color: widget.textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: widget.subtextColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallSettingsToggleRow extends StatefulWidget {
  final String label;
  final bool value;
  final Color textColor;
  final Color accentColor;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _CallSettingsToggleRow({
    required this.label,
    required this.value,
    required this.textColor,
    required this.accentColor,
    required this.isDark,
    required this.onChanged,
  });

  @override
  State<_CallSettingsToggleRow> createState() => _CallSettingsToggleRowState();
}

class _CallSettingsToggleRowState extends State<_CallSettingsToggleRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg =
        widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        child: Container(
          color: _hovered ? hoverBg : Colors.transparent,
          padding: SettingsStyle.iconRowPadding,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    color: widget.textColor,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                height: 20,
                child: Switch(
                  value: widget.value,
                  onChanged: widget.onChanged,
                  activeColor: widget.accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallSettingsInfoLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _CallSettingsInfoLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: color),
      ),
    );
  }
}

class _CallSettingsActionRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color textColor;
  final bool isDark;
  final VoidCallback onTap;

  const _CallSettingsActionRow({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_CallSettingsActionRow> createState() => _CallSettingsActionRowState();
}

class _CallSettingsActionRowState extends State<_CallSettingsActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg =
        widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final iconColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? hoverBg : Colors.transparent,
          padding: SettingsStyle.iconRowPadding,
          child: Row(
            children: [
              Icon(widget.icon, size: 24, color: iconColor),
              const SizedBox(width: SettingsStyle.iconGap),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    color: widget.textColor,
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

// §34.14 LevelMeter: 18px height, 3px line width, 5px spacing, 44 lines.
class _InputLevelMeter extends StatefulWidget {
  final bool isDark;
  final Color accentColor;

  const _InputLevelMeter({required this.isDark, required this.accentColor});

  @override
  State<_InputLevelMeter> createState() => _InputLevelMeterState();
}

class _InputLevelMeterState extends State<_InputLevelMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(double.infinity, 18),
          painter: _LevelMeterPainter(
            level: _controller.value * 0.35,
            activeColor: widget.accentColor,
            inactiveColor: widget.isDark
                ? const Color(0xFF3B4654)
                : const Color(0xFFD8D8D8),
          ),
        );
      },
    );
  }
}

class _LevelMeterPainter extends CustomPainter {
  final double level;
  final Color activeColor;
  final Color inactiveColor;

  static const int _lineCount = 44;
  static const double _lineWidth = 3;
  static const double _spacing = 5;

  _LevelMeterPainter({
    required this.level,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = _lineWidth
      ..strokeCap = StrokeCap.round;
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = _lineWidth
      ..strokeCap = StrokeCap.round;

    final totalWidth = _lineCount * _lineWidth + (_lineCount - 1) * _spacing;
    final startX = (size.width - totalWidth) / 2;
    final clampedStart = startX < 0 ? 0.0 : startX;
    final activeCount = (level * _lineCount).round();

    for (int i = 0; i < _lineCount; i++) {
      final x = clampedStart + i * (_lineWidth + _spacing) + _lineWidth / 2;
      if (x > size.width) break;
      final paint = i < activeCount ? activePaint : inactivePaint;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelMeterPainter oldDelegate) =>
      level != oldDelegate.level;
}

class _CameraPreviewPlaceholder extends StatelessWidget {
  final bool isDark;

  const _CameraPreviewPlaceholder({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0);
    final iconColor =
        isDark ? const Color(0xFF3B4654) : const Color(0xFFBBBBBB);
    final textColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return AspectRatio(
      aspectRatio: 640 / 480,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, size: 48, color: iconColor),
            const SizedBox(height: 8),
            Text(
              'Camera preview',
              style: TextStyle(fontSize: 13, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
