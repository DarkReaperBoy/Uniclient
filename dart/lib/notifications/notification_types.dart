import 'dart:convert';

import '../l10n/strings.dart';

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
  // Carries the COMPOSED subtitle from NotificationSystem._dispatch() to the
  // managers (NativeManager/DefaultManager read it to render the second line).
  // Composition derives it from senderName via _composeSubtitle(), so it is left
  // empty at construction and filled in _dispatch() — not a dead field.
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
  // Per-chat ringtone volume OVERRIDE (0 = no override -> use the global
  // notification volume). Mirrors AyuGram ringtoneVolume(peer, ...), which is 0
  // unless the peer has a custom ringtone volume. (notifications_manager.cpp:763-775)
  final int perChatVolume;
  final String groupedId;
  final bool isPollVote;
  final bool isSenderMuted;
  // Whether this message personally mentions me in a group/channel (AyuGram's
  // mentionsMe() && !peer->isUser()). A mention pierces a muted chat: the
  // notify-by peer becomes the sender, so the chat mute is bypassed unless the
  // sender itself is individually muted ([isSenderMuted]).
  // (notifications_manager.cpp:337-369, specialNotificationPeer)
  final bool mentionsMe;
  final bool slowmodeActive;
  final bool requiresStars;
  final bool spoilerLoginCode;
  final bool isMonoforumSublist;
  final String sublistPeerName;
  final String topicRootId;
  final String sublistPeerId;
  final bool hideMarkAsRead;
  final bool muteStateUnknown;
  final String pollVoteOption;
  final bool isReactorPeer;
  final bool isHidden;
  final String senderId;
  final String contentRich;
  // Whether this message's chat is the Saved Messages / self chat. Distinguishes
  // a fired self-reminder ("📅 Reminder") from a scheduled message sent to
  // another chat ("📅 PeerName"), and gates the "You" subtitle — mirrors
  // AyuGram's peer->isSelf() checks in notificationHeader() and
  // doShowNativeNotification (notifications_manager.cpp:1568,1582;
  // history_item.cpp:2770).
  final bool isSelf;
  // Whether this message's chat is the Replies chat (the aggregated
  // comments/replies service peer). AyuGram's GenerateUserpic routes
  // peer->isRepliesChat() to EmptyUserpic::GenerateRepliesMessages — the
  // dedicated white reply-arrow glyph on the saved-messages blue gradient —
  // instead of colored initials, mirroring isSelf's Saved Messages bookmark
  // branch. (notifications_utilities.cpp:29-30, empty_userpic.cpp:147-161)
  final bool isReplies;
  // Whether the user can send a text reply here (AyuGram's CanSendTexts(peer) &&
  // (!topic || CanSendTexts(topic))). Gates the inline reply button. Defaults
  // true so unrestricted chats keep the reply action.
  // (notifications_manager.cpp:1097-1099)
  final bool canSendText;
  // Whether a reacted-to poll is a quiz (AyuGram poll->quiz()), selecting the
  // quiz vs poll reaction notification string. (notifications_manager.cpp:1205)
  final bool isQuiz;
  // Document/audio filename. AyuGram's MediaFile::notificationText() prefers
  // `_document->filename()` over the generic "File"/"Audio file" type string
  // when a file (case 8) or audio file (case 3) has a name — the filename check
  // precedes the isAudioFile()/lng_in_dlg_file fallbacks
  // (data_media_types.cpp:1287-1294). Empty for media with no filename.
  final String mediaFileName;
  // Venue / place title. AyuGram's MediaLocation::notificationText() appends it
  // as the caption ("Location, {title}") via
  // WithCaptionNotificationText(typeString(), { .text = _title })
  // (data_media_types.cpp:1701-1703). Empty for a plain geo point.
  final String venueTitle;
  // Service message (joined / pinned / etc.). notificationHeader() returns an
  // empty subtitle for service items (history_item.cpp:2768-2769).
  final bool isService;
  // Broadcast-channel post that hides its author (channel has no signature
  // profiles, so the post is attributed to the channel itself). The sender line
  // is then suppressed because the channel name is already the title — mirrors
  // AyuGram's isPostHidingAuthor() gate in notificationHeader()
  // (history_item.cpp:2772, :3952-3959). Never set for megagroups (not posts).
  final bool isPostHidingAuthor;

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
    this.perChatVolume = 0,
    this.groupedId = '',
    this.isPollVote = false,
    this.isSenderMuted = false,
    this.mentionsMe = false,
    this.slowmodeActive = false,
    this.requiresStars = false,
    this.spoilerLoginCode = false,
    this.isMonoforumSublist = false,
    this.sublistPeerName = '',
    this.topicRootId = '',
    this.sublistPeerId = '',
    this.hideMarkAsRead = false,
    this.muteStateUnknown = false,
    this.pollVoteOption = '',
    this.isReactorPeer = false,
    this.isHidden = false,
    this.senderId = '',
    this.contentRich = '',
    this.isSelf = false,
    this.isReplies = false,
    this.canSendText = true,
    this.isQuiz = false,
    this.mediaFileName = '',
    this.venueTitle = '',
    this.isService = false,
    this.isPostHidingAuthor = false,
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
    bool? mentionsMe,
    bool? slowmodeActive,
    bool? requiresStars,
    bool? spoilerLoginCode,
    bool? isMonoforumSublist,
    String? sublistPeerName,
    String? topicRootId,
    String? sublistPeerId,
    bool? hideMarkAsRead,
    bool? muteStateUnknown,
    String? pollVoteOption,
    bool? isReactorPeer,
    bool? isHidden,
    String? senderId,
    String? contentRich,
    bool? isSelf,
    bool? isReplies,
    bool? canSendText,
    bool? isQuiz,
    String? mediaFileName,
    String? venueTitle,
    bool? isService,
    bool? isPostHidingAuthor,
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
      mentionsMe: mentionsMe ?? this.mentionsMe,
      slowmodeActive: slowmodeActive ?? this.slowmodeActive,
      requiresStars: requiresStars ?? this.requiresStars,
      spoilerLoginCode: spoilerLoginCode ?? this.spoilerLoginCode,
      isMonoforumSublist: isMonoforumSublist ?? this.isMonoforumSublist,
      sublistPeerName: sublistPeerName ?? this.sublistPeerName,
      topicRootId: topicRootId ?? this.topicRootId,
      sublistPeerId: sublistPeerId ?? this.sublistPeerId,
      hideMarkAsRead: hideMarkAsRead ?? this.hideMarkAsRead,
      muteStateUnknown: muteStateUnknown ?? this.muteStateUnknown,
      pollVoteOption: pollVoteOption ?? this.pollVoteOption,
      isReactorPeer: isReactorPeer ?? this.isReactorPeer,
      isHidden: isHidden ?? this.isHidden,
      senderId: senderId ?? this.senderId,
      contentRich: contentRich ?? this.contentRich,
      isSelf: isSelf ?? this.isSelf,
      isReplies: isReplies ?? this.isReplies,
      canSendText: canSendText ?? this.canSendText,
      isQuiz: isQuiz ?? this.isQuiz,
      mediaFileName: mediaFileName ?? this.mediaFileName,
      venueTitle: venueTitle ?? this.venueTitle,
      isService: isService ?? this.isService,
      isPostHidingAuthor: isPostHidingAuthor ?? this.isPostHidingAuthor,
    );
  }
}

