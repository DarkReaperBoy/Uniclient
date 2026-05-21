import 'dart:io';

class Debug {
  static bool enabled = true;
  static bool crashReportingEnabled = true;
  static String _crashLogDir = '';

  static void setCrashLogDir(String dir) {
    _crashLogDir = dir;
  }

  static void log(String tag, String message) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    stderr.writeln('[$ts] $tag: $message');
  }

  static void error(String tag, String message, [Object? err, StackTrace? stack]) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    stderr.writeln('[$ts] ERROR $tag: $message');
    if (err != null) stderr.writeln('  $err');
    if (stack != null) stderr.writeln('  ${stack.toString().split('\n').take(5).join('\n  ')}');
    if (crashReportingEnabled && _crashLogDir.isNotEmpty) {
      _appendCrashLog(ts, tag, message, err, stack);
    }
  }

  static void _appendCrashLog(String ts, String tag, String message, Object? err, StackTrace? stack) {
    try {
      final dir = Directory(_crashLogDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/crash_$today.log');
      final buf = StringBuffer()
        ..writeln('[$ts] $tag: $message');
      if (err != null) buf.writeln('  $err');
      if (stack != null) buf.writeln('  ${stack.toString().split('\n').take(10).join('\n  ')}');
      buf.writeln();
      file.writeAsStringSync(buf.toString(), mode: FileMode.append);
    } catch (_) {}
  }
}
