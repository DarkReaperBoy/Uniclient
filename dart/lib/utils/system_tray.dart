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
  int _lastUnread = -1;
  bool _windowVisible = true;

  /// Whether the native tray icon is active.
  bool get isAvailable => _available;

  /// Whether the main window is currently visible (not hidden to tray).
  bool get windowVisible => _windowVisible;

  /// Callback invoked when the user chooses "Quit" from the tray menu.
  void Function()? onQuit;

  /// Callback invoked when the window is hidden via the close button
  /// (minimized to tray).
  void Function()? onWindowHidden;

  /// Callback invoked when the user clicks the Streamer Mode tray item.
  void Function()? onStreamerToggle;

  /// Callback invoked when the user clicks the Ghost Mode tray item.
  void Function()? onGhostToggle;

  /// Callback invoked when the user clicks the Notifications tray item.
  void Function()? onNotificationsToggle;

  /// Callback invoked when the user switches accounts from the tray menu.
  void Function(String accountId)? onAccountSwitch;

  /// Initialize the tray.  Call once after the engine is running.
  /// No-op on Flutter Web — native tray is desktop-only (§13.5).
  Future<void> init() async {
    if (kIsWeb) return;

    // Listen for native → Dart calls (onQuit, onWindowHidden).
    _channel.setMethodCallHandler(_handleNativeCall);

    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      _available = result ?? false;
      Debug.log('TRAY', 'available=$_available');
    } catch (e) {
      Debug.log('TRAY', 'init failed: $e');
      _available = false;
    }

    // Register global hide-window hook for Ctrl+W shortcut.
    hideWindowRequest = hideWindow;

    // Register global minimize-window hook for Ctrl+M shortcut. Doesn't
    // depend on tray availability — minimize is a plain GTK window action.
    minimizeWindowRequest = minimizeWindow;

    // Register global quit hook for Ctrl+Q shortcut. Doesn't depend on
    // tray availability — quit tears down the main window.
    quitAppRequest = quitApp;
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
    if (!_available || count == _lastUnread) return;
    _lastUnread = count;
    try {
      await _channel.invokeMethod<void>('setTooltip', 'UniClient');
    } catch (e) {
      Debug.log('TRAY', 'setTooltip failed: $e');
    }
  }

  /// Update the notifications toggle tray item label.
  Future<void> updateNotificationsItem({required bool enabled}) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('setNotificationsTrayItem', {
        'enabled': enabled,
      });
    } catch (e) {
      Debug.log('TRAY', 'setNotificationsTrayItem failed: $e');
    }
  }

  /// Render an unread-count badge overlay on the tray icon.
  Future<void> updateBadge(int count, {bool muted = false}) async {
    if (!_available) return;
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
    if (!_available) return;
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
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('setGhostTrayItem', {
        'show': show,
        'enabled': enabled,
      });
    } catch (e) {
      Debug.log('TRAY', 'setGhostTrayItem failed: $e');
    }
  }

  /// Show the main window.
  Future<void> showWindow() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('showWindow');
      _windowVisible = true;
    } catch (e) {
      Debug.log('TRAY', 'showWindow failed: $e');
    }
  }

  /// Hide the main window.
  Future<void> hideWindow() async {
    if (!_available) return;
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

  /// Toggle window visibility.
  Future<void> toggleVisibility() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('toggleVisibility');
      _windowVisible = !_windowVisible;
    } catch (e) {
      Debug.log('TRAY', 'toggleVisibility failed: $e');
    }
  }

  /// Populate the tray context menu with per-account entries for switching.
  /// Only shown when multiple accounts are logged in, matching AyuGram's
  /// TrayAccountsMenu::Fill behavior.
  Future<void> updateAccountsMenu(List<Map<String, String>> accounts) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('setAccountsMenu', {
        'accounts': accounts,
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
        final accountId = call.arguments as String?;
        Debug.log('TRAY', 'account switch requested: $accountId');
        if (accountId != null) onAccountSwitch?.call(accountId);
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
