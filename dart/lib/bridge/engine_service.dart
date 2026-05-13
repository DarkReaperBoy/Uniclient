import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'bridge.dart';
import '../models/engine_models.dart';
import '../proto/models.pb.dart' as pb;
import '../proto/engine.pb.dart' as epb;
import '../utils/debug.dart';

// Re-export for local use — actual implementation in utils/safe_string.dart.
import '../utils/safe_string.dart';
String _safeStr(String s) => safeStr(s);

/// High-level wrapper around the FFI bridge for engine operations.
///
/// Serializes requests as protobuf BridgeRequest, deserializes BridgeResponse.
/// Engine events arrive as protobuf BridgeEvent with JSON-encoded engine_event.
class EngineService {
  final Bridge _bridge = Bridge();
  bool _initialized = false;

  // Event streams — engine pushes events, we parse and dispatch.
  final _authStateController = StreamController<AuthStateEvent>.broadcast();
  final _connStateController = StreamController<ConnStateEvent>.broadcast();
  final _accountListController = StreamController<List<AccountInfo>>.broadcast();
  final _chatUpdatedController = StreamController<ChatInfo>.broadcast();
  final _chatSnapshotController = StreamController<List<ChatInfo>>.broadcast();
  final _chatRemovedController = StreamController<ChatRemovedEvent>.broadcast();
  final _msgReceivedController = StreamController<MsgReceivedEvent>.broadcast();
  final _msgEditedController = StreamController<MsgEditedEvent>.broadcast();
  final _msgDeletedController = StreamController<MsgDeletedEvent>.broadcast();
  final _msgStatusController = StreamController<MsgStatusEvent>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  final _downloadProgressController = StreamController<DownloadProgressEvent>.broadcast();
  final _downloadCompleteController = StreamController<DownloadCompleteEvent>.broadcast();
  final _userStatusController = StreamController<UserStatusEvent>.broadcast();
  final _incomingCallController = StreamController<IncomingCallEvent>.broadcast();
  final _callStateController = StreamController<CallStateEvent>.broadcast();
  final _groupCallStateController = StreamController<GroupCallStateEvent>.broadcast();
  final _exportProgressController = StreamController<ExportProgressEvent>.broadcast();
  final _exportErrorController = StreamController<ExportErrorEvent>.broadcast();
  final _exportCompleteController = StreamController<ExportCompleteEvent>.broadcast();
  StreamSubscription<Uint8List>? _bridgeEventSub;

  Stream<AuthStateEvent> get onAuthState => _authStateController.stream;
  Stream<ConnStateEvent> get onConnState => _connStateController.stream;
  Stream<List<AccountInfo>> get onAccountList => _accountListController.stream;
  Stream<ChatInfo> get onChatUpdated => _chatUpdatedController.stream;
  Stream<List<ChatInfo>> get onChatSnapshot => _chatSnapshotController.stream;
  Stream<ChatRemovedEvent> get onChatRemoved => _chatRemovedController.stream;
  Stream<MsgReceivedEvent> get onMsgReceived => _msgReceivedController.stream;
  Stream<MsgEditedEvent> get onMsgEdited => _msgEditedController.stream;
  Stream<MsgDeletedEvent> get onMsgDeleted => _msgDeletedController.stream;
  Stream<MsgStatusEvent> get onMsgStatus => _msgStatusController.stream;
  Stream<TypingEvent> get onTyping => _typingController.stream;
  Stream<DownloadProgressEvent> get onDownloadProgress => _downloadProgressController.stream;
  Stream<DownloadCompleteEvent> get onDownloadComplete => _downloadCompleteController.stream;
  Stream<UserStatusEvent> get onUserStatus => _userStatusController.stream;
  Stream<IncomingCallEvent> get onIncomingCall => _incomingCallController.stream;
  Stream<CallStateEvent> get onCallState => _callStateController.stream;
  Stream<GroupCallStateEvent> get onGroupCallState => _groupCallStateController.stream;
  Stream<ExportProgressEvent> get onExportProgress => _exportProgressController.stream;
  Stream<ExportErrorEvent> get onExportError => _exportErrorController.stream;
  Stream<ExportCompleteEvent> get onExportComplete => _exportCompleteController.stream;

  bool get isInitialized => _initialized;

  /// Initialize the bridge and engine.
  Future<void> init({
    required String configDir,
    required String cacheDir,
    required String downloadDir,
    String vaultPassword = '',
    String? libraryPath,
  }) async {
    if (_initialized) return;

    _bridge.init(libraryPath: libraryPath);
    _bridgeEventSub = _bridge.events.listen(_handleBridgeEvent);

    final req = epb.EngineInitRequest()
      ..configDir = configDir
      ..cacheDir = cacheDir
      ..downloadDir = downloadDir
      ..vaultPassword = vaultPassword;

    final respBytes = _callRaw('__engine', 'Init', req.writeToBuffer());
    final resp = epb.EngineInitResponse.fromBuffer(respBytes);
    if (!resp.ok) {
      throw EngineException(resp.error.isNotEmpty ? resp.error : 'init failed');
    }

    _initialized = true;
  }

  // ── Account management ──

  List<AccountInfo> listAccounts() {
    final respBytes = _callRaw('__engine', 'ListAccounts', Uint8List(0));
    final resp = epb.EngineListAccountsResponse.fromBuffer(respBytes);
    return resp.accounts.map(_accountInfoFromProto).toList();
  }

  String addAccount(String platform) {
    final req = epb.EngineAddAccountRequest()..platform = platform;
    final respBytes = _callRaw('__engine', 'AddAccount', req.writeToBuffer());
    final resp = epb.EngineAddAccountResponse.fromBuffer(respBytes);
    return resp.accountId;
  }

  void removeAccount(String accountId) {
    final req = epb.EngineRemoveAccountRequest()..accountId = accountId;
    _callRaw('__engine', 'RemoveAccount', req.writeToBuffer());
  }

  void reorderAccounts(List<String> accountIds) {
    final req = epb.EngineReorderAccountsRequest()..accountIds.addAll(accountIds);
    _callRaw('__engine', 'ReorderAccounts', req.writeToBuffer());
  }

  Future<void> connectAccount(String accountId) async {
    final req = epb.EngineConnectAccountRequest()..accountId = accountId;
    await _callAsync('__engine', 'ConnectAccount', req.writeToBuffer());
  }

  Future<void> connectAllAccounts() async {
    await _callAsync('__engine', 'ConnectAllAccounts', Uint8List(0));
  }

  Future<void> disconnectAccount(String accountId) async {
    final req = epb.EngineDisconnectAccountRequest()..accountId = accountId;
    await _callAsync('__engine', 'DisconnectAccount', req.writeToBuffer());
  }

  // ── Auth flow ──

  Future<AuthStateData?> startAuth(String accountId) async {
    final req = epb.EngineStartAuthRequest()..accountId = accountId;
    final respBytes = await _callAsync('__engine', 'StartAuth', req.writeToBuffer());
    final resp = epb.EngineStartAuthResponse.fromBuffer(respBytes);
    return resp.hasState() ? _authStateFromProto(resp.state) : null;
  }

  Future<AuthStateData?> submitAuthInput(String accountId, String input) async {
    final req = epb.EngineSubmitAuthInputRequest()
      ..accountId = accountId
      ..input = input;
    final respBytes = await _callAsync('__engine', 'SubmitAuthInput', req.writeToBuffer());
    final resp = epb.EngineSubmitAuthInputResponse.fromBuffer(respBytes);
    return resp.hasState() ? _authStateFromProto(resp.state) : null;
  }

  void cancelAuth(String accountId) {
    final req = epb.EngineCancelAuthRequest()..accountId = accountId;
    _callRaw('__engine', 'CancelAuth', req.writeToBuffer());
  }

  // ── Chat list ──

  List<ChatInfo> getChatList({String accountId = '', bool archived = false, int limit = 50, int offset = 0}) {
    final req = epb.EngineGetChatListRequest()
      ..accountId = accountId
      ..archived = archived
      ..limit = limit
      ..offset = offset;
    final respBytes = _callRaw('__engine', 'GetChatList', req.writeToBuffer());
    final resp = epb.EngineGetChatListResponse.fromBuffer(respBytes);
    return resp.chats.map(_chatInfoFromProto).toList();
  }

  (List<SavedSublistInfo>, int) getSavedSublists(String accountId, {int limit = 50, int offsetDate = 0, int offsetId = 0, bool excludePinned = false}) {
    final req = epb.EngineGetSavedSublistsRequest()
      ..accountId = accountId
      ..limit = limit
      ..offsetDate = offsetDate
      ..offsetId = offsetId
      ..excludePinned = excludePinned;
    final respBytes = _callRaw('__engine', 'GetSavedSublists', req.writeToBuffer());
    final resp = epb.EngineGetSavedSublistsResponse.fromBuffer(respBytes);
    final sublists = resp.sublists.map(_savedSublistFromProto).toList();
    return (sublists, resp.totalCount);
  }

  (List<SavedSublistInfo>, int) getPinnedSavedSublists(String accountId) {
    final req = epb.EngineGetSavedSublistsRequest()
      ..accountId = accountId;
    final respBytes = _callRaw('__engine', 'GetPinnedSavedSublists', req.writeToBuffer());
    final resp = epb.EngineGetSavedSublistsResponse.fromBuffer(respBytes);
    final sublists = resp.sublists.map(_savedSublistFromProto).toList();
    return (sublists, resp.totalCount);
  }

  static SavedSublistInfo _savedSublistFromProto(epb.EngineSavedSublist s) {
    return SavedSublistInfo(
      peerId: s.peerId,
      peerName: s.peerName,
      avatarPath: s.avatarPath,
      type: s.type,
      isPinned: s.isPinned,
      topMessage: s.topMessage,
      lastMsgText: s.lastMsgText,
      lastMsgTime: s.lastMsgTime.toInt(),
      isSelf: s.isSelf,
      unreadCount: s.unreadCount,
    );
  }

  List<SavedReactionTagInfo> getSavedReactionTags(String accountId, {String sublistPeerId = ''}) {
    final req = epb.EngineGetSavedReactionTagsRequest()
      ..accountId = accountId
      ..sublistPeerId = sublistPeerId;
    final respBytes = _callRaw('__engine', 'GetSavedReactionTags', req.writeToBuffer());
    final resp = epb.EngineGetSavedReactionTagsResponse.fromBuffer(respBytes);
    return resp.tags.map(_savedReactionTagFromProto).toList();
  }

  void renameSavedReactionTag(String accountId, {String emoji = '', int customId = 0, String title = ''}) {
    final req = epb.EngineRenameSavedReactionTagRequest()
      ..accountId = accountId
      ..emoji = emoji
      ..customId = Int64(customId)
      ..title = title;
    _callRaw('__engine', 'RenameSavedReactionTag', req.writeToBuffer());
  }

  static SavedReactionTagInfo _savedReactionTagFromProto(epb.EngineSavedReactionTag t) {
    return SavedReactionTagInfo(
      emoji: t.emoji,
      customId: t.customId.toInt(),
      title: t.title,
      count: t.count,
    );
  }

  void saveDraft(String accountId, String chatId, String text) {
    final req = epb.EngineSaveDraftRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..text = text;
    _callRaw('__engine', 'SaveDraft', req.writeToBuffer());
  }

  void muteChat(String accountId, String chatId, bool muted, {int durationSeconds = 0}) {
    final req = epb.EngineMuteChatRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..muted = muted
      ..durationSeconds = durationSeconds;
    _callRaw('__engine', 'MuteChat', req.writeToBuffer());
  }

  void pinChat(String accountId, String chatId, bool pinned) {
    final req = epb.EnginePinChatRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..pinned = pinned;
    _callRaw('__engine', 'PinChat', req.writeToBuffer());
  }

  void toggleSavedDialogPin(String accountId, String peerId, bool pinned) {
    final req = epb.EnginePinChatRequest()
      ..accountId = accountId
      ..chatId = peerId
      ..pinned = pinned;
    _callRaw('__engine', 'ToggleSavedDialogPin', req.writeToBuffer());
  }

  void markSavedSublistRead(String accountId, String peerId) {
    final req = epb.EngineMarkSavedSublistReadRequest()
      ..accountId = accountId
      ..peerId = peerId;
    _callRaw('__engine', 'MarkSavedSublistRead', req.writeToBuffer());
  }

  void deleteSavedSublistHistory(String accountId, String peerId) {
    final req = epb.EngineDeleteSavedSublistHistoryRequest()
      ..accountId = accountId
      ..peerId = peerId;
    _callRaw('__engine', 'DeleteSavedSublistHistory', req.writeToBuffer());
  }

