import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/chat_state.dart';
import 'chat_list_row.dart' show ForwardDragData;
import 'message_bubble.dart';

/// Chat column: top bar + message list + compose area.
/// Spec §4 (top bar 54px), §5 (messages), §7 (compose).
class ChatView extends StatefulWidget {
  /// Global hook used by app-level keyboard shortcuts (ArrowUp with nothing
  /// focused) to trigger edit-last-outgoing-message behavior on the active
  /// chat (spec §24.7). Set by the active [_ChatViewState] on mount, cleared
  /// on dispose. Returns true if the active ChatView entered edit mode.
  static bool Function()? editLastOutgoingRequest;

  /// Invoked by the app-level ArrowUp binding. Returns true if consumed.
  static bool requestEditLastOutgoing() =>
      editLastOutgoingRequest?.call() ?? false;

  /// Global hook used by app-level keyboard shortcuts (Ctrl+R with a chat
  /// open) to mark the currently active chat as read (spec §24.4
  /// `read_chat`). Set by the active [_ChatViewState] on mount, cleared on
  /// dispose. Returns true if the active chat was successfully marked read.
  static bool Function()? markActiveChatReadRequest;

  /// Invoked by the app-level Ctrl+R binding. Returns true if consumed.
  static bool requestMarkActiveChatRead() =>
      markActiveChatReadRequest?.call() ?? false;

  /// Global hook used by app-level keyboard shortcuts (Ctrl+\ with a chat
  /// open) to open the chat-level action menu (spec §24.4 `show_chat_menu`,
  /// the "peer menu"). Set by the active [_ChatViewState] on mount, cleared
  /// on dispose. Returns true if the menu was shown.
  static bool Function()? showActiveChatMenuRequest;

  /// Invoked by the app-level Ctrl+\ binding. Returns true if consumed.
  static bool requestShowActiveChatMenu() =>
      showActiveChatMenuRequest?.call() ?? false;

  /// Harness hook for always-send (spec §24.4 line 2978: Ctrl+Shift+Enter
  /// always sends regardless of mode). Real OS-delivered Ctrl+Shift+Enter
  /// reaches the compose TextField's FocusNode.onKeyEvent directly; this hook
  /// exists so the test harness (which uses HardwareKeyboard.handleKeyEvent
  /// and does not route through FocusManager in all cases) can drive the
  /// shortcut. Returns true iff the send fired (non-empty compose + active
  /// chat).
  static bool Function()? sendComposeRequest;

  /// Invoked by the harness `ctrl+shift+enter` binding. Returns true if
  /// consumed (send dispatched).
  static bool requestSendCompose() => sendComposeRequest?.call() ?? false;

  /// Global hook used by Ctrl+Up / Ctrl+Down (spec §24.6 lines 2982-2983) to
  /// cycle the reply target. direction=+1 → older message (Ctrl+Up), -1 →
  /// newer message (Ctrl+Down). Ctrl+Down on the newest message cancels the
  /// reply. Set by the active [_ChatViewState] on mount, cleared on dispose.
  /// Returns true if consumed (active chat with messages and non-edit state).
  static bool Function(int direction)? cycleReplyRequest;

  /// Invoked by the app-level Ctrl+Up / Ctrl+Down bindings. Returns true if
  /// consumed.
  static bool requestCycleReply(int direction) =>
      cycleReplyRequest?.call(direction) ?? false;

  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;
  /// Spec §4.3: true when the info panel is open so the info toggle icon
  /// renders in `windowActiveTextFg` (blue).
  final bool isInfoOpen;
  /// Spec §1: Wide chat mode (chat width >= 880px) centers the message bubble
  /// column within the chat area.
  final bool wideChatMode;
  /// Spec §4.1: hide the 1px divider below the top bar during one-column
  /// slide transitions. Re-shown after the transition completes.
  final bool hideTopBarDivider;
  /// Spec §4.7: when viewing the scheduled messages section, the selection bar
  /// shows "SEND NOW" instead of "FORWARD" and hides "COPY".
  final bool isScheduledView;

  const ChatView({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.onToggleInfo,
    this.isInfoOpen = false,
    this.wideChatMode = false,
    this.hideTopBarDivider = false,
    this.isScheduledView = false,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView>
    with TickerProviderStateMixin {
  final _composeController = TextEditingController();
  final _scrollController = ScrollController();
  String? _replyToId;
  String? _editingMsgId;
  bool _showScrollToBottom = false;
  /// Spec §5: 150ms slide-up animation for scroll-to-bottom FAB.
  late final AnimationController _fabAnimCtrl;
  /// Spec §5 / §49.17: corner button stack — Mentions, Reactions, PollVotes
  /// slide from right (150ms linear), stacked above Jump-down with 4px gaps.
  late final AnimationController _mentionsAnimCtrl;
  late final AnimationController _reactionsAnimCtrl;
  late final AnimationController _pollVotesAnimCtrl;
  bool _showMentionsBtn = false;
  bool _showReactionsBtn = false;
  bool _showPollVotesBtn = false;
  String? _lastChatId;
  /// Spec §4.4: when the user taps the close button on the pinned bar,
  /// the bar is hidden locally for the current chat until the chat changes.
  bool _pinnedBarDismissed = false;
  final Set<String> _selectedMsgIds = {};
  bool get _selectionMode => _selectedMsgIds.isNotEmpty;
  /// Spec §4.7: selection bar slide animation (200ms easeOutCirc).
  late final AnimationController _selectionAnimCtrl;
  late final CurvedAnimation _selectionCurvedAnim;
  int _lastSelectionCount = 0;
  /// Spec §4.3: when true, the top bar shows an inline search text field
  /// instead of the title/subtitle. Toggled by the search button.
  bool _isSearching = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  /// Spec §4.3: search results — list of message IDs matching the query
  /// in the current chat, and the index of the currently highlighted result.
  List<String> _searchResultIds = [];
  int _searchResultIndex = -1;
  /// Currently active search query (for highlight in message list).
  String _activeSearchQuery = '';
  // GlobalKey attached to the top-bar more_vert IconButton so the Ctrl+\
  // keyboard shortcut (spec §24.4 `show_chat_menu`) can anchor the menu
  // at the same pixel position as clicking the button. The key is passed
  // into _ChatTopBar on every rebuild; the button's RenderBox is read
  // from `_moreVertKey.currentContext` when the shortcut fires.
  final GlobalKey _moreVertKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectionAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _selectionCurvedAnim = CurvedAnimation(
      parent: _selectionAnimCtrl,
      curve: Curves.easeOutCirc,
    );
    _fabAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _mentionsAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _reactionsAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _pollVotesAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scrollController.addListener(_onScroll);
    // Register the app-level ArrowUp hook (spec §24.7: edit last outgoing
    // when compose field is empty and no edit/reply is active).
    ChatView.editLastOutgoingRequest = _editLastOutgoing;
    // Register the app-level Ctrl+R hook (spec §24.4 `read_chat`: mark the
    // currently active chat as read).
    ChatView.markActiveChatReadRequest = _markActiveChatRead;
    // Register the app-level Ctrl+\ hook (spec §24.4 `show_chat_menu`:
    // open the chat-level action menu anchored to the top-bar more_vert).
    ChatView.showActiveChatMenuRequest = _showActiveChatMenu;
    // Register the harness Ctrl+Shift+Enter hook (spec §24.4 line 2978:
    // always send regardless of mode). The real FocusNode.onKeyEvent path on
    // the compose TextField catches OS-delivered Ctrl+Shift+Enter directly;
    // this hook lets the automated harness exercise the same _sendMessage
    // entry point without having to synthesize the full modifier keystream.
    ChatView.sendComposeRequest = _requestSendCompose;
    // Register the Ctrl+Up / Ctrl+Down reply-cycling hook (spec §24.6 lines
    // 2982-2983). Real OS-delivered keystrokes land in the compose TextField's
    // FocusNode.onKeyEvent; this hook exists for the harness path AND for
    // app-level CallbackShortcuts so the shortcut works regardless of current
    // focus.
    ChatView.cycleReplyRequest = _cycleReply;
    _searchController.addListener(_onSearchQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchQueryChanged);
    if (ChatView.editLastOutgoingRequest == _editLastOutgoing) {
      ChatView.editLastOutgoingRequest = null;
    }
    if (ChatView.markActiveChatReadRequest == _markActiveChatRead) {
      ChatView.markActiveChatReadRequest = null;
    }
    if (ChatView.showActiveChatMenuRequest == _showActiveChatMenu) {
      ChatView.showActiveChatMenuRequest = null;
    }
    if (ChatView.sendComposeRequest == _requestSendCompose) {
      ChatView.sendComposeRequest = null;
    }
    if (ChatView.cycleReplyRequest == _cycleReply) {
      ChatView.cycleReplyRequest = null;
    }
    _selectionCurvedAnim.dispose();
    _selectionAnimCtrl.dispose();
    _fabAnimCtrl.dispose();
    _mentionsAnimCtrl.dispose();
    _reactionsAnimCtrl.dispose();
    _pollVotesAnimCtrl.dispose();
    _composeController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Open the chat-level action menu (Mute/Read/Pin/Archive/Leave) anchored
  /// at the top-bar more_vert button. No-op when no chat is active or the
  /// top-bar button hasn't been laid out yet (e.g. narrow-layout shell with
  /// chat column hidden). Returns true if the menu was shown.
  bool _showActiveChatMenu() {
    if (!mounted) return false;
    final chat = context.read<ChatState>().activeChat;
    if (chat == null) return false;
    final btnCtx = _moreVertKey.currentContext;
    if (btnCtx == null) return false;
    _ChatTopBar._showTopBarMenu(btnCtx, chat, onToggleInfo: widget.onToggleInfo);
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mark as read when opening a new chat.
    final chatState = context.read<ChatState>();
    final chatId = chatState.activeChat?.chatId;
    if (chatId != null && chatId != _lastChatId) {
      _lastChatId = chatId;
      // Chat changed — cancel any in-progress edit/reply/search so stale
      // state doesn't leak into the new chat's compose area.
      // Also reset pinned bar dismiss state and corner button tracking.
      _showMentionsBtn = false;
      _showReactionsBtn = false;
      _showPollVotesBtn = false;
      _mentionsAnimCtrl.value = 0;
      _reactionsAnimCtrl.value = 0;
      _pollVotesAnimCtrl.value = 0;
      if (_editingMsgId != null || _replyToId != null || _isSearching || _pinnedBarDismissed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _editingMsgId = null;
            _replyToId = null;
            _composeController.clear();
            _isSearching = false;
            _searchController.clear();
            _searchResultIds = [];
            _searchResultIndex = -1;
            _activeSearchQuery = '';
            _pinnedBarDismissed = false;
          });
        });
      }
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
    // Spec §5: show FAB after scrolling 480px from bottom.
    final showFab = _scrollController.offset > 480;
    if (showFab != _showScrollToBottom) {
      _showScrollToBottom = showFab;
      if (showFab) {
        _fabAnimCtrl.forward();
      } else {
        _fabAnimCtrl.reverse();
      }
    }
    // Spec §49.4: destroy unread bar when user scrolls to bottom.
    if (_scrollController.offset < 10) {
      context.read<ChatState>().clearOpenedUnread();
    }
  }

