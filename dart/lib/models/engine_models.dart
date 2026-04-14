/// Dart model classes mirroring the Go engine types.
///
/// These are used by the EngineService for typed event dispatch and API responses.
library;

// ── Chat types ──
enum ChatType {
  unspec,
  dm,
  group,
  channel,
  topic;

  static ChatType fromInt(int v) => switch (v) {
    1 => dm,
    2 => group,
    3 => channel,
    4 => topic,
    _ => unspec,
  };
}

// ── Message status ──
enum MsgStatus {
  unknown,
  sending,
  sent,
  delivered,
  read,
  failed;

  static MsgStatus fromInt(int v) => switch (v) {
    1 => sending,
    2 => sent,
    3 => delivered,
    4 => read,
    5 => failed,
    _ => unknown,
  };
}

// ── Connection state ──
enum ConnState {
  disconnected,
  connecting,
  connected,
  unstable,
  authRequired;

  static ConnState fromString(String s) => switch (s) {
    'connecting' => connecting,
    'connected' => connected,
    'unstable' => unstable,
    'auth_required' => authRequired,
    _ => disconnected,
  };
}

// ── Account ──
class AccountInfo {
  final String id;
  final String platform;
  final String displayName;
  final String avatarPath;
  final int sortOrder;
  final ConnState connState;

