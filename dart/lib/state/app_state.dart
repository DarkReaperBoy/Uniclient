import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';

/// Top-level app state: accounts, connection, config, active platform.
class AppState extends ChangeNotifier {
  final EngineService _engine;

  List<AccountInfo> _accounts = [];
  final Map<String, ConnState> _connStates = {};
  String _activePlatform = ''; // platform filter for chat list (empty = all)
  AppConfig _config = AppConfig.defaults();
  bool _initialized = false;
  String? _initError;

  final List<StreamSubscription<dynamic>> _subs = [];

  AppState(this._engine);

  // ── Getters ──

  List<AccountInfo> get accounts => _accounts;
  Map<String, ConnState> get connStates => _connStates;
  String get activePlatform => _activePlatform;
  AppConfig get config => _config;
  bool get initialized => _initialized;
  String? get initError => _initError;

  ThemeMode get themeMode => switch (_config.theme) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };

  /// Distinct platforms from connected accounts, sorted by sort order.
  List<String> get platforms {
    final seen = <String>{};
    final result = <String>[];
    for (final a in _accounts) {
      if (seen.add(a.platform)) result.add(a.platform);
    }
    return result;
  }

  /// Accounts for a given platform.
  List<AccountInfo> accountsForPlatform(String platform) =>
      _accounts.where((a) => a.platform == platform).toList();

  ConnState connStateFor(String accountId) =>
      _connStates[accountId] ?? ConnState.disconnected;

  /// Total unread across all accounts (placeholder — chat state tracks this).
  int unreadForPlatform(String platform) => 0;

  // ── Actions ──

  Future<void> initialize({
    required String configDir,
    required String cacheDir,
    required String downloadDir,
    String vaultPassword = '',
  }) async {
    try {
      await _engine.init(
        configDir: configDir,
        cacheDir: cacheDir,
        downloadDir: downloadDir,
        vaultPassword: vaultPassword,
      );

      // Subscribe to events.
      _subs.add(_engine.onAccountList.listen((accounts) {
        _accounts = accounts;
        notifyListeners();
      }));
      _subs.add(_engine.onConnState.listen((event) {
        _connStates[event.accountId] = ConnState.fromString(event.state);
        notifyListeners();
      }));

      // Load initial state.
      _accounts = _engine.listAccounts();
      _config = _engine.getConfig();
      _initialized = true;
      notifyListeners();

      // Connect all accounts.
      _engine.connectAllAccounts();
    } catch (e) {
      _initError = e.toString();
      notifyListeners();
    }
  }

  void setActivePlatform(String platform) {
    _activePlatform = platform;
    notifyListeners();
  }

  String addAccount(String platform) {
    final id = _engine.addAccount(platform);
    _accounts = _engine.listAccounts();
    notifyListeners();
    return id;
  }

  void removeAccount(String accountId) {
    _engine.removeAccount(accountId);
    _accounts = _engine.listAccounts();
    _connStates.remove(accountId);
    notifyListeners();
  }

  void updateTheme(String theme) {
    _engine.updateConfig(theme: theme);
    _config = _engine.getConfig();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
