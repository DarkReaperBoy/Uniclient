/// Dart model classes mirroring the Go engine types.
///
/// These are used by the EngineService for typed event dispatch and API responses.
library;

import 'dart:convert';
import 'dart:typed_data';

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
  final String selfUserId;

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
    this.selfUserId = '',
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
    selfUserId: j['self_user_id'] as String? ?? '',
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
    qrData: (j['qr_data'] as List<dynamic>?)?.cast<int>() ?? const [],
    qrExpiresIn: j['qr_expires_in'] as int? ?? 0,
    displayName: j['display_name'] as String? ?? '',
    avatarB64: j['avatar_b64'] as String? ?? '',
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
  final int unreadPollCount;
  final bool isContact;
  final bool isBlocked;
  final bool isVerified;
  final bool isScam;
  final bool isFake;
  final bool voiceRestricted;
  final bool videoRestricted;
  final int slowmodeSeconds;
  final int slowmodeNextSendDate;
  final int starsToSend;
  final int ttlPeriod;
  final String emojiStatusId;
  final bool isForum;
  final int writeRestrictionType;
  final String writeRestrictionText;
  final int boostsToLift;
  final bool notJoined;
  final bool joinRequest;
  final bool canPost;
  final bool isAdmin;
  final bool noForwards;
  final bool isSelf;

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
    this.unreadPollCount = 0,
    this.isVerified = false,
    this.isScam = false,
    this.isFake = false,
    this.voiceRestricted = false,
    this.videoRestricted = false,
    this.slowmodeSeconds = 0,
    this.slowmodeNextSendDate = 0,
    this.starsToSend = 0,
    this.ttlPeriod = 0,
    this.emojiStatusId = '',
    this.isForum = false,
    this.writeRestrictionType = 0,
    this.writeRestrictionText = '',
    this.boostsToLift = 0,
    this.notJoined = false,
    this.joinRequest = false,
    this.canPost = false,
    this.isAdmin = false,
    this.noForwards = false,
    this.isSelf = false,
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
    unreadPollCount: j['unread_poll_count'] as int? ?? 0,
    isVerified: j['is_verified'] as bool? ?? false,
    isScam: j['is_scam'] as bool? ?? false,
    isFake: j['is_fake'] as bool? ?? false,
    voiceRestricted: j['voice_restricted'] as bool? ?? false,
    videoRestricted: j['video_restricted'] as bool? ?? false,
    slowmodeSeconds: j['slowmode_seconds'] as int? ?? 0,
    slowmodeNextSendDate: j['slowmode_next_send_date'] as int? ?? 0,
    starsToSend: j['stars_to_send'] as int? ?? 0,
    ttlPeriod: j['ttl_period'] as int? ?? 0,
    emojiStatusId: j['emoji_status_id'] as String? ?? '',
    isForum: j['is_forum'] as bool? ?? false,
    writeRestrictionType: j['write_restriction_type'] as int? ?? 0,
    writeRestrictionText: j['write_restriction_text'] as String? ?? '',
    boostsToLift: j['boosts_to_lift'] as int? ?? 0,
    notJoined: j['not_joined'] as bool? ?? false,
    joinRequest: j['join_request'] as bool? ?? false,
    canPost: j['can_post'] as bool? ?? false,
    isAdmin: j['is_admin'] as bool? ?? false,
    noForwards: j['no_forwards'] as bool? ?? false,
    isSelf: j['is_self'] as bool? ?? false,
  );

  /// Time as DateTime for display.
  DateTime get lastMsgDateTime => DateTime.fromMillisecondsSinceEpoch(lastMsgTime);
}

// ── Forum topic ──

class ForumTopic {
  final String id;
  final String title;
  final int colorId;
  final int iconEmojiId;
  final String creatorId;
  final int creationDate;
  final bool isClosed;
  final bool isHidden;
  final bool isMy;
  final bool isPinned;
  final int unreadCount;
  final int unreadMentions;
  final int unreadReactions;
  final String topMessageId;
  final int readInboxMaxId;
  final int readOutboxMaxId;
  final String parentId;
  final bool canEdit;
  final bool canDelete;
  final bool canToggleClosed;
  final bool canTogglePinned;
  final String lastMsgText;
  final int lastMsgDate;

  const ForumTopic({
    required this.id,
    this.title = '',
    this.colorId = 0,
    this.iconEmojiId = 0,
    this.creatorId = '',
    this.creationDate = 0,
    this.isClosed = false,
    this.isHidden = false,
    this.isMy = false,
    this.isPinned = false,
    this.unreadCount = 0,
    this.unreadMentions = 0,
    this.unreadReactions = 0,
    this.topMessageId = '',
    this.readInboxMaxId = 0,
    this.readOutboxMaxId = 0,
    this.parentId = '',
    this.canEdit = false,
    this.canDelete = false,
    this.canToggleClosed = false,
    this.canTogglePinned = false,
    this.lastMsgText = '',
    this.lastMsgDate = 0,
  });

  bool get isGeneral => id == '1';

  bool get hasCustomIcon => iconEmojiId != 0;

  DateTime get creationDateTime =>
      DateTime.fromMillisecondsSinceEpoch(creationDate * 1000);

  DateTime get lastMsgDateTime =>
      lastMsgDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastMsgDate * 1000)
          : creationDateTime;

  static const Map<int, String> colorNames = {
    0x6FB9F0: 'blue',
    0xFFD67E: 'yellow',
    0xCB86DB: 'violet',
    0x8EEE98: 'green',
    0xFF93B2: 'rose',
    0xFB6F5F: 'red',
  };

  String get colorName => colorNames[colorId] ?? 'blue';
}

class VideoQuality {
  final int height;
  final int width;
  final int size;
  final int seq;
  const VideoQuality({this.height = 0, this.width = 0, this.size = 0, this.seq = 0});
  String get label => '${height}p';
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
  final String mediaRemoteRef; // document/file ID for sticker/GIF operations
  final String mediaExtra; // encoded access hash + file reference
  final List<VideoQuality> altQualities;
  final List<int> mediaWaveform; // 5-bit amplitude samples (0–31), typically 100 entries for voice messages
  final List<MessageReaction> reactions;

  // Anti-recall metadata.
  final bool isDeleted;
  final int deletedAt;

  // TTL media metadata (self-destructing media not yet viewed).
  final bool mediaUnread;
  final int ttlSeconds;

  // Forum topic info (populated from contentRaw extra fields).
  final String topicId;    // topic root message ID (empty = not a forum topic message)
  final String topicName;  // topic title (may be empty if not cached)
  final int topicColorId;  // topic icon color (0 = default/unknown)

  // Via-bot label (populated from contentRaw extra fields).
  final String viaBotName; // e.g. "@gif" — inline bot that generated this message

  // Media spoiler flag (photo/video/GIF marked with spoiler overlay).
  final bool mediaSpoiler;

  // Message-level forwarding restriction (AyuNoForwards flag).
  final bool noForwards;

  // Unsupported TTL media (MessageMediaUnsupported with self-destruct timer).
  final bool unsupportedTTL;

  // Sender's AyuNoForwards flag (derived from users table, not persisted on message).
  final bool senderNoForwards;

  // Album grouping (messages with same groupedId form a media album).
  final String groupedId;

  // Channel post metadata (extracted from contentRaw).
  final int views;    // view count (channel posts)
  final int forwards; // forward/share count (channel posts)

  // Sticker set info (extracted from contentRaw extra fields).
  final String stickerSetShortName;
  final int stickerSetId;
  final int stickerSetAccessHash;

  // Premium sticker flag (has premium effect animation via VideoSize type "f").
  final bool stickerPremium;

  // Audio/music metadata (extracted from contentRaw extra fields).
  final String audioTitle;
  final String audioPerformer;

  // Poll data (extracted from contentRaw extra fields).
  final String pollQuestion;
  final List<PollOption> pollOptions;
  final bool pollQuiz;
  final bool pollMultiple;
  final bool pollClosed;
  final bool pollPublic;
  final int pollTotalVoters;
  final int pollCloseDate;
  final int pollClosePeriod;
  final List<String> pollRecentVoters;

  // Location data (extracted from contentRaw extra fields).
  final double geoLat;
  final double geoLong;
  final bool geoLive;
  final int geoPeriod;
  final String venueTitle;
  final String venueAddress;

  // Contact data (extracted from contentRaw extra fields).
  final String contactFirstName;
  final String contactLastName;
  final String contactPhone;
  final int contactUserId;

  // Web page preview data (extracted from contentRaw extra fields).
  final String wpUrl;
  final String wpSiteName;
  final String wpTitle;
  final String wpDescription;
  final String wpType;
  final String wpThumbB64;
  final bool wpForceLargeMedia;
  final bool wpForceSmallMedia;
  final bool wpHasLargeMedia;
  final bool wpHasIv;
  final int wpPhotoW;
  final int wpPhotoH;
  final int wpDuration;

  // Game message data (extracted from contentRaw extra fields).
  final String gameTitle;
  final String gameDescription;
  final String gameShortName;
  final String gameThumbB64;
  final int gamePhotoW;
  final int gamePhotoH;

  // Invoice data (extracted from contentRaw extra fields).
  final String invoiceTitle;
  final String invoiceDescription;
  final String invoiceCurrency;
  final int invoiceTotalAmount;
  final bool invoiceTest;
  final int invoiceReceiptMsgId;
  final String invoicePhotoUrl;
  final bool invoiceShippingRequested;

  // Thread/replies data (extracted from contentRaw extra fields).
  final int repliesCount;
  final String repliesChannelId;
  final bool repliesIsComments;

