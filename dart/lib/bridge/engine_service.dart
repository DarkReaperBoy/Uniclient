import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'bridge.dart';
import '../models/engine_models.dart';
import '../proto/models.pb.dart' as pb;
import '../proto/engine.pb.dart' as epb;
import '../utils/debug.dart';

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
  final _chatRemovedController = StreamController<String>.broadcast();
  final _msgReceivedController = StreamController<MsgReceivedEvent>.broadcast();
  final _msgEditedController = StreamController<MsgEditedEvent>.broadcast();
  final _msgDeletedController = StreamController<MsgDeletedEvent>.broadcast();
  final _msgStatusController = StreamController<MsgStatusEvent>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  final _downloadProgressController = StreamController<DownloadProgressEvent>.broadcast();
  final _downloadCompleteController = StreamController<DownloadCompleteEvent>.broadcast();

  Stream<AuthStateEvent> get onAuthState => _authStateController.stream;
  Stream<ConnStateEvent> get onConnState => _connStateController.stream;
  Stream<List<AccountInfo>> get onAccountList => _accountListController.stream;
  Stream<ChatInfo> get onChatUpdated => _chatUpdatedController.stream;
  Stream<List<ChatInfo>> get onChatSnapshot => _chatSnapshotController.stream;
  Stream<String> get onChatRemoved => _chatRemovedController.stream;
  Stream<MsgReceivedEvent> get onMsgReceived => _msgReceivedController.stream;
  Stream<MsgEditedEvent> get onMsgEdited => _msgEditedController.stream;
  Stream<MsgDeletedEvent> get onMsgDeleted => _msgDeletedController.stream;
  Stream<MsgStatusEvent> get onMsgStatus => _msgStatusController.stream;
  Stream<TypingEvent> get onTyping => _typingController.stream;
  Stream<DownloadProgressEvent> get onDownloadProgress => _downloadProgressController.stream;
  Stream<DownloadCompleteEvent> get onDownloadComplete => _downloadCompleteController.stream;

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
    _bridge.events.listen(_handleBridgeEvent);

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

  void markChatRead(String accountId, String chatId, String upToMsgId) {
    final req = epb.EngineMarkChatReadRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..upToMsgId = upToMsgId;
    _callRaw('__engine', 'MarkChatRead', req.writeToBuffer());
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

  Future<String> sendMessage(String accountId, String chatId, String text, {String replyToId = ''}) async {
    final req = epb.EngineSendMessageRequest()
      ..accountId = accountId
      ..chatId = chatId
      ..text = text
      ..replyToId = replyToId;
    final respBytes = await _callAsync('__engine', 'SendMessage', req.writeToBuffer());
    final resp = epb.EngineSendMessageResponse.fromBuffer(respBytes);
    return resp.localId;
  }

  Future<void> editMessage(String accountId, String chatId, String msgId, String newText) async {
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

  void retryPending(String localId) {
    final req = epb.EngineRetryPendingRequest()..localId = localId;
    _callRaw('__engine', 'RetryPending', req.writeToBuffer());
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

  void updateConfig({String? theme, String? accentColor, double? fontScale, String? language, int? maxCacheSize}) {
    final req = epb.EngineUpdateConfigRequest();
    if (theme != null) req.theme = theme;
    if (accentColor != null) req.accentColor = accentColor;
    if (fontScale != null) req.fontScale = fontScale;
    if (language != null) req.language = language;
    if (maxCacheSize != null) req.maxCacheSize = Int64(maxCacheSize);
    _callRaw('__engine', 'UpdateConfig', req.writeToBuffer());
  }

  // ── Shutdown ──

  void shutdown() {
    _callRaw('__engine', 'Shutdown', Uint8List(0));
    _initialized = false;
  }

  void dispose() {
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
    } catch (_) {
      // Ignore unparseable events during development.
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
          _chatRemovedController.add(data['chat_id'] as String? ?? '');
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
    }
  }

  // ── Proto → Model converters ──

  static AccountInfo _accountInfoFromProto(epb.AccountInfo p) => AccountInfo(
    id: p.id,
    platform: p.platform,
    displayName: p.displayName,
    avatarPath: p.avatarPath,
    sortOrder: p.sortOrder,
    connState: ConnState.values[p.connState.clamp(0, ConnState.values.length - 1)],
  );

  static AuthStateData _authStateFromProto(epb.EngineAuthState p) => AuthStateData(
    accountId: p.accountId,
    platform: p.platform,
    state: p.state,
    options: p.options.map((o) => AuthOption(id: o.id, label: o.label)).toList(),
    fieldType: p.fieldType,
    label: p.label,
    hint: p.hint,
    error: p.error,
    codeLength: p.codeLength,
    sentTo: p.sentTo,
    timeoutSecs: p.timeoutSecs,
    canResend: p.canResend,
    hasRecovery: p.hasRecovery,
    qrData: p.qrData,
    displayName: p.displayName,
    avatarB64: p.avatarB64,
    message: p.message,
    recoverable: p.recoverable,
  );

  static ChatInfo _chatInfoFromProto(epb.EngineChatInfo p) => ChatInfo(
    accountId: p.accountId,
    chatId: p.chatId,
    type: ChatType.values[p.type.clamp(0, ChatType.values.length - 1)],
    title: p.title,
    avatarPath: p.avatarPath,
    lastMsgId: p.lastMsgId,
    lastMsgText: p.lastMsgText,
    lastMsgTime: p.lastMsgTime.toInt(),
    lastMsgSender: p.lastMsgSender,
    unreadCount: p.unreadCount,
    isMuted: p.isMuted,
    isPinned: p.isPinned,
    isArchived: p.isArchived,
    draftText: p.draftText,
    memberCount: p.memberCount,
    parentId: p.parentId,
  );

  static CachedMessage _cachedMsgFromProto(epb.EngineCachedMessage p) => CachedMessage(
    accountId: p.accountId,
    chatId: p.chatId,
    msgId: p.msgId,
    localId: p.localId,
    senderId: p.senderId,
    senderName: p.senderName,
    contentText: p.contentText,
    timestamp: p.timestamp.toInt(),
    editedAt: p.editedAt.toInt(),
    status: MsgStatus.values[p.status.clamp(0, MsgStatus.values.length - 1)],
    replyToId: p.replyToId,
    replyPreview: p.replyPreview,
    forwardFrom: p.forwardFrom,
    isPinned: p.isPinned,
    hasMedia: p.hasMedia,
  );

  static SearchResult _searchResultFromProto(epb.EngineSearchResult p) => SearchResult(
    accountId: p.accountId,
    chatId: p.chatId,
    msgId: p.msgId,
    senderName: p.senderName,
    text: p.text,
    timestamp: p.timestamp.toInt(),
    chatTitle: p.chatTitle,
  );
}

class EngineException implements Exception {
  final String message;
  final String code;
  EngineException(this.message, {this.code = ''});

  @override
  String toString() => code.isNotEmpty ? 'EngineException($code): $message' : 'EngineException: $message';
}
