import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/chat_state.dart';
import '../models/engine_models.dart';
import '../theme/theme.dart';
import 'emoji_panel.dart';
import 'forward_dialog.dart';

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
          if (chat.type == ChatType.topic) _TopicChannelTabBar(chat: chat),
          Expanded(
            child: chat.type != ChatType.channel
                ? _ChatViewBody(chat: chat)
                : Column(
                    children: [
                      Expanded(child: _MessageListWithFAB(chat: chat)),
                      _ChannelNotice(isDark: isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Wraps message list + input, holds reply/edit state for coordination.
class _ChatViewBody extends StatefulWidget {
  final ChatInfo chat;
  const _ChatViewBody({required this.chat});

  @override
  State<_ChatViewBody> createState() => _ChatViewBodyState();
}

class _ChatViewBodyState extends State<_ChatViewBody> {
  CachedMessage? _replyTo;
  CachedMessage? _editingMsg;
  bool _showEmoji = false;
  final _inputKey = GlobalKey<_MessageInputState>();

  void _setReply(CachedMessage msg) {
    setState(() {
      _replyTo = msg;
      _editingMsg = null;
    });
  }

  void _setEditing(CachedMessage msg) {
    setState(() {
      _editingMsg = msg;
      _replyTo = null;
    });
  }

  void _clearMode() {
    setState(() {
      _replyTo = null;
      _editingMsg = null;
    });
  }

  @override
  void didUpdateWidget(covariant _ChatViewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear reply/edit state when switching chats.
    if (oldWidget.chat.chatId != widget.chat.chatId) {
      _replyTo = null;
      _editingMsg = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _MessageListWithFAB(
            chat: widget.chat,
            onReply: _setReply,
            onEdit: _setEditing,
          ),
        ),
        _MessageInput(
          key: _inputKey,
          chat: widget.chat,
          replyTo: _replyTo,
          editingMsg: _editingMsg,
          onClearMode: _clearMode,
          showEmoji: _showEmoji,
          onToggleEmoji: () => setState(() => _showEmoji = !_showEmoji),
        ),
        if (_showEmoji)
          SizedBox(
            height: 280,
            child: EmojiPanel(
              onEmojiSelected: (emoji) {
                _inputKey.currentState?.insertText(emoji);
              },
              onClose: () => setState(() => _showEmoji = false),
            ),
          ),
      ],
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
          // Chat info (tappable — opens info dialog)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showChatInfoDialog(context, chat, isDark),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chat.type == ChatType.topic && chat.parentTitle.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              chat.parentTitle,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                          Flexible(
                            child: Text(
                              chat.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkText : AppColors.lightText,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
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
                      _TypingIndicator(userName: typing)
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
            ),
          ),

          // Action buttons
          if (chat.type == ChatType.dm || chat.type == ChatType.group) ...[
            IconButton(
              icon: const Icon(Icons.call, size: 20),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Voice calls coming soon'), duration: Duration(seconds: 2)),
                );
              },
              tooltip: 'Voice call',
              splashRadius: 18,
            ),
            IconButton(
              icon: const Icon(Icons.videocam, size: 20),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Video calls coming soon'), duration: Duration(seconds: 2)),
                );
              },
              tooltip: 'Video call',
              splashRadius: 18,
            ),
          ],
          _PinnedMessagesButton(messages: chatState.messages, isDark: isDark),
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: () => _showSearchDialog(context, chat),
            tooltip: 'Search',
            splashRadius: 18,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: () => _showMoreMenu(context, chat),
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

  static void _showChatInfoDialog(BuildContext context, ChatInfo chat, bool isDark) {
    final initial = chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?';
    final hue = (chat.chatId.hashCode % 360).abs().toDouble();
    final avatarColor = HSLColor.fromAHSL(1, hue, 0.5, 0.4).toColor();

    final bgColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        bool muted = false;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Dialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Large avatar
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Title
                      Text(
                        chat.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),

                      // Status / member count
                      Text(
                        switch (chat.type) {
                          ChatType.dm => 'Online',
                          ChatType.group || ChatType.topic =>
                            '${chat.memberCount} members',
                          ChatType.channel => '${chat.memberCount} subscribers',
                          _ => '',
                        },
                        style: TextStyle(fontSize: 13, color: mutedColor),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      Divider(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        height: 1,
                      ),
                      const SizedBox(height: 16),

                      // Action buttons row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Mute toggle
                          _InfoActionButton(
                            icon: muted ? Icons.notifications_off : Icons.notifications,
                            label: muted ? 'Unmute' : 'Mute',
                            color: mutedColor,
                            onTap: () => setState(() => muted = !muted),
                          ),
                          // Search
                          _InfoActionButton(
                            icon: Icons.search,
                            label: 'Search',
                            color: mutedColor,
                            onTap: () => Navigator.of(ctx).pop(),
                          ),
                          // Leave (danger)
                          _InfoActionButton(
                            icon: Icons.exit_to_app,
                            label: 'Leave',
                            color: AppColors.danger,
                            onTap: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void _showSearchDialog(BuildContext context, ChatInfo chat) {
    final engine = context.read<EngineService>();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        List<SearchResult> results = [];
        return StatefulBuilder(
          builder: (ctx, setState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bgColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
            final textColor = isDark ? AppColors.darkText : AppColors.lightText;
            final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
            return Dialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440, maxHeight: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: 'Search in ${chat.title}...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onSubmitted: (query) {
                                if (query.trim().isEmpty) return;
                                final r = engine.searchMessages(query.trim(), accountId: chat.accountId, limit: 30);
                                setState(() => results = r);
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          controller.text.isEmpty ? 'Type to search messages' : 'No results',
                          style: TextStyle(color: mutedColor),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final r = results[i];
                            return ListTile(
                              dense: true,
                              leading: r.senderName.isNotEmpty
                                  ? CircleAvatar(radius: 14, child: Text(r.senderName[0], style: const TextStyle(fontSize: 12)))
                                  : null,
                              title: Text(
                                r.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textColor, fontSize: 13),
                              ),
                              subtitle: Text(
                                r.senderName.isNotEmpty ? r.senderName : r.chatTitle,
                                style: TextStyle(color: mutedColor, fontSize: 11),
                              ),
                              onTap: () => Navigator.of(ctx).pop(),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void _showMoreMenu(BuildContext context, ChatInfo chat) {
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(button.size.width - 48, button.size.height), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(value: 'mute', child: Text(chat.isMuted ? 'Unmute' : 'Mute')),
        PopupMenuItem(value: 'pin', child: Text(chat.isPinned ? 'Unpin' : 'Pin')),
        const PopupMenuItem(value: 'info', child: Text('Chat info')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'mute':
          engine.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
          chatState.loadChats();
        case 'pin':
          engine.pinChat(chat.accountId, chat.chatId, !chat.isPinned);
          chatState.loadChats();
        case 'info':
          final isDark = Theme.of(context).brightness == Brightness.dark;
          _showChatInfoDialog(context, chat, isDark);
      }
    });
  }
}

/// Pin icon button with badge count; opens a bottom sheet listing pinned messages.
class _PinnedMessagesButton extends StatelessWidget {
  final List<CachedMessage> messages;
  final bool isDark;

  const _PinnedMessagesButton({required this.messages, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final pinned = messages.where((m) => m.isPinned).toList();
    final count = pinned.length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.push_pin, size: 20),
          onPressed: () => _showPinnedSheet(context, pinned),
          tooltip: 'Pinned messages',
          splashRadius: 18,
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showPinnedSheet(BuildContext context, List<CachedMessage> pinned) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.push_pin, size: 18, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        'Pinned Messages',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkText : AppColors.lightText,
                        ),
                      ),
                      const Spacer(),
                      if (pinned.isNotEmpty)
                        Text(
                          '${pinned.length}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
                Expanded(
                  child: pinned.isEmpty
                      ? Center(
                          child: Text(
                            'No pinned messages',
                            style: TextStyle(
                              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: pinned.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 56,
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          ),
                          itemBuilder: (_, i) => _PinnedMessageTile(
                            message: pinned[i],
                            isDark: isDark,
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
}

/// Single row in the pinned messages bottom sheet.
class _PinnedMessageTile extends StatelessWidget {
  final CachedMessage message;
  final bool isDark;

  const _PinnedMessageTile({required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      message.timestamp > 9999999999 ? message.timestamp : message.timestamp * 1000,
    );
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    final senderName = message.senderName.isNotEmpty ? message.senderName : 'Unknown';
    final preview = message.contentText.isNotEmpty
        ? message.contentText
        : message.hasMedia
            ? '[Media]'
            : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender avatar placeholder
          CircleAvatar(
            radius: 18,
            backgroundColor: HSLColor.fromAHSL(
              1,
              (message.senderId.hashCode % 360).abs().toDouble(),
              0.6,
              isDark ? 0.45 : 0.55,
            ).toColor(),
            child: Text(
              senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        senderName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkText : AppColors.lightText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated typing indicator with bouncing dots.
class _TypingIndicator extends StatefulWidget {
  final String userName;
  const _TypingIndicator({required this.userName});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${widget.userName} is typing',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.accent,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(width: 2),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final delay = i * 0.2;
                final t = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
                final y = t < 0.5 ? -3.0 * (1 - (2 * t - 1).abs()) : 0.0;
                return Transform.translate(
                  offset: Offset(0, y),
                  child: const Text(
                    '.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

/// Message list wrapped with a scroll-to-bottom FAB.
class _MessageListWithFAB extends StatefulWidget {
  final ChatInfo chat;
  final ValueChanged<CachedMessage>? onReply;
  final ValueChanged<CachedMessage>? onEdit;

  const _MessageListWithFAB({
    required this.chat,
    this.onReply,
    this.onEdit,
  });

  @override
  State<_MessageListWithFAB> createState() => _MessageListWithFABState();
}

class _MessageListWithFABState extends State<_MessageListWithFAB> {
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  final Set<String> _selectedMsgIds = {};
  bool _selectionMode = false;

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
    // Load more when near the top (end of reversed list).
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<ChatState>().loadMoreMessages();
    }
    // Show FAB when scrolled up more than 300px from bottom.
    final shouldShow = _scrollController.position.pixels > 300;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _enterSelectionMode(String msgId) {
    setState(() {
      _selectionMode = true;
      _selectedMsgIds.add(msgId);
    });
  }

  void _toggleSelection(String msgId) {
    setState(() {
      if (_selectedMsgIds.contains(msgId)) {
        _selectedMsgIds.remove(msgId);
        if (_selectedMsgIds.isEmpty) _selectionMode = false;
      } else {
        _selectedMsgIds.add(msgId);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedMsgIds.clear();
    });
  }

  void _copySelected() {
    final chatState = context.read<ChatState>();
    final messages = chatState.messages;
    final selectedTexts = messages
        .where((m) => _selectedMsgIds.contains(m.msgId))
        .map((m) => m.contentText)
        .where((t) => t.isNotEmpty)
        .toList()
        .reversed
        .toList();
    Clipboard.setData(ClipboardData(text: selectedTexts.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
    );
    _cancelSelection();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Drag target wrapping the message list.
        DragTarget<String>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File upload coming soon'), duration: Duration(seconds: 2)),
              );
            }
          },
          builder: (context, candidateData, rejectedData) {
            final isDragging = candidateData.isNotEmpty;
            return Stack(
              children: [
                _MessageList(
                  chat: widget.chat,
                  scrollController: _scrollController,
                  onReply: widget.onReply,
                  onEdit: widget.onEdit,
                  selectionMode: _selectionMode,
                  selectedMsgIds: _selectedMsgIds,
                  onToggleSelection: _toggleSelection,
                  onEnterSelectionMode: _enterSelectionMode,
                ),
                if (isDragging)
                  Positioned.fill(
                    child: Container(
                      color: (isDark ? Colors.white : Colors.black).withAlpha(30),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withAlpha(220),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Drop files to upload',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_showScrollToBottom && !_selectionMode)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              backgroundColor: AppColors.accent,
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            ),
          ),
        // Selection mode bottom bar.
        if (_selectionMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                border: Border(
                  top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${_selectedMsgIds.length} selected',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    onPressed: _copySelected,
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                    label: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                    onPressed: () async {
                      final engine = context.read<EngineService>();
                      final chat = widget.chat;
                      for (final id in _selectedMsgIds.toList()) {
                        await engine.deleteMessage(chat.accountId, chat.chatId, id);
                      }
                      _cancelSelection();
                    },
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.forward, size: 18),
                    label: const Text('Forward'),
                    onPressed: () async {
                      final chat = widget.chat;
                      final result = await ForwardDialog.show(
                        context,
                        messageText: '${_selectedMsgIds.length} messages',
                        fromChatTitle: chat.title,
                      );
                      if (result != null && mounted) {
                        final engine = context.read<EngineService>();
                        for (final id in _selectedMsgIds.toList()) {
                          await engine.forwardMessage(chat.accountId, chat.chatId, id, result.chatId);
                        }
                        _cancelSelection();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _cancelSelection,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Scrollable message list with date separators and unread separator.
class _MessageList extends StatelessWidget {
  final ChatInfo chat;
  final ScrollController scrollController;
  final ValueChanged<CachedMessage>? onReply;
  final ValueChanged<CachedMessage>? onEdit;
  final bool selectionMode;
  final Set<String> selectedMsgIds;
  final ValueChanged<String>? onToggleSelection;
  final ValueChanged<String>? onEnterSelectionMode;

  const _MessageList({
    required this.chat,
    required this.scrollController,
    this.onReply,
    this.onEdit,
    this.selectionMode = false,
    this.selectedMsgIds = const {},
    this.onToggleSelection,
    this.onEnterSelectionMode,
  });

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // For topic-type chats with a non-default channel selected, show a
    // placeholder until the engine exposes per-topic message loading.
    final activeChannelId = chatState.activeChannelId;
    if (chat.type == ChatType.topic && activeChannelId != null) {
      // Look up the channel label for display.
      final ch = _kMockChannels.firstWhere(
        (c) => c.id == activeChannelId,
        orElse: () => _MockChannel(id: activeChannelId, label: activeChannelId),
      );
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tag,
              size: 40,
              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
            ),
            const SizedBox(height: 12),
            Text(
              '#${ch.label}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Messages for this channel will appear here',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
      );
    }

    final messages = chatState.messages;

    if (messages.isEmpty && !chatState.loadingMessages) {
      return Center(
        child: Text(
          'No messages yet',
          style: TextStyle(color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
        ),
      );
    }

    // Determine unread separator position.
    // In a reversed list, index 0 = newest. The unread boundary is at index == unreadCount.
    final unreadIndex = chat.unreadCount > 0 && chat.unreadCount < messages.length
        ? chat.unreadCount
        : -1;

    // Extra items: loading spinner + possible unread separator.
    final extraItems = (chatState.loadingMessages ? 1 : 0) + (unreadIndex >= 0 ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length + extraItems,
      itemBuilder: (context, index) {
        // Loading spinner at the very end.
        if (index >= messages.length + (unreadIndex >= 0 ? 1 : 0)) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        // If we have an unread separator, adjust indices.
        int msgIndex = index;
        bool showUnreadSep = false;
        if (unreadIndex >= 0) {
          if (index == unreadIndex) {
            // This is the unread separator row.
            showUnreadSep = true;
          } else if (index > unreadIndex) {
            msgIndex = index - 1;
          }
        }

        if (showUnreadSep) {
          return _UnreadSeparator(count: chat.unreadCount);
        }

        final msg = messages[msgIndex];
        final prevMsgIndex = msgIndex + 1;
        final prevMsg = prevMsgIndex < messages.length ? messages[prevMsgIndex] : null;
        final showDate = prevMsg == null || !_sameDay(msg.dateTime, prevMsg.dateTime);
        final showSender = prevMsg == null ||
            prevMsg.senderId != msg.senderId ||
            msg.timestamp - prevMsg.timestamp > 300000; // 5 min gap

        return Column(
          children: [
            if (showDate) _DateSeparator(date: msg.dateTime),
            if (selectionMode)
              GestureDetector(
                onTap: () => onToggleSelection?.call(msg.msgId),
                child: Row(
                  children: [
                    Checkbox(
                      value: selectedMsgIds.contains(msg.msgId),
                      onChanged: (_) => onToggleSelection?.call(msg.msgId),
                      activeColor: AppColors.accent,
                    ),
                    Expanded(
                      child: _MessageBubble(
                        message: msg,
                        showSender: showSender && chat.type != ChatType.channel,
                        isChannel: chat.type == ChatType.channel,
                        onReply: onReply,
                        onEdit: onEdit,
                        onLongPressSelect: null,
                      ),
                    ),
                  ],
                ),
              )
            else
              _MessageBubble(
                message: msg,
                showSender: showSender && chat.type != ChatType.channel,
                isChannel: chat.type == ChatType.channel,
                onReply: onReply,
                onEdit: onEdit,
                onLongPressSelect: () => onEnterSelectionMode?.call(msg.msgId),
              ),
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Unread separator pill.
class _UnreadSeparator extends StatelessWidget {
  final int count;
  const _UnreadSeparator({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count new message${count != 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
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

// ── Rich text parsing ──

/// Segment types for parsed content text.
enum _SegType { text, link, inlineCode, codeBlock }

class _Seg {
  final _SegType type;
  final String content;
  const _Seg(this.type, this.content);
}

/// Parse content text into segments: code blocks, inline code, links, and plain text.
List<_Seg> _parseContentText(String text) {
  final segments = <_Seg>[];
  if (text.isEmpty) return segments;

  // First pass: split by code blocks (```)
  final blockRegex = RegExp(r'```([\s\S]*?)```');
  int pos = 0;
  for (final match in blockRegex.allMatches(text)) {
    if (match.start > pos) {
      _parseInlineSegments(text.substring(pos, match.start), segments);
    }
    segments.add(_Seg(_SegType.codeBlock, match.group(1) ?? ''));
    pos = match.end;
  }
  if (pos < text.length) {
    _parseInlineSegments(text.substring(pos), segments);
  }
  return segments;
}

/// Second pass: split by inline code (`) and URLs.
void _parseInlineSegments(String text, List<_Seg> segments) {
  final inlineRegex = RegExp(r'`([^`]+)`');
  int pos = 0;
  for (final match in inlineRegex.allMatches(text)) {
    if (match.start > pos) {
      _parseLinkSegments(text.substring(pos, match.start), segments);
    }
    segments.add(_Seg(_SegType.inlineCode, match.group(1) ?? ''));
    pos = match.end;
  }
  if (pos < text.length) {
    _parseLinkSegments(text.substring(pos), segments);
  }
}

void _parseLinkSegments(String text, List<_Seg> segments) {
  final linkRegex = RegExp(r'https?://\S+');
  int pos = 0;
  for (final match in linkRegex.allMatches(text)) {
    if (match.start > pos) {
      segments.add(_Seg(_SegType.text, text.substring(pos, match.start)));
    }
    segments.add(_Seg(_SegType.link, match.group(0) ?? ''));
    pos = match.end;
  }
  if (pos < text.length) {
    segments.add(_Seg(_SegType.text, text.substring(pos)));
  }
}

/// Build a rich text widget from parsed segments.
Widget _buildRichText(String text, bool isDark) {
  final segments = _parseContentText(text);
  if (segments.isEmpty) return const SizedBox.shrink();

  // Check if there are any code blocks — they need block-level rendering.
  final hasCodeBlocks = segments.any((s) => s.type == _SegType.codeBlock);

  if (!hasCodeBlocks) {
    // Pure inline content: use Text.rich.
    return Text.rich(
      TextSpan(children: _buildInlineSpans(segments, isDark)),
      style: TextStyle(fontSize: 14, color: isDark ? AppColors.darkText : AppColors.lightText),
    );
  }

  // Mixed content with code blocks: use a Column.
  final widgets = <Widget>[];
  final inlineBuf = <_Seg>[];

  void flushInline() {
    if (inlineBuf.isEmpty) return;
    widgets.add(
      Text.rich(
        TextSpan(children: _buildInlineSpans(List.of(inlineBuf), isDark)),
        style: TextStyle(fontSize: 14, color: isDark ? AppColors.darkText : AppColors.lightText),
      ),
    );
    inlineBuf.clear();
  }

  for (final seg in segments) {
    if (seg.type == _SegType.codeBlock) {
      flushInline();
      widgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              seg.content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
          ),
        ),
      );
    } else {
      inlineBuf.add(seg);
    }
  }
  flushInline();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: widgets,
  );
}

List<InlineSpan> _buildInlineSpans(List<_Seg> segments, bool isDark) {
  final spans = <InlineSpan>[];
  for (final seg in segments) {
    switch (seg.type) {
      case _SegType.text:
        spans.add(TextSpan(text: seg.content));
      case _SegType.link:
        spans.add(TextSpan(
          text: seg.content,
          style: const TextStyle(
            color: AppColors.accentLight,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()..onTap = () {
            Process.run('xdg-open', [seg.content]);
          },
        ));
      case _SegType.inlineCode:
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              seg.content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
          ),
        ));
      case _SegType.codeBlock:
        break; // Handled at block level.
    }
  }
  return spans;
}

// ── Media rendering helpers ──

/// Format duration in seconds to mm:ss.
String _formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Download button / state indicator for media.
Widget _buildDownloadIndicator(BuildContext context, CachedMessage msg, bool isDark) {
  final state = msg.mediaDownloadState;
  if (state == 3) return const SizedBox.shrink(); // done

  IconData icon;
  bool spinning = false;
  switch (state) {
    case 1: // queued
      icon = Icons.hourglass_top;
      spinning = true;
    case 2: // downloading
      icon = Icons.downloading;
      spinning = true;
    case 4: // failed
      icon = Icons.refresh;
    default: // none
      icon = Icons.download;
  }

  return GestureDetector(
    onTap: () {
      context.read<EngineService>().requestDownload(
        msg.accountId,
        msg.chatId,
        msg.msgId,
      ).catchError((e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e')),
          );
        }
      });
    },
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        shape: BoxShape.circle,
      ),
      child: spinning
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withAlpha(200),
              ),
            )
          : Icon(icon, size: 20, color: Colors.white.withAlpha(220)),
    ),
  );
}

/// Build the media widget for a message (shown above the text).
Widget _buildMediaContent(BuildContext context, CachedMessage msg, bool isDark) {
  if (msg.isImage || msg.isGif || msg.isSticker) {
    return _buildImageMedia(context, msg, isDark);
  } else if (msg.isVideo) {
    return _buildVideoMedia(context, msg, isDark);
  } else if (msg.isAudio || msg.isVoice) {
    return _buildAudioMedia(context, msg, isDark);
  } else if (msg.isFile) {
    return _buildFileMedia(context, msg, isDark);
  }
  // Generic fallback for unknown media types.
  return _buildFileMedia(context, msg, isDark);
}

Widget _buildImageMedia(BuildContext context, CachedMessage msg, bool isDark) {
  const maxW = 300.0;
  final w = msg.mediaWidth > 0 ? math.min(maxW, msg.mediaWidth.toDouble()) : maxW;

  if (msg.mediaLocalPath.isNotEmpty && msg.isMediaDownloaded) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(msg.mediaLocalPath),
          width: w,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _mediaPlaceholder(
            icon: msg.isSticker ? Icons.emoji_emotions : (msg.isGif ? Icons.gif_box : Icons.photo),
            fileName: msg.mediaFileName,
            size: msg.mediaSizeLabel,
            isDark: isDark,
          ),
        ),
      ),
    );
  }

  if (msg.mediaThumbB64.isNotEmpty) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(msg.mediaThumbB64),
              width: w,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _mediaPlaceholder(
                icon: Icons.photo,
                fileName: msg.mediaFileName,
                size: msg.mediaSizeLabel,
                isDark: isDark,
              ),
            ),
          ),
          _buildDownloadIndicator(context, msg, isDark),
        ],
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Stack(
      alignment: Alignment.center,
      children: [
        _mediaPlaceholder(
          icon: msg.isSticker ? Icons.emoji_emotions : (msg.isGif ? Icons.gif_box : Icons.photo),
          fileName: msg.mediaFileName,
          size: msg.mediaSizeLabel,
          isDark: isDark,
        ),
        _buildDownloadIndicator(context, msg, isDark),
      ],
    ),
  );
}

Widget _buildVideoMedia(BuildContext context, CachedMessage msg, bool isDark) {
  const maxW = 300.0;
  final w = msg.mediaWidth > 0 ? math.min(maxW, msg.mediaWidth.toDouble()) : maxW;

  Widget thumb;
  if (msg.mediaLocalPath.isNotEmpty && msg.isMediaDownloaded && msg.mediaThumbB64.isNotEmpty) {
    thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(base64Decode(msg.mediaThumbB64), width: w, fit: BoxFit.contain),
    );
  } else if (msg.mediaThumbB64.isNotEmpty) {
    thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(base64Decode(msg.mediaThumbB64), width: w, fit: BoxFit.contain),
    );
  } else {
    thumb = _mediaPlaceholder(
      icon: Icons.videocam,
      fileName: msg.mediaFileName,
      size: msg.mediaSizeLabel,
      isDark: isDark,
    );
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Stack(
      alignment: Alignment.center,
      children: [
        thumb,
        // Play icon overlay.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(120),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow, size: 28, color: Colors.white),
        ),
        // Duration label.
        if (msg.mediaDuration > 0)
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(160),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(msg.mediaDuration),
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        if (!msg.isMediaDownloaded)
          Positioned(
            top: 6,
            right: 6,
            child: _buildDownloadIndicator(context, msg, isDark),
          ),
      ],
    ),
  );
}

Widget _buildAudioMedia(BuildContext context, CachedMessage msg, bool isDark) {
  final isVoice = msg.isVoice;

  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (msg.isMediaDownloaded)
            const Icon(Icons.play_arrow, size: 24, color: AppColors.accent)
          else
            SizedBox(
              width: 24,
              height: 24,
              child: _buildDownloadIndicator(context, msg, isDark),
            ),
          const SizedBox(width: 8),
          if (isVoice) ...[
            // Waveform placeholder: a row of thin bars.
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(16, (i) {
                final h = 6.0 + (math.sin(i * 0.8) * 8).abs();
                return Container(
                  width: 3,
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(180),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                );
              }),
            ),
            const SizedBox(width: 8),
          ],
          if (msg.mediaDuration > 0)
            Text(
              _formatDuration(msg.mediaDuration),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          if (!isVoice && msg.mediaSizeLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              msg.mediaSizeLabel,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _buildFileMedia(BuildContext context, CachedMessage msg, bool isDark) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.insert_drive_file, size: 22, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.mediaFileName.isNotEmpty ? msg.mediaFileName : 'File',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                if (msg.mediaSizeLabel.isNotEmpty)
                  Text(
                    msg.mediaSizeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            height: 32,
            child: _buildDownloadIndicator(context, msg, isDark),
          ),
        ],
      ),
    ),
  );
}

Widget _mediaPlaceholder({
  required IconData icon,
  required String fileName,
  required String size,
  required bool isDark,
}) {
  return Container(
    width: 200,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    decoration: BoxDecoration(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
        if (fileName.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
        ],
        if (size.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            size,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
            ),
          ),
        ],
      ],
    ),
  );
}