  // Bot keyboard data (extracted from contentRaw extra fields).
  final ReplyKeyboardData? replyKeyboard;
  final List<List<InlineKeyboardButton>> inlineKeyboard;
  final bool keyboardHide;
  final bool forceReply;
  final String forceReplyPlaceholder;

  // Data center ID for the media.
  final int dcId;

  // Scheduled message metadata.
  final int scheduleDate;
  final bool isSilent;
  final int scheduleRepeatPeriod;

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
    this.mediaRemoteRef = '',
    this.mediaExtra = '',
    this.altQualities = const [],
    this.mediaWaveform = const [],
    this.reactions = const [],
    this.isDeleted = false,
    this.deletedAt = 0,
    this.mediaUnread = false,
    this.ttlSeconds = 0,
    this.topicId = '',
    this.topicName = '',
    this.topicColorId = 0,
    this.viaBotName = '',
    this.mediaSpoiler = false,
    this.noForwards = false,
    this.unsupportedTTL = false,
    this.senderNoForwards = false,
    this.groupedId = '',
    this.views = 0,
    this.forwards = 0,
    this.stickerSetShortName = '',
    this.stickerSetId = 0,
    this.stickerSetAccessHash = 0,
    this.stickerPremium = false,
    this.audioTitle = '',
    this.audioPerformer = '',
    this.pollQuestion = '',
    this.pollOptions = const [],
    this.pollQuiz = false,
    this.pollMultiple = false,
    this.pollClosed = false,
    this.pollPublic = false,
    this.pollTotalVoters = 0,
    this.pollCloseDate = 0,
    this.pollClosePeriod = 0,
    this.pollRecentVoters = const [],
    this.geoLat = 0.0,
    this.geoLong = 0.0,
    this.geoLive = false,
    this.geoPeriod = 0,
    this.venueTitle = '',
    this.venueAddress = '',
    this.contactFirstName = '',
    this.contactLastName = '',
    this.contactPhone = '',
    this.contactUserId = 0,
    this.wpUrl = '',
    this.wpSiteName = '',
    this.wpTitle = '',
    this.wpDescription = '',
    this.wpType = '',
    this.wpThumbB64 = '',
    this.wpForceLargeMedia = false,
    this.wpForceSmallMedia = false,
    this.wpHasLargeMedia = false,
    this.wpHasIv = false,
    this.wpPhotoW = 0,
    this.wpPhotoH = 0,
    this.wpDuration = 0,
    this.gameTitle = '',
    this.gameDescription = '',
    this.gameShortName = '',
    this.gameThumbB64 = '',
    this.gamePhotoW = 0,
    this.gamePhotoH = 0,
    this.invoiceTitle = '',
    this.invoiceDescription = '',
    this.invoiceCurrency = '',
    this.invoiceTotalAmount = 0,
    this.invoiceTest = false,
    this.invoiceReceiptMsgId = 0,
    this.invoicePhotoUrl = '',
    this.invoiceShippingRequested = false,
    this.repliesCount = 0,
    this.repliesChannelId = '',
    this.repliesIsComments = false,
    this.replyKeyboard,
    this.inlineKeyboard = const [],
    this.keyboardHide = false,
    this.forceReply = false,
    this.forceReplyPlaceholder = '',
    this.dcId = 0,
    this.scheduleDate = 0,
    this.isSilent = false,
    this.scheduleRepeatPeriod = 0,
  });

  factory CachedMessage.fromJson(Map<String, dynamic> j) {
    final rawStr = j['content_raw'] as String? ?? '';
    final extra = _decodeContentRawExtra(rawStr);
    final rawMsg = _decodeContentRawTop(rawStr);
    final waveform = _decodeWaveform(extra['waveform'] as String?);

    return CachedMessage(
      accountId: j['account_id'] as String? ?? '',
      chatId: j['chat_id'] as String? ?? '',
      msgId: j['msg_id'] as String? ?? '',
      localId: j['local_id'] as String? ?? '',
      senderId: j['sender_id'] as String? ?? '',
      senderName: safeStr(j['sender_name'] as String? ?? ''),
      senderRank: j['sender_rank'] as String? ?? '',
      senderColorId: j['sender_color_id'] as int? ?? 0,
      contentText: safeStr(j['content_text'] as String? ?? ''),
      contentRaw: safeStr(rawStr),
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
      mediaWaveform: waveform,
      isDeleted: j['is_deleted'] as bool? ?? false,
      deletedAt: j['deleted_at'] as int? ?? 0,
      mediaSpoiler: j['media_spoiler'] as bool? ?? (extra['media_spoiler'] as bool? ?? false),
      noForwards: j['no_forwards'] as bool? ?? (extra['no_forwards'] as bool? ?? false),
      groupedId: j['grouped_id'] as String? ?? '',
      reactions: (j['reactions'] as List<dynamic>?)
          ?.map((r) => MessageReaction.fromJson(r as Map<String, dynamic>))
          .toList() ?? const [],
      dcId: j['dc_id'] as int? ?? 0,
      scheduleDate: j['schedule_date'] as int? ?? 0,
      isSilent: j['is_silent'] as bool? ?? (extra['is_silent'] as bool? ?? false),
      scheduleRepeatPeriod: j['schedule_repeat_period'] as int? ?? (extra['schedule_repeat_period'] as int? ?? 0),
      pollQuestion: extra['poll_question'] as String? ?? '',
      pollOptions: _decodePollOptions(extra['poll_options']),
      pollQuiz: extra['poll_quiz'] as bool? ?? false,
      pollMultiple: extra['poll_multiple'] as bool? ?? false,
      pollClosed: extra['poll_closed'] as bool? ?? false,
      pollPublic: extra['poll_public'] as bool? ?? false,
      pollTotalVoters: _safeInt(extra['poll_total_voters']),
      pollCloseDate: _safeInt(extra['poll_close_date']),
      pollClosePeriod: _safeInt(extra['poll_close_period']),
      pollRecentVoters: (extra['poll_recent_voters'] as List<dynamic>?)?.cast<String>() ?? const [],
      geoLat: _safeDouble(extra['geo_lat']),
      geoLong: _safeDouble(extra['geo_long']),
      geoLive: extra['geo_live'] as bool? ?? false,
      geoPeriod: _safeInt(extra['geo_period']),
      venueTitle: extra['venue_title'] as String? ?? '',
      venueAddress: extra['venue_address'] as String? ?? '',
      contactFirstName: extra['contact_first_name'] as String? ?? '',
      contactLastName: extra['contact_last_name'] as String? ?? '',
      contactPhone: extra['contact_phone'] as String? ?? '',
      contactUserId: _safeInt(extra['contact_user_id']),
      wpUrl: extra['wp_url'] as String? ?? '',
      wpSiteName: extra['wp_site_name'] as String? ?? '',
      wpTitle: extra['wp_title'] as String? ?? '',
      wpDescription: extra['wp_description'] as String? ?? '',
      wpType: extra['wp_type'] as String? ?? '',
      wpThumbB64: extra['wp_thumb_b64'] as String? ?? '',
      wpForceLargeMedia: extra['wp_force_large_media'] as bool? ?? false,
      wpForceSmallMedia: extra['wp_force_small_media'] as bool? ?? false,
      wpHasLargeMedia: extra['wp_has_large_media'] as bool? ?? false,
      wpHasIv: extra['wp_has_iv'] as bool? ?? false,
      wpPhotoW: _safeInt(extra['wp_photo_w']),
      wpPhotoH: _safeInt(extra['wp_photo_h']),
      wpDuration: _safeInt(extra['wp_duration']),
      gameTitle: extra['game_title'] as String? ?? '',
      gameDescription: extra['game_description'] as String? ?? '',
      gameShortName: extra['game_short_name'] as String? ?? '',
      gameThumbB64: extra['game_thumb_b64'] as String? ?? '',
      gamePhotoW: _safeInt(extra['game_photo_w']),
      gamePhotoH: _safeInt(extra['game_photo_h']),
      invoiceTitle: extra['invoice_title'] as String? ?? '',
      invoiceDescription: extra['invoice_description'] as String? ?? '',
      invoiceCurrency: extra['invoice_currency'] as String? ?? '',
      invoiceTotalAmount: _safeInt(extra['invoice_total_amount']),
      invoiceTest: extra['invoice_test'] as bool? ?? false,
      invoiceReceiptMsgId: _safeInt(extra['invoice_receipt_msg_id']),
      invoicePhotoUrl: extra['invoice_photo_url'] as String? ?? '',
      invoiceShippingRequested: extra['invoice_shipping_requested'] as bool? ?? false,
      audioTitle: extra['audio_title'] as String? ?? '',
      audioPerformer: extra['audio_performer'] as String? ?? '',
      repliesCount: _safeInt(extra['replies_count']),
      repliesChannelId: extra['replies_channel_id'] as String? ?? '',
      repliesIsComments: extra['replies_is_comments'] as bool? ?? false,
      topicId: extra['topic_id'] as String? ?? '',
      topicName: extra['topic_name'] as String? ?? '',
      topicColorId: _safeInt(extra['topic_color']),
      viaBotName: extra['via_bot_name'] as String? ?? '',
      stickerSetShortName: extra['sticker_set_short_name'] as String? ?? '',
      stickerSetId: _safeInt(extra['sticker_set_id']),
      stickerSetAccessHash: _safeInt(extra['sticker_set_access_hash']),
      stickerPremium: extra['sticker_premium'] as bool? ?? false,
      mediaUnread: extra['media_unread'] as bool? ?? false,
      ttlSeconds: _safeInt(extra['ttl_seconds']),
      views: _safeInt(rawMsg['views']),
      forwards: _safeInt(rawMsg['forwards']),
    );
  }

  static Map<String, dynamic> _decodeContentRawExtra(String rawStr) {
    if (rawStr.isEmpty) return const {};
    try {
      final bytes = base64Decode(rawStr);
      final parsed = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
      return parsed['extra'] as Map<String, dynamic>? ?? const {};
    } catch (_) {
      return const {};
    }
  }

  static Map<String, dynamic> _decodeContentRawTop(String rawStr) {
    if (rawStr.isEmpty) return const {};
    try {
      final bytes = base64Decode(rawStr);
      return json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  static List<PollOption> _decodePollOptions(dynamic raw) {
    if (raw is! List) return const [];
    final result = <PollOption>[];
    for (final o in raw) {
      if (o is Map<String, dynamic>) {
        result.add(PollOption(
          text: o['text'] as String? ?? '',
          optionB64: o['option'] as String? ?? '',
          chosen: o['chosen'] as bool? ?? false,
          correct: o['correct'] as bool? ?? false,
          voters: _safeInt(o['voters']),
        ));
      }
    }
    return result;
  }

  static List<int> _decodeWaveform(String? b64) {
    if (b64 == null || b64.isEmpty) return const [];
    try {
      final bytes = base64Decode(b64);
      final samples = <int>[];
      int bitPos = 0;
      while (bitPos + 5 <= bytes.length * 8) {
        final byteIdx = bitPos ~/ 8;
        final bitOff = bitPos % 8;
        int val;
        if (bitOff <= 3) {
          val = (bytes[byteIdx] >> bitOff) & 0x1F;
        } else {
          val = bytes[byteIdx] >> bitOff;
          if (byteIdx + 1 < bytes.length) {
            val |= (bytes[byteIdx + 1] << (8 - bitOff));
          }
          val &= 0x1F;
        }
        samples.add(val);
        bitPos += 5;
      }
      return samples;
    } catch (_) {
      return const [];
    }
  }

  static int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return 0;
  }

  static double _safeDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return 0.0;
  }

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
  bool get isPoll => mediaType == 9;
  bool get isLocation => mediaType == 10;
  bool get isContact => mediaType == 11;
  bool get isMediaDownloaded => mediaDownloadState == 2;
  bool get isAlbumMember => groupedId.isNotEmpty;
  bool get hasWebPage => wpUrl.isNotEmpty;
  bool get hasGame => gameTitle.isNotEmpty;
  bool get hasInvoice => invoiceTitle.isNotEmpty;
  bool get isInvoice => mediaType == 12;
  bool get isReceipt => invoiceReceiptMsgId > 0;

  bool get isScheduled => scheduleDate > 0;
  bool get isScheduledUntilOnline =>
      scheduleDate == ScheduledMessages.kScheduledUntilOnlineTimestamp;
  bool get allowsSendNow =>
      isScheduled && !isSending && !isFailed && !isService;
  bool get allowsReschedule => allowsSendNow;

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
    String? mediaRemoteRef,
    String? mediaExtra,
    List<VideoQuality>? altQualities,
    List<int>? mediaWaveform,
    List<MessageReaction>? reactions,
    bool? isDeleted,
    int? deletedAt,
    String? viaBotName,
    bool? mediaSpoiler,
    bool? noForwards,
    bool? unsupportedTTL,
    bool? senderNoForwards,
    String? groupedId,
    int? views,
    int? forwards,
    bool? stickerPremium,
    String? audioTitle,
    String? audioPerformer,
    String? pollQuestion,
    List<PollOption>? pollOptions,
    bool? pollQuiz,
    bool? pollMultiple,
    bool? pollClosed,
    bool? pollPublic,
    int? pollTotalVoters,
    int? pollCloseDate,
    int? pollClosePeriod,
    List<String>? pollRecentVoters,
    double? geoLat,
    double? geoLong,
    bool? geoLive,
    int? geoPeriod,
    String? venueTitle,
    String? venueAddress,
    String? contactFirstName,
    String? contactLastName,
    String? contactPhone,
    int? contactUserId,
    String? wpUrl,
    String? wpSiteName,
    String? wpTitle,
    String? wpDescription,
    String? wpType,
    String? wpThumbB64,
    bool? wpForceLargeMedia,
    bool? wpForceSmallMedia,
    bool? wpHasLargeMedia,
    bool? wpHasIv,
    int? wpPhotoW,
    int? wpPhotoH,
    int? wpDuration,
    String? gameTitle,
    String? gameDescription,
    String? gameShortName,
    String? gameThumbB64,
    int? gamePhotoW,
    int? gamePhotoH,
    String? invoiceTitle,
    String? invoiceDescription,
    String? invoiceCurrency,
    int? invoiceTotalAmount,
    bool? invoiceTest,
    int? invoiceReceiptMsgId,
    String? invoicePhotoUrl,
    bool? invoiceShippingRequested,
    int? repliesCount,
    String? repliesChannelId,
    bool? repliesIsComments,
    ReplyKeyboardData? replyKeyboard,
    List<List<InlineKeyboardButton>>? inlineKeyboard,
    bool? keyboardHide,
    bool? forceReply,
    String? forceReplyPlaceholder,
    int? dcId,
    int? scheduleDate,
    bool? isSilent,
    int? scheduleRepeatPeriod,
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
    mediaRemoteRef: mediaRemoteRef ?? this.mediaRemoteRef,
    mediaExtra: mediaExtra ?? this.mediaExtra,
    altQualities: altQualities ?? this.altQualities,
    mediaWaveform: mediaWaveform ?? this.mediaWaveform,
    reactions: reactions ?? this.reactions,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt ?? this.deletedAt,
    topicId: topicId,
    topicName: topicName,
    topicColorId: topicColorId,
    viaBotName: viaBotName ?? this.viaBotName,
    mediaSpoiler: mediaSpoiler ?? this.mediaSpoiler,
    noForwards: noForwards ?? this.noForwards,
    unsupportedTTL: unsupportedTTL ?? this.unsupportedTTL,
    senderNoForwards: senderNoForwards ?? this.senderNoForwards,
    groupedId: groupedId ?? this.groupedId,
    views: views ?? this.views,
    forwards: forwards ?? this.forwards,
    stickerSetShortName: stickerSetShortName,
    stickerSetId: stickerSetId,
    stickerSetAccessHash: stickerSetAccessHash,
    stickerPremium: stickerPremium ?? this.stickerPremium,
    audioTitle: audioTitle ?? this.audioTitle,
    audioPerformer: audioPerformer ?? this.audioPerformer,
    pollQuestion: pollQuestion ?? this.pollQuestion,
    pollOptions: pollOptions ?? this.pollOptions,
    pollQuiz: pollQuiz ?? this.pollQuiz,
    pollMultiple: pollMultiple ?? this.pollMultiple,
    pollClosed: pollClosed ?? this.pollClosed,
    pollPublic: pollPublic ?? this.pollPublic,
    pollTotalVoters: pollTotalVoters ?? this.pollTotalVoters,
    pollCloseDate: pollCloseDate ?? this.pollCloseDate,
    pollClosePeriod: pollClosePeriod ?? this.pollClosePeriod,
    pollRecentVoters: pollRecentVoters ?? this.pollRecentVoters,
    geoLat: geoLat ?? this.geoLat,
    geoLong: geoLong ?? this.geoLong,
    geoLive: geoLive ?? this.geoLive,
    geoPeriod: geoPeriod ?? this.geoPeriod,
    venueTitle: venueTitle ?? this.venueTitle,
    venueAddress: venueAddress ?? this.venueAddress,
    contactFirstName: contactFirstName ?? this.contactFirstName,
    contactLastName: contactLastName ?? this.contactLastName,
    contactPhone: contactPhone ?? this.contactPhone,
    contactUserId: contactUserId ?? this.contactUserId,
    wpUrl: wpUrl ?? this.wpUrl,
    wpSiteName: wpSiteName ?? this.wpSiteName,
    wpTitle: wpTitle ?? this.wpTitle,
    wpDescription: wpDescription ?? this.wpDescription,
    wpType: wpType ?? this.wpType,
    wpThumbB64: wpThumbB64 ?? this.wpThumbB64,
    wpForceLargeMedia: wpForceLargeMedia ?? this.wpForceLargeMedia,
    wpForceSmallMedia: wpForceSmallMedia ?? this.wpForceSmallMedia,
    wpHasLargeMedia: wpHasLargeMedia ?? this.wpHasLargeMedia,
    wpHasIv: wpHasIv ?? this.wpHasIv,
    wpPhotoW: wpPhotoW ?? this.wpPhotoW,
    wpPhotoH: wpPhotoH ?? this.wpPhotoH,
    wpDuration: wpDuration ?? this.wpDuration,
    gameTitle: gameTitle ?? this.gameTitle,
    gameDescription: gameDescription ?? this.gameDescription,
    gameShortName: gameShortName ?? this.gameShortName,
    gameThumbB64: gameThumbB64 ?? this.gameThumbB64,
    gamePhotoW: gamePhotoW ?? this.gamePhotoW,
    gamePhotoH: gamePhotoH ?? this.gamePhotoH,
    invoiceTitle: invoiceTitle ?? this.invoiceTitle,
    invoiceDescription: invoiceDescription ?? this.invoiceDescription,
    invoiceCurrency: invoiceCurrency ?? this.invoiceCurrency,
    invoiceTotalAmount: invoiceTotalAmount ?? this.invoiceTotalAmount,
    invoiceTest: invoiceTest ?? this.invoiceTest,
    invoiceReceiptMsgId: invoiceReceiptMsgId ?? this.invoiceReceiptMsgId,
    invoicePhotoUrl: invoicePhotoUrl ?? this.invoicePhotoUrl,
    invoiceShippingRequested: invoiceShippingRequested ?? this.invoiceShippingRequested,
    repliesCount: repliesCount ?? this.repliesCount,
    repliesChannelId: repliesChannelId ?? this.repliesChannelId,
    repliesIsComments: repliesIsComments ?? this.repliesIsComments,
    replyKeyboard: replyKeyboard ?? this.replyKeyboard,
    inlineKeyboard: inlineKeyboard ?? this.inlineKeyboard,
    keyboardHide: keyboardHide ?? this.keyboardHide,
    forceReply: forceReply ?? this.forceReply,
    forceReplyPlaceholder: forceReplyPlaceholder ?? this.forceReplyPlaceholder,
    dcId: dcId ?? this.dcId,
    scheduleDate: scheduleDate ?? this.scheduleDate,
    isSilent: isSilent ?? this.isSilent,
    scheduleRepeatPeriod: scheduleRepeatPeriod ?? this.scheduleRepeatPeriod,
  );

  bool get hasStickerSet => stickerSetShortName.isNotEmpty || stickerSetId != 0;
  bool get hasReplies => repliesCount > 0;
  bool get hasThread => topicId.isNotEmpty || hasReplies;
  bool get hasReplyKeyboard => replyKeyboard != null && replyKeyboard!.rows.isNotEmpty;
  bool get hasInlineKeyboard => inlineKeyboard.isNotEmpty;
}

