/// Dart model classes mirroring the Go engine types.
///
/// These are used by the EngineService for typed event dispatch and API responses.
library;

import '../utils/safe_string.dart';

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
  unstable;

  static ConnState fromString(String s) => switch (s) {
    'connecting' => connecting,
    'connected' => connected,
    'unstable' => unstable,
    _ => disconnected,
  };
}

// ── Account ──
class AccountInfo {
  final String id;
  final String platform;
  final String displayName;
  final String phone;
  final String username;
  final String avatarPath;
  final int sortOrder;
  final ConnState connState;
  final bool isVerified;
  final bool isPremium;

  const AccountInfo({
    required this.id,
    required this.platform,
    this.displayName = '',
    this.phone = '',
    this.username = '',
    this.avatarPath = '',
    this.sortOrder = 0,
    this.connState = ConnState.disconnected,
    this.isVerified = false,
    this.isPremium = false,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
    id: j['id'] as String? ?? '',
    platform: j['platform'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    username: j['username'] as String? ?? '',
    avatarPath: j['avatar_path'] as String? ?? '',
    sortOrder: j['sort_order'] as int? ?? 0,
    connState: ConnState.values[(j['conn_state'] as int? ?? 0).clamp(0, ConnState.values.length - 1)],
    isVerified: j['is_verified'] as bool? ?? false,
    isPremium: j['is_premium'] as bool? ?? false,
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
  final int qrExpiresIn;
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
    this.qrExpiresIn = 0,
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
  final bool lastMsgIsOutgoing;
  final MsgStatus lastMsgStatus;
  final int lastMsgMediaType;
  final String lastMsgThumbB64;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final bool isArchived;
  final String draftText;
  final int memberCount;
  final String parentId;
  final String parentTitle;
  final int storyCount;
  final bool hasUnreadStory;
  final bool isLiveStream;
  final bool isBot;
  final bool isUnreadMark;
  final int unreadMentionCount;
  final int unreadReactionCount;
  final bool isContact;
  final bool isBlocked;
  final bool isVerified;
  final bool isScam;
  final bool isFake;

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
    this.lastMsgIsOutgoing = false,
    this.lastMsgStatus = MsgStatus.unknown,
    this.lastMsgMediaType = 0,
    this.lastMsgThumbB64 = '',
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.isArchived = false,
    this.draftText = '',
    this.memberCount = 0,
    this.parentId = '',
    this.parentTitle = '',
    this.storyCount = 0,
    this.hasUnreadStory = false,
    this.isLiveStream = false,
    this.isBot = false,
    this.isContact = false,
    this.isBlocked = false,
    this.isUnreadMark = false,
    this.unreadMentionCount = 0,
    this.unreadReactionCount = 0,
    this.isVerified = false,
    this.isScam = false,
    this.isFake = false,
  });

  factory ChatInfo.fromJson(Map<String, dynamic> j) => ChatInfo(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    type: ChatType.fromInt(j['type'] as int? ?? 0),
    title: safeStr(j['title'] as String? ?? ''),
    avatarPath: j['avatar_path'] as String? ?? '',
    lastMsgId: j['last_msg_id'] as String? ?? '',
    lastMsgText: safeStr(j['last_msg_text'] as String? ?? ''),
    lastMsgTime: j['last_msg_time'] as int? ?? 0,
    lastMsgSender: safeStr(j['last_msg_sender'] as String? ?? ''),
    lastMsgIsOutgoing: j['last_msg_is_outgoing'] as bool? ?? false,
    lastMsgStatus: MsgStatus.fromInt(j['last_msg_status'] as int? ?? 0),
    lastMsgMediaType: j['last_msg_media_type'] as int? ?? 0,
    lastMsgThumbB64: j['last_msg_thumb_b64'] as String? ?? '',
    unreadCount: j['unread_count'] as int? ?? 0,
    isMuted: j['is_muted'] as bool? ?? false,
    isPinned: j['is_pinned'] as bool? ?? false,
    isArchived: j['is_archived'] as bool? ?? false,
    draftText: safeStr(j['draft_text'] as String? ?? ''),
    memberCount: j['member_count'] as int? ?? 0,
    parentId: j['parent_id'] as String? ?? '',
    parentTitle: safeStr(j['parent_title'] as String? ?? ''),
    storyCount: j['story_count'] as int? ?? 0,
    hasUnreadStory: j['has_unread_story'] as bool? ?? false,
    isLiveStream: j['is_live_stream'] as bool? ?? false,
    isBot: j['is_bot'] as bool? ?? false,
    isContact: j['is_contact'] as bool? ?? false,
    isBlocked: j['is_blocked'] as bool? ?? false,
    isUnreadMark: j['unread_mark'] as bool? ?? false,
    unreadMentionCount: j['unread_mention_count'] as int? ?? 0,
    unreadReactionCount: j['unread_reaction_count'] as int? ?? 0,
    isVerified: j['is_verified'] as bool? ?? false,
    isScam: j['is_scam'] as bool? ?? false,
    isFake: j['is_fake'] as bool? ?? false,
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
  final String senderRank; // admin/creator custom title (e.g. "admin", "owner", "Head Mod")
  final int senderColorId; // name color palette index (0..63)
  final String contentText;
  final String contentRaw;
  final String contentRich;
  final int timestamp;
  final int editedAt;
  final MsgStatus status;
  final String replyToId;
  final String replyPreview;
  final String forwardFrom;
  final bool isPinned;
  final bool isOutgoing;
  final bool isService;
  final bool hasMedia;

  // Media metadata.
  final int mediaType; // 0=none, 1=image, 2=video, 3=audio, 4=voice, 5=videonote, 6=sticker, 7=gif, 8=file
  final String mediaFileName;
  final String mediaMimeType;
  final int mediaFileSize;
  final String mediaThumbB64; // base64 thumbnail
  final String mediaLocalPath; // local file path if downloaded
  final int mediaWidth;
  final int mediaHeight;
  final int mediaDuration; // seconds
  final int mediaDownloadState; // 0=none, 1=in_progress, 2=complete, 3=failed (matches Go engine/db.go)
  final List<MessageReaction> reactions;

  // Forum topic info (populated from contentRaw extra fields).
  final String topicId;    // topic root message ID (empty = not a forum topic message)
  final String topicName;  // topic title (may be empty if not cached)
  final int topicColorId;  // topic icon color (0 = default/unknown)

  // Via-bot label (populated from contentRaw extra fields).
  final String viaBotName; // e.g. "@gif" — inline bot that generated this message

  // Media spoiler flag (photo/video/GIF marked with spoiler overlay).
  final bool mediaSpoiler;

  // Album grouping (messages with same groupedId form a media album).
  final String groupedId;

  // Channel post metadata (extracted from contentRaw).
  final int views;    // view count (channel posts)
  final int forwards; // forward/share count (channel posts)

  // Sticker set info (extracted from contentRaw extra fields).
  final String stickerSetShortName;
  final int stickerSetId;
  final int stickerSetAccessHash;

  const CachedMessage({
    required this.accountId,
    required this.chatId,
    required this.msgId,
    this.localId = '',
    this.senderId = '',
    this.senderName = '',
    this.senderRank = '',
    this.senderColorId = 0,
    this.contentText = '',
    this.contentRaw = '',
    this.contentRich = '',
    this.timestamp = 0,
    this.editedAt = 0,
    this.status = MsgStatus.unknown,
    this.replyToId = '',
    this.replyPreview = '',
    this.forwardFrom = '',
    this.isPinned = false,
    this.isOutgoing = false,
    this.isService = false,
    this.hasMedia = false,
    this.mediaType = 0,
    this.mediaFileName = '',
    this.mediaMimeType = '',
    this.mediaFileSize = 0,
    this.mediaThumbB64 = '',
    this.mediaLocalPath = '',
    this.mediaWidth = 0,
    this.mediaHeight = 0,
    this.mediaDuration = 0,
    this.mediaDownloadState = 0,
    this.reactions = const [],
    this.topicId = '',
    this.topicName = '',
    this.topicColorId = 0,
    this.viaBotName = '',
    this.mediaSpoiler = false,
    this.groupedId = '',
    this.views = 0,
    this.forwards = 0,
    this.stickerSetShortName = '',
    this.stickerSetId = 0,
    this.stickerSetAccessHash = 0,
  });

  factory CachedMessage.fromJson(Map<String, dynamic> j) => CachedMessage(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    localId: j['local_id'] as String? ?? '',
    senderId: j['sender_id'] as String? ?? '',
    senderName: safeStr(j['sender_name'] as String? ?? ''),
    senderRank: j['sender_rank'] as String? ?? '',
    senderColorId: j['sender_color_id'] as int? ?? 0,
    contentText: safeStr(j['content_text'] as String? ?? ''),
    contentRaw: safeStr(j['content_raw'] as String? ?? ''),
    contentRich: safeStr(j['content_rich'] as String? ?? ''),
    timestamp: j['timestamp'] as int? ?? 0,
    editedAt: j['edited_at'] as int? ?? 0,
    status: MsgStatus.fromInt(j['status'] as int? ?? 0),
    replyToId: j['reply_to_id'] as String? ?? '',
    replyPreview: safeStr(j['reply_preview'] as String? ?? ''),
    forwardFrom: safeStr(j['forward_from'] as String? ?? ''),
    isPinned: j['is_pinned'] as bool? ?? false,
    isOutgoing: j['is_outgoing'] as bool? ?? false,
    isService: j['is_service'] as bool? ?? false,
    hasMedia: j['has_media'] as bool? ?? false,
    mediaType: j['media_type'] as int? ?? 0,
    mediaFileName: j['media_file_name'] as String? ?? '',
    mediaMimeType: j['media_mime_type'] as String? ?? '',
    mediaFileSize: j['media_file_size'] as int? ?? 0,
    mediaThumbB64: j['media_thumb_b64'] as String? ?? '',
    mediaLocalPath: j['media_local_path'] as String? ?? '',
    mediaWidth: j['media_width'] as int? ?? 0,
    mediaHeight: j['media_height'] as int? ?? 0,
    mediaDuration: j['media_duration'] as int? ?? 0,
    mediaDownloadState: j['media_download_state'] as int? ?? 0,
    mediaSpoiler: j['media_spoiler'] as bool? ?? false,
    groupedId: j['grouped_id'] as String? ?? '',
    reactions: (j['reactions'] as List<dynamic>?)
        ?.map((r) => MessageReaction.fromJson(r as Map<String, dynamic>))
        .toList() ?? const [],
  );

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
  bool get isEdited => editedAt > 0;
  bool get isSending => status == MsgStatus.sending;
  bool get isFailed => status == MsgStatus.failed;
  bool get isSent => isOutgoing; // Set by Go engine per-platform
  bool get isImage => mediaType == 1;
  bool get isVideo => mediaType == 2;
  bool get isAudio => mediaType == 3;
  bool get isVoice => mediaType == 4;
  bool get isSticker => mediaType == 6;
  bool get isGif => mediaType == 7;
  bool get isFile => mediaType == 8;
  bool get isMediaDownloaded => mediaDownloadState == 2;
  bool get isAlbumMember => groupedId.isNotEmpty;
  String get mediaSizeLabel {
    if (mediaFileSize <= 0) return '';
    if (mediaFileSize < 1024) return '$mediaFileSize B';
    if (mediaFileSize < 1024 * 1024) return '${(mediaFileSize / 1024).toStringAsFixed(1)} KB';
    return '${(mediaFileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  CachedMessage copyWith({
    String? accountId,
    String? chatId,
    String? msgId,
    String? localId,
    String? senderId,
    String? senderName,
    String? senderRank,
    int? senderColorId,
    String? contentText,
    String? contentRaw,
    String? contentRich,
    int? timestamp,
    int? editedAt,
    MsgStatus? status,
    String? replyToId,
    String? replyPreview,
    String? forwardFrom,
    bool? isPinned,
    bool? isOutgoing,
    bool? isService,
    bool? hasMedia,
    int? mediaType,
    String? mediaFileName,
    String? mediaMimeType,
    int? mediaFileSize,
    String? mediaThumbB64,
    String? mediaLocalPath,
    int? mediaWidth,
    int? mediaHeight,
    int? mediaDuration,
    int? mediaDownloadState,
    List<MessageReaction>? reactions,
    String? viaBotName,
    bool? mediaSpoiler,
    String? groupedId,
    int? views,
    int? forwards,
  }) => CachedMessage(
    accountId: accountId ?? this.accountId,
    chatId: chatId ?? this.chatId,
    msgId: msgId ?? this.msgId,
    localId: localId ?? this.localId,
    senderId: senderId ?? this.senderId,
    senderName: senderName ?? this.senderName,
    senderRank: senderRank ?? this.senderRank,
    senderColorId: senderColorId ?? this.senderColorId,
    contentText: contentText ?? this.contentText,
    contentRaw: contentRaw ?? this.contentRaw,
    contentRich: contentRich ?? this.contentRich,
    timestamp: timestamp ?? this.timestamp,
    editedAt: editedAt ?? this.editedAt,
    status: status ?? this.status,
    replyToId: replyToId ?? this.replyToId,
    replyPreview: replyPreview ?? this.replyPreview,
    forwardFrom: forwardFrom ?? this.forwardFrom,
    isPinned: isPinned ?? this.isPinned,
    isOutgoing: isOutgoing ?? this.isOutgoing,
    isService: isService ?? this.isService,
    hasMedia: hasMedia ?? this.hasMedia,
    mediaType: mediaType ?? this.mediaType,
    mediaFileName: mediaFileName ?? this.mediaFileName,
    mediaMimeType: mediaMimeType ?? this.mediaMimeType,
    mediaFileSize: mediaFileSize ?? this.mediaFileSize,
    mediaThumbB64: mediaThumbB64 ?? this.mediaThumbB64,
    mediaLocalPath: mediaLocalPath ?? this.mediaLocalPath,
    mediaWidth: mediaWidth ?? this.mediaWidth,
    mediaHeight: mediaHeight ?? this.mediaHeight,
    mediaDuration: mediaDuration ?? this.mediaDuration,
    mediaDownloadState: mediaDownloadState ?? this.mediaDownloadState,
    reactions: reactions ?? this.reactions,
    topicId: topicId,
    topicName: topicName,
    topicColorId: topicColorId,
    viaBotName: viaBotName ?? this.viaBotName,
    mediaSpoiler: mediaSpoiler ?? this.mediaSpoiler,
    groupedId: groupedId ?? this.groupedId,
    views: views ?? this.views,
    forwards: forwards ?? this.forwards,
    stickerSetShortName: stickerSetShortName,
    stickerSetId: stickerSetId,
    stickerSetAccessHash: stickerSetAccessHash,
  );

  bool get hasStickerSet => stickerSetShortName.isNotEmpty || stickerSetId != 0;
}

// ── Message reaction ──
class MessageReaction {
  final String emoji;
  final int count;
  final bool byMe;

