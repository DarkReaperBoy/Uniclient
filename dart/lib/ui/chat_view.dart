import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/chat_state.dart';
import 'message_bubble.dart';

/// Chat column: top bar + message list + compose area.
/// Spec §4 (top bar 54px), §5 (messages), §7 (compose).
class ChatView extends StatefulWidget {
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;

  const ChatView({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.onToggleInfo,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _composeController = TextEditingController();
  final _scrollController = ScrollController();
  String? _replyToId;
  bool _showScrollToBottom = false;
  String? _lastChatId;
  final Set<String> _selectedMsgIds = {};
  bool get _selectionMode => _selectedMsgIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _composeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mark as read when opening a new chat.
    final chatState = context.read<ChatState>();
    final chatId = chatState.activeChat?.chatId;
    if (chatId != null && chatId != _lastChatId) {
      _lastChatId = chatId;
      // Delay slightly to ensure messages are loaded.
      Future.microtask(() => chatState.markRead());
    }
  }

  void _onScroll() {
    // Load more messages when near the top (oldest messages).
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<ChatState>().loadMoreMessages();
    }
    // Show/hide scroll-to-bottom FAB.
    final showFab = _scrollController.offset > 200;
    if (showFab != _showScrollToBottom) {
      setState(() => _showScrollToBottom = showFab);
    }
  }

  void _scrollToBottom() {
    final chatState = context.read<ChatState>();
    if (chatState.isJumped) {
      // If we jumped to a pinned message, reload latest messages first.
      chatState.returnToLatest();
    }
    _scrollController.animateTo(
      0, // reverse: true means 0 is the bottom
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCirc,
    );
  }

