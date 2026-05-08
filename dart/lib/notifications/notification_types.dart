enum ManagerType { native, defaultPopup, dummy }

enum NotificationCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  topCenter,
}

enum PrivacyLevel { showPreview, showName, hideAll }

class NotificationData {
  final String accountId;
  final String chatId;
  final String messageId;
  final String senderName;
  final String chatTitle;
  final String text;
  final String subtitle;
  final String avatarPath;
  final bool isMuted;
  final bool isOutgoing;
  final bool isChannel;
  final bool isGroup;
  final bool isSilent;
  final int timestamp;

  final int messageType; // 0=none, 1=image, 2=video, 3=audio, 4=voice, 5=videonote, 6=sticker, 7=gif, 8=file, 9=poll, 10=location, 11=contact, 12=invoice
  final bool isScheduled;
  final bool isForumTopic;
  final String topicTitle;
  final String forwardFrom;
  final int forwardCount;
  final String stickerEmoji;
  final bool hasSpoiler;
  final String caption;
  final bool isReaction;
  final String reactionEmoji;
  final String reactorName;
  final int reactedToType; // media type of the message being reacted to
  final String accountUsername;
  final bool multiAccount;
  final String pollQuestion;
  final String gameTitle;
  final String invoiceTitle;
  final String contactName;
  final bool isLiveLocation;
  final String soundDocumentPath;
  final bool soundNone;
  final int perChatVolume;
  final String groupedId;
  final bool isPollVote;
  final bool isSenderMuted;
  final bool slowmodeActive;
  final bool requiresStars;
  final bool spoilerLoginCode;
  final bool isMonoforumSublist;
  final String sublistPeerName;
  final String topicRootId;
  final String sublistPeerId;
  final bool hideMarkAsRead;

  const NotificationData({
    required this.accountId,
    required this.chatId,
    this.messageId = '',
    this.senderName = '',
    this.chatTitle = '',
    this.text = '',
    this.subtitle = '',
    this.avatarPath = '',
    this.isMuted = false,
    this.isOutgoing = false,
    this.isChannel = false,
    this.isGroup = false,
    this.isSilent = false,
    this.timestamp = 0,
    this.messageType = 0,
    this.isScheduled = false,
    this.isForumTopic = false,
    this.topicTitle = '',
    this.forwardFrom = '',
    this.forwardCount = 0,
    this.stickerEmoji = '',
    this.hasSpoiler = false,
    this.caption = '',
    this.isReaction = false,
    this.reactionEmoji = '',
    this.reactorName = '',
    this.reactedToType = 0,
    this.accountUsername = '',
    this.multiAccount = false,
    this.pollQuestion = '',
    this.gameTitle = '',
    this.invoiceTitle = '',
    this.contactName = '',
    this.isLiveLocation = false,
    this.soundDocumentPath = '',
    this.soundNone = false,
    this.perChatVolume = 100,
    this.groupedId = '',
    this.isPollVote = false,
    this.isSenderMuted = false,
    this.slowmodeActive = false,
    this.requiresStars = false,
    this.spoilerLoginCode = false,
    this.isMonoforumSublist = false,
    this.sublistPeerName = '',
    this.topicRootId = '',
    this.sublistPeerId = '',
    this.hideMarkAsRead = false,
  });

