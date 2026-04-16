import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  String _activeAccountId = ''; // account filter within a platform (empty = all accounts for platform)
  AppConfig _config = AppConfig.defaults();
  bool _initialized = false;
  String? _initError;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// Callback for showing connection-state notifications (set by UI layer).
  void Function(String text, IconData icon, Color color)? onConnStateNotification;

  /// Callback for triggering the auth flow (set by UI layer).
  /// Called when a CLI command adds an account. Parameters: (accountId, platform).
  void Function(String accountId, String platform)? onAddAccount;

  Timer? _cmdPollTimer;

  /// File path for CLI automation: add accounts without GUI interaction.
  ///   {"action": "add", "platform": "irc"}
  static const cmdFilePath = '/tmp/uniclient_cmd.json';

  AppState(this._engine);

  // ── Getters ──

  List<AccountInfo> get accounts => _accounts;
  Map<String, ConnState> get connStates => _connStates;
  String get activePlatform => _activePlatform;
  String get activeAccountId => _activeAccountId;
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
        final newState = ConnState.fromString(event.state);
        final oldState = _connStates[event.accountId];
        _connStates[event.accountId] = newState;
        notifyListeners();

        // Fire notification callback when state actually changes.
        if (newState != oldState && onConnStateNotification != null) {
          final account = _accounts.where((a) => a.id == event.accountId).firstOrNull;
          final label = _platformLabel(account?.platform ?? 'Account');
          switch (newState) {
            case ConnState.connected:
              onConnStateNotification!(
                '$label connected',
                Icons.cloud_done_outlined,
                const Color(0xFF3BA55C),
              );
            case ConnState.disconnected:
              onConnStateNotification!(
                '$label disconnected',
                Icons.cloud_off_outlined,
                const Color(0xFFFAA61A),
              );
            case ConnState.unstable:
              onConnStateNotification!(
                '$label connection unstable',
                Icons.cloud_outlined,
                const Color(0xFFFAA61A),
              );
            case ConnState.connecting:
              break; // No toast for transient connecting state.
          }
        }
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

      // Start polling for CLI commands.
      _cmdPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollCmdFile());
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
    _activeAccountId = ''; // reset account filter when switching platforms
    notifyListeners();
  }

  void setActiveAccountId(String accountId) {
    _activeAccountId = accountId;
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

  static String _platformLabel(String platform) => switch (platform.toLowerCase()) {
    'telegram' => 'Telegram',
    'matrix' => 'Matrix',
    'xmpp' => 'XMPP',
    'irc' => 'IRC',
    'bale' => 'Bale',
    'rubika' => 'Rubika',
    'delta' || 'deltachat' => 'Delta Chat',
    'mumble' => 'Mumble',
    'teamspeak' || 'ts3' => 'TeamSpeak',
    'discord' => 'Discord',
    _ => platform,
  };

  void _pollCmdFile() {
    try {
      final f = File(cmdFilePath);
      if (!f.existsSync()) return;
      final content = f.readAsStringSync().trim();
      f.deleteSync();
      if (content.isEmpty) return;
      final cmd = jsonDecode(content) as Map<String, dynamic>;
      final action = cmd['action'] as String?;
      if (action == 'add') {
        final platform = cmd['platform'] as String? ?? '';
        if (platform.isEmpty) return;
        Debug.log('APP', 'CLI command: add $platform');
        final id = addAccount(platform);
        onAddAccount?.call(id, platform);
      }
    } catch (e) {
      // Ignore malformed/missing files.
    }
  }

  @override
  void dispose() {
    _cmdPollTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