// ── Message reaction ──
class MessageReaction {
  final String emoji;
  final int count;
  final bool byMe;
  final int documentId;

  const MessageReaction({
    required this.emoji,
    this.count = 1,
    this.byMe = false,
    this.documentId = 0,
  });

  bool get isCustomEmoji => documentId != 0;

  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
    emoji: j['emoji'] as String? ?? '',
    count: j['count'] as int? ?? 1,
    byMe: j['by_me'] as bool? ?? false,
    documentId: (j['document_id'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'emoji': emoji,
    'count': count,
    'by_me': byMe,
    if (documentId != 0) 'document_id': documentId,
  };
}

enum ReadPrivacyState { none, myHidden, hisHidden, tooOld }

class ReadParticipantsResult {
  final List<ReadParticipantInfo> participants;
  final ReadPrivacyState privacyState;

  const ReadParticipantsResult({
    this.participants = const [],
    this.privacyState = ReadPrivacyState.none,
  });
}

class ReadParticipantInfo {
  final String userId;
  final int date;
  final String name;

  const ReadParticipantInfo({
    required this.userId,
    this.date = 0,
    this.name = '',
  });
}

class ReadDateResult {
  final int date;
  final ReadPrivacyState privacyState;
  const ReadDateResult({this.date = 0, this.privacyState = ReadPrivacyState.none});
}

// ── Reactor info (who reacted with what emoji) ──
class ReactorInfo {
  final String emoji;
  final int documentId;
  final String peerId;
  final String peerName;
  final int date;

