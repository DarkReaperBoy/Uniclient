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

  DateTime? _lastSrpIdInvalidTime;
  static const _kSrpIdInvalidTimeout = Duration(seconds: 60);

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
            _error = 'Server error. Please try again later.';
            Debug.log('AUTH', 'SRP_ID_INVALID storm detected — aborting');
          } else {
            _lastSrpIdInvalidTime = now;
            try {
              final freshAuth = await _engine.startAuth(auth.accountId);
              if (freshAuth != null && freshAuth.state == '2fa') {
                _currentAuth = freshAuth;
                Debug.log('AUTH', 'SRP_ID_INVALID — re-fetched fresh SRP params');
              } else {
                _currentAuth = AuthStateData(
                  accountId: auth.accountId,
                  platform: auth.platform,
                  state: '2fa',
                  label: auth.label.isNotEmpty ? auth.label : 'Two-Factor Password',
                  hint: auth.hint,
                  hasRecovery: auth.hasRecovery,
                  sentTo: auth.sentTo,
                );
              }
            } catch (_) {
              _currentAuth = AuthStateData(
                accountId: auth.accountId,
                platform: auth.platform,
                state: '2fa',
                label: auth.label.isNotEmpty ? auth.label : 'Two-Factor Password',
                hint: auth.hint,
                hasRecovery: auth.hasRecovery,
                sentTo: auth.sentTo,
              );
            }
            _error = 'Password verification failed. Please try again.';
            Debug.log('AUTH', 'SRP_ID_INVALID — restored 2FA state for re-entry');
          }
        } else {
          _error = rawError;
        }
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

  void _handleAuthEvent(AuthStateEvent event) {
    Debug.log('AUTH', 'event: account=${event.accountId} state=${event.state} error=${event.error}');
    if (_currentAuth == null || _currentAuth!.accountId != event.accountId) return;

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
