import 'package:system_fonts/system_fonts.dart';

/// System font enumeration **without shelling out** to `fc-list` /
/// `system_profiler` / `osascript` / `powershell`.
///
/// Uses the `system_fonts` plugin (Windows / macOS / Linux via platform
/// channels — no Rust, no subprocess). The result is cached for the session
/// and falls back to a small bundled list if the platform returns nothing.
class NativeFonts {
  NativeFonts._();

  static List<String>? _cache;
  static final SystemFonts _sf = SystemFonts();

  /// Installed system font family names, de-duplicated and sorted
  /// case-insensitively. Cached after the first call.
  static List<String> list() {
    final cached = _cache;
    if (cached != null) return cached;
    List<String> fonts;
    try {
      fonts = _sf.getFontList();
    } catch (_) {
      fonts = const <String>[];
    }
    if (fonts.isEmpty) fonts = List<String>.of(_fallback);
    final out = fonts.toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _cache = out;
    return out;
  }

  /// A reasonable default set when the platform cannot enumerate fonts.
  static const List<String> _fallback = <String>[
    'Inter', 'Roboto', 'Open Sans', 'Noto Sans', 'DejaVu Sans',
    'Liberation Sans', 'Arial', 'Helvetica', 'Segoe UI', 'Ubuntu', 'Cantarell',
  ];
}
