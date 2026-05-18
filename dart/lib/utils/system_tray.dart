import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'debug.dart';

/// Manages the system tray icon via a native MethodChannel.
///
/// On Linux the tray is implemented via libayatana-appindicator in the
/// C++ runner.  On other platforms the channel responds with `isAvailable`
/// = false and all calls are silently ignored.
class SystemTray {
  static const _channel = MethodChannel('com.uniclient.app/tray');
  static const _kMaxAccountNameLength = 30;
  static const _kEllipsis = '…';

  /// Global hook invoked by `Ctrl+W` (Telegram Desktop spec §24.4
  /// `close_telegram`). Wired to `SystemTray.hideWindow` after `init()`.
  /// No-op when the native tray is unavailable.
  static Future<void> Function()? hideWindowRequest;

  /// Global hook invoked by `Ctrl+M` (Telegram Desktop spec §24.4
  /// `minimize_telegram`). Wired to `SystemTray.minimizeWindow` after
  /// `init()`. Works on any platform that implements the native channel;
  /// unlike hideWindow, minimize does not depend on appindicator being
  /// present (it just iconifies the existing GTK window).
  static Future<void> Function()? minimizeWindowRequest;

  /// Global hook invoked by `Ctrl+Q` (Telegram Desktop spec §24.4
  /// `quit_telegram`). Wired to `SystemTray.quitApp` after `init()`.
  /// Fully quits the application — does NOT hide to tray. Works
  /// regardless of tray availability.
  static Future<void> Function()? quitAppRequest;

  bool _available = false;
  bool _iconCreated = false;
  int _lastUnread = -1;
  bool _windowVisible = true;
  bool _windowActive = true;
  int _lastTrayClickTime = 0;

  /// Whether the native tray icon is active.
  bool get isAvailable => _available && _iconCreated;

  /// Whether the native platform supports tray icons at all.
  bool get platformSupported => _available;

  /// Whether the main window is currently visible (not hidden to tray).
  bool get windowVisible => _windowVisible;

  /// Callback invoked when the user chooses "Quit" from the tray menu.
  void Function()? onQuit;

  /// Callback invoked when the window is hidden via the close button
  /// (minimized to tray).
  void Function()? onWindowHidden;

  /// Callback invoked when the window is shown from the tray (restore).
  /// AyuGram's showFromTrayRequests() drives post-show actions:
  /// updateGlobalMenu(), activate(), unreadCounterChangedHook(),
  /// updateIconCounters().
  void Function()? onWindowShown;

  /// Callback invoked when the user clicks the Streamer Mode tray item.
  void Function()? onStreamerToggle;

  /// Callback invoked when the user clicks the Ghost Mode tray item.
  void Function()? onGhostToggle;

  /// Callback invoked when the user clicks the Notifications tray item.
  void Function()? onNotificationsToggle;

  /// Callback invoked when the user switches accounts from the tray menu.
  /// [ctrlPressed] mirrors AyuGram's `base::IsCtrlPressed()` check —
  /// when true, the caller should open a separate window for that account
  /// instead of switching the active account in the current window.
  void Function(String accountId, {bool ctrlPressed})? onAccountSwitch;

  /// Initialize the tray.  Call once after the engine is running.
  /// [showTrayIcon] controls whether the tray icon is created (false =
  /// WorkMode::WindowOnly). No-op on Flutter Web — native tray is
  /// desktop-only (§13.5).
  Future<void> init({bool showTrayIcon = true}) async {
    if (kIsWeb) return;

    _channel.setMethodCallHandler(_handleNativeCall);

    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      _available = result ?? false;
      Debug.log('TRAY', 'available=$_available');
    } catch (e) {
      Debug.log('TRAY', 'init failed: $e');
      _available = false;
    }

    if (_available && showTrayIcon) {
      await _createIcon();
    }