const _appName = 'UniClient';
const _spoilerBlock = '▚';
// AyuGram caps the notification body at kNotificationTextLimit and appends an
// ellipsis (history_item.cpp:86,4325-4329).
const _kNotificationTextLimit = 255;
const _kEllipsis = '…';
// TextWithForwardedChar prepends ONLY this glyph (no sender, no space) to a
// single forwarded message (notifications_manager.cpp:81-86).
const _forwardedChar = '➡️'; // ➡️
// WrapFromScheduled prepends "📅 " to a fired scheduled message's title
// (notifications_manager.cpp:1673-1675).
const _scheduledPrefix = '\u{1F4C5} ';
// SpoilerLoginCode pattern, 1:1 with history_item.cpp:106-107. NOTE the AyuGram
// lookahead is (?!\w\-) — a two-char sequence (word char THEN hyphen), NOT a
// character class — so a code immediately followed by a single word char (e.g.
// "12345abc") is still masked.
final _loginCodePattern = RegExp(r'(?<![\w\-#])(\d[\d\-]{2,6}\d)(?!\w\-)');


class NotificationContent {
  final String title;
  final String subtitle;
  final String body;
  final List<NotifEntity> bodyEntities;

  const NotificationContent({
    required this.title,
    required this.subtitle,
    required this.body,
    this.bodyEntities = const [],
  });
}

