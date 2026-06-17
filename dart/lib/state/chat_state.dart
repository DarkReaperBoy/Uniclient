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
import '../state/support_templates.dart';
import '../data/emoji_data.dart';
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
  // After a jumpToMessage the shown window is centered on a past target, so beyond
  // its loaded newer-context half there are still more NEWER messages to load when
  // scrolling back toward the present (AyuGram's loadMessagesDown direction).
  // Tracked separately from _hasMoreMessages.
  bool _loadingMessagesDown = false;
  bool _hasMoreMessagesDown = false;
  bool _isFirstLoad = true;
  DateTime? _jumpedUntil; // suppress polling refresh until this time
  // chatId → live typing/send-action entries, ONE per user (deduped, ordered by
  // arrival). Mirrors AyuGram's SendActionPainter keeping a per-history set of
  // typers (`_typing.emplace_or_assign(user, …)`, history_view_send_action.cpp:83)
  // so a group can render "N people are typing" / "A and B are typing" instead of
  // collapsing every event to the single last sender.
  final Map<String, List<_TypingEntry>> _typingUsers = {};
  final Map<String, bool> _onlineUsers = {}; // "accountId:chatId" → isOnline (DMs only)
  // "accountId:userId" → (kind, lastSeenMs) for DM subtitle text.
  final Map<String, ({String kind, int lastSeenMs})> _userLastSeen = {};
  final Map<String, String> _senderAvatars = {}; // senderId → base64 avatar thumbnail
  final Map<String, Map<String, String>> _avatarCache = {}; // "accountId:chatId" → {senderId → b64}
  final Set<String> _senderAvatarsFetching = {}; // senderIds with an in-flight lazy avatar fetch
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
  /// notification system dismisses that thread's already-shown incoming
  /// notifications. When a forum topic or monoforum sublist is the read thread,
  /// [topicRootId]/[sublistPeerId] are non-empty so ONLY that sub-thread is
  /// cleared (AyuGram clearIncomingFromTopic/clearIncomingFromSublist); both
  /// empty means the whole chat (clearIncomingFromHistory). Mirrors AyuGram's
  /// History::inboxRead path (history/history.cpp:2105).
  void Function(String accountId, String chatId, String topicRootId,
      String sublistPeerId)? onChatRead;

  /// Fired when a chat/thread is opened/activated, so the notification system
  /// clears that thread's notifications. For a forum topic or sublist
  /// [topicRootId]/[sublistPeerId] are non-empty so ONLY that sub-thread is
  /// cleared (AyuGram clearFromTopic/clearFromSublist, called from
  /// openNotificationMessage, notifications_manager.cpp:1354-1356); both empty
  /// clears the whole history (clearFromHistory). This is what keeps opening one
  /// forum topic from wiping its sibling topics.
  void Function(String accountId, String chatId, String topicRootId,
      String sublistPeerId)? onChatActivated;

  /// Fired when a message is deleted/unsent in ANY chat (not just the active
  /// one), so the notification system dismisses that message's on-screen popup.
  /// Mirrors AyuGram's History::destroyMessage → System::clearFromItem
  /// (history/history.cpp:630).
  void Function(String accountId, String chatId, String messageId)?
      onMessageDeleted;

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

  // §31.7: Server-side reaction-tag search results. When ≥1 tag is selected the
  // message list shows these (fetched via messages.search with saved_reaction —
  // AyuGram SearchTagFromQuery → searchMessages) instead of client-filtering the
  // loaded history. Paginated by the last result's msgId.
  List<CachedMessage> _taggedMessages = [];
  bool _taggedSearchLoading = false;
  bool _taggedHasMore = true;
  int _taggedOffsetId = 0;
  int _taggedSearchSeq = 0; // bumped on every tag change to drop stale responses

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
  Timer? _avatarNotifyDebounce; // coalesces per-sender avatar repaints into one
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
    // With a reaction tag selected, show the server-search results (only tagged
    // messages, properly paginated) — not a client-side filter of the loaded
    // window. Mirrors AyuGram converting the tag into a messages.search query.
    if (_selectedReactionTagIds.isEmpty) return _messages;
    return _taggedMessages;
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
  bool get loadingMessages =>
      _selectedReactionTagIds.isEmpty ? _loadingMessages : _taggedSearchLoading;
  bool get hasMoreMessages =>
      _selectedReactionTagIds.isEmpty ? _hasMoreMessages : _taggedHasMore;
  bool get hasMoreMessagesDown => _hasMoreMessagesDown;
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

  /// Display subject for a chat's typing/send-action state — now the FULL
  /// aggregated text (not just one name), so the existing typing widgets render
  /// "N people are typing" / "A and B are typing" verbatim. Null when idle.
  String? typingUserFor(String chatId) =>
      typingSummaryFor(chatId, isGroup: _isGroupChat(chatId))?.text;

  /// Effective send-action for a chat (drives the typing-dots vs record/upload/
  /// sticker animation). 'typing' whenever ≥1 plain typer is active.
  String typingActionFor(String chatId) =>
      typingSummaryFor(chatId, isGroup: _isGroupChat(chatId))?.action ?? 'typing';

  /// Aggregated typing / send-action summary for a chat, mirroring AyuGram's
  /// SendActionPainter::updateNeedsAnimating (history_view_send_action.cpp:245-369):
  /// >2 plain typers → "N people are typing" (lng_many_typing); exactly 2 →
  /// "A and B are typing" (lng_users_typing); 1 → "A is typing" (group,
  /// lng_user_typing) or "typing" (DM, lng_typing); else the first non-game send
  /// action ("A is sending a photo" / "sending a photo"); and when EVERY active
  /// action is PlayGame, the aggregated "N people are playing a game" /
  /// "A and B are playing a game" / "A is playing a game" / "playing a game"
  /// (lng_*_playing_game). Plain typers take precedence over other send actions,
  /// exactly like AyuGram keeping `_typing` separate from `_sendActions`.
  /// Returns null when idle.
  ({String text, String action})? typingSummaryFor(String chatId, {required bool isGroup}) {
    _pruneTyping(chatId);
    final list = _typingUsers[chatId];
    if (list == null || list.isEmpty) return null;
    final typers = list.where((e) => e.action == 'typing').toList();
    if (typers.length > 2) {
      return (text: '${typers.length} people are typing', action: 'typing');
    } else if (typers.length == 2) {
      return (
        text: '${_firstName(typers[0].name)} and ${_firstName(typers[1].name)} are typing',
        action: 'typing',
      );
    } else if (typers.length == 1) {
      return isGroup
          ? (text: '${_firstName(typers[0].name)} is typing', action: 'typing')
          : (text: 'typing', action: 'typing');
    }
    // No plain typers — AyuGram shows the FIRST non-game send action (PlayGame
    // yields an empty string in its switch, so it is skipped); if EVERY active
    // action is PlayGame it aggregates them instead
    // (history_view_send_action.cpp:265-369).
    final nonGame = list.where((e) => e.action != 'game_play').toList();
    if (nonGame.isNotEmpty) {
      final a = nonGame.first;
      final label = _sendActionLabel(a.action);
      return isGroup
          ? (text: '${_firstName(a.name)} is $label', action: a.action)
          : (text: label, action: a.action);
    }
    // Everyone is playing a game → lng_(many|users|user)_playing_game /
    // lng_playing_game (history_view_send_action.cpp:345-368).
    if (list.length > 2) {
      return (text: '${list.length} people are playing a game', action: 'game_play');
    } else if (list.length == 2) {
      return (
        text: '${_firstName(list[0].name)} and ${_firstName(list[1].name)} are playing a game',
        action: 'game_play',
      );
    }
    return isGroup
        ? (text: '${_firstName(list.first.name)} is playing a game', action: 'game_play')
        : (text: 'playing a game', action: 'game_play');
  }

  /// Whether [chatId] belongs to a group/channel/topic (drives whether the
  /// typing string includes the sender's name, like AyuGram's `peer->isUser()`).
  bool _isGroupChat(String chatId) {
    final c = _chats.where((c) => c.chatId == chatId).firstOrNull;
    return c != null && c.type != ChatType.dm;
  }

  /// First whitespace-delimited token of a name (≈ AyuGram's `user->firstName`).
  static String _firstName(String name) {
    final t = name.trim();
    if (t.isEmpty) return name;
    final sp = t.indexOf(' ');
    return sp > 0 ? t.substring(0, sp) : t;
  }

  /// Verb phrase for a non-typing send action (matches the labels used by the
  /// typing widgets, ← AyuGram lng_user_action_* strings).
  static String _sendActionLabel(String action) {
    switch (action) {
      case 'record_video': return 'recording video';
      case 'upload_video': return 'sending video';
      case 'record_audio': return 'recording voice';
      case 'upload_audio': return 'sending audio';
      case 'upload_photo': return 'sending photo';
      case 'upload_document': return 'sending file';
      // AyuGram maps ChooseLocation/ChooseContact to lng_typing / lng_user_typing
      // — plain "typing" / "X is typing", no distinct strings
      // (history_view_send_action.cpp:296-299).
      case 'geo_location':
      case 'choose_contact':
        return 'typing';
      // Singular game label (lng_playing_game); multi-player aggregation is
      // handled in typingSummaryFor.
      case 'game_play': return 'playing a game';
      case 'record_round': return 'recording video message';
      case 'upload_round': return 'sending video message';
      case 'choose_sticker': return 'choosing sticker';
      default: return 'typing';
    }
  }

  /// Drop expired typing entries for a chat; returns true if anything changed.
  /// Each entry carries its own expiry (6s for most actions, 10s for PlayGame —
  /// AyuGram kStatusShowClientside* in history_view_send_action.cpp:31-43).
  bool _pruneTyping(String chatId) {
    final list = _typingUsers[chatId];
    if (list == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final before = list.length;
    list.removeWhere((e) => e.expiresAt <= now);
    if (list.isEmpty) _typingUsers.remove(chatId);
    return list.length != before;
  }

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
    // A tag change restarts the server search from scratch (or cancels it).
    _taggedMessages = [];
    _taggedHasMore = true;
    _taggedOffsetId = 0;
    _taggedSearchSeq++; // invalidate any in-flight response
    notifyListeners();
    if (_selectedReactionTagIds.isNotEmpty) {
      _runTaggedSearch();
    }
  }

  /// Selected tags as core reaction strings: 'custom_<docId>' for a custom
  /// emoji, otherwise the raw emoji (the `_selectedReactionTagIds` keys are
  /// 'custom:<id>' / 'emoji:<e>'; see [_reactionTagKey]).
  List<String> _selectedReactionStrings() {
    return _selectedReactionTagIds.map((key) {
      if (key.startsWith('custom:')) return 'custom_${key.substring('custom:'.length)}';
      if (key.startsWith('emoji:')) return key.substring('emoji:'.length);
      return key;
    }).toList();
  }

  /// Run (or paginate) the server-side reaction-tag search for Saved Messages.
  /// Replaces the old whole-history client-side paging: only tagged messages are
  /// fetched, scoped to the open sublist when there is one.
  Future<void> _runTaggedSearch({bool more = false}) async {
    final accountId = _savedSublistsAccountId;
    final chat = _activeChat;
    if (accountId.isEmpty || chat == null || _selectedReactionTagIds.isEmpty) return;
    if (_taggedSearchLoading) return;
    if (more && !_taggedHasMore) return;

    _taggedSearchLoading = true;
    final seq = ++_taggedSearchSeq;
    final savedPeerId = _activeSublist?.peerId ?? '';
    final reactions = _selectedReactionStrings();
    final offsetId = more ? _taggedOffsetId : 0;
    notifyListeners();

    try {
      final results = await _engine.searchSavedMessagesByReaction(
        accountId,
        chatId: chat.chatId,
        savedPeerId: savedPeerId,
        reactions: reactions,
        offsetId: offsetId,
        limit: 30,
      );
      if (_disposed || seq != _taggedSearchSeq) return; // superseded by a newer change
      if (more) {
        _taggedMessages.addAll(results);
      } else {
        _taggedMessages = results;
      }
      _taggedHasMore = results.length >= 30;
      if (_taggedMessages.isNotEmpty) {
        _taggedOffsetId = int.tryParse(_taggedMessages.last.msgId) ?? 0;
      }
    } catch (e) {
      Debug.log('chat_state', 'searchSavedMessagesByReaction: $e');
    } finally {
      if (seq == _taggedSearchSeq) {
        _taggedSearchLoading = false;
        notifyListeners();
      }
    }
  }

  void clearReactionTagSelection() {
    if (_selectedReactionTagIds.isNotEmpty) {
      _selectedReactionTagIds.clear();
      _taggedMessages = [];
      _taggedHasMore = true;
      _taggedOffsetId = 0;
      _taggedSearchSeq++; // cancel any in-flight search
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
        _forumRecentTopics[key] = _recentTopicsByDate(topics);
        notifyListeners();
      }).catchError((_) {
        _forumTopicsFetching.remove(key);
      });
    }
    return const [];
  }

  /// Whether the recent-topics list for a forum chat has finished loading (vs
  /// still being fetched). Mirrors AyuGram `Forum::topicsList()->loaded()`,
  /// which `TopicsView` uses to pick "No chats" over "Loading…" in the empty
  /// state (dialogs_topics_view.cpp:113,212-214). The key is present in
  /// `_forumRecentTopics` only after `getForumTopics` resolves, so a still-
  /// fetching forum (which `recentTopicsFor` returns `const []` for) reports
  /// not-loaded, and a loaded-but-topicless forum reports loaded.
  bool forumTopicsLoaded(String accountId, String chatId) =>
      _forumRecentTopics.containsKey('$accountId:$chatId');

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
      // The scheduled view set _hasMoreMessages=false; reset it so upward
      // pagination works again in the normal view (like returnToLatest).
      _hasMoreMessages = true;
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
    // The edit-history view set _hasMoreMessages=false; reset it so upward
    // pagination works again in the normal view (like returnToLatest).
    _hasMoreMessages = true;
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
    // The deleted-messages view set _hasMoreMessages=false; reset it so upward
    // pagination works again in the normal view (like returnToLatest).
    _hasMoreMessages = true;
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
      // AyuGram ChatFilter::contains keeps any history whose badge state.unread
      // is set (data_chat_filters.cpp:379-385: the NoRead clause passes on
      // `state.unread || state.mention`). A manually marked-unread chat HAS
      // state.unread == true even with zero unread messages, so excludeRead
      // must NOT drop it — hence the `!c.isUnreadMark` guard. (folderUnreadBadge
      // already counts such chats as `marks`; this keeps the list consistent.)
      if (folder.excludeRead &&
          c.unreadCount == 0 &&
          c.unreadMentionCount == 0 &&
          !c.isUnreadMark) {
        return false;
      }
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

  /// Folder / "All Chats" sidebar badge value: the number of unread **chats**
  /// (not the sum of unread messages), mirroring AyuGram's
  /// `window_filters_menu.cpp:343`:
  ///   count = (chats + marks) - (includeMuted ? 0 : chatsMuted + marksMuted)
  /// where `chats` counts chats with unread messages, `marks` counts chats
  /// manually marked unread (no unread messages), and the `*Muted` terms are
  /// their muted subsets. The badge is muted-styled only when [includeMuted]
  /// is set and every counted chat is muted (`includeMuted && count == muted`).
  /// Archived chats are excluded (the archive carries its own badge).
  ({int count, bool allMuted}) folderUnreadBadge(
    String? folderId, {
    required bool includeMuted,
  }) {
    var chats = 0, chatsMuted = 0, marks = 0, marksMuted = 0;
    for (final c in chatsForFolder(folderId)) {
      if (c.isArchived) continue;
      if (c.unreadCount > 0) {
        chats++;
        if (c.isMuted) chatsMuted++;
      } else if (c.isUnreadMark) {
        marks++;
        if (c.isMuted) marksMuted++;
      }
    }
    final muted = chatsMuted + marksMuted;
    final count = (chats + marks) - (includeMuted ? 0 : muted);
    return (count: count, allMuted: includeMuted && count == muted);
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
    } catch (e) {
      Debug.log('chat_state', 'await _engine.deleteFolder(accountId, folderId): $e');
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
    bool excludeMuted = false,
    bool excludeRead = false,
    bool excludeArchived = false,
    List<String> excludeChatIds = const [],
    List<String> pinnedChatIds = const [],
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
      excludeMuted: excludeMuted,
      excludeRead: excludeRead,
      excludeArchived: excludeArchived,
      excludeChatIds: excludeChatIds,
      pinnedChatIds: pinnedChatIds,
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
    List<String> pinnedChatIds = const [],
    bool isChatList = false,
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
      pinnedChatIds: pinnedChatIds,
      isChatList: isChatList,
      staticTitle: staticTitle,
      colorIndex: colorIndex,
      emoticon: emoticon,
    );
    await loadFoldersForAccount(accountId);
  }

  /// Whether [chatId] is in the "always include" list of any loaded folder.
  /// Mirrors AyuGram's removeFromChatsFilters(history).empty() check
  /// (moderate_messages_box.cpp:1034-1042) used to decide whether to offer the
  /// "Remove … from all folders" checkbox in the delete/leave box.
  bool isChatInAnyFolder(String chatId) {
    for (final folder in _folders) {
      if (folder.chatIds.contains(chatId)) return true;
    }
    return false;
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
          pinnedChatIds: folder.pinnedChatIds,
          isChatList: folder.isChatList,
          staticTitle: folder.staticTitle,
          colorIndex: folder.colorIndex,
          emoticon: folder.emoticon,
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

  /// Apply a new sidebar order produced by a drag on the vertical folder rail.
  /// [orderedIds] is the *unified* order in which the string `'0'` marks the
  /// "All Chats" position (premium users can reposition it among folders —
  /// AyuGram `window_filters_menu.cpp` keeps id 0 in the reorderable `_list`).
  /// Folders are reordered to match and the full order — including the `0`
  /// sentinel — is persisted via `messages.updateDialogFiltersOrder`, mirroring
  /// AyuGram's `applyReorder`. The All position is not returned by `getFolders`
  /// (the engine skips `dialogFilterDefault`), so it is tracked in the sidebar
  /// widget for the session; the folder order itself round-trips normally.
  void applyFolderOrder(List<String> orderedIds) {
    final byId = {for (final f in _folders) f.id: f};
    final newFolders = <FolderInfo>[];
    for (final id in orderedIds) {
      final f = byId[id];
      if (f != null) newFolders.add(f);
    }
    if (newFolders.length == _folders.length) {
      _folders = newFolders;
    }
    if (_foldersForAccount.isNotEmpty) {
      _engine.reorderDialogFilters(
        _foldersForAccount,
        orderedIds.map((id) => int.tryParse(id) ?? 0).toList(),
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
    } catch (e) {
      Debug.log('chat_state', 'final limits = await _engine.getFolderLimits(accountId): $e');
    }
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
    // Full activation, identical to a normal open — but WITHOUT pushing onto the
    // history stack (we're moving the cursor within it, not adding an entry).
    // Routing through _activateChat fixes the prior partial copy that skipped
    // notification dismissal, polling, channel/keyboard resets and saved-
    // sublists/forum routing.
    _activateChat(chat);
    return true;
  }

  /// Re-read the local support-template files (`tl_*.txt` under the working-dir
  /// `TEMPLATES` folder) and return the parse / IO errors (empty == success).
  /// Port of `Support::Templates::reload()` (support_templates.cpp:464), bound
  /// to the `SupportReloadTemplates` shortcut. The shortcut handler toasts the
  /// result, mirroring AyuGram's `Ui::Toast::Show` (cpp:465-470). Previously
  /// this wrongly reloaded the dialog list (`loadChats()`).
  Future<List<String>> reloadSupportTemplates() {
    return SupportTemplates.instance.reload();
  }

  void openChat(ChatInfo chat) {
    // Push onto the back/forward history stack and reset the cursor to the top.
    // History *navigation* (navigateChatHistory) reuses the same activation via
    // _activateChat but must NOT mutate the stack, so the stack ops live here.
    _chatOpenHistory.remove(chat.chatId);
    _chatOpenHistory.insert(0, chat.chatId);
    if (_chatOpenHistory.length > _maxChatOpenHistory) {
      _chatOpenHistory.removeRange(_maxChatOpenHistory, _chatOpenHistory.length);
    }
    _chatHistoryIndex = 0;
    _activateChat(chat);
  }

  /// Full chat activation shared by [openChat] and [navigateChatHistory]:
  /// forum/saved-sublists routing, active-chat swap, on-screen-notification
  /// dismissal, section-state reset, message/pinned/scheduled loads, avatar/
  /// online/group-call fetches, and polling start. Does NOT touch the back/
  /// forward history stack — callers own that. Mirrors AyuGram routing both a
  /// normal open AND a history move through the identical showThread activation
  /// path (window_session_controller.cpp:2291), so notifications clear and
  /// section state resets the same way every time.
  void _activateChat(ChatInfo chat) {
    if (chat.isForum && _forumParentChat?.chatId != chat.chatId) {
      _checkAndOpenForum(chat);
    }
    if (chat.isSelf && chat.type == ChatType.dm) {
      openSavedSublists(chat.accountId);
    } else if (_isViewingSavedSublists) {
      closeSavedSublists();
    }
    SpoilerRevealManager.instance.hideAll();
    _activeChat = chat;
    // Opening a chat dismisses its on-screen notifications. A forum TOPIC clears
    // only itself (AyuGram clearFromTopic), keyed by the parent forum chat id +
    // topic root id — NOT the whole forum, which would wipe every sibling topic.
    // A normal chat (or forum CONTAINER) clears its whole history.
    if (chat.type == ChatType.topic && chat.parentId.isNotEmpty) {
      onChatActivated?.call(chat.accountId, chat.parentId, chat.chatId, '');
    } else {
      onChatActivated?.call(chat.accountId, chat.chatId, '', '');
    }
    _openedUnreadCount = chat.unreadCount;
    _messages = [];
    _pinnedMessages = [];
    _hasMoreMessages = true;
    _isFirstLoad = true;
    _jumpedUntil = null; // clear jump lock on chat change
    _hasMoreMessagesDown = false;
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
    _senderAvatarsFetching.clear();
    if (chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic) {
      // Restore previously-fetched sender thumbnails for this chat; avatars for
      // senders not yet seen are fetched lazily per-message in
      // _ensureSenderAvatars as their messages load — AyuGram loads only the
      // userpics that actually paint (Message::displayFromPhoto), never a bulk
      // participant fetch.
      if (_avatarCache.containsKey(cacheKey)) {
        _senderAvatars.addAll(_avatarCache[cacheKey]!);
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
      _forumRecentTopics[key] = _recentTopicsByDate(topics);
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

  /// AyuGram Forum::reorderLastTopics (data/data_forum.cpp:233) — the recent-
  /// topic names shown on a collapsed forum row are ordered purely by last-
  /// message date (topMessageId proxy) DESCENDING, with NO pinned-first
  /// priority. (Pinned-first is only for the full topic list, _sortTopics.)
  /// Returns the top kShowTopicNamesCount (=8) without mutating [topics].
  static List<ForumTopic> _recentTopicsByDate(List<ForumTopic> topics) {
    final sorted = [...topics];
    sorted.sort((a, b) {
      final aId = int.tryParse(a.topMessageId) ?? 0;
      final bId = int.tryParse(b.topMessageId) ?? 0;
      return bId.compareTo(aId);
    });
    return sorted.take(8).toList();
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
    } catch (e) {
      Debug.log('chat_state', 'final topics = await _engine.getForumTopics(chat.accountI...: $e');
    }
    _forumFirstLoadDone = true;
    final key = '${chat.accountId}:${chat.chatId}';
    _forumRecentTopics[key] = _recentTopicsByDate(_forumTopics);
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
        var added = 0;
        for (final t in topics) {
          if (!existingIds.contains(t.id)) {
            _forumTopics.add(t);
            added++;
          }
        }
        _sortTopics(_forumTopics);
        // AyuGram (data_forum.cpp:171-184) keeps paging while a page comes back
        // non-empty AND the offset advances — it stops only on an empty page
        // or a stalled offset (`_offset == previousOffset`), NOT when a page is
        // shorter than kTopicsPerPage. The engine requests 500/page but
        // Telegram caps each response well below that, so the old
        // `topics.length >= 500` test flipped hasMore false after the first
        // short page and stalled forums past ~40 topics. `added > 0` is the
        // Dart analog of the offset advancing (new topics arrived).
        _forumHasMore = topics.isNotEmpty && added > 0;
      }
    } catch (e) {
      Debug.log('chat_state', 'int offsetDate = 0: $e');
    }
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
    } catch (e) {
      Debug.log('chat_state', 'final topics = await _engine.getForumTopics(chat.accountI...: $e');
    }
    if (chat == _forumParentChat) {
      final key = '${chat.accountId}:${chat.chatId}';
      _forumRecentTopics[key] = _recentTopicsByDate(_forumTopics);
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
      } catch (e) {
        Debug.log('chat_state', 'final (pinned, _) = _engine.getPinnedSavedSublists(accoun...: $e');
      }

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
    } catch (e) {
      Debug.log('chat_state', 'final (pinned, _) = _engine.getPinnedSavedSublists(accoun...: $e');
    }
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
    } catch (e) {
      Debug.log('chat_state', 'final (sublists, total) = _engine.getSavedSublists(: $e');
    }
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
    // Opening a saved-messages sublist dismisses only that sublist's
    // notifications (AyuGram clearFromSublist), like opening a chat clears its
    // history. The host chat is the Saved Messages (self) chat being viewed.
    final host = _activeChat;
    if (host != null) {
      onChatActivated?.call(host.accountId, host.chatId, '', sublist.peerId);
    }
    _selectedReactionTagIds.clear();
    _taggedMessages = [];
    _taggedHasMore = true;
    _taggedOffsetId = 0;
    _taggedSearchSeq++;
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
    _taggedMessages = [];
    _taggedHasMore = true;
    _taggedOffsetId = 0;
    _taggedSearchSeq++;
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
    } catch (e) {
      Debug.log('chat_state', 'final tags = _engine.getSavedReactionTags(: $e');
    }
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
    } catch (e) {
      Debug.log('chat_state', '_engine.renameSavedReactionTag(: $e');
    }
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
    if (_activeChat == null) return;
    // Reaction-tag filter active → paginate the server search, not the history.
    if (_selectedReactionTagIds.isNotEmpty) {
      _runTaggedSearch(more: true);
      return;
    }
    if (_loadingMessages || !_hasMoreMessages) return;
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

  /// Highlight state for jump-to-message: the UI fade-highlights this msgId once
  /// after a jump completes, then calls [clearPendingHighlight].
  String? _pendingHighlightMsgId;
  String? get pendingHighlightMsgId => _pendingHighlightMsgId;
  void clearPendingHighlight() { _pendingHighlightMsgId = null; }

  void setHighlightMessage(String msgId) {
    _pendingHighlightMsgId = msgId;
    notifyListeners();
  }

  /// Jump to a window of messages CENTERED on the message at [timestampMs], so the
  /// target lands mid-viewport with context on BOTH sides. Mirrors AyuGram's
  /// HistoryWidget::firstLoadMessages jump branch (history_widget.cpp:4420-4423),
  /// which requests `offset = -kMessagesPerPage/2; offsetId = _showAtMsgId;` — the
  /// MTProto idiom that fetches ~half newer + half older around the target.
  ///
  /// The engine's GetMessages treats beforeMs/afterMs as mutually exclusive (one
  /// query each, cache_msgs.go:100-125), so we issue two parallel reads and stitch
  /// them newest-first:
  ///   - older-or-equal half: `beforeMs: timestampMs + 1` → [target, older…]
  ///   - strictly-newer half: `afterMs: timestampMs`      → [newer…]
  /// The `+1` boundary keeps same-timestamp siblings in the older half only, so the
  /// two sets are disjoint by timestamp (we de-dup by msgId defensively anyway).
  ///
  /// Suppresses polling refresh for 10s — only while genuinely jumped away from the
  /// bottom — so the user can read the area. If [highlightMsgId] is set, the UI
  /// highlights that message with a fade animation.
  Future<void> jumpToMessage(int timestampMs, {String? highlightMsgId}) async {
    final chat = _activeChat;
    if (chat == null) return;
    SpoilerRevealManager.instance.hideAll();

    // kMessagesPerPage = 50; offset = -loadCount/2 → ~25 newer + 25 older (incl. target).
    const half = 25;
    final results = await Future.wait([
      _engine.getMessages(chat.accountId, chat.chatId,
          beforeMs: timestampMs + 1, limit: half),
      _engine.getMessages(chat.accountId, chat.chatId,
          afterMs: timestampMs, limit: half),
    ]);
    if (_disposed) return;
    final olderHalf = results[0]; // [target, older…] newest-first
    final newerHalf = results[1]; // [newer…] newest-first
    if (olderHalf.isEmpty && newerHalf.isEmpty) return;

    // Stitch newest-first: newer context on top, target + older context below.
    final seen = <String>{};
    final combined = <CachedMessage>[];
    for (final m in [...newerHalf, ...olderHalf]) {
      if (seen.add(m.msgId)) combined.add(m);
    }
    _messages = combined;

    // Older (up) direction: keep loadable; loadMoreMessages self-corrects at the top.
    _hasMoreMessages = true;
    // Newer (down) direction: we are "jumped" only if a full newer page came back,
    // i.e. messages exist beyond the loaded window. A short newer half means the
    // present is already in view, so we're at the bottom (not jumped).
    _hasMoreMessagesDown = newerHalf.length >= half;
    _loadingMessagesDown = false;
    if (_hasMoreMessagesDown) {
      _jumpedUntil = DateTime.now().add(const Duration(seconds: 10));
    } else {
      _jumpedUntil = null;
    }
    _pendingHighlightMsgId = highlightMsgId;
    _preloadCustomEmoji(combined, chat.accountId);
    _autoDownloadMedia(combined);
    notifyListeners();
  }

  /// Whether the message list is in a "jumped" state (not showing latest messages).
  bool get isJumped => _jumpedUntil != null && DateTime.now().isBefore(_jumpedUntil!);

  /// Load messages NEWER than the currently-loaded newest, for scrolling back
  /// toward the present after a jumpToMessage. Mirrors AyuGram
  /// HistoryWidget::loadMessagesDown (history_widget.cpp:4522). New messages are
  /// prepended (the list is newest-first); reaching the present clears the
  /// jumped state so normal append/polling resumes.
  Future<void> loadMoreMessagesDown() async {
    if (_disposed || _loadingMessagesDown || !_hasMoreMessagesDown) return;
    final chat = _activeChat;
    if (chat == null || _messages.isEmpty) return;
    _loadingMessagesDown = true;
    const limit = 50;
    final afterMs = _messages.first.timestamp;
    final newer = await _engine.getMessages(
        chat.accountId, chat.chatId, afterMs: afterMs, limit: limit);
    if (_disposed) return;
    _loadingMessagesDown = false;
    if (newer.isEmpty) {
      // Reached the present — resume normal (non-jumped) behaviour.
      _hasMoreMessagesDown = false;
      _jumpedUntil = null;
      notifyListeners();
      return;
    }
    // Prepend (newest-first), de-duping any same-timestamp boundary overlap.
    final existingIds = _messages.map((m) => m.msgId).toSet();
    _messages = [
      ...newer.where((m) => !existingIds.contains(m.msgId)),
      ..._messages,
    ];
    if (newer.length < limit) {
      _hasMoreMessagesDown = false;
      _jumpedUntil = null;
    }
    _preloadCustomEmoji(newer, chat.accountId);
    _autoDownloadMedia(newer);
    notifyListeners();
  }

  /// Return to the latest messages (undo jumpToMessage).
  void returnToLatest() {
    final chat = _activeChat;
    if (chat == null) return;
    _jumpedUntil = null;
    _hasMoreMessagesDown = false;
    _loadingMessagesDown = false;
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

    if (forwardMsgs.isNotEmpty && AyuForward.needsIntelligentForward(forwardMsgs, chat)) {
      // Restricted forward (no-forwards bypass / resend-as-own). AyuGram creates
      // a ForwardState here (ayu_forward.cpp:287,330,332), so the AyuForward
      // progress bar replaces the compose area in the destination chat.
      final progress = ForwardProgress();
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
      // Non-restricted (plain) forward. AyuGram falls through both early-return
      // branches of `ApiWrap::forwardMessages` to the normal Telegram batch path,
      // which never constructs a ForwardState — so no AyuForward progress bar is
      // shown (apiwrap.cpp:3494-3503). Register NO ForwardProgress here: the
      // compose area stays put and the forward fires as an ordinary batch.
      for (final id in msgIds) {
        await _engine.forwardMessage(chat.accountId, chat.chatId, id, toChatId,
          dropAuthor: dropAuthor, dropCaptions: dropCaptions,
          silent: silent, scheduleDate: scheduleDate);
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
    // Dismiss only the read thread's incoming notifications: a forum topic or
    // saved sublist clears itself (AyuGram clearIncomingFromTopic/Sublist), not
    // the whole forum / Saved Messages.
    if (chat.type == ChatType.topic && chat.parentId.isNotEmpty) {
      onChatRead?.call(chat.accountId, chat.parentId, chat.chatId, '');
    } else if (_isViewingSavedSublists && _activeSublist != null) {
      onChatRead?.call(chat.accountId, chat.chatId, '', _activeSublist!.peerId);
    } else {
      onChatRead?.call(chat.accountId, chat.chatId, '', '');
    }
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
    // AyuGram picks the emoticon theme's day/night variant from the app's
    // CURRENT theme (IsNightMode()), never the OS brightness — a forced
    // light/night theme must override the system setting
    // (data_cloud_themes.cpp:234, window_theme.cpp:1411).
    final isDark = _appState.isNightMode;
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

  void clearHistory(String accountId, String chatId, {bool revoke = false}) {
    _engine.clearHistory(accountId, chatId, revoke: revoke);
    // If this is the active chat, clear local messages.
    if (_activeChat?.accountId == accountId && _activeChat?.chatId == chatId) {
      _messages.clear();
      notifyListeners();
    }
    loadChats();
  }

  void deleteChat(String accountId, String chatId, {bool revoke = false}) {
    _engine.deleteChat(accountId, chatId, revoke: revoke);
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
    // Generic whole-chat read (no specific topic/sublist context here).
    onChatRead?.call(accountId, chatId, '', '');
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

  Future<void> addChatToFolder(String accountId, String chatId, String folderId) async {
    _engine.addChatToFolder(accountId, chatId, folderId);
    // Reload so FolderInfo.chatIds (and chatsForFolder) reflect the addition
    // immediately, like editFolder / removeChatFromAllFolders. The engine call
    // is a synchronous round-trip (_callRaw), so the reload sees fresh data.
    await loadFoldersForAccount(accountId);
  }

  Future<void> removeSavedReactionTag(String accountId, {String emoji = '', int customId = 0}) async {
    _engine.removeSavedReactionTag(accountId, emoji: emoji, customId: customId);
    // Reload so the removed tag disappears from the tag filter bar immediately,
    // like the sibling renameSavedReactionTag. loadSavedReactionTags resolves
    // the account from _savedSublistsAccountId (set in the Saved Messages view
    // where reaction tags live); the engine call is a synchronous _callRaw
    // round-trip, so the reload sees fresh data.
    await loadSavedReactionTags();
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

  /// Message search restricted to a specific sender within a chat — the
  /// "Search from [user]" filter (AyuGram ChatSearchIn `_from` section).
  Future<List<SearchResult>> searchMessagesFrom(String accountId, String chatId, String query, String senderId, {int limit = 50}) {
    return _engine.searchMessagesFrom(accountId, chatId, query, senderId, limit: limit);
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
    _ensureSenderAvatars(newMsgs);
    notifyListeners();
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
      } catch (e) {
        Debug.log('chat_state', 'final entities = jsonDecode(msg.contentRich) as List: $e');
      }
    }
    if (ids.isNotEmpty) {
      CustomEmojiCache.instance.preloadBatch(ids, accountId, _engine);
    }
  }

  /// Lazily fetch sender avatar thumbnails for the senders that actually appear
  /// in [msgs] (one cheap stripped-thumb request per new sender), instead of
  /// bulk-fetching up to 1000 group/channel members on chat open. Mirrors
  /// AyuGram loading only each painted message's own sender userpic
  /// (Message::displayFromPhoto → loadUserpic, history_view_message.cpp:1878).
  /// Results are cached per chat in [_avatarCache] so reopening is instant.
  void _ensureSenderAvatars(List<CachedMessage> msgs) {
    final chat = _activeChat;
    if (chat == null) return;
    if (chat.type != ChatType.group &&
        chat.type != ChatType.channel &&
        chat.type != ChatType.topic) {
      return;
    }
    final accountId = chat.accountId;
    final cacheKey = '$accountId:${chat.chatId}';
    // senderId → one of that sender's message ids. The msgId lets the core
    // resolve members whose access hash isn't cached, via inputUserFromMessage
    // (cached-history senders otherwise come back with no avatar).
    final toFetch = <String, String>{};
    for (final m in msgs) {
      final sid = m.senderId;
      if (sid.isEmpty || m.isOutgoing || m.isService) continue;
      if (_senderAvatars.containsKey(sid)) continue;
      if (_senderAvatarsFetching.contains(sid)) continue;
      toFetch.putIfAbsent(sid, () => m.msgId);
    }
    if (toFetch.isEmpty) return;
    toFetch.forEach((sid, msgId) {
      _senderAvatarsFetching.add(sid);
      _engine.getUserAvatarThumb(accountId, sid, chatId: chat.chatId, msgId: msgId).then((b64) {
        if (_disposed) return;
        _senderAvatarsFetching.remove(sid);
        if (b64 == null || b64.isEmpty) return;
        // Always cache for this chat (used on reopen). Only push into the live
        // map + repaint if the user is still viewing the same chat.
        (_avatarCache[cacheKey] ??= {})[sid] = b64;
        if (_activeChat?.accountId == accountId && _activeChat?.chatId == chat.chatId) {
          _senderAvatars[sid] = b64;
          // Coalesce repaints: a group page can resolve 10-20 sender avatars in
          // a burst, and one notifyListeners() per avatar rebuilds the whole
          // message list each time — the flicker + jank on chat open. Debounce
          // so a burst collapses into a single rebuild.
          _scheduleAvatarNotify();
        }
      }).catchError((_) {
        _senderAvatarsFetching.remove(sid);
      });
    });
  }

  /// Debounced repaint for streamed-in sender avatars (see _ensureSenderAvatars).
  void _scheduleAvatarNotify() {
    if (_disposed) return;
    _avatarNotifyDebounce?.cancel();
    _avatarNotifyDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!_disposed) notifyListeners();
    });
  }

  /// Fetch the online member count for a group/channel via the platform API.
  Future<void> _loadOnlineCount(String accountId, String chatId) async {
    try {
      final count = await _engine.getOnlineCount(accountId, chatId);
      if (count != _groupOnlineCount) {
        _groupOnlineCount = count;
        notifyListeners();
      }
    } catch (e) {
      Debug.log('chat_state', 'final count = await _engine.getOnlineCount(accountId, cha...: $e');
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
    } catch (e) {
      Debug.log('chat_state', 'await _engine.toggleConnectedBotPaused(chat.accountId, ch...: $e');
    }
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
    } catch (e) {
      Debug.log('chat_state', 'await _engine.disablePeerConnectedBot(chat.accountId, cha...: $e');
    }
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
    // Forum topics are NOT top-level dialogs — they live under their parent
    // forum and are reached via the topic list (getForumTopics). A topic chat
    // update must never enter the main chat list (it would clutter it with
    // dozens of per-topic rows). The update still flows through below to drive
    // the forum-topic-list refresh and active-chat swap. Drop any topic row
    // that was inserted by an older build/snapshot, then skip the list write.
    if (updated.type == ChatType.topic) {
      if (idx >= 0) _chats.removeAt(idx);
    } else if (idx >= 0) {
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
    // Never inject a live incoming message into a read-only special view. The
    // deleted-messages / scheduled / edit-history views are sourced solely from
    // local storage, like AyuGram's separate read-only history sections
    // (AyuMessages::getDeletedMessages). _handleMsgEdited guards the same set.
    if (isActiveChat &&
        !_isScheduledView &&
        !_isEditHistoryView &&
        !_isDeletedMessagesView) {
      final exists = _messages.any((m) =>
        m.msgId == event.message.msgId ||
        (event.message.localId.isNotEmpty && m.localId == event.message.localId));
      if (!exists) {
        _messages.insert(0, event.message);
        // Feed emoji from freshly-arrived INCOMING messages into the global
        // recent list that inline suggestions prioritize. AyuGram increments
        // recentEmoji() for every emoji the text engine renders — sent OR
        // received (UiIntegration::defaultEmojiVariant, ui_integration.cpp:471).
        // Outgoing echoes are skipped here: they were already counted at send
        // time (chat_view), so counting them again would double-rate them.
        if (!event.message.isOutgoing && event.message.contentText.isNotEmpty) {
          EmojiKeywords.instance.recordRecentFromText(event.message.contentText);
        }
        onNewActiveMessage?.call(event.message);
        _ensureSenderAvatars([event.message]);
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
        // Service message (joined/pinned/photo changed/etc.) → empty subtitle,
        // matching notificationHeader()'s isService() short-circuit
        // (history_item.cpp:2768-2769).
        isService: msg.isService,
        // isPostHidingAuthor(): a broadcast-channel post hides its author when
        // there is no distinct user sender — `from_id` is absent, so the post is
        // attributed to the channel itself (no signature profiles). The notif
        // subtitle is then suppressed (the channel name is already the title).
        // With signature profiles the sender IS a user (senderId set), so the
        // author name is shown. Megagroups (ChatType.group) are not posts, so
        // this never fires for them. Mirrors AyuGram isPostHidingAuthor()
        // (history_item.cpp:3952-3959).
        isPostHidingAuthor:
            chat?.type == ChatType.channel && msg.senderId.isEmpty,
        isSilent: msg.isSilent,
        timestamp: msg.timestamp,
        messageType: msg.mediaType,
        // One-time (view-once) voice/video → "One-time …" notification variant.
        // Media-level self-destruct TTL (messageMediaDocument.ttl_seconds), the
        // signal AyuGram's MediaFile::notificationText() keys on via
        // media->ttlSeconds() (data_media_types.cpp:1273-1286); only the voice(4)
        // and videonote(5) bodies consume it.
        isOneTime: msg.mediaTtlSeconds > 0,
        isScheduled: msg.scheduleDate > 0,
        // Saved Messages / self chat. Distinguishes a fired self-reminder
        // ("📅 Reminder") from a scheduled message sent to another chat
        // ("📅 PeerName") in _composeTitle, and gates the "You" subtitle —
        // mirrors AyuGram's peer->isSelf() (notifications_manager.cpp:1582).
        isSelf: chat?.isSelf ?? false,
        // Replies chat → dedicated reply-arrow glyph instead of "R" initials in
        // the avatar-less notification userpic (mirrors isSelf's Saved Messages
        // bookmark) — AyuGram GenerateUserpic peer->isRepliesChat()
        // (notifications_utilities.cpp:29-30).
        isReplies: chat?.isReplies ?? false,
        isForumTopic: msg.topicId.isNotEmpty,
        topicTitle: msg.topicName,
        // Monoforum (channel "Direct Messages") sublist title. A message carrying a
        // saved_peer_id whose chat is NOT the user's own Saved Messages is a
        // monoforum sublist — AyuGram's savedSublist() with a non-null parentChat()
        // (history_item.cpp:4255-4264). The title then becomes
        // "{sublistPeer shortName} ({channel})" (notifications_manager.cpp:1576-1578).
        // Requiring a cached chat (the channel) both supplies the parenthesised name
        // and rules out the self Saved-Messages sublist (parentChat()==null), which
        // keeps the plain title. sublistPeerId is forwarded too so NotificationSystem
        // can clear/dedup this thread per-sublist (main.dart clearIncomingFromSublist).
        isMonoforumSublist:
            chat != null && !chat.isSelf && msg.sublistPeerId.isNotEmpty,
        sublistPeerName: msg.sublistPeerName,
        sublistPeerId: msg.sublistPeerId,
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
        // excluded; poll/location/contact have their own text. A PAID-MEDIA invoice
        // (type 12) is the lone invoice exception: MediaInvoice::notificationText()
        // appends parent()->originalText() as the caption ("Photo, {caption}") when
        // _invoice.isPaidMedia, while a plain invoice shows only its title
        // (data_media_types.cpp:2185-2193).
        caption: ((const {1, 2, 3, 4, 7, 8}.contains(msg.mediaType) ||
                    (msg.mediaType == 12 && msg.invoiceIsPaidMedia)) &&
                msg.contentText.isNotEmpty)
            ? msg.contentText
            : '',
        // Document/audio filename — MediaFile::notificationText() shows it in
        // place of the generic "File"/"Audio file" type string for a named file
        // (case 8) or audio file (case 3) (data_media_types.cpp:1287-1294).
        mediaFileName: msg.mediaFileName,
        pollQuestion: msg.pollQuestion,
        // Quiz vs regular poll — selects lng_reaction_quiz over lng_reaction_poll
        // for a reaction to a quiz (AyuGram poll->quiz(), notifications_manager.cpp:1205).
        isQuiz: msg.pollQuiz,
        gameTitle: msg.gameTitle,
        invoiceTitle: msg.invoiceTitle,
        // Paid-media invoice (messageMediaPaidMedia) → notification body renders
        // "Photo"/"Video"[, caption] instead of the title; firstVideo selects
        // which (AyuGram MediaInvoice::notificationText, data_media_types.cpp:2185-2193).
        invoiceIsPaidMedia: msg.invoiceIsPaidMedia,
        invoiceFirstVideo: msg.invoiceFirstVideo,
        contactName: msg.contactFirstName.isNotEmpty
            ? '${msg.contactFirstName} ${msg.contactLastName}'.trim()
            : '',
        isLiveLocation: msg.geoLive,
        // Venue/place title — MediaLocation::notificationText() appends it as the
        // caption ("Location, {title}"); empty for a plain geo point
        // (data_media_types.cpp:1701-1703).
        venueTitle: msg.venueTitle,
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
        // Per-chat ringtone volume override (AyuGram ringtoneVolume(peer,...) →
        // default-notify-type fallback, notifications_manager.cpp:763-772). The
        // 2-tier resolution (per-chat → per-type → 0) lives in AppState; 0 means
        // NotificationSoundPlayer falls back to the global notification volume.
        perChatVolume:
            _appState.ringtoneVolume(event.accountId, event.chatId, (chat?.type ?? ChatType.unspec).index),
        // Per-chat sound override (AyuGram sound(thread).none / .id). "None"
        // silences the alert; a custom ringtone supplies a local file the
        // sound player uses instead of the bundled default. Set via the
        // per-chat ringtone picker (info_panel); 0/'' = default.
        soundNone: _appState.chatSoundIsNone(event.accountId, event.chatId),
        soundDocumentPath: _appState.chatSoundPath(event.accountId, event.chatId),
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
      // Re-filter the edited message. AyuGram calls FiltersController::invalidate on
      // every message edit (data_session.cpp:2750) so the regex verdict is recomputed
      // from the new text: an incoming message edited to newly match a filter gets
      // hidden, and a hidden message edited to no longer match reappears. Without it the
      // stale per-message verdict in the cache survives until an unrelated rebuildCache().
      // groupedId invalidates the whole album (AyuGram invalidates every group member).
      // Gated on filtersEnabled, matching FiltersController::invalidate's early-out.
      // ← filters_controller.cpp:206-213, filters_cache_controller.cpp:216-225
      if (_appState.filtersEnabled) {
        _appState.filterEngine.invalidateMessage(
          event.chatId,
          event.msgId,
          groupedId: updated.groupedId,
        );
      }
      notifyListeners();
    }
  }

  void _handleMsgDeleted(MsgDeletedEvent event) {
    if (_disposed) return;
    // Pull the message's notification popup regardless of which chat is open —
    // AyuGram's History::destroyMessage fires System::clearFromItem for every
    // removal in any history, not only the active one (the active-chat guard
    // below is purely about updating the visible message list).
    onMessageDeleted?.call(event.accountId, event.chatId, event.msgId);
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = _typingUsers.putIfAbsent(event.chatId, () => <_TypingEntry>[]);
    // Per-action client-side window: PlayGame lingers 10s
    // (kStatusShowClientsidePlayGame), every other action 6s
    // (history_view_send_action.cpp:31-43).
    final isGame = event.action == 'game_play';
    final ttlMs = isGame ? 10000 : 6000;
    if (isGame) {
      // AyuGram (re-)emplaces PlayGame only when the user has no current action,
      // already has PlayGame, or the prior action has expired — a live non-game
      // send-action is never overridden by a game event
      // (history_view_send_action.cpp:123-129).
      final existing = list.where((e) => e.userId == event.userId).firstOrNull;
      if (existing != null &&
          existing.action != 'game_play' &&
          existing.expiresAt > now) {
        return;
      }
    }
    // Upsert this user's entry (dedup by userId), keeping every OTHER typer —
    // AyuGram `_typing` / `_sendActions` `emplace_or_assign(user, …)`.
    list.removeWhere((e) => e.userId == event.userId);
    list.add(_TypingEntry(event.userId, name, event.action, now + ttlMs));
    notifyListeners();

    // Re-evaluate after THIS entry's own client-side window; prune only expired
    // entries so other still-active typers are preserved (guard after dispose).
    Future.delayed(Duration(milliseconds: ttlMs), () {
      if (_disposed) return;
      if (_pruneTyping(event.chatId)) notifyListeners();
    });
  }

  /// Auto-download photos and small media for visible messages.
  void _autoDownloadMedia(List<CachedMessage> msgs) {
    // Mirror AyuGram Data::AutoDownload::Should()/ShouldAutoPlay()
    // (data/data_auto_download.cpp): gate every prefetch on the user's
    // per-source/per-type auto-download settings + byte limits instead of a
    // fixed policy. Source is the active chat's peer kind, matching
    // SourceFromPeer() (User→private / Chat|Megagroup→group / Channel→channel).
    final settings =
        _appState.getAutoDownloadForSource(_autoDownloadSource(_activeChat));
    final photos = settings['photos'] as bool? ?? true;
    final files = settings['files'] as bool? ?? false;
    final videos = settings['videos'] as bool? ?? true;
    final gifs = settings['gifs'] as bool? ?? true;
    final videoMessages = settings['videoMessages'] as bool? ?? true;
    // Saved values are bytes (the settings UI persists MB×1MiB); the unsaved
    // defaults are megabytes (10 / 50). Normalize both to a byte limit.
    final downloadLimit = _autoDownloadBytes(settings['downloadLimit'], 10);
    final autoPlayLimit = _autoDownloadBytes(settings['autoPlayLimit'], 50);

    for (final m in msgs) {
      if (!m.hasMedia || m.mediaDownloadState != 0) continue;
      if (m.mediaLocalPath.isNotEmpty) continue;
      final size = m.mediaFileSize;
      bool ok;
      switch (m.mediaType) {
        case 6: // sticker — AyuGram Should() always returns true for stickers
          ok = true;
          break;
        case 1: // photo
          ok = photos && _autoDownloadFits(size, downloadLimit);
          break;
        case 8: // file / document
          ok = files && _autoDownloadFits(size, downloadLimit);
          break;
        case 7: // gif (auto-play media → AutoPlayGIF limit)
          ok = gifs && _autoDownloadFits(size, autoPlayLimit);
          break;
        case 2: // video (auto-play media → AutoPlayVideo limit)
          ok = videos && _autoDownloadFits(size, autoPlayLimit);
          break;
        case 5: // round video message (auto-play → AutoPlayVideoMessage limit)
          ok = videoMessages && _autoDownloadFits(size, autoPlayLimit);
          break;
        default:
          // voice (4), music (3) and non-media types are streamed on demand in
          // AyuGram (Should() returns false), so they are not prefetched.
          ok = false;
      }
      if (ok) {
        _engine.requestDownload(m.accountId, m.chatId, m.msgId);
      }
    }
  }

  /// AyuGram Data::AutoDownload::SourceFromPeer — map the active chat to an
  /// auto-download source key. Forum topics live in a megagroup → 'group'.
  String _autoDownloadSource(ChatInfo? chat) {
    switch (chat?.type) {
      case ChatType.channel:
        return 'channel';
      case ChatType.group:
      case ChatType.topic:
        return 'group';
      default:
        return 'private';
    }
  }

  /// Normalize a stored auto-download size limit (bytes once saved, megabytes
  /// for the unsaved default) to a byte count.
  int _autoDownloadBytes(Object? raw, double defaultMb) {
    final v = (raw as num?)?.toDouble() ?? defaultMb;
    return (v > 10000 ? v : v * 1024 * 1024).round();
  }

  /// AyuGram Single::shouldDownload — fetch only when the limit is positive and
  /// the file fits. Unknown size (0) counts as fitting, matching `size<=limit`.
  bool _autoDownloadFits(int size, int limit) => limit > 0 && size <= limit;

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
  // lower index. The order/repeat-all/shuffle rules live in [AudioService]
  // (which owns those settings) — we just supply the ordered playlist and play
  // whatever track it picks.

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

  /// Step [delta] within [curMsgId]'s playlist and play the neighbour
  /// (delta +1 = next, -1 = previous). [chatId]/[curMsgId]/[isSong] are the
  /// finishing or displayed track's own context (not necessarily the bar's), so
  /// a song advances the music overview and a voice advances the voice+round
  /// overview independently even when both are loaded. The actual target is
  /// chosen by [AudioService.nextInPlaylist], which applies the order
  /// (default/reverse/shuffle) and repeat-all (modulo wrap) rules. Returns true
  /// if a neighbour was found (now playing or queued for download), false if
  /// none — matching AyuGram moveInPlaylist returning false → StoppedAtEnd stays
  /// finished. If the chosen neighbour isn't cached yet it is downloaded first,
  /// then played on arrival (AyuGram streams it; we play once the file is local).
  bool moveAudioInPlaylist(
      AudioService audio, String chatId, String curMsgId, bool isSong, int delta) {
    if (_disposed) return false;
    _audioServiceRef = audio;
    if (chatId.isEmpty || curMsgId.isEmpty) return false;
    final playlist = _audioPlaylist(chatId, isSong);
    if (playlist.isEmpty) return false;
    final targetMsgId = audio.nextInPlaylist(
      playlist: [for (final m in playlist) m.msgId],
      currentMsgId: curMsgId,
      delta: delta,
      isSong: isSong,
    );
    if (targetMsgId == null) return false; // no neighbour → track stays finished
    final targetIdx = playlist.indexWhere((m) => m.msgId == targetMsgId);
    if (targetIdx < 0) return false; // not in the loaded playlist (shouldn't happen)
    _playAudioMessage(audio, playlist[targetIdx], fromMsgId: curMsgId);
    return true;
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
        } catch (e) {
          Debug.log('chat_state', 'fileRef = base64.decode(parts[1]): $e');
        }
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
      // Document duration (seconds) gates the changeable-playback-speed rule:
      // a music file < 1 minute always plays at 1.0× (AyuGram
      // kMinLengthForChangeablePlaybackSpeed, data_audio_msg_id.cpp:14,28-30).
      durationSeconds: msg.mediaDuration,
      // mediaType 5 = round-video message (chat_state.dart:3083) — drives the
      // display-sleep power-save blocker while it plays.
      isRoundVideo: msg.mediaType == 5,
    );
  }

  /// If [msg] is the neighbour queued by [moveAudioInPlaylist] while it
  /// downloaded, and the audio context hasn't moved on since, start it now.
  void _maybeAutoplayDownloaded(CachedMessage msg) {
    final audio = _audioServiceRef;
    if (audio == null || _pendingAutoplayMsgId != msg.msgId) return;
    // Abort if the track we were advancing FROM is no longer loaded (the user
    // started something else). With two coexisting tracks the "from" track may
    // be the song or the voice, so check whether it is still active in either —
    // a finished track stays loaded until its neighbour replaces it.
    final fromMsgId = _pendingAutoplayFromMsgId;
    if (fromMsgId == null || !audio.isActiveMsg(fromMsgId)) {
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
    _avatarNotifyDebounce?.cancel();
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

/// One live typing / send-action entry for a chat — a single user with their
/// current action and a client-side expiry (AyuGram's per-user `_typing` /
/// `_sendActions` flat-map entries, history_view_send_action.cpp).
class _TypingEntry {
  final String userId;
  final String name;
  final String action;
  final int expiresAt; // epoch ms; entry is dropped once now ≥ expiresAt
  const _TypingEntry(this.userId, this.name, this.action, this.expiresAt);
}
