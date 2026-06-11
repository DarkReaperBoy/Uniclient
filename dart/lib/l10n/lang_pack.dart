import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../utils/debug.dart';
import 'lang_plural.dart';

/// App localization backed by Telegram's cloud language pack.
///
/// Mirrors AyuGram building every intro string from the lang pack
/// (`tr::lng_phone_title`, `tr::lng_intro_qr_step1..3`, … — intro_phone.cpp:92,
/// intro_qr.cpp): picking a language re-renders the UI in that language. The
/// English values below are the embedded baseline (Telegram Desktop ships
/// English built-in, `lang.strings`); non-English strings are fetched on demand
/// from the engine's cloud pack via `langpack.getStrings`, which is an
/// unauthorized MTProto method and so works mid-login (served by the core's
/// preAuthAPI). Lookups resolve server overlay → English baseline → raw key, so
/// the UI never renders blank when a string or the network is missing.
class LangPack extends ChangeNotifier {
  LangPack(this._engine) {
    // Register as the active (global) instance so the static [TrStrings] lang-
    // pack table can resolve keys WITHOUT a BuildContext — mirroring AyuGram's
    // `tr::lng_*(tr::now)` → `Lang::GetInstance().getValue(key)` global singleton
    // (lang_instance.h:90). The app constructs exactly one LangPack (main.dart),
    // and [setLanguage] mutates its overlay in place, so `instance` never goes
    // stale: `TrStrings.lngXxx()` always reflects the currently selected language.
    instance = this;
  }

  final EngineService _engine;

  /// The active language instance — AyuGram's global `Lang::GetInstance()`.
  /// Consulted by the static [TrStrings] table so notification/dialog/box copy
  /// localizes through the cloud overlay just like the intro/login screen. Null
  /// only before the first LangPack is constructed (very early startup / widget
  /// tests with no provider), where [TrStrings] falls back to the embedded
  /// English baseline via [baseline]/[baselineF]/[baselineCount].
  static LangPack? instance;

  String _code = 'en';
  String get code => _code;

  Map<String, String> _overlay = const {};

