// Centralised translatable strings — maps to Telegram lang pack keys.
// Replace with server-sourced language packs when i18n is implemented.

class TrStrings {
  TrStrings._();

  // Theme confirmation overlay (window_theme_warning.cpp)
  static String lngThemeSureKeep() => 'Keep this theme?';
  static String lngThemeReverting(int count) =>
      'Theme will revert in $count second${count == 1 ? '' : 's'}';
  static String lngThemeKeepChanges() => 'Keep Changes';
  static String lngThemeRevert() => 'Revert';

  // Passcode lock (window_lock_widgets.cpp)
  static String lngPasscodeEnter() => 'Enter your local passcode';
  static String lngPasscodePh() => 'Your passcode';
  static String lngPasscodeSubmit() => 'Submit';
  static String lngPasscodeLogout() => 'Log out';
  static String lngPasscodeWrong() => 'Wrong passcode';
  static String lngPasscodeEmpty() => 'Please enter your passcode';
  static String lngPasscodeLogoutSure() => 'Are you sure you want to log out?';
  static String lngCancel() => 'Cancel';
  static String lngFloodError() => 'Too many tries. Please try again later.';

  // Notification grouping (notifications_manager.cpp)
  static String lngForwardMessages(int count) =>
      '$count forwarded message${count == 1 ? '' : 's'}';
  static String lngInDlgAlbum() => 'Album';

  // Notification content (notification_types.dart)
  static String lngNotifNewMessage() => 'You have a new message';
  static String lngNotifReminder() => 'Reminder';
  static String lngNotifYou() => 'You';
  static String lngNotifPhoto() => 'Photo';
  static String lngNotifVideo() => 'Video';
  static String lngNotifAudioFile() => 'Audio file';
  static String lngNotifVoiceMessage() => 'Voice message';
  static String lngNotifVideoMessage() => 'Video message';
  static String lngNotifSticker() => 'Sticker';
  static String lngNotifGif() => 'GIF';
  static String lngNotifFile() => 'File';
  static String lngNotifPoll() => 'Poll';
  static String lngNotifLocation() => 'Location';
  static String lngNotifLiveLocation() => 'Live location';
  static String lngNotifContact() => 'Contact';
  static String lngNotifInvoice() => 'Invoice';
  static String lngNotifVotedInPoll() => 'Voted in a poll';
  static String lngNotifVotedFor(String option) => 'Voted for «$option»';
  static String lngNotifVotedInPollNamed(String question) =>
      'Voted in poll: $question';
  static String lngNotifReactedToMessage(String emoji) =>
      '$emoji to your message';
  static String lngNotifReactedToPhoto(String emoji) => '$emoji to your photo';
  static String lngNotifReactedToVideo(String emoji) => '$emoji to your video';
  static String lngNotifReactedToFile(String emoji) => '$emoji to your file';
  static String lngNotifReactedToVoice(String emoji) =>
      '$emoji to your voice message';
  static String lngNotifReactedToVideoMsg(String emoji) =>
      '$emoji to your video message';
  static String lngNotifReactedToSticker(String emoji, String stickerEmoji) =>
      '$emoji to your $stickerEmoji sticker';
  static String lngNotifReactedToStickerPlain(String emoji) =>
      '$emoji to your sticker';
  static String lngNotifReactedToGif(String emoji) => '$emoji to your GIF';
  static String lngNotifReactedToPoll(String emoji) => '$emoji to your poll';
  static String lngNotifReactedToLocation(String emoji) =>
      '$emoji to your location';
  static String lngNotifReactedToContact(String emoji, String name) =>
      '$emoji to contact: $name';
  static String lngNotifReactedToContactPlain(String emoji) =>
      '$emoji to your contact';
  static String lngNotifReactedToInvoice(String emoji) =>
      '$emoji to your invoice';
  static String lngNotifReactedToText(String emoji, String text) =>
      '$emoji to: $text';
}