/// Message bubble — sent (right) or received (left), with context menu and hover actions.
class _MessageBubble extends StatefulWidget {
  final CachedMessage message;
  final bool showSender;
  final bool isChannel;
  final ValueChanged<CachedMessage>? onReply;
  final ValueChanged<CachedMessage>? onEdit;
  final VoidCallback? onLongPressSelect;

  const _MessageBubble({
    required this.message,
    required this.showSender,
    required this.isChannel,
    this.onReply,
    this.onEdit,
    this.onLongPressSelect,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSent = widget.message.senderId.isEmpty;
    final time = _formatTime(widget.message.dateTime);

    // Failed message: show retry indicator.
    if (widget.message.isFailed) {
      return _buildBubbleWrapper(
        context,
        isDark: isDark,
        isSent: isSent,
        child: _buildFailedContent(context, isDark),
      );
    }

    return _buildBubbleWrapper(
      context,
      isDark: isDark,
      isSent: isSent,
      child: _buildNormalContent(context, isDark, isSent, time),
    );
  }

  Widget _buildBubbleWrapper(
    BuildContext context, {
    required bool isDark,
    required bool isSent,
    required Widget child,
  }) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.showSender ? 8 : 2,
          left: isSent ? 60 : 0,
          right: isSent ? 0 : 60,
        ),
        child: Column(
          crossAxisAlignment: isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  mainAxisAlignment: isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Avatar for received messages
                    if (!isSent && !widget.isChannel && widget.showSender)
                      _SenderAvatar(name: widget.message.senderName)
                    else if (!isSent && !widget.isChannel)
                      const SizedBox(width: AppSizes.avatarSizeSmall + 8),

                    // Bubble with context menu
                    Flexible(
                      child: GestureDetector(
                        onSecondaryTapUp: (details) =>
                            _showContextMenu(context, details.globalPosition),
                        onLongPressStart: (details) {
                          if (widget.onLongPressSelect != null) {
                            widget.onLongPressSelect!();
                          } else {
                            _showContextMenu(context, details.globalPosition);
                          }
                        },
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
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),

                // Hover action buttons (desktop).
                if (_hovered)
                  Positioned(
                    top: -4,
                    right: isSent ? 0 : null,
                    left: isSent ? null : (widget.isChannel ? 0 : AppSizes.avatarSizeSmall + 8),
                    child: _HoverActions(
                      isDark: isDark,
                      onReply: () => widget.onReply?.call(widget.message),
                      onReact: () => _showReactionPicker(context),
                      onMore: (pos) => _showContextMenu(context, pos),
                    ),
                  ),
              ],
            ),