class NotifEntity {
  final String type;
  final int offset;
  final int length;
  const NotifEntity(this.type, this.offset, this.length);
}

NotificationContent composeNotificationContent(
  NotificationData data,
  NotificationSettings settings,
) {
  final title = _composeTitle(data, settings);
  final subtitle = _composeSubtitle(data, settings);
  final body = _composeBody(data, settings);
  final entities = _composeBodyEntities(data, settings, body);
  return NotificationContent(title: title, subtitle: subtitle, body: body, bodyEntities: entities);
}

String _composeTitle(NotificationData data, NotificationSettings settings) {
  // scheduled mirrors AyuGram's
  //   !hideNameAndPhoto && !reactionFrom && (out() || isSelf()) && isFromScheduled()
  // (notifications_manager.cpp:1566-1569), where hideNameAndPhoto == !previewName.
  final scheduled = settings.previewName &&
      !data.isReaction &&
      !data.isPollVote &&
      (data.isOutgoing || data.isSelf) &&
      data.isScheduled;

  String title;
  if (!settings.previewName) {
    title = _appName;
  } else if (scheduled && data.isSelf) {
    // Only a self-reminder collapses to "Reminder"; a scheduled message fired to
    // another chat keeps that chat's name (and gets the 📅 prefix below).
    title = TrStrings.lngNotifReminder();
  } else if (data.isMonoforumSublist && data.sublistPeerName.isNotEmpty) {
    title = '${data.sublistPeerName} (${data.chatTitle})';
  } else if (data.isForumTopic && data.topicTitle.isNotEmpty) {
    title = '${data.topicTitle} (${data.chatTitle})';
  } else {
    title = data.chatTitle.isNotEmpty ? data.chatTitle : data.senderName;
  }

  // addTargetAccountName — applied UNCONDITIONALLY, including the hidden-preview
  // case, so multi-account users always see which account was notified
  // (notifications_manager.cpp:1585 + 1248-1268).
  if (data.multiAccount && data.accountUsername.isNotEmpty) {
    title = '$title ➜ ${data.accountUsername}';
  }

  // WrapFromScheduled — prepend 📅 to the WHOLE title (account suffix included)
  // when a scheduled message fires (notifications_manager.cpp:1658).
  if (scheduled) {
    title = '$_scheduledPrefix$title';
  }

  return title;
}

String _composeSubtitle(NotificationData data, NotificationSettings settings) {
  if (!settings.previewName) return '';

  if ((data.isReaction || data.isPollVote) && data.reactorName.isNotEmpty) {
    final hideReactionSender = !settings.reactionsShowPreview;
    if (!hideReactionSender && !data.isReactorPeer) {
      return data.reactorName;
    }
    return '';
  }

  // --- notificationHeader() (history_item.cpp:2767-2774) ---

  // Service messages (joined / pinned / changed photo / etc.) have no header —
  // isService() short-circuits to an empty string (history_item.cpp:2768-2769).
  if (data.isService) return '';

  // "You" whenever a scheduled message I sent fires in a non-self chat —
  // regardless of chat type, 1-on-1 INCLUDED (history_item.cpp:2770-2771).
  if (data.isOutgoing && data.isScheduled && !data.isSelf) {
    return TrStrings.lngNotifYou();
  }

  // Group/channel (non-user peer): the sender's name — but a broadcast-channel
  // post that hides its author yields an EMPTY header, since the channel name is
  // already the title. Mirrors `!_history->peer->isUser() && !isPostHidingAuthor()`
  // (history_item.cpp:2772-2773).
  if ((data.isGroup || data.isChannel) && !data.isPostHidingAuthor) {
    return data.senderName;
  }

  return '';
}