  bool _shouldShowContactStatusBar(ChatInfo chat) {
    if (chat.type != ChatType.dm) return false;
    if (chat.title == 'Saved Messages') return false;
    // Show for: non-contacts, blocked users, or bots.
    return !chat.isContact || chat.isBlocked || chat.isBot;
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

  /// Jump to the replied-to message when a user taps a reply preview.
  /// If the target message is already loaded, calls `jumpToMessage` with its
  /// timestamp so it becomes the newest visible (index 0 in the reversed list)
  /// and scrolls the viewport to it. If not loaded (e.g. older than the
  /// currently paged-in window), shows a snackbar instead of silently failing.
  void _showAllPinnedMessages(BuildContext context, ChatState chatState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    final textColor = isDark ? const Color(0xFFdcdcdc) : const Color(0xFF000000);
    final dividerColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1b2734) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Pinned Messages',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
              Divider(height: 1, color: dividerColor),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: chatState.pinnedMessages.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: dividerColor),
                  itemBuilder: (_, i) {
                    final msg = chatState.pinnedMessages[i];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        chatState.jumpToMessage(msg.timestamp);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(0);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 2,
                              height: 36,
                              color: accentColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pinned Message #${chatState.pinnedMessages.length - i}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                    ),
                                  ),
                                  Text(
                                    msg.contentText.isNotEmpty
                                        ? msg.contentText
                                        : '[media]',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: textColor,
                                    ),
                                  ),
                                ],
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
        );
      },
    );
  }

  void _jumpToReply(ChatState chatState, String replyToId) {
    if (replyToId.isEmpty) return;
    final target = chatState.messages.where((m) => m.msgId == replyToId).firstOrNull;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message not loaded'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    chatState.jumpToMessage(target.timestamp);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
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
        PopupMenuItem(
          value: 'pin',
          child: ListTile(
            dense: true,
            leading: Icon(msg.isPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20),
            title: Text(msg.isPinned ? 'Unpin Message' : 'Pin Message'),
          ),
        ),
        if (msg.isOutgoing)
          const PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit, size: 20), title: Text('Edit'))),
        PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error), title: Text('Delete', style: TextStyle(color: theme.colorScheme.error)))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy_info',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline, size: 20),
            title: const Text('Copy Info'),
            trailing: const Icon(Icons.chevron_right, size: 16),
          ),
        ),
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
          _modifySelection(() => _selectedMsgIds.add(msgId));
        case 'pin':
          chatState.pinMessage(msgId, !msg.isPinned);
        case 'edit':
          setState(() {
            _editingMsgId = msgId;
            _replyToId = null; // edit and reply are mutually exclusive
            _composeController.text = msg.contentText;
            _composeController.selection = TextSelection.fromPosition(
              TextPosition(offset: _composeController.text.length),
            );
          });
        case 'delete':
          chatState.deleteMessage(msgId);
        case 'copy_info':
          _showCopyInfoMenu(msg, position);
      }
    });
  }

  void _showCopyInfoMenu(CachedMessage msg, Offset position) {
    final theme = Theme.of(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: theme.colorScheme.surface,
      items: [
        PopupMenuItem(value: 'msg_id', child: Text('Message ID: ${msg.msgId}')),
        PopupMenuItem(value: 'sender_id', child: Text('Sender ID: ${msg.senderId}')),
        PopupMenuItem(value: 'chat_id', child: Text('Chat ID: ${msg.chatId}')),
        PopupMenuItem(value: 'timestamp', child: Text('Timestamp: ${msg.timestamp}')),
      ],
    ).then((value) {
      if (value == null) return;
      final text = switch (value) {
        'msg_id' => msg.msgId,
        'sender_id' => msg.senderId,
        'chat_id' => msg.chatId,
        'timestamp' => msg.timestamp.toString(),
        _ => '',
      };
      if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
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

  static const _colorIndexRemap = [0, 7, 4, 1, 6, 3, 5];
  static const _userpicColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];

  static Widget _senderFallbackAvatar(String senderId, String name, double radius) {
    final numId = int.tryParse(senderId) ?? senderId.hashCode.abs();
    final paletteIndex = _colorIndexRemap[numId.abs() % 7];
    return CircleAvatar(
      radius: radius,
      backgroundColor: _userpicColors[paletteIndex],
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontSize: radius * 0.6, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Spec §4.7: modify selection set and trigger slide animation on transitions.
  void _modifySelection(void Function() fn) {
    final wasSelecting = _selectionMode;
    setState(fn);
    if (_selectionMode) _lastSelectionCount = _selectedMsgIds.length;
    if (_selectionMode && !wasSelecting) {
      _selectionAnimCtrl.forward();
    } else if (!_selectionMode && wasSelecting) {
      _selectionAnimCtrl.reverse();
    }
  }

  void _sendNowSelected(ChatState chatState) {
    final msgIds = _selectedMsgIds.toList();
    chatState.sendScheduledNow(msgIds);
    _modifySelection(() => _selectedMsgIds.clear());
  }

  void _deleteSelected(ChatState chatState) {
    for (final id in _selectedMsgIds) {
      chatState.deleteMessage(id);
    }
    _modifySelection(() => _selectedMsgIds.clear());
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
          _modifySelection(() => _selectedMsgIds.clear());
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
    _modifySelection(() => _selectedMsgIds.clear());
  }

  /// Harness entry point for spec §24.4 line 2978 "Ctrl+Shift+Enter always
  /// sends". Gates on the same preconditions as the FocusNode-level Enter
  /// handler: compose text must be non-empty and a chat must be active.
  /// Returns true iff the send (or edit) fired.
  bool _requestSendCompose() {
    if (!mounted) return false;
    if (_composeController.text.trim().isEmpty) return false;
    if (context.read<ChatState>().activeChat == null) return false;
    _sendMessage();
    return true;
  }

  void _sendMessage() {
    final text = _composeController.text.trim();
    if (text.isEmpty) return;
    final chatState = context.read<ChatState>();
    if (_editingMsgId != null) {
      chatState.editMessage(_editingMsgId!, text);
      _composeController.clear();
      setState(() => _editingMsgId = null);
      return;
    }
    chatState.sendMessage(text, replyToId: _replyToId ?? '');
    _composeController.clear();
    setState(() => _replyToId = null);
    // Scroll to bottom after sending.
    _scrollToBottom();
  }

  /// Up-arrow-to-edit-last-message — Telegram Desktop spec §24.7: when the
  /// compose field is empty and no edit/reply is active, pressing Up enters
  /// edit mode on the newest outgoing message. `_messages` is newest-first
  /// (see ChatState._onNewMessage which inserts at index 0), so we scan from
  /// the front and pick the first `isOutgoing` message. Returns true if edit
  /// mode was entered, so the key event can be consumed.
  bool _editLastOutgoing() {
    if (_composeController.text.isNotEmpty) return false;
    if (_editingMsgId != null || _replyToId != null) return false;
    final chatState = context.read<ChatState>();
    final target = chatState.messages
        .where((m) => m.isOutgoing && m.contentText.isNotEmpty)
        .firstOrNull;
    if (target == null) return false;
    setState(() {
      _editingMsgId = target.msgId;
      _composeController.text = target.contentText;
      _composeController.selection = TextSelection.fromPosition(
        TextPosition(offset: _composeController.text.length),
      );
    });
    return true;
  }

  /// Ctrl+R handler — Telegram Desktop spec §24.4 `read_chat`: marks the
  /// currently active chat as read. Uses [ChatState.markChatRead] (not the
  /// active-only [ChatState.markRead]) so that chats with no messages
  /// currently loaded still get their unread count cleared, and so the
  /// sidebar unread badges refresh via the follow-up `loadChats()`.
  /// Returns true if a chat was active and the mark-read call was issued.
  bool _markActiveChatRead() {
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return false;
    chatState.markChatRead(chat.accountId, chat.chatId);
    return true;
  }

  /// Ctrl+Up / Ctrl+Down reply-navigation handler — Telegram Desktop spec
  /// §24.6 lines 2982-2983. `direction` is +1 for Ctrl+Up (older message)
  /// and -1 for Ctrl+Down (newer message). `chatState.messages` is newest-
  /// first (ChatState._onNewMessage inserts at index 0), so "older" is
  /// `idx + 1` and "newer" is `idx - 1`.
  ///
  /// Behavior:
  /// * If editing, no-op (edit mode takes precedence; cursor movement stays
  ///   default).
  /// * If no chat loaded / no messages, no-op.
  /// * If no reply is set and direction is +1 (Ctrl+Up): set reply to the
  ///   newest message (index 0).
  /// * If no reply is set and direction is -1 (Ctrl+Down): no-op (nothing to
  ///   cancel, nothing newer than "no reply").
  /// * If a reply is set, move the target by `direction`. Moving past the
  ///   oldest message clamps (no-op). Moving past the newest message (i.e.
  ///   Ctrl+Down on index 0) cancels the reply.
  /// * If the current reply id has scrolled out of the loaded window, restart
  ///   from the appropriate end.
  ///
  /// Returns true iff the event should be consumed.
  bool _cycleReply(int direction) {
    if (_editingMsgId != null) return false;
    final chatState = context.read<ChatState>();
    final messages = chatState.messages;
    if (messages.isEmpty) return false;
    int currentIdx;
    if (_replyToId == null) {
      if (direction < 0) return false;
      currentIdx = -1;
    } else {
      currentIdx = messages.indexWhere((m) => m.msgId == _replyToId);
      if (currentIdx < 0) currentIdx = direction > 0 ? -1 : 0;
    }
    final newIdx = currentIdx + direction;
    if (newIdx >= messages.length) {
      return true;
    }
    if (newIdx < 0) {
      setState(() => _replyToId = null);
      return true;
    }
    setState(() => _replyToId = messages[newIdx].msgId);
    return true;
  }

  /// Spec §4.3: execute in-chat search — filter current chat messages matching
  /// the query text. Results are ordered newest-first (matching the reversed
  /// ListView). Navigating results jumps the message list to each match.
  void _onSearchQueryChanged() {
    if (!mounted) return;
    final query = _searchController.text.trim().toLowerCase();
    // Avoid redundant updates if query hasn't actually changed.
    if (query == _activeSearchQuery) return;
    if (query.isEmpty) {
      setState(() {
        _searchResultIds = [];
        _searchResultIndex = -1;
        _activeSearchQuery = '';
      });
      return;
    }
    final chatState = context.read<ChatState>();
    final matches = <String>[];
    for (final msg in chatState.messages) {
      if (msg.contentText.toLowerCase().contains(query)) {
        matches.add(msg.msgId);
      }
    }
    setState(() {
      _activeSearchQuery = query;
      _searchResultIds = matches;
      _searchResultIndex = matches.isNotEmpty ? 0 : -1;
    });
    if (matches.isNotEmpty) {
      _jumpToSearchResult(chatState, 0);
    }
  }

  /// Navigate to the next search result (down = older messages).
  void _searchNext() {
    if (_searchResultIds.isEmpty) return;
    final next = (_searchResultIndex + 1) % _searchResultIds.length;
    setState(() => _searchResultIndex = next);
    _jumpToSearchResult(context.read<ChatState>(), next);
  }

  /// Navigate to the previous search result (up = newer messages).
  void _searchPrev() {
    if (_searchResultIds.isEmpty) return;
    final prev = (_searchResultIndex - 1 + _searchResultIds.length) %
        _searchResultIds.length;
    setState(() => _searchResultIndex = prev);
    _jumpToSearchResult(context.read<ChatState>(), prev);
  }

  /// Scroll the message list so the search result at [index] is visible.
  void _jumpToSearchResult(ChatState chatState, int index) {
    if (index < 0 || index >= _searchResultIds.length) return;
    final targetId = _searchResultIds[index];
    // Find the message in the currently loaded list.
    final msgIndex = chatState.messages.indexWhere((m) => m.msgId == targetId);
    if (msgIndex < 0) return;
    // The ListView is reversed (index 0 = newest = bottom). Estimate
    // pixel position: each message row ~72px average. Jump to approximate
    // position so the target is visible.
    final target = chatState.messages[msgIndex];
    chatState.jumpToMessage(target.timestamp);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  /// Escape key handler — Telegram Desktop spec §8: cancels reply, edit,
  /// or selection in priority order (selection > edit > reply). Returns
  /// `handled` if anything was cancelled so the event doesn't bubble further.
  KeyEventResult _handleEscape() {
    if (_isSearching) {
      setState(() {
        _isSearching = false;
        _searchController.clear();
        _searchResultIds = [];
        _searchResultIndex = -1;
        _activeSearchQuery = '';
      });
      return KeyEventResult.handled;
    }
    if (_selectionMode) {
      _modifySelection(() => _selectedMsgIds.clear());
      return KeyEventResult.handled;
    }
    if (_editingMsgId != null) {
      setState(() {
        _editingMsgId = null;
        _composeController.clear();
      });
      return KeyEventResult.handled;
    }
    if (_replyToId != null) {
      setState(() => _replyToId = null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = context.watch<ChatState>();
    final chat = chatState.activeChat;

    if (chat == null) {
      return const SizedBox.shrink();
    }

    // Spec §5 / §49.17: drive corner button visibility from chat data.
    final wantMentions = chat.unreadMentionCount > 0;
    if (wantMentions != _showMentionsBtn) {
      _showMentionsBtn = wantMentions;
      if (wantMentions) _mentionsAnimCtrl.forward(); else _mentionsAnimCtrl.reverse();
    }
    final wantReactions = chat.unreadReactionCount > 0;
    if (wantReactions != _showReactionsBtn) {
      _showReactionsBtn = wantReactions;
      if (wantReactions) _reactionsAnimCtrl.forward(); else _reactionsAnimCtrl.reverse();
    }
    // PollVotes: no data field yet — always hidden.
    if (_showPollVotesBtn) {
      _showPollVotesBtn = false;
      _pollVotesAnimCtrl.reverse();
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          return _handleEscape();
        }
        return KeyEventResult.ignored;
      },
      child: Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // Spec §4.7: selection bar slides in from below (200ms easeOutCirc)
          // while the top bar title/subtitle translates up by topBarHeight.
          SizedBox(
            height: 54, // topBarHeight
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _selectionCurvedAnim,
                builder: (context, _) {
                  final v = _selectionCurvedAnim.value;
                  return Stack(
                    children: [
                      // Top bar translates up as selection bar appears
                      Transform.translate(
                        offset: Offset(0, -54 * v),
                        child: _ChatTopBar(
                          chat: chat,
                          typingUser: chatState.typingUserFor(chat.chatId),
                          isOnline: chatState.isChatOnline(chat),
                          lastSeen: chatState.chatLastSeen(chat),
                          showBackButton: widget.showBackButton,
                          onBack: widget.onBack,
                          onToggleInfo: widget.onToggleInfo,
                          isInfoOpen: widget.isInfoOpen,
                          moreVertKey: _moreVertKey,
                          hideDivider: widget.hideTopBarDivider,
                          groupOnlineCount: chatState.groupOnlineCount,
                          isSearching: _isSearching,
                          searchController: _searchController,
                          searchFocusNode: _searchFocusNode,
                          searchResultCount: _searchResultIds.length,
                          searchResultIndex: _searchResultIndex,
                          hasSearchQuery: _activeSearchQuery.isNotEmpty,
                          onToggleSearch: () {
                            setState(() {
                              _isSearching = !_isSearching;
                              if (_isSearching) {
                                _searchFocusNode.requestFocus();
                              } else {
                                _searchController.clear();
                                _searchResultIds = [];
                                _searchResultIndex = -1;
                                _activeSearchQuery = '';
                              }
                            });
                          },
                          onSearchPrev: _searchPrev,
                          onSearchNext: _searchNext,
                          onSearchChanged: (_) => _onSearchQueryChanged(),
                        ),
                      ),
                      // Selection bar slides in from below
                      if (v > 0)
                        Transform.translate(
                          offset: Offset(0, 54 * (1 - v)),
                          child: _SelectionBar(
                            count: _selectionMode ? _selectedMsgIds.length : _lastSelectionCount,
                            onCancel: () => _modifySelection(() => _selectedMsgIds.clear()),
                            onDelete: () => _deleteSelected(chatState),
                            onCopy: () => _copySelected(chatState),
                            onForward: () => _forwardSelected(context, chatState),
                            isScheduledView: widget.isScheduledView,
                            onSendNow: widget.isScheduledView
                                ? () => _sendNowSelected(chatState)
                                : null,
                            forwardDragData: ForwardDragData(
                              accountId: chat.accountId,
                              sourceChatId: chat.chatId,
                              messageIds: _selectedMsgIds.toList(),
                            ),
                            hideDivider: widget.hideTopBarDivider,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          // Group call bar (§4.6) — shown when there's an active group call.
          if (chatState.activeGroupCall != null)
            _GroupCallBar(
              groupCall: chatState.activeGroupCall!,
              onJoin: () => chatState.joinGroupCall(),
            ),
          // Pinned message bar (if any pinned messages).
          if (chatState.pinnedMessages.isNotEmpty && !_pinnedBarDismissed)
            _PinnedBar(
              pinned: chatState.pinnedMessages.first,
              pinnedCount: chatState.pinnedMessages.length,
              pinnedIndex: 0,
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
              onClose: () {
                setState(() => _pinnedBarDismissed = true);
              },
              onShowAll: chatState.pinnedMessages.length > 1
                  ? () => _showAllPinnedMessages(context, chatState)
                  : null,
            ),
          // Contact status / action bar (§4.5) — shown for non-contact DMs, blocked users, or bots.
          if (_shouldShowContactStatusBar(chat))
            _ContactStatusBar(
              chat: chat,
              chatState: chatState,
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
                  onToggleSelect: (msgId) => _modifySelection(() {
                    if (_selectedMsgIds.contains(msgId)) {
                      _selectedMsgIds.remove(msgId);
                    } else {
                      _selectedMsgIds.add(msgId);
                    }
                  }),
                  onLongPress: (msgId) => _modifySelection(() {
                    _selectedMsgIds.add(msgId);
                  }),
                  onContextMenu: _showMessageContextMenu,
                  onSenderTap: (senderId) => _showSenderProfile(context, chatState, senderId),
                  onReplyTap: (replyToId) => _jumpToReply(chatState, replyToId),
                  searchHighlightId: _searchResultIndex >= 0 && _searchResultIndex < _searchResultIds.length
                      ? _searchResultIds[_searchResultIndex]
                      : null,
                  searchQuery: _activeSearchQuery,
                  openedUnreadCount: chatState.openedUnreadCount,
                ),
                // Spec §5 / §49.17: Stacked corner buttons.
                // Order bottom→top: Jump-down → Mentions → Reactions → PollVotes.
                // 4px gap (historyUnreadThingsSkip) between buttons, 12px right, 10px bottom.
                // Jump-down slides up; others slide from right. 150ms linear.
                // Each button: 52×62px hit-area.
                // --- Jump-down button (bottommost) ---
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: AnimatedBuilder(
                    animation: _fabAnimCtrl,
                    builder: (context, child) {
                      if (_fabAnimCtrl.isDismissed) return const SizedBox.shrink();
                      final dy = (1.0 - _fabAnimCtrl.value) * 82.0;
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: child,
                      );
                    },
                    child: _ScrollToBottomFab(
                      unreadCount: chatState.openedUnreadCount,
                      onTap: _scrollToBottom,
                    ),
                  ),
                ),
                // --- Mentions button ---
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_fabAnimCtrl, _mentionsAnimCtrl]),
                    builder: (context, child) {
                      if (_mentionsAnimCtrl.isDismissed) return const SizedBox.shrink();
                      // Y: stacks above jump-down (66 = 62 + 4px gap).
                      final dy = -(66.0 * _fabAnimCtrl.value);
                      // X: slides from off-screen right.
                      final dx = (1.0 - _mentionsAnimCtrl.value) * 64.0;
                      return Transform.translate(
                        offset: Offset(dx, dy),
                        child: child,
                      );
                    },
                    child: _CornerButton(
                      icon: Icons.alternate_email,
                      count: chat.unreadMentionCount,
                      onTap: _scrollToBottom,
                    ),
                  ),
                ),
                // --- Reactions button ---
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_fabAnimCtrl, _mentionsAnimCtrl, _reactionsAnimCtrl]),
                    builder: (context, child) {
                      if (_reactionsAnimCtrl.isDismissed) return const SizedBox.shrink();
                      final dy = -(66.0 * _fabAnimCtrl.value + 66.0 * _mentionsAnimCtrl.value);
                      final dx = (1.0 - _reactionsAnimCtrl.value) * 64.0;
                      return Transform.translate(
                        offset: Offset(dx, dy),
                        child: child,
                      );
                    },
                    child: _CornerButton(
                      icon: Icons.favorite_border,
                      count: chat.unreadReactionCount,
                      onTap: _scrollToBottom,
                    ),
                  ),
                ),
                // --- PollVotes button (no data yet — always hidden) ---
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_fabAnimCtrl, _mentionsAnimCtrl, _reactionsAnimCtrl, _pollVotesAnimCtrl]),
                    builder: (context, child) {
                      if (_pollVotesAnimCtrl.isDismissed) return const SizedBox.shrink();
                      final dy = -(66.0 * _fabAnimCtrl.value + 66.0 * _mentionsAnimCtrl.value + 66.0 * _reactionsAnimCtrl.value);
                      final dx = (1.0 - _pollVotesAnimCtrl.value) * 64.0;
                      return Transform.translate(
                        offset: Offset(dx, dy),
                        child: child,
                      );
                    },
                    child: _CornerButton(
                      icon: Icons.poll,
                      count: 0,
                      onTap: _scrollToBottom,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Edit bar (takes precedence over reply bar).
          if (_editingMsgId != null)
            _EditBar(
              editingId: _editingMsgId!,
              messages: chatState.messages,
              onCancel: () {
                setState(() {
                  _editingMsgId = null;
                  _composeController.clear();
                });
              },
            )
          else if (_replyToId != null)
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
            isEditing: _editingMsgId != null,
            onEditLast: _editLastOutgoing,
            onCycleReply: _cycleReply,
          ),
        ],
      ),
      ),
    );
  }
}

