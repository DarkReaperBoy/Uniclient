import 'dart:async';
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
///  - Windows : `GetLastInputInfo` + `GetTickCount64` (user32/kernel32)
///              ← `base_last_input_win.cpp` — the full reading incl. the
///              `GetTickCount64` sanity check and 32-bit-overrun fallback, so
///              idle stays correct across the ~49.7-day `GetTickCount` wrap.
///  - Linux   : `XScreenSaverQueryInfo` (libXss/libX11), then a
///              `org.gnome.Mutter.IdleMonitor` D-Bus fallback (libdbus-1)
///              ← `base_last_input_linux.cpp` — AyuGram tries XCB
///              MIT-SCREEN-SAVER first and falls back to Mutter's idle monitor
///              precisely because XScreenSaver cannot see native (non-X11)
///              input under Wayland, where most modern GNOME sessions run.
///  - macOS   : `CGEventSourceSecondsSinceLastEventType` (CoreGraphics)
///              — the global HID idle, equivalent to AyuGram's IOKit
///              `HIDIdleTime` read in `base_last_input_mac.mm`, via a single
///              well-defined call instead of the multi-step IOKit registry walk.
///
/// All native sources are probed lazily and cached; the connection/handles are
/// opened once and reused per poll. When a platform can't report idle (no X
/// screensaver extension and no Mutter idle monitor, an unexpected lib layout,
/// web, …) every accessor returns null — the mirror of
/// `LastUserInputTimeSupported() == false`, and callers fall back to the
/// always-available app-local pointer signal.
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

// ── Windows: GetLastInputInfo + GetTickCount64 ───────────────────────────────
// Full port of AyuGram base_last_input_win.cpp:21-69. The naive
// `GetTickCount() - dwTime` is wrong across the ~49.7-day 32-bit GetTickCount
// wrap (it goes negative once the counter wraps while dwTime still holds a
// pre-wrap value), so AyuGram cross-checks against GetTickCount64 and, in the
// unreliable window, estimates the last-input instant from tracked state.

final class _LastInputInfo extends ffi.Struct {
  @ffi.Uint32()
  external int cbSize;
  @ffi.Uint32()
  external int dwTime;
}

class _WinIdle {
  // Re-check a "bad" (mid-overrun) reading after this delay so the tracked
  // state self-heals once the tick counters agree again. ← base_last_input_win.cpp:17
  static const int _kRefreshBadMs = 10 * 1000;
  // GetTickCount() is a 32-bit ms counter that wraps at DWORD max
  // (0xFFFFFFFF) every ~49.7 days. ← base_last_input_win.cpp:51-52
  static const int _overrunLimit = 0xFFFFFFFF;
  static const int _overrunThreshold = 0x3FFFFFFF; // = _overrunLimit ~/ 4

  final int Function(ffi.Pointer<_LastInputInfo>) _getLastInputInfo;
  final int Function() _getTickCount;
  final int Function() _getTickCount64;
  final ffi.Pointer<_LastInputInfo> _info;
  // crl::now() analog — a monotonic ms clock started when this backend opened.
  final Stopwatch _clock;

  // Mirrors of AyuGram's function-static state, carried across the 32-bit
  // GetTickCount overrun window. ← base_last_input_win.cpp:29-30,43
  bool _trackedInit = false;
  int _lastTrackedInput = 0;
  int _lastTrackedWhen = 0;
  bool _waitingDelayed = false;

  _WinIdle._(this._getLastInputInfo, this._getTickCount, this._getTickCount64,
      this._info, this._clock);

