import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:uniclient/utils/debug.dart';

/// Thrown by [getClipboardImage] when the platform clipboard-image tool is not
/// available (Linux: neither `wl-paste` from wl-clipboard nor `xclip` is
/// installed / on PATH). This is deliberately distinct from "the clipboard
/// holds no image" — which [getClipboardImage] signals by returning null — so
/// callers can show an accurate diagnostic ("install wl-clipboard or xclip")
/// instead of the misleading "No image in clipboard". AyuGram reads the
/// clipboard natively via `QGuiApplication::clipboard()->mimeData()` with no
/// external-binary dependency, so this failure mode never arises there
/// (userpic_button.cpp:383-384).
class ClipboardToolMissingException implements Exception {
  final String message;
  const ClipboardToolMissingException(this.message);
  @override
  String toString() => message;
}

/// Reads a raw image from the system clipboard, returning its PNG bytes, or
/// null if the clipboard holds no image. Mirrors AyuGram's
/// `QGuiApplication::clipboard()->mimeData()->hasImage()` path used by
/// `showPhotoMenu` ("Photo from clipboard"). Qt coerces ANY clipboard image
/// format to a QImage (`qvariant_cast<QImage>(data->imageData())`,
/// userpic_button.cpp:384,391); we reproduce that by accepting any `image/*`
/// MIME type — not just `image/png` — and re-encoding to PNG. Uses platform
/// tools because Flutter's `Clipboard` only exposes text.
///
/// Throws [ClipboardToolMissingException] on Linux when no clipboard tool is
/// installed, so the caller can distinguish "tool missing" from "no image".
Future<Uint8List?> getClipboardImage() async {
  if (Platform.isLinux) {
    return _getLinuxClipboardImage();
  } else if (Platform.isMacOS) {
    // `«class PNGf»` makes AppleScript coerce any clipboard image to PNG.
    try {
      final tmpPath = '${Directory.systemTemp.path}/uniclient_clip_paste.png';
      final result = await Process.run('osascript', ['-e',
        'set img to the clipboard as «class PNGf»\n'
        'set f to open for access POSIX file "$tmpPath" with write permission\n'
        'write img to f\nclose access f']);
      if (result.exitCode == 0) {
        final file = File(tmpPath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          file.deleteSync();
          return bytes;
        }
      }
    } catch (_) {}
  } else if (Platform.isWindows) {
    // Clipboard.GetImage() returns any clipboard image; Save() writes PNG.
    try {
      final tmpPath = '${Directory.systemTemp.path}\\uniclient_clip_paste.png';
      final result = await Process.run('powershell', ['-command',
        'Add-Type -Assembly System.Windows.Forms; '
        r'$img = [System.Windows.Forms.Clipboard]::GetImage(); '
        'if (\$img -ne \$null) { \$img.Save("$tmpPath") }']);
      if (result.exitCode == 0) {
        final file = File(tmpPath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          file.deleteSync();
          return bytes;
        }
      }
    } catch (_) {}
  }
  return null;
}