            // Reactions row.
            if (widget.message.reactions.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  left: (!isSent && !widget.isChannel) ? AppSizes.avatarSizeSmall + 8 : 0,
                  top: 4,
                ),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: widget.message.reactions.map((r) {
                    return _ReactionChip(
                      emoji: r.emoji,
                      count: r.count,
                      byMe: r.byMe,
                      isDark: isDark,
                      onTap: () {
                        final msg = widget.message;
                        context.read<EngineService>().reactToMessage(
                          msg.accountId, msg.chatId, msg.msgId, r.emoji,
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy - 48, pos.dx + 200, pos.dy),
      color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      items: ['👍', '❤️', '😂', '😮', '😢', '👎'].map((emoji) {
        return PopupMenuItem<String>(
          value: emoji,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        );
      }).toList(),
    ).then((emoji) {
      if (emoji != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reacted with $emoji'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    });
  }

  Widget _buildNormalContent(BuildContext context, bool isDark, bool isSent, String time) {
    final message = widget.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sender name
        if (!isSent && !widget.isChannel && widget.showSender)
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

        // Forward from indicator.
        if (message.forwardFrom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forward, size: 12,
                    color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                const SizedBox(width: 4),
                Text(
                  'Forwarded from ${message.forwardFrom}',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                  ),
                ),
              ],
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

        // Media content (above text).
        if (message.hasMedia && message.mediaType > 0)
          _buildMediaContent(context, message, isDark),

        // Message text + time
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          children: [
            if (message.contentText.isNotEmpty)
              _buildRichText(message.contentText, isDark),
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
                    message.isSending ? Icons.access_time
                        : message.status == MsgStatus.read ? Icons.done_all
                        : Icons.done,
                    size: 14,
                    color: message.status == MsgStatus.read ? AppColors.accent
                        : (isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFailedContent(BuildContext context, bool isDark) {
    final message = widget.message;
    return GestureDetector(
      onTap: () => context.read<ChatState>().retryPending(message.localId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.hasMedia)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Icon(
                Icons.attach_file,
                size: 14,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          if (message.contentText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message.contentText,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: AppColors.danger),
              SizedBox(width: 4),
              Text(
                'Tap to retry',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final message = widget.message;
    final isSent = message.senderId.isEmpty;
    final chatState = context.read<ChatState>();

    final menuBg = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        _menuItem('reply', Icons.reply, 'Reply', textColor),
        _menuItem('react', Icons.emoji_emotions_outlined, 'React', textColor),
        _menuItem('copy', Icons.copy, 'Copy', textColor),
        if (widget.onLongPressSelect != null)
          _menuItem('select', Icons.check_box_outlined, 'Select', textColor),
        if (isSent) _menuItem('edit', Icons.edit, 'Edit', textColor),
        if (isSent) _menuItem('delete', Icons.delete_outline, 'Delete', AppColors.danger),
        _menuItem('forward', Icons.forward, 'Forward', textColor),
        _menuItem('pin', Icons.push_pin_outlined, message.isPinned ? 'Unpin' : 'Pin', textColor),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      switch (value) {
        case 'reply':
          widget.onReply?.call(message);
        case 'react':
          _showReactionPicker(context);
        case 'copy':
          Clipboard.setData(ClipboardData(text: message.contentText));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
            );
          }
        case 'select':
          widget.onLongPressSelect?.call();
        case 'edit':
          widget.onEdit?.call(message);
        case 'delete':
          chatState.deleteMessage(message.msgId).catchError((e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Delete failed: $e')),
              );
            }
          });
        case 'forward':
          _forwardMessage(context, message);
        case 'pin':
          context.read<EngineService>().pinMessage(
            message.accountId, message.chatId, message.msgId, !message.isPinned,
          );
      }
    });
  }

  void _forwardMessage(BuildContext context, CachedMessage message) {
    final chatState = context.read<ChatState>();
    final activeChat = chatState.activeChat;
    ForwardDialog.show(
      context,
      messageText: message.contentText,
      fromChatTitle: activeChat?.title ?? '',
    ).then((targetChat) async {
      if (targetChat != null && context.mounted) {
        await context.read<EngineService>().forwardMessage(
          message.accountId, message.chatId, message.msgId, targetChat.chatId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Forwarded to ${targetChat.title}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, color: color)),
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

/// Hover action buttons that appear above a message bubble on desktop.
class _HoverActions extends StatelessWidget {
  final bool isDark;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final void Function(Offset position) onMore;

  const _HoverActions({
    required this.isDark,
    required this.onReply,
    required this.onReact,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionIcon(Icons.reply, 'Reply', onReply),
          _actionIcon(Icons.emoji_emotions_outlined, 'React', onReact),
          Builder(
            builder: (ctx) => _actionIcon(Icons.more_horiz, 'More', () {
              final RenderBox box = ctx.findRenderObject() as RenderBox;
              final pos = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
              onMore(pos);
            }),
          ),
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),
      ),
    );
  }
}

/// Reaction chip shown below a message bubble.
class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool byMe;
  final bool isDark;
  final VoidCallback? onTap;

  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.byMe,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: byMe
              ? AppColors.accent.withAlpha(40)
              : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: byMe ? AppColors.accent.withAlpha(120) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (count > 1) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: byMe
                      ? AppColors.accent
                      : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

/// Small icon+label button used in the chat info dialog action row.
class _InfoActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _InfoActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Message input area with reply/edit mode support and markdown toolbar.
class _MessageInput extends StatefulWidget {
  final ChatInfo chat;
  final CachedMessage? replyTo;
  final CachedMessage? editingMsg;
  final VoidCallback onClearMode;
  final bool showEmoji;
  final VoidCallback? onToggleEmoji;

  const _MessageInput({
    super.key,
    required this.chat,
    required this.replyTo,
    required this.editingMsg,
    required this.onClearMode,
    this.showEmoji = false,
    this.onToggleEmoji,
  });

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _inputRowKey = GlobalKey();
  bool _sending = false;
  bool _hasSelection = false;
  bool _textIsEmpty = true;

  // --- Voice recording state ---
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  bool _pulseVisible = true;
  Timer? _pulseTimer;

  // --- Mention autocomplete state ---
  OverlayEntry? _mentionOverlay;
  // '@' or '#'
  String? _mentionTrigger;
  // partial query after the trigger char
  String _mentionQuery = '';

  /// Pick a file via native dialog and upload it to the current chat.
  Future<void> _pickAndUploadFile() async {
    try {
      final result = await Process.run('zenity', ['--file-selection']);
      if (result.exitCode != 0) return; // cancelled
      final filePath = (result.stdout as String).trim();
      if (filePath.isEmpty) return;

      final engine = context.read<EngineService>();
      final chat = widget.chat;
      await engine.uploadFile(chat.accountId, chat.chatId, filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--file-filter=Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp',
        '--title=Select an image',
      ]);
      if (result.exitCode != 0) return;
      final filePath = (result.stdout as String).trim();
      if (filePath.isEmpty) return;

      final engine = context.read<EngineService>();
      final chat = widget.chat;
      await engine.uploadFile(chat.accountId, chat.chatId, filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  /// Insert text (e.g. emoji) at the current cursor position.
  void insertText(String text) {
    final sel = _controller.selection;
    final before = _controller.text.substring(0, sel.baseOffset.clamp(0, _controller.text.length));
    final after = _controller.text.substring(sel.extentOffset.clamp(0, _controller.text.length));
    _controller.text = '$before$text$after';
    final newOffset = before.length + text.length;
    _controller.selection = TextSelection.collapsed(offset: newOffset);
  }

  // --- Voice recording helpers ---

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
      _pulseVisible = true;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordingSeconds++);
    });
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      setState(() => _pulseVisible = !_pulseVisible);
    });
  }

  void _cancelRecording() {
    _recordingTimer?.cancel();
    _pulseTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
      _pulseVisible = true;
    });
  }

