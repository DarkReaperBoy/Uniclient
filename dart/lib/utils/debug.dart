import 'dart:io';

/// Global debug logger. Toggle via Settings → Debug mode.
class Debug {
  static bool enabled = true;

  static void log(String tag, String message) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    stderr.writeln('[$ts] $tag: $message');
  }

  static void error(String tag, String message, [Object? err, StackTrace? stack]) {
    // Always print errors regardless of debug mode.
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    stderr.writeln('[$ts] ERROR $tag: $message');
    if (err != null) stderr.writeln('  $err');
    if (stack != null) stderr.writeln('  ${stack.toString().split('\n').take(5).join('\n  ')}');
  }
}
