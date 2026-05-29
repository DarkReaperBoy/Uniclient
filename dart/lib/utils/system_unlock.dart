import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

enum UnlockType { none, defaultUnlock, biometrics, companion }

enum SystemUnlockResult { success, cancelled, floodError }

/// Mirrors AyuGram / desktop-app-toolkit's `base::SystemUnlockAvailability`
/// (lib_base/base/system_unlock.h:14-23). The cross-platform contract has four
/// fields. `known` is platform-agnostic: it tells callers whether the status has
/// actually been determined yet. Without it there is no way to distinguish
/// "not checked yet" from "checked, unavailable".
class SystemUnlockStatus {
  /// Whether availability has actually been probed. `false` means "unknown".
  final bool known;

  /// General device authentication is available (a system passcode / credential
  /// exists). The LAPolicyDeviceOwnerAuthentication equivalent — `isDeviceSupported()`
  /// here, UserConsentVerifier availability on Windows.
  final bool available;

  /// A usable, enrolled biometric (fingerprint / face / iris) is present. The
  /// LAPolicyDeviceOwnerAuthenticationWithBiometrics equivalent. Independent of
  /// [available] (matches the mac impl, which probes the two policies separately).
  final bool withBiometrics;

  /// A companion device (Apple Watch) can authorize unlock
  /// (LAPolicyDeviceOwnerAuthenticationWithWatch on macOS 10.15+). `local_auth`
  /// exposes no equivalent query, so this is always `false` on the platforms it
  /// supports — matching AyuGram's Linux stub, which also reports no companion
  /// support. Detecting it would require a macOS-specific platform channel.
  final bool withCompanion;

  const SystemUnlockStatus({
    this.known = false,
    this.available = false,
    this.withBiometrics = false,
    this.withCompanion = false,
  });

  UnlockType get unlockType {
    if (!known) return UnlockType.none;
    if (withBiometrics) return UnlockType.biometrics;
    if (withCompanion) return UnlockType.companion;
    if (available) return UnlockType.defaultUnlock;
    return UnlockType.none;
  }
}

/// Cached availability, mirroring AyuGram's static `rpl::variable`
/// (base_system_unlock_mac.mm:50). A cheap refresh (`lookupDetails == false`)
/// recomputes `available` but carries the previously-detected biometric /
/// companion details forward, gated by the previously-known availability
/// (base_system_unlock_mac.mm:53-56). The first probe always looks up details so
/// the default no-arg call still fully populates the status.
SystemUnlockStatus _cachedStatus = const SystemUnlockStatus();

/// Probes system-unlock availability. Pass [lookupDetails] `true` to force a full
/// re-probe of biometric/companion capability (e.g. after the user enrols a
/// fingerprint in system settings and returns to the app); otherwise a cheap
/// refresh recomputes only general availability and reuses the cached details.
Future<SystemUnlockStatus> getSystemUnlockStatus({
  bool lookupDetails = false,
}) async {
  if (kIsWeb) {
    // We know web offers no system unlock — a determined (known) result.
    return _cachedStatus = const SystemUnlockStatus(known: true);
  }
  final auth = LocalAuthentication();
  final cached = _cachedStatus;
  // Probe details on an explicit request, or the first time we run, so the
  // default no-arg call still detects biometrics like the previous behaviour.
  final fullProbe = lookupDetails || !cached.known;
  try {
    // General device authentication (passcode / credential, with biometric
    // fallback). The LAPolicyDeviceOwnerAuthentication equivalent — kept separate
    // from the biometric-specific check rather than OR'd into one flag.
    final available = await auth.isDeviceSupported();

    bool withBiometrics;
    bool withCompanion;
    if (fullProbe) {
      // Biometric-specific availability is an independent flag: hardware present
      // AND at least one biometric actually enrolled. `getAvailableBiometrics`
      // may report `strong`/`weak` on Android, not just fingerprint/face/iris,
      // so test for any enrolled type.
      final canCheck = await auth.canCheckBiometrics;
      final enrolled = canCheck
          ? await auth.getAvailableBiometrics()
          : const <BiometricType>[];
      withBiometrics = canCheck && enrolled.isNotEmpty;
      // No Apple-Watch-style companion query in local_auth (see field doc).
      withCompanion = false;
    } else {
      // Cheap refresh: carry the last detected details forward, gated by the
      // previously-known availability (base_system_unlock_mac.mm:55-56).
      withBiometrics = cached.available && cached.withBiometrics;
      withCompanion = cached.available && cached.withCompanion;
    }

    return _cachedStatus = SystemUnlockStatus(
      known: true,
      available: available,
      withBiometrics: withBiometrics,
      withCompanion: withCompanion,
    );
  } catch (_) {
    // A thrown exception (e.g. no local_auth plugin on Linux/desktop) still
    // counts as "checked": we determined the platform offers no system unlock.
    // This matches AyuGram's Linux behaviour (known: true, everything else false).
    return _cachedStatus = const SystemUnlockStatus(known: true);
  }
}

Future<SystemUnlockResult> attemptSystemUnlock() async {
  if (kIsWeb) return SystemUnlockResult.cancelled;
  final auth = LocalAuthentication();
  try {
    final didAuth = await auth.authenticate(
      localizedReason: 'Confirm your identity to unlock the app',
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );
    return didAuth ? SystemUnlockResult.success : SystemUnlockResult.cancelled;
  } on PlatformException catch (e) {
    // Only a real lockout (too many failed attempts) maps to FloodError,
    // mirroring AyuGram's `error.code == LAErrorTouchIDLockout` check
    // (base_system_unlock_mac.mm:76). User cancellation, missing hardware,
    // not-enrolled, etc. are plain cancellations, not flood errors.
    if (e.code == auth_error.lockedOut ||
        e.code == auth_error.permanentlyLockedOut) {
      return SystemUnlockResult.floodError;
    }
    return SystemUnlockResult.cancelled;
  } catch (_) {
    // Non-platform errors (cancellation, invalid state) are not flood errors.
    return SystemUnlockResult.cancelled;
  }
}

String getSystemUnlockLabel(UnlockType type) {
  if (type == UnlockType.none) return '';
  if (!kIsWeb && Platform.isWindows) return 'Use Windows Hello';
  switch (type) {
    case UnlockType.biometrics:
      if (!kIsWeb && Platform.isAndroid) return 'Use biometrics';
      return 'Use Touch ID';
    case UnlockType.companion:
      return 'Use Apple Watch';
    case UnlockType.defaultUnlock:
      return 'Use system password';
    case UnlockType.none:
      return '';
  }
}

IconData getSystemUnlockIcon(UnlockType type) {
  if (!kIsWeb && Platform.isWindows) return Icons.security;
  switch (type) {
    case UnlockType.biometrics:
      return Icons.fingerprint;
    case UnlockType.companion:
      return Icons.watch;
    case UnlockType.defaultUnlock:
      return Icons.admin_panel_settings;
    case UnlockType.none:
      return Icons.admin_panel_settings;
  }
}
