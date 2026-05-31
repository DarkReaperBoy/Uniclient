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
  Timer? _autoPollTimer;
  bool _autoInputBusy = false;

  // Timestamp of the last SRP_ID_INVALID, used to detect a storm of repeats
  // within the timeout window. Reset to null whenever the auth flow tears down
  // or leaves the 2FA step, so the storm window is scoped to a single
  // password-entry attempt — mirroring AyuGram's per-PasswordCheckWidget
  // `_lastSrpIdInvalidTime = 0` (intro_password_check.h:71), which re-inits on
  // every `goReplace<PasswordCheckWidget>`.
  DateTime? _lastSrpIdInvalidTime;
  static const _kSrpIdInvalidTimeout = Duration(seconds: 60);

  // Last-entered 2FA password, retained so a transparent SRP_ID_INVALID retry
  // can re-submit it without prompting the user again. Cleared on success,
  // cancel, and clear().
  String? _last2faPassword;

  Timer? _qrExpiryTimer;

  /// File path for CLI automation input.
  /// Write JSON to this file to control auth flow:
  ///   {"action": "choose", "value": "phone"}   — pick auth method
  ///   {"action": "submit", "value": "12345"}    — enter text input/OTP/2FA
  ///   {"action": "cancel"}                      — cancel auth
  static const autoInputPath = '/tmp/uniclient_auth_cmd.json';

  AuthState(this._engine) {
    _sub = _engine.onAuthState.listen(_handleAuthEvent);
  }

  // ── Getters ──

  AuthStateData? get currentAuth => _currentAuth;
  bool get submitting => _submitting;
  String? get error => _error;
  bool get hasActiveFlow => _currentAuth != null;

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

    // Retain the 2FA password so a transparent SRP_ID_INVALID retry can
    // re-submit it without bouncing the user back to a blank prompt.
    if (auth.state == '2fa') {
      _last2faPassword = input;
    }

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
        if (rawError == 'SRP_ID_INVALID') {
          final now = DateTime.now();
          if (_lastSrpIdInvalidTime != null &&
              now.difference(_lastSrpIdInvalidTime!) < _kSrpIdInvalidTimeout) {
            // Storm — repeated SRP_ID_INVALID within the timeout. Surface a
            // server error instead of retrying forever. Mirrors
            // handleSrpIdInvalid → showError(ServerError)
            // (intro_password_check.cpp:171-173).
            _error = 'Server error. Please try again later.';
            Debug.log('AUTH', 'SRP_ID_INVALID storm detected — aborting');
          } else {
            // First occurrence — TRANSPARENT retry: re-fetch fresh SRP params
            // and auto-resubmit the SAME password the user already entered. No
            // error is shown and the user is NOT bounced back to a blank prompt.
            // Mirrors handleSrpIdInvalid → requestPasswordData → passwordChecked
            // (intro_password_check.cpp:174-176), which re-runs the SRP check
            // automatically without any UI feedback.
            _lastSrpIdInvalidTime = now;
            final retryPassword = _last2faPassword;
            AuthStateData? freshAuth;
            try {
              freshAuth = await _engine.startAuth(auth.accountId);
            } catch (e) {
              Debug.log('AUTH', 'SRP_ID_INVALID — fresh-params fetch failed: $e');
            }
            if (freshAuth != null) {
              _currentAuth = freshAuth;
            }
            if (retryPassword != null &&
                retryPassword.isNotEmpty &&
                _currentAuth?.state == '2fa') {
              Debug.log('AUTH',
                  'SRP_ID_INVALID — re-fetched params, auto-resubmitting password');
              // Transparent re-submit. submitInput resets _submitting/_error and
              // calls notifyListeners itself, so return here to avoid clobbering
              // its result with the stale error state below.
              await submitInput(retryPassword);
              return;
            }
            // No retained password (or unexpected state) — leave the freshly
            // fetched 2fa state in place WITHOUT an error so the user can simply
            // re-enter. Still no forced error message.
            Debug.log('AUTH', 'SRP_ID_INVALID — awaiting 2FA re-entry');
          }
        } else {
          _error = rawError;
        }
      }

      // Drop the retained 2FA password and reset the SRP-storm window once the
      // step was accepted (auth moved past the 2fa prompt without an error).
      // Mirrors AyuGram recreating a fresh PasswordCheckWidget — whose
      // `_lastSrpIdInvalidTime` re-initializes to 0 — on each entry to the
      // password step (intro_password_check.h:71, goReplace at
      // intro_code.cpp:364 / intro_qr.cpp:504).
      if (result != null && result.state != 'error' && result.state != '2fa') {
        _last2faPassword = null;
        _lastSrpIdInvalidTime = null;
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
    _lastSrpIdInvalidTime = null;
    _stopAutoPoll();
    notifyListeners();
    await startAuth(accountId);
    if (_currentAuth?.state == 'choose') {
      await submitInput(method);
    }
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
    _last2faPassword = null;
    _lastSrpIdInvalidTime = null;
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
    _last2faPassword = null;
    _lastSrpIdInvalidTime = null;
    _stopAutoPoll();
    _qrExpiryTimer?.cancel();
    _qrExpiryTimer = null;
    notifyListeners();
  }

  // ── Internal ──

  void _handleAuthEvent(AuthStateEvent event) {
    Debug.log('AUTH', 'event: account=${event.accountId} state=${event.state} error=${event.error}');
    if (_currentAuth == null || _currentAuth!.accountId != event.accountId) return;

    // Clear any stale error when applying a non-error state transition, mirroring
    // AyuGram clearing the error label on every step change. Surface the error
    // only when the incoming event itself is an error (intro_password_check.cpp
    // hides the error on each step and shows it on failure).
    if (event.state == 'error') {
      if (event.error.isNotEmpty) _error = event.error;
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
      final result = await _engine.startAuth(auth.accountId);
      if (result != null && result.state == 'qr') {
        _currentAuth = result;
        _updateQrExpiryTimer();
        notifyListeners();
      }
    } catch (e) {
      Debug.log('AUTH', 'QR refresh failed: $e');
    }
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
    super.dispose();
  }
}
