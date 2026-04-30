import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  List<_ActiveGroupCallEntry> _activeGroupCalls = [];
  StreamSubscription<GroupCallStateEvent>? _groupCallSub;

  List<CallHistoryEntry> _callHistory = [];
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
        _loadingMore = false;
        _hasMore = entries.length >= _kNextPage;
      });
    }
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
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text(
                'Clear Call History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete all call history?',
                    style: TextStyle(fontSize: 14, color: textColor),
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
                            style: TextStyle(fontSize: 14, color: textColor),
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
                    style: TextStyle(
                      color: isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await engine.clearCallHistory(accountId, revoke: revoke);
                      if (mounted) {
                        setState(() => _callHistory.clear());
                      }
                    } catch (_) {}
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: isDark ? const Color(0xFFe85050) : const Color(0xFFdd4b39),
                    ),
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

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final menuIconColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final attentionColor = isDark ? const Color(0xFFe85050) : const Color(0xFFdd4b39);

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
            color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF),
            onSelected: (value) {
              switch (value) {
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
      itemCount: _callHistory.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _callHistory.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )),
          );
        }
        return _CallHistoryRow(
          entry: _callHistory[index],
          isDark: isDark,
          textColor: textColor,
          subtextColor: subtextColor,
          menuIconColor: menuIconColor,
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

  static const _avatarColors = [
    Color(0xFFE17076),
    Color(0xFF7BC862),
    Color(0xFFE5CA77),
    Color(0xFF65AADD),
    Color(0xFFA695E7),
    Color(0xFFEE7AAE),
    Color(0xFF6EC9CB),
  ];

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

    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final avatarColor = _avatarColors[colorIndex];
    final initials = _getInitials(chat.title);
    final avatarCorner = context.watch<AppState>().avatarCornerRadius;
    const avatarSize = 42.0;
    final avatarRadius = avatarSize / 2 * (avatarCorner / 50.0);

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

  const _CreateCallButton({
    required this.accentColor,
    required this.textColor,
    required this.subtextColor,
    required this.dividerColor,
    required this.isDark,
  });

  @override
  State<_CreateCallButton> createState() => _CreateCallButtonState();
}

class _CreateCallButtonState extends State<_CreateCallButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg = widget.isDark
        ? const Color(0xFF202B36)
        : const Color(0xFFF1F1F1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () {},
            child: Container(
              color: _hovered ? hoverBg : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'You can create a group call for up to 200 participants.',
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

class _CallHistoryRow extends StatefulWidget {
  final CallHistoryEntry entry;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color menuIconColor;

  const _CallHistoryRow({
    required this.entry,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.menuIconColor,
  });

  @override
  State<_CallHistoryRow> createState() => _CallHistoryRowState();
}

class _CallHistoryRowState extends State<_CallHistoryRow> {
  bool _hovered = false;

  static const _avatarColors = [
    Color(0xFFE17076),
    Color(0xFF7BC862),
    Color(0xFFE5CA77),
    Color(0xFF65AADD),
    Color(0xFFA695E7),
    Color(0xFFEE7AAE),
    Color(0xFF6EC9CB),
  ];

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

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final hoverBg = widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final arrowColor = entry.isMissed
        ? (widget.isDark ? const Color(0xFFe85050) : const Color(0xFFdd4b39))
        : (widget.isDark ? const Color(0xFF49ad55) : const Color(0xFF4dc920));

    final colorIndex = entry.peerId.hashCode.abs() % 7;
    final avatarColor = _avatarColors[colorIndex];
    final initials = _getInitials(entry.peerName);
    final avatarCorner = context.watch<AppState>().avatarCornerRadius;
    const avatarSize = 42.0;
    final avatarRadius = avatarSize / 2 * (avatarCorner / 50.0);

    final redialIcon = entry.isVideo ? Icons.videocam : Icons.call;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          height: 56,
          color: _hovered ? hoverBg : Colors.transparent,
          padding: const EdgeInsets.only(left: 16, right: 0),
          child: Row(
            children: [
              SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: entry.avatarPath.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(avatarRadius),
                        child: Image.file(
                          File(entry.avatarPath),
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
                      entry.peerName.isEmpty ? 'Unknown' : entry.peerName,
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
                            entry.isOutgoing
                                ? Icons.call_made
                                : Icons.call_received,
                            size: 16,
                            color: arrowColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _formatTimestamp(entry.timestamp),
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
                  onPressed: () {},
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
