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
  final _groupCallStateController = StreamController<GroupCallStateEvent>.broadcast();
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
  Stream<GroupCallStateEvent> get onGroupCallState => _groupCallStateController.stream;

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

  void saveDraft(String accountId, String chatId, String text) {
    final req = epb.EngineSaveDraftRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..text = text;
    _callRaw('__engine', 'SaveDraft', req.writeToBuffer());
  }

  void muteChat(String accountId, String chatId, bool muted) {
    final req = epb.EngineMuteChatRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..muted = muted;
    _callRaw('__engine', 'MuteChat', req.writeToBuffer());
  }

  void pinChat(String accountId, String chatId, bool pinned) {
    final req = epb.EnginePinChatRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..pinned = pinned;
    _callRaw('__engine', 'PinChat', req.writeToBuffer());
  }

  void archiveChat(String accountId, String chatId, bool archived) {
    final req = epb.EngineArchiveChatRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..archived = archived;
    _callRaw('__engine', 'ArchiveChat', req.writeToBuffer());
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

  Future<void> addContact(String accountId, String phone, String firstName, String lastName) async {
    final req = epb.EngineAddContactRequest()
      ..accountId = accountId
      ..phone = phone
      ..firstName = firstName
      ..lastName = lastName;
    await _callAsync('__engine', 'AddContact', req.writeToBuffer());
  }

  void markChatRead(String accountId, String chatId, String upToMsgId) {
    final req = epb.EngineMarkChatReadRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..upToMsgId = upToMsgId;
    _callRaw('__engine', 'MarkChatRead', req.writeToBuffer());
  }

  /// Fetch forum topics for a chat. Returns empty list if the platform
  /// doesn't support forum topics. Topics are cached in the engine DB.
  Future<List<ChatInfo>> getForumTopics(String accountId, String chatId) async {
    final req = epb.EngineGetForumTopicsRequest()
      ..accountId = accountId
      ..chatId = chatId;
    final respBytes = await _callAsync('__engine', 'GetForumTopics', req.writeToBuffer());
    if (respBytes.isEmpty) return [];
    final resp = epb.EngineGetForumTopicsResponse.fromBuffer(respBytes);
    return resp.chats.map(_chatInfoFromProto).toList();
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

  /// Delete a folder by its ID. The underlying core handles the platform-
  /// specific API call (Telegram uses filter ID, Bale/Rubika use their IDs).
  Future<void> deleteFolder(String accountId, String folderId) async {
    final req = epb.EngineDeleteFolderRequest()
      ..accountId = accountId
      ..folderId = folderId;
    await _callAsync('__engine', 'DeleteFolder', req.writeToBuffer());
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
      if (resp.title.isEmpty && resp.description.isEmpty && resp.siteName.isEmpty) return null;
      return WebPagePreview(
        url: resp.url,
        siteName: resp.siteName,
        title: resp.title,
        description: resp.description,
        thumbB64: resp.thumbB64,
      );
    } catch (_) {
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
        count: resp.count,
        installed: resp.installed,
        archived: resp.archived,
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

  Future<String> sendMessage(String accountId, String chatId, String text, {String replyToId = '', String entities = '', bool silent = false}) async {
    final req = epb.EngineSendMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..text = text
      ..replyToId = replyToId
      ..silent = silent;
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

  Future<void> leaveChat(String accountId, String chatId) async {
    final req = epb.EngineLeaveChatRequest()
      ..accountId = accountId
      ..chatId = chatId;
    await _callAsync('__engine', 'LeaveChat', req.writeToBuffer());
  }

  Future<void> clearHistory(String accountId, String chatId) async {
    final req = epb.EngineLeaveChatRequest()
      ..accountId = accountId
      ..chatId = chatId;
    await _callAsync('__engine', 'ClearHistory', req.writeToBuffer());
  }

  Future<void> deleteChat(String accountId, String chatId) async {
    final req = epb.EngineLeaveChatRequest()
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

  Future<void> forwardMessage(String accountId, String chatId, String msgId, String toChatId) async {
    final req = epb.EngineForwardMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..toChatId = toChatId;
    await _callAsync('__engine', 'ForwardMessage', req.writeToBuffer());
  }

  Future<void> sendScheduledNow(String accountId, String chatId, List<String> msgIds) async {
    final req = epb.EngineSendScheduledNowRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgIds.addAll(msgIds);
    await _callAsync('__engine', 'SendScheduledNow', req.writeToBuffer());
  }

  Future<void> reactToMessage(String accountId, String chatId, String msgId, String emoji) async {
    final req = epb.EngineReactToMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..emoji = emoji;
    await _callAsync('__engine', 'ReactToMessage', req.writeToBuffer());
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

  Future<void> pinMessage(String accountId, String chatId, String msgId, bool pinned) async {
    final req = epb.EnginePinMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..msgId = msgId
      ..pinned = pinned;
    await _callAsync('__engine', 'PinMessage', req.writeToBuffer());
  }

  Future<String> uploadFile(String accountId, String chatId, String filePath, {String caption = ''}) async {
    final req = epb.EngineUploadFileRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..filePath = filePath
      ..caption = caption;
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

  void updateConfig({
    String? theme,
    String? accentColor,
    double? fontScale,
    String? language,
    String? downloadDir,
    int? maxCacheSize,
    bool? sendReadReceipts,
    bool? sendTyping,
    bool? notifyDms,
    bool? notifyGroups,
    bool? notifyMentionsOnly,
  }) {
    final req = epb.EngineUpdateConfigRequest();
    if (theme != null) req.theme = theme;
    if (accentColor != null) req.accentColor = accentColor;
    if (fontScale != null) req.fontScale = fontScale;
    if (language != null) req.language = language;
    // downloadDir not yet in EngineUpdateConfigRequest proto — stored locally only.
    if (maxCacheSize != null) req.maxCacheSize = Int64(maxCacheSize);
    if (sendReadReceipts != null) {
      req.sendReadReceipts = sendReadReceipts;
      req.hasSendReadReceipts_7 = true;
    }
    if (sendTyping != null) {
      req.sendTyping = sendTyping;
      req.hasSendTyping_9 = true;
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

      case 'group_call_state':
        if (data is Map<String, dynamic>) {
          _groupCallStateController.add(GroupCallStateEvent(
            accountId: event['account_id'] as String? ?? '',
            info: GroupCallInfo.fromJson(data),
          ));
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
  );

  static CachedMessage _cachedMsgFromProto(epb.EngineCachedMessage p) {
    final contentRaw = p.contentRaw.isEmpty ? '' : _safeStr(utf8.decode(p.contentRaw, allowMalformed: true));
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
      mediaWaveform: _waveformFromRaw(contentRaw),
      reactions: _reactionsFromRaw(contentRaw),
      topicId: _topicFieldFromRaw(contentRaw, 'topic_id') ?? '',
      topicName: _topicFieldFromRaw(contentRaw, 'topic_name') ?? '',
      topicColorId: _topicColorFromRaw(contentRaw),
      viaBotName: _topicFieldFromRaw(contentRaw, 'via_bot_name') ?? '',
      mediaSpoiler: _boolExtraFromRaw(contentRaw, 'media_spoiler'),
      views: _intFieldFromRaw(contentRaw, 'views'),
      forwards: _intFieldFromRaw(contentRaw, 'forwards'),
      stickerSetShortName: _topicFieldFromRaw(contentRaw, 'sticker_set_short_name') ?? '',
      stickerSetId: _int64FieldFromRaw(contentRaw, 'sticker_set_id'),
      stickerSetAccessHash: _int64FieldFromRaw(contentRaw, 'sticker_set_access_hash'),
      stickerPremium: _boolExtraFromRaw(contentRaw, 'sticker_premium'),
      audioTitle: _topicFieldFromRaw(contentRaw, 'audio_title') ?? '',
      audioPerformer: _topicFieldFromRaw(contentRaw, 'audio_performer') ?? '',
      pollQuestion: _topicFieldFromRaw(contentRaw, 'poll_question') ?? '',
      pollOptions: _pollOptionsFromRaw(contentRaw),
      pollQuiz: _boolExtraFromRaw(contentRaw, 'poll_quiz'),
      pollMultiple: _boolExtraFromRaw(contentRaw, 'poll_multiple'),
      pollClosed: _boolExtraFromRaw(contentRaw, 'poll_closed'),
      pollPublic: _boolExtraFromRaw(contentRaw, 'poll_public'),
      pollTotalVoters: _int64FieldFromRaw(contentRaw, 'poll_total_voters'),
      pollCloseDate: _int64FieldFromRaw(contentRaw, 'poll_close_date'),
      pollClosePeriod: _int64FieldFromRaw(contentRaw, 'poll_close_period'),
      pollRecentVoters: _stringListExtraFromRaw(contentRaw, 'poll_recent_voters'),
      geoLat: _doubleExtraFromRaw(contentRaw, 'geo_lat'),
      geoLong: _doubleExtraFromRaw(contentRaw, 'geo_long'),
      geoLive: _boolExtraFromRaw(contentRaw, 'geo_live'),
      geoPeriod: _int64FieldFromRaw(contentRaw, 'geo_period'),
      venueTitle: _topicFieldFromRaw(contentRaw, 'venue_title') ?? '',
      venueAddress: _topicFieldFromRaw(contentRaw, 'venue_address') ?? '',
      contactFirstName: _topicFieldFromRaw(contentRaw, 'contact_first_name') ?? '',
      contactLastName: _topicFieldFromRaw(contentRaw, 'contact_last_name') ?? '',
      contactPhone: _topicFieldFromRaw(contentRaw, 'contact_phone') ?? '',
      contactUserId: _int64FieldFromRaw(contentRaw, 'contact_user_id'),
      wpUrl: _topicFieldFromRaw(contentRaw, 'wp_url') ?? '',
      wpSiteName: _topicFieldFromRaw(contentRaw, 'wp_site_name') ?? '',
      wpTitle: _topicFieldFromRaw(contentRaw, 'wp_title') ?? '',
      wpDescription: _topicFieldFromRaw(contentRaw, 'wp_description') ?? '',
      wpType: _topicFieldFromRaw(contentRaw, 'wp_type') ?? '',
      wpThumbB64: _topicFieldFromRaw(contentRaw, 'wp_thumb_b64') ?? '',
      wpForceLargeMedia: _boolExtraFromRaw(contentRaw, 'wp_force_large_media'),
      wpForceSmallMedia: _boolExtraFromRaw(contentRaw, 'wp_force_small_media'),
      wpHasLargeMedia: _boolExtraFromRaw(contentRaw, 'wp_has_large_media'),
      wpPhotoW: _int64FieldFromRaw(contentRaw, 'wp_photo_w'),
      wpPhotoH: _int64FieldFromRaw(contentRaw, 'wp_photo_h'),
      wpDuration: _int64FieldFromRaw(contentRaw, 'wp_duration'),
      replyKeyboard: _replyKeyboardFromRaw(contentRaw),
      inlineKeyboard: _inlineKeyboardFromRaw(contentRaw),
      keyboardHide: _boolExtraFromRaw(contentRaw, 'keyboard_hide'),
      forceReply: _boolExtraFromRaw(contentRaw, 'force_reply'),
      forceReplyPlaceholder: _topicFieldFromRaw(contentRaw, 'force_reply_placeholder') ?? '',
    );
  }

  static ReplyKeyboardData? _replyKeyboardFromRaw(String contentRaw) {
    if (contentRaw.isEmpty || !contentRaw.contains('"reply_keyboard"')) return null;
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return null;
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return null;
      final kb = extra['reply_keyboard'];
      if (kb is! Map<String, dynamic>) return null;
      return ReplyKeyboardData.fromJson(kb);
    } catch (_) {
      return null;
    }
  }

  static List<List<InlineKeyboardButton>> _inlineKeyboardFromRaw(String contentRaw) {
    if (contentRaw.isEmpty || !contentRaw.contains('"inline_keyboard"')) return const [];
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return const [];
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return const [];
      final kb = extra['inline_keyboard'];
      if (kb is! List) return const [];
      return kb.map((row) {
        final r = row as List<dynamic>;
        return r.map((b) => InlineKeyboardButton.fromJson(b as Map<String, dynamic>)).toList();
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Parse reactions list from the raw JSON blob written by the Go engine
  /// (`json.Marshal(*cores.Message)`). The engine doesn't expose reactions as
  /// a first-class proto field, so we peek into `contentRaw` to recover them.
  static List<MessageReaction> _reactionsFromRaw(String contentRaw) {
    if (contentRaw.isEmpty || !contentRaw.contains('"reactions"')) return const [];
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return const [];
      final raw = decoded['reactions'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(MessageReaction.fromJson)
          .where((r) => r.emoji.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Extract a string field from the "extra" map inside contentRaw JSON.
  static String? _topicFieldFromRaw(String contentRaw, String key) {
    if (contentRaw.isEmpty || !contentRaw.contains('"extra"')) return null;
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return null;
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return null;
      final v = extra[key];
      return v is String ? v : v?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Extract topic_color (int) from the "extra" map inside contentRaw JSON.
  static int _topicColorFromRaw(String contentRaw) {
    if (contentRaw.isEmpty || !contentRaw.contains('"topic_color"')) return 0;
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return 0;
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return 0;
      final v = extra['topic_color'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static List<int> _waveformFromRaw(String contentRaw) {
    if (contentRaw.isEmpty || !contentRaw.contains('"waveform"')) return const [];
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return const [];
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return const [];
      final wfB64 = extra['waveform'];
      if (wfB64 is! String || wfB64.isEmpty) return const [];
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

  static bool _boolExtraFromRaw(String contentRaw, String key) {
    if (contentRaw.isEmpty || !contentRaw.contains('"$key"')) return false;
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return false;
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return false;
      return extra[key] == true;
    } catch (_) {
      return false;
    }
  }

  /// Extract a top-level int field from contentRaw JSON (e.g. "views", "forwards").
  static int _intFieldFromRaw(String contentRaw, String key) {
    if (contentRaw.isEmpty || !contentRaw.contains('"$key"')) return 0;
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return 0;
      final v = decoded[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static int _int64FieldFromRaw(String contentRaw, String key) {
    if (contentRaw.isEmpty || !contentRaw.contains('"$key"')) return 0;
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return 0;
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return 0;
      final v = extra[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static double _doubleExtraFromRaw(String contentRaw, String key) {
    if (contentRaw.isEmpty || !contentRaw.contains('"$key"')) return 0.0;
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return 0.0;
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return 0.0;
      final v = extra[key];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  static List<String> _stringListExtraFromRaw(String contentRaw, String key) {
    if (contentRaw.isEmpty || !contentRaw.contains('"$key"')) return const [];
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return const [];
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return const [];
      final raw = extra[key];
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<PollOption> _pollOptionsFromRaw(String contentRaw) {
    if (contentRaw.isEmpty || !contentRaw.contains('"poll_options"')) return const [];
    try {
      final decoded = jsonDecode(contentRaw);
      if (decoded is! Map<String, dynamic>) return const [];
      final extra = decoded['extra'];
      if (extra is! Map<String, dynamic>) return const [];
      final raw = extra['poll_options'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(PollOption.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
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
  );
}

class EngineException implements Exception {
  final String message;
  final String code;
  EngineException(this.message, {this.code = ''});

  @override
  String toString() => code.isNotEmpty ? 'EngineException($code): $message' : 'EngineException: $message';
}
