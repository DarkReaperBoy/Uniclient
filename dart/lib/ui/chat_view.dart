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

  const ChatView({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.onToggleInfo,
    this.isInfoOpen = false,
    this.wideChatMode = false,
    this.hideTopBarDivider = false,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _composeController = TextEditingController();
  final _scrollController = ScrollController();
  String? _replyToId;
  String? _editingMsgId;
  bool _showScrollToBottom = false;
  String? _lastChatId;
  /// Spec §4.4: when the user taps the close button on the pinned bar,
  /// the bar is hidden locally for the current chat until the chat changes.
  bool _pinnedBarDismissed = false;
  final Set<String> _selectedMsgIds = {};
  bool get _selectionMode => _selectedMsgIds.isNotEmpty;
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
      // Also reset pinned bar dismiss state for the new chat.
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

  /// Jump to the replied-to message when a user taps a reply preview.
  /// If the target message is already loaded, calls `jumpToMessage` with its
  /// timestamp so it becomes the newest visible (index 0 in the reversed list)
  /// and scrolls the viewport to it. If not loaded (e.g. older than the
  /// currently paged-in window), shows a snackbar instead of silently failing.
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
          setState(() => _selectedMsgIds.add(msgId));
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
      setState(() => _selectedMsgIds.clear());
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
          // Top bar (54px per spec) or selection action bar.
          if (_selectionMode)
            _SelectionBar(
              count: _selectedMsgIds.length,
              onCancel: () => setState(() => _selectedMsgIds.clear()),
              onDelete: () => _deleteSelected(chatState),
              onCopy: () => _copySelected(chatState),
              onForward: () => _forwardSelected(context, chatState),
              forwardDragData: ForwardDragData(
                accountId: chat.accountId,
                sourceChatId: chat.chatId,
                messageIds: _selectedMsgIds.toList(),
              ),
              hideDivider: widget.hideTopBarDivider,
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
                  onReplyTap: (replyToId) => _jumpToReply(chatState, replyToId),
                  searchHighlightId: _searchResultIndex >= 0 && _searchResultIndex < _searchResultIds.length
                      ? _searchResultIds[_searchResultIndex]
                      : null,
                  searchQuery: _activeSearchQuery,
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

        return Column(
          children: [
            if (showDate) _DateSeparator(timestamp: msg.timestamp),
            GestureDetector(
              onLongPress: () => onLongPress(msg.msgId),
              onTap: inSelectionMode ? () => onToggleSelect(msg.msgId) : null,
              child: Container(
                color: isSearchHighlight
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                    : isSelected
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

/// Selection action bar replacing the top bar during multi-select mode.
class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onForward;

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

    // Spec §2.7: Drag feedback widget — small badge showing forward count.
    Widget forwardButton = IconButton(
      icon: const Icon(Icons.forward),
      tooltip: 'Forward (or drag to chat)',
      onPressed: onForward,
    );

    // Wrap forward button in Draggable if drag data is available.
    if (forwardDragData != null) {
      forwardButton = Draggable<ForwardDragData>(
        data: forwardDragData,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
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

    return Container(
      height: 54, // topBarHeight per spec §4.1
      decoration: BoxDecoration(
        color: topBarBg,
        // Spec §4.1: divider hidden during one-column slide transitions.
        border: hideDivider ? null : Border(
          bottom: BorderSide(color: shadowFg, width: 1),
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
          forwardButton,
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
  final int pinnedCount;
  final int pinnedIndex;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const _PinnedBar({
    required this.pinned,
    this.pinnedCount = 1,
    this.pinnedIndex = 0,
    this.onTap,
    this.onClose,
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

  static Color _avatarColor(String id) {
    const colors = [
      Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
      Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb),
    ];
    return colors[id.hashCode.abs() % 7];
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