  void reorderPinnedDialogs(String accountId, List<String> chatIds) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_ids': chatIds,
    }));
    _callRaw('__engine', 'ReorderPinnedDialogs', Uint8List.fromList(payload));
  }

  void reorderDialogFilters(String accountId, List<int> filterIds) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'filter_ids': filterIds,
    }));
    _callRaw('__engine', 'ReorderDialogFilters', Uint8List.fromList(payload));
  }

  void archiveChat(String accountId, String chatId, bool archived) {
    final req = epb.EngineArchiveChatRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..archived = archived;
    _callRaw('__engine', 'ArchiveChat', req.writeToBuffer());
  }

  void setHistoryTTL(String accountId, String chatId, int period) {
    final req = epb.EngineSetHistoryTTLRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..period = period;
    _callRaw('__engine', 'SetHistoryTTL', req.writeToBuffer());
  }

  Future<void> blockUser(String accountId, String userId) async {
    final req = epb.EngineBlockUserRequest()
      ..accountId = accountId
      ..userId = userId;
    await _callAsync('__engine', 'BlockUser', req.writeToBuffer());
  }

  Future<void> unblockUser(String accountId, String userId) async {
    final req = epb.EngineUnblockUserRequest()
      ..accountId = accountId
      ..userId = userId;
    await _callAsync('__engine', 'UnblockUser', req.writeToBuffer());
  }

  Future<void> setUserNoForwardsFlags(
    String accountId,
    String userId, {
    bool myEnabled = false,
    bool peerEnabled = false,
  }) async {
    final req = epb.EngineSetUserNoForwardsFlagsRequest()
      ..accountId = accountId
      ..userId = userId
      ..myEnabled = myEnabled
      ..peerEnabled = peerEnabled;
    await _callAsync('__engine', 'SetUserNoForwardsFlags', req.writeToBuffer());
  }

  Future<void> banMember(String accountId, String chatId, String userId) async {
    final req = epb.EngineBanMemberRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..userId = userId;
    await _callAsync('__engine', 'BanMember', req.writeToBuffer());
  }

  Future<void> removeMember(String accountId, String chatId, String userId) async {
    final req = epb.EngineRemoveMemberRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..userId = userId;
    await _callAsync('__engine', 'RemoveMember', req.writeToBuffer());
  }

  Future<void> unbanChatMember(String accountId, String chatId, String userId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'user_id': userId,
    }));
    await _callAsync('__engine', 'UnbanMember', Uint8List.fromList(payload));
  }

  Future<void> demoteAdmin(String accountId, String chatId, String userId) async {
    final req = epb.EngineDemoteAdminRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..userId = userId;
    await _callAsync('__engine', 'DemoteAdmin', req.writeToBuffer());
  }

  Future<void> transferChannelOwnership(String accountId, String chatId, String userId, String password) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'user_id': userId,
      'password': password,
    }));
    await _callAsync('__engine', 'TransferChannelOwnership', Uint8List.fromList(payload));
  }

  Future<void> promoteAdmin(String accountId, String chatId, String userId) async {
    final req = epb.EnginePromoteAdminRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..userId = userId;
    await _callAsync('__engine', 'PromoteAdmin', req.writeToBuffer());
  }

  Future<void> promoteAdminWithRights(
    String accountId,
    String chatId,
    String userId,
    Map<String, bool> rights,
    String rank,
  ) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'user_id': userId,
      ...rights,
      'rank': rank,
    }));
    await _callAsync('__engine', 'PromoteAdminWithRights', Uint8List.fromList(payload));
  }

  Future<void> restrictMember(String accountId, String chatId, String userId) async {
    final req = epb.EngineRestrictMemberRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..userId = userId;
    await _callAsync('__engine', 'RestrictMember', req.writeToBuffer());
  }

  Future<void> restrictMemberWithRights(
    String accountId,
    String chatId,
    String userId,
    Map<String, bool> rights,
    int untilDate,
  ) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'user_id': userId,
      ...rights,
      'until_date': untilDate,
    }));
    await _callAsync('__engine', 'RestrictMemberWithRights', Uint8List.fromList(payload));
  }

  Future<void> reportSpam(String accountId, String chatId) async {
    final req = epb.EngineReportSpamRequest()
      ..accountId = accountId
      ..chatId = chatId;
    await _callAsync('__engine', 'ReportSpam', req.writeToBuffer());
  }

  Future<String> getLinkedChatId(String accountId, String chatId) async {
    final req = epb.EngineGetLinkedChatIdRequest()
      ..accountId = accountId
      ..chatId = chatId;
    final respBytes = await _callAsync('__engine', 'GetLinkedChatId', req.writeToBuffer());
    if (respBytes == null || respBytes.isEmpty) return '';
    return utf8.decode(respBytes);
  }

  Future<void> addContact(String accountId, String phone, String firstName, String lastName, {String note = ''}) async {
    final req = epb.EngineAddContactRequest()
      ..accountId = accountId
      ..phone = phone
      ..firstName = firstName
      ..lastName = lastName;
    if (note.isNotEmpty) {
      req.note = note;
    }
    await _callAsync('__engine', 'AddContact', req.writeToBuffer());
  }

  Future<void> suggestContactPhoto(String accountId, String userId, String photoPath) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'user_id': userId,
      'photo_path': photoPath,
    }));
    await _callAsync('__engine', 'SuggestContactPhoto', Uint8List.fromList(payload));
  }

  Future<void> setPersonalContactPhoto(String accountId, String userId, String photoPath) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'user_id': userId,
      'photo_path': photoPath,
    }));
    await _callAsync('__engine', 'SetPersonalContactPhoto', Uint8List.fromList(payload));
  }

  Future<void> clearPersonalContactPhoto(String accountId, String userId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'user_id': userId,
    }));
    await _callAsync('__engine', 'ClearPersonalContactPhoto', Uint8List.fromList(payload));
  }

  Future<void> deleteContact(String accountId, String userId) async {
    final req = epb.EngineDeleteContactRequest()
      ..accountId = accountId
      ..userId = userId;
    await _callAsync('__engine', 'DeleteContact', req.writeToBuffer());
  }

  void markChatRead(String accountId, String chatId, String upToMsgId) {
    final req = epb.EngineMarkChatReadRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..upToMsgId = upToMsgId;
    _callRaw('__engine', 'MarkChatRead', req.writeToBuffer());
  }

  void markChatUnread(String accountId, String chatId) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    _callRaw('__engine', 'MarkChatUnread', Uint8List.fromList(payload));
  }

  void addChatToFolder(String accountId, String chatId, String folderId) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'folder_id': folderId,
    }));
    _callRaw('__engine', 'AddChatToFolder', Uint8List.fromList(payload));
  }

  List<ChatInfo> getTopPeers(String accountId, {int limit = 20}) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'limit': limit,
    }));
    final respBytes = _callRaw('__engine', 'GetTopPeers', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return [];
    final list = json.decode(utf8.decode(respBytes)) as List<dynamic>;
    return list.map((e) => ChatInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  void removeSavedReactionTag(String accountId, {String emoji = '', int customId = 0}) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'emoji': emoji,
      'custom_id': customId,
    }));
    _callRaw('__engine', 'RemoveSavedReactionTag', Uint8List.fromList(payload));
  }

  List<ChatInfo> searchGlobalChats(String accountId, String query, {int limit = 20}) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'query': query,
      'limit': limit,
    }));
    final respBytes = _callRaw('__engine', 'SearchGlobalChats', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return [];
    final list = json.decode(utf8.decode(respBytes)) as List<dynamic>;
    return list.map((e) => ChatInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  List<ChatInfo> searchGlobalPosts(String accountId, String query, {int limit = 20}) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'query': query,
      'limit': limit,
    }));
    final respBytes = _callRaw('__engine', 'SearchGlobalPosts', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return [];
    final list = json.decode(utf8.decode(respBytes)) as List<dynamic>;
    return list.map((e) => ChatInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  void readMessageContents(String accountId, String chatId, String msgId) {
    final req = epb.EngineReadMessageContentsRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId;
    _callRaw('__engine', 'ReadMessageContents', req.writeToBuffer());
  }

  void reportMusicListen(String accountId, int docId, int accessHash, List<int> fileRef, int durationSec) {
    final req = epb.EngineReportMusicListenRequest()
      ..accountId = accountId
      ..docId = Int64(docId)
      ..accessHash = Int64(accessHash)
      ..fileRef = fileRef
      ..durationSec = durationSec;
    _callRaw('__engine', 'ReportMusicListen', req.writeToBuffer());
  }

  /// Fetch forum topics for a chat. Returns empty list if the platform
  /// doesn't support forum topics. Topics are cached in the engine DB.
  Future<List<ForumTopic>> getForumTopics(String accountId, String chatId) async {
    final req = epb.EngineGetForumTopicsRequest()
      ..accountId = accountId
      ..chatId = chatId;
    final respBytes = await _callAsync('__engine', 'GetForumTopics', req.writeToBuffer());
    if (respBytes.isEmpty) return [];
    final resp = epb.EngineGetForumTopicsResponse.fromBuffer(respBytes);
    return resp.topics.map(_forumTopicFromProto).toList();
  }

  Future<List<ForumTopic>> getForumTopicsWithOffset(
    String accountId, String chatId,
    {int offsetDate = 0, int offsetId = 0, int offsetTopic = 0}
  ) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'offset_date': offsetDate,
      'offset_id': offsetId,
      'offset_topic': offsetTopic,
    }));
    final respBytes = await _callAsync(
      '__engine', 'GetForumTopicsWithOffset', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return [];
    final resp = epb.EngineGetForumTopicsResponse.fromBuffer(respBytes);
    return resp.topics.map(_forumTopicFromProto).toList();
  }

  static ForumTopic _forumTopicFromProto(epb.EngineForumTopic p) => ForumTopic(
    id: p.id,
    title: p.title,
    colorId: p.colorId,
    iconEmojiId: p.iconEmojiId.toInt(),
    creatorId: p.creatorId,
    creationDate: p.creationDate.toInt(),
    isClosed: p.isClosed,
    isHidden: p.isHidden,
    isMy: p.isMy,
    isPinned: p.isPinned,
    unreadCount: p.unreadCount,
    unreadMentions: p.unreadMentions,
    unreadReactions: p.unreadReactions,
    topMessageId: p.topMessageId,
    readInboxMaxId: p.readInboxMaxId,
    readOutboxMaxId: p.readOutboxMaxId,
    parentId: p.parentId,
    canEdit: p.canEdit,
    canDelete: p.canDelete,
    canToggleClosed: p.canToggleClosed,
    canTogglePinned: p.canTogglePinned,
    lastMsgText: p.lastMsgText,
    lastMsgDate: p.lastMsgDate.toInt(),
  );

  Future<int> createForumTopic(String accountId, String chatId, String title, int colorId, int iconEmojiId) async {
    final req = epb.EngineCreateForumTopicRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..title = title
      ..colorId = colorId
      ..iconEmojiId = Int64(iconEmojiId);
    final respBytes = await _callAsync('__engine', 'CreateForumTopic', req.writeToBuffer());
    if (respBytes.isEmpty) return 0;
    final resp = epb.EngineCreateForumTopicResponse.fromBuffer(respBytes);
    return resp.topicId.toInt();
  }

  Future<void> editForumTopic(String accountId, String chatId, int topicId, String title, {int iconEmojiId = -1}) async {
    final req = epb.EngineEditForumTopicRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..topicId = Int64(topicId)
      ..title = title;
    if (iconEmojiId >= 0) {
      req.iconEmojiId = Int64(iconEmojiId);
    }
    await _callAsync('__engine', 'EditForumTopic', req.writeToBuffer());
  }

  Future<void> pinForumTopic(String accountId, String chatId, int topicId, bool pinned) async {
    final req = epb.EnginePinForumTopicRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..topicId = Int64(topicId)
      ..pinned = pinned;
    await _callAsync('__engine', 'PinForumTopic', req.writeToBuffer());
  }

  Future<void> toggleForumTopicClosed(String accountId, String chatId, int topicId, bool closed) async {
    final req = epb.EngineToggleForumTopicClosedRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..topicId = Int64(topicId)
      ..closed = closed;
    await _callAsync('__engine', 'ToggleForumTopicClosed', req.writeToBuffer());
  }

  Future<void> toggleGeneralTopicHidden(String accountId, String chatId, bool hidden) async {
    final req = epb.EngineToggleGeneralTopicHiddenRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..hidden = hidden;
    await _callAsync('__engine', 'ToggleGeneralTopicHidden', req.writeToBuffer());
  }

  Future<void> deleteForumTopicHistory(String accountId, String chatId, int topicId) async {
    final req = epb.EngineEditForumTopicRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..topicId = Int64(topicId);
    await _callAsync('__engine', 'DeleteForumTopicHistory', req.writeToBuffer());
  }

  // ── Folders ──

  /// Fetch synced folders for an account. Returns empty list if the platform
  /// doesn't support folders (e.g. only Telegram has them).
  Future<List<FolderInfo>> getFolders(String accountId) async {
    final req = epb.EngineGetFoldersRequest()..accountId = accountId;
    final respBytes = await _callAsync('__engine', 'GetFolders', req.writeToBuffer());
    if (respBytes.isEmpty) return [];
    final resp = epb.EngineGetFoldersResponse.fromBuffer(respBytes);
    return resp.folders.map(_folderInfoFromProto).toList();
  }

  Future<FolderInfo?> createFolder(String accountId, String name, List<String> chatIds, {
    bool contacts = false,
    bool nonContacts = false,
    bool groups = false,
    bool channels = false,
    bool bots = false,
  }) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'name': name,
      'chat_ids': chatIds,
      'contacts': contacts,
      'non_contacts': nonContacts,
      'groups': groups,
      'channels': channels,
      'bots': bots,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'CreateFolder', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final m = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return FolderInfo(
        id: m['ID'] as String? ?? '',
        name: m['Name'] as String? ?? '',
        chatIds: (m['ChatIDs'] as List<dynamic>?)?.cast<String>() ?? [],
      );
    } catch (e) {
      Debug.error('ENGINE', 'createFolder failed', e);
      return null;
    }
  }

  Future<List<SuggestedFolderInfo>> getSuggestedFolders(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetSuggestedFolders', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final list = json.decode(utf8.decode(respBytes)) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return SuggestedFolderInfo(
          name: m['name'] as String? ?? '',
          description: m['description'] as String? ?? '',
          contacts: m['contacts'] as bool? ?? false,
          nonContacts: m['non_contacts'] as bool? ?? false,
          groups: m['groups'] as bool? ?? false,
          channels: m['channels'] as bool? ?? false,
          bots: m['bots'] as bool? ?? false,
        );
      }).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getSuggestedFolders failed', e);
      return [];
    }
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
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'folder_id': folderId,
      'name': name,
      'chat_ids': chatIds,
      'contacts': contacts,
      'non_contacts': nonContacts,
      'groups': groups,
      'channels': channels,
      'bots': bots,
      'exclude_muted': excludeMuted,
      'exclude_read': excludeRead,
      'exclude_archived': excludeArchived,
      'exclude_chat_ids': excludeChatIds,
    }));
    try {
      await _callAsync('__engine', 'EditFolder', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'editFolder failed', e);
      rethrow;
    }
  }

  Future<void> deleteFolder(String accountId, String folderId) async {
    final req = epb.EngineDeleteFolderRequest()
      ..accountId = accountId
      ..folderId = folderId;
    await _callAsync('__engine', 'DeleteFolder', req.writeToBuffer());
  }

  Future<bool> toggleDialogFilterTags(String accountId, bool enabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'enabled': enabled,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'ToggleDialogFilterTags', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return false;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return data['ok'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  // ── Folder Invite Links ──

  Future<List<ChatlistInviteLink>> getFolderInviteLinks(String accountId, int folderId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'folder_id': folderId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetFolderInviteLinks', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final list = json.decode(utf8.decode(respBytes)) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return ChatlistInviteLink(
          url: m['url'] as String? ?? '',
          title: m['title'] as String? ?? '',
          peerCount: m['peer_count'] as int? ?? 0,
          slug: m['slug'] as String? ?? '',
          peerIds: (m['peer_ids'] as List<dynamic>?)?.cast<String>() ?? [],
        );
      }).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getFolderInviteLinks failed', e);
      return [];
    }
  }

  Future<String?> createFolderInviteLink(String accountId, int folderId, String title, List<String> peerIds) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'folder_id': folderId,
      'title': title,
      'peer_ids': peerIds,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'CreateFolderInviteLink', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final m = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return m['url'] as String?;
    } catch (e) {
      Debug.error('ENGINE', 'createFolderInviteLink failed', e);
      return null;
    }
  }

  Future<ChatlistInviteLink?> editFolderInviteLink(String accountId, int folderId, String slug, List<String> peerIds) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'folder_id': folderId,
      'slug': slug,
      'peer_ids': peerIds,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'EditFolderInviteLink', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final m = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return ChatlistInviteLink(
        url: m['url'] as String? ?? '',
        title: m['title'] as String? ?? '',
        peerCount: m['peer_count'] as int? ?? 0,
        slug: m['slug'] as String? ?? '',
        peerIds: (m['peer_ids'] as List<dynamic>?)?.cast<String>() ?? [],
      );
    } catch (e) {
      Debug.error('ENGINE', 'editFolderInviteLink failed', e);
      return null;
    }
  }

  Future<bool> deleteFolderInviteLink(String accountId, int folderId, String slug) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'folder_id': folderId,
      'slug': slug,
    }));
    try {
      await _callAsync('__engine', 'DeleteFolderInviteLink', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'deleteFolderInviteLink failed', e);
      return false;
    }
  }

  Future<List<String>> getLeaveChatlistSuggestions(String accountId, int folderId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'folder_id': folderId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetLeaveChatlistSuggestions', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final list = json.decode(utf8.decode(respBytes)) as List<dynamic>?;
      if (list == null) return [];
      return list.cast<String>();
    } catch (e) {
      Debug.error('ENGINE', 'getLeaveChatlistSuggestions failed', e);
      return [];
    }
  }

  Future<bool> leaveChatlistFolder(String accountId, int folderId, List<String> peerIds) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'folder_id': folderId,
      'peer_ids': peerIds,
    }));
    try {
      await _callAsync('__engine', 'LeaveChatlistFolder', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'leaveChatlistFolder failed', e);
      return false;
    }
  }

  // ── Members ──

  Future<List<MemberInfo>> getChatMembers(String accountId, String chatId, {int limit = 50, int offset = 0}) async {
    final req = epb.EngineGetChatMembersRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..limit = limit
      ..offset = offset;
    final respBytes = await _callAsync('__engine', 'GetChatMembers', req.writeToBuffer());
    final resp = epb.EngineGetChatMembersResponse.fromBuffer(respBytes);
    return resp.members.map(_memberInfoFromProto).toList();
  }

  Future<MembersByRoleResult> getChatMembersByRole(
    String accountId,
    String chatId, {
    String role = 'members',
    String query = '',
    int limit = 200,
    int offset = 0,
  }) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'role': role,
      'query': query,
      'limit': limit,
      'offset': offset,
    }));
    final respBytes = await _callAsync('__engine', 'GetChatMembersByRole', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    final list = data['members'] as List<dynamic>? ?? [];
    final members = list.map((m) {
      final map = m as Map<String, dynamic>;
      return MemberInfo(
        userId: map['user_id'] as String? ?? '',
        username: map['username'] as String? ?? '',
        displayName: map['display_name'] as String? ?? '',
        avatarB64: map['avatar_b64'] as String? ?? '',
        isBot: map['is_bot'] as bool? ?? false,
        isOnline: map['is_online'] as bool? ?? false,
        role: map['role'] as String? ?? 'member',
        customRank: map['custom_rank'] as String? ?? '',
        promotedBy: map['promoted_by'] as String? ?? '',
        promotedByID: map['promoted_by_id'] as String? ?? '',
        promotedDate: map['promoted_date'] as int? ?? 0,
      );
    }).toList();
    return MembersByRoleResult(
      members: members,
      total: data['total'] as int? ?? members.length,
    );
  }

  // ── Online count ──

  Future<int> getOnlineCount(String accountId, String chatId) async {
    final req = epb.EngineGetOnlineCountRequest()
      ..accountId = accountId
      ..chatId = chatId;
    final respBytes = await _callAsync('__engine', 'GetOnlineCount', req.writeToBuffer());
    if (respBytes.isEmpty) return 0;
    final resp = epb.EngineGetOnlineCountResponse.fromBuffer(respBytes);
    return resp.onlineCount;
  }

  // ── Peer colors ──

  Future<List<PeerColorEntry>> getPeerColors(String accountId) async {
    final req = epb.EngineGetPeerColorsRequest()
      ..accountId = accountId;
    final respBytes = await _callAsync('__engine', 'GetPeerColors', req.writeToBuffer());
    if (respBytes.isEmpty) return [];
    final resp = epb.EngineGetPeerColorsResponse.fromBuffer(respBytes);
    return resp.colors.map((c) => PeerColorEntry(
      colorId: c.colorId,
      dayColors: c.dayColors.toList(),
      nightColors: c.nightColors.toList(),
      hidden: c.hidden,
    )).toList();
  }

  // ── Web page preview ──

  Future<WebPagePreview?> getWebPagePreview(String accountId, String url) async {
    final req = epb.EngineGetWebPagePreviewRequest()
      ..accountId = accountId
      ..url = url;
    try {
      final respBytes = await _callAsync('__engine', 'GetWebPagePreview', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineGetWebPagePreviewResponse.fromBuffer(respBytes);
      final pending = resp.pendingTill.toInt();
      if (pending > 0) {
        return WebPagePreview(url: resp.url.isNotEmpty ? resp.url : url, pendingTill: pending);
      }
      if (resp.title.isEmpty && resp.description.isEmpty && resp.siteName.isEmpty) return null;
      return WebPagePreview(
        url: resp.url,
        siteName: resp.siteName,
        title: resp.title,
        description: resp.description,
        thumbB64: resp.thumbB64,
        type: resp.type,
        hasLargeMedia: resp.hasLargeMedia,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Instant View ──

  Future<Map<String, dynamic>?> getInstantViewPage(String accountId, String url) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'url': url,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetInstantViewPage', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'getInstantViewPage failed', e);
      return null;
    }
  }

  Future<String?> downloadIVPhoto(String accountId, int photoId, String extra) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'photo_id': photoId,
      'extra': extra,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'DownloadIVPhoto', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final resp = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return resp['path'] as String?;
    } catch (e) {
      Debug.error('ENGINE', 'downloadIVPhoto failed', e);
      return null;
    }
  }

  // ── Sticker sets ──

  Future<StickerSetInfo?> getStickerSetInfo(String accountId, {String shortName = '', int setId = 0, int accessHash = 0}) async {
    final req = epb.EngineGetStickerSetInfoRequest()
      ..accountId = accountId
      ..shortName = shortName
      ..setId = Int64(setId)
      ..accessHash = Int64(accessHash);
    try {
      final respBytes = await _callAsync('__engine', 'GetStickerSetInfo', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineGetStickerSetInfoResponse.fromBuffer(respBytes);
      return StickerSetInfo(
        title: resp.title,
        shortName: resp.shortName,
        setId: setId,
        accessHash: accessHash,
        count: resp.count,
        installed: resp.installed,
        archived: resp.archived,
        animated: resp.animated,
        video: resp.video,
        masks: resp.masks,
        emojis: resp.emojis,
        stickers: resp.stickers.map((s) => StickerInfoItem(
          emoji: s.emoji,
          thumbB64: s.thumbB64,
          width: s.width,
          height: s.height,
          mimeType: s.mimeType,
          fileId: s.fileId,
        )).toList(),
      );
    } catch (e) {
      Debug.error('ENGINE', 'getStickerSetInfo failed', e);
      return null;
    }
  }

  Future<List<StickerInfoItem>> getStickerSuggestions(String accountId, String emoji) async {
    final req = epb.EngineGetStickerSuggestionsRequest()
      ..accountId = accountId
      ..emoji = emoji;
    try {
      final respBytes = await _callAsync('__engine', 'GetStickerSuggestions', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetStickerSuggestionsResponse.fromBuffer(respBytes);
      return resp.stickers.map((s) => StickerInfoItem(
        emoji: s.emoji,
        thumbB64: s.thumbB64,
        width: s.width,
        height: s.height,
        mimeType: s.mimeType,
        fileId: s.fileId,
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getStickerSuggestions failed', e);
      return [];
    }
  }

  Future<EmojiKeywordsResult?> getEmojiKeywords(String accountId, String langCode) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'lang_code': langCode,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetEmojiKeywords', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return EmojiKeywordsResult.fromJson(data);
    } catch (e) {
      Debug.error('ENGINE', 'getEmojiKeywords failed', e);
      return null;
    }
  }

  Future<void> sendSticker(String accountId, String chatId, String stickerId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'sticker_id': stickerId,
    }));
    try {
      await _callAsync('__engine', 'SendSticker', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'sendSticker failed', e);
    }
  }

  Future<int> sendStoryWithPhoto(
    String accountId,
    String caption,
    Uint8List photoData, {
    String privacy = 'everyone',
    int durationHours = 24,
    bool saveToProfile = true,
    bool allowSharing = true,
    List<String> selectedContactIds = const [],
    double trimStart = 0.0,
    double trimEnd = 1.0,
  }) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'caption': caption,
      'photo_data': photoData.toList(),
      'privacy': privacy,
      'duration_hours': durationHours,
      'save_to_profile': saveToProfile,
      'allow_sharing': allowSharing,
      'selected_contact_ids': selectedContactIds,
      'trim_start': trimStart,
      'trim_end': trimEnd,
    }));
    try {
      final resp = await _callAsync('__engine', 'SendStoryWithPhoto', Uint8List.fromList(payload));
      if (resp.isNotEmpty) {
        final data = json.decode(utf8.decode(resp));
        return data['story_id'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      Debug.error('ENGINE', 'sendStoryWithPhoto failed', e);
      rethrow;
    }
  }

  // ── Custom emoji thumbnails (for forum topic icons) ──

  Future<Map<int, CustomEmojiThumbData>> getCustomEmojiThumbs(String accountId, List<int> documentIds) async {
    final req = epb.EngineGetCustomEmojiThumbsRequest()
      ..accountId = accountId
      ..documentIds.addAll(documentIds.map((id) => Int64(id)));
    try {
      final respBytes = await _callAsync('__engine', 'GetCustomEmojiThumbs', req.writeToBuffer());
      if (respBytes.isEmpty) return {};
      final resp = epb.EngineGetCustomEmojiThumbsResponse.fromBuffer(respBytes);
      return {
        for (final t in resp.thumbs)
          t.documentId.toInt(): CustomEmojiThumbData(
            thumbB64: t.thumbB64,
            pathB64: t.pathB64,
          ),
      };
    } catch (e) {
      Debug.error('ENGINE', 'getCustomEmojiThumbs failed', e);
      return {};
    }
  }

  // ── Custom emoji full files (for animated playback §45.3) ──

  Future<Map<int, CustomEmojiFileData>> getCustomEmojiFiles(String accountId, List<int> documentIds) async {
    final req = epb.EngineGetCustomEmojiFilesRequest()
      ..accountId = accountId
      ..documentIds.addAll(documentIds.map((id) => Int64(id)));
    try {
      final respBytes = await _callAsync('__engine', 'GetCustomEmojiFiles', req.writeToBuffer());
      if (respBytes.isEmpty) return {};
      final resp = epb.EngineGetCustomEmojiFilesResponse.fromBuffer(respBytes);
      return {
        for (final f in resp.files) f.documentId.toInt(): CustomEmojiFileData(
          mimeType: f.mimeType,
          fileData: Uint8List.fromList(f.fileData),
        ),
      };
    } catch (e) {
      Debug.error('ENGINE', 'getCustomEmojiFiles failed', e);
      return {};
    }
  }

  Future<CustomEmojiSetInfo?> getCustomEmojiSetInfo(String accountId, int documentId) async {
    final req = epb.EngineGetCustomEmojiSetInfoRequest()
      ..accountId = accountId
      ..documentId = Int64(documentId);
    try {
      final respBytes = await _callAsync('__engine', 'GetCustomEmojiSetInfo', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineGetCustomEmojiSetInfoResponse.fromBuffer(respBytes);
      if (!resp.found) return null;
      return CustomEmojiSetInfo(
        setId: resp.setId.toInt(),
        accessHash: resp.accessHash.toInt(),
        title: resp.title,
        shortName: resp.shortName,
        count: resp.count,
      );
    } catch (e) {
      Debug.error('ENGINE', 'getCustomEmojiSetInfo failed', e);
      return null;
    }
  }

  // ── Installed custom emoji sets ──

  Future<List<CustomEmojiSetSummary>> getInstalledEmojiSets(String accountId) async {
    final req = epb.EngineGetInstalledEmojiSetsRequest()
      ..accountId = accountId;
    try {
      final respBytes = await _callAsync('__engine', 'GetInstalledEmojiSets', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetInstalledEmojiSetsResponse.fromBuffer(respBytes);
      return resp.sets.map((s) => CustomEmojiSetSummary(
        setId: s.setId.toInt(),
        accessHash: s.accessHash.toInt(),
        title: s.title,
        shortName: s.shortName,
        count: s.count,
        installed: s.installed,
        premium: s.premium,
        stickers: s.stickers.map((st) => StickerInfoItem(
          emoji: st.emoji,
          thumbB64: st.thumbB64,
          width: st.width,
          height: st.height,
          mimeType: st.mimeType,
          fileId: st.fileId,
        )).toList(),
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getInstalledEmojiSets failed', e);
      return [];
    }
  }

  // ── Installed sticker packs ──

  Future<List<StickerPackSummary>> getInstalledStickerPacks(String accountId) async {
    final req = epb.EngineGetInstalledStickerPacksRequest()
      ..accountId = accountId;
    try {
      final respBytes = await _callAsync('__engine', 'GetInstalledStickerPacks', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetInstalledStickerPacksResponse.fromBuffer(respBytes);
      return resp.packs.map((p) => StickerPackSummary(
        setId: p.setId.toInt(),
        accessHash: p.accessHash.toInt(),
        title: p.title,
        shortName: p.shortName,
        count: p.count,
        animated: p.animated,
        video: p.video,
        thumbB64: p.thumbB64,
        stickers: p.stickers.map((s) => StickerInfoItem(
          emoji: s.emoji,
          thumbB64: s.thumbB64,
          width: s.width,
          height: s.height,
          mimeType: s.mimeType,
          fileId: s.fileId,
        )).toList(),
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getInstalledStickerPacks failed', e);
      return [];
    }
  }

  // ── Recent stickers ──

  Future<List<StickerInfoItem>> getRecentStickers(String accountId) async {
    final req = epb.EngineGetRecentStickersRequest()
      ..accountId = accountId;
    try {
      final respBytes = await _callAsync('__engine', 'GetRecentStickers', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetRecentStickersResponse.fromBuffer(respBytes);
      return resp.stickers.map((s) => StickerInfoItem(
        emoji: s.emoji,
        thumbB64: s.thumbB64,
        width: s.width,
        height: s.height,
        mimeType: s.mimeType,
        fileId: s.fileId,
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getRecentStickers failed', e);
      return [];
    }
  }

  // ── Featured sticker packs ──

  Future<List<StickerPackSummary>> getFeaturedStickerPacks(String accountId) async {
    final req = epb.EngineGetFeaturedStickerPacksRequest()
      ..accountId = accountId;
    try {
      final respBytes = await _callAsync('__engine', 'GetFeaturedStickerPacks', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetFeaturedStickerPacksResponse.fromBuffer(respBytes);
      return resp.packs.map((p) => StickerPackSummary(
        setId: p.setId.toInt(),
        accessHash: p.accessHash.toInt(),
        title: p.title,
        shortName: p.shortName,
        count: p.count,
        animated: p.animated,
        video: p.video,
        thumbB64: p.thumbB64,
        installed: p.installed,
        stickers: p.stickers.map((s) => StickerInfoItem(
          emoji: s.emoji,
          thumbB64: s.thumbB64,
          width: s.width,
          height: s.height,
          mimeType: s.mimeType,
          fileId: s.fileId,
        )).toList(),
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getFeaturedStickerPacks failed', e);
      return [];
    }
  }

  // ── Search sticker sets ──

  Future<List<StickerPackSummary>> searchStickerSets(String accountId, String query) async {
    final req = epb.EngineSearchStickerSetsRequest()
      ..accountId = accountId
      ..query = query;
    try {
      final respBytes = await _callAsync('__engine', 'SearchStickerSets', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineSearchStickerSetsResponse.fromBuffer(respBytes);
      return resp.packs.map((p) => StickerPackSummary(
        setId: p.setId.toInt(),
        accessHash: p.accessHash.toInt(),
        title: p.title,
        shortName: p.shortName,
        count: p.count,
        animated: p.animated,
        video: p.video,
        thumbB64: p.thumbB64,
        installed: p.installed,
        stickers: p.stickers.map((s) => StickerInfoItem(
          emoji: s.emoji,
          thumbB64: s.thumbB64,
          width: s.width,
          height: s.height,
          mimeType: s.mimeType,
          fileId: s.fileId,
        )).toList(),
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'searchStickerSets failed', e);
      return [];
    }
  }

  // ── Install sticker set ──

  Future<bool> installStickerSet(String accountId, int setId, int accessHash) async {
    final req = epb.EngineInstallStickerSetRequest()
      ..accountId = accountId
      ..setId = Int64(setId)
      ..accessHash = Int64(accessHash);
    try {
      await _callAsync('__engine', 'InstallStickerSet', req.writeToBuffer());
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'installStickerSet failed', e);
      return false;
    }
  }

  Future<bool> uninstallStickerSet(String accountId, int setId, int accessHash) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'set_id': setId,
      'access_hash': accessHash,
    }));
    try {
      await _callAsync('__engine', 'UninstallStickerSet', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'uninstallStickerSet failed', e);
      return false;
    }
  }

  // ── Voice transcription ──

  Future<({bool pending, int transcriptionId, String text})?> transcribeAudio(String accountId, String chatId, String msgId) async {
    final req = epb.EngineTranscribeAudioRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId;
    try {
      final respBytes = await _callAsync('__engine', 'TranscribeAudio', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineTranscribeAudioResponse.fromBuffer(respBytes);
      return (pending: resp.pending, transcriptionId: resp.transcriptionId.toInt(), text: resp.text);
    } catch (e) {
      Debug.error('ENGINE', 'transcribeAudio failed', e);
      return null;
    }
  }

  Future<String?> translateText(String accountId, String chatId, String msgId, String toLang) async {
    final req = epb.EngineTranslateTextRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..toLang = toLang;
    try {
      final respBytes = await _callAsync('__engine', 'TranslateText', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineTranslateTextResponse.fromBuffer(respBytes);
      return resp.translatedText;
    } catch (e) {
      Debug.error('ENGINE', 'translateText failed', e);
      return null;
    }
  }

  Future<String?> translateFreeText(String accountId, String text, String toLang) async {
    final req = epb.EngineTranslateTextRequest()
      ..accountId = accountId
      ..text = text
      ..toLang = toLang;
    try {
      final respBytes = await _callAsync('__engine', 'TranslateText', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineTranslateTextResponse.fromBuffer(respBytes);
      return resp.translatedText;
    } catch (e) {
      Debug.error('ENGINE', 'translateFreeText failed', e);
      return null;
    }
  }

  // ── Poll actions ──

  Future<bool> votePoll(String accountId, String chatId, String msgId, int optionIndex) async {
    final req = epb.EngineVotePollRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..optionIndex = optionIndex;
    try {
      await _callAsync('__engine', 'VotePoll', req.writeToBuffer());
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'votePoll failed', e);
      return false;
    }
  }

  Future<bool> votePollMulti(String accountId, String chatId, String msgId, List<int> optionIndices) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
      'options': optionIndices,
    }));
    try {
      await _callAsync('__engine', 'VotePollMulti', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'votePollMulti failed', e);
      return false;
    }
  }

  Future<bool> retractPollVote(String accountId, String chatId, String msgId) async {
    final req = epb.EngineRetractPollVoteRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId;
    try {
      await _callAsync('__engine', 'RetractPollVote', req.writeToBuffer());
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'retractPollVote failed', e);
      return false;
    }
  }

  Future<bool> stopPoll(String accountId, String chatId, String msgId) async {
    final req = epb.EngineStopPollRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId;
    try {
      await _callAsync('__engine', 'StopPoll', req.writeToBuffer());
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'stopPoll failed', e);
      return false;
    }
  }

  // ── Report message ──

  Future<ReportMessageResult?> reportMessage(String accountId, String chatId, List<int> msgIds, {List<int> option = const [], String message = ''}) async {
    final req = epb.EngineReportMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgIds.addAll(msgIds)
      ..option = option
      ..message = message;
    try {
      final respBytes = await _callAsync('__engine', 'ReportMessage', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineReportMessageResponse.fromBuffer(respBytes);
      return ReportMessageResult(
        resultType: resp.resultType,
        title: resp.title,
        options: resp.options.map((o) => ReportOptionItem(text: o.text, option: o.option)).toList(),
        commentOptional: resp.commentOptional,
        commentOption: resp.commentOption,
      );
    } catch (e) {
      Debug.error('ENGINE', 'reportMessage failed', e);
      return null;
    }
  }

  // ── Sticker/GIF actions ──

  Future<bool> faveSticker(String accountId, int fileId, {String extra = '', bool unfave = false}) async {
    final req = epb.EngineFaveStickerRequest()
      ..accountId = accountId
      ..fileId = Int64(fileId)
      ..unfave = unfave
      ..extra = extra;
    try {
      await _callAsync('__engine', 'FaveSticker', req.writeToBuffer());
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'faveSticker failed', e);
      return false;
    }
  }

  Future<bool> removeRecentSticker(String accountId, int fileId, {String extra = ''}) async {
    final req = epb.EngineFaveStickerRequest()
      ..accountId = accountId
      ..fileId = Int64(fileId)
      ..extra = extra;
    try {
      await _callAsync('__engine', 'RemoveRecentSticker', req.writeToBuffer());
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'removeRecentSticker failed', e);
      return false;
    }
  }

  Future<Map<int, CustomEmojiFileData>> getStickerFiles(String accountId, List<int> documentIds) async {
    final req = epb.EngineGetCustomEmojiFilesRequest()
      ..accountId = accountId
      ..documentIds.addAll(documentIds.map((id) => Int64(id)));
    try {
      final respBytes = await _callAsync('__engine', 'GetStickerFiles', req.writeToBuffer());
      if (respBytes.isEmpty) return {};
      final resp = epb.EngineGetCustomEmojiFilesResponse.fromBuffer(respBytes);
      return {
        for (final f in resp.files) f.documentId.toInt(): CustomEmojiFileData(
          mimeType: f.mimeType,
          fileData: Uint8List.fromList(f.fileData),
        ),
      };
    } catch (e) {
      Debug.error('ENGINE', 'getStickerFiles failed', e);
      return {};
    }
  }

  Future<Map<int, Uint8List>> getGifFiles(String accountId, List<int> documentIds) async {
    final req = epb.EngineGetCustomEmojiFilesRequest()
      ..accountId = accountId
      ..documentIds.addAll(documentIds.map((id) => Int64(id)));
    try {
      final respBytes = await _callAsync('__engine', 'GetGifFiles', req.writeToBuffer());
      if (respBytes.isEmpty) return {};
      final resp = epb.EngineGetCustomEmojiFilesResponse.fromBuffer(respBytes);
      return {
        for (final f in resp.files) f.documentId.toInt(): Uint8List.fromList(f.fileData),
      };
    } catch (e) {
      Debug.error('ENGINE', 'getGifFiles failed', e);
      return {};
    }
  }

  Future<bool> saveGif(String accountId, int fileId, {String extra = '', bool unsave = false}) async {
    final req = epb.EngineSaveGifRequest()
      ..accountId = accountId
      ..fileId = Int64(fileId)
      ..unsave = unsave
      ..extra = extra;
    try {
      await _callAsync('__engine', 'SaveGif', req.writeToBuffer());
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'saveGif failed', e);
      return false;
    }
  }

  Future<List<GifInfoItem>> getSavedGifs(String accountId) async {
    final req = epb.EngineGetSavedGifsRequest()..accountId = accountId;
    try {
      final respBytes = await _callAsync('__engine', 'GetSavedGifs', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetSavedGifsResponse.fromBuffer(respBytes);
      return resp.gifs.map((g) => GifInfoItem(
        thumbB64: g.thumbB64,
        width: g.width,
        height: g.height,
        mimeType: g.mimeType,
        fileId: g.fileId,
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getSavedGifs failed', e);
      return [];
    }
  }

  // ── Attach menu bots ──

  Future<List<AttachMenuBotInfo>> getAttachMenuBots(String accountId) async {
    final req = epb.EngineGetAttachMenuBotsRequest()..accountId = accountId;
    try {
      final respBytes = await _callAsync('__engine', 'GetAttachMenuBots', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetAttachMenuBotsResponse.fromBuffer(respBytes);
      return resp.bots.map((b) => AttachMenuBotInfo(
        botId: b.botId.toInt(),
        shortName: b.shortName,
        inactive: b.inactive,
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getAttachMenuBots failed', e);
      return [];
    }
  }

  // ── Send As (channel sender identity) ──

  Future<List<SendAsPeerInfo>> getSendAs(String accountId, String chatId) async {
    final req = epb.EngineGetSendAsRequest()
      ..accountId = accountId
      ..chatId = chatId;
    try {
      final respBytes = await _callAsync('__engine', 'GetSendAs', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetSendAsResponse.fromBuffer(respBytes);
      return resp.peers.map((p) => SendAsPeerInfo(
        peerId: p.peerId,
        displayName: p.displayName,
        avatarPath: p.avatarPath,
        isChannel: p.isChannel,
      )).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getSendAs failed', e);
      return [];
    }
  }

  Future<bool> saveDefaultSendAs(String accountId, String chatId, String peerId) async {
    final req = epb.EngineSaveDefaultSendAsRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..peerId = peerId;
    try {
      final respBytes = await _callAsync('__engine', 'SaveDefaultSendAs', req.writeToBuffer());
      if (respBytes.isEmpty) return false;
      final resp = epb.EngineSaveDefaultSendAsResponse.fromBuffer(respBytes);
      return resp.ok;
    } catch (e) {
      Debug.error('ENGINE', 'saveDefaultSendAs failed', e);
      return false;
    }
  }

  // ── Confcall size limit ──

  Future<int> getConfcallSizeLimit(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetConfcallSizeLimit', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return 200;
      final m = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (m['limit'] as num?)?.toInt() ?? 200;
    } catch (_) {
      return 200;
    }
  }

  // ── Group calls ──

  /// Get active group call info for a chat, or null if no active call.
  Future<GroupCallInfo?> getGroupCall(String accountId, String chatId) async {
    final req = epb.EngineGetGroupCallRequest()
      ..accountId = accountId
      ..chatId = chatId;
    final respBytes = await _callAsync('__engine', 'GetGroupCall', req.writeToBuffer());
    if (respBytes.isEmpty) return null;
    final resp = epb.EngineGetGroupCallResponse.fromBuffer(respBytes);
    if (!resp.hasGroupCall()) return null;
    final gc = resp.groupCall;
    return GroupCallInfo(
      callId: gc.callId,
      chatId: gc.chatId,
      title: gc.title,
      participantsCount: gc.participantsCount,
      participants: gc.participants.map((p) => GroupCallParticipant(
        userId: p.userId,
        displayName: p.displayName,
        isMuted: p.isMuted,
        isSpeaking: p.isSpeaking,
        hasVideo: p.hasVideo,
        avatarPath: p.avatarPath,
      )).toList(),
      active: gc.active,
    );
  }

  /// Join an active group call in a chat.
  Future<String> joinGroupCall(String accountId, String chatId) async {
    final req = epb.EngineJoinGroupCallRequest()
      ..accountId = accountId
      ..chatId = chatId;
    final respBytes = await _callAsync('__engine', 'JoinGroupCall', req.writeToBuffer());
    final resp = epb.EngineJoinGroupCallResponse.fromBuffer(respBytes);
    return resp.callId;
  }

  Future<void> sendCallRating(String accountId, String callId, int rating, String comment) async {
    final req = epb.EngineSendCallRatingRequest()
      ..accountId = accountId
      ..callId = callId
      ..rating = rating
      ..comment = comment;
    await _callAsync('__engine', 'SendCallRating', req.writeToBuffer());
  }

  Future<String?> acceptCall(String accountId, String callId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'call_id': callId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'AcceptCall', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final result = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return result['call_id'] as String?;
    } catch (e) {
      Debug.error('ENGINE', 'acceptCall failed', e);
      return null;
    }
  }

  Future<void> declineCall(String accountId, String callId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'call_id': callId,
    }));
    try {
      await _callAsync('__engine', 'DeclineCall', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'declineCall failed', e);
    }
  }

  Future<void> endCall(String accountId, String callId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'call_id': callId,
    }));
    try {
      await _callAsync('__engine', 'EndCall', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'endCall failed', e);
    }
  }

  Future<void> endGroupCall(String accountId, String callId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'call_id': callId,
    }));
    try {
      await _callAsync('__engine', 'EndGroupCall', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'endGroupCall failed', e);
    }
  }

  Future<void> setCallMuted(String accountId, String callId, bool muted) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'call_id': callId,
      'muted': muted,
    }));
    try {
      await _callAsync('__engine', 'SetCallMuted', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'setCallMuted failed', e);
    }
  }

  Future<void> setCallAudioDevice(String accountId, String type, String device) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'type': type,
      'device': device,
    }));
    try {
      await _callAsync('__engine', 'SetCallAudioDevice', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'setCallAudioDevice failed', e);
    }
  }

  Future<void> toggleCamera(String accountId, String callId, bool enabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'call_id': callId,
      'enabled': enabled,
    }));
    try {
      await _callAsync('__engine', 'ToggleCamera', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'toggleCamera failed', e);
    }
  }

  Future<void> toggleScreenSharing(String accountId, String callId, bool enabled, {String? sourceId, bool withAudio = false}) async {
    final map = <String, dynamic>{
      'account_id': accountId,
      'call_id': callId,
      'enabled': enabled,
    };
    if (sourceId != null) map['source_id'] = sourceId;
    if (withAudio) map['with_audio'] = true;
    final payload = utf8.encode(json.encode(map));
    try {
      await _callAsync('__engine', 'ToggleScreenSharing', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'toggleScreenSharing failed', e);
    }
  }

  Future<String?> startCall(String accountId, String chatId, {bool video = false}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'video': video,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'StartCall', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final result = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return result['call_id'] as String?;
    } catch (e) {
      Debug.error('ENGINE', 'startCall failed', e);
      return null;
    }
  }

  Future<({String callId, String inviteLink})?> createConferenceCall(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'CreateConferenceCall', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final result = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (callId: result['call_id'] as String? ?? '', inviteLink: result['invite_link'] as String? ?? '');
    } catch (e) {
      Debug.error('ENGINE', 'createConferenceCall failed', e);
      return null;
    }
  }

  Future<bool> accountUpdateDeviceLocked(String accountId, int period) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'period': period,
    }));
    try {
      final respBytes = await _callAsync(
          '__engine', 'AccountUpdateDeviceLocked', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return false;
      final result =
          json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return result['result'] as bool? ?? false;
    } catch (e) {
      Debug.error('ENGINE', 'accountUpdateDeviceLocked failed', e);
      return false;
    }
  }

  Future<void> clearCallHistory(String accountId, {bool revoke = false}) async {
    final req = epb.EngineClearCallHistoryRequest()
      ..accountId = accountId
      ..revoke = revoke;
    await _callAsync('__engine', 'ClearCallHistory', req.writeToBuffer());
  }

  Future<List<CallHistoryEntry>> getCallHistory(String accountId, {int offsetId = 0, int limit = 20}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'offset_id': offsetId,
      'limit': limit,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetCallHistory', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final list = json.decode(utf8.decode(respBytes)) as List<dynamic>;
      return list.map((e) => CallHistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getCallHistory failed', e);
      return [];
    }
  }

  // ── Statistics ──

  Future<Map<String, dynamic>> getBroadcastStats(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetBroadcastStatsEngine', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMegagroupStats(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetMegagroupStatsEngine', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMessageStats(String accountId, String chatId, int msgId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
    }));
    final respBytes = await _callAsync('__engine', 'GetMessageStatsEngine', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loadStatsGraph(String accountId, String token, {int x = 0}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'token': token,
      'x': x,
    }));
    final respBytes = await _callAsync('__engine', 'LoadStatsGraphEngine', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMorePublicForwards(String accountId, String chatId, int msgId, String offset) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
      'offset': offset,
    }));
    final respBytes = await _callAsync('__engine', 'GetMorePublicForwardsEngine', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  // ── Stories ──

  Future<void> reactToStory(String accountId, String userId, int storyId, String emoji) async {
    final payload = utf8.encode(json.encode({
      'user_id': userId,
      'story_id': storyId,
      'emoji': emoji,
    }));
    await _callAsync('__engine', 'ReactToStory', Uint8List.fromList(payload));
  }

  Future<void> activateStealthMode(String accountId) async {
    await _callAsync('__engine', 'ActivateStealthMode', Uint8List(0));
  }

  Future<List<StoryItem>> fetchPeerStories(String accountId, String peerId) async {
    final req = epb.EngineFetchPeerStoriesRequest()
      ..accountId = accountId
      ..peerId = peerId;
    final respBytes = await _callAsync('__engine', 'FetchPeerStories', req.writeToBuffer());
    final resp = epb.EngineFetchPeerStoriesResponse.fromBuffer(respBytes);
    if (resp.storiesJson.isEmpty) return [];
    final List<dynamic> items = json.decode(resp.storiesJson);
    return items.map((j) => StoryItem.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<StoryAlbumInfo>> getStoryAlbums(String accountId) async {
    final req = epb.EngineGetStoryAlbumsRequest()
      ..accountId = accountId;
    final respBytes = await _callAsync('__engine', 'GetStoryAlbums', req.writeToBuffer());
    final resp = epb.EngineGetStoryAlbumsResponse.fromBuffer(respBytes);
    return resp.albums.map((a) => StoryAlbumInfo(
      id: a.id.toInt(),
      title: a.title,
      count: a.count,
    )).toList();
  }

  Future<({List<dynamic> stories, int totalCount})> getAlbumStories(
    String accountId, int albumId, {int offset = 0, int limit = 50}
  ) async {
    final req = epb.EngineGetAlbumStoriesRequest()
      ..accountId = accountId
      ..albumId = Int64(albumId)
      ..offset = offset
      ..limit = limit;
    final respBytes = await _callAsync('__engine', 'GetAlbumStories', req.writeToBuffer());
    final resp = epb.EngineGetAlbumStoriesResponse.fromBuffer(respBytes);
    final List<dynamic> items = resp.storiesJson.isEmpty
        ? []
        : json.decode(resp.storiesJson);
    return (stories: items, totalCount: resp.totalCount);
  }

  Future<StoryAlbumInfo> createStoryAlbum(String accountId, String title) async {
    final req = epb.EngineCreateStoryAlbumRequest()
      ..accountId = accountId
      ..title = title;
    final respBytes = await _callAsync('__engine', 'CreateStoryAlbum', req.writeToBuffer());
    final resp = epb.EngineCreateStoryAlbumResponse.fromBuffer(respBytes);
    return StoryAlbumInfo(
      id: resp.albumId.toInt(),
      title: resp.title,
      count: 0,
    );
  }

  Future<void> reorderStoryAlbums(String accountId, List<int> albumIds) async {
    final req = epb.EngineReorderStoryAlbumsRequest()
      ..accountId = accountId
      ..albumIds.addAll(albumIds.map((id) => Int64(id)));
    await _callAsync('__engine', 'ReorderStoryAlbums', req.writeToBuffer());
  }

  // ── Contacts ──

  Future<List<ContactInfo>> getContacts(String accountId) async {
    final req = epb.EngineGetContactsRequest()
      ..accountId = accountId;
    final respBytes = await _callAsync('__engine', 'GetContacts', req.writeToBuffer());
    final resp = epb.EngineGetContactsResponse.fromBuffer(respBytes);
    return resp.contacts.map(_contactInfoFromProto).toList();
  }

  // ── Messages ──

  List<CachedMessage> getMessages(String accountId, String chatId, {int beforeMs = 0, int limit = 50}) {
    final req = epb.EngineGetMessagesRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..beforeMs = Int64(beforeMs)
      ..limit = limit;
    final respBytes = _callRaw('__engine', 'GetMessages', req.writeToBuffer());
    final resp = epb.EngineGetMessagesResponse.fromBuffer(respBytes);
    return resp.messages.map(_cachedMsgFromProto).toList();
  }

  /// Fetch live messages directly from the core (not cache).
  /// Used for reading OTP codes from connected accounts.
  Future<List<CachedMessage>> fetchLiveMessages(String accountId, String chatId, {int limit = 3}) async {
    final req = epb.EngineGetMessagesRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..limit = limit;
    final respBytes = await _callAsync('__engine', 'FetchLiveMessages', req.writeToBuffer());
    final resp = epb.EngineGetMessagesResponse.fromBuffer(respBytes);
    return resp.messages.map(_cachedMsgFromProto).toList();
  }

  /// Get all pinned messages for a chat from the cache.
  List<CachedMessage> getPinnedMessages(String accountId, String chatId) {
    final req = epb.EngineGetPinnedMessagesRequest()
      ..accountId = accountId
      ..chatId = chatId;
    final respBytes = _callRaw('__engine', 'GetPinnedMessages', req.writeToBuffer());
    final resp = epb.EngineGetPinnedMessagesResponse.fromBuffer(respBytes);
    return resp.messages.map(_cachedMsgFromProto).toList();
  }

  List<Map<String, dynamic>> getEditRevisions(String accountId, String chatId, String msgId, {int offset = 0, int limit = 20}) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
      'offset': offset,
      'limit': limit,
    }));
    final respBytes = _callRaw('__engine', 'GetEditRevisions', Uint8List.fromList(payload));
    final resp = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return (resp['revisions'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
  }

  bool hasEditRevisions(String accountId, String chatId, String msgId) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
    }));
    final respBytes = _callRaw('__engine', 'HasEditRevisions', Uint8List.fromList(payload));
    final resp = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return resp['has_revisions'] == true;
  }

  void setAntiRecallSettings({required bool saveDeleted, required bool saveHistory, required bool saveForBots}) {
    final payload = utf8.encode(json.encode({
      'save_deleted_messages': saveDeleted,
      'save_messages_history': saveHistory,
      'save_for_bots': saveForBots,
    }));
    _callRaw('__engine', 'SetAntiRecallSettings', Uint8List.fromList(payload));
  }

  List<CachedMessage> getDeletedMessages(String accountId, String chatId, {String search = '', int offset = 0, int limit = 20}) {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'search': search,
      'offset': offset,
      'limit': limit,
    }));
    final respBytes = _callRaw('__engine', 'GetDeletedMessages', Uint8List.fromList(payload));
    final resp = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    final list = resp['messages'] as List<dynamic>? ?? [];
    return list.map((m) {
      final map = m as Map<String, dynamic>;
      return CachedMessage(
        accountId: map['account_id'] as String? ?? '',
        chatId: map['chat_id'] as String? ?? '',
        msgId: map['msg_id'] as String? ?? '',
        senderId: map['sender_id'] as String? ?? '',
        senderName: map['sender_name'] as String? ?? '',
        contentText: map['content_text'] as String? ?? '',
        timestamp: map['timestamp'] as int? ?? 0,
        editedAt: map['edited_at'] as int? ?? 0,
        status: MsgStatus.read,
        isOutgoing: map['is_outgoing'] == true || map['is_outgoing'] == 1,
        isDeleted: true,
        deletedAt: map['deleted_at'] as int? ?? 0,
        forwardFrom: map['forward_from'] as String? ?? '',
        replyToId: map['reply_to_id'] as String? ?? '',
        replyPreview: map['reply_preview'] as String? ?? '',
        hasMedia: map['has_media'] == true || map['has_media'] == 1,
        senderColorId: map['sender_color_id'] as int? ?? -1,
      );
    }).toList();
  }

  Future<String> sendMessage(String accountId, String chatId, String text, {String replyToId = '', String entities = '', bool silent = false, int scheduleDate = 0, String topicRootId = '', String webPageUrl = '', bool forceLargeMedia = false, bool forceSmallMedia = false, bool invertMedia = false, bool webPageOptional = true}) async {
    final req = epb.EngineSendMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..text = text
      ..replyToId = replyToId
      ..silent = silent;
    if (scheduleDate > 0) {
      req.scheduleDate = Int64(scheduleDate);
    }
    if (topicRootId.isNotEmpty) {
      req.topicRootId = topicRootId;
    }
    if (entities.isNotEmpty) {
      req.entitiesJson = entities;
    }
    if (webPageUrl.isNotEmpty) {
      req.webPageUrl = webPageUrl;
    }
    if (forceLargeMedia) {
      req.forceLargeMedia = true;
    }
    if (forceSmallMedia) {
      req.forceSmallMedia = true;
    }
    if (invertMedia) {
      req.invertMedia = true;
    }
    if (webPageUrl.isNotEmpty && webPageOptional) {
      req.webPageOptional = true;
    }
    final respBytes = await _callAsync('__engine', 'SendMessage', req.writeToBuffer());
    final resp = epb.EngineSendMessageResponse.fromBuffer(respBytes);
    return resp.localId;
  }

  Future<void> editMessage(String accountId, String chatId, String msgId, String newText, {String entities = ''}) async {
    final req = epb.EngineEditMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..newText = newText;
    if (entities.isNotEmpty) {
      req.entitiesJson = entities;
    }
    await _callAsync('__engine', 'EditMessage', req.writeToBuffer());
  }

  Future<void> deleteMessage(String accountId, String chatId, String msgId) async {
    final req = epb.EngineDeleteMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId;
    await _callAsync('__engine', 'DeleteMessage', req.writeToBuffer());
  }

  Future<void> joinChat(String accountId, String channelName) async {
    final req = epb.EngineJoinChatRequest()
      ..accountId = accountId
      ..channelName = channelName;
    await _callAsync('__engine', 'JoinChat', req.writeToBuffer());
  }

  Future<void> joinChannel(String accountId, String chatId) async {
    final req = epb.EngineJoinChannelRequest()
      ..accountId = accountId
      ..chatId = chatId;
    await _callAsync('__engine', 'JoinChannel', req.writeToBuffer());
  }

  Future<void> leaveChat(String accountId, String chatId) async {
    final req = epb.EngineLeaveChatRequest()
      ..accountId = accountId
      ..chatId = chatId;
    await _callAsync('__engine', 'LeaveChat', req.writeToBuffer());
  }

  Future<void> editChatTitle(String accountId, String chatId, String title) async {
    final req = epb.EngineEditChatTitleRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..title = title;
    await _callAsync('__engine', 'EditChatTitle', req.writeToBuffer());
  }

  Future<void> editChatDescription(String accountId, String chatId, String description) async {
    final req = epb.EngineEditChatDescriptionRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..description = description;
    await _callAsync('__engine', 'EditChatDescription', req.writeToBuffer());
  }

  Future<void> toggleForum(String accountId, String chatId, bool enabled) async {
    final req = epb.EngineToggleForumRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..enabled = enabled;
    await _callAsync('__engine', 'ToggleForum', req.writeToBuffer());
  }

  Future<void> setForumViewAsMessages(String accountId, String chatId, bool asMessages) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'as_messages': asMessages,
    }));
    await _callAsync('__engine', 'SetForumViewAsMessages', Uint8List.fromList(payload));
  }

  Future<void> clearHistory(String accountId, String chatId) async {
    final req = epb.EngineClearHistoryRequest()
      ..accountId = accountId
      ..chatId = chatId;
    await _callAsync('__engine', 'ClearHistory', req.writeToBuffer());
  }

  Future<void> deleteChat(String accountId, String chatId) async {
    final req = epb.EngineDeleteChatRequest()
      ..accountId = accountId
      ..chatId = chatId;
    await _callAsync('__engine', 'DeleteChat', req.writeToBuffer());
  }

  Future<epb.EngineChatInfo> createChannel(String accountId, String name, String description) async {
    final req = epb.EngineCreateChannelRequest()
      ..accountId = accountId
      ..name = name
      ..description = description;
    final respBytes = await _callAsync('__engine', 'CreateChannel', req.writeToBuffer());
    final resp = epb.EngineCreateChannelResponse.fromBuffer(respBytes);
    return resp.chat;
  }

  Future<Map<String, dynamic>> createGroup(String accountId, String name, List<String> members) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'name': name,
      'members': members,
    }));
    final respBytes = await _callAsync('__engine', 'CreateGroup', Uint8List.fromList(payload));
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<void> addMembers(String accountId, String chatId, List<String> userIds) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'user_ids': userIds,
    }));
    await _callAsync('__engine', 'AddMembers', Uint8List.fromList(payload));
  }

  Future<String> getInviteLink(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetInviteLink', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['link'] as String? ?? '';
  }

  // ── Data Export ──

  Future<void> startExport(String accountId, Map<String, dynamic> settings) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      ...settings,
    }));
    await _callAsync('__engine', 'StartExport', Uint8List.fromList(payload));
  }

  Future<void> skipExportFile(String accountId, int randomId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'random_id': randomId,
    }));
    await _callAsync('__engine', 'SkipExportFile', Uint8List.fromList(payload));
  }

  Future<void> cancelExport(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'CancelExport', Uint8List.fromList(payload));
  }

  Future<void> saveExportSettings(String accountId, Map<String, dynamic> settings) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'settings': settings,
    }));
    await _callAsync('__engine', 'SaveExportSettings', Uint8List.fromList(payload));
  }

  Future<Map<String, dynamic>> loadExportSettings(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    final respBytes = await _callAsync('__engine', 'LoadExportSettings', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  // ── Chat Invite Links ──

  Future<List<Map<String, dynamic>>> getExportedChatInvites(String accountId, String chatId, {bool revoked = false, String adminId = ''}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'revoked': revoked,
      if (adminId.isNotEmpty) 'admin_id': adminId,
    }));
    final respBytes = await _callAsync('__engine', 'GetExportedChatInvites', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    final list = data['links'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createChatInviteLink(String accountId, String chatId, {String label = '', int expireDate = 0, int usageLimit = 0, bool requestApproval = false, int subscriptionCredits = 0}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'label': label,
      'expire_date': expireDate,
      'usage_limit': usageLimit,
      'request_approval': requestApproval,
      'subscription_credits': subscriptionCredits,
    }));
    final respBytes = await _callAsync('__engine', 'CreateChatInviteLink', Uint8List.fromList(payload));
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> editChatInviteLink(String accountId, String chatId, String link, {String label = '', int expireDate = 0, int usageLimit = 0, bool requestApproval = false, int subscriptionCredits = 0}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'link': link,
      'label': label,
      'expire_date': expireDate,
      'usage_limit': usageLimit,
      'request_approval': requestApproval,
      'subscription_credits': subscriptionCredits,
    }));
    final respBytes = await _callAsync('__engine', 'EditChatInviteLink', Uint8List.fromList(payload));
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> revokeChatInviteLink(String accountId, String chatId, String link) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'link': link,
    }));
    final respBytes = await _callAsync('__engine', 'RevokeChatInviteLink', Uint8List.fromList(payload));
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<void> deleteRevokedChatInviteLink(String accountId, String chatId, String link) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'link': link,
    }));
    await _callAsync('__engine', 'DeleteRevokedChatInviteLink', Uint8List.fromList(payload));
  }

  Future<void> deleteAllRevokedChatInvites(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    await _callAsync('__engine', 'DeleteAllRevokedChatInvites', Uint8List.fromList(payload));
  }

  Future<List<Map<String, dynamic>>> getAdminsWithInvites(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetAdminsWithInvites', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    final list = data['admins'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<String> getChatUsername(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetChatUsername', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['username'] as String? ?? '';
  }

  Future<bool> checkChannelUsername(String accountId, String chatId, String username) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'username': username,
    }));
    final respBytes = await _callAsync('__engine', 'CheckChannelUsername', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['available'] as bool? ?? false;
  }

  Future<void> updateChannelUsername(String accountId, String chatId, String username) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'username': username,
    }));
    await _callAsync('__engine', 'UpdateChannelUsername', Uint8List.fromList(payload));
  }

  Future<Map<String, int>> getFolderLimits(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    final respBytes = await _callAsync('__engine', 'GetFolderLimits', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return {
      'free_limit': data['free_limit'] as int? ?? 10,
      'premium_limit': data['premium_limit'] as int? ?? 20,
      'chats_per_folder_free': data['chats_per_folder_free'] as int? ?? 100,
      'chats_per_folder_premium': data['chats_per_folder_premium'] as int? ?? 200,
      'shared_folders_free': data['shared_folders_free'] as int? ?? 2,
      'shared_folders_premium': data['shared_folders_premium'] as int? ?? 20,
      'links_per_folder_free': data['links_per_folder_free'] as int? ?? 3,
      'links_per_folder_premium': data['links_per_folder_premium'] as int? ?? 20,
    };
  }

  Future<Map<String, int>> getPublicLinksLimits(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    final respBytes = await _callAsync('__engine', 'GetPublicLinksLimits', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return {
      'free_limit': data['free_limit'] as int? ?? 10,
      'premium_limit': data['premium_limit'] as int? ?? 20,
    };
  }

  Future<List<Map<String, dynamic>>> getForumTopicDefaultIcons(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    final respBytes = await _callAsync('__engine', 'GetForumTopicDefaultIcons', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    final icons = data['icons'] as List<dynamic>? ?? [];
    return icons.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getChannelUsernames(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetChannelUsernames', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    final usernames = data['usernames'] as List<dynamic>? ?? [];
    return usernames.cast<Map<String, dynamic>>();
  }

  Future<bool> toggleChannelUsername(String accountId, String chatId, String username, bool active) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'username': username,
      'active': active,
    }));
    final respBytes = await _callAsync('__engine', 'ToggleChannelUsername', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['ok'] as bool? ?? false;
  }

  Future<bool> reorderChannelUsernames(String accountId, String chatId, List<String> order) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'order': order,
    }));
    final respBytes = await _callAsync('__engine', 'ReorderChannelUsernames', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['ok'] as bool? ?? false;
  }

  Future<bool> checkAccountUsername(String accountId, String username) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'username': username,
    }));
    final respBytes = await _callAsync('__engine', 'CheckAccountUsername', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['available'] as bool? ?? false;
  }

  Future<void> updateAccountUsername(String accountId, String username) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'username': username,
    }));
    await _callAsync('__engine', 'UpdateAccountUsername', Uint8List.fromList(payload));
  }

  Future<List<Map<String, dynamic>>> getAccountUsernames(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    final respBytes = await _callAsync('__engine', 'GetAccountUsernames', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    final usernames = data['usernames'] as List<dynamic>? ?? [];
    return usernames.cast<Map<String, dynamic>>();
  }

  Future<bool> toggleAccountUsername(String accountId, String username, bool active) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'username': username,
      'active': active,
    }));
    final respBytes = await _callAsync('__engine', 'ToggleAccountUsername', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['ok'] as bool? ?? false;
  }

  Future<bool> reorderAccountUsernames(String accountId, List<String> order) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'order': order,
    }));
    final respBytes = await _callAsync('__engine', 'ReorderAccountUsernames', Uint8List.fromList(payload));
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['ok'] as bool? ?? false;
  }

  Future<String> createPoll(
    String accountId, String chatId, String question, List<String> options, {
    bool multipleChoice = false,
    bool anonymous = true,
    bool quiz = false,
    bool allowRevoting = true,
    int correctOption = -1,
    String solution = '',
  }) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'question': question,
      'options': options,
      'multiple_choice': multipleChoice,
      'anonymous': anonymous,
      'quiz': quiz,
      'allow_revoting': allowRevoting,
      'correct_option': correctOption,
      'solution': solution,
    }));
    final respBytes = await _callAsync('__engine', 'CreatePoll', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return '';
    final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return data['msg_id'] as String? ?? '';
  }

  Future<List<PublicLinkInfo>> getAdminedPublicChannels(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    final resp = await _callAsync('__engine', 'GetAdminedPublicChannels', Uint8List.fromList(payload));
    if (resp.isEmpty) return [];
    final list = json.decode(utf8.decode(resp)) as List<dynamic>;
    return list.map((j) => PublicLinkInfo.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<AdminLogEvent>> getAdminLogEvents(
    String accountId,
    String chatId, {
    int limit = 20,
    String query = '',
    int maxId = 0,
    Map<String, bool>? filters,
  }) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'limit': limit,
      'query': query,
      'max_id': maxId,
      if (filters != null) 'filters': filters,
    }));
    final resp = await _callAsync('__engine', 'GetAdminLogEvents', Uint8List.fromList(payload));
    if (resp.isEmpty) return [];
    final list = json.decode(utf8.decode(resp)) as List<dynamic>;
    return list.map((j) => AdminLogEvent.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getDefaultBannedRights(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetDefaultBannedRights', Uint8List.fromList(payload));
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<void> setDefaultBannedRights(String accountId, String chatId, Map<String, dynamic> rights) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      ...rights,
    }));
    await _callAsync('__engine', 'SetDefaultBannedRights', Uint8List.fromList(payload));
  }

  Future<Map<String, dynamic>> getChatPermissionFlags(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetChatPermissionFlags', Uint8List.fromList(payload));
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<void> setSlowMode(String accountId, String chatId, int seconds) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'seconds': seconds,
    }));
    await _callAsync('__engine', 'SetSlowMode', Uint8List.fromList(payload));
  }

  Future<void> toggleJoinToSend(String accountId, String chatId, bool enabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'enabled': enabled,
    }));
    await _callAsync('__engine', 'ToggleJoinToSend', Uint8List.fromList(payload));
  }

  Future<void> toggleNoForwards(String accountId, String chatId, bool enabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'enabled': enabled,
    }));
    await _callAsync('__engine', 'ToggleNoForwards', Uint8List.fromList(payload));
  }

  Future<void> toggleJoinRequest(String accountId, String chatId, bool enabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'enabled': enabled,
    }));
    await _callAsync('__engine', 'ToggleJoinRequest', Uint8List.fromList(payload));
  }

  Future<void> toggleAntiSpam(String accountId, String chatId, bool enabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'enabled': enabled,
    }));
    await _callAsync('__engine', 'ToggleAntiSpam', Uint8List.fromList(payload));
  }

  Future<void> togglePeerTranslations(String accountId, String chatId, bool disabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'disabled': disabled,
    }));
    await _callAsync('__engine', 'TogglePeerTranslations', Uint8List.fromList(payload));
  }

  Future<void> togglePreHistoryHidden(String accountId, String chatId, bool hidden) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'hidden': hidden,
    }));
    await _callAsync('__engine', 'TogglePreHistoryHidden', Uint8List.fromList(payload));
  }

  Future<void> toggleSignatures(String accountId, String chatId, bool enabled, {bool? profilesEnabled}) async {
    final data = <String, dynamic>{
      'account_id': accountId,
      'chat_id': chatId,
      'enabled': enabled,
    };
    if (profilesEnabled != null) {
      data['profiles_enabled'] = profilesEnabled;
    }
    await _callAsync('__engine', 'ToggleSignatures', Uint8List.fromList(utf8.encode(json.encode(data))));
  }

  Future<void> setChatReactionsMode(String accountId, String chatId, String mode, {List<String> emojis = const []}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'mode': mode,
      'emojis': emojis,
    }));
    await _callAsync('__engine', 'SetChatReactionsMode', Uint8List.fromList(payload));
  }

  Future<void> updateChannelColor(String accountId, String chatId, int colorIndex) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'color_index': colorIndex,
    }));
    await _callAsync('__engine', 'UpdateChannelColor', Uint8List.fromList(payload));
  }

  Future<void> updatePaidMessagesPrice(String accountId, String chatId, int stars, {bool broadcastEnabled = false}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'stars': stars,
      'broadcast_enabled': broadcastEnabled,
    }));
    await _callAsync('__engine', 'UpdatePaidMessagesPrice', Uint8List.fromList(payload));
  }

  Future<Map<String, dynamic>> getFullChatInfo(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final respBytes = await _callAsync('__engine', 'GetFullChatInfo', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getParticipantInfo(String accountId, String chatId, String userId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'user_id': userId,
    }));
    final respBytes = await _callAsync('__engine', 'GetParticipantInfo', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<void> editChannelPhoto(String accountId, String chatId, String filePath) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'file_path': filePath,
    }));
    await _callAsync('__engine', 'EditChannelPhoto', Uint8List.fromList(payload));
  }

  Future<void> deleteChannelPhoto(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    await _callAsync('__engine', 'DeleteChannelPhoto', Uint8List.fromList(payload));
  }

  Future<void> setGroupStickerSet(String accountId, String chatId, String shortName) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'short_name': shortName,
    }));
    await _callAsync('__engine', 'SetGroupStickerSet', Uint8List.fromList(payload));
  }

  Future<void> setDiscussionGroup(String accountId, String broadcastId, String groupId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'broadcast_id': broadcastId,
      'group_id': groupId,
    }));
    await _callAsync('__engine', 'SetDiscussionGroup', Uint8List.fromList(payload));
  }

  Future<List<Map<String, dynamic>>> getDiscussionGroups(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    final respBytes = await _callAsync('__engine', 'GetDiscussionGroups', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return [];
    final decoded = json.decode(utf8.decode(respBytes));
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<void> forwardMessage(String accountId, String chatId, String msgId, String toChatId, {
    bool dropAuthor = false,
    bool dropCaptions = false,
    bool silent = false,
    int scheduleDate = 0,
  }) async {
    final req = epb.EngineForwardMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..toChatId = toChatId
      ..dropAuthor = dropAuthor
      ..dropCaptions = dropCaptions
      ..silent = silent;
    if (scheduleDate > 0) {
      req.scheduleDate = Int64(scheduleDate);
    }
    await _callAsync('__engine', 'ForwardMessage', req.writeToBuffer());
  }

  Future<void> resendAsOwn(String accountId, String sourceChatId, String msgId, String toChatId, {
    bool silent = false,
    int scheduleDate = 0,
    bool dropCaptions = false,
  }) async {
    final req = epb.EngineResendAsOwnRequest()
      ..accountId = accountId
      ..sourceChatId = sourceChatId
      ..msgId = msgId
      ..toChatId = toChatId
      ..silent = silent
      ..dropCaptions = dropCaptions;
    if (scheduleDate > 0) {
      req.scheduleDate = Int64(scheduleDate);
    }
    await _callAsync('__engine', 'ResendAsOwn', req.writeToBuffer());
  }

  Future<void> resendAlbumAsOwn(String accountId, String sourceChatId, List<String> msgIds, String toChatId, {
    bool silent = false,
    int scheduleDate = 0,
    bool dropCaptions = false,
  }) async {
    final req = epb.EngineResendAlbumAsOwnRequest()
      ..accountId = accountId
      ..sourceChatId = sourceChatId
      ..msgIds.addAll(msgIds)
      ..toChatId = toChatId
      ..silent = silent
      ..dropCaptions = dropCaptions;
    if (scheduleDate > 0) {
      req.scheduleDate = Int64(scheduleDate);
    }
    await _callAsync('__engine', 'ResendAlbumAsOwn', req.writeToBuffer());
  }

  Future<void> sendContact(String accountId, String toChatId, String phone, String firstName, String lastName, {String userId = ''}) async {
    final req = epb.EngineSendContactRequest()
      ..accountId = accountId
      ..toChatId = toChatId
      ..phone = phone
      ..firstName = firstName
      ..lastName = lastName
      ..userId = userId;
    await _callAsync('__engine', 'SendContact', req.writeToBuffer());
  }

  Future<void> sendScheduledNow(String accountId, String chatId, List<String> msgIds) async {
    final req = epb.EngineSendScheduledNowRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgIds.addAll(msgIds);
    await _callAsync('__engine', 'SendScheduledNow', req.writeToBuffer());
  }

  Future<void> rescheduleMessage(String accountId, String chatId, String msgId, int scheduleDate) async {
    final req = epb.EngineRescheduleMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..scheduleDate = Int64(scheduleDate);
    await _callAsync('__engine', 'RescheduleMessage', req.writeToBuffer());
  }

  Future<void> reactToMessage(String accountId, String chatId, String msgId, String emoji) async {
    final req = epb.EngineReactToMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..emoji = emoji;
    await _callAsync('__engine', 'ReactToMessage', req.writeToBuffer());
  }

  Future<ReactorsListResult> getMessageReactorsList(String accountId, String chatId, int msgId, {int limit = 50, String offset = '', String reactionFilter = ''}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
      'limit': limit,
      if (offset.isNotEmpty) 'offset': offset,
      if (reactionFilter.isNotEmpty) 'reaction_filter': reactionFilter,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetMessageReactorsList', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return const ReactorsListResult(reactors: [], nextOffset: '');
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      final reactorsList = (data['reactors'] as List<dynamic>?) ?? [];
      final nextOffset = (data['next_offset'] as String?) ?? '';
      final reactors = reactorsList.map((e) => ReactorInfo(
        emoji: (e['emoji'] as String?) ?? '',
        documentId: (e['document_id'] as num?)?.toInt() ?? 0,
        peerId: (e['peer_id'] as String?) ?? '',
        peerName: (e['peer_name'] as String?) ?? '',
        date: (e['date'] as num?)?.toInt() ?? 0,
      )).toList();
      return ReactorsListResult(reactors: reactors, nextOffset: nextOffset);
    } catch (e) {
      Debug.error('ENGINE', 'getMessageReactorsList failed', e);
      return const ReactorsListResult(reactors: [], nextOffset: '');
    }
  }

  Future<ReadDateResult> getOutboxReadDate(String accountId, String chatId, String msgId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetOutboxReadDate', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return const ReadDateResult();
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      final date = (data['date'] as num?)?.toInt() ?? 0;
      final privacyStr = data['privacy_state'] as String? ?? '';
      final privacyState = switch (privacyStr) {
        'my_hidden' => ReadPrivacyState.myHidden,
        'his_hidden' => ReadPrivacyState.hisHidden,
        'too_old' => ReadPrivacyState.tooOld,
        _ => ReadPrivacyState.none,
      };
      return ReadDateResult(date: date, privacyState: privacyState);
    } catch (e) {
      Debug.error('ENGINE', 'getOutboxReadDate failed', e);
      return const ReadDateResult();
    }
  }

  Future<List<int>> getMessageReadParticipants(String accountId, String chatId, String msgId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetMessageReadParticipants', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      final userIds = (data['user_ids'] as List<dynamic>?) ?? [];
      return userIds.map((e) => (e as num).toInt()).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getMessageReadParticipants failed', e);
      return [];
    }
  }

  Future<ReadParticipantsResult> getMessageReadParticipantsDetailed(String accountId, String chatId, String msgId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetMessageReadParticipantsDetailed', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return const ReadParticipantsResult();
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      final privacyStr = data['privacy_state'] as String? ?? '';
      final privacyState = switch (privacyStr) {
        'my_hidden' => ReadPrivacyState.myHidden,
        'his_hidden' => ReadPrivacyState.hisHidden,
        'too_old' => ReadPrivacyState.tooOld,
        _ => ReadPrivacyState.none,
      };
      final list = (data['participants'] as List<dynamic>?) ?? [];
      final participants = list.map((e) {
        final m = e as Map<String, dynamic>;
        return ReadParticipantInfo(
          userId: ((m['user_id'] as num?)?.toInt() ?? 0).toString(),
          date: (m['date'] as num?)?.toInt() ?? 0,
          name: m['name'] as String? ?? '',
        );
      }).toList();
      return ReadParticipantsResult(participants: participants, privacyState: privacyState);
    } catch (e) {
      Debug.error('ENGINE', 'getMessageReadParticipantsDetailed failed', e);
      return const ReadParticipantsResult();
    }
  }

  Future<int> getScheduledCount(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetScheduledCount', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return 0;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (data['count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<List<CachedMessage>> getScheduledMessages(String accountId, String chatId) async {
    final req = epb.EngineGetMessagesRequest()
      ..accountId = accountId
      ..chatId = chatId;
    try {
      final respBytes = await _callAsync('__engine', 'GetScheduledMessages', req.writeToBuffer());
      if (respBytes.isEmpty) return [];
      final resp = epb.EngineGetMessagesResponse.fromBuffer(respBytes);
      return resp.messages.map(_cachedMsgFromProto).toList();
    } catch (e) {
      return [];
    }
  }

  Future<CachedMessage?> getOldestUnreadMention(String accountId, String chatId) async {
    final req = epb.EngineGetMessagesRequest()
      ..accountId = accountId
      ..chatId = chatId;
    try {
      final respBytes = await _callAsync('__engine', 'GetUnreadMentions', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineGetMessagesResponse.fromBuffer(respBytes);
      if (resp.messages.isEmpty) return null;
      return _cachedMsgFromProto(resp.messages.first);
    } catch (e) {
      return null;
    }
  }

  Future<CachedMessage?> getOldestUnreadReaction(String accountId, String chatId) async {
    final req = epb.EngineGetMessagesRequest()
      ..accountId = accountId
      ..chatId = chatId;
    try {
      final respBytes = await _callAsync('__engine', 'GetUnreadReactions', req.writeToBuffer());
      if (respBytes.isEmpty) return null;
      final resp = epb.EngineGetMessagesResponse.fromBuffer(respBytes);
      if (resp.messages.isEmpty) return null;
      return _cachedMsgFromProto(resp.messages.first);
    } catch (e) {
      return null;
    }
  }

  // ── Inline bot results (JSON-based, no proto) ──

  Future<InlineBotResults?> getInlineBotResults(String accountId, String botId, String query, {String offset = '', String chatId = ''}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'bot_id': botId,
      'query': query,
      'offset': offset,
      'chat_id': chatId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetInlineBotResults', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return InlineBotResults.fromJson(data);
    } catch (e) {
      Debug.error('ENGINE', 'getInlineBotResults failed', e);
      return null;
    }
  }

  Future<StarGiftsResult?> getStarGifts(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetStarGifts', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return StarGiftsResult.fromJson(data);
    } catch (e) {
      Debug.error('ENGINE', 'getStarGifts failed', e);
      return null;
    }
  }

  Future<PinnedGiftsResult?> getPinnedStarGifts(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetPinnedStarGifts', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return PinnedGiftsResult.fromJson(data);
    } catch (e) {
      Debug.error('ENGINE', 'getPinnedStarGifts failed', e);
      return null;
    }
  }

  Future<bool> sendStarGift(String accountId, String chatId, int giftId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'gift_id': giftId,
    }));
    try {
      await _callAsync('__engine', 'SendStarGift', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'sendStarGift failed', e);
      return false;
    }
  }

  Future<String?> resolveUsername(String accountId, String username) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'username': username,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'ResolveUsername', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return data['user_id'] as String?;
    } catch (e) {
      Debug.error('ENGINE', 'resolveUsername failed', e);
      return null;
    }
  }

  Future<String?> downloadSingleAvatar(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'DownloadSingleAvatar', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return data['path'] as String?;
    } catch (e) {
      Debug.error('ENGINE', 'downloadSingleAvatar failed', e);
      return null;
    }
  }

  Future<UserProfile?> getUserProfile(String accountId, String userId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'user_id': userId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetUserProfile', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return UserProfile.fromJson(data);
    } catch (e) {
      Debug.error('ENGINE', 'getUserProfile failed', e);
      return null;
    }
  }

  Future<int> getUserPhotoCount(String accountId, String userId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'user_id': userId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetUserPhotoCount', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return 1;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (data['count'] as num?)?.toInt() ?? 1;
    } catch (e) {
      Debug.error('ENGINE', 'getUserPhotoCount failed', e);
      return 1;
    }
  }

  Future<String?> getUserPhotoAtIndex(String accountId, String userId, int index) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'user_id': userId,
      'index': index,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetUserPhotoAtIndex', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return data['path'] as String?;
    } catch (e) {
      Debug.error('ENGINE', 'getUserPhotoAtIndex failed', e);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getCommonChats(String accountId, String userId, {int limit = 100}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'user_id': userId,
      'limit': limit,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetCommonChats', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final data = json.decode(utf8.decode(respBytes));
      if (data is Map && data['chats'] is List) {
        return (data['chats'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Debug.error('ENGINE', 'getCommonChats failed', e);
      return [];
    }
  }

  Future<String> getSelfBio(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetSelfBio', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return '';
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return data['bio'] as String? ?? '';
    } catch (e) {
      Debug.error('ENGINE', 'getSelfBio failed', e);
      return '';
    }
  }

  Future<void> updateBio(String accountId, String bio) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'bio': bio,
    }));
    await _callAsync('__engine', 'UpdateBio', Uint8List.fromList(payload));
  }

  Future<({int day, int month, int year})> getSelfBirthday(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetSelfBirthday', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return (day: 0, month: 0, year: 0);
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (
        day: data['day'] as int? ?? 0,
        month: data['month'] as int? ?? 0,
        year: data['year'] as int? ?? 0,
      );
    } catch (e) {
      Debug.error('ENGINE', 'getSelfBirthday failed', e);
      return (day: 0, month: 0, year: 0);
    }
  }

  Future<void> updateBirthday(String accountId, int day, int month, int year) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'day': day,
      'month': month,
      'year': year,
    }));
    await _callAsync('__engine', 'UpdateBirthday', Uint8List.fromList(payload));
  }

  Future<({int colorId, String channelName})> getSelfColorAndChannel(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetSelfColorAndChannel', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return (colorId: -1, channelName: '');
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (
        colorId: data['color_id'] as int? ?? -1,
        channelName: data['channel_name'] as String? ?? '',
      );
    } catch (e) {
      Debug.error('ENGINE', 'getSelfColorAndChannel failed', e);
      return (colorId: -1, channelName: '');
    }
  }

  Future<void> updateProfile(String accountId, String firstName, String lastName) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'first_name': firstName,
      'last_name': lastName,
      'about': '',
    }));
    await _callAsync('__engine', 'UpdateProfile', Uint8List.fromList(payload));
  }

  Future<void> updateNameColor(String accountId, int colorId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'color_id': colorId,
    }));
    await _callAsync('__engine', 'UpdateNameColor', Uint8List.fromList(payload));
  }

  Future<({bool sensitiveEnabled, bool sensitiveCanChange})> getContentSettings(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetContentSettings', Uint8List.fromList(payload));
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (
        sensitiveEnabled: data['sensitive_enabled'] as bool? ?? false,
        sensitiveCanChange: data['sensitive_can_change'] as bool? ?? false,
      );
    } catch (e) {
      Debug.error('ENGINE', 'getContentSettings failed', e);
      return (sensitiveEnabled: false, sensitiveCanChange: false);
    }
  }

  Future<void> setContentSettings(String accountId, bool sensitiveEnabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'sensitive_enabled': sensitiveEnabled,
    }));
    await _callAsync('__engine', 'SetContentSettings', Uint8List.fromList(payload));
  }

  Future<({bool archiveAndMute, bool keepArchivedUnmuted, bool keepArchivedFolders})> getArchiveSettings(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetArchiveSettings', Uint8List.fromList(payload));
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (
        archiveAndMute: data['archive_and_mute'] as bool? ?? false,
        keepArchivedUnmuted: data['keep_archived_unmuted'] as bool? ?? false,
        keepArchivedFolders: data['keep_archived_folders'] as bool? ?? false,
      );
    } catch (e) {
      Debug.error('ENGINE', 'getArchiveSettings failed', e);
      return (archiveAndMute: false, keepArchivedUnmuted: false, keepArchivedFolders: false);
    }
  }

  Future<void> setArchiveSettings(String accountId, {required bool archiveAndMute, required bool keepArchivedUnmuted, required bool keepArchivedFolders}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'archive_and_mute': archiveAndMute,
      'keep_archived_unmuted': keepArchivedUnmuted,
      'keep_archived_folders': keepArchivedFolders,
    }));
    await _callAsync('__engine', 'SetArchiveSettings', Uint8List.fromList(payload));
  }

  Future<void> setEmojiStatus(String accountId, String emoji, int expiresInSeconds) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'emoji': emoji,
      'expires_in': expiresInSeconds,
    }));
    await _callAsync('__engine', 'SetEmojiStatus', Uint8List.fromList(payload));
  }

  Future<void> clearEmojiStatus(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'ClearEmojiStatus', Uint8List.fromList(payload));
  }

  Future<void> setPersonalChannel(String accountId, String channelUsername) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'channel_username': channelUsername,
    }));
    await _callAsync('__engine', 'SetPersonalChannel', Uint8List.fromList(payload));
  }

  Future<void> clearPersonalChannel(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'ClearPersonalChannel', Uint8List.fromList(payload));
  }

  Future<void> clearPaymentInfo(String accountId, {required bool clearCredentials, required bool clearShipping}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'clear_credentials': clearCredentials,
      'clear_shipping': clearShipping,
    }));
    await _callAsync('__engine', 'ClearPaymentInfo', Uint8List.fromList(payload));
  }

  Future<Map<String, dynamic>> getPaymentForm(String accountId, String chatId, String msgId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
    }));
    final respBytes = await _callAsync('__engine', 'GetPaymentForm', Uint8List.fromList(payload));
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<void> sendPaymentForm(String accountId, String chatId, String msgId, Map<String, dynamic> formData) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
      'form_data': formData,
    }));
    await _callAsync('__engine', 'SendPaymentForm', Uint8List.fromList(payload));
  }

  Future<Map<String, dynamic>> getPaymentReceipt(String accountId, String chatId, String msgId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
    }));
    final respBytes = await _callAsync('__engine', 'GetPaymentReceipt', Uint8List.fromList(payload));
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<bool> getHideReadMarks(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetHideReadMarks', Uint8List.fromList(payload));
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return data['hide_read_marks'] as bool? ?? false;
    } catch (e) {
      Debug.error('ENGINE', 'getHideReadMarks failed', e);
      return false;
    }
  }

  Future<void> setHideReadMarks(String accountId, {required bool hide}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'hide_read_marks': hide,
    }));
    await _callAsync('__engine', 'SetHideReadMarks', Uint8List.fromList(payload));
  }

  Future<({String option, int chargeStars})> getMessagesPrivacy(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetMessagesPrivacy', Uint8List.fromList(payload));
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (
        option: data['option'] as String? ?? 'everyone',
        chargeStars: (data['charge_stars'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      Debug.error('ENGINE', 'getMessagesPrivacy failed', e);
      return (option: 'everyone', chargeStars: 0);
    }
  }

  Future<void> setMessagesPrivacy(String accountId, {required String option, int chargeStars = 0}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'option': option,
      'charge_stars': chargeStars,
    }));
    await _callAsync('__engine', 'SetMessagesPrivacy', Uint8List.fromList(payload));
  }

  Future<({int maxStars, int commissionPermille, double withdrawRate})> getPaidMessagesConfig(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetPaidMessagesConfig', Uint8List.fromList(payload));
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return (
        maxStars: (data['max_stars'] as num?)?.toInt() ?? 10000,
        commissionPermille: (data['commission_permille'] as num?)?.toInt() ?? 150,
        withdrawRate: (data['withdraw_rate'] as num?)?.toDouble() ?? 0.013,
      );
    } catch (e) {
      Debug.error('ENGINE', 'getPaidMessagesConfig failed', e);
      return (maxStars: 10000, commissionPermille: 150, withdrawRate: 0.013);
    }
  }

  Future<List<CloudThemeInfo>> getCloudThemes(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetCloudThemes', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final data = json.decode(utf8.decode(respBytes));
      if (data == null) return [];
      return (data as List).map((e) => CloudThemeInfo.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getCloudThemes failed', e);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getWallpapers(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetWallpapers', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final data = json.decode(utf8.decode(respBytes));
      if (data == null) return [];
      return (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      Debug.error('ENGINE', 'getWallpapers failed', e);
      return [];
    }
  }

  Future<void> installCloudTheme(String accountId, int themeId, {bool isDark = false}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'theme_id': themeId,
      'is_dark': isDark,
    }));
    await _callAsync('__engine', 'InstallCloudTheme', Uint8List.fromList(payload));
  }

  Future<void> deleteCloudTheme(String accountId, int themeId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'theme_id': themeId,
    }));
    await _callAsync('__engine', 'DeleteCloudTheme', Uint8List.fromList(payload));
  }

  Future<Map<String, dynamic>?> createCloudTheme(String accountId, String title, String slug, Uint8List themeData) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'title': title,
      'slug': slug,
      'theme_data': base64.encode(themeData),
    }));
    try {
      final respBytes = await _callAsync('__engine', 'CreateCloudTheme', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'createCloudTheme failed', e);
      rethrow;
    }
  }

  Future<void> uploadProfilePhoto(String accountId, String filePath) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'file_path': filePath,
    }));
    await _callAsync('__engine', 'UploadProfilePhoto', Uint8List.fromList(payload));
  }

  Future<void> deleteProfilePhotos(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'DeleteProfilePhotos', Uint8List.fromList(payload));
  }

  Future<void> uploadFallbackPhoto(String accountId, String filePath) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'file_path': filePath,
    }));
    await _callAsync('__engine', 'UploadFallbackPhoto', Uint8List.fromList(payload));
  }

  Future<void> deleteFallbackPhoto(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'DeleteFallbackPhoto', Uint8List.fromList(payload));
  }

  Future<bool> hasFallbackPhoto(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'HasFallbackPhoto', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return false;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return data['has'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<int?> sendInlineBotResult(String accountId, String chatId, int queryId, String resultId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'query_id': queryId,
      'result_id': resultId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'SendInlineBotResult', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      final data = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return data['msg_id'] as int?;
    } catch (e) {
      Debug.error('ENGINE', 'sendInlineBotResult failed', e);
      return null;
    }
  }

  // ── Similar channels ──

  Future<List<SimilarChannelInfo>> getSimilarChannels(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetSimilarChannels', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final list = json.decode(utf8.decode(respBytes)) as List<dynamic>;
      return list.map((e) => SimilarChannelInfo.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getSimilarChannels failed', e);
      return [];
    }
  }

  Future<List<BotCommandInfo>> getChatBotCommands(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetChatBotCommands', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final list = json.decode(utf8.decode(respBytes)) as List<dynamic>;
      return list.map((e) => BotCommandInfo.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getChatBotCommands failed', e);
      return [];
    }
  }

  // ── Chat themes ──

  Future<List<ChatThemeData>> getChatThemes(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetChatThemes', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final list = json.decode(utf8.decode(respBytes)) as List<dynamic>;
      return list.map((e) => ChatThemeData.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getChatThemes failed', e);
      return [];
    }
  }

  Future<bool> setChatTheme(String accountId, String chatId, String emoticon) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'emoticon': emoticon,
    }));
    try {
      await _callAsync('__engine', 'SetChatTheme', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'setChatTheme failed', e);
      return false;
    }
  }

  // ── Bot callback ──

  Future<String> botCallback(String accountId, String chatId, String msgId, String data) async {
    final req = epb.EngineBotCallbackRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..data = data;
    final respBytes = await _callAsync('__engine', 'BotCallback', req.writeToBuffer());
    if (respBytes.isEmpty) return '';
    final resp = epb.EngineBotCallbackResponse.fromBuffer(respBytes);
    return resp.message;
  }

  Future<({String message, String url, bool showAlert})> botCallbackFull(String accountId, String chatId, String msgId, String data) async {
    final req = epb.EngineBotCallbackRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..data = data;
    final respBytes = await _callAsync('__engine', 'BotCallback', req.writeToBuffer());
    if (respBytes.isEmpty) return (message: '', url: '', showAlert: false);
    final resp = epb.EngineBotCallbackResponse.fromBuffer(respBytes);
    return (message: resp.message, url: resp.url, showAlert: resp.showAlert);
  }

  Future<String> requestBotWebView(String accountId, String chatId, String botId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'bot_id': botId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'RequestBotWebView', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return '';
      final m = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return m['url'] as String? ?? '';
    } catch (e) {
      Debug.error('ENGINE', 'requestBotWebView failed', e);
      return '';
    }
  }

  Future<Map<String, dynamic>> requestUrlAuth(String accountId, String chatId, String msgId, int buttonId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
      'button_id': buttonId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'RequestURLAuth', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return {'type': 'default'};
      return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'requestUrlAuth failed', e);
      return {'type': 'error', 'message': e.toString()};
    }
  }

  Future<String> acceptUrlAuth(String accountId, String chatId, String msgId, int buttonId, bool writeAllowed, bool sharePhone) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'msg_id': msgId,
      'button_id': buttonId,
      'write_allowed': writeAllowed,
      'share_phone': sharePhone,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'AcceptURLAuth', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return '';
      final m = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return m['url'] as String? ?? '';
    } catch (e) {
      Debug.error('ENGINE', 'acceptUrlAuth failed', e);
      return '';
    }
  }

  Future<void> pinMessage(String accountId, String chatId, String msgId, bool pinned) async {
    final req = epb.EnginePinMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..pinned = pinned;
    await _callAsync('__engine', 'PinMessage', req.writeToBuffer());
  }

  Future<String> uploadFile(String accountId, String chatId, String filePath, {String caption = '', String captionEntities = '', bool silent = false, int scheduleDate = 0, bool spoiler = false, bool sendAsDocument = false, bool captionAbove = false, String videoCoverPath = ''}) async {
    final req = epb.EngineUploadFileRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..filePath = filePath
      ..caption = caption
      ..silent = silent
      ..scheduleDate = scheduleDate
      ..spoiler = spoiler
      ..sendAsDocument = sendAsDocument
      ..captionAbove = captionAbove
      ..captionEntities = captionEntities
      ..videoCoverPath = videoCoverPath;
    final resp = epb.EngineUploadFileResponse.fromBuffer(
      await _callAsync('__engine', 'UploadFile', req.writeToBuffer()),
    );
    return resp.msgId;
  }

  Future<String> sendVoice(String accountId, String chatId, String filePath, {int duration = 0, String caption = ''}) async {
    final req = epb.EngineUploadFileRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..filePath = filePath
      ..caption = caption
      ..duration = duration;
    final resp = epb.EngineUploadFileResponse.fromBuffer(
      await _callAsync('__engine', 'UploadFile', req.writeToBuffer()),
    );
    return resp.msgId;
  }

  Future<String> sendVideoNote(String accountId, String chatId, String filePath, {int duration = 0, String caption = ''}) async {
    final req = epb.EngineUploadFileRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..filePath = filePath
      ..caption = caption
      ..duration = duration;
    final resp = epb.EngineUploadFileResponse.fromBuffer(
      await _callAsync('__engine', 'UploadFile', req.writeToBuffer()),
    );
    return resp.msgId;
  }

  Future<void> retryPending(String localId) async {
    final req = epb.EngineRetryPendingRequest()..localId = localId;
    await _callAsync('__engine', 'RetryPending', req.writeToBuffer());
  }

  // ── Active chat ──

  void setActiveChat(String accountId, String chatId) {
    final req = epb.EngineSetActiveChatRequest()
      ..accountId = accountId
      ..chatId = chatId;
    _callRaw('__engine', 'SetActiveChat', req.writeToBuffer());
  }

  void clearActiveChat() {
    _callRaw('__engine', 'ClearActiveChat', Uint8List(0));
  }

  // ── Search ──

  List<SearchResult> searchMessages(String query, {String accountId = '', int limit = 50}) {
    final req = epb.EngineSearchMessagesRequest()
      ..query = query
      ..accountId = accountId
      ..limit = limit;
    final respBytes = _callRaw('__engine', 'SearchMessages', req.writeToBuffer());
    final resp = epb.EngineSearchMessagesResponse.fromBuffer(respBytes);
    return resp.results.map(_searchResultFromProto).toList();
  }

  List<ChatInfo> searchChats(String query, {int limit = 20}) {
    final req = epb.EngineSearchChatsRequest()
      ..query = query
      ..limit = limit;
    final respBytes = _callRaw('__engine', 'SearchChats', req.writeToBuffer());
    final resp = epb.EngineSearchChatsResponse.fromBuffer(respBytes);
    return resp.chats.map(_chatInfoFromProto).toList();
  }

  // ── Media ──

  Future<void> requestDownload(String accountId, String chatId, String msgId, {int seq = 0, int priority = 2}) async {
    final req = epb.EngineRequestDownloadRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..seq = seq
      ..priority = priority;
    await _callAsync('__engine', 'RequestDownload', req.writeToBuffer());
  }

  void cancelDownload(String accountId, String chatId, String msgId, {int seq = 0}) {
    final req = epb.EngineCancelDownloadRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..seq = seq;
    _callRaw('__engine', 'CancelDownload', req.writeToBuffer());
  }

  int getCacheSize() {
    final respBytes = _callRaw('__engine', 'GetCacheSize', Uint8List(0));
    final resp = epb.EngineGetCacheSizeResponse.fromBuffer(respBytes);
    return resp.sizeBytes.toInt();
  }

  void clearCache({String accountId = ''}) {
    final req = epb.EngineClearCacheRequest()..accountId = accountId;
    _callRaw('__engine', 'ClearCache', req.writeToBuffer());
  }

  /// Get shared media items for a chat, optionally filtered by type.
  /// [mediaType]: "image", "video", "audio", "file", or "" for all.
  List<SharedMediaItem> getSharedMedia(String accountId, String chatId, {String mediaType = '', int limit = 50, int offset = 0}) {
    final req = epb.EngineGetSharedMediaRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..mediaType = mediaType
      ..limit = limit
      ..offset = offset;
    final respBytes = _callRaw('__engine', 'GetSharedMedia', req.writeToBuffer());
    final resp = epb.EngineGetSharedMediaResponse.fromBuffer(respBytes);
    return resp.items.map(_sharedMediaItemFromProto).toList();
  }

  Map<String, int> getSharedMediaCounts(String accountId, String chatId) {
    final req = epb.EngineGetSharedMediaCountsRequest()
      ..accountId = accountId
      ..chatId = chatId;
    final respBytes = _callRaw('__engine', 'GetSharedMediaCounts', req.writeToBuffer());
    final resp = epb.EngineGetSharedMediaCountsResponse.fromBuffer(respBytes);
    final counts = <String, int>{};
    for (final c in resp.counts) {
      counts[c.mediaType] = c.count;
    }
    return counts;
  }

  // ── Config ──

  AppConfig getConfig() {
    final respBytes = _callRaw('__engine', 'GetConfig', Uint8List(0));
    final resp = epb.EngineGetConfigResponse.fromBuffer(respBytes);
    return AppConfig(
      theme: resp.theme.isNotEmpty ? resp.theme : 'dark',
      accentColor: resp.accentColor.isNotEmpty ? resp.accentColor : '#4f6ef7',
      fontScale: resp.fontScale > 0 ? resp.fontScale : 1.0,
      language: resp.language.isNotEmpty ? resp.language : 'en',
      downloadDir: resp.downloadDir,
      maxCacheSize: resp.maxCacheSize.toInt(),
      sendReadReceipts: resp.sendReadReceipts,
      sendTyping: resp.sendTyping,
      notifyDms: resp.notifyDms,
      notifyGroups: resp.notifyGroups,
      notifyMentionsOnly: resp.notifyMentionsOnly,
    );
  }

  void markAsOnline() {
    try {
      _callRaw('__engine', 'MarkAsOnline', Uint8List(0));
    } catch (_) {}
  }

  void updateConfig({
    String? theme,
    String? accentColor,
    double? fontScale,
    String? language,
    String? downloadDir,
    int? maxCacheSize,
    bool? sendReadReceipts,
    bool? sendTyping,
    bool? sendUploadProgress,
    bool? sendReadStories,
    bool? sendOnlinePackets,
    bool? sendOfflineAfterOnline,
    bool? markReadAfterAction,
    bool? useScheduledMessages,
    bool? sendWithoutSound,
    bool? notifyDms,
    bool? notifyGroups,
    bool? notifyMentionsOnly,
  }) {
    final req = epb.EngineUpdateConfigRequest();
    if (theme != null) req.theme = theme;
    if (accentColor != null) req.accentColor = accentColor;
    if (fontScale != null) req.fontScale = fontScale;
    if (language != null) req.language = language;
    if (downloadDir != null) req.downloadDir = downloadDir;
    if (maxCacheSize != null) req.maxCacheSize = Int64(maxCacheSize);
    if (sendReadReceipts != null) {
      req.sendReadReceipts = sendReadReceipts;
      req.hasSendReadReceipts_7 = true;
    }
    if (sendTyping != null) {
      req.sendTyping = sendTyping;
      req.hasSendTyping_9 = true;
    }
    if (sendUploadProgress != null) {
      req.sendUploadProgress = sendUploadProgress;
      req.hasSendUploadProgress_29 = true;
    }
    if (sendReadStories != null) {
      req.sendReadStories = sendReadStories;
      req.hasSendReadStories_17 = true;
    }
    if (sendOnlinePackets != null) {
      req.sendOnlinePackets = sendOnlinePackets;
      req.hasSendOnlinePackets_19 = true;
    }
    if (sendOfflineAfterOnline != null) {
      req.sendOfflineAfterOnline = sendOfflineAfterOnline;
      req.hasSendOfflineAfterOnline_21 = true;
    }
    if (markReadAfterAction != null) {
      req.markReadAfterAction = markReadAfterAction;
      req.hasMarkReadAfterAction_23 = true;
    }
    if (useScheduledMessages != null) {
      req.useScheduledMessages = useScheduledMessages;
      req.hasUseScheduledMessages_25 = true;
    }
    if (sendWithoutSound != null) {
      req.sendWithoutSound = sendWithoutSound;
      req.hasSendWithoutSound_27 = true;
    }
    if (notifyDms != null) {
      req.notifyDms = notifyDms;
      req.hasNotifyDms_11 = true;
    }
    if (notifyGroups != null) {
      req.notifyGroups = notifyGroups;
      req.hasNotifyGroups_13 = true;
    }
    if (notifyMentionsOnly != null) {
      req.notifyMentionsOnly = notifyMentionsOnly;
      req.hasNotifyMentionsOnly_15 = true;
    }
    _callRaw('__engine', 'UpdateConfig', req.writeToBuffer());
  }

  // ── Global TTL (Auto-Delete Messages) ──

  Future<int> getDefaultHistoryTTL(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetDefaultHistoryTTL', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return 0;
      final resp = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return resp['period'] as int? ?? 0;
    } catch (e) {
      Debug.error('ENGINE', 'getDefaultHistoryTTL failed', e);
      return 0;
    }
  }

  Future<void> setDefaultHistoryTTL(String accountId, int period) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'period': period,
    }));
    await _callAsync('__engine', 'SetDefaultHistoryTTL', Uint8List.fromList(payload));
  }

  Future<int> getAccountTTL(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetAccountTTL', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return 0;
      final resp = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return resp['days'] as int? ?? 0;
    } catch (e) {
      Debug.error('ENGINE', 'getAccountTTL failed', e);
      return 0;
    }
  }

  Future<void> setAccountTTL(String accountId, int days) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'days': days,
    }));
    await _callAsync('__engine', 'SetAccountTTL', Uint8List.fromList(payload));
  }

  Future<bool> getTopPeersEnabled(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetTopPeersEnabled', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return true;
      final resp = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return resp['enabled'] as bool? ?? true;
    } catch (e) {
      Debug.error('ENGINE', 'getTopPeersEnabled failed', e);
      return true;
    }
  }

  Future<void> toggleTopPeers(String accountId, bool enabled) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'enabled': enabled,
    }));
    await _callAsync('__engine', 'ToggleTopPeers', Uint8List.fromList(payload));
  }

  // ── Cloud Password (2FA) ──

  Future<Map<String, dynamic>?> getCloudPasswordState(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetCloudPasswordState', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'getCloudPasswordState failed', e);
      return null;
    }
  }

  Future<void> checkCloudPassword(String accountId, String password) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'password': password,
    }));
    await _callAsync('__engine', 'CheckCloudPassword', Uint8List.fromList(payload));
  }

  Future<void> setCloudPassword(String accountId, {
    String currentPassword = '',
    required String newPassword,
    String hint = '',
    String email = '',
  }) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'current_password': currentPassword,
      'new_password': newPassword,
      'hint': hint,
      'email': email,
    }));
    await _callAsync('__engine', 'SetCloudPassword', Uint8List.fromList(payload));
  }

  Future<void> removeCloudPassword(String accountId, String password) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'password': password,
    }));
    await _callAsync('__engine', 'RemoveCloudPassword', Uint8List.fromList(payload));
  }

  Future<void> confirmPasswordEmail(String accountId, String code) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'code': code,
    }));
    await _callAsync('__engine', 'ConfirmPasswordEmail', Uint8List.fromList(payload));
  }

  Future<void> resendPasswordEmail(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'ResendPasswordEmail', Uint8List.fromList(payload));
  }

  Future<void> cancelPasswordEmail(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'CancelPasswordEmail', Uint8List.fromList(payload));
  }

  Future<String> requestPasswordRecovery(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    final respBytes = await _callAsync('__engine', 'RequestPasswordRecovery', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return '';
    final decoded = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    return decoded['emailPattern'] as String? ?? '';
  }

  Future<Map<String, dynamic>> resetPassword(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    final respBytes = await _callAsync('__engine', 'ResetPassword', Uint8List.fromList(payload));
    if (respBytes.isEmpty) return {};
    return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
  }

  Future<void> cancelResetPassword(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    await _callAsync('__engine', 'CancelResetPassword', Uint8List.fromList(payload));
  }

  Future<void> setCloudPasswordEmail(String accountId, {required String currentPassword, required String email}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'current_password': currentPassword,
      'email': email,
    }));
    await _callAsync('__engine', 'SetCloudPasswordEmail', Uint8List.fromList(payload));
  }

  Future<void> checkRecoveryPassword(String accountId, String code) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'code': code,
    }));
    await _callAsync('__engine', 'CheckRecoveryPassword', Uint8List.fromList(payload));
  }

  Future<void> recoverPasswordWithCode(String accountId, {required String code, String newPassword = '', String hint = ''}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'code': code,
      'new_password': newPassword,
      'hint': hint,
    }));
    await _callAsync('__engine', 'RecoverPasswordWithCode', Uint8List.fromList(payload));
  }

  // ── Passkeys ──

  Future<List<Map<String, dynamic>>> getPasskeyList(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetPasskeyList', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final decoded = json.decode(utf8.decode(respBytes));
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Debug.error('ENGINE', 'getPasskeyList failed', e);
      return [];
    }
  }

  Future<void> removePasskey(String accountId, String passkeyId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'passkey_id': passkeyId,
    }));
    try {
      await _callAsync('__engine', 'RemovePasskey', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'removePasskey failed', e);
      rethrow;
    }
  }

  // ── Blocked Users ──

  Future<int> getBlockedUsersCount(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetBlockedUsers', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return 0;
      final decoded = json.decode(utf8.decode(respBytes));
      if (decoded is List) return decoded.length;
      return 0;
    } catch (e) {
      Debug.error('ENGINE', 'getBlockedUsersCount failed', e);
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getBlockedUsers(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetBlockedUsers', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final decoded = json.decode(utf8.decode(respBytes));
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
      return [];
    } catch (e) {
      Debug.error('ENGINE', 'getBlockedUsers failed', e);
      return [];
    }
  }

  Future<({List<Map<String, dynamic>> users, int total})> getBlockedUsersPaged(
    String accountId, {int offset = 0, int limit = 50}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'offset': offset,
      'limit': limit,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetBlockedUsers', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return (users: <Map<String, dynamic>>[], total: 0);
      final decoded = json.decode(utf8.decode(respBytes));
      if (decoded is Map) {
        final users = (decoded['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final total = decoded['total'] as int? ?? users.length;
        return (users: users, total: total);
      }
      return (users: <Map<String, dynamic>>[], total: 0);
    } catch (e) {
      Debug.error('ENGINE', 'getBlockedUsersPaged failed', e);
      return (users: <Map<String, dynamic>>[], total: 0);
    }
  }

  // ── Sessions ──

  Future<int> getSessionsCount(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetSessions', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return 0;
      final decoded = json.decode(utf8.decode(respBytes));
      if (decoded is List) return decoded.length;
      return 0;
    } catch (e) {
      Debug.error('ENGINE', 'getSessionsCount failed', e);
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getSessions(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetSessions', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final decoded = json.decode(utf8.decode(respBytes));
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
      return [];
    } catch (e) {
      Debug.error('ENGINE', 'getSessions failed', e);
      return [];
    }
  }

  Future<bool> terminateSession(String accountId, String sessionId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'session_id': sessionId,
    }));
    try {
      await _callAsync('__engine', 'TerminateSession', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'terminateSession failed', e);
      return false;
    }
  }

  Future<bool> terminateAllOtherSessions(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      await _callAsync('__engine', 'TerminateAllOtherSessions', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'terminateAllOtherSessions failed', e);
      return false;
    }
  }

  Future<int> getSessionAutoTerminateDays(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetSessionAutoTerminateDays', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return 0;
      final decoded = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
      return decoded['days'] as int? ?? 0;
    } catch (e) {
      Debug.error('ENGINE', 'getSessionAutoTerminateDays failed', e);
      return 0;
    }
  }

  Future<bool> setSessionAutoTerminateDays(String accountId, int days) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'days': days,
    }));
    try {
      await _callAsync('__engine', 'SetSessionAutoTerminateDays', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'setSessionAutoTerminateDays failed', e);
      return false;
    }
  }

  Future<bool> setCustomDeviceModel(String accountId, String model) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'model': model,
    }));
    try {
      await _callAsync('__engine', 'SetCustomDeviceModel', Uint8List.fromList(payload));
      return true;
    } catch (e) {
      Debug.error('ENGINE', 'setCustomDeviceModel failed', e);
      return false;
    }
  }

  // ── Language Pack ──

  Future<List<Map<String, dynamic>>> getLanguages(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetLanguages', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return [];
      final decoded = json.decode(utf8.decode(respBytes));
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
      return [];
    } catch (e) {
      Debug.error('ENGINE', 'getLanguages failed', e);
      return [];
    }
  }

  Future<void> saveLanguagePrefs(String accountId, Map<String, dynamic> prefs) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'prefs': prefs,
    }));
    try {
      await _callAsync('__engine', 'SaveLanguagePrefs', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'saveLanguagePrefs failed', e);
    }
  }

  Future<Map<String, dynamic>> loadLanguagePrefs(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'LoadLanguagePrefs', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return {};
      return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'loadLanguagePrefs failed', e);
      return {};
    }
  }

  // ─�� Privacy Settings ──

  Future<Map<String, dynamic>?> getPrivacySetting(String accountId, String key) async {
    final payload = utf8.encode(json.encode({'account_id': accountId, 'key': key}));
    try {
      final respBytes = await _callAsync('__engine', 'GetPrivacySetting', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'getPrivacySetting($key) failed', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getAllPrivacySettings(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final respBytes = await _callAsync('__engine', 'GetAllPrivacySettings', Uint8List.fromList(payload));
      if (respBytes.isEmpty) return null;
      return json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'getAllPrivacySettings failed', e);
      return null;
    }
  }

  Future<void> setPrivacySetting(String accountId, String key, String option, {List<String> alwaysIds = const [], List<String> neverIds = const [], bool allowPremium = false}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'key': key,
      'option': option,
      'always_ids': alwaysIds,
      'never_ids': neverIds,
      'allow_premium': allowPremium,
    }));
    await _callAsync('__engine', 'SetPrivacySetting', Uint8List.fromList(payload));
  }

  // ── Shutdown ──

  void shutdown() {
    _callRaw('__engine', 'Shutdown', Uint8List(0));
    _initialized = false;
  }

  void dispose() {
    _bridgeEventSub?.cancel();
    _bridge.dispose();
    _authStateController.close();
    _connStateController.close();
    _accountListController.close();
    _chatUpdatedController.close();
    _chatSnapshotController.close();
    _chatRemovedController.close();
    _msgReceivedController.close();
    _msgEditedController.close();
    _msgDeletedController.close();
    _msgStatusController.close();
    _typingController.close();
    _downloadProgressController.close();
    _downloadCompleteController.close();
    _userStatusController.close();
    _groupCallStateController.close();
    _exportProgressController.close();
    _exportErrorController.close();
    _exportCompleteController.close();
  }

  // ── Internal ──

  /// Synchronous bridge call — for fast local ops only.
  Uint8List _callRaw(String coreId, String method, Uint8List payload) {
    Debug.log('ENGINE', '→ $coreId.$method (${payload.length}B)');
    final req = pb.BridgeRequest()
      ..coreId = coreId
      ..method = method
      ..payload = payload;

    try {
      final respBytes = _bridge.call(Uint8List.fromList(req.writeToBuffer()));
      if (respBytes.isEmpty) {
        Debug.log('ENGINE', '← $coreId.$method = empty');
        return Uint8List(0);
      }

      final resp = pb.BridgeResponse.fromBuffer(respBytes);
      if (!resp.ok) {
        final err = resp.error.isNotEmpty ? resp.error : 'unknown error';
        Debug.error('ENGINE', '← $coreId.$method FAILED: $err (code=${resp.errorCode})');
        throw EngineException(err, code: resp.errorCode);
      }
      Debug.log('ENGINE', '← $coreId.$method OK (${resp.payload.length}B)');
      return Uint8List.fromList(resp.payload);
    } catch (e, stack) {
      if (e is EngineException) rethrow;
      Debug.error('ENGINE', '$coreId.$method crashed', e, stack);
      rethrow;
    }
  }

  /// Async bridge call — runs on background isolate to avoid UI freeze.
  /// Use for any operation that may hit the network.
  Future<Uint8List> _callAsync(String coreId, String method, Uint8List payload) async {
    Debug.log('ENGINE', '→ $coreId.$method (${payload.length}B) [async]');
    final req = pb.BridgeRequest()
      ..coreId = coreId
      ..method = method
      ..payload = payload;

    try {
      final respBytes = await _bridge.callAsync(Uint8List.fromList(req.writeToBuffer()));
      if (respBytes.isEmpty) {
        Debug.log('ENGINE', '← $coreId.$method = empty');
        return Uint8List(0);
      }

      final resp = pb.BridgeResponse.fromBuffer(respBytes);
      if (!resp.ok) {
        final err = resp.error.isNotEmpty ? resp.error : 'unknown error';
        Debug.error('ENGINE', '← $coreId.$method FAILED: $err (code=${resp.errorCode})');
        throw EngineException(err, code: resp.errorCode);
      }
      Debug.log('ENGINE', '← $coreId.$method OK (${resp.payload.length}B)');
      return Uint8List.fromList(resp.payload);
    } catch (e, stack) {
      if (e is EngineException) rethrow;
      Debug.error('ENGINE', '$coreId.$method crashed', e, stack);
      rethrow;
    }
  }

  /// Handle raw BridgeEvent bytes from Go.
  void _handleBridgeEvent(Uint8List bytes) {
    try {
      final event = pb.BridgeEvent.fromBuffer(bytes);

      if (event.coreId == '__engine' && event.engineEvent.isNotEmpty) {
        final engineEvent = json.decode(utf8.decode(event.engineEvent)) as Map<String, dynamic>;
        _dispatchEngineEvent(engineEvent);
      }
      // Non-engine core events will be handled when per-core UI is built.
    } catch (e, stack) {
      Debug.error('EVENT', 'Failed to parse bridge event', e, stack);
    }
  }

  /// Dispatch a parsed EngineEvent to the appropriate typed stream.
  void _dispatchEngineEvent(Map<String, dynamic> event) {
    final type = event['type'] as String? ?? '';
    final data = event['data'];
    Debug.log('EVENT', 'type=$type accountId=${event['account_id'] ?? ''}');

    switch (type) {
      case 'auth_state':
        if (data is Map<String, dynamic>) {
          _authStateController.add(AuthStateEvent(
            accountId: event['account_id'] as String? ?? '',
            state: data['state'] as String? ?? '',
            prompt: data['prompt'] as String? ?? '',
            error: data['error'] as String? ?? '',
          ));
        }

      case 'conn_state':
        if (data is Map<String, dynamic>) {
          _connStateController.add(ConnStateEvent(
            accountId: event['account_id'] as String? ?? '',
            state: data['state'] as String? ?? '',
            error: data['error'] as String? ?? '',
          ));
        }

      case 'account_list':
        if (data is List) {
          _accountListController.add(
            data.map((a) => AccountInfo.fromJson(a as Map<String, dynamic>)).toList(),
          );
        }

      case 'chat_snapshot':
        if (data is Map<String, dynamic>) {
          final chats = data['chats'] as List<dynamic>? ?? [];
          _chatSnapshotController.add(
            chats.map((c) => ChatInfo.fromJson(c as Map<String, dynamic>)).toList(),
          );
        }

      case 'chat_updated':
        if (data is Map<String, dynamic>) {
          final chat = data['chat'] as Map<String, dynamic>?;
          if (chat != null) _chatUpdatedController.add(ChatInfo.fromJson(chat));
        }

      case 'chat_removed':
        if (data is Map<String, dynamic>) {
          _chatRemovedController.add(ChatRemovedEvent(
            accountId: event['account_id'] as String? ?? '',
            chatId: data['chat_id'] as String? ?? '',
          ));
        }

      case 'msg_received':
        if (data is Map<String, dynamic>) {
          _msgReceivedController.add(MsgReceivedEvent.fromJson(data));
        }

      case 'msg_edited':
        if (data is Map<String, dynamic>) {
          _msgEditedController.add(MsgEditedEvent.fromJson(data));
        }

      case 'msg_deleted':
        if (data is Map<String, dynamic>) {
          _msgDeletedController.add(MsgDeletedEvent.fromJson(data));
        }

      case 'msg_status':
        if (data is Map<String, dynamic>) {
          _msgStatusController.add(MsgStatusEvent.fromJson(data));
        }

      case 'typing':
        if (data is Map<String, dynamic>) {
          _typingController.add(TypingEvent.fromJson(data));
        }

      case 'download_progress':
        if (data is Map<String, dynamic>) {
          _downloadProgressController.add(DownloadProgressEvent.fromJson(data));
        }

      case 'download_complete':
        if (data is Map<String, dynamic>) {
          _downloadCompleteController.add(DownloadCompleteEvent.fromJson(data));
        }

      case 'user_status':
        if (data is Map<String, dynamic>) {
          _userStatusController.add(UserStatusEvent.fromJson(data,
            accountId: event['account_id'] as String? ?? ''));
        }

      case 'incoming_call':
        if (data is Map<String, dynamic>) {
          _incomingCallController.add(IncomingCallEvent(
            accountId: event['account_id'] as String? ?? '',
            call: CallSessionInfo.fromJson(data),
          ));
        }

      case 'call_state':
        if (data is Map<String, dynamic>) {
          _callStateController.add(CallStateEvent(
            accountId: event['account_id'] as String? ?? '',
            call: CallSessionInfo.fromJson(data),
          ));
        }

      case 'group_call_state':
        if (data is Map<String, dynamic>) {
          _groupCallStateController.add(GroupCallStateEvent(
            accountId: event['account_id'] as String? ?? '',
            info: GroupCallInfo.fromJson(data),
          ));
        }

      case 'export_progress':
        if (data is Map<String, dynamic>) {
          _exportProgressController.add(ExportProgressEvent.fromJson(data,
            accountId: event['account_id'] as String? ?? ''));
        }

      case 'export_error':
        if (data is Map<String, dynamic>) {
          _exportErrorController.add(ExportErrorEvent.fromJson(data,
            accountId: event['account_id'] as String? ?? ''));
        }

      case 'export_complete':
        if (data is Map<String, dynamic>) {
          _exportCompleteController.add(ExportCompleteEvent.fromJson(data,
            accountId: event['account_id'] as String? ?? ''));
        }
    }
  }

  // ── Proto → Model converters ──

  static AccountInfo _accountInfoFromProto(epb.AccountInfo p) => AccountInfo(
    id: p.id,
    platform: p.platform,
    displayName: _safeStr(p.displayName),
    phone: p.phone,
    username: _safeStr(p.username),
    avatarPath: p.avatarPath,
    sortOrder: p.sortOrder,
    connState: ConnState.values[p.connState.clamp(0, ConnState.values.length - 1)],
    isVerified: p.isVerified,
    isPremium: p.isPremium,
    selfUserId: p.selfUserId,
  );

  static AuthStateData _authStateFromProto(epb.EngineAuthState p) => AuthStateData(
    accountId: p.accountId,
    platform: p.platform,
    state: p.state,
    options: p.options.map((o) => AuthOption(id: o.id, label: _safeStr(o.label))).toList(),
    fieldType: p.fieldType,
    label: _safeStr(p.label),
    hint: _safeStr(p.hint),
    error: _safeStr(p.error),
    codeLength: p.codeLength,
    sentTo: _safeStr(p.sentTo),
    timeoutSecs: p.timeoutSecs,
    canResend: p.canResend,
    hasRecovery: p.hasRecovery,
    qrData: p.qrData,
    qrExpiresIn: p.qrExpiresIn,
    displayName: _safeStr(p.displayName),
    avatarB64: p.avatarB64,
    message: _safeStr(p.message),
    recoverable: p.recoverable,
  );

  static ChatInfo _chatInfoFromProto(epb.EngineChatInfo p) => ChatInfo(
    accountId: p.accountId,
    chatId: p.chatId,
    type: ChatType.values[p.type.clamp(0, ChatType.values.length - 1)],
    title: _safeStr(p.title),
    avatarPath: p.avatarPath,
    lastMsgId: p.lastMsgId,
    lastMsgText: _safeStr(p.lastMsgText),
    lastMsgTime: p.lastMsgTime.toInt(),
    lastMsgSender: _safeStr(p.lastMsgSender),
    lastMsgIsOutgoing: p.lastMsgIsOutgoing,
    lastMsgStatus: MsgStatus.fromInt(p.lastMsgStatus),
    unreadCount: p.unreadCount,
    isMuted: p.isMuted,
    isPinned: p.isPinned,
    isArchived: p.isArchived,
    draftText: _safeStr(p.draftText),
    memberCount: p.memberCount,
    parentId: p.parentId,
    isBot: p.isBot,
    isContact: p.isContact,
    isBlocked: p.isBlocked,
    slowmodeSeconds: p.slowmodeSeconds,
    slowmodeNextSendDate: p.slowmodeNextSendDate.toInt(),
    starsToSend: p.starsToSend,
    ttlPeriod: p.ttlPeriod,
    emojiStatusId: p.emojiStatusId,
    isForum: p.isForum,
    writeRestrictionType: p.writeRestrictionType,
    writeRestrictionText: p.writeRestrictionText,
    notJoined: p.notJoined,
    joinRequest: p.joinRequest,
    canPost: p.canPost,
    noForwards: p.noForwards,
    isSelf: p.isSelf,
  );

  static CachedMessage _cachedMsgFromProto(epb.EngineCachedMessage p) {
    final contentRaw = p.contentRaw.isEmpty ? '' : _safeStr(utf8.decode(p.contentRaw, allowMalformed: true));
    Map<String, dynamic>? decoded;
    Map<String, dynamic>? extra;
    if (contentRaw.isNotEmpty) {
      try {
        final d = jsonDecode(contentRaw);
        if (d is Map<String, dynamic>) {
          decoded = d;
          final e = d['extra'];
          if (e is Map<String, dynamic>) extra = e;
        }
      } catch (_) {}
    }
    return CachedMessage(
      accountId: p.accountId,
      chatId: p.chatId,
      msgId: p.msgId,
      localId: p.localId,
      senderId: p.senderId,
      senderName: _safeStr(p.senderName),
      senderRank: p.senderRank,
      senderColorId: p.senderColorId,
      contentText: _safeStr(p.contentText),
      contentRaw: contentRaw,
      contentRich: p.contentRich.isEmpty ? '' : _safeStr(utf8.decode(p.contentRich, allowMalformed: true)),
      timestamp: p.timestamp.toInt(),
      editedAt: p.editedAt.toInt(),
      status: MsgStatus.values[p.status.clamp(0, MsgStatus.values.length - 1)],
      replyToId: p.replyToId,
      replyPreview: _safeStr(p.replyPreview),
      forwardFrom: _safeStr(p.forwardFrom),
      isPinned: p.isPinned,
      isOutgoing: p.isOutgoing,
      isService: p.isService,
      hasMedia: p.hasMedia,
      groupedId: p.groupedId,
      mediaType: p.mediaType,
      mediaFileName: _safeStr(p.mediaFileName),
      mediaMimeType: p.mediaMimeType,
      mediaFileSize: p.mediaFileSize.toInt(),
      mediaThumbB64: p.mediaThumbB64,
      mediaLocalPath: p.mediaLocalPath,
      mediaWidth: p.mediaWidth,
      mediaHeight: p.mediaHeight,
      mediaDuration: p.mediaDuration,
      mediaDownloadState: p.mediaDownloadState,
      mediaRemoteRef: p.mediaRemoteRef,
      mediaExtra: p.mediaExtra,
      mediaWaveform: _waveformFromParsed(extra),
      reactions: _reactionsFromParsed(decoded),
      topicId: _strFromExtra(extra, 'topic_id') ?? '',
      topicName: _strFromExtra(extra, 'topic_name') ?? '',
      topicColorId: _intFromExtra(extra, 'topic_color'),
      viaBotName: _strFromExtra(extra, 'via_bot_name') ?? '',
      mediaSpoiler: _boolFromExtra(extra, 'media_spoiler'),
      mediaUnread: _boolFromExtra(extra, 'media_unread'),
      ttlSeconds: _intFromExtra(extra, 'ttl_seconds'),
      unsupportedTTL: _boolFromExtra(extra, 'unsupported_ttl'),
      senderNoForwards: p.senderNoForwards,
      altQualities: _altQualitiesFromParsed(extra),
      views: _intFromDecoded(decoded, 'views'),
      forwards: _intFromDecoded(decoded, 'forwards'),
      stickerSetShortName: _strFromExtra(extra, 'sticker_set_short_name') ?? '',
      stickerSetId: _intFromExtra(extra, 'sticker_set_id'),
      stickerSetAccessHash: _intFromExtra(extra, 'sticker_set_access_hash'),
      stickerPremium: _boolFromExtra(extra, 'sticker_premium'),
      audioTitle: _strFromExtra(extra, 'audio_title') ?? '',
      audioPerformer: _strFromExtra(extra, 'audio_performer') ?? '',
      pollQuestion: _strFromExtra(extra, 'poll_question') ?? '',
      pollOptions: _pollOptionsFromParsed(extra),
      pollQuiz: _boolFromExtra(extra, 'poll_quiz'),
      pollMultiple: _boolFromExtra(extra, 'poll_multiple'),
      pollClosed: _boolFromExtra(extra, 'poll_closed'),
      pollPublic: _boolFromExtra(extra, 'poll_public'),
      pollTotalVoters: _intFromExtra(extra, 'poll_total_voters'),
      pollCloseDate: _intFromExtra(extra, 'poll_close_date'),
      pollClosePeriod: _intFromExtra(extra, 'poll_close_period'),
      pollRecentVoters: _strListFromExtra(extra, 'poll_recent_voters'),
      geoLat: _doubleFromExtra(extra, 'geo_lat'),
      geoLong: _doubleFromExtra(extra, 'geo_long'),
      geoLive: _boolFromExtra(extra, 'geo_live'),
      geoPeriod: _intFromExtra(extra, 'geo_period'),
      venueTitle: _strFromExtra(extra, 'venue_title') ?? '',
      venueAddress: _strFromExtra(extra, 'venue_address') ?? '',
      contactFirstName: _strFromExtra(extra, 'contact_first_name') ?? '',
      contactLastName: _strFromExtra(extra, 'contact_last_name') ?? '',
      contactPhone: _strFromExtra(extra, 'contact_phone') ?? '',
      contactUserId: _intFromExtra(extra, 'contact_user_id'),
      wpUrl: _strFromExtra(extra, 'wp_url') ?? '',
      wpSiteName: _strFromExtra(extra, 'wp_site_name') ?? '',
      wpTitle: _strFromExtra(extra, 'wp_title') ?? '',
      wpDescription: _strFromExtra(extra, 'wp_description') ?? '',
      wpType: _strFromExtra(extra, 'wp_type') ?? '',
      wpThumbB64: _strFromExtra(extra, 'wp_thumb_b64') ?? '',
      wpForceLargeMedia: _boolFromExtra(extra, 'wp_force_large_media'),
      wpForceSmallMedia: _boolFromExtra(extra, 'wp_force_small_media'),
      wpHasLargeMedia: _boolFromExtra(extra, 'wp_has_large_media'),
      wpHasIv: _boolFromExtra(extra, 'wp_has_iv'),
      wpPhotoW: _intFromExtra(extra, 'wp_photo_w'),
      wpPhotoH: _intFromExtra(extra, 'wp_photo_h'),
      wpDuration: _intFromExtra(extra, 'wp_duration'),
      gameTitle: _strFromExtra(extra, 'game_title') ?? '',
      gameDescription: _strFromExtra(extra, 'game_description') ?? '',
      gameShortName: _strFromExtra(extra, 'game_short_name') ?? '',
      gameThumbB64: _strFromExtra(extra, 'game_thumb_b64') ?? '',
      gamePhotoW: _intFromExtra(extra, 'game_photo_w'),
      gamePhotoH: _intFromExtra(extra, 'game_photo_h'),
      invoiceTitle: _strFromExtra(extra, 'invoice_title') ?? '',
      invoiceDescription: _strFromExtra(extra, 'invoice_description') ?? '',
      invoiceCurrency: _strFromExtra(extra, 'invoice_currency') ?? '',
      invoiceTotalAmount: _intFromExtra(extra, 'invoice_total_amount'),
      invoiceTest: _boolFromExtra(extra, 'invoice_test'),
      invoiceReceiptMsgId: _intFromExtra(extra, 'invoice_receipt_msg_id'),
      invoicePhotoUrl: _strFromExtra(extra, 'invoice_photo_url') ?? '',
      invoiceShippingRequested: _boolFromExtra(extra, 'invoice_shipping_requested'),
      noForwards: _boolFromExtra(extra, 'no_forwards'),
      repliesCount: _intFromExtra(extra, 'replies_count'),
      repliesChannelId: _strFromExtra(extra, 'replies_channel_id') ?? '',
      repliesIsComments: _boolFromExtra(extra, 'replies_is_comments'),
      replyKeyboard: _replyKeyboardFromParsed(extra),
      inlineKeyboard: _inlineKeyboardFromParsed(extra),
      keyboardHide: _boolFromExtra(extra, 'keyboard_hide'),
      forceReply: _boolFromExtra(extra, 'force_reply'),
      forceReplyPlaceholder: _strFromExtra(extra, 'force_reply_placeholder') ?? '',
    );
  }

  static String? _strFromExtra(Map<String, dynamic>? extra, String key) {
    if (extra == null) return null;
    final v = extra[key];
    return v is String ? v : v?.toString();
  }

  static int _intFromExtra(Map<String, dynamic>? extra, String key) {
    if (extra == null) return 0;
    final v = extra[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static int _intFromDecoded(Map<String, dynamic>? decoded, String key) {
    if (decoded == null) return 0;
    final v = decoded[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static bool _boolFromExtra(Map<String, dynamic>? extra, String key) {
    if (extra == null) return false;
    return extra[key] == true;
  }

  static double _doubleFromExtra(Map<String, dynamic>? extra, String key) {
    if (extra == null) return 0.0;
    final v = extra[key];
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return 0.0;
  }

  static List<String> _strListFromExtra(Map<String, dynamic>? extra, String key) {
    if (extra == null) return const [];
    final raw = extra[key];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  static ReplyKeyboardData? _replyKeyboardFromParsed(Map<String, dynamic>? extra) {
    if (extra == null) return null;
    final kb = extra['reply_keyboard'];
    if (kb is! Map<String, dynamic>) return null;
    return ReplyKeyboardData.fromJson(kb);
  }

  static List<List<InlineKeyboardButton>> _inlineKeyboardFromParsed(Map<String, dynamic>? extra) {
    if (extra == null) return const [];
    final kb = extra['inline_keyboard'];
    if (kb is! List) return const [];
    return kb.map((row) {
      final r = row as List<dynamic>;
      return r.map((b) => InlineKeyboardButton.fromJson(b as Map<String, dynamic>)).toList();
    }).toList();
  }

  static List<MessageReaction> _reactionsFromParsed(Map<String, dynamic>? decoded) {
    if (decoded == null) return const [];
    final raw = decoded['reactions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MessageReaction.fromJson)
        .where((r) => r.emoji.isNotEmpty)
        .toList(growable: false);
  }

  static List<int> _waveformFromParsed(Map<String, dynamic>? extra) {
    if (extra == null) return const [];
    final wfB64 = extra['waveform'];
    if (wfB64 is! String || wfB64.isEmpty) return const [];
    try {
      final bytes = base64Decode(wfB64);
      final samples = <int>[];
      for (int i = 0; i < 100; i++) {
        final bitOffset = i * 5;
        final byteIdx = bitOffset ~/ 8;
        final bitIdx = bitOffset % 8;
        if (byteIdx >= bytes.length) break;
        int val;
        if (bitIdx + 5 <= 8) {
          val = (bytes[byteIdx] >> bitIdx) & 0x1F;
        } else {
          final lo = bytes[byteIdx] >> bitIdx;
          final hi = byteIdx + 1 < bytes.length ? bytes[byteIdx + 1] : 0;
          val = (lo | (hi << (8 - bitIdx))) & 0x1F;
        }
        samples.add(val);
      }
      return samples;
    } catch (_) {
      return const [];
    }
  }

  static List<PollOption> _pollOptionsFromParsed(Map<String, dynamic>? extra) {
    if (extra == null) return const [];
    final raw = extra['poll_options'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PollOption.fromJson)
        .toList(growable: false);
  }

  static List<VideoQuality> _altQualitiesFromParsed(Map<String, dynamic>? extra) {
    if (extra == null) return const [];
    final raw = extra['alt_qualities'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map((q) => VideoQuality(
      height: (q['height'] as num?)?.toInt() ?? 0,
      width: (q['width'] as num?)?.toInt() ?? 0,
      size: (q['size'] as num?)?.toInt() ?? 0,
      seq: (q['seq'] as num?)?.toInt() ?? 0,
    )).where((q) => q.height > 0).toList(growable: false);
  }

  static MemberInfo _memberInfoFromProto(epb.EngineMemberInfo p) => MemberInfo(
    userId: p.userId,
    username: _safeStr(p.username),
    displayName: _safeStr(p.displayName),
    avatarB64: p.avatarB64,
    isBot: p.isBot,
    isOnline: p.isOnline,
    role: p.role.isNotEmpty ? p.role : 'member',
  );

  static ContactInfo _contactInfoFromProto(epb.EngineContactInfo p) => ContactInfo(
    userId: p.userId,
    username: _safeStr(p.username),
    displayName: _safeStr(p.displayName),
    phone: p.phone,
    avatarB64: p.avatarB64,
    isBot: p.isBot,
    isOnline: p.isOnline,
    storyCount: p.storyCount,
    hasUnreadStory: p.hasUnreadStory,
    isVerified: p.isVerified,
    isPremium: p.isPremium,
    isScam: p.isScam,
    isFake: p.isFake,
    lastSeenKind: _safeStr(p.lastSeenKind),
    lastSeenTs: p.lastSeenTs.toInt(),
  );

  static SearchResult _searchResultFromProto(epb.EngineSearchResult p) => SearchResult(
    accountId: p.accountId,
    chatId: p.chatId,
    msgId: p.msgId,
    senderName: _safeStr(p.senderName),
    text: _safeStr(p.text),
    timestamp: p.timestamp.toInt(),
    chatTitle: _safeStr(p.chatTitle),
  );

  static FolderInfo _folderInfoFromProto(epb.EngineFolderInfo p) => FolderInfo(
    id: p.id,
    name: _safeStr(p.name),
    chatIds: p.chatIds.toList(),
    excludeChatIds: p.excludeChatIds.toList(),
    pinnedChatIds: p.pinnedChatIds.toList(),
    contacts: p.contacts,
    nonContacts: p.nonContacts,
    groups: p.groups,
    channels: p.channels,
    bots: p.bots,
    excludeMuted: p.excludeMuted,
    excludeRead: p.excludeRead,
    excludeArchived: p.excludeArchived,
    isChatList: p.isChatList,
    emoticon: _safeStr(p.emoticon),
  );

  static SharedMediaItem _sharedMediaItemFromProto(epb.EngineSharedMediaItem p) => SharedMediaItem(
    msgId: p.msgId,
    timestamp: p.timestamp.toInt(),
    mediaType: p.mediaType,
    fileName: _safeStr(p.fileName),
    mimeType: p.mimeType,
    fileSize: p.fileSize.toInt(),
    thumbB64: p.thumbB64,
    localPath: p.localPath,
    width: p.width,
    height: p.height,
    duration: p.duration,
    waveform: p.hasWaveform() ? _decode5BitWaveform(p.waveform) : const [],
  );

  static List<int> _decode5BitWaveform(List<int> raw) {
    if (raw.isEmpty) return const [];
    final samples = <int>[];
    for (int i = 0; i < 100; i++) {
      final bitOffset = i * 5;
      final byteIdx = bitOffset ~/ 8;
      final bitIdx = bitOffset % 8;
      if (byteIdx >= raw.length) break;
      int val;
      if (bitIdx + 5 <= 8) {
        val = (raw[byteIdx] >> bitIdx) & 0x1F;
      } else {
        final lo = raw[byteIdx] >> bitIdx;
        final hi = byteIdx + 1 < raw.length ? raw[byteIdx + 1] : 0;
        val = (lo | (hi << (8 - bitIdx))) & 0x1F;
      }
      samples.add(val);
    }
    return samples;
  }

  Future<List<ConnectedBotInfo>> getConnectedBots(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    try {
      final respBytes = await _callAsync('__engine', 'GetConnectedBots', Uint8List.fromList(payload));
      final list = json.decode(utf8.decode(respBytes)) as List<dynamic>;
      return list.map((e) => ConnectedBotInfo.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      Debug.error('ENGINE', 'getConnectedBots failed', e);
      return [];
    }
  }

  Future<void> toggleConnectedBotPaused(String accountId, String chatId, {required bool paused}) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
      'paused': paused,
    }));
    await _callAsync('__engine', 'ToggleConnectedBotPaused', Uint8List.fromList(payload));
  }

  Future<void> disablePeerConnectedBot(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    await _callAsync('__engine', 'DisablePeerConnectedBot', Uint8List.fromList(payload));
  }

  Future<void> markAllChatsRead(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'MarkAllChatsRead', Uint8List.fromList(payload));
  }

  Future<void> openSavedMessages(String accountId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
    }));
    await _callAsync('__engine', 'OpenSavedMessages', Uint8List.fromList(payload));
  }

  Future<void> removeBotFromMenu(String accountId, String botId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'bot_id': botId,
    }));
    await _callAsync('__engine', 'RemoveBotFromMenu', Uint8List.fromList(payload));
  }

  Future<Map<String, dynamic>> getBoosts(String accountId, String chatId) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'chat_id': chatId,
    }));
    final resp = await _callAsync('__engine', 'GetBoosts', Uint8List.fromList(payload));
    return json.decode(utf8.decode(resp)) as Map<String, dynamic>;
  }

  // ── Notification Settings ──

  Future<bool> getContactSignUpNotification(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final resp = await _callAsync('__engine', 'GetContactSignUpNotification', Uint8List.fromList(payload));
      if (resp.isEmpty) return true;
      final decoded = json.decode(utf8.decode(resp));
      return decoded['enabled'] as bool? ?? true;
    } catch (e) {
      Debug.error('ENGINE', 'getContactSignUpNotification failed', e);
      return true;
    }
  }

  Future<void> setContactSignUpNotification(String accountId, {required bool silent}) async {
    final payload = utf8.encode(json.encode({'account_id': accountId, 'silent': silent}));
    try {
      await _callAsync('__engine', 'SetContactSignUpNotification', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'setContactSignUpNotification failed', e);
    }
  }

  Future<void> setCallsDisabledHere(String accountId, {required bool disabled}) async {
    final payload = utf8.encode(json.encode({'account_id': accountId, 'disabled': disabled}));
    try {
      await _callAsync('__engine', 'SetCallsDisabledHere', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'setCallsDisabledHere failed', e);
    }
  }

  Future<void> updateDefaultNotifySettings(String accountId, {required String peerType, required bool enabled, bool? soundEnabled}) async {
    final data = <String, dynamic>{'account_id': accountId, 'peer_type': peerType, 'enabled': enabled};
    if (soundEnabled != null) data['sound_enabled'] = soundEnabled;
    final payload = utf8.encode(json.encode(data));
    try {
      await _callAsync('__engine', 'UpdateDefaultNotifySettings', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'updateDefaultNotifySettings failed', e);
    }
  }

  Future<Map<String, dynamic>> getDefaultNotifySettings(String accountId, {required String peerType}) async {
    final payload = utf8.encode(json.encode({'account_id': accountId, 'peer_type': peerType}));
    try {
      final resp = await _callAsync('__engine', 'GetDefaultNotifySettings', Uint8List.fromList(payload));
      if (resp.isEmpty) return {};
      return json.decode(utf8.decode(resp)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'getDefaultNotifySettings failed', e);
      return {};
    }
  }

  Future<Map<String, dynamic>> getReactionsNotifySettings(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final resp = await _callAsync('__engine', 'GetReactionsNotifySettings', Uint8List.fromList(payload));
      if (resp.isEmpty) return {};
      return json.decode(utf8.decode(resp)) as Map<String, dynamic>;
    } catch (e) {
      Debug.error('ENGINE', 'getReactionsNotifySettings failed', e);
      return {};
    }
  }

  Future<void> setReactionsNotifySettings(String accountId, {
    required bool reactionsEnabled,
    required String reactionsFrom,
    required bool pollVotesEnabled,
    required String pollVotesFrom,
    required bool showSenderName,
  }) async {
    final payload = utf8.encode(json.encode({
      'account_id': accountId,
      'reactions_enabled': reactionsEnabled,
      'reactions_from': reactionsFrom,
      'poll_votes_enabled': pollVotesEnabled,
      'poll_votes_from': pollVotesFrom,
      'show_sender_name': showSenderName,
    }));
    try {
      await _callAsync('__engine', 'SetReactionsNotifySettings', Uint8List.fromList(payload));
    } catch (e) {
      Debug.error('ENGINE', 'setReactionsNotifySettings failed', e);
    }
  }

  Future<List<Map<String, dynamic>>> getSavedRingtones(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final resp = await _callAsync('__engine', 'GetSavedRingtones', Uint8List.fromList(payload));
      if (resp.isEmpty) return [];
      final decoded = json.decode(utf8.decode(resp));
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
      return [];
    } catch (e) {
      Debug.error('ENGINE', 'getSavedRingtones failed', e);
      return [];
    }
  }

  Future<Map<String, int>> getMutedChatsByType(String accountId) async {
    final payload = utf8.encode(json.encode({'account_id': accountId}));
    try {
      final resp = await _callAsync('__engine', 'GetMutedChatsByType', Uint8List.fromList(payload));
      if (resp.isEmpty) return {};
      final decoded = json.decode(utf8.decode(resp));
      if (decoded is Map) return decoded.cast<String, int>();
      return {};
    } catch (e) {
      Debug.error('ENGINE', 'getMutedChatsByType failed', e);
      return {};
    }
  }
}

class EngineException implements Exception {
  final String message;
  final String code;
  EngineException(this.message, {this.code = ''});

  @override
  String toString() => code.isNotEmpty ? 'EngineException($code): $message' : 'EngineException: $message';
}