  static _WinIdle? tryOpen() {
    try {
      final user32 = ffi.DynamicLibrary.open('user32.dll');
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final getLastInputInfo = user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<_LastInputInfo>),
          int Function(ffi.Pointer<_LastInputInfo>)>('GetLastInputInfo');
      final getTickCount = kernel32.lookupFunction<ffi.Uint32 Function(),
          int Function()>('GetTickCount');
      final getTickCount64 = kernel32.lookupFunction<ffi.Uint64 Function(),
          int Function()>('GetTickCount64');
      final info = pkg_ffi.calloc<_LastInputInfo>();
      info.ref.cbSize = ffi.sizeOf<_LastInputInfo>();
      return _WinIdle._(getLastInputInfo, getTickCount, getTickCount64, info,
          Stopwatch()..start());
    } catch (_) {
      return null;
    }
  }

  int _now() => _clock.elapsedMilliseconds;

  /// Port of `base::Platform::LastUserInputTime()` (base_last_input_win.cpp:21-69)
  /// — returns the instant (in [_now] units) of the last global input, or null
  /// when GetLastInputInfo fails. GetTickCount64 keeps this correct across the
  /// 32-bit GetTickCount wrap instead of the naive `GetTickCount() - dwTime`.
  int? _lastUserInputInstant() {
    _info.ref.cbSize = ffi.sizeOf<_LastInputInfo>();
    if (_getLastInputInfo(_info) == 0) return null;
    final now = _now();
    final input = _info.ref.dwTime;
    if (!_trackedInit) {
      _trackedInit = true;
      _lastTrackedInput = input;
      _lastTrackedWhen = now;
    }

    final ticks32 = _getTickCount();
    final ticks64 = _getTickCount64();
    final maxTicks = ticks32 > ticks64 ? ticks32 : ticks64;
    final elapsed = maxTicks - input;
    // Trust the simple subtraction only while the two counters still agree
    // (no wrap has happened yet) and the idle is non-negative. ← :34-36
    final good = ((ticks32 - ticks64).abs() <= 1000) && (elapsed >= 0);
    if (good) {
      _lastTrackedInput = input;
      _lastTrackedWhen = now;
      return now > elapsed ? now - elapsed : 0;
    }

    // Bad (mid-overrun) reading: schedule a single delayed re-check so the
    // tracked state refreshes once the counters agree again. ← :43-50
    if (!_waitingDelayed) {
      _waitingDelayed = true;
      Timer(const Duration(milliseconds: _kRefreshBadMs), () {
        _waitingDelayed = false;
        _lastUserInputInstant();
      });
    }

    // Input unchanged since the last good reading → freeze at that instant. ← :53-55
    if (_lastTrackedInput == input) {
      return _lastTrackedWhen;
    }
    try {
      if (input > _lastTrackedInput) {
        // dwTime advanced normally. ← :60-62
        final add = input - _lastTrackedInput;
        final cand = _lastTrackedWhen + add;
        return cand < now ? cand : now;
      } else if (_overrunLimit + input - _lastTrackedInput < _overrunThreshold) {
        // dwTime wrapped past DWORD max by a plausible (< quarter-range)
        // amount → recover the true delta across one wrap. ← :63-66
        final add = _overrunLimit + input - _lastTrackedInput;
        final cand = _lastTrackedWhen + add;
        return cand < now ? cand : now;
      }
      return _lastTrackedWhen;
    } finally {
      // gsl::finally — update tracked state on every branch above. ← :56-59
      _lastTrackedInput = input;
      _lastTrackedWhen = now;
    }
  }

  int? idleMillis() {
    final instant = _lastUserInputInstant();
    if (instant == null) return null;
    final n = _now();
    return n > instant ? n - instant : 0;
  }
}

// ── Linux ────────────────────────────────────────────────────────────────────
// AyuGram base_last_input_linux.cpp dispatches the XCB MIT-SCREEN-SAVER path
// first and falls back to the org.gnome.Mutter.IdleMonitor D-Bus service. The
// Mutter fallback is essential under Wayland: XScreenSaverQueryInfo reports no
// server (pure Wayland) or, via XWayland, only X11-client input — never native
// compositor/Wayland input — so on the default Wayland sessions of Fedora /
// Ubuntu / GNOME the X11 reading is absent or stale. ← base_last_input_linux.cpp:88-102