    hideWindowRequest = hideWindow;
    minimizeWindowRequest = minimizeWindow;
    quitAppRequest = quitApp;
  }

  /// Create the tray icon on the native side.
  Future<void> _createIcon() async {
    if (!_available || _iconCreated) return;
    try {
      await _channel.invokeMethod<void>('createIcon');
      _iconCreated = true;
      Debug.log('TRAY', 'icon created');
    } on MissingPluginException {
      _iconCreated = true;
    } catch (e) {
      Debug.log('TRAY', 'createIcon failed: $e');
    }
  }

  /// Destroy the tray icon on the native side.
  Future<void> _destroyIcon() async {
    if (!_iconCreated) return;
    try {
      await _channel.invokeMethod<void>('destroyIcon');
      _iconCreated = false;
      Debug.log('TRAY', 'icon destroyed');
    } on MissingPluginException {
      _iconCreated = false;
    } catch (e) {
      Debug.log('TRAY', 'destroyIcon failed: $e');
    }
  }

  /// React to the showTrayIcon setting changing. Creates or destroys
  /// the icon, matching AyuGram's workModeValue subscription.
  Future<void> updateTrayIconVisibility(bool show) async {
    if (!_available) return;
    if (show && !_iconCreated) {
      await _createIcon();
    } else if (!show && _iconCreated) {
      await _destroyIcon();
    }
  }

  /// Flash the taskbar icon / bounce the dock icon (§37.10).
  Future<void> flashWindow() async {
    try {
      await _channel.invokeMethod<void>('flashWindow');
    } on MissingPluginException {
      // Native side doesn't implement it yet. Silent no-op.
    } catch (e) {
      Debug.log('TRAY', 'flashWindow failed: $e');
    }
  }

  /// Update the tray tooltip. Always uses the bare app name — unread count
  /// is communicated via the icon badge only, matching AyuGram behavior.
  Future<void> updateUnread(int count) async {
    if (!isAvailable || count == _lastUnread) return;
    _lastUnread = count;
    try {
      await _channel.invokeMethod<void>('setTooltip', 'UniClient');
    } catch (e) {
      Debug.log('TRAY', 'setTooltip failed: $e');
    }
  }

  /// Update the notifications toggle tray item label.
  Future<void> updateNotificationsItem({required bool enabled}) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('setNotificationsTrayItem', {
        'enabled': enabled,
      });
    } catch (e) {
      Debug.log('TRAY', 'setNotificationsTrayItem failed: $e');
    }
  }

  /// Toggle desktop notifications from the tray menu, matching AyuGram's
  /// Tray::toggleSoundNotifications(). Saves sound and flash-bounce state
  /// when disabling, restores when re-enabling.
  ///
  /// [rememberedSound] and [rememberedFlash] are the persisted "remembered"
  /// flags from AppState. Returns updated values including the new remembered
  /// state — caller MUST persist the returned values via
  /// `AppState.rememberedSoundNotifyFromTray` / `...FlashBounce...` followed
  /// by `saveSettingsDelayed()`, matching AyuGram's tray.cpp:243.
  ({
    bool desktopNotify,
    bool? soundNotify,
    bool? flashBounce,
    bool rememberedSound,
    bool rememberedFlash,
  })
      toggleSoundNotifications({
    required bool currentDesktopNotify,
    required bool currentSoundNotify,
    required bool currentFlashBounce,
    required bool rememberedSound,
    required bool rememberedFlash,
  }) {
    final toggled = !currentDesktopNotify;
    bool? newSound;
    bool? newFlash;
    var newRememberedSound = rememberedSound;
    var newRememberedFlash = rememberedFlash;

    if (toggled) {
      if (rememberedSound && !currentSoundNotify) {
        newSound = true;
        newRememberedSound = false;
      }
      if (rememberedFlash && !currentFlashBounce) {
        newFlash = true;
        newRememberedFlash = false;
      }
    } else {
      if (currentSoundNotify) {
        newSound = false;
        newRememberedSound = true;
      } else {
        newRememberedSound = false;
      }
      if (currentFlashBounce) {
        newFlash = false;
        newRememberedFlash = true;
      } else {
        newRememberedFlash = false;
      }
    }

    return (
      desktopNotify: toggled,
      soundNotify: newSound,
      flashBounce: newFlash,
      rememberedSound: newRememberedSound,
      rememberedFlash: newRememberedFlash,
    );
  }

  /// Render an unread-count badge overlay on the tray icon.
  Future<void> updateBadge(int count, {bool muted = false}) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('setUnreadBadge', {
        'count': count,
        'muted': muted,
      });
    } catch (e) {
      Debug.log('TRAY', 'setUnreadBadge failed: $e');
    }
  }

  /// Show or hide the Streamer Mode tray item, updating its label.
  Future<void> updateStreamerItem(bool show, bool enabled) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('setStreamerTrayItem', {
        'show': show,
        'enabled': enabled,
      });
    } catch (e) {
      Debug.log('TRAY', 'setStreamerTrayItem failed: $e');
    }
  }

  /// Show or hide the Ghost Mode tray item, updating its label.
  Future<void> updateGhostItem(bool show, bool enabled) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('setGhostTrayItem', {
        'show': show,
        'enabled': enabled,
      });
    } catch (e) {
      Debug.log('TRAY', 'setGhostTrayItem failed: $e');
    }
  }

  /// Refresh the tray icon (re-render badge/monochrome state).
  /// Called after the window is restored from tray, matching AyuGram's
  /// updateIconCounters() in showFromTrayRequests subscribers.
  Future<void> updateIconCounters() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('updateIconCounters');
    } on MissingPluginException {
      // Not implemented on native side yet.
    } catch (e) {
      Debug.log('TRAY', 'updateIconCounters failed: $e');
    }
  }

  /// Apply a new app icon at runtime. Updates both the window icon and
  /// the tray icon. [iconName] is the asset name (e.g. 'alt', 'discord')
  /// or empty string for the default icon.
  Future<void> updateAppIcon(String iconName) async {
    try {
      await _channel.invokeMethod<void>('updateAppIcon', {
        'icon': iconName.isEmpty ? 'default' : iconName,
      });
    } on MissingPluginException {
      // Not implemented on native side yet.
    } catch (e) {
      Debug.log('TRAY', 'updateAppIcon failed: $e');
    }
  }

  /// Update the monochrome tray icon setting on the native side,
  /// then refresh the icon. Matches AyuGram's
  /// trayIconMonochromeChanges → updateIconCounters() subscription.
  Future<void> updateMonochromeIcon(bool monochrome) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('setMonochrome', {
        'monochrome': monochrome,
      });
    } catch (e) {
      Debug.log('TRAY', 'setMonochrome failed: $e');
    }
  }

  /// Show the main window.
  Future<void> showWindow() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('showWindow');
      _windowVisible = true;
    } catch (e) {
      Debug.log('TRAY', 'showWindow failed: $e');
    }
  }

  /// Hide the main window.
  Future<void> hideWindow() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('hideWindow');
      _windowVisible = false;
      Debug.log('TRAY', 'hideWindow dispatched');
    } catch (e) {
      Debug.log('TRAY', 'hideWindow failed: $e');
    }
  }

  /// Minimize (iconify) the main window. Unlike `hideWindow`, this does
  /// not depend on the native tray being available — it just asks the
  /// window manager to minimize the window to its taskbar entry. No-op on
  /// platforms without a native handler (the channel responds with
  /// `notImplemented`, which throws `MissingPluginException` — we swallow
  /// it).
  Future<void> minimizeWindow() async {
    try {
      await _channel.invokeMethod<void>('minimizeWindow');
      Debug.log('TRAY', 'minimizeWindow dispatched');
    } on MissingPluginException {
      // Native side doesn't implement it (non-Linux for now). Silent no-op.
    } catch (e) {
      Debug.log('TRAY', 'minimizeWindow failed: $e');
    }
  }

  /// Fully quit the application (Ctrl+Q `quit_telegram`). Destroys the
  /// main window so GApplication shuts down cleanly. Unlike `hideWindow`,
  /// does NOT depend on the tray being available. No-op on platforms
  /// without a native handler.
  Future<void> quitApp() async {
    try {
      await _channel.invokeMethod<void>('quitApp');
      Debug.log('TRAY', 'quitApp dispatched');
    } on MissingPluginException {
      // Native side doesn't implement it. Silent no-op.
    } catch (e) {
      Debug.log('TRAY', 'quitApp failed: $e');
    }
  }

  /// Toggle window visibility. Guarded against double-clicks matching
  /// AyuGram's `_lastTrayClickTime` + `QApplication::doubleClickInterval()`
  /// check.
  Future<void> toggleVisibility() async {
    if (!isAvailable) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastTrayClickTime > 0 &&
        (now - _lastTrayClickTime) < _kDoubleClickIntervalMs) {
      return;
    }
    _lastTrayClickTime = now;
    try {
      await _channel.invokeMethod<void>('toggleVisibility');
      _windowVisible = !_windowVisible;
    } catch (e) {
      Debug.log('TRAY', 'toggleVisibility failed: $e');
    }
  }

  static const _kDoubleClickIntervalMs = 400;

  /// Populate the tray context menu with per-account entries for switching.
  /// Only shown when multiple accounts are logged in, matching AyuGram's
  /// TrayAccountsMenu::Fill behavior.
  ///
  /// Each entry should contain:
  ///   - `id`: account ID
  ///   - `name`: display name (truncated to 30 chars + ellipsis if needed)
  ///   - `avatarPath`: path to on-disk avatar file (may be empty)
  ///   - `avatarBase64`: base64-encoded PNG userpic thumbnail for native rendering
  ///   - `initials`: fallback initials for placeholder userpic generation
  ///   - `colorIndex`: int index for placeholder background color
  Future<void> updateAccountsMenu(List<Map<String, dynamic>> accounts) async {
    if (!isAvailable) return;
    final truncated = accounts.map((a) {
      final name = a['name'] as String? ?? '';
      final safeName = name.length > _kMaxAccountNameLength
          ? '${name.substring(0, _kMaxAccountNameLength)}$_kEllipsis'
          : name;
      return <String, dynamic>{...a, 'name': safeName};
    }).toList();
    try {
      await _channel.invokeMethod<void>('setAccountsMenu', {
        'accounts': truncated,
      });
    } on MissingPluginException {
      // Native side doesn't implement it yet.
    } catch (e) {
      Debug.log('TRAY', 'setAccountsMenu failed: $e');
    }
  }

  /// Handle method calls from native side → Dart.
  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onQuit':
        Debug.log('TRAY', 'quit requested from tray menu');
        onQuit?.call();
      case 'onWindowHidden':
        Debug.log('TRAY', 'window hidden (minimized to tray)');
        _windowVisible = false;
        onWindowHidden?.call();
      case 'onWindowShown':
        Debug.log('TRAY', 'window shown from tray');
        _windowVisible = true;
        onWindowShown?.call();
      case 'onStreamerToggle':
        Debug.log('TRAY', 'streamer toggle requested from tray menu');
        onStreamerToggle?.call();
      case 'onGhostToggle':
        Debug.log('TRAY', 'ghost toggle requested from tray menu');
        onGhostToggle?.call();
      case 'onNotificationsToggle':
        Debug.log('TRAY', 'notifications toggle requested from tray menu');
        onNotificationsToggle?.call();
      case 'onAccountSwitch':
        final args = call.arguments;
        String? accountId;
        bool ctrlPressed = false;
        if (args is Map) {
          accountId = args['accountId'] as String?;
          ctrlPressed = args['ctrlPressed'] as bool? ?? false;
        } else if (args is String) {
          accountId = args;
        }
        Debug.log('TRAY', 'account switch requested: $accountId (ctrl=$ctrlPressed)');
        if (accountId != null) {
          onAccountSwitch?.call(accountId, ctrlPressed: ctrlPressed);
        }
      case 'onWindowFocusChanged':
        final focused = call.arguments as bool? ?? false;
        _windowActive = focused;
      case 'onTrayIconClick':
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_lastTrayClickTime > 0 &&
            (now - _lastTrayClickTime) < _kDoubleClickIntervalMs) {
          return;
        }
        _lastTrayClickTime = now;
        // AyuGram: isActiveForTrayMenu() = !isHidden() && _isActive
        // Only hide when window is visible AND focused. If visible but
        // unfocused, bring it to the foreground instead of hiding.
        bool isActiveForTray = _windowVisible && _windowActive;
        final args = call.arguments;
        if (args is Map && args.containsKey('isActive')) {
          isActiveForTray = args['isActive'] as bool? ?? isActiveForTray;
        }
        if (isActiveForTray) {
          _windowVisible = false;
          _windowActive = false;
          onWindowHidden?.call();
        } else {
          _windowVisible = true;
          _windowActive = true;
          onWindowShown?.call();
        }
      default:
        Debug.log('TRAY', 'unknown native call: ${call.method}');
    }
  }

  /// Clean up resources.
  void dispose() {
    _channel.setMethodCallHandler(null);
    if (hideWindowRequest == hideWindow) {
      hideWindowRequest = null;
    }
    if (minimizeWindowRequest == minimizeWindow) {
      minimizeWindowRequest = null;
    }
    if (quitAppRequest == quitApp) {
      quitAppRequest = null;
    }
  }
}
