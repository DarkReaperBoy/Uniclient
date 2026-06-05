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
    // arrived via the Telegram app, the Fragment title/instruction.
    'lng_code_no_telegram',
    'lng_intro_fragment_title',
    'lng_intro_fragment_about',
    // 2FA / cloud-password step (intro_password_check.cpp:55,358).
    'lng_signin_title',
    'lng_signin_desc',
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
  ];

  /// Embedded English baseline (Telegram Desktop `lang.strings`). Kept in sync
  /// with [keys]; all entries are plain text (no markdown/newlines) since the
  /// intro renders them directly.
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
    'lng_signin_title': 'Cloud password check',
    'lng_signin_desc': 'Please enter your cloud password.',
    'lng_signup_title': 'Your Info',
    'lng_signup_desc': 'Please enter your name and\nupload a photo.',
    'lng_signup_firstname': 'First name',
    'lng_signup_lastname': 'Last name',
    'lng_full_name': '{first_name} {last_name}',
    'lng_intro_email_setup_title': 'Choose a login email',
    'lng_settings_cloud_login_email_about':
        'You will receive Telegram login codes via email and not SMS. Please '
        'enter an email address to which you have access.',
  };

  /// Localized string: server overlay → English baseline → raw key.
  String tr(String key) => _overlay[key] ?? _en[key] ?? key;

  /// Localized string with `{name}` placeholder substitution.
  String trf(String key, Map<String, String> params) {
    var s = tr(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
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
