// Centralised translatable strings — maps to Telegram lang pack keys.
//
// Every accessor resolves through [LangPack] (the active language instance,
// AyuGram's global `Lang::GetInstance()`): cloud overlay → embedded English
// baseline → raw key. This mirrors AyuGram, where every `tr::lng_*(tr::now)`
// goes through `Lang::Instance::getValue` (lang_instance.h:90) and returns the
// cloud-overlaid value or the built-in English default — so a non-English
// session localizes these notification/passcode/session/auto-delete/report/
// paid-post strings instead of always rendering English. The keys + English
// baselines live in `LangPack.keys` / `LangPack._en`; see those for the 1:1
// mapping to `Resources/langs/lang.strings`.
//
// A handful of accessors stay hardcoded English on purpose (no localizable
// cloud key exists): the `Lang::Hard::` email-expiry string, the literal "GIF"
// AyuGram emits for animations, and the empty-token sticker/contact reaction
// fallbacks. Each is flagged inline.

import 'lang_pack.dart';

class TrStrings {
  TrStrings._();

  // Resolve a plain lang-pack key through the active LangPack (cloud overlay →
  // English baseline → key), or the embedded English baseline when no instance
  // exists yet (early startup / tests). AyuGram `tr::lng_x(tr::now)`.
  static String _v(String key) =>
      LangPack.instance?.tr(key) ?? LangPack.baseline(key);

  // Same, with `{placeholder}` substitution. AyuGram `tr::lng_x(tr::now, lt_y, v)`.
  static String _vf(String key, Map<String, String> params) =>
      LangPack.instance?.trf(key, params) ?? LangPack.baselineF(key, params);

  // Same, pluralized on [count] with `{count}` substituted. AyuGram
  // `tr::lng_x(tr::now, lt_count, n)`.
  static String _vc(String key, int count) =>
      LangPack.instance?.trCount(key, count) ?? LangPack.baselineCount(key, count);

  // Auth intro (intro_signup.cpp, intro_code.cpp, intro_widget.cpp)
  static String lngIntroFinish() => _v('lng_intro_finish');
  static String lngIntroNext() => _v('lng_intro_next');
  static String lngIntroSubmit() => _v('lng_intro_submit');
  // Login-email setup: EMAIL_HASH_EXPIRED. AyuGram intentionally uses the
  // non-localized Lang::Hard::EmailConfirmationExpired() here (lang_hardcoded.h:65,
  // intro_email.cpp:119), so this stays hardcoded English by design — there is no
  // cloud key to overlay.
  static String lngHardEmailConfirmationExpired() =>
      'This email confirmation has expired. Please setup two-step verification '
      'once again.';
  static String lngSigninCantEmailForgot() =>
      _v('lng_signin_cant_email_forgot');

  // Theme confirmation overlay (window_theme_warning.cpp)
  static String lngThemeSureKeep() => _v('lng_theme_sure_keep');
  static String lngThemeReverting(int count) => _vc('lng_theme_reverting', count);
  static String lngThemeKeepChanges() => _v('lng_theme_keep_changes');
  static String lngThemeRevert() => _v('lng_theme_revert');