/// Chat top bar. Spec §4: 54px height.
/// Spec §4.3: shared top-bar button chrome — 40px width (overridable),
/// 54px height, 40px circular ripple centered at (0, 7), 20px icon glyph.
/// Colors: menuIconFg resting, menuIconFgOver on hover, windowBgOver overlay.
class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double width;
  /// Optional padding inside the 40×40 ripple circle to offset the icon
  /// from center. Used by menu toggle to place icon at spec position (16, 17).
  final EdgeInsetsGeometry? iconPadding;
  /// Spec §4.3: active state uses `windowActiveTextFg` (blue) instead of
  /// `menuIconFg`. Used by the info toggle when the info panel is open.
  final bool isActive;
  const _TopBarButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.width = 40,
    this.iconPadding,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuIconFg = isDark
        ? const Color(0xFF6c7883)
        : const Color(0xFF999999);
    final menuIconFgOver = isDark
        ? const Color(0xFFdcdcdc)
        : const Color(0xFF8a8a8a);
    final windowBgOver = isDark
        ? const Color(0xFF202b36)
        : const Color(0xFFf1f1f1);
    // Spec §4.3: windowActiveTextFg — day #168acd, night #6ab3f3.
    final windowActiveTextFg = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);

    final restColor = isActive ? windowActiveTextFg : menuIconFg;
    final hoverColor = isActive ? windowActiveTextFg : menuIconFgOver;

    Widget btn = SizedBox(
      width: width,
      height: 54,
      child: Center(
        child: IconButton(
          icon: Icon(icon, size: 20),
          onPressed: onPressed,
          padding: iconPadding ?? EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: ButtonStyle(
            fixedSize: const WidgetStatePropertyAll(Size(40, 40)),
            minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
            maximumSize: const WidgetStatePropertyAll(Size(40, 40)),
            shape: const WidgetStatePropertyAll(CircleBorder()),
            iconColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return menuIconFg.withAlpha((0.4 * 255).round());
              }
              if (states.contains(WidgetState.hovered)) return hoverColor;
              return restColor;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.transparent;
              }
              return windowBgOver;
            }),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
    return btn;
  }
}

