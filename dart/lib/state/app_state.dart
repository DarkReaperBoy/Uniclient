import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../theme/theme_file.dart';
import '../theme/telegram_palette.dart';
import '../theme/wallpaper.dart';
import '../ui/media_viewer.dart';
import '../utils/debug.dart';

/// §51.1: Ghost Mode per-account settings object.
/// Key "0" is the global profile; other keys are bare user IDs (uint64 as string).
class GhostModeAccountSettings {
  bool sendReadMessages;
  bool sendReadStories;
  bool sendOnlinePackets;
  bool sendUploadProgress;
  bool sendOfflinePacketAfterOnline;
  bool markReadAfterAction;
  bool useScheduledMessages;
  bool sendWithoutSound;
  bool sendReadMessagesLocked;
  bool sendReadStoriesLocked;
  bool sendOnlinePacketsLocked;
  bool sendUploadProgressLocked;
  bool sendOfflinePacketAfterOnlineLocked;

  GhostModeAccountSettings({
    this.sendReadMessages = true,
    this.sendReadStories = true,
    this.sendOnlinePackets = true,
    this.sendUploadProgress = true,
    this.sendOfflinePacketAfterOnline = false,
    this.markReadAfterAction = true,
    this.useScheduledMessages = false,
    this.sendWithoutSound = false,
    this.sendReadMessagesLocked = false,
    this.sendReadStoriesLocked = false,
    this.sendOnlinePacketsLocked = false,
    this.sendUploadProgressLocked = false,
    this.sendOfflinePacketAfterOnlineLocked = false,
  });

  bool get ghostModeActive =>
      (sendReadMessagesLocked || !sendReadMessages) &&
      (sendReadStoriesLocked || !sendReadStories) &&
      (sendOnlinePacketsLocked || !sendOnlinePackets) &&
      (sendUploadProgressLocked || !sendUploadProgress) &&
      (sendOfflinePacketAfterOnlineLocked || sendOfflinePacketAfterOnline);

