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

  // SRP_ID_INVALID rate limiting — 60s time gate matching AyuGram.
  DateTime? _lastSrpIdInvalidTime;
  static const _srpIdInvalidTimeout = Duration(seconds: 60);

  StreamSubscription<AuthStateEvent>? _sub;
  Timer? _autoPollTimer;
  bool _autoInputBusy = false;

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
    'choose' || 'input' || 'otp' || '2fa' || 'signup' => true,
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

      if (result?.state == 'error' &&
          (result!.message.contains('SRP_ID_INVALID') ||
           result.error.contains('SRP_ID_INVALID'))) {
        final now = DateTime.now();
        if (_lastSrpIdInvalidTime != null &&
            now.difference(_lastSrpIdInvalidTime!) < _srpIdInvalidTimeout) {
          _error = 'Server error. Please try again later.';
          Debug.log('AUTH', 'SRP_ID_INVALID twice within 60s — giving up');
        } else {
          _lastSrpIdInvalidTime = now;
          _error = 'Server challenge expired. Please try again.';
          Debug.log('AUTH', 'SRP_ID_INVALID — will retry');
        }
      } else {
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
    // Yield to let the engine process the cancel before starting new auth.
    await Future<void>.delayed(Duration.zero);
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
    notifyListeners();
  }

  /// Clear auth state (e.g. after dismissing success/error).
  void clear() {
    _currentAuth = null;
    _submitting = false;
    _error = null;
    _stopAutoPoll();
    notifyListeners();
  }

  // ── Internal ──

  void _handleAuthEvent(AuthStateEvent event) {
    Debug.log('AUTH', 'event: account=${event.accountId} state=${event.state} error=${event.error}');
    if (_currentAuth == null || _currentAuth!.accountId != event.accountId) return;

    _currentAuth = AuthStateData(
      accountId: event.accountId,
      state: event.state,
      label: event.prompt,
      error: event.error,
    );
    _submitting = false;
    _updateAutoPoll();
    notifyListeners();
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
          if (value.isNotEmpty) submitInput(value);
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
    _sub?.cancel();
    super.dispose();
  }
}
