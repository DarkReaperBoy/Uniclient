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

  void _onScroll() {
    // Load more messages when near the top (oldest messages).
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<ChatState>().loadMoreMessages();
    }
  }

  void _sendMessage() {
    final text = _composeController.text.trim();
    if (text.isEmpty) return;
    final chatState = context.read<ChatState>();
    chatState.sendMessage(text, replyToId: _replyToId ?? '');
    _composeController.clear();
    setState(() => _replyToId = null);
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
          // Top bar (54px per spec).
          _ChatTopBar(
            chat: chat,
            typingUser: chatState.typingUserFor(chat.chatId),
            showBackButton: widget.showBackButton,
            onBack: widget.onBack,
            onToggleInfo: widget.onToggleInfo,
          ),
          // Message list.
          Expanded(
            child: _MessageList(
              messages: chatState.messages,
              loading: chatState.loadingMessages,
              scrollController: _scrollController,
              onReply: (msgId) => setState(() => _replyToId = msgId),
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
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;

  const _ChatTopBar({
    required this.chat,
    this.typingUser,
    required this.showBackButton,
    this.onBack,
    this.onToggleInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Subtitle: typing, member count, or last seen.
    String subtitle;
    Color? subtitleColor;
    if (typingUser != null) {
      subtitle = '$typingUser is typing...';
      subtitleColor = theme.colorScheme.primary;
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
          // Avatar.
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.3),
            child: Text(
              chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
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
  final ScrollController scrollController;
  final ValueChanged<String> onReply;

  const _MessageList({
    required this.messages,
    required this.loading,
    required this.scrollController,
    required this.onReply,
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

        return Column(
          children: [
            if (showDate) _DateSeparator(timestamp: msg.timestamp),
            MessageBubble(
              message: msg,
              isFirstInGroup: isFirstInGroup,
              isLastInGroup: isLastInGroup,
              onReply: () => onReply(msg.msgId),
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