String _composeBody(NotificationData data, NotificationSettings settings) {
  final hideMessageText = !settings.previewText;

  if (data.isPollVote) {
    return _composePollVoteText(data, hideMessageText: hideMessageText);
  }

  if (data.isReaction) {
    return _composeReactionText(data, hideMessageText: hideMessageText);
  }

  if (hideMessageText) return TrStrings.lngNotifNewMessage();

  // Body ternary order mirrors AyuGram exactly
  // (notifications_manager.cpp:1606-1616):
  //   forwardedCount>1 → album(groupId) → TextWithForwardedChar(notificationText)
  if (data.forwardCount > 1) {
    return TrStrings.lngForwardMessages(data.forwardCount);
  }
  // Album: any message that is part of a media group shows "Album" BEFORE its
  // own media string ("Photo"/"Video"). AyuGram branches on item->groupId().
  if (data.groupedId.isNotEmpty) {
    return TrStrings.lngInDlgAlbum();
  }

  var text = _messageTextForType(data);
  if (data.spoilerLoginCode) {
    text = _maskLoginCodes(text, data.contentRich);
  }
  text = _truncateNotification(text);
  // TextWithForwardedChar: prepend the ➡️ glyph (no sender, no colon, no space)
  // for a single forwarded message; gated purely on forwardedCount == 1.
  if (data.forwardCount == 1) {
    text = '$_forwardedChar$text';
  }
  return text;
}

// "{attachType}, {caption}" when a caption is present, else just the type —
// mirrors AyuGram's WithCaptionNotificationText (data_media_types.cpp). The
// caption's own spoiler entities are masked (▚) BEFORE the type prefix is added,
// matching TextWithPermanentSpoiler operating on the composed text-with-entities.
String _withCaption(String attachType, NotificationData data) {
  if (data.caption.isEmpty) return attachType;
  return '$attachType, ${_maskSpoilers(data.caption, data.contentRich)}';
}