  const MessageReaction({
    required this.emoji,
    this.count = 1,
    this.byMe = false,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
    emoji: j['emoji'] as String? ?? '',
    count: j['count'] as int? ?? 1,
    byMe: j['by_me'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'emoji': emoji,
    'count': count,
    'by_me': byMe,
  };
}

// ── Shared media item ──
class SharedMediaItem {
  final String msgId;
  final int timestamp;
  final int mediaType; // 1=image, 2=video, 3=audio, 4=voice, 5=videonote, 6=sticker, 7=gif, 8=file
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String thumbB64;
  final String localPath;
  final int width;
  final int height;
  final int duration; // seconds

  const SharedMediaItem({
    required this.msgId,
    this.timestamp = 0,
    this.mediaType = 0,
    this.fileName = '',
    this.mimeType = '',
    this.fileSize = 0,
    this.thumbB64 = '',
    this.localPath = '',
    this.width = 0,
    this.height = 0,
    this.duration = 0,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
  bool get isImage => mediaType == 1 || mediaType == 6 || mediaType == 7; // image, sticker, gif
  bool get isVideo => mediaType == 2 || mediaType == 5; // video, videonote
  bool get isAudio => mediaType == 3 || mediaType == 4; // audio, voice
  bool get isFile => mediaType == 8;

  String get fileSizeLabel {
    if (fileSize <= 0) return '';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ── Folder info ──
class FolderInfo {
  final String id;
  final String name;
  final List<String> chatIds;
  final List<String> excludeChatIds;
  final List<String> pinnedChatIds;
  final bool contacts;
  final bool nonContacts;
  final bool groups;
  final bool channels;
  final bool bots;
  final bool excludeMuted;
  final bool excludeRead;
  final bool excludeArchived;

  /// Whether this folder uses type-based filter flags (not just explicit IDs).
  bool get hasTypeFilters => contacts || nonContacts || groups || channels || bots;

  const FolderInfo({
    this.id = '',
    this.name = '',
    this.chatIds = const [],
    this.excludeChatIds = const [],
    this.pinnedChatIds = const [],
    this.contacts = false,
    this.nonContacts = false,
    this.groups = false,
    this.channels = false,
    this.bots = false,
    this.excludeMuted = false,
    this.excludeRead = false,
    this.excludeArchived = false,
  });
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

// ── Member info ──
class MemberInfo {
  final String userId;
  final String username;
  final String displayName;
  final String avatarB64;
  final bool isBot;
  final bool isOnline;
  final String role; // "owner", "admin", "member", "restricted", "banned"

  const MemberInfo({
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.avatarB64 = '',
    this.isBot = false,
    this.isOnline = false,
    this.role = 'member',
  });

  /// Display label: displayName if available, else username, else userId.
  String get label => displayName.isNotEmpty
      ? displayName
      : username.isNotEmpty
          ? username
          : userId;
}

// ── Contact info ──
class ContactInfo {
  final String userId;
  final String username;
  final String displayName;
  final String phone;
  final String avatarB64;
  final bool isBot;
  final bool isOnline;

  const ContactInfo({
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.phone = '',
    this.avatarB64 = '',
    this.isBot = false,
    this.isOnline = false,
  });

  String get label => displayName.isNotEmpty
      ? displayName
      : username.isNotEmpty
          ? '@$username'
          : userId;
}

// ── Menu Bot (attach-menu bot with inMainMenu + media) ──
class MenuBotInfo {
  final String id;
  final String name;
  final String iconPath; // local path to bot's menu icon, or empty

  const MenuBotInfo({
    required this.id,
    this.name = '',
    this.iconPath = '',
  });

  factory MenuBotInfo.fromJson(Map<String, dynamic> j) => MenuBotInfo(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    iconPath: j['icon_path'] as String? ?? '',
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

class ChatRemovedEvent {
  final String accountId;
  final String chatId;
  const ChatRemovedEvent({this.accountId = '', this.chatId = ''});
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
    newText: safeStr(j['new_text'] as String? ?? ''),
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

class UserStatusEvent {
  final String accountId;
  final String userId;
  final bool isOnline;
  /// Coarse visibility kind: "online", "recently", "within_week",
  /// "within_month", "long_ago", "exact", "hidden", or "".
  final String lastSeenKind;
  /// Unix millis, only valid when [lastSeenKind] == "exact". 0 = unset.
  final int lastSeenMs;
  const UserStatusEvent({
    this.accountId = '',
    this.userId = '',
    this.isOnline = false,
    this.lastSeenKind = '',
    this.lastSeenMs = 0,
  });

  factory UserStatusEvent.fromJson(Map<String, dynamic> j, {String accountId = ''}) => UserStatusEvent(
    accountId: accountId,
    userId: j['user_id'] as String? ?? '',
    isOnline: j['is_online'] as bool? ?? false,
    lastSeenKind: j['last_seen_kind'] as String? ?? '',
    lastSeenMs: (j['last_seen'] as num?)?.toInt() ?? 0,
  );
}

// ── Group call ──
class GroupCallParticipant {
  final String userId;
  final String displayName;
  final bool isMuted;
  final bool isSpeaking;
  final bool hasVideo;
  final String avatarPath;

  const GroupCallParticipant({
    this.userId = '',
    this.displayName = '',
    this.isMuted = false,
    this.isSpeaking = false,
    this.hasVideo = false,
    this.avatarPath = '',
  });

  factory GroupCallParticipant.fromJson(Map<String, dynamic> j) => GroupCallParticipant(
    userId: j['user_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    isMuted: j['is_muted'] as bool? ?? false,
    isSpeaking: j['is_speaking'] as bool? ?? false,
    hasVideo: j['has_video'] as bool? ?? false,
    avatarPath: j['avatar_path'] as String? ?? '',
  );
}

class GroupCallInfo {
  final String callId;
  final String chatId;
  final String title;
  final int participantsCount;
  final List<GroupCallParticipant> participants;
  final bool active;

  const GroupCallInfo({
    this.callId = '',
    this.chatId = '',
    this.title = '',
    this.participantsCount = 0,
    this.participants = const [],
    this.active = false,
  });

  factory GroupCallInfo.fromJson(Map<String, dynamic> j) => GroupCallInfo(
    callId: j['call_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    participantsCount: j['participants_count'] as int? ?? 0,
    participants: (j['participants'] as List<dynamic>?)
        ?.map((p) => GroupCallParticipant.fromJson(p as Map<String, dynamic>))
        .toList() ?? [],
    active: j['active'] as bool? ?? false,
  );
}

class GroupCallStateEvent {
  final String accountId;
  final GroupCallInfo info;

  const GroupCallStateEvent({
    this.accountId = '',
    this.info = const GroupCallInfo(),
  });
}

class PeerColorEntry {
  final int colorId;
  final List<int> dayColors;
  final List<int> nightColors;
  final bool hidden;

  const PeerColorEntry({
    required this.colorId,
    this.dayColors = const [],
    this.nightColors = const [],
    this.hidden = false,
  });
}

// ── Sticker set info (for sticker pack viewer) ──

class StickerInfoItem {
  final String emoji;
  final String thumbB64;
  final int width;
  final int height;
  final String mimeType;
  final String fileId;

  const StickerInfoItem({
    this.emoji = '',
    this.thumbB64 = '',
    this.width = 0,
    this.height = 0,
    this.mimeType = '',
    this.fileId = '',
  });
}

class StickerSetInfo {
  final String title;
  final String shortName;
  final int count;
  final bool installed;
  final bool archived;
  final List<StickerInfoItem> stickers;

  const StickerSetInfo({
    this.title = '',
    this.shortName = '',
    this.count = 0,
    this.installed = false,
    this.archived = false,
    this.stickers = const [],
  });
}