  NotificationData copyWith({
    String? accountId,
    String? chatId,
    String? messageId,
    String? senderName,
    String? chatTitle,
    String? text,
    String? subtitle,
    String? avatarPath,
    bool? isMuted,
    bool? isOutgoing,
    bool? isChannel,
    bool? isGroup,
    bool? isSilent,
    int? timestamp,
    int? messageType,
    bool? isScheduled,
    bool? isForumTopic,
    String? topicTitle,
    String? forwardFrom,
    int? forwardCount,
    String? stickerEmoji,
    bool? hasSpoiler,
    String? caption,
    bool? isReaction,
    String? reactionEmoji,
    String? reactorName,
    int? reactedToType,
    String? accountUsername,
    bool? multiAccount,
    String? pollQuestion,
    String? gameTitle,
    String? invoiceTitle,
    String? contactName,
    bool? isLiveLocation,
    String? soundDocumentPath,
    bool? soundNone,
    int? perChatVolume,
    String? groupedId,
    bool? isPollVote,
    bool? isSenderMuted,
    bool? slowmodeActive,
    bool? requiresStars,
    bool? spoilerLoginCode,
    bool? isMonoforumSublist,
    String? sublistPeerName,
    String? topicRootId,
    String? sublistPeerId,
    bool? hideMarkAsRead,
  }) {
    return NotificationData(
      accountId: accountId ?? this.accountId,
      chatId: chatId ?? this.chatId,
      messageId: messageId ?? this.messageId,
      senderName: senderName ?? this.senderName,
      chatTitle: chatTitle ?? this.chatTitle,
      text: text ?? this.text,
      subtitle: subtitle ?? this.subtitle,
      avatarPath: avatarPath ?? this.avatarPath,
      isMuted: isMuted ?? this.isMuted,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isChannel: isChannel ?? this.isChannel,
      isGroup: isGroup ?? this.isGroup,
      isSilent: isSilent ?? this.isSilent,
      timestamp: timestamp ?? this.timestamp,
      messageType: messageType ?? this.messageType,
      isScheduled: isScheduled ?? this.isScheduled,
      isForumTopic: isForumTopic ?? this.isForumTopic,
      topicTitle: topicTitle ?? this.topicTitle,
      forwardFrom: forwardFrom ?? this.forwardFrom,
      forwardCount: forwardCount ?? this.forwardCount,
      stickerEmoji: stickerEmoji ?? this.stickerEmoji,
      hasSpoiler: hasSpoiler ?? this.hasSpoiler,
      caption: caption ?? this.caption,
      isReaction: isReaction ?? this.isReaction,
      reactionEmoji: reactionEmoji ?? this.reactionEmoji,
      reactorName: reactorName ?? this.reactorName,
      reactedToType: reactedToType ?? this.reactedToType,
      accountUsername: accountUsername ?? this.accountUsername,
      multiAccount: multiAccount ?? this.multiAccount,
      pollQuestion: pollQuestion ?? this.pollQuestion,
      gameTitle: gameTitle ?? this.gameTitle,
      invoiceTitle: invoiceTitle ?? this.invoiceTitle,
      contactName: contactName ?? this.contactName,
      isLiveLocation: isLiveLocation ?? this.isLiveLocation,
      soundDocumentPath: soundDocumentPath ?? this.soundDocumentPath,
      soundNone: soundNone ?? this.soundNone,
      perChatVolume: perChatVolume ?? this.perChatVolume,
      groupedId: groupedId ?? this.groupedId,
      isPollVote: isPollVote ?? this.isPollVote,
      isSenderMuted: isSenderMuted ?? this.isSenderMuted,
      slowmodeActive: slowmodeActive ?? this.slowmodeActive,
      requiresStars: requiresStars ?? this.requiresStars,
      spoilerLoginCode: spoilerLoginCode ?? this.spoilerLoginCode,
      isMonoforumSublist: isMonoforumSublist ?? this.isMonoforumSublist,
      sublistPeerName: sublistPeerName ?? this.sublistPeerName,
      topicRootId: topicRootId ?? this.topicRootId,
      sublistPeerId: sublistPeerId ?? this.sublistPeerId,
      hideMarkAsRead: hideMarkAsRead ?? this.hideMarkAsRead,
    );
  }
}

const _appName = 'UniClient';
const _spoilerBlock = '▚';
final _loginCodePattern = RegExp(r'(?<![\w\-#])(\d[\d\-]{2,6}\d)(?!\w|\-)');


class NotificationContent {
  final String title;
  final String subtitle;
  final String body;

  const NotificationContent({
    required this.title,
    required this.subtitle,
    required this.body,
  });
}

NotificationContent composeNotificationContent(
  NotificationData data,
  NotificationSettings settings,
) {
  final title = _composeTitle(data, settings);
  final subtitle = _composeSubtitle(data, settings);
  final body = _composeBody(data, settings);
  return NotificationContent(title: title, subtitle: subtitle, body: body);
}