  const ReactorInfo({
    required this.emoji,
    this.documentId = 0,
    required this.peerId,
    required this.peerName,
    this.date = 0,
  });

  bool get isCustomEmoji => documentId != 0;
  String get reactionKey => isCustomEmoji ? 'custom:$documentId' : emoji;
}

class ReactorsListResult {
  final List<ReactorInfo> reactors;
  final String nextOffset;

  const ReactorsListResult({
    required this.reactors,
    required this.nextOffset,
  });
}

// ── Poll option ──
class PollOption {
  final String text;
  final String optionB64;
  final int voters;
  final bool chosen;
  final bool correct;

  const PollOption({
    required this.text,
    this.optionB64 = '',
    this.voters = 0,
    this.chosen = false,
    this.correct = false,
  });

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
    text: j['text'] as String? ?? '',
    optionB64: j['option'] as String? ?? '',
    voters: j['voters'] as int? ?? 0,
    chosen: j['chosen'] as bool? ?? false,
    correct: j['correct'] as bool? ?? false,
  );
}

// ── Keyboard button (reply keyboard & inline keyboard) ──
enum KeyboardButtonColor { normal, primary, danger, success }

class KeyboardButton {
  final String text;
  final String type; // text, request_phone, request_location, request_poll, request_peer, web_view, simple_web_view
  final String url;
  final KeyboardButtonColor color;

  const KeyboardButton({required this.text, this.type = 'text', this.url = '', this.color = KeyboardButtonColor.normal});

  factory KeyboardButton.fromJson(Map<String, dynamic> j) {
    final colorStr = j['color'] as String? ?? '';
    final color = switch (colorStr) {
      'primary' => KeyboardButtonColor.primary,
      'danger' => KeyboardButtonColor.danger,
      'success' => KeyboardButtonColor.success,
      _ => KeyboardButtonColor.normal,
    };
    return KeyboardButton(
      text: j['text'] as String? ?? '',
      type: j['type'] as String? ?? 'text',
      url: j['url'] as String? ?? '',
      color: color,
    );
  }
}

class InlineKeyboardButton {
  final String text;
  final String type; // url, callback, switch_inline, game, buy, url_auth, web_view, simple_web_view, copy, request_phone, request_location, request_poll, request_peer, user_profile
  final String url;
  final String data;
  final String query;
  final String copyText;
  final int buttonId;
  final KeyboardButtonColor color;

  const InlineKeyboardButton({
    required this.text,
    this.type = 'callback',
    this.url = '',
    this.data = '',
    this.query = '',
    this.copyText = '',
    this.buttonId = 0,
    this.color = KeyboardButtonColor.normal,
  });

  factory InlineKeyboardButton.fromJson(Map<String, dynamic> j) {
    final colorStr = j['color'] as String? ?? '';
    final color = switch (colorStr) {
      'primary' => KeyboardButtonColor.primary,
      'danger' => KeyboardButtonColor.danger,
      'success' => KeyboardButtonColor.success,
      _ => KeyboardButtonColor.normal,
    };
    return InlineKeyboardButton(
      text: j['text'] as String? ?? '',
      type: j['type'] as String? ?? 'callback',
      url: j['url'] as String? ?? '',
      data: j['data'] as String? ?? '',
      query: j['query'] as String? ?? '',
      copyText: j['copy_text'] as String? ?? '',
      buttonId: j['button_id'] as int? ?? 0,
      color: color,
    );
  }
}

class ReplyKeyboardData {
  final List<List<KeyboardButton>> rows;
  final bool resize;
  final bool singleUse;
  final bool persistent;
  final String placeholder;

  const ReplyKeyboardData({
    required this.rows,
    this.resize = false,
    this.singleUse = false,
    this.persistent = false,
    this.placeholder = '',
  });

  factory ReplyKeyboardData.fromJson(Map<String, dynamic> j) {
    final rawRows = j['rows'] as List<dynamic>? ?? [];
    final rows = rawRows.map((row) {
      final r = row as List<dynamic>;
      return r.map((b) => KeyboardButton.fromJson(b as Map<String, dynamic>)).toList();
    }).toList();
    return ReplyKeyboardData(
      rows: rows,
      resize: j['resize'] as bool? ?? false,
      singleUse: j['single_use'] as bool? ?? false,
      persistent: j['persistent'] as bool? ?? false,
      placeholder: j['placeholder'] as String? ?? '',
    );
  }
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
  final List<int> waveform;

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
    this.waveform = const [],
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
  final bool newChats;
  final bool existingChats;
  final bool excludeMuted;
  final bool excludeRead;
  final bool excludeArchived;
  final int colorIndex;
  final bool isChatList;
  final String emoticon;

  bool get hasTypeFilters => contacts || nonContacts || groups || channels || bots;
  bool get hasTagColor => colorIndex >= 0 && colorIndex <= 7;

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
    this.newChats = false,
    this.existingChats = false,
    this.excludeMuted = false,
    this.excludeRead = false,
    this.excludeArchived = false,
    this.colorIndex = -1,
    this.isChatList = false,
    this.emoticon = '',
  });
}

class SuggestedFolderInfo {
  final String name;
  final String description;
  final bool contacts;
  final bool nonContacts;
  final bool groups;
  final bool channels;
  final bool bots;

  const SuggestedFolderInfo({
    this.name = '',
    this.description = '',
    this.contacts = false,
    this.nonContacts = false,
    this.groups = false,
    this.channels = false,
    this.bots = false,
  });
}

// ── Chatlist invite link ──
class ChatlistInviteLink {
  final String url;
  final String title;
  final int peerCount;
  final String slug;
  final List<String> peerIds;

  const ChatlistInviteLink({
    this.url = '',
    this.title = '',
    this.peerCount = 0,
    this.slug = '',
    this.peerIds = const [],
  });

  String get displayName {
    if (title.isNotEmpty) return title;
    var s = url;
    for (final prefix in ['https://', 'http://', 't.me/+', 't.me/joinchat/']) {
      if (s.startsWith(prefix)) {
        s = s.substring(prefix.length);
        break;
      }
    }
    return s;
  }
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
  final int storyCount;
  final bool hasUnreadStory;
  final String customRank;
  final String promotedBy;
  final String promotedByID;
  final int promotedDate;

  const MemberInfo({
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.avatarB64 = '',
    this.isBot = false,
    this.isOnline = false,
    this.role = 'member',
    this.storyCount = 0,
    this.hasUnreadStory = false,
    this.customRank = '',
    this.promotedBy = '',
    this.promotedByID = '',
    this.promotedDate = 0,
  });

  bool get hasStories => storyCount > 0;

