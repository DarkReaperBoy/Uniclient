import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../utils/debug.dart';

/// Top-level app state: accounts, connection, config, active platform.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final EngineService _engine;

  /// Spec §3.2: max accounts 100 (AyuGram), 200 for premium.
  static const kMaxAccounts = 100;
  static const kPremiumMaxAccounts = 200;

  List<AccountInfo> _accounts = [];
  final Map<String, ConnState> _connStates = {};
  String _activeAccountId = ''; // currently viewed account (always set when accounts exist)
  AppConfig _config = AppConfig.defaults();
  bool _initialized = false;
  String? _initError;

  String _configDir = '';
  bool _nativeWindowFrame = false;
  bool _mainMenuAccountsShown = false;
  bool _systemDarkMode = false;
  bool _showChatNameInTitle = true;
  bool _showAccountNameInTitle = true;
  bool _showUnreadCountInTitle = true;
  int _windowCloseBehavior = 0; // 0=Run in Background, 1=Close to Taskbar, 2=Quit
  bool _showTrayIcon = true;
  bool _showTaskbarIcon = true;
  bool _monochromeTrayIcon = false;
  bool _launchAtStartup = false;
  bool _startMinimized = false;
  bool _hardwareAccelVideo = true;
  bool _openGlDisabled = false;
  bool _spellcheckerEnabled = true;
  bool _spellcheckerAutoDownload = true;
  bool _autoUpdateEnabled = true;
  bool _installBetaVersions = false;
  int _downloadPathMode = 0; // 0=default, 1=temp, 2=custom
  String _customDownloadPath = '';
  bool _askDownloadPath = false;
  List<Map<String, dynamic>> _recentDownloads = [];
  Map<String, bool> _experimentalFlags = {};
  bool _editingTheme = false;
  List<String> _accountOrder = []; // persisted display order of account IDs
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Spec §3.3 / §54.8a: Menu bots per account (attach-menu bots with
  /// inMainMenu + bot.media). Keyed by account ID.
  final Map<String, List<MenuBotInfo>> _menuBots = {};

  /// Spec §2.7: Configurable swipe action for chat list rows.
  /// Values: "mute", "pin", "read", "archive", "delete". Default: "archive".
  String _swipeAction = 'archive';

  /// Spec §7.3: When true, empty-field send button shows Round (camera) instead of Record (mic).
  bool _recordVideoMessages = false;

  // Spec §17.7.1: PowerSaving bitfield (matches tdesktop bit positions).
  static const kPowerSavingStickersPanel = 1 << 0;
  static const kPowerSavingStickersChat  = 1 << 1;
  static const kPowerSavingEmojiPanel    = 1 << 3;
  static const kPowerSavingEmojiReactions = 1 << 4;
  static const kPowerSavingEmojiChat     = 1 << 5;
  static const kPowerSavingEmojiStatus   = 1 << 9;
  static const kPowerSavingChatBackground = 1 << 6;
  static const kPowerSavingChatSpoiler   = 1 << 7;
  static const kPowerSavingChatEffects   = 1 << 8;
  static const kPowerSavingCalls         = 1 << 10;
  static const kPowerSavingAnimations    = 1 << 11;
  int _powerSavingFlags = 0;
  bool _autoPowerSaving = false;

  /// Callback for showing connection-state notifications (set by UI layer).
  void Function(String text, IconData icon, Color color)? onConnStateNotification;

  /// Callback for triggering the auth flow (set by UI layer).
  /// Called when a CLI command adds an account. Parameters: (accountId, platform).
  void Function(String accountId, String platform)? onAddAccount;

  /// Callback for toggling archive view in chat list (set by ChatListPanel).
  VoidCallback? onShowArchiveRequested;

  Timer? _cmdPollTimer;

  /// File path for CLI automation: add accounts without GUI interaction.
  ///   {"action": "add", "platform": "irc"}
  static const cmdFilePath = '/tmp/uniclient_cmd.json';

  AppState(this._engine);

  // ── Getters ──

  List<AccountInfo> get accounts {
    if (_accountOrder.isEmpty) return _accounts;
    final ordered = <AccountInfo>[];
    for (final id in _accountOrder) {
      final a = _accounts.where((x) => x.id == id).firstOrNull;
      if (a != null) ordered.add(a);
    }
    for (final a in _accounts) {
      if (!_accountOrder.contains(a.id)) ordered.add(a);
    }
    return ordered;
  }
  Map<String, ConnState> get connStates => _connStates;
  String get activeAccountId => _activeAccountId;
  String get configDir => _configDir;
  AppConfig get config => _config;
  bool get initialized => _initialized;
  String? get initError => _initError;

  /// The currently active account (null if no accounts exist).
  AccountInfo? get activeAccount =>
      _accounts.where((a) => a.id == _activeAccountId).firstOrNull;

  /// Spec §3.2: account limit — 200 if any account is premium, else 100.
  int get maxAccountLimit =>
      _accounts.any((a) => a.isPremium) ? kPremiumMaxAccounts : kMaxAccounts;

  /// Whether a new account can be added (under the limit).
  bool get canAddAccount => _accounts.length < maxAccountLimit;

  bool get nativeWindowFrame => _nativeWindowFrame;
  bool get showChatNameInTitle => _showChatNameInTitle;
  bool get showAccountNameInTitle => _showAccountNameInTitle;
  bool get showUnreadCountInTitle => _showUnreadCountInTitle;
  int get windowCloseBehavior => _windowCloseBehavior;
  bool get showTrayIcon => _showTrayIcon;
  bool get showTaskbarIcon => _showTaskbarIcon;
  bool get monochromeTrayIcon => _monochromeTrayIcon;
  bool get launchAtStartup => _launchAtStartup;
  bool get startMinimized => _startMinimized;
  bool get hardwareAccelVideo => _hardwareAccelVideo;
  bool get openGlDisabled => _openGlDisabled;
  bool get spellcheckerEnabled => _spellcheckerEnabled;
  bool get spellcheckerAutoDownload => _spellcheckerAutoDownload;
  bool get autoUpdateEnabled => _autoUpdateEnabled;
  bool get installBetaVersions => _installBetaVersions;
  int get downloadPathMode => _downloadPathMode;
  String get customDownloadPath => _customDownloadPath;
  bool get askDownloadPath => _askDownloadPath;
  List<Map<String, dynamic>> get recentDownloads => List.unmodifiable(_recentDownloads);

  bool setShowTrayIcon(bool v) {
    if (!v && !_showTaskbarIcon) return false;
    if (_showTrayIcon == v) return true;
    _showTrayIcon = v;
    notifyListeners();
    _saveWindowPrefs();
    return true;
  }

  bool setShowTaskbarIcon(bool v) {
    if (!v && !_showTrayIcon) return false;
    if (_showTaskbarIcon == v) return true;
    _showTaskbarIcon = v;
    notifyListeners();
    _saveWindowPrefs();
    return true;
  }

  void setMonochromeTrayIcon(bool v) {
    if (_monochromeTrayIcon == v) return;
    _monochromeTrayIcon = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setLaunchAtStartup(bool v) {
    if (_launchAtStartup == v) return;
    _launchAtStartup = v;
    if (!v) {
      _startMinimized = false;
    }
    notifyListeners();
    _saveWindowPrefs();
  }

  void setStartMinimized(bool v) {
    if (_startMinimized == v) return;
    _startMinimized = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setHardwareAccelVideo(bool v) {
    if (_hardwareAccelVideo == v) return;
    _hardwareAccelVideo = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setOpenGlDisabled(bool v) {
    if (_openGlDisabled == v) return;
    _openGlDisabled = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSpellcheckerEnabled(bool v) {
    if (_spellcheckerEnabled == v) return;
    _spellcheckerEnabled = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSpellcheckerAutoDownload(bool v) {
    if (_spellcheckerAutoDownload == v) return;
    _spellcheckerAutoDownload = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setAutoUpdateEnabled(bool v) {
    if (_autoUpdateEnabled == v) return;
    _autoUpdateEnabled = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setInstallBetaVersions(bool v) {
    if (_installBetaVersions == v) return;
    _installBetaVersions = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setDownloadPathMode(int mode, [String customPath = '']) {
    if (_downloadPathMode == mode && _customDownloadPath == customPath) return;
    _downloadPathMode = mode;
    if (mode == 2) _customDownloadPath = customPath;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setAskDownloadPath(bool v) {
    if (_askDownloadPath == v) return;
    _askDownloadPath = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void addRecentDownload(String fileName, String filePath, int sizeBytes) {
    _recentDownloads.insert(0, {
      'name': fileName,
      'path': filePath,
      'size': sizeBytes,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    if (_recentDownloads.length > 100) {
      _recentDownloads = _recentDownloads.sublist(0, 100);
    }
    notifyListeners();
    _saveWindowPrefs();
  }

  void removeRecentDownload(int index) {
    if (index < 0 || index >= _recentDownloads.length) return;
    _recentDownloads.removeAt(index);
    notifyListeners();
    _saveWindowPrefs();
  }

  void clearRecentDownloads() {
    if (_recentDownloads.isEmpty) return;
    _recentDownloads.clear();
    notifyListeners();
    _saveWindowPrefs();
  }

  String get downloadPathLabel => switch (_downloadPathMode) {
    1 => 'Temp folder',
    2 => _customDownloadPath.isNotEmpty
        ? _customDownloadPath.split('/').last
        : 'Custom folder',
    _ => 'Default folder',
  };

  void setShowChatNameInTitle(bool v) {
    if (_showChatNameInTitle == v) return;
    _showChatNameInTitle = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowAccountNameInTitle(bool v) {
    if (_showAccountNameInTitle == v) return;
    _showAccountNameInTitle = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowUnreadCountInTitle(bool v) {
    if (_showUnreadCountInTitle == v) return;
    _showUnreadCountInTitle = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setWindowCloseBehavior(int v) {
    if (_windowCloseBehavior == v) return;
    _windowCloseBehavior = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  /// Spec §3.4: true when the theme editor is open — blocks night mode toggle.
  bool get isEditingTheme => _editingTheme;

  void setEditingTheme(bool value) {
    if (_editingTheme == value) return;
    _editingTheme = value;
    notifyListeners();
  }

  /// Spec §3.4: when true, theme auto-follows system dark mode changes.
  bool get systemDarkModeEnabled => _systemDarkMode;

  void setSystemDarkMode(bool value) {
    if (_systemDarkMode == value) return;
    _systemDarkMode = value;
    if (value) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      updateTheme(brightness == Brightness.dark ? 'dark' : 'light');
    }
    _saveWindowPrefs();
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_systemDarkMode) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      updateTheme(brightness == Brightness.dark ? 'dark' : 'light');
    }
  }

  /// Spec §3.2: persisted toggle for account list in hamburger menu.
  bool get mainMenuAccountsShown => _mainMenuAccountsShown;

  void setMainMenuAccountsShown(bool value) {
    if (_mainMenuAccountsShown == value) return;
    _mainMenuAccountsShown = value;
    _saveWindowPrefs();
    notifyListeners();
  }

  /// Spec §3.3: Menu bots for the active account. Empty when no bots
  /// have inMainMenu + media set, or engine hasn't provided data yet.
  List<MenuBotInfo> get menuBots =>
      _menuBots[_activeAccountId] ?? const [];

  /// Update menu bots for an account (called by engine event handler).
  void setMenuBots(String accountId, List<MenuBotInfo> bots) {
    _menuBots[accountId] = bots;
    notifyListeners();
  }

  String get swipeAction => _swipeAction;
  set swipeAction(String value) {
    if (_swipeAction != value) {
      _swipeAction = value;
      notifyListeners();
    }
  }

  bool get recordVideoMessages => _recordVideoMessages;
  set recordVideoMessages(bool value) {
    if (_recordVideoMessages != value) {
      _recordVideoMessages = value;
      _saveWindowPrefs();
      notifyListeners();
    }
  }

  int get powerSavingFlags => _powerSavingFlags;
  bool powerSaving(int flag) => _powerSavingFlags & flag != 0;
  bool get autoPowerSaving => _autoPowerSaving;

  void setAutoPowerSaving(bool v) {
    if (v == _autoPowerSaving) return;
    _autoPowerSaving = v;
    _saveWindowPrefs();
    notifyListeners();
  }

  void setPowerSaving(int flag, bool on) {
    final updated = on
        ? (_powerSavingFlags | flag)
        : (_powerSavingFlags & ~flag);
    if (updated == _powerSavingFlags) return;
    _powerSavingFlags = updated;
    _saveWindowPrefs();
    notifyListeners();
  }

  Map<String, bool> get experimentalFlags => Map.unmodifiable(_experimentalFlags);

  void setExperimentalFlag(String key, bool value) {
    if (_experimentalFlags[key] == value) return;
    if (value) {
      _experimentalFlags[key] = true;
    } else {
      _experimentalFlags.remove(key);
    }
    _saveWindowPrefs();
    notifyListeners();
  }

  void setExperimentalFlags(Map<String, bool> flags) {
    _experimentalFlags = Map<String, bool>.from(flags);
    _experimentalFlags.removeWhere((_, v) => !v);
    _saveWindowPrefs();
    notifyListeners();
  }

  void resetExperimentalFlags() {
    if (_experimentalFlags.isEmpty) return;
    _experimentalFlags.clear();
    _saveWindowPrefs();
    notifyListeners();
  }

  ThemeMode get themeMode => switch (_config.theme) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };

  ConnState connStateFor(String accountId) =>
      _connStates[accountId] ?? ConnState.disconnected;

  void requestShowArchive() {
    onShowArchiveRequested?.call();
  }

  // ── Actions ──

  Future<void> initialize({
    required String configDir,
    required String cacheDir,
    required String downloadDir,
    String vaultPassword = '',
  }) async {
    try {
      _configDir = configDir;
      await _engine.init(
        configDir: configDir,
        cacheDir: cacheDir,
        downloadDir: downloadDir,
        vaultPassword: vaultPassword,
      );

      // Subscribe to events.
      _subs.add(_engine.onAccountList.listen((accounts) {
        _accounts = accounts;
        _ensureActiveAccount();
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
      _ensureActiveAccount();
      // Load window prefs (native frame toggle) before marking initialized.
      _loadWindowPrefs();
      WidgetsBinding.instance.addObserver(this);
      if (_systemDarkMode) {
        final brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        updateTheme(brightness == Brightness.dark ? 'dark' : 'light');
      }
      if (_nativeWindowFrame && Platform.isLinux) {
        try {
          await _windowChannel.invokeMethod('setDecorated', true);
        } catch (_) {}
      }
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

  /// Switch to a different account. Notifies listeners so the UI rebuilds
  /// with the new account's chats and folders.
  void setActiveAccountId(String accountId) {
    if (_activeAccountId == accountId) return;
    _activeAccountId = accountId;
    notifyListeners();
  }

  /// Ensure activeAccountId points to a valid account.
  void _ensureActiveAccount() {
    if (_accounts.isEmpty) {
      _activeAccountId = '';
      return;
    }
    // If current selection is still valid, keep it.
    if (_activeAccountId.isNotEmpty &&
        _accounts.any((a) => a.id == _activeAccountId)) {
      return;
    }
    // Default to first account.
    _activeAccountId = _accounts.first.id;
  }

  String addAccount(String platform) {
    // Spec §3.2: enforce max accounts limit.
    if (!canAddAccount) {
      final limit = maxAccountLimit;
      Debug.log('APP', 'Cannot add account: at limit ($limit)');
      throw StateError('Maximum account limit reached ($limit)');
    }
    Debug.log('APP', 'Adding account: $platform');
    try {
      final id = _engine.addAccount(platform);
      _accounts = _engine.listAccounts();
      _ensureActiveAccount();
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
    _accountOrder.remove(accountId);
    _saveWindowPrefs();
    notifyListeners();
  }

  /// Spec §3.2: drag-to-reorder accounts. Persists new order.
  void reorderAccounts(int oldIndex, int newIndex) {
    final ordered = accounts.toList();
    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    if (newIndex < 0 || newIndex > ordered.length) return;
    if (oldIndex < newIndex) newIndex--;
    final item = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, item);
    _accountOrder = ordered.map((a) => a.id).toList();
    _saveWindowPrefs();
    notifyListeners();
  }

  void updateTheme(String theme) {
    _engine.updateConfig(theme: theme);
    _config = _engine.getConfig();
    notifyListeners();
  }

  void updateAccentColor(String hexColor) {
    _engine.updateConfig(accentColor: hexColor);
    _config = _engine.getConfig();
    notifyListeners();
  }

  String get accentColorHex =>
      _config.accentColor.isNotEmpty ? _config.accentColor : '#40a7e3';

  static const _windowChannel = MethodChannel('com.uniclient.app/window');

  /// Toggle between native system window frame and client-side custom titlebar.
  /// Spec §1: _nativeWindowFrame defaults to false; toggled via Settings → Advanced.
  Future<void> setNativeWindowFrame(bool value) async {
    if (_nativeWindowFrame == value) return;
    _nativeWindowFrame = value;
    // Tell GTK to add/remove window decorations.
    if (Platform.isLinux) {
      try {
        await _windowChannel.invokeMethod('setDecorated', value);
      } catch (_) {}
    }
    _saveWindowPrefs();
    notifyListeners();
  }

  String get _windowPrefsPath =>
      _configDir.isEmpty ? '' : '$_configDir/window_prefs.json';

  void _loadWindowPrefs() {
    final path = _windowPrefsPath;
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _nativeWindowFrame = data['nativeWindowFrame'] as bool? ?? false;
      _mainMenuAccountsShown = data['mainMenuAccountsShown'] as bool? ?? false;
      _systemDarkMode = data['systemDarkMode'] as bool? ?? false;
      _recordVideoMessages = data['recordVideoMessages'] as bool? ?? false;
      _powerSavingFlags = data['powerSavingFlags'] as int? ?? 0;
      _autoPowerSaving = data['autoPowerSaving'] as bool? ?? false;
      _showChatNameInTitle = data['showChatNameInTitle'] as bool? ?? true;
      _showAccountNameInTitle = data['showAccountNameInTitle'] as bool? ?? true;
      _showUnreadCountInTitle = data['showUnreadCountInTitle'] as bool? ?? true;
      _windowCloseBehavior = data['windowCloseBehavior'] as int? ?? 0;
      _showTrayIcon = data['showTrayIcon'] as bool? ?? true;
      _showTaskbarIcon = data['showTaskbarIcon'] as bool? ?? true;
      _monochromeTrayIcon = data['monochromeTrayIcon'] as bool? ?? false;
      _launchAtStartup = data['launchAtStartup'] as bool? ?? false;
      _startMinimized = data['startMinimized'] as bool? ?? false;
      _hardwareAccelVideo = data['hardwareAccelVideo'] as bool? ?? true;
      _openGlDisabled = data['openGlDisabled'] as bool? ?? false;
      _spellcheckerEnabled = data['spellcheckerEnabled'] as bool? ?? true;
      _spellcheckerAutoDownload = data['spellcheckerAutoDownload'] as bool? ?? true;
      _autoUpdateEnabled = data['autoUpdateEnabled'] as bool? ?? true;
      _installBetaVersions = data['installBetaVersions'] as bool? ?? false;
      _downloadPathMode = data['downloadPathMode'] as int? ?? 0;
      _customDownloadPath = data['customDownloadPath'] as String? ?? '';
      _askDownloadPath = data['askDownloadPath'] as bool? ?? false;
      final dl = data['recentDownloads'] as List<dynamic>?;
      if (dl != null) _recentDownloads = dl.cast<Map<String, dynamic>>();
      final expFlags = data['experimentalFlags'] as Map<String, dynamic>?;
      if (expFlags != null) {
        _experimentalFlags = expFlags.map((k, v) => MapEntry(k, v == true));
        _experimentalFlags.removeWhere((_, v) => !v);
      }
      final order = data['accountOrder'] as List<dynamic>?;
      if (order != null) _accountOrder = order.cast<String>();
    } catch (_) {}
  }

  void _saveWindowPrefs() {
    final path = _windowPrefsPath;
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(jsonEncode({
        'nativeWindowFrame': _nativeWindowFrame,
        'mainMenuAccountsShown': _mainMenuAccountsShown,
        'systemDarkMode': _systemDarkMode,
        'recordVideoMessages': _recordVideoMessages,
        'powerSavingFlags': _powerSavingFlags,
        'autoPowerSaving': _autoPowerSaving,
        'accountOrder': _accountOrder,
        'showChatNameInTitle': _showChatNameInTitle,
        'showAccountNameInTitle': _showAccountNameInTitle,
        'showUnreadCountInTitle': _showUnreadCountInTitle,
        'windowCloseBehavior': _windowCloseBehavior,
        'showTrayIcon': _showTrayIcon,
        'showTaskbarIcon': _showTaskbarIcon,
        'monochromeTrayIcon': _monochromeTrayIcon,
        'launchAtStartup': _launchAtStartup,
        'startMinimized': _startMinimized,
        'hardwareAccelVideo': _hardwareAccelVideo,
        'openGlDisabled': _openGlDisabled,
        'spellcheckerEnabled': _spellcheckerEnabled,
        'spellcheckerAutoDownload': _spellcheckerAutoDownload,
        'autoUpdateEnabled': _autoUpdateEnabled,
        'installBetaVersions': _installBetaVersions,
        'downloadPathMode': _downloadPathMode,
        'customDownloadPath': _customDownloadPath,
        'askDownloadPath': _askDownloadPath,
        'recentDownloads': _recentDownloads,
        'experimentalFlags': _experimentalFlags,
      }));
    } catch (_) {}
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
        if (!canAddAccount) {
          Debug.log('APP', 'CLI add rejected: at account limit ($maxAccountLimit)');
          return;
        }
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
    WidgetsBinding.instance.removeObserver(this);
    _cmdPollTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
