# Native De-Hack Sweep — replacing Linux/OS CLI shell-outs with native Flutter

**Goal:** the Flutter app was shelling out to OS CLI tools (`xdg-open`, `wl-paste`,
`pactl`, `fc-list`, `geoclue-where-am-i`, `notify-send`, `reg`, `gsettings`, …) —
non-cross-platform and, most visibly, the "music opens an mpv window" report.
This sweep replaces those with native Flutter / pure-Dart paths, guided by the
project rule **pure Go + Dart, ZERO Rust/CGo**. Standard Flutter platform-channel
plugins are acceptable (the app already uses media_kit, record, webview, etc.);
Rust-based plugins (e.g. `super_clipboard`) are NOT — no Rust toolchain exists in
the nix dev shell and it is out of spirit.

## The "mpv window" — root cause + fix
- `media_kit` (libmpv) **already defaults `vid=no`** for any `Player` without a
  `VideoController` (real.dart:2325), so the in-app audio player does NOT open a
  window on its own. The visible "opens mpv" was the OS **file-open** path:
  `xdg-open`/`open` handed a media file to the system player (mpv).
- Fixes shipped:
  1. **Explicit guard:** `audio_service.dart` + `notification_sound.dart` now call
     `player.setVideoTrack(VideoTrack.no())` so cover-art audio / round-video audio
     can never spawn libmpv's own window, even if media_kit's default changes.
  2. **File-open de-hack** (below) routes file opening through `url_launcher`
     instead of `xdg-open`, and media stays in-app.

## CLI → native replacement map (DONE, builds green)
| Category | Was (CLI) | Now | Helper / dep |
|---|---|---|---|
| Open file / reveal in folder | `xdg-open`/`open`/`explorer`/`open -R` | `url_launcher` | `utils/native_files.dart` |
| Image clipboard read/write | `wl-paste`/`wl-copy`/`xclip`/`osascript`/`powershell` | `pasteboard` plugin (+ Flutter `Clipboard` for text) | `utils/native_clipboard.dart` (dep `pasteboard`) |
| System font list | `fc-list`/`system_profiler`/`osascript`/`powershell` | `system_fonts` `getFontList()` | `utils/native_fonts.dart` (dep `system_fonts`) |
| Current location | `geoclue-where-am-i` | `geolocator` (non-Linux) + manual picker (Linux) | `utils/native_location.dart` (dep `geolocator`) |
| Screen-reader detect | `pgrep orca`/`gdbus`/`defaults`/`powershell` | Flutter `accessibilityFeatures` | `utils/native_a11y.dart` |
| Test notification | `notify-send`/`osascript` | app's own in-app notification preview | (reuses existing) |
| Launch at startup | `reg add/delete` (Win-only) | `launch_at_startup` (cross-platform) | dep `launch_at_startup` |
| OS sound-settings panel | `gnome-control-center`/`pavucontrol`/`control`/`open` | removed (no cross-platform API) | — |
| OS accent color | `gsettings`/`reg`/`defaults` | KDE via pure `kdeglobals` file read; option hidden elsewhere (no fake value) | — |
| Power-profile detect | `powerprofilesctl`/`gdbus` | dropped → assume balanced | — |

### New dependencies (all platform-channel, no Rust)
`launch_at_startup`, `pasteboard`, `system_fonts`, `geolocator`. (`screen_capturer`
+ `screen_retriever` were briefly added then removed — see screenshare below.)

### Helpers added under `dart/lib/utils/`
`native_files.dart`, `native_clipboard.dart`, `native_fonts.dart`,
`native_location.dart`, `native_a11y.dart`.

## Deliberate EXCEPTIONS (kept on purpose, documented in-code)
1. **`tg://` URL-scheme handler registration** (`ayu_other_page.dart`,
   `xdg-mime`/`reg`/`lsregister`): no Flutter API to "become the OS default
   protocol handler" — it's an install-time/packaging concern. Left guarded + TODO.
2. **Self-update** (`advanced_settings_screen.dart`, `chmod +x` + detached
   `bash mv && exec`): `dart:io` has no chmod, and a process cannot overwrite its
   own running binary then relaunch itself — the detached helper is the canonical
   self-replace pattern. Legitimate, not a hack.
3. **Audio-device enumeration + screenshare/window capture** (`confirm_box.dart`,
   `call_screen.dart`: `pactl`/`pw-cli`/`kdotool`/`xrandr`/`wmctrl`/`grim`): these
   belong to the **calls/screenshare** feature, which is OUT OF SCOPE for the
   current main-chat work. Left untouched with `// TODO(de-hack deferred)` markers.
   (media_kit can list output devices but needs a live `Player`; revisit with calls.)
4. **webp sticker encode** (`send_files_box.dart`, optional `ffmpeg`/`magick`/
   `cwebp`): no pure-Dart webp ENCODER exists (the `image` pkg decodes webp but
   cannot encode). Only runs on the explicit "send as sticker" path and degrades
   gracefully if no tool is present. Kept as documented exception (removing it
   would silently send a photo instead of a sticker — a worse, fake outcome).
5. **App self-relaunch** (`Process.start(Platform.resolvedExecutable, ['--account', …])`
   in `main.dart`, `hamburger_drawer.dart`, `my_profile_page.dart`, etc.): the
   legitimate multi-account "open another window" mechanism. Kept (desktop-only by UI).

## Verification status
- All edits **compile** (`scripts/build_flutter.sh linux debug` green after each wave).
- **Runtime still to confirm** (next launch): `pasteboard` actually reading an image
  off the Linux clipboard (if it returns null on Linux at runtime, remove image
  paste/copy per the agreed "no pure option → remove" rule; text clipboard is
  unaffected). Also confirm no stray window when playing music/round-video.

## Follow-ups
- Re-test image paste (Ctrl+V) into compose + "copy image" from media viewer on Linux.
- When calls work resumes: de-hack audio-device enum (media_kit/record) + screenshare.