  const AccountInfo({
    required this.id,
    required this.platform,
    this.displayName = '',
    this.avatarPath = '',
    this.sortOrder = 0,
    this.connState = ConnState.disconnected,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
    id: j['id'] as String? ?? '',
    platform: j['platform'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    avatarPath: j['avatar_path'] as String? ?? '',
    sortOrder: j['sort_order'] as int? ?? 0,
    connState: ConnState.values[(j['conn_state'] as int? ?? 0).clamp(0, ConnState.values.length - 1)],
  );
}

// ── Auth state ──
class AuthStateData {
  final String accountId;
  final String platform;
  final String state; // choose, input, otp, 2fa, qr, ready, error
  final String fieldType;
  final String label;
  final String hint;
  final String error;
  final int codeLength;
  final String sentTo;
  final int timeoutSecs;
  final bool canResend;
  final bool hasRecovery;
  final List<int> qrData;
  final String displayName;
  final String avatarB64;
  final String message;
  final bool recoverable;
  final List<AuthOption> options;

  const AuthStateData({
    this.accountId = '',
    this.platform = '',
    this.state = '',
    this.fieldType = '',
    this.label = '',
    this.hint = '',
    this.error = '',
    this.codeLength = 0,
    this.sentTo = '',
    this.timeoutSecs = 0,
    this.canResend = false,
    this.hasRecovery = false,
    this.qrData = const [],
    this.displayName = '',
    this.avatarB64 = '',
    this.message = '',
    this.recoverable = false,
    this.options = const [],
  });

  factory AuthStateData.fromJson(Map<String, dynamic> j) => AuthStateData(
    accountId: j['account_id'] as String? ?? '',
    platform: j['platform'] as String? ?? '',
    state: j['state'] as String? ?? '',
    fieldType: j['field_type'] as String? ?? '',
    label: j['label'] as String? ?? '',
    hint: j['hint'] as String? ?? '',
    error: j['error'] as String? ?? '',
    codeLength: j['code_length'] as int? ?? 0,
    sentTo: j['sent_to'] as String? ?? '',
    timeoutSecs: j['timeout_secs'] as int? ?? 0,
    canResend: j['can_resend'] as bool? ?? false,
    hasRecovery: j['has_recovery'] as bool? ?? false,
    displayName: j['display_name'] as String? ?? '',
    message: j['message'] as String? ?? '',
    recoverable: j['recoverable'] as bool? ?? false,
    options: (j['options'] as List<dynamic>?)
        ?.map((o) => AuthOption.fromJson(o as Map<String, dynamic>))
        .toList() ?? [],
  );
}

class AuthOption {
  final String id;
  final String label;
  const AuthOption({required this.id, required this.label});

  factory AuthOption.fromJson(Map<String, dynamic> j) => AuthOption(
    id: j['id'] as String? ?? '',
    label: j['label'] as String? ?? '',
  );
}

// ── Chat info ──
class ChatInfo {
  final String accountId;
  final String chatId;
  final ChatType type;
  final String title;
  final String avatarPath;
  final String lastMsgId;
  final String lastMsgText;
  final int lastMsgTime;
  final String lastMsgSender;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final bool isArchived;
  final String draftText;
  final int memberCount;
  final String parentId;

  const ChatInfo({
    required this.accountId,
    required this.chatId,
    this.type = ChatType.unspec,
    this.title = '',
    this.avatarPath = '',
    this.lastMsgId = '',
    this.lastMsgText = '',
    this.lastMsgTime = 0,
    this.lastMsgSender = '',
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.isArchived = false,
    this.draftText = '',
    this.memberCount = 0,
    this.parentId = '',
  });

  factory ChatInfo.fromJson(Map<String, dynamic> j) => ChatInfo(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    type: ChatType.fromInt(j['type'] as int? ?? 0),
    title: j['title'] as String? ?? '',
    avatarPath: j['avatar_path'] as String? ?? '',
    lastMsgId: j['last_msg_id'] as String? ?? '',
    lastMsgText: j['last_msg_text'] as String? ?? '',
    lastMsgTime: j['last_msg_time'] as int? ?? 0,
    lastMsgSender: j['last_msg_sender'] as String? ?? '',
    unreadCount: j['unread_count'] as int? ?? 0,
    isMuted: j['is_muted'] as bool? ?? false,
    isPinned: j['is_pinned'] as bool? ?? false,
    isArchived: j['is_archived'] as bool? ?? false,
    draftText: j['draft_text'] as String? ?? '',
    memberCount: j['member_count'] as int? ?? 0,
    parentId: j['parent_id'] as String? ?? '',
  );

  /// Time as DateTime for display.
  DateTime get lastMsgDateTime => DateTime.fromMillisecondsSinceEpoch(lastMsgTime);
}

// ── Cached message ──
class CachedMessage {
  final String accountId;
  final String chatId;
  final String msgId;
  final String localId;
  final String senderId;
  final String senderName;
  final String contentText;
  final int timestamp;
  final int editedAt;
  final MsgStatus status;
  final String replyToId;
  final String replyPreview;
  final String forwardFrom;
  final bool isPinned;
  final bool hasMedia;

  const CachedMessage({
    required this.accountId,
    required this.chatId,
    required this.msgId,
    this.localId = '',
    this.senderId = '',
    this.senderName = '',
    this.contentText = '',
    this.timestamp = 0,
    this.editedAt = 0,
    this.status = MsgStatus.unknown,
    this.replyToId = '',
    this.replyPreview = '',
    this.forwardFrom = '',
    this.isPinned = false,
    this.hasMedia = false,
  });

  factory CachedMessage.fromJson(Map<String, dynamic> j) => CachedMessage(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    localId: j['local_id'] as String? ?? '',
    senderId: j['sender_id'] as String? ?? '',
    senderName: j['sender_name'] as String? ?? '',
    contentText: j['content_text'] as String? ?? '',
    timestamp: j['timestamp'] as int? ?? 0,
    editedAt: j['edited_at'] as int? ?? 0,
    status: MsgStatus.fromInt(j['status'] as int? ?? 0),
    replyToId: j['reply_to_id'] as String? ?? '',
    replyPreview: j['reply_preview'] as String? ?? '',
    forwardFrom: j['forward_from'] as String? ?? '',
    isPinned: j['is_pinned'] as bool? ?? false,
    hasMedia: j['has_media'] as bool? ?? false,
  );

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
  bool get isEdited => editedAt > 0;
  bool get isSending => status == MsgStatus.sending;
  bool get isFailed => status == MsgStatus.failed;
}

// ── Search result ──
class SearchResult {
  final String accountId;
  final String chatId;
  final String msgId;
  final String senderName;
  final String text;
  final int timestamp;
  final String chatTitle;

  const SearchResult({
    required this.accountId,
    required this.chatId,
    required this.msgId,
    this.senderName = '',
    this.text = '',
    this.timestamp = 0,
    this.chatTitle = '',
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    senderName: j['sender_name'] as String? ?? '',
    text: j['text'] as String? ?? '',
    timestamp: j['timestamp'] as int? ?? 0,
    chatTitle: j['chat_title'] as String? ?? '',
  );
}

// ── App config ──
class AppConfig {
  final String theme;
  final String accentColor;
  final double fontScale;
  final String language;
  final String downloadDir;
  final int maxCacheSize;
  final bool sendReadReceipts;
  final bool sendTyping;
  final bool notifyDms;
  final bool notifyGroups;
  final bool notifyMentionsOnly;

  const AppConfig({
    this.theme = 'dark',
    this.accentColor = '#4f6ef7',
    this.fontScale = 1.0,
    this.language = 'en',
    this.downloadDir = '',
    this.maxCacheSize = 1073741824,
    this.sendReadReceipts = true,
    this.sendTyping = true,
    this.notifyDms = true,
    this.notifyGroups = true,
    this.notifyMentionsOnly = false,
  });

  factory AppConfig.defaults() => const AppConfig();

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
    theme: j['theme'] as String? ?? 'dark',
    accentColor: j['accent_color'] as String? ?? '#4f6ef7',
    fontScale: (j['font_scale'] as num?)?.toDouble() ?? 1.0,
    language: j['language'] as String? ?? 'en',
    downloadDir: j['download_dir'] as String? ?? '',
    maxCacheSize: j['max_cache_size'] as int? ?? 1073741824,
    sendReadReceipts: j['send_read_receipts'] as bool? ?? true,
    sendTyping: j['send_typing'] as bool? ?? true,
    notifyDms: j['notify_dms'] as bool? ?? true,
    notifyGroups: j['notify_groups'] as bool? ?? true,
    notifyMentionsOnly: j['notify_mentions_only'] as bool? ?? false,
  );
}

// ── Event types ──

class AuthStateEvent {
  final String accountId;
  final String state;
  final String prompt;
  final String error;
  const AuthStateEvent({this.accountId = '', this.state = '', this.prompt = '', this.error = ''});
}

class ConnStateEvent {
  final String accountId;
  final String state;
  final String error;
  const ConnStateEvent({this.accountId = '', this.state = '', this.error = ''});
}

class MsgReceivedEvent {
  final String accountId;
  final String chatId;
  final CachedMessage message;
  const MsgReceivedEvent({required this.accountId, required this.chatId, required this.message});

  factory MsgReceivedEvent.fromJson(Map<String, dynamic> j) => MsgReceivedEvent(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    message: CachedMessage.fromJson(j['message'] as Map<String, dynamic>? ?? {}),
  );
}

class MsgEditedEvent {
  final String accountId;
  final String chatId;
  final String msgId;
  final String newText;
  final int editedAt;
  const MsgEditedEvent({this.accountId = '', this.chatId = '', this.msgId = '', this.newText = '', this.editedAt = 0});

  factory MsgEditedEvent.fromJson(Map<String, dynamic> j) => MsgEditedEvent(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    newText: j['new_text'] as String? ?? '',
    editedAt: j['edited_at'] as int? ?? 0,
  );
}

class MsgDeletedEvent {
  final String accountId;
  final String chatId;
  final String msgId;
  const MsgDeletedEvent({this.accountId = '', this.chatId = '', this.msgId = ''});

  factory MsgDeletedEvent.fromJson(Map<String, dynamic> j) => MsgDeletedEvent(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
  );
}

class MsgStatusEvent {
  final String accountId;
  final String chatId;
  final String msgId;
  final String localId;
  final int status;
  const MsgStatusEvent({this.accountId = '', this.chatId = '', this.msgId = '', this.localId = '', this.status = 0});

  factory MsgStatusEvent.fromJson(Map<String, dynamic> j) => MsgStatusEvent(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    localId: j['local_id'] as String? ?? '',
    status: j['status'] as int? ?? 0,
  );
}

class TypingEvent {
  final String chatId;
  final String userId;
  final String userName;
  const TypingEvent({this.chatId = '', this.userId = '', this.userName = ''});

  factory TypingEvent.fromJson(Map<String, dynamic> j) => TypingEvent(
    chatId: j['chat_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    userName: j['user_name'] as String? ?? '',
  );
}

class DownloadProgressEvent {
  final String accountId;
  final String chatId;
  final String msgId;
  final int seq;
  final int bytesRecv;
  final int bytesTotal;
  const DownloadProgressEvent({
    this.accountId = '', this.chatId = '', this.msgId = '',
    this.seq = 0, this.bytesRecv = 0, this.bytesTotal = 0,
  });

  factory DownloadProgressEvent.fromJson(Map<String, dynamic> j) => DownloadProgressEvent(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    seq: j['seq'] as int? ?? 0,
    bytesRecv: j['bytes_recv'] as int? ?? 0,
    bytesTotal: j['bytes_total'] as int? ?? 0,
  );

  double get progress => bytesTotal > 0 ? bytesRecv / bytesTotal : 0;
}

class DownloadCompleteEvent {
  final String accountId;
  final String chatId;
  final String msgId;
  final int seq;
  final String localPath;
  const DownloadCompleteEvent({
    this.accountId = '', this.chatId = '', this.msgId = '',
    this.seq = 0, this.localPath = '',
  });

  factory DownloadCompleteEvent.fromJson(Map<String, dynamic> j) => DownloadCompleteEvent(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    seq: j['seq'] as int? ?? 0,
    localPath: j['local_path'] as String? ?? '',
  );
}