  /// Cloud-pack keys we fetch for the intro/login screen. These are the strings
  /// AyuGram pulls from `tr::lng_*` on the phone/QR/code steps.
  static const List<String> keys = [
    'lng_phone_title',
    // Persistent "Quick log in using QR code" link on the phone step
    // (intro_phone.cpp:114).
    'lng_phone_to_qr',
    'lng_intro_qr_title',
    'lng_intro_qr_step1',
    'lng_intro_qr_step2',
    'lng_intro_qr_step3',
    'lng_intro_qr_phone',
    'lng_intro_qr_passkey',
    'lng_code_call',
    'lng_code_calling',
    'lng_code_called',
    'lng_intro_next',
    'lng_intro_finish',
    // Code step (intro_code.cpp): the "send via SMS" link shown when the code
    // arrived via the Telegram app, the Fragment title/instruction, and the
    // three delivery-specific subtitles updateDescText picks between
    // (intro_code.cpp:83-115).
    'lng_code_no_telegram',
    'lng_intro_fragment_title',
    'lng_intro_fragment_about',
    'lng_code_desc',
    'lng_code_from_telegram',
    'lng_intro_email_confirm_subtitle',
    // 2FA / cloud-password step (intro_password_check.cpp:55,358) + recovery /
    // account-reset texts (intro_password_check.cpp:316,350; intro_widget.cpp:570-628).
    'lng_signin_title',
    'lng_signin_desc',
    // 2FA field labels + recovery links (intro_password_check.cpp:35-39):
    // password / recovery-code field placeholders and the forgot/try-password
    // links shown below the field.
    'lng_signin_password',
    'lng_signin_code',
    'lng_signin_recover',
    'lng_signin_try_password',
    'lng_signin_recover_desc',
    'lng_signin_no_email_forgot',
    'lng_signin_sure_reset',
    'lng_signin_reset',
    'lng_signin_reset_in_days',
    'lng_signin_reset_in_hours',
    'lng_signin_reset_wait',
    'lng_days',
    'lng_hours',
    'lng_minutes',
    // Signup step (intro_signup.cpp:53-54): title, description, field labels,
    // and the name-ordering probe string.
    'lng_signup_title',
    'lng_signup_desc',
    'lng_signup_firstname',
    'lng_signup_lastname',
    'lng_full_name',
    // Login-email setup step (intro_email.cpp:45,53,74).
    'lng_intro_email_setup_title',
    'lng_settings_cloud_login_email_about',
    'lng_settings_cloud_login_email_placeholder',
    // Intro/login error + button strings, sourced from the cloud pack so the
    // whole flow localizes instead of mixing English error text into a
    // non-English session. 2FA errors + hint (intro_password_check.cpp:142,151,
    // 264,61-64), email-setup errors (intro_email.cpp:111-122), phone errors +
    // banned box (intro_phone.cpp:178,271,283 → phone_banned_box.cpp),
    // next-button labels (intro_code.cpp:428, intro_password_check.cpp:405-407),
    // and the language-switcher label (intro_widget.cpp:267-308).
    'lng_signin_bad_password',
    'lng_signin_wrong_code',
    'lng_flood_error',
    'lng_signin_hint',
    'lng_settings_error_email_not_alowed',
    'lng_cloud_password_bad_email',
    'lng_bad_phone',
    'lng_signin_banned_text',
    'lng_signin_banned_help',
    'lng_box_ok',
    'lng_intro_fragment_button',
    'lng_intro_submit',
    'lng_languages',
    // Forum row topics-preview empty state (dialogs_topics_view.cpp:212-214):
    // shown in a collapsed forum dialog row when it has no recent topics.
    'lng_filters_no_chats',
    'lng_contacts_loading',
    // Full month names for date wheels (birthday drum picker, info dates).
    // AyuGram `Lang::Month(n)` → `tr::lng_month1..12` (lang_keys.cpp:205-222,
    // lang.strings:37-48).
    'lng_month1', 'lng_month2', 'lng_month3', 'lng_month4',
    'lng_month5', 'lng_month6', 'lng_month7', 'lng_month8',
    'lng_month9', 'lng_month10', 'lng_month11', 'lng_month12',
    // --- TrStrings table (notifications, passcode, theme, sessions, reports,
    // auto-delete, paid-post warnings, file-size limits) ---
    // Every key below backs a `TrStrings.lngXxx()` accessor, ported 1:1 from
    // AyuGram `tr::lng_*` (Resources/langs/lang.strings). Registering them here
    // means a non-English session fetches their cloud values, so these strings
    // localize instead of always rendering the embedded English baseline.
    // `lng_intro_finish/_next/_submit`, `lng_flood_error`, `lng_box_ok`,
    // `lng_contacts_loading` are already fetched above — not repeated here.
    // Account-recovery copy (intro_password_check.cpp).
    'lng_signin_cant_email_forgot',
    // Theme-change confirmation overlay (window_theme_warning.cpp). `_reverting`
    // is a plural (lt_count) — fetched by base key, resolved via #form.
    'lng_theme_sure_keep', 'lng_theme_reverting', 'lng_theme_keep_changes',
    'lng_theme_revert',
    // Passcode lock (window_lock_widgets.cpp).
    'lng_passcode_enter', 'lng_passcode_ph', 'lng_passcode_submit',
    'lng_passcode_logout', 'lng_passcode_wrong', 'lng_sure_logout',
    'lng_passcode_winhello', 'lng_passcode_touchid', 'lng_passcode_applewatch',
    'lng_passcode_systempwd', 'lng_cancel',
    // Over-sized-document upload box (premium_limits_box.cpp). `_limit` is the
    // "{count} GB" plural.
    'lng_file_size_limit_title', 'lng_file_size_limit', 'lng_file_size_limit1',
    'lng_file_size_limit2', 'lng_limits_increase',
    // Dialog last-message prefix (dialogs_message_view.cpp): "{from}:" wraps the
    // sender, then "{from_part} {message}" joins it to the preview.
    'lng_dialogs_text_with_from', 'lng_dialogs_text_from_wrapped',
    // Native notification action buttons + grouping (notifications_manager.cpp).
    // `_forward_messages` is a plural (lt_count).
    'lng_open_link', 'lng_context_mark_read', 'lng_notification_reply',
    'lng_forward_messages', 'lng_in_dlg_album',
    // Notification preview content — media type strings & reminder/you headers
    // (data_media_types.cpp, history_item.cpp, notifications_manager.cpp).
    'lng_notification_preview', 'lng_notification_reminder', 'lng_from_you',
    'lng_in_dlg_photo', 'lng_in_dlg_video', 'lng_in_dlg_audio_file',
    'lng_in_dlg_audio', 'lng_in_dlg_video_message', 'lng_in_dlg_voice_message_ttl',
    'lng_in_dlg_video_message_ttl', 'lng_in_dlg_sticker', 'lng_in_dlg_file',
    'lng_in_dlg_poll', 'lng_maps_point', 'lng_live_location', 'lng_in_dlg_contact',
    'lng_payments_invoice_label',
    // Poll-vote notification text (notifications_manager.cpp:1222-).
    'lng_poll_vote_notext', 'lng_poll_vote_option', 'lng_poll_vote',
    // Reaction notification text (notifications_manager.cpp:1150-1219). Tokens:
    // {reaction}, plus {emoji}/{name}/{title}/{text} on the typed variants.
    'lng_reaction_notext', 'lng_reaction_photo', 'lng_reaction_video',
    'lng_reaction_document', 'lng_reaction_voice_message',
    'lng_reaction_video_message', 'lng_reaction_sticker', 'lng_reaction_gif',
    'lng_reaction_location', 'lng_reaction_contact', 'lng_reaction_game',
    'lng_reaction_invoice', 'lng_reaction_text', 'lng_reaction_poll',
    'lng_reaction_quiz',
    // Report-reaction / report-message boxes (info_profile_actions.cpp,
    // mainwidget.cpp).
    'lng_report_reaction_title', 'lng_report_reaction_about',
    'lng_report_and_ban_button', 'lng_report_select_messages',
    'lng_report_please_select_messages',
    // Auto-delete toggle + paid-post (TON/Stars) delete warnings
    // (delete_messages_box.cpp).
    'lng_enable_auto_delete', 'lng_edit_auto_delete_settings',
    'lng_suggest_warn_title_ton', 'lng_suggest_warn_title_stars',
    'lng_suggest_warn_text_ton', 'lng_suggest_warn_text_stars',
    'lng_suggest_warn_delete_anyway',
    // Delete-chat / leave box (moderate_messages_box.cpp).
    'lng_profile_delete_conversation', 'lng_profile_block_bot',
    'lng_filters_checkbox_remove_bot', 'lng_filters_checkbox_remove_channel',
    'lng_filters_checkbox_remove_group',
    // Common dialog buttons + accent-color box title (layers.style,
    // color_picker.cpp, settings_chat.cpp).
    'lng_settings_save', 'lng_box_done', 'lng_settings_theme_accent_title',
    // Auto-delete timer box (auto_delete_settings.cpp). `_about` carries {user},
    // `_about2` carries {link}.
    'lng_manage_messages_ttl_title', 'lng_manage_messages_ttl_disable',
    'lng_manage_messages_ttl_after1', 'lng_manage_messages_ttl_after2',
    'lng_manage_messages_ttl_after3', 'lng_ttl_edit_about',
    'lng_ttl_edit_about_group', 'lng_ttl_edit_about_channel',
    'lng_ttl_edit_about2', 'lng_ttl_edit_about2_link',
    // Localized "edited" mark (ayu_settings.cpp seeds tr::lng_edited).
    'lng_edited',
    // Active sessions screen + termination confirm boxes
    // (settings_active_sessions.cpp, self_destruction_box.cpp).
    'lng_settings_reset_button', 'lng_settings_reset_one_sure',
    'lng_settings_reset_sure', 'lng_self_destruct_sessions_title',
    'lng_self_destruct_sessions_description', 'lng_settings_sessions_title',
    'lng_sessions_header', 'lng_settings_rename_device',
    'lng_settings_rename_device_title', 'lng_settings_device_name',
    'lng_sessions_terminate_all', 'lng_sessions_terminate_all_about',
    'lng_sessions_incomplete', 'lng_sessions_incomplete_about',
    'lng_sessions_other_header', 'lng_sessions_about_apps',
    'lng_sessions_other_desc', 'lng_settings_terminate_title',
    'lng_settings_terminate_if', 'lng_sessions_info', 'lng_sessions_application',
    'lng_sessions_system', 'lng_box_yes', 'lng_box_no', 'lng_sessions_ip',
    'lng_sessions_location', 'lng_sessions_location_about',
    'lng_sessions_terminate', 'lng_about_done',
    // NOTE: AyuGram-custom `ayu_*` keys (AyuForward status, the EditMark "Reset"
    // button, "Official app") are NOT requested here — they live in AyuGram's
    // own translation source, not Telegram's `tdesktop` cloud pack, so the
    // server returns nothing for them. They resolve to the embedded English
    // baseline below (the honest best-effort; Telegram cloud can't localize them).
  ];