String _composeTitle(NotificationData data, NotificationSettings settings) {
  if (!settings.previewName) return _appName;

  String title;
  if (data.isScheduled && data.isOutgoing) {
    title = 'Reminder';
  } else if (data.isMonoforumSublist && data.sublistPeerName.isNotEmpty) {
    title = '${data.sublistPeerName} (${data.chatTitle})';
  } else if (data.isForumTopic && data.topicTitle.isNotEmpty) {
    title = '${data.topicTitle} (${data.chatTitle})';
  } else {
    title = data.chatTitle.isNotEmpty ? data.chatTitle : data.senderName;
  }

  if (data.isScheduled && !data.isOutgoing) {
    title = '\u{1F4C5} $title';
  }

  if (data.multiAccount && data.accountUsername.isNotEmpty) {
    title = '$title ➜ ${data.accountUsername}';
  }

  return title;
}

String _composeSubtitle(NotificationData data, NotificationSettings settings) {
  if (!settings.previewName) return '';

  if (data.isReaction && data.reactorName.isNotEmpty) {
    return data.reactorName;
  }

  if (data.isGroup || data.isChannel) {
    if (data.isScheduled && data.isOutgoing) return 'You';
    return data.senderName;
  }

  return '';
}

String _composeBody(NotificationData data, NotificationSettings settings) {
  if (!settings.previewText) return 'You have a new message';

  if (data.isReaction) return _composeReactionText(data);

  if (data.forwardCount > 1) {
    return '${data.forwardCount} forwarded messages';
  }
  if (data.forwardFrom.isNotEmpty && data.forwardCount <= 1) {
    final fwdText = _messageTextForType(data);
    return '➡️ $fwdText';
  }

  var text = _messageTextForType(data);
  if (data.spoilerLoginCode) {
    text = _maskLoginCodes(text);
  }
  return text;
}

String _messageTextForType(NotificationData data) {
  switch (data.messageType) {
    case 1: // image
      return data.caption.isNotEmpty ? 'Photo, ${_applySpoiler(data.caption, data.hasSpoiler)}' : 'Photo';
    case 2: // video
      return data.caption.isNotEmpty ? 'Video, ${_applySpoiler(data.caption, data.hasSpoiler)}' : 'Video';
    case 3: // audio
      return 'Audio file';
    case 4: // voice
      return 'Voice message';
    case 5: // videonote
      return 'Video message';
    case 6: // sticker
      if (data.stickerEmoji.isNotEmpty) {
        return '${data.stickerEmoji} Sticker';
      }
      return 'Sticker';
    case 7: // gif
      return 'GIF';
    case 8: // file
      return 'File';
    case 9: // poll
      return data.pollQuestion.isNotEmpty
          ? '\u{1F4CA} ${data.pollQuestion}'
          : 'Poll';
    case 10: // location
      return data.isLiveLocation ? 'Live location' : 'Location';
    case 11: // contact
      return data.contactName.isNotEmpty
          ? 'Contact: ${data.contactName}'
          : 'Contact';
    case 12: // invoice
      return data.invoiceTitle.isNotEmpty ? data.invoiceTitle : 'Invoice';
    default:
      return _applySpoiler(data.text, data.hasSpoiler);
  }
}

String _applySpoiler(String text, bool hasSpoiler) {
  if (!hasSpoiler || text.isEmpty) return text;
  return _spoilerBlock * text.length.clamp(1, 40);
}

String _maskLoginCodes(String text) {
  return text.replaceAllMapped(_loginCodePattern, (m) {
    return _spoilerBlock * m.group(0)!.length;
  });
}

String _composeReactionText(NotificationData data) {
  final emoji = data.reactionEmoji;
  if (emoji.isEmpty) return '';

  switch (data.reactedToType) {
    case 1: return '$emoji to your photo';
    case 2: return '$emoji to your video';
    case 3: return '$emoji to your file';
    case 4: return '$emoji to your voice message';
    case 5: return '$emoji to your video message';
    case 6:
      if (data.stickerEmoji.isNotEmpty) {
        return '$emoji to your ${data.stickerEmoji} sticker';
      }
      return '$emoji to your sticker';
    case 7: return '$emoji to your GIF';
    case 8: return '$emoji to your file';
    case 9: return '$emoji to your poll';
    case 10: return '$emoji to your location';
    case 11:
      if (data.contactName.isNotEmpty) {
        return '$emoji to contact: ${data.contactName}';
      }
      return '$emoji to your contact';
    case 12: return '$emoji to your invoice';
    default:
      if (data.text.isNotEmpty) {
        return '$emoji to: ${data.text}';
      }
      return emoji;
  }
}

