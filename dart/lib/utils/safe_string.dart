/// Sanitize a string for safe display in Flutter's text renderer.
///
/// Replaces any lone (unpaired) UTF-16 surrogates with U+FFFD replacement
/// character. Valid surrogate pairs are preserved. This prevents
/// "string is not well-formed UTF-16" errors from Skia/Impeller.
String safeStr(String s) {
  if (s.isEmpty) return s;

  // Fast path: check if we even need sanitization.
  bool needsSanitize = false;
  for (var i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    if (code >= 0xD800 && code <= 0xDFFF) {
      needsSanitize = true;
      break;
    }
  }
  if (!needsSanitize) return s;

  // Direct surrogate pair validation — replace lone surrogates with U+FFFD.
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    if (code >= 0xD800 && code <= 0xDBFF) {
      // High surrogate — must be followed by low surrogate.
      if (i + 1 < s.length) {
        final next = s.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          buf.writeCharCode(code);
          buf.writeCharCode(next);
          i++; // skip the paired low surrogate
          continue;
        }
      }
      buf.writeCharCode(0xFFFD); // lone high surrogate
    } else if (code >= 0xDC00 && code <= 0xDFFF) {
      buf.writeCharCode(0xFFFD); // lone low surrogate
    } else {
      buf.writeCharCode(code);
    }
  }
  return buf.toString();
}

/// Get the first user-visible character from a string,
/// safe for use in Text/TextSpan. Never splits a surrogate pair.
/// Returns '?' if the string is empty.
String safeInitial(String s) {
  if (s.isEmpty) return '?';
  final code = s.codeUnitAt(0);
  // If it's a high surrogate, take both units of the pair.
  if (code >= 0xD800 && code <= 0xDBFF && s.length > 1) {
    return String.fromCharCodes([code, s.codeUnitAt(1)]).toUpperCase();
  }
  return String.fromCharCode(code).toUpperCase();
}

/// Whether Zalgo-stripping is active. Mirrors AyuGram's global
/// `AyuSettings::getInstance().filterZalgo()` singleton — set once from the
/// persisted setting at startup (and on change) by AppState. AyuGram reads the
/// setting at name/text display time and shows a restart prompt on toggle, so
/// filtering newly-built strings (and everything after a restart) matches.
bool gFilterZalgo = false;

/// Matches a run of 3+ combining marks (`\p{Mn}{3,}`) or a bidi-control
/// character — the exact "Zalgo" pattern AyuGram strips
/// (telegram_helpers.cpp:75 kZalgoPattern).
final RegExp _zalgoRegExp = RegExp(
  r'\p{Mn}{3,}|[\u202A-\u202E\u2066-\u2069\u200E\u200F\u061C]',
  unicode: true,
);

/// Port of AyuGram's `filterZalgo` (telegram_helpers.cpp:1260): replaces each
/// Zalgo/bidi character with U+2060 (word joiner, zero-width) so the surrounding
/// base characters render cleanly while string length/positions are preserved.
/// No-op (returns the input untouched, zero regex cost) unless [gFilterZalgo].
String filterZalgo(String text) {
  if (!gFilterZalgo || text.isEmpty) return text;
  return text.replaceAllMapped(
    _zalgoRegExp,
    (m) => '\u2060' * m.group(0)!.length,
  );
}

/// Truncate a string to [maxLen] code units without splitting a surrogate pair.
/// Appends '...' if truncated.
String safeTruncate(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  var end = maxLen;
  // If we'd cut in the middle of a surrogate pair, back up one.
  if (end > 0) {
    final code = s.codeUnitAt(end - 1);
    if (code >= 0xD800 && code <= 0xDBFF) end--;
  }
  return '${s.substring(0, end)}...';
}
