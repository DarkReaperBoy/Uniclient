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

  /// Whether the native tray icon is active.
  bool get isAvailable => _available;

  /// Callback invoked when the user chooses "Quit" from the tray menu.
  void Function()? onQuit;

  /// Callback invoked when the window is hidden via the close button
  /// (minimized to tray).
  void Function()? onWindowHidden;

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

  /// Update the tray tooltip / label with the current unread count.
  Future<void> updateUnread(int count) async {
    if (!_available || count == _lastUnread) return;
    _lastUnread = count;
    final label = count > 0 ? 'UniClient ($count unread)' : 'UniClient';
    try {
      await _channel.invokeMethod<void>('setTooltip', label);
    } catch (e) {
      Debug.log('TRAY', 'setTooltip failed: $e');
    }
  }

  /// Show the main window.
  Future<void> showWindow() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('showWindow');
    } catch (e) {
      Debug.log('TRAY', 'showWindow failed: $e');
    }
  }

  /// Hide the main window.
  Future<void> hideWindow() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('hideWindow');
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
    } catch (e) {
      Debug.log('TRAY', 'toggleVisibility failed: $e');
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
        onWindowHidden?.call();
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