class _ChatTopBar extends StatelessWidget {
  final ChatInfo chat;
  final String? typingUser;
  final bool isOnline;
  final ({String kind, int lastSeenMs}) lastSeen;
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;
  /// Attached to the more_vert IconButton so the Ctrl+\ shortcut (spec
  /// §24.4 `show_chat_menu`) can anchor the menu at the same pixel
  /// position as clicking the button.
  final Key? moreVertKey;
  /// Spec §4.1: hide the bottom divider during one-column slide transitions.
  final bool hideDivider;

  final int groupOnlineCount;
  /// Spec §4.3: when true, the info toggle icon uses `windowActiveTextFg`
  /// (blue) instead of the default `menuIconFg`.
  final bool isInfoOpen;

  /// Spec §4.3: search button state — when true, the title/subtitle area is
  /// replaced with an inline search text field.
  final bool isSearching;
  final VoidCallback? onToggleSearch;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  /// Spec §4.3: search results navigation state.
  final int searchResultCount;
  final int searchResultIndex;
  /// True when a search query has been entered (to show counter/nav).
  final bool hasSearchQuery;
  final VoidCallback? onSearchPrev;
  final VoidCallback? onSearchNext;
  final ValueChanged<String>? onSearchChanged;

  const _ChatTopBar({
    required this.chat,
    this.typingUser,
    this.isOnline = false,
    this.lastSeen = (kind: '', lastSeenMs: 0),
    required this.showBackButton,
    this.onBack,
    this.onToggleInfo,
    this.moreVertKey,
    this.hideDivider = false,
    this.groupOnlineCount = 0,
    this.isInfoOpen = false,
    this.isSearching = false,
    this.onToggleSearch,
    this.searchController,
    this.searchFocusNode,
    this.searchResultCount = 0,
    this.searchResultIndex = -1,
    this.hasSearchQuery = false,
    this.onSearchPrev,
    this.onSearchNext,
    this.onSearchChanged,
  });

  /// Format a last-seen descriptor per Telegram Desktop spec §1.4 / §7588.
  static String _formatLastSeen(({String kind, int lastSeenMs}) ls) =>
      formatChatLastSeen(ls);

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

