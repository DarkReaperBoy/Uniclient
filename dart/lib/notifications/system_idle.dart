import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' as pkg_ffi;

/// Global, system-wide user-input idle time — the Dart analog of AyuGram's
/// `base::Platform::LastUserInputTime()` / `LastUserInputTimeSupported()`
/// (`lib_base/base/platform/.../base_last_input_*`), consumed by the custom
/// notification manager's wait-for-input gate exactly like
/// `Core::App().lastNonIdleTime()` in
/// `window/notifications_manager_default.cpp:186-200`.
///
/// AyuGram gates a notification's auto-dismiss countdown on the GLOBAL idle
/// time so a popup that arrives while the user is away from the machine stays
/// on screen until they return. The Dart popup controller/view previously only
/// had an app-local pointer signal (pointer events over our own window), so on
/// Linux/macOS the countdown started immediately on arrival. This restores the
/// missing half: a real OS-level idle source per platform, mirroring AyuGram:
///
///  - Windows : `GetLastInputInfo` (user32)            ← `base_last_input_win.cpp`
///  - Linux   : `XScreenSaverQueryInfo` (libXss/libX11) ← `base_last_input_linux.cpp`
///              (the XCB MIT-SCREEN-SAVER path; same `idle` ms reading)
///  - macOS   : `CGEventSourceSecondsSinceLastEventType` (CoreGraphics)
///              — the global HID idle, equivalent to AyuGram's IOKit
///              `HIDIdleTime` read in `base_last_input_mac.mm`, via a single
///              well-defined call instead of the multi-step IOKit registry walk.
///
/// All native sources are probed lazily and cached; the connection/handles are
/// opened once and reused per poll. When a platform can't report idle (no X
/// screensaver extension, an unexpected lib layout, web, …) every accessor
/// returns null — the mirror of `LastUserInputTimeSupported() == false`, and
/// callers fall back to the always-available app-local pointer signal.
class SystemIdle {
  SystemIdle._();

  static bool _probed = false;
  static _WinIdle? _win;
  static _LinuxIdle? _linux;
  static _MacIdle? _mac;

  static void _probe() {
    if (_probed) return;
    _probed = true;
    try {
      if (Platform.isWindows) {
        _win = _WinIdle.tryOpen();
      } else if (Platform.isLinux) {
        _linux = _LinuxIdle.tryOpen();
      } else if (Platform.isMacOS) {
        _mac = _MacIdle.tryOpen();
      }
    } catch (_) {
      // Leave every backend null → unsupported.
    }
  }

  /// Whether the OS exposes a global idle source on this platform — the mirror
  /// of `base::Platform::LastUserInputTimeSupported()`.
  static bool get supported {
    _probe();
    return _win != null || _linux != null || _mac != null;
  }

  /// Milliseconds since the last system-wide input event, or null when the
  /// platform can't report it.
  static int? idleMillis() {
    _probe();
    try {
      final ms = _win?.idleMillis() ?? _linux?.idleMillis() ?? _mac?.idleMillis();
      if (ms == null) return null;
      return ms < 0 ? 0 : ms;
    } catch (_) {
      return null;
    }
  }

  /// The instant of the last system-wide input (`now - idle`), or null when the
  /// platform can't report it — the mirror of
  /// `base::Platform::LastUserInputTime()` returning `std::nullopt`.
  static DateTime? lastInputTime() {
    final ms = idleMillis();
    if (ms == null) return null;
    return DateTime.now().subtract(Duration(milliseconds: ms));
  }
}

// ── Windows: GetLastInputInfo ────────────────────────────────────────────────
// AyuGram base_last_input_win.cpp — idle = GetTickCount() - lii.dwTime.

final class _LastInputInfo extends ffi.Struct {
  @ffi.Uint32()
  external int cbSize;
  @ffi.Uint32()
  external int dwTime;
}

class _WinIdle {
  final int Function(ffi.Pointer<_LastInputInfo>) _getLastInputInfo;
  final int Function() _getTickCount;
  final ffi.Pointer<_LastInputInfo> _info;

  _WinIdle._(this._getLastInputInfo, this._getTickCount, this._info);

  static _WinIdle? tryOpen() {
    try {
      final user32 = ffi.DynamicLibrary.open('user32.dll');
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final getLastInputInfo = user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<_LastInputInfo>),
          int Function(ffi.Pointer<_LastInputInfo>)>('GetLastInputInfo');
      final getTickCount = kernel32.lookupFunction<ffi.Uint32 Function(),
          int Function()>('GetTickCount');
      final info = pkg_ffi.calloc<_LastInputInfo>();
      info.ref.cbSize = ffi.sizeOf<_LastInputInfo>();
      return _WinIdle._(getLastInputInfo, getTickCount, info);
    } catch (_) {
      return null;
    }
  }

  int? idleMillis() {
    _info.ref.cbSize = ffi.sizeOf<_LastInputInfo>();
    if (_getLastInputInfo(_info) == 0) return null;
    return _getTickCount() - _info.ref.dwTime;
  }
}

