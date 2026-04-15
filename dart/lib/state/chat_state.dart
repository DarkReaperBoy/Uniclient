import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';

/// Chat list + active chat + messages state.
class ChatState extends ChangeNotifier {
  final EngineService _engine;

  List<ChatInfo> _chats = [];
  ChatInfo? _activeChat;
  List<CachedMessage> _messages = [];
  bool _loadingMessages = false;
  bool _hasMoreMessages = true;
  final Map<String, String> _typingUsers = {}; // chatId → userName

  final List<StreamSubscription<dynamic>> _subs = [];

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
      if (event.state == 'connected') {
        loadChats();
      }
    }));
    // Also reload when auth finishes (finalizeAuth emits account_list).
    _subs.add(_engine.onAccountList.listen((_) {
      loadChats();
    }));
  }

  // ── Getters ──

  List<ChatInfo> get chats => _chats;
  ChatInfo? get activeChat => _activeChat;
  List<CachedMessage> get messages => _messages;
  bool get loadingMessages => _loadingMessages;
  bool get hasMoreMessages => _hasMoreMessages;

  String? typingUserFor(String chatId) => _typingUsers[chatId];

  /// Chats filtered by platform (empty = all).
  List<ChatInfo> chatsForPlatform(String platform) {
    if (platform.isEmpty) return _chats;
    return _chats.where((c) {
      // Platform prefix is the first part of accountId (e.g. "tg_abc123" → "tg")
      return c.accountId.startsWith(platform);
    }).toList();
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
    _engine.setActiveChat(chat.accountId, chat.chatId);
    _loadMessages();
    notifyListeners();
  }

  /// Close the active chat.
  void closeChat() {
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
  Future<String?> sendMessage(String text, {String replyToId = ''}) async {
    final chat = _activeChat;
    if (chat == null || text.trim().isEmpty) return null;

    // Generate temporary local ID for optimistic insert.
    final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistic insert.
    _messages.insert(0, CachedMessage(
      accountId: chat.accountId,
      chatId: chat.chatId,
      msgId: tempId,
      localId: tempId,
      contentText: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: MsgStatus.sending,
      replyToId: replyToId,
    ));
    notifyListeners();

    final localId = await _engine.sendMessage(chat.accountId, chat.chatId, text, replyToId: replyToId);
    return localId;
  }

  Future<void> editMessage(String msgId, String newText) async {
    final chat = _activeChat;
    if (chat == null) return;
    await _engine.editMessage(chat.accountId, chat.chatId, msgId, newText);
  }

  Future<void> deleteMessage(String msgId) async {
    final chat = _activeChat;
    if (chat == null) return;
    await _engine.deleteMessage(chat.accountId, chat.chatId, msgId);
  }

  void retryPending(String localId) {
    _engine.retryPending(localId);
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
  }

  void pinChat(String accountId, String chatId, bool pinned) {
    _engine.pinChat(accountId, chatId, pinned);
  }

  void archiveChat(String accountId, String chatId, bool archived) {
    _engine.archiveChat(accountId, chatId, archived);
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

  void _handleChatRemoved(String chatId) {
    _chats.removeWhere((c) => c.chatId == chatId);
    if (_activeChat?.chatId == chatId) {
      _activeChat = null;
      _messages = [];
    }
    notifyListeners();
  }

  void _handleMsgReceived(MsgReceivedEvent event) {
    if (_activeChat?.accountId == event.accountId && _activeChat?.chatId == event.chatId) {
      // Dedup: don't add if already present (e.g. optimistic insert).
      final exists = _messages.any((m) => m.msgId == event.message.msgId);
      if (!exists) {
        _messages.insert(0, event.message);
        notifyListeners();
      }
    }
  }

  void _handleMsgEdited(MsgEditedEvent event) {
    if (_activeChat?.accountId != event.accountId || _activeChat?.chatId != event.chatId) return;
    final idx = _messages.indexWhere((m) => m.msgId == event.msgId);
    if (idx >= 0) {
      final old = _messages[idx];
      _messages[idx] = CachedMessage(
        accountId: old.accountId,
        chatId: old.chatId,
        msgId: old.msgId,
        localId: old.localId,
        senderId: old.senderId,
        senderName: old.senderName,
        contentText: event.newText,
        timestamp: old.timestamp,
        editedAt: event.editedAt,
        status: old.status,
        replyToId: old.replyToId,
        replyPreview: old.replyPreview,
        forwardFrom: old.forwardFrom,
        isPinned: old.isPinned,
        hasMedia: old.hasMedia,
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
      final old = _messages[idx];
      _messages[idx] = CachedMessage(
        accountId: old.accountId,
        chatId: old.chatId,
        msgId: event.msgId.isNotEmpty ? event.msgId : old.msgId,
        localId: old.localId,
        senderId: old.senderId,
        senderName: old.senderName,
        contentText: old.contentText,
        timestamp: old.timestamp,
        editedAt: old.editedAt,
        status: MsgStatus.fromInt(event.status),
        replyToId: old.replyToId,
        replyPreview: old.replyPreview,
        forwardFrom: old.forwardFrom,
        isPinned: old.isPinned,
        hasMedia: old.hasMedia,
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

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
