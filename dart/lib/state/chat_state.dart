import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../utils/debug.dart';

/// Chat list + active chat + messages state.
class ChatState extends ChangeNotifier {
  final EngineService _engine;

  List<ChatInfo> _chats = [];
  ChatInfo? _activeChat;
  List<CachedMessage> _messages = [];
  bool _loadingMessages = false;
  bool _hasMoreMessages = true;
  final Map<String, String> _typingUsers = {}; // chatId → userName

  /// Callback for showing in-app notifications (set by UI layer).
  void Function(String senderName, String text, String chatTitle)? onNotification;

  /// Active channel/topic ID within a topic-type group.
  /// Null means "show all" (the default channel).
  String? _activeChannelId;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _pollTimer;

  ChatState(this._engine) {
    _subs.add(_engine.onChatSnapshot.listen((chats) {
      _chats = chats;
      notifyListeners();
    }));
    _subs.add(_engine.onChatUpdated.listen(_handleChatUpdated));
    _subs.add(_engine.onChatRemoved.listen(_handleChatRemoved));
    _subs.add(_engine.onMsgReceived.listen(_handleMsgReceived));
    _subs.add(_engine.onMsgEdited.listen(_handleMsgEdited));
    _subs.add(_engine.onMsgDeleted.listen(_handleMsgDeleted));
    _subs.add(_engine.onMsgStatus.listen(_handleMsgStatus));
    _subs.add(_engine.onTyping.listen(_handleTyping));
    // Reload chats when any account connects (sync may have finished).
    _subs.add(_engine.onConnState.listen((event) {
      Debug.log('CHAT', 'conn_state: ${event.accountId} → ${event.state}');
      if (event.state == 'connected') {
        Debug.log('CHAT', 'Loading chats after connect...');
        loadChats();
      }
    }));
    // Also reload when auth finishes (finalizeAuth emits account_list).
    _subs.add(_engine.onAccountList.listen((_) {
      loadChats();
    }));
    // Download complete → update message's local path in-memory.
    _subs.add(_engine.onDownloadComplete.listen(_handleDownloadComplete));
  }

  // ── Getters ──

  List<ChatInfo> get chats => _chats;
  ChatInfo? get activeChat => _activeChat;
  List<CachedMessage> get messages => _messages;
  bool get loadingMessages => _loadingMessages;
  bool get hasMoreMessages => _hasMoreMessages;

  /// Active channel/topic within a topic-type group. Null = default/all.
  String? get activeChannelId => _activeChannelId;

  String? typingUserFor(String chatId) => _typingUsers[chatId];

  /// Chats filtered by platform (empty = all).
  /// Account IDs use a 4-char prefix of the platform name (e.g. "tele_abc123"
  /// for "telegram"), so we match by that prefix.
  List<ChatInfo> chatsForPlatform(String platform) {
    if (platform.isEmpty) return _chats;
    final prefix = platform.length > 4 ? platform.substring(0, 4) : platform;
    return _chats.where((c) => c.accountId.startsWith(prefix)).toList();
  }

  /// Total unread count across all visible chats.
  int get totalUnread => _chats.fold(0, (sum, c) => sum + c.unreadCount);

  // ── Actions ──

  /// Load the chat list from engine.
  void loadChats({String accountId = '', bool archived = false}) {
    _chats = _engine.getChatList(accountId: accountId, archived: archived);
    notifyListeners();
  }

  /// Open a chat — loads messages and sets as active.
  void openChat(ChatInfo chat) {
    _activeChat = chat;
    _messages = [];
    _hasMoreMessages = true;
    _activeChannelId = null; // reset channel selection on chat change
    _engine.setActiveChat(chat.accountId, chat.chatId);
    _loadMessages();
    _startPolling();
    notifyListeners();
  }

  /// Select a channel/topic within the active topic-type group.
  /// Pass null to deselect (show default/all).
  void setActiveChannel(String? channelId) {
    _activeChannelId = channelId;
    notifyListeners();
  }

  /// Close the active chat.
  void closeChat() {
    _stopPolling();
    _activeChat = null;
    _messages = [];
    _engine.clearActiveChat();
    notifyListeners();
  }

