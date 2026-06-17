import 'package:media_kit/media_kit.dart';

/// Forces `force-window=no` on the underlying libmpv instance so it can never
/// open its own top-level window, even if a [VideoController]'s GPU render
/// context fails to initialise (NVIDIA + Wayland fallback).
///
/// The call waits for player/VideoController initialisation internally and is a
/// no-op once the texture render API is active, so it is safe to fire and
/// forget. Errors (e.g. the player being disposed before init completes) are
/// swallowed.
void hardenPlayer(Player player) {
  final platform = player.platform;
  if (platform is NativePlayer) {
    platform.setProperty('force-window', 'no').catchError((Object _) {});
  }
}
