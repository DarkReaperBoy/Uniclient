// Centralised translatable strings — maps to Telegram lang pack keys.
// Replace with server-sourced language packs when i18n is implemented.

class TrStrings {
  TrStrings._();

  // Auth intro (intro_signup.cpp, intro_code.cpp, intro_widget.cpp)
  static String lngIntroFinish() => 'Sign Up';
  static String lngIntroNext() => 'Next';
  static String lngIntroSubmit() => 'Submit';
  static String lngSigninCantEmailForgot() =>
      "If you can't restore access to your email, your remaining options are "
      "either to remember your password or to reset your account.";

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
  static String lngFileTooLarge(int count) =>
      count == 1 ? 'The file exceeds the size limit.' : '$count files exceed the size limit.';
  static String lngFloodError() => 'Too many tries. Please try again later.';

  // Dialog text formatting (dialogs_entry.cpp)
  static String lngDialogsTextWithFrom(String from, String message) =>
      '$from: $message';

  // Native notification action buttons (lang.strings: lng_open_link,
  // lng_context_mark_read, lng_notification_reply)
  static String lngOpenLink() => 'Open';
  static String lngContextMarkRead() => 'Mark as read';
  static String lngNotificationReply() => 'Reply';

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
  static String lngNotifReactedToPoll(String emoji, String question) =>
      question.isEmpty
          ? '$emoji to your poll'
          : '$emoji to your poll "$question"';
  static String lngNotifReactedToQuiz(String emoji, String question) =>
      question.isEmpty
          ? '$emoji to your quiz'
          : '$emoji to your quiz "$question"';
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

  // Report reactions (info_profile_actions.cpp:1302-1339)
  static String lngReportReactionTitle() => 'Report reaction';
  static String lngReportReactionAbout() =>
      'Are you sure you want to report reactions from this user?';
  static String lngReportAndBanButton() => 'Ban user';

  // Auto-delete (delete_messages_box.cpp:306-315)
  static String lngEnableAutoDelete() => 'Enable auto-delete';
  static String lngEditAutoDeleteSettings() => 'Edit auto-delete settings';

  // Paid post types (delete_messages_box.cpp:563-576)
  static String lngSuggestWarnTitleTon() => 'Delete TON Suggested Post';
  static String lngSuggestWarnTitleStars() => 'Delete Stars Suggested Post';
  static String lngSuggestWarnTextTon() =>
      'This is a paid suggested post. The TON payment will be lost if you delete it. Are you sure you want to delete it anyway?';
  static String lngSuggestWarnTextStars() =>
      'This is a paid suggested post. The Stars payment will be lost if you delete it. Are you sure you want to delete it anyway?';
  static String lngSuggestWarnDeleteAnyway() => 'Delete Anyway';

  // Delete chat box (moderate_messages_box.cpp:1020-1066)
  static String lngProfileBlockBot() => 'Block bot';
  static String lngFiltersCheckboxRemoveBot() => 'Remove from chat folders';
  static String lngFiltersCheckboxRemoveChannel() => 'Remove from chat folders';
  static String lngFiltersCheckboxRemoveGroup() => 'Remove from chat folders';

  // Common dialog buttons (edit_mark_box.cpp:44-58, layers.style)
  static String lngSettingsSave() => 'Save';
  static String lngAyuBoxActionReset() => 'Reset';

  // Localized default "edited" mark (lang.strings:2838 "lng_edited" = "edited").
  // AyuGram seeds the edited-mark default and the EditMarkBox with
  // tr::lng_edited(tr::now) (ayu_settings.cpp:358, settings_chats.cpp:189),
  // so non-English users get their localized word instead of literal "edited".
  static String lngEdited() => 'edited';

  // Active sessions termination (settings_active_sessions.cpp,
  // self_destruction_box.cpp). Confirm-box copy matches AyuGram's
  // Ui::MakeConfirmBox + st::attentionBoxButton ("Terminate") usage.
  static String lngSettingsResetButton() => 'Terminate';
  static String lngSettingsResetOneSure() =>
      'Do you want to terminate this session?';
  static String lngSettingsResetSure() =>
      'Are you sure you want to terminate\nall other sessions?';
  static String lngSelfDestructSessionsTitle() => 'Session termination';
  static String lngSelfDestructSessionsDescription() =>
      "If you don't come online from a specific session at least once within "
      'this period, it will be terminated.';

  // AyuForward status strings (ayu_forward.cpp:64-89)
  static String lngAyuForwardStatusPreparing() => 'Preparing...';
  static String lngAyuForwardStatusForwarding() => 'Forwarding messages';
  static String lngAyuForwardStatusLoadingMedia() => 'Loading media';
  static String lngAyuForwardStatusFinished() => 'Done';
  static String lngAyuForwardStatusSentCount(int sent, int total) =>
      'sent $sent of $total';
  static String lngAyuForwardStatusChunkCount(int chunk, int total) =>
      'chunk $chunk of $total';
}
