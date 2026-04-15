import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../utils/debug.dart';

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
      Debug.log('APP', 'Engine initialized, ${_accounts.length} accounts');
      notifyListeners();

      // Connect all accounts (async — don't block init).
      _engine.connectAllAccounts().catchError((e, stack) {
        Debug.error('APP', 'connectAllAccounts failed', e, stack);
      });
    } catch (e, stack) {
      _initError = e.toString();
      Debug.error('APP', 'Engine init failed', e, stack);
      notifyListeners();
    }
  }

  /// Test-only: mark as initialized with given accounts without calling engine.init()
  /// or connectAllAccounts(). Used when engine is already running.
  void initForTest(List<AccountInfo> accounts) {
    _accounts = accounts;
    _initialized = true;
    notifyListeners();
  }

  void setActivePlatform(String platform) {
    _activePlatform = platform;
    notifyListeners();
  }

  String addAccount(String platform) {
    Debug.log('APP', 'Adding account: $platform');
    try {
      final id = _engine.addAccount(platform);
      _accounts = _engine.listAccounts();
      Debug.log('APP', 'Account added: $platform → $id (${_accounts.length} total)');
      notifyListeners();
      return id;
    } catch (e, stack) {
      Debug.error('APP', 'addAccount($platform) failed', e, stack);
      rethrow;
    }
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