/// Linux clipboard-image retrieval. Enumerates the MIME types the clipboard
/// currently offers (via wl-clipboard on Wayland or xclip on X11), picks any
/// `image/*` target — not just `image/png` — and coerces the bytes to PNG,
/// matching Qt's `qvariant_cast<QImage>` behaviour in AyuGram. Throws
/// [ClipboardToolMissingException] if neither tool can even be launched, so the
/// caller never mistakes "no clipboard tool installed" for "no image".
Future<Uint8List?> _getLinuxClipboardImage() async {
  var anyToolRan = false;

  // Wayland — wl-clipboard. `--list-types` prints one offered MIME type per
  // line; we then fetch the chosen one with `--type`.
  final wlTypes = await _runTool('wl-paste', const ['--list-types']);
  if (wlTypes != null) {
    anyToolRan = true;
    final type = _pickImageType(_linesOf(wlTypes.stdout));
    if (type != null) {
      final data = await _runTool('wl-paste', ['--type', type], binary: true);
      if (data != null && data.exitCode == 0) {
        final png = _coerceToPng(_bytesOf(data.stdout), type);
        if (png != null) return png;
      }
    }
  }

  // X11 — xclip. `-t TARGETS -o` lists offered targets; `-t <mime> -o` fetches.
  final xTargets = await _runTool(
      'xclip', const ['-selection', 'clipboard', '-t', 'TARGETS', '-o']);
  if (xTargets != null) {
    anyToolRan = true;
    final type = _pickImageType(_linesOf(xTargets.stdout));
    if (type != null) {
      final data = await _runTool(
          'xclip', ['-selection', 'clipboard', '-t', type, '-o'],
          binary: true);
      if (data != null && data.exitCode == 0) {
        final png = _coerceToPng(_bytesOf(data.stdout), type);
        if (png != null) return png;
      }
    }
  }

  if (!anyToolRan) {
    const msg = 'Clipboard image paste needs wl-clipboard (Wayland) or xclip '
        '(X11) — neither is installed. Install one and try again.';
    Debug.log('clipboard_image', msg);
    throw const ClipboardToolMissingException(msg);
  }
  return null; // a tool ran; the clipboard simply has no image
}

/// Runs a clipboard CLI tool. Returns its [ProcessResult], or null if the tool
/// could not even be launched (not installed / not on PATH) — distinct from the
/// tool running and reporting no data, so callers can tell the two apart.
Future<ProcessResult?> _runTool(String exe, List<String> args,
    {bool binary = false}) async {
  try {
    return await Process.run(exe, args,
        stdoutEncoding: binary ? null : systemEncoding);
  } on ProcessException {
    return null; // binary missing / not on PATH
  }
}

/// Picks the best `image/*` MIME type from a list of clipboard targets,
/// preferring `image/png` (no re-encode needed) then any other image format
/// (jpeg/bmp/tiff/webp/…). Returns null when no image type is offered.
String? _pickImageType(List<String> types) {
  final images = types
      .map((t) => t.trim())
      .where((t) => t.startsWith('image/'))
      .toList();
  if (images.isEmpty) return null;
  return images.contains('image/png') ? 'image/png' : images.first;
}

/// Coerces raw clipboard image bytes of any format to PNG, mirroring Qt's
/// `qvariant_cast<QImage>(...)` coercion. `image/png` passes through untouched;
/// other formats are decoded and re-encoded so the PhotoCropEditor (which uses
/// `ui.instantiateImageCodec`, lacking TIFF support) accepts them. Returns null
/// for empty data; on an undecodable payload, hands back the raw bytes as a
/// best effort for the downstream decoder.
Uint8List? _coerceToPng(Uint8List? raw, String sourceType) {
  if (raw == null || raw.isEmpty) return null;
  if (sourceType == 'image/png') return raw;
  try {
    final decoded = img.decodeImage(raw);
    if (decoded != null) {
      return Uint8List.fromList(img.encodePng(decoded));
    }
    Debug.log('clipboard_image',
        'could not decode clipboard image of type $sourceType; passing raw bytes');
  } catch (e) {
    Debug.log('clipboard_image', 'PNG coercion failed for $sourceType: $e');
  }
  return raw; // best effort: let the downstream decoder try the raw bytes
}

/// Splits a tool's text stdout into lines.
List<String> _linesOf(Object? stdout) {
  if (stdout is String) return stdout.split('\n');
  if (stdout is List<int>) return systemEncoding.decode(stdout).split('\n');
  return const [];
}

/// Normalises a tool's binary stdout to [Uint8List].
Uint8List? _bytesOf(Object? stdout) {
  if (stdout is Uint8List) return stdout;
  if (stdout is List<int>) return Uint8List.fromList(stdout);
  return null;
}
