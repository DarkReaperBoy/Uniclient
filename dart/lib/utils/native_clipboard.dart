import 'dart:typed_data';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pasteboard/pasteboard.dart';

/// Cross-platform clipboard access **without shelling out** to
/// `wl-paste` / `wl-copy` / `xclip` / `osascript` / `powershell`.
///
/// Plain text goes through Flutter's built-in [Clipboard]; images and file
/// lists go through the `pasteboard` plugin (platform channels — no Rust, no
/// subprocess), which covers every platform Flutter targets behind one API.
/// This replaces the per-OS `Process.run` clipboard branches that were the
/// "it shells out to Linux CLI tools" smell.
class NativeClipboard {
  /// Reads a raster image off the clipboard as PNG bytes, or null if the
  /// clipboard holds no image.
  static Future<Uint8List?> readImage() => Pasteboard.image;

  /// Writes [bytes] (PNG-encoded) to the clipboard as an image.
  static Future<void> writeImage(Uint8List bytes) => Pasteboard.writeImage(bytes);

  /// File paths currently on the clipboard (empty if none).
  static Future<List<String>> readFiles() => Pasteboard.files();

  /// Places the given file [paths] on the clipboard.
  static Future<bool> writeFiles(List<String> paths) => Pasteboard.writeFiles(paths);

  /// Plain text on the clipboard, or null.
  static Future<String?> readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  /// Writes plain [text] to the clipboard.
  static Future<void> writeText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