String _messageTextForType(NotificationData data) {
  // MediaGame::notificationText() — a game carries no attachment, so the engine
  // assigns it no media-type int (messageType stays 0/none; the db.go media
  // constants stop at MediaInvoice=12) and an empty body text. A game is
  // identified solely by its title (Message.hasGame == gameTitle.isNotEmpty).
  // Prepend the 🎮 game-controller emoji (U+1F3AE, UTF-16 surrogate pair
  // 0xD83C 0xDFAE) + a space + the title, exactly like AyuGram. Checked BEFORE
  // the switch — otherwise messageType 0 falls through to `default`, which masks
  // the empty text and yields a blank/generic body.
  // (data_media_types.cpp:2069-2081)
  if (data.gameTitle.isNotEmpty) {
    return '\u{1F3AE} ${data.gameTitle}';
  }
  switch (data.messageType) {
    case 1: // image
      return _withCaption(TrStrings.lngNotifPhoto(), data);
    case 2: // video
      return _withCaption(TrStrings.lngNotifVideo(), data);
    case 3: // audio
      // MediaFile::notificationText(): the document filename takes priority over
      // the generic "Audio file" string — the `!filename().isEmpty()` branch
      // precedes the `isAudioFile()` → lng_in_dlg_audio_file fallback
      // (data_media_types.cpp:1287-1290). Caption (originalText) is still
      // appended via WithCaptionNotificationText.
      return _withCaption(
        data.mediaFileName.isNotEmpty
            ? data.mediaFileName
            : TrStrings.lngNotifAudioFile(),
        data,
      );
    case 4: // voice
      return _withCaption(TrStrings.lngNotifVoiceMessage(), data);
    case 5: // videonote
      return TrStrings.lngNotifVideoMessage();
    case 6: // sticker
      if (data.stickerEmoji.isNotEmpty) {
        return '${data.stickerEmoji} ${TrStrings.lngNotifSticker()}';
      }
      return TrStrings.lngNotifSticker();
    case 7: // gif
      return _withCaption(TrStrings.lngNotifGif(), data);
    case 8: // file
      // MediaFile::notificationText(): a document with a filename shows the
      // filename ("report.pdf") instead of the generic "File"; only a nameless
      // document falls back to lng_in_dlg_file (data_media_types.cpp:1287-1294).
      return _withCaption(
        data.mediaFileName.isNotEmpty
            ? data.mediaFileName
            : TrStrings.lngNotifFile(),
        data,
      );
    case 9: // poll
      return data.pollQuestion.isNotEmpty
          ? '\u{1F4CA} ${data.pollQuestion}'
          : TrStrings.lngNotifPoll();
    case 10: // location
      // MediaLocation::notificationText() = WithCaptionNotificationText(
      //   typeString(), { .text = _title }) — the venue title is appended as the
      // caption ("Location, {venue}"). typeString() is "Live Location" for a
      // live period, else "Location" (data_media_types.cpp:1686-1690,1701-1703).
      // The title carries no entities, so no spoiler masking; a plain geo point
      // has an empty title and shows only the type string.
      final locationType = data.isLiveLocation
          ? TrStrings.lngNotifLiveLocation()
          : TrStrings.lngNotifLocation();
      return data.venueTitle.isNotEmpty
          ? '$locationType, ${data.venueTitle}'
          : locationType;
    case 11: // contact
      // MediaContact::notificationText() returns ONLY lng_in_dlg_contact
      // ("Contact") — the contact's name is never appended to the plain message
      // body (it only appears in the *reaction* string lng_reaction_contact)
      // (data_media_types.cpp:1591-1593).
      return TrStrings.lngNotifContact();
    case 12: // invoice
      return data.invoiceTitle.isNotEmpty ? data.invoiceTitle : TrStrings.lngNotifInvoice();
    default:
      return _maskSpoilers(data.text, data.contentRich);
  }
}

// TextWithPermanentSpoiler (notifications_manager.cpp:88-100): replace each
// spoiler ENTITY range with ▚ repeated its EXACT length, leaving the rest of the
// text intact (so `visible ||secret||` → `visible ▚▚▚▚▚▚`). Offsets/lengths are
// UTF-16 code units (Telegram convention), which line up with Dart's native
// String indexing; ▚ is a single BMP code unit, so each replacement preserves
// length and keeps later spoiler offsets valid.
String _maskSpoilers(String text, String contentRich) {
  if (text.isEmpty || contentRich.isEmpty) return text;
  List<dynamic> list;
  try {
    list = jsonDecode(contentRich) as List;
  } catch (_) {
    return text;
  }
  var result = text;
  for (final e in list) {
    if (e is! Map<String, dynamic>) continue;
    if ((e['type'] as String? ?? '') != 'spoiler') continue;
    final offset = e['offset'] as int? ?? 0;
    final length = e['length'] as int? ?? 0;
    if (length <= 0 || offset < 0 || offset + length > result.length) continue;
    result = result.substring(0, offset) +
        (_spoilerBlock * length) +
        result.substring(offset + length);
  }
  return result;
}

// SpoilerLoginCode (history_item.cpp:105-124): mask only the FIRST code match,
// and only if it does not intersect an existing entity.
String _maskLoginCodes(String text, String contentRich) {
  final m = _loginCodePattern.firstMatch(text);
  if (m == null) return text;
  final codeStart = m.start;
  final codeLength = m.end - m.start;
  if (_loginCodeIntersectsEntity(contentRich, codeStart)) return text;
  return text.substring(0, codeStart) +
      (_spoilerBlock * codeLength) +
      text.substring(codeStart + codeLength);
}

