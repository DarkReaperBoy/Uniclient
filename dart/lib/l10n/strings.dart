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
      'Reverting to the old theme in $count second${count == 1 ? '' : 's'}.';
  static String lngThemeKeepChanges() => 'Keep Changes';
  static String lngThemeRevert() => 'Revert';

  // Passcode lock (window_lock_widgets.cpp)
  static String lngPasscodeEnter() => 'Enter your local passcode';
  static String lngPasscodePh() => 'Your passcode';
  static String lngPasscodeSubmit() => 'Submit';
  static String lngPasscodeLogout() => 'Log out';
  static String lngPasscodeWrong() => 'Wrong passcode';
  static String lngPasscodeLogoutSure() => 'Are you sure you want to log out?';
  // System-unlock info label shown on the cold-start lock (domain not started),
  // beneath the logout link. AyuGram's lng_passcode_winhello / _touchid /
  // _applewatch / _systempwd (window_lock_widgets.cpp:132-161).
  static String lngPasscodeWinhello() =>
      'You need to enter your passcode\nbefore you can use Windows Hello.';
  static String lngPasscodeTouchid() =>
      'You need to enter your passcode\nbefore you can use Touch ID.';
  static String lngPasscodeApplewatch() =>
      'You need to enter your passcode\nbefore you can use Watch to unlock.';
  static String lngPasscodeSystempwd() =>
      'You need to enter your passcode\nbefore you can use system password.';
  static String lngCancel() => 'Cancel';
  // FileSizeLimitBox / SimpleLimitBox — over-sized-document upload box
  // (premium_limits_box.cpp:1009-1064, triggered by FileLoadTask::finish at
  // localimageloader.cpp:1058-1069; lang.strings:267-271,285,125). The body
  // states the real backend upload limit (bold, e.g. "4 GB") via the {size}
  // placeholder, with a Premium-doubling upsell when Premium would still accept
  // the file. "$count GB" mirrors lng_file_size_limit#one/#other.
  static String lngFileSizeLimitTitle() => 'File Too Large';
  static String lngFileSizeLimitGb(int count) => '$count GB';
  static String lngFileSizeLimit1(String size) =>
      "The document can't be sent, because it is larger than $size.";
  static String lngFileSizeLimit2(String size) =>
      'You can double this limit to $size per document by subscribing to '
      '**Telegram Premium**.';
  static String lngLimitsIncrease() => 'Increase Limit';
  static String lngBoxOk() => 'OK';
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
  // One-time (self-destruct / view-once, media->ttlSeconds() set) voice & video
  // messages. lng_in_dlg_voice_message_ttl / lng_in_dlg_video_message_ttl
  // (lang.strings:4554-4555), chosen by MediaFile::notificationText() over the
  // plain variants (data_media_types.cpp:1273-1286).
  static String lngNotifVoiceMessageTtl() => 'One-time Voice Message';
  static String lngNotifVideoMessageTtl() => 'One-time Video Message';
  static String lngNotifSticker() => 'Sticker';
  static String lngNotifGif() => 'GIF';
  static String lngNotifFile() => 'File';
  static String lngNotifPoll() => 'Poll';
  static String lngNotifLocation() => 'Location';
  static String lngNotifLiveLocation() => 'Live location';
  static String lngNotifContact() => 'Contact';
  static String lngNotifInvoice() => 'Invoice';
  static String lngNotifVotedInPoll() => 'voted in your poll';
  static String lngNotifVotedFor(String option) =>
      'voted for "$option" in your poll';
  static String lngNotifVotedInPollNamed(String question) =>
      'voted in your poll "$question"';
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
      '$emoji to your map';
  static String lngNotifReactedToContact(String emoji, String name) =>
      '$emoji to your contact $name';
  static String lngNotifReactedToContactPlain(String emoji) =>
      '$emoji to your contact';
  static String lngNotifReactedToGame(String emoji) =>
      '$emoji to your game';
  static String lngNotifReactedToInvoice(String emoji) =>
      '$emoji to your invoice';
  static String lngNotifReactedToText(String emoji, String text) =>
      '$emoji to your "$text"';

  // Report reactions (info_profile_actions.cpp:1302-1339)
  static String lngReportReactionTitle() => 'Report reaction';
  static String lngReportReactionAbout() =>
      'Are you sure you want to report reactions from this user?';
  static String lngReportAndBanButton() => 'Ban user';

  // Report message chooser (lang.strings lng_report_select_messages /
  // lng_report_please_select_messages → mainwidget.cpp:1291)
  static String lngReportSelectMessages() => 'Select messages';
  static String lngReportPleaseSelectMessages() =>
      'Please select messages to report.';

  // Auto-delete (delete_messages_box.cpp:306-315)
  static String lngEnableAutoDelete() => 'Enable auto-delete';
  static String lngEditAutoDeleteSettings() => 'Edit auto-delete settings';

  // Paid post types (delete_messages_box.cpp:563-576)
  static String lngSuggestWarnTitleTon() => 'TON will be lost';
  static String lngSuggestWarnTitleStars() => 'Stars will be lost';
  static String lngSuggestWarnTextTon() =>
      "You won't receive **TON** for the post if you delete it now. "
      'The post must remain visible for at least **24 hours** after it was published.';
  static String lngSuggestWarnTextStars() =>
      "You won't receive **Stars** for the post if you delete it now. "
      'The post must remain visible for at least **24 hours** after it was published.';
  static String lngSuggestWarnDeleteAnyway() => 'Delete Anyway';

  // Delete chat box (moderate_messages_box.cpp:1020-1066)
  static String lngProfileDeleteConversation() => 'Delete chat';
  static String lngProfileBlockBot() => 'Stop and block bot';
  static String lngFiltersCheckboxRemoveBot() => 'Remove bot from all folders';
  static String lngFiltersCheckboxRemoveChannel() =>
      'Remove channel from all folders';
  static String lngFiltersCheckboxRemoveGroup() =>
      'Remove group from all folders';

  // Common dialog buttons (edit_mark_box.cpp:44-58, layers.style)
  static String lngSettingsSave() => 'Save';
  static String lngAyuBoxActionReset() => 'Reset';
  // Photo-editor brush color box positive button (color_picker.cpp:759,
  // lang.strings:126)
  static String lngBoxDone() => 'Done';

  // Chat-accent color picker box title (settings_chat.cpp:395, lang.strings:858)
  static String lngSettingsThemeAccentTitle() => 'Choose accent color';

  // Auto-delete timer box (auto_delete_settings.cpp, lang.strings:2162-2175)
  static String lngManageMessagesTtlTitle() => 'Auto-delete messages';
  static String lngManageMessagesTtlDisable() => 'Disable';
  static String lngManageMessagesTtlAfter1() => '1 day';
  static String lngManageMessagesTtlAfter2() => '1 week';
  static String lngManageMessagesTtlAfter3() => '1 month';
  static String lngTtlEditAbout(String user) =>
      'Automatically delete new messages for you and $user after a certain period of time.';
  static String lngTtlEditAboutGroup() =>
      'Automatically delete new messages sent in this chat after a certain period of time.';
  static String lngTtlEditAboutChannel() =>
      'Automatically delete new messages sent in this channel after a certain period of time.';
  static String lngTtlEditAbout2(String link) =>
      'You can also set a default $link for all your chats in Settings.';
  static String lngTtlEditAbout2Link() => 'self-destruct timer';

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
  static String lngAyuForwardStatusPreparing() => 'Forwarding messages';
  static String lngAyuForwardStatusForwarding() => 'Forwarding messages';
  static String lngAyuForwardStatusLoadingMedia() => 'Loading media';
  static String lngAyuForwardStatusFinished() => 'Done';
  static String lngAyuForwardStatusSentCount(int sent, int total) =>
      'sent $sent of $total';
  static String lngAyuForwardStatusChunkCount(int chunk, int total) =>
      'chunk $chunk of $total';
}
