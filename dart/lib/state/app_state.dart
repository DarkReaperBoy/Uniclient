import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/engine_service.dart';
import '../data/ayu_filter.dart';
import '../models/engine_models.dart';
import '../theme/theme_file.dart';
import '../theme/telegram_palette.dart';
import '../theme/wallpaper.dart';
import '../ui/emoji_panel.dart'
    show resetEmojiPrefsForAccountSwitch, initEmojiSuggestionVariants;
import '../ui/media_viewer.dart';
import '../utils/debug.dart';
import '../utils/safe_string.dart' show gFilterZalgo;

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
  int sendWithoutSound; // 0=Never, 1=InGhostMode, 2=Always
  bool suggestGhostModeBeforeViewingStory;
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
    this.sendWithoutSound = 0,
    this.suggestGhostModeBeforeViewingStory = true,
    this.sendReadMessagesLocked = false,
    this.sendReadStoriesLocked = false,
    this.sendOnlinePacketsLocked = false,
    this.sendUploadProgressLocked = false,
    this.sendOfflinePacketAfterOnlineLocked = false,
  });

  void copyFrom(GhostModeAccountSettings src) {
    sendReadMessages = src.sendReadMessages;
    sendReadStories = src.sendReadStories;
    sendOnlinePackets = src.sendOnlinePackets;
    sendUploadProgress = src.sendUploadProgress;
    sendOfflinePacketAfterOnline = src.sendOfflinePacketAfterOnline;
    markReadAfterAction = src.markReadAfterAction;
    useScheduledMessages = src.useScheduledMessages;
    sendWithoutSound = src.sendWithoutSound;
    suggestGhostModeBeforeViewingStory = src.suggestGhostModeBeforeViewingStory;
    sendReadMessagesLocked = src.sendReadMessagesLocked;
    sendReadStoriesLocked = src.sendReadStoriesLocked;
    sendOnlinePacketsLocked = src.sendOnlinePacketsLocked;
    sendUploadProgressLocked = src.sendUploadProgressLocked;
    sendOfflinePacketAfterOnlineLocked = src.sendOfflinePacketAfterOnlineLocked;
  }

  bool get ghostModeActive =>
      (sendReadMessagesLocked || !sendReadMessages) &&
      (sendReadStoriesLocked || !sendReadStories) &&
      (sendOnlinePacketsLocked || !sendOnlinePackets) &&
      (sendUploadProgressLocked || !sendUploadProgress) &&
      (sendOfflinePacketAfterOnlineLocked || sendOfflinePacketAfterOnline);

  bool get shouldSendWithoutSound {
    switch (sendWithoutSound) {
      case 0: return false;
      case 1: return ghostModeActive;
      case 2: return true;
      default: return false;
    }
  }

  factory GhostModeAccountSettings.fromJson(Map<String, dynamic> j) {
    final rawSendWithoutSound = j['sendWithoutSound'];
    int sendWithoutSoundValue;
    if (rawSendWithoutSound is bool) {
      sendWithoutSoundValue = rawSendWithoutSound ? 2 : 0;
    } else {
      sendWithoutSoundValue = (rawSendWithoutSound as int?) ?? 0;
    }
    return GhostModeAccountSettings(
      sendReadMessages: j['sendReadMessages'] as bool? ?? true,
      sendReadStories: j['sendReadStories'] as bool? ?? true,
      sendOnlinePackets: j['sendOnlinePackets'] as bool? ?? true,
      sendUploadProgress: j['sendUploadProgress'] as bool? ?? true,
      sendOfflinePacketAfterOnline: j['sendOfflinePacketAfterOnline'] as bool? ?? false,
      markReadAfterAction: j['markReadAfterAction'] as bool? ?? true,
      useScheduledMessages: j['useScheduledMessages'] as bool? ?? false,
      sendWithoutSound: sendWithoutSoundValue,
      suggestGhostModeBeforeViewingStory: j['suggestGhostModeBeforeViewingStory'] as bool? ?? true,
      sendReadMessagesLocked: j['sendReadMessagesLocked'] as bool? ?? false,
      sendReadStoriesLocked: j['sendReadStoriesLocked'] as bool? ?? false,
      sendOnlinePacketsLocked: j['sendOnlinePacketsLocked'] as bool? ?? false,
      sendUploadProgressLocked: j['sendUploadProgressLocked'] as bool? ?? false,
      sendOfflinePacketAfterOnlineLocked: j['sendOfflinePacketAfterOnlineLocked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'sendReadMessages': sendReadMessages,
        'sendReadStories': sendReadStories,
        'sendOnlinePackets': sendOnlinePackets,
        'sendUploadProgress': sendUploadProgress,
        'sendOfflinePacketAfterOnline': sendOfflinePacketAfterOnline,
        'markReadAfterAction': markReadAfterAction,
        'useScheduledMessages': useScheduledMessages,
        'sendWithoutSound': sendWithoutSound,
        'suggestGhostModeBeforeViewingStory': suggestGhostModeBeforeViewingStory,
        'sendReadMessagesLocked': sendReadMessagesLocked,
        'sendReadStoriesLocked': sendReadStoriesLocked,
        'sendOnlinePacketsLocked': sendOnlinePacketsLocked,
        'sendUploadProgressLocked': sendUploadProgressLocked,
        'sendOfflinePacketAfterOnlineLocked': sendOfflinePacketAfterOnlineLocked,
      };
}

/// AyuGram "message shot" (message screenshot) render settings.
/// 1:1 with `MessageShotSettings` in AyuGram `ayu/ayu_settings.h:184-238`
/// and the behaviour in `ayu/ayu_settings.cpp:227-354`. Holds how a captured
/// message screenshot is rendered (background, date, reactions, theme, …).
/// The boolean feature toggle is the separate [AppState.showMessageShot].
class MessageShotSettings {
  bool showBackground;
  bool showDate;
  bool showReactions;
  bool showHeaderDecorations;
  bool showColorfulReplies;
  bool revealSpoilers;

  /// -1 = no embedded theme. C++ uint32 accent color packed as ARGB.
  int embeddedThemeType;
  int embeddedThemeAccentColor;

  /// Cloud theme reference (C++ uint64 ids). 0/empty = no cloud theme.
  int cloudThemeId;
  int cloudThemeAccessHash;
  int cloudThemeDocumentId;
  String cloudThemeTitle;
  int cloudThemeAccountId;

  MessageShotSettings({
    this.showBackground = true,
    this.showDate = false,
    this.showReactions = false,
    this.showHeaderDecorations = true,
    this.showColorfulReplies = true,
    this.revealSpoilers = true,
    this.embeddedThemeType = -1,
    this.embeddedThemeAccentColor = 0,
    this.cloudThemeId = 0,
    this.cloudThemeAccessHash = 0,
    this.cloudThemeDocumentId = 0,
    this.cloudThemeTitle = '',
    this.cloudThemeAccountId = 0,
  });

  // ayu_settings.cpp:263-268
  bool get isCloudThemeEmpty =>
      cloudThemeId == 0 &&
      cloudThemeAccessHash == 0 &&
      cloudThemeDocumentId == 0 &&
      cloudThemeTitle.isEmpty;

  // ayu_settings.cpp:270-276
  void _clearCloudThemeData() {
    cloudThemeId = 0;
    cloudThemeAccessHash = 0;
    cloudThemeDocumentId = 0;
    cloudThemeTitle = '';
    cloudThemeAccountId = 0;
  }

  /// ayu_settings.cpp:278-288. Returns true if anything changed (caller saves).
  bool setEmbeddedTheme(int type, [int accentColor = 0]) {
    if (embeddedThemeType == type &&
        embeddedThemeAccentColor == accentColor &&
        isCloudThemeEmpty) {
      return false;
    }
    embeddedThemeType = type;
    embeddedThemeAccentColor = accentColor;
    _clearCloudThemeData();
    return true;
  }

  /// ayu_settings.cpp:290-308. Returns true if anything changed (caller saves).
  bool setCloudTheme(
    int accountId,
    int id,
    int accessHash,
    int documentId,
    String title,
  ) {
    if (embeddedThemeType == -1 &&
        embeddedThemeAccentColor == 0 &&
        cloudThemeAccountId == accountId &&
        cloudThemeId == id &&
        cloudThemeAccessHash == accessHash &&
        cloudThemeDocumentId == documentId &&
        cloudThemeTitle == title) {
      return false;
    }
    embeddedThemeType = -1;
    embeddedThemeAccentColor = 0;
    cloudThemeAccountId = accountId;
    cloudThemeId = id;
    cloudThemeAccessHash = accessHash;
    cloudThemeDocumentId = documentId;
    cloudThemeTitle = title;
    return true;
  }

  /// ayu_settings.cpp:310-320. Returns true if anything changed (caller saves).
  bool clearTheme() {
    if (embeddedThemeType == -1 &&
        embeddedThemeAccentColor == 0 &&
        isCloudThemeEmpty) {
      return false;
    }
    embeddedThemeType = -1;
    embeddedThemeAccentColor = 0;
    _clearCloudThemeData();
    return true;
  }

  void copyFrom(MessageShotSettings src) {
    showBackground = src.showBackground;
    showDate = src.showDate;
    showReactions = src.showReactions;
    showHeaderDecorations = src.showHeaderDecorations;
    showColorfulReplies = src.showColorfulReplies;
    revealSpoilers = src.revealSpoilers;
    embeddedThemeType = src.embeddedThemeType;
    embeddedThemeAccentColor = src.embeddedThemeAccentColor;
    cloudThemeId = src.cloudThemeId;
    cloudThemeAccessHash = src.cloudThemeAccessHash;
    cloudThemeDocumentId = src.cloudThemeDocumentId;
    cloudThemeTitle = src.cloudThemeTitle;
    cloudThemeAccountId = src.cloudThemeAccountId;
  }

  // ayu_settings.cpp:340-354 (from_json). embeddedTheme* fall back to the
  // legacy "themeType"/"themeAccentColor" keys, matching the C++ migration.
  factory MessageShotSettings.fromJson(Map<String, dynamic> j) =>
      MessageShotSettings(
        showBackground: j['showBackground'] as bool? ?? true,
        showDate: j['showDate'] as bool? ?? false,
        showReactions: j['showReactions'] as bool? ?? false,
        showHeaderDecorations: j['showHeaderDecorations'] as bool? ?? true,
        showColorfulReplies: j['showColorfulReplies'] as bool? ?? true,
        revealSpoilers: j['revealSpoilers'] as bool? ?? true,
        embeddedThemeType:
            j['embeddedThemeType'] as int? ?? j['themeType'] as int? ?? -1,
        embeddedThemeAccentColor: j['embeddedThemeAccentColor'] as int? ??
            j['themeAccentColor'] as int? ??
            0,
        cloudThemeId: j['cloudThemeId'] as int? ?? 0,
        cloudThemeAccessHash: j['cloudThemeAccessHash'] as int? ?? 0,
        cloudThemeDocumentId: j['cloudThemeDocumentId'] as int? ?? 0,
        cloudThemeTitle: j['cloudThemeTitle'] as String? ?? '',
        cloudThemeAccountId: j['cloudThemeAccountId'] as int? ?? 0,
      );

  // ayu_settings.cpp:322-338 (to_json).
  Map<String, dynamic> toJson() => {
        'showBackground': showBackground,
        'showDate': showDate,
        'showReactions': showReactions,
        'showHeaderDecorations': showHeaderDecorations,
        'showColorfulReplies': showColorfulReplies,
        'revealSpoilers': revealSpoilers,
        'embeddedThemeType': embeddedThemeType,
        'embeddedThemeAccentColor': embeddedThemeAccentColor,
        'cloudThemeId': cloudThemeId,
        'cloudThemeAccessHash': cloudThemeAccessHash,
        'cloudThemeDocumentId': cloudThemeDocumentId,
        'cloudThemeTitle': cloudThemeTitle,
        'cloudThemeAccountId': cloudThemeAccountId,
      };
}

/// Top-level app state: accounts, connection, config, active platform.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final EngineService _engine;

  EngineService get engine => _engine;

  static bool noHwAccelVideo = false;

  /// Spec §3.2: max accounts 100 (AyuGram), 200 for premium.
  static const kMaxAccounts = 100;
  static const kPremiumMaxAccounts = 200;

  List<AccountInfo> _accounts = [];
  Map<String, AccountInfo> _accountById = {};
  AccountInfo? _cachedActiveAccount;
  final Map<String, ConnState> _connStates = {};
  final Map<String, int> _connWaitSeconds = {};
  String _activeAccountId = ''; // currently viewed account (always set when accounts exist)
  AppConfig _config = AppConfig.defaults();
  bool _initialized = false;
  String? _initError;

  String _configDir = '';
  bool _passcodeLocked = false;
  // AyuGram's Core::App().domain().started(): false during the cold-start lock
  // that protects local storage before login, true once the first unlock (or a
  // no-passcode startup) has loaded accounts. Drives which system-unlock affordance
  // the lock screen shows — the active IconButton when started, the "enter your
  // passcode first" info label when not. ← window_lock_widgets.cpp:123-128.
  bool _domainStarted = false;
  int _passcodeBadTries = 0;
  DateTime? _passcodeLastTry;
  Timer? _autoLockTimer;
  int _shouldLockAt = 0; // millisecondsSinceEpoch when lock should trigger
  int _lastNonIdleTime = 0; // millisecondsSinceEpoch of last user interaction
  bool? _cachedHasPasscode;
  int? _cachedAutoLockSeconds;
  bool _nativeWindowFrame = false;
  bool _mainMenuAccountsShown = false;
  bool _systemDarkMode = false;
  bool _showChatNameInTitle = true;
  bool _showAccountNameInTitle = true;
  bool _showUnreadCountInTitle = true;
  int _windowCloseBehavior = 0; // 0=Quit, 1=Close to Taskbar, 2=Run in Background
  bool _showTrayIcon = true;
  bool _showTaskbarIcon = true;
  bool _monochromeTrayIcon = false;
  bool _launchAtStartup = false;
  bool _startMinimized = false;
  bool _hardwareAccelVideo = true;
  bool _openGlDisabled = false;
  int _angleBackendIndex = 0; // 0=Auto, 1=D3D11, 2=D3D9, 3=D3D11on12, 4=Disabled
  bool _addToSendToMenu = false; // Windows only
  bool _warnBeforeQuit = false; // macOS only
  bool _systemTextReplacements = false; // macOS only
  bool _roundDockIcon = false; // macOS only
  bool _spellcheckerEnabled = true;
  bool _spellcheckerAutoDownload = true;
  Set<String> _enabledDictionaries = {};
  bool _screenReaderModeDisabled = false;
  bool _autoUpdateEnabled = true;
  bool _installBetaVersions = false;
  int _downloadPathMode = 0; // 0=default, 1=temp, 2=custom
  String _customDownloadPath = '';
  bool _askDownloadPath = false;
  Set<String> _noWarningExtensions = {};
  int _proxyMode = 0; // 0=disabled, 1=system, 2=custom
  String _selectedProxyType = ''; // e.g. 'SOCKS5', 'HTTP', 'MTPROTO'
  bool _proxyIpv6 = false;
  bool _proxyForCalls = false;
  bool _callSameDevice = false;
  bool _proxyRotationEnabled = false;
  // AyuGram/Telegram-core default is 10s (core_settings_proxy.h:25
  // kDefaultProxyRotationTimeout = 10). 60 is the MAX of {5,10,15,30,60}.
  int _proxyRotationTimeout = 10;
  // One-time "this will expose your IP to the proxy admin" acknowledgement,
  // persisted so the connectivity check warns only once (AyuGram
  // checkIpWarningShown(), connection_box.cpp:1824-1842).
  bool _proxyCheckIpWarningShown = false;
  List<Map<String, dynamic>> _proxyList = [];
  Map<String, dynamic> _selectedProxyData = {};
  Map<String, Map<String, dynamic>> _autoDownloadSettings = {};
  String _cacheDir = '';
  int _localStorageTotalLimit = 8192; // MB
  int _localStorageMediaLimit = 4096; // MB
  int _localStorageTimeLimit = 15; // index into time labels
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

  /// Accounts whose main-menu bots have been fetched at least once this session
  /// (success — even an empty result counts), and those with a fetch in flight.
  /// Lets [ensureMenuBotsLoaded] dedupe without re-hitting the network on every
  /// drawer/settings rebuild, while still retrying when the account wasn't
  /// connected yet (those fetches return null and are NOT marked loaded).
  final Set<String> _menuBotsLoaded = {};
  final Set<String> _menuBotsLoading = {};

  /// Spec §2.7: Configurable swipe action for chat list rows.
  /// Values: "mute", "pin", "read", "archive", "delete". Default: "archive".
  String _swipeAction = 'archive';

  /// Spec §24.6: Submit mode for compose field. Values: "enter", "ctrl_enter".
  String _sendBy = 'enter';

  bool? _rememberedSendAsDocuments;
  bool? _rememberedGroupFiles;

  bool _rememberedSoundNotifyFromTray = false;
  bool _rememberedFlashBounceNotifyFromTray = false;

  List<String> _recentHashtags = [];

  /// Spec §7.3: When true, empty-field send button shows Round (camera) instead of Record (mic).
  bool _recordVideoMessages = false;

  // Spec §25.15: AyuGram-specific theming preferences.
  int _bubbleRadius = 16; // 0-16, default matches _radiusLarge
  bool _removeTail = false;
  bool _materialSwitches = true;
  int _avatarCorners = 23; // 0-23 (kMaxAvatarCorners), 23=circle (default)
  bool _singleCornerRadius = false;
  bool _disableCustomBackgrounds = false;
  bool _hidePremiumStatuses = false;
  String _monoFont = '';
  bool _hideNotificationCounters = false;
  bool _hideAllChatsFolder = false;
  bool _hideNotificationBadge = false;
  int _photoEditorHintCount = 0;

  // §15: Transient — true while the notification-position sample is on screen
  // (settings monitor preview). NOT persisted. Drives the custom-popup overlay's
  // demo master opacity so live notifications dim while the sample is shown.
  bool _notifDemoShown = false;

  // §15: Notification settings persistence
  bool _notifDesktopNotify = true;
  bool _notifFlashBounce = true;
  bool _notifAllowSound = true;
  int _notifVolume = 100;
  // Per-chat & per-notify-type ringtone VOLUME overrides (0 = no override).
  // Mirrors AyuGram's local SessionSettings._ringtoneVolumes map keyed by thread
  // (main_session_settings.cpp:950-984): the notification sound resolves
  // per-chat → per-default-type → global, a 2-tier hierarchy applied in
  // ringtoneVolume() below. Both are persisted locally in window prefs (the
  // per-type tier is also pushed to the engine for parity with the settings UI).
  final Map<String, int> _ringtoneVolumes = {}; // key "accountId:chatId"
  final Map<String, int> _notifTypeVolumes = {}; // key "accountId:type" (private/group/channel)
  // Last-used mute durations (seconds), most-recent kept sorted ascending and
  // capped at 2 — mirrors AyuGram SessionSettings::mutePeriods()/addMutePeriod()
  // (main_session_settings.cpp:934-948). The mute menu renders one quick item per
  // entry; the list starts empty (no defaults).
  final List<int> _mutePeriods = [];
  // Per-chat custom notification SOUND override (AyuGram notifySettings().sound(thread),
  // notifications_manager.cpp:763,1006-1028). Set via the per-chat ringtone picker.
  // _chatSoundDocId: -2 = "None"/silent, >0 = custom ringtone (file path captured in
  // _chatSoundPath at pick time). Default (0/-1) = no override. Persisted locally.
  final Map<String, int> _chatSoundDocId = {}; // key "accountId:chatId" → sound document id
  final Map<String, String> _chatSoundPath = {}; // key "accountId:chatId" → local ringtone file path
  bool _notifPreviewName = true;
  bool _notifPreviewText = true;
  bool _notifPrivateChats = true;
  bool _notifGroups = true;
  bool _notifChannels = true;
  bool _notifReactions = true;
  bool _notifUseNative = true;
  bool _notifSkipToastsInFocus = false;
  int _notifDisplayIndex = 0;
  int _notifCorner = 2; // 0=topLeft,1=topRight,2=bottomRight,3=bottomLeft,4=topCenter
  int _notifCount = 3;
  bool _notifContactJoinedTelegram = true;
  bool _notifPinnedMessages = true;
  bool _notifAcceptCallsOnDevice = true;
  String _callOutputDevice = 'Default';
  String _callInputDevice = 'Default';
  String _callCameraDevice = 'Default';
  bool _callUseSameDevices = true;
  String _callSpecificOutputDevice = '';
  String _callSpecificInputDevice = '';
  bool _callNoiseSuppression = true;
  bool _callPushToTalk = false;
  String _callPttShortcut = 'Space';
  int _callPttDelay = 200; // ms — release delay after the PTT key is let go
  bool _notifAllAccountsNotify = true;
  bool _notifIncludeMutedChats = true;
  bool _notifIncludeMutedInFolders = true;
  bool _notifCountUnreadMessages = true;

  // §14.6: Chat appearance settings persistence
  bool _chatLargeEmoji = true;
  bool _chatReplaceEmojis = true;
  bool _chatSuggestEmoji = true;
  bool _chatSuggestAnimatedEmoji = true;
  bool _chatSuggestStickersByEmoji = true;
  bool _chatLoopAnimatedStickers = true;
  String _chatDoubleClickAction = 'reply';
  String _chatDoubleClickReaction = '❤️';
  bool _chatShowReplyButton = true;
  bool _chatShowReactionButton = true;
  // Emoji rendering set (AyuGram Ui::Emoji::ManageSetsBox). 'system' = the
  // platform's native color-emoji font; 'twemoji' = the bundled Twemoji set.
  String _emojiSet = 'system';
  bool _useSystemAccent = false;
  bool _adaptiveForWide = true;
  String _customFontFamily = 'Inter';
  String _appIcon = '';
  String _customDeviceModel = '';
  bool _replaceBottomInfoWithIcons = true;
  bool _adaptiveCoverColor = true;
  bool _simpleQuotesAndReplies = false;
  bool _semiTransparentDeleted = false;
  double _wideMultiplier = 1.0; // §54.3: 0.50–4.00 in 0.05 steps
  double _uiScalePercent = 100.0; // §14.4 / §57: Interface scale, 100–300%
  double _ivZoom = 1.0;
  bool _showNightModeToggleInDrawer = true;

  // §54.8: Per-item drawer visibility toggles (all default true).
  bool _showMyProfileInDrawer = true;
  bool _showBotsInDrawer = true;
  bool _showNewGroupInDrawer = true;
  bool _showNewChannelInDrawer = true;
  bool _showContactsInDrawer = true;
  bool _showCallsInDrawer = true;
  bool _showSavedMessagesInDrawer = true;

  bool _archiveInMainMenu = false;
  bool _archiveCollapsed = false;

  // §50.2: Streamer Mode — global, non-persistent (OFF on every cold launch).
  bool _streamerModeEnabled = false;
  final StreamController<bool> _streamerModeController = StreamController<bool>.broadcast();
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
  int _showViewsPanelInContextMenu = 1; // 0=hidden, 1=visible, 2=visibleWithModifier
  int _showRepeatMessageInContextMenu = 0; // 0=hidden, 1=visible, 2=visibleWithModifier (default: hidden per §53.3)
  int _showReactionsPanelInContextMenu = 1;
  int _showHideMessageInContextMenu = 0;
  int _showUserMessagesInContextMenu = 2;
  int _showMessageDetailsInContextMenu = 2;
  int _showAddFilterInContextMenu = 1;
  bool _showMessageSeconds = false;

  // Media player playback settings (mirror AyuGram core_settings.h:
  // voicePlaybackSpeed/audioPlaybackSpeed + playerRepeatMode, and the
  // OptionDisableAutoplayNext toggle). Speeds default to 1.0 (normal speed);
  // repeat 0=none. Consumed by AudioService via main.dart sync.
  double _voicePlaybackSpeed = 1.0; // voice & video messages
  double _audioPlaybackSpeed = 1.0; // music tracks
  int _playerRepeatMode = 0; // 0=none, 1=one, 2=all
  int _playerOrderMode = 0; // 0=default, 1=reverse, 2=shuffle
  bool _disableAutoplayNext = false;
  // Song playback volume 0..1 and the last non-zero value, mirroring AyuGram
  // core_settings songVolume / rememberedSongVolume (core_settings.h:172,632;
  // default kDefaultVolume = 0.9, core_settings.h:123). The volume toggle mutes
  // to 0 and restores to rememberedSongVolume; the slider updates both.
  double _songVolume = 0.9;
  double _rememberedSongVolume = 0.9;
  // Video playback volume 0..1, mirroring AyuGram core_settings videoVolume
  // (declared core_settings.h:1077, serialized core_settings.cpp:284, restored
  // :975; default kDefaultVolume = 0.9). Unlike song volume there is no
  // "remembered" sibling — the media viewer holds the mute-restore value in a
  // transient local field (_lastPositiveVolume, media_view_overlay_widget.cpp:611).
  // Persisted globally so a user-set video volume survives viewer reopen / restart.
  double _videoVolume = 0.9;

  // §54.14: AyuGram General settings.
  int _translationProvider = 0; // 0=Telegram, 1=Google, 2=Yandex, 3=Native
  bool _disableStories = false;
  bool _disableOpenLinkWarning = false;
  bool _collapseSimilarChannels = true;
  bool _hideSimilarChannels = false;
  bool _disableNotifyDelay = false;
  bool _filterZalgo = false;
  bool _improveLinkPreviews = false;
  int _showPeerId = 2; // 0=Hide, 1=Telegram API, 2=Bot API
  bool _spoofWebviewAsAndroid = false;
  bool _increaseWebviewHeight = false;
  bool _increaseWebviewWidth = false;
  bool _stickerConfirmation = false;
  bool _gifConfirmation = false;
  bool _voiceConfirmation = false;

  bool _showIpInWebRtcCalls = false;

  // §54.11: Additional chat settings.
  bool _showOnlyAddedEmojisAndStickers = false;
  bool _showChannelReactions = true;
  bool _showGroupReactions = true;
  bool _showPrivateChatReactions = true;
  int _recentStickersCount = 100;
  int _channelBottomButton = 2; // 0=Hidden, 1=MuteUnmute, 2=DiscussWithFallback
  bool _quickAdminShortcuts = true;
  bool _showMessageShot = true;
  // AyuGram `_messageShotSettings` (ayu_settings.h:703) — render config for the
  // message-screenshot feature, distinct from the [_showMessageShot] toggle.
  MessageShotSettings _messageShotSettings = MessageShotSettings();
  bool _hideFastShare = false;

  // §54.9: Message field button toggles (all default true).
  bool _showAttachButton = true;
  bool _showCommandsButton = true;
  bool _showAutoDeleteButton = true;
  bool _showEmojiButton = true;
  bool _showMicrophoneButton = true;
  bool _showGiftButton = true;
  bool _showAiEditorButton = true;
  bool _showAttachPopup = true;
  bool _showEmojiPopup = true;

  // §51.4: Spy essentials + Other section settings.
  bool _saveDeletedMessages = true;
  bool _saveMessagesHistory = true;
  bool _saveForBots = false;
  String _deletedMark = '\u{1F9F9}'; // broom emoji
  String _editedMark = ''; // empty = Telegram default "edited"
  bool _replaceMarksWithIcons = true;
  bool _localPremium = false;
  bool _disableAds = true;

  // §54.16: AyuGram Filters settings.
  bool _filtersEnabled = false;
  bool _filtersEnabledInChats = false;
  bool _hideFromBlocked = false;
  Set<int> _shadowBanIds = {};
  Set<int> _blockedIds = {};
  final AyuFilterEngine filterEngine = AyuFilterEngine();

  // Delete dialog: remember "delete for everyone" choice (AyuGram: rememberedDeleteMessageOnlyForYou)
  bool _deleteOnlyForYouRemembered = false;

  // §54.15: Other settings.
  bool _crashReporting = true;

  // §50.7: Per-peer read exclusions. Key: "accountId:chatId", value: 0=default, 1=neverRead, 2=alwaysRead.
  Map<String, int> _readExclusions = {};
  // §50.9: Per-peer typing exclusions. Key: "accountId:chatId", value: 0=default, 1=neverType, 2=alwaysType.
  Map<String, int> _typingExclusions = {};

  // Spec §17.7.1: PowerSaving bitfield (matches tdesktop power_saving.h).
  static const kPowerSavingAnimations     = 1 << 0;
  static const kPowerSavingStickersPanel  = 1 << 1;
  static const kPowerSavingStickersChat   = 1 << 2;
  static const kPowerSavingEmojiPanel     = 1 << 3;
  static const kPowerSavingEmojiReactions = 1 << 4;
  static const kPowerSavingEmojiChat      = 1 << 5;
  static const kPowerSavingChatBackground = 1 << 6;
  static const kPowerSavingChatSpoiler    = 1 << 7;
  static const kPowerSavingCalls          = 1 << 8;
  static const kPowerSavingEmojiStatus    = 1 << 9;
  static const kPowerSavingChatEffects    = 1 << 10;
  static const kPowerSavingAll            = (1 << 11) - 1;
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

  /// Fired when an account is logged out / removed, so the notification system
  /// can drop all of that session's notifications, pending timers and per-thread
  /// state — otherwise already-scheduled dispatch timers fire after logout and
  /// surface stale data. Mirrors AyuGram clearing the session's notifications on
  /// Session::clear() (data/data_session.cpp:411, clearFromSession).
  void Function(String accountId)? onAccountRemoved;

  Timer? _cmdPollTimer;
  Timer? _saveDebounceTimer;

  /// File path for CLI automation: add accounts without GUI interaction.
  ///   {"action": "add", "platform": "irc"}
  static const cmdFilePath = '/tmp/uniclient_cmd.json';

  AppState(this._engine);

  void _rebuildAccountLookup() {
    _accountById = {for (final a in _accounts) a.id: a};
    _cachedActiveAccount = _accountById[_activeAccountId];
  }

  /// Self user id for [accountId], or '' if unknown. Lets the notification layer
  /// recognise this account's OWN status updates (which only arrive from another
  /// logged-in device) and feed them into the online-aware notification delay.
  String selfUserIdFor(String accountId) =>
      _accountById[accountId]?.selfUserId ?? '';

  /// Epoch-ms of the last local user interaction (the value AyuGram's online
  /// tracking is built on, Core::App().lastNonIdleTime()).
  int get lastNonIdleTime => _lastNonIdleTime;

  /// Whether THIS desktop session counts as "online" for notification timing —
  /// true while the user has interacted within the online window. Mirrors
  /// AyuGram deriving the session online state from lastNonIdleTime
  /// (api/api_updates.cpp updateOnline). Consumed by NotificationSystem's
  /// countTiming to decide whether to cloud-delay a notification.
  bool get isSessionOnline {
    if (_lastNonIdleTime <= 0) return true;
    return DateTime.now().millisecondsSinceEpoch - _lastNonIdleTime <
        _kOnlineWindowMs;
  }

  static const int _kOnlineWindowMs = 60 * 1000;

  // ── Getters ──

  List<AccountInfo> get accounts {
    if (_accountOrder.isEmpty) return _accounts;
    final ordered = <AccountInfo>[];
    for (final id in _accountOrder) {
      final a = _accountById[id];
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

  AccountInfo? get activeAccount => _cachedActiveAccount;

  /// Account limit — each premium account raises the cap by exactly 1, capped
  /// at kPremiumMaxAccounts. Matches AyuGram Domain::maxAccounts() =
  /// min(premiumCount + kMaxAccounts, kPremiumMaxAccounts) (main_domain.cpp:503).
  int get maxAccountLimit {
    final premiumCount = _accounts.where((a) => a.isPremium).length;
    return (premiumCount + kMaxAccounts).clamp(kMaxAccounts, kPremiumMaxAccounts);
  }

  /// Whether a new account can be added (under the limit).
  bool get canAddAccount => _accounts.length < maxAccountLimit;

  bool get passcodeLocked => _passcodeLocked;
  bool get domainStarted => _domainStarted;
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
  int get angleBackendIndex => _angleBackendIndex;
  bool get addToSendToMenu => _addToSendToMenu;
  bool get warnBeforeQuit => _warnBeforeQuit;
  bool get systemTextReplacements => _systemTextReplacements;
  bool get roundDockIcon => _roundDockIcon;
  bool get spellcheckerEnabled => _spellcheckerEnabled;
  bool get spellcheckerAutoDownload => _spellcheckerAutoDownload;
  Set<String> get enabledDictionaries => Set.unmodifiable(_enabledDictionaries);
  bool get screenReaderModeDisabled => _screenReaderModeDisabled;
  bool get autoUpdateEnabled => _autoUpdateEnabled;
  bool get installBetaVersions => _installBetaVersions;
  int get downloadPathMode => _downloadPathMode;
  String get customDownloadPath => _customDownloadPath;
  bool get askDownloadPath => _askDownloadPath;
  Set<String> get noWarningExtensions => Set.unmodifiable(_noWarningExtensions);
  int get proxyMode => _proxyMode;
  String get selectedProxyType => _selectedProxyType;
  bool get proxyIpv6 => _proxyIpv6;
  bool get proxyForCalls => _proxyForCalls;
  bool get callSameDevice => _callSameDevice;
  bool get proxyRotationEnabled => _proxyRotationEnabled;
  int get proxyRotationTimeout => _proxyRotationTimeout;
  bool get proxyCheckIpWarningShown => _proxyCheckIpWarningShown;
  List<Map<String, dynamic>> get proxyList => List.unmodifiable(_proxyList);
  Map<String, Map<String, dynamic>> get autoDownloadSettings => Map.unmodifiable(_autoDownloadSettings);
  String get cacheDir => _cacheDir;
  int get localStorageTotalLimit => _localStorageTotalLimit;
  int get localStorageMediaLimit => _localStorageMediaLimit;
  int get localStorageTimeLimit => _localStorageTimeLimit;
  List<Map<String, dynamic>> get recentDownloads => List.unmodifiable(_recentDownloads);

  // §25.15 AyuGram getters
  int get bubbleRadius => _bubbleRadius;
  bool get removeTail => _removeTail;
  bool get materialSwitches => _materialSwitches;
  int get avatarCorners => _avatarCorners;
  bool get singleCornerRadius => _singleCornerRadius;
  bool get disableCustomBackgrounds => _disableCustomBackgrounds;
  bool get hidePremiumStatuses => _hidePremiumStatuses;
  String get monoFont => _monoFont;
  bool get hideNotificationCounters => _hideNotificationCounters;
  bool get hideAllChatsFolder => _hideAllChatsFolder;
  bool get hideNotificationBadge => _hideNotificationBadge;
  int get photoEditorHintCount => _photoEditorHintCount;
  bool get notifContactJoinedTelegram => _notifContactJoinedTelegram;
  bool get notifPinnedMessages => _notifPinnedMessages;
  bool get notifAcceptCallsOnDevice => _notifAcceptCallsOnDevice;
  String get callOutputDevice => _callOutputDevice;
  String get callInputDevice => _callInputDevice;
  String get callCameraDevice => _callCameraDevice;
  bool get callUseSameDevices => _callUseSameDevices;
  String get callSpecificOutputDevice => _callSpecificOutputDevice;
  String get callSpecificInputDevice => _callSpecificInputDevice;
  bool get callNoiseSuppression => _callNoiseSuppression;
  bool get callPushToTalk => _callPushToTalk;
  String get callPttShortcut => _callPttShortcut;
  int get callPttDelay => _callPttDelay;
  bool get notifAllAccountsNotify => _notifAllAccountsNotify;
  bool get notifIncludeMutedChats => _notifIncludeMutedChats;
  bool get notifIncludeMutedInFolders => _notifIncludeMutedInFolders;
  bool get notifCountUnreadMessages => _notifCountUnreadMessages;
  String get appIcon => _appIcon;
  bool get replaceBottomInfoWithIcons => _replaceBottomInfoWithIcons;
  bool get adaptiveCoverColor => _adaptiveCoverColor;
  bool get simpleQuotesAndReplies => _simpleQuotesAndReplies;
  bool get semiTransparentDeleted => _semiTransparentDeleted;
  double get wideMultiplier => _wideMultiplier;
  double get uiScalePercent => _uiScalePercent;
  double get uiScaleFactor => _uiScalePercent / 100.0;
  double get ivZoom => _ivZoom;
  bool get showNightModeToggleInDrawer => _showNightModeToggleInDrawer;

  // §54.8: Per-item drawer visibility getters.
  bool get showMyProfileInDrawer => _showMyProfileInDrawer;
  bool get showBotsInDrawer => _showBotsInDrawer;
  bool get showNewGroupInDrawer => _showNewGroupInDrawer;
  bool get showNewChannelInDrawer => _showNewChannelInDrawer;
  bool get showContactsInDrawer => _showContactsInDrawer;
  bool get showCallsInDrawer => _showCallsInDrawer;
  bool get showSavedMessagesInDrawer => _showSavedMessagesInDrawer;

  bool get archiveInMainMenu => _archiveInMainMenu;
  void setArchiveInMainMenu(bool v) {
    if (_archiveInMainMenu == v) return;
    _archiveInMainMenu = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  bool get archiveCollapsed => _archiveCollapsed;
  void setArchiveCollapsed(bool v) {
    if (_archiveCollapsed == v) return;
    _archiveCollapsed = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  // §50.2 Streamer Mode getters
  bool get streamerModeEnabled => _streamerModeEnabled;
  Stream<bool> get streamerModeStream => _streamerModeController.stream;
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

  String resolveGhostKey(String? selectedUserId) {
    if (_useGlobalGhostMode) return '0';
    final key = selectedUserId ?? activeAccount?.selfUserId ?? '0';
    return key.isEmpty ? '0' : key;
  }

  GhostModeAccountSettings ensureGhostForKey(String key) {
    return _ghostModeSettings.putIfAbsent(key, GhostModeAccountSettings.new);
  }

  void ghostSettingChanged(String key) {
    // Global mode: only the shared '0' profile reaches the engine. Per-account
    // mode: ANY account's change must be re-pushed, since each connected
    // account carries its own override (not just the active one).
    if (!_useGlobalGhostMode || key == _ghostKey) _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void copyGhostToGlobal(String fromKey) {
    final src = _ghostModeSettings[fromKey];
    if (src == null) return;
    final dst = _ghostModeSettings.putIfAbsent('0', GhostModeAccountSettings.new);
    dst.copyFrom(src);
  }

  void setGhostModeEnabledForKey(String key, bool v) {
    final s = _ghostModeSettings.putIfAbsent(key, GhostModeAccountSettings.new);
    bool changed = false;
    if (v) {
      if (!s.sendReadMessagesLocked && s.sendReadMessages) { s.sendReadMessages = false; changed = true; }
      if (!s.sendReadStoriesLocked && s.sendReadStories) { s.sendReadStories = false; changed = true; }
      if (!s.sendOnlinePacketsLocked && s.sendOnlinePackets) { s.sendOnlinePackets = false; changed = true; }
      if (!s.sendUploadProgressLocked && s.sendUploadProgress) { s.sendUploadProgress = false; changed = true; }
      if (!s.sendOfflinePacketAfterOnlineLocked && !s.sendOfflinePacketAfterOnline) { s.sendOfflinePacketAfterOnline = true; changed = true; }
    } else {
      if (!s.sendReadMessagesLocked && !s.sendReadMessages) { s.sendReadMessages = true; changed = true; }
      if (!s.sendReadStoriesLocked && !s.sendReadStories) { s.sendReadStories = true; changed = true; }
      if (!s.sendOnlinePacketsLocked && !s.sendOnlinePackets) { s.sendOnlinePackets = true; changed = true; }
      if (!s.sendUploadProgressLocked && !s.sendUploadProgress) { s.sendUploadProgress = true; changed = true; }
      if (!s.sendOfflinePacketAfterOnlineLocked && s.sendOfflinePacketAfterOnline) { s.sendOfflinePacketAfterOnline = false; changed = true; }
    }
    if (v && key == _ghostKey && changed) _engine.markAsOnline();
    ghostSettingChanged(key);
  }

  // The 5 lockable ghost toggles (matches the 5 rows in ghost_settings_page).
  static const _ghostLockFields = <String>{
    'sendReadMessages',
    'sendReadStories',
    'sendOnlinePackets',
    'sendUploadProgress',
    'sendOfflinePacketAfterOnline',
  };

  void toggleLockForKey(String key, String field) {
    if (!_ghostLockFields.contains(field)) return;
    final s = _ghostModeSettings.putIfAbsent(key, GhostModeAccountSettings.new);
    final isCurrentlyLocked = switch (field) {
      'sendReadMessages' => s.sendReadMessagesLocked,
      'sendReadStories' => s.sendReadStoriesLocked,
      'sendOnlinePackets' => s.sendOnlinePacketsLocked,
      'sendUploadProgress' => s.sendUploadProgressLocked,
      'sendOfflinePacketAfterOnline' => s.sendOfflinePacketAfterOnlineLocked,
      _ => false,
    };
    // AyuGram denies a lock that would leave zero unlocked toggles —
    // settings_ayu_utils.cpp:386-396 (`if (lockedCount + 1 >= checkboxes.size()) return;`).
    // This keeps the master Ghost Mode switch meaningful (never all-locked).
    if (!isCurrentlyLocked) {
      final lockedCount = [
        s.sendReadMessagesLocked,
        s.sendReadStoriesLocked,
        s.sendOnlinePacketsLocked,
        s.sendUploadProgressLocked,
        s.sendOfflinePacketAfterOnlineLocked,
      ].where((l) => l).length;
      if (lockedCount + 1 >= _ghostLockFields.length) return;
    }
    switch (field) {
      case 'sendReadMessages': s.sendReadMessagesLocked = !s.sendReadMessagesLocked;
      case 'sendReadStories': s.sendReadStoriesLocked = !s.sendReadStoriesLocked;
      case 'sendOnlinePackets': s.sendOnlinePacketsLocked = !s.sendOnlinePacketsLocked;
      case 'sendUploadProgress': s.sendUploadProgressLocked = !s.sendUploadProgressLocked;
      case 'sendOfflinePacketAfterOnline': s.sendOfflinePacketAfterOnlineLocked = !s.sendOfflinePacketAfterOnlineLocked;
    }
    notifyListeners();
    _saveWindowPrefs();
  }
  bool get ghostModeEnabled => _ghostSettings.ghostModeActive;
  bool get sendReadMessages => _ghostSettings.sendReadMessages;
  bool get sendReadStories => _ghostSettings.sendReadStories;
  bool get sendOnlinePackets => _ghostSettings.sendOnlinePackets;
  bool get sendUploadProgress => _ghostSettings.sendUploadProgress;
  bool get sendOfflinePacketAfterOnline => _ghostSettings.sendOfflinePacketAfterOnline;
  bool get markReadAfterAction => _ghostSettings.markReadAfterAction;
  bool get useScheduledMessages => _ghostSettings.useScheduledMessages;
  int get sendWithoutSound => _ghostSettings.sendWithoutSound;
  bool get shouldSendWithoutSound => _ghostSettings.shouldSendWithoutSound;
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

  // Media player playback settings.
  double get voicePlaybackSpeed => _voicePlaybackSpeed;
  double get audioPlaybackSpeed => _audioPlaybackSpeed;
  int get playerRepeatMode => _playerRepeatMode;
  int get playerOrderMode => _playerOrderMode;
  bool get disableAutoplayNext => _disableAutoplayNext;
  double get songVolume => _songVolume;
  double get rememberedSongVolume => _rememberedSongVolume;
  double get videoVolume => _videoVolume;

  // §54.14: AyuGram General settings getters.
  int get translationProvider => _translationProvider;
  bool get disableStories => _disableStories;
  bool get disableOpenLinkWarning => _disableOpenLinkWarning;
  bool get collapseSimilarChannels => _collapseSimilarChannels;
  bool get hideSimilarChannels => _hideSimilarChannels;
  bool get disableNotifyDelay => _disableNotifyDelay;
  bool get filterZalgo => _filterZalgo;
  bool get improveLinkPreviews => _improveLinkPreviews;
  int get showPeerId => _showPeerId;
  bool get spoofWebviewAsAndroid => _spoofWebviewAsAndroid;
  bool get increaseWebviewHeight => _increaseWebviewHeight;
  bool get increaseWebviewWidth => _increaseWebviewWidth;
  bool get stickerConfirmation => _stickerConfirmation;
  bool get gifConfirmation => _gifConfirmation;
  bool get voiceConfirmation => _voiceConfirmation;

  bool get showIpInWebRtcCalls => _showIpInWebRtcCalls;

  // §54.9: Message field button toggle getters.
  bool get showAttachButton => _showAttachButton;
  bool get showCommandsButton => _showCommandsButton;
  bool get showAutoDeleteButton => _showAutoDeleteButton;
  bool get showEmojiButton => _showEmojiButton;
  bool get showMicrophoneButton => _showMicrophoneButton;
  bool get showGiftButton => _showGiftButton;
  bool get showAiEditorButton => _showAiEditorButton;
  bool get showAttachPopup => _showAttachPopup;
  bool get showEmojiPopup => _showEmojiPopup;

  // §54.11: Additional chat settings getters.
  bool get showOnlyAddedEmojisAndStickers => _showOnlyAddedEmojisAndStickers;
  bool get showChannelReactions => _showChannelReactions;
  bool get showGroupReactions => _showGroupReactions;
  bool get showPrivateChatReactions => _showPrivateChatReactions;
  int get recentStickersCount => _recentStickersCount;
  int get channelBottomButton => _channelBottomButton;
  bool get quickAdminShortcuts => _quickAdminShortcuts;
  bool get showMessageShot => _showMessageShot;
  bool get hideFastShare => _hideFastShare;

  bool get saveDeletedMessages => _saveDeletedMessages;
  bool get saveMessagesHistory => _saveMessagesHistory;
  bool get saveForBots => _saveForBots;
  String get deletedMark => _deletedMark;
  String get editedMark => _editedMark;
  bool get replaceMarksWithIcons => _replaceMarksWithIcons;
  bool get localPremium => _localPremium;
  bool get effectivePremium => (activeAccount?.isPremium ?? false) || _localPremium;
  bool get disableAds => _disableAds;
  bool get shouldSuppressSponsoredContent => _disableAds;
  bool get crashReporting => _crashReporting;

  // §54.16: AyuGram Filters settings getters.
  bool get filtersEnabled => _filtersEnabled;
  bool get filtersEnabledInChats => _filtersEnabledInChats;
  bool get hideFromBlocked => _hideFromBlocked;
  Set<int> get shadowBanIds => _shadowBanIds;

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

  void setHidePremiumStatuses(bool v) {
    if (_hidePremiumStatuses == v) return;
    _hidePremiumStatuses = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setMonoFont(String v) {
    if (_monoFont == v) return;
    _monoFont = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setHideNotificationCounters(bool v) {
    if (_hideNotificationCounters == v) return;
    _hideNotificationCounters = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setHideAllChatsFolder(bool v) {
    if (_hideAllChatsFolder == v) return;
    _hideAllChatsFolder = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setHideNotificationBadge(bool v) {
    if (_hideNotificationBadge == v) return;
    _hideNotificationBadge = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void incrementPhotoEditorHintCount() {
    _photoEditorHintCount++;
    _saveWindowPrefs();
  }

  void setNotifContactJoinedTelegram(bool v) {
    if (_notifContactJoinedTelegram == v) return;
    _notifContactJoinedTelegram = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setNotifPinnedMessages(bool v) {
    if (_notifPinnedMessages == v) return;
    _notifPinnedMessages = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setNotifAcceptCallsOnDevice(bool v) {
    if (_notifAcceptCallsOnDevice == v) return;
    _notifAcceptCallsOnDevice = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setNotifAllAccountsNotify(bool v) {
    if (_notifAllAccountsNotify == v) return;
    _notifAllAccountsNotify = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setCallOutputDevice(String v) {
    if (_callOutputDevice == v) return;
    _callOutputDevice = v;
    notifyListeners();
    _saveWindowPrefs();
    _engine.setCallAudioDevice(_activeAccountId, 'output', v);
  }

  void setCallInputDevice(String v) {
    if (_callInputDevice == v) return;
    _callInputDevice = v;
    notifyListeners();
    _saveWindowPrefs();
    _engine.setCallAudioDevice(_activeAccountId, 'input', v);
  }

  void setCallCameraDevice(String v) {
    if (_callCameraDevice == v) return;
    _callCameraDevice = v;
    notifyListeners();
    _saveWindowPrefs();
    _engine.setCallAudioDevice(_activeAccountId, 'camera', v);
  }

  void setCallUseSameDevices(bool v) {
    if (_callUseSameDevices == v) return;
    _callUseSameDevices = v;
    if (v) {
      _callSpecificOutputDevice = '';
      _callSpecificInputDevice = '';
    } else {
      _callSpecificOutputDevice =
          _callOutputDevice.isEmpty ? 'Default' : _callOutputDevice;
      _callSpecificInputDevice =
          _callInputDevice.isEmpty ? 'Default' : _callInputDevice;
    }
    notifyListeners();
    _saveWindowPrefs();
    _engine.setCallAudioDevice(
        _activeAccountId, 'call_output', _callSpecificOutputDevice);
    _engine.setCallAudioDevice(
        _activeAccountId, 'call_input', _callSpecificInputDevice);
  }

  void setCallSpecificOutputDevice(String v) {
    if (_callSpecificOutputDevice == v) return;
    _callSpecificOutputDevice = v;
    notifyListeners();
    _saveWindowPrefs();
    _engine.setCallAudioDevice(_activeAccountId, 'call_output', v);
  }

  void setCallSpecificInputDevice(String v) {
    if (_callSpecificInputDevice == v) return;
    _callSpecificInputDevice = v;
    notifyListeners();
    _saveWindowPrefs();
    _engine.setCallAudioDevice(_activeAccountId, 'call_input', v);
  }

  void setCallNoiseSuppression(bool v) {
    if (_callNoiseSuppression == v) return;
    _callNoiseSuppression = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setCallPushToTalk(bool v) {
    if (_callPushToTalk == v) return;
    _callPushToTalk = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setCallPttShortcut(String v) {
    if (_callPttShortcut == v) return;
    _callPttShortcut = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setCallPttDelay(int v) {
    if (_callPttDelay == v) return;
    _callPttDelay = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setNotifIncludeMutedChats(bool v) {
    if (_notifIncludeMutedChats == v) return;
    _notifIncludeMutedChats = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setNotifIncludeMutedInFolders(bool v) {
    if (_notifIncludeMutedInFolders == v) return;
    _notifIncludeMutedInFolders = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setNotifCountUnreadMessages(bool v) {
    if (_notifCountUnreadMessages == v) return;
    _notifCountUnreadMessages = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setAppIcon(String v) {
    if (_appIcon == v) return;
    _appIcon = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setReplaceBottomInfoWithIcons(bool v) {
    if (_replaceBottomInfoWithIcons == v) return;
    _replaceBottomInfoWithIcons = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setAdaptiveCoverColor(bool v) {
    if (_adaptiveCoverColor == v) return;
    _adaptiveCoverColor = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSimpleQuotesAndReplies(bool v) {
    if (_simpleQuotesAndReplies == v) return;
    _simpleQuotesAndReplies = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setWideMultiplier(double v) {
    v = (v * 20).round() / 20.0; // snap to 0.05 increments
    v = v.clamp(0.5, 4.0);
    if ((_wideMultiplier - v).abs() < 0.001) return;
    _wideMultiplier = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setUiScalePercent(double v) {
    v = (v / 5).round() * 5.0;
    v = v.clamp(100.0, 300.0);
    if ((_uiScalePercent - v).abs() < 0.01) return;
    _uiScalePercent = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setIvZoom(double v) {
    v = v.clamp(1.0, 3.0);
    if ((_ivZoom - v).abs() < 0.01) return;
    _ivZoom = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSemiTransparentDeleted(bool v) {
    if (_semiTransparentDeleted == v) return;
    _semiTransparentDeleted = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowNightModeToggleInDrawer(bool v) {
    if (_showNightModeToggleInDrawer == v) return;
    _showNightModeToggleInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  // §50.2 Streamer Mode setters
  void setStreamerModeEnabled(bool v) {
    if (_streamerModeEnabled == v) return;
    _streamerModeEnabled = v;
    _streamerModeController.add(v);
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

  // §54.8: Per-item drawer visibility setters.
  void setShowMyProfileInDrawer(bool v) {
    if (_showMyProfileInDrawer == v) return;
    _showMyProfileInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowBotsInDrawer(bool v) {
    if (_showBotsInDrawer == v) return;
    _showBotsInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowNewGroupInDrawer(bool v) {
    if (_showNewGroupInDrawer == v) return;
    _showNewGroupInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowNewChannelInDrawer(bool v) {
    if (_showNewChannelInDrawer == v) return;
    _showNewChannelInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowContactsInDrawer(bool v) {
    if (_showContactsInDrawer == v) return;
    _showContactsInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowCallsInDrawer(bool v) {
    if (_showCallsInDrawer == v) return;
    _showCallsInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowSavedMessagesInDrawer(bool v) {
    if (_showSavedMessagesInDrawer == v) return;
    _showSavedMessagesInDrawer = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  bool get deleteOnlyForYouRemembered => _deleteOnlyForYouRemembered;
  set deleteOnlyForYouRemembered(bool v) { if (_deleteOnlyForYouRemembered != v) { _deleteOnlyForYouRemembered = v; _saveWindowPrefs(); notifyListeners(); } }

  Future<void> _applyStreamerMode(bool enabled) async {
    if (Platform.isWindows) {
      try {
        await _windowChannel.invokeMethod('setDisplayAffinity', enabled);
      } catch (e) {
        Debug.log('app_state', 'await _windowChannel.invokeMethod(\'setDisplayAffinity\', e...: $e');
      }
    } else if (Platform.isMacOS) {
      try {
        await _windowChannel.invokeMethod('setWindowSharing', !enabled);
      } catch (e) {
        Debug.log('app_state', 'await _windowChannel.invokeMethod(\'setWindowSharing\', !en...: $e');
      }
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
    if (v) {
      _engine.markAsOnline();
    }
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

  // The five ghost toggles below route through the per-account-aware
  // _syncGhostToEngine() (NOT a direct global updateConfig) so that in
  // "individual settings for each account" mode they update the ACTIVE
  // account's per-account override instead of the global config — matching the
  // sibling setMarkReadAfterAction/setUseScheduledMessages and AyuGram's
  // per-session ghost resolution (ayu_settings.cpp:437-448, 70-74).
  void setSendReadMessages(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendReadMessages == v) return;
    s.sendReadMessages = v;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendReadStories(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendReadStories == v) return;
    s.sendReadStories = v;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendOnlinePackets(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendOnlinePackets == v) return;
    s.sendOnlinePackets = v;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendUploadProgress(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendUploadProgress == v) return;
    s.sendUploadProgress = v;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendOfflinePacketAfterOnline(bool v) {
    final s = _ensureGhostSettings();
    if (s.sendOfflinePacketAfterOnline == v) return;
    s.sendOfflinePacketAfterOnline = v;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setMarkReadAfterAction(bool v) {
    final s = _ensureGhostSettings();
    if (s.markReadAfterAction == v) return;
    s.markReadAfterAction = v;
    if (v) s.useScheduledMessages = false;
    // Route through the per-account-aware sync so in "individual settings"
    // mode this updates the ACTIVE account's override, not the global config.
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setUseScheduledMessages(bool v) {
    final s = _ensureGhostSettings();
    if (s.useScheduledMessages == v) return;
    s.useScheduledMessages = v;
    if (v) s.markReadAfterAction = false;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSendWithoutSound(int v) {
    final s = _ensureGhostSettings();
    if (s.sendWithoutSound == v) return;
    s.sendWithoutSound = v;
    _syncGhostToEngine();
    notifyListeners();
    _saveWindowPrefs();
  }

  bool get suggestGhostModeBeforeViewingStory =>
      _ghostSettings.suggestGhostModeBeforeViewingStory;

  void setSuggestGhostModeBeforeViewingStory(bool v) {
    final s = _ensureGhostSettings();
    if (s.suggestGhostModeBeforeViewingStory == v) return;
    s.suggestGhostModeBeforeViewingStory = v;
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
    _syncAntiRecallSettings();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSaveMessagesHistory(bool v) {
    if (_saveMessagesHistory == v) return;
    _saveMessagesHistory = v;
    _syncAntiRecallSettings();
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSaveForBots(bool v) {
    if (_saveForBots == v) return;
    _saveForBots = v;
    _syncAntiRecallSettings();
    notifyListeners();
    _saveWindowPrefs();
  }

  void _syncAntiRecallSettings() {
    _engine.setAntiRecallSettings(
      saveDeleted: _saveDeletedMessages,
      saveHistory: _saveMessagesHistory,
      saveForBots: _saveForBots,
    );
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

  void setCrashReporting(bool v) {
    if (_crashReporting == v) return;
    _crashReporting = v;
    Debug.crashReportingEnabled = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void resetAyuSettings() {
    _bubbleRadius = 16;
    _removeTail = false;
    _materialSwitches = true;
    _avatarCorners = 23;
    _singleCornerRadius = false;
    _disableCustomBackgrounds = false;
    _hidePremiumStatuses = false;
    _monoFont = '';
    _hideNotificationCounters = false;
    _hideAllChatsFolder = false;
    _hideNotificationBadge = false;
    _photoEditorHintCount = 0;
    _appIcon = '';
    _replaceBottomInfoWithIcons = true;
    _adaptiveCoverColor = true;
    _simpleQuotesAndReplies = false;
    _semiTransparentDeleted = false;
    _wideMultiplier = 1.0;
    _showNightModeToggleInDrawer = true;
    _showMyProfileInDrawer = true;
    _showBotsInDrawer = true;
    _showNewGroupInDrawer = true;
    _showNewChannelInDrawer = true;
    _showContactsInDrawer = true;
    _showCallsInDrawer = true;
    _showSavedMessagesInDrawer = true;
    _showStreamerToggleInDrawer = false;
    _showStreamerToggleInTray = false;
    _showGhostToggleInDrawer = true;
    _showGhostToggleInTray = true;
    _showLReadToggleInDrawer = false;
    _showSReadToggleInDrawer = true;
    _useGlobalGhostMode = true;
    _ghostModeSettings = {'0': GhostModeAccountSettings()};
    _showViewsPanelInContextMenu = 1;
    _showRepeatMessageInContextMenu = 0;
    _showReactionsPanelInContextMenu = 1;
    _showHideMessageInContextMenu = 0;
    _showUserMessagesInContextMenu = 2;
    _showMessageDetailsInContextMenu = 2;
    _showAddFilterInContextMenu = 1;
    _showMessageSeconds = false;
    // Voice/audio playback speed, player repeat/order mode, autoplay-next and
    // song/video volume are Core::Settings, not AyuSettings (core_settings.h:1076-1077).
    // AyuGram's AyuSettings::reset() reconstructs only the AyuSettings singleton
    // (ayu_settings.cpp:428-431), so "Reset AyuGram settings" must NOT clobber the
    // user's playback speed and music/video volume — leave these untouched.
    _translationProvider = 0;
    _disableStories = false;
    _disableOpenLinkWarning = false;
    _collapseSimilarChannels = true;
    _hideSimilarChannels = false;
    _disableNotifyDelay = false;
    _filterZalgo = false;
    _improveLinkPreviews = false;
    _showPeerId = 2;
    _spoofWebviewAsAndroid = false;
    _increaseWebviewHeight = false;
    _increaseWebviewWidth = false;
    _stickerConfirmation = false;
    _gifConfirmation = false;
    _voiceConfirmation = false;
    _showIpInWebRtcCalls = false;
    _showAttachButton = true;
    _showCommandsButton = true;
    _showAutoDeleteButton = true;
    _showEmojiButton = true;
    _showMicrophoneButton = true;
    _showGiftButton = true;
    _showAiEditorButton = true;
    _showAttachPopup = true;
    _showEmojiPopup = true;
    _showOnlyAddedEmojisAndStickers = false;
    _showChannelReactions = true;
    _showGroupReactions = true;
    _showPrivateChatReactions = true;
    _recentStickersCount = 100;
    _channelBottomButton = 2;
    _quickAdminShortcuts = true;
    _showMessageShot = true;
    _messageShotSettings = MessageShotSettings();
    _hideFastShare = false;
    _saveDeletedMessages = true;
    _saveMessagesHistory = true;
    _saveForBots = false;
    _deletedMark = '\u{1F9F9}';
    _editedMark = '';
    _replaceMarksWithIcons = true;
    _localPremium = false;
    _disableAds = true;
    _crashReporting = true;
    _filtersEnabled = false;
    _filtersEnabledInChats = false;
    _hideFromBlocked = false;
    _shadowBanIds = {};
    _blockedIds = {};
    _readExclusions = {};
    _typingExclusions = {};
    notifyListeners();
    _saveWindowPrefs();
    // Direct field assignment above skips the engine/global re-pushes the
    // individual setters perform, so the reset would otherwise only take effect
    // on next launch (when _loadWindowPrefs re-seeds these). Replay them now:
    //  - anti-recall config → Go engine (setSaveDeletedMessages, :1714-1717)
    //  - gFilterZalgo global the display choke point reads (setFilterZalgo, :2196)
    //  - Debug.crashReportingEnabled mirror (setCrashReporting, :1784)
    _syncGhostToEngine();
    _syncAntiRecallSettings();
    gFilterZalgo = _filterZalgo;
    Debug.crashReportingEnabled = _crashReporting;
  }

  void _syncGhostToEngine() {
    if (_useGlobalGhostMode) {
      // One shared profile → global engine config. Drop any stale per-account
      // overrides so the shared profile governs every connected account.
      final s = _ghostModeSettings['0'] ?? GhostModeAccountSettings();
      _engine.updateConfig(
        sendReadReceipts: s.sendReadMessages,
        sendUploadProgress: s.sendUploadProgress,
        sendReadStories: s.sendReadStories,
        sendOnlinePackets: s.sendOnlinePackets,
        sendOfflineAfterOnline: s.sendOfflinePacketAfterOnline,
        markReadAfterAction: s.markReadAfterAction,
        useScheduledMessages: s.useScheduledMessages,
        sendWithoutSound: s.shouldSendWithoutSound,
      );
      _engine.clearAccountGhostOverrides();
      return;
    }
    // "Individual settings for each account": push EACH connected account's own
    // resolved profile as a per-account override, so simultaneously-connected
    // background accounts enforce THEIR config instead of the foreground
    // account's. AyuGram resolves ghost per session/userId — ayu_settings.cpp:437
    // `ghost(uint64 userId)`. Ghost settings are keyed by selfUserId here, but
    // the engine keys accounts by accountId, so we resolve per account and push
    // by accountId (the engine's consumption points use accountId).
    for (final acc in _accounts) {
      final s = _ghostModeSettings[acc.selfUserId] ??
          _ghostModeSettings['0'] ??
          GhostModeAccountSettings();
      _engine.updateConfig(
        accountId: acc.id,
        sendReadReceipts: s.sendReadMessages,
        sendUploadProgress: s.sendUploadProgress,
        sendReadStories: s.sendReadStories,
        sendOnlinePackets: s.sendOnlinePackets,
        sendOfflineAfterOnline: s.sendOfflinePacketAfterOnline,
        markReadAfterAction: s.markReadAfterAction,
        useScheduledMessages: s.useScheduledMessages,
        sendWithoutSound: s.shouldSendWithoutSound,
      );
    }
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
    notifyListeners();
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

  // §50.9: Per-peer typing exclusion. 0=default, 1=neverType, 2=alwaysType.
  int getTypingExclusion(String accountId, String chatId) =>
      _typingExclusions['$accountId:$chatId'] ?? 0;

  void setTypingExclusion(String accountId, String chatId, int value) {
    final key = '$accountId:$chatId';
    if (value == 0) {
      _typingExclusions.remove(key);
    } else {
      _typingExclusions[key] = value.clamp(0, 2);
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

  // Media player playback settings. Speed is clamped to Telegram's 0.5x–2.5x
  // range; setting 1.0 means "normal speed".
  void setVoicePlaybackSpeed(double v) {
    final speed = v.clamp(0.5, 2.5).toDouble();
    if (_voicePlaybackSpeed == speed) return;
    _voicePlaybackSpeed = speed;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setAudioPlaybackSpeed(double v) {
    final speed = v.clamp(0.5, 2.5).toDouble();
    if (_audioPlaybackSpeed == speed) return;
    _audioPlaybackSpeed = speed;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setPlayerRepeatMode(int v) {
    final mode = v.clamp(0, 2);
    if (_playerRepeatMode == mode) return;
    _playerRepeatMode = mode;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setPlayerOrderMode(int v) {
    final mode = v.clamp(0, 2);
    if (_playerOrderMode == mode) return;
    _playerOrderMode = mode;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setDisableAutoplayNext(bool v) {
    if (_disableAutoplayNext == v) return;
    _disableAutoplayNext = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  /// Set the song playback volume (0..1). Mirrors AyuGram setSongVolume — the
  /// remembered (last non-zero) value is NOT touched here; the slider records it
  /// separately via [setRememberedSongVolume] on drag-finish, and the mute
  /// toggle restores from it (media_player_widget.cpp:130-137 /
  /// media_player_volume_controller.cpp:38-44).
  void setSongVolume(double v) {
    final vol = v.clamp(0.0, 1.0).toDouble();
    if (_songVolume == vol) return;
    _songVolume = vol;
    notifyListeners();
    _saveWindowPrefs();
  }

  /// Record the volume to restore on un-mute. Only updated for values > 0,
  /// matching VolumeController's changeFinished callback.
  void setRememberedSongVolume(double v) {
    final vol = v.clamp(0.0, 1.0).toDouble();
    if (vol <= 0 || _rememberedSongVolume == vol) return;
    _rememberedSongVolume = vol;
    _saveWindowPrefs();
  }

  /// Set the video playback volume (0..1). Mirrors AyuGram setVideoVolume
  /// (core_settings.h:186, called from media_view_overlay_widget.cpp:5218 on
  /// every volume change) — a single persisted field with no remembered
  /// sibling; the media viewer keeps its mute-restore value locally. Save only,
  /// no notifyListeners: nothing in the tree rebuilds on this and it fires
  /// rapidly during a slider drag (the 500ms-debounced save coalesces writes).
  void setVideoVolume(double v) {
    final vol = v.clamp(0.0, 1.0).toDouble();
    if (_videoVolume == vol) return;
    _videoVolume = vol;
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

  /// Whether the "Native" translation provider (index 3) is usable on this
  /// platform. Mirrors AyuGram's `Platform::IsTranslateProviderAvailable()`:
  /// on Linux the native provider shells out to Crow Translate, so it is only
  /// available when `crow`/`org.kde.CrowTranslate` is on PATH
  /// (translate_provider_linux.cpp:20-38,86). Windows/macOS ship an OS
  /// translation API, so it is always available there.
  bool? _cachedNativeTranslateAvailable;
  bool get nativeTranslateAvailable {
    final cached = _cachedNativeTranslateAvailable;
    if (cached != null) return cached;
    bool available;
    if (kIsWeb) {
      available = false;
    } else if (Platform.isLinux) {
      available =
          _hasExecutable('crow') || _hasExecutable('org.kde.CrowTranslate');
    } else {
      available = true;
    }
    _cachedNativeTranslateAvailable = available;
    return available;
  }

  bool _hasExecutable(String name) {
    final pathEnv = Platform.environment['PATH'] ?? '';
    if (pathEnv.isEmpty) return false;
    final sep = Platform.isWindows ? ';' : ':';
    for (final dir in pathEnv.split(sep)) {
      if (dir.isEmpty) continue;
      try {
        if (File('$dir${Platform.pathSeparator}$name').existsSync()) return true;
      } catch (e) {
        Debug.log('app_state', 'if (File(\'\$dir\${Platform.pathSeparator}\$name\').existsSync...: $e');
      }
    }
    return false;
  }

  // §54.14: AyuGram General settings setters.
  void setTranslationProvider(int v) {
    var p = v.clamp(0, 3);
    // AyuGram forces Native→Telegram when the platform provider is unavailable
    // (ayu_settings.cpp:1008-1012 setter gate). Native is index 3, Telegram is 0.
    if (p == 3 && !nativeTranslateAvailable) p = 0;
    if (_translationProvider == p) return;
    _translationProvider = p;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setDisableStories(bool v) {
    if (_disableStories == v) return;
    _disableStories = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setDisableOpenLinkWarning(bool v) {
    if (_disableOpenLinkWarning == v) return;
    _disableOpenLinkWarning = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setCollapseSimilarChannels(bool v) {
    if (_collapseSimilarChannels == v) return;
    _collapseSimilarChannels = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setHideSimilarChannels(bool v) {
    if (_hideSimilarChannels == v) return;
    _hideSimilarChannels = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setDisableNotifyDelay(bool v) {
    if (_disableNotifyDelay == v) return;
    _disableNotifyDelay = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setFilterZalgo(bool v) {
    if (_filterZalgo == v) return;
    _filterZalgo = v;
    gFilterZalgo = v; // mirror to the global the display choke point reads
    notifyListeners();
    _saveWindowPrefs();
  }
  void setImproveLinkPreviews(bool v) {
    if (_improveLinkPreviews == v) return;
    _improveLinkPreviews = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowPeerId(int v) {
    if (_showPeerId == v) return;
    _showPeerId = v.clamp(0, 2);
    notifyListeners();
    _saveWindowPrefs();
  }
  void setSpoofWebviewAsAndroid(bool v) {
    if (_spoofWebviewAsAndroid == v) return;
    _spoofWebviewAsAndroid = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setIncreaseWebviewHeight(bool v) {
    if (_increaseWebviewHeight == v) return;
    _increaseWebviewHeight = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setIncreaseWebviewWidth(bool v) {
    if (_increaseWebviewWidth == v) return;
    _increaseWebviewWidth = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setStickerConfirmation(bool v) {
    if (_stickerConfirmation == v) return;
    _stickerConfirmation = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setGifConfirmation(bool v) {
    if (_gifConfirmation == v) return;
    _gifConfirmation = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setVoiceConfirmation(bool v) {
    if (_voiceConfirmation == v) return;
    _voiceConfirmation = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowIpInWebRtcCalls(bool v) {
    if (_showIpInWebRtcCalls == v) return;
    _showIpInWebRtcCalls = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  // §54.16: AyuGram Filters settings setters.
  void setFiltersEnabled(bool v) {
    if (_filtersEnabled == v) return;
    _filtersEnabled = v;
    filterEngine.rebuildCache();
    notifyListeners();
    _saveWindowPrefs();
  }
  void setFiltersEnabledInChats(bool v) {
    if (_filtersEnabledInChats == v) return;
    _filtersEnabledInChats = v;
    filterEngine.rebuildCache();
    notifyListeners();
    _saveWindowPrefs();
  }
  void setHideFromBlocked(bool v) {
    if (_hideFromBlocked == v) return;
    _hideFromBlocked = v;
    filterEngine.rebuildCache();
    notifyListeners();
    _saveWindowPrefs();
  }
  void addShadowBan(int id) {
    if (_shadowBanIds.contains(id)) return;
    _shadowBanIds = {..._shadowBanIds, id};
    filterEngine.rebuildCache();
    notifyListeners();
    _saveWindowPrefs();
  }
  void removeShadowBan(int id) {
    if (!_shadowBanIds.contains(id)) return;
    _shadowBanIds = {..._shadowBanIds}..remove(id);
    filterEngine.rebuildCache();
    notifyListeners();
    _saveWindowPrefs();
  }
  bool isShadowBanned(int id) => _shadowBanIds.contains(id);
  void addBlocked(int id) {
    if (_blockedIds.contains(id)) return;
    _blockedIds = {..._blockedIds, id};
    filterEngine.rebuildCache();
    notifyListeners();
    _saveWindowPrefs();
  }
  void removeBlocked(int id) {
    if (!_blockedIds.contains(id)) return;
    _blockedIds = {..._blockedIds}..remove(id);
    filterEngine.rebuildCache();
    notifyListeners();
    _saveWindowPrefs();
  }
  bool isBlocked(int id) => _blockedIds.contains(id);

  // The Dart [AyuFilterEngine] is the authoritative filter store — there is no
  // separate Go filter engine; regex matching runs in-process via Dart's RegExp
  // (filterEngine.isFiltered) and is persisted inside the window prefs JSON
  // (toJson()/loadFromJson). After a filter mutation this both persists the change
  // and broadcasts AppState — the equivalent of AyuGram's FiltersCacheController::
  // fireUpdate() — so settings screens (context.select/watch) and the chat list
  // re-render against the new filter state.
  void saveFilterEngine() {
    _saveWindowPrefs();
    notifyListeners();
  }

  // §54.9: Message field button toggle setters.
  void setShowAttachButton(bool v) {
    if (_showAttachButton == v) return;
    _showAttachButton = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowCommandsButton(bool v) {
    if (_showCommandsButton == v) return;
    _showCommandsButton = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowAutoDeleteButton(bool v) {
    if (_showAutoDeleteButton == v) return;
    _showAutoDeleteButton = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowEmojiButton(bool v) {
    if (_showEmojiButton == v) return;
    _showEmojiButton = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowMicrophoneButton(bool v) {
    if (_showMicrophoneButton == v) return;
    _showMicrophoneButton = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowGiftButton(bool v) {
    if (_showGiftButton == v) return;
    _showGiftButton = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowAiEditorButton(bool v) {
    if (_showAiEditorButton == v) return;
    _showAiEditorButton = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowAttachPopup(bool v) {
    if (_showAttachPopup == v) return;
    _showAttachPopup = v;
    notifyListeners();
    _saveWindowPrefs();
  }
  void setShowEmojiPopup(bool v) {
    if (_showEmojiPopup == v) return;
    _showEmojiPopup = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  // §54.11: Additional chat settings setters.
  void setShowOnlyAddedEmojisAndStickers(bool v) {
    if (_showOnlyAddedEmojisAndStickers == v) return;
    _showOnlyAddedEmojisAndStickers = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowChannelReactions(bool v) {
    if (_showChannelReactions == v) return;
    _showChannelReactions = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowGroupReactions(bool v) {
    if (_showGroupReactions == v) return;
    _showGroupReactions = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowPrivateChatReactions(bool v) {
    if (_showPrivateChatReactions == v) return;
    _showPrivateChatReactions = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setRecentStickersCount(int v) {
    v = v.clamp(1, 200);
    if (_recentStickersCount == v) return;
    _recentStickersCount = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setChannelBottomButton(int v) {
    v = v.clamp(0, 2);
    if (_channelBottomButton == v) return;
    _channelBottomButton = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setQuickAdminShortcuts(bool v) {
    if (_quickAdminShortcuts == v) return;
    _quickAdminShortcuts = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setShowMessageShot(bool v) {
    if (_showMessageShot == v) return;
    _showMessageShot = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  // AyuGram `messageShotSettings()` accessor (ayu_settings.h:260-261).
  MessageShotSettings get messageShotSettings => _messageShotSettings;

  void _onMessageShotChanged() {
    notifyListeners();
    _saveWindowPrefs();
  }

  void setMessageShotShowBackground(bool v) {
    if (_messageShotSettings.showBackground == v) return;
    _messageShotSettings.showBackground = v;
    _onMessageShotChanged();
  }

  void setMessageShotShowDate(bool v) {
    if (_messageShotSettings.showDate == v) return;
    _messageShotSettings.showDate = v;
    _onMessageShotChanged();
  }

  void setMessageShotShowReactions(bool v) {
    if (_messageShotSettings.showReactions == v) return;
    _messageShotSettings.showReactions = v;
    _onMessageShotChanged();
  }

  void setMessageShotShowHeaderDecorations(bool v) {
    if (_messageShotSettings.showHeaderDecorations == v) return;
    _messageShotSettings.showHeaderDecorations = v;
    _onMessageShotChanged();
  }

  void setMessageShotShowColorfulReplies(bool v) {
    if (_messageShotSettings.showColorfulReplies == v) return;
    _messageShotSettings.showColorfulReplies = v;
    _onMessageShotChanged();
  }

  void setMessageShotRevealSpoilers(bool v) {
    if (_messageShotSettings.revealSpoilers == v) return;
    _messageShotSettings.revealSpoilers = v;
    _onMessageShotChanged();
  }

  void setMessageShotEmbeddedTheme(int type, [int accentColor = 0]) {
    if (_messageShotSettings.setEmbeddedTheme(type, accentColor)) {
      _onMessageShotChanged();
    }
  }

  void setMessageShotCloudTheme(
    int accountId,
    int id,
    int accessHash,
    int documentId,
    String title,
  ) {
    if (_messageShotSettings.setCloudTheme(
        accountId, id, accessHash, documentId, title)) {
      _onMessageShotChanged();
    }
  }

  void clearMessageShotTheme() {
    if (_messageShotSettings.clearTheme()) {
      _onMessageShotChanged();
    }
  }

  void setHideFastShare(bool v) {
    if (_hideFastShare == v) return;
    _hideFastShare = v;
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
    _configureAutostart(v);
  }

  Future<void> _configureAutostart(bool enable) async {
    if (kIsWeb) return;
    final exe = Platform.resolvedExecutable;
    final appName = 'uniclient';
    try {
      if (Platform.isLinux) {
        final autostartDir = '${Platform.environment['HOME']}/.config/autostart';
        final desktopFile = '$autostartDir/$appName.desktop';
        if (enable) {
          await Directory(autostartDir).create(recursive: true);
          await File(desktopFile).writeAsString(
            '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=UniClient\n'
            'Exec=$exe\n'
            'Terminal=false\n'
            'X-GNOME-Autostart-enabled=true\n',
          );
        } else {
          final f = File(desktopFile);
          if (await f.exists()) await f.delete();
        }
      } else if (Platform.isWindows) {
        final regKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
        if (enable) {
          await Process.run('reg', ['add', regKey, '/v', appName, '/t', 'REG_SZ', '/d', exe, '/f']);
        } else {
          await Process.run('reg', ['delete', regKey, '/v', appName, '/f']);
        }
      } else if (Platform.isMacOS) {
        final plistDir = '${Platform.environment['HOME']}/Library/LaunchAgents';
        final plistFile = '$plistDir/com.$appName.plist';
        if (enable) {
          await Directory(plistDir).create(recursive: true);
          await File(plistFile).writeAsString(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0"><dict>\n'
            '<key>Label</key><string>com.$appName</string>\n'
            '<key>ProgramArguments</key><array><string>$exe</string></array>\n'
            '<key>RunAtLoad</key><true/>\n'
            '</dict></plist>\n',
          );
        } else {
          final f = File(plistFile);
          if (await f.exists()) await f.delete();
        }
      }
    } catch (e) {
      Debug.log('app_state', 'if (Platform.isLinux): $e');
    }
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
    noHwAccelVideo = !v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setOpenGlDisabled(bool v) {
    if (_openGlDisabled == v) return;
    _openGlDisabled = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setAngleBackendIndex(int v) {
    if (_angleBackendIndex == v) return;
    _angleBackendIndex = v.clamp(0, 4);
    notifyListeners();
    _saveWindowPrefs();
  }

  void setAddToSendToMenu(bool v) {
    if (_addToSendToMenu == v) return;
    _addToSendToMenu = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setWarnBeforeQuit(bool v) {
    if (_warnBeforeQuit == v) return;
    _warnBeforeQuit = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setSystemTextReplacements(bool v) {
    if (_systemTextReplacements == v) return;
    _systemTextReplacements = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setRoundDockIcon(bool v) {
    if (_roundDockIcon == v) return;
    _roundDockIcon = v;
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

  void toggleDictionary(String code) {
    if (_enabledDictionaries.contains(code)) {
      _enabledDictionaries.remove(code);
    } else {
      _enabledDictionaries.add(code);
    }
    notifyListeners();
    _saveWindowPrefs();
  }

  // Mirrors AyuGram Ui::SetScreenReaderModeDisabled (lib_ui/ui/screen_reader_mode.cpp):
  // when the mode is NOT disabled, screen-reader optimizations are active
  // (ScreenReaderModeActive = !disabled && detected), so make sure the semantics
  // tree is built to serve a connected reader.
  void setScreenReaderModeDisabled(bool v) {
    if (_screenReaderModeDisabled == v) return;
    _screenReaderModeDisabled = v;
    if (!v) {
      WidgetsBinding.instance.ensureSemantics();
    }
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

  void setNoWarningExtensions(Set<String> exts) {
    if (_setEquals(_noWarningExtensions, exts)) return;
    _noWarningExtensions = exts;
    notifyListeners();
    _saveWindowPrefs();
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  void setProxyMode(int mode, [String proxyType = '']) {
    if (_proxyMode == mode && _selectedProxyType == proxyType) return;
    _proxyMode = mode;
    _selectedProxyType = proxyType;
    notifyListeners();
    _saveWindowPrefs();
    _syncProxyToEngine();
  }

  void setProxyIpv6(bool v) {
    if (_proxyIpv6 == v) return;
    _proxyIpv6 = v;
    notifyListeners();
    _saveWindowPrefs();
    _syncProxyToEngine();
  }

  void setProxyForCalls(bool v) {
    if (_proxyForCalls == v) return;
    _proxyForCalls = v;
    notifyListeners();
    _saveWindowPrefs();
    _syncProxyToEngine();
  }

  void setCallSameDevice(bool v) {
    if (_callSameDevice == v) return;
    _callSameDevice = v;
    notifyListeners();
    _saveWindowPrefs();
  }

  void setProxyRotationEnabled(bool v) {
    if (_proxyRotationEnabled == v) return;
    _proxyRotationEnabled = v;
    notifyListeners();
    _saveWindowPrefs();
    _syncProxyToEngine();
  }

  void setProxyRotationTimeout(int v) {
    if (_proxyRotationTimeout == v) return;
    _proxyRotationTimeout = v;
    notifyListeners();
    _saveWindowPrefs();
    _syncProxyToEngine();
  }

  void setProxyCheckIpWarningShown(bool v) {
    if (_proxyCheckIpWarningShown == v) return;
    _proxyCheckIpWarningShown = v;
    _saveWindowPrefs();
  }

  void setProxyList(List<Map<String, dynamic>> list) {
    _proxyList = list;
    notifyListeners();
    _saveWindowPrefs();
    _syncProxyToEngine();
  }

  void setSelectedProxy(Map<String, dynamic> proxy) {
    _selectedProxyData = Map<String, dynamic>.from(proxy);
    _saveWindowPrefs();
    _syncProxyToEngine();
  }

  void _syncProxyToEngine() {
    final activeProxy = (_proxyMode == 2 && _selectedProxyData.isNotEmpty)
        ? _selectedProxyData
        : (_proxyMode == 2 && _proxyList.isNotEmpty)
            ? _proxyList.first
            : <String, dynamic>{};
    final payload = {
      'mode': _proxyMode,
      'ipv6': _proxyIpv6,
      'use_for_calls': _proxyForCalls,
      // Use the active proxy's own lowercase type.name so the type always
      // matches the host/port/secret being sent from the same object. The
      // separate _selectedProxyType holds the uppercase display label
      // ("SOCKS5") for the settings status text only — sending it here was a
      // no-op (and could go stale/empty relative to activeProxy), because the
      // Go dialer's ProxyConfig.active() compares against lowercase tokens.
      'proxy_type': activeProxy['type'] ?? _selectedProxyType.toLowerCase(),
      'host': activeProxy['host'] ?? '',
      'port': activeProxy['port'] ?? 0,
      'username': activeProxy['username'] ?? '',
      'password': activeProxy['password'] ?? '',
      'secret': activeProxy['secret'] ?? '',
      'proxies': _proxyList,
      // AyuGram SettingsProxy.proxyRotationEnabled/proxyRotationTimeout
      // (core_settings_proxy.h:43-47) — forward so the backend can rotate
      // through the proxy list on the configured timeout.
      'rotation_enabled': _proxyRotationEnabled,
      'rotation_timeout': _proxyRotationTimeout,
    };
    for (final a in _accounts) {
      _engine.callGeneric(a.id, 'SetProxy', payload).catchError((_) {});
    }
  }

  // Re-pushes engine-side settings that the Go engine holds in memory only (no
  // disk persistence) so they survive an app restart. Called from initialize()
  // after loading prefs — the same pattern as _syncGhostToEngine /
  // _syncAntiRecallSettings. Without this, a restart drops the user's
  // auto-download limits, local-storage caps and power-saving flags back to
  // engine defaults.
  void _resyncEngineSettings() {
    // Per-source auto-download limits (engine ShouldAutoDownload reads these).
    for (final entry in _autoDownloadSettings.entries) {
      final payload = {'source': entry.key, ...entry.value};
      for (final a in _accounts) {
        _engine.callGeneric(a.id, 'SetAutoDownload', payload).catchError((_) {});
      }
    }
    // Local-storage eviction limits (media/total caps + time-based eviction).
    _engine.updateConfig(maxCacheSize: _localStorageTotalLimit * 1024 * 1024);
    _engine.callGeneric('__engine', 'SetLocalStorageLimits', {
      'total_limit_mb': _localStorageTotalLimit,
      'media_limit_mb': _localStorageMediaLimit,
      'time_limit_days': _timeLimitIndexToDays(_localStorageTimeLimit),
    }).catchError((_) {});
    // Power-saving flags + ForceAll state.
    _engine.callGeneric('__engine', 'SetPowerSaving', {
      'flags': _powerSavingFlags,
      'force_all': _autoPowerSaving,
    }).catchError((_) {});
    // Notification sound volume is intentionally NOT pushed here: it is consumed
    // entirely Dart-side (notification_sound.dart reads settings.volume), so it
    // never reverts to an engine default on restart. (The engine has no
    // SetNotificationVolume method — its server-side notify "global_volume" is a
    // separate concept set through Get/UpdateNotifyConfig, not local playback.)
  }

  void setAutoDownloadSettings(String source, Map<String, dynamic> settings) {
    _autoDownloadSettings[source] = settings;
    notifyListeners();
    _saveWindowPrefs();
    final payload = {'source': source, ...settings};
    for (final a in _accounts) {
      _engine.callGeneric(a.id, 'SetAutoDownload', payload).catchError((_) {});
    }
  }

  Map<String, dynamic> getAutoDownloadForSource(String source) {
    return _autoDownloadSettings[source] ?? {
      'photos': true,
      'files': false,
      'downloadLimit': 10.0,
      'videoMessages': true,
      'videos': true,
      'gifs': true,
      'autoPlayLimit': 50.0,
    };
  }

  void setLocalStorageLimits({int? totalLimit, int? mediaLimit, int? timeLimit}) {
    if (totalLimit != null) _localStorageTotalLimit = totalLimit;
    if (mediaLimit != null) _localStorageMediaLimit = mediaLimit;
    if (timeLimit != null) _localStorageTimeLimit = timeLimit;
    notifyListeners();
    _saveWindowPrefs();
    _engine.updateConfig(maxCacheSize: _localStorageTotalLimit * 1024 * 1024);
    _engine.callGeneric('__engine', 'SetLocalStorageLimits', {
      'total_limit_mb': _localStorageTotalLimit,
      'media_limit_mb': _localStorageMediaLimit,
      'time_limit_days': _timeLimitIndexToDays(_localStorageTimeLimit),
    }).catchError((_) {});
  }

  // Converts the Keep-media time-limit slider index (0..15) into a real number
  // of days for the engine's time-based eviction. Mirrors AyuGram's
  // TimeLimitInDays (boxes/local_storage_box.cpp:69): indices 0..2 are weeks
  // (1..3)*7, indices 3..14 are months (≈30 days with calendar nudges), and the
  // final index ("Forever") yields 0 = no time limit.
  int _timeLimitIndexToDays(int index) {
    if (index < 3) return (index + 1) * 7;
    if (index < 15) {
      final month = index - 2;
      final extra = month >= 12
          ? 5
          : month >= 10
              ? 4
              : month >= 8
                  ? 3
                  : month >= 7
                      ? 2
                      : month >= 5
                          ? 1
                          : month >= 3
                              ? 0
                              : month >= 2
                                  ? -1
                                  : 1; // month == 1
      return month * 30 + extra;
    }
    return 0; // "Forever"
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
    _ensureWallpaperAverageColor();
  }

  /// Computes an image wallpaper's average colour off the UI thread and, once
  /// it lands, rebuilds so the service-message colours adapt to the background
  /// ([adjustServiceColorsForWallpaper]). No-op for gradient/solid wallpapers
  /// (their average is a cheap synchronous mean) and when the value is already
  /// cached. Mirrors AyuGram preparing the background — `CountAverageColor`
  /// included — off-thread and refreshing the chat theme when it arrives
  /// (chat_theme.cpp:880, dispatched via `crl::async` :705).
  void _ensureWallpaperAverageColor() {
    final wp = _wallpaper;
    if (wp.imageBytes == null || wp.averageColor != null) return;
    wp.ensureAverageColor().then((_) {
      // Skip if a newer wallpaper has superseded this one in the meantime.
      if (identical(_wallpaper, wp)) notifyListeners();
    });
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

  /// Update menu bots for an account.
  void setMenuBots(String accountId, List<MenuBotInfo> bots) {
    _menuBots[accountId] = bots;
    notifyListeners();
  }

  /// Fetch the account's main-menu (drawer) bots from the engine and publish
  /// them via [setMenuBots]. This is the Dart equivalent of AyuGram querying
  /// `attachWebView().attachBots()` live when the drawer/appearance settings are
  /// built (settings_appearance.cpp:291 HasDrawerBots) — it's what makes the
  /// "Bots" drawer toggle appear for accounts that have a main-menu bot.
  ///
  /// Idempotent: once a fetch succeeds for an account it is not repeated this
  /// session. A fetch that fails because the account isn't connected yet returns
  /// null and is NOT marked loaded, so a later call (e.g. the next time the
  /// drawer opens) retries. Safe to call from a widget build via a post-frame
  /// callback — when nothing changes it does no work and fires no notifications.
  Future<void> ensureMenuBotsLoaded(String accountId) async {
    if (accountId.isEmpty) return;
    if (_menuBotsLoaded.contains(accountId)) return;
    if (_menuBotsLoading.contains(accountId)) return;
    _menuBotsLoading.add(accountId);
    try {
      final bots = await _engine.getMainMenuBots(accountId);
      if (bots == null) return; // not connected yet — allow a later retry
      _menuBotsLoaded.add(accountId);
      // Only notify if the published list actually changed.
      final existing = _menuBots[accountId];
      final changed = existing == null ||
          existing.length != bots.length ||
          !_sameBots(existing, bots);
      if (changed) setMenuBots(accountId, bots);
    } finally {
      _menuBotsLoading.remove(accountId);
    }
  }

  bool _sameBots(List<MenuBotInfo> a, List<MenuBotInfo> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  String get swipeAction => _swipeAction;
  set swipeAction(String value) {
    if (_swipeAction != value) {
      _swipeAction = value;
      _saveWindowPrefs();
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

  bool? get rememberedSendAsDocuments => _rememberedSendAsDocuments;
  set rememberedSendAsDocuments(bool? value) {
    if (_rememberedSendAsDocuments != value) {
      _rememberedSendAsDocuments = value;
      _saveWindowPrefs();
      notifyListeners();
    }
  }

  bool? get rememberedGroupFiles => _rememberedGroupFiles;
  set rememberedGroupFiles(bool? value) {
    if (_rememberedGroupFiles != value) {
      _rememberedGroupFiles = value;
      _saveWindowPrefs();
      notifyListeners();
    }
  }

  List<String> get recentHashtags => _recentHashtags;
  void updateRecentHashtags(List<String> tags) {
    _recentHashtags = tags.take(40).toList();
    _saveWindowPrefs();
  }

  bool get rememberedSoundNotifyFromTray => _rememberedSoundNotifyFromTray;
  set rememberedSoundNotifyFromTray(bool value) {
    if (_rememberedSoundNotifyFromTray != value) {
      _rememberedSoundNotifyFromTray = value;
      _saveWindowPrefs();
    }
  }

  bool get rememberedFlashBounceNotifyFromTray => _rememberedFlashBounceNotifyFromTray;
  set rememberedFlashBounceNotifyFromTray(bool value) {
    if (_rememberedFlashBounceNotifyFromTray != value) {
      _rememberedFlashBounceNotifyFromTray = value;
      _saveWindowPrefs();
    }
  }

  // §15: Notification settings getters/setters
  // Transient demo-sample flag (not persisted) — only notifies listeners.
  bool get notifDemoShown => _notifDemoShown;
  void setNotifDemoShown(bool v) {
    if (_notifDemoShown == v) return;
    _notifDemoShown = v;
    notifyListeners();
  }
  bool get notifDesktopNotify => _notifDesktopNotify;
  set notifDesktopNotify(bool v) { if (_notifDesktopNotify != v) { _notifDesktopNotify = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get notifFlashBounce => _notifFlashBounce;
  set notifFlashBounce(bool v) { if (_notifFlashBounce != v) { _notifFlashBounce = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get notifAllowSound => _notifAllowSound;
  set notifAllowSound(bool v) { if (_notifAllowSound != v) { _notifAllowSound = v; _saveWindowPrefs(); notifyListeners(); } }
  int get notifVolume => _notifVolume;
  // No engine push: the volume is consumed entirely Dart-side by
  // notification_sound.dart (see the comment at _saveWindowPrefs above). The
  // engine has no SetNotificationVolume handler, so any FFI call here would just
  // error and be swallowed.
  set notifVolume(int v) { if (_notifVolume != v) { _notifVolume = v; _saveWindowPrefs(); notifyListeners(); } }
  void setNotifVolumeFromEngine(int v) { if (_notifVolume != v) { _notifVolume = v; notifyListeners(); } }

  // ── Per-chat / per-type ringtone volume (AyuGram ringtoneVolume, 2-tier) ──
  // Maps a notify-type ('private'/'group'/'channel') from the chat's notify
  // category. Topics inherit their parent group's type.
  static String notifTypeKey(int chatTypeInt) {
    // engine ChatType ints: 1=dm/private, 2=group, 3=channel, 4=topic.
    switch (chatTypeInt) {
      case 3:
        return 'channel';
      case 2:
      case 4:
        return 'group';
      default:
        return 'private';
    }
  }

  /// Resolves the ringtone volume OVERRIDE for a chat (AyuGram
  /// notifications_manager.cpp:763-772): per-chat volume first, then the
  /// per-default-notify-type volume; returns 0 when neither is set so the sound
  /// player falls back to the global notification volume.
  int ringtoneVolume(String accountId, String chatId, int chatTypeInt) {
    final perChat = _ringtoneVolumes['$accountId:$chatId'] ?? 0;
    if (perChat > 0) return perChat;
    return _notifTypeVolumes['$accountId:${notifTypeKey(chatTypeInt)}'] ?? 0;
  }

  int chatRingtoneVolume(String accountId, String chatId) =>
      _ringtoneVolumes['$accountId:$chatId'] ?? 0;

  /// Last-used mute durations (seconds) for the quick-mute menu items.
  List<int> get mutePeriods => List.unmodifiable(_mutePeriods);

  /// Records a used mute duration, keeping the most-recent pair sorted ascending
  /// (AyuGram SessionSettings::addMutePeriod, main_session_settings.cpp:938-948).
  void addMutePeriod(int period) {
    if (period <= 0) return;
    if (_mutePeriods.isEmpty) {
      _mutePeriods.add(period);
    } else if (_mutePeriods.last != period) {
      final last = _mutePeriods.last;
      _mutePeriods
        ..clear()
        ..addAll(last < period ? [last, period] : [period, last]);
    }
    _saveWindowPrefs();
    notifyListeners();
  }

  /// Sets (or clears, when [volume] <= 0) a per-chat ringtone volume override.
  void setChatRingtoneVolume(String accountId, String chatId, int volume) {
    final key = '$accountId:$chatId';
    final v = volume.clamp(0, 100);
    final cur = _ringtoneVolumes[key] ?? 0;
    if (cur == v) return;
    if (v > 0) {
      _ringtoneVolumes[key] = v;
    } else {
      _ringtoneVolumes.remove(key);
    }
    _saveWindowPrefs();
    notifyListeners();
  }

  int notifTypeVolume(String accountId, String type) =>
      _notifTypeVolumes['$accountId:$type'] ?? 0;

  /// Seeds the local per-type ringtone-volume mirror from the engine's stored
  /// value (called when the notifications settings screen loads). Persists but
  /// does NOT notify (the value is read at notification time, not bound to a
  /// rebuild) and never re-pushes to the engine.
  void setNotifTypeVolumeFromEngine(String accountId, String type, int volume) {
    final key = '$accountId:$type';
    final v = volume.clamp(0, 100);
    final cur = _notifTypeVolumes[key] ?? 0;
    if (cur == v) return;
    if (v > 0) {
      _notifTypeVolumes[key] = v;
    } else {
      _notifTypeVolumes.remove(key);
    }
    _saveWindowPrefs();
  }

  /// Sets a per-notify-type default ringtone volume. Persisted locally AND
  /// pushed to the engine's local notify config (parity with the per-type
  /// notifications settings screen).
  void setNotifTypeVolume(String accountId, String type, int volume) {
    final key = '$accountId:$type';
    final v = volume.clamp(0, 100);
    final cur = _notifTypeVolumes[key] ?? 0;
    if (cur != v) {
      if (v > 0) {
        _notifTypeVolumes[key] = v;
      } else {
        _notifTypeVolumes.remove(key);
      }
      _saveWindowPrefs();
      notifyListeners();
    }
    _engine.saveLocalNotifyConfig(accountId, {
      'type': 'per_type_volume_$type',
      'peer_type': type,
      'volume': v,
    }).catchError((_) {});
  }

  // ── Per-chat notification sound (AyuGram per-thread sound override) ──
  /// True when the chat is set to "None" (silent) — gates the alert sound
  /// (NotificationSoundPlayer skips when soundNone) mirroring sound(thread).none.
  bool chatSoundIsNone(String accountId, String chatId) =>
      (_chatSoundDocId['$accountId:$chatId'] ?? 0) == -2;

  /// Local file path of the chat's custom ringtone, or '' for default/none.
  String chatSoundPath(String accountId, String chatId) =>
      _chatSoundPath['$accountId:$chatId'] ?? '';

  /// Current per-chat sound document id (0 = default, -2 = none, >0 = ringtone).
  int chatSoundDocId(String accountId, String chatId) =>
      _chatSoundDocId['$accountId:$chatId'] ?? 0;

  /// Sets a chat's notification sound. [docId] 0/-1 clears the override
  /// (default), -2 = None (silent), >0 = a saved ringtone whose local [path]
  /// is captured for playback. Persisted locally (AyuGram stores the per-thread
  /// sound override in local notify settings).
  void setChatSound(String accountId, String chatId, int docId, String path) {
    final key = '$accountId:$chatId';
    final hadId = _chatSoundDocId.containsKey(key);
    final hadPath = _chatSoundPath.containsKey(key);
    if (docId == 0 || docId == -1) {
      _chatSoundDocId.remove(key);
      _chatSoundPath.remove(key);
      if (hadId || hadPath) {
        _saveWindowPrefs();
        notifyListeners();
      }
      return;
    }
    _chatSoundDocId[key] = docId;
    if (docId > 0 && path.isNotEmpty) {
      _chatSoundPath[key] = path;
    } else {
      _chatSoundPath.remove(key); // None (-2) carries no file
    }
    _saveWindowPrefs();
    notifyListeners();
  }

  static Map<String, int> _decodeVolumeMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      final iv = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      if (iv > 0) out['$k'] = iv.clamp(1, 100);
    });
    return out;
  }

  static Map<String, int> _decodeIntMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      final iv = (v is num) ? v.toInt() : int.tryParse('$v');
      if (iv != null && iv != 0) out['$k'] = iv;
    });
    return out;
  }

  static Map<String, String> _decodeStringMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final s = '$v';
      if (s.isNotEmpty) out['$k'] = s;
    });
    return out;
  }

  bool get notifPreviewName => _notifPreviewName;
  set notifPreviewName(bool v) { if (_notifPreviewName != v) { _notifPreviewName = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get notifPreviewText => _notifPreviewText;
  set notifPreviewText(bool v) { if (_notifPreviewText != v) { _notifPreviewText = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get notifPrivateChats => _notifPrivateChats;
  set notifPrivateChats(bool v) { if (_notifPrivateChats != v) { _notifPrivateChats = v; _engine.updateConfig(notifyDms: v); _engine.updateDefaultNotifySettings(_activeAccountId, peerType: 'private', enabled: v); _saveWindowPrefs(); notifyListeners(); } }
  bool get notifGroups => _notifGroups;
  set notifGroups(bool v) { if (_notifGroups != v) { _notifGroups = v; _engine.updateConfig(notifyGroups: v); _engine.updateDefaultNotifySettings(_activeAccountId, peerType: 'group', enabled: v); _saveWindowPrefs(); notifyListeners(); } }
  bool get notifChannels => _notifChannels;
  set notifChannels(bool v) { if (_notifChannels != v) { _notifChannels = v; _engine.updateDefaultNotifySettings(_activeAccountId, peerType: 'channel', enabled: v); _saveWindowPrefs(); notifyListeners(); } }
  bool get notifReactions => _notifReactions;
  set notifReactions(bool v) { if (_notifReactions != v) { _notifReactions = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get notifUseNative => _notifUseNative;
  set notifUseNative(bool v) { if (_notifUseNative != v) { _notifUseNative = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get notifSkipToastsInFocus => _notifSkipToastsInFocus;
  set notifSkipToastsInFocus(bool v) { if (_notifSkipToastsInFocus != v) { _notifSkipToastsInFocus = v; _saveWindowPrefs(); notifyListeners(); } }
  int get notifDisplayIndex => _notifDisplayIndex;
  set notifDisplayIndex(int v) { if (_notifDisplayIndex != v) { _notifDisplayIndex = v; _saveWindowPrefs(); notifyListeners(); } }
  int get notifCorner => _notifCorner;
  set notifCorner(int v) { if (_notifCorner != v) { _notifCorner = v; _saveWindowPrefs(); notifyListeners(); } }
  int get notifCount => _notifCount;
  set notifCount(int v) { if (_notifCount != v) { _notifCount = v; _saveWindowPrefs(); notifyListeners(); } }

  // §14.6: Chat appearance settings getters/setters
  bool get chatLargeEmoji => _chatLargeEmoji;
  set chatLargeEmoji(bool v) { if (_chatLargeEmoji != v) { _chatLargeEmoji = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get chatReplaceEmojis => _chatReplaceEmojis;
  set chatReplaceEmojis(bool v) { if (_chatReplaceEmojis != v) { _chatReplaceEmojis = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get chatSuggestEmoji => _chatSuggestEmoji;
  set chatSuggestEmoji(bool v) { if (_chatSuggestEmoji != v) { _chatSuggestEmoji = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get chatSuggestAnimatedEmoji => _chatSuggestAnimatedEmoji;
  set chatSuggestAnimatedEmoji(bool v) { if (_chatSuggestAnimatedEmoji != v) { _chatSuggestAnimatedEmoji = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get chatSuggestStickersByEmoji => _chatSuggestStickersByEmoji;
  set chatSuggestStickersByEmoji(bool v) { if (_chatSuggestStickersByEmoji != v) { _chatSuggestStickersByEmoji = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get chatLoopAnimatedStickers => _chatLoopAnimatedStickers;
  set chatLoopAnimatedStickers(bool v) { if (_chatLoopAnimatedStickers != v) { _chatLoopAnimatedStickers = v; _saveWindowPrefs(); notifyListeners(); } }
  String get chatDoubleClickAction => _chatDoubleClickAction;
  set chatDoubleClickAction(String v) { if (_chatDoubleClickAction != v) { _chatDoubleClickAction = v; _saveWindowPrefs(); notifyListeners(); } }
  String get chatDoubleClickReaction => _chatDoubleClickReaction;
  set chatDoubleClickReaction(String v) { if (_chatDoubleClickReaction != v) { _chatDoubleClickReaction = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get chatShowReplyButton => _chatShowReplyButton;
  set chatShowReplyButton(bool v) { if (_chatShowReplyButton != v) { _chatShowReplyButton = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get chatShowReactionButton => _chatShowReactionButton;
  set chatShowReactionButton(bool v) { if (_chatShowReactionButton != v) { _chatShowReactionButton = v; _saveWindowPrefs(); notifyListeners(); } }
  String get emojiSet => _emojiSet;
  set emojiSet(String v) { if (_emojiSet != v) { _emojiSet = v; _saveWindowPrefs(); notifyListeners(); } }
  /// Font-family fallback chain for the chosen emoji rendering set, applied
  /// app-wide so plain-unicode emoji render from the selected font. Returns
  /// null for 'system' (use the platform default emoji font).
  List<String>? get emojiFontFallback =>
      _emojiSet == 'twemoji' ? const ['Twemoji'] : null;
  bool get useSystemAccent => _useSystemAccent;
  set useSystemAccent(bool v) { if (_useSystemAccent != v) { _useSystemAccent = v; _saveWindowPrefs(); notifyListeners(); } }
  bool get adaptiveForWide => _adaptiveForWide;
  set adaptiveForWide(bool v) { if (_adaptiveForWide != v) { _adaptiveForWide = v; _saveWindowPrefs(); notifyListeners(); } }
  String get customFontFamily => _customFontFamily;
  set customFontFamily(String v) { if (_customFontFamily != v) { _customFontFamily = v; _saveWindowPrefs(); notifyListeners(); } }
  String get customDeviceModel => _customDeviceModel;
  // Pure local-state setter: persists to prefs + notifies. The engine call is
  // owned by the caller (ActiveSessionsScreen._showRenameDialog →
  // engine.setCustomDeviceModel → 'SetCustomDeviceModel' handler), so this
  // setter must NOT fire its own engine call. Previously it called a
  // non-existent 'SetDeviceModel' handler, double-writing on every rename.
  set customDeviceModel(String v) { if (_customDeviceModel != v) { _customDeviceModel = v; _saveWindowPrefs(); notifyListeners(); } }

  bool get recordVideoMessages => _recordVideoMessages;
  set recordVideoMessages(bool value) {
    if (_recordVideoMessages != value) {
      _recordVideoMessages = value;
      _saveWindowPrefs();
      notifyListeners();
    }
  }

  int get powerSavingFlags => _powerSavingFlags;
  // 1:1 with AyuGram PowerSaving::On(flag) = ForceAll() || (Current() & flag)
  // (power_saving.h:38-40). _autoPowerSaving maps to ForceAll(): when enabled,
  // every flag reads as "power saving ON" so all animations are disabled.
  bool powerSaving(int flag) => _autoPowerSaving || (_powerSavingFlags & flag != 0);
  bool get animationsEnabled => !powerSaving(kPowerSavingAnimations);
  bool get stickersPanelAnimEnabled => !powerSaving(kPowerSavingStickersPanel);
  bool get stickersChatAnimEnabled => !powerSaving(kPowerSavingStickersChat);
  bool get emojiReactionsAnimEnabled => !powerSaving(kPowerSavingEmojiReactions);
  bool get chatBackgroundAnimEnabled => !powerSaving(kPowerSavingChatBackground);
  bool get chatEffectsAnimEnabled => !powerSaving(kPowerSavingChatEffects);
  bool get callsAnimEnabled => !powerSaving(kPowerSavingCalls);
  Duration animDuration(Duration normal) =>
      animationsEnabled ? normal : Duration.zero;
  bool get autoPowerSaving => _autoPowerSaving;

  void setAutoPowerSaving(bool v) {
    if (v == _autoPowerSaving) return;
    _autoPowerSaving = v;
    _saveWindowPrefs();
    notifyListeners();
    // 1:1 with AyuGram PowerSaving::SetForceAll (power_saving.cpp:35-50):
    // toggling "auto power saving" forces all power-saving flags on/off at the
    // engine level. Forward force_all so the backend tracks ForceAll() state.
    _engine.callGeneric('__engine', 'SetPowerSaving', {
      'flags': _powerSavingFlags,
      'force_all': _autoPowerSaving,
    }).catchError((_) {});
  }

  void setPowerSaving(int flag, bool on) {
    final updated = on
        ? (_powerSavingFlags | flag)
        : (_powerSavingFlags & ~flag);
    if (updated == _powerSavingFlags) return;
    _powerSavingFlags = updated;
    _saveWindowPrefs();
    notifyListeners();
    _engine.callGeneric('__engine', 'SetPowerSaving', {
      'flags': _powerSavingFlags,
      'force_all': _autoPowerSaving,
    }).catchError((_) {});
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

  Locale get locale {
    final code = _selectedLanguageCode;
    if (code.contains('-')) {
      final parts = code.split('-');
      final lang = parts[0];
      final sub = parts.sublist(1).join('-');
      if (sub.length == 2) return Locale(lang, sub.toUpperCase());
      return Locale.fromSubtags(
        languageCode: lang,
        scriptCode: '${sub[0].toUpperCase()}${sub.substring(1).toLowerCase()}',
      );
    }
    return Locale(code);
  }

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

  bool experimentalFlag(String key, {bool defaultValue = true}) =>
      _experimentalFlags[key] ?? defaultValue;

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

  /// Mirrors AyuGram `Window::Theme::IsNightMode()` (window_theme.cpp:1411): the
  /// app's CURRENT theme background lightness. A forced light/night theme wins;
  /// only `ThemeMode.system` defers to the OS brightness. Used to pick the
  /// day/night variant of a per-chat emoticon theme (data_cloud_themes.cpp:234),
  /// which must follow the app's theme, never the raw OS setting.
  bool get isNightMode => switch (themeMode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => WidgetsBinding
        .instance.platformDispatcher.platformBrightness == Brightness.dark,
  };

  String get themeId => switch (_config.theme) {
    'classic_day' => 'classic_day',
    'day_blue' || 'light' => 'day_blue',
    'night_green' => 'night_green',
    'night' || 'dark' || _ => 'night',
  };

  ConnState connStateFor(String accountId) =>
      _connStates[accountId] ?? ConnState.disconnected;

  int connWaitSecondsFor(String accountId) =>
      _connWaitSeconds[accountId] ?? 0;

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
      _cacheDir = cacheDir;
      // Wire skin-tone preferences into emoji suggestions from startup, so
      // suggestions honor the chosen tone before the emoji panel is ever opened.
      initEmojiSuggestionVariants(configDir);
      Debug.setCrashLogDir('$configDir/crash_reports');
      await _engine.init(
        configDir: configDir,
        cacheDir: cacheDir,
        downloadDir: downloadDir,
        vaultPassword: vaultPassword,
      );

      // Subscribe to events.
      _subs.add(_engine.onAccountList.listen((accounts) {
        _accounts = accounts;
        _rebuildAccountLookup();
        _ensureActiveAccount();
        notifyListeners();
      }));
      _subs.add(_engine.onConnState.listen((event) {
        final newState = ConnState.fromString(event.state);
        final oldState = _connStates[event.accountId];
        _connStates[event.accountId] = newState;
        _connWaitSeconds[event.accountId] = event.waitSeconds;
        if (newState == ConnState.connected && oldState != ConnState.connected) {
          _accounts = _engine.listAccounts();
          _rebuildAccountLookup();
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
      _subs.add(_engine.onDownloadComplete.listen((event) {
        if (event.localPath.isNotEmpty) {
          final name = event.localPath.split('/').last.split('\\').last;
          int size = 0;
          try { size = File(event.localPath).lengthSync(); } catch (e) {
            Debug.log('app_state', 'size = File(event.localPath).lengthSync(): $e');
          }
          addRecentDownload(name, event.localPath, size);
        }
      }));

      // Load initial state.
      _accounts = _engine.listAccounts();
      _rebuildAccountLookup();
      _config = _engine.getConfig();
      _ensureActiveAccount();
      // Load window prefs (native frame toggle) before marking initialized.
      await _loadWindowPrefs();
      // §51.1 Sync ghost mode toggles to engine on startup.
      _syncGhostToEngine();
      // §52.2 Sync anti-recall settings to engine on startup.
      _syncAntiRecallSettings();
      // Re-sync proxy + other in-memory-only engine settings on startup. The Go
      // engine holds these in memory (no disk load), so without re-pushing them
      // after loading prefs they silently revert to engine defaults on every
      // restart — same reason ghost/anti-recall are re-synced above.
      _syncProxyToEngine();
      _resyncEngineSettings();
      WidgetsBinding.instance.addObserver(this);
      if (_systemDarkMode) {
        final brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        updateTheme(brightness == Brightness.dark ? 'night' : 'day_blue');
      }
      if (_nativeWindowFrame && (Platform.isLinux || Platform.isWindows)) {
        try {
          await _windowChannel.invokeMethod('setDecorated', true);
        } catch (e) {
          Debug.log('app_state', 'await _windowChannel.invokeMethod(\'setDecorated\', true): $e');
        }
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
    _rebuildAccountLookup();
    _initialized = true;
    _domainStarted = true;
    notifyListeners();
  }

  void _checkPasscodeAtStartup() {
    try {
      final data = _engine.getPasscodeConfig();
      if ((data['hash'] as String? ?? '').isNotEmpty) {
        _passcodeLocked = true;
      }
    } catch (e) {
      Debug.log('app_state', 'final data = _engine.getPasscodeConfig(): $e');
    }
    // No passcode gate at startup → the domain is started immediately. With a
    // passcode, it stays "not started" until the first successful unlock.
    if (!_passcodeLocked) _domainStarted = true;
    _lastNonIdleTime = DateTime.now().millisecondsSinceEpoch;
    checkAutoLock(_lastNonIdleTime);
  }

  bool get hasLocalPasscode {
    if (_cachedHasPasscode != null) return _cachedHasPasscode!;
    try {
      final data = _engine.getPasscodeConfig();
      _cachedHasPasscode = (data['hash'] as String? ?? '').isNotEmpty;
      return _cachedHasPasscode!;
    } catch (_) {
      _cachedHasPasscode = false;
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
    // First unlock starts the domain (AyuGram's domain.start(passcode)); it stays
    // started across any later auto-lock for the rest of the session.
    _domainStarted = true;
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
    final elapsed = DateTime.now().difference(last).inMilliseconds;
    final waitMs = switch (_passcodeBadTries) {
      3 => 5000,
      4 => 10000,
      5 => 15000,
      6 => 20000,
      7 => 25000,
      _ => 30000,
    };
    return elapsed >= waitMs;
  }

  static String _computePasscodeHash(List<String> args) {
    final salt = args[0];
    final entered = args[1];
    if (salt.isNotEmpty) {
      final saltedInput = utf8.encode(salt + entered);
      var digest = sha256.convert(saltedInput);
      for (var i = 0; i < 99999; i++) {
        digest = sha256.convert(digest.bytes + saltedInput);
      }
      return digest.toString();
    }
    return sha256.convert(utf8.encode(entered)).toString();
  }

  Future<bool> checkPasscode(String entered) async {
    try {
      final data = _engine.getPasscodeConfig();
      final storedHash = data['hash'] as String? ?? '';
      if (storedHash.isEmpty) return false;
      final salt = data['salt'] as String? ?? '';
      final hash = await compute(_computePasscodeHash, [salt, entered]);
      if (hash == storedHash) {
        unlockPasscode();
        return true;
      }
    } catch (e) {
      Debug.log('app_state', 'final data = _engine.getPasscodeConfig(): $e');
    }
    _passcodeBadTries++;
    _passcodeLastTry = DateTime.now();
    return false;
  }

  static const _kAutoLockTimeoutLateMs = 3000;

  int _readAutoLockSeconds() {
    if (_cachedAutoLockSeconds != null) return _cachedAutoLockSeconds!;
    try {
      final data = _engine.getPasscodeConfig();
      _cachedAutoLockSeconds = (data['autoLockSeconds'] as int?) ?? 0;
      return _cachedAutoLockSeconds!;
    } catch (_) {
      _cachedAutoLockSeconds = 0;
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
    _cachedHasPasscode = null;
    _cachedAutoLockSeconds = null;
    _shouldLockAt = 0;
    _autoLockTimer?.cancel();
    checkAutoLock(DateTime.now().millisecondsSinceEpoch);
  }

  /// Switch to a different account. Notifies listeners so the UI rebuilds
  /// with the new account's chats and folders.
  void setActiveAccountId(String accountId) {
    if (_activeAccountId == accountId) return;
    _activeAccountId = accountId;
    _cachedActiveAccount = _accountById[accountId];
    resetEmojiPrefsForAccountSwitch();
    // Re-arm the suggestion skin-tone resolver after the reset so suggestions
    // keep honoring the chosen tone without waiting for the panel to reopen.
    initEmojiSuggestionVariants(_configDir);
    if (!_useGlobalGhostMode) _syncGhostToEngine();
    _autoMigrateGhostToGlobal();
    notifyListeners();
  }

  /// Ensure activeAccountId points to a valid account.
  void _ensureActiveAccount() {
    if (_accounts.isEmpty) {
      _activeAccountId = '';
      _cachedActiveAccount = null;
      return;
    }
    if (_activeAccountId.isNotEmpty && _accountById.containsKey(_activeAccountId)) {
      _cachedActiveAccount = _accountById[_activeAccountId];
      return;
    }
    _activeAccountId = _accounts.first.id;
    _cachedActiveAccount = _accounts.first;
  }

  String addAccount(String platform, {bool testMode = false}) {
    // Spec §3.2: enforce max accounts limit.
    if (!canAddAccount) {
      final limit = maxAccountLimit;
      Debug.log('APP', 'Cannot add account: at limit ($limit)');
      throw StateError('Maximum account limit reached ($limit)');
    }
    Debug.log('APP', 'Adding account: $platform${testMode ? ' (test server)' : ''}');
    try {
      final id = _engine.addAccount(platform, testMode: testMode);
      _accounts = _engine.listAccounts();
      _rebuildAccountLookup();
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
    // Drop the logged-out account's notification state (pending timers, queued
    // waiters, on-screen toasts) before anything else can fire stale.
    onAccountRemoved?.call(accountId);
    _accounts = _engine.listAccounts();
    _rebuildAccountLookup();
    _connStates.remove(accountId);
    _accountOrder.remove(accountId);
    _ensureActiveAccount();
    _saveWindowPrefs();
    removePasscodeIfEmpty();
    notifyListeners();
  }

  void removePasscodeIfEmpty() {
    _cachedHasPasscode = null;
    _cachedAutoLockSeconds = null;
    if (_accounts.isNotEmpty) return;
    if (!hasLocalPasscode) return;
    if (_passcodeLocked) {
      _passcodeLocked = false;
      _passcodeBadTries = 0;
      _passcodeLastTry = null;
    }
    try {
      _engine.clearPasscode();
    } catch (e) {
      Debug.log('app_state', '_engine.clearPasscode(): $e');
    }
    _autoLockTimer?.cancel();
    _shouldLockAt = 0;
  }

  /// Lock-screen "forgot passcode" escape hatch. Mirrors AyuGram's
  /// `Application::logout(nullptr)` → `Domain::resetWithForgottenPasscode`
  /// (core/application.cpp:943-948, main/main_domain.cpp:117-126): the passcode
  /// lock screen passes `account == nullptr` (Core::App().passcodeLocked() is
  /// true), so EVERY account is logged out and the passcode is wiped — a user
  /// who forgot the passcode can always get back in. Removing only the active
  /// account (the old behaviour) left multi-account users locked out forever.
  void resetWithForgottenPasscode() {
    // Snapshot ids first — _engine.removeAccount mutates the account list.
    final ids = _accounts.map((a) => a.id).toList();
    for (final id in ids) {
      try {
        _engine.removeAccount(id);
      } catch (e) {
        Debug.log('app_state', '_engine.removeAccount(id): $e');
      }
      // Drop each logged-out account's notification state before stale timers fire.
      onAccountRemoved?.call(id);
      _connStates.remove(id);
      _accountOrder.remove(id);
    }
    _accounts = _engine.listAccounts();
    _rebuildAccountLookup();
    _ensureActiveAccount();
    _saveWindowPrefs();
    // Forget the passcode unconditionally — this is the escape hatch, so the
    // lock must always lift even if an engine removal left residue (AyuGram
    // clears it via removePasscodeIfEmpty once every account is gone).
    _passcodeLocked = false;
    _passcodeBadTries = 0;
    _passcodeLastTry = null;
    _autoLockTimer?.cancel();
    _shouldLockAt = 0;
    try {
      _engine.clearPasscode();
    } catch (e) {
      Debug.log('app_state', '_engine.clearPasscode(): $e');
    }
    _cachedHasPasscode = null;
    _cachedAutoLockSeconds = null;
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

  void setLivePalette(TelegramPalette palette) {
    _cachedCustomPalette = palette;
    notifyListeners();
  }
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
    // Tell the native runner (GTK on Linux, Win32 on Windows) to add/remove the
    // system window frame.
    if (Platform.isLinux || Platform.isWindows) {
      try {
        await _windowChannel.invokeMethod('setDecorated', value);
      } catch (e) {
        Debug.log('app_state', 'await _windowChannel.invokeMethod(\'setDecorated\', value): $e');
      }
    }
    _saveWindowPrefs();
    notifyListeners();
  }

  String get _windowPrefsPath =>
      _configDir.isEmpty ? '' : '$_configDir/window_prefs.json';

  Future<void> _loadWindowPrefs() async {
    final path = _windowPrefsPath;
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _nativeWindowFrame = data['nativeWindowFrame'] as bool? ?? false;
      _mainMenuAccountsShown = data['mainMenuAccountsShown'] as bool? ?? false;
      _systemDarkMode = data['systemDarkMode'] as bool? ?? false;
      _sendBy = data['sendBy'] as String? ?? 'enter';
      _swipeAction = data['swipeAction'] as String? ?? 'archive';
      _rememberedSendAsDocuments = data['rememberedSendAsDocuments'] as bool?;
      _rememberedGroupFiles = data['rememberedGroupFiles'] as bool?;
      _rememberedSoundNotifyFromTray = data['rememberedSoundNotifyFromTray'] as bool? ?? false;
      _rememberedFlashBounceNotifyFromTray = data['rememberedFlashBounceNotifyFromTray'] as bool? ?? false;
      final savedHashtags = data['recentHashtags'];
      if (savedHashtags is List) {
        _recentHashtags = savedHashtags.map((e) => e.toString()).take(40).toList();
      }
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
      _angleBackendIndex = data['angleBackendIndex'] as int? ?? 0;
      _addToSendToMenu = data['addToSendToMenu'] as bool? ?? false;
      _warnBeforeQuit = data['warnBeforeQuit'] as bool? ?? false;
      _systemTextReplacements = data['systemTextReplacements'] as bool? ?? false;
      _roundDockIcon = data['roundDockIcon'] as bool? ?? false;
      _spellcheckerEnabled = data['spellcheckerEnabled'] as bool? ?? true;
      _spellcheckerAutoDownload = data['spellcheckerAutoDownload'] as bool? ?? true;
      final dicts = data['enabledDictionaries'] as List<dynamic>?;
      if (dicts != null) _enabledDictionaries = dicts.cast<String>().toSet();
      _screenReaderModeDisabled = data['screenReaderModeDisabled'] as bool? ?? false;
      _autoUpdateEnabled = data['autoUpdateEnabled'] as bool? ?? true;
      _installBetaVersions = data['installBetaVersions'] as bool? ?? false;
      _downloadPathMode = data['downloadPathMode'] as int? ?? 0;
      _customDownloadPath = data['customDownloadPath'] as String? ?? '';
      _askDownloadPath = data['askDownloadPath'] as bool? ?? false;
      final nwExts = data['noWarningExtensions'] as List<dynamic>?;
      if (nwExts != null) _noWarningExtensions = nwExts.cast<String>().toSet();
      _proxyMode = data['proxyMode'] as int? ?? 0;
      _selectedProxyType = data['selectedProxyType'] as String? ?? '';
      _proxyIpv6 = data['proxyIpv6'] as bool? ?? false;
      _proxyForCalls = data['proxyForCalls'] as bool? ?? false;
      _callSameDevice = data['callSameDevice'] as bool? ?? false;
      _proxyRotationEnabled = data['proxyRotationEnabled'] as bool? ?? false;
      // Default 10s — core_settings_proxy.h:25 (kDefaultProxyRotationTimeout).
      _proxyRotationTimeout = data['proxyRotationTimeout'] as int? ?? 10;
      _proxyCheckIpWarningShown =
          data['proxyCheckIpWarningShown'] as bool? ?? false;
      final pList = data['proxyList'] as List<dynamic>?;
      if (pList != null) _proxyList = pList.cast<Map<String, dynamic>>();
      final selProxy = data['selectedProxyData'] as Map<String, dynamic>?;
      if (selProxy != null) _selectedProxyData = selProxy;
      final adSettings = data['autoDownloadSettings'] as Map<String, dynamic>?;
      if (adSettings != null) {
        _autoDownloadSettings = adSettings.map((k, v) => MapEntry(k, (v as Map<String, dynamic>)));
      }
      _localStorageTotalLimit = data['localStorageTotalLimit'] as int? ?? 8192;
      _localStorageMediaLimit = data['localStorageMediaLimit'] as int? ?? 4096;
      _localStorageTimeLimit = data['localStorageTimeLimit'] as int? ?? 15;
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
      // §25.15 AyuGram prefs. AyuGram validate() clamps every out-of-range
      // persisted value on load (ayu_settings.cpp:481-533); replicated here so a
      // corrupt / hand-edited / version-downgraded prefs value can't flow into
      // rendering. bubbleRadius → [0,16] (ayu_settings.cpp:518).
      _bubbleRadius = ((data['bubbleRadius'] as int?) ?? 16).clamp(0, 16);
      _removeTail = data['removeTail'] as bool? ?? false;
      _materialSwitches = data['materialSwitches'] as bool? ?? true;
      final oldAvatarRadius = data['avatarCornerRadius'] as int?;
      // avatarCorners → [0,kMaxAvatarCorners=23] (ayu_settings.cpp:520). The
      // direct key was previously read raw (only the legacy-migration branch
      // clamped), so an out-of-range value could reach the userpic renderer.
      _avatarCorners = ((data['avatarCorners'] as int?) ??
              (oldAvatarRadius != null ? (oldAvatarRadius * 23 / 50).round() : 23))
          .clamp(0, 23);
      _singleCornerRadius = data['singleCornerRadius'] as bool? ?? false;
      _disableCustomBackgrounds = data['disableCustomBackgrounds'] as bool? ?? false;
      _hidePremiumStatuses = data['hidePremiumStatuses'] as bool? ?? false;
      _monoFont = data['monoFont'] as String? ?? '';
      _hideNotificationCounters = data['hideNotificationCounters'] as bool? ?? false;
      _hideAllChatsFolder = data['hideAllChatsFolder'] as bool? ?? false;
      _hideNotificationBadge = data['hideNotificationBadge'] as bool? ?? false;
      _photoEditorHintCount = data['photoEditorHintCount'] as int? ?? 0;
      _notifDesktopNotify = data['notifDesktopNotify'] as bool? ?? true;
      _notifFlashBounce = data['notifFlashBounce'] as bool? ?? true;
      _notifAllowSound = data['notifAllowSound'] as bool? ?? true;
      _notifVolume = data['notifVolume'] as int? ?? 100;
      _ringtoneVolumes
        ..clear()
        ..addAll(_decodeVolumeMap(data['ringtoneVolumes']));
      _notifTypeVolumes
        ..clear()
        ..addAll(_decodeVolumeMap(data['notifTypeVolumes']));
      _mutePeriods
        ..clear()
        ..addAll(((data['mutePeriods'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .where((e) => e > 0));
      _chatSoundDocId
        ..clear()
        ..addAll(_decodeIntMap(data['chatSoundDocId']));
      _chatSoundPath
        ..clear()
        ..addAll(_decodeStringMap(data['chatSoundPath']));
      _notifPreviewName = data['notifPreviewName'] as bool? ?? true;
      _notifPreviewText = data['notifPreviewText'] as bool? ?? true;
      _notifPrivateChats = data['notifPrivateChats'] as bool? ?? true;
      _notifGroups = data['notifGroups'] as bool? ?? true;
      _notifChannels = data['notifChannels'] as bool? ?? true;
      _notifReactions = data['notifReactions'] as bool? ?? true;
      _notifUseNative = data['notifUseNative'] as bool? ?? true;
      _notifSkipToastsInFocus = data['notifSkipToastsInFocus'] as bool? ?? false;
      _notifDisplayIndex = data['notifDisplayIndex'] as int? ?? 0;
      _notifCorner = data['notifCorner'] as int? ?? 2;
      _notifCount = data['notifCount'] as int? ?? 3;
      _notifContactJoinedTelegram = data['notifContactJoinedTelegram'] as bool? ?? true;
      _notifPinnedMessages = data['notifPinnedMessages'] as bool? ?? true;
      _notifAcceptCallsOnDevice = data['notifAcceptCallsOnDevice'] as bool? ?? true;
      _callOutputDevice = data['callOutputDevice'] as String? ?? 'Default';
      _callInputDevice = data['callInputDevice'] as String? ?? 'Default';
      _callCameraDevice = data['callCameraDevice'] as String? ?? 'Default';
      _callUseSameDevices = data['callUseSameDevices'] as bool? ?? true;
      _callSpecificOutputDevice = data['callSpecificOutputDevice'] as String? ?? '';
      _callSpecificInputDevice = data['callSpecificInputDevice'] as String? ?? '';
      _callNoiseSuppression = data['callNoiseSuppression'] as bool? ?? true;
      _callPushToTalk = data['callPushToTalk'] as bool? ?? false;
      _callPttShortcut = data['callPttShortcut'] as String? ?? 'Space';
      _callPttDelay = (data['callPttDelay'] as num?)?.toInt() ?? 200;
      _notifAllAccountsNotify = data['notifAllAccountsNotify'] as bool? ?? true;
      _notifIncludeMutedChats = data['notifIncludeMutedChats'] as bool? ?? true;
      _notifIncludeMutedInFolders = data['notifIncludeMutedInFolders'] as bool? ?? true;
      _notifCountUnreadMessages = data['notifCountUnreadMessages'] as bool? ?? true;
      _chatLargeEmoji = data['chatLargeEmoji'] as bool? ?? true;
      _chatReplaceEmojis = data['chatReplaceEmojis'] as bool? ?? true;
      _chatSuggestEmoji = data['chatSuggestEmoji'] as bool? ?? true;
      _chatSuggestAnimatedEmoji = data['chatSuggestAnimatedEmoji'] as bool? ?? true;
      _chatSuggestStickersByEmoji = data['chatSuggestStickersByEmoji'] as bool? ?? true;
      _chatLoopAnimatedStickers = data['chatLoopAnimatedStickers'] as bool? ?? true;
      _chatDoubleClickAction = data['chatDoubleClickAction'] as String? ?? 'reply';
      _chatDoubleClickReaction = data['chatDoubleClickReaction'] as String? ?? '❤️';
      _chatShowReplyButton = data['chatShowReplyButton'] as bool? ?? true;
      _chatShowReactionButton = data['chatShowReactionButton'] as bool? ?? true;
      _emojiSet = data['emojiSet'] as String? ?? 'system';
      _useSystemAccent = data['useSystemAccent'] as bool? ?? false;
      _adaptiveForWide = data['adaptiveForWide'] as bool? ?? true;
      _customFontFamily = data['customFontFamily'] as String? ?? 'Inter';
      _customDeviceModel = data['customDeviceModel'] as String? ?? '';
      _appIcon = data['appIcon'] as String? ?? '';
      _replaceBottomInfoWithIcons = data['replaceBottomInfoWithIcons'] as bool? ?? true;
      _adaptiveCoverColor = data['adaptiveCoverColor'] as bool? ?? true;
      _simpleQuotesAndReplies = data['simpleQuotesAndReplies'] as bool? ?? false;
      _semiTransparentDeleted = data['semiTransparentDeleted'] as bool? ?? false;
      _wideMultiplier = ((data['wideMultiplier'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 4.0);
      _uiScalePercent = (data['uiScalePercent'] as num?)?.toDouble() ?? 100.0;
      _ivZoom = (data['ivZoom'] as num?)?.toDouble() ?? 1.0;
      _showNightModeToggleInDrawer = data['showNightModeToggleInDrawer'] as bool? ?? true;
      _archiveInMainMenu = data['archiveInMainMenu'] as bool? ?? false;
      _archiveCollapsed = data['archiveCollapsed'] as bool? ?? false;
      // §54.8: Per-item drawer visibility.
      _showMyProfileInDrawer = data['showMyProfileInDrawer'] as bool? ?? true;
      _showBotsInDrawer = data['showBotsInDrawer'] as bool? ?? true;
      _showNewGroupInDrawer = data['showNewGroupInDrawer'] as bool? ?? true;
      _showNewChannelInDrawer = data['showNewChannelInDrawer'] as bool? ?? true;
      _showContactsInDrawer = data['showContactsInDrawer'] as bool? ?? true;
      _showCallsInDrawer = data['showCallsInDrawer'] as bool? ?? true;
      _showSavedMessagesInDrawer = data['showSavedMessagesInDrawer'] as bool? ?? true;
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
      // Context-menu visibility enums → [0,2] (ayu_settings.cpp:506-514
      // validateEnum). Read raw before; clamp now so a corrupt value can't slip
      // through to the menu-visibility switch.
      _showViewsPanelInContextMenu = ((data['showViewsPanelInContextMenu'] as int?) ?? 1).clamp(0, 2);
      _showRepeatMessageInContextMenu = ((data['showRepeatMessageInContextMenu'] as int?) ?? 0).clamp(0, 2);
      _showReactionsPanelInContextMenu = ((data['showReactionsPanelInContextMenu'] as int?) ?? 1).clamp(0, 2);
      _showHideMessageInContextMenu = ((data['showHideMessageInContextMenu'] as int?) ?? 0).clamp(0, 2);
      _showUserMessagesInContextMenu = ((data['showUserMessagesInContextMenu'] as int?) ?? 2).clamp(0, 2);
      _showMessageDetailsInContextMenu = ((data['showMessageDetailsInContextMenu'] as int?) ?? 2).clamp(0, 2);
      _showAddFilterInContextMenu = ((data['showAddFilterInContextMenu'] as int?) ?? 1).clamp(0, 2);
      _showMessageSeconds = data['showMessageSeconds'] as bool? ?? false;
      _voicePlaybackSpeed =
          ((data['voicePlaybackSpeed'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.5).toDouble();
      _audioPlaybackSpeed =
          ((data['audioPlaybackSpeed'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.5).toDouble();
      _playerRepeatMode = (data['playerRepeatMode'] as int? ?? 0).clamp(0, 2);
      _playerOrderMode = (data['playerOrderMode'] as int? ?? 0).clamp(0, 2);
      _disableAutoplayNext = data['disableAutoplayNext'] as bool? ?? false;
      _songVolume =
          ((data['songVolume'] as num?)?.toDouble() ?? 0.9).clamp(0.0, 1.0).toDouble();
      _rememberedSongVolume =
          ((data['rememberedSongVolume'] as num?)?.toDouble() ?? 0.9).clamp(0.0, 1.0).toDouble();
      _videoVolume =
          ((data['videoVolume'] as num?)?.toDouble() ?? 0.9).clamp(0.0, 1.0).toDouble();
      // §54.14: AyuGram General settings.
      final rawTp = data['translationProvider'];
      if (rawTp is String) {
        _translationProvider = const {'telegram': 0, 'google': 1, 'yandex': 2, 'native': 3}[rawTp] ?? 0;
      } else {
        // translationProvider enum → [0,3] (ayu_settings.cpp:516 validateEnum
        // with max=3: Telegram/Google/Yandex/Native).
        _translationProvider = ((rawTp as int?) ?? 0).clamp(0, 3);
      }
      // AyuGram validate() resets Native→default(Telegram) when the platform
      // provider is unavailable (ayu_settings.cpp:511-515).
      if (_translationProvider == 3 && !nativeTranslateAvailable) {
        _translationProvider = 0;
      }
      _disableStories = data['disableStories'] as bool? ?? false;
      _disableOpenLinkWarning = data['disableOpenLinkWarning'] as bool? ?? false;
      _collapseSimilarChannels = data['collapseSimilarChannels'] as bool? ?? true;
      _hideSimilarChannels = data['hideSimilarChannels'] as bool? ?? false;
      _disableNotifyDelay = data['disableNotifyDelay'] as bool? ?? false;
      _filterZalgo = data['filterZalgo'] as bool? ?? false;
      gFilterZalgo = _filterZalgo; // seed the global at startup

      _improveLinkPreviews = data['improveLinkPreviews'] as bool? ?? false;
      // showPeerId → [0,2] (ayu_settings.cpp:505 validateEnum).
      _showPeerId = ((data['showPeerId'] as int?) ?? 2).clamp(0, 2);
      _spoofWebviewAsAndroid = data['spoofWebviewAsAndroid'] as bool? ?? false;
      _increaseWebviewHeight = data['increaseWebviewHeight'] as bool? ?? false;
      _increaseWebviewWidth = data['increaseWebviewWidth'] as bool? ?? false;
      _stickerConfirmation = data['stickerConfirmation'] as bool? ?? false;
      _gifConfirmation = data['gifConfirmation'] as bool? ?? false;
      _voiceConfirmation = data['voiceConfirmation'] as bool? ?? false;
      _showIpInWebRtcCalls = data['showIpInWebRtcCalls'] as bool? ?? false;
      // §54.9: Message field button toggles.
      _showAttachButton = data['showAttachButton'] as bool? ?? true;
      _showCommandsButton = data['showCommandsButton'] as bool? ?? true;
      _showAutoDeleteButton = data['showAutoDeleteButton'] as bool? ?? true;
      _showEmojiButton = data['showEmojiButton'] as bool? ?? true;
      _showMicrophoneButton = data['showMicrophoneButton'] as bool? ?? true;
      _showGiftButton = data['showGiftButton'] as bool? ?? true;
      _showAiEditorButton = data['showAiEditorButton'] as bool? ?? true;
      _showAttachPopup = data['showAttachPopup'] as bool? ?? true;
      _showEmojiPopup = data['showEmojiPopup'] as bool? ?? true;
      // §54.11: Additional chat settings.
      _showOnlyAddedEmojisAndStickers = data['showOnlyAddedEmojisAndStickers'] as bool? ?? false;
      _showChannelReactions = data['showChannelReactions'] as bool? ?? true;
      _showGroupReactions = data['showGroupReactions'] as bool? ?? true;
      _showPrivateChatReactions = data['showPrivateChatReactions'] as bool? ?? true;
      // Clamp on load to AyuGram's valid range (validateRange 1..200,
      // ayu_settings.cpp:519). setRecentStickersCount also clamps on set, so a
      // stale/hand-edited 0 (or >200) from an older build is corrected here.
      _recentStickersCount =
          ((data['recentStickersCount'] as int?) ?? 100).clamp(1, 200);
      // channelBottomButton → [0,2] (ayu_settings.cpp:506 validateEnum).
      _channelBottomButton = ((data['channelBottomButton'] as int?) ?? 2).clamp(0, 2);
      _quickAdminShortcuts = data['quickAdminShortcuts'] as bool? ?? true;
      _showMessageShot = data['showMessageShot'] as bool? ?? true;
      final messageShotData =
          data['messageShotSettings'] as Map<String, dynamic>?;
      _messageShotSettings = messageShotData != null
          ? MessageShotSettings.fromJson(messageShotData)
          : MessageShotSettings();
      // embeddedThemeType valid only as -1 (none) or 0..3 (DayBlue..NightGreen)
      // — ayu_settings.cpp:525-531. On a corrupt value reset both the type and
      // its accent color to defaults, matching validate().
      final et = _messageShotSettings.embeddedThemeType;
      if (et != -1 && (et < 0 || et > 3)) {
        _messageShotSettings.embeddedThemeType = -1;
        _messageShotSettings.embeddedThemeAccentColor = 0;
      }
      _hideFastShare = data['hideFastShare'] as bool? ?? false;
      _saveDeletedMessages = data['saveDeletedMessages'] as bool? ?? true;
      _saveMessagesHistory = data['saveMessagesHistory'] as bool? ?? true;
      _saveForBots = data['saveForBots'] as bool? ?? false;
      _deletedMark = data['deletedMark'] as String? ?? '\u{1F9F9}';
      _editedMark = data['editedMark'] as String? ?? '';
      _replaceMarksWithIcons = data['replaceMarksWithIcons'] as bool? ?? true;
      _localPremium = data['localPremium'] as bool? ?? false;
      _disableAds = data['disableAds'] as bool? ?? true;
      _deleteOnlyForYouRemembered = data['deleteOnlyForYouRemembered'] as bool? ?? false;
      _crashReporting = data['crashReporting'] as bool? ?? true;
      Debug.crashReportingEnabled = _crashReporting;
      if (_configDir.isNotEmpty) {
        Debug.setCrashLogDir('$_configDir/crash_reports');
      }
      _filtersEnabled = data['filtersEnabled'] as bool? ?? false;
      _filtersEnabledInChats = data['filtersEnabledInChats'] as bool? ?? false;
      _hideFromBlocked = data['hideFromBlocked'] as bool? ?? false;
      final rawShadowBan = data['shadowBanIds'] as List<dynamic>?;
      if (rawShadowBan != null) {
        _shadowBanIds = rawShadowBan.map((e) => (e as num).toInt()).toSet();
      }
      final rawBlocked = data['blockedIds'] as List<dynamic>?;
      if (rawBlocked != null) {
        _blockedIds = rawBlocked.map((e) => (e as num).toInt()).toSet();
      }
      final rawExcl = data['readExclusions'] as Map<String, dynamic>?;
      if (rawExcl != null) {
        _readExclusions = rawExcl.map((k, v) => MapEntry(k, (v as int?) ?? 0));
      }
      final rawTypingExcl = data['typingExclusions'] as Map<String, dynamic>?;
      if (rawTypingExcl != null) {
        _typingExclusions = rawTypingExcl.map((k, v) => MapEntry(k, (v as int?) ?? 0));
      }
      filterEngine.loadFromJson(data);
      _loadWallpaper(data);
      _loadCustomThemeFromCache();
      noHwAccelVideo = !_hardwareAccelVideo;
    } catch (e) {
      Debug.log('app_state', 'final file = File(path): $e');
    }
  }

  void _saveWindowPrefs() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), _flushWindowPrefs);
  }

  void _flushWindowPrefsSync() {
    final path = _windowPrefsPath;
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(jsonEncode(_buildPrefsMap()));
    } catch (e) {
      Debug.log('app_state', 'File(path).writeAsStringSync(jsonEncode(_buildPrefsMap())): $e');
    }
  }

  Future<void> _flushWindowPrefs() async {
    final path = _windowPrefsPath;
    if (path.isEmpty) return;
    try {
      await File(path).writeAsString(jsonEncode(_buildPrefsMap()));
    } catch (e) {
      Debug.log('app_state', 'await File(path).writeAsString(jsonEncode(_buildPrefsMap())): $e');
    }
  }

  Map<String, dynamic> _buildPrefsMap() => {
        'nativeWindowFrame': _nativeWindowFrame,
        'mainMenuAccountsShown': _mainMenuAccountsShown,
        'systemDarkMode': _systemDarkMode,
        'sendBy': _sendBy,
        'swipeAction': _swipeAction,
        if (_rememberedSendAsDocuments != null) 'rememberedSendAsDocuments': _rememberedSendAsDocuments,
        if (_rememberedGroupFiles != null) 'rememberedGroupFiles': _rememberedGroupFiles,
        'rememberedSoundNotifyFromTray': _rememberedSoundNotifyFromTray,
        if (_recentHashtags.isNotEmpty) 'recentHashtags': _recentHashtags,
        'rememberedFlashBounceNotifyFromTray': _rememberedFlashBounceNotifyFromTray,
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
        'angleBackendIndex': _angleBackendIndex,
        'addToSendToMenu': _addToSendToMenu,
        'warnBeforeQuit': _warnBeforeQuit,
        'systemTextReplacements': _systemTextReplacements,
        'roundDockIcon': _roundDockIcon,
        'spellcheckerEnabled': _spellcheckerEnabled,
        'spellcheckerAutoDownload': _spellcheckerAutoDownload,
        'enabledDictionaries': _enabledDictionaries.toList(),
        'screenReaderModeDisabled': _screenReaderModeDisabled,
        'autoUpdateEnabled': _autoUpdateEnabled,
        'installBetaVersions': _installBetaVersions,
        'downloadPathMode': _downloadPathMode,
        'customDownloadPath': _customDownloadPath,
        'askDownloadPath': _askDownloadPath,
        'noWarningExtensions': _noWarningExtensions.toList(),
        'proxyMode': _proxyMode,
        'selectedProxyType': _selectedProxyType,
        'proxyIpv6': _proxyIpv6,
        'proxyForCalls': _proxyForCalls,
        'callSameDevice': _callSameDevice,
        'proxyRotationEnabled': _proxyRotationEnabled,
        'proxyRotationTimeout': _proxyRotationTimeout,
        'proxyCheckIpWarningShown': _proxyCheckIpWarningShown,
        'proxyList': _proxyList,
        'selectedProxyData': _selectedProxyData,
        'autoDownloadSettings': _autoDownloadSettings,
        'localStorageTotalLimit': _localStorageTotalLimit,
        'localStorageMediaLimit': _localStorageMediaLimit,
        'localStorageTimeLimit': _localStorageTimeLimit,
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
        'hidePremiumStatuses': _hidePremiumStatuses,
        'monoFont': _monoFont,
        'hideNotificationCounters': _hideNotificationCounters,
        'hideAllChatsFolder': _hideAllChatsFolder,
        'hideNotificationBadge': _hideNotificationBadge,
        'photoEditorHintCount': _photoEditorHintCount,
        'notifDesktopNotify': _notifDesktopNotify,
        'notifFlashBounce': _notifFlashBounce,
        'notifAllowSound': _notifAllowSound,
        'notifVolume': _notifVolume,
        'ringtoneVolumes': _ringtoneVolumes,
        'mutePeriods': _mutePeriods,
        'notifTypeVolumes': _notifTypeVolumes,
        'chatSoundDocId': _chatSoundDocId,
        'chatSoundPath': _chatSoundPath,
        'notifPreviewName': _notifPreviewName,
        'notifPreviewText': _notifPreviewText,
        'notifPrivateChats': _notifPrivateChats,
        'notifGroups': _notifGroups,
        'notifChannels': _notifChannels,
        'notifReactions': _notifReactions,
        'notifUseNative': _notifUseNative,
        'notifSkipToastsInFocus': _notifSkipToastsInFocus,
        'notifDisplayIndex': _notifDisplayIndex,
        'notifCorner': _notifCorner,
        'notifCount': _notifCount,
        'notifContactJoinedTelegram': _notifContactJoinedTelegram,
        'notifPinnedMessages': _notifPinnedMessages,
        'notifAcceptCallsOnDevice': _notifAcceptCallsOnDevice,
        'callOutputDevice': _callOutputDevice,
        'callInputDevice': _callInputDevice,
        'callCameraDevice': _callCameraDevice,
        'callUseSameDevices': _callUseSameDevices,
        'callSpecificOutputDevice': _callSpecificOutputDevice,
        'callSpecificInputDevice': _callSpecificInputDevice,
        'callNoiseSuppression': _callNoiseSuppression,
        'callPushToTalk': _callPushToTalk,
        'callPttShortcut': _callPttShortcut,
        'callPttDelay': _callPttDelay,
        'notifAllAccountsNotify': _notifAllAccountsNotify,
        'notifIncludeMutedChats': _notifIncludeMutedChats,
        'notifIncludeMutedInFolders': _notifIncludeMutedInFolders,
        'notifCountUnreadMessages': _notifCountUnreadMessages,
        'chatLargeEmoji': _chatLargeEmoji,
        'chatReplaceEmojis': _chatReplaceEmojis,
        'chatSuggestEmoji': _chatSuggestEmoji,
        'chatSuggestAnimatedEmoji': _chatSuggestAnimatedEmoji,
        'chatSuggestStickersByEmoji': _chatSuggestStickersByEmoji,
        'chatLoopAnimatedStickers': _chatLoopAnimatedStickers,
        'chatDoubleClickAction': _chatDoubleClickAction,
        'chatDoubleClickReaction': _chatDoubleClickReaction,
        'chatShowReplyButton': _chatShowReplyButton,
        'chatShowReactionButton': _chatShowReactionButton,
        'emojiSet': _emojiSet,
        'useSystemAccent': _useSystemAccent,
        'adaptiveForWide': _adaptiveForWide,
        'customFontFamily': _customFontFamily,
        'customDeviceModel': _customDeviceModel,
        'appIcon': _appIcon,
        'replaceBottomInfoWithIcons': _replaceBottomInfoWithIcons,
        'adaptiveCoverColor': _adaptiveCoverColor,
        'simpleQuotesAndReplies': _simpleQuotesAndReplies,
        'semiTransparentDeleted': _semiTransparentDeleted,
        'wideMultiplier': _wideMultiplier,
        'uiScalePercent': _uiScalePercent,
        'ivZoom': _ivZoom,
        'showNightModeToggleInDrawer': _showNightModeToggleInDrawer,
        'archiveInMainMenu': _archiveInMainMenu,
        'archiveCollapsed': _archiveCollapsed,
        'showMyProfileInDrawer': _showMyProfileInDrawer,
        'showBotsInDrawer': _showBotsInDrawer,
        'showNewGroupInDrawer': _showNewGroupInDrawer,
        'showNewChannelInDrawer': _showNewChannelInDrawer,
        'showContactsInDrawer': _showContactsInDrawer,
        'showCallsInDrawer': _showCallsInDrawer,
        'showSavedMessagesInDrawer': _showSavedMessagesInDrawer,
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
        'voicePlaybackSpeed': _voicePlaybackSpeed,
        'audioPlaybackSpeed': _audioPlaybackSpeed,
        'playerRepeatMode': _playerRepeatMode,
        'playerOrderMode': _playerOrderMode,
        'disableAutoplayNext': _disableAutoplayNext,
        'songVolume': _songVolume,
        'rememberedSongVolume': _rememberedSongVolume,
        'videoVolume': _videoVolume,
        'translationProvider': const ['telegram', 'google', 'yandex', 'native'][_translationProvider.clamp(0, 3)],
        'disableStories': _disableStories,
        'disableOpenLinkWarning': _disableOpenLinkWarning,
        'collapseSimilarChannels': _collapseSimilarChannels,
        'hideSimilarChannels': _hideSimilarChannels,
        'disableNotifyDelay': _disableNotifyDelay,
        'filterZalgo': _filterZalgo,
        'improveLinkPreviews': _improveLinkPreviews,
        'showPeerId': _showPeerId,
        'spoofWebviewAsAndroid': _spoofWebviewAsAndroid,
        'increaseWebviewHeight': _increaseWebviewHeight,
        'increaseWebviewWidth': _increaseWebviewWidth,
        'stickerConfirmation': _stickerConfirmation,
        'gifConfirmation': _gifConfirmation,
        'voiceConfirmation': _voiceConfirmation,
        'showIpInWebRtcCalls': _showIpInWebRtcCalls,
        'showAttachButton': _showAttachButton,
        'showCommandsButton': _showCommandsButton,
        'showAutoDeleteButton': _showAutoDeleteButton,
        'showEmojiButton': _showEmojiButton,
        'showMicrophoneButton': _showMicrophoneButton,
        'showGiftButton': _showGiftButton,
        'showAiEditorButton': _showAiEditorButton,
        'showAttachPopup': _showAttachPopup,
        'showEmojiPopup': _showEmojiPopup,
        'showOnlyAddedEmojisAndStickers': _showOnlyAddedEmojisAndStickers,
        'showChannelReactions': _showChannelReactions,
        'showGroupReactions': _showGroupReactions,
        'showPrivateChatReactions': _showPrivateChatReactions,
        'recentStickersCount': _recentStickersCount,
        'channelBottomButton': _channelBottomButton,
        'quickAdminShortcuts': _quickAdminShortcuts,
        'showMessageShot': _showMessageShot,
        'messageShotSettings': _messageShotSettings.toJson(),
        'hideFastShare': _hideFastShare,
        'saveDeletedMessages': _saveDeletedMessages,
        'saveMessagesHistory': _saveMessagesHistory,
        'saveForBots': _saveForBots,
        'deletedMark': _deletedMark,
        'editedMark': _editedMark,
        'replaceMarksWithIcons': _replaceMarksWithIcons,
        'localPremium': _localPremium,
        'disableAds': _disableAds,
        'deleteOnlyForYouRemembered': _deleteOnlyForYouRemembered,
        'crashReporting': _crashReporting,
        'filtersEnabled': _filtersEnabled,
        'filtersEnabledInChats': _filtersEnabledInChats,
        'hideFromBlocked': _hideFromBlocked,
        'shadowBanIds': _shadowBanIds.toList(),
        'blockedIds': _blockedIds.toList(),
        ...filterEngine.toJson(),
        'readExclusions': _readExclusions,
        'typingExclusions': _typingExclusions,
        'wallpaperType': _wallpaper.type.index,
        'wallpaperColors': _wallpaper.backgroundColors
            .map((c) => (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0'))
            .toList(),
        'wallpaperIntensity': _wallpaper.patternIntensity,
        'wallpaperRotation': _wallpaper.gradientRotation,
        'wallpaperBlurred': _wallpaper.blurred,
        'wallpaperTiled': _wallpaper.tiled,
      };

  void _saveWallpaper() {
    _saveWindowPrefs();
    if (_wallpaper.imageBytes != null && _configDir.isNotEmpty) {
      try {
        File('$_configDir/wallpaper.dat').writeAsBytesSync(_wallpaper.imageBytes!);
      } catch (e) {
        Debug.log('app_state', 'File(\'\$_configDir/wallpaper.dat\').writeAsBytesSync(_wallp...: $e');
      }
    } else if (_wallpaper.patternBytes != null && _configDir.isNotEmpty) {
      try {
        File('$_configDir/wallpaper_pattern.dat').writeAsBytesSync(_wallpaper.patternBytes!);
      } catch (e) {
        Debug.log('app_state', 'File(\'\$_configDir/wallpaper_pattern.dat\').writeAsBytesSyn...: $e');
      }
    }
  }

  void _loadWallpaper(Map<String, dynamic> data) {
    final typeIdx = data['wallpaperType'] as int? ?? 0;
    final type = WallpaperType.values.elementAtOrNull(typeIdx) ?? WallpaperType.solid;
    final colorHexes = (data['wallpaperColors'] as List<dynamic>?)?.cast<String>() ?? [];
    final intensity = data['wallpaperIntensity'] as int? ?? 50;
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

    if (type == WallpaperType.pattern && patternBytes != null) {
      // Collectible-gift pattern documents embed a `<g id="GiftPatterns">`
      // cut-out group whose rects define the gift-symbol overlay placements.
      // AyuGram re-parses these from the pattern bytes on every background
      // prepare (ReadBackgroundImage findGiftSymbols=true → ParseGiftSymbols,
      // chat_theme.cpp:1084-1099) — they are never persisted separately. Route
      // reload-from-prefs through fromPattern (exactly like the live apply path,
      // message_bubble.dart:9433) so giftSymbols are re-parsed; the bare
      // constructor leaves them empty, which makes the rotated gift overlay +
      // center-skip layout vanish after a restart until the wallpaper is
      // re-applied. No giftSymbolFrame is passed (matching the apply path) — the
      // frame is derived from the document SVG itself at decode time.
      _wallpaper = WallpaperData.fromPattern(
        patternBytes: patternBytes,
        backgroundColors: colors,
        intensity: intensity,
        rotation: rotation,
      );
    } else {
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
    // Kick the off-thread average-colour computation for an image wallpaper
    // restored from prefs, so the service colours adapt once it lands (see
    // [_ensureWallpaperAverageColor]).
    _ensureWallpaperAverageColor();
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
      Debug.log('app_state', 'final f = File(cmdFilePath): $e');
    }
  }

  void flushSettingsSync() {
    _saveDebounceTimer?.cancel();
    _flushWindowPrefsSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cmdPollTimer?.cancel();
    _autoLockTimer?.cancel();
    _streamerModeController.close();
    if (_saveDebounceTimer?.isActive ?? false) {
      _saveDebounceTimer!.cancel();
      _flushWindowPrefsSync();
    }
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
