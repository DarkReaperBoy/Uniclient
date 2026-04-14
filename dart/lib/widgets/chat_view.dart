import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/chat_state.dart';
import '../models/engine_models.dart';
import '../theme/theme.dart';

/// Main chat area — header + messages + input.
class ChatView extends StatelessWidget {
  const ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? AppColors.darkBase : AppColors.lightBase,
      child: Column(
        children: [
          _ChatHeader(chat: chat),
          Divider(height: 1, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          Expanded(child: _MessageList(chat: chat)),
          if (chat.type != ChatType.channel)
            _MessageInput(chat: chat)
          else
            _ChannelNotice(isDark: isDark),
        ],
      ),
    );
  }
}

/// Chat header with avatar, name, status, and action buttons.
class _ChatHeader extends StatelessWidget {
  final ChatInfo chat;
  const _ChatHeader({required this.chat});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = context.watch<ChatState>();
    final typing = chatState.typingUserFor(chat.chatId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Chat info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 2),
                if (typing != null)
                  Text(
                    '$typing is typing...',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Text(
                    _statusText(chat),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
              ],
            ),
          ),

          // Action buttons
          if (chat.type == ChatType.dm || chat.type == ChatType.group) ...[
            IconButton(
              icon: const Icon(Icons.call, size: 20),
              onPressed: () {},
              tooltip: 'Voice call',
              splashRadius: 18,
            ),
            IconButton(
              icon: const Icon(Icons.videocam, size: 20),
              onPressed: () {},
              tooltip: 'Video call',
              splashRadius: 18,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: () {},
            tooltip: 'Search',
            splashRadius: 18,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: () {},
            tooltip: 'More',
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  String _statusText(ChatInfo chat) => switch (chat.type) {
    ChatType.dm => 'Online',
    ChatType.group || ChatType.topic => '${chat.memberCount} members',
    ChatType.channel => '${chat.memberCount} subscribers',
    _ => '',
  };
}

/// Scrollable message list with date separators.
class _MessageList extends StatefulWidget {
  final ChatInfo chat;
  const _MessageList({required this.chat});

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<ChatState>().loadMoreMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final messages = chatState.messages;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (messages.isEmpty && !chatState.loadingMessages) {
      return Center(
        child: Text(
          'No messages yet',
          style: TextStyle(color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length + (chatState.loadingMessages ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final msg = messages[index];
        final prevMsg = index + 1 < messages.length ? messages[index + 1] : null;
        final showDate = prevMsg == null || !_sameDay(msg.dateTime, prevMsg.dateTime);
        final showSender = prevMsg == null ||
            prevMsg.senderId != msg.senderId ||
            msg.timestamp - prevMsg.timestamp > 300000; // 5 min gap

        return Column(
          children: [
            if (showDate) _DateSeparator(date: msg.dateTime),
            _MessageBubble(
              message: msg,
              showSender: showSender && widget.chat.type != ChatType.channel,
              isChannel: widget.chat.type == ChatType.channel,
            ),
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Date separator pill.
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    String text;

    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      text = 'TODAY';
    } else if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
      text = 'YESTERDAY';
    } else {
      text = '${_months[date.month - 1]} ${date.day}, ${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
        ),
      ),
    );
  }

  static const _months = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
}

/// Message bubble — sent (right) or received (left).
class _MessageBubble extends StatelessWidget {
  final CachedMessage message;
  final bool showSender;
  final bool isChannel;

  const _MessageBubble({
    required this.message,
    required this.showSender,
    required this.isChannel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // For now, messages with empty senderId are treated as "sent by me".
    final isSent = message.senderId.isEmpty;
    final time = _formatTime(message.dateTime);

    return Padding(
      padding: EdgeInsets.only(
        top: showSender ? 8 : 2,
        left: isSent ? 60 : 0,
        right: isSent ? 0 : 60,
      ),
      child: Row(
        mainAxisAlignment: isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar for received messages
          if (!isSent && !isChannel && showSender)
            _SenderAvatar(name: message.senderName)
          else if (!isSent && !isChannel)
            const SizedBox(width: AppSizes.avatarSizeSmall + 8),

          // Bubble
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: isSent
                    ? (isDark ? AppColors.bubbleSent : AppColors.bubbleSentLight)
                    : (isDark ? AppColors.bubbleReceived : AppColors.bubbleReceivedLight),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppSizes.bubbleRadius),
                  topRight: const Radius.circular(AppSizes.bubbleRadius),
                  bottomLeft: Radius.circular(isSent ? AppSizes.bubbleRadius : AppSizes.bubbleTailRadius),
                  bottomRight: Radius.circular(isSent ? AppSizes.bubbleTailRadius : AppSizes.bubbleRadius),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name
                  if (!isSent && !isChannel && showSender)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _senderColor(message.senderId),
                        ),
                      ),
                    ),

                  // Reply preview
                  if (message.replyToId.isNotEmpty && message.replyPreview.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      decoration: BoxDecoration(
                        border: const Border(
                          left: BorderSide(color: AppColors.accent, width: 2),
                        ),
                        color: isDark
                            ? Colors.white.withAlpha(10)
                            : Colors.black.withAlpha(10),
                      ),
                      child: Text(
                        message.replyPreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    ),

                  // Message text + time
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 8,
                    children: [
                      Text(
                        message.contentText,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? AppColors.darkText : AppColors.lightText,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.isEdited)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                'edited',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                                ),
                              ),
                            ),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                            ),
                          ),
                          if (isSent) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.isFailed ? Icons.error_outline
                                  : message.isSending ? Icons.access_time
                                  : message.status == MsgStatus.read ? Icons.done_all
                                  : Icons.done,
                              size: 14,
                              color: message.isFailed ? AppColors.danger
                                  : message.status == MsgStatus.read ? AppColors.accent
                                  : (isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Color _senderColor(String id) {
    final hue = (id.hashCode % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.7, 0.6).toColor();
  }
}

class _SenderAvatar extends StatelessWidget {
  final String name;
  const _SenderAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hue = (name.hashCode % 360).abs().toDouble();
    final color = HSLColor.fromAHSL(1, hue, 0.5, 0.4).toColor();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        width: AppSizes.avatarSizeSmall,
        height: AppSizes.avatarSizeSmall,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(
          child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Message input area.
class _MessageInput extends StatefulWidget {
  final ChatInfo chat;
  const _MessageInput({required this.chat});

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<ChatState>().sendMessage(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 22),
            onPressed: () {},
            tooltip: 'Attach',
            splashRadius: 18,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Message ${widget.chat.title}',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                      onPressed: () {},
                      splashRadius: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _send,
              splashRadius: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only notice for broadcast channels.
class _ChannelNotice extends StatelessWidget {
  final bool isDark;
  const _ChannelNotice({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: Center(
        child: Text(
          'Only admins can post in this channel',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),
      ),
    );
  }
}