  // Passcode lock (window_lock_widgets.cpp)
  static String lngPasscodeEnter() => _v('lng_passcode_enter');
  static String lngPasscodePh() => _v('lng_passcode_ph');
  static String lngPasscodeSubmit() => _v('lng_passcode_submit');
  static String lngPasscodeLogout() => _v('lng_passcode_logout');
  static String lngPasscodeWrong() => _v('lng_passcode_wrong');
  static String lngPasscodeLogoutSure() => _v('lng_sure_logout');
  // System-unlock info label shown on the cold-start lock (domain not started),
  // beneath the logout link. AyuGram's lng_passcode_winhello / _touchid /
  // _applewatch / _systempwd (window_lock_widgets.cpp:132-161).
  static String lngPasscodeWinhello() => _v('lng_passcode_winhello');
  static String lngPasscodeTouchid() => _v('lng_passcode_touchid');
  static String lngPasscodeApplewatch() => _v('lng_passcode_applewatch');
  static String lngPasscodeSystempwd() => _v('lng_passcode_systempwd');
  static String lngCancel() => _v('lng_cancel');
  // FileSizeLimitBox / SimpleLimitBox — over-sized-document upload box
  // (premium_limits_box.cpp:1009-1064, triggered by FileLoadTask::finish at
  // localimageloader.cpp:1058-1069; lang.strings:267-271,285,125). The body
  // states the real backend upload limit (bold, e.g. "4 GB") via the {size}
  // placeholder, with a Premium-doubling upsell when Premium would still accept
  // the file. lngFileSizeLimitGb mirrors lng_file_size_limit#one/#other.
  static String lngFileSizeLimitTitle() => _v('lng_file_size_limit_title');
  static String lngFileSizeLimitGb(int count) => _vc('lng_file_size_limit', count);
  static String lngFileSizeLimit1(String size) =>
      _vf('lng_file_size_limit1', {'size': size});
  static String lngFileSizeLimit2(String size) =>
      _vf('lng_file_size_limit2', {'size': size});
  static String lngLimitsIncrease() => _v('lng_limits_increase');
  static String lngBoxOk() => _v('lng_box_ok');
  static String lngFloodError() => _v('lng_flood_error');

  // Dialog text formatting (dialogs_message_view.cpp:587-595): "{from}:" wraps
  // the sender, then "{from_part} {message}" joins it to the preview — so the
  // colon (and any future RTL ordering) comes from the cloud pack, not us.
  static String lngDialogsTextWithFrom(String from, String message) {
    final fromPart = _vf('lng_dialogs_text_from_wrapped', {'from': from});
    return _vf('lng_dialogs_text_with_from',
        {'from_part': fromPart, 'message': message});
  }

  // Native notification action buttons (lang.strings: lng_open_link,
  // lng_context_mark_read, lng_notification_reply)
  static String lngOpenLink() => _v('lng_open_link');
  static String lngContextMarkRead() => _v('lng_context_mark_read');
  static String lngNotificationReply() => _v('lng_notification_reply');

  // Notification grouping (notifications_manager.cpp)
  static String lngForwardMessages(int count) =>
      _vc('lng_forward_messages', count);
  static String lngInDlgAlbum() => _v('lng_in_dlg_album');

