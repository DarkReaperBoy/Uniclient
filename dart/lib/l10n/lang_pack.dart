import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../utils/debug.dart';

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
  LangPack(this._engine);

  final EngineService _engine;

  String _code = 'en';
  String get code => _code;

  Map<String, String> _overlay = const {};

  /// Cloud-pack keys we fetch for the intro/login screen. These are the strings
  /// AyuGram pulls from `tr::lng_*` on the phone/QR/code steps.
  static const List<String> keys = [
    'lng_phone_title',
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
    // Login-email setup step (intro_email.cpp:45,53).
    'lng_intro_email_setup_title',
    'lng_settings_cloud_login_email_about',
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
  ];

  /// Embedded English baseline (Telegram Desktop `lang.strings`). Kept in sync
  /// with [keys]. Most entries are plain text; the code/2FA/reset descriptions
  /// carry `\n` line breaks and `lng_code_from_telegram` keeps Telegram's `**`
  /// bold markers — callers that render these strip `**` (the intro has no
  /// rich-text label), so the raw values stay 1:1 with `lang.strings`.
  static const Map<String, String> _en = {
    'lng_phone_title': 'Your Phone Number',
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
  };

  /// Localized string: server overlay → English baseline → raw key.
  String tr(String key) => _overlay[key] ?? _en[key] ?? key;

  /// Localized string with `{name}` placeholder substitution.
  String trf(String key, Map<String, String> params) {
    var s = tr(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// Pluralized string for [count] with `{count}` substituted. Resolves the
  /// English-rule form (`1` → `#one`, else `#other`); cloud languages expose
  /// only the `#other` value (the engine's `langpack.getStrings` bridge
  /// collapses pluralized strings to `other_value`), so non-English falls back
  /// to that bare-key overlay. Mirrors AyuGram `tr::lng_days(lt_count, n)` etc.
  String trCount(String key, int count) {
    final form = count == 1 ? 'one' : 'other';
    final v = _overlay['$key#$form'] ??
        _overlay[key] ??
        _en['$key#$form'] ??
        _en[key] ??
        key;
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
