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
  final String avatarPath;
  final bool isMuted;
  final bool isOutgoing;
  final bool isChannel;
  final bool isGroup;
  final bool isSilent;
  final int timestamp;

  const NotificationData({
    required this.accountId,
    required this.chatId,
    this.messageId = '',
    this.senderName = '',
    this.chatTitle = '',
    this.text = '',
    this.avatarPath = '',
    this.isMuted = false,
    this.isOutgoing = false,
    this.isChannel = false,
    this.isGroup = false,
    this.isSilent = false,
    this.timestamp = 0,
  });
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
      corner: corner ?? this.corner,
      maxNotificationCount: maxNotificationCount ?? this.maxNotificationCount,
      displayIndex: displayIndex ?? this.displayIndex,
    );
  }
}
