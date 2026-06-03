import 'dart:io';
import 'dart:typed_data';

/// Reads a raw image from the system clipboard, returning its PNG bytes, or
/// null if the clipboard holds no image. Mirrors AyuGram's
/// `QGuiApplication::clipboard()->mimeData()->hasImage()` path used by
/// `showPhotoMenu` ("Photo from clipboard"). Uses platform tools because
/// Flutter's `Clipboard` only exposes text.
Future<Uint8List?> getClipboardImage() async {
  if (Platform.isLinux) {
    try {
      final result = await Process.run('wl-paste', ['--type', 'image/png'],
          stdoutEncoding: null);
      if (result.exitCode == 0 && (result.stdout as List<int>).isNotEmpty) {
        return Uint8List.fromList(result.stdout as List<int>);
      }
    } catch (_) {}
    try {
      final result = await Process.run('xclip',
          ['-selection', 'clipboard', '-t', 'image/png', '-o'],
          stdoutEncoding: null);
      if (result.exitCode == 0 && (result.stdout as List<int>).isNotEmpty) {
        return Uint8List.fromList(result.stdout as List<int>);
      }
    } catch (_) {}
  } else if (Platform.isMacOS) {
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