  factory GhostModeAccountSettings.fromJson(Map<String, dynamic> j) =>
      GhostModeAccountSettings(
        sendReadMessages: j['sendReadMessages'] as bool? ?? true,
        sendReadStories: j['sendReadStories'] as bool? ?? true,
        sendOnlinePackets: j['sendOnlinePackets'] as bool? ?? true,
        sendUploadProgress: j['sendUploadProgress'] as bool? ?? true,
        sendOfflinePacketAfterOnline: j['sendOfflinePacketAfterOnline'] as bool? ?? false,
        markReadAfterAction: j['markReadAfterAction'] as bool? ?? true,
        useScheduledMessages: j['useScheduledMessages'] as bool? ?? false,
        sendWithoutSound: j['sendWithoutSound'] as bool? ?? false,
        sendReadMessagesLocked: j['sendReadMessagesLocked'] as bool? ?? false,
        sendReadStoriesLocked: j['sendReadStoriesLocked'] as bool? ?? false,
        sendOnlinePacketsLocked: j['sendOnlinePacketsLocked'] as bool? ?? false,
        sendUploadProgressLocked: j['sendUploadProgressLocked'] as bool? ?? false,
        sendOfflinePacketAfterOnlineLocked: j['sendOfflinePacketAfterOnlineLocked'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'sendReadMessages': sendReadMessages,
        'sendReadStories': sendReadStories,
        'sendOnlinePackets': sendOnlinePackets,
        'sendUploadProgress': sendUploadProgress,
        'sendOfflinePacketAfterOnline': sendOfflinePacketAfterOnline,
        'markReadAfterAction': markReadAfterAction,
        'useScheduledMessages': useScheduledMessages,
        'sendWithoutSound': sendWithoutSound,
        'sendReadMessagesLocked': sendReadMessagesLocked,
        'sendReadStoriesLocked': sendReadStoriesLocked,
        'sendOnlinePacketsLocked': sendOnlinePacketsLocked,
        'sendUploadProgressLocked': sendUploadProgressLocked,
        'sendOfflinePacketAfterOnlineLocked': sendOfflinePacketAfterOnlineLocked,
      };
}

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
  bool _passcodeLocked = false;
  int _passcodeBadTries = 0;
  DateTime? _passcodeLastTry;
  Timer? _autoLockTimer;
  int _shouldLockAt = 0; // millisecondsSinceEpoch when lock should trigger
  int _lastNonIdleTime = 0; // millisecondsSinceEpoch of last user interaction
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
  String? _revertThemeId;
  String? _revertAccentColor;
  String _customThemePath = '';
  TelegramPalette? _cachedCustomPalette;
  Uint8List? _cachedCustomBackground;
  bool _cachedCustomTiled = false;
  List<String> _accountOrder = []; // persisted display order of account IDs
  WallpaperData _wallpaper = WallpaperData.none;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Spec §3.3 / §54.8a: Menu bots per account (attach-menu bots with
  /// inMainMenu + bot.media). Keyed by account ID.
  final Map<String, List<MenuBotInfo>> _menuBots = {};

  /// Spec §2.7: Configurable swipe action for chat list rows.
  /// Values: "mute", "pin", "read", "archive", "delete". Default: "archive".
  String _swipeAction = 'archive';

  /// Spec §24.6: Submit mode for compose field. Values: "enter", "ctrl_enter".
  String _sendBy = 'enter';

  /// Spec §7.3: When true, empty-field send button shows Round (camera) instead of Record (mic).
  bool _recordVideoMessages = false;

  // Spec §25.15: AyuGram-specific theming preferences.
  int _bubbleRadius = 16; // 0-16, default matches _radiusLarge
  bool _removeTail = false;
  bool _materialSwitches = true;
  int _avatarCorners = 23; // 0-23 (kMaxAvatarCorners), 23=circle (default)
  bool _singleCornerRadius = false;
  bool _disableCustomBackgrounds = false;
  bool _simpleQuotes = false;
  bool _semiTransparentDeleted = false;
  double _wideMultiplier = 1.0; // §54.3: 1.00–4.00 in 0.05 steps
  bool _showDrawerThemeToggle = true;

  // §50.2: Streamer Mode — global, non-persistent (OFF on every cold launch).
  bool _streamerModeEnabled = false;
  bool _showStreamerToggleInDrawer = false;
  bool _showStreamerToggleInTray = false;

  // §51.5: Ghost Mode / LRead / SRead drawer visibility.
  bool _showGhostToggleInDrawer = true;
  // §51.6: Ghost Mode tray toggle visibility (persistent, default true).
  bool _showGhostToggleInTray = true;
  bool _showLReadToggleInDrawer = false;
  bool _showSReadToggleInDrawer = true;

  // §51.1: Ghost Mode per-account settings. Key "0" is global; other keys are user IDs.
  bool _useGlobalGhostMode = true;
  Map<String, GhostModeAccountSettings> _ghostModeSettings = {'0': GhostModeAccountSettings()};
  int _showViewsPanelInContextMenu = 0; // 0=visible, 1=hidden, 2=visibleWithModifier
  int _showRepeatMessageInContextMenu = 1; // 0=visible, 1=hidden, 2=visibleWithModifier (default: hidden per §53.3)
  int _showReactionsPanelInContextMenu = 0;
  int _showHideMessageInContextMenu = 1;
  int _showUserMessagesInContextMenu = 2;
  int _showMessageDetailsInContextMenu = 2;
  int _showAddFilterInContextMenu = 0;
  bool _showMessageSeconds = false;

  // §51.4: Spy essentials + Other section settings.
  bool _saveDeletedMessages = true;
  bool _saveMessagesHistory = true;
  bool _saveForBots = false;
  String _deletedMark = '\u{1F9F9}'; // broom emoji
  String _editedMark = ''; // empty = Telegram default "edited"
  bool _replaceMarksWithIcons = true;
  bool _localPremium = false;
  bool _disableAds = true;

  // §50.7: Per-peer read exclusions. Key: "accountId:chatId", value: 0=default, 1=neverRead, 2=alwaysRead.
  Map<String, int> _readExclusions = {};

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

  // Spec §19.14: Translation settings (client-side, persisted in window_prefs).
  bool _showTranslateButton = false;
  bool _translateEntireChats = false;
  List<String> _skipTranslationLanguages = ['en'];

  // §19.15: Recently used language codes (most-recent first), persisted.
  List<String> _recentLanguageCodes = [];
  String _selectedLanguageCode = 'en';

  // §19.17: Language codes the user has "deleted" (dimmed in list, restorable).
  List<String> _removedLanguageCodes = [];

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

  bool get passcodeLocked => _passcodeLocked;
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

  // §25.15 AyuGram getters
  int get bubbleRadius => _bubbleRadius;
  bool get removeTail => _removeTail;
  bool get materialSwitches => _materialSwitches;
  int get avatarCorners => _avatarCorners;
  bool get singleCornerRadius => _singleCornerRadius;
  bool get disableCustomBackgrounds => _disableCustomBackgrounds;
  bool get simpleQuotes => _simpleQuotes;
  bool get semiTransparentDeleted => _semiTransparentDeleted;
  double get wideMultiplier => _wideMultiplier;
  bool get showDrawerThemeToggle => _showDrawerThemeToggle;

  // §50.2 Streamer Mode getters
  bool get streamerModeEnabled => _streamerModeEnabled;
  bool get showStreamerToggleInDrawer => _showStreamerToggleInDrawer;
  bool get showStreamerToggleInTray => _showStreamerToggleInTray;
  bool get showGhostToggleInTray => _showGhostToggleInTray;
  bool get showGhostToggleInDrawer => _showGhostToggleInDrawer;
  bool get showLReadToggleInDrawer => _showLReadToggleInDrawer;
  bool get showSReadToggleInDrawer => _showSReadToggleInDrawer;

  // §51.1: Resolved ghost settings for the active account.
  GhostModeAccountSettings get _ghostSettings {
    if (_useGlobalGhostMode) return _ghostModeSettings['0'] ?? GhostModeAccountSettings();
    final userId = activeAccount?.selfUserId ?? '';
    if (userId.isEmpty) return _ghostModeSettings['0'] ?? GhostModeAccountSettings();
    return _ghostModeSettings[userId] ?? _ghostModeSettings['0'] ?? GhostModeAccountSettings();
  }

  String get _ghostKey {
    if (_useGlobalGhostMode) return '0';
    final userId = activeAccount?.selfUserId ?? '';
    return userId.isEmpty ? '0' : userId;
  }

  GhostModeAccountSettings _ensureGhostSettings() {
    final key = _ghostKey;
    return _ghostModeSettings.putIfAbsent(key, GhostModeAccountSettings.new);
  }

  bool get useGlobalGhostMode => _useGlobalGhostMode;
  Map<String, GhostModeAccountSettings> get ghostModeSettings =>
      Map.unmodifiable(_ghostModeSettings);
  bool get ghostModeEnabled => _ghostSettings.ghostModeActive;
  bool get sendReadMessages => _ghostSettings.sendReadMessages;
  bool get sendReadStories => _ghostSettings.sendReadStories;
  bool get sendOnlinePackets => _ghostSettings.sendOnlinePackets;
  bool get sendUploadProgress => _ghostSettings.sendUploadProgress;
  bool get sendOfflinePacketAfterOnline => _ghostSettings.sendOfflinePacketAfterOnline;
  bool get markReadAfterAction => _ghostSettings.markReadAfterAction;
  bool get useScheduledMessages => _ghostSettings.useScheduledMessages;
  bool get sendWithoutSound => _ghostSettings.sendWithoutSound;
  bool get sendReadMessagesLocked => _ghostSettings.sendReadMessagesLocked;
  bool get sendReadStoriesLocked => _ghostSettings.sendReadStoriesLocked;
  bool get sendOnlinePacketsLocked => _ghostSettings.sendOnlinePacketsLocked;
  bool get sendUploadProgressLocked => _ghostSettings.sendUploadProgressLocked;
  bool get sendOfflinePacketAfterOnlineLocked => _ghostSettings.sendOfflinePacketAfterOnlineLocked;
  int get showViewsPanelInContextMenu => _showViewsPanelInContextMenu;
  int get showRepeatMessageInContextMenu => _showRepeatMessageInContextMenu;
  int get showReactionsPanelInContextMenu => _showReactionsPanelInContextMenu;
  int get showHideMessageInContextMenu => _showHideMessageInContextMenu;
  int get showUserMessagesInContextMenu => _showUserMessagesInContextMenu;
  int get showMessageDetailsInContextMenu => _showMessageDetailsInContextMenu;
  int get showAddFilterInContextMenu => _showAddFilterInContextMenu;
  bool get showMessageSeconds => _showMessageSeconds;
  bool get saveDeletedMessages => _saveDeletedMessages;
  bool get saveMessagesHistory => _saveMessagesHistory;
  bool get saveForBots => _saveForBots;
  String get deletedMark => _deletedMark;
  String get editedMark => _editedMark;
  bool get replaceMarksWithIcons => _replaceMarksWithIcons;
  bool get localPremium => _localPremium;
  bool get disableAds => _disableAds;

  // §25.15 AyuGram setters
  void setBubbleRadius(int v) {
    v = v.clamp(0, 16);
    if (_bubbleRadius == v) return;
    _bubbleRadius = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setRemoveTail(bool v) {
    if (_removeTail == v) return;
    _removeTail = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setMaterialSwitches(bool v) {
    if (_materialSwitches == v) return;
    _materialSwitches = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setAvatarCorners(int v) {
    v = v.clamp(0, 23);
    if (_avatarCorners == v) return;
    _avatarCorners = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSingleCornerRadius(bool v) {
    if (_singleCornerRadius == v) return;
    _singleCornerRadius = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setDisableCustomBackgrounds(bool v) {
    if (_disableCustomBackgrounds == v) return;
    _disableCustomBackgrounds = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSimpleQuotes(bool v) {
    if (_simpleQuotes == v) return;
    _simpleQuotes = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setWideMultiplier(double v) {
    v = (v * 20).round() / 20.0; // snap to 0.05 increments
    v = v.clamp(1.0, 4.0);
    if ((_wideMultiplier - v).abs() < 0.001) return;
    _wideMultiplier = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSemiTransparentDeleted(bool v) {
    if (_semiTransparentDeleted == v) return;
    _semiTransparentDeleted = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowDrawerThemeToggle(bool v) {
    if (_showDrawerThemeToggle == v) return;
    _showDrawerThemeToggle = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  // §50.2 Streamer Mode setters
  void setStreamerModeEnabled(bool v) {
    if (_streamerModeEnabled == v) return;
    _streamerModeEnabled = v;
    _applyStreamerMode(v);
    notifyListeners();
  }

  void setShowStreamerToggleInDrawer(bool v) {
    if (_showStreamerToggleInDrawer == v) return;
    _showStreamerToggleInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowStreamerToggleInTray(bool v) {
    if (_showStreamerToggleInTray == v) return;
    _showStreamerToggleInTray = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowGhostToggleInTray(bool v) {
    if (_showGhostToggleInTray == v) return;
    _showGhostToggleInTray = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowGhostToggleInDrawer(bool v) {
    if (_showGhostToggleInDrawer == v) return;
    _showGhostToggleInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowLReadToggleInDrawer(bool v) {
    if (_showLReadToggleInDrawer == v) return;
    _showLReadToggleInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowSReadToggleInDrawer(bool v) {
    if (_showSReadToggleInDrawer == v) return;
    _showSReadToggleInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  Future<void> _applyStreamerMode(bool enabled) async {
    if (Platform.isWindows) {
      try {
        await _windowChannel.invokeMethod('setDisplayAffinity', enabled);
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        await _windowChannel.invokeMethod('setWindowSharing', !enabled);
      } catch (_) {}
    }
  }

  // §51.1 Ghost mode master toggle — sets all 5 core toggles respecting locks.
  void setGhostModeEnabled(bool v) {
    final s = _ensureGhostSettings();
    bool changed = false;
    if (v) {
      if (!s.sendReadMessagesLocked && s.sendReadMessages) {
        s.sendReadMessages = false; changed = true;
      }
      if (!s.sendReadStoriesLocked && s.sendReadStories) {
        s.sendReadStories = false; changed = true;
      }
      if (!s.sendOnlinePacketsLocked && s.sendOnlinePackets) {
        s.sendOnlinePackets = false; changed = true;
      }
      if (!s.sendUploadProgressLocked && s.sendUploadProgress) {
        s.sendUploadProgress = false; changed = true;
      }
      if (!s.sendOfflinePacketAfterOnlineLocked && !s.sendOfflinePacketAfterOnline) {
        s.sendOfflinePacketAfterOnline = true; changed = true;
      }
    } else {
      if (!s.sendReadMessagesLocked && !s.sendReadMessages) {
        s.sendReadMessages = true; changed = true;
      }
      if (!s.sendReadStoriesLocked && !s.sendReadStories) {
        s.sendReadStories = true; changed = true;
      }
      if (!s.sendOnlinePacketsLocked && !s.sendOnlinePackets) {
        s.sendOnlinePackets = true; changed = true;
      }
      if (!s.sendUploadProgressLocked && !s.sendUploadProgress) {
        s.sendUploadProgress = true; changed = true;
      }
      if (!s.sendOfflinePacketAfterOnlineLocked && s.sendOfflinePacketAfterOnline) {
        s.sendOfflinePacketAfterOnline = false; changed = true;
      }
    }
    if (!changed) return;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setUseGlobalGhostMode(bool v) {
    if (_useGlobalGhostMode == v) return;
    _useGlobalGhostMode = v;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendReadMessages(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendReadMessages == v) return;
    s.sendReadMessages = v;
    _engine.updateConfig(sendReadReceipts: v);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendReadStories(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendReadStories == v) return;
    s.sendReadStories = v;
    _engine.updateConfig(sendReadStories: v);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendOnlinePackets(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendOnlinePackets == v) return;
    s.sendOnlinePackets = v;
    _engine.updateConfig(sendOnlinePackets: v);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendUploadProgress(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendUploadProgress == v) return;
    s.sendUploadProgress = v;
    _engine.updateConfig(sendTyping: v);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendOfflinePacketAfterOnline(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendOfflinePacketAfterOnline == v) return;
    s.sendOfflinePacketAfterOnline = v;
    _engine.updateConfig(sendOfflineAfterOnline: v);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setMarkReadAfterAction(bool v) {
    final s = _ensureGhostSettings();
    if (s.markReadAfterAction == v) return;
    s.markReadAfterAction = v;
    if (v) s.useScheduledMessages = false;
    _engine.updateConfig(
      markReadAfterAction: v,
      useScheduledMessages: v ? false : null,
    );
    notifyListeners();
    _saveWindowPrefs();
  }

  void setUseScheduledMessages(bool v) {
    final s = _ensureGhostSettings();
    if (s.useScheduledMessages == v) return;
    s.useScheduledMessages = v;
    if (v) s.markReadAfterAction = false;
    _engine.updateConfig(
      useScheduledMessages: v,
      markReadAfterAction: v ? false : null,
    );
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendWithoutSound(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendWithoutSound == v) return;
    s.sendWithoutSound = v;
    _engine.updateConfig(sendWithoutSound: v);
    notifyListeners();
    _saveWindowPrefs();
  }

  void toggleLock(String field) {
    final s = _ensureGhostSettings();
    final locks = [
      s.sendReadMessagesLocked,
      s.sendReadStoriesLocked,
      s.sendOnlinePacketsLocked,
      s.sendUploadProgressLocked,
      s.sendOfflinePacketAfterOnlineLocked,
    ];
    bool isCurrentlyLocked;
    switch (field) {
      case 'sendReadMessages':
        isCurrentlyLocked = s.sendReadMessagesLocked;
      case 'sendReadStories':
        isCurrentlyLocked = s.sendReadStoriesLocked;
      case 'sendOnlinePackets':
        isCurrentlyLocked = s.sendOnlinePacketsLocked;
      case 'sendUploadProgress':
        isCurrentlyLocked = s.sendUploadProgressLocked;
      case 'sendOfflinePacketAfterOnline':
        isCurrentlyLocked = s.sendOfflinePacketAfterOnlineLocked;
      default:
        return;
    }
    if (!isCurrentlyLocked) {
      final unlockedCount = locks.where((l) => !l).length;
      if (unlockedCount <= 1) return;
    }
    switch (field) {
      case 'sendReadMessages':
        s.sendReadMessagesLocked = !s.sendReadMessagesLocked;
      case 'sendReadStories':
        s.sendReadStoriesLocked = !s.sendReadStoriesLocked;
      case 'sendOnlinePackets':
        s.sendOnlinePacketsLocked = !s.sendOnlinePacketsLocked;
      case 'sendUploadProgress':
        s.sendUploadProgressLocked = !s.sendUploadProgressLocked;
      case 'sendOfflinePacketAfterOnline':
        s.sendOfflinePacketAfterOnlineLocked = !s.sendOfflinePacketAfterOnlineLocked;
    }
    notifyListeners();
    _saveWindowPrefs();
  }

  bool isLocked(String field) => switch (field) {
    'sendReadMessages' => _ghostSettings.sendReadMessagesLocked,
    'sendReadStories' => _ghostSettings.sendReadStoriesLocked,
    'sendOnlinePackets' => _ghostSettings.sendOnlinePacketsLocked,
    'sendUploadProgress' => _ghostSettings.sendUploadProgressLocked,
    'sendOfflinePacketAfterOnline' => _ghostSettings.sendOfflinePacketAfterOnlineLocked,
    _ => false,
  };

  void setSaveDeletedMessages(bool v) {
    if (_saveDeletedMessages == v) return;
    _saveDeletedMessages = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSaveMessagesHistory(bool v) {
    if (_saveMessagesHistory == v) return;
    _saveMessagesHistory = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSaveForBots(bool v) {
    if (_saveForBots == v) return;
    _saveForBots = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setDeletedMark(String v) {
    if (_deletedMark == v) return;
    _deletedMark = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setEditedMark(String v) {
    if (_editedMark == v) return;
    _editedMark = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setReplaceMarksWithIcons(bool v) {
    if (_replaceMarksWithIcons == v) return;
    _replaceMarksWithIcons = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setLocalPremium(bool v) {
    if (_localPremium == v) return;
    _localPremium = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setDisableAds(bool v) {
    if (_disableAds == v) return;
    _disableAds = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void _syncGhostToEngine() {
    final s = _ghostSettings;
    _engine.updateConfig(
      sendReadReceipts: s.sendReadMessages,
      sendTyping: s.sendUploadProgress,
      sendReadStories: s.sendReadStories,
      sendOnlinePackets: s.sendOnlinePackets,
      sendOfflineAfterOnline: s.sendOfflinePacketAfterOnline,
      markReadAfterAction: s.markReadAfterAction,
      useScheduledMessages: s.useScheduledMessages,
      sendWithoutSound: s.sendWithoutSound,
    );
  }

  void _autoMigrateGhostToGlobal() {
    if (_useGlobalGhostMode || _accounts.length > 1) return;
    final userId = _accounts.firstOrNull?.selfUserId ?? '';
    if (userId.isEmpty) return;
    final perAccount = _ghostModeSettings[userId];
    if (perAccount == null) return;
    _ghostModeSettings['0'] = perAccount;
    _ghostModeSettings.remove(userId);
    _useGlobalGhostMode = true;
    _saveWindowPrefs();
  }

  // §50.7: Per-peer read exclusion. 0=default, 1=neverRead, 2=alwaysRead.
  int getReadExclusion(String accountId, String chatId) =>
      _readExclusions['$accountId:$chatId'] ?? 0;

  void setReadExclusion(String accountId, String chatId, int value) {
    final key = '$accountId:$chatId';
    if (value == 0) {
      _readExclusions.remove(key);
    } else {
      _readExclusions[key] = value.clamp(0, 2);
    }
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowViewsPanelInContextMenu(int v) {
    if (_showViewsPanelInContextMenu == v) return;
    _showViewsPanelInContextMenu = v.clamp(0, 2);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowRepeatMessageInContextMenu(int v) {
    if (_showRepeatMessageInContextMenu == v) return;
    _showRepeatMessageInContextMenu = v.clamp(0, 2);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowReactionsPanelInContextMenu(int v) {
    if (_showReactionsPanelInContextMenu == v) return;
    _showReactionsPanelInContextMenu = v.clamp(0, 2);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowHideMessageInContextMenu(int v) {
    if (_showHideMessageInContextMenu == v) return;
    _showHideMessageInContextMenu = v.clamp(0, 2);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowUserMessagesInContextMenu(int v) {
    if (_showUserMessagesInContextMenu == v) return;
    _showUserMessagesInContextMenu = v.clamp(0, 2);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowMessageDetailsInContextMenu(int v) {
    if (_showMessageDetailsInContextMenu == v) return;
    _showMessageDetailsInContextMenu = v.clamp(0, 2);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowAddFilterInContextMenu(int v) {
    if (_showAddFilterInContextMenu == v) return;
    _showAddFilterInContextMenu = v.clamp(0, 2);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowMessageSeconds(bool v) {
    if (_showMessageSeconds == v) return;
    _showMessageSeconds = v;
    notifyListeners();
    _saveWindowPrefs();
  }

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

  WallpaperData get wallpaper => _wallpaper;

  void setWallpaper(WallpaperData data) {
    _wallpaper = data;
    _saveWallpaper();
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
      updateTheme(brightness == Brightness.dark ? 'night' : 'day_blue');
    }
    _saveWindowPrefs();
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_systemDarkMode) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      updateTheme(brightness == Brightness.dark ? 'night' : 'day_blue');
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

  String get sendBy => _sendBy;
  set sendBy(String value) {
    if (_sendBy != value) {
      _sendBy = value;
      _saveWindowPrefs();
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

  // §19.14: Translation settings
  bool get showTranslateButton => _showTranslateButton;
  bool get translateEntireChats => _translateEntireChats;
  List<String> get skipTranslationLanguages =>
      List.unmodifiable(_skipTranslationLanguages);

  void setShowTranslateButton(bool v) {
    if (v == _showTranslateButton) return;
    _showTranslateButton = v;
    _saveWindowPrefs();
    notifyListeners();
  }

  void setTranslateEntireChats(bool v) {
    if (v == _translateEntireChats) return;
    _translateEntireChats = v;
    _saveWindowPrefs();
    notifyListeners();
  }

  void setSkipTranslationLanguages(List<String> langs) {
    if (langs.isEmpty) return;
    _skipTranslationLanguages = List<String>.from(langs);
    _saveWindowPrefs();
    notifyListeners();
  }

  // §19.15: Recent language codes and selected language.
  List<String> get recentLanguageCodes => List.unmodifiable(_recentLanguageCodes);
  String get selectedLanguageCode => _selectedLanguageCode;

  void addRecentLanguage(String code) {
    _recentLanguageCodes.remove(code);
    _recentLanguageCodes.insert(0, code);
    if (_recentLanguageCodes.length > 20) {
      _recentLanguageCodes = _recentLanguageCodes.sublist(0, 20);
    }
    _selectedLanguageCode = code;
    _saveWindowPrefs();
    notifyListeners();
  }

  // §19.17: Removed (dimmed) language codes.
  List<String> get removedLanguageCodes => List.unmodifiable(_removedLanguageCodes);

  void addRemovedLanguage(String code) {
    if (_removedLanguageCodes.contains(code)) return;
    _removedLanguageCodes.add(code);
    _saveWindowPrefs();
    notifyListeners();
  }

  void restoreRemovedLanguage(String code) {
    if (!_removedLanguageCodes.remove(code)) return;
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
    'light' || 'classic_day' || 'day_blue' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };

  String get themeId => switch (_config.theme) {
    'classic_day' => 'classic_day',
    'day_blue' || 'light' => 'day_blue',
    'night_green' => 'night_green',
    'night' || 'dark' || _ => 'night',
  };

  ConnState connStateFor(String accountId) =>
      _connStates[accountId] ?? ConnState.disconnected;

  void debugSetConnState(String accountId, ConnState state) {
    _connStates[accountId] = state;
    notifyListeners();
  }

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
        if (newState == ConnState.connected && oldState != ConnState.connected) {
          _accounts = _engine.listAccounts();
        }
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
      // §51.1 Sync ghost mode toggles to engine on startup.
      _syncGhostToEngine();
      WidgetsBinding.instance.addObserver(this);
      if (_systemDarkMode) {
        final brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        updateTheme(brightness == Brightness.dark ? 'night' : 'day_blue');
      }
      if (_nativeWindowFrame && Platform.isLinux) {
        try {
          await _windowChannel.invokeMethod('setDecorated', true);
        } catch (_) {}
      }
      _initialized = true;
      Debug.log('APP', 'Engine initialized, ${_accounts.length} accounts');
      _checkPasscodeAtStartup();
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

  void _checkPasscodeAtStartup() {
    if (_configDir.isEmpty) return;
    final file = File('$_configDir/local_passcode.json');
    if (file.existsSync()) {
      try {
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        if ((data['hash'] as String? ?? '').isNotEmpty) {
          _passcodeLocked = true;
        }
      } catch (_) {}
    }
    _lastNonIdleTime = DateTime.now().millisecondsSinceEpoch;
    checkAutoLock(_lastNonIdleTime);
  }

  bool get hasLocalPasscode {
    if (_configDir.isEmpty) return false;
    final file = File('$_configDir/local_passcode.json');
    if (!file.existsSync()) return false;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (data['hash'] as String? ?? '').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void lockByPasscode() {
    if (!hasLocalPasscode) return;
    PipManager.instance.dismiss();
    MediaViewer.close();
    _passcodeLocked = true;
    notifyListeners();
  }

  void unlockPasscode() {
    _passcodeLocked = false;
    _passcodeBadTries = 0;
    _passcodeLastTry = null;
    _lastNonIdleTime = DateTime.now().millisecondsSinceEpoch;
    checkAutoLock(_lastNonIdleTime);
    notifyListeners();
  }

  bool passcodeCanTry() {
    if (_passcodeBadTries < 3) return true;
    final last = _passcodeLastTry;
    if (last == null) return true;
    final elapsed = DateTime.now().difference(last).inSeconds;
    return elapsed >= _passcodeBadTries * 5;
  }

  bool checkPasscode(String entered) {
    if (_configDir.isEmpty) return false;
    final file = File('$_configDir/local_passcode.json');
    if (!file.existsSync()) return false;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final storedHash = data['hash'] as String? ?? '';
      final bytes = utf8.encode(entered);
      final hash = sha256.convert(bytes).toString();
      if (hash == storedHash) {
        unlockPasscode();
        return true;
      }
    } catch (_) {}
    _passcodeBadTries++;
    _passcodeLastTry = DateTime.now();
    return false;
  }

  static const _kAutoLockTimeoutLateMs = 3000;

  int _readAutoLockSeconds() {
    if (_configDir.isEmpty) return 0;
    final file = File('$_configDir/local_passcode.json');
    if (!file.existsSync()) return 0;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (data['autoLockSeconds'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void checkAutoLock([int? lastNonIdle]) {
    if (!hasLocalPasscode || _passcodeLocked || _accounts.isEmpty) {
      _autoLockTimer?.cancel();
      _shouldLockAt = 0;
      return;
    }
    final autoLockSec = _readAutoLockSeconds();
    if (autoLockSec <= 0) {
      _autoLockTimer?.cancel();
      _shouldLockAt = 0;
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final idle = lastNonIdle ?? _lastNonIdleTime;
    if (idle <= 0) {
      _lastNonIdleTime = now;
      _shouldLockAt = now + autoLockSec * 1000;
      _autoLockTimer?.cancel();
      _autoLockTimer = Timer(Duration(seconds: autoLockSec), () => checkAutoLock());
      return;
    }
    final shouldLockInMs = autoLockSec * 1000;
    final checkTimeMs = now - idle;
    if (checkTimeMs >= shouldLockInMs ||
        (_shouldLockAt > 0 && now > _shouldLockAt + _kAutoLockTimeoutLateMs)) {
      lockByPasscode();
      return;
    }
    final remaining = shouldLockInMs - checkTimeMs;
    _shouldLockAt = idle + shouldLockInMs;
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(Duration(milliseconds: remaining), () => checkAutoLock());
  }

  void updateNonIdle() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNonIdleTime < 1000) return;
    _lastNonIdleTime = now;
    if (hasLocalPasscode && !_passcodeLocked && _readAutoLockSeconds() > 0) {
      checkAutoLock(_lastNonIdleTime);
    }
  }

  void localPasscodeChanged() {
    _shouldLockAt = 0;
    _autoLockTimer?.cancel();
    checkAutoLock(DateTime.now().millisecondsSinceEpoch);
  }

  /// Switch to a different account. Notifies listeners so the UI rebuilds
  /// with the new account's chats and folders.
  void setActiveAccountId(String accountId) {
    if (_activeAccountId == accountId) return;
    _activeAccountId = accountId;
    if (!_useGlobalGhostMode) _syncGhostToEngine();
    _autoMigrateGhostToGlobal();
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
    _ensureActiveAccount();
    _saveWindowPrefs();
    removePasscodeIfEmpty();
    notifyListeners();
  }

  void removePasscodeIfEmpty() {
    if (_accounts.isNotEmpty) return;
    if (!hasLocalPasscode) return;
    if (_passcodeLocked) {
      _passcodeLocked = false;
      _passcodeBadTries = 0;
      _passcodeLastTry = null;
    }
    if (_configDir.isEmpty) return;
    final file = File('$_configDir/local_passcode.json');
    if (file.existsSync()) {
      file.deleteSync();
    }
    _autoLockTimer?.cancel();
    _shouldLockAt = 0;
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

  bool get isTestingTheme => _revertThemeId != null;

  void applyTestingTheme(String theme, {String? accentColor}) {
    if (_revertThemeId == null) {
      _revertThemeId = themeId;
      _revertAccentColor = accentColorHex;
    }
    if (accentColor != null) {
      _engine.updateConfig(theme: theme, accentColor: accentColor);
    } else {
      _engine.updateConfig(theme: theme);
    }
    _config = _engine.getConfig();
    notifyListeners();
  }

  void keepAppliedTheme() {
    _revertThemeId = null;
    _revertAccentColor = null;
    notifyListeners();
  }

  void revertTheme() {
    if (_revertThemeId == null) return;
    final t = _revertThemeId!;
    final a = _revertAccentColor;
    _revertThemeId = null;
    _revertAccentColor = null;
    _engine.updateConfig(theme: t, accentColor: a ?? '#40a7e3');
    _config = _engine.getConfig();
    notifyListeners();
  }

  // ── §25.10 Custom theme with caching ──

  TelegramPalette? get customPalette => _cachedCustomPalette;
  Uint8List? get customThemeBackground => _cachedCustomBackground;
  bool get customThemeTiled => _cachedCustomTiled;
  String get customThemePath => _customThemePath;
  bool get hasCustomTheme => _customThemePath.isNotEmpty && _cachedCustomPalette != null;

  void applyCustomTheme(String path, Uint8List bytes) {
    final parsed = parseThemeFile(bytes);
    if (parsed == null) return;

    _customThemePath = path;
    _cachedCustomPalette = parsed.palette;
    _cachedCustomBackground = parsed.backgroundImage;
    _cachedCustomTiled = parsed.backgroundTiled;

    if (_configDir.isNotEmpty) {
      final cache = buildThemeCache(bytes, parsed);
      saveThemeCache(_configDir, cache);
    }

    _saveWindowPrefs();
    notifyListeners();
  }

  void clearCustomTheme() {
    _customThemePath = '';
    _cachedCustomPalette = null;
    _cachedCustomBackground = null;
    _cachedCustomTiled = false;
    if (_configDir.isNotEmpty) clearThemeCache(_configDir);
    _saveWindowPrefs();
    notifyListeners();
  }

  void _loadCustomThemeFromCache() {
    if (_configDir.isEmpty || _customThemePath.isEmpty) return;

    final cache = loadThemeCache(_configDir);
    if (cache == null) {
      _reloadCustomThemeFromFile();
      return;
    }

    final themeFile = File(_customThemePath);
    if (!themeFile.existsSync()) {
      _customThemePath = '';
      clearThemeCache(_configDir);
      return;
    }

    final bytes = themeFile.readAsBytesSync();
    if (validateThemeCache(cache, bytes)) {
      _cachedCustomPalette = cache.palette;
      _cachedCustomBackground = cache.backgroundImage;
      _cachedCustomTiled = cache.tileBg;
    } else {
      _reloadCustomThemeFromFile();
    }
  }

  void _reloadCustomThemeFromFile() {
    try {
      final themeFile = File(_customThemePath);
      if (!themeFile.existsSync()) {
        _customThemePath = '';
        return;
      }
      final bytes = themeFile.readAsBytesSync();
      final parsed = parseThemeFile(bytes);
      if (parsed == null) {
        _customThemePath = '';
        return;
      }
      _cachedCustomPalette = parsed.palette;
      _cachedCustomBackground = parsed.backgroundImage;
      _cachedCustomTiled = parsed.backgroundTiled;

      if (_configDir.isNotEmpty) {
        final cache = buildThemeCache(bytes, parsed);
        saveThemeCache(_configDir, cache);
      }
    } catch (_) {
      _customThemePath = '';
    }
  }

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
      _sendBy = data['sendBy'] as String? ?? 'enter';
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
      _showTranslateButton = data['showTranslateButton'] as bool? ?? false;
      _translateEntireChats = data['translateEntireChats'] as bool? ?? false;
      final skipLangs = data['skipTranslationLanguages'] as List<dynamic>?;
      if (skipLangs != null && skipLangs.isNotEmpty) {
        _skipTranslationLanguages = skipLangs.cast<String>();
      }
      final recLangs = data['recentLanguageCodes'] as List<dynamic>?;
      if (recLangs != null) _recentLanguageCodes = recLangs.cast<String>();
      _selectedLanguageCode = data['selectedLanguageCode'] as String? ?? 'en';
      final rmLangs = data['removedLanguageCodes'] as List<dynamic>?;
      if (rmLangs != null) _removedLanguageCodes = rmLangs.cast<String>();
      final order = data['accountOrder'] as List<dynamic>?;
      if (order != null) _accountOrder = order.cast<String>();
      _customThemePath = data['customThemePath'] as String? ?? '';
      // §25.15 AyuGram prefs
      _bubbleRadius = (data['bubbleRadius'] as int?) ?? 16;
      _removeTail = data['removeTail'] as bool? ?? false;
      _materialSwitches = data['materialSwitches'] as bool? ?? false;
      final oldAvatarRadius = data['avatarCornerRadius'] as int?;
      _avatarCorners = (data['avatarCorners'] as int?) ??
          (oldAvatarRadius != null ? (oldAvatarRadius * 23 / 50).round().clamp(0, 23) : 23);
      _singleCornerRadius = data['singleCornerRadius'] as bool? ?? false;
      _disableCustomBackgrounds = data['disableCustomBackgrounds'] as bool? ?? false;
      _simpleQuotes = data['simpleQuotes'] as bool? ?? false;
      _semiTransparentDeleted = data['semiTransparentDeleted'] as bool? ?? false;
      _wideMultiplier = (data['wideMultiplier'] as num?)?.toDouble() ?? 1.0;
      _showDrawerThemeToggle = data['showDrawerThemeToggle'] as bool? ?? true;
      // §50.2 Streamer Mode toggle visibility (persistent); mode itself is NOT persisted
      _showStreamerToggleInDrawer = data['showStreamerToggleInDrawer'] as bool? ?? false;
      _showStreamerToggleInTray = data['showStreamerToggleInTray'] as bool? ?? false;
      _showGhostToggleInDrawer = data['showGhostToggleInDrawer'] as bool? ?? true;
      _showGhostToggleInTray = data['showGhostToggleInTray'] as bool? ?? true;
      _showLReadToggleInDrawer = data['showLReadToggleInDrawer'] as bool? ?? false;
      _showSReadToggleInDrawer = data['showSReadToggleInDrawer'] as bool? ?? true;
      // §51.1 Ghost Mode per-account settings (with migration from flat format).
      final ghostMap = data['ghostModeSettings'] as Map<String, dynamic>?;
      if (ghostMap != null) {
        _useGlobalGhostMode = data['useGlobalGhostMode'] as bool? ?? true;
        _ghostModeSettings = ghostMap.map((k, v) =>
            MapEntry(k, GhostModeAccountSettings.fromJson(v as Map<String, dynamic>)));
        if (!_ghostModeSettings.containsKey('0')) {
          _ghostModeSettings['0'] = GhostModeAccountSettings();
        }
      } else {
        // Migrate old flat format → global ("0") profile.
        final oldGhost = data['ghostModeEnabled'] as bool?;
        _useGlobalGhostMode = true;
        _ghostModeSettings = {
          '0': GhostModeAccountSettings(
            sendReadMessages: data['sendReadMessages'] as bool? ?? (oldGhost != null ? !oldGhost : true),
            sendReadStories: data['sendReadStories'] as bool? ?? true,
            sendOnlinePackets: data['sendOnlinePackets'] as bool? ?? true,
            sendUploadProgress: data['sendUploadProgress'] as bool? ?? true,
            sendOfflinePacketAfterOnline: data['sendOfflinePacketAfterOnline'] as bool? ?? false,
            markReadAfterAction: data['markReadAfterAction'] as bool? ?? true,
            sendReadMessagesLocked: data['sendReadMessagesLocked'] as bool? ?? false,
            sendReadStoriesLocked: data['sendReadStoriesLocked'] as bool? ?? false,
            sendOnlinePacketsLocked: data['sendOnlinePacketsLocked'] as bool? ?? false,
            sendUploadProgressLocked: data['sendUploadProgressLocked'] as bool? ?? false,
            sendOfflinePacketAfterOnlineLocked: data['sendOfflinePacketAfterOnlineLocked'] as bool? ?? false,
          ),
        };
      }
      _showViewsPanelInContextMenu = data['showViewsPanelInContextMenu'] as int? ?? 0;
      _showRepeatMessageInContextMenu = data['showRepeatMessageInContextMenu'] as int? ?? 1;
      _showReactionsPanelInContextMenu = data['showReactionsPanelInContextMenu'] as int? ?? 0;
      _showHideMessageInContextMenu = data['showHideMessageInContextMenu'] as int? ?? 1;
      _showUserMessagesInContextMenu = data['showUserMessagesInContextMenu'] as int? ?? 2;
      _showMessageDetailsInContextMenu = data['showMessageDetailsInContextMenu'] as int? ?? 2;
      _showAddFilterInContextMenu = data['showAddFilterInContextMenu'] as int? ?? 0;
      _showMessageSeconds = data['showMessageSeconds'] as bool? ?? false;
      _saveDeletedMessages = data['saveDeletedMessages'] as bool? ?? true;
      _saveMessagesHistory = data['saveMessagesHistory'] as bool? ?? true;
      _saveForBots = data['saveForBots'] as bool? ?? false;
      _deletedMark = data['deletedMark'] as String? ?? '\u{1F9F9}';
      _editedMark = data['editedMark'] as String? ?? '';
      _replaceMarksWithIcons = data['replaceMarksWithIcons'] as bool? ?? true;
      _localPremium = data['localPremium'] as bool? ?? false;
      _disableAds = data['disableAds'] as bool? ?? true;
      final rawExcl = data['readExclusions'] as Map<String, dynamic>?;
      if (rawExcl != null) {
        _readExclusions = rawExcl.map((k, v) => MapEntry(k, (v as int?) ?? 0));
      }
      _loadWallpaper(data);
      _loadCustomThemeFromCache();
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
        'sendBy': _sendBy,
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
        'showTranslateButton': _showTranslateButton,
        'translateEntireChats': _translateEntireChats,
        'skipTranslationLanguages': _skipTranslationLanguages,
        'recentLanguageCodes': _recentLanguageCodes,
        'selectedLanguageCode': _selectedLanguageCode,
        'removedLanguageCodes': _removedLanguageCodes,
        'experimentalFlags': _experimentalFlags,
        'customThemePath': _customThemePath,
        'bubbleRadius': _bubbleRadius,
        'removeTail': _removeTail,
        'materialSwitches': _materialSwitches,
        'avatarCorners': _avatarCorners,
        'singleCornerRadius': _singleCornerRadius,
        'disableCustomBackgrounds': _disableCustomBackgrounds,
        'simpleQuotes': _simpleQuotes,
        'semiTransparentDeleted': _semiTransparentDeleted,
        'wideMultiplier': _wideMultiplier,
        'showDrawerThemeToggle': _showDrawerThemeToggle,
        'showStreamerToggleInDrawer': _showStreamerToggleInDrawer,
        'showStreamerToggleInTray': _showStreamerToggleInTray,
        'showGhostToggleInDrawer': _showGhostToggleInDrawer,
        'showGhostToggleInTray': _showGhostToggleInTray,
        'showLReadToggleInDrawer': _showLReadToggleInDrawer,
        'showSReadToggleInDrawer': _showSReadToggleInDrawer,
        'useGlobalGhostMode': _useGlobalGhostMode,
        'ghostModeSettings': _ghostModeSettings.map((k, v) => MapEntry(k, v.toJson())),
        'showViewsPanelInContextMenu': _showViewsPanelInContextMenu,
        'showRepeatMessageInContextMenu': _showRepeatMessageInContextMenu,
        'showReactionsPanelInContextMenu': _showReactionsPanelInContextMenu,
        'showHideMessageInContextMenu': _showHideMessageInContextMenu,
        'showUserMessagesInContextMenu': _showUserMessagesInContextMenu,
        'showMessageDetailsInContextMenu': _showMessageDetailsInContextMenu,
        'showAddFilterInContextMenu': _showAddFilterInContextMenu,
        'showMessageSeconds': _showMessageSeconds,
        'saveDeletedMessages': _saveDeletedMessages,
        'saveMessagesHistory': _saveMessagesHistory,
        'saveForBots': _saveForBots,
        'deletedMark': _deletedMark,
        'editedMark': _editedMark,
        'replaceMarksWithIcons': _replaceMarksWithIcons,
        'localPremium': _localPremium,
        'disableAds': _disableAds,
        'readExclusions': _readExclusions,
        'wallpaperType': _wallpaper.type.index,
        'wallpaperColors': _wallpaper.backgroundColors
            .map((c) => (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0'))
            .toList(),
        'wallpaperIntensity': _wallpaper.patternIntensity,
        'wallpaperRotation': _wallpaper.gradientRotation,
        'wallpaperBlurred': _wallpaper.blurred,
        'wallpaperTiled': _wallpaper.tiled,
      }));
    } catch (_) {}
  }

  void _saveWallpaper() {
    _saveWindowPrefs();
    if (_wallpaper.imageBytes != null && _configDir.isNotEmpty) {
      try {
        File('$_configDir/wallpaper.dat').writeAsBytesSync(_wallpaper.imageBytes!);
      } catch (_) {}
    } else if (_wallpaper.patternBytes != null && _configDir.isNotEmpty) {
      try {
        File('$_configDir/wallpaper_pattern.dat').writeAsBytesSync(_wallpaper.patternBytes!);
      } catch (_) {}
    }
  }

  void _loadWallpaper(Map<String, dynamic> data) {
    final typeIdx = data['wallpaperType'] as int? ?? 0;
    final type = WallpaperType.values.elementAtOrNull(typeIdx) ?? WallpaperType.solid;
    final colorHexes = (data['wallpaperColors'] as List<dynamic>?)?.cast<String>() ?? [];
    final intensity = data['wallpaperIntensity'] as int? ?? 40;
    final rotation = data['wallpaperRotation'] as int? ?? 0;
    final blurred = data['wallpaperBlurred'] as bool? ?? false;
    final tiled = data['wallpaperTiled'] as bool? ?? false;

    final colors = <Color>[];
    for (final hex in colorHexes) {
      final v = int.tryParse('FF$hex', radix: 16);
      if (v != null) colors.add(Color(v));
    }

    Uint8List? imageBytes;
    Uint8List? patternBytes;
    if (_configDir.isNotEmpty) {
      if (type == WallpaperType.image) {
        final f = File('$_configDir/wallpaper.dat');
        if (f.existsSync()) imageBytes = f.readAsBytesSync();
      } else if (type == WallpaperType.pattern) {
        final f = File('$_configDir/wallpaper_pattern.dat');
        if (f.existsSync()) patternBytes = f.readAsBytesSync();
      }
    }

    _wallpaper = WallpaperData(
      type: type,
      backgroundColors: colors,
      patternIntensity: intensity,
      gradientRotation: rotation,
      blurred: blurred,
      tiled: tiled,
      imageBytes: imageBytes,
      patternBytes: patternBytes,
    );
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
    _autoLockTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