  // Notification content (notification_types.dart)
  static String lngNotifNewMessage() => _v('lng_notification_preview');
  static String lngNotifReminder() => _v('lng_notification_reminder');
  static String lngNotifYou() => _v('lng_from_you');
  static String lngNotifPhoto() => _v('lng_in_dlg_photo');
  static String lngNotifVideo() => _v('lng_in_dlg_video');
  static String lngNotifAudioFile() => _v('lng_in_dlg_audio_file');
  static String lngNotifVoiceMessage() => _v('lng_in_dlg_audio');
  static String lngNotifVideoMessage() => _v('lng_in_dlg_video_message');
  // One-time (self-destruct / view-once, media->ttlSeconds() set) voice & video
  // messages. lng_in_dlg_voice_message_ttl / lng_in_dlg_video_message_ttl
  // (lang.strings:4554-4555), chosen by MediaFile::notificationText() over the
  // plain variants (data_media_types.cpp:1273-1286).
  static String lngNotifVoiceMessageTtl() => _v('lng_in_dlg_voice_message_ttl');
  static String lngNotifVideoMessageTtl() => _v('lng_in_dlg_video_message_ttl');
  static String lngNotifSticker() => _v('lng_in_dlg_sticker');
  // AyuGram emits a literal u"GIF"_q for animations (data_media_types.cpp:1229),
  // NOT a lang key — so this stays hardcoded, matching the original.
  static String lngNotifGif() => 'GIF';
  static String lngNotifFile() => _v('lng_in_dlg_file');
  static String lngNotifPoll() => _v('lng_in_dlg_poll');
  static String lngNotifLocation() => _v('lng_maps_point');
  static String lngNotifLiveLocation() => _v('lng_live_location');
  static String lngNotifContact() => _v('lng_in_dlg_contact');
  static String lngNotifInvoice() => _v('lng_payments_invoice_label');
  static String lngNotifVotedInPoll() => _v('lng_poll_vote_notext');
  static String lngNotifVotedFor(String option) =>
      _vf('lng_poll_vote_option', {'option': option});
  static String lngNotifVotedInPollNamed(String question) =>
      _vf('lng_poll_vote', {'title': question});
  static String lngNotifReactedToMessage(String emoji) =>
      _vf('lng_reaction_notext', {'reaction': emoji});
  static String lngNotifReactedToPhoto(String emoji) =>
      _vf('lng_reaction_photo', {'reaction': emoji});
  static String lngNotifReactedToVideo(String emoji) =>
      _vf('lng_reaction_video', {'reaction': emoji});
  static String lngNotifReactedToFile(String emoji) =>
      _vf('lng_reaction_document', {'reaction': emoji});
  static String lngNotifReactedToVoice(String emoji) =>
      _vf('lng_reaction_voice_message', {'reaction': emoji});
  static String lngNotifReactedToVideoMsg(String emoji) =>
      _vf('lng_reaction_video_message', {'reaction': emoji});
  static String lngNotifReactedToSticker(String emoji, String stickerEmoji) =>
      _vf('lng_reaction_sticker', {'reaction': emoji, 'emoji': stickerEmoji});
  // Empty-emoji fallback: AyuGram has no dedicated key (it would render
  // lng_reaction_sticker with a blank {emoji}, "X to your  sticker"); the clean
  // single-spaced form here is a UniClient convenience and stays hardcoded.
  static String lngNotifReactedToStickerPlain(String emoji) =>
      '$emoji to your sticker';
  static String lngNotifReactedToGif(String emoji) =>
      _vf('lng_reaction_gif', {'reaction': emoji});
  static String lngNotifReactedToPoll(String emoji, String question) =>
      question.isEmpty
          ? '$emoji to your poll'
          : _vf('lng_reaction_poll', {'reaction': emoji, 'title': question});
  static String lngNotifReactedToQuiz(String emoji, String question) =>
      question.isEmpty
          ? '$emoji to your quiz'
          : _vf('lng_reaction_quiz', {'reaction': emoji, 'title': question});
  static String lngNotifReactedToLocation(String emoji) =>
      _vf('lng_reaction_location', {'reaction': emoji});
  static String lngNotifReactedToContact(String emoji, String name) =>
      _vf('lng_reaction_contact', {'reaction': emoji, 'name': name});
  // Empty-name fallback: AyuGram has no dedicated key; stays hardcoded like the
  // sticker-plain variant above.
  static String lngNotifReactedToContactPlain(String emoji) =>
      '$emoji to your contact';
  static String lngNotifReactedToGame(String emoji) =>
      _vf('lng_reaction_game', {'reaction': emoji});
  static String lngNotifReactedToInvoice(String emoji) =>
      _vf('lng_reaction_invoice', {'reaction': emoji});
  static String lngNotifReactedToText(String emoji, String text) =>
      _vf('lng_reaction_text', {'reaction': emoji, 'text': text});

  // Report reactions (info_profile_actions.cpp:1302-1339)
  static String lngReportReactionTitle() => _v('lng_report_reaction_title');
  static String lngReportReactionAbout() => _v('lng_report_reaction_about');
  static String lngReportAndBanButton() => _v('lng_report_and_ban_button');