  /// Load more messages (pagination).
  void loadMoreMessages() {
    if (_loadingMessages || !_hasMoreMessages || _activeChat == null) return;
    _loadMessages();
  }

  /// Send a message in the active chat.
  /// Go handles optimistic insert + event emission; we refresh after send.
  Future<String?> sendMessage(String text, {String replyToId = ''}) async {
    final chat = _activeChat;
    if (chat == null || text.trim().isEmpty) return null;

    final localId = await _engine.sendMessage(chat.accountId, chat.chatId, text, replyToId: replyToId);

    // Refresh messages — Go inserted the optimistic message into cache,
    // so re-fetching picks it up even if the event callback didn't fire.
    _refreshMessages();

    return localId;
  }

  Future<void> editMessage(String msgId, String newText) async {
    final chat = _activeChat;
    if (chat == null) return;
    await _engine.editMessage(chat.accountId, chat.chatId, msgId, newText);
    // Optimistic local update — don't wait for event.
    final idx = _messages.indexWhere((m) => m.msgId == msgId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(
        contentText: newText,
        editedAt: DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    }
  }

  Future<void> deleteMessage(String msgId) async {
    final chat = _activeChat;
    if (chat == null) return;
    await _engine.deleteMessage(chat.accountId, chat.chatId, msgId);
    // Optimistic local removal — don't wait for event.
    _messages.removeWhere((m) => m.msgId == msgId);
    notifyListeners();
  }

  Future<void> retryPending(String localId) async {
    await _engine.retryPending(localId);
  }

  void saveDraft(String text) {
    final chat = _activeChat;
    if (chat == null) return;
    _engine.saveDraft(chat.accountId, chat.chatId, text);
  }

  void markRead() {
    final chat = _activeChat;
    if (chat == null || _messages.isEmpty) return;
    _engine.markChatRead(chat.accountId, chat.chatId, _messages.first.msgId);
  }

  // ── Chat operations ──

  void muteChat(String accountId, String chatId, bool muted) {
    _engine.muteChat(accountId, chatId, muted);
    loadChats(); // refresh to reflect change
  }

  void pinChat(String accountId, String chatId, bool pinned) {
    _engine.pinChat(accountId, chatId, pinned);
    loadChats();
  }

  void archiveChat(String accountId, String chatId, bool archived) {
    _engine.archiveChat(accountId, chatId, archived);
    loadChats();
  }

  void markChatRead(String accountId, String chatId) {
    // Find the latest message for this chat.
    final chatMsgs = _messages.where((m) => m.accountId == accountId && m.chatId == chatId);
    if (chatMsgs.isNotEmpty) {
      _engine.markChatRead(accountId, chatId, chatMsgs.first.msgId);
    }
    loadChats();
  }

  // ── Search ──

  List<SearchResult> searchMessages(String query, {String accountId = ''}) {
    return _engine.searchMessages(query, accountId: accountId);
  }

  List<ChatInfo> searchChats(String query) {
    return _engine.searchChats(query);
  }

  // ── Internal ──

  void _loadMessages() {
    final chat = _activeChat;
    if (chat == null) return;

    _loadingMessages = true;
    notifyListeners();

    final beforeMs = _messages.isNotEmpty ? _messages.last.timestamp : 0;
    final newMsgs = _engine.getMessages(chat.accountId, chat.chatId, beforeMs: beforeMs);

    if (newMsgs.length < 50) _hasMoreMessages = false;
    _messages.addAll(newMsgs);
    _loadingMessages = false;
    notifyListeners();
  }

  /// Re-fetch the latest messages for the active chat and merge.
  /// Used after send and as a periodic fallback for event delivery issues.
  void _refreshMessages() {
    final chat = _activeChat;
    if (chat == null) return;

    final fresh = _engine.getMessages(chat.accountId, chat.chatId, beforeMs: 0);
    if (fresh.isEmpty) return;

    // Merge: replace the newest portion of messages with fresh data.
    // Keep any older paginated messages that aren't in the fresh batch.
    final freshIds = fresh.map((m) => m.msgId).toSet();
    final older = _messages.where((m) => !freshIds.contains(m.msgId)).toList();
    // fresh is newest-first; older are already oldest-last from pagination.
    _messages = [...fresh, ...older.where((m) => m.timestamp < (fresh.last.timestamp))];
    notifyListeners();
  }

  /// Start periodic polling for the active chat (fallback for event delivery).
  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshMessages();
      // Also refresh chat list for unread counts etc.
      loadChats();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _handleChatUpdated(ChatInfo updated) {
    final idx = _chats.indexWhere((c) => c.accountId == updated.accountId && c.chatId == updated.chatId);
    if (idx >= 0) {
      _chats[idx] = updated;
    } else {
      _chats.insert(0, updated);
    }
    // Update active chat if it matches.
    if (_activeChat?.accountId == updated.accountId && _activeChat?.chatId == updated.chatId) {
      _activeChat = updated;
    }
    notifyListeners();
  }

  void _handleChatRemoved(ChatRemovedEvent event) {
    _chats.removeWhere((c) => c.chatId == event.chatId && (event.accountId.isEmpty || c.accountId == event.accountId));
    if (_activeChat?.chatId == event.chatId && (event.accountId.isEmpty || _activeChat?.accountId == event.accountId)) {
      _activeChat = null;
      _messages = [];
    }
    notifyListeners();
  }

  void _handleMsgReceived(MsgReceivedEvent event) {
    final isActiveChat = _activeChat?.accountId == event.accountId &&
        _activeChat?.chatId == event.chatId;
    if (isActiveChat) {
      // Dedup: don't add if already present (by msgId or localId).
      final exists = _messages.any((m) =>
        m.msgId == event.message.msgId ||
        (event.message.localId.isNotEmpty && m.localId == event.message.localId));
      if (!exists) {
        _messages.insert(0, event.message);
        notifyListeners();
      }
    } else if (onNotification != null && !event.message.isSent) {
      // Show in-app notification for messages in non-active chats.
      final chat = _chats.where((c) =>
          c.accountId == event.accountId && c.chatId == event.chatId).firstOrNull;
      onNotification!(
        event.message.senderName,
        event.message.contentText,
        chat?.title ?? '',
      );
    }
  }

  void _handleMsgEdited(MsgEditedEvent event) {
    if (_activeChat?.accountId != event.accountId || _activeChat?.chatId != event.chatId) return;
    final idx = _messages.indexWhere((m) => m.msgId == event.msgId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(
        contentText: event.newText,
        editedAt: event.editedAt,
      );
      notifyListeners();
    }
  }

  void _handleMsgDeleted(MsgDeletedEvent event) {
    if (_activeChat?.accountId != event.accountId || _activeChat?.chatId != event.chatId) return;
    _messages.removeWhere((m) => m.msgId == event.msgId);
    notifyListeners();
  }

  void _handleMsgStatus(MsgStatusEvent event) {
    if (_activeChat?.accountId != event.accountId || _activeChat?.chatId != event.chatId) return;
    final idx = _messages.indexWhere((m) =>
      m.msgId == event.msgId || (event.localId.isNotEmpty && m.localId == event.localId));
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(
        msgId: event.msgId.isNotEmpty ? event.msgId : null,
        status: MsgStatus.fromInt(event.status),
      );
      notifyListeners();
    }
  }

  void _handleTyping(TypingEvent event) {
    _typingUsers[event.chatId] = event.userName.isNotEmpty ? event.userName : event.userId;
    notifyListeners();

    // Clear typing after 6s.
    Future.delayed(const Duration(seconds: 6), () {
      if (_typingUsers[event.chatId] == (event.userName.isNotEmpty ? event.userName : event.userId)) {
        _typingUsers.remove(event.chatId);
        notifyListeners();
      }
    });
  }

  void _handleDownloadComplete(DownloadCompleteEvent event) {
    final idx = _messages.indexWhere((m) => m.msgId == event.msgId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(
        mediaLocalPath: event.localPath,
        mediaDownloadState: 2, // DownloadComplete
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