  void _sendVoice() {
    _recordingTimer?.cancel();
    _pulseTimer?.cancel();
    final seconds = _recordingSeconds;
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
      _pulseVisible = true;
    });
    final dur = seconds < 60
        ? '0:${seconds.toString().padLeft(2, '0')}'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Voice message sent ($dur)')),
    );
  }

  String get _recordingTimerLabel {
    final m = _recordingSeconds ~/ 60;
    final s = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSelectionChanged);
    _controller.addListener(_onTextChangedForMention);
  }

  // ---- mention helpers ----

  /// Returns unique sender names from chat messages (for '@' suggestions).
  List<String> _userSuggestions() {
    final chatState = context.read<ChatState>();
    final seen = <String>{};
    final result = <String>[];
    for (final msg in chatState.messages) {
      final name = msg.senderName.trim();
      if (name.isNotEmpty && seen.add(name)) result.add(name);
    }
    return result;
  }

  /// Returns channel suggestions (currently empty — no API wired yet).
  List<String> _channelSuggestions() => [];

  /// Scans the text left of the cursor for an active mention token.
  /// Returns null if the cursor is not inside a mention, otherwise returns
  /// a record of (trigger, query, tokenStart).
  ({String trigger, String query, int tokenStart})? _detectMentionToken() {
    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final cursor = sel.baseOffset.clamp(0, _controller.text.length);
    final textBefore = _controller.text.substring(0, cursor);
    // Walk backwards to find the nearest '@' or '#' that isn't preceded by
    // a word character (i.e. it's truly the start of a mention token).
    for (int i = textBefore.length - 1; i >= 0; i--) {
      final ch = textBefore[i];
      if (ch == '@' || ch == '#') {
        // Make sure there's no whitespace between trigger and cursor.
        final query = textBefore.substring(i + 1);
        if (query.contains(' ') || query.contains('\n')) return null;
        return (trigger: ch, query: query, tokenStart: i);
      }
      // Stop scanning if we hit whitespace (the token would have a space in it
      // which we already checked above, but we stop here to avoid scanning the
      // whole document).
      if (ch == ' ' || ch == '\n') return null;
    }
    return null;
  }

  void _onTextChangedForMention() {
    final token = _detectMentionToken();
    if (token == null) {
      _dismissMentionPopup();
      return;
    }
    _mentionTrigger = token.trigger;
    _mentionQuery = token.query;
    _showMentionPopup();
  }

  void _showMentionPopup() {
    // Remove stale overlay first, then rebuild.
    _mentionOverlay?.remove();
    _mentionOverlay = null;

    final List<String> pool = _mentionTrigger == '@'
        ? _userSuggestions()
        : _channelSuggestions();

    final query = _mentionQuery.toLowerCase();
    final suggestions = pool
        .where((s) => s.toLowerCase().contains(query))
        .take(5)
        .toList();

    // We always show the popup even if empty (with "No results" placeholder),
    // but only while a trigger token is active.
    final overlay = Overlay.of(context);
    _mentionOverlay = OverlayEntry(
      builder: (ctx) => _MentionPopup(
        inputRowKey: _inputRowKey,
        trigger: _mentionTrigger!,
        suggestions: suggestions,
        onSelect: _insertMention,
        onDismiss: _dismissMentionPopup,
      ),
    );
    overlay.insert(_mentionOverlay!);
    // Rebuild the overlay whenever suggestions change without recreating the
    // entry — simpler to just recreate it since text changes are infrequent.
  }

  void _dismissMentionPopup() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
    _mentionTrigger = null;
    _mentionQuery = '';
  }

  /// Replaces the active mention token with the selected suggestion.
  void _insertMention(String suggestion) {
    final token = _detectMentionToken();
    if (token == null) {
      _dismissMentionPopup();
      return;
    }
    final sel = _controller.selection;
    final cursor = sel.baseOffset.clamp(0, _controller.text.length);
    final before = _controller.text.substring(0, token.tokenStart);
    final after = _controller.text.substring(cursor);
    final inserted = '${token.trigger}$suggestion ';
    _controller.text = '$before$inserted$after';
    _controller.selection = TextSelection.collapsed(
      offset: before.length + inserted.length,
    );
    _dismissMentionPopup();
    _focusNode.requestFocus();
  }

  // ---- end mention helpers ----

  void _onSelectionChanged() {
    final sel = _controller.selection;
    final hasSel = sel.isValid && !sel.isCollapsed;
    final isEmpty = _controller.text.isEmpty;
    if (hasSel != _hasSelection || isEmpty != _textIsEmpty) {
      setState(() {
        _hasSelection = hasSel;
        _textIsEmpty = isEmpty;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When entering edit mode, pre-fill the input.
    if (widget.editingMsg != null && oldWidget.editingMsg != widget.editingMsg) {
      _controller.text = widget.editingMsg!.contentText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _focusNode.requestFocus();
    }
    // When entering reply mode, just focus.
    if (widget.replyTo != null && oldWidget.replyTo != widget.replyTo) {
      _focusNode.requestFocus();
    }
    // When clearing mode (from edit), clear the input only if it still matches the old editing text.
    if (oldWidget.editingMsg != null && widget.editingMsg == null && widget.replyTo == null) {
      if (_controller.text == oldWidget.editingMsg!.contentText) {
        _controller.clear();
      }
    }
  }

  @override
  void dispose() {
    _dismissMentionPopup();
    _recordingTimer?.cancel();
    _pulseTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    if (_sending) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _sending = true;
    _controller.clear();
    _focusNode.requestFocus();

    final chatState = context.read<ChatState>();

    if (widget.editingMsg != null) {
      // Edit mode: call editMessage.
      chatState.editMessage(widget.editingMsg!.msgId, text).then((_) {
        _sending = false;
      }).catchError((e) {
        _sending = false;
        _controller.text = text; // restore text so user doesn't lose it
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Edit failed: $e')),
          );
        }
      });
    } else {
      // Normal or reply mode.
      final replyId = widget.replyTo?.msgId ?? '';
      chatState.sendMessage(text, replyToId: replyId).then((_) {
        _sending = false;
      }).catchError((e) {
        _sending = false;
        _controller.text = text; // restore text so user doesn't lose it
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Send failed: $e')),
          );
        }
      });
    }

    widget.onClearMode();
  }

  /// Wrap the selected text with markdown markers.
  void _wrapSelection(String marker) {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final text = _controller.text;
    final selected = text.substring(sel.start, sel.end);
    final newText = '${text.substring(0, sel.start)}$marker$selected$marker${text.substring(sel.end)}';
    _controller.text = newText;
    _controller.selection = TextSelection(
      baseOffset: sel.start + marker.length,
      extentOffset: sel.end + marker.length,
    );
    _focusNode.requestFocus();
  }

  /// Handle Enter to send, Shift+Enter for newline.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (!isShift) {
        // If mention popup is open, dismiss it instead of sending.
        if (_mentionOverlay != null) {
          _dismissMentionPopup();
          return KeyEventResult.handled;
        }
        _send();
        return KeyEventResult.handled;
      }
    }
    // Escape to cancel mention popup, then reply/edit mode.
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      if (_mentionOverlay != null) {
        _dismissMentionPopup();
        return KeyEventResult.handled;
      }
      if (widget.replyTo != null || widget.editingMsg != null) {
        widget.onClearMode();
        if (widget.editingMsg != null) {
          _controller.clear();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasReply = widget.replyTo != null;
    final hasEdit = widget.editingMsg != null;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply / edit bar
          if (hasReply || hasEdit)
            _ModeBar(
              isDark: isDark,
              isEdit: hasEdit,
              senderName: hasEdit
                  ? 'Editing message'
                  : (widget.replyTo!.senderName.isNotEmpty
                      ? widget.replyTo!.senderName
                      : 'You'),
              previewText: hasEdit
                  ? widget.editingMsg!.contentText
                  : widget.replyTo!.contentText,
              onCancel: () {
                widget.onClearMode();
                if (hasEdit) _controller.clear();
              },
            ),

          // Markdown toolbar (shown when text is selected).
          if (_hasSelection)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _mdButton('B', '**', isDark),
                  _mdButton('I', '*', isDark),
                  _mdButton('</>', '`', isDark),
                  _mdButton('S', '~~', isDark),
                ],
              ),
            ),

          // Input row (or recording bar when voice recording is active)
          Padding(
            key: _inputRowKey,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _isRecording
                ? _buildRecordingBar(isDark)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add, size: 22),
                        onPressed: _pickAndUploadFile,
                        tooltip: 'Attach',
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.camera_alt_outlined, size: 22),
                        onPressed: _pickAndUploadImage,
                        tooltip: 'Send image',
                        splashRadius: 18,
                      ),
                      Expanded(
                        child: Focus(
                          onKeyEvent: _handleKeyEvent,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            maxLines: 5,
                            minLines: 1,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: hasEdit ? 'Edit message...' : 'Message ${widget.chat.title}',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      widget.showEmoji ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                                      size: 20,
                                    ),
                                    onPressed: widget.onToggleEmoji,
                                    splashRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_textIsEmpty && !hasEdit)
                        Container(
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.mic,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: _startRecording,
                            splashRadius: 20,
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: hasEdit ? AppColors.warning : AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              hasEdit ? Icons.check_rounded : Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: _send,
                            splashRadius: 20,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar(bool isDark) {
    final bgColor = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Pulsing red dot
          AnimatedOpacity(
            opacity: _pulseVisible ? 1.0 : 0.15,
            duration: const Duration(milliseconds: 400),
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Timer label
          Text(
            _recordingTimerLabel,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          const Spacer(),
          // Cancel button
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            color: Colors.red,
            tooltip: 'Cancel',
            splashRadius: 18,
            onPressed: _cancelRecording,
          ),
          // Send button
          Container(
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
              tooltip: 'Send voice message',
              splashRadius: 20,
              onPressed: _sendVoice,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mdButton(String label, String marker, bool isDark) {
    final isCode = label == '</>';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _wrapSelection(marker),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: label == 'B' ? FontWeight.w700 : (label == 'I' ? FontWeight.w400 : FontWeight.w500),
              fontStyle: label == 'I' ? FontStyle.italic : FontStyle.normal,
              fontFamily: isCode ? 'monospace' : null,
              decoration: label == 'S' ? TextDecoration.lineThrough : null,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mention autocomplete popup
// ---------------------------------------------------------------------------

/// An overlay widget that positions itself just above the input row and shows
/// up to 5 filtered mention suggestions.
class _MentionPopup extends StatelessWidget {
  final GlobalKey inputRowKey;
  final String trigger;
  final List<String> suggestions;
  final void Function(String) onSelect;
  final VoidCallback onDismiss;

  const _MentionPopup({
    required this.inputRowKey,
    required this.trigger,
    required this.suggestions,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Locate the input row on screen so we can position the popup above it.
    final renderBox = inputRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();

    final offset = renderBox.localToGlobal(Offset.zero);
    final inputTop = offset.dy;
    final inputLeft = offset.dx;
    final inputWidth = renderBox.size.width;

    // Height per item (approx) + some padding.
    const itemH = 40.0;
    const maxItems = 5;
    final itemCount = suggestions.isEmpty ? 1 : suggestions.length.clamp(1, maxItems);
    final popupH = itemCount * itemH + 8.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      left: inputLeft,
      top: inputTop - popupH - 6,
      width: inputWidth.clamp(200.0, 420.0),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        color: isDark ? AppColors.darkSurfaceAlt : Colors.white,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: suggestions.isEmpty
              ? SizedBox(
                  height: popupH,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        trigger == '@' ? 'No users found' : 'No channels',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: suggestions.map((s) {
                    return InkWell(
                      onTap: () => onSelect(s),
                      child: SizedBox(
                        height: itemH,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor: trigger == '@'
                                    ? AppColors.accent.withValues(alpha: 0.18)
                                    : Colors.grey.withValues(alpha: 0.18),
                                child: Text(
                                  s.isNotEmpty ? s[0].toUpperCase() : trigger,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: trigger == '@'
                                        ? AppColors.accent
                                        : (isDark ? AppColors.darkText : AppColors.lightText),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '$trigger$s',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? AppColors.darkText : AppColors.lightText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ),
    );
  }
}

/// Bar shown above the input when replying or editing.
class _ModeBar extends StatelessWidget {
  final bool isDark;
  final bool isEdit;
  final String senderName;
  final String previewText;
  final VoidCallback onCancel;

  const _ModeBar({
    required this.isDark,
    required this.isEdit,
    required this.senderName,
    required this.previewText,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
      ),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 32,
            decoration: BoxDecoration(
              color: isEdit ? AppColors.warning : AppColors.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isEdit ? AppColors.warning : AppColors.accent,
                  ),
                ),
                Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
            onPressed: onCancel,
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}

// ── Topic channel tab bar ──────────────────────────────────────────────────

/// Static mock channel definitions shown for topic-type groups.
/// When the engine exposes real topic/thread lists these will be replaced.
const List<_MockChannel> _kMockChannels = [
  _MockChannel(id: 'general', label: 'general'),
  _MockChannel(id: 'random', label: 'random'),
  _MockChannel(id: 'off-topic', label: 'off-topic'),
  _MockChannel(id: 'announcements', label: 'announcements'),
];

class _MockChannel {
  final String id;
  final String label;
  const _MockChannel({required this.id, required this.label});
}

/// Horizontal channel/topic tab strip shown below the header for topic groups.
class _TopicChannelTabBar extends StatelessWidget {
  final ChatInfo chat;
  const _TopicChannelTabBar({required this.chat});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = context.watch<ChatState>();
    final activeId = chatState.activeChannelId;

    final bg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textMuted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final textActive = isDark ? AppColors.darkText : AppColors.lightText;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _kMockChannels.length,
        itemBuilder: (context, i) {
          final ch = _kMockChannels[i];
          // First channel is treated as default — selected when activeId is null.
          final isSelected = activeId == null ? i == 0 : activeId == ch.id;

          return GestureDetector(
            onTap: () {
              // Tapping the first (default) channel clears the selection.
              context.read<ChatState>().setActiveChannel(i == 0 ? null : ch.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: isSelected
                  ? const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.accent, width: 2),
                      ),
                    )
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#',
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? AppColors.accent : textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    ch.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? textActive : textMuted,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
