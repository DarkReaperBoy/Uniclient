import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../notifications/notification_types.dart';
import '../state/app_state.dart';
import '../ui/message_bubble.dart';
import '../ui/spoiler_animation.dart';

/// Chat list + active chat + messages state.
class ChatState extends ChangeNotifier {
  final EngineService _engine;
  final AppState _appState;

  List<ChatInfo> _chats = [];
  ChatInfo? _activeChat;
  int _openedUnreadCount = 0; // unread count at time chat was opened
  void Function(CachedMessage msg)? onNewActiveMessage;
  List<CachedMessage> _messages = [];
  List<CachedMessage> _pinnedMessages = [];
  bool _loadingMessages = false;
  bool _hasMoreMessages = true;
  bool _isFirstLoad = true;
  DateTime? _jumpedUntil; // suppress polling refresh until this time
  final Map<String, String> _typingUsers = {}; // chatId → userName
  final Map<String, bool> _onlineUsers = {}; // "accountId:chatId" → isOnline (DMs only)
  // "accountId:userId" → (kind, lastSeenMs) for DM subtitle text.
  final Map<String, ({String kind, int lastSeenMs})> _userLastSeen = {};
  final Map<String, String> _senderAvatars = {}; // senderId → base64 avatar thumbnail
  final Map<String, String> _altQualityPaths = {}; // "msgId:seq" → local path
  final Map<String, DownloadProgressEvent> _downloadProgress = {}; // msgId → latest progress
  int _groupOnlineCount = 0; // online members in active group/channel chat
  GroupCallInfo? _activeGroupCall; // active group call in current chat
  PersonalCallInfo? _activePersonalCall; // active 1:1 call
  int _scheduledCount = 0;
  bool _isScheduledView = false;
  String _linkedChatId = '';

  // ── Edit history view (§52.4) ──
  bool _isEditHistoryView = false;
  String _editHistoryMsgId = '';
  String _editHistorySenderName = '';

  // ── Archive state ──
  bool _hasArchivedChats = false;

  // ── Pinned chat order (drag-to-reorder, spec §2.7) ──
  // Key: accountId, Value: ordered list of pinned chat IDs.
  final Map<String, List<String>> _pinnedChatOrders = {};

  // ── Folder state ──
  List<FolderInfo> _folders = [];
  String _foldersForAccount = ''; // which account the current _folders belong to
  String? _activeFolderId; // null = "All Chats"
  bool _showFolderTags = false;
  bool _useVerticalFilters = true;

  void Function(NotificationData data)? onNotification;

  /// Active channel/topic ID within a topic-type group.
  /// Null means "show all" (the default channel).
  String? _activeChannelId;

  // ── Forum topic list state (§22.3) ──
  List<ForumTopic> _forumTopics = [];
  ChatInfo? _forumParentChat;
  String? _activeTopicId;
  final Set<String> _forumViewAsMessages = {};
  bool _forumHasMore = false;
  bool _forumLoadingMore = false;
  bool _forumFirstLoadDone = false;

  // §22.4: Recent topic names for forum chats (up to 8), keyed by "accountId:chatId".
  final Map<String, List<ForumTopic>> _forumRecentTopics = {};
  final Set<String> _forumTopicsFetching = {};

  // §31.2–31.5: Saved Messages sublist state with pagination.
  List<SavedSublistInfo> _pinnedSublists = [];
  List<SavedSublistInfo> _regularSublists = [];
  bool _isViewingSavedSublists = false;
  int _savedSublistsTotalCount = 0;
  bool _savedSublistsLoading = false;
  bool _savedSublistsLoadingMore = false;
  bool _savedSublistsHasMore = true;
  int _savedSublistsOffsetDate = 0;
  int _savedSublistsOffsetId = 0;
  bool _savedSublistsFirstLoad = true;
  SavedSublistInfo? _activeSublist;
  List<SavedSublistInfo> _recentSublists = [];
  static const _kFirstPerPage = 10;
  static const _kPerPage = 50;
  static const _kLoadedSublistsMinCount = 20;
  static const _kRecentSublistsMax = 6;

  // §31.6–31.7: Saved reaction tags + selection state
  List<SavedReactionTagInfo> _savedReactionTags = [];
  bool _savedReactionTagsLoading = false;
  final Set<String> _selectedReactionTagIds = {};

  // §24.5: Recently opened chats for Ctrl+Tab switcher overlay.
  final List<String> _chatOpenHistory = []; // chatId list, most-recent first
  static const _maxChatOpenHistory = 30;

  // ── Business bot bar state (§30.11) ──
  ConnectedBotInfo? _connectedBot;
  bool _connectedBotPaused = false;
  final Map<String, List<ConnectedBotInfo>> _connectedBotsCache = {};

  // ── Bot start token (§47: deep link t.me/bot?start=TOKEN) ──
  String _botStartToken = '';

  // ── Export top bar state (§29.9) ──
  bool _exportActive = false;
  String _exportStepLabel = '';
  String _exportInfoText = '';
  double _exportProgress = 0.0;
  VoidCallback? _exportOnTap;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _pollTimer;
  Timer? _loadChatsDebounce;
  bool _disposed = false;

