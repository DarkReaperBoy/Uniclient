import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:local_auth/local_auth.dart';

enum UnlockType { none, defaultUnlock, biometrics, companion }

enum SystemUnlockResult { success, cancelled, floodError }

class SystemUnlockStatus {
  final bool available;
  final bool withBiometrics;
  final bool withCompanion;

  const SystemUnlockStatus({
    this.available = false,
    this.withBiometrics = false,
    this.withCompanion = false,
  });

  UnlockType get unlockType {
    if (withBiometrics) return UnlockType.biometrics;
    if (withCompanion) return UnlockType.companion;
    if (available) return UnlockType.defaultUnlock;
    return UnlockType.none;
  }
}

Future<SystemUnlockStatus> getSystemUnlockStatus() async {
  if (kIsWeb) return const SystemUnlockStatus();
  final auth = LocalAuthentication();
  try {
    final canAuth = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    if (!canAuth) return const SystemUnlockStatus();
    final biometrics = await auth.getAvailableBiometrics();
    final hasBiometrics = biometrics.contains(BiometricType.fingerprint) ||
        biometrics.contains(BiometricType.face) ||
        biometrics.contains(BiometricType.iris);
    return SystemUnlockStatus(
      available: true,
      withBiometrics: hasBiometrics,
    );
  } catch (_) {
    return const SystemUnlockStatus();
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
  } catch (_) {
    return SystemUnlockResult.floodError;
  }
}

String getSystemUnlockLabel(UnlockType type) {
  if (!kIsWeb && Platform.isWindows) return 'Use Windows Hello';
  switch (type) {
    case UnlockType.biometrics:
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
      return Icons.lock_open_outlined;
    case UnlockType.none:
      return Icons.lock_open_outlined;
  }
}
