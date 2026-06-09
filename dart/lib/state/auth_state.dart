import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../utils/debug.dart';

/// Auth flow state — tracks in-progress authentication for accounts.
class AuthState extends ChangeNotifier {
  final EngineService _engine;

  // Active auth flow (null = no auth in progress).
  AuthStateData? _currentAuth;
  bool _submitting = false;
  String? _error;

  StreamSubscription<AuthStateEvent>? _sub;
  StreamSubscription<String>? _loginCodeSub;
  Timer? _autoPollTimer;
  bool _autoInputBusy = false;

  Timer? _qrExpiryTimer;

  // A login code pushed by Telegram to a connected session (intro_code.cpp:59).
  // The auth screen watches [loginCodeSeq] to detect a fresh code and fills it.
  String? _pendingLoginCode;
  int _loginCodeSeq = 0;

  /// File path for CLI automation input.
  /// Write JSON to this file to control auth flow:
  ///   {"action": "choose", "value": "phone"}   — pick auth method
  ///   {"action": "submit", "value": "12345"}    — enter text input/OTP/2FA
  ///   {"action": "cancel"}                      — cancel auth
  static const autoInputPath = '/tmp/uniclient_auth_cmd.json';

  AuthState(this._engine) {
    _sub = _engine.onAuthState.listen(_handleAuthEvent);
    _loginCodeSub = _engine.onLoginCode.listen(_handleLoginCode);
  }

  // ── Getters ──

  AuthStateData? get currentAuth => _currentAuth;
  bool get submitting => _submitting;
  String? get error => _error;
  bool get hasActiveFlow => _currentAuth != null;

  /// A login code Telegram pushed to a connected session, pending auto-fill on
  /// the code step (null once consumed). Read together with [loginCodeSeq].
  String? get pendingLoginCode => _pendingLoginCode;

  /// Bumped every time a fresh [pendingLoginCode] arrives; the auth screen
  /// compares it against its last-seen value to fill+submit exactly once.
  int get loginCodeSeq => _loginCodeSeq;

  /// Whether the current state needs user input.
  bool get needsInput => _currentAuth != null && switch (_currentAuth!.state) {
    'choose' || 'input' || 'otp' || '2fa' || 'signup' || 'recover' || 'email' => true,
    _ => false,
  };

  /// Whether auth is showing a QR code.
  bool get isQR => _currentAuth?.state == 'qr';

  /// Whether auth completed successfully.
  bool get isReady => _currentAuth?.state == 'ready';

  /// Whether auth hit an error.
  bool get isError => _currentAuth?.state == 'error';

  // ── Actions ──

  /// Start auth flow for an account.
  Future<void> startAuth(String accountId) async {
    Debug.log('AUTH', 'startAuth($accountId)');
    _error = null;
    _submitting = false;
    notifyListeners();
    try {
      _currentAuth = await _engine.startAuth(accountId);
      Debug.log('AUTH', 'startAuth → state=${_currentAuth?.state} label=${_currentAuth?.label}');
      _updateAutoPoll();
    } catch (e, stack) {
      _error = e.toString();
      _currentAuth = AuthStateData(
        accountId: accountId,
        state: 'error',
        error: e.toString(),
        recoverable: true,
      );
      Debug.error('AUTH', 'startAuth($accountId) failed', e, stack);
    }
    notifyListeners();
  }