/// First soname in [names] that loads, or null if none do — shared by the X11
/// and libdbus backends.
ffi.DynamicLibrary? _openFirstLib(List<String> names) {
  for (final name in names) {
    try {
      return ffi.DynamicLibrary.open(name);
    } catch (_) {
      // try the next soname
    }
  }
  return null;
}

/// Linux idle dispatcher mirroring `LastUserInputTime()` (base_last_input_linux.cpp:88):
/// take the X11/XScreenSaver reading, and only when it yields nothing fall back
/// to the Mutter idle monitor over D-Bus. Mutter is probed lazily — a D-Bus
/// connection is never opened on real X11 sessions where XScreenSaver works.
class _LinuxIdle {
  final _X11Idle? _x11;
  _MutterIdle? _mutter;
  bool _mutterProbed;

  _LinuxIdle._(this._x11, this._mutter, this._mutterProbed);

  static _LinuxIdle? tryOpen() {
    final x11 = _X11Idle.tryOpen();
    if (x11 != null) {
      // XScreenSaver works → defer (skip) Mutter unless X11 ever returns null.
      return _LinuxIdle._(x11, null, false);
    }
    // No X server / no MIT-SCREEN-SAVER (e.g. pure Wayland) → Mutter is the
    // only global idle source. ← base_last_input_linux.cpp:96
    final mutter = _MutterIdle.tryOpen();
    if (mutter == null) return null;
    return _LinuxIdle._(null, mutter, true);
  }

  int? idleMillis() {
    final viaX11 = _x11?.idleMillis();
    if (viaX11 != null) return viaX11;
    // X11 absent or transiently failed → Mutter fallback (lazy-probe once).
    if (!_mutterProbed) {
      _mutterProbed = true;
      _mutter = _MutterIdle.tryOpen();
    }
    return _mutter?.idleMillis();
  }
}

// ── Linux X11: XScreenSaverQueryInfo ─────────────────────────────────────────
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

class _X11Idle {
  final ffi.Pointer<ffi.Void> _display;
  final int _root;
  final int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<_XScreenSaverInfo>)
      _queryInfo;
  final ffi.Pointer<_XScreenSaverInfo> _info;

  _X11Idle._(this._display, this._root, this._queryInfo, this._info);

  static _X11Idle? tryOpen() {
    try {
      final x11 = _openFirstLib(['libX11.so.6', 'libX11.so']);
      final xss = _openFirstLib(['libXss.so.1', 'libXss.so']);
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
      return _X11Idle._(display, root, xssQueryInfo, info);
    } catch (_) {
      return null;
    }
  }

  int? idleMillis() {
    if (_queryInfo(_display, _root, _info) == 0) return null;
    return _info.ref.idle;
  }
}

// ── Linux Wayland/GNOME: org.gnome.Mutter.IdleMonitor (D-Bus) ─────────────────
// AyuGram MutterDBusLastUserInputTime() (base_last_input_linux.cpp:58) calls
// `GetIdletime` on org.gnome.Mutter.IdleMonitor (session bus, object
// /org/gnome/Mutter/IdleMonitor/Core) and returns `now - idletime`. Mirrored
// here through libdbus-1 — a runtime DynamicLibrary.open, exactly like libXss
// above (no CGo) — using the synchronous send-with-reply-and-block round-trip
// so the existing synchronous idle API is preserved (the pure-Dart `dbus`
// package is async and cannot satisfy SystemIdle's synchronous accessors).

