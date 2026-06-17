import 'package:media_kit/media_kit.dart';

// Native uses libmpv and can spawn a stray window; web uses HTML <video> and
// cannot. The conditional import picks the matching no-window guard.
import 'mpv_player_native.dart'
    if (dart.library.js_interop) 'mpv_player_web.dart';

/// Creates a media_kit [Player] that is guaranteed never to spawn a stray
/// native libmpv output window — the "mpv window" users occasionally see pop up
/// when playing media.
///
/// A bare `Player()` already initialises with `vo=null` (no video output), so
/// audio-only playback (music, voice notes, notification sounds) can never open
/// a window. The remaining hazard is the desktop *video* path: when a
/// [VideoController] switches the output to libmpv's texture-render API and its
/// GPU/EGL context fails to initialise — a well-known failure mode on NVIDIA +
/// Wayland — libmpv falls back to opening its OWN top-level window. We defend
/// against that on every player by forcing `force-window=no`, so a render
/// failure renders nothing instead of a stray window.
///
/// Every media_kit player in the app MUST be created through this factory so
/// the guarantee holds uniformly. No-op on web.
Player createPlayer() {
  final player = Player();
  hardenPlayer(player);
  return player;
}
