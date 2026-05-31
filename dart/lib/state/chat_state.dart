import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../utils/debug.dart';
import '../notifications/notification_types.dart';
import '../state/app_state.dart';
import '../state/audio_service.dart';
import '../state/ayu_forward.dart';
import '../ui/custom_emoji_cache.dart';
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
  final Map<String, ({String name, String action})> _typingUsers = {}; // chatId → (name, action)
  final Map<String, bool> _onlineUsers = {}; // "accountId:chatId" → isOnline (DMs only)
  // "accountId:userId" → (kind, lastSeenMs) for DM subtitle text.
  final Map<String, ({String kind, int lastSeenMs})> _userLastSeen = {};
  final Map<String, String> _senderAvatars = {}; // senderId → base64 avatar thumbnail
  final Map<String, Map<String, String>> _avatarCache = {}; // "accountId:chatId" → {senderId → b64}
  final Map<String, String> _altQualityPaths = {}; // "msgId:seq" → local path
  final Map<String, DownloadProgressEvent> _downloadProgress = {}; // msgId → latest progress
  // ── Media-player playlist (auto-advance, next/previous) ──
  AudioService? _audioServiceRef; // set once from main.dart for download-driven autoplay
  String? _pendingAutoplayMsgId; // neighbour track awaiting download before it can play
  String? _pendingAutoplayFromMsgId; // audio context msgId when the neighbour was queued
  int _groupOnlineCount = 0; // online members in active group/channel chat
  GroupCallInfo? _activeGroupCall; // active group call in current chat
  PersonalCallInfo? _activePersonalCall; // active 1:1 call
  int _scheduledCount = 0;
  bool _isScheduledView = false;
  String _linkedChatId = '';
  Map<String, dynamic> _peerBarSettings = const {};

  // ── Edit history view (§52.4) ──
  bool _isEditHistoryView = false;
  String _editHistoryMsgId = '';
  String _editHistorySenderName = '';

  // ── Deleted messages view (§52.5) ──
  bool _isDeletedMessagesView = false;
  String _deletedMsgSearch = '';

  // ── Archive state ──
  bool _hasArchivedChats = false;
  bool _archiveChecked = false;

  // ── Pinned chat order (drag-to-reorder, spec §2.7) ──
  // Key: accountId, Value: ordered list of pinned chat IDs.
  final Map<String, List<String>> _pinnedChatOrders = {};

  // ── Folder state ──
  List<FolderInfo> _folders = [];
  String _foldersForAccount = ''; // which account the current _folders belong to
  String? _activeFolderId; // null = "All Chats"
  bool _showFolderTags = false;
  bool _useVerticalFilters = true;
  int _folderLimitFree = 10;
  int _folderLimitPremium = 20;
  int _chatsPerFolderFree = 100;
  int _chatsPerFolderPremium = 200;
  int _sharedFoldersFree = 2;
  int _sharedFoldersPremium = 20;
  int _linksPerFolderFree = 3;
  int _linksPerFolderPremium = 20;

  void Function(NotificationData data)? onNotification;

  /// Fired when a peer's userpic finishes downloading (its [ChatInfo.avatarPath]
  /// becomes a non-empty path that differs from before), so any on-screen
  /// notification for that peer can repaint its avatar. Mirrors AyuGram
  /// subscribing to `downloaderTaskFinished` per session and calling
  /// `notification->updatePeerPhoto()` (notifications_manager_default.cpp:280-294).
  void Function(String accountId, String chatId, String avatarPath)?
      onPeerAvatarUpdated;

  /// Fired when a chat's inbox is read (markRead/markChatRead), so the
  /// notification system dismisses that chat's already-shown incoming
  /// notifications. Mirrors AyuGram's History::inboxRead → clearIncomingFromHistory
  /// (history/history.cpp:2105).
  void Function(String accountId, String chatId)? onChatRead;

  /// Fired when a chat is opened/activated, so the notification system clears
  /// that whole chat's notifications (all topics/sublists). Mirrors AyuGram
  /// calling clearFromHistory(_history) on chat activation
  /// (history/history_widget.cpp:4086).
  void Function(String accountId, String chatId)? onChatActivated;

  /// Fired when THIS account's own user status arrives (only ever from another
  /// logged-in device), feeding the online-aware notification delay
  /// (cOtherOnline). [lastSeenMs] is the exact was-online epoch-ms for offline
  /// statuses, 0 otherwise.
  void Function(String accountId, bool isOnline, int lastSeenMs)? onSelfStatus;

  /// Fired when the chat list (and thus cached mute state) may have changed, so
  /// the notification system can resolve notifications it parked while the mute
  /// state was unknown (AyuGram's checkDelayed on settings arrival).
  void Function()? onMuteStateMaybeResolved;

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
  static const _kFirstPerPage = 20; // AyuGram kListFirstPerPage (data_saved_messages.cpp:33)
  static const _kPerPage = 100; // AyuGram kListPerPage (data_saved_messages.cpp:32)
  static const _kLoadedSublistsMinCount = 20;
  static const _kRecentSublistsMax = 5;

  // §31.6–31.7: Saved reaction tags + selection state
  List<SavedReactionTagInfo> _savedReactionTags = [];
  bool _savedReactionTagsLoading = false;
  final Set<String> _selectedReactionTagIds = {};

  // §24.5: Recently opened chats for Ctrl+Tab switcher overlay.
  final List<String> _chatOpenHistory = []; // chatId list, most-recent first
  static const _maxChatOpenHistory = 50; // AyuGram kMaxChatEntryHistorySize (window_session_controller.cpp:138)

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
  Timer? _forumTopicDebounce;
  Timer? _savedSublistDebounce;
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
    _subs.add(_engine.onMsgReactionsUpdated.listen(_handleMsgReactionsUpdated));
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
        _connectedBotsCache.remove(event.accountId);
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

  bool canShowSponsoredMessages(String chatId) => !_appState.shouldSuppressSponsoredContent;

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
  List<CachedMessage> get messages {
    if (_selectedReactionTagIds.isEmpty) return _messages;
    return _messages.where((msg) {
      for (final r in msg.reactions) {
        final key = r.isCustomEmoji
            ? 'custom:${r.documentId}'
            : 'emoji:${r.emoji}';
        if (_selectedReactionTagIds.contains(key)) return true;
      }
      return false;
    }).toList();
  }
  List<CachedMessage> get pinnedMessages => _pinnedMessages;
  GroupCallInfo? get activeGroupCall => _activeGroupCall;
  PersonalCallInfo? get activePersonalCall => _activePersonalCall;

  void setActivePersonalCall(PersonalCallInfo? info) {
    _activePersonalCall = info;
    notifyListeners();
  }
  void setActiveGroupCall(GroupCallInfo? info) {
    _activeGroupCall = info;
    notifyListeners();
  }
  ConnectedBotInfo? get connectedBot => _connectedBot;
  bool get connectedBotPaused => _connectedBotPaused;
  bool get loadingMessages => _loadingMessages;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get hasArchivedChats => _hasArchivedChats;

  bool get hasArchivedUnread =>
      _chats.any((c) => c.isArchived && c.unreadCount > 0);

  void markArchivedAsRead() {
    final archived = _chats.where((c) => c.isArchived && c.unreadCount > 0).toList();
    for (final chat in archived) {
      _engine.markChatRead(chat.accountId, chat.chatId, '');
    }
  }

  /// Active channel/topic within a topic-type group. Null = default/all.
  String? get activeChannelId => _activeChannelId;

  String? typingUserFor(String chatId) => _typingUsers[chatId]?.name;
  String typingActionFor(String chatId) => _typingUsers[chatId]?.action ?? 'typing';

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
    if (_selectedReactionTagIds.isNotEmpty) {
      _ensureEnoughTaggedMessages();
    }
  }

  void _ensureEnoughTaggedMessages() {
    if (!_hasMoreMessages) return;
    if (messages.length < 20) {
      _loadMessages();
    }
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
  Map<String, dynamic> get peerBarSettings => _peerBarSettings;

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

  // ── Deleted messages view (§52.5) ──
  bool get isDeletedMessagesView => _isDeletedMessagesView;
  String get deletedMsgSearch => _deletedMsgSearch;

  void openDeletedMessages() {
    _isDeletedMessagesView = true;
    _deletedMsgSearch = '';
    _messages = [];
    _isFirstLoad = true;
    _loadDeletedMessages();
    notifyListeners();
  }

  void closeDeletedMessages() {
    _isDeletedMessagesView = false;
    _deletedMsgSearch = '';
    _messages = [];
    _isFirstLoad = true;
    _loadMessages();
    notifyListeners();
  }

  void searchDeletedMessages(String query) {
    _deletedMsgSearch = query;
    _messages = [];
    _isFirstLoad = true;
    _loadDeletedMessages();
    notifyListeners();
  }

  void _loadDeletedMessages() {
    final chat = _activeChat;
    if (chat == null) return;
    try {
      final msgs = _engine.getDeletedMessages(
        chat.accountId, chat.chatId,
        search: _deletedMsgSearch, offset: 0, limit: 20,
      );
      if (_isDeletedMessagesView) {
        _messages = msgs;
        _hasMoreMessages = msgs.length >= 20;
        _isFirstLoad = false;
        notifyListeners();
      }
    } catch (_) {
      _messages = [];
      _isFirstLoad = false;
      notifyListeners();
    }
  }

  void _loadMoreDeletedMessages() {
    final chat = _activeChat;
    if (chat == null || _loadingMessages) return;
    _loadingMessages = true;
    try {
      final msgs = _engine.getDeletedMessages(
        chat.accountId, chat.chatId,
        search: _deletedMsgSearch, offset: _messages.length, limit: 30,
      );
      _messages.addAll(msgs);
      _hasMoreMessages = msgs.length >= 30;
      notifyListeners();
    } finally {
      _loadingMessages = false;
    }
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

  int get folderLimitFree => _folderLimitFree;
  int get folderLimitPremium => _folderLimitPremium;
  int get chatsPerFolderFree => _chatsPerFolderFree;
  int get chatsPerFolderPremium => _chatsPerFolderPremium;
  int get sharedFoldersFree => _sharedFoldersFree;
  int get sharedFoldersPremium => _sharedFoldersPremium;
  int get linksPerFolderFree => _linksPerFolderFree;
  int get linksPerFolderPremium => _linksPerFolderPremium;

  bool get showFolderTags => _showFolderTags;
  set showFolderTags(bool v) {
    if (_showFolderTags == v) return;
    _showFolderTags = v;
    notifyListeners();
  }

  VoidCallback? onPersistLayout;

  bool get useVerticalFilters => _useVerticalFilters;
  set useVerticalFilters(bool v) {
    if (_useVerticalFilters == v) return;
    _useVerticalFilters = v;
    notifyListeners();
    onPersistLayout?.call();
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
      if (accountId.isNotEmpty && c.accountId != accountId) return false;
      if (excludeSet.contains(c.chatId)) return false;

      if (includeSet.contains(c.chatId)) return true;

      if (folder.excludeMuted && c.isMuted && c.unreadMentionCount == 0) return false;
      if (folder.excludeRead && c.unreadCount == 0 && c.unreadMentionCount == 0) return false;
      if (folder.excludeArchived && c.isArchived) return false;

      if (folder.hasTypeFilters) {
        if (folder.groups && c.type == ChatType.group) return true;
        if (folder.channels && c.type == ChatType.channel) return true;
        if (c.type == ChatType.dm) {
          if (folder.bots && c.isBot) return true;
          if (folder.contacts && c.isContact) return true;
          if (folder.nonContacts && !c.isContact && !c.isBot) return true;
        }
      }

      return false;
    }).toList();
  }

  /// Unread count for a specific folder.
  int unreadCountForFolder(String? folderId) {
    return chatsForFolder(folderId).fold(0, (sum, c) => sum + c.unreadCount);
  }

  /// Whether ALL unreads are from muted chats (badge should use muted color).
  /// Matches AyuGram's Domain::unreadBadgeMuted() — starts true, set false
  /// if any account has non-muted unreads.
  bool badgeUnreadMuted({bool includeMuted = true}) {
    final eligible = _chats.where((c) {
      if (c.unreadCount <= 0) return false;
      if (!includeMuted && c.isMuted) return false;
      return true;
    });
    if (eligible.isEmpty) return true;
    return eligible.every((c) => c.isMuted);
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
    bool staticTitle = false,
    int colorIndex = -1,
    String emoticon = '',
  }) async {
    final result = await _engine.createFolder(accountId, name, chatIds,
      contacts: contacts,
      nonContacts: nonContacts,
      groups: groups,
      channels: channels,
      bots: bots,
      staticTitle: staticTitle,
      colorIndex: colorIndex,
      emoticon: emoticon,
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
    bool staticTitle = false,
    int colorIndex = -1,
    String emoticon = '',
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
      staticTitle: staticTitle,
      colorIndex: colorIndex,
      emoticon: emoticon,
    );
    await loadFoldersForAccount(accountId);
  }

  Future<void> removeChatFromAllFolders(String accountId, String chatId) async {
    for (final folder in _folders) {
      if (folder.chatIds.contains(chatId)) {
        final updated = List<String>.from(folder.chatIds)..remove(chatId);
        await _engine.editFolder(accountId, folder.id, folder.name, updated,
          contacts: folder.contacts,
          nonContacts: folder.nonContacts,
          groups: folder.groups,
          channels: folder.channels,
          bots: folder.bots,
          excludeMuted: folder.excludeMuted,
          excludeRead: folder.excludeRead,
          excludeArchived: folder.excludeArchived,
          excludeChatIds: folder.excludeChatIds,
        );
      }
    }
    await loadFoldersForAccount(accountId);
  }

  /// Reorder folders (drag-and-drop in folder sidebar).
  void reorderFolders(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _folders.length) return;
    if (newIndex < 0 || newIndex > _folders.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = _folders.removeAt(oldIndex);
    _folders.insert(newIndex, item);
    if (_foldersForAccount.isNotEmpty) {
      _engine.reorderDialogFilters(
        _foldersForAccount,
        _folders.map((f) => int.tryParse(f.id) ?? 0).toList(),
      );
    }
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
    _fetchFolderLimits(accountId);
    notifyListeners();
  }

  Future<void> _fetchFolderLimits(String accountId) async {
    try {
      final limits = await _engine.getFolderLimits(accountId);
      _folderLimitFree = limits['free_limit'] ?? 10;
      _folderLimitPremium = limits['premium_limit'] ?? 20;
      _chatsPerFolderFree = limits['chats_per_folder_free'] ?? 100;
      _chatsPerFolderPremium = limits['chats_per_folder_premium'] ?? 200;
      _sharedFoldersFree = limits['shared_folders_free'] ?? 2;
      _sharedFoldersPremium = limits['shared_folders_premium'] ?? 20;
      _linksPerFolderFree = limits['links_per_folder_free'] ?? 3;
      _linksPerFolderPremium = limits['links_per_folder_premium'] ?? 20;
    } catch (_) {}
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
    _archiveChecked = false;
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
    if (!_archiveChecked) {
      _archiveChecked = true;
      _hasArchivedChats = _engine.getChatList(archived: true, limit: 1).isNotEmpty;
    }
    notifyListeners();
    // A fresh chat list may have populated the mute state for chats that
    // notified before their settings were cached — let the notification system
    // resolve anything it parked as "mute unknown" (cheap no-op when empty).
    onMuteStateMaybeResolved?.call();
  }

  /// Debounced version of loadChats — coalesces rapid event-driven reloads.
  void _debouncedLoadChats() {
    _loadChatsDebounce?.cancel();
    _loadChatsDebounce = Timer(const Duration(milliseconds: 300), () {
      loadChats();
    });
  }

  void _debouncedRefreshForumTopics() {
    _forumTopicDebounce?.cancel();
    _forumTopicDebounce = Timer(const Duration(milliseconds: 500), () {
      refreshForumTopics();
    });
  }

  void _debouncedRefreshSavedSublists() {
    if (!_isViewingSavedSublists || _savedSublistsAccountId.isEmpty) return;
    _savedSublistDebounce?.cancel();
    _savedSublistDebounce = Timer(const Duration(milliseconds: 500), () {
      openSavedSublists(_savedSublistsAccountId);
    });
  }

  /// Open a chat — loads messages and sets as active.
  /// For group chats, auto-detects forums and shows topic list.
  void removeChatFromOpenHistory(String chatId) {
    _chatOpenHistory.remove(chatId);
  }

  int _chatHistoryIndex = 0;

  bool navigateChatHistory(int direction) {
    final history = collectChatOpenHistory();
    if (history.length < 2) return false;
    final newIdx = (_chatHistoryIndex + direction).clamp(0, history.length - 1);
    if (newIdx == _chatHistoryIndex) return false;
    _chatHistoryIndex = newIdx;
    final chat = history[newIdx];
    if (chat.chatId == _activeChat?.chatId) return false;
    _activeChat = chat;
    _openedUnreadCount = chat.unreadCount;
    _messages = [];
    _pinnedMessages = [];
    _hasMoreMessages = true;
    _isFirstLoad = true;
    _jumpedUntil = null;
    _groupOnlineCount = 0;
    _activeGroupCall = null;
    _connectedBot = null;
    _connectedBotPaused = false;
    _scheduledCount = 0;
    _isScheduledView = false;
    _isEditHistoryView = false;
    _editHistoryMsgId = '';
    _editHistorySenderName = '';
    _isDeletedMessagesView = false;
    _deletedMsgSearch = '';
    _linkedChatId = '';
    _botStartToken = '';
    _peerBarSettings = const {};
    _engine.setActiveChat(chat.accountId, chat.chatId);
    _loadMessages();
    _loadPinnedMessages(chat.accountId, chat.chatId);
    _loadScheduledCount(chat.accountId, chat.chatId);
    final cacheKey = '${chat.accountId}:${chat.chatId}';
    if (!_avatarCache.containsKey(cacheKey)) {
      if (chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic) {
        _loadMemberAvatars(chat.accountId, chat.chatId);
        _loadOnlineCount(chat.accountId, chat.chatId);
        _loadGroupCall(chat.accountId, chat.chatId);
      }
    } else {
      _senderAvatars
        ..clear()
        ..addAll(_avatarCache[cacheKey]!);
    }
    if (chat.type == ChatType.dm) {
      _loadConnectedBot(chat.accountId, chat.chatId);
    }
    _loadPeerBarSettings(chat.accountId, chat.chatId);
    notifyListeners();
    return true;
  }

  void reloadSupportTemplates() {
    loadChats();
  }

  void openChat(ChatInfo chat) {
    if (chat.isForum && _forumParentChat?.chatId != chat.chatId) {
      _checkAndOpenForum(chat);
    }
    if (chat.isSelf && chat.type == ChatType.dm) {
      openSavedSublists(chat.accountId);
    } else if (_isViewingSavedSublists) {
      closeSavedSublists();
    }
    _chatOpenHistory.remove(chat.chatId);
    _chatOpenHistory.insert(0, chat.chatId);
    if (_chatOpenHistory.length > _maxChatOpenHistory) {
      _chatOpenHistory.removeRange(_maxChatOpenHistory, _chatOpenHistory.length);
    }
    _chatHistoryIndex = 0;
    SpoilerRevealManager.instance.hideAll();
    _activeChat = chat;
    // Opening a chat dismisses all of its on-screen notifications (every
    // topic/sublist), like AyuGram's clearFromHistory on chat activation.
    onChatActivated?.call(chat.accountId, chat.chatId);
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
    _isDeletedMessagesView = false;
    _deletedMsgSearch = '';
    _linkedChatId = '';
    _botStartToken = '';
    _peerBarSettings = const {};
    _loadScheduledCount(chat.accountId, chat.chatId);
    final cacheKey = '${chat.accountId}:${chat.chatId}';
    _senderAvatars.clear();
    if (chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic) {
      if (_avatarCache.containsKey(cacheKey)) {
        _senderAvatars.addAll(_avatarCache[cacheKey]!);
      } else {
        _loadMemberAvatars(chat.accountId, chat.chatId);
      }
      _loadOnlineCount(chat.accountId, chat.chatId);
      _loadGroupCall(chat.accountId, chat.chatId);
      if (chat.type == ChatType.channel) {
        _loadLinkedChatId(chat.accountId, chat.chatId);
      }
    } else {
      if (chat.type == ChatType.dm) {
        _loadConnectedBot(chat.accountId, chat.chatId);
      }
    }
    _loadPeerBarSettings(chat.accountId, chat.chatId);
    _startPolling();
    notifyListeners();
  }

  void _checkAndOpenForum(ChatInfo chat) {
    _engine.getForumTopics(chat.accountId, chat.chatId).then((topics) {
      if (_disposed || topics.isEmpty) return;
      _sortTopics(topics);
      _forumParentChat = chat;
      _forumTopics = topics;
      _forumHasMore = topics.length >= 20;
      _activeTopicId = null;
      final key = '${chat.accountId}:${chat.chatId}';
      _forumRecentTopics[key] = topics.take(8).toList();
      if (_forumHasMore) {
        _autoPreloadForumTopics(chat);
      }
      notifyListeners();
    }).catchError((_) {});
  }

  void openChatById(String chatId) {
    final idx = _chats.indexWhere((c) => c.chatId == chatId);
    if (idx >= 0) openChat(_chats[idx]);
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
      _forumHasMore = topics.length >= 20;
      if (_forumHasMore) {
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
      int offsetDate = 0;
      int offsetId = 0;
      int offsetTopic = 0;
      if (_forumTopics.isNotEmpty) {
        final last = _forumTopics.last;
        offsetDate = last.creationDate;
        offsetId = int.tryParse(last.topMessageId) ?? 0;
        offsetTopic = int.tryParse(last.id) ?? 0;
      }
      final topics = await _engine.getForumTopicsWithOffset(
        chat.accountId, chat.chatId,
        offsetDate: offsetDate,
        offsetId: offsetId,
        offsetTopic: offsetTopic,
      );
      if (chat == _forumParentChat) {
        final existingIds = _forumTopics.map((t) => t.id).toSet();
        for (final t in topics) {
          if (!existingIds.contains(t.id)) _forumTopics.add(t);
        }
        _sortTopics(_forumTopics);
        _forumHasMore = topics.length >= 500;
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
      _forumHasMore = topics.length >= 20;
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

  Future<void> deleteForumTopic(String accountId, String chatId, int topicId) async {
    await _engine.deleteForumTopicHistory(accountId, chatId, topicId);
    _forumTopics.removeWhere((t) => t.id == topicId.toString());
    notifyListeners();
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

      // First batch: kListFirstPerPage=20 non-pinned sublists
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
    _selectedReactionTagIds.clear();
    notifyListeners();
  }

  void closeSavedSublist() {
    _activeSublist = null;
    notifyListeners();
  }

  void togglePinSavedSublist(SavedSublistInfo sub) {
    final wasPinned = sub.isPinned;
    if (_savedSublistsAccountId.isNotEmpty) {
      _engine.toggleSavedDialogPin(_savedSublistsAccountId, sub.peerId, !wasPinned);
    }
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
    if (_savedSublistsAccountId.isNotEmpty) {
      _engine.markSavedSublistRead(_savedSublistsAccountId, sub.peerId);
    }
    notifyListeners();
  }

  void deleteSavedSublist(SavedSublistInfo sub) {
    if (_savedSublistsAccountId.isNotEmpty) {
      _engine.deleteSavedSublistHistory(_savedSublistsAccountId, sub.peerId);
    }
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
    if (_isDeletedMessagesView) {
      _loadMoreDeletedMessages();
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

  Future<String?> uploadFile(String filePath, {String caption = '', String captionEntities = '', bool silent = false, int scheduleDate = 0, bool spoiler = false, bool sendAsDocument = false, bool captionAbove = false, String videoCoverPath = '', bool sendLargePhotos = false, bool sendAsSticker = false, String replyToMsgId = '', String groupId = '', int price = 0}) async {
    final chat = _activeChat;
    if (chat == null) return null;
    clearOpenedUnread();
    final msgId = await _engine.uploadFile(chat.accountId, chat.chatId, filePath, caption: caption, captionEntities: captionEntities, silent: silent, scheduleDate: scheduleDate, spoiler: spoiler, sendAsDocument: sendAsDocument, captionAbove: captionAbove, videoCoverPath: videoCoverPath, sendLargePhotos: sendLargePhotos, sendAsSticker: sendAsSticker, replyToMsgId: replyToMsgId, groupId: groupId, price: price);
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

  void setHighlightMessage(String msgId) {
    _pendingHighlightMsgId = msgId;
    notifyListeners();
  }

  Future<void> jumpToMessage(int timestampMs, {String? highlightMsgId}) async {
    final chat = _activeChat;
    if (chat == null) return;
    SpoilerRevealManager.instance.hideAll();

    final around = await _engine.getMessages(
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

    final forwardMsgs = <CachedMessage>[];
    for (final id in msgIds) {
      final idx = _messages.indexWhere((m) => m.msgId == id);
      if (idx >= 0) forwardMsgs.add(_messages[idx]);
    }

    final progress = ForwardProgress();

    if (forwardMsgs.isNotEmpty && AyuForward.needsIntelligentForward(forwardMsgs, chat)) {
      await AyuForward.intelligentForward(
        engine: _engine,
        accountId: chat.accountId,
        sourceChatId: chat.chatId,
        messages: forwardMsgs,
        toChatId: toChatId,
        sourceChat: chat,
        dropAuthor: dropAuthor,
        dropCaptions: dropCaptions,
        silent: silent,
        scheduleDate: scheduleDate,
        progress: progress,
      );
    } else {
      AyuForward.startNativeForward(toChatId, progress, msgIds.length);
      int sent = 0;
      try {
        for (final id in msgIds) {
          if (progress.isCancelled) break;
          await _engine.forwardMessage(chat.accountId, chat.chatId, id, toChatId,
            dropAuthor: dropAuthor, dropCaptions: dropCaptions,
            silent: silent, scheduleDate: scheduleDate);
          sent++;
          progress.update(sent: sent);
        }
      } finally {
        AyuForward.finishNativeForward(toChatId, progress, sent);
      }
    }

    if (toChatId == chat.chatId) {
      _refreshMessages();
    }
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

  Future<({String message, String url, bool showAlert})> botCallbackGame(String msgId) async {
    final chat = _activeChat;
    if (chat == null) return (message: '', url: '', showAlert: false);
    return _engine.botCallbackFull(chat.accountId, chat.chatId, msgId, '__game');
  }

  Future<bool> votePoll(String msgId, List<int> optionIndices) async {
    final chat = _activeChat;
    if (chat == null) return false;
    return _engine.votePollMulti(chat.accountId, chat.chatId, msgId, optionIndices);
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
    onChatRead?.call(chat.accountId, chat.chatId);
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
    _engine.reorderPinnedDialogs(accountId, List<String>.from(order));
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
    if (archived) _hasArchivedChats = true;
    _archiveChecked = false;
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

  Future<void> sharePhoneWithPeer(String accountId, String chatId) async {
    await _engine.sharePhoneWithPeer(accountId, chatId);
    _peerBarSettings = const {};
    notifyListeners();
  }

  Future<void> hidePeerSettingsBar(String accountId, String chatId) async {
    await _engine.hidePeerSettingsBar(accountId, chatId);
    _peerBarSettings = const {};
    notifyListeners();
  }

  Future<void> setBotPhoto(String accountId, String chatId, String filePath) async {
    await _engine.setBotPhoto(accountId, chatId, filePath);
    _peerBarSettings = const {};
    notifyListeners();
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
    onChatRead?.call(accountId, chatId);
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

  void markChatUnread(String accountId, String chatId) {
    _engine.markChatUnread(accountId, chatId);
    loadChats();
  }

  void addChatToFolder(String accountId, String chatId, String folderId) {
    _engine.addChatToFolder(accountId, chatId, folderId);
  }

  void removeSavedReactionTag(String accountId, {String emoji = '', int customId = 0}) {
    _engine.removeSavedReactionTag(accountId, emoji: emoji, customId: customId);
  }

  List<ChatInfo> getTopPeers(String accountId, {int limit = 20}) {
    return _engine.getTopPeers(accountId, limit: limit);
  }

  Future<bool> getTopPeersEnabled(String accountId) {
    return _engine.getTopPeersEnabled(accountId);
  }

  Future<void> removeTopPeer(String accountId, String peerId) async {
    await _engine.removeTopPeer(accountId, peerId);
    notifyListeners();
  }

  Future<void> toggleTopPeers(String accountId, bool enabled) async {
    await _engine.toggleTopPeers(accountId, enabled);
    notifyListeners();
  }

  Future<List<ContactInfo>> getContacts(String accountId) {
    return _engine.getContacts(accountId);
  }

  Future<List<ChatInfo>> searchGlobalChats(String accountId, String query, {int limit = 20}) {
    return _engine.searchGlobalChats(accountId, query, limit: limit);
  }

  Future<List<ChatInfo>> searchGlobalPosts(String accountId, String query, {int limit = 20}) {
    return _engine.searchGlobalPosts(accountId, query, limit: limit);
  }

  Future<List<SearchResult>> searchGlobalPostMessages(String accountId, String query, {int limit = 20}) {
    return _engine.searchGlobalPostMessages(accountId, query, limit: limit);
  }

  // ── Search ──

  Future<List<SearchResult>> searchMessages(String query, {String accountId = '', String chatId = '', String topicId = ''}) {
    return _engine.searchMessages(query, accountId: accountId, chatId: chatId, topicId: topicId);
  }

  Future<List<ChatInfo>> searchChats(String query) {
    return _engine.searchChats(query);
  }

  // ── Internal ──

  Future<void> _loadMessages() async {
    if (_disposed) return;
    final chat = _activeChat;
    if (chat == null) return;

    _loadingMessages = true;
    notifyListeners();

    // Spec §49.1: first load 30 messages, subsequent loads 50.
    final limit = _isFirstLoad ? 30 : 50;
    final beforeMs = _messages.isNotEmpty ? _messages.last.timestamp : 0;
    final newMsgs = await _engine.getMessages(chat.accountId, chat.chatId, beforeMs: beforeMs, limit: limit);

    if (_disposed) return;
    if (newMsgs.length < limit) _hasMoreMessages = false;
    _messages.addAll(newMsgs);
    _isFirstLoad = false;
    _loadingMessages = false;
    _preloadCustomEmoji(newMsgs, chat.accountId);
    _autoDownloadMedia(newMsgs);
    notifyListeners();
    if (_selectedReactionTagIds.isNotEmpty) {
      _ensureEnoughTaggedMessages();
    }
  }

  void _preloadCustomEmoji(List<CachedMessage> msgs, String accountId) {
    final ids = <int>[];
    for (final msg in msgs) {
      if (msg.contentRich.isEmpty) continue;
      try {
        final entities = jsonDecode(msg.contentRich) as List;
        for (final e in entities) {
          if (e is Map<String, dynamic> && e['type'] == 'custom_emoji') {
            final docId = (e['document_id'] as num?)?.toInt() ?? 0;
            if (docId > 0) ids.add(docId);
          }
        }
      } catch (_) {}
    }
    if (ids.isNotEmpty) {
      CustomEmojiCache.instance.preloadBatch(ids, accountId, _engine);
    }
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
      } while (fetched >= batchSize && offset < 1000);
      if (_senderAvatars.isNotEmpty) {
        _avatarCache['$accountId:$chatId'] = Map.of(_senderAvatars);
        notifyListeners();
      }
    } catch (_) {}
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

  Future<void> _loadPeerBarSettings(String accountId, String chatId) async {
    try {
      final settings = await _engine.getPeerBarSettings(accountId, chatId);
      if (_activeChat?.chatId == chatId) {
        _peerBarSettings = settings;
        notifyListeners();
      }
    } catch (_) {
      _peerBarSettings = const {};
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

  /// Start or join the group call in the current chat.
  /// Returns the call ID on success, or null on failure.
  Future<String?> joinGroupCall() async {
    final chat = _activeChat;
    if (chat == null) return null;
    try {
      return await _engine.joinGroupCall(chat.accountId, chat.chatId);
    } catch (e) {
      Debug.error('CHAT', 'joinGroupCall failed', e);
      return null;
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

  Future<void> _refreshMessages() async {
    if (_disposed) return;
    if (_isScheduledView) return;
    if (_isEditHistoryView) return;
    if (_isDeletedMessagesView) return;
    final chat = _activeChat;
    if (chat == null) return;

    // Don't overwrite jumped-to messages while the user is reading them.
    if (_jumpedUntil != null && DateTime.now().isBefore(_jumpedUntil!)) return;

    final fresh = await _engine.getMessages(chat.accountId, chat.chatId, beforeMs: 0);
    if (_disposed || fresh.isEmpty) return;

    // Merge: replace the newest portion of messages with fresh data.
    // Keep any older paginated messages that aren't in the fresh batch.
    final freshIds = fresh.map((m) => m.msgId).toSet();
    final oldestFreshId = int.tryParse(fresh.last.msgId);
    final older = _messages.where((m) => !freshIds.contains(m.msgId)).toList();
    if (oldestFreshId != null) {
      _messages = [...fresh, ...older.where((m) {
        final mid = int.tryParse(m.msgId);
        return mid != null && mid < oldestFreshId;
      })];
    } else {
      _messages = [...fresh, ...older.where((m) => m.timestamp <= fresh.last.timestamp)];
    }
    _autoDownloadMedia(fresh);
    notifyListeners();
  }

  /// Start periodic polling for the active chat (rare safety-net fallback).
  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
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
    final String? oldAvatar = idx >= 0 ? _chats[idx].avatarPath : null;
    if (idx >= 0) {
      _chats[idx] = updated;
    } else {
      _chats.insert(0, updated);
    }
    // When a peer's userpic finishes downloading, repaint any on-screen
    // notification for that peer — same event that refreshes chat-list avatars,
    // mirroring AyuGram's downloaderTaskFinished → updatePeerPhoto().
    if (updated.avatarPath.isNotEmpty && updated.avatarPath != oldAvatar) {
      onPeerAvatarUpdated?.call(
          updated.accountId, updated.chatId, updated.avatarPath);
    }
    // Update active chat if it matches.
    if (_activeChat?.accountId == updated.accountId && _activeChat?.chatId == updated.chatId) {
      _activeChat = updated;
    }
    // Refresh forum topic list when a topic chat or its parent forum is updated.
    if (_forumParentChat != null && _forumParentChat!.accountId == updated.accountId) {
      if (updated.type == ChatType.topic ||
          (updated.isForum && updated.chatId == _forumParentChat!.chatId)) {
        _debouncedRefreshForumTopics();
      }
    }
    // Refresh saved sublists when Saved Messages chat is updated (pin/unpin from another device).
    if (updated.isSelf && _isViewingSavedSublists &&
        _savedSublistsAccountId == updated.accountId) {
      _debouncedRefreshSavedSublists();
    }
    // Track archive presence from chat updates.
    if (updated.isArchived) _hasArchivedChats = true;
    notifyListeners();
    // This chat's mute state is now known — let the notification system flush
    // anything it parked for it while the chat was uncached.
    onMuteStateMaybeResolved?.call();
  }

  void _handleChatRemoved(ChatRemovedEvent event) {
    if (_disposed) return;
    _chats.removeWhere((c) => c.chatId == event.chatId && (event.accountId.isEmpty || c.accountId == event.accountId));
    if (_activeChat?.chatId == event.chatId && (event.accountId.isEmpty || _activeChat?.accountId == event.accountId)) {
      _activeChat = null;
      _messages = [];
    }
    // Refresh forum topics if a topic was removed from the active forum.
    if (_forumParentChat != null &&
        (event.accountId.isEmpty || _forumParentChat!.accountId == event.accountId)) {
      _debouncedRefreshForumTopics();
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

      if (_appState.filterEngine.isFiltered(msg, _appState, chatType: chat?.type)) return;

      String stickerEmoji = '';
      if (msg.mediaType == 6 && msg.contentText.isNotEmpty) {
        stickerEmoji = msg.contentText;
      }

      final notifText = _applySpoilerEntities(msg.contentText, msg.contentRich);
      // Mask login codes from Telegram's service accounts. Mirrors AyuGram's
      // getNotificationOptions(): spoilerLoginCode = !out && (peer.isNotificationsUser
      // || peer.isVerifyCodes). isNotificationsUser == id 333000|777000,
      // isVerifyCodes == id 489000 — well-known service IDs hardcoded in Telegram
      // Desktop itself (data_peer.h/.cpp), not invented here. AyuGram checks the
      // PEER (chat) id; we check chatId first with a senderId fallback.
      const loginCodePeerIds = {'333000', '777000', '489000'};
      final isLoginCodeSender = !msg.isOutgoing &&
          (loginCodePeerIds.contains(event.chatId) ||
              loginCodePeerIds.contains(msg.senderId));

      // A message that personally mentions me (Telegram `mentioned` flag) in a
      // group/channel pierces the chat mute (AyuGram specialNotificationPeer);
      // a "mention" in a DM is just a normal message, so gate on non-DM.
      final mentionsMeInGroup = msg.mentionsMe && chat?.type != ChatType.dm;

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
        // Saved Messages / self chat. Distinguishes a fired self-reminder
        // ("📅 Reminder") from a scheduled message sent to another chat
        // ("📅 PeerName") in _composeTitle, and gates the "You" subtitle —
        // mirrors AyuGram's peer->isSelf() (notifications_manager.cpp:1582).
        isSelf: chat?.isSelf ?? false,
        isForumTopic: msg.topicId.isNotEmpty,
        topicTitle: msg.topicName,
        forwardFrom: msg.forwardFrom,
        // Per-message count is 0/1 (matches AyuGram's `isForwarded ? 1 : 0`).
        // NotificationSystem groups consecutive forwards from the same sender
        // and raises it >1 → "Forwarded N messages"; that grouping keys on
        // senderId (populated below), so without it all forwards collapse.
        forwardCount: msg.forwardFrom.isNotEmpty ? 1 : 0,
        stickerEmoji: stickerEmoji,
        hasSpoiler: msg.mediaSpoiler,
        // Captions show for photo/video/audio/voice/GIF/file — matches AyuGram's
        // MediaFile::notificationText(), which appends originalText for all these
        // document types via WithCaptionNotificationText (data_media_types.cpp).
        // Sticker(6) carries its emoji in contentText, not a caption, so it is
        // excluded; poll/location/contact/invoice have their own text.
        caption: (msg.contentText.isNotEmpty &&
                const {1, 2, 3, 4, 7, 8}.contains(msg.mediaType))
            ? msg.contentText
            : '',
        pollQuestion: msg.pollQuestion,
        // Quiz vs regular poll — selects lng_reaction_quiz over lng_reaction_poll
        // for a reaction to a quiz (AyuGram poll->quiz(), notifications_manager.cpp:1205).
        isQuiz: msg.pollQuiz,
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
        // Whether the user can send a text reply here — gates the inline reply
        // button (shouldHideReplyButton). The Go engine's computeWriteRestriction
        // returns writeRestrictionType > 0 for ANY send restriction (banned /
        // restricted / no-post-rights / forbidden / deactivated) and 0 only when
        // no ban applies (telegram.go:16171), so 0 == can write. AyuGram hides the
        // reply button on !CanSendTexts(peer) (notifications_manager.cpp:1097-1099).
        canSendText: (chat?.writeRestrictionType ?? 0) == 0,
        spoilerLoginCode: isLoginCodeSender,
        contentRich: msg.contentRich,
        isReaction: msg.isReaction,
        reactionEmoji: msg.reactionEmoji,
        reactorName: msg.reactorName,
        reactedToType: msg.reactedToType,
        isPollVote: msg.isPollVote,
        pollVoteOption: msg.pollVoteOption,
        // Sender identity — used by NotificationSystem to group forwards/albums
        // by author and to dedup per thread.
        senderId: msg.senderId,
        // Forum-topic root id keys per-topic dedup/clear in NotificationSystem.
        topicRootId: msg.topicRootId,
        // Muted-chat tracking. `isSenderMuted` is the mention SENDER's individual
        // mute (AyuGram's isMuted(notifyBy)); we don't cache per-user mute, so it
        // is false — meaning a mention from any sender pierces a muted group.
        // `mentionsMe` carries the bypass eligibility; `muteStateUnknown` defers
        // the decision when the chat isn't cached yet (mute genuinely unknown),
        // matching AyuGram's SkipState::Unknown → checkDelayed.
        isSenderMuted: false,
        mentionsMe: mentionsMeInGroup,
        muteStateUnknown: chat == null,
        // Reactor == peer only in 1:1 chats, where the reactor's name duplicates
        // the chat title, so it's hidden (AyuGram: reactionFrom != peer).
        isReactorPeer: (msg.isReaction || msg.isPollVote) &&
            chat?.type == ChatType.dm,
        // Multi-account label appended to the title (AyuGram addTargetAccountName).
        multiAccount: _appState.accounts.length > 1,
        accountUsername: _notifAccountLabel(event.accountId),
        // Per-chat ringtone volume override. AyuGram sources this from
        // ringtoneVolume(peer, topicRootId, monoforumPeerId) (per-peer
        // PeerNotifySettings); the Go bridge does not expose per-peer notify
        // settings yet (AccountGetNotifySettings is skipped in dispatch_gen.go),
        // so it stays 0 and NotificationSoundPlayer falls back to the global
        // notification volume -- matching AyuGram's no-override fallback.
        perChatVolume: 0,
      ));
    }
    // Refresh saved sublists when messages arrive in Saved Messages.
    final savedChat = _chats.where((c) =>
        c.accountId == event.accountId && c.chatId == event.chatId && c.isSelf).firstOrNull;
    if (savedChat != null) {
      _debouncedRefreshSavedSublists();
    }
  }

  // Label for the account that received a notification, appended to the title
  // when more than one account is logged in. Mirrors AyuGram's
  // addTargetAccountName(): prefer the username, fall back to the display name.
  String _notifAccountLabel(String accountId) {
    final acc =
        _appState.accounts.where((a) => a.id == accountId).firstOrNull;
    if (acc == null) return '';
    return acc.username.isNotEmpty ? acc.username : acc.displayName;
  }

  void _handleMsgEdited(MsgEditedEvent event) {
    if (_disposed) return;
    if (_isEditHistoryView) return;
    if (_isDeletedMessagesView) return;
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

  void _handleMsgReactionsUpdated(MsgReactionsUpdatedEvent event) {
    if (_disposed) return;
    if (_activeChat?.accountId != event.accountId || _activeChat?.chatId != event.chatId) return;
    final idx = _messages.indexWhere((m) => m.msgId == event.msgId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(reactions: event.reactions);
      notifyListeners();
    }
  }

  void _handleTyping(TypingEvent event) {
    if (_disposed) return;
    if (_appState.filtersEnabled) {
      final uid = int.tryParse(event.userId);
      if (uid != null && _appState.isShadowBanned(uid)) return;
    }
    final name = event.userName.isNotEmpty ? event.userName : event.userId;
    _typingUsers[event.chatId] = (name: name, action: event.action);
    notifyListeners();

    // Clear typing after 6s (guard against notifyListeners after dispose).
    Future.delayed(const Duration(seconds: 6), () {
      if (_disposed) return;
      if (_typingUsers[event.chatId]?.name == name) {
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

  // ── Media-player playlist navigation ──────────────────────────────────────
  // Mirrors AyuGram Media::Player::Instance::moveInPlaylist
  // (media_player_instance.cpp:531). The playlist is the active chat's shared-
  // media overview for ONE kind: music (MusicFile) when the current track is a
  // song, otherwise voice + round-video messages (RoundVoiceFile, which AyuGram
  // bundles together). AyuGram's slice is a flat_set<MsgId> in ascending order,
  // so delta +1 (next) advances to a newer message and -1 (previous) to an
  // older one. Our _messages list is newest-first, so a newer message sits at a
  // lower index.

  /// Register the shared [AudioService] so a track queued for download-then-play
  /// (see [moveAudioInPlaylist]) can start once its file arrives. Called once
  /// from main.dart where both providers are in scope.
  void setAudioService(AudioService audio) {
    _audioServiceRef = audio;
  }

  /// The active chat's ordered audio playlist, newest-first. [isSong] selects
  /// music (mediaType 3); otherwise voice + round video (mediaType 4/5).
  List<CachedMessage> _audioPlaylist(String chatId, bool isSong) {
    final items = _messages.where((m) {
      if (m.chatId != chatId) return false;
      return isSong ? m.mediaType == 3 : (m.mediaType == 4 || m.mediaType == 5);
    }).toList();
    // Newest-first by numeric msgId, so direction stays correct even if the
    // in-memory order was perturbed by inserts/edits.
    items.sort((a, b) =>
        (int.tryParse(b.msgId) ?? 0).compareTo(int.tryParse(a.msgId) ?? 0));
    return items;
  }

  /// Step [delta] within the current track's playlist and play the neighbour,
  /// mirroring AyuGram moveInPlaylist (delta +1 = next/newer, -1 = previous/
  /// older). Leaves playback stopped when there is no neighbour (matches
  /// moveInPlaylist returning false → StoppedAtEnd stays finished). If the
  /// neighbour isn't cached yet it is downloaded first, then played on arrival
  /// (AyuGram streams it; we play once the file is local).
  void moveAudioInPlaylist(AudioService audio, int delta) {
    if (_disposed) return;
    _audioServiceRef = audio;
    final chatId = audio.currentChatId;
    final curMsgId = audio.currentMsgId;
    if (chatId.isEmpty || curMsgId.isEmpty) return;
    final playlist = _audioPlaylist(chatId, audio.currentIsSong);
    final curIdx = playlist.indexWhere((m) => m.msgId == curMsgId);
    if (curIdx < 0) return; // current track not in the loaded playlist
    // Newest-first list: next (delta +1, newer) is a lower index.
    final targetIdx = curIdx - delta;
    if (targetIdx < 0 || targetIdx >= playlist.length) return; // no neighbour
    _playAudioMessage(audio, playlist[targetIdx], fromMsgId: curMsgId);
  }

  /// Play [msg] as the active audio track. Downloads first if not cached,
  /// deferring playback to [_handleDownloadComplete] via [_pendingAutoplayMsgId].
  void _playAudioMessage(AudioService audio, CachedMessage msg,
      {required String fromMsgId}) {
    if (msg.mediaLocalPath.isEmpty) {
      _pendingAutoplayMsgId = msg.msgId;
      _pendingAutoplayFromMsgId = fromMsgId;
      if (msg.mediaDownloadState != 1) requestDownload(msg);
      return;
    }
    _pendingAutoplayMsgId = null;
    _pendingAutoplayFromMsgId = null;
    _startAudioPlayback(audio, msg);
  }

  /// Hand [msg] to the [AudioService], reconstructing the song access-hash /
  /// file-reference from mediaExtra exactly as the message-bubble play buttons do.
  void _startAudioPlayback(AudioService audio, CachedMessage msg) {
    final isSong = msg.mediaType == 3;
    int accessHash = 0;
    List<int> fileRef = const [];
    if (isSong) {
      final parts = msg.mediaExtra.split(':');
      if (parts.length == 2) {
        accessHash = int.tryParse(parts[0]) ?? 0;
        try {
          fileRef = base64.decode(parts[1]);
        } catch (_) {}
      }
    }
    audio.playVoice(
      msg.mediaLocalPath,
      msg.msgId,
      chatId: msg.chatId,
      performer: isSong ? msg.audioPerformer : msg.senderName,
      title: isSong ? msg.audioTitle : '',
      msgTimestamp: msg.timestamp,
      accountId: msg.accountId,
      docId: msg.mediaRemoteRef,
      accessHash: accessHash,
      fileRef: fileRef,
      isSong: isSong,
    );
  }

  /// If [msg] is the neighbour queued by [moveAudioInPlaylist] while it
  /// downloaded, and the audio context hasn't moved on since, start it now.
  void _maybeAutoplayDownloaded(CachedMessage msg) {
    final audio = _audioServiceRef;
    if (audio == null || _pendingAutoplayMsgId != msg.msgId) return;
    // Abort if the user started a different track while we were downloading.
    if (audio.currentMsgId != _pendingAutoplayFromMsgId) {
      _pendingAutoplayMsgId = null;
      _pendingAutoplayFromMsgId = null;
      return;
    }
    if (msg.mediaLocalPath.isEmpty) return; // download produced no file
    _pendingAutoplayMsgId = null;
    _pendingAutoplayFromMsgId = null;
    _startAudioPlayback(audio, msg);
  }

  String? getAltQualityPath(String msgId, int seq) => _altQualityPaths['$msgId:$seq'];

  void requestAltQualityDownload(CachedMessage msg, int seq) {
    _engine.requestDownload(msg.accountId, msg.chatId, msg.msgId, seq: seq);
  }

  void _handleDownloadProgress(DownloadProgressEvent event) {
    if (_disposed) return;
    final prev = _downloadProgress[event.msgId];
    _downloadProgress[event.msgId] = event;
    if (prev != null && event.bytesTotal > 0 && prev.bytesTotal > 0) {
      final prevPct = prev.bytesRecv / prev.bytesTotal;
      final curPct = event.bytesRecv / event.bytesTotal;
      if ((curPct - prevPct).abs() < 0.02 && curPct < 1.0) return;
    }
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
      _maybeAutoplayDownloaded(_messages[idx]);
    }
  }

  void _handleUserStatus(UserStatusEvent event) {
    if (_disposed) return;
    // Our OWN status only ever reaches us from another logged-in device, so it
    // is the cOtherOnline signal — route it to the notification delay instead
    // of rendering it as a (meaningless) online dot on Saved Messages.
    final selfId = _appState.selfUserIdFor(event.accountId);
    if (selfId.isNotEmpty && event.userId == selfId) {
      onSelfStatus?.call(event.accountId, event.isOnline, event.lastSeenMs);
      return;
    }
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
    _forumTopicDebounce?.cancel();
    _savedSublistDebounce?.cancel();
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