class NotificationSettings {
  final bool desktopNotify;
  final bool allowSound;
  final int volume;
  final bool flashBounce;
  final bool previewName;
  final bool previewText;
  final bool privateChatsNotify;
  final bool groupsNotify;
  final bool channelsNotify;
  final bool reactionsNotify;
  final bool includeMutedChats;
  final bool countUnreadMessages;
  final bool useNativeNotifications;
  final bool forceCustomNotifications;
  final bool disableNotificationsDelay;
  final bool hideReplyButton;
  final NotificationCorner corner;
  final int maxNotificationCount;
  final int displayIndex;

  const NotificationSettings({
    this.desktopNotify = true,
    this.allowSound = true,
    this.volume = 100,
    this.flashBounce = true,
    this.previewName = true,
    this.previewText = true,
    this.privateChatsNotify = true,
    this.groupsNotify = true,
    this.channelsNotify = true,
    this.reactionsNotify = true,
    this.includeMutedChats = true,
    this.countUnreadMessages = true,
    this.useNativeNotifications = true,
    this.forceCustomNotifications = false,
    this.disableNotificationsDelay = false,
    this.hideReplyButton = false,
    this.corner = NotificationCorner.bottomRight,
    this.maxNotificationCount = 3,
    this.displayIndex = 0,
  });

  NotificationSettings copyWith({
    bool? desktopNotify,
    bool? allowSound,
    int? volume,
    bool? flashBounce,
    bool? previewName,
    bool? previewText,
    bool? privateChatsNotify,
    bool? groupsNotify,
    bool? channelsNotify,
    bool? reactionsNotify,
    bool? includeMutedChats,
    bool? countUnreadMessages,
    bool? useNativeNotifications,
    bool? forceCustomNotifications,
    bool? disableNotificationsDelay,
    bool? hideReplyButton,
    NotificationCorner? corner,
    int? maxNotificationCount,
    int? displayIndex,
  }) {
    return NotificationSettings(
      desktopNotify: desktopNotify ?? this.desktopNotify,
      allowSound: allowSound ?? this.allowSound,
      volume: volume ?? this.volume,
      flashBounce: flashBounce ?? this.flashBounce,
      previewName: previewName ?? this.previewName,
      previewText: previewText ?? this.previewText,
      privateChatsNotify: privateChatsNotify ?? this.privateChatsNotify,
      groupsNotify: groupsNotify ?? this.groupsNotify,
      channelsNotify: channelsNotify ?? this.channelsNotify,
      reactionsNotify: reactionsNotify ?? this.reactionsNotify,
      includeMutedChats: includeMutedChats ?? this.includeMutedChats,
      countUnreadMessages: countUnreadMessages ?? this.countUnreadMessages,
      useNativeNotifications:
          useNativeNotifications ?? this.useNativeNotifications,
      forceCustomNotifications:
          forceCustomNotifications ?? this.forceCustomNotifications,
      disableNotificationsDelay:
          disableNotificationsDelay ?? this.disableNotificationsDelay,
      hideReplyButton: hideReplyButton ?? this.hideReplyButton,
      corner: corner ?? this.corner,
      maxNotificationCount: maxNotificationCount ?? this.maxNotificationCount,
      displayIndex: displayIndex ?? this.displayIndex,
    );
  }
}

bool shouldHideReplyButton(
  NotificationData data,
  NotificationSettings settings, {
  bool isPasscodeLocked = false,
}) {
  if (settings.hideReplyButton) return true;
  if (isPasscodeLocked) return true;
  if (!settings.previewText) return true;
  if (data.isReaction || data.isPollVote) return true;
  if (data.messageId.isEmpty) return true;
  if (data.isScheduled && data.isOutgoing) return true;
  if (data.isChannel) return true;
  if (data.slowmodeActive) return true;
  if (data.requiresStars) return true;
  return false;
}