  // Report message chooser (lang.strings lng_report_select_messages /
  // lng_report_please_select_messages → mainwidget.cpp:1291)
  static String lngReportSelectMessages() => _v('lng_report_select_messages');
  static String lngReportPleaseSelectMessages() =>
      _v('lng_report_please_select_messages');

  // Auto-delete (delete_messages_box.cpp:306-315)
  static String lngEnableAutoDelete() => _v('lng_enable_auto_delete');
  static String lngEditAutoDeleteSettings() =>
      _v('lng_edit_auto_delete_settings');

  // Paid post types (delete_messages_box.cpp:563-576)
  static String lngSuggestWarnTitleTon() => _v('lng_suggest_warn_title_ton');
  static String lngSuggestWarnTitleStars() => _v('lng_suggest_warn_title_stars');
  static String lngSuggestWarnTextTon() => _v('lng_suggest_warn_text_ton');
  static String lngSuggestWarnTextStars() => _v('lng_suggest_warn_text_stars');
  static String lngSuggestWarnDeleteAnyway() =>
      _v('lng_suggest_warn_delete_anyway');

  // Delete chat box (moderate_messages_box.cpp:1020-1066)
  static String lngProfileDeleteConversation() =>
      _v('lng_profile_delete_conversation');
  static String lngProfileBlockBot() => _v('lng_profile_block_bot');
  static String lngFiltersCheckboxRemoveBot() =>
      _v('lng_filters_checkbox_remove_bot');
  static String lngFiltersCheckboxRemoveChannel() =>
      _v('lng_filters_checkbox_remove_channel');
  static String lngFiltersCheckboxRemoveGroup() =>
      _v('lng_filters_checkbox_remove_group');

  // Common dialog buttons (edit_mark_box.cpp:44-58, layers.style)
  static String lngSettingsSave() => _v('lng_settings_save');
  static String lngAyuBoxActionReset() => _v('ayu_BoxActionReset');
  // Photo-editor brush color box positive button (color_picker.cpp:759,
  // lang.strings:126)
  static String lngBoxDone() => _v('lng_box_done');

  // Chat-accent color picker box title (settings_chat.cpp:395, lang.strings:858)
  static String lngSettingsThemeAccentTitle() =>
      _v('lng_settings_theme_accent_title');

  // Auto-delete timer box (auto_delete_settings.cpp, lang.strings:2162-2175)
  static String lngManageMessagesTtlTitle() =>
      _v('lng_manage_messages_ttl_title');
  static String lngManageMessagesTtlDisable() =>
      _v('lng_manage_messages_ttl_disable');
  static String lngManageMessagesTtlAfter1() =>
      _v('lng_manage_messages_ttl_after1');
  static String lngManageMessagesTtlAfter2() =>
      _v('lng_manage_messages_ttl_after2');
  static String lngManageMessagesTtlAfter3() =>
      _v('lng_manage_messages_ttl_after3');
  static String lngTtlEditAbout(String user) =>
      _vf('lng_ttl_edit_about', {'user': user});
  static String lngTtlEditAboutGroup() => _v('lng_ttl_edit_about_group');
  static String lngTtlEditAboutChannel() => _v('lng_ttl_edit_about_channel');
  static String lngTtlEditAbout2(String link) =>
      _vf('lng_ttl_edit_about2', {'link': link});
  static String lngTtlEditAbout2Link() => _v('lng_ttl_edit_about2_link');

  // Localized default "edited" mark (lang.strings:2838 "lng_edited" = "edited").
  // AyuGram seeds the edited-mark default and the EditMarkBox with
  // tr::lng_edited(tr::now) (ayu_settings.cpp:358, settings_chats.cpp:189),
  // so non-English users get their localized word instead of literal "edited".
  static String lngEdited() => _v('lng_edited');

