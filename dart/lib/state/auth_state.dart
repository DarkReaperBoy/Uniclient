import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';

/// Auth flow state — tracks in-progress authentication for accounts.
class AuthState extends ChangeNotifier {
  final EngineService _engine;

  // Active auth flow (null = no auth in progress).
  AuthStateData? _currentAuth;
  bool _submitting = false;
  String? _error;

  StreamSubscription<AuthStateEvent>? _sub;

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
    'choose' || 'input' || 'otp' || '2fa' => true,
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
  void startAuth(String accountId) {
    _error = null;
    _submitting = false;
    try {
      _currentAuth = _engine.startAuth(accountId);
    } catch (e) {
      _error = e.toString();
      _currentAuth = AuthStateData(
        accountId: accountId,
        state: 'error',
        error: e.toString(),
        recoverable: true,
      );
    }
    notifyListeners();
  }

  /// Submit user input (phone number, password, OTP, etc.).
  void submitInput(String input) {
    final auth = _currentAuth;
    if (auth == null) return;

    _submitting = true;
    _error = null;
    notifyListeners();

    try {
      final result = _engine.submitAuthInput(auth.accountId, input);
      _currentAuth = result;
      _submitting = false;
    } catch (e) {
      _error = e.toString();
      _submitting = false;
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
    notifyListeners();
  }

  /// Clear auth state (e.g. after dismissing success/error).
  void clear() {
    _currentAuth = null;
    _submitting = false;
    _error = null;
    notifyListeners();
  }

  // ── Internal ──

  void _handleAuthEvent(AuthStateEvent event) {
    if (_currentAuth == null || _currentAuth!.accountId != event.accountId) return;

    _currentAuth = AuthStateData(
      accountId: event.accountId,
      state: event.state,
      label: event.prompt,
      error: event.error,
    );
    _submitting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
