import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../ui/message_bubble.dart';

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
  // "accountId:userId" → (kind, lastSeenMs) for DM subtitle text.
  final Map<String, ({String kind, int lastSeenMs})> _userLastSeen = {};
  final Map<String, String> _senderAvatars = {}; // senderId → base64 avatar thumbnail
  int _groupOnlineCount = 0; // online members in active group/channel chat
  GroupCallInfo? _activeGroupCall; // active group call in current chat
  int _scheduledCount = 0;
  bool _isScheduledView = false;

  // ── Archive state ──
  bool _hasArchivedChats = false;

  // ── Pinned chat order (drag-to-reorder, spec §2.7) ──
  // Key: accountId, Value: ordered list of pinned chat IDs.
  final Map<String, List<String>> _pinnedChatOrders = {};

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
        // Fetch extended peer name color palette (help.peerColors).
        _fetchPeerColors(event.accountId);
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
    // Group call state → update active group call bar.
    _subs.add(_engine.onGroupCallState.listen(_handleGroupCallState));
  }

  // Accounts for which we've already fetched peer colors.
  final Set<String> _peerColorsFetched = {};

  /// Fetch extended peer name colors (help.peerColors) from the engine.
  void _fetchPeerColors(String accountId) {
    if (_peerColorsFetched.contains(accountId)) return;
    _peerColorsFetched.add(accountId);
    _engine.getPeerColors(accountId).then((colors) {
      if (colors.isNotEmpty) {
        // Import into the static palette used by MessageBubble.
        // Use dynamic import to avoid circular dependency.
        MessageBubble.loadPeerColors(colors);
      }
    }).catchError((_) {
      // Non-fatal: extended colors are optional, base 8 still works.
      _peerColorsFetched.remove(accountId);
    });
  }

  // ── Getters ──

  List<ChatInfo> get chats => _chats;
  ChatInfo? get activeChat => _activeChat;
  int get openedUnreadCount => _openedUnreadCount;
  List<CachedMessage> get messages => _messages;
  List<CachedMessage> get pinnedMessages => _pinnedMessages;
  GroupCallInfo? get activeGroupCall => _activeGroupCall;
  bool get loadingMessages => _loadingMessages;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get hasArchivedChats => _hasArchivedChats;

  /// Active channel/topic within a topic-type group. Null = default/all.
  String? get activeChannelId => _activeChannelId;

  String? typingUserFor(String chatId) => _typingUsers[chatId];

  ReplyKeyboardData? get activeReplyKeyboard {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.keyboardHide) return null;
      if (m.hasReplyKeyboard) return m.replyKeyboard;
    }
    return null;
  }

  String? _hiddenKeyboardMsgId;

  void hideReplyKeyboard(String msgId) {
    _hiddenKeyboardMsgId = msgId;
    notifyListeners();
  }

  ReplyKeyboardData? get visibleReplyKeyboard {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.keyboardHide) return null;
      if (m.hasReplyKeyboard) {
        if (_hiddenKeyboardMsgId == m.msgId) return null;
        return m.replyKeyboard;
      }
    }
    return null;
  }

  /// Get sender avatar base64 data by sender ID.
  String? senderAvatar(String senderId) => _senderAvatars[senderId];

  /// Online member count for the active group/channel chat.
  int get groupOnlineCount => _groupOnlineCount;

  int get scheduledCount => _scheduledCount;
  bool get isScheduledView => _isScheduledView;

  void toggleScheduledView() {
    _isScheduledView = !_isScheduledView;
    if (_isScheduledView) {
      _loadScheduledMessages();
    } else {
      _loadMessages();
    }
    notifyListeners();
  }

  Future<void> _loadScheduledMessages() async {
    final chat = _activeChat;
    if (chat == null) return;
    try {
      final msgs = await _engine.getScheduledMessages(chat.accountId, chat.chatId);
      if (_activeChat?.chatId == chat.chatId && _isScheduledView) {
        _messages = msgs;
        _hasMoreMessages = false;
        notifyListeners();
      }
    } catch (_) {
      _messages = [];
      notifyListeners();
    }
  }

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

  /// Unread count summed across a single account's chats.
  /// Used by the folder sidebar's "All" tab badge.
  int unreadCountForAccount(String accountId) {
    if (accountId.isEmpty) return 0;
    return _chats
        .where((c) => c.accountId == accountId && !c.isArchived)
        .fold(0, (sum, c) => sum + c.unreadCount);
  }

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

  /// Whether ALL unreads in a folder are from muted chats.
  /// Returns true if every chat with unreads is muted (badge should be gray).
  /// Returns false if any chat with unreads is unmuted (badge should be blue).
  bool isFolderUnreadAllMuted(String? folderId) {
    final folderChats = chatsForFolder(folderId);
    return folderChats
        .where((c) => c.unreadCount > 0)
        .every((c) => c.isMuted);
  }

  /// Whether ALL unreads for an account are from muted chats.
  bool isAccountUnreadAllMuted(String accountId) {
    if (accountId.isEmpty) return true;
    return _chats
        .where((c) => c.accountId == accountId && !c.isArchived && c.unreadCount > 0)
        .every((c) => c.isMuted);
  }

  // ── Actions ──

  /// Set the active folder filter.
  void setActiveFolder(String? folderId) {
    _activeFolderId = folderId;
    notifyListeners();
  }

  /// Delete a folder by its ID. Resets active folder to "All" if the deleted
  /// folder was active, then reloads the folder list from the engine.
  Future<void> deleteFolder(String accountId, String folderId) async {
    try {
      await _engine.deleteFolder(accountId, folderId);
    } catch (_) {
      // Engine error — folder might already be gone; still refresh.
    }
    if (_activeFolderId == folderId) {
      _activeFolderId = null;
    }
    _folders.removeWhere((f) => f.id == folderId);
    notifyListeners();
    // Reload from server to stay in sync.
    await loadFoldersForAccount(accountId);
  }

  /// Reorder folders locally (drag-and-drop in folder sidebar).
  void reorderFolders(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _folders.length) return;
    if (newIndex < 0 || newIndex > _folders.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = _folders.removeAt(oldIndex);
    _folders.insert(newIndex, item);
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
    // Update archive presence: check loaded chats first, then probe engine.
    _hasArchivedChats = _chats.any((c) => c.isArchived) ||
        _engine.getChatList(archived: true, limit: 1).isNotEmpty;
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
    _hiddenKeyboardMsgId = null;
    _engine.setActiveChat(chat.accountId, chat.chatId);
    _loadMessages();
    _loadPinnedMessages(chat.accountId, chat.chatId);
    // Fetch member avatars and online count for group chats.
    _groupOnlineCount = 0;
    _activeGroupCall = null;
    _scheduledCount = 0;
    _isScheduledView = false;
    _loadScheduledCount(chat.accountId, chat.chatId);
    if (chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic) {
      _loadMemberAvatars(chat.accountId, chat.chatId);
      _loadOnlineCount(chat.accountId, chat.chatId);
      _loadGroupCall(chat.accountId, chat.chatId);
    } else {
      _senderAvatars.clear();
    }
    _startPolling();
    notifyListeners();
  }

  void openChatById(String chatId) {
    final chat = _chats.firstWhere(
      (c) => c.chatId == chatId,
      orElse: () => _chats.first,
    );
    if (chat.chatId == chatId) openChat(chat);
  }

  /// Select a channel/topic within the active topic-type group.
  /// Pass null to deselect (show default/all).
  void setActiveChannel(String? channelId) {
    _activeChannelId = channelId;
    notifyListeners();
  }

  /// Clear the unread bar (e.g. when user scrolls to bottom).
  void clearOpenedUnread() {
    if (_openedUnreadCount > 0) {
      _openedUnreadCount = 0;
      notifyListeners();
    }
  }

  /// Close the active chat.
  void closeChat() {
    _stopPolling();
    _activeChat = null;
    _openedUnreadCount = 0;
    _messages = [];
    _pinnedMessages = [];
    _activeGroupCall = null;
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
  Future<String?> sendMessage(String text, {String replyToId = '', String entities = '', bool silent = false}) async {
    final chat = _activeChat;
    if (chat == null || text.trim().isEmpty) return null;

    final localId = await _engine.sendMessage(chat.accountId, chat.chatId, text, replyToId: replyToId, entities: entities, silent: silent);

    // Refresh messages — Go inserted the optimistic message into cache,
    // so re-fetching picks it up even if the event callback didn't fire.
    _refreshMessages();

    return localId;
  }

  Future<String?> uploadFile(String filePath, {String caption = ''}) async {
    final chat = _activeChat;
    if (chat == null) return null;
    final msgId = await _engine.uploadFile(chat.accountId, chat.chatId, filePath, caption: caption);
    _refreshMessages();
    return msgId;
  }

  Future<void> editMessage(String msgId, String newText, {String entities = ''}) async {
    final chat = _activeChat;
    if (chat == null) return;
    await _engine.editMessage(chat.accountId, chat.chatId, msgId, newText, entities: entities);
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

  /// Whether the message list is in a "jumped" state (not showing latest messages).
  bool get isJumped => _jumpedUntil != null && DateTime.now().isBefore(_jumpedUntil!);

  /// Return to the latest messages (undo jumpToMessage).
  void returnToLatest() {
    final chat = _activeChat;
    if (chat == null) return;
    _jumpedUntil = null;
    _messages = [];
    _hasMoreMessages = true;
    _loadMessages();
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

  Future<void> sendScheduledNow(List<String> msgIds) async {
    final chat = _activeChat;
    if (chat == null) return;
    await _engine.sendScheduledNow(chat.accountId, chat.chatId, msgIds);
    _messages.removeWhere((m) => msgIds.contains(m.msgId));
    notifyListeners();
  }

  /// Pin or unpin a message in the active chat. Optimistically flips
  /// `isPinned` on the cached message so the context menu label and any
  /// pin-dependent UI update immediately, without waiting for the engine
  /// event round-trip.
  Future<void> pinMessage(String msgId, bool pinned) async {
    final chat = _activeChat;
    if (chat == null) return;
    await _engine.pinMessage(chat.accountId, chat.chatId, msgId, pinned);
    final idx = _messages.indexWhere((m) => m.msgId == msgId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(isPinned: pinned);
      notifyListeners();
    }
  }

  Future<String> botCallback(String msgId, String data) async {
    final chat = _activeChat;
    if (chat == null) return '';
    return _engine.botCallback(chat.accountId, chat.chatId, msgId, data);
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
    // Invalidate custom pin order so it gets rebuilt from fresh data.
    _pinnedChatOrders.remove(accountId);
    loadChats();
  }

  /// Get the custom pinned chat order for an account, or null if default.
  List<String>? pinnedChatOrder(String accountId) =>
      _pinnedChatOrders[accountId];

  /// Reorder pinned chats (drag-to-reorder, spec §2.7).
  /// [oldIndex] and [newIndex] are indices within the pinned-only sublist.
  void reorderPinnedChats(String accountId, int oldIndex, int newIndex) {
    final order = _pinnedChatOrders[accountId];
    if (order == null || oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex < 0 || newIndex >= order.length) return;
    if (oldIndex == newIndex) return;
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    notifyListeners();
  }

  /// Initialize pinned chat order for an account from the current chat list.
  /// Merges: keeps existing custom order, adds new pinned chats, removes gone.
  void ensurePinnedOrder(String accountId) {
    final pinned = _chats
        .where((c) => c.accountId == accountId && c.isPinned && !c.isArchived)
        .toList()
      ..sort((a, b) => b.lastMsgTime.compareTo(a.lastMsgTime));
    final currentIds = pinned.map((c) => c.chatId).toList();

    final existing = _pinnedChatOrders[accountId];
    if (existing == null) {
      _pinnedChatOrders[accountId] = currentIds;
      return;
    }
    // Keep existing order, add new, remove gone.
    final currentSet = currentIds.toSet();
    final newOrder = existing.where((id) => currentSet.contains(id)).toList();
    for (final id in currentIds) {
      if (!newOrder.contains(id)) newOrder.add(id);
    }
    _pinnedChatOrders[accountId] = newOrder;
  }

  void archiveChat(String accountId, String chatId, bool archived) {
    _engine.archiveChat(accountId, chatId, archived);
    loadChats();
  }

  Future<void> blockUser(String accountId, String userId) async {
    await _engine.blockUser(accountId, userId);
    loadChats();
  }

  Future<void> unblockUser(String accountId, String userId) async {
    await _engine.unblockUser(accountId, userId);
    loadChats();
  }

  Future<void> addContact(String accountId, String phone, String firstName, String lastName) async {
    await _engine.addContact(accountId, phone, firstName, lastName);
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

  void clearHistory(String accountId, String chatId) {
    _engine.clearHistory(accountId, chatId);
    // If this is the active chat, clear local messages.
    if (_activeChat?.accountId == accountId && _activeChat?.chatId == chatId) {
      _messages.clear();
      notifyListeners();
    }
    loadChats();
  }

  void deleteChat(String accountId, String chatId) {
    _engine.deleteChat(accountId, chatId);
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

  /// Mark all chats for an account as read (spec §3.2: "Mark-As-Read" context menu).
  void markAllChatsReadForAccount(String accountId) {
    final accountChats = _chats.where(
      (c) => c.accountId == accountId && c.unreadCount > 0,
    );
    for (final chat in accountChats) {
      _engine.markChatRead(accountId, chat.chatId, '');
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
  /// Paginates through all members to cover large groups.
  Future<void> _loadMemberAvatars(String accountId, String chatId) async {
    try {
      const batchSize = 200;
      var offset = 0;
      var fetched = 0;
      do {
        final members = await _engine.getChatMembers(accountId, chatId, limit: batchSize, offset: offset);
        fetched = members.length;
        for (final m in members) {
          if (m.avatarB64.isNotEmpty) {
            _senderAvatars[m.userId] = m.avatarB64;
          }
        }
        offset += fetched;
        // Stop after first batch if we got fewer than requested (no more pages).
        // Also cap at 1000 to avoid hammering huge channels.
      } while (fetched >= batchSize && offset < 1000);
      if (_senderAvatars.isNotEmpty) notifyListeners();
    } catch (_) {
      // Non-critical — avatars fall back to initials.
    }
  }

  /// Fetch the online member count for a group/channel via the platform API.
  Future<void> _loadOnlineCount(String accountId, String chatId) async {
    try {
      final count = await _engine.getOnlineCount(accountId, chatId);
      if (count != _groupOnlineCount) {
        _groupOnlineCount = count;
        notifyListeners();
      }
    } catch (_) {
      // Non-critical — subtitle falls back to "X members" without online count.
    }
  }

  void _loadPinnedMessages(String accountId, String chatId) {
    try {
      _pinnedMessages = _engine.getPinnedMessages(accountId, chatId);
    } catch (_) {
      _pinnedMessages = [];
    }
  }

  Future<void> _loadScheduledCount(String accountId, String chatId) async {
    try {
      final count = await _engine.getScheduledCount(accountId, chatId);
      if (_activeChat?.chatId == chatId) {
        _scheduledCount = count;
        notifyListeners();
      }
    } catch (_) {
      _scheduledCount = 0;
    }
  }

  Future<void> _loadGroupCall(String accountId, String chatId) async {
    try {
      _activeGroupCall = await _engine.getGroupCall(accountId, chatId);
      notifyListeners();
    } catch (_) {
      _activeGroupCall = null;
    }
  }

  void _handleGroupCallState(GroupCallStateEvent event) {
    final chat = _activeChat;
    if (chat == null) return;
    // Only process events for the currently active chat.
    if (event.info.chatId != chat.chatId) return;
    _activeGroupCall = event.info.active ? event.info : null;
    notifyListeners();
  }

  /// Join the active group call in the current chat.
  Future<void> joinGroupCall() async {
    final chat = _activeChat;
    if (chat == null || _activeGroupCall == null) return;
    try {
      await _engine.joinGroupCall(chat.accountId, chat.chatId);
    } catch (e) {
      // TODO: show error to user
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
      var updated = _messages[idx].copyWith(
        contentText: event.newText,
        editedAt: event.editedAt,
      );
      final extra = event.contentRaw?['extra'] as Map<String, dynamic>?;
      if (extra != null) {
        updated = updated.copyWith(
          wpUrl: extra['wp_url'] as String? ?? '',
          wpSiteName: extra['wp_site_name'] as String? ?? '',
          wpTitle: extra['wp_title'] as String? ?? '',
          wpDescription: extra['wp_description'] as String? ?? '',
          wpType: extra['wp_type'] as String? ?? '',
          wpThumbB64: extra['wp_thumb_b64'] as String? ?? '',
          wpForceLargeMedia: extra['wp_force_large_media'] == true,
          wpForceSmallMedia: extra['wp_force_small_media'] == true,
          wpHasLargeMedia: extra['wp_has_large_media'] == true,
          wpPhotoW: (extra['wp_photo_w'] as num?)?.toInt() ?? 0,
          wpPhotoH: (extra['wp_photo_h'] as num?)?.toInt() ?? 0,
          wpDuration: (extra['wp_duration'] as num?)?.toInt() ?? 0,
        );
      }
      _messages[idx] = updated;
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

  void requestDownload(CachedMessage msg) {
    if (msg.mediaDownloadState == 1) return;
    final idx = _messages.indexWhere((m) => m.msgId == msg.msgId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(mediaDownloadState: 1);
      notifyListeners();
    }
    _engine.requestDownload(msg.accountId, msg.chatId, msg.msgId);
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
    final prevOnline = _onlineUsers[key];
    final prevLastSeen = _userLastSeen[key];
    final newLastSeen = (kind: event.lastSeenKind, lastSeenMs: event.lastSeenMs);
    var changed = false;
    if (prevOnline != event.isOnline) {
      _onlineUsers[key] = event.isOnline;
      changed = true;
    }
    if (prevLastSeen?.kind != newLastSeen.kind ||
        prevLastSeen?.lastSeenMs != newLastSeen.lastSeenMs) {
      _userLastSeen[key] = newLastSeen;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Whether a DM chat's peer is currently online.
  bool isChatOnline(ChatInfo chat) {
    if (chat.type != ChatType.dm) return false;
    return _onlineUsers['${chat.accountId}:${chat.chatId}'] ?? false;
  }

  /// Last-seen descriptor for a DM's peer: (kind, lastSeenMs).
  /// kind ∈ {"", "online", "recently", "within_week", "within_month",
  /// "long_ago", "exact", "hidden"}. Empty kind means unknown.
  ({String kind, int lastSeenMs}) chatLastSeen(ChatInfo chat) {
    if (chat.type != ChatType.dm) return (kind: '', lastSeenMs: 0);
    return _userLastSeen['${chat.accountId}:${chat.chatId}'] ??
        (kind: '', lastSeenMs: 0);
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