  void _showMessageContextMenu(String msgId, Offset position) {
    final chatState = context.read<ChatState>();
    final msg = chatState.messages.where((m) => m.msgId == msgId).firstOrNull;
    if (msg == null) return;

    final theme = Theme.of(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: theme.colorScheme.surface,
      items: [
        const PopupMenuItem(value: 'reply', child: ListTile(dense: true, leading: Icon(Icons.reply, size: 20), title: Text('Reply'))),
        if (msg.contentText.isNotEmpty)
          const PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: Icon(Icons.copy, size: 20), title: Text('Copy Text'))),
        const PopupMenuItem(value: 'forward', child: ListTile(dense: true, leading: Icon(Icons.forward, size: 20), title: Text('Forward'))),
        const PopupMenuItem(value: 'select', child: ListTile(dense: true, leading: Icon(Icons.check_circle_outline, size: 20), title: Text('Select'))),
        if (msg.isOutgoing)
          const PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit, size: 20), title: Text('Edit'))),
        PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error), title: Text('Delete', style: TextStyle(color: theme.colorScheme.error)))),
      ],
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case 'reply':
          setState(() => _replyToId = msgId);
        case 'copy':
          Clipboard.setData(ClipboardData(text: msg.contentText));
        case 'forward':
          _forwardSingle(context, chatState, msgId);
        case 'select':
          setState(() => _selectedMsgIds.add(msgId));
        case 'edit':
          _composeController.text = msg.contentText;
          // TODO: wire up edit mode
        case 'delete':
          chatState.deleteMessage(msgId);
      }
    });
  }

  void _showSenderProfile(BuildContext context, ChatState chatState, String senderId) {
    // Find sender info from messages.
    final msg = chatState.messages.where((m) => m.senderId == senderId).firstOrNull;
    final avatarB64 = chatState.senderAvatar(senderId);
    final senderName = msg?.senderName ?? senderId;

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        const avatarRadius = 36.0;
        Widget avatar;
        if (avatarB64 != null && avatarB64.isNotEmpty) {
          try {
            final bytes = base64Decode(avatarB64);
            avatar = ClipOval(
              child: Image.memory(bytes, width: avatarRadius * 2, height: avatarRadius * 2, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _senderFallbackAvatar(senderId, senderName, avatarRadius)),
            );
          } catch (_) {
            avatar = _senderFallbackAvatar(senderId, senderName, avatarRadius);
          }
        } else {
          avatar = _senderFallbackAvatar(senderId, senderName, avatarRadius);
        }

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profile header with avatar + name.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    children: [
                      avatar,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              senderName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: $senderId',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Actions.
                InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final dmChat = chatState.chats.where((c) =>
                      c.chatId == senderId && c.accountId == chatState.activeChat?.accountId).firstOrNull;
                    if (dmChat != null) chatState.openChat(dmChat);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.message_outlined, size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 14),
                        Text('Send Message', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _senderFallbackAvatar(String senderId, String name, double radius) {
    const colors = [
      Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
      Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb),
    ];
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors[senderId.hashCode.abs() % 7],
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontSize: radius * 0.6, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _deleteSelected(ChatState chatState) {
    for (final id in _selectedMsgIds) {
      chatState.deleteMessage(id);
    }
    setState(() => _selectedMsgIds.clear());
  }

  void _forwardSingle(BuildContext context, ChatState chatState, String msgId) {
    showDialog(
      context: context,
      builder: (ctx) => _ForwardDialog(
        chats: chatState.chats,
        onSelect: (toChatId) async {
          Navigator.of(ctx).pop();
          await chatState.forwardMessages([msgId], toChatId);
        },
      ),
    );
  }

  void _forwardSelected(BuildContext context, ChatState chatState) {
    final msgIds = _selectedMsgIds.toList();
    showDialog(
      context: context,
      builder: (ctx) => _ForwardDialog(
        chats: chatState.chats,
        onSelect: (toChatId) async {
          Navigator.of(ctx).pop();
          await chatState.forwardMessages(msgIds, toChatId);
          setState(() => _selectedMsgIds.clear());
        },
      ),
    );
  }

  void _copySelected(ChatState chatState) {
    final msgs = chatState.messages
        .where((m) => _selectedMsgIds.contains(m.msgId))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final text = msgs.map((m) => m.contentText).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _selectedMsgIds.clear());
  }

  void _sendMessage() {
    final text = _composeController.text.trim();
    if (text.isEmpty) return;
    final chatState = context.read<ChatState>();
    chatState.sendMessage(text, replyToId: _replyToId ?? '');
    _composeController.clear();
    setState(() => _replyToId = null);
    // Scroll to bottom after sending.
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = context.watch<ChatState>();
    final chat = chatState.activeChat;

    if (chat == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // Top bar (54px per spec) or selection action bar.
          if (_selectionMode)
            _SelectionBar(
              count: _selectedMsgIds.length,
              onCancel: () => setState(() => _selectedMsgIds.clear()),
              onDelete: () => _deleteSelected(chatState),
              onCopy: () => _copySelected(chatState),
              onForward: () => _forwardSelected(context, chatState),
            )
          else
            _ChatTopBar(
              chat: chat,
              typingUser: chatState.typingUserFor(chat.chatId),
              isOnline: chatState.isChatOnline(chat),
              lastSeen: chatState.chatLastSeen(chat),
              showBackButton: widget.showBackButton,
              onBack: widget.onBack,
              onToggleInfo: widget.onToggleInfo,
            ),
          // Pinned message bar (if any pinned messages).
          if (chatState.pinnedMessages.isNotEmpty)
            _PinnedBar(
              pinned: chatState.pinnedMessages.first,
              onTap: () {
                final pinned = chatState.pinnedMessages.first;
                // Load messages with pinned message as the newest (index 0).
                chatState.jumpToMessage(pinned.timestamp);
                // Scroll to bottom (offset 0 in reversed list = newest = pinned message).
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(0);
                  }
                });
              },
            ),
          // Message list with scroll-to-bottom FAB.
          Expanded(
            child: Stack(
              children: [
                _MessageList(
                  messages: chatState.messages,
                  loading: chatState.loadingMessages,
                  isGroupChat: chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic,
                  senderAvatars: chatState,
                  scrollController: _scrollController,
                  onReply: (msgId) => setState(() => _replyToId = msgId),
                  selectedIds: _selectedMsgIds,
                  onToggleSelect: (msgId) => setState(() {
                    if (_selectedMsgIds.contains(msgId)) {
                      _selectedMsgIds.remove(msgId);
                    } else {
                      _selectedMsgIds.add(msgId);
                    }
                  }),
                  onLongPress: (msgId) => setState(() {
                    _selectedMsgIds.add(msgId);
                  }),
                  onContextMenu: _showMessageContextMenu,
                  onSenderTap: (senderId) => _showSenderProfile(context, chatState, senderId),
                ),
                // Scroll-to-bottom FAB (spec §5: JumpDownButton).
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: _ScrollToBottomFab(
                      unreadCount: chatState.openedUnreadCount,
                      onTap: _scrollToBottom,
                    ),
                  ),
              ],
            ),
          ),
          // Reply bar.
          if (_replyToId != null)
            _ReplyBar(
              replyId: _replyToId!,
              messages: chatState.messages,
              onCancel: () => setState(() => _replyToId = null),
            ),
          // Compose area.
          _ComposeArea(
            controller: _composeController,
            onSend: _sendMessage,
            onDraftChanged: (text) => chatState.saveDraft(text),
          ),
        ],
      ),
    );
  }
}

