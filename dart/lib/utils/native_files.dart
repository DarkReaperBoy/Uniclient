import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Cross-platform file / folder opening **without shelling out** to
/// `xdg-open` / `open` / `explorer`.
///
/// Every function here routes through `url_launcher`, which dispatches to each
/// OS's native URL handler (`gtk_show_uri` on Linux, `NSWorkspace` on macOS,
/// `ShellExecute` on Windows, the platform intent on Android/iOS) — no
/// subprocess is spawned, and the same call works on every platform Flutter
/// targets. This replaces the per-OS `Process.run` branches that previously
/// littered the UI (the source of the "it launches mpv / a CLI tool" smell).

/// Opens [path] with the operating system's default application for that file
/// type. Returns `true` if the OS accepted the request.
Future<bool> openFileExternally(String path) async {
  if (path.isEmpty) return false;
  try {
    return await launchUrl(Uri.file(path));
  } catch (_) {
    return false;
  }
}

/// Reveals [path] in the system file manager by opening its containing folder.
///
/// Flutter has no cross-platform "select this file in the manager" primitive
/// (that is what `explorer /select,` and `open -R` did), so we open the parent
/// directory instead — the de-hack trade-off is losing the highlight, not the
/// reveal. If [path] is itself a directory it is opened directly.
Future<bool> revealInFolder(String path) async {
  if (path.isEmpty) return false;
  final dir =
      FileSystemEntity.isDirectorySync(path) ? path : File(path).parent.path;
  return openFolder(dir);
}

/// Opens [dirPath] in the system file manager.
Future<bool> openFolder(String dirPath) async {
  if (dirPath.isEmpty) return false;
  try {
    return await launchUrl(Uri.directory(dirPath));
  } catch (_) {
    return false;
  }
}
