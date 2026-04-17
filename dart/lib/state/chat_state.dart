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
  List<CachedMessage> _pinnedMessages = [];
  bool _loadingMessages = false;
  bool _hasMoreMessages = true;
  DateTime? _jumpedUntil; // suppress polling refresh until this time
  final Map<String, String> _typingUsers = {}; // chatId → userName
  final Map<String, bool> _onlineUsers = {}; // "accountId:chatId" → isOnline (DMs only)
  final Map<String, String> _senderAvatars = {}; // senderId → base64 avatar thumbnail

  // ── Folder state ──
  List<FolderInfo> _folders = [];
  String _foldersForAccount = ''; // which account the current _folders belong to
  String? _activeFolderId; // null = "All Chats"

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
        // Reload folders if this is the currently viewed account.
        if (event.accountId == _foldersForAccount) {
          loadFoldersForAccount(event.accountId);
        }
      }
    }));
    // Also reload when auth finishes (finalizeAuth emits account_list).
    _subs.add(_engine.onAccountList.listen((_) {
      _debouncedLoadChats();
    }));
    // Download complete → update message's local path in-memory.
    _subs.add(_engine.onDownloadComplete.listen(_handleDownloadComplete));
    // User status → track online/offline for DM avatar dots.
    _subs.add(_engine.onUserStatus.listen(_handleUserStatus));
  }

  // ── Getters ──

  List<ChatInfo> get chats => _chats;
  ChatInfo? get activeChat => _activeChat;
  int get openedUnreadCount => _openedUnreadCount;
  List<CachedMessage> get messages => _messages;
  List<CachedMessage> get pinnedMessages => _pinnedMessages;
  bool get loadingMessages => _loadingMessages;
  bool get hasMoreMessages => _hasMoreMessages;

  /// Active channel/topic within a topic-type group. Null = default/all.
  String? get activeChannelId => _activeChannelId;

  String? typingUserFor(String chatId) => _typingUsers[chatId];

  /// Get sender avatar base64 data by sender ID.
  String? senderAvatar(String senderId) => _senderAvatars[senderId];

  /// All loaded folders across accounts.
  List<FolderInfo> get folders => _folders;

  /// Active folder ID (null = "All Chats").
  String? get activeFolderId => _activeFolderId;

  /// Whether any folders exist (controls folder sidebar visibility).
  bool get hasFolders => _folders.isNotEmpty;

  /// Chats filtered by platform (empty = all).
  /// Account IDs use a 4-char prefix of the platform name (e.g. "tele_abc123"
  /// for "telegram"), so we match by that prefix.
  List<ChatInfo> chatsForPlatform(String platform) {
    if (platform.isEmpty) return _chats;
    final prefix = platform.length > 4 ? platform.substring(0, 4) : platform;
    return _chats.where((c) => c.accountId.startsWith(prefix)).toList();
  }

  /// Chats filtered by a specific account ID.
  List<ChatInfo> chatsForAccount(String accountId) {
    if (accountId.isEmpty) return _chats;
    return _chats.where((c) => c.accountId == accountId).toList();
  }

  /// Total unread count across all visible chats.
  int get totalUnread => _chats.fold(0, (sum, c) => sum + c.unreadCount);

  /// Chats filtered by active folder. Returns all chats if no folder active.
  /// Applies Telegram-style folder filtering: a chat is included if it's in
  /// the explicit include list OR matches any type filter flag, minus excludes.
  /// Scoped to the account the folders belong to.
  List<ChatInfo> chatsForFolder(String? folderId) {
    if (folderId == null) return _chats;
    final folder = _folders.where((f) => f.id == folderId).firstOrNull;
    if (folder == null) return _chats;

    final includeSet = folder.chatIds.toSet();
    final excludeSet = folder.excludeChatIds.toSet();
    final accountId = _foldersForAccount;

    return _chats.where((c) {
      // Scope to the folder's account.
      if (accountId.isNotEmpty && c.accountId != accountId) return false;

      // Always exclude explicitly excluded chats.
      if (excludeSet.contains(c.chatId)) return false;

      // Exclusion filters.
      if (folder.excludeMuted && c.isMuted) return false;
      if (folder.excludeRead && c.unreadCount == 0) return false;
      if (folder.excludeArchived && c.isArchived) return false;

      // Explicitly included chats always pass.
      if (includeSet.contains(c.chatId)) return true;

      // Type-based filters: include if chat matches any active flag.
      if (folder.hasTypeFilters) {
        if (folder.groups && c.type == ChatType.group) return true;
        if (folder.channels && c.type == ChatType.channel) return true;
        // For DMs: contacts, non_contacts, and bots all map to DM type.
        // We can't distinguish contact/non-contact/bot yet, so include
        // all DMs if any of these flags are set.
        if (c.type == ChatType.dm &&
            (folder.contacts || folder.nonContacts || folder.bots)) {
          return true;
        }
      }

      // If no type filters are set, only explicit includes match.
      return false;
    }).toList();
  }

  /// Unread count for a specific folder.
  int unreadCountForFolder(String? folderId) {
    return chatsForFolder(folderId).fold(0, (sum, c) => sum + c.unreadCount);
  }

  // ── Actions ──

  /// Set the active folder filter.
  void setActiveFolder(String? folderId) {
    _activeFolderId = folderId;
    notifyListeners();
  }

  /// Load folders for a specific account.
  Future<void> loadFoldersForAccount(String accountId) async {
    _foldersForAccount = accountId;
    _activeFolderId = null; // reset folder selection on account switch
    try {
      _folders = await _engine.getFolders(accountId);
    } catch (_) {
      _folders = [];
    }
    notifyListeners();
  }

  /// Called when the user switches active account.
  /// Clears active chat, resets folders, reloads folder list.
  void switchAccount(String accountId) {
    if (_foldersForAccount == accountId) return;
    _activeChat = null;
    _messages = [];
    _activeFolderId = null;
    _activeChannelId = null;
    _stopPolling();
    _engine.clearActiveChat();
    loadFoldersForAccount(accountId);
    notifyListeners();
  }

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
    _pinnedMessages = [];
    _hasMoreMessages = true;
    _jumpedUntil = null; // clear jump lock on chat change
    _activeChannelId = null; // reset channel selection on chat change
    _engine.setActiveChat(chat.accountId, chat.chatId);
    _loadMessages();
    _loadPinnedMessages(chat.accountId, chat.chatId);
    // Fetch member avatars for group chats.
    if (chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic) {
      _loadMemberAvatars(chat.accountId, chat.chatId);
    } else {
      _senderAvatars.clear();
    }
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
    _pinnedMessages = [];
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

  /// Jump to messages around a specific timestamp (for pinned message navigation).
  /// Loads a window of messages where the target is the newest (index 0 in reversed list).
  /// Suppresses polling refresh for 10 seconds so the user can read the jumped-to area.
  void jumpToMessage(int timestampMs) {
    final chat = _activeChat;
    if (chat == null) return;

    // getMessages returns messages with timestamp < beforeMs, newest first.
    // +1 ensures the target message itself is included as the first item.
    final around = _engine.getMessages(
      chat.accountId, chat.chatId,
      beforeMs: timestampMs + 1,
    );
    if (around.isNotEmpty) {
      _messages = around;
      _hasMoreMessages = true;
      // Suppress polling refresh so it doesn't immediately snap back to latest.
      _jumpedUntil = DateTime.now().add(const Duration(seconds: 10));
      notifyListeners();
    }
  }

  Future<void> forwardMessages(List<String> msgIds, String toChatId) async {
    final chat = _activeChat;
    if (chat == null) return;
    for (final id in msgIds) {
      await _engine.forwardMessage(chat.accountId, chat.chatId, id, toChatId);
    }
    // If forwarding to the active chat, refresh messages immediately.
    if (toChatId == chat.chatId) {
      _refreshMessages();
    }
    // Always refresh chat list so the destination chat's preview updates
    // and the forwarded message gets cached for when the user opens that chat.
    _debouncedLoadChats();
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

  void leaveChat(String accountId, String chatId) {
    _engine.leaveChat(accountId, chatId);
    // If this was the active chat, clear it.
    if (_activeChat?.accountId == accountId && _activeChat?.chatId == chatId) {
      _activeChat = null;
      _messages.clear();
    }
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
    _autoDownloadMedia(newMsgs);
    notifyListeners();
  }

  /// Fetch chat members and cache their avatar thumbnails for sender display.
  Future<void> _loadMemberAvatars(String accountId, String chatId) async {
    try {
      final members = await _engine.getChatMembers(accountId, chatId, limit: 200);
      for (final m in members) {
        if (m.avatarB64.isNotEmpty) {
          _senderAvatars[m.userId] = m.avatarB64;
        }
      }
      if (_senderAvatars.isNotEmpty) notifyListeners();
    } catch (_) {
      // Non-critical — avatars fall back to initials.
    }
  }

  void _loadPinnedMessages(String accountId, String chatId) {
    try {
      _pinnedMessages = _engine.getPinnedMessages(accountId, chatId);
    } catch (_) {
      _pinnedMessages = [];
    }
  }

  /// Re-fetch the latest messages for the active chat and merge.
  /// Used after send and as a periodic fallback for event delivery issues.
  void _refreshMessages() {
    if (_disposed) return;
    final chat = _activeChat;
    if (chat == null) return;

    // Don't overwrite jumped-to messages while the user is reading them.
    if (_jumpedUntil != null && DateTime.now().isBefore(_jumpedUntil!)) return;

    final fresh = _engine.getMessages(chat.accountId, chat.chatId, beforeMs: 0);
    if (fresh.isEmpty) return;

    // Merge: replace the newest portion of messages with fresh data.
    // Keep any older paginated messages that aren't in the fresh batch.
    final freshIds = fresh.map((m) => m.msgId).toSet();
    final older = _messages.where((m) => !freshIds.contains(m.msgId)).toList();
    // fresh is newest-first; older are already oldest-last from pagination.
    _messages = [...fresh, ...older.where((m) => m.timestamp < (fresh.last.timestamp))];
    _autoDownloadMedia(fresh);
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

  /// Auto-download photos and small media for visible messages.
  void _autoDownloadMedia(List<CachedMessage> msgs) {
    for (final m in msgs) {
      if (!m.hasMedia || m.mediaDownloadState != 0) continue;
      if (m.mediaLocalPath.isNotEmpty) continue;
      // Auto-download photos, stickers, GIFs, and small videos (<5MB).
      final autoTypes = {1, 6, 7}; // photo, sticker, gif
      if (autoTypes.contains(m.mediaType) ||
          (m.mediaType == 2 && m.mediaFileSize > 0 && m.mediaFileSize < 5 * 1024 * 1024)) {
        _engine.requestDownload(m.accountId, m.chatId, m.msgId);
      }
    }
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

  void _handleUserStatus(UserStatusEvent event) {
    if (_disposed) return;
    // For DMs, the user ID typically maps to the chat ID.
    final key = '${event.accountId}:${event.userId}';
    final prev = _onlineUsers[key];
    if (prev != event.isOnline) {
      _onlineUsers[key] = event.isOnline;
      notifyListeners();
    }
  }

  /// Whether a DM chat's peer is currently online.
  bool isChatOnline(ChatInfo chat) {
    if (chat.type != ChatType.dm) return false;
    return _onlineUsers['${chat.accountId}:${chat.chatId}'] ?? false;
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
