import 'dart:io' show Platform;

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'debug.dart';

/// Which kind of OS power-saving to block. Mirrors AyuGram
/// `base::PowerSaveBlockType` (lib_base/base/power_save_blocker.h:14-19).
enum PowerSaveBlockType {
  /// Block the system from suspending/sleeping (XDG portal Suspend, flag 4).
  preventAppSuspension,

  /// Block the display from blanking/sleeping (XDG portal Idle, flag 8).
  preventDisplaySleep,
}

/// Monotonic counter feeding unique XDG-portal `handle_token`s.
int _tokenCounter = 0;

/// Pure-Dart port of AyuGram's power-save blocker
/// (lib_base/base/power_save_blocker.cpp +
/// base/platform/linux/base_power_save_blocker_linux.cpp). On Linux it holds an
/// XDG Desktop Portal `org.freedesktop.portal.Inhibit` inhibition for as long
/// as the blocker is engaged, matching AyuGram's `PortalPreventAppSuspension` /
/// `PortalPreventDisplaySleep` (base_power_save_blocker_linux.cpp:155-175): the
/// Suspend flag (4) for app-suspension, the Idle flag (8) for display-sleep.
/// The inhibition is released by closing the returned portal Request object,
/// exactly as `PortalInhibit::~PortalInhibit` calls `_request.call_close()`.
///
/// On non-Linux desktop / web it is a no-op — only the Linux portal path is
/// wired today (Windows/macOS/Android would each need their own native
/// inhibitor), consistent with the rest of uniclient's desktop integration
/// (system tray, native notifications) being Linux/D-Bus only.
class PowerSaveBlocker {
  PowerSaveBlocker(this.type, this.description);

  final PowerSaveBlockType type;
  final String description;

  DBusClient? _bus;
  DBusObjectPath? _requestHandle;
  bool _active = false; // an inhibition is currently held
  bool _desired = false; // the most recently requested state
  bool _busy = false; // a toggle is in flight (serializes overlap)

  /// Whether an inhibition is currently held.
  bool get isBlocking => _active;

  /// Idempotently engage ([block] = true) or release ([block] = false) the
  /// inhibition, settling to the latest requested state even when play/pause
  /// toggles arrive faster than the async portal round-trip completes. Mirrors
  /// `base::UpdatePowerSaveBlocker` (power_save_blocker.h:47-63), which
  /// creates/destroys the blocker only on an actual transition.
  Future<void> update(bool block) async {
    if (kIsWeb || !Platform.isLinux) return;
    _desired = block;
    if (_busy) return; // the in-flight toggle re-checks _desired when it ends
    _busy = true;
    try {
      while (_desired != _active) {
        final want = _desired;
        try {
          if (want) {
            await _inhibit();
          } else {
            await _release();
          }
        } catch (e) {
          Debug.log('power_save',
              '${type.name} ${want ? 'inhibit' : 'release'} failed: $e');
          // Could not reach the wanted state (e.g. no portal available).
          // Abandon this toggle so we don't spin; a later update() retries
          // from a real playback event. Treat the inhibition as not held.
          _requestHandle = null;
          _active = false;
          break;
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _inhibit() async {
    final bus = _bus ??= DBusClient.session();
    final portal = DBusRemoteObject(
      bus,
      name: 'org.freedesktop.portal.Desktop',
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    );
    // XDG portal Inhibit flags: 1 Logout, 2 User Switch, 4 Suspend, 8 Idle
    // (base_power_save_blocker_linux.cpp:61-66).
    final flags = (type == PowerSaveBlockType.preventAppSuspension) ? 4 : 8;
    final token = 'uniclient_${type.name}_${_tokenCounter++}';
    final result = await portal.callMethod(
      'org.freedesktop.portal.Inhibit',
      'Inhibit',
      [
        const DBusString(''), // parent window — none (we hold no XID/handle)
        DBusUint32(flags),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {
          DBusString('reason'): DBusVariant(DBusString(description)),
          DBusString('handle_token'): DBusVariant(DBusString(token)),
        }),
      ],
      replySignature: DBusSignature('o'),
    );
    _requestHandle = result.returnValues[0].asObjectPath();
    _active = true;
  }

  Future<void> _release() async {
    final handle = _requestHandle;
    final bus = _bus;
    _requestHandle = null;
    _active = false;
    if (handle == null || bus == null) return;
    // Closing the portal Request object cancels the inhibition (AyuGram
    // PortalInhibit::~PortalInhibit -> _request.call_close()).
    final request = DBusRemoteObject(
      bus,
      name: 'org.freedesktop.portal.Desktop',
      path: handle,
    );
    await request.callMethod(
      'org.freedesktop.portal.Request',
      'Close',
      [],
      replySignature: DBusSignature(''),
    );
  }

  /// Release any held inhibition and close the D-Bus connection.
  Future<void> dispose() async {
    await update(false);
    final bus = _bus;
    _bus = null;
    if (bus != null) {
      try {
        await bus.close();
      } catch (_) {}
    }
  }
}
