import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' as pkg_ffi;

/// Platform notification-state queries — the Dart analog of AyuGram's
/// `Platform::Notifications` namespace (`platform/platform_notifications_manager.h`).
/// Currently exposes only `WaitForInputForCustom()`, consumed by the custom
/// (Default) in-app popup manager's wait-for-input gate in
/// `notification_manager_default.dart`.
class PlatformNotifications {
  PlatformNotifications._();

  /// Whether the custom in-app popup should WAIT for user input before arming
  /// its auto-hide countdown — the mirror of
  /// `Platform::Notifications::WaitForInputForCustom()`.
  ///
  ///  - Linux  : always true ← `notifications_manager_linux.cpp:197-199`
  ///  - macOS  : always true ← `notifications_manager_mac.mm:221-223`
  ///  - Windows: `SHQueryUserNotificationState() != QUNS_BUSY`
  ///             ← `notifications_manager_win.cpp:398-402`. Returns false while a
  ///             full-screen app / presentation settings put the shell in
  ///             `QUNS_BUSY`, so the popup does NOT wait — the 3s auto-hide
  ///             starts immediately rather than holding a toast on screen while
  ///             the user is busy.
  ///
  /// On Windows, when `shell32`/`SHQueryUserNotificationState` is unavailable or
  /// the query fails, defaults to true (not-busy) — exactly AyuGram's
  /// `UserNotificationState` staying at its `QUNS_ACCEPTS_NOTIFICATIONS` initial
  /// value when the query never succeeds (`notifications_manager_win.cpp:342-352`).
  static bool waitForInputForCustom() {
    if (!Platform.isWindows) return true;
    return _WinNotificationState.notBusy();
  }
}

// ── Windows: SHQueryUserNotificationState (shell32) ──────────────────────────
// Port of QueryUserNotificationState()/WaitForInputForCustom()
// (notifications_manager_win.cpp:342-402). QUNS_BUSY (== 2) means a full-screen
// app or presentation settings are active; AyuGram does not wait for input then.
// Probed lazily and cached, mirroring system_idle.dart's _WinIdle: the shell32
// handle + out-param buffer are opened once and reused per query. Never executes
// off Windows (guarded by Platform.isWindows in waitForInputForCustom()).

class _WinNotificationState {
  static const int _qunsBusy = 2; // QUNS_BUSY

  static bool _probed = false;
  static int Function(ffi.Pointer<ffi.Int32>)? _query;
  static ffi.Pointer<ffi.Int32>? _state;

  static void _probe() {
    if (_probed) return;
    _probed = true;
    try {
      final shell32 = ffi.DynamicLibrary.open('shell32.dll');
      _query = shell32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Int32>),
          int Function(
              ffi.Pointer<ffi.Int32>)>('SHQueryUserNotificationState');
      _state = pkg_ffi.calloc<ffi.Int32>();
    } catch (_) {
      _query = null;
      _state = null;
    }
  }

  /// true when the shell is NOT in `QUNS_BUSY` — the `WaitForInputForCustom()`
  /// result on Windows. SHQueryUserNotificationState returns an HRESULT; AyuGram
  /// only updates `UserNotificationState` on `SUCCEEDED(hr)` (hr >= 0) and
  /// otherwise keeps the prior (initially not-busy) value, so any failure here
  /// returns true.
  static bool notBusy() {
    _probe();
    final query = _query;
    final state = _state;
    if (query == null || state == null) return true; // unavailable → not busy
    try {
      // SUCCEEDED(hr) ⟺ hr >= 0; a negative HRESULT means the query failed.
      if (query(state) < 0) return true; // failed → keep last (not busy)
      return state.value != _qunsBusy;
    } catch (_) {
      return true;
    }
  }
}