// AyuGram guard (history_item.cpp:114-120): walk entities ordered by offset; if
// an entity that STARTS before the code extends past the code's start, the
// ranges intersect and masking is skipped entirely.
bool _loginCodeIntersectsEntity(String contentRich, int codeStart) {
  if (contentRich.isEmpty) return false;
  List<dynamic> list;
  try {
    list = jsonDecode(contentRich) as List;
  } catch (_) {
    return false;
  }
  final ranges = <List<int>>[];
  for (final e in list) {
    if (e is! Map<String, dynamic>) continue;
    final offset = e['offset'] as int? ?? 0;
    final length = e['length'] as int? ?? 0;
    if (length <= 0) continue;
    ranges.add([offset, length]);
  }
  ranges.sort((a, b) => a[0].compareTo(b[0]));
  for (final r in ranges) {
    if (r[0] >= codeStart) break;
    if (r[0] + r[1] > codeStart) return true;
  }
  return false;
}

// notificationText cap (history_item.cpp:4325-4329): truncate to 255 code units
// and append an ellipsis.
String _truncateNotification(String text) {
  if (text.length <= _kNotificationTextLimit) return text;
  return text.substring(0, _kNotificationTextLimit) + _kEllipsis;
}

List<NotifEntity> _composeBodyEntities(NotificationData data, NotificationSettings settings, String body) {
  if (!settings.previewText || data.contentRich.isEmpty) return const [];
  if (data.isReaction || data.isPollVote) return const [];
  if (data.forwardFrom.isNotEmpty || data.forwardCount == 1) return const [];
  if (data.messageType != 0) return const [];
  final rawText = data.text;
  if (rawText.isEmpty || body.isEmpty) return const [];
  if (body != rawText && body != _maskLoginCodes(rawText, data.contentRich)) return const [];
  try {
    final list = jsonDecode(data.contentRich) as List;
    final entities = <NotifEntity>[];
    for (final e in list) {
      if (e is! Map<String, dynamic>) continue;
      final type = e['type'] as String? ?? '';
      if (type == 'spoiler') continue;
      final offset = e['offset'] as int? ?? 0;
      final length = e['length'] as int? ?? 0;
      if (length <= 0 || offset < 0 || offset + length > body.length) continue;
      entities.add(NotifEntity(type, offset, length));
    }
    return entities;
  } catch (_) {
    return const [];
  }
}

