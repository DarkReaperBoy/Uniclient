import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'bridge.dart';
import '../models/engine_models.dart';

/// High-level wrapper around the FFI bridge for engine operations.
///
/// Handles protobuf serialization, event stream parsing, and provides
/// typed Dart APIs for all engine methods.
class EngineService {
  final Bridge _bridge = Bridge();
  bool _initialized = false;

  // Event streams — engine pushes JSON events, we parse and dispatch.
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

    // Listen to bridge events and dispatch to typed streams.
    _bridge.events.listen(_handleBridgeEvent);

    // Call engine Init via the bridge.
    final result = _callEngine('Init', {
      'config_dir': configDir,
      'cache_dir': cacheDir,
      'download_dir': downloadDir,
      'vault_password': vaultPassword,
    });

    if (result != null && result['ok'] == false) {
      throw EngineException(result['error'] as String? ?? 'init failed');
    }

    _initialized = true;
  }

  // ── Account management ──

  List<AccountInfo> listAccounts() {
    final resp = _callEngine('ListAccounts', null);
    if (resp == null) return [];
    final accounts = resp['accounts'] as List<dynamic>? ?? [];
    return accounts.map((a) => AccountInfo.fromJson(a as Map<String, dynamic>)).toList();
  }

  String addAccount(String platform) {
    final resp = _callEngine('AddAccount', {'platform': platform});
    return resp?['account_id'] as String? ?? '';
  }

  void removeAccount(String accountId) {
    _callEngine('RemoveAccount', {'account_id': accountId});
  }

  void reorderAccounts(List<String> accountIds) {
    _callEngine('ReorderAccounts', {'account_ids': accountIds});
  }

  void connectAccount(String accountId) {
    _callEngine('ConnectAccount', {'account_id': accountId});
  }

  void connectAllAccounts() {
    _callEngine('ConnectAllAccounts', null);
  }

  void disconnectAccount(String accountId) {
    _callEngine('DisconnectAccount', {'account_id': accountId});
  }

  // ── Auth flow ──

  AuthStateData? startAuth(String accountId) {
    final resp = _callEngine('StartAuth', {'account_id': accountId});
    if (resp == null) return null;
    return AuthStateData.fromJson(resp);
  }

  AuthStateData? submitAuthInput(String accountId, String input) {
    final resp = _callEngine('SubmitAuthInput', {
      'account_id': accountId,
      'input': input,
    });
    if (resp == null) return null;
    final state = resp['state'] as Map<String, dynamic>?;
    return state != null ? AuthStateData.fromJson(state) : null;
  }

  void cancelAuth(String accountId) {
    _callEngine('CancelAuth', {'account_id': accountId});
  }

  // ── Chat list ──

  List<ChatInfo> getChatList({String accountId = '', bool archived = false, int limit = 50, int offset = 0}) {
    final resp = _callEngine('GetChatList', {
      'account_id': accountId,
      'archived': archived,
      'limit': limit,
      'offset': offset,
    });
    if (resp == null) return [];
    final chats = resp['chats'] as List<dynamic>? ?? [];
    return chats.map((c) => ChatInfo.fromJson(c as Map<String, dynamic>)).toList();
  }

  void saveDraft(String accountId, String chatId, String text) {
    _callEngine('SaveDraft', {'account_id': accountId, 'chat_id': chatId, 'text': text});
  }

  void muteChat(String accountId, String chatId, bool muted) {
    _callEngine('MuteChat', {'account_id': accountId, 'chat_id': chatId, 'muted': muted});
  }

  void pinChat(String accountId, String chatId, bool pinned) {
    _callEngine('PinChat', {'account_id': accountId, 'chat_id': chatId, 'pinned': pinned});
  }

  void archiveChat(String accountId, String chatId, bool archived) {
    _callEngine('ArchiveChat', {'account_id': accountId, 'chat_id': chatId, 'archived': archived});
  }

  void markChatRead(String accountId, String chatId, String upToMsgId) {
    _callEngine('MarkChatRead', {'account_id': accountId, 'chat_id': chatId, 'up_to_msg_id': upToMsgId});
  }

  // ── Messages ──

  List<CachedMessage> getMessages(String accountId, String chatId, {int beforeMs = 0, int limit = 50}) {
    final resp = _callEngine('GetMessages', {
      'account_id': accountId,
      'chat_id': chatId,
      'before_ms': beforeMs,
      'limit': limit,
    });
    if (resp == null) return [];
    final msgs = resp['messages'] as List<dynamic>? ?? [];
    return msgs.map((m) => CachedMessage.fromJson(m as Map<String, dynamic>)).toList();
  }

  String sendMessage(String accountId, String chatId, String text, {String replyToId = ''}) {
    final resp = _callEngine('SendMessage', {
      'account_id': accountId,
      'chat_id': chatId,
      'text': text,
      'reply_to_id': replyToId,
    });
    return resp?['local_id'] as String? ?? '';
  }

  void editMessage(String accountId, String chatId, String msgId, String newText) {
    _callEngine('EditMessage', {'account_id': accountId, 'chat_id': chatId, 'msg_id': msgId, 'new_text': newText});
  }

  void deleteMessage(String accountId, String chatId, String msgId) {
    _callEngine('DeleteMessage', {'account_id': accountId, 'chat_id': chatId, 'msg_id': msgId});
  }

  void retryPending(String localId) {
    _callEngine('RetryPending', {'local_id': localId});
  }

  // ── Active chat ──

  void setActiveChat(String accountId, String chatId) {
    _callEngine('SetActiveChat', {'account_id': accountId, 'chat_id': chatId});
  }

  void clearActiveChat() {
    _callEngine('ClearActiveChat', null);
  }

  // ── Search ──

  List<SearchResult> searchMessages(String query, {String accountId = '', int limit = 50}) {
    final resp = _callEngine('SearchMessages', {'query': query, 'account_id': accountId, 'limit': limit});
    if (resp == null) return [];
    final results = resp['results'] as List<dynamic>? ?? [];
    return results.map((r) => SearchResult.fromJson(r as Map<String, dynamic>)).toList();
  }

  List<ChatInfo> searchChats(String query, {int limit = 20}) {
    final resp = _callEngine('SearchChats', {'query': query, 'limit': limit});
    if (resp == null) return [];
    final chats = resp['chats'] as List<dynamic>? ?? [];
    return chats.map((c) => ChatInfo.fromJson(c as Map<String, dynamic>)).toList();
  }

  // ── Media ──

  void requestDownload(String accountId, String chatId, String msgId, {int seq = 0, int priority = 2}) {
    _callEngine('RequestDownload', {
      'account_id': accountId, 'chat_id': chatId, 'msg_id': msgId,
      'seq': seq, 'priority': priority,
    });
  }

  void cancelDownload(String accountId, String chatId, String msgId, {int seq = 0}) {
    _callEngine('CancelDownload', {
      'account_id': accountId, 'chat_id': chatId, 'msg_id': msgId, 'seq': seq,
    });
  }

  int getCacheSize() {
    final resp = _callEngine('GetCacheSize', null);
    return resp?['size_bytes'] as int? ?? 0;
  }

  void clearCache({String accountId = ''}) {
    _callEngine('ClearCache', {'account_id': accountId});
  }

  // ── Config ──

  AppConfig getConfig() {
    final resp = _callEngine('GetConfig', null);
    if (resp == null) return AppConfig.defaults();
    return AppConfig.fromJson(resp);
  }

  void updateConfig({String? theme, String? accentColor, double? fontScale, String? language, int? maxCacheSize}) {
    _callEngine('UpdateConfig', {
      if (theme != null) 'theme': theme,
      if (accentColor != null) 'accent_color': accentColor,
      if (fontScale != null) 'font_scale': fontScale,
      if (language != null) 'language': language,
      if (maxCacheSize != null) 'max_cache_size': maxCacheSize,
    });
  }

  // ── Shutdown ──

  void shutdown() {
    _callEngine('Shutdown', null);
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

  /// Call an engine method via the bridge. Returns decoded JSON response payload,
  /// or null on error.
  Map<String, dynamic>? _callEngine(String method, Map<String, dynamic>? params) {
    // For now, engine calls use JSON encoding through the bridge.
    // TODO: Switch to protobuf once Dart proto codegen is wired.
    final request = {
      'core_id': '__engine',
      'method': method,
      if (params != null) 'payload': params,
    };

    final reqBytes = Uint8List.fromList(utf8.encode(json.encode(request)));
    final respBytes = _bridge.call(reqBytes);
    if (respBytes.isEmpty) return null;

    final resp = json.decode(utf8.decode(respBytes)) as Map<String, dynamic>;
    if (resp['ok'] != true) {
      final error = resp['error'] as String? ?? 'unknown error';
      final code = resp['error_code'] as String? ?? '';
      throw EngineException(error, code: code);
    }
    return resp['payload'] as Map<String, dynamic>?;
  }

  /// Handle raw BridgeEvent bytes from Go.
  void _handleBridgeEvent(Uint8List bytes) {
    // Engine events come as JSON in the engine_event field of BridgeEvent.
    // For now, we parse the entire blob as JSON since the bridge currently
    // sends JSON-encoded EngineEvents for __engine core_id.
    try {
      final event = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
      final coreId = event['core_id'] as String?;

      if (coreId == '__engine') {
        final engineEventBytes = event['engine_event'];
        if (engineEventBytes != null) {
          final engineEvent = json.decode(
            engineEventBytes is String ? engineEventBytes : utf8.decode(engineEventBytes as List<int>),
          ) as Map<String, dynamic>;
          _dispatchEngineEvent(engineEvent);
        }
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
}

class EngineException implements Exception {
  final String message;
  final String code;
  EngineException(this.message, {this.code = ''});

  @override
  String toString() => code.isNotEmpty ? 'EngineException($code): $message' : 'EngineException: $message';
}