  /// Submit user input (phone number, password, OTP, etc.).
  Future<void> submitInput(String input) async {
    final auth = _currentAuth;
    if (auth == null) return;

    Debug.log('AUTH', 'submitInput(${input.length > 20 ? '${input.substring(0, 20)}...' : input}) for ${auth.accountId}');
    _submitting = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _engine.submitAuthInput(auth.accountId, input);
      _currentAuth = result;
      _submitting = false;

      if (result?.state == 'error') {
        final rawError = result!.error.isNotEmpty ? result.error : result.message;
        // Surface the final error. SRP_ID_INVALID is retried transparently by
        // the core ONCE (it re-fetches account.GetPassword and re-checks the SRP
        // hash — telegram.go:1059-1071); if it still surfaces here that retry has
        // already failed, so we must NOT re-run a Dart-side retry. A startAuth
        // here would rebuild the flow with an empty `collected` map (losing the
        // entered phone+OTP) and drop the user at the method picker. See
        // _finalizeAuthError for the SRP mapping. Mirrors AyuGram
        // handleSrpIdInvalid → showError(ServerError) on the repeat hit
        // (intro_password_check.cpp:171-173).
        _error = _finalizeAuthError(rawError);
      }

      Debug.log('AUTH', 'submitInput → state=${result?.state} label=${result?.label}');
    } catch (e, stack) {
      _error = e.toString();
      _submitting = false;
      Debug.error('AUTH', 'submitInput failed', e, stack);
    }
    notifyListeners();
  }

  Future<void> switchToMethod(String method) async {
    final auth = _currentAuth;
    if (auth == null) return;
    final accountId = auth.accountId;
    _engine.cancelAuth(accountId);
    _currentAuth = null;
    _submitting = false;
    _error = null;
    _stopAutoPoll();
    notifyListeners();
    await startAuth(accountId);
    if (_currentAuth?.state == 'choose') {
      await submitInput(method);
    }
  }

  /// Step back to the previous auth step within the same live flow, mirroring
  /// AyuGram's intro back arrow → Widget::backRequested → historyMove(Back)
  /// (intro_widget.cpp:888). Unlike [cancelAuth] this does NOT tear the flow
  /// down: the engine keeps the MTProto connection and the collected phone/code,
  /// pops the last step and re-emits the previous one, so the user returns to the
  /// prior step with the number preserved (editable & resendable). When already
  /// at the first step the engine has no prior step to pop (returns null), so we
  /// fall through to a full exit ([cancelAuth]) — matching AyuGram exiting intro
  /// only at the first step. (The engine also emits an auth-state event for the
  /// restored step, which refreshes auto-poll/QR timers via [_handleAuthEvent].)
  Future<void> goBack() async {
    final auth = _currentAuth;
    if (auth == null) return;
    try {
      final result = await _engine.goBackAuth(auth.accountId);
      if (result == null) {
        // First step — no prior step to return to; exit the flow entirely.
        cancelAuth();
        return;
      }
      _currentAuth = result;
      _submitting = false;
      _error = null;
      Debug.log('AUTH', 'goBack → state=${result.state} label=${result.label}');
    } catch (e, stack) {
      _error = e.toString();
      Debug.error('AUTH', 'goBack failed', e, stack);
    }
    notifyListeners();
  }

  /// Cancel the current auth flow.
  void cancelAuth() {
    final auth = _currentAuth;
    if (auth != null) {
      _engine.cancelAuth(auth.accountId);
    }
    _currentAuth = null;
    _submitting = false;
    _error = null;
    _stopAutoPoll();
    _qrExpiryTimer?.cancel();
    _qrExpiryTimer = null;
    notifyListeners();
  }

  /// Clear auth state (e.g. after dismissing success/error).
  void clear() {
    _currentAuth = null;
    _submitting = false;
    _error = null;
    _stopAutoPoll();
    _qrExpiryTimer?.cancel();
    _qrExpiryTimer = null;
    notifyListeners();
  }

  // ── Internal ──

  /// Apply a Telegram-pushed login code to the in-progress flow. Account-
  /// agnostic, mirroring AyuGram's `domain.active().handleLoginCode(code)`
  /// (local_url_handlers.cpp:1446): the code is delivered to whichever account
  /// received the service message but applied to the active login flow. Only
  /// acts on the code step (not Fragment, which reads the code off the URL).
  void _handleLoginCode(String code) {
    final auth = _currentAuth;
    if (code.isEmpty || auth == null || auth.state != 'otp') return;
    if (auth.codeByFragmentUrl.isNotEmpty) return;
    Debug.log('AUTH', 'pushed login code received (len=${code.length})');
    _pendingLoginCode = code;
    _loginCodeSeq++;
    notifyListeners();
  }

  void _handleAuthEvent(AuthStateEvent event) {
    Debug.log('AUTH', 'event: account=${event.accountId} state=${event.state} error=${event.error}');
    if (_currentAuth == null || _currentAuth!.accountId != event.accountId) return;

    // Clear any stale error when applying a non-error state transition, mirroring
    // AyuGram clearing the error label on every step change. Surface the error
    // only when the incoming event itself is an error (intro_password_check.cpp
    // hides the error on each step and shows it on failure).
    if (event.state == 'error') {
      if (event.error.isNotEmpty) _error = _finalizeAuthError(event.error);
    } else {
      _error = null;
    }

    if (event.fullData != null) {
      _currentAuth = event.fullData;
    } else {
      final existing = _currentAuth;
      _currentAuth = AuthStateData(
        accountId: event.accountId,
        state: event.state,
        label: event.prompt.isNotEmpty ? event.prompt : (existing?.label ?? ''),
        error: event.error,
        platform: existing?.platform ?? '',
        hint: existing?.hint ?? '',
        hasRecovery: existing?.hasRecovery ?? false,
        sentTo: existing?.sentTo ?? '',
        qrExpiresIn: existing?.qrExpiresIn ?? 0,
        qrData: existing?.qrData ?? const [],
        codeLength: existing?.codeLength ?? 0,
        timeoutSecs: existing?.timeoutSecs ?? 0,
        canResend: existing?.canResend ?? false,
        displayName: existing?.displayName ?? '',
        avatarB64: existing?.avatarB64 ?? '',
        recoverable: existing?.recoverable ?? false,
        codeByTelegram: existing?.codeByTelegram ?? false,
        codeByFragmentUrl: existing?.codeByFragmentUrl ?? '',
        email: existing?.email ?? '',
        emailPatternSetup: existing?.emailPatternSetup ?? '',
        tosText: existing?.tosText ?? '',
        options: existing?.options ?? const [],
      );
    }
    _submitting = false;
    _updateAutoPoll();
    _updateQrExpiryTimer();
    notifyListeners();
  }

  void _updateQrExpiryTimer() {
    _qrExpiryTimer?.cancel();
    _qrExpiryTimer = null;
    if (_currentAuth?.state == 'qr' && _currentAuth!.qrExpiresIn > 0) {
      final left = _currentAuth!.qrExpiresIn - 1;
      final delaySecs = left < 1 ? 1 : left;
      _qrExpiryTimer = Timer(Duration(seconds: delaySecs), _onQrExpired);
    }
  }

  Future<void> _onQrExpired() async {
    final auth = _currentAuth;
    if (auth == null || auth.state != 'qr') return;
    Debug.log('AUTH', 'QR code expired, requesting refresh');
    try {
      // Re-export the login token IN PLACE via the QR-refresh engine path
      // (SubmitAuthInput → advanceAuth case AuthStateQR → RefreshQRToken,
      // auth.go:417-443), which returns a fresh `qr` (or `ready` if the code was
      // just scanned). Do NOT call startAuth here — that rebuilds the core with
      // an empty flow and emits the `choose` method picker, bouncing the user
      // off the QR screen on every expiry. The input is ignored by the QR case.
      // Mirrors AyuGram QrWidget::refreshCode staying on the QR step and
      // rescheduling its refresh timer (intro_qr.cpp:417,441).
      final result = await _engine.submitAuthInput(auth.accountId, '');
      if (result != null && result.state == 'qr') {
        _currentAuth = result;
        _updateQrExpiryTimer();
        notifyListeners();
      }
    } catch (e) {
      Debug.log('AUTH', 'QR refresh failed: $e');
    }
  }

  /// Map a raw engine auth error string to the final, user-facing message.
  ///
  /// SRP_ID_INVALID is special: the core already performs a transparent retry
  /// ONCE on this error (re-fetching `account.GetPassword` and re-checking the
  /// SRP hash — telegram.go:1059-1071), so by the time it surfaces to Dart that
  /// retry has *already* failed. We surface a final error instead of implying
  /// (via "retrying…") that anything is still in progress, and we do NOT run a
  /// Dart-side retry. The engine wraps the error string
  /// (`"auth: user auth: …: SRP_ID_INVALID"`), so match by substring — the same
  /// convention used by auth_screen.dart's `_mapAuthError`. Mirrors AyuGram's
  /// handleSrpIdInvalid → showError(ServerError) on the repeat hit
  /// (intro_password_check.cpp:171-173).
  String _finalizeAuthError(String raw) {
    if (raw.contains('SRP_ID_INVALID')) {
      return 'Session expired. Please try again.';
    }
    return raw;
  }

  // ── CLI automation polling ──

  void _updateAutoPoll() {
    if (needsInput && _autoPollTimer == null) {
      _startAutoPoll();
    } else if (!needsInput && _autoPollTimer != null) {
      _stopAutoPoll();
    }
  }

  void _startAutoPoll() {
    _autoPollTimer?.cancel();
    Debug.log('AUTH', 'Auto-input polling started (${autoInputPath})');
    _autoPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkAutoInput());
  }

  void _stopAutoPoll() {
    _autoPollTimer?.cancel();
    _autoPollTimer = null;
  }

  Future<void> _checkAutoInput() async {
    if (_autoInputBusy) return;
    _autoInputBusy = true;
    try {
      final file = File(autoInputPath);
      if (!await file.exists()) return;

      final content = (await file.readAsString()).trim();
      if (content.isEmpty) return;

      await file.delete();

      final cmd = jsonDecode(content) as Map<String, dynamic>;
      final action = cmd['action'] as String? ?? '';
      final value = cmd['value'] as String? ?? '';

      Debug.log('AUTH', 'Auto-input: action=$action value=${value.length > 20 ? '${value.substring(0, 20)}...' : value}');

      switch (action) {
        case 'choose' || 'submit':
          if (value.isNotEmpty) await submitInput(value);
        case 'cancel':
          cancelAuth();
        default:
          Debug.log('AUTH', 'Unknown auto-input action: $action');
      }
    } catch (e) {
      // Silently ignore — file might not exist or be in transit.
    } finally {
      _autoInputBusy = false;
    }
  }

  @override
  void dispose() {
    _stopAutoPoll();
    _qrExpiryTimer?.cancel();
    _sub?.cancel();
    _loginCodeSub?.cancel();
    super.dispose();
  }
}
