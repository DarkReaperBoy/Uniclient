import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';

/// Chat list + active chat + messages state.
class ChatState extends ChangeNotifier {
  final EngineService _engine;

  List<ChatInfo> _chats = [];
  ChatInfo? _activeChat;
  int _openedUnreadCount = 0; // unread count at time chat was opened
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
  Timer? _loadChatsDebounce;
  bool _disposed = false;

  ChatState(this._engine) {
    // Snapshot events are per-account; reload the unified list from SQLite
    // so that one account's sync doesn't erase another's chats.
    _subs.add(_engine.onChatSnapshot.listen((_) {
      _debouncedLoadChats();
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
      if (event.state == 'connected') {
        _debouncedLoadChats();
      }
    }));
    // Also reload when auth finishes (finalizeAuth emits account_list).
    _subs.add(_engine.onAccountList.listen((_) {
      _debouncedLoadChats();
    }));
    // Download complete → update message's local path in-memory.
    _subs.add(_engine.onDownloadComplete.listen(_handleDownloadComplete));
  }

  // ── Getters ──

  List<ChatInfo> get chats => _chats;
  ChatInfo? get activeChat => _activeChat;
  int get openedUnreadCount => _openedUnreadCount;
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

  /// Merge a chat into the in-memory list (upsert). Used when forum topics
  /// are fetched on demand and need to appear in the chat list.
  void mergeChat(ChatInfo chat) {
    final idx = _chats.indexWhere((c) => c.accountId == chat.accountId && c.chatId == chat.chatId);
    if (idx >= 0) {
      _chats[idx] = chat;
    } else {
      _chats.add(chat);
    }
    // Don't notify per-item — caller should call notifyListeners() after batch.
  }

  /// Notify listeners after batch mergeChat calls.
  void notifyMerged() => notifyListeners();

  /// Load the chat list from engine.
  void loadChats({String accountId = '', bool archived = false}) {
    if (_disposed) return;
    // Use a large limit for unified list so all accounts' chats are included.
    _chats = _engine.getChatList(accountId: accountId, archived: archived, limit: 500);
    notifyListeners();
  }

  /// Debounced version of loadChats — coalesces rapid event-driven reloads.
  void _debouncedLoadChats() {
    _loadChatsDebounce?.cancel();
    _loadChatsDebounce = Timer(const Duration(milliseconds: 300), () {
      loadChats();
    });
  }

  /// Open a chat — loads messages and sets as active.
  void openChat(ChatInfo chat) {
    _activeChat = chat;
    _openedUnreadCount = chat.unreadCount;
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
    _openedUnreadCount = 0;
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
    // Try to find latest message ID if available (active chat only).
    final chatMsgs = _messages.where((m) => m.accountId == accountId && m.chatId == chatId);
    final upToId = chatMsgs.isNotEmpty ? chatMsgs.first.msgId : '';
    // Engine always resets unread count in DB; only calls core.MarkAsRead if upToId is non-empty.
    _engine.markChatRead(accountId, chatId, upToId);
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
    if (_disposed) return;
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
    if (_disposed) return;
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
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _handleChatUpdated(ChatInfo updated) {
    if (_disposed) return;
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
    if (_disposed) return;
    _chats.removeWhere((c) => c.chatId == event.chatId && (event.accountId.isEmpty || c.accountId == event.accountId));
    if (_activeChat?.chatId == event.chatId && (event.accountId.isEmpty || _activeChat?.accountId == event.accountId)) {
      _activeChat = null;
      _messages = [];
    }
    notifyListeners();
  }

  // Rate-limit notifications: max 1 per chat per 5 seconds, max 3 total per 5 seconds.
  final Map<String, DateTime> _lastNotifPerChat = {};
  final List<DateTime> _recentNotifs = [];

  void _handleMsgReceived(MsgReceivedEvent event) {
    if (_disposed) return;
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
      final chatKey = '${event.accountId}:${event.chatId}';
      final chat = _chats.where((c) =>
          c.accountId == event.accountId && c.chatId == event.chatId).firstOrNull;

      // Skip muted chats.
      if (chat != null && chat.isMuted) return;

      // Rate limit: max 1 notification per chat per 5 seconds.
      final now = DateTime.now();
      final lastForChat = _lastNotifPerChat[chatKey];
      if (lastForChat != null && now.difference(lastForChat).inSeconds < 5) return;

      // Global rate limit: max 3 notifications per 5 seconds.
      _recentNotifs.removeWhere((t) => now.difference(t).inSeconds > 5);
      if (_recentNotifs.length >= 3) return;

      _lastNotifPerChat[chatKey] = now;
      _recentNotifs.add(now);

      onNotification!(
        event.message.senderName,
        event.message.contentText,
        chat?.title ?? '',
      );
    }
  }

  void _handleMsgEdited(MsgEditedEvent event) {
    if (_disposed) return;
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
    if (_disposed) return;
    if (_activeChat?.accountId != event.accountId || _activeChat?.chatId != event.chatId) return;
    _messages.removeWhere((m) => m.msgId == event.msgId);
    notifyListeners();
  }

  void _handleMsgStatus(MsgStatusEvent event) {
    if (_disposed) return;
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
    if (_disposed) return;
    _typingUsers[event.chatId] = event.userName.isNotEmpty ? event.userName : event.userId;
    notifyListeners();

    // Clear typing after 6s (guard against notifyListeners after dispose).
    Future.delayed(const Duration(seconds: 6), () {
      if (_disposed) return;
      if (_typingUsers[event.chatId] == (event.userName.isNotEmpty ? event.userName : event.userId)) {
        _typingUsers.remove(event.chatId);
        notifyListeners();
      }
    });
  }

  void _handleDownloadComplete(DownloadCompleteEvent event) {
    if (_disposed) return;
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
    _disposed = true;
    _stopPolling();
    _loadChatsDebounce?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
