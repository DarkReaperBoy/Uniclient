import 'dart:ui' show PlatformDispatcher;

/// Assistive-technology detection **without shelling out** to `pgrep orca` /
/// `gdbus` / `defaults` / `powershell`.
///
/// Uses Flutter's built-in accessibility signal, which is pure-Dart and
/// cross-platform. Caveat: on desktop Linux the embedder does not always
/// surface screen-reader state, so this can under-report there; a future
/// `org.a11y.Bus` D-Bus probe (via the `dbus` package) could refine it, but we
/// deliberately avoid re-introducing a CLI hack for a best-effort hint.
class NativeA11y {
  NativeA11y._();

  /// Whether a screen reader / assistive navigation appears to be active.
  static bool get screenReaderActive =>
      PlatformDispatcher.instance.accessibilityFeatures.accessibleNavigation;
}