  /// Embedded English baseline (Telegram Desktop `lang.strings`). Kept in sync
  /// with [keys]. Most entries are plain text; the code/2FA/reset descriptions
  /// carry `\n` line breaks and `lng_code_from_telegram` keeps Telegram's `**`
  /// bold markers — callers that render these strip `**` (the intro has no
  /// rich-text label), so the raw values stay 1:1 with `lang.strings`.
  static const Map<String, String> _en = {
    'lng_phone_title': 'Your Phone Number',
    'lng_phone_to_qr': 'Quick log in using QR code',
    'lng_intro_qr_title': 'Scan From Mobile Telegram',
    'lng_intro_qr_step1': 'Open Telegram on your phone',
    'lng_intro_qr_step2': 'Go to Settings > Devices > Link Desktop Device',
    'lng_intro_qr_step3': 'Scan this image to Log In',
    'lng_intro_qr_phone': 'Log in using phone number',
    'lng_intro_qr_passkey': 'Log in using passkey',
    'lng_code_call': 'Telegram will call you in {minutes}:{seconds}',
    'lng_code_calling': 'Requesting a call from Telegram...',
    'lng_code_called': 'Telegram dialed your number',
    'lng_intro_next': 'Next',
    'lng_intro_finish': 'Sign Up',
    'lng_code_no_telegram': 'Send code via SMS',
    'lng_intro_fragment_title': 'Enter code',
    'lng_intro_fragment_about':
        'Get the code for {phone_number} in the Anonymous Numbers section on '
        'Fragment.',
    'lng_code_desc':
        'We\'ve sent an activation code to your phone.\nPlease enter it below.',
    'lng_code_from_telegram':
        'A code was sent **via Telegram** to your other\ndevices, if you have '
        'any connected.',
    'lng_intro_email_confirm_subtitle':
        'Please check your email {email} (don\'t forget the spam folder) and '
        'enter the code we just sent you.',
    'lng_signin_title': 'Cloud password check',
    'lng_signin_desc': 'Please enter your cloud password.',
    'lng_signin_password': 'Your cloud password',
    'lng_signin_code': 'Code from the email',
    'lng_signin_recover': 'Forgot password?',
    'lng_signin_try_password': 'Unable to access your email?',
    'lng_signin_recover_desc': 'Please enter the code from the email\n{email}',
    'lng_signin_no_email_forgot':
        'Since you didn\'t provide a recovery email when setting up your '
        'password, your remaining options are either to remember your password '
        'or to reset your account.',
    'lng_signin_sure_reset':
        'You will lose all your Telegram chats, messages, media and files if '
        'you proceed.\n\nDo you want to reset your account?',
    'lng_signin_reset': 'Reset',
    'lng_signin_reset_in_days': '{days_count} {hours_count} {minutes_count}',
    'lng_signin_reset_in_hours': '{hours_count} {minutes_count}',
    'lng_signin_reset_wait':
        'Since the account {phone_number} is active and protected by a '
        'password, it will be deleted in 1 week. This delay is required for '
        'security purposes. You can cancel this process anytime.\n\nYou\'ll be '
        'able to reset your account in:\n{when}',
    'lng_days#one': '{count} day',
    'lng_days#other': '{count} days',
    'lng_hours#one': '{count} hour',
    'lng_hours#other': '{count} hours',
    'lng_minutes#one': '{count} minute',
    'lng_minutes#other': '{count} minutes',
    'lng_signup_title': 'Your Info',
    'lng_signup_desc': 'Please enter your name and\nupload a photo.',
    'lng_signup_firstname': 'First name',
    'lng_signup_lastname': 'Last name',
    'lng_full_name': '{first_name} {last_name}',
    'lng_intro_email_setup_title': 'Choose a login email',
    'lng_settings_cloud_login_email_about':
        'You will receive Telegram login codes via email and not SMS. Please '
        'enter an email address to which you have access.',
    'lng_settings_cloud_login_email_placeholder': 'Enter Login Email',
    // Intro/login error + button strings (English baseline = lang.strings).
    'lng_signin_bad_password': 'You have entered a wrong password.',
    'lng_signin_wrong_code': 'You have entered an invalid code.',
    'lng_flood_error': 'Too many tries. Please try again later.',
    'lng_signin_hint': 'Hint: {password_hint}',
    'lng_settings_error_email_not_alowed': 'Sorry, this email is not allowed',
    'lng_cloud_password_bad_email': 'Invalid email',
    'lng_bad_phone': 'Invalid phone number. Please try again.',
    'lng_signin_banned_text': 'This phone number is banned.',
    'lng_signin_banned_help': 'Help',
    'lng_box_ok': 'OK',
    'lng_intro_fragment_button': 'Open Fragment',
    'lng_intro_submit': 'Submit',
    'lng_languages': 'Language',
    'lng_filters_no_chats': 'No chats',
    'lng_contacts_loading': 'Loading...',
    // Full month names — AyuGram `Lang::Month(n)` baseline (lang.strings:37-48).
    'lng_month1': 'January',
    'lng_month2': 'February',
    'lng_month3': 'March',
    'lng_month4': 'April',
    'lng_month5': 'May',
    'lng_month6': 'June',
    'lng_month7': 'July',
    'lng_month8': 'August',
    'lng_month9': 'September',
    'lng_month10': 'October',
    'lng_month11': 'November',
    'lng_month12': 'December',
    // --- TrStrings table baseline (English = lang.strings, verified 1:1) ---
    // Account recovery (lang.strings:440).
    'lng_signin_cant_email_forgot':
        "If you can't restore access to the email, your remaining options are "
        'either to remember your password or to reset your account.',
    // Theme-change confirmation overlay (lang.strings:1085-1089).
    'lng_theme_sure_keep': 'Keep this theme?',
    'lng_theme_reverting#one': 'Reverting to the old theme in {count} second.',
    'lng_theme_reverting#other': 'Reverting to the old theme in {count} seconds.',
    'lng_theme_keep_changes': 'Keep changes',
    'lng_theme_revert': 'Revert',
    // Passcode lock (lang.strings:1171-1180, :1303).
    'lng_passcode_enter': 'Enter your local passcode',
    'lng_passcode_ph': 'Your passcode',
    'lng_passcode_submit': 'Submit',
    'lng_passcode_logout': 'Log out',
    'lng_passcode_wrong': 'Wrong passcode',
    'lng_sure_logout': 'Are you sure you want to log out?',
    'lng_passcode_winhello':
        'You need to enter your passcode\nbefore you can use Windows Hello.',
    'lng_passcode_touchid':
        'You need to enter your passcode\nbefore you can use Touch ID.',
    'lng_passcode_applewatch':
        'You need to enter your passcode\nbefore you can use Watch to unlock.',
    'lng_passcode_systempwd':
        'You need to enter your passcode\nbefore you can use system password.',
    'lng_cancel': 'Cancel',
    // Over-sized-document upload box (lang.strings:267-271,285). "{count} GB" is
    // the same in #one/#other (the unit, not the noun, is what's pluralized).
    'lng_file_size_limit_title': 'File Too Large',
    'lng_file_size_limit#one': '{count} GB',
    'lng_file_size_limit#other': '{count} GB',
    'lng_file_size_limit1':
        "The document can't be sent, because it is larger than {size}.",
    'lng_file_size_limit2':
        'You can double this limit to {size} per document by subscribing to '
        '**Telegram Premium**.',
    'lng_limits_increase': 'Increase Limit',
    // Dialog last-message prefix (lang.strings:4779-4780).
    'lng_dialogs_text_with_from': '{from_part} {message}',
    'lng_dialogs_text_from_wrapped': '{from}:',
    // Native notification actions + grouping (lang.strings:570,4831,5003,5309-5310,4547).
    'lng_open_link': 'Open',
    'lng_context_mark_read': 'Mark as read',
    'lng_notification_reply': 'Reply',
    'lng_forward_messages#one': '{count} forwarded message',
    'lng_forward_messages#other': '{count} forwarded messages',
    'lng_in_dlg_album': 'Album',
    // Notification preview content (lang.strings:569,573,4716,4546-4559,4958,4967,5770).
    'lng_notification_preview': 'You have a new message',
    'lng_notification_reminder': 'Reminder',
    'lng_from_you': 'You',
    'lng_in_dlg_photo': 'Photo',
    'lng_in_dlg_video': 'Video',
    'lng_in_dlg_audio_file': 'Audio file',
    'lng_in_dlg_audio': 'Voice message',
    'lng_in_dlg_video_message': 'Video message',
    'lng_in_dlg_voice_message_ttl': 'One-time Voice Message',
    'lng_in_dlg_video_message_ttl': 'One-time Video Message',
    'lng_in_dlg_sticker': 'Sticker',
    'lng_in_dlg_file': 'File',
    'lng_in_dlg_poll': 'Poll',
    'lng_maps_point': 'Location',
    'lng_live_location': 'Live Location',
    'lng_in_dlg_contact': 'Contact',
    'lng_payments_invoice_label': 'Invoice',
    // Poll-vote notification text (lang.strings:637-639).
    'lng_poll_vote_notext': 'voted in your poll',
    'lng_poll_vote_option': 'voted for "{option}" in your poll',
    'lng_poll_vote': 'voted in your poll "{title}"',
    // Reaction notification text (lang.strings:621-635).
    'lng_reaction_notext': '{reaction} to your message',
    'lng_reaction_photo': '{reaction} to your photo',
    'lng_reaction_video': '{reaction} to your video',
    'lng_reaction_document': '{reaction} to your file',
    'lng_reaction_voice_message': '{reaction} to your voice message',
    'lng_reaction_video_message': '{reaction} to your video message',
    'lng_reaction_sticker': '{reaction} to your {emoji} sticker',
    'lng_reaction_gif': '{reaction} to your GIF',
    'lng_reaction_location': '{reaction} to your map',
    'lng_reaction_contact': '{reaction} to your contact {name}',
    'lng_reaction_game': '{reaction} to your game',
    'lng_reaction_invoice': '{reaction} to your invoice',
    'lng_reaction_text': '{reaction} to your "{text}"',
    'lng_reaction_poll': '{reaction} to your poll "{title}"',
    'lng_reaction_quiz': '{reaction} to your quiz "{title}"',
    // Report boxes (lang.strings:2191-2200).
    'lng_report_reaction_title': 'Report reaction',
    'lng_report_reaction_about':
        'Are you sure you want to report reactions from this user?',
    'lng_report_and_ban_button': 'Ban user',
    'lng_report_select_messages': 'Select messages',
    'lng_report_please_select_messages': 'Please select messages to report.',
    // Auto-delete toggle + paid-post delete warnings (lang.strings:5558-5559,5418-5422).
    'lng_enable_auto_delete': 'Enable Auto-Delete',
    'lng_edit_auto_delete_settings': 'Edit Auto-Delete Settings',
    'lng_suggest_warn_title_ton': 'TON will be lost',
    'lng_suggest_warn_title_stars': 'Stars will be lost',
    'lng_suggest_warn_text_ton':
        "You won't receive **TON** for the post if you delete it now. The post "
        'must remain visible for at least **24 hours** after it was published.',
    'lng_suggest_warn_text_stars':
        "You won't receive **Stars** for the post if you delete it now. The "
        'post must remain visible for at least **24 hours** after it was published.',
    'lng_suggest_warn_delete_anyway': 'Delete Anyway',
    // Delete-chat / leave box (lang.strings:1625,1837,7139-7141).
    'lng_profile_delete_conversation': 'Delete chat',
    'lng_profile_block_bot': 'Stop and block bot',
    'lng_filters_checkbox_remove_bot': 'Remove bot from all folders',
    'lng_filters_checkbox_remove_channel': 'Remove channel from all folders',
    'lng_filters_checkbox_remove_group': 'Remove group from all folders',
    // Common buttons + accent-color box title (lang.strings:478,126,858).
    'lng_settings_save': 'Save',
    'lng_box_done': 'Done',
    'lng_settings_theme_accent_title': 'Choose accent color',
    // Auto-delete timer box (lang.strings:2162-2175).
    'lng_manage_messages_ttl_title': 'Auto-delete messages',
    'lng_manage_messages_ttl_disable': 'Disable',
    'lng_manage_messages_ttl_after1': '1 day',
    'lng_manage_messages_ttl_after2': '1 week',
    'lng_manage_messages_ttl_after3': '1 month',
    'lng_ttl_edit_about':
        'Automatically delete new messages for you and {user} after a certain '
        'period of time.',
    'lng_ttl_edit_about_group':
        'Automatically delete new messages sent in this chat after a certain '
        'period of time.',
    'lng_ttl_edit_about_channel':
        'Automatically delete new messages sent in this channel after a certain '
        'period of time.',
    'lng_ttl_edit_about2':
        'You can also set a default {link} for all your chats in Settings.',
    'lng_ttl_edit_about2_link': 'self-destruct timer',
    // Localized "edited" mark (lang.strings:2838).
    'lng_edited': 'edited',
    // Active sessions screen + termination confirm boxes (lang.strings:865,
    // 1283-1290,1370-1385,1579-1580).
    'lng_settings_reset_button': 'Terminate',
    'lng_settings_reset_one_sure': 'Do you want to terminate this session?',
    'lng_settings_reset_sure':
        'Are you sure you want to terminate\nall other sessions?',
    'lng_self_destruct_sessions_title': 'Session termination',
    'lng_self_destruct_sessions_description':
        "If you don't come online from a specific session at least once within "
        'this period, it will be terminated.',
    'lng_settings_sessions_title': 'Active sessions',
    'lng_sessions_header': 'This device',
    'lng_settings_rename_device': 'Rename',
    'lng_settings_rename_device_title': 'Rename current device',
    'lng_settings_device_name': 'Device name',
    'lng_sessions_terminate_all': 'Terminate all other sessions',
    'lng_sessions_terminate_all_about': 'Logs out all devices except for this one.',
    'lng_sessions_incomplete': 'Incomplete login attempts',
    'lng_sessions_incomplete_about':
        'The devices above have no access to your messages. The code was '
        'entered correctly, but no correct password was given.',
    'lng_sessions_other_header': 'Active Devices',
    'lng_sessions_about_apps':
        'The official Telegram app is available for Android, iPhone, iPad, '
        'Windows, macOS and Linux.',
    'lng_sessions_other_desc':
        'You can log in to Telegram from other mobile, tablet and desktop '
        'devices, using the same phone number. All your data will be '
        'instantly synchronized.',
    'lng_settings_terminate_title': 'Terminate old sessions',
    'lng_settings_terminate_if': 'If inactive for...',
    'lng_sessions_info': 'Info',
    'lng_sessions_application': 'Application',
    'lng_sessions_system': 'System version',
    'lng_box_yes': 'Yes',
    'lng_box_no': 'No',
    'lng_sessions_ip': 'IP address',
    'lng_sessions_location': 'Location',
    'lng_sessions_location_about':
        'This location estimate is based on the IP address and may not always '
        'be accurate.',
    'lng_sessions_terminate': 'Terminate Session',
    'lng_about_done': 'Done',
    // AyuGram-custom keys (lang.strings:8279,8323-8328,8373). Not on Telegram's
    // cloud pack, so these only ever resolve to this English baseline.
    'ayu_BoxActionReset': 'Reset',
    'ayu_SessionInfoOfficialApp': 'Official app',
    'ayu_AyuForwardStatusPreparing': 'Forwarding messages',
    'ayu_AyuForwardStatusForwarding': 'Forwarding messages',
    'ayu_AyuForwardStatusLoadingMedia': 'Loading media',
    'ayu_AyuForwardStatusFinished': 'Done',
    'ayu_AyuForwardStatusSentCount': 'sent {count1} of {count2}',
    'ayu_AyuForwardStatusChunkCount': 'chunk {count1} of {count2}',
  };