/// Chat top bar. Spec §4: 54px height.
class _ChatTopBar extends StatelessWidget {
  final ChatInfo chat;
  final String? typingUser;
  final bool isOnline;
  final ({String kind, int lastSeenMs}) lastSeen;
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;

  const _ChatTopBar({
    required this.chat,
    this.typingUser,
    this.isOnline = false,
    this.lastSeen = (kind: '', lastSeenMs: 0),
    required this.showBackButton,
    this.onBack,
    this.onToggleInfo,
  });

  /// Format a last-seen descriptor per Telegram Desktop spec §1.4 / §7588.
  static String _formatLastSeen(({String kind, int lastSeenMs}) ls) {
    switch (ls.kind) {
      case 'recently':
        return 'last seen recently';
      case 'within_week':
        return 'last seen within a week';
      case 'within_month':
        return 'last seen within a month';
      case 'long_ago':
        return 'last seen a long time ago';
      case 'exact':
        if (ls.lastSeenMs <= 0) return '';
        final then = DateTime.fromMillisecondsSinceEpoch(ls.lastSeenMs);
        final now = DateTime.now();
        final diff = now.difference(then);
        if (diff.inSeconds < 60) return 'last seen just now';
        if (diff.inMinutes < 60) {
          final m = diff.inMinutes;
          return 'last seen $m ${m == 1 ? "minute" : "minutes"} ago';
        }
        final sameDay = then.year == now.year &&
            then.month == now.month &&
            then.day == now.day;
        final y = now.subtract(const Duration(days: 1));
        final yesterday = then.year == y.year &&
            then.month == y.month &&
            then.day == y.day;
        String twoDigits(int n) => n.toString().padLeft(2, '0');
        final time = '${twoDigits(then.hour)}:${twoDigits(then.minute)}';
        if (sameDay) return 'last seen today at $time';
        if (yesterday) return 'last seen yesterday at $time';
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        return 'last seen ${months[then.month - 1]} ${then.day} at $time';
      default:
        return '';
    }
  }

  static Widget _chatAvatar(ChatInfo chat, ThemeData theme, double radius) {
    if (chat.avatarPath.isNotEmpty) {
      final file = File(chat.avatarPath);
      return ClipOval(
        child: Image.file(
          file,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(chat, theme, radius),
        ),
      );
    }
    return _fallbackAvatar(chat, theme, radius);
  }