  /// Show the chat-level action menu anchored to the more_vert button.
  /// Spec §4.3: New Window, Archive, Pin, View Profile, Mute, Mark Read/Unread,
  /// Clear History, Delete Chat, Leave Channel.
  static void _showTopBarMenu(BuildContext btnCtx, ChatInfo chat, {VoidCallback? onToggleInfo}) {
    final chatState = btnCtx.read<ChatState>();
    final overlay = Overlay.of(btnCtx).context.findRenderObject() as RenderBox;
    final button = btnCtx.findRenderObject() as RenderBox;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      origin & button.size,
      Offset.zero & overlay.size,
    );
    final isGroupy = chat.type == ChatType.group ||
        chat.type == ChatType.channel ||
        chat.type == ChatType.topic;
    final isDm = chat.type == ChatType.dm;
    showMenu<String>(
      context: btnCtx,
      position: position,
      items: [
        if (onToggleInfo != null)
          const PopupMenuItem(value: 'view_profile', child: Text('View Profile')),
        PopupMenuItem(value: 'mute', child: Text(chat.isMuted ? 'Unmute' : 'Mute')),
        PopupMenuItem(
          value: 'read',
          child: Text(chat.unreadCount > 0 ? 'Mark as Read' : 'Mark as Unread'),
        ),
        PopupMenuItem(value: 'pin', child: Text(chat.isPinned ? 'Unpin' : 'Pin')),
        PopupMenuItem(value: 'archive', child: Text(chat.isArchived ? 'Unarchive' : 'Archive')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'clear_history', child: Text('Clear History')),
        if (isDm)
          const PopupMenuItem(value: 'delete_chat', child: Text('Delete Chat')),
        if (isGroupy)
          PopupMenuItem(value: 'leave', child: Text(chat.type == ChatType.channel ? 'Leave Channel' : 'Leave Chat')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'view_profile':
          onToggleInfo?.call();
        case 'mute':
          chatState.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
        case 'read':
          if (chat.unreadCount > 0) {
            chatState.markChatRead(chat.accountId, chat.chatId);
          }
        case 'pin':
          chatState.pinChat(chat.accountId, chat.chatId, !chat.isPinned);
        case 'archive':
          chatState.archiveChat(chat.accountId, chat.chatId, !chat.isArchived);
        case 'clear_history':
          chatState.clearHistory(chat.accountId, chat.chatId);
        case 'delete_chat':
          chatState.deleteChat(chat.accountId, chat.chatId);
        case 'leave':
          chatState.leaveChat(chat.accountId, chat.chatId);
      }
    });
  }

  /// Spec §4.3: right-click on call button opens audio/video call submenu.
  static void _showCallMenu(BuildContext context, Offset globalPos) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      globalPos & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(
          value: 'audio_call',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.call, size: 20),
            title: Text('Audio Call'),
          ),
        ),
        PopupMenuItem(
          value: 'video_call',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.videocam, size: 20),
            title: Text('Video Call'),
          ),
        ),
      ],
    );
  }

  /// Spec §4.2: right-click on back button opens a call-type menu.
  static void _showBackButtonCallMenu(BuildContext context, Offset globalPos) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      globalPos & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(
          value: 'audio_call',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.call, size: 20),
            title: Text('Audio Call'),
          ),
        ),
        PopupMenuItem(
          value: 'video_call',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.videocam, size: 20),
            title: Text('Video Call'),
          ),
        ),
      ],
    );
  }

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
  static const _userpicPalette = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];

  static Widget _fallbackAvatar(ChatInfo chat, ThemeData theme, double radius) {
    final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
    final paletteIndex = _colorRemap[numId.abs() % 7];
    return CircleAvatar(
      radius: radius,
      backgroundColor: _userpicPalette[paletteIndex],
      child: Text(
        chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontSize: radius * 0.7, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Subtitle: typing, online status, member count, or last seen.
    String subtitle;
    Color? subtitleColor;
    final bool isTyping = typingUser != null;
    if (isTyping) {
      subtitle = ''; // rendered via _TopBarTypingDots widget instead
      subtitleColor = theme.colorScheme.primary;
    } else if (chat.type == ChatType.dm && isOnline) {
      subtitle = 'online';
      subtitleColor = const Color(0xFF3BA55C); // online green
    } else if (chat.type == ChatType.dm) {
      subtitle = _formatLastSeen(lastSeen);
      // Spec §4.2 / §14135: windowSubTextFg gray for offline/last-seen.
      // Day #999999, night #98b4d3.
      subtitleColor = isDark
          ? const Color(0xFF98b4d3)
          : const Color(0xFF999999);
    } else if (chat.memberCount > 0) {
      // Spec §4.2: windowSubTextFg for group/channel subtitle.
      subtitleColor = isDark
          ? const Color(0xFF98b4d3)
          : const Color(0xFF999999);
      if (chat.type == ChatType.channel) {
        subtitle = '${chat.memberCount} subscribers';
      } else if (groupOnlineCount > 1) {
        subtitle = '${chat.memberCount} members, $groupOnlineCount online';
      } else {
        subtitle = '${chat.memberCount} members';
      }
    } else {
      subtitle = '';
    }
    // Spec §4.1: topBarBg = windowBg. Day #ffffff, night #17212b.
    final topBarBg = isDark ? const Color(0xFF17212b) : Colors.white;
    // Spec §4.1: shadowFg divider. Day #00000018 (~9% black), night #04080e56 (~34%).
    final shadowFg = isDark ? const Color(0x5604080e) : const Color(0x18000000);

    return Container(
      height: 54, // topBarHeight per spec §4.1
      decoration: BoxDecoration(
        color: topBarBg,
        // Spec §4.1: divider hidden during one-column slide transitions.
        border: hideDivider ? null : Border(
          bottom: BorderSide(color: shadowFg, width: 1),
        ),
      ),
      // Spec §4.2: left uses _leftTaken (60px with back, 17px without).
      // Spec §4.3: buttons flush (0-gap) — no right padding; the menu toggle's
      // 44px width provides the right-side breathing room for the icon.
      child: Row(
        children: [
          if (showBackButton)
            // Spec §4.2: historyTopBarBack — exact 60px width, full 54px height.
            // Right-click opens call-type menu per spec §4.2.
            GestureDetector(
              onSecondaryTapUp: (details) {
                _showBackButtonCallMenu(context, details.globalPosition);
              },
              child: SizedBox(
                width: 60,
                height: 54,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ),
            )
          else
            // Spec §4.2: _leftTaken = 17px when no back button.
            const SizedBox(width: 17),
          // Spec §4.2: UserpicButton — 52×54px hit-area, 42px photo diameter,
          // photo offset (2, -1) → positioned at left=2, top=(54-42)/2-1=5.
          // Full 52×54 hit-area is opaque (accepts taps everywhere).
          // Horizontal origin = _leftTaken (60px with back, 17px without).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleInfo,
            child: SizedBox(
              width: 52,
              height: 54,
              child: Stack(
                children: [
                  Positioned(
                    left: 2,
                    top: 5, // (54 - 42) / 2 + (-1)
                    child: _chatAvatar(chat, theme, 21),
                  ),
                ],
              ),
            ),
          ),
          // Spec §4.3: when searching, replace title/subtitle with inline
          // search text field + filter buttons + results navigation.
          if (isSearching)
            Expanded(
              child: Row(
                children: [
                  // Search text field fills available space.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          hintStyle: TextStyle(
                            color: isDark
                                ? const Color(0xFF6c7883)
                                : const Color(0xFF999999),
                            fontSize: 14,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                        ),
                        onChanged: onSearchChanged,
                        onSubmitted: (_) => onSearchNext?.call(),
                      ),
                    ),
                  ),
                  // Spec §4.3: when query is active, show results counter
                  // and navigation arrows. When empty, show filter buttons.
                  if (hasSearchQuery) ...[
                    // Results counter text.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        searchResultCount > 0
                            ? '${searchResultIndex + 1} of $searchResultCount'
                            : 'No results',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF6c7883)
                              : const Color(0xFF999999),
                        ),
                      ),
                    ),
                    // Up arrow — previous (newer) result.
                    SizedBox(
                      width: 28,
                      height: 54,
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                        onPressed: searchResultCount > 0
                            ? onSearchPrev
                            : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 14,
                        color: isDark
                            ? const Color(0xFF6c7883)
                            : const Color(0xFF999999),
                      ),
                    ),
                    // Down arrow — next (older) result.
                    SizedBox(
                      width: 28,
                      height: 54,
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                        onPressed: searchResultCount > 0
                            ? onSearchNext
                            : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 14,
                        color: isDark
                            ? const Color(0xFF6c7883)
                            : const Color(0xFF999999),
                      ),
                    ),
                  ] else ...[
                    // Spec §4.3: "jump to date" filter button (calendar icon).
                    _TopBarButton(
                      icon: Icons.calendar_today,
                      onPressed: () {
                        final ctx = searchFocusNode?.context;
                        if (ctx == null) return;
                        showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2013, 8),
                          lastDate: DateTime.now(),
                        ).then((date) {
                          if (date == null) return;
                          final chatState = ctx.read<ChatState>();
                          chatState.jumpToMessage(date.millisecondsSinceEpoch);
                        });
                      },
                    ),
                    // Spec §4.3: "choose from user" filter button (person icon).
                    if (chat.type == ChatType.group ||
                        chat.type == ChatType.channel ||
                        chat.type == ChatType.topic)
                      _TopBarButton(
                        icon: Icons.person_search,
                        onPressed: () {
                          // TODO: open user picker for "from user" filter
                        },
                      ),
                  ],
                ],
              ),
            )
          else
            // Tappable title block — toggles info panel.
            Expanded(
              child: InkWell(
                onTap: onToggleInfo,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              chat.title.isNotEmpty ? chat.title : chat.chatId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (chat.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                              size: 16,
                              color: Color(0xFF168acd),
                            ),
                          ],
                          if (chat.isScam) ...[
                            const SizedBox(width: 4),
                            _TopBarWarningBadge(label: 'SCAM'),
                          ],
                          if (chat.isFake) ...[
                            const SizedBox(width: 4),
                            _TopBarWarningBadge(label: 'FAKE'),
                          ],
                          if (chat.isMuted) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.volume_off,
                              size: 16,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ],
                        ],
                      ),
                      if (isTyping)
                        _TopBarTypingDots(
                          userName: typingUser!,
                          color: subtitleColor ?? theme.colorScheme.primary,
                        )
                      else if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13, // dialogsTextFont = normalFont 13px
                            color: subtitleColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          // Spec §4.3: right-side buttons — shared 40×54 chrome.
          // Per spec order (left to right): Search, GroupCall, Call, Info, Menu.
          // Spec §4.3: Search button — top_bar_search icon, toggles inline search.
          _TopBarButton(
            icon: Icons.search,
            onPressed: onToggleSearch,
            isActive: isSearching,
          ),
          // Spec §4.3: Call button — 1:1 DMs only, phone icon.
          // Right-click opens audio/video call submenu.
          if (chat.type == ChatType.dm)
            Builder(
              builder: (btnCtx) => GestureDetector(
                onSecondaryTapUp: (details) {
                  _showCallMenu(btnCtx, details.globalPosition);
                },
                child: _TopBarButton(
                  icon: Icons.call,
                  onPressed: () {
                    // TODO: initiate audio call via engine
                  },
                ),
              ),
            ),
          // Spec §4.3: Group call button — groups/channels when calls permitted.
          // icon: top_bar_group_call, iconPosition (4, 12).
          if (chat.type == ChatType.group || chat.type == ChatType.channel)
            _TopBarButton(
              icon: Icons.phone_in_talk,
              onPressed: () {
                // TODO: initiate group call via engine
              },
            ),
          if (onToggleInfo != null)
            _TopBarButton(
              icon: Icons.info_outline,
              onPressed: onToggleInfo,
              isActive: isInfoOpen,
            ),
          // Spec §4.3: topBarSkip = -5px — menu toggle pulled 5px tighter
          // against its left neighbour.  Allocate 39px (44 − 5) in the Row
          // while rendering the full 44px button; the 5px overflow extends
          // leftward into the previous button's space.
          SizedBox(
            width: 39, // 44 - topBarSkip(5)
            child: OverflowBox(
              maxWidth: 44,
              alignment: Alignment.centerRight,
              child: Builder(
                builder: (btnCtx) => _TopBarButton(
                  key: moreVertKey,
                  icon: Icons.more_vert,
                  width: 44,
                  iconPadding: const EdgeInsets.only(left: 8),
                  onPressed: () => _showTopBarMenu(btnCtx, chat, onToggleInfo: onToggleInfo),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spec §4.2: Animated typing indicator for the top bar subtitle.
/// Shows "UserName is typing" with three bouncing dots.
class _TopBarWarningBadge extends StatelessWidget {
  final String label;
  const _TopBarWarningBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFe53935);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.0,
        ),
      ),
    );
  }
}

class _TopBarTypingDots extends StatefulWidget {
  final String userName;
  final Color color;

  const _TopBarTypingDots({required this.userName, required this.color});

  @override
  State<_TopBarTypingDots> createState() => _TopBarTypingDotsState();
}

