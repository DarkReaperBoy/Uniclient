import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

enum UnlockType { none, defaultUnlock, biometrics, companion }

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

SystemUnlockStatus getSystemUnlockStatus() {
  if (kIsWeb) return const SystemUnlockStatus();
  if (Platform.isLinux) return const SystemUnlockStatus();
  if (Platform.isWindows) {
    return const SystemUnlockStatus(available: false);
  }
  if (Platform.isMacOS) {
    return const SystemUnlockStatus(available: false);
  }
  return const SystemUnlockStatus();
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

IconDataForUnlock getSystemUnlockIcon(UnlockType type) {
  if (!kIsWeb && Platform.isWindows) return IconDataForUnlock.windowsHello;
  switch (type) {
    case UnlockType.biometrics:
      return IconDataForUnlock.touchId;
    case UnlockType.companion:
      return IconDataForUnlock.watch;
    case UnlockType.defaultUnlock:
      return IconDataForUnlock.password;
    case UnlockType.none:
      return IconDataForUnlock.password;
  }
}

enum IconDataForUnlock { windowsHello, touchId, watch, password }