  String get label => displayName.isNotEmpty
      ? displayName
      : username.isNotEmpty
          ? username
          : userId;
}

class MembersByRoleResult {
  final List<MemberInfo> members;
  final int total;

  const MembersByRoleResult({required this.members, required this.total});
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
  final int storyCount;
  final bool hasUnreadStory;
  final bool isVerified;
  final bool isPremium;
  final bool isScam;
  final bool isFake;
  final String lastSeenKind;
  final int lastSeenTs;

  const ContactInfo({
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.phone = '',
    this.avatarB64 = '',
    this.isBot = false,
    this.isOnline = false,
    this.storyCount = 0,
    this.hasUnreadStory = false,
    this.isVerified = false,
    this.isPremium = false,
    this.isScam = false,
    this.isFake = false,
    this.lastSeenKind = '',
    this.lastSeenTs = 0,
  });

  bool get hasStories => storyCount > 0;

  String get label => displayName.isNotEmpty
      ? displayName
      : username.isNotEmpty
          ? '@$username'
          : userId;
}

// ── Similar channel info ──
class SimilarChannelInfo {
  final String chatId;
  final String title;
  final String avatarB64;
  final int memberCount;

  const SimilarChannelInfo({
    required this.chatId,
    this.title = '',
    this.avatarB64 = '',
    this.memberCount = 0,
  });

  factory SimilarChannelInfo.fromJson(Map<String, dynamic> j) => SimilarChannelInfo(
    chatId: j['chat_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    avatarB64: j['avatar_b64'] as String? ?? '',
    memberCount: j['member_count'] as int? ?? 0,
  );
}

// ── Public link info (for PublicLinksLimitBox) ──
class PublicLinkInfo {
  final String chatId;
  final String title;
  final String username;
  final String avatarB64;

  const PublicLinkInfo({
    required this.chatId,
    this.title = '',
    this.username = '',
    this.avatarB64 = '',
  });

  factory PublicLinkInfo.fromJson(Map<String, dynamic> j) => PublicLinkInfo(
    chatId: j['chat_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    username: j['username'] as String? ?? '',
    avatarB64: j['avatar_b64'] as String? ?? '',
  );
}

class AdminLogEvent {
  final int id;
  final int date;
  final int userId;
  final String userName;
  final String action;
  final String detail;
  final String oldValue;
  final String newValue;
  final int messageId;
  final String msgText;

  const AdminLogEvent({
    required this.id,
    required this.date,
    this.userId = 0,
    this.userName = '',
    this.action = '',
    this.detail = '',
    this.oldValue = '',
    this.newValue = '',
    this.messageId = 0,
    this.msgText = '',
  });

  factory AdminLogEvent.fromJson(Map<String, dynamic> j) => AdminLogEvent(
    id: (j['id'] as num?)?.toInt() ?? 0,
    date: (j['date'] as num?)?.toInt() ?? 0,
    userId: (j['user_id'] as num?)?.toInt() ?? 0,
    userName: j['user_name'] as String? ?? '',
    action: j['action'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    oldValue: j['old_value'] as String? ?? '',
    newValue: j['new_value'] as String? ?? '',
    messageId: (j['message_id'] as num?)?.toInt() ?? 0,
    msgText: j['msg_text'] as String? ?? '',
  );

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date * 1000);
}

// ── Bot command info ──
class BotCommandInfo {
  final String command;
  final String description;
  final String botId;
  final String botName;
  final String botUsername;
  final String avatarB64;

  const BotCommandInfo({
    required this.command,
    this.description = '',
    this.botId = '',
    this.botName = '',
    this.botUsername = '',
    this.avatarB64 = '',
  });

  factory BotCommandInfo.fromJson(Map<String, dynamic> j) => BotCommandInfo(
    command: j['command'] as String? ?? '',
    description: j['description'] as String? ?? '',
    botId: j['bot_id'] as String? ?? '',
    botName: j['bot_name'] as String? ?? '',
    botUsername: j['bot_username'] as String? ?? '',
    avatarB64: j['avatar_b64'] as String? ?? '',
  );
}

// ── User profile (full, with phone/bio) ──
class UserProfile {
  final String userId;
  final String displayName;
  final String username;
  final String phone;
  final String bio;
  final bool isBot;
  final bool isOnline;
  final bool isContact;
  final bool isBlocked;
  final String botMenuText;
  final int lastSeen;
  final String lastSeenKind;
  final bool hasPersonalPhoto;
  final int birthdayDay;
  final int birthdayMonth;
  final int birthdayYear;
  final String personalChannelId;
  final String personalChannelName;
  final bool voiceMessagesForbidden;
  final bool contactRequirePremium;
  final String businessHours;
  final String businessLocation;
  final String notes;
  final String videoAvatarPath;

  const UserProfile({
    required this.userId,
    this.displayName = '',
    this.username = '',
    this.phone = '',
    this.bio = '',
    this.isBot = false,
    this.isOnline = false,
    this.isContact = false,
    this.isBlocked = false,
    this.botMenuText = '',
    this.lastSeen = 0,
    this.lastSeenKind = '',
    this.hasPersonalPhoto = false,
    this.birthdayDay = 0,
    this.birthdayMonth = 0,
    this.birthdayYear = 0,
    this.personalChannelId = '',
    this.personalChannelName = '',
    this.voiceMessagesForbidden = false,
    this.contactRequirePremium = false,
    this.businessHours = '',
    this.businessLocation = '',
    this.notes = '',
    this.videoAvatarPath = '',
  });