// ── Linux: XScreenSaverQueryInfo ─────────────────────────────────────────────
// AyuGram base_last_input_linux.cpp — the XCB MIT-SCREEN-SAVER path reads
// `reply->ms_since_user_input`; the Xlib equivalent is XScreenSaverInfo.idle.

final class _XScreenSaverInfo extends ffi.Struct {
  @ffi.UnsignedLong()
  external int window;
  @ffi.Int()
  external int state;
  @ffi.Int()
  external int kind;
  @ffi.UnsignedLong()
  external int tilOrSince;
  @ffi.UnsignedLong()
  external int idle; // milliseconds since last input
  @ffi.UnsignedLong()
  external int eventMask;
}

class _LinuxIdle {
  final ffi.Pointer<ffi.Void> _display;
  final int _root;
  final int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<_XScreenSaverInfo>)
      _queryInfo;
  final ffi.Pointer<_XScreenSaverInfo> _info;

  _LinuxIdle._(this._display, this._root, this._queryInfo, this._info);

  static ffi.DynamicLibrary? _openFirst(List<String> names) {
    for (final name in names) {
      try {
        return ffi.DynamicLibrary.open(name);
      } catch (_) {
        // try the next soname
      }
    }
    return null;
  }

  static _LinuxIdle? tryOpen() {
    try {
      final x11 = _openFirst(['libX11.so.6', 'libX11.so']);
      final xss = _openFirst(['libXss.so.1', 'libXss.so']);
      if (x11 == null || xss == null) return null;

      final xOpenDisplay = x11.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>)>('XOpenDisplay');
      final xDefaultRootWindow = x11.lookupFunction<
          ffi.UnsignedLong Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)>('XDefaultRootWindow');
      final xssQueryExtension = xss.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>,
              ffi.Pointer<ffi.Int32>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>,
              ffi.Pointer<ffi.Int32>)>('XScreenSaverQueryExtension');
      final xssQueryInfo = xss.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.UnsignedLong,
              ffi.Pointer<_XScreenSaverInfo>),
          int Function(ffi.Pointer<ffi.Void>, int,
              ffi.Pointer<_XScreenSaverInfo>)>('XScreenSaverQueryInfo');

      // XOpenDisplay(nullptr) → use $DISPLAY (same server the app uses).
      final display = xOpenDisplay(ffi.nullptr);
      if (display.address == 0) return null;

      // Confirm the MIT-SCREEN-SAVER extension is present before trusting
      // QueryInfo — the analog of AyuGram's XCB IsExtensionPresent() guard.
      final evBase = pkg_ffi.calloc<ffi.Int32>();
      final errBase = pkg_ffi.calloc<ffi.Int32>();
      final present = xssQueryExtension(display, evBase, errBase);
      pkg_ffi.calloc.free(evBase);
      pkg_ffi.calloc.free(errBase);
      if (present == 0) return null;

      final root = xDefaultRootWindow(display);
      final info = pkg_ffi.calloc<_XScreenSaverInfo>();
      return _LinuxIdle._(display, root, xssQueryInfo, info);
    } catch (_) {
      return null;
    }
  }

  int? idleMillis() {
    if (_queryInfo(_display, _root, _info) == 0) return null;
    return _info.ref.idle;
  }
}

// ── macOS: CGEventSourceSecondsSinceLastEventType ────────────────────────────
// Global HID idle (seconds → ms), equivalent to AyuGram's IOKit HIDIdleTime
// read in base_last_input_mac.mm.

class _MacIdle {
  // kCGEventSourceStateHIDSystemState = 1; kCGAnyInputEventType = ~0.
  static const int _kHidSystemState = 1;
  static const int _kAnyInputEventType = 0xFFFFFFFF;

  final double Function(int, int) _secondsSinceLastEvent;

  _MacIdle._(this._secondsSinceLastEvent);

  static _MacIdle? tryOpen() {
    try {
      final cg = ffi.DynamicLibrary.open(
          '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
      final fn = cg.lookupFunction<ffi.Double Function(ffi.Uint32, ffi.Uint32),
          double Function(int, int)>('CGEventSourceSecondsSinceLastEventType');
      return _MacIdle._(fn);
    } catch (_) {
      return null;
    }
  }

  int? idleMillis() {
    final seconds = _secondsSinceLastEvent(_kHidSystemState, _kAnyInputEventType);
    if (seconds < 0) return null;
    return (seconds * 1000).round();
  }
}