  static Widget _fallbackAvatar(ChatInfo chat, ThemeData theme, double radius) {
    const colors = [
      Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
      Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb),
    ];
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors[chat.chatId.hashCode.abs() % 7],
      child: Text(
        chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontSize: radius * 0.7, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Subtitle: typing, online status, member count, or last seen.
    String subtitle;
    Color? subtitleColor;
    if (typingUser != null) {
      subtitle = '$typingUser is typing...';
      subtitleColor = theme.colorScheme.primary;
    } else if (chat.type == ChatType.dm && isOnline) {
      subtitle = 'online';
      subtitleColor = const Color(0xFF3BA55C); // online green
    } else if (chat.type == ChatType.dm) {
      subtitle = _formatLastSeen(lastSeen);
    } else if (chat.memberCount > 0) {
      subtitle = '${chat.memberCount} members';
    } else {
      subtitle = '';
    }

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (showBackButton) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: onBack,
            ),
          ],
          // Avatar — use real photo when available.
          _chatAvatar(chat, theme, 18),
          const SizedBox(width: 10),
          // Title + subtitle.
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat.title.isNotEmpty ? chat.title : chat.chatId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtitleColor,
                    ),
                  ),
              ],
            ),
          ),
          // Right-side buttons.
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: () {}, // TODO: in-chat search
          ),
          if (onToggleInfo != null)
            IconButton(
              icon: const Icon(Icons.info_outline, size: 20),
              onPressed: onToggleInfo,
            ),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: () {}, // TODO: chat menu
          ),
        ],
      ),
    );
  }
}

/// Scrollable message list. Newest at bottom, loads more at top.
class _MessageList extends StatelessWidget {
  final List<CachedMessage> messages;
  final bool loading;
  final bool isGroupChat;
  final ChatState? senderAvatars; // for looking up sender avatar b64 by ID
  final ScrollController scrollController;
  final ValueChanged<String> onReply;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<String> onLongPress;
  final void Function(String msgId, Offset position) onContextMenu;
  final ValueChanged<String>? onSenderTap;