  // Active sessions termination (settings_active_sessions.cpp,
  // self_destruction_box.cpp). Confirm-box copy matches AyuGram's
  // Ui::MakeConfirmBox + st::attentionBoxButton ("Terminate") usage.
  static String lngSettingsResetButton() => _v('lng_settings_reset_button');
  static String lngSettingsResetOneSure() => _v('lng_settings_reset_one_sure');
  static String lngSettingsResetSure() => _v('lng_settings_reset_sure');
  static String lngSelfDestructSessionsTitle() =>
      _v('lng_self_destruct_sessions_title');
  static String lngSelfDestructSessionsDescription() =>
      _v('lng_self_destruct_sessions_description');

  // Active Sessions screen — section/row labels & about paragraphs, resolved
  // 1:1 from lang.strings so the screen localizes instead of shipping inline
  // English literals (settings_active_sessions.cpp + api_authorizations.cpp).
  static String lngSettingsSessionsTitle() => _v('lng_settings_sessions_title');
  static String lngSessionsHeader() => _v('lng_sessions_header');
  static String lngSettingsRenameDevice() => _v('lng_settings_rename_device');
  static String lngSettingsRenameDeviceTitle() =>
      _v('lng_settings_rename_device_title');
  static String lngSettingsDeviceName() => _v('lng_settings_device_name');
  static String lngSessionsTerminateAll() => _v('lng_sessions_terminate_all');
  static String lngSessionsTerminateAllAbout() =>
      _v('lng_sessions_terminate_all_about');
  static String lngSessionsIncomplete() => _v('lng_sessions_incomplete');
  static String lngSessionsIncompleteAbout() =>
      _v('lng_sessions_incomplete_about');
  static String lngSessionsOtherHeader() => _v('lng_sessions_other_header');
  static String lngSessionsAboutApps() => _v('lng_sessions_about_apps');
  static String lngSessionsOtherDesc() => _v('lng_sessions_other_desc');
  static String lngSettingsTerminateTitle() =>
      _v('lng_settings_terminate_title');
  static String lngSettingsTerminateIf() => _v('lng_settings_terminate_if');
  // Session info box (settings_active_sessions.cpp:451-486).
  static String lngSessionsInfo() => _v('lng_sessions_info');
  static String lngSessionsApplication() => _v('lng_sessions_application');
  static String lngSessionsSystem() => _v('lng_sessions_system');
  static String ayuSessionInfoOfficialApp() => _v('ayu_SessionInfoOfficialApp');
  static String lngBoxYes() => _v('lng_box_yes');
  static String lngBoxNo() => _v('lng_box_no');
  static String lngSessionsIp() => _v('lng_sessions_ip');
  static String lngSessionsLocation() => _v('lng_sessions_location');
  static String lngSessionsLocationAbout() => _v('lng_sessions_location_about');
  static String lngSessionsTerminate() => _v('lng_sessions_terminate');
  static String lngAboutDone() => _v('lng_about_done');
  static String lngContactsLoading() => _v('lng_contacts_loading');

  // AyuForward status strings (ayu_forward.cpp:64-89). AyuGram-custom `ayu_*`
  // keys — absent from Telegram's cloud pack, so they resolve to the English
  // baseline registered in LangPack.
  static String lngAyuForwardStatusPreparing() =>
      _v('ayu_AyuForwardStatusPreparing');
  static String lngAyuForwardStatusForwarding() =>
      _v('ayu_AyuForwardStatusForwarding');
  static String lngAyuForwardStatusLoadingMedia() =>
      _v('ayu_AyuForwardStatusLoadingMedia');
  static String lngAyuForwardStatusFinished() =>
      _v('ayu_AyuForwardStatusFinished');
  static String lngAyuForwardStatusSentCount(int sent, int total) => _vf(
      'ayu_AyuForwardStatusSentCount',
      {'count1': '$sent', 'count2': '$total'});
  static String lngAyuForwardStatusChunkCount(int chunk, int total) => _vf(
      'ayu_AyuForwardStatusChunkCount',
      {'count1': '$chunk', 'count2': '$total'});
}