  bool get hasBirthday => birthdayDay > 0 && birthdayMonth > 0;

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    userId: j['user_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    username: j['username'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    bio: j['bio'] as String? ?? '',
    isBot: j['is_bot'] as bool? ?? false,
    isOnline: j['is_online'] as bool? ?? false,
    isContact: j['is_contact'] as bool? ?? false,
    isBlocked: j['is_blocked'] as bool? ?? false,
    botMenuText: j['bot_menu_text'] as String? ?? '',
    lastSeen: j['last_seen'] as int? ?? 0,
    lastSeenKind: j['last_seen_kind'] as String? ?? '',
    hasPersonalPhoto: j['has_personal_photo'] as bool? ?? false,
    birthdayDay: j['birthday_day'] as int? ?? 0,
    birthdayMonth: j['birthday_month'] as int? ?? 0,
    birthdayYear: j['birthday_year'] as int? ?? 0,
    personalChannelId: j['personal_channel_id'] as String? ?? '',
    personalChannelName: j['personal_channel_name'] as String? ?? '',
    voiceMessagesForbidden: j['voice_messages_forbidden'] as bool? ?? false,
    contactRequirePremium: j['contact_require_premium'] as bool? ?? false,
    businessHours: j['business_hours'] as String? ?? '',
    businessLocation: j['business_location'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    videoAvatarPath: j['video_avatar_path'] as String? ?? '',
  );
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
  final String gifSearchUsername;

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
    this.gifSearchUsername = 'gif',
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
    gifSearchUsername: j['gif_search_username'] as String? ?? 'gif',
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

class ConnectedBotInfo {
  final String botId;
  final String botName;
  final bool canReply;
  final bool excludeSelected;
  final bool existingChats;
  final bool newChats;
  final bool contacts;
  final bool nonContacts;
  final List<String> userIds;

  const ConnectedBotInfo({
    this.botId = '',
    this.botName = '',
    this.canReply = false,
    this.excludeSelected = false,
    this.existingChats = false,
    this.newChats = false,
    this.contacts = false,
    this.nonContacts = false,
    this.userIds = const [],
  });

  factory ConnectedBotInfo.fromJson(Map<String, dynamic> j) => ConnectedBotInfo(
    botId: j['bot_id'] as String? ?? '',
    botName: j['bot_name'] as String? ?? '',
    canReply: j['can_reply'] as bool? ?? false,
    excludeSelected: j['exclude_selected'] as bool? ?? false,
    existingChats: j['existing_chats'] as bool? ?? false,
    newChats: j['new_chats'] as bool? ?? false,
    contacts: j['contacts'] as bool? ?? false,
    nonContacts: j['non_contacts'] as bool? ?? false,
    userIds: (j['user_ids'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
  );

  bool appliesTo(String peerId, {required bool isContact}) {
    if (excludeSelected) {
      return !userIds.contains(peerId);
    }
    if (userIds.contains(peerId)) return true;
    if (existingChats) return true;
    if (contacts && isContact) return true;
    if (nonContacts && !isContact) return true;
    return false;
  }
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
  final Map<String, dynamic>? contentRaw;
  const MsgEditedEvent({this.accountId = '', this.chatId = '', this.msgId = '', this.newText = '', this.editedAt = 0, this.contentRaw});

  factory MsgEditedEvent.fromJson(Map<String, dynamic> j) => MsgEditedEvent(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    newText: safeStr(j['new_text'] as String? ?? ''),
    editedAt: j['edited_at'] as int? ?? 0,
    contentRaw: j['content_raw'] as Map<String, dynamic>?,
  );
}

class MsgDeletedEvent {
  final String accountId;
  final String chatId;
  final String msgId;
  final bool senderIsBot;
  const MsgDeletedEvent({this.accountId = '', this.chatId = '', this.msgId = '', this.senderIsBot = false});

  factory MsgDeletedEvent.fromJson(Map<String, dynamic> j) => MsgDeletedEvent(
    accountId: j['account_id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    msgId: j['msg_id'] as String? ?? '',
    senderIsBot: j['sender_is_bot'] as bool? ?? false,
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
  final String action;
  const TypingEvent({this.chatId = '', this.userId = '', this.userName = '', this.action = 'typing'});

  factory TypingEvent.fromJson(Map<String, dynamic> j) => TypingEvent(
    chatId: j['chat_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    userName: j['user_name'] as String? ?? '',
    action: j['action'] as String? ?? 'typing',
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
  final double audioLevel;

  const GroupCallParticipant({
    this.userId = '',
    this.displayName = '',
    this.isMuted = false,
    this.isSpeaking = false,
    this.hasVideo = false,
    this.avatarPath = '',
    this.audioLevel = 0.0,
  });

  factory GroupCallParticipant.fromJson(Map<String, dynamic> j) => GroupCallParticipant(
    userId: j['user_id'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    isMuted: j['is_muted'] as bool? ?? false,
    isSpeaking: j['is_speaking'] as bool? ?? false,
    hasVideo: j['has_video'] as bool? ?? false,
    avatarPath: j['avatar_path'] as String? ?? '',
    audioLevel: (j['audio_level'] as num?)?.toDouble() ?? 0.0,
  );
}

class GroupCallInfo {
  final String callId;
  final String chatId;
  final String title;
  final int participantsCount;
  final List<GroupCallParticipant> participants;
  final bool active;
  final bool isRtmp;

  const GroupCallInfo({
    this.callId = '',
    this.chatId = '',
    this.title = '',
    this.participantsCount = 0,
    this.participants = const [],
    this.active = false,
    this.isRtmp = false,
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
    isRtmp: j['is_rtmp'] as bool? ?? false,
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

// ── 1:1 Call events ──

class CallSessionInfo {
  final String id;
  final String chatId;
  final bool isVideo;
  final String state;
  final List<GroupCallParticipant> participants;
  final Map<String, String> meta;

  const CallSessionInfo({
    this.id = '',
    this.chatId = '',
    this.isVideo = false,
    this.state = '',
    this.participants = const [],
    this.meta = const {},
  });

  factory CallSessionInfo.fromJson(Map<String, dynamic> j) => CallSessionInfo(
    id: j['id'] as String? ?? '',
    chatId: j['chat_id'] as String? ?? '',
    isVideo: j['is_video'] as bool? ?? false,
    state: j['state'] as String? ?? '',
    participants: (j['participants'] as List<dynamic>?)
        ?.map((p) => GroupCallParticipant.fromJson(p as Map<String, dynamic>))
        .toList() ?? [],
    meta: (j['meta'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, v.toString())) ?? {},
  );
}

class IncomingCallEvent {
  final String accountId;
  final CallSessionInfo call;

  const IncomingCallEvent({
    this.accountId = '',
    this.call = const CallSessionInfo(),
  });
}

class CallStateEvent {
  final String accountId;
  final CallSessionInfo call;

  const CallStateEvent({
    this.accountId = '',
    this.call = const CallSessionInfo(),
  });
}

// ── Export events ──

class ExportProgressEvent {
  final String accountId;
  final String step;
  final int stepIndex;
  final int totalSteps;
  final double progress;
  final String info;
  final int totalFiles;
  final int totalSizeBytes;
  final int fileRandomId;
  final String fileName;

  const ExportProgressEvent({
    this.accountId = '',
    this.step = '',
    this.stepIndex = 0,
    this.totalSteps = 0,
    this.progress = 0.0,
    this.info = '',
    this.totalFiles = 0,
    this.totalSizeBytes = 0,
    this.fileRandomId = 0,
    this.fileName = '',
  });

  factory ExportProgressEvent.fromJson(Map<String, dynamic> j, {String accountId = ''}) => ExportProgressEvent(
    accountId: accountId,
    step: j['step'] as String? ?? '',
    stepIndex: j['step_index'] as int? ?? 0,
    totalSteps: j['total_steps'] as int? ?? 0,
    progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
    info: j['info'] as String? ?? '',
    totalFiles: j['total_files'] as int? ?? 0,
    totalSizeBytes: j['total_size_bytes'] as int? ?? 0,
    fileRandomId: j['file_random_id'] as int? ?? 0,
    fileName: j['file_name'] as String? ?? '',
  );
}

class ExportErrorEvent {
  final String accountId;
  final String errorType;
  final int code;
  final String errorName;
  final String description;
  final String path;
  final int hoursRemaining;
  final int availableAtMs;

  const ExportErrorEvent({
    this.accountId = '',
    this.errorType = '',
    this.code = 0,
    this.errorName = '',
    this.description = '',
    this.path = '',
    this.hoursRemaining = 0,
    this.availableAtMs = 0,
  });

  factory ExportErrorEvent.fromJson(Map<String, dynamic> j, {String accountId = ''}) => ExportErrorEvent(
    accountId: accountId,
    errorType: j['error_type'] as String? ?? '',
    code: j['code'] as int? ?? 0,
    errorName: j['error_name'] as String? ?? '',
    description: j['description'] as String? ?? '',
    path: j['path'] as String? ?? '',
    hoursRemaining: j['hours_remaining'] as int? ?? 0,
    availableAtMs: j['available_at_ms'] as int? ?? 0,
  );
}

class ExportCompleteEvent {
  final String accountId;
  final String exportPath;
  final int totalFiles;
  final int totalSizeBytes;

  const ExportCompleteEvent({
    this.accountId = '',
    this.exportPath = '',
    this.totalFiles = 0,
    this.totalSizeBytes = 0,
  });

  factory ExportCompleteEvent.fromJson(Map<String, dynamic> j, {String accountId = ''}) => ExportCompleteEvent(
    accountId: accountId,
    exportPath: j['export_path'] as String? ?? '',
    totalFiles: j['total_files'] as int? ?? 0,
    totalSizeBytes: j['total_size_bytes'] as int? ?? 0,
  );
}

class PersonalCallInfo {
  final String callId;
  final String peerId;
  final String peerName;
  final String peerFirstName;
  final String peerAvatarPath;
  final bool isMuted;
  final int signalQuality;
  final bool isConnecting;
  final DateTime startTime;

  const PersonalCallInfo({
    this.callId = '',
    this.peerId = '',
    this.peerName = '',
    this.peerFirstName = '',
    this.peerAvatarPath = '',
    this.isMuted = false,
    this.signalQuality = 4,
    this.isConnecting = false,
    required this.startTime,
  });

  PersonalCallInfo copyWith({
    bool? isMuted,
    int? signalQuality,
    bool? isConnecting,
  }) => PersonalCallInfo(
    callId: callId,
    peerId: peerId,
    peerName: peerName,
    peerFirstName: peerFirstName,
    peerAvatarPath: peerAvatarPath,
    isMuted: isMuted ?? this.isMuted,
    signalQuality: signalQuality ?? this.signalQuality,
    isConnecting: isConnecting ?? this.isConnecting,
    startTime: startTime,
  );
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

class WebPagePreview {
  final String url;
  final String siteName;
  final String title;
  final String description;
  final String thumbB64;
  final String type;
  final bool hasLargeMedia;
  final int pendingTill;

  const WebPagePreview({
    this.url = '',
    this.siteName = '',
    this.title = '',
    this.description = '',
    this.thumbB64 = '',
    this.type = '',
    this.hasLargeMedia = false,
    this.pendingTill = 0,
  });

  bool get isPending => pendingTill > 0;

  bool get defaultSmallMedia {
    if (type == 'profile') return true;
    if (type == 'twitter' || type == 'facebook') return false;
    if (title.isEmpty && description.isEmpty && siteName.isEmpty) return false;
    if (thumbB64.isNotEmpty && type != 'video' && type != 'gif' && type != 'document') return true;
    return false;
  }
}

// ── Sticker set info (for sticker pack viewer) ──

class StickerInfoItem {
  final String emoji;
  final String thumbB64;
  final int width;
  final int height;
  final String mimeType;
  final String fileId;
  final bool isFaved;

  const StickerInfoItem({
    this.emoji = '',
    this.thumbB64 = '',
    this.width = 0,
    this.height = 0,
    this.mimeType = '',
    this.fileId = '',
    this.isFaved = false,
  });

  StickerInfoItem copyWith({bool? isFaved}) => StickerInfoItem(
    emoji: emoji,
    thumbB64: thumbB64,
    width: width,
    height: height,
    mimeType: mimeType,
    fileId: fileId,
    isFaved: isFaved ?? this.isFaved,
  );
}

class GifInfoItem {
  final String thumbB64;
  final int width;
  final int height;
  final String mimeType;
  final String fileId;

  const GifInfoItem({
    this.thumbB64 = '',
    this.width = 0,
    this.height = 0,
    this.mimeType = '',
    this.fileId = '',
  });
}

class SendAsPeerInfo {
  final String peerId;
  final String displayName;
  final String avatarPath;
  final bool isChannel;

  const SendAsPeerInfo({
    this.peerId = '',
    this.displayName = '',
    this.avatarPath = '',
    this.isChannel = false,
  });
}

class AttachMenuBotInfo {
  final int botId;
  final String shortName;
  final bool inactive;

  const AttachMenuBotInfo({
    this.botId = 0,
    this.shortName = '',
    this.inactive = false,
  });
}

class StickerSetInfo {
  final String title;
  final String shortName;
  final int setId;
  final int accessHash;
  final int count;
  final bool installed;
  final bool archived;
  final bool animated;
  final bool video;
  final bool masks;
  final bool emojis;
  final List<StickerInfoItem> stickers;

  const StickerSetInfo({
    this.title = '',
    this.shortName = '',
    this.setId = 0,
    this.accessHash = 0,
    this.count = 0,
    this.installed = false,
    this.archived = false,
    this.animated = false,
    this.video = false,
    this.masks = false,
    this.emojis = false,
    this.stickers = const [],
  });
}

class CustomEmojiThumbData {
  final String thumbB64;
  final String pathB64;
  const CustomEmojiThumbData({required this.thumbB64, this.pathB64 = ''});
}

class CustomEmojiFileData {
  final String mimeType;
  final Uint8List fileData;
  const CustomEmojiFileData({required this.mimeType, required this.fileData});

  bool get isTgs => mimeType == 'application/x-tgsticker';
  bool get isWebm => mimeType == 'video/webm';
  bool get isWebp => mimeType == 'image/webp';
}

class CustomEmojiSetInfo {
  final int setId;
  final int accessHash;
  final String title;
  final String shortName;
  final int count;

  const CustomEmojiSetInfo({
    this.setId = 0,
    this.accessHash = 0,
    this.title = '',
    this.shortName = '',
    this.count = 0,
  });
}

class CustomEmojiSetSummary {
  final int setId;
  final int accessHash;
  final String title;
  final String shortName;
  final int count;
  final bool installed;
  final bool premium;
  final List<StickerInfoItem> stickers;

  const CustomEmojiSetSummary({
    this.setId = 0,
    this.accessHash = 0,
    this.title = '',
    this.shortName = '',
    this.count = 0,
    this.installed = false,
    this.premium = false,
    this.stickers = const [],
  });
}

class StickerPackSummary {
  final int setId;
  final int accessHash;
  final String title;
  final String shortName;
  final int count;
  final bool animated;
  final bool video;
  final String thumbB64;
  final List<StickerInfoItem> stickers;
  final bool installed;

  const StickerPackSummary({
    this.setId = 0,
    this.accessHash = 0,
    this.title = '',
    this.shortName = '',
    this.count = 0,
    this.animated = false,
    this.video = false,
    this.thumbB64 = '',
    this.stickers = const [],
    this.installed = false,
  });
}

class InlineBotResult {
  final String id;
  final String type;
  final String title;
  final String description;
  final String thumbUrl;
  final String contentUrl;
  final int thumbW;
  final int thumbH;
  final String thumbB64;

  const InlineBotResult({
    this.id = '',
    this.type = '',
    this.title = '',
    this.description = '',
    this.thumbUrl = '',
    this.contentUrl = '',
    this.thumbW = 0,
    this.thumbH = 0,
    this.thumbB64 = '',
  });

  factory InlineBotResult.fromJson(Map<String, dynamic> json) {
    return InlineBotResult(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      thumbUrl: json['thumb_url'] as String? ?? '',
      contentUrl: json['content_url'] as String? ?? '',
      thumbW: json['thumb_w'] as int? ?? 0,
      thumbH: json['thumb_h'] as int? ?? 0,
      thumbB64: json['thumb_b64'] as String? ?? '',
    );
  }
}

class InlineBotResults {
  final int queryId;
  final String nextOffset;
  final bool gallery;
  final List<InlineBotResult> results;
  final String switchPM;
  final String switchPMParam;

  const InlineBotResults({
    this.queryId = 0,
    this.nextOffset = '',
    this.gallery = false,
    this.results = const [],
    this.switchPM = '',
    this.switchPMParam = '',
  });

  factory InlineBotResults.fromJson(Map<String, dynamic> json) {
    return InlineBotResults(
      queryId: json['query_id'] as int? ?? 0,
      nextOffset: json['next_offset'] as String? ?? '',
      gallery: json['gallery'] as bool? ?? false,
      results: (json['results'] as List<dynamic>?)
          ?.map((e) => InlineBotResult.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      switchPM: json['switch_pm'] as String? ?? '',
      switchPMParam: json['switch_pm_param'] as String? ?? '',
    );
  }
}

class StarGiftItem {
  final int id;
  final int stars;
  final String title;
  final bool limited;
  final bool soldOut;
  final bool birthday;
  final int remaining;
  final int total;
  final String thumbB64;

  const StarGiftItem({
    this.id = 0,
    this.stars = 0,
    this.title = '',
    this.limited = false,
    this.soldOut = false,
    this.birthday = false,
    this.remaining = 0,
    this.total = 0,
    this.thumbB64 = '',
  });

  factory StarGiftItem.fromJson(Map<String, dynamic> json) => StarGiftItem(
    id: json['id'] as int? ?? 0,
    stars: json['stars'] as int? ?? 0,
    title: json['title'] as String? ?? '',
    limited: json['limited'] as bool? ?? false,
    soldOut: json['sold_out'] as bool? ?? false,
    birthday: json['birthday'] as bool? ?? false,
    remaining: json['remaining'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
    thumbB64: json['thumb_b64'] as String? ?? '',
  );
}

class StarGiftsResult {
  final List<StarGiftItem> gifts;

  const StarGiftsResult({this.gifts = const []});

  factory StarGiftsResult.fromJson(Map<String, dynamic> json) => StarGiftsResult(
    gifts: (json['gifts'] as List<dynamic>?)
        ?.map((e) => StarGiftItem.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
  );
}

class PinnedGiftItem {
  final int id;
  final String thumbB64;

  const PinnedGiftItem({this.id = 0, this.thumbB64 = ''});

  factory PinnedGiftItem.fromJson(Map<String, dynamic> json) => PinnedGiftItem(
    id: json['id'] as int? ?? 0,
    thumbB64: json['thumb_b64'] as String? ?? '',
  );
}

class PinnedGiftsResult {
  final List<PinnedGiftItem> gifts;

  const PinnedGiftsResult({this.gifts = const []});

  factory PinnedGiftsResult.fromJson(Map<String, dynamic> json) => PinnedGiftsResult(
    gifts: (json['gifts'] as List<dynamic>?)
        ?.map((e) => PinnedGiftItem.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
  );
}

class ReportOptionItem {
  final String text;
  final List<int> option;

  const ReportOptionItem({required this.text, required this.option});
}

class ReportMessageResult {
  final String resultType;
  final String title;
  final List<ReportOptionItem> options;
  final bool commentOptional;
  final List<int> commentOption;

  const ReportMessageResult({
    required this.resultType,
    this.title = '',
    this.options = const [],
    this.commentOptional = false,
    this.commentOption = const [],
  });
}

class CloudThemeInfo {
  final int id;
  final String title;
  final String slug;
  final bool isCreator;
  final int accentColor;
  final int bgColor;
  final int sentColor;
  final int recvColor;
  final bool isDark;

  const CloudThemeInfo({
    required this.id,
    required this.title,
    required this.slug,
    this.isCreator = false,
    this.accentColor = 0,
    this.bgColor = 0,
    this.sentColor = 0,
    this.recvColor = 0,
    this.isDark = false,
  });

  factory CloudThemeInfo.fromJson(Map<String, dynamic> json) => CloudThemeInfo(
    id: (json['id'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    isCreator: json['is_creator'] as bool? ?? false,
    accentColor: (json['accent_color'] as num?)?.toInt() ?? 0,
    bgColor: (json['bg_color'] as num?)?.toInt() ?? 0,
    sentColor: (json['sent_color'] as num?)?.toInt() ?? 0,
    recvColor: (json['recv_color'] as num?)?.toInt() ?? 0,
    isDark: json['is_dark'] as bool? ?? false,
  );
}

enum StoryPrivacy { public, closeFriends, contacts, selectedContacts }

class StoryMediaAreaCoords {
  final double x, y, w, h, rotation, radius;
  const StoryMediaAreaCoords({
    this.x = 0, this.y = 0, this.w = 0, this.h = 0,
    this.rotation = 0, this.radius = 0,
  });
  factory StoryMediaAreaCoords.fromJson(Map<String, dynamic> j) =>
      StoryMediaAreaCoords(
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 0,
        h: (j['h'] as num?)?.toDouble() ?? 0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
        radius: (j['radius'] as num?)?.toDouble() ?? 0,
      );
}

enum StoryMediaAreaType { venue, location, reaction, channelPost, url, weather, unknown }

class StoryMediaArea {
  final StoryMediaAreaType type;
  final StoryMediaAreaCoords coords;
  final double lat, lng;
  final String title, address, emoji, reaction, url;
  final bool flipped, dark;
  final int channelId, msgId, color;
  final double tempC;

  const StoryMediaArea({
    required this.type,
    required this.coords,
    this.lat = 0, this.lng = 0,
    this.title = '', this.address = '', this.emoji = '',
    this.reaction = '', this.url = '',
    this.flipped = false, this.dark = false,
    this.channelId = 0, this.msgId = 0, this.color = 0,
    this.tempC = 0,
  });

  factory StoryMediaArea.fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'] as String? ?? '';
    final type = switch (typeStr) {
      'venue' => StoryMediaAreaType.venue,
      'location' => StoryMediaAreaType.location,
      'reaction' => StoryMediaAreaType.reaction,
      'channel_post' => StoryMediaAreaType.channelPost,
      'url' => StoryMediaAreaType.url,
      'weather' => StoryMediaAreaType.weather,
      _ => StoryMediaAreaType.unknown,
    };
    return StoryMediaArea(
      type: type,
      coords: StoryMediaAreaCoords.fromJson(
          j['coords'] as Map<String, dynamic>? ?? {}),
      lat: (j['lat'] as num?)?.toDouble() ?? 0,
      lng: (j['lng'] as num?)?.toDouble() ?? 0,
      title: j['title'] as String? ?? '',
      address: j['address'] as String? ?? '',
      emoji: j['emoji'] as String? ?? '',
      reaction: j['reaction'] as String? ?? '',
      url: j['url'] as String? ?? '',
      flipped: j['flipped'] as bool? ?? false,
      dark: j['dark'] as bool? ?? false,
      channelId: (j['channel_id'] as num?)?.toInt() ?? 0,
      msgId: (j['msg_id'] as num?)?.toInt() ?? 0,
      color: (j['color'] as num?)?.toInt() ?? 0,
      tempC: (j['temp_c'] as num?)?.toDouble() ?? 0,
    );
  }
}

class StoryItem {
  final int id;
  final int date;
  final String caption;
  final String mediaType;
  final String localPath;
  final String thumbB64;
  final int width;
  final int height;
  final int duration;
  final int views;
  final bool pinned;
  final bool edited;
  final StoryPrivacy privacy;
  final String fwdFromName;
  final String fwdFromPeerId;
  final int fwdStoryId;
  final bool fwdModified;
  final List<StoryMediaArea> mediaAreas;

  const StoryItem({
    required this.id,
    required this.date,
    this.caption = '',
    this.mediaType = 'photo',
    this.localPath = '',
    this.thumbB64 = '',
    this.width = 0,
    this.height = 0,
    this.duration = 0,
    this.views = 0,
    this.pinned = false,
    this.edited = false,
    this.privacy = StoryPrivacy.public,
    this.fwdFromName = '',
    this.fwdFromPeerId = '',
    this.fwdStoryId = 0,
    this.fwdModified = false,
    this.mediaAreas = const [],
  });

  bool get isVideo => mediaType == 'video';
  bool get hasMedia => localPath.isNotEmpty;
  bool get isRepost => fwdFromName.isNotEmpty || fwdFromPeerId.isNotEmpty;

  factory StoryItem.fromJson(Map<String, dynamic> j) {
    final fileRef = j['file_ref'] as Map<String, dynamic>? ?? {};
    final privStr = j['privacy'] as String? ?? 'public';
    final priv = switch (privStr) {
      'close_friends' => StoryPrivacy.closeFriends,
      'contacts' => StoryPrivacy.contacts,
      'selected_contacts' => StoryPrivacy.selectedContacts,
      _ => StoryPrivacy.public,
    };
    return StoryItem(
      id: (j['id'] as num?)?.toInt() ?? 0,
      date: (j['date'] as num?)?.toInt() ?? 0,
      caption: j['caption'] as String? ?? '',
      mediaType: j['media_type'] as String? ?? 'photo',
      localPath: j['local_path'] as String? ?? '',
      thumbB64: fileRef['thumb_b64'] as String? ?? '',
      width: (fileRef['width'] as num?)?.toInt() ?? 0,
      height: (fileRef['height'] as num?)?.toInt() ?? 0,
      duration: (fileRef['duration'] as num?)?.toInt() ?? 0,
      views: (j['views'] as num?)?.toInt() ?? 0,
      pinned: j['pinned'] as bool? ?? false,
      edited: j['edited'] as bool? ?? false,
      privacy: priv,
      fwdFromName: j['fwd_from_name'] as String? ?? '',
      fwdFromPeerId: j['fwd_from_peer_id'] as String? ?? '',
      fwdStoryId: (j['fwd_story_id'] as num?)?.toInt() ?? 0,
      fwdModified: j['fwd_modified'] as bool? ?? false,
      mediaAreas: (j['media_areas'] as List<dynamic>?)
              ?.map((e) =>
                  StoryMediaArea.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class StoryAlbumInfo {
  final int id;
  final String title;
  final int count;

  const StoryAlbumInfo({
    required this.id,
    required this.title,
    this.count = 0,
  });
}

// ── Scheduled messages ──

enum SendMenuType {
  scheduled,
  scheduledToUser,
  reminder,
  silentOnly,
}

class ScheduledMessages {
  ScheduledMessages._();

  static const int kScheduledUntilOnlineTimestamp = 0x7FFFFFFE;
  static const int kMinimalScheduleSeconds = 10;
  static const int kMaxScheduleHorizonDays = 365;
  static const int kRequestTimeLimitMs = 60000;

  static bool isScheduledMsgId(int id) => id > _kServerMaxMsgId;

  static const int _kServerMaxMsgId = 1 << 56;

  static bool canScheduleUntilOnline(ChatInfo peer) {
    return peer.type == ChatType.dm;
  }

  static SendMenuType menuTypeForChat(ChatInfo chat, String selfId) {
    if (chat.chatId == selfId) return SendMenuType.reminder;
    if (chat.type == ChatType.dm) return SendMenuType.scheduledToUser;
    return SendMenuType.scheduled;
  }

  static DateTime defaultScheduleTime() =>
      DateTime.now().add(const Duration(seconds: 600));

  static DateTime clampScheduleTime(DateTime dt) {
    final now = DateTime.now();
    final min = now.add(const Duration(seconds: kMinimalScheduleSeconds));
    final max = now.add(const Duration(days: kMaxScheduleHorizonDays));
    if (dt.isBefore(min)) return min;
    if (dt.isAfter(max)) return max;
    return dt;
  }

  static const List<ScheduleRepeatOption> repeatOptions = [
    ScheduleRepeatOption(0, 'Never'),
    ScheduleRepeatOption(86400, 'Daily'),
    ScheduleRepeatOption(604800, 'Weekly'),
    ScheduleRepeatOption(1209600, 'Every 2 weeks'),
    ScheduleRepeatOption(2592000, 'Monthly'),
    ScheduleRepeatOption(7862400, 'Every 3 months'),
    ScheduleRepeatOption(15724800, 'Every 6 months'),
    ScheduleRepeatOption(31536000, 'Yearly'),
  ];
}

class ScheduleRepeatOption {
  final int periodSeconds;
  final String label;
  const ScheduleRepeatOption(this.periodSeconds, this.label);
}

class ChatThemeData {
  final String emoticon;
  final int id;
  final bool isDark;
  final int accentColor;
  final List<int> messageColors;
  final List<int> bgColors;

  const ChatThemeData({
    required this.emoticon,
    required this.id,
    this.isDark = false,
    this.accentColor = 0,
    this.messageColors = const [],
    this.bgColors = const [],
  });

  factory ChatThemeData.fromJson(Map<String, dynamic> j) => ChatThemeData(
    emoticon: j['emoticon'] as String? ?? '',
    id: (j['id'] as num?)?.toInt() ?? 0,
    isDark: j['is_dark'] as bool? ?? false,
    accentColor: (j['accent_color'] as num?)?.toInt() ?? 0,
    messageColors: (j['message_colors'] as List<dynamic>?)
        ?.map((e) => (e as num).toInt()).toList() ?? const [],
    bgColors: (j['bg_colors'] as List<dynamic>?)
        ?.map((e) => (e as num).toInt()).toList() ?? const [],
  );
}

class SavedSublistInfo {
  final String peerId;
  final String peerName;
  final String avatarPath;
  final int type; // 1=DM, 2=group, 3=channel
  final bool isPinned;
  final int topMessage;
  final String lastMsgText;
  final int lastMsgTime;
  final bool isSelf;
  final int unreadCount;

  const SavedSublistInfo({
    required this.peerId,
    required this.peerName,
    this.avatarPath = '',
    this.type = 1,
    this.isPinned = false,
    this.topMessage = 0,
    this.lastMsgText = '',
    this.lastMsgTime = 0,
    this.isSelf = false,
    this.unreadCount = 0,
  });
}

class SavedReactionTagInfo {
  final String emoji;
  final int customId;
  final String title;
  final int count;

  const SavedReactionTagInfo({
    this.emoji = '',
    this.customId = 0,
    this.title = '',
    this.count = 0,
  });

  bool get isCustomEmoji => customId != 0;
}

class CallHistoryEntry {
  final String msgId;
  final String peerId;
  final String peerName;
  final String avatarPath;
  final int timestamp;
  final int duration;
  final bool isOutgoing;
  final bool isMissed;
  final bool isVideo;

  const CallHistoryEntry({
    required this.msgId,
    this.peerId = '',
    this.peerName = '',
    this.avatarPath = '',
    this.timestamp = 0,
    this.duration = 0,
    this.isOutgoing = false,
    this.isMissed = false,
    this.isVideo = false,
  });

  factory CallHistoryEntry.fromJson(Map<String, dynamic> j) => CallHistoryEntry(
    msgId: j['msg_id'] as String? ?? '',
    peerId: j['peer_id'] as String? ?? '',
    peerName: j['peer_name'] as String? ?? '',
    avatarPath: j['avatar_path'] as String? ?? '',
    timestamp: j['timestamp'] as int? ?? 0,
    duration: j['duration'] as int? ?? 0,
    isOutgoing: j['is_outgoing'] as bool? ?? false,
    isMissed: j['is_missed'] as bool? ?? false,
    isVideo: j['is_video'] as bool? ?? false,
  );
}

class EmojiKeywordEntry {
  final String keyword;
  final List<String> emoticons;
  const EmojiKeywordEntry({required this.keyword, required this.emoticons});

  factory EmojiKeywordEntry.fromJson(Map<String, dynamic> j) => EmojiKeywordEntry(
    keyword: j['keyword'] as String? ?? '',
    emoticons: (j['emoticons'] as List<dynamic>?)?.cast<String>() ?? const [],
  );
}

class EmojiKeywordsResult {
  final String langCode;
  final int version;
  final List<EmojiKeywordEntry> keywords;
  const EmojiKeywordsResult({required this.langCode, required this.version, required this.keywords});

  factory EmojiKeywordsResult.fromJson(Map<String, dynamic> j) => EmojiKeywordsResult(
    langCode: j['lang_code'] as String? ?? '',
    version: j['version'] as int? ?? 0,
    keywords: (j['keywords'] as List<dynamic>?)
        ?.map((e) => EmojiKeywordEntry.fromJson(e as Map<String, dynamic>))
        .toList() ?? const [],
  );
}