  const _MessageList({
    required this.messages,
    required this.loading,
    this.isGroupChat = false,
    this.senderAvatars,
    required this.scrollController,
    required this.onReply,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onLongPress,
    required this.onContextMenu,
    this.onSenderTap,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !loading) {
      return Center(
        child: Text(
          'No messages yet',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      reverse: true, // Newest at bottom.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length + (loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (loading && index == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final msg = messages[index];
        // Check if we should show a date separator.
        final showDate = index == messages.length - 1 ||
            _differentDay(msg.timestamp, messages[index + 1].timestamp);

        // Consecutive message grouping (spec §5):
        // Same sender within 3 minutes → group together.
        final prevMsg = index > 0 ? messages[index - 1] : null;
        final nextMsg = index < messages.length - 1 ? messages[index + 1] : null;
        final isFirstInGroup = nextMsg == null ||
            nextMsg.senderId != msg.senderId ||
            showDate ||
            (msg.timestamp - nextMsg.timestamp).abs() > 180000;
        final isLastInGroup = prevMsg == null ||
            prevMsg.senderId != msg.senderId ||
            _differentDay(msg.timestamp, prevMsg.timestamp) ||
            (prevMsg.timestamp - msg.timestamp).abs() > 180000;

        final isSelected = selectedIds.contains(msg.msgId);
        final inSelectionMode = selectedIds.isNotEmpty;

        return Column(
          children: [
            if (showDate) _DateSeparator(timestamp: msg.timestamp),
            GestureDetector(
              onLongPress: () => onLongPress(msg.msgId),
              onTap: inSelectionMode ? () => onToggleSelect(msg.msgId) : null,
              child: Container(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                    : null,
                child: Row(
                  children: [
                    if (inSelectionMode) ...[
                      const SizedBox(width: 8),
                      Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        size: 22,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: IgnorePointer(
                        ignoring: inSelectionMode,
                        child: MessageBubble(
                          message: msg,
                          isFirstInGroup: isFirstInGroup,
                          isLastInGroup: isLastInGroup,
                          isGroupChat: isGroupChat,
                          senderAvatarB64: senderAvatars?.senderAvatar(msg.senderId),
                          onReply: () => onReply(msg.msgId),
                          onContextMenu: (pos) => onContextMenu(msg.msgId, pos),
                          onSenderTap: onSenderTap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _differentDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year != d2.year || d1.month != d2.month || d1.day != d2.day;
  }
}

/// Centered date separator pill.
class _DateSeparator extends StatelessWidget {
  final int timestamp;

  const _DateSeparator({required this.timestamp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);

    String text;
    if (diff.inDays == 0 && dt.day == now.day) {
      text = 'Today';
    } else if (diff.inDays == 1 || (diff.inDays == 0 && dt.day != now.day)) {
      text = 'Yesterday';
    } else {
      text = '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
        ),
      ),
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
}

/// Reply preview bar above compose.
class _ReplyBar extends StatelessWidget {
  final String replyId;
  final List<CachedMessage> messages;
  final VoidCallback onCancel;

  const _ReplyBar({
    required this.replyId,
    required this.messages,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = messages.where((m) => m.msgId == replyId).firstOrNull;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(width: 2, height: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg?.senderName ?? 'Reply',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  msg?.contentText ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// Selection action bar replacing the top bar during multi-select mode.
class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onForward;

  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
    required this.onCopy,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onCancel,
          ),
          const SizedBox(width: 8),
          Text(
            '$count selected',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.forward),
            tooltip: 'Forward',
            onPressed: onForward,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
            onPressed: onCopy,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Pinned message bar below the top bar.
/// Shows the most recent pinned message with a pin icon.
class _PinnedBar extends StatelessWidget {
  final CachedMessage pinned;
  final VoidCallback? onTap;

  const _PinnedBar({required this.pinned, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.push_pin, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Container(width: 2, height: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pinned Message',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  pinned.contentText.isNotEmpty
                      ? pinned.contentText
                      : (pinned.senderName.isNotEmpty
                          ? '${pinned.senderName}: [media]'
                          : '[media]'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
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

/// Scroll-to-bottom FAB (spec §5: JumpDownButton).
class _ScrollToBottomFab extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _ScrollToBottomFab({required this.unreadCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unreadCount > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unreadCount > 99 ? '99+' : unreadCount.toString(),
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        FloatingActionButton.small(
          onPressed: onTap,
          backgroundColor: theme.colorScheme.surface,
          elevation: 4,
          child: Icon(Icons.keyboard_arrow_down, color: theme.textTheme.bodyMedium?.color),
        ),
      ],
    );
  }
}

/// Compose area at bottom. Spec §7.
/// Enter sends, Shift+Enter for newline (matching Telegram Desktop).
class _ComposeArea extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onDraftChanged;

  const _ComposeArea({
    required this.controller,
    required this.onSend,
    required this.onDraftChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attachment button.
          IconButton(
            icon: const Icon(Icons.attach_file, size: 22),
            onPressed: () {}, // TODO: attachment menu
          ),
          // Text input with Enter-to-send.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    // Prevent the newline from being inserted.
                    onSend();
                  }
                },
                child: TextField(
                  controller: controller,
                  onChanged: onDraftChanged,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Write a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF1e2430)
                        : const Color(0xFFF0F0F0),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
          ),
          // Emoji button.
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined, size: 22),
            onPressed: () {}, // TODO: emoji panel
          ),
          // Send button.
          IconButton(
            icon: Icon(Icons.send, size: 22, color: theme.colorScheme.primary),
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}

/// Forward dialog — shows a searchable chat list to pick a destination.
class _ForwardDialog extends StatefulWidget {
  final List<ChatInfo> chats;
  final ValueChanged<String> onSelect;

  const _ForwardDialog({required this.chats, required this.onSelect});

  @override
  State<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<_ForwardDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _query.isEmpty
        ? widget.chats
        : widget.chats
            .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Forward to...',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final chat = filtered[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: _avatarColor(chat.chatId),
                      child: Text(
                        chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => widget.onSelect(chat.chatId),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Color _avatarColor(String id) {
    const colors = [
      Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
      Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb),
    ];
    return colors[id.hashCode.abs() % 7];
  }
}