  ChatState(this._engine, this._appState) {
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
    // Download progress → track bytes received for radial indicators.
    _subs.add(_engine.onDownloadProgress.listen(_handleDownloadProgress));
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
  List<String> get chatOpenHistory => List.unmodifiable(_chatOpenHistory);

  List<ChatInfo> collectChatOpenHistory() {
    final result = <ChatInfo>[];
    for (final cid in _chatOpenHistory) {
      final chat = _chats.where((c) => c.chatId == cid).firstOrNull;
      if (chat != null) result.add(chat);
    }
    return result;
  }
  int get openedUnreadCount => _openedUnreadCount;
  List<CachedMessage> get messages => _messages;
  List<CachedMessage> get pinnedMessages => _pinnedMessages;
  GroupCallInfo? get activeGroupCall => _activeGroupCall;
  PersonalCallInfo? get activePersonalCall => _activePersonalCall;

  void setActivePersonalCall(PersonalCallInfo? info) {
    _activePersonalCall = info;
    notifyListeners();
  }
  ConnectedBotInfo? get connectedBot => _connectedBot;
  bool get connectedBotPaused => _connectedBotPaused;
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

  // ── Bot start token (§47) ──
  String get botStartToken => _botStartToken;
  set botStartToken(String v) {
    if (_botStartToken != v) {
      _botStartToken = v;
      notifyListeners();
    }
  }

  // ── Export top bar getters (§29.9) ──
  bool get exportActive => _exportActive;
  String get exportStepLabel => _exportStepLabel;
  String get exportInfoText => _exportInfoText;
  double get exportProgress => _exportProgress;
  VoidCallback? get exportOnTap => _exportOnTap;

  void startExportBar({required VoidCallback onTap}) {
    _exportActive = true;
    _exportStepLabel = 'Initializing';
    _exportInfoText = '';
    _exportProgress = 0.0;
    _exportOnTap = onTap;
    notifyListeners();
  }

  void updateExportBar({
    required String stepLabel,
    required String infoText,
    required double progress,
  }) {
    _exportStepLabel = stepLabel;
    _exportInfoText = infoText;
    _exportProgress = progress;
    notifyListeners();
  }

  void stopExportBar() {
    _exportActive = false;
    _exportStepLabel = '';
    _exportInfoText = '';
    _exportProgress = 0.0;
    _exportOnTap = null;
    notifyListeners();
  }

  // ── Forum topic list getters (§22.3) ──
  List<ForumTopic> get forumTopics => _forumTopics;
  ChatInfo? get forumParentChat => _forumParentChat;
  bool get isViewingForum => _forumParentChat != null && !isForumViewAsMessages;
  String? get activeTopicId => _activeTopicId;
  bool get forumHasMore => _forumHasMore;
  bool get forumLoadingMore => _forumLoadingMore;
  bool get forumFirstLoadDone => _forumFirstLoadDone;

  bool get isForumViewAsMessages {
    final chat = _forumParentChat;
    if (chat == null) return false;
    return _forumViewAsMessages.contains('${chat.accountId}:${chat.chatId}');
  }

  // §31.2–31.5: Saved sublists getters
  List<SavedSublistInfo> get savedSublists {
    final pinnedIds = _pinnedSublists.map((s) => s.peerId).toSet();
    final deduped = _regularSublists.where((s) => !pinnedIds.contains(s.peerId)).toList();
    return [..._pinnedSublists, ...deduped];
  }
  List<SavedSublistInfo> get pinnedSublists => _pinnedSublists;
  List<SavedSublistInfo> get recentSublists => _recentSublists;
  bool get isViewingSavedSublists => _isViewingSavedSublists;
  int get savedSublistsTotalCount => _savedSublistsTotalCount;
  bool get savedSublistsLoading => _savedSublistsLoading;
  bool get savedSublistsLoadingMore => _savedSublistsLoadingMore;
  bool get savedSublistsHasMore => _savedSublistsHasMore;
  SavedSublistInfo? get activeSublist => _activeSublist;

  // §31.6–31.7: Reaction tags getters + selection
  List<SavedReactionTagInfo> get savedReactionTags => _savedReactionTags;
  bool get savedReactionTagsLoading => _savedReactionTagsLoading;
  Set<String> get selectedReactionTagIds => Set.unmodifiable(_selectedReactionTagIds);

  String _reactionTagKey(SavedReactionTagInfo tag) =>
      tag.isCustomEmoji ? 'custom:${tag.customId}' : 'emoji:${tag.emoji}';

  void toggleReactionTag(SavedReactionTagInfo tag, {bool multiSelect = false}) {
    final key = _reactionTagKey(tag);
    if (!multiSelect) {
      if (_selectedReactionTagIds.contains(key) && _selectedReactionTagIds.length == 1) {
        _selectedReactionTagIds.clear();
      } else {
        _selectedReactionTagIds.clear();
        _selectedReactionTagIds.add(key);
      }
    } else {
      if (_selectedReactionTagIds.contains(key)) {
        _selectedReactionTagIds.remove(key);
      } else {
        _selectedReactionTagIds.add(key);
      }
    }
    notifyListeners();
  }

  void clearReactionTagSelection() {
    if (_selectedReactionTagIds.isNotEmpty) {
      _selectedReactionTagIds.clear();
      notifyListeners();
    }
  }

  bool isReactionTagSelected(SavedReactionTagInfo tag) =>
      _selectedReactionTagIds.contains(_reactionTagKey(tag));

  void toggleForumViewAsMessages() {
    final chat = _forumParentChat;
    if (chat == null) return;
    final key = '${chat.accountId}:${chat.chatId}';
    if (_forumViewAsMessages.contains(key)) {
      _forumViewAsMessages.remove(key);
      openForum(chat);
    } else {
      _forumViewAsMessages.add(key);
      _activeTopicId = null;
      openChat(chat);
    }
  }

  Set<String> get forumViewAsMessagesKeys => Set.unmodifiable(_forumViewAsMessages);

  void loadForumViewPrefs(Set<String> keys) {
    _forumViewAsMessages.addAll(keys);
  }

  void goBackFromTopic() {
    if (_activeTopicId != null) {
      _activeTopicId = null;
      closeChat();
    } else {
      closeForum();
    }
  }

  List<ForumTopic> recentTopicsFor(String accountId, String chatId) {
    final key = '$accountId:$chatId';
    final cached = _forumRecentTopics[key];
    if (cached != null) return cached;
    if (!_forumTopicsFetching.contains(key)) {
      _forumTopicsFetching.add(key);
      _engine.getForumTopics(accountId, chatId).then((topics) {
        if (_disposed) return;
        topics.sort((a, b) {
          final aId = int.tryParse(a.topMessageId) ?? 0;
          final bId = int.tryParse(b.topMessageId) ?? 0;
          return bId.compareTo(aId);
        });
        _forumRecentTopics[key] = topics.take(8).toList();
        notifyListeners();
      }).catchError((_) {
        _forumTopicsFetching.remove(key);
      });
    }
    return const [];
  }

  /// Online member count for the active group/channel chat.
  int get groupOnlineCount => _groupOnlineCount;

  int get scheduledCount => _scheduledCount;
  bool get isScheduledView => _isScheduledView;
  String get linkedChatId => _linkedChatId;

  void toggleScheduledView() {
    _isScheduledView = !_isScheduledView;
    _messages = [];
    _isFirstLoad = true;
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
      // §23.9: For topic chats, load from parent group and filter by topic.
      final fetchChatId = (chat.type == ChatType.topic && chat.parentId.isNotEmpty)
          ? chat.parentId
          : chat.chatId;
      var msgs = await _engine.getScheduledMessages(chat.accountId, fetchChatId);
      if (chat.type == ChatType.topic) {
        msgs = msgs.where((m) => m.topicId == chat.chatId).toList();
      }
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

  bool get isEditHistoryView => _isEditHistoryView;
  String get editHistoryMsgId => _editHistoryMsgId;
  String get editHistorySenderName => _editHistorySenderName;

  void openEditHistory(String msgId, String senderName) {
    _editHistoryMsgId = msgId;
    _editHistorySenderName = senderName;
    _isEditHistoryView = true;
    _messages = [];
    _isFirstLoad = true;
    _loadEditRevisions();
    notifyListeners();
  }

  void closeEditHistory() {
    _isEditHistoryView = false;
    _editHistoryMsgId = '';
    _editHistorySenderName = '';
    _messages = [];
    _isFirstLoad = true;
    _loadMessages();
    notifyListeners();
  }

  void _loadEditRevisions() {
    final chat = _activeChat;
    if (chat == null || _editHistoryMsgId.isEmpty) return;
    try {
      final revisions = _engine.getEditRevisions(chat.accountId, chat.chatId, _editHistoryMsgId, offset: 0, limit: 20);
      final msgs = <CachedMessage>[];
      for (final r in revisions) {
        msgs.add(CachedMessage(
          accountId: r['account_id'] as String? ?? '',
          chatId: r['chat_id'] as String? ?? '',
          msgId: 'rev_${r['id']}',
          senderId: r['sender_id'] as String? ?? '',
          senderName: r['sender_name'] as String? ?? '',
          contentText: r['content_text'] as String? ?? '',
          timestamp: r['timestamp'] as int? ?? 0,
          editedAt: 0,
          status: MsgStatus.read,
          isOutgoing: false,
        ));
      }
      if (_isEditHistoryView) {
        _messages = msgs;
        _hasMoreMessages = revisions.length >= 20;
        _isFirstLoad = false;
        notifyListeners();
      }
    } catch (_) {
      _messages = [];
      _isFirstLoad = false;
      notifyListeners();
    }
  }

  /// All loaded folders across accounts.
  List<FolderInfo> get folders => _folders;

  /// Active folder ID (null = "All Chats").
  String? get activeFolderId => _activeFolderId;

  /// Whether any folders exist (controls folder sidebar visibility).
  bool get hasFolders => _folders.isNotEmpty;

  bool get showFolderTags => _showFolderTags;
  set showFolderTags(bool v) {
    if (_showFolderTags == v) return;
    _showFolderTags = v;
    notifyListeners();
  }

  bool get useVerticalFilters => _useVerticalFilters;
  set useVerticalFilters(bool v) {
    if (_useVerticalFilters == v) return;
    _useVerticalFilters = v;
    notifyListeners();
  }

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

  /// Badge-ready unread count respecting notification settings.
  /// [includeMuted]: whether muted chats contribute to the count.
  /// [countMessages]: true = count individual messages, false = count chats with unreads.
  int badgeUnreadCount({bool includeMuted = true, bool countMessages = true}) {
    final eligible = _chats.where((c) {
      if (c.unreadCount <= 0) return false;
      if (!includeMuted && c.isMuted) return false;
      return true;
    });
    if (countMessages) {
      return eligible.fold(0, (sum, c) => sum + c.unreadCount);
    }
    return eligible.length;
  }

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

  Future<FolderInfo?> createFolder(String accountId, String name, List<String> chatIds, {
    bool contacts = false,
    bool nonContacts = false,
    bool groups = false,
    bool channels = false,
    bool bots = false,
  }) async {
    final result = await _engine.createFolder(accountId, name, chatIds,
      contacts: contacts,
      nonContacts: nonContacts,
      groups: groups,
      channels: channels,
      bots: bots,
    );
    if (result != null) {
      await loadFoldersForAccount(accountId);
    }
    return result;
  }

  Future<void> editFolder(String accountId, String folderId, String name, List<String> chatIds, {
    bool contacts = false,
    bool nonContacts = false,
    bool groups = false,
    bool channels = false,
    bool bots = false,
    bool excludeMuted = false,
    bool excludeRead = false,
    bool excludeArchived = false,
    List<String> excludeChatIds = const [],
  }) async {
    await _engine.editFolder(accountId, folderId, name, chatIds,
      contacts: contacts,
      nonContacts: nonContacts,
      groups: groups,
      channels: channels,
      bots: bots,
      excludeMuted: excludeMuted,
      excludeRead: excludeRead,
      excludeArchived: excludeArchived,
      excludeChatIds: excludeChatIds,
    );
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
    _isFirstLoad = true;
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
  /// For group chats, auto-detects forums and shows topic list.
  void removeChatFromOpenHistory(String chatId) {
    _chatOpenHistory.remove(chatId);
  }

  void openChat(ChatInfo chat) {
    if (chat.isForum && _forumParentChat?.chatId != chat.chatId) {
      _checkAndOpenForum(chat);
    }
    if (chat.title == 'Saved Messages' && chat.type == ChatType.dm) {
      openSavedSublists(chat.accountId);
    } else if (_isViewingSavedSublists) {
      closeSavedSublists();
    }
    _chatOpenHistory.remove(chat.chatId);
    _chatOpenHistory.insert(0, chat.chatId);
    if (_chatOpenHistory.length > _maxChatOpenHistory) {
      _chatOpenHistory.removeRange(_maxChatOpenHistory, _chatOpenHistory.length);
    }
    SpoilerRevealManager.instance.hideAll();
    _activeChat = chat;
    _openedUnreadCount = chat.unreadCount;
    _messages = [];
    _pinnedMessages = [];
    _hasMoreMessages = true;
    _isFirstLoad = true;
    _jumpedUntil = null; // clear jump lock on chat change
    _activeChannelId = null; // reset channel selection on chat change
    _hiddenKeyboardMsgId = null;
    _engine.setActiveChat(chat.accountId, chat.chatId);
    _loadMessages();
    _loadPinnedMessages(chat.accountId, chat.chatId);
    // Fetch member avatars and online count for group chats.
    _groupOnlineCount = 0;
    _activeGroupCall = null;
    _connectedBot = null;
    _connectedBotPaused = false;
    _scheduledCount = 0;
    _isScheduledView = false;
    _isEditHistoryView = false;
    _editHistoryMsgId = '';
    _editHistorySenderName = '';
    _linkedChatId = '';
    _botStartToken = '';
    _loadScheduledCount(chat.accountId, chat.chatId);
    if (chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic) {
      _loadMemberAvatars(chat.accountId, chat.chatId);
      _loadOnlineCount(chat.accountId, chat.chatId);
      _loadGroupCall(chat.accountId, chat.chatId);
      if (chat.type == ChatType.channel) {
        _loadLinkedChatId(chat.accountId, chat.chatId);
      }
    } else {
      _senderAvatars.clear();
      if (chat.type == ChatType.dm) {
        _loadConnectedBot(chat.accountId, chat.chatId);
      }
    }
    _startPolling();
    notifyListeners();
  }

  void _checkAndOpenForum(ChatInfo chat) {
    _engine.getForumTopics(chat.accountId, chat.chatId).then((topics) {
      if (_disposed || topics.isEmpty) return;
      _sortTopics(topics);
      _forumParentChat = chat;
      _forumTopics = topics;
      _forumHasMore = topics.length >= 100;
      _activeTopicId = null;
      final key = '${chat.accountId}:${chat.chatId}';
      _forumRecentTopics[key] = topics.take(8).toList();
      if (topics.length < 20) {
        _autoPreloadForumTopics(chat);
      }
      notifyListeners();
    }).catchError((_) {});
  }

  void openChatById(String chatId) {
    final chat = _chats.firstWhere(
      (c) => c.chatId == chatId,
      orElse: () => _chats.first,
    );
    if (chat.chatId == chatId) openChat(chat);
  }

  static void _sortTopics(List<ForumTopic> topics) {
    topics.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final aId = int.tryParse(a.topMessageId) ?? 0;
      final bId = int.tryParse(b.topMessageId) ?? 0;
      return bId.compareTo(aId);
    });
  }

  Future<void> openForum(ChatInfo chat) async {
    _forumParentChat = chat;
    _forumTopics = [];
    _activeTopicId = null;
    _forumHasMore = false;
    _forumLoadingMore = false;
    _forumFirstLoadDone = false;
    notifyListeners();
    try {
      final topics = await _engine.getForumTopics(chat.accountId, chat.chatId);
      _forumTopics = topics;
      _sortTopics(_forumTopics);
      _forumHasMore = topics.length >= 100;
      if (topics.length < 20 && topics.isNotEmpty) {
        _autoPreloadForumTopics(chat);
      }
    } catch (_) {}
    _forumFirstLoadDone = true;
    final key = '${chat.accountId}:${chat.chatId}';
    _forumRecentTopics[key] = _forumTopics.take(8).toList();
    notifyListeners();
  }

  Future<void> _autoPreloadForumTopics(ChatInfo chat) async {
    if (_forumLoadingMore || !_forumHasMore) return;
    _forumLoadingMore = true;
    try {
      final topics = await _engine.getForumTopics(chat.accountId, chat.chatId);
      if (chat == _forumParentChat) {
        final existingIds = _forumTopics.map((t) => t.id).toSet();
        for (final t in topics) {
          if (!existingIds.contains(t.id)) _forumTopics.add(t);
        }
        _sortTopics(_forumTopics);
        _forumHasMore = topics.length >= 100;
      }
    } catch (_) {}
    _forumLoadingMore = false;
    if (chat == _forumParentChat) notifyListeners();
  }

  Future<void> loadMoreForumTopics() async {
    final chat = _forumParentChat;
    if (chat == null || _forumLoadingMore || !_forumHasMore) return;
    await _autoPreloadForumTopics(chat);
  }

  Future<void> refreshForumTopics() async {
    final chat = _forumParentChat;
    if (chat == null) return;
    try {
      final topics = await _engine.getForumTopics(chat.accountId, chat.chatId);
      _forumTopics = topics;
      _sortTopics(_forumTopics);
      _forumHasMore = topics.length >= 100;
    } catch (_) {}
    if (chat == _forumParentChat) {
      final key = '${chat.accountId}:${chat.chatId}';
      _forumRecentTopics[key] = _forumTopics.take(8).toList();
      notifyListeners();
    }
  }

  Future<void> pinForumTopic(String accountId, String chatId, int topicId, bool pinned) async {
    await _engine.pinForumTopic(accountId, chatId, topicId, pinned);
    await refreshForumTopics();
  }

  Future<void> toggleForumTopicClosed(String accountId, String chatId, int topicId, bool closed) async {
    await _engine.toggleForumTopicClosed(accountId, chatId, topicId, closed);
    await refreshForumTopics();
  }

  Future<void> toggleGeneralTopicHidden(String accountId, String chatId, bool hidden) async {
    await _engine.toggleGeneralTopicHidden(accountId, chatId, hidden);
    await refreshForumTopics();
  }

  Future<void> deleteForumTopicHistory(String accountId, String chatId, int topicId) async {
    await _engine.deleteForumTopicHistory(accountId, chatId, topicId);
    await refreshForumTopics();
  }

  void closeForum() {
    _forumParentChat = null;
    _forumTopics = [];
    _activeTopicId = null;
    _forumHasMore = false;
    _forumLoadingMore = false;
    _forumFirstLoadDone = false;
    notifyListeners();
  }

  // §31.2–31.5: Saved Messages sublists with pagination
  String _savedSublistsAccountId = '';

  Future<void> openSavedSublists(String accountId) async {
    _isViewingSavedSublists = true;
    _savedSublistsAccountId = accountId;
    _pinnedSublists = [];
    _regularSublists = [];
    _savedSublistsTotalCount = 0;
    _savedSublistsLoading = true;
    _savedSublistsHasMore = true;
    _savedSublistsOffsetDate = 0;
    _savedSublistsOffsetId = 0;
    _savedSublistsFirstLoad = true;
    _recentSublists = [];
    notifyListeners();
    try {
      // Load pinned sublists separately (spec §31.5)
      try {
        final (pinned, _) = _engine.getPinnedSavedSublists(accountId);
        _pinnedSublists = pinned;
      } catch (_) {}

      // First batch: kFirstPerPage=10 non-pinned sublists
      final (sublists, total) = _engine.getSavedSublists(
        accountId,
        limit: _kFirstPerPage,
        excludePinned: true,
      );
      _regularSublists = sublists;
      _savedSublistsTotalCount = total;
      _savedSublistsFirstLoad = false;

      if (sublists.isNotEmpty) {
        final last = sublists.last;
        _savedSublistsOffsetDate = (last.lastMsgTime ~/ 1000);
        _savedSublistsOffsetId = last.topMessage;
      }
      _savedSublistsHasMore = sublists.length >= _kFirstPerPage;

      _updateRecentSublists();

      // Auto-load more if below kLoadedSublistsMinCount=20 (spec §31.5)
      final totalLoaded = _pinnedSublists.length + _regularSublists.length;
      if (totalLoaded < _kLoadedSublistsMinCount && _savedSublistsHasMore) {
        _savedSublistsLoading = false;
        notifyListeners();
        await _loadMoreSavedSublistsInternal();
        return;
      }
    } catch (_) {}
    _savedSublistsLoading = false;
    notifyListeners();
    loadSavedReactionTags();
  }

  Future<void> loadMoreSavedSublists() async {
    if (_savedSublistsLoadingMore || !_savedSublistsHasMore || _savedSublistsAccountId.isEmpty) return;
    await _loadMoreSavedSublistsInternal();
  }

  Future<void> _loadMoreSavedSublistsInternal() async {
    _savedSublistsLoadingMore = true;
    notifyListeners();
    try {
      final (sublists, total) = _engine.getSavedSublists(
        _savedSublistsAccountId,
        limit: _kPerPage,
        offsetDate: _savedSublistsOffsetDate,
        offsetId: _savedSublistsOffsetId,
        excludePinned: true,
      );
      _regularSublists = [..._regularSublists, ...sublists];
      _savedSublistsTotalCount = total;

      if (sublists.isNotEmpty) {
        final last = sublists.last;
        _savedSublistsOffsetDate = (last.lastMsgTime ~/ 1000);
        _savedSublistsOffsetId = last.topMessage;
      }
      _savedSublistsHasMore = sublists.length >= _kPerPage;

      _updateRecentSublists();

      // Continue auto-loading if still below minimum (spec §31.5)
      final totalLoaded = _pinnedSublists.length + _regularSublists.length;
      if (totalLoaded < _kLoadedSublistsMinCount && _savedSublistsHasMore) {
        _savedSublistsLoadingMore = false;
        notifyListeners();
        await _loadMoreSavedSublistsInternal();
        return;
      }
    } catch (_) {}
    _savedSublistsLoadingMore = false;
    notifyListeners();
  }

  void _updateRecentSublists() {
    final all = [..._pinnedSublists, ..._regularSublists];
    all.sort((a, b) => b.lastMsgTime.compareTo(a.lastMsgTime));
    _recentSublists = all.take(_kRecentSublistsMax).toList();
  }

  void openSavedSublist(SavedSublistInfo sublist) {
    _activeSublist = sublist;
    notifyListeners();
  }

  void closeSavedSublist() {
    _activeSublist = null;
    notifyListeners();
  }

  void togglePinSavedSublist(SavedSublistInfo sub) {
    // Toggle pinned state locally — backend wiring (MessagesToggleSavedDialogPin) TBD.
    final wasPinned = sub.isPinned;
    if (wasPinned) {
      _pinnedSublists.removeWhere((s) => s.peerId == sub.peerId);
      _regularSublists.insert(0, SavedSublistInfo(
        peerId: sub.peerId, peerName: sub.peerName, avatarPath: sub.avatarPath,
        type: sub.type, isPinned: false, topMessage: sub.topMessage,
        lastMsgText: sub.lastMsgText, lastMsgTime: sub.lastMsgTime,
        isSelf: sub.isSelf, unreadCount: sub.unreadCount,
      ));
    } else {
      _regularSublists.removeWhere((s) => s.peerId == sub.peerId);
      _pinnedSublists.add(SavedSublistInfo(
        peerId: sub.peerId, peerName: sub.peerName, avatarPath: sub.avatarPath,
        type: sub.type, isPinned: true, topMessage: sub.topMessage,
        lastMsgText: sub.lastMsgText, lastMsgTime: sub.lastMsgTime,
        isSelf: sub.isSelf, unreadCount: sub.unreadCount,
      ));
    }
    _updateRecentSublists();
    notifyListeners();
  }

  void markSavedSublistRead(SavedSublistInfo sub) {
    notifyListeners();
  }

  void deleteSavedSublist(SavedSublistInfo sub) {
    _pinnedSublists.removeWhere((s) => s.peerId == sub.peerId);
    _regularSublists.removeWhere((s) => s.peerId == sub.peerId);
    if (_activeSublist?.peerId == sub.peerId) {
      _activeSublist = null;
    }
    _updateRecentSublists();
    notifyListeners();
  }

  void closeSavedSublists() {
    _isViewingSavedSublists = false;
    _activeSublist = null;
    _pinnedSublists = [];
    _regularSublists = [];
    _savedSublistsTotalCount = 0;
    _savedSublistsLoading = false;
    _savedSublistsLoadingMore = false;
    _savedSublistsHasMore = true;
    _savedSublistsOffsetDate = 0;
    _savedSublistsOffsetId = 0;
    _savedSublistsFirstLoad = true;
    _recentSublists = [];
    _savedSublistsAccountId = '';
    _savedReactionTags = [];
    _savedReactionTagsLoading = false;
    _selectedReactionTagIds.clear();
    notifyListeners();
  }

  Future<void> loadSavedReactionTags({String sublistPeerId = ''}) async {
    if (_savedSublistsAccountId.isEmpty) return;
    _savedReactionTagsLoading = true;
    notifyListeners();
    try {
      final tags = _engine.getSavedReactionTags(
        _savedSublistsAccountId,
        sublistPeerId: sublistPeerId,
      );
      _savedReactionTags = tags;
    } catch (_) {}
    _savedReactionTagsLoading = false;
    notifyListeners();
  }

  Future<void> renameSavedReactionTag({String emoji = '', int customId = 0, required String title}) async {
    if (_savedSublistsAccountId.isEmpty) return;
    try {
      _engine.renameSavedReactionTag(
        _savedSublistsAccountId,
        emoji: emoji,
        customId: customId,
        title: title,
      );
      await loadSavedReactionTags();
    } catch (_) {}
  }

  void openTopic(ForumTopic topic) {
    _activeTopicId = topic.id;
    final parent = _forumParentChat;
    if (parent == null) return;
    final topicChat = _chats.firstWhere(
      (c) => c.chatId == topic.id && c.accountId == parent.accountId,
      orElse: () => ChatInfo(
        accountId: parent.accountId,
        chatId: topic.id,
        type: ChatType.topic,
        title: topic.title,
        unreadCount: topic.unreadCount,
        isPinned: topic.isPinned,
        parentId: parent.chatId,
        parentTitle: parent.title,
      ),
    );
    openChat(topicChat);
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

  /// §49.6: Increment unread badge when incoming message arrives while not at bottom.
  void incrementOpenedUnread() {
    _openedUnreadCount++;
    notifyListeners();
  }

  /// Close the active chat.
  void closeChat() {
    _stopPolling();
    _activeChat = null;
    _activeSublist = null;
    _openedUnreadCount = 0;
    _messages = [];
    _isFirstLoad = true;
    _pinnedMessages = [];
    _activeGroupCall = null;
    _engine.clearActiveChat();
    notifyListeners();
  }

  /// Load more messages (pagination).
  void loadMoreMessages() {
    if (_loadingMessages || !_hasMoreMessages || _activeChat == null) return;
    if (_isScheduledView) return;
    if (_isEditHistoryView) {
      _loadMoreEditRevisions();
      return;
    }
    _loadMessages();
  }

  void _loadMoreEditRevisions() {
    final chat = _activeChat;
    if (chat == null || _editHistoryMsgId.isEmpty || _loadingMessages) return;
    _loadingMessages = true;
    try {
      final revisions = _engine.getEditRevisions(
        chat.accountId, chat.chatId, _editHistoryMsgId,
        offset: _messages.length, limit: 30,
      );
      for (final r in revisions) {
        _messages.add(CachedMessage(
          accountId: r['account_id'] as String? ?? '',
          chatId: r['chat_id'] as String? ?? '',
          msgId: 'rev_${r['id']}',
          senderId: r['sender_id'] as String? ?? '',
          senderName: r['sender_name'] as String? ?? '',
          contentText: r['content_text'] as String? ?? '',
          timestamp: r['timestamp'] as int? ?? 0,
          editedAt: 0,
          status: MsgStatus.read,
          isOutgoing: false,
        ));
      }
      _hasMoreMessages = revisions.length >= 30;
      notifyListeners();
    } finally {
      _loadingMessages = false;
    }
  }

  /// Send a message in the active chat.
  /// Go handles optimistic insert + event emission; we refresh after send.
  Future<String?> sendMessage(String text, {String replyToId = '', String entities = '', bool silent = false, int scheduleDate = 0, String webPageUrl = '', bool forceLargeMedia = false, bool forceSmallMedia = false, bool invertMedia = false, bool webPageOptional = true}) async {
    final chat = _activeChat;
    if (chat == null || text.trim().isEmpty) return null;

    // ��23.9: For topic chats, send to the parent group with topicRootId.
    final sendChatId = (chat.type == ChatType.topic && chat.parentId.isNotEmpty)
        ? chat.parentId
        : chat.chatId;
    final topicRootId = (chat.type == ChatType.topic) ? chat.chatId : '';

    final localId = await _engine.sendMessage(chat.accountId, sendChatId, text,
        replyToId: replyToId, entities: entities, silent: silent,
        scheduleDate: scheduleDate, topicRootId: topicRootId,
        webPageUrl: webPageUrl, forceLargeMedia: forceLargeMedia, forceSmallMedia: forceSmallMedia, invertMedia: invertMedia, webPageOptional: webPageOptional);

    // Spec §49.4: destroy unread bar when user sends outgoing message.
    clearOpenedUnread();

    if (scheduleDate > 0) {
      _loadScheduledCount(chat.accountId, chat.chatId);
      if (!_isScheduledView) {
        toggleScheduledView();
      }
    } else {
      _refreshMessages();
    }

    return localId;
  }

  Future<String?> uploadFile(String filePath, {String caption = ''}) async {
    final chat = _activeChat;
    if (chat == null) return null;
    clearOpenedUnread();
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
  /// If [highlightMsgId] is set, the UI will highlight that message with a fade animation.
  String? _pendingHighlightMsgId;
  String? get pendingHighlightMsgId => _pendingHighlightMsgId;
  void clearPendingHighlight() { _pendingHighlightMsgId = null; }

  void jumpToMessage(int timestampMs, {String? highlightMsgId}) {
    final chat = _activeChat;
    if (chat == null) return;
    SpoilerRevealManager.instance.hideAll();

    final around = _engine.getMessages(
      chat.accountId, chat.chatId,
      beforeMs: timestampMs + 1,
    );
    if (around.isNotEmpty) {
      _messages = around;
      _hasMoreMessages = true;
      _jumpedUntil = DateTime.now().add(const Duration(seconds: 10));
      _pendingHighlightMsgId = highlightMsgId;
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
    _isFirstLoad = true;
    _loadMessages();
  }

  Future<void> forwardMessages(List<String> msgIds, String toChatId, {
    bool dropAuthor = false,
    bool dropCaptions = false,
    bool silent = false,
    int scheduleDate = 0,
  }) async {
    final chat = _activeChat;
    if (chat == null) return;
    for (final id in msgIds) {
      await _engine.forwardMessage(chat.accountId, chat.chatId, id, toChatId,
        dropAuthor: dropAuthor, dropCaptions: dropCaptions,
        silent: silent, scheduleDate: scheduleDate);
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

  Future<void> rescheduleMessage(String msgId, int scheduleDate) async {
    final chat = _activeChat;
    if (chat == null) return;
    await _engine.rescheduleMessage(chat.accountId, chat.chatId, msgId, scheduleDate);
    final idx = _messages.indexWhere((m) => m.msgId == msgId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(scheduleDate: scheduleDate);
    }
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

  Future<String> requestBotWebView(String botId) async {
    final chat = _activeChat;
    if (chat == null) return '';
    return _engine.requestBotWebView(chat.accountId, chat.chatId, botId);
  }

  Future<Map<String, dynamic>> requestUrlAuth(String msgId, int buttonId) async {
    final chat = _activeChat;
    if (chat == null) return {'type': 'default'};
    return _engine.requestUrlAuth(chat.accountId, chat.chatId, msgId, buttonId);
  }

  Future<String> acceptUrlAuth(String msgId, int buttonId, bool writeAllowed, bool sharePhone) async {
    final chat = _activeChat;
    if (chat == null) return '';
    return _engine.acceptUrlAuth(chat.accountId, chat.chatId, msgId, buttonId, writeAllowed, sharePhone);
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

  void muteChat(String accountId, String chatId, bool muted, {int durationSeconds = 0}) {
    _engine.muteChat(accountId, chatId, muted, durationSeconds: durationSeconds);
    loadChats();
  }

  // ── Per-chat themes (§25.11) ──
  List<ChatThemeData> _availableChatThemes = [];
  List<ChatThemeData> get availableChatThemes => _availableChatThemes;
  final Map<String, String> _chatThemeEmoticons = {};
  String? _selectedThemeEmoticon;
  String? get selectedThemeEmoticon => _selectedThemeEmoticon;
  bool _showThemeChooser = false;
  bool get showThemeChooser => _showThemeChooser;

  void toggleThemeChooser() {
    _showThemeChooser = !_showThemeChooser;
    if (_showThemeChooser && _availableChatThemes.isEmpty && _activeChat != null) {
      fetchChatThemes(_activeChat!.accountId);
    }
    notifyListeners();
  }

  void closeThemeChooser() {
    if (!_showThemeChooser) return;
    _showThemeChooser = false;
    _selectedThemeEmoticon = null;
    notifyListeners();
  }

  Future<void> fetchChatThemes(String accountId) async {
    final themes = await _engine.getChatThemes(accountId);
    _availableChatThemes = themes;
    notifyListeners();
  }

  String? chatThemeEmoticon(String chatId) => _chatThemeEmoticons[chatId];

  void selectThemePreview(String? emoticon) {
    _selectedThemeEmoticon = emoticon;
    notifyListeners();
  }

  Future<void> applyChatTheme(String accountId, String chatId, String emoticon) async {
    final ok = await _engine.setChatTheme(accountId, chatId, emoticon);
    if (ok) {
      if (emoticon.isEmpty) {
        _chatThemeEmoticons.remove(chatId);
      } else {
        _chatThemeEmoticons[chatId] = emoticon;
      }
      _selectedThemeEmoticon = null;
      _showThemeChooser = false;
      notifyListeners();
    }
  }

  ChatThemeData? getActiveThemeData(String chatId) {
    final emoticon = _selectedThemeEmoticon ?? _chatThemeEmoticons[chatId];
    if (emoticon == null || emoticon.isEmpty) return null;
    final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    return _availableChatThemes.cast<ChatThemeData?>().firstWhere(
      (t) => t!.emoticon == emoticon && t.isDark == isDark,
      orElse: () => _availableChatThemes.cast<ChatThemeData?>().firstWhere(
        (t) => t!.emoticon == emoticon,
        orElse: () => null,
      ),
    );
  }

  void setHistoryTTL(String accountId, String chatId, int period) {
    _engine.setHistoryTTL(accountId, chatId, period);
    loadChats();
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

  Future<void> reportSpam(String accountId, String chatId) async {
    await _engine.reportSpam(accountId, chatId);
    loadChats();
  }

  Future<void> addContact(String accountId, String phone, String firstName, String lastName) async {
    await _engine.addContact(accountId, phone, firstName, lastName);
    loadChats();
  }

  Future<void> deleteContact(String accountId, String userId) async {
    await _engine.deleteContact(accountId, userId);
    loadChats();
  }

  Future<void> joinChannel(String accountId, String chatId) async {
    await _engine.joinChannel(accountId, chatId);
    loadChats();
    if (_activeChat?.accountId == accountId && _activeChat?.chatId == chatId) {
      openChatById(chatId);
    }
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

    // Spec §49.1: first load 30 messages, subsequent loads 50.
    final limit = _isFirstLoad ? 30 : 50;
    final beforeMs = _messages.isNotEmpty ? _messages.last.timestamp : 0;
    final newMsgs = _engine.getMessages(chat.accountId, chat.chatId, beforeMs: beforeMs, limit: limit);

    if (newMsgs.length < limit) _hasMoreMessages = false;
    _messages.addAll(newMsgs);
    _isFirstLoad = false;
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
      final chat = _activeChat;
      // §23.9: For topic chats, count scheduled messages from parent group filtered by topic.
      final fetchChatId = (chat != null && chat.type == ChatType.topic && chat.parentId.isNotEmpty)
          ? chat.parentId
          : chatId;
      if (chat != null && chat.type == ChatType.topic) {
        final msgs = await _engine.getScheduledMessages(accountId, fetchChatId);
        final filtered = msgs.where((m) => m.topicId == chatId).length;
        if (_activeChat?.chatId == chatId) {
          _scheduledCount = filtered;
          notifyListeners();
        }
      } else {
        final count = await _engine.getScheduledCount(accountId, chatId);
        if (_activeChat?.chatId == chatId) {
          _scheduledCount = count;
          notifyListeners();
        }
      }
    } catch (_) {
      _scheduledCount = 0;
    }
  }

  Future<void> _loadLinkedChatId(String accountId, String chatId) async {
    try {
      final id = await _engine.getLinkedChatId(accountId, chatId);
      if (_activeChat?.chatId == chatId) {
        _linkedChatId = id;
        notifyListeners();
      }
    } catch (_) {
      _linkedChatId = '';
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

  // ── Business bot bar (§30.11) ──

  Future<void> _loadConnectedBot(String accountId, String chatId) async {
    try {
      List<ConnectedBotInfo>? bots = _connectedBotsCache[accountId];
      if (bots == null) {
        bots = await _engine.getConnectedBots(accountId);
        _connectedBotsCache[accountId] = bots;
      }
      final chat = _activeChat;
      if (chat == null || chat.chatId != chatId) return;
      for (final bot in bots) {
        if (bot.appliesTo(chatId, isContact: chat.isContact)) {
          _connectedBot = bot;
          _connectedBotPaused = false;
          notifyListeners();
          return;
        }
      }
      _connectedBot = null;
      notifyListeners();
    } catch (_) {
      _connectedBot = null;
    }
  }

  Future<void> toggleConnectedBotPaused() async {
    final chat = _activeChat;
    final bot = _connectedBot;
    if (chat == null || bot == null) return;
    final newPaused = !_connectedBotPaused;
    try {
      await _engine.toggleConnectedBotPaused(chat.accountId, chat.chatId, paused: newPaused);
      _connectedBotPaused = newPaused;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> removeConnectedBot() async {
    final chat = _activeChat;
    if (chat == null || _connectedBot == null) return;
    try {
      await _engine.disablePeerConnectedBot(chat.accountId, chat.chatId);
      _connectedBot = null;
      _connectedBotPaused = false;
      _connectedBotsCache.remove(chat.accountId);
      notifyListeners();
    } catch (_) {}
  }

  /// Re-fetch the latest messages for the active chat and merge.
  /// Used after send and as a periodic fallback for event delivery issues.
  void refreshMessages() => _refreshMessages();

  void _refreshMessages() {
    if (_disposed) return;
    if (_isScheduledView) return;
    if (_isEditHistoryView) return;
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

  void _handleMsgReceived(MsgReceivedEvent event) {
    if (_disposed) return;
    final isActiveChat = _activeChat?.accountId == event.accountId &&
        _activeChat?.chatId == event.chatId;
    if (isActiveChat && !_isScheduledView && !_isEditHistoryView) {
      final exists = _messages.any((m) =>
        m.msgId == event.message.msgId ||
        (event.message.localId.isNotEmpty && m.localId == event.message.localId));
      if (!exists) {
        _messages.insert(0, event.message);
        onNewActiveMessage?.call(event.message);
        notifyListeners();
      }
    } else if (onNotification != null && !event.message.isSent) {
      final chat = _chats.where((c) =>
          c.accountId == event.accountId && c.chatId == event.chatId).firstOrNull;
      final msg = event.message;

      String stickerEmoji = '';
      if (msg.mediaType == 6 && msg.contentText.isNotEmpty) {
        stickerEmoji = msg.contentText;
      }

      final notifText = _applySpoilerEntities(msg.contentText, msg.contentRich);
      final isLoginCodeSender = msg.senderId == '777000';

      onNotification!(NotificationData(
        accountId: event.accountId,
        chatId: event.chatId,
        messageId: msg.msgId,
        senderName: msg.senderName,
        chatTitle: chat?.title ?? '',
        text: notifText,
        avatarPath: chat?.avatarPath ?? '',
        isMuted: chat?.isMuted ?? false,
        isOutgoing: msg.isOutgoing,
        isChannel: chat?.type == ChatType.channel,
        isGroup: chat?.type == ChatType.group || chat?.type == ChatType.topic,
        isSilent: msg.isSilent,
        timestamp: msg.timestamp,
        messageType: msg.mediaType,
        isScheduled: msg.scheduleDate > 0,
        isForumTopic: msg.topicId.isNotEmpty,
        topicTitle: msg.topicName,
        forwardFrom: msg.forwardFrom,
        forwardCount: msg.forwardFrom.isNotEmpty ? 1 : 0,
        stickerEmoji: stickerEmoji,
        hasSpoiler: msg.mediaSpoiler,
        caption: (msg.mediaType >= 1 && msg.mediaType <= 2 && msg.contentText.isNotEmpty)
            ? msg.contentText
            : '',
        pollQuestion: msg.pollQuestion,
        gameTitle: msg.gameTitle,
        invoiceTitle: msg.invoiceTitle,
        contactName: msg.contactFirstName.isNotEmpty
            ? '${msg.contactFirstName} ${msg.contactLastName}'.trim()
            : '',
        isLiveLocation: msg.geoLive,
        groupedId: msg.groupedId,
        slowmodeActive: (chat?.slowmodeNextSendDate ?? 0) > 0 &&
            chat!.slowmodeNextSendDate > DateTime.now().millisecondsSinceEpoch ~/ 1000,
        requiresStars: (chat?.starsToSend ?? 0) > 0,
        spoilerLoginCode: isLoginCodeSender,
      ));
    }
  }

  void _handleMsgEdited(MsgEditedEvent event) {
    if (_disposed) return;
    if (_isEditHistoryView) return;
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
          wpHasIv: extra['wp_has_iv'] == true,
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

    final idx = _messages.indexWhere((m) => m.msgId == event.msgId);
    if (idx < 0) return;

    final savable = _appState.saveDeletedMessages &&
        (!event.senderIsBot || _appState.saveForBots);

    if (savable) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _messages[idx] = _messages[idx].copyWith(isDeleted: true, deletedAt: now);
    } else {
      _messages.removeAt(idx);
    }
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

  String? getAltQualityPath(String msgId, int seq) => _altQualityPaths['$msgId:$seq'];

  void requestAltQualityDownload(CachedMessage msg, int seq) {
    _engine.requestDownload(msg.accountId, msg.chatId, msg.msgId, seq: seq);
  }

  void _handleDownloadProgress(DownloadProgressEvent event) {
    if (_disposed) return;
    _downloadProgress[event.msgId] = event;
    notifyListeners();
  }

  DownloadProgressEvent? getDownloadProgress(String msgId) => _downloadProgress[msgId];

  void _handleDownloadComplete(DownloadCompleteEvent event) {
    if (_disposed) return;
    _downloadProgress.remove(event.msgId);
    if (event.seq > 0) {
      _altQualityPaths['${event.msgId}:${event.seq}'] = event.localPath;
      notifyListeners();
      return;
    }
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

  static const _spoilerChar = '▚';

  static String _applySpoilerEntities(String text, String contentRich) {
    if (text.isEmpty || contentRich.isEmpty) return text;
    try {
      final list = jsonDecode(contentRich) as List;
      final spoilers = <(int, int)>[];
      for (final e in list) {
        if (e is Map<String, dynamic> && e['type'] == 'spoiler') {
          final offset = e['offset'] as int? ?? 0;
          final length = e['length'] as int? ?? 0;
          if (length > 0) spoilers.add((offset, length));
        }
      }
      if (spoilers.isEmpty) return text;
      spoilers.sort((a, b) => a.$1.compareTo(b.$1));
      final buf = StringBuffer();
      var pos = 0;
      for (final (offset, length) in spoilers) {
        if (offset > pos) buf.write(text.substring(pos, offset.clamp(0, text.length)));
        buf.write(_spoilerChar * length.clamp(1, 40));
        pos = (offset + length).clamp(0, text.length);
      }
      if (pos < text.length) buf.write(text.substring(pos));
      return buf.toString();
    } catch (_) {
      return text;
    }
  }
}
