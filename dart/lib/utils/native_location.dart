import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

/// A resolved geographic coordinate.
typedef LatLon = ({double lat, double lon});

/// Current-location lookup **without shelling out** to `geoclue-where-am-i`.
///
/// Uses the `geolocator` plugin (Android / iOS / macOS / Windows / Web — native
/// APIs, no Rust, no subprocess). Linux has no `geolocator` implementation, and
/// talking to geoclue2 over D-Bus directly requires a system whitelist a normal
/// app does not have, so on Linux this returns null and the caller falls back
/// to the manual location picker (which already exists). Either way, the CLI
/// hack is gone.
class NativeLocation {
  NativeLocation._();

  /// Resolves the device's current position, or null if unavailable / denied /
  /// unsupported (caller should then offer manual entry).
  static Future<LatLon?> current() async {
    if (!kIsWeb && Platform.isLinux) return null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition();
      return (lat: pos.latitude, lon: pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