/// Resolved libdbus-1 entry points (loaded once) — just the handful needed for
/// one blocking method call and a uint64 reply parse.
class _DbusApi {
  final ffi.Pointer<ffi.Void> Function(int, ffi.Pointer<ffi.Void>) busGet;
  final void Function(ffi.Pointer<ffi.Void>, int) setExitOnDisconnect;
  final void Function(ffi.Pointer<ffi.Void>) errorInit;
  final int Function(ffi.Pointer<ffi.Void>) errorIsSet;
  final void Function(ffi.Pointer<ffi.Void>) errorFree;
  final ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<pkg_ffi.Utf8>,
      ffi.Pointer<pkg_ffi.Utf8>,
      ffi.Pointer<pkg_ffi.Utf8>,
      ffi.Pointer<pkg_ffi.Utf8>) newMethodCall;
  final void Function(ffi.Pointer<ffi.Void>, int) setAutoStart;
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>) sendWithReplyAndBlock;
  final void Function(ffi.Pointer<ffi.Void>) messageUnref;
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) iterInit;
  final int Function(ffi.Pointer<ffi.Void>) iterGetArgType;
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) iterGetBasic;

  _DbusApi._(
      this.busGet,
      this.setExitOnDisconnect,
      this.errorInit,
      this.errorIsSet,
      this.errorFree,
      this.newMethodCall,
      this.setAutoStart,
      this.sendWithReplyAndBlock,
      this.messageUnref,
      this.iterInit,
      this.iterGetArgType,
      this.iterGetBasic);

  static _DbusApi? open() {
    final lib = _openFirstLib(['libdbus-1.so.3', 'libdbus-1.so']);
    if (lib == null) return null;
    try {
      return _DbusApi._(
        lib.lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Int32, ffi.Pointer<ffi.Void>),
            ffi.Pointer<ffi.Void> Function(
                int, ffi.Pointer<ffi.Void>)>('dbus_bus_get'),
        lib.lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32),
            void Function(ffi.Pointer<ffi.Void>,
                int)>('dbus_connection_set_exit_on_disconnect'),
        lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)>('dbus_error_init'),
        lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)>('dbus_error_is_set'),
        lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)>('dbus_error_free'),
        lib.lookupFunction<
            ffi.Pointer<ffi.Void> Function(
                ffi.Pointer<pkg_ffi.Utf8>,
                ffi.Pointer<pkg_ffi.Utf8>,
                ffi.Pointer<pkg_ffi.Utf8>,
                ffi.Pointer<pkg_ffi.Utf8>),
            ffi.Pointer<ffi.Void> Function(
                ffi.Pointer<pkg_ffi.Utf8>,
                ffi.Pointer<pkg_ffi.Utf8>,
                ffi.Pointer<pkg_ffi.Utf8>,
                ffi.Pointer<pkg_ffi.Utf8>)>('dbus_message_new_method_call'),
        lib.lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32),
            void Function(ffi.Pointer<ffi.Void>,
                int)>('dbus_message_set_auto_start'),
        lib.lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Pointer<ffi.Void>),
            ffi.Pointer<ffi.Void> Function(
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                int,
                ffi.Pointer<
                    ffi.Void>)>('dbus_connection_send_with_reply_and_block'),
        lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)>('dbus_message_unref'),
        lib.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>)>('dbus_message_iter_init'),
        lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(
                ffi.Pointer<ffi.Void>)>('dbus_message_iter_get_arg_type'),
        lib.lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>)>('dbus_message_iter_get_basic'),
      );
    } catch (_) {
      return null;
    }
  }
}

class _MutterIdle {
  static const int _dbusBusSession = 0; // DBUS_BUS_SESSION
  static const int _dbusTypeUint64 = 116; // 't' — GetIdletime returns (t)
  // libdbus's DBusError / DBusMessageIter are only ever handed to accessor
  // functions here (never read field-by-field), so an over-sized zeroed buffer
  // is ABI-safe regardless of the exact struct sizeof on this build.
  static const int _structBufBytes = 256;
  // Bound the blocking round-trip; Mutter answers in well under a millisecond,
  // but a wedged compositor must never stall the synchronous notification gate.
  static const int _callTimeoutMs = 1000;