  /// Localized string: server overlay → English baseline → raw key.
  String tr(String key) => _overlay[key] ?? _en[key] ?? key;

  /// Localized string with `{name}` placeholder substitution.
  String trf(String key, Map<String, String> params) {
    var s = tr(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// Pluralized string for [count] with `{count}` substituted, applying the
  /// active language's full CLDR plural rule (zero/one/two/few/many/other) to
  /// pick the grammatical form — mirroring AyuGram `tr::lng_days(lt_count, n)`
  /// → `Lang::Plural()` → `ChoosePlural` (lang_tag.cpp). The engine's
  /// `langpack.getStrings` bridge now emits every form the server sent under a
  /// `key#form` suffix, so e.g. Russian `2` resolves `#few` ("2 дня") instead of
  /// always collapsing to `#other` ("2 дней").
  ///
  /// Fallback chain: the computed form in the server overlay → the overlay's
  /// `#other` (always present from the server, so a fetched language never falls
  /// through to English) → the English baseline's form → English `#other` →
  /// bare English → the raw key. English itself uses the embedded baseline (the
  /// `en` rule yields one/other, both present in [_en]).
  String trCount(String key, int count) {
    final form = pluralForm(_code, count);
    final v = _overlay['$key#$form'] ??
        _overlay['$key#other'] ??
        _en['$key#$form'] ??
        _en['$key#other'] ??
        _en[key] ??
        key;
    return v.replaceAll('{count}', '$count');
  }

  // --- Static (instance-free) baseline resolvers ---
  // Used by [TrStrings] when [instance] is null (early startup / tests). They
  // resolve against the embedded English [_en] baseline only — no cloud overlay,
  // since there is no active language. Mirror tr/trf/trCount minus the overlay.

  /// English baseline for [key] (overlay-free): `_en[key]` → raw key.
  static String baseline(String key) => _en[key] ?? key;

  /// English baseline for [key] with `{name}` placeholder substitution.
  static String baselineF(String key, Map<String, String> params) {
    var s = baseline(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// English baseline pluralized for [count] (`en` rule → one/other), with
  /// `{count}` substituted.
  static String baselineCount(String key, int count) {
    final form = pluralForm('en', count);
    final v = _en['$key#$form'] ?? _en['$key#other'] ?? _en[key] ?? key;
    return v.replaceAll('{count}', '$count');
  }

  /// Whether the active language orders the family name *before* the given
  /// name, so the signup form should put the last-name field first.
  ///
  /// Mirrors AyuGram `langFirstNameGoesSecond()` (lang_keys.cpp:59-69): it
  /// renders `lng_full_name` with sentinel first/last tokens and checks whether
  /// the last name appears before the first. This is keyed to name *ordering*,
  /// NOT text *direction* — East-Asian/Hungarian (ja/ko/zh/hu, all LTR) invert,
  /// while RTL languages (ar/fa) keep the first-name field first.
  bool get firstNameGoesSecond {
    final first = String.fromCharCode(1);
    final last = String.fromCharCode(2);
    final full =
        trf('lng_full_name', {'first_name': first, 'last_name': last});
    return full.indexOf(last) < full.indexOf(first);
  }

  /// Switch the active language. English uses the embedded baseline; other
  /// languages are fetched from the cloud pack (best-effort — keeps English on
  /// failure). [accountId] is the account whose connection performs the fetch;
  /// during login this is the in-progress account, which `langpack.getStrings`
  /// serves pre-auth.
  Future<void> setLanguage(String code, {String? accountId}) async {
    if (code.isEmpty) code = 'en';
    final changed = _code != code;
    _code = code;
    if (code == 'en') {
      _overlay = const {};
      if (changed) notifyListeners();
      return;
    }
    // Reflect the selection immediately on the English baseline — drop any
    // previous language's overlay first, so switching A→B never leaves A's
    // strings on screen while B is fetched. Then overlay B's cloud strings once
    // fetched. If the fetch comes back empty (Telegram ships no `tdesktop` pack
    // for this language — e.g. a community/RTL language not translated for
    // Desktop), we stay on the English baseline, exactly as AyuGram falls back
    // to its built-in English when the cloud pack lacks a string.
    _overlay = const {};
    notifyListeners();
    if (accountId == null || accountId.isEmpty) return;
    try {
      final fetched = await _engine.getLangStrings(accountId, code, keys);
      if (fetched.isNotEmpty && _code == code) {
        _overlay = fetched;
        notifyListeners();
      }
    } catch (e) {
      Debug.error('L10N', 'lang fetch failed for $code', e);
    }
  }
}