String _composeReactionText(NotificationData data, {required bool hideMessageText}) {
  final emoji = data.reactionEmoji;
  if (emoji.isEmpty) return '';

  if (hideMessageText) return TrStrings.lngNotifReactedToMessage(emoji);

  switch (data.reactedToType) {
    case 1: return TrStrings.lngNotifReactedToPhoto(emoji);
    case 2: return TrStrings.lngNotifReactedToVideo(emoji);
    case 3: return TrStrings.lngNotifReactedToFile(emoji);
    case 4: return TrStrings.lngNotifReactedToVoice(emoji);
    case 5: return TrStrings.lngNotifReactedToVideoMsg(emoji);
    case 6:
      if (data.stickerEmoji.isNotEmpty) {
        return TrStrings.lngNotifReactedToSticker(emoji, data.stickerEmoji);
      }
      return TrStrings.lngNotifReactedToStickerPlain(emoji);
    case 7: return TrStrings.lngNotifReactedToGif(emoji);
    case 8: return TrStrings.lngNotifReactedToFile(emoji);
    case 9:
      // lng_reaction_poll / lng_reaction_quiz — include the poll question and
      // distinguish quizzes (notifications_manager.cpp:1204-1213).
      return data.isQuiz
          ? TrStrings.lngNotifReactedToQuiz(emoji, data.pollQuestion)
          : TrStrings.lngNotifReactedToPoll(emoji, data.pollQuestion);
    case 10: return TrStrings.lngNotifReactedToLocation(emoji);
    case 11:
      if (data.contactName.isNotEmpty) {
        return TrStrings.lngNotifReactedToContact(emoji, data.contactName);
      }
      return TrStrings.lngNotifReactedToContactPlain(emoji);
    case 12: return TrStrings.lngNotifReactedToInvoice(emoji);
    default:
      // MediaGame carries no media-type int, so the engine leaves reactedToType
      // at 0 (the comment at _messageTextForType:502-510) and a game reaction
      // lands in this default branch. AyuGram's ComposeReactionNotification
      // matches `media->game()` → lng_reaction_game ("{reaction} to your game")
      // before the text() fallback; a game is identified solely by its title,
      // exactly as _messageTextForType:511 does. Checked BEFORE the text branch
      // because a game's body text is empty — otherwise it falls through to the
      // bare emoji. (notifications_manager.cpp:1214-1215)
      if (data.gameTitle.isNotEmpty) {
        return TrStrings.lngNotifReactedToGame(emoji);
      }
      // lng_reaction_text embeds item->notificationText(): the reacted-to
      // message's text with spoiler entities masked (▚) and truncated to 255
      // (+ ellipsis via Ui::Text::Mid), the whole composed reaction string then
      // re-wrapped in TextWithPermanentSpoiler. The message text must therefore
      // be masked & capped here — exactly like the regular (non-reaction) body
      // at composeNotificationContent:479-483 — not inserted raw, or a spoiler
      // would leak. notificationText() is called with DEFAULT options, so
      // spoilerLoginCode masking does NOT apply to reactions. _maskSpoilers is
      // length-preserving, so mask-then-truncate equals AyuGram's
      // truncate-then-mask. (notifications_manager.cpp:1151-1158,1601-1605;
      // history_item.cpp:4325-4329)
      final text = _truncateNotification(
        _maskSpoilers(data.text, data.contentRich),
      );
      if (text.isNotEmpty) {
        return TrStrings.lngNotifReactedToText(emoji, text);
      }
      return emoji;
  }
}

String _composePollVoteText(NotificationData data, {required bool hideMessageText}) {
  if (hideMessageText) return TrStrings.lngNotifVotedInPoll();

  if (data.pollVoteOption.isNotEmpty) {
    return TrStrings.lngNotifVotedFor(data.pollVoteOption);
  }

  if (data.pollQuestion.isNotEmpty) {
    return TrStrings.lngNotifVotedInPollNamed(data.pollQuestion);
  }

  return TrStrings.lngNotifVotedInPoll();
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
  final bool reactionsShowPreview;
  final bool includeMutedChats;
  final bool countUnreadMessages;
  final bool useNativeNotifications;
  final bool forceCustomNotifications;
  final bool disableNotificationsDelay;
  final bool hideReplyButton;
  final NotificationCorner corner;
  final int maxNotificationCount;
  final int displayIndex;
  final bool notifyFromAll;

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
    this.reactionsShowPreview = true,
    this.includeMutedChats = true,
    this.countUnreadMessages = true,
    this.useNativeNotifications = true,
    this.forceCustomNotifications = false,
    this.disableNotificationsDelay = false,
    this.hideReplyButton = false,
    this.corner = NotificationCorner.bottomRight,
    this.maxNotificationCount = 3,
    this.displayIndex = 0,
    this.notifyFromAll = true,
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
    bool? reactionsShowPreview,
    bool? includeMutedChats,
    bool? countUnreadMessages,
    bool? useNativeNotifications,
    bool? forceCustomNotifications,
    bool? disableNotificationsDelay,
    bool? hideReplyButton,
    NotificationCorner? corner,
    int? maxNotificationCount,
    int? displayIndex,
    bool? notifyFromAll,
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
      reactionsShowPreview:
          reactionsShowPreview ?? this.reactionsShowPreview,
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
      notifyFromAll: notifyFromAll ?? this.notifyFromAll,
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
  // AyuGram hides the reply button when the user cannot send a text reply in the
  // peer (and topic, if any) — banned / restricted / no post rights
  // (notifications_manager.cpp:1097-1099).
  if (!data.canSendText) return true;
  if (data.isChannel) return true;
  if (data.slowmodeActive) return true;
  if (data.requiresStars) return true;
  return false;
}