  final _DbusApi _api;
  final ffi.Pointer<ffi.Void> _conn;
  final ffi.Pointer<pkg_ffi.Utf8> _busName;
  final ffi.Pointer<pkg_ffi.Utf8> _path;
  final ffi.Pointer<pkg_ffi.Utf8> _iface;
  final ffi.Pointer<pkg_ffi.Utf8> _method;
  final ffi.Pointer<ffi.Void> _err; // DBusError buffer
  final ffi.Pointer<ffi.Void> _iter; // DBusMessageIter buffer
  final ffi.Pointer<ffi.Uint64> _value;

  _MutterIdle._(this._api, this._conn, this._busName, this._path, this._iface,
      this._method, this._err, this._iter, this._value);

  static _MutterIdle? tryOpen() {
    try {
      final api = _DbusApi.open();
      if (api == null) return null;
      final err = pkg_ffi.calloc<ffi.Uint8>(_structBufBytes).cast<ffi.Void>();
      api.errorInit(err);
      final conn = api.busGet(_dbusBusSession, err);
      if (conn.address == 0) {
        if (api.errorIsSet(err) != 0) api.errorFree(err);
        pkg_ffi.calloc.free(err);
        return null;
      }
      // The shared session connection defaults to exit-on-disconnect = TRUE,
      // which would _exit() the whole app if the bus drops. Never allow that.
      api.setExitOnDisconnect(conn, 0);
      final iter = pkg_ffi.calloc<ffi.Uint8>(_structBufBytes).cast<ffi.Void>();
      final value = pkg_ffi.calloc<ffi.Uint64>();
      final mutter = _MutterIdle._(
        api,
        conn,
        'org.gnome.Mutter.IdleMonitor'.toNativeUtf8(),
        '/org/gnome/Mutter/IdleMonitor/Core'.toNativeUtf8(),
        'org.gnome.Mutter.IdleMonitor'.toNativeUtf8(),
        'GetIdletime'.toNativeUtf8(),
        err,
        iter,
        value,
      );
      // Probe once: only treat Mutter as a usable backend if it actually
      // answers — mirrors AyuGram latching NotSupported on a failed call (a
      // non-GNOME session simply has no IdleMonitor on the bus). ← base_last_input_linux.cpp:59,72-81
      if (mutter._query() == null) {
        mutter._dispose();
        return null;
      }
      return mutter;
    } catch (_) {
      return null;
    }
  }

  void _dispose() {
    pkg_ffi.malloc.free(_busName);
    pkg_ffi.malloc.free(_path);
    pkg_ffi.malloc.free(_iface);
    pkg_ffi.malloc.free(_method);
    pkg_ffi.calloc.free(_err);
    pkg_ffi.calloc.free(_iter);
    pkg_ffi.calloc.free(_value);
    // The libdbus shared connection is owned by libdbus; do not unref/close it.
  }

  /// One synchronous `GetIdletime` round-trip → idle milliseconds, or null on
  /// any failure (no service, malformed reply, timeout). ← base_last_input_linux.cpp:58-84
  int? _query() {
    final msg = _api.newMethodCall(_busName, _path, _iface, _method);
    if (msg.address == 0) return null;
    try {
      _api.setAutoStart(msg, 0); // don't D-Bus-activate the service
      _api.errorInit(_err);
      final reply = _api.sendWithReplyAndBlock(_conn, msg, _callTimeoutMs, _err);
      if (reply.address == 0) {
        if (_api.errorIsSet(_err) != 0) _api.errorFree(_err);
        return null;
      }
      try {
        if (_api.iterInit(reply, _iter) == 0) return null;
        if (_api.iterGetArgType(_iter) != _dbusTypeUint64) return null;
        _value.value = 0;
        _api.iterGetBasic(_iter, _value.cast<ffi.Void>());
        return _value.value;
      } finally {
        _api.messageUnref(reply);
      }
    } finally {
      _api.messageUnref(msg);
    }
  }

  int? idleMillis() => _query();
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