class _TopBarTypingDotsState extends State<_TopBarTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 13, // dialogsTextFont = normalFont 13px
      color: widget.color,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '${widget.userName} is typing',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 1),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value + i / 3.0) * 2 * math.pi;
                final dy = -2.5 * math.max(0.0, math.sin(phase));
                return Padding(
                  padding: const EdgeInsets.only(left: 1),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Text(
                      '.',
                      style: style?.copyWith(fontWeight: FontWeight.bold),
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
  final ValueChanged<String>? onReplyTap;
  /// Spec §4.3: ID of the currently highlighted search result message.
  final String? searchHighlightId;
  /// Spec §4.3: active search query for text highlighting within bubbles.
  final String searchQuery;
  /// Spec §5 / §49.4: unread count at time chat was opened (for unread bar).
  final int openedUnreadCount;

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
    this.onReplyTap,
    this.searchHighlightId,
    this.searchQuery = '',
    this.openedUnreadCount = 0,
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
        final isSearchHighlight = msg.msgId == searchHighlightId;

        // Spec §5 / §49.4: unread bar above oldest unread message.
        // messages[0] = newest, so oldest unread = messages[openedUnreadCount - 1].
        final showUnreadBar = openedUnreadCount > 0 &&
            openedUnreadCount <= messages.length &&
            index == openedUnreadCount - 1;

        return Column(
          children: [
            if (showDate) _DateSeparator(timestamp: msg.timestamp),
            if (showUnreadBar) _UnreadBar(count: openedUnreadCount),
            GestureDetector(
              behavior: inSelectionMode ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
              onLongPress: () => onLongPress(msg.msgId),
              onTap: inSelectionMode ? () => onToggleSelect(msg.msgId) : null,
              child: Container(
                color: isSearchHighlight
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
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
                          isSelected: isSelected,
                          senderAvatarB64: senderAvatars?.senderAvatar(msg.senderId),
                          onReply: () => onReply(msg.msgId),
                          onContextMenu: (pos) => onContextMenu(msg.msgId, pos),
                          onSenderTap: onSenderTap,
                          onReplyTap: onReplyTap,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    // msgServiceBg: day #517c417f, night #213040d5
    final bgColor = isDark ? const Color(0xD5213040) : const Color(0x7F517c41);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
}

/// Spec §5 / §49.4: Full-width "N unread messages" divider band.
/// historyUnreadBarBg: day #FCFBFA / night #182433
/// historyUnreadBarFg: day #538BB4 / night #FFFFFF
class _UnreadBar extends StatelessWidget {
  final int count;
  const _UnreadBar({required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF182433) : const Color(0xFFFCFBFA);
    final fgColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF538BB4);
    // 1px top/bottom borders — subtle separator lines
    final borderColor = isDark
        ? const Color(0xFF0E1621) // slightly darker than bg
        : const Color(0xFFE8E8E8); // light gray

    final label = count == 1 ? '1 unread message' : '$count unread messages';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.symmetric(
          horizontal: BorderSide(color: borderColor, width: 1),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: fgColor,
        ),
      ),
    );
  }
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

/// Edit bar shown above the compose area while editing an outgoing message.
/// Telegram Desktop-style: blue 2px side stripe, pencil icon, "Editing" header +
/// 1-line preview of the message being edited.
class _EditBar extends StatelessWidget {
  final String editingId;
  final List<CachedMessage> messages;
  final VoidCallback onCancel;

  const _EditBar({
    required this.editingId,
    required this.messages,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = messages.where((m) => m.msgId == editingId).firstOrNull;

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
          Icon(Icons.edit, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Container(width: 2, height: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing',
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
            tooltip: 'Cancel edit',
          ),
        ],
      ),
    );
  }
}

/// Spec §4.5: Contact Status / Action Bar.
/// Shows below the top bar for DMs with non-contacts (Add Contact + Block),
/// blocked users (Unblock), or bots (status label).
class _ContactStatusBar extends StatelessWidget {
  final ChatInfo chat;
  final ChatState chatState;

  const _ContactStatusBar({required this.chat, required this.chatState});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec: windowActiveTextFg — day #168acd, night #6ab3f3.
    final windowActiveTextFg = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);
    // Spec: attentionButtonFg — red in both themes.
    const attentionButtonFg = Color(0xFFdf3f40);
    // Spec: historyComposeAreaBg — flat background matches compose area.
    final bgColor = isDark
        ? const Color(0xFF17212b)
        : const Color(0xFFffffff);
    // Spec: historyComposeButtonBg — hover background.
    final hoverColor = isDark
        ? const Color(0xFF202b36)
        : const Color(0xFFF1F1F1);

    if (chat.isBlocked) {
      // Blocked: single "Unblock" button, 46px height, attentionButtonFg red.
      return Container(
        color: bgColor,
        height: 46,
        child: _ContactStatusButton(
          label: 'Unblock',
          color: attentionButtonFg,
          hoverColor: hoverColor,
          height: 46,
          textTop: 14,
          onTap: () => chatState.unblockUser(chat.accountId, chat.chatId),
        ),
      );
    }

    if (chat.isBot) {
      // Bot: status label centered, minWidth 240, no buttons.
      return Container(
        color: bgColor,
        height: 49,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240),
          child: Text(
            'This is a bot',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      );
    }

    // Non-contact: "Add Contact" (blue) + "Block" (red), side by side.
    return Container(
      color: bgColor,
      height: 49,
      child: Row(
        children: [
          Expanded(
            child: _ContactStatusButton(
              label: 'Add Contact',
              color: windowActiveTextFg,
              hoverColor: hoverColor,
              height: 49,
              textTop: 16,
              onTap: () => _showAddContactDialog(context),
            ),
          ),
          const SizedBox(width: 16), // Spec: historyContactStatusMinSkip 16px.
          Expanded(
            child: _ContactStatusButton(
              label: 'Block',
              color: attentionButtonFg,
              hoverColor: hoverColor,
              height: 49,
              textTop: 16,
              onTap: () => chatState.blockUser(chat.accountId, chat.chatId),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddContactDialog(BuildContext context) {
    final firstNameCtrl = TextEditingController(text: chat.title);
    final lastNameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameCtrl,
              decoration: const InputDecoration(labelText: 'First Name'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lastNameCtrl,
              decoration: const InputDecoration(labelText: 'Last Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              chatState.addContact(
                chat.accountId,
                '', // phone unknown from DM context
                firstNameCtrl.text.trim(),
                lastNameCtrl.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

/// Spec §4.5: A single full-width flat button for the contact status bar.
class _ContactStatusButton extends StatefulWidget {
  final String label;
  final Color color;
  final Color hoverColor;
  final double height;
  final double textTop;
  final VoidCallback onTap;

  const _ContactStatusButton({
    required this.label,
    required this.color,
    required this.hoverColor,
    required this.height,
    required this.textTop,
    required this.onTap,
  });

  @override
  State<_ContactStatusButton> createState() => _ContactStatusButtonState();
}

class _ContactStatusButtonState extends State<_ContactStatusButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          color: _hovered ? widget.hoverColor : Colors.transparent,
          alignment: Alignment.topCenter,
          padding: EdgeInsets.only(top: widget.textTop),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Selection action bar replacing the top bar during multi-select mode.
/// In scheduled view (spec §4.7), shows "SEND NOW" + "DELETE" + "CLEAR"
/// instead of the normal "FORWARD" + "COPY" + "DELETE" + "CLEAR".
class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onForward;

  /// Spec §4.7: when true, shows "SEND NOW" replacing "FORWARD" and hides "COPY".
  final bool isScheduledView;
  /// Spec §4.7: callback for "Send Now" in scheduled section.
  final VoidCallback? onSendNow;

  /// Spec §2.7: Drag data for forward drag-and-drop.
  final ForwardDragData? forwardDragData;
  /// Spec §4.1: hide the bottom divider during one-column slide transitions.
  final bool hideDivider;

  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
    required this.onCopy,
    required this.onForward,
    this.isScheduledView = false,
    this.onSendNow,
    this.forwardDragData,
    this.hideDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Spec §4.1: match top bar colors in selection mode.
    final topBarBg = isDark ? const Color(0xFF17212b) : Colors.white;
    final shadowFg = isDark ? const Color(0x5604080e) : const Color(0x18000000);

    // Spec §4.7: defaultActiveButton — blue pill RoundButton, white text.
    // Corner radii: 8px outer ends, 4px small inner ends (segmented pill).
    const largeR = Radius.circular(8);
    const smallR = Radius.circular(4);
    final basePillStyle = TextButton.styleFrom(
      backgroundColor: const Color(0xFF40A7E3), // activeButtonBg
      foregroundColor: Colors.white, // activeButtonFg
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    // First button: large left corners, small right corners.
    final firstPillStyle = basePillStyle.copyWith(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: const BorderRadius.only(
          topLeft: largeR, bottomLeft: largeR,
          topRight: smallR, bottomRight: smallR,
        ),
      )),
    );
    // Middle button: all small corners.
    final middlePillStyle = basePillStyle.copyWith(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.all(smallR),
      )),
    );
    // Last button: small left corners, large right corners.
    final lastPillStyle = basePillStyle.copyWith(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: const BorderRadius.only(
          topLeft: smallR, bottomLeft: smallR,
          topRight: largeR, bottomRight: largeR,
        ),
      )),
    );

    // Spec §4.7: In scheduled view, show "SEND NOW" + "DELETE" only.
    // In normal view, show "FORWARD" + "COPY" + "DELETE".
    final List<Widget> actionButtons;

    if (isScheduledView) {
      // Scheduled section: SEND NOW (first) + DELETE (last) — two buttons only.
      actionButtons = [
        Expanded(
          child: TextButton(
            onPressed: onSendNow,
            style: firstPillStyle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('SEND NOW', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                _AnimatedCountBadge(count: count),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextButton(
            onPressed: onDelete,
            style: lastPillStyle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('DELETE', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                _AnimatedCountBadge(count: count),
              ],
            ),
          ),
        ),
      ];
    } else {
      // Normal selection: FORWARD + COPY + DELETE — three buttons.
      Widget forwardButton = TextButton(
        onPressed: onForward,
        style: firstPillStyle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(child: Text('FORWARD', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            _AnimatedCountBadge(count: count),
          ],
        ),
      );

      // Wrap forward button in Draggable if drag data is available.
      if (forwardDragData != null) {
        forwardButton = Draggable<ForwardDragData>(
          data: forwardDragData,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 4,
            borderRadius: const BorderRadius.only(
              topLeft: largeR, bottomLeft: largeR,
              topRight: smallR, bottomRight: smallR,
            ),
            color: isDark ? const Color(0xFF2b5278) : const Color(0xFF419fd9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.forward, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '$count message${count > 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: forwardButton,
        );
      }

      actionButtons = [
        Expanded(child: forwardButton),
        const SizedBox(width: 10), // topBarActionSkip
        Expanded(
          child: TextButton(
            onPressed: onCopy,
            style: middlePillStyle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('COPY', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                _AnimatedCountBadge(count: count),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextButton(
            onPressed: onDelete,
            style: lastPillStyle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('DELETE', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                _AnimatedCountBadge(count: count),
              ],
            ),
          ),
        ),
      ];
    }

    return Container(
      height: 54, // topBarHeight per spec §4.1
      decoration: BoxDecoration(
        color: topBarBg,
        // Spec §4.1: divider hidden during one-column slide transitions.
        border: hideDivider ? null : Border(
          bottom: BorderSide(color: shadowFg, width: 1),
        ),
      ),
      padding: const EdgeInsets.only(left: 8, right: 10),
      child: Row(
        children: [
          const SizedBox(width: 8),
          // Spec §4.7: action buttons share equal width via setFullWidth.
          ...actionButtons,
          const SizedBox(width: 10),
          // Spec §4.7: Cancel/clear button — RoundButton(defaultLightButton),
          // width: -18px (auto-width with 18px horizontal padding),
          // right-aligned 10px from edge. Label: "CLEAR" uppercase.
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: isDark
                  ? const Color(0xFF6AB2F2) // windowActiveTextFg night
                  : const Color(0xFF168ACD), // windowActiveTextFg day
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              shape: const StadiumBorder(),
            ),
            child: const Text('CLEAR'),
          ),
        ],
      ),
    );
  }
}

/// Spec §4.7: Animated count badge for selection bar buttons.
/// Mimics tdesktop `setNumbersText` — count slides vertically when changing.
class _AnimatedCountBadge extends StatelessWidget {
  final int count;
  const _AnimatedCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      transitionBuilder: (child, animation) {
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
      child: Text(
        '$count',
        key: ValueKey<int>(count),
      ),
    );
  }
}

/// Group call bar (§4.6) — shown when there's an active group call in a group/channel.
/// Displays overlapping participant userpics with green speaking-indicator rings and a "Join" button.
class _GroupCallBar extends StatelessWidget {
  final GroupCallInfo groupCall;
  final VoidCallback? onJoin;

  const _GroupCallBar({
    required this.groupCall,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? const Color(0xFF1B2734) : const Color(0xFFFFFFFF);
    final shadowColor = isDark ? const Color(0x5604080E) : const Color(0x18000000);
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtitleColor = isDark ? const Color(0xFF7E8B99) : const Color(0xFF999999);
    final accentGreen = const Color(0xFF4DC920);
    final joinBg = const Color(0xFF40A7E3);

    final participants = groupCall.participants;
    // Show up to 3 overlapping userpics.
    final visibleParticipants = participants.take(3).toList();

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: shadowColor, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            // Overlapping participant userpics.
            if (visibleParticipants.isNotEmpty) ...[
              SizedBox(
                width: 28.0 + (visibleParticipants.length - 1) * 20.0,
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < visibleParticipants.length; i++)
                      Positioned(
                        left: i * 20.0,
                        child: _GroupCallUserpic(
                          participant: visibleParticipants[i],
                          isSpeaking: visibleParticipants[i].isSpeaking,
                          accentGreen: accentGreen,
                          isDark: isDark,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              // No participants yet — show a phone icon.
              Icon(Icons.phone_in_talk, size: 22, color: joinBg),
              const SizedBox(width: 10),
            ],
            // Title and participant count.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupCall.title.isNotEmpty ? groupCall.title : 'Voice Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    groupCall.participantsCount > 0
                        ? '${groupCall.participantsCount} participant${groupCall.participantsCount == 1 ? '' : 's'}'
                        : 'No participants',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            // "Join" button.
            Material(
              color: joinBg,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onJoin,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  child: Text(
                    'Join',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular userpic for a group call participant with optional green speaking ring.
class _GroupCallUserpic extends StatelessWidget {
  final GroupCallParticipant participant;
  final bool isSpeaking;
  final Color accentGreen;
  final bool isDark;

  const _GroupCallUserpic({
    required this.participant,
    required this.isSpeaking,
    required this.accentGreen,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 28;
    const double borderWidth = 2;
    // Color by userId hash for deterministic avatar bg.
    final hue = (participant.userId.hashCode % 360).abs().toDouble();
    final avatarBg = HSLColor.fromAHSL(1, hue, 0.5, 0.45).toColor();
    final initials = participant.displayName.isNotEmpty
        ? participant.displayName[0].toUpperCase()
        : '?';

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarBg,
        border: isSpeaking
            ? Border.all(color: accentGreen, width: borderWidth)
            : Border.all(
                color: isDark ? const Color(0xFF17212B) : Colors.white,
                width: borderWidth,
              ),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );

    return avatar;
  }
}

/// Pinned message bar below the top bar.
/// Shows the most recent pinned message with a pin icon.
class _PinnedBar extends StatelessWidget {
  final CachedMessage pinned;
  final int pinnedCount;
  final int pinnedIndex;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final VoidCallback? onShowAll;

  const _PinnedBar({
    required this.pinned,
    this.pinnedCount = 1,
    this.pinnedIndex = 0,
    this.onTap,
    this.onClose,
    this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec §4.4: historyPinnedBg. Day=#ffffff, night=#1b2734.
    final pinnedBg = isDark ? const Color(0xFF1b2734) : Colors.white;
    // Spec §4.4: bottom divider same as top bar shadow.
    final shadowFg = isDark ? const Color(0x5604080e) : const Color(0x18000000);
    // Spec §4.4: left accent stripe in msgInReplyBarColor.
    // Day = activeLineFg (~#168acd). Night ≈ #429bdb.
    final accentColor = isDark ? const Color(0xFF429bdb) : const Color(0xFF168acd);
    // Spec §4.4: title color = windowActiveTextFg (blue accent).
    final titleColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    // Spec §4.4: preview text = historyComposeAreaFg.
    final previewColor = isDark ? const Color(0xFFdcdcdc) : const Color(0xFF000000);

    return Container(
      height: 49, // historyReplyHeight
      decoration: BoxDecoration(
        color: pinnedBg,
        border: Border(
          bottom: BorderSide(color: shadowFg, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Content area — tapping navigates to pinned message.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Row(
                children: [
                  const SizedBox(width: 1), // msgReplyBarPos offset x=1px
                  // Spec §4.4: left accent stripe — 2px wide, 36px tall.
                  Container(width: 2, height: 36, color: accentColor),
                  const SizedBox(width: 10), // msgReplyBarSkip
                  // Spec §4.4: content change animation 160ms.
                  // Wraps thumbnail + title/preview so entire content
                  // animates together when the pinned message changes.
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        final slideIn = Tween<Offset>(
                          begin: const Offset(0, 0.5),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slideIn,
                            child: child,
                          ),
                        );
                      },
                      child: Row(
                        key: ValueKey(pinned.msgId),
                        children: [
                          if (pinned.mediaThumbB64.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: _buildPinnedThumb(),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _pinnedTitle(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: titleColor,
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
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: previewColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Spec §4.4: multi-pin "Show All" button — same size as close,
          // icon pinned_show_all, only shown when pinnedCount > 1.
          if (pinnedCount > 1)
            _PinnedBarShowAllButton(onShowAll: onShowAll),
          // Spec §4.4: close/unpin button — 49×49 hit-area, 40px ripple
          // at (4,4), box_button_close icon in historyReplyCancelFg.
          _PinnedBarCloseButton(onClose: onClose),
        ],
      ),
    );
  }

  String _pinnedTitle() {
    if (pinnedCount <= 1) return 'Pinned Message';
    if (pinnedCount == 2 && pinnedIndex > 0) {
      return 'Previous Pinned Message';
    }
    return 'Pinned Message #${pinnedCount - pinnedIndex}';
  }

  Widget _buildPinnedThumb() {
    try {
      final bytes = base64Decode(pinned.mediaThumbB64);
      return Image.memory(
        bytes,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbPlaceholder(),
      );
    } catch (_) {
      return _thumbPlaceholder();
    }
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 32,
      height: 32,
      color: Colors.grey.shade300,
      child: const Icon(Icons.image, size: 16, color: Colors.grey),
    );
  }
}

/// Spec §4.4: historyPinnedShowAll — same 49×49 hit-area, 40px circular
/// ripple at (4,4), `pinned_show_all` icon. Same colors as close button.
/// Only shown when multiple pinned messages exist.
class _PinnedBarShowAllButton extends StatelessWidget {
  final VoidCallback? onShowAll;
  const _PinnedBarShowAllButton({this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cancelFg = isDark ? const Color(0xFF6c7883) : const Color(0xFF999999);
    final cancelFgOver = isDark ? const Color(0xFFa8a8a8) : const Color(0xFF7c7c7c);

    return SizedBox(
      width: 49,
      height: 49,
      child: Stack(
        children: [
          Positioned(
            left: 4,
            top: 4,
            child: ClipOval(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onShowAll,
                  splashColor: (isDark
                      ? const Color(0xFF3a4654)
                      : const Color(0xFFf1f1f1)),
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: _HoverColorIcon(
                      icon: Icons.view_list,
                      size: 18,
                      color: cancelFg,
                      hoverColor: cancelFgOver,
                    ),
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

/// Spec §4.4: historyReplyCancel — 49×49 hit-area, 40px circular ripple
/// at (4,4), `box_button_close` icon. Colors: historyReplyCancelFg resting,
/// historyReplyCancelFgOver on hover.
class _PinnedBarCloseButton extends StatelessWidget {
  final VoidCallback? onClose;
  const _PinnedBarCloseButton({this.onClose});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // historyReplyCancelFg: day #999999 (placeholderFg), night #6c7883.
    final cancelFg = isDark ? const Color(0xFF6c7883) : const Color(0xFF999999);
    // historyReplyCancelFgOver: day #7c7c7c, night #a8a8a8.
    final cancelFgOver = isDark ? const Color(0xFFa8a8a8) : const Color(0xFF7c7c7c);

    return SizedBox(
      width: 49,
      height: 49,
      child: Stack(
        children: [
          // Ripple circle: 40px at offset (4,4) inside the 49×49 area.
          Positioned(
            left: 4,
            top: 4,
            child: ClipOval(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClose,
                  splashColor: (isDark
                      ? const Color(0xFF3a4654)
                      : const Color(0xFFf1f1f1)),
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: _HoverColorIcon(
                      icon: Icons.close,
                      size: 18,
                      color: cancelFg,
                      hoverColor: cancelFgOver,
                    ),
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

/// Icon that changes color on hover (no surrounding InkWell needed —
/// used inside the ripple ClipOval above).
class _HoverColorIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final Color hoverColor;
  const _HoverColorIcon({required this.icon, required this.size, required this.color, required this.hoverColor});
  @override
  State<_HoverColorIcon> createState() => _HoverColorIconState();
}

class _HoverColorIconState extends State<_HoverColorIcon> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Center(
        child: Icon(
          widget.icon,
          size: widget.size,
          color: _hovered ? widget.hoverColor : widget.color,
        ),
      ),
    );
  }
}

/// Scroll-to-bottom FAB (spec §5: JumpDownButton).
/// Spec §5: JumpDownButton — 52×62px hit-area, 42px visible disc,
/// two-layer icon (shadow disc + arrow), muted unread badge 4px above.
class _ScrollToBottomFab extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _ScrollToBottomFab({required this.unreadCount, required this.onTap});

  @override
  State<_ScrollToBottomFab> createState() => _ScrollToBottomFabState();
}

class _ScrollToBottomFabState extends State<_ScrollToBottomFab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec colors.
    final discBg = isDark ? const Color(0xFF1D2B3A) : const Color(0xFFFFFFFF);
    final discBgOver = isDark ? const Color(0xFF243446) : const Color(0xFFF1F1F1);
    final arrowColor = isDark ? const Color(0xFFADB4BA) : const Color(0xFF999999);
    const shadowColor = Color(0x40000000); // #00000040 = 25% black
    // Badge: muted palette.
    final badgeBg = isDark ? const Color(0xFF3E546A) : const Color(0xFFBBBBBB);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 52,
          height: 62 + (widget.unreadCount > 0 ? 26 : 0), // badge adds 22+4 above
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Badge: 4px above the 62px button area.
              if (widget.unreadCount > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.unreadCount > 9999
                            ? '9999+'
                            : widget.unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              // Button area: 52×62, disc at (5,15) within it.
              Positioned(
                bottom: 0,
                left: 0,
                child: SizedBox(
                  width: 52,
                  height: 62,
                  child: Stack(
                    children: [
                      // Shadow disc (slightly offset down for drop shadow).
                      Positioned(
                        left: 5,
                        top: 17, // 15 + 2px shadow offset
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: shadowColor,
                          ),
                        ),
                      ),
                      // Main disc.
                      Positioned(
                        left: 5,
                        top: 15,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _hovered ? discBgOver : discBg,
                          ),
                        ),
                      ),
                      // Arrow icon centered on disc.
                      Positioned(
                        left: 5,
                        top: 15,
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(
                            Icons.arrow_downward,
                            size: 20,
                            color: arrowColor,
                          ),
                        ),
                      ),
                    ],
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

/// Corner button for Mentions/Reactions/PollVotes (spec §5 / §49.17).
/// Same 52×62px hit-area and 42px visible disc as JumpDownButton, but
/// with a custom icon and count badge on the disc itself.
class _CornerButton extends StatefulWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  const _CornerButton({
    required this.icon,
    required this.count,
    required this.onTap,
  });

  @override
  State<_CornerButton> createState() => _CornerButtonState();
}

class _CornerButtonState extends State<_CornerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final discBg = isDark ? const Color(0xFF1D2B3A) : const Color(0xFFFFFFFF);
    final discBgOver = isDark ? const Color(0xFF243446) : const Color(0xFFF1F1F1);
    final iconColor = isDark ? const Color(0xFFADB4BA) : const Color(0xFF999999);
    const shadowColor = Color(0x40000000);
    // Badge uses the same muted palette as JumpDownButton.
    final badgeBg = isDark ? const Color(0xFF3E546A) : const Color(0xFFBBBBBB);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 52,
          height: 62 + (widget.count > 0 ? 26 : 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Badge: 4px above the 62px button area.
              if (widget.count > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.count > 9999
                            ? '9999+'
                            : widget.count.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              // Button area: 52×62, disc at (5,15).
              Positioned(
                bottom: 0,
                left: 0,
                child: SizedBox(
                  width: 52,
                  height: 62,
                  child: Stack(
                    children: [
                      // Shadow disc.
                      Positioned(
                        left: 5,
                        top: 17,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: shadowColor,
                          ),
                        ),
                      ),
                      // Main disc.
                      Positioned(
                        left: 5,
                        top: 15,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _hovered ? discBgOver : discBg,
                          ),
                        ),
                      ),
                      // Icon centered on disc.
                      Positioned(
                        left: 5,
                        top: 15,
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(
                            widget.icon,
                            size: 20,
                            color: iconColor,
                          ),
                        ),
                      ),
                    ],
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

/// Compose area at bottom. Spec §7.
/// Enter sends, Shift+Enter for newline (matching Telegram Desktop).
/// Up arrow with empty field → edit last outgoing message (spec §24.7).
class _ComposeArea extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onDraftChanged;
  final bool isEditing;
  /// Called when Up is pressed with empty field + no edit/reply active.
  /// Returns true if edit mode was entered (so the event is consumed).
  final bool Function()? onEditLast;
  /// Called on Ctrl+Up (direction=+1) / Ctrl+Down (direction=-1) to cycle
  /// the reply target (spec §24.6 lines 2982-2983). Returns true when the
  /// event was consumed.
  final bool Function(int direction)? onCycleReply;

  const _ComposeArea({
    required this.controller,
    required this.onSend,
    required this.onDraftChanged,
    this.isEditing = false,
    this.onEditLast,
    this.onCycleReply,
  });

  @override
  State<_ComposeArea> createState() => _ComposeAreaState();
}

class _ComposeAreaState extends State<_ComposeArea> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    // FocusNode.onKeyEvent runs BEFORE EditableText's built-in text-editing
    // actions (MoveSelectionUp on ArrowUp), so this is the only place we can
    // reliably intercept ArrowUp in an empty compose field before it gets
    // consumed as cursor movement. Enter handling moved here too for symmetry.
    _focusNode = FocusNode(onKeyEvent: _onKey);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Ctrl+Shift+Enter → always send (spec §24.4 line 2978: "always sends
    // regardless of mode"). Intercepted BEFORE the plain-Enter branch since
    // isShiftPressed is true here, and BEFORE falling through to default
    // EditableText handling which would otherwise insert a newline.
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      widget.onSend();
      return KeyEventResult.handled;
    }
    // Enter without Shift → send (spec §7).
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onSend();
      return KeyEventResult.handled;
    }
    // Up-arrow-to-edit-last-outgoing (spec §24.7): only when field is empty
    // and no modifier held. The onEditLast callback itself gates on edit/reply
    // state and message availability, returning false when it declines.
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        widget.controller.text.isEmpty &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      final handled = widget.onEditLast?.call() ?? false;
      if (handled) return KeyEventResult.handled;
    }
    // Ctrl+Up / Ctrl+Down cycle the reply target (spec §24.6 lines 2982-2983).
    // Intercepted BEFORE EditableText's cursor-movement actions so the reply
    // bar appears instead of the caret jumping. No-op when edit mode is active
    // or when there are no messages loaded (see onCycleReply docs).
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      final handled = widget.onCycleReply?.call(1) ?? false;
      if (handled) return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      final handled = widget.onCycleReply?.call(-1) ?? false;
      if (handled) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

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
          // Text input — key handling lives on the FocusNode so Enter (send)
          // and ArrowUp (edit last) fire before EditableText's default actions.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                onChanged: widget.onDraftChanged,
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
          // Send button — icon switches to check/save while editing (spec §7: "editing -> Save").
          IconButton(
            tooltip: widget.isEditing ? 'Save' : 'Send',
            icon: Icon(
              widget.isEditing ? Icons.check : Icons.send,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            onPressed: widget.onSend,
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

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
  static const _userpicPalette = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];

  static Color _avatarColor(String id) {
    final numId = int.tryParse(id) ?? id.hashCode.abs();
    return _userpicPalette[_colorRemap[numId.abs() % 7]];
  }
}

/// Format a last-seen descriptor per Telegram Desktop spec §4.2 / §14138.
/// Shared by the chat top bar and the info panel avatar header.
///
/// Time format matches Telegram Desktop: 12-hour AM/PM (via QLocale in
/// original source). kind variants: recently, within_week, within_month,
/// long_ago, exact (with lastSeenMs timestamp).
String formatChatLastSeen(({String kind, int lastSeenMs}) ls) {
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
      final time = _formatTime12h(then);
      if (sameDay) return 'last seen today at $time';
      if (yesterday) return 'last seen yesterday at $time';
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final date = '${months[then.month - 1]} ${then.day}';
      if (then.year != now.year) {
        return 'last seen $date, ${then.year} at $time';
      }
      return 'last seen $date at $time';
    default:
      return '';
  }
}

/// Format a [DateTime] as 12-hour time with AM/PM (e.g. "3:45 PM").
/// Matches Telegram Desktop QLocale English format per spec §14145.
String _formatTime12h(DateTime dt) {
  final h = dt.hour;
  final m = dt.minute.toString().padLeft(2, '0');
  if (h == 0) return '12:$m AM';
  if (h < 12) return '$h:$m AM';
  if (h == 12) return '12:$m PM';
  return '${h - 12}:$m PM';
}
