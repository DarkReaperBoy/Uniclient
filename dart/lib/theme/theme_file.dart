import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'telegram_palette.dart';

const _maxThemeFileSize = 5 * 1024 * 1024; // 5 MB
const _maxPaletteFileSize = 1 * 1024 * 1024; // 1 MB
const _kBackgroundMaxPixels = 25 * 1024 * 1024; // matches AyuGram kBackgroundSizeLimit

class ThemeFileData {
  final TelegramPalette palette;
  final Uint8List? backgroundImage;
  final bool backgroundTiled;
  final CloudThemeMeta? cloudMeta;
  final Map<String, String> referenceChain;
  final Set<String> explicitTokens;

  const ThemeFileData({
    required this.palette,
    this.backgroundImage,
    this.backgroundTiled = false,
    this.cloudMeta,
    this.referenceChain = const {},
    this.explicitTokens = const {},
  });
}

class CloudThemeMeta {
  final int id;
  final int accessHash;
  final String? title;
  final String? slug;

  const CloudThemeMeta({required this.id, required this.accessHash, this.title, this.slug});
}

ThemeFileData? parseThemeFile(
  Uint8List bytes, {
  TelegramPalette fallback = TelegramPalette.dayBlue,
}) {
  if (bytes.length > _maxThemeFileSize) return null;

  if (_looksLikeZip(bytes)) {
    return _parseZipTheme(bytes, fallback);
  }

  final text = utf8.decode(bytes, allowMalformed: true);
  if (text.length > _maxPaletteFileSize) return null;
  final result = parsePaletteText(text, fallback: fallback);
  if (result == null) return null;
  return ThemeFileData(palette: result.palette, cloudMeta: result.cloudMeta, referenceChain: result.referenceChain, explicitTokens: result.explicitTokens);
}

class PaletteParseResult {
  final TelegramPalette palette;
  final CloudThemeMeta? cloudMeta;
  final Map<String, String> referenceChain;
  final Set<String> explicitTokens;
  const PaletteParseResult({
    required this.palette,
    this.cloudMeta,
    this.referenceChain = const {},
    this.explicitTokens = const {},
  });
}

PaletteParseResult? parsePaletteText(
  String text, {
  TelegramPalette fallback = TelegramPalette.dayBlue,
}) {
  final fallbackMap = paletteToMap(fallback);
  final paletteKeys = fallbackMap.keys.toSet();
  // Cloud-theme service metadata lives in `// THEME EDITOR SERVICE INFO` lines,
  // which are `//` comments — invisible to the palette tokenizer below once
  // comments are stripped. AyuGram reads it in a SEPARATE pass over the raw text
  // (`ReadCloudFromText`, window_theme_editor.cpp:357-381), NOT as part of
  // `ReadPaletteValues`; we mirror that by extracting it from the un-stripped text.
  final CloudThemeMeta? cloudMeta = readCloudMeta(text);

  // ── Pass 1: STREAMING tokenize into ordered (name, value) pairs ──
  // Mirrors AyuGram's `ReadPaletteValues` (window_theme.cpp:1514-1537): strip all
  // C-style comments (`base::parse::stripComments`), then run a whitespace-delimited
  // loop of `readNameAndValue` (window_theme.cpp:122-164) that is NEWLINE-AGNOSTIC.
  // A declaration may span physical lines (`windowBg:\n#ffffff;`) and several pairs
  // may share one line (`windowBg: #fff; windowFg: #000;`) — the previous line-based
  // `split('\n')` mis-parsed both (the former hard-rejected the whole theme, the
  // latter silently dropped colors). AyuGram HARD-REJECTS the entire theme on ANY
  // structural syntax error (`readNameAndValue` → false → `ReadPaletteValues` →
  // false → `LoadTheme` declines and the previous theme stays — user sees "Theme
  // Error"). The rejecting conditions are: an empty name (:129-132), a missing `:`
  // separator (:137-140), an empty value token (:148-151), and a missing trailing
  // `;` (:158-161). We reproduce each by returning null — the caller then keeps the
  // previous theme instead of loading a partial palette. (Bad hex DIGITS and
  // unresolved references are NOT structural errors: AyuGram skips those in
  // `setColorSchemeValue` and keeps loading — handled in pass 2.)
  final stripped = _stripComments(text);
  final entries = <MapEntry<String, String>>[];
  var pos = 0;
  final end = stripped.length;
  while (true) {
    final nv = _readNameAndValue(stripped, pos, end);
    if (nv == null) return null; // structural syntax error → hard reject
    pos = nv.next;
    if (nv.name == null) break; // skipWhitespaces reached end → done (empty name)
    entries.add(MapEntry(nv.name!, nv.value!));
  }

  // ── Pass 2: resolve values STRICTLY IN-ORDER, single pass ──
  // Mirrors `loadColorScheme` + `setColorSchemeValue` + `palette::setColor`
  // (window_theme.cpp:170-232, style_core_palette.cpp:104-136). For `name: ref`,
  // `setColor(name, from)` copies `from`'s value ONLY if `from` was already
  // explicitly Loaded EARLIER in this file (style_core_palette.cpp:130-131);
  // a forward reference, or a reference to a palette key the theme never sets,
  // returns ValueNotFound → skipped (window_theme.cpp:206-208), leaving `name`
  // to take ITS OWN default at finalize(). Names that are not palette keys are
  // recorded in `unsupported` so later lines can reference them, and a value is
  // resolved through that map first (window_theme.cpp:222-230). This replaces the
  // previous order-independent fixpoint + `fallbackMap[ref]` substitution, which
  // resolved forward refs and wrongly gave `name` the *referenced* key's default.
  final resolved = <String, Color>{}; // palette key -> explicit color (Loaded)
  final loaded = <String>{}; // palette keys that are Loaded
  final unsupported = <String, String>{}; // non-palette name -> resolved value
  final referenceChain = <String, String>{};

  for (final entry in entries) {
    final name = entry.key;
    // window_theme.cpp:225 — resolve the value through previously-seen
    // unsupported (custom intermediate) keys before interpreting it.
    final value = unsupported[entry.value] ?? entry.value;
    final isPaletteKey = paletteKeys.contains(name);

    if (_isHexShaped(value)) {
      final color = _parseHexColor(value);
      if (color == null) {
        // Right shape, bad hex digit → setColorSchemeValue logs and returns Ok
        // (window_theme.cpp:187-189): skip, the color keeps its own default.
        continue;
      }
      if (isPaletteKey) {
        resolved[name] = color;
        loaded.add(name);
      } else {
        unsupported[name] = value; // KeyNotFound → record (window_theme.cpp:228-229)
      }
    } else {
      // Reference to another key.
      if (isPaletteKey) {
        referenceChain[name] = value;
        if (paletteKeys.contains(value) && loaded.contains(value)) {
          resolved[name] = resolved[value]!;
          loaded.add(name);
        }
        // else ValueNotFound → skip; `name` keeps its own default.
      } else {
        unsupported[name] = value; // KeyNotFound → record
      }
    }
  }

  // Snapshot the tokens the theme file EXPLICITLY declared (an explicit hex or an
  // in-file reference) BEFORE the cascade below starts writing inherited colors
  // into `resolved`. The editor uses this to split "the theme's own colors" from
  // the rest (`theme_editor.dart:186`); a cascaded key (e.g. menuBg inheriting
  // windowBg) must stay on the "New color scheme keys" side, not masquerade as a
  // user-set token.
  final explicitTokens = {...resolved.keys, ...referenceChain.keys};

  // ── Pass 3: finalize() fallback-chain cascade ──
  // The missing piece AyuGram runs as `out->palette.finalize(paletteColorizer)`
  // right after loadColorScheme (window_theme.cpp:368). `palette::compute(index,
  // fallbackIndex, value)` (style_core_palette.cpp:158-180) copies each color the
  // theme did NOT set from its colors.palette fallback WHEN that fallback is Loaded
  // — set by the theme OR by an earlier cascade step — and marks the inherited
  // color Loaded too, so later links inherit transitively. We replicate it by
  // walking `_paletteFallbacks` in EXACT colors.palette declaration order: a
  // reference key absent from the theme inherits its fallback's resolved value iff
  // that fallback is already loaded. Declaration order is essential and faithful —
  // a forward reference whose fallback is only DEFAULTING (not theme-set, not yet
  // cascaded) keeps its own default, exactly as C++'s in-order compute() leaves it
  // `Created`. (No colorizer here: the user-import / .tdesktop-palette path passes
  // an empty colorizer — window_theme.cpp:294-295 — so compute()'s colorize branch
  // never runs.) Without this, a theme that set only `windowBg: #000000;` left
  // menuBg/msgInBg/… (up to 236 reference colors) at the light dayBlue default;
  // now they cascade to black, matching AyuGram.
  for (final fb in _paletteFallbacks.entries) {
    final name = fb.key;
    if (loaded.contains(name)) continue; // theme set it → status != Initial, skip
    final fallbackColor = resolved[fb.value]; // non-null ⇔ fallback is Loaded
    if (fallbackColor != null) {
      resolved[name] = fallbackColor;
      loaded.add(name); // mark Loaded so a later link can cascade through this one
    }
  }

  final merged = Map<String, Color>.from(fallbackMap)..addAll(resolved);
  final palette = paletteFromMap(merged, fallback);

  return PaletteParseResult(
    palette: palette,
    cloudMeta: cloudMeta,
    referenceChain: referenceChain,
    explicitTokens: explicitTokens,
  );
}

/// Whether `v` has the shape of a hex color literal (`#rrggbb` / `#rrggbbaa`) —
/// the gate AyuGram uses before parsing hex (`data[0]=='#' && (size==7||size==9)`,
/// window_theme.cpp:178). Anything else is treated as a reference to another key.
bool _isHexShaped(String v) =>
    v.startsWith('#') && (v.length == 7 || v.length == 9);

Uint8List exportThemeFile(ThemeFileData data) {
  final archive = Archive();

  final paletteText = _generatePaletteText(data);
  final paletteBytes = Uint8List.fromList(paletteText.codeUnits);
  archive.addFile(ArchiveFile(
    'colors.tdesktop-theme',
    paletteBytes.length,
    paletteBytes,
  ));

  if (data.backgroundImage != null) {
    final isPng = data.backgroundImage!.length >= 8 &&
        data.backgroundImage![0] == 0x89 && data.backgroundImage![1] == 0x50 &&
        data.backgroundImage![2] == 0x4E && data.backgroundImage![3] == 0x47;
    final ext = isPng ? '.png' : '.jpg';
    final bgName = (data.backgroundTiled ? 'tiled' : 'background') + ext;
    archive.addFile(ArchiveFile(
      bgName,
      data.backgroundImage!.length,
      data.backgroundImage!,
    ));
  }

  final encoded = ZipEncoder().encode(archive);
  return encoded is Uint8List ? encoded : Uint8List.fromList(encoded);
}

String writeCloudMeta(CloudThemeMeta meta) {
  return '// THEME EDITOR SERVICE INFO START\n'
      '// ID: ${_uint64ToString(meta.id)}\n'
      '// ACCESS: ${_uint64ToString(meta.accessHash)}\n'
      '// THEME EDITOR SERVICE INFO END\n\n';
}

CloudThemeMeta? readCloudMeta(String text) {
  final startIdx = text.indexOf('// THEME EDITOR SERVICE INFO START');
  final endIdx = text.indexOf('// THEME EDITOR SERVICE INFO END');
  if (startIdx < 0 || endIdx < 0 || endIdx <= startIdx) return null;

  final block = text.substring(startIdx, endIdx);
  int? id;
  int? accessHash;
  for (final rawLine in block.split('\n')) {
    final stripped = rawLine.startsWith('//')
        ? rawLine.substring(2).trim()
        : rawLine.trim();
    final colonPos = stripped.indexOf(': ');
    if (colonPos < 0) continue;
    final key = stripped.substring(0, colonPos).toUpperCase();
    final value = _parseUint64(stripped.substring(colonPos + 2).trim());
    if (value == null) continue;
    if (key == 'ID') id = value;
    if (key == 'ACCESS') accessHash = value;
  }
  if (id == null || accessHash == null) return null;

  return CloudThemeMeta(id: id, accessHash: accessHash);
}

// ── Private helpers ──

/// Strip all C-style comments — `//` to end-of-line and `/* … */` — faithfully
/// porting `base::parse::stripComments` (parse_helper.cpp:13-97). Each comment is
/// replaced by a single space so it can never glue two adjacent tokens together,
/// and every line break is preserved (newlines inside a block comment too). An
/// unterminated `/* …` eats to EOF and is dropped, matching AyuGram. (The C++
/// version also tracks `"`-delimited strings; palette files contain none — a `"`
/// is not a name character so it would be rejected either way — so that branch is
/// intentionally omitted.) The result feeds the whitespace-delimited tokenizer.
String _stripComments(String text) {
  const none = 0, singleLine = 1, multiLine = 2;
  var state = none;
  final buf = StringBuffer();
  var i = 0;
  final n = text.length;
  while (i < n) {
    final c = text.codeUnitAt(i);
    final next = (i + 1 < n) ? text.codeUnitAt(i + 1) : 0;
    if (state == none && c == 0x2F /* / */ && next == 0x2F /* / */) {
      buf.write(' ');
      state = singleLine;
      i += 2;
    } else if (state == singleLine && (c == 0x0A || c == 0x0D)) {
      buf.writeCharCode(c); // the line break that ends the comment is kept
      state = none;
      i++;
    } else if (state == none && c == 0x2F /* / */ && next == 0x2A /* * */) {
      buf.write(' ');
      state = multiLine;
      i += 2;
    } else if (state == multiLine && c == 0x2A /* * */ && next == 0x2F /* / */) {
      state = none;
      i += 2;
    } else if (state == multiLine && (c == 0x0A || c == 0x0D)) {
      buf.writeCharCode(c); // newlines inside a block comment are kept
      i++;
    } else if (state == none) {
      buf.writeCharCode(c);
      i++;
    } else {
      i++; // inside a comment — drop the character
    }
  }
  return buf.toString();
}

/// `base::parse::skipWhitespaces` (parse_helper.h:15-25): advance past spaces,
/// newlines, tabs and CRs. Returns the new offset (callers test `== end`).
int _skipWhitespaces(String s, int from, int end) {
  while (from != end) {
    final c = s.codeUnitAt(from);
    if (c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D) {
      from++;
    } else {
      break;
    }
  }
  return from;
}

/// `base::parse::readName` (parse_helper.h:27-38): read a maximal run of name
/// characters `[A-Za-z0-9_]`. Returns the offset just past the run.
int _readName(String s, int from, int end) {
  while (from != end) {
    final c = s.codeUnitAt(from);
    if ((c >= 0x61 && c <= 0x7A) || // a-z
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x30 && c <= 0x39) || // 0-9
        (c == 0x5F)) {
      // _
      from++;
    } else {
      break;
    }
  }
  return from;
}

/// One step of AyuGram's streaming `readNameAndValue` (window_theme.cpp:122-164),
/// operating on the comment-stripped scheme. Returns the parsed (name, value) and
/// the offset to resume from; `name == null` signals clean end-of-content (the
/// `skipWhitespaces` returned end with nothing left). Returns null on ANY of the
/// four structural errors AyuGram rejects with (empty name, missing `:`, empty
/// value, missing `;`), which the caller turns into a whole-theme rejection.
({String? name, String? value, int next})? _readNameAndValue(
    String s, int from, int end) {
  from = _skipWhitespaces(s, from, end);
  if (from == end) return (name: null, value: null, next: from); // end of content

  final nameStart = from;
  from = _readName(s, from, end);
  if (from == nameStart) return null; // empty name (:129-132)
  final name = s.substring(nameStart, from);

  from = _skipWhitespaces(s, from, end);
  if (from == end) return null; // unexpected end (:133-135)
  if (s.codeUnitAt(from) != 0x3A /* : */) return null; // expected ':' (:137-140)
  from = _skipWhitespaces(s, from + 1, end);
  if (from == end) return null; // unexpected end (:141-143)

  final valueStart = from;
  if (s.codeUnitAt(from) == 0x23 /* # */) from++;
  final valueNameStart = from;
  from = _readName(s, from, end);
  if (from == valueNameStart) return null; // empty value (:148-151)
  final value = s.substring(valueStart, from);

  from = _skipWhitespaces(s, from, end);
  if (from == end) return null; // unexpected end (:154-156)
  if (s.codeUnitAt(from) != 0x3B /* ; */) return null; // expected ';' (:158-161)
  return (name: name, value: value, next: from + 1);
}

bool _looksLikeZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4B &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// Decodes a theme background, enforces AyuGram's pixel-size limit, and forces
/// it OPAQUE — returning the bytes to store/cache, or null when the image can't
/// be decoded or exceeds kBackgroundSizeLimit (25 Mpx). AyuGram treats either
/// failure as "reject the whole theme" (window_theme.cpp:331-342).
///
/// Mirrors AyuGram's `Images::Read({.content=…, .forceOpaque=true})`
/// (window_theme.cpp:336-339): a decoded image carrying an alpha channel is
/// composited over an opaque WHITE background (Ui::Images::Opaque,
/// image_prepare.cpp:1214-1233 — guarded by `if (image.hasAlphaChannel())`), so
/// a transparent PNG no longer renders see-through. AyuGram then caches the
/// flattened result as a BMP; we re-encode it as PNG instead (lossless, far
/// smaller than an uncompressed BMP) so the stored/cached bytes carry NO alpha.
///
/// When the source has no alpha channel (JPEG, opaque PNG/WebP, …) the original
/// bytes are already opaque — exactly the case AyuGram's forceOpaque skips
/// (`result.format != "jpeg"` guard at image_prepare.cpp:506 + Opaque's
/// hasAlphaChannel guard) — so they are returned verbatim, avoiding a pointless
/// decode→re-encode round-trip and the cache bloat it would cause.
Uint8List? _decodeOpaqueBackground(Uint8List bytes) {
  if (bytes.length < 4) return null;
  // AyuGram reads the background by FILENAME only and decodes it FORMAT-AGNOSTICALLY
  // (QImageReader::size() bound check, then Images::Read({.forceOpaque=true}),
  // window_theme.cpp:328-343) — it does NOT gate on JPEG/PNG magic bytes. So a
  // Qt-decodable WebP/BMP stored as `background.png` renders there; gating on magic
  // bytes here (the previous behaviour) rejected the WHOLE theme for inputs AyuGram
  // accepts. We now mirror AyuGram: decode whatever the image library can read.
  //
  // Fast-path bound: when the header IS a measurable PNG/JPEG, read the dimensions
  // cheaply and reject an oversized bitmap before paying for a full decode (mirrors
  // QImageReader::size()). Unmeasurable formats (WebP/BMP/…) fall through to the
  // decode below — exactly AyuGram's path, not an early rejection.
  final dims = _readImageDimensions(bytes);
  if (dims != null) {
    final (w, h) = dims;
    if (w <= 0 || h <= 0 || w * h > _kBackgroundMaxPixels) return null;
  }
  // Full format-agnostic decode ≡ Images::Read: package:image decodes PNG/JPEG/
  // WebP/BMP/GIF/TIFF, matching Qt's broad support. A null/throwing decode is
  // AyuGram's `background.isNull()` → reject. The caller already capped the input
  // at kThemeBackgroundSizeLimit (4 MB), so the decode cost stays bounded even for
  // untrusted archives.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  // Authoritative size check for formats _readImageDimensions can't measure
  // (size.isEmpty() / > kBackgroundSizeLimit, window_theme.cpp:331-334).
  final w = decoded.width, h = decoded.height;
  if (w <= 0 || h <= 0 || w * h > _kBackgroundMaxPixels) return null;

  // forceOpaque: only images WITH an alpha channel need flattening — matching
  // both Read's `result.format != "jpeg"` guard and Opaque's
  // `if (image.hasAlphaChannel())` guard (image_prepare.cpp:506,1215).
  // Image.hasAlpha is true for RGBA (4ch) AND grayscale+alpha (2ch).
  if (!decoded.hasAlpha) return bytes;

  // Composite every pixel over opaque WHITE, exactly like Ui::Images::Opaque:
  // out_rgb = src_rgb·srcA + white·(1−srcA), out_a = 1. compositeImage's default
  // BlendMode.alpha is standard source-over, and a 3-channel white canvas keeps
  // the result strictly opaque (no residual alpha channel survives the encode).
  final opaque = img.Image(width: w, height: h, numChannels: 3);
  img.fill(opaque, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(opaque, decoded);
  try {
    return img.encodePng(opaque);
  } catch (_) {
    return null;
  }
}

(int, int)? _readImageDimensions(Uint8List bytes) {
  if (bytes.length < 24) return null;
  if (bytes[0] == 0x89 && bytes[1] == 0x50) {
    final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return (w > 0 && h > 0) ? (w, h) : null;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) { i++; continue; }
      final marker = bytes[i + 1];
      // All JPEG SOF markers (0xC0-0xCF) carry frame dimensions EXCEPT
      // DHT(0xC4), JPG(0xC8) and DAC(0xCC). AyuGram uses QImageReader::size()
      // which handles every SOF variant, not just SOF0/SOF2.
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        return (w > 0 && h > 0) ? (w, h) : null;
      }
      if (marker == 0xD9 || marker == 0xDA) break;
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      i += 2 + len;
    }
  }
  return null;
}

// AyuGram kThemeBackgroundSizeLimit (window_theme.h:42): backgrounds larger than
// this are rejected to bound memory use when parsing untrusted theme archives.
const int _kThemeBackgroundSizeLimit = 4 * 1024 * 1024;

/// Parses a uint64 decimal string into Dart's signed 64-bit int, preserving the
/// bit pattern. Telegram access hashes are uint64; values with the high bit set
/// exceed int64 max and int.tryParse would return null (silently dropping the
/// cloud-theme metadata). Mirrors AyuGram's toULongLong(). Returns null if the
/// string is not a valid 0..2^64-1 integer.
int? _parseUint64(String s) {
  final b = BigInt.tryParse(s.trim());
  if (b == null || b.isNegative || b.bitLength > 64) return null;
  return b.toSigned(64).toInt();
}

// Serialize a uint64 (stored as a signed Dart int holding the correct MTProto
// bit pattern) as its UNSIGNED decimal string, matching AyuGram's
// QString::number(uint64) (window_theme_editor.cpp:352-353). High-bit-set id /
// accessHash values would otherwise be written as negative (e.g. "-1"), which
// both AyuGram's toULongLong("-1")→0 and our own _parseUint64("-1")→null reject,
// silently dropping the cloud-theme metadata on export round-trip.
String _uint64ToString(int value) => BigInt.from(value).toUnsigned(64).toString();

ThemeFileData? _parseZipTheme(Uint8List bytes, TelegramPalette fallback) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    debugPrint('THEME: ZIP decode failed: $e');
    return null;
  }

  ArchiveFile? bgFile;
  bool tiled = false;

  final Map<String, ArchiveFile> entries = {};
  for (final file in archive) {
    final name = file.name.toLowerCase();
    entries.putIfAbsent(name, () => file);
  }
  // AyuGram (window_theme.cpp:300-307) reads 'colors.tdesktop-theme' FIRST and only
  // falls back to 'colors.tdesktop-palette' when the former is absent — a strict
  // priority, NOT archive iteration order. A zip carrying BOTH (with the palette
  // listed first in the directory) must still load the -theme scheme. entries keeps
  // the first occurrence of each name, so this honors AyuGram's ordering regardless
  // of how the two files are laid out in the zip.
  final ArchiveFile? paletteFile =
      entries['colors.tdesktop-theme'] ?? entries['colors.tdesktop-palette'];
  // AyuGram (window_theme.cpp:262-275) probes backgrounds in a FIXED priority
  // order rather than archive iteration order, marking tiled=true only for the
  // tiled.* names: background.jpg > background.png > tiled.jpg > tiled.png.
  for (final (cname, ctiled) in [
    ('background.jpg', false),
    ('background.png', false),
    ('tiled.jpg', true),
    ('tiled.png', true),
  ]) {
    final f = entries[cname];
    if (f != null) {
      bgFile = f;
      tiled = ctiled;
      break;
    }
  }

  if (paletteFile == null) return null;
  // AyuGram's readCurrentFileContent reads fileInfo.uncompressed_size from the zip
  // directory and bails BEFORE openCurrentFile when it exceeds the limit
  // (zlib_help.h:258-263; the palette is loaded through this kThemeSchemeSizeLimit-
  // bounded path at window_theme.cpp:302-306). Mirror that here: check the
  // directory-recorded uncompressed size (.size — populated from zf.uncompressedSize
  // during decode; archive 4.0.9 only decompresses lazily on .content) BEFORE
  // touching .content, so a zip-bomb (tiny compressed, huge uncompressed) can't be
  // fully expanded into memory before being rejected. Same guard as the background
  // path below (line ~541).
  if (paletteFile.size > _maxPaletteFileSize) {
    debugPrint('THEME: palette too large (${paletteFile.size} bytes) — theme rejected');
    return null;
  }
  final paletteBytes = paletteFile.content as List<int>;

  final text = utf8.decode(paletteBytes, allowMalformed: true);
  final result = parsePaletteText(text, fallback: fallback);
  if (result == null) return null;

  Uint8List? bgBytes;
  if (bgFile != null) {
    // AyuGram bounds the background to kThemeBackgroundSizeLimit (4 MB,
    // window_theme.h:42) and LoadTheme refuses the whole theme if a present
    // background is oversized or invalid. Check the uncompressed size BEFORE
    // touching .content so a zip-bomb can't be fully decompressed into memory.
    if (bgFile.size > _kThemeBackgroundSizeLimit) {
      debugPrint('THEME: background too large (${bgFile.size} bytes) — theme rejected');
      return null;
    }
    final raw = Uint8List.fromList(bgFile.content as List<int>);
    // Decode + size-check + force opaque (AyuGram: QImageReader::size() →
    // Images::Read({.forceOpaque=true}) → cache the decoded image as a BMP,
    // window_theme.cpp:328-355). The returned bytes are guaranteed opaque, so
    // storing AND caching them strips any alpha exactly as AyuGram does — a
    // transparent-PNG wallpaper no longer renders see-through. null means the
    // decode failed or the bitmap exceeded kBackgroundSizeLimit → reject the
    // whole theme.
    final opaque = _decodeOpaqueBackground(raw);
    if (opaque == null) {
      debugPrint('THEME: background image invalid/oversized — theme rejected');
      return null;
    }
    bgBytes = opaque;
  }

  return ThemeFileData(
    palette: result.palette,
    backgroundImage: bgBytes,
    backgroundTiled: tiled,
    cloudMeta: result.cloudMeta,
    referenceChain: result.referenceChain,
    explicitTokens: result.explicitTokens,
  );
}

Color? _parseHexColor(String hex) {
  if (!hex.startsWith('#')) return null;
  final digits = hex.substring(1);
  if (digits.length == 6) {
    final v = int.tryParse(digits, radix: 16);
    if (v == null) return null;
    return Color((0xFF << 24) | v);
  } else if (digits.length == 8) {
    final v = int.tryParse(digits, radix: 16);
    if (v == null) return null;
    final r = (v >> 24) & 0xFF;
    final g = (v >> 16) & 0xFF;
    final b = (v >> 8) & 0xFF;
    final a = v & 0xFF;
    return Color((a << 24) | (r << 16) | (g << 8) | b);
  }
  return null;
}

String _colorToHex(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  final a = (c.a * 255).round();
  if (a == 255) {
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'
      '${a.toRadixString(16).padLeft(2, '0')}';
}

String _generatePaletteText(ThemeFileData data) {
  final buf = StringBuffer();

  // The cloud-theme service block MUST be the very first bytes of the file —
  // AyuGram writes it as a PREFIX (`WriteCloudToText(cloud) + palette`,
  // window_theme_editor_box.cpp:230,324) and ReadCloudFromText parses it
  // POSITIONALLY: list[1]=ID, list[2]=ACCESS in the text before the END marker,
  // guarded by `index <= 1` (window_theme_editor.cpp:357-381). If anything —
  // even the "// Generated by UniClient" header — precedes it, other clients
  // (AyuGram/TDesktop) read an empty CloudTheme and the in-file cloud identity
  // is lost. So prepend it before the header and colors.
  if (data.cloudMeta != null) {
    buf.write(writeCloudMeta(data.cloudMeta!));
  }

  buf.writeln('// Generated by UniClient');
  buf.writeln();

  final map = paletteToMap(data.palette);
  for (final entry in map.entries) {
    buf.writeln('${entry.key}: ${_colorToHex(entry.value)};');
  }

  return buf.toString();
}

// ── Palette fallback chain (for finalize() cascade) ──
// Every `key: fallbackKey;` reference from AyuGram's lib_ui/ui/colors.palette, in
// EXACT declaration order (236 of the 580 colors are references; the other 344 have
// literal `#rrggbb` defaults and need no cascade — an unset literal simply keeps its
// dayBlue default via `merged`). The order mirrors the generated `palette::finalize()`
// compute(index, fallbackIndex, value) call sequence (style_core_palette.cpp:158-180);
// a const map literal preserves insertion order, so iterating `.entries` walks it in
// declaration order. Used by Pass 3 in parsePaletteText. Keep 1:1 with colors.palette.
const Map<String, String> _paletteFallbacks = {
  'windowFgOver': 'windowFg',
  'slideFadeOutShadowFg': 'windowShadowFg',
  'activeButtonBg': 'windowBgActive',
  'activeButtonFg': 'windowFgActive',
  'activeButtonFgOver': 'activeButtonFg',
  'activeButtonSecondaryFgOver': 'activeButtonSecondaryFg',
  'lightButtonBg': 'windowBg',
  'lightButtonFg': 'windowActiveTextFg',
  'lightButtonFgOver': 'lightButtonFg',
  'menuBg': 'windowBg',
  'menuBgOver': 'windowBgOver',
  'menuBgRipple': 'windowBgRipple',
  'radialFg': 'windowFgActive',
  'placeholderFg': 'windowSubTextFg',
  'filterInputActiveBg': 'windowBg',
  'filterInputInactiveBg': 'windowBgOver',
  'botKbBg': 'menuBgOver',
  'botKbDownBg': 'menuBgRipple',
  'botKbColor': 'windowBoldFgOver',
  'sliderBgActive': 'windowBgActive',
  'titleBg': 'windowBgOver',
  'titleBgActive': 'titleBg',
  'titleButtonBg': 'titleBg',
  'titleButtonBgActive': 'titleButtonBg',
  'titleButtonFgActive': 'titleButtonFg',
  'titleButtonBgActiveOver': 'titleButtonBgOver',
  'titleButtonFgActiveOver': 'titleButtonFgOver',
  'titleButtonCloseBg': 'titleButtonBg',
  'titleButtonCloseFg': 'titleButtonFg',
  'titleButtonCloseFgOver': 'windowFgActive',
  'titleButtonCloseBgActive': 'titleButtonCloseBg',
  'titleButtonCloseFgActive': 'titleButtonCloseFg',
  'titleButtonCloseBgActiveOver': 'titleButtonCloseBgOver',
  'titleButtonCloseFgActiveOver': 'titleButtonCloseFgOver',
  'cancelIconFg': 'menuIconFg',
  'cancelIconFgOver': 'menuIconFgOver',
  'boxBg': 'windowBg',
  'boxTextFg': 'windowFg',
  'boxSearchBg': 'boxBg',
  'boxTitleCloseFg': 'cancelIconFg',
  'boxTitleCloseFgOver': 'cancelIconFgOver',
  'boxDividerBg': 'windowBgOver',
  'boxDividerFg': 'windowShadowFg',
  'membersAboutLimitFg': 'windowSubTextFgOver',
  'contactsBg': 'windowBg',
  'contactsBgOver': 'windowBgOver',
  'contactsNameFg': 'boxTextFg',
  'contactsStatusFg': 'windowSubTextFg',
  'contactsStatusFgOver': 'windowSubTextFgOver',
  'contactsStatusFgOnline': 'windowActiveTextFg',
  'photoCropFadeBg': 'layerBg',
  'introBg': 'windowBg',
  'introTitleFg': 'windowBoldFg',
  'introDescriptionFg': 'windowSubTextFg',
  'dialogsMenuIconFg': 'menuIconFg',
  'dialogsMenuIconFgOver': 'menuIconFgOver',
  'dialogsBg': 'windowBg',
  'dialogsNameFg': 'windowBoldFg',
  'dialogsChatIconFg': 'dialogsNameFg',
  'dialogsDateFg': 'windowSubTextFg',
  'dialogsTextFg': 'windowSubTextFg',
  'dialogsTextFgService': 'windowActiveTextFg',
  'dialogsVerifiedIconBg': 'windowBgActive',
  'dialogsVerifiedIconFg': 'windowFgActive',
  'dialogsUnreadBg': 'windowBgActive',
  'dialogsUnreadFg': 'windowFgActive',
  'dialogsScamFg': 'dialogsDraftFg',
  'dialogsBgOver': 'windowBgOver',
  'dialogsNameFgOver': 'windowBoldFgOver',
  'dialogsChatIconFgOver': 'dialogsNameFgOver',
  'dialogsDateFgOver': 'windowSubTextFgOver',
  'dialogsTextFgOver': 'windowSubTextFgOver',
  'dialogsTextFgServiceOver': 'dialogsTextFgService',
  'dialogsDraftFgOver': 'dialogsDraftFg',
  'dialogsVerifiedIconBgOver': 'dialogsVerifiedIconBg',
  'dialogsVerifiedIconFgOver': 'dialogsVerifiedIconFg',
  'dialogsSendingIconFgOver': 'dialogsSendingIconFg',
  'dialogsUnreadBgOver': 'dialogsUnreadBg',
  'dialogsUnreadBgMutedOver': 'dialogsUnreadBgMuted',
  'dialogsUnreadFgOver': 'dialogsUnreadFg',
  'dialogsScamFgOver': 'dialogsDraftFgOver',
  'dialogsNameFgActive': 'windowFgActive',
  'dialogsChatIconFgActive': 'dialogsNameFgActive',
  'dialogsDateFgActive': 'windowFgActive',
  'dialogsTextFgActive': 'windowFgActive',
  'dialogsTextFgServiceActive': 'dialogsTextFgActive',
  'dialogsVerifiedIconBgActive': 'dialogsTextFgActive',
  'dialogsVerifiedIconFgActive': 'dialogsBgActive',
  'dialogsSentIconFgActive': 'dialogsTextFgActive',
  'dialogsUnreadBgActive': 'dialogsTextFgActive',
  'dialogsUnreadBgMutedActive': 'dialogsDraftFgActive',
  'dialogsUnreadFgActive': 'dialogsBgActive',
  'dialogsScamFgActive': 'dialogsDraftFgActive',
  'dialogsRippleBg': 'windowBgRipple',
  'dialogsRippleBgActive': 'activeButtonBgRipple',
  'searchedBarBg': 'windowBgOver',
  'searchedBarFg': 'windowSubTextFgOver',
  'topBarBg': 'windowBg',
  'emojiPanBg': 'windowBg',
  'emojiPanHeaderFg': 'windowSubTextFg',
  'stickerPanDeleteFg': 'windowFgActive',
  'historyTextInFg': 'windowFg',
  'historyTextInFgSelected': 'historyTextInFg',
  'historyTextOutFg': 'windowFg',
  'historyTextOutFgSelected': 'historyTextOutFg',
  'historyLinkInFg': 'windowActiveTextFg',
  'historyLinkInFgSelected': 'historyLinkInFg',
  'historyLinkOutFg': 'windowActiveTextFg',
  'historyLinkOutFgSelected': 'historyLinkOutFg',
  'historyFileNameInFg': 'historyTextInFg',
  'historyFileNameInFgSelected': 'historyFileNameInFg',
  'historyFileNameOutFg': 'historyTextOutFg',
  'historyFileNameOutFgSelected': 'historyFileNameOutFg',
  'historyIconFgInverted': 'windowFgActive',
  'historyCallArrowMissedInFg': 'callArrowMissedFg',
  'historyCallArrowMissedInFgSelected': 'callArrowMissedFg',
  'historyCallArrowOutFg': 'historyCallArrowInFg',
  'historyCallArrowOutFgSelected': 'historyCallArrowInFgSelected',
  'historyUnreadBarBorder': 'shadowFg',
  'historyForwardChooseFg': 'windowFgActive',
  'historyPeer1NameFgSelected': 'historyPeer1NameFg',
  'historyPeer2NameFgSelected': 'historyPeer2NameFg',
  'historyPeer3NameFgSelected': 'historyPeer3NameFg',
  'historyPeer4NameFg': 'windowActiveTextFg',
  'historyPeer4NameFgSelected': 'historyPeer4NameFg',
  'historyPeer5NameFgSelected': 'historyPeer5NameFg',
  'historyPeer6NameFgSelected': 'historyPeer6NameFg',
  'historyPeer7NameFgSelected': 'historyPeer7NameFg',
  'historyPeer8NameFgSelected': 'historyPeer8NameFg',
  'historyPeerUserpicFg': 'windowFgActive',
  'historyPeerSavedMessagesBg': 'historyPeer4UserpicBg',
  'historyPeerArchiveUserpicBg': 'dialogsUnreadBgMuted',
  'historyPeerSavedMessagesBg2': 'historyPeer4UserpicBg2',
  'msgInBg': 'windowBg',
  'msgInServiceFg': 'windowActiveTextFg',
  'msgInServiceFgSelected': 'windowActiveTextFg',
  'msgServiceFg': 'windowFgActive',
  'msgInReplyBarColor': 'activeLineFg',
  'msgInReplyBarSelColor': 'activeLineFg',
  'msgOutReplyBarSelColor': 'historyOutIconFgSelected',
  'msgImgReplyBarColor': 'msgServiceFg',
  'msgInMonoFgSelected': 'msgInMonoFg',
  'msgOutMonoFgSelected': 'msgOutMonoFg',
  'msgDateImgFg': 'msgServiceFg',
  'msgFileThumbLinkInFg': 'lightButtonFg',
  'msgFileThumbLinkInFgSelected': 'lightButtonFgOver',
  'msgFileInBg': 'windowBgActive',
  'historyFileInIconFg': 'msgInBg',
  'historyFileInIconFgSelected': 'msgInBgSelected',
  'historyFileInRadialFg': 'historyFileInIconFg',
  'historyFileInRadialFgSelected': 'historyFileInIconFgSelected',
  'historyFileOutIconFg': 'msgOutBg',
  'historyFileOutIconFgSelected': 'msgOutBgSelected',
  'historyFileOutRadialFg': 'historyFileOutIconFg',
  'historyFileOutRadialFgSelected': 'historyFileOutIconFgSelected',
  'historyFileThumbIconFg': 'msgInBg',
  'historyFileThumbIconFgSelected': 'msgInBgSelected',
  'historyFileThumbRadialFg': 'historyFileThumbIconFg',
  'historyFileThumbRadialFgSelected': 'historyFileThumbIconFgSelected',
  'historyVideoMessageProgressFg': 'historyFileThumbIconFg',
  'msgWaveformInActive': 'windowBgActive',
  'msgBotKbIconFg': 'msgServiceFg',
  'mediaInFg': 'msgInDateFg',
  'mediaInFgSelected': 'msgInDateFgSelected',
  'mediaOutFg': 'msgOutDateFg',
  'mediaOutFgSelected': 'msgOutDateFgSelected',
  'youtubePlayIconFg': 'windowFgActive',
  'historyToDownBg': 'windowBg',
  'historyToDownBgOver': 'windowBgOver',
  'historyToDownBgRipple': 'windowBgRipple',
  'historyToDownFg': 'menuIconFg',
  'historyToDownFgOver': 'menuIconFgOver',
  'historyComposeAreaBg': 'msgInBg',
  'historyComposeAreaFg': 'historyTextInFg',
  'historyComposeAreaFgService': 'msgInDateFg',
  'historyComposeIconFg': 'menuIconFg',
  'historyComposeIconFgOver': 'menuIconFgOver',
  'historySendIconFg': 'windowBgActive',
  'historySendIconFgOver': 'windowBgActive',
  'historyPinnedBg': 'historyComposeAreaBg',
  'historyReplyBg': 'historyComposeAreaBg',
  'historyReplyIconFg': 'windowBgActive',
  'historyReplyCancelFg': 'cancelIconFg',
  'historyReplyCancelFgOver': 'cancelIconFgOver',
  'historyComposeButtonBg': 'historyComposeAreaBg',
  'historyComposeButtonBgOver': 'windowBgOver',
  'historyComposeButtonBgRipple': 'windowBgRipple',
  'overviewCheckBgActive': 'windowBgActive',
  'overviewCheckBorder': 'windowBg',
  'overviewCheckFgActive': 'windowBg',
  'profileVerifiedCheckBg': 'windowBgActive',
  'profileVerifiedCheckFg': 'windowFgActive',
  'profileAdminStartFg': 'windowBgActive',
  'notificationsBoxMonitorFg': 'windowFg',
  'notificationsBoxScreenBg': 'dialogsBgActive',
  'notificationSampleUserpicFg': 'windowBgActive',
  'mainMenuBg': 'windowBg',
  'mainMenuCoverBg': 'dialogsBgActive',
  'mainMenuCloudFg': 'activeButtonFg',
  'mediaPlayerBg': 'windowBg',
  'mediaPlayerActiveFg': 'windowBgActive',
  'mediaPlayerInactiveFg': 'sliderBgInactive',
  'mediaviewFileBg': 'windowBg',
  'mediaviewFileNameFg': 'windowFg',
  'mediaviewFileSizeFg': 'windowSubTextFg',
  'mediaviewFileExtFg': 'activeButtonFg',
  'mediaviewMenuFg': 'windowFgActive',
  'mediaviewVideoBg': 'imageBg',
  'mediaviewCaptionFg': 'mediaviewControlFg',
  'mediaviewSaveMsgBg': 'toastBg',
  'mediaviewSaveMsgFg': 'toastFg',
  'mediaviewPlaybackIconFg': 'mediaviewPlaybackActive',
  'mediaviewPlaybackIconFgOver': 'mediaviewPlaybackActiveOver',
  'notificationBg': 'windowBg',
  'callBarBg': 'dialogsBgActive',
  'callBarMuteRipple': 'dialogsRippleBgActive',
  'callBarFg': 'dialogsNameFgActive',
  'importantTooltipBg': 'toastBg',
  'importantTooltipFg': 'toastFg',
  'importantTooltipFgLink': 'mediaviewTextLinkFg',
  'walletTitleBgActive': 'walletTitleBg',
  'walletTitleButtonBg': 'walletTitleBg',
  'walletTitleButtonBgActive': 'walletTitleButtonBg',
  'walletTitleButtonFgActive': 'walletTitleButtonFg',
  'walletTitleButtonBgActiveOver': 'walletTitleButtonBgOver',
  'walletTitleButtonFgActiveOver': 'walletTitleButtonFgOver',
  'walletTitleButtonCloseBg': 'walletTitleButtonBg',
  'walletTitleButtonCloseFg': 'walletTitleButtonFg',
  'walletTitleButtonCloseBgOver': 'titleButtonCloseBgOver',
  'walletTitleButtonCloseFgOver': 'titleButtonCloseFgOver',
  'walletTitleButtonCloseBgActive': 'walletTitleButtonCloseBg',
  'walletTitleButtonCloseFgActive': 'walletTitleButtonCloseFg',
  'walletTitleButtonCloseBgActiveOver': 'walletTitleButtonCloseBgOver',
  'walletTitleButtonCloseFgActiveOver': 'walletTitleButtonCloseFgOver',
  'walletTopIconFg': 'walletTopLabelFg',
  'rankUserFg': 'windowSubTextFg',
};

// ── Token name ↔ palette field mapping ──

Map<String, Color> paletteToMap(TelegramPalette p) => {
  'windowBg': p.windowBg,
  'windowBgOver': p.windowBgOver,
  'windowBgRipple': p.windowBgRipple,
  'windowBgActive': p.windowBgActive,
  'windowFg': p.windowFg,
  'windowFgOver': p.windowFgOver,
  'windowFgActive': p.windowFgActive,
  'windowSubTextFg': p.windowSubTextFg,
  'windowSubTextFgOver': p.windowSubTextFgOver,
  'windowBoldFg': p.windowBoldFg,
  'windowBoldFgOver': p.windowBoldFgOver,
  'windowActiveTextFg': p.windowActiveTextFg,
  'windowShadowFg': p.windowShadowFg,
  'windowShadowFgFallback': p.windowShadowFgFallback,
  'shadowFg': p.shadowFg,
  'titleBg': p.titleBg,
  'titleBgActive': p.titleBgActive,
  'titleShadow': p.titleShadow,
  'titleFg': p.titleFg,
  'titleFgActive': p.titleFgActive,
  'layerBg': p.layerBg,
  'activeButtonBg': p.activeButtonBg,
  'activeButtonBgOver': p.activeButtonBgOver,
  'activeButtonBgRipple': p.activeButtonBgRipple,
  'activeButtonFg': p.activeButtonFg,
  'activeButtonSecondaryFg': p.activeButtonSecondaryFg,
  'activeLineFg': p.activeLineFg,
  'activeLineFgError': p.activeLineFgError,
  'lightButtonBg': p.lightButtonBg,
  'lightButtonBgOver': p.lightButtonBgOver,
  'lightButtonBgRipple': p.lightButtonBgRipple,
  'lightButtonFg': p.lightButtonFg,
  'lightButtonFgOver': p.lightButtonFgOver,
  'attentionButtonFg': p.attentionButtonFg,
  'attentionButtonBgOver': p.attentionButtonBgOver,
  'attentionButtonBgRipple': p.attentionButtonBgRipple,
  'dialogsBg': p.dialogsBg,
  'dialogsBgOver': p.dialogsBgOver,
  'dialogsBgActive': p.dialogsBgActive,
  'dialogsRippleBg': p.dialogsRippleBg,
  'dialogsRippleBgActive': p.dialogsRippleBgActive,
  'dialogsNameFg': p.dialogsNameFg,
  'dialogsNameFgOver': p.dialogsNameFgOver,
  'dialogsNameFgActive': p.dialogsNameFgActive,
  'dialogsTextFg': p.dialogsTextFg,
  'dialogsTextFgOver': p.dialogsTextFgOver,
  'dialogsTextFgActive': p.dialogsTextFgActive,
  'dialogsTextFgService': p.dialogsTextFgService,
  'dialogsDateFg': p.dialogsDateFg,
  'dialogsDraftFg': p.dialogsDraftFg,
  'dialogsUnreadBg': p.dialogsUnreadBg,
  'dialogsUnreadBgMuted': p.dialogsUnreadBgMuted,
  'dialogsUnreadBgActive': p.dialogsUnreadBgActive,
  'dialogsUnreadBgMutedActive': p.dialogsUnreadBgMutedActive,
  'dialogsUnreadFg': p.dialogsUnreadFg,
  'dialogsUnreadFgActive': p.dialogsUnreadFgActive,
  'dialogsOnlineBadgeFg': p.dialogsOnlineBadgeFg,
  'dialogsOnlineBadgeFgActive': p.dialogsOnlineBadgeFgActive,
  'dialogsSentIconFg': p.dialogsSentIconFg,
  'dialogsSendingIconFg': p.dialogsSendingIconFg,
  'dialogsVerifiedIconBg': p.dialogsVerifiedIconBg,
  'dialogsVerifiedIconFg': p.dialogsVerifiedIconFg,
  'dialogsArchiveFg': p.dialogsArchiveFg,
  'topBarBg': p.topBarBg,
  'msgInBg': p.msgInBg,
  'msgInBgSelected': p.msgInBgSelected,
  'msgOutBg': p.msgOutBg,
  'msgOutBgSelected': p.msgOutBgSelected,
  'msgInShadow': p.msgInShadow,
  'msgOutShadow': p.msgOutShadow,
  'msgInDateFg': p.msgInDateFg,
  'msgOutDateFg': p.msgOutDateFg,
  'msgInServiceFg': p.msgInServiceFg,
  'msgOutServiceFg': p.msgOutServiceFg,
  'msgInReplyBarColor': p.msgInReplyBarColor,
  'msgOutReplyBarColor': p.msgOutReplyBarColor,
  'msgInMonoFg': p.msgInMonoFg,
  'msgOutMonoFg': p.msgOutMonoFg,
  'msgFileInBg': p.msgFileInBg,
  'msgFileOutBg': p.msgFileOutBg,
  'msgServiceBg': p.msgServiceBg,
  'msgServiceBgSelected': p.msgServiceBgSelected,
  'msgServiceFg': p.msgServiceFg,
  'msgSelectOverlay': p.msgSelectOverlay,
  'msgStickerOverlay': p.msgStickerOverlay,
  'msgDateImgBg': p.msgDateImgBg,
  'msgDateImgBgOver': p.msgDateImgBgOver,
  'msgDateImgBgSelected': p.msgDateImgBgSelected,
  'historyTextInFg': p.historyTextInFg,
  'historyTextOutFg': p.historyTextOutFg,
  'historyComposeAreaBg': p.historyComposeAreaBg,
  'historyComposeAreaFg': p.historyComposeAreaFg,
  'historyComposeIconFg': p.historyComposeIconFg,
  'historyComposeIconFgOver': p.historyComposeIconFgOver,
  'historyComposeButtonBg': p.historyComposeButtonBg,
  'historyComposeButtonBgOver': p.historyComposeButtonBgOver,
  'historyComposeButtonBgRipple': p.historyComposeButtonBgRipple,
  'historySendIconFg': p.historySendIconFg,
  'historyReplyBg': p.historyReplyBg,
  'historyReplyIconFg': p.historyReplyIconFg,
  'historyPinnedBg': p.historyPinnedBg,
  'historyUnreadBarBg': p.historyUnreadBarBg,
  'historyUnreadBarFg': p.historyUnreadBarFg,
  'historyScrollBg': p.historyScrollBg,
  'historyScrollBgOver': p.historyScrollBgOver,
  'historyScrollBarBg': p.historyScrollBarBg,
  'historyScrollBarBgOver': p.historyScrollBarBgOver,
  'historyToDownBg': p.historyToDownBg,
  'historyToDownBgOver': p.historyToDownBgOver,
  'historyToDownFg': p.historyToDownFg,
  'historyOutIconFg': p.historyOutIconFg,
  'historySendingOutIconFg': p.historySendingOutIconFg,
  'historySendingInIconFg': p.historySendingInIconFg,
  'historyIconFgInverted': p.historyIconFgInverted,
  'historySendingInvertedIconFg': p.historySendingInvertedIconFg,
  'historyPeer1NameFg': p.historyPeer1NameFg,
  'historyPeer2NameFg': p.historyPeer2NameFg,
  'historyPeer3NameFg': p.historyPeer3NameFg,
  'historyPeer4NameFg': p.historyPeer4NameFg,
  'historyPeer5NameFg': p.historyPeer5NameFg,
  'historyPeer6NameFg': p.historyPeer6NameFg,
  'historyPeer7NameFg': p.historyPeer7NameFg,
  'historyPeer8NameFg': p.historyPeer8NameFg,
  'historyPeer1UserpicBg': p.historyPeer1UserpicBg,
  'historyPeer2UserpicBg': p.historyPeer2UserpicBg,
  'historyPeer3UserpicBg': p.historyPeer3UserpicBg,
  'historyPeer4UserpicBg': p.historyPeer4UserpicBg,
  'historyPeer5UserpicBg': p.historyPeer5UserpicBg,
  'historyPeer6UserpicBg': p.historyPeer6UserpicBg,
  'historyPeer7UserpicBg': p.historyPeer7UserpicBg,
  'historyPeer8UserpicBg': p.historyPeer8UserpicBg,
  'historyPeer1UserpicBg2': p.historyPeer1UserpicBg2,
  'historyPeer2UserpicBg2': p.historyPeer2UserpicBg2,
  'historyPeer3UserpicBg2': p.historyPeer3UserpicBg2,
  'historyPeer4UserpicBg2': p.historyPeer4UserpicBg2,
  'historyPeer5UserpicBg2': p.historyPeer5UserpicBg2,
  'historyPeer6UserpicBg2': p.historyPeer6UserpicBg2,
  'historyPeer7UserpicBg2': p.historyPeer7UserpicBg2,
  'historyPeer8UserpicBg2': p.historyPeer8UserpicBg2,
  'msgFile1Bg': p.msgFile1Bg,
  'msgFile1BgDark': p.msgFile1BgDark,
  'msgFile1BgOver': p.msgFile1BgOver,
  'msgFile1BgSelected': p.msgFile1BgSelected,
  'msgFile2Bg': p.msgFile2Bg,
  'msgFile2BgDark': p.msgFile2BgDark,
  'msgFile2BgOver': p.msgFile2BgOver,
  'msgFile2BgSelected': p.msgFile2BgSelected,
  'msgFile3Bg': p.msgFile3Bg,
  'msgFile3BgDark': p.msgFile3BgDark,
  'msgFile3BgOver': p.msgFile3BgOver,
  'msgFile3BgSelected': p.msgFile3BgSelected,
  'msgFile4Bg': p.msgFile4Bg,
  'msgFile4BgDark': p.msgFile4BgDark,
  'msgFile4BgOver': p.msgFile4BgOver,
  'msgFile4BgSelected': p.msgFile4BgSelected,
  'msgWaveformInActive': p.msgWaveformInActive,
  'msgWaveformInInactive': p.msgWaveformInInactive,
  'msgWaveformOutActive': p.msgWaveformOutActive,
  'msgWaveformOutInactive': p.msgWaveformOutInactive,
  'mediaviewBg': p.mediaviewBg,
  'mediaviewControlBg': p.mediaviewControlBg,
  'mediaviewControlFg': p.mediaviewControlFg,
  'mediaviewCaptionBg': p.mediaviewCaptionBg,
  'mediaviewPlaybackActive': p.mediaviewPlaybackActive,
  'mediaviewPlaybackInactive': p.mediaviewPlaybackInactive,
  'mediaviewPlaybackActiveOver': p.mediaviewPlaybackActiveOver,
  'introCoverTopBg': p.introCoverTopBg,
  'introCoverBottomBg': p.introCoverBottomBg,
  'introCoverIconsFg': p.introCoverIconsFg,
  'introCoverPlaneTrace': p.introCoverPlaneTrace,
  'introCoverPlaneTop': p.introCoverPlaneTop,
  'scrollBarBg': p.scrollBarBg,
  'scrollBarBgOver': p.scrollBarBgOver,
  'scrollBg': p.scrollBg,
  'scrollBgOver': p.scrollBgOver,
  'boxBg': p.boxBg,
  'boxTextFg': p.boxTextFg,
  'boxTitleFg': p.boxTitleFg,
  'boxSearchBg': p.boxSearchBg,
  'boxTitleAdditionalFg': p.boxTitleAdditionalFg,
  'boxTextFgGood': p.boxTextFgGood,
  'boxTextFgError': p.boxTextFgError,
  'boxDividerBg': p.boxDividerBg,
  'profileStatusFgOver': p.profileStatusFgOver,
  'profileVerifiedCheckBg': p.profileVerifiedCheckBg,
  'profileVerifiedCheckFg': p.profileVerifiedCheckFg,
  'profileAdminStartFg': p.profileAdminStartFg,
  'sideBarBg': p.sideBarBg,
  'sideBarBgActive': p.sideBarBgActive,
  'sideBarBgRipple': p.sideBarBgRipple,
  'sideBarTextFg': p.sideBarTextFg,
  'sideBarTextFgActive': p.sideBarTextFgActive,
  'sideBarIconFg': p.sideBarIconFg,
  'sideBarIconFgActive': p.sideBarIconFgActive,
  'sideBarBadgeBg': p.sideBarBadgeBg,
  'sideBarBadgeBgMuted': p.sideBarBadgeBgMuted,
  'sideBarBadgeFg': p.sideBarBadgeFg,
  'menuBg': p.menuBg,
  'menuBgOver': p.menuBgOver,
  'menuBgRipple': p.menuBgRipple,
  'menuIconFg': p.menuIconFg,
  'menuIconFgOver': p.menuIconFgOver,
  'menuSeparatorFg': p.menuSeparatorFg,
  'mainMenuBg': p.mainMenuBg,
  'mainMenuCoverBg': p.mainMenuCoverBg,
  'settingsIconBg1': p.settingsIconBg1,
  'settingsIconBg2': p.settingsIconBg2,
  'settingsIconBg3': p.settingsIconBg3,
  'settingsIconBg4': p.settingsIconBg4,
  'settingsIconBg5': p.settingsIconBg5,
  'settingsIconBg6': p.settingsIconBg6,
  'settingsIconBg8': p.settingsIconBg8,
  'settingsIconBgArchive': p.settingsIconBgArchive,
  'historyPeer1NameFgSelected': p.historyPeer1NameFgSelected,
  'historyPeer2NameFgSelected': p.historyPeer2NameFgSelected,
  'historyPeer3NameFgSelected': p.historyPeer3NameFgSelected,
  'historyPeer4NameFgSelected': p.historyPeer4NameFgSelected,
  'historyPeer5NameFgSelected': p.historyPeer5NameFgSelected,
  'historyPeer6NameFgSelected': p.historyPeer6NameFgSelected,
  'historyPeer7NameFgSelected': p.historyPeer7NameFgSelected,
  'historyPeer8NameFgSelected': p.historyPeer8NameFgSelected,
  'mediaviewFileRedCornerFg': p.mediaviewFileRedCornerFg,
  'mediaviewFileYellowCornerFg': p.mediaviewFileYellowCornerFg,
  'mediaviewFileGreenCornerFg': p.mediaviewFileGreenCornerFg,
  'mediaviewFileBlueCornerFg': p.mediaviewFileBlueCornerFg,
  'premiumButtonBg1': p.premiumButtonBg1,
  'premiumButtonBg2': p.premiumButtonBg2,
  'premiumButtonBg3': p.premiumButtonBg3,
  'premiumIconBg1': p.premiumIconBg1,
  'premiumIconBg2': p.premiumIconBg2,
  'callIconFg': p.callIconFg,
  'tooltipBg': p.tooltipBg,
  'tooltipFg': p.tooltipFg,
  'tooltipBorderFg': p.tooltipBorderFg,
  'importantTooltipBg': p.importantTooltipBg,
  'overviewCheckBg': p.overviewCheckBg,
  // §57.11 derived token synonyms
  'dialogsChatBgOver': p.dialogsChatBgOver,
  'topBarIconFg': p.topBarIconFg,
  'topBarMenuFg': p.topBarMenuFg,
  'topBarTextFg': p.topBarTextFg,
  'profileStatusFg': p.profileStatusFg,
  'slideFadeOutBg': p.slideFadeOutBg,
  'slideFadeOutShadowFg': p.slideFadeOutShadowFg,
  'imageBg': p.imageBg,
  'imageBgTransparent': p.imageBgTransparent,
  'activeButtonFgOver': p.activeButtonFgOver,
  'activeButtonSecondaryFgOver': p.activeButtonSecondaryFgOver,
  'attentionButtonFgOver': p.attentionButtonFgOver,
  'menuSubmenuArrowFg': p.menuSubmenuArrowFg,
  'menuFgDisabled': p.menuFgDisabled,
  'smallCloseIconFg': p.smallCloseIconFg,
  'smallCloseIconFgOver': p.smallCloseIconFgOver,
  'radialFg': p.radialFg,
  'radialBg': p.radialBg,
  'placeholderFg': p.placeholderFg,
  'placeholderFgActive': p.placeholderFgActive,
  'inputBorderFg': p.inputBorderFg,
  'filterInputBorderFg': p.filterInputBorderFg,
  'filterInputActiveBg': p.filterInputActiveBg,
  'filterInputInactiveBg': p.filterInputInactiveBg,
  'checkboxFg': p.checkboxFg,
  'botKbBg': p.botKbBg,
  'botKbDownBg': p.botKbDownBg,
  'botKbColor': p.botKbColor,
  'botKbPrimaryBg': p.botKbPrimaryBg,
  'botKbDangerBg': p.botKbDangerBg,
  'botKbSuccessBg': p.botKbSuccessBg,
  'botKbInlinePrimaryBg': p.botKbInlinePrimaryBg,
  'botKbInlineDangerBg': p.botKbInlineDangerBg,
  'botKbInlineSuccessBg': p.botKbInlineSuccessBg,
  'sliderBgInactive': p.sliderBgInactive,
  'sliderBgActive': p.sliderBgActive,
  'titleButtonBg': p.titleButtonBg,
  'titleButtonFg': p.titleButtonFg,
  'titleButtonBgOver': p.titleButtonBgOver,
  'titleButtonFgOver': p.titleButtonFgOver,
  'titleButtonBgActive': p.titleButtonBgActive,
  'titleButtonFgActive': p.titleButtonFgActive,
  'titleButtonBgActiveOver': p.titleButtonBgActiveOver,
  'titleButtonFgActiveOver': p.titleButtonFgActiveOver,
  'titleButtonCloseBg': p.titleButtonCloseBg,
  'titleButtonCloseFg': p.titleButtonCloseFg,
  'titleButtonCloseBgOver': p.titleButtonCloseBgOver,
  'titleButtonCloseFgOver': p.titleButtonCloseFgOver,
  'titleButtonCloseBgActive': p.titleButtonCloseBgActive,
  'titleButtonCloseFgActive': p.titleButtonCloseFgActive,
  'titleButtonCloseBgActiveOver': p.titleButtonCloseBgActiveOver,
  'titleButtonCloseFgActiveOver': p.titleButtonCloseFgActiveOver,
  'trayCounterBg': p.trayCounterBg,
  'trayCounterBgMute': p.trayCounterBgMute,
  'trayCounterFg': p.trayCounterFg,
  'trayCounterBgMacInvert': p.trayCounterBgMacInvert,
  'trayCounterFgMacInvert': p.trayCounterFgMacInvert,
  'cancelIconFg': p.cancelIconFg,
  'cancelIconFgOver': p.cancelIconFgOver,
  'boxTitleCloseFg': p.boxTitleCloseFg,
  'boxTitleCloseFgOver': p.boxTitleCloseFgOver,
  'boxDividerFg': p.boxDividerFg,
  'paymentsTipActive': p.paymentsTipActive,
  'membersAboutLimitFg': p.membersAboutLimitFg,
  'contactsBg': p.contactsBg,
  'contactsBgOver': p.contactsBgOver,
  'contactsNameFg': p.contactsNameFg,
  'contactsStatusFg': p.contactsStatusFg,
  'contactsStatusFgOver': p.contactsStatusFgOver,
  'contactsStatusFgOnline': p.contactsStatusFgOnline,
  'photoCropFadeBg': p.photoCropFadeBg,
  'photoCropPointFg': p.photoCropPointFg,
  'callArrowFg': p.callArrowFg,
  'callArrowMissedFg': p.callArrowMissedFg,
  'introBg': p.introBg,
  'introTitleFg': p.introTitleFg,
  'introDescriptionFg': p.introDescriptionFg,
  'introCoverPlaneInner': p.introCoverPlaneInner,
  'introCoverPlaneOuter': p.introCoverPlaneOuter,
  'dialogsMenuIconFg': p.dialogsMenuIconFg,
  'dialogsMenuIconFgOver': p.dialogsMenuIconFgOver,
  'dialogsChatIconFg': p.dialogsChatIconFg,
  'dialogsChatIconFgOver': p.dialogsChatIconFgOver,
  'dialogsDateFgOver': p.dialogsDateFgOver,
  'dialogsTextFgServiceOver': p.dialogsTextFgServiceOver,
  'dialogsDraftFgOver': p.dialogsDraftFgOver,
  'dialogsVerifiedIconBgOver': p.dialogsVerifiedIconBgOver,
  'dialogsVerifiedIconFgOver': p.dialogsVerifiedIconFgOver,
  'dialogsSendingIconFgOver': p.dialogsSendingIconFgOver,
  'dialogsSentIconFgOver': p.dialogsSentIconFgOver,
  'dialogsUnreadBgOver': p.dialogsUnreadBgOver,
  'dialogsUnreadBgMutedOver': p.dialogsUnreadBgMutedOver,
  'dialogsUnreadFgOver': p.dialogsUnreadFgOver,
  'dialogsArchiveFgOver': p.dialogsArchiveFgOver,
  'dialogsScamFg': p.dialogsScamFg,
  'dialogsScamFgOver': p.dialogsScamFgOver,
  'dialogsChatIconFgActive': p.dialogsChatIconFgActive,
  'dialogsDateFgActive': p.dialogsDateFgActive,
  'dialogsTextFgServiceActive': p.dialogsTextFgServiceActive,
  'dialogsDraftFgActive': p.dialogsDraftFgActive,
  'dialogsVerifiedIconBgActive': p.dialogsVerifiedIconBgActive,
  'dialogsVerifiedIconFgActive': p.dialogsVerifiedIconFgActive,
  'dialogsSendingIconFgActive': p.dialogsSendingIconFgActive,
  'dialogsSentIconFgActive': p.dialogsSentIconFgActive,
  'dialogsScamFgActive': p.dialogsScamFgActive,
  'dialogsMentionIconFg': p.dialogsMentionIconFg,
  'dialogsReactionIconFg': p.dialogsReactionIconFg,
  'dialogsPollIconFg': p.dialogsPollIconFg,
  'searchedBarBg': p.searchedBarBg,
  'searchedBarFg': p.searchedBarFg,
  'emojiPanBg': p.emojiPanBg,
  'emojiPanCategories': p.emojiPanCategories,
  'emojiPanHeaderFg': p.emojiPanHeaderFg,
  'emojiPanHeaderBg': p.emojiPanHeaderBg,
  'emojiIconFg': p.emojiIconFg,
  'emojiSubIconFgActive': p.emojiSubIconFgActive,
  'stickerPanDeleteBg': p.stickerPanDeleteBg,
  'stickerPanDeleteFg': p.stickerPanDeleteFg,
  'stickerPreviewBg': p.stickerPreviewBg,
  'stickerPanPremium1': p.stickerPanPremium1,
  'stickerPanPremium2': p.stickerPanPremium2,
  'historyTextInFgSelected': p.historyTextInFgSelected,
  'historyTextOutFgSelected': p.historyTextOutFgSelected,
  'historyLinkInFg': p.historyLinkInFg,
  'historyLinkInFgSelected': p.historyLinkInFgSelected,
  'historyLinkOutFg': p.historyLinkOutFg,
  'historyLinkOutFgSelected': p.historyLinkOutFgSelected,
  'historyFileNameInFg': p.historyFileNameInFg,
  'historyFileNameInFgSelected': p.historyFileNameInFgSelected,
  'historyFileNameOutFg': p.historyFileNameOutFg,
  'historyFileNameOutFgSelected': p.historyFileNameOutFgSelected,
  'historyOutIconFgSelected': p.historyOutIconFgSelected,
  'historyCallArrowInFg': p.historyCallArrowInFg,
  'historyCallArrowInFgSelected': p.historyCallArrowInFgSelected,
  'historyCallArrowMissedInFg': p.historyCallArrowMissedInFg,
  'historyCallArrowMissedInFgSelected': p.historyCallArrowMissedInFgSelected,
  'historyCallArrowOutFg': p.historyCallArrowOutFg,
  'historyCallArrowOutFgSelected': p.historyCallArrowOutFgSelected,
  'historyUnreadBarBorder': p.historyUnreadBarBorder,
  'historyForwardChooseBg': p.historyForwardChooseBg,
  'historyForwardChooseFg': p.historyForwardChooseFg,
  'historyPeerUserpicFg': p.historyPeerUserpicFg,
  'historyPeerSavedMessagesBg': p.historyPeerSavedMessagesBg,
  'historyPeerArchiveUserpicBg': p.historyPeerArchiveUserpicBg,
  'historyPeerSavedMessagesBg2': p.historyPeerSavedMessagesBg2,
  'settingsIconFg': p.settingsIconFg,
  'msgInServiceFgSelected': p.msgInServiceFgSelected,
  'msgOutServiceFgSelected': p.msgOutServiceFgSelected,
  'msgInShadowSelected': p.msgInShadowSelected,
  'msgOutShadowSelected': p.msgOutShadowSelected,
  'msgInDateFgSelected': p.msgInDateFgSelected,
  'msgOutDateFgSelected': p.msgOutDateFgSelected,
  'msgInReplyBarSelColor': p.msgInReplyBarSelColor,
  'msgOutReplyBarSelColor': p.msgOutReplyBarSelColor,
  'msgImgReplyBarColor': p.msgImgReplyBarColor,
  'msgInMonoFgSelected': p.msgInMonoFgSelected,
  'msgOutMonoFgSelected': p.msgOutMonoFgSelected,
  'msgDateImgFg': p.msgDateImgFg,
  'msgFileThumbLinkInFg': p.msgFileThumbLinkInFg,
  'msgFileThumbLinkInFgSelected': p.msgFileThumbLinkInFgSelected,
  'msgFileThumbLinkOutFg': p.msgFileThumbLinkOutFg,
  'msgFileThumbLinkOutFgSelected': p.msgFileThumbLinkOutFgSelected,
  'msgFileInBgOver': p.msgFileInBgOver,
  'msgFileInBgSelected': p.msgFileInBgSelected,
  'msgFileOutBgSelected': p.msgFileOutBgSelected,
  'historyFileInIconFg': p.historyFileInIconFg,
  'historyFileInIconFgSelected': p.historyFileInIconFgSelected,
  'historyFileInRadialFg': p.historyFileInRadialFg,
  'historyFileInRadialFgSelected': p.historyFileInRadialFgSelected,
  'historyFileOutIconFg': p.historyFileOutIconFg,
  'historyFileOutIconFgSelected': p.historyFileOutIconFgSelected,
  'historyFileOutRadialFg': p.historyFileOutRadialFg,
  'historyFileOutRadialFgSelected': p.historyFileOutRadialFgSelected,
  'historyFileThumbIconFg': p.historyFileThumbIconFg,
  'historyFileThumbIconFgSelected': p.historyFileThumbIconFgSelected,
  'historyFileThumbRadialFg': p.historyFileThumbRadialFg,
  'historyFileThumbRadialFgSelected': p.historyFileThumbRadialFgSelected,
  'historyVideoMessageProgressFg': p.historyVideoMessageProgressFg,
  'msgWaveformInActiveSelected': p.msgWaveformInActiveSelected,
  'msgWaveformInInactiveSelected': p.msgWaveformInInactiveSelected,
  'msgWaveformOutActiveSelected': p.msgWaveformOutActiveSelected,
  'msgWaveformOutInactiveSelected': p.msgWaveformOutInactiveSelected,
  'msgBotKbOverBgAdd': p.msgBotKbOverBgAdd,
  'msgBotKbIconFg': p.msgBotKbIconFg,
  'msgBotKbRippleBg': p.msgBotKbRippleBg,
  'mediaInFg': p.mediaInFg,
  'mediaInFgSelected': p.mediaInFgSelected,
  'mediaOutFg': p.mediaOutFg,
  'mediaOutFgSelected': p.mediaOutFgSelected,
  'youtubePlayIconBg': p.youtubePlayIconBg,
  'youtubePlayIconFg': p.youtubePlayIconFg,
  'videoPlayIconBg': p.videoPlayIconBg,
  'videoPlayIconFg': p.videoPlayIconFg,
  'toastBg': p.toastBg,
  'toastFg': p.toastFg,
  'historyToDownBgRipple': p.historyToDownBgRipple,
  'historyToDownFgOver': p.historyToDownFgOver,
  'historyToDownShadow': p.historyToDownShadow,
  'historyComposeAreaFgService': p.historyComposeAreaFgService,
  'historySendIconFgOver': p.historySendIconFgOver,
  'historyReplyCancelFg': p.historyReplyCancelFg,
  'historyReplyCancelFgOver': p.historyReplyCancelFgOver,
  'mapPointDrop': p.mapPointDrop,
  'mapPointDot': p.mapPointDot,
  'overviewCheckBgActive': p.overviewCheckBgActive,
  'overviewCheckBorder': p.overviewCheckBorder,
  'overviewCheckFgActive': p.overviewCheckFgActive,
  'overviewPhotoSelectOverlay': p.overviewPhotoSelectOverlay,
  'notificationsBoxMonitorFg': p.notificationsBoxMonitorFg,
  'notificationsBoxScreenBg': p.notificationsBoxScreenBg,
  'notificationSampleUserpicFg': p.notificationSampleUserpicFg,
  'notificationSampleCloseFg': p.notificationSampleCloseFg,
  'notificationSampleTextFg': p.notificationSampleTextFg,
  'notificationSampleNameFg': p.notificationSampleNameFg,
  'mainMenuCloudFg': p.mainMenuCloudFg,
  'mainMenuCloudBg': p.mainMenuCloudBg,
  'mediaPlayerBg': p.mediaPlayerBg,
  'mediaPlayerActiveFg': p.mediaPlayerActiveFg,
  'mediaPlayerInactiveFg': p.mediaPlayerInactiveFg,
  'mediaPlayerDisabledFg': p.mediaPlayerDisabledFg,
  'mediaviewFileBg': p.mediaviewFileBg,
  'mediaviewFileNameFg': p.mediaviewFileNameFg,
  'mediaviewFileSizeFg': p.mediaviewFileSizeFg,
  'mediaviewFileExtFg': p.mediaviewFileExtFg,
  'mediaviewMenuBg': p.mediaviewMenuBg,
  'mediaviewMenuBgOver': p.mediaviewMenuBgOver,
  'mediaviewMenuBgRipple': p.mediaviewMenuBgRipple,
  'mediaviewMenuFg': p.mediaviewMenuFg,
  'mediaviewVideoBg': p.mediaviewVideoBg,
  'mediaviewCaptionFg': p.mediaviewCaptionFg,
  'mediaviewTextLinkFg': p.mediaviewTextLinkFg,
  'mediaviewSaveMsgBg': p.mediaviewSaveMsgBg,
  'mediaviewSaveMsgFg': p.mediaviewSaveMsgFg,
  'mediaviewPlaybackInactiveOver': p.mediaviewPlaybackInactiveOver,
  'mediaviewPlaybackProgressFg': p.mediaviewPlaybackProgressFg,
  'mediaviewPlaybackIconFg': p.mediaviewPlaybackIconFg,
  'mediaviewPlaybackIconFgOver': p.mediaviewPlaybackIconFgOver,
  'mediaviewPlaybackIconRipple': p.mediaviewPlaybackIconRipple,
  'mediaviewPipControlsFg': p.mediaviewPipControlsFg,
  'mediaviewPipControlsFgOver': p.mediaviewPipControlsFgOver,
  'mediaviewPipPlaybackActive': p.mediaviewPipPlaybackActive,
  'mediaviewPipPlaybackInactive': p.mediaviewPipPlaybackInactive,
  'mediaviewTransparentBg': p.mediaviewTransparentBg,
  'mediaviewTransparentFg': p.mediaviewTransparentFg,
  'notificationBg': p.notificationBg,
  'callBg': p.callBg,
  'callBgOpaque': p.callBgOpaque,
  'callBgButton': p.callBgButton,
  'callNameFg': p.callNameFg,
  'callStatusFg': p.callStatusFg,
  'callIconBg': p.callIconBg,
  'callIconBgActive': p.callIconBgActive,
  'callIconFgActive': p.callIconFgActive,
  'callIconActiveRipple': p.callIconActiveRipple,
  'callAnswerBg': p.callAnswerBg,
  'callAnswerRipple': p.callAnswerRipple,
  'callAnswerBgOuter': p.callAnswerBgOuter,
  'callHangupBg': p.callHangupBg,
  'callHangupRipple': p.callHangupRipple,
  'callMuteRipple': p.callMuteRipple,
  'callBarBg': p.callBarBg,
  'callBarMuteRipple': p.callBarMuteRipple,
  'callBarBgMuted': p.callBarBgMuted,
  'callBarFg': p.callBarFg,
  'importantTooltipFg': p.importantTooltipFg,
  'importantTooltipFgLink': p.importantTooltipFgLink,
  'premiumButtonFg': p.premiumButtonFg,
  'premiumIconBg3': p.premiumIconBg3,
  'groupCallBg': p.groupCallBg,
  'groupCallActiveFg': p.groupCallActiveFg,
  'groupCallMembersBg': p.groupCallMembersBg,
  'groupCallMembersBgOver': p.groupCallMembersBgOver,
  'groupCallMembersBgRipple': p.groupCallMembersBgRipple,
  'groupCallMembersFg': p.groupCallMembersFg,
  'groupCallMemberActiveIcon': p.groupCallMemberActiveIcon,
  'groupCallMemberActiveStatus': p.groupCallMemberActiveStatus,
  'groupCallMemberInactiveIcon': p.groupCallMemberInactiveIcon,
  'groupCallMemberInactiveStatus': p.groupCallMemberInactiveStatus,
  'groupCallMemberMutedIcon': p.groupCallMemberMutedIcon,
  'groupCallMemberNotJoinedStatus': p.groupCallMemberNotJoinedStatus,
  'groupCallIconFg': p.groupCallIconFg,
  'groupCallLive1': p.groupCallLive1,
  'groupCallLive2': p.groupCallLive2,
  'groupCallMuted1': p.groupCallMuted1,
  'groupCallMuted2': p.groupCallMuted2,
  'groupCallForceMutedBar1': p.groupCallForceMutedBar1,
  'groupCallForceMutedBar2': p.groupCallForceMutedBar2,
  'groupCallForceMutedBar3': p.groupCallForceMutedBar3,
  'groupCallForceMuted1': p.groupCallForceMuted1,
  'groupCallForceMuted2': p.groupCallForceMuted2,
  'groupCallForceMuted3': p.groupCallForceMuted3,
  'groupCallMenuBg': p.groupCallMenuBg,
  'groupCallMenuBgOver': p.groupCallMenuBgOver,
  'groupCallMenuBgRipple': p.groupCallMenuBgRipple,
  'groupCallLeaveBg': p.groupCallLeaveBg,
  'groupCallLeaveBgRipple': p.groupCallLeaveBgRipple,
  'groupCallVideoTextFg': p.groupCallVideoTextFg,
  'groupCallVideoSubTextFg': p.groupCallVideoSubTextFg,
  'outdatedFg': p.outdatedFg,
  'outdateSoonBg': p.outdateSoonBg,
  'outdatedBg': p.outdatedBg,
  'spellUnderline': p.spellUnderline,
  'walletTitleBg': p.walletTitleBg,
  'walletTitleBgActive': p.walletTitleBgActive,
  'walletTitleButtonBg': p.walletTitleButtonBg,
  'walletTitleButtonFg': p.walletTitleButtonFg,
  'walletTitleButtonBgOver': p.walletTitleButtonBgOver,
  'walletTitleButtonFgOver': p.walletTitleButtonFgOver,
  'walletTitleButtonBgActive': p.walletTitleButtonBgActive,
  'walletTitleButtonFgActive': p.walletTitleButtonFgActive,
  'walletTitleButtonBgActiveOver': p.walletTitleButtonBgActiveOver,
  'walletTitleButtonFgActiveOver': p.walletTitleButtonFgActiveOver,
  'walletTitleButtonCloseBg': p.walletTitleButtonCloseBg,
  'walletTitleButtonCloseFg': p.walletTitleButtonCloseFg,
  'walletTitleButtonCloseBgOver': p.walletTitleButtonCloseBgOver,
  'walletTitleButtonCloseFgOver': p.walletTitleButtonCloseFgOver,
  'walletTitleButtonCloseBgActive': p.walletTitleButtonCloseBgActive,
  'walletTitleButtonCloseFgActive': p.walletTitleButtonCloseFgActive,
  'walletTitleButtonCloseBgActiveOver': p.walletTitleButtonCloseBgActiveOver,
  'walletTitleButtonCloseFgActiveOver': p.walletTitleButtonCloseFgActiveOver,
  'walletTopBg': p.walletTopBg,
  'walletBalanceFg': p.walletBalanceFg,
  'walletSubBalanceFg': p.walletSubBalanceFg,
  'walletTopLabelFg': p.walletTopLabelFg,
  'walletTopIconFg': p.walletTopIconFg,
  'walletTopIconRipple': p.walletTopIconRipple,
  'songCoverOverlayFg': p.songCoverOverlayFg,
  'photoEditorItemBaseHandleFg': p.photoEditorItemBaseHandleFg,
  'statisticsChartInactive': p.statisticsChartInactive,
  'statisticsChartActive': p.statisticsChartActive,
  'statisticsChartLineBlue': p.statisticsChartLineBlue,
  'statisticsChartLineGreen': p.statisticsChartLineGreen,
  'statisticsChartLineRed': p.statisticsChartLineRed,
  'statisticsChartLineGolden': p.statisticsChartLineGolden,
  'statisticsChartLineLightblue': p.statisticsChartLineLightblue,
  'statisticsChartLineLightgreen': p.statisticsChartLineLightgreen,
  'statisticsChartLineOrange': p.statisticsChartLineOrange,
  'statisticsChartLineIndigo': p.statisticsChartLineIndigo,
  'statisticsChartLinePurple': p.statisticsChartLinePurple,
  'statisticsChartLineCyan': p.statisticsChartLineCyan,
  'creditsBg1': p.creditsBg1,
  'creditsBg2': p.creditsBg2,
  'creditsBg3': p.creditsBg3,
  'creditsFg': p.creditsFg,
  'creditsStroke': p.creditsStroke,
  'currencyFg': p.currencyFg,
  'rankAdminFg': p.rankAdminFg,
  'rankOwnerFg': p.rankOwnerFg,
  'rankUserFg': p.rankUserFg,
};

TelegramPalette paletteFromMap(Map<String, Color> m, TelegramPalette fb) =>
    TelegramPalette(
      windowBg: m['windowBg'] ?? fb.windowBg,
      windowBgOver: m['windowBgOver'] ?? fb.windowBgOver,
      windowBgRipple: m['windowBgRipple'] ?? fb.windowBgRipple,
      windowBgActive: m['windowBgActive'] ?? fb.windowBgActive,
      windowFg: m['windowFg'] ?? fb.windowFg,
      windowFgOver: m['windowFgOver'] ?? fb.windowFgOver,
      windowFgActive: m['windowFgActive'] ?? fb.windowFgActive,
      windowSubTextFg: m['windowSubTextFg'] ?? fb.windowSubTextFg,
      windowSubTextFgOver: m['windowSubTextFgOver'] ?? fb.windowSubTextFgOver,
      windowBoldFg: m['windowBoldFg'] ?? fb.windowBoldFg,
      windowBoldFgOver: m['windowBoldFgOver'] ?? fb.windowBoldFgOver,
      windowActiveTextFg: m['windowActiveTextFg'] ?? fb.windowActiveTextFg,
      windowShadowFg: m['windowShadowFg'] ?? fb.windowShadowFg,
      windowShadowFgFallback: m['windowShadowFgFallback'] ?? fb.windowShadowFgFallback,
      shadowFg: m['shadowFg'] ?? fb.shadowFg,
      titleBg: m['titleBg'] ?? fb.titleBg,
      titleBgActive: m['titleBgActive'] ?? fb.titleBgActive,
      titleShadow: m['titleShadow'] ?? fb.titleShadow,
      titleFg: m['titleFg'] ?? fb.titleFg,
      titleFgActive: m['titleFgActive'] ?? fb.titleFgActive,
      layerBg: m['layerBg'] ?? fb.layerBg,
      activeButtonBg: m['activeButtonBg'] ?? fb.activeButtonBg,
      activeButtonBgOver: m['activeButtonBgOver'] ?? fb.activeButtonBgOver,
      activeButtonBgRipple: m['activeButtonBgRipple'] ?? fb.activeButtonBgRipple,
      activeButtonFg: m['activeButtonFg'] ?? fb.activeButtonFg,
      activeButtonSecondaryFg: m['activeButtonSecondaryFg'] ?? fb.activeButtonSecondaryFg,
      activeLineFg: m['activeLineFg'] ?? fb.activeLineFg,
      activeLineFgError: m['activeLineFgError'] ?? fb.activeLineFgError,
      lightButtonBg: m['lightButtonBg'] ?? fb.lightButtonBg,
      lightButtonBgOver: m['lightButtonBgOver'] ?? fb.lightButtonBgOver,
      lightButtonBgRipple: m['lightButtonBgRipple'] ?? fb.lightButtonBgRipple,
      lightButtonFg: m['lightButtonFg'] ?? fb.lightButtonFg,
      lightButtonFgOver: m['lightButtonFgOver'] ?? fb.lightButtonFgOver,
      attentionButtonFg: m['attentionButtonFg'] ?? fb.attentionButtonFg,
      attentionButtonBgOver: m['attentionButtonBgOver'] ?? fb.attentionButtonBgOver,
      attentionButtonBgRipple: m['attentionButtonBgRipple'] ?? fb.attentionButtonBgRipple,
      dialogsBg: m['dialogsBg'] ?? fb.dialogsBg,
      dialogsBgOver: m['dialogsBgOver'] ?? m['dialogsChatBgOver'] ?? fb.dialogsBgOver,
      dialogsBgActive: m['dialogsBgActive'] ?? fb.dialogsBgActive,
      dialogsRippleBg: m['dialogsRippleBg'] ?? fb.dialogsRippleBg,
      dialogsRippleBgActive: m['dialogsRippleBgActive'] ?? fb.dialogsRippleBgActive,
      dialogsNameFg: m['dialogsNameFg'] ?? fb.dialogsNameFg,
      dialogsNameFgOver: m['dialogsNameFgOver'] ?? fb.dialogsNameFgOver,
      dialogsNameFgActive: m['dialogsNameFgActive'] ?? fb.dialogsNameFgActive,
      dialogsTextFg: m['dialogsTextFg'] ?? fb.dialogsTextFg,
      dialogsTextFgOver: m['dialogsTextFgOver'] ?? fb.dialogsTextFgOver,
      dialogsTextFgActive: m['dialogsTextFgActive'] ?? fb.dialogsTextFgActive,
      dialogsTextFgService: m['dialogsTextFgService'] ?? fb.dialogsTextFgService,
      dialogsDateFg: m['dialogsDateFg'] ?? fb.dialogsDateFg,
      dialogsDraftFg: m['dialogsDraftFg'] ?? fb.dialogsDraftFg,
      dialogsUnreadBg: m['dialogsUnreadBg'] ?? fb.dialogsUnreadBg,
      dialogsUnreadBgMuted: m['dialogsUnreadBgMuted'] ?? fb.dialogsUnreadBgMuted,
      dialogsUnreadBgActive: m['dialogsUnreadBgActive'] ?? fb.dialogsUnreadBgActive,
      dialogsUnreadBgMutedActive: m['dialogsUnreadBgMutedActive'] ?? fb.dialogsUnreadBgMutedActive,
      dialogsUnreadFg: m['dialogsUnreadFg'] ?? fb.dialogsUnreadFg,
      dialogsUnreadFgActive: m['dialogsUnreadFgActive'] ?? fb.dialogsUnreadFgActive,
      dialogsOnlineBadgeFg: m['dialogsOnlineBadgeFg'] ?? fb.dialogsOnlineBadgeFg,
      dialogsOnlineBadgeFgActive: m['dialogsOnlineBadgeFgActive'] ?? fb.dialogsOnlineBadgeFgActive,
      dialogsSentIconFg: m['dialogsSentIconFg'] ?? fb.dialogsSentIconFg,
      dialogsSendingIconFg: m['dialogsSendingIconFg'] ?? fb.dialogsSendingIconFg,
      dialogsVerifiedIconBg: m['dialogsVerifiedIconBg'] ?? fb.dialogsVerifiedIconBg,
      dialogsVerifiedIconFg: m['dialogsVerifiedIconFg'] ?? fb.dialogsVerifiedIconFg,
      dialogsArchiveFg: m['dialogsArchiveFg'] ?? fb.dialogsArchiveFg,
      topBarBg: m['topBarBg'] ?? fb.topBarBg,
      msgInBg: m['msgInBg'] ?? fb.msgInBg,
      msgInBgSelected: m['msgInBgSelected'] ?? fb.msgInBgSelected,
      msgOutBg: m['msgOutBg'] ?? fb.msgOutBg,
      msgOutBgSelected: m['msgOutBgSelected'] ?? fb.msgOutBgSelected,
      msgInShadow: m['msgInShadow'] ?? fb.msgInShadow,
      msgOutShadow: m['msgOutShadow'] ?? fb.msgOutShadow,
      msgInDateFg: m['msgInDateFg'] ?? fb.msgInDateFg,
      msgOutDateFg: m['msgOutDateFg'] ?? fb.msgOutDateFg,
      msgInServiceFg: m['msgInServiceFg'] ?? fb.msgInServiceFg,
      msgOutServiceFg: m['msgOutServiceFg'] ?? fb.msgOutServiceFg,
      msgInReplyBarColor: m['msgInReplyBarColor'] ?? fb.msgInReplyBarColor,
      msgOutReplyBarColor: m['msgOutReplyBarColor'] ?? fb.msgOutReplyBarColor,
      msgInMonoFg: m['msgInMonoFg'] ?? fb.msgInMonoFg,
      msgOutMonoFg: m['msgOutMonoFg'] ?? fb.msgOutMonoFg,
      msgFileInBg: m['msgFileInBg'] ?? fb.msgFileInBg,
      msgFileOutBg: m['msgFileOutBg'] ?? fb.msgFileOutBg,
      msgServiceBg: m['msgServiceBg'] ?? fb.msgServiceBg,
      msgServiceBgSelected: m['msgServiceBgSelected'] ?? fb.msgServiceBgSelected,
      msgServiceFg: m['msgServiceFg'] ?? fb.msgServiceFg,
      msgSelectOverlay: m['msgSelectOverlay'] ?? fb.msgSelectOverlay,
      msgStickerOverlay: m['msgStickerOverlay'] ?? fb.msgStickerOverlay,
      msgDateImgBg: m['msgDateImgBg'] ?? fb.msgDateImgBg,
      msgDateImgBgOver: m['msgDateImgBgOver'] ?? fb.msgDateImgBgOver,
      msgDateImgBgSelected: m['msgDateImgBgSelected'] ?? fb.msgDateImgBgSelected,
      historyTextInFg: m['historyTextInFg'] ?? fb.historyTextInFg,
      historyTextOutFg: m['historyTextOutFg'] ?? fb.historyTextOutFg,
      historyComposeAreaBg: m['historyComposeAreaBg'] ?? fb.historyComposeAreaBg,
      historyComposeAreaFg: m['historyComposeAreaFg'] ?? fb.historyComposeAreaFg,
      historyComposeIconFg: m['historyComposeIconFg'] ?? fb.historyComposeIconFg,
      historyComposeIconFgOver: m['historyComposeIconFgOver'] ?? fb.historyComposeIconFgOver,
      historyComposeButtonBg: m['historyComposeButtonBg'] ?? fb.historyComposeButtonBg,
      historyComposeButtonBgOver: m['historyComposeButtonBgOver'] ?? fb.historyComposeButtonBgOver,
      historyComposeButtonBgRipple: m['historyComposeButtonBgRipple'] ?? fb.historyComposeButtonBgRipple,
      historySendIconFg: m['historySendIconFg'] ?? fb.historySendIconFg,
      historyReplyBg: m['historyReplyBg'] ?? fb.historyReplyBg,
      historyReplyIconFg: m['historyReplyIconFg'] ?? fb.historyReplyIconFg,
      historyPinnedBg: m['historyPinnedBg'] ?? fb.historyPinnedBg,
      historyUnreadBarBg: m['historyUnreadBarBg'] ?? fb.historyUnreadBarBg,
      historyUnreadBarFg: m['historyUnreadBarFg'] ?? fb.historyUnreadBarFg,
      historyScrollBg: m['historyScrollBg'] ?? fb.historyScrollBg,
      historyScrollBgOver: m['historyScrollBgOver'] ?? fb.historyScrollBgOver,
      historyScrollBarBg: m['historyScrollBarBg'] ?? fb.historyScrollBarBg,
      historyScrollBarBgOver: m['historyScrollBarBgOver'] ?? fb.historyScrollBarBgOver,
      historyToDownBg: m['historyToDownBg'] ?? fb.historyToDownBg,
      historyToDownBgOver: m['historyToDownBgOver'] ?? fb.historyToDownBgOver,
      historyToDownFg: m['historyToDownFg'] ?? fb.historyToDownFg,
      historyOutIconFg: m['historyOutIconFg'] ?? fb.historyOutIconFg,
      historySendingOutIconFg: m['historySendingOutIconFg'] ?? fb.historySendingOutIconFg,
      historySendingInIconFg: m['historySendingInIconFg'] ?? fb.historySendingInIconFg,
      historyIconFgInverted: m['historyIconFgInverted'] ?? fb.historyIconFgInverted,
      historySendingInvertedIconFg: m['historySendingInvertedIconFg'] ?? fb.historySendingInvertedIconFg,
      historyPeer1NameFg: m['historyPeer1NameFg'] ?? fb.historyPeer1NameFg,
      historyPeer2NameFg: m['historyPeer2NameFg'] ?? fb.historyPeer2NameFg,
      historyPeer3NameFg: m['historyPeer3NameFg'] ?? fb.historyPeer3NameFg,
      historyPeer4NameFg: m['historyPeer4NameFg'] ?? fb.historyPeer4NameFg,
      historyPeer5NameFg: m['historyPeer5NameFg'] ?? fb.historyPeer5NameFg,
      historyPeer6NameFg: m['historyPeer6NameFg'] ?? fb.historyPeer6NameFg,
      historyPeer7NameFg: m['historyPeer7NameFg'] ?? fb.historyPeer7NameFg,
      historyPeer8NameFg: m['historyPeer8NameFg'] ?? fb.historyPeer8NameFg,
      historyPeer1UserpicBg: m['historyPeer1UserpicBg'] ?? fb.historyPeer1UserpicBg,
      historyPeer2UserpicBg: m['historyPeer2UserpicBg'] ?? fb.historyPeer2UserpicBg,
      historyPeer3UserpicBg: m['historyPeer3UserpicBg'] ?? fb.historyPeer3UserpicBg,
      historyPeer4UserpicBg: m['historyPeer4UserpicBg'] ?? fb.historyPeer4UserpicBg,
      historyPeer5UserpicBg: m['historyPeer5UserpicBg'] ?? fb.historyPeer5UserpicBg,
      historyPeer6UserpicBg: m['historyPeer6UserpicBg'] ?? fb.historyPeer6UserpicBg,
      historyPeer7UserpicBg: m['historyPeer7UserpicBg'] ?? fb.historyPeer7UserpicBg,
      historyPeer8UserpicBg: m['historyPeer8UserpicBg'] ?? fb.historyPeer8UserpicBg,
      historyPeer1UserpicBg2: m['historyPeer1UserpicBg2'] ?? fb.historyPeer1UserpicBg2,
      historyPeer2UserpicBg2: m['historyPeer2UserpicBg2'] ?? fb.historyPeer2UserpicBg2,
      historyPeer3UserpicBg2: m['historyPeer3UserpicBg2'] ?? fb.historyPeer3UserpicBg2,
      historyPeer4UserpicBg2: m['historyPeer4UserpicBg2'] ?? fb.historyPeer4UserpicBg2,
      historyPeer5UserpicBg2: m['historyPeer5UserpicBg2'] ?? fb.historyPeer5UserpicBg2,
      historyPeer6UserpicBg2: m['historyPeer6UserpicBg2'] ?? fb.historyPeer6UserpicBg2,
      historyPeer7UserpicBg2: m['historyPeer7UserpicBg2'] ?? fb.historyPeer7UserpicBg2,
      historyPeer8UserpicBg2: m['historyPeer8UserpicBg2'] ?? fb.historyPeer8UserpicBg2,
      msgFile1Bg: m['msgFile1Bg'] ?? fb.msgFile1Bg,
      msgFile1BgDark: m['msgFile1BgDark'] ?? fb.msgFile1BgDark,
      msgFile1BgOver: m['msgFile1BgOver'] ?? fb.msgFile1BgOver,
      msgFile1BgSelected: m['msgFile1BgSelected'] ?? fb.msgFile1BgSelected,
      msgFile2Bg: m['msgFile2Bg'] ?? fb.msgFile2Bg,
      msgFile2BgDark: m['msgFile2BgDark'] ?? fb.msgFile2BgDark,
      msgFile2BgOver: m['msgFile2BgOver'] ?? fb.msgFile2BgOver,
      msgFile2BgSelected: m['msgFile2BgSelected'] ?? fb.msgFile2BgSelected,
      msgFile3Bg: m['msgFile3Bg'] ?? fb.msgFile3Bg,
      msgFile3BgDark: m['msgFile3BgDark'] ?? fb.msgFile3BgDark,
      msgFile3BgOver: m['msgFile3BgOver'] ?? fb.msgFile3BgOver,
      msgFile3BgSelected: m['msgFile3BgSelected'] ?? fb.msgFile3BgSelected,
      msgFile4Bg: m['msgFile4Bg'] ?? fb.msgFile4Bg,
      msgFile4BgDark: m['msgFile4BgDark'] ?? fb.msgFile4BgDark,
      msgFile4BgOver: m['msgFile4BgOver'] ?? fb.msgFile4BgOver,
      msgFile4BgSelected: m['msgFile4BgSelected'] ?? fb.msgFile4BgSelected,
      msgWaveformInActive: m['msgWaveformInActive'] ?? fb.msgWaveformInActive,
      msgWaveformInInactive: m['msgWaveformInInactive'] ?? fb.msgWaveformInInactive,
      msgWaveformOutActive: m['msgWaveformOutActive'] ?? fb.msgWaveformOutActive,
      msgWaveformOutInactive: m['msgWaveformOutInactive'] ?? fb.msgWaveformOutInactive,
      mediaviewBg: m['mediaviewBg'] ?? fb.mediaviewBg,
      mediaviewControlBg: m['mediaviewControlBg'] ?? fb.mediaviewControlBg,
      mediaviewControlFg: m['mediaviewControlFg'] ?? fb.mediaviewControlFg,
      mediaviewCaptionBg: m['mediaviewCaptionBg'] ?? fb.mediaviewCaptionBg,
      mediaviewPlaybackActive: m['mediaviewPlaybackActive'] ?? fb.mediaviewPlaybackActive,
      mediaviewPlaybackInactive: m['mediaviewPlaybackInactive'] ?? fb.mediaviewPlaybackInactive,
      mediaviewPlaybackActiveOver: m['mediaviewPlaybackActiveOver'] ?? fb.mediaviewPlaybackActiveOver,
      introCoverTopBg: m['introCoverTopBg'] ?? fb.introCoverTopBg,
      introCoverBottomBg: m['introCoverBottomBg'] ?? fb.introCoverBottomBg,
      introCoverIconsFg: m['introCoverIconsFg'] ?? fb.introCoverIconsFg,
      introCoverPlaneTrace: m['introCoverPlaneTrace'] ?? fb.introCoverPlaneTrace,
      introCoverPlaneTop: m['introCoverPlaneTop'] ?? fb.introCoverPlaneTop,
      scrollBarBg: m['scrollBarBg'] ?? fb.scrollBarBg,
      scrollBarBgOver: m['scrollBarBgOver'] ?? fb.scrollBarBgOver,
      scrollBg: m['scrollBg'] ?? fb.scrollBg,
      scrollBgOver: m['scrollBgOver'] ?? fb.scrollBgOver,
      boxBg: m['boxBg'] ?? fb.boxBg,
      boxTextFg: m['boxTextFg'] ?? fb.boxTextFg,
      boxTitleFg: m['boxTitleFg'] ?? fb.boxTitleFg,
      boxSearchBg: m['boxSearchBg'] ?? fb.boxSearchBg,
      boxTitleAdditionalFg: m['boxTitleAdditionalFg'] ?? fb.boxTitleAdditionalFg,
      boxTextFgGood: m['boxTextFgGood'] ?? fb.boxTextFgGood,
      boxTextFgError: m['boxTextFgError'] ?? fb.boxTextFgError,
      boxDividerBg: m['boxDividerBg'] ?? fb.boxDividerBg,
      profileStatusFgOver: m['profileStatusFgOver'] ?? fb.profileStatusFgOver,
      profileVerifiedCheckBg: m['profileVerifiedCheckBg'] ?? fb.profileVerifiedCheckBg,
      profileVerifiedCheckFg: m['profileVerifiedCheckFg'] ?? fb.profileVerifiedCheckFg,
      profileAdminStartFg: m['profileAdminStartFg'] ?? fb.profileAdminStartFg,
      sideBarBg: m['sideBarBg'] ?? fb.sideBarBg,
      sideBarBgActive: m['sideBarBgActive'] ?? fb.sideBarBgActive,
      sideBarBgRipple: m['sideBarBgRipple'] ?? fb.sideBarBgRipple,
      sideBarTextFg: m['sideBarTextFg'] ?? fb.sideBarTextFg,
      sideBarTextFgActive: m['sideBarTextFgActive'] ?? fb.sideBarTextFgActive,
      sideBarIconFg: m['sideBarIconFg'] ?? fb.sideBarIconFg,
      sideBarIconFgActive: m['sideBarIconFgActive'] ?? fb.sideBarIconFgActive,
      sideBarBadgeBg: m['sideBarBadgeBg'] ?? fb.sideBarBadgeBg,
      sideBarBadgeBgMuted: m['sideBarBadgeBgMuted'] ?? fb.sideBarBadgeBgMuted,
      sideBarBadgeFg: m['sideBarBadgeFg'] ?? fb.sideBarBadgeFg,
      menuBg: m['menuBg'] ?? fb.menuBg,
      menuBgOver: m['menuBgOver'] ?? fb.menuBgOver,
      menuBgRipple: m['menuBgRipple'] ?? fb.menuBgRipple,
      menuIconFg: m['menuIconFg'] ?? m['topBarIconFg'] ?? fb.menuIconFg,
      menuIconFgOver: m['menuIconFgOver'] ?? fb.menuIconFgOver,
      menuSeparatorFg: m['menuSeparatorFg'] ?? fb.menuSeparatorFg,
      mainMenuBg: m['mainMenuBg'] ?? fb.mainMenuBg,
      mainMenuCoverBg: m['mainMenuCoverBg'] ?? fb.mainMenuCoverBg,
      settingsIconBg1: m['settingsIconBg1'] ?? fb.settingsIconBg1,
      settingsIconBg2: m['settingsIconBg2'] ?? fb.settingsIconBg2,
      settingsIconBg3: m['settingsIconBg3'] ?? fb.settingsIconBg3,
      settingsIconBg4: m['settingsIconBg4'] ?? fb.settingsIconBg4,
      settingsIconBg5: m['settingsIconBg5'] ?? fb.settingsIconBg5,
      settingsIconBg6: m['settingsIconBg6'] ?? fb.settingsIconBg6,
      settingsIconBg8: m['settingsIconBg8'] ?? fb.settingsIconBg8,
      settingsIconBgArchive: m['settingsIconBgArchive'] ?? fb.settingsIconBgArchive,
      historyPeer1NameFgSelected: m['historyPeer1NameFgSelected'] ?? fb.historyPeer1NameFgSelected,
      historyPeer2NameFgSelected: m['historyPeer2NameFgSelected'] ?? fb.historyPeer2NameFgSelected,
      historyPeer3NameFgSelected: m['historyPeer3NameFgSelected'] ?? fb.historyPeer3NameFgSelected,
      historyPeer4NameFgSelected: m['historyPeer4NameFgSelected'] ?? fb.historyPeer4NameFgSelected,
      historyPeer5NameFgSelected: m['historyPeer5NameFgSelected'] ?? fb.historyPeer5NameFgSelected,
      historyPeer6NameFgSelected: m['historyPeer6NameFgSelected'] ?? fb.historyPeer6NameFgSelected,
      historyPeer7NameFgSelected: m['historyPeer7NameFgSelected'] ?? fb.historyPeer7NameFgSelected,
      historyPeer8NameFgSelected: m['historyPeer8NameFgSelected'] ?? fb.historyPeer8NameFgSelected,
      mediaviewFileRedCornerFg: m['mediaviewFileRedCornerFg'] ?? fb.mediaviewFileRedCornerFg,
      mediaviewFileYellowCornerFg: m['mediaviewFileYellowCornerFg'] ?? fb.mediaviewFileYellowCornerFg,
      mediaviewFileGreenCornerFg: m['mediaviewFileGreenCornerFg'] ?? fb.mediaviewFileGreenCornerFg,
      mediaviewFileBlueCornerFg: m['mediaviewFileBlueCornerFg'] ?? fb.mediaviewFileBlueCornerFg,
      premiumButtonBg1: m['premiumButtonBg1'] ?? fb.premiumButtonBg1,
      premiumButtonBg2: m['premiumButtonBg2'] ?? fb.premiumButtonBg2,
      premiumButtonBg3: m['premiumButtonBg3'] ?? fb.premiumButtonBg3,
      premiumIconBg1: m['premiumIconBg1'] ?? fb.premiumIconBg1,
      premiumIconBg2: m['premiumIconBg2'] ?? fb.premiumIconBg2,
      callIconFg: m['callIconFg'] ?? fb.callIconFg,
      tooltipBg: m['tooltipBg'] ?? fb.tooltipBg,
      tooltipFg: m['tooltipFg'] ?? fb.tooltipFg,
      tooltipBorderFg: m['tooltipBorderFg'] ?? fb.tooltipBorderFg,
      importantTooltipBg: m['importantTooltipBg'] ?? fb.importantTooltipBg,
      overviewCheckBg: m['overviewCheckBg'] ?? fb.overviewCheckBg,
      slideFadeOutBg: m['slideFadeOutBg'] ?? fb.slideFadeOutBg,
      slideFadeOutShadowFg: m['slideFadeOutShadowFg'] ?? fb.slideFadeOutShadowFg,
      imageBg: m['imageBg'] ?? fb.imageBg,
      imageBgTransparent: m['imageBgTransparent'] ?? fb.imageBgTransparent,
      activeButtonFgOver: m['activeButtonFgOver'] ?? fb.activeButtonFgOver,
      activeButtonSecondaryFgOver: m['activeButtonSecondaryFgOver'] ?? fb.activeButtonSecondaryFgOver,
      attentionButtonFgOver: m['attentionButtonFgOver'] ?? fb.attentionButtonFgOver,
      menuSubmenuArrowFg: m['menuSubmenuArrowFg'] ?? fb.menuSubmenuArrowFg,
      menuFgDisabled: m['menuFgDisabled'] ?? fb.menuFgDisabled,
      smallCloseIconFg: m['smallCloseIconFg'] ?? fb.smallCloseIconFg,
      smallCloseIconFgOver: m['smallCloseIconFgOver'] ?? fb.smallCloseIconFgOver,
      radialFg: m['radialFg'] ?? fb.radialFg,
      radialBg: m['radialBg'] ?? fb.radialBg,
      placeholderFg: m['placeholderFg'] ?? fb.placeholderFg,
      placeholderFgActive: m['placeholderFgActive'] ?? fb.placeholderFgActive,
      inputBorderFg: m['inputBorderFg'] ?? fb.inputBorderFg,
      filterInputBorderFg: m['filterInputBorderFg'] ?? fb.filterInputBorderFg,
      filterInputActiveBg: m['filterInputActiveBg'] ?? fb.filterInputActiveBg,
      filterInputInactiveBg: m['filterInputInactiveBg'] ?? fb.filterInputInactiveBg,
      checkboxFg: m['checkboxFg'] ?? fb.checkboxFg,
      botKbBg: m['botKbBg'] ?? fb.botKbBg,
      botKbDownBg: m['botKbDownBg'] ?? fb.botKbDownBg,
      botKbColor: m['botKbColor'] ?? fb.botKbColor,
      botKbPrimaryBg: m['botKbPrimaryBg'] ?? fb.botKbPrimaryBg,
      botKbDangerBg: m['botKbDangerBg'] ?? fb.botKbDangerBg,
      botKbSuccessBg: m['botKbSuccessBg'] ?? fb.botKbSuccessBg,
      botKbInlinePrimaryBg: m['botKbInlinePrimaryBg'] ?? fb.botKbInlinePrimaryBg,
      botKbInlineDangerBg: m['botKbInlineDangerBg'] ?? fb.botKbInlineDangerBg,
      botKbInlineSuccessBg: m['botKbInlineSuccessBg'] ?? fb.botKbInlineSuccessBg,
      sliderBgInactive: m['sliderBgInactive'] ?? fb.sliderBgInactive,
      sliderBgActive: m['sliderBgActive'] ?? fb.sliderBgActive,
      titleButtonBg: m['titleButtonBg'] ?? fb.titleButtonBg,
      titleButtonFg: m['titleButtonFg'] ?? fb.titleButtonFg,
      titleButtonBgOver: m['titleButtonBgOver'] ?? fb.titleButtonBgOver,
      titleButtonFgOver: m['titleButtonFgOver'] ?? fb.titleButtonFgOver,
      titleButtonBgActive: m['titleButtonBgActive'] ?? fb.titleButtonBgActive,
      titleButtonFgActive: m['titleButtonFgActive'] ?? fb.titleButtonFgActive,
      titleButtonBgActiveOver: m['titleButtonBgActiveOver'] ?? fb.titleButtonBgActiveOver,
      titleButtonFgActiveOver: m['titleButtonFgActiveOver'] ?? fb.titleButtonFgActiveOver,
      titleButtonCloseBg: m['titleButtonCloseBg'] ?? fb.titleButtonCloseBg,
      titleButtonCloseFg: m['titleButtonCloseFg'] ?? fb.titleButtonCloseFg,
      titleButtonCloseBgOver: m['titleButtonCloseBgOver'] ?? fb.titleButtonCloseBgOver,
      titleButtonCloseFgOver: m['titleButtonCloseFgOver'] ?? fb.titleButtonCloseFgOver,
      titleButtonCloseBgActive: m['titleButtonCloseBgActive'] ?? fb.titleButtonCloseBgActive,
      titleButtonCloseFgActive: m['titleButtonCloseFgActive'] ?? fb.titleButtonCloseFgActive,
      titleButtonCloseBgActiveOver: m['titleButtonCloseBgActiveOver'] ?? fb.titleButtonCloseBgActiveOver,
      titleButtonCloseFgActiveOver: m['titleButtonCloseFgActiveOver'] ?? fb.titleButtonCloseFgActiveOver,
      trayCounterBg: m['trayCounterBg'] ?? fb.trayCounterBg,
      trayCounterBgMute: m['trayCounterBgMute'] ?? fb.trayCounterBgMute,
      trayCounterFg: m['trayCounterFg'] ?? fb.trayCounterFg,
      trayCounterBgMacInvert: m['trayCounterBgMacInvert'] ?? fb.trayCounterBgMacInvert,
      trayCounterFgMacInvert: m['trayCounterFgMacInvert'] ?? fb.trayCounterFgMacInvert,
      cancelIconFg: m['cancelIconFg'] ?? fb.cancelIconFg,
      cancelIconFgOver: m['cancelIconFgOver'] ?? fb.cancelIconFgOver,
      boxTitleCloseFg: m['boxTitleCloseFg'] ?? fb.boxTitleCloseFg,
      boxTitleCloseFgOver: m['boxTitleCloseFgOver'] ?? fb.boxTitleCloseFgOver,
      boxDividerFg: m['boxDividerFg'] ?? fb.boxDividerFg,
      paymentsTipActive: m['paymentsTipActive'] ?? fb.paymentsTipActive,
      membersAboutLimitFg: m['membersAboutLimitFg'] ?? fb.membersAboutLimitFg,
      contactsBg: m['contactsBg'] ?? fb.contactsBg,
      contactsBgOver: m['contactsBgOver'] ?? fb.contactsBgOver,
      contactsNameFg: m['contactsNameFg'] ?? fb.contactsNameFg,
      contactsStatusFg: m['contactsStatusFg'] ?? fb.contactsStatusFg,
      contactsStatusFgOver: m['contactsStatusFgOver'] ?? fb.contactsStatusFgOver,
      contactsStatusFgOnline: m['contactsStatusFgOnline'] ?? fb.contactsStatusFgOnline,
      photoCropFadeBg: m['photoCropFadeBg'] ?? fb.photoCropFadeBg,
      photoCropPointFg: m['photoCropPointFg'] ?? fb.photoCropPointFg,
      callArrowFg: m['callArrowFg'] ?? fb.callArrowFg,
      callArrowMissedFg: m['callArrowMissedFg'] ?? fb.callArrowMissedFg,
      introBg: m['introBg'] ?? fb.introBg,
      introTitleFg: m['introTitleFg'] ?? fb.introTitleFg,
      introDescriptionFg: m['introDescriptionFg'] ?? fb.introDescriptionFg,
      introCoverPlaneInner: m['introCoverPlaneInner'] ?? fb.introCoverPlaneInner,
      introCoverPlaneOuter: m['introCoverPlaneOuter'] ?? fb.introCoverPlaneOuter,
      dialogsMenuIconFg: m['dialogsMenuIconFg'] ?? fb.dialogsMenuIconFg,
      dialogsMenuIconFgOver: m['dialogsMenuIconFgOver'] ?? fb.dialogsMenuIconFgOver,
      dialogsChatIconFg: m['dialogsChatIconFg'] ?? fb.dialogsChatIconFg,
      dialogsChatIconFgOver: m['dialogsChatIconFgOver'] ?? fb.dialogsChatIconFgOver,
      dialogsDateFgOver: m['dialogsDateFgOver'] ?? fb.dialogsDateFgOver,
      dialogsTextFgServiceOver: m['dialogsTextFgServiceOver'] ?? fb.dialogsTextFgServiceOver,
      dialogsDraftFgOver: m['dialogsDraftFgOver'] ?? fb.dialogsDraftFgOver,
      dialogsVerifiedIconBgOver: m['dialogsVerifiedIconBgOver'] ?? fb.dialogsVerifiedIconBgOver,
      dialogsVerifiedIconFgOver: m['dialogsVerifiedIconFgOver'] ?? fb.dialogsVerifiedIconFgOver,
      dialogsSendingIconFgOver: m['dialogsSendingIconFgOver'] ?? fb.dialogsSendingIconFgOver,
      dialogsSentIconFgOver: m['dialogsSentIconFgOver'] ?? fb.dialogsSentIconFgOver,
      dialogsUnreadBgOver: m['dialogsUnreadBgOver'] ?? fb.dialogsUnreadBgOver,
      dialogsUnreadBgMutedOver: m['dialogsUnreadBgMutedOver'] ?? fb.dialogsUnreadBgMutedOver,
      dialogsUnreadFgOver: m['dialogsUnreadFgOver'] ?? fb.dialogsUnreadFgOver,
      dialogsArchiveFgOver: m['dialogsArchiveFgOver'] ?? fb.dialogsArchiveFgOver,
      dialogsScamFg: m['dialogsScamFg'] ?? fb.dialogsScamFg,
      dialogsScamFgOver: m['dialogsScamFgOver'] ?? fb.dialogsScamFgOver,
      dialogsChatIconFgActive: m['dialogsChatIconFgActive'] ?? fb.dialogsChatIconFgActive,
      dialogsDateFgActive: m['dialogsDateFgActive'] ?? fb.dialogsDateFgActive,
      dialogsTextFgServiceActive: m['dialogsTextFgServiceActive'] ?? fb.dialogsTextFgServiceActive,
      dialogsDraftFgActive: m['dialogsDraftFgActive'] ?? fb.dialogsDraftFgActive,
      dialogsVerifiedIconBgActive: m['dialogsVerifiedIconBgActive'] ?? fb.dialogsVerifiedIconBgActive,
      dialogsVerifiedIconFgActive: m['dialogsVerifiedIconFgActive'] ?? fb.dialogsVerifiedIconFgActive,
      dialogsSendingIconFgActive: m['dialogsSendingIconFgActive'] ?? fb.dialogsSendingIconFgActive,
      dialogsSentIconFgActive: m['dialogsSentIconFgActive'] ?? fb.dialogsSentIconFgActive,
      dialogsScamFgActive: m['dialogsScamFgActive'] ?? fb.dialogsScamFgActive,
      dialogsMentionIconFg: m['dialogsMentionIconFg'] ?? fb.dialogsMentionIconFg,
      dialogsReactionIconFg: m['dialogsReactionIconFg'] ?? fb.dialogsReactionIconFg,
      dialogsPollIconFg: m['dialogsPollIconFg'] ?? fb.dialogsPollIconFg,
      searchedBarBg: m['searchedBarBg'] ?? fb.searchedBarBg,
      searchedBarFg: m['searchedBarFg'] ?? fb.searchedBarFg,
      emojiPanBg: m['emojiPanBg'] ?? fb.emojiPanBg,
      emojiPanCategories: m['emojiPanCategories'] ?? fb.emojiPanCategories,
      emojiPanHeaderFg: m['emojiPanHeaderFg'] ?? fb.emojiPanHeaderFg,
      emojiPanHeaderBg: m['emojiPanHeaderBg'] ?? fb.emojiPanHeaderBg,
      emojiIconFg: m['emojiIconFg'] ?? fb.emojiIconFg,
      emojiSubIconFgActive: m['emojiSubIconFgActive'] ?? fb.emojiSubIconFgActive,
      stickerPanDeleteBg: m['stickerPanDeleteBg'] ?? fb.stickerPanDeleteBg,
      stickerPanDeleteFg: m['stickerPanDeleteFg'] ?? fb.stickerPanDeleteFg,
      stickerPreviewBg: m['stickerPreviewBg'] ?? fb.stickerPreviewBg,
      stickerPanPremium1: m['stickerPanPremium1'] ?? fb.stickerPanPremium1,
      stickerPanPremium2: m['stickerPanPremium2'] ?? fb.stickerPanPremium2,
      historyTextInFgSelected: m['historyTextInFgSelected'] ?? fb.historyTextInFgSelected,
      historyTextOutFgSelected: m['historyTextOutFgSelected'] ?? fb.historyTextOutFgSelected,
      historyLinkInFg: m['historyLinkInFg'] ?? fb.historyLinkInFg,
      historyLinkInFgSelected: m['historyLinkInFgSelected'] ?? fb.historyLinkInFgSelected,
      historyLinkOutFg: m['historyLinkOutFg'] ?? fb.historyLinkOutFg,
      historyLinkOutFgSelected: m['historyLinkOutFgSelected'] ?? fb.historyLinkOutFgSelected,
      historyFileNameInFg: m['historyFileNameInFg'] ?? fb.historyFileNameInFg,
      historyFileNameInFgSelected: m['historyFileNameInFgSelected'] ?? fb.historyFileNameInFgSelected,
      historyFileNameOutFg: m['historyFileNameOutFg'] ?? fb.historyFileNameOutFg,
      historyFileNameOutFgSelected: m['historyFileNameOutFgSelected'] ?? fb.historyFileNameOutFgSelected,
      historyOutIconFgSelected: m['historyOutIconFgSelected'] ?? fb.historyOutIconFgSelected,
      historyCallArrowInFg: m['historyCallArrowInFg'] ?? fb.historyCallArrowInFg,
      historyCallArrowInFgSelected: m['historyCallArrowInFgSelected'] ?? fb.historyCallArrowInFgSelected,
      historyCallArrowMissedInFg: m['historyCallArrowMissedInFg'] ?? fb.historyCallArrowMissedInFg,
      historyCallArrowMissedInFgSelected: m['historyCallArrowMissedInFgSelected'] ?? fb.historyCallArrowMissedInFgSelected,
      historyCallArrowOutFg: m['historyCallArrowOutFg'] ?? fb.historyCallArrowOutFg,
      historyCallArrowOutFgSelected: m['historyCallArrowOutFgSelected'] ?? fb.historyCallArrowOutFgSelected,
      historyUnreadBarBorder: m['historyUnreadBarBorder'] ?? fb.historyUnreadBarBorder,
      historyForwardChooseBg: m['historyForwardChooseBg'] ?? fb.historyForwardChooseBg,
      historyForwardChooseFg: m['historyForwardChooseFg'] ?? fb.historyForwardChooseFg,
      historyPeerUserpicFg: m['historyPeerUserpicFg'] ?? fb.historyPeerUserpicFg,
      historyPeerSavedMessagesBg: m['historyPeerSavedMessagesBg'] ?? fb.historyPeerSavedMessagesBg,
      historyPeerArchiveUserpicBg: m['historyPeerArchiveUserpicBg'] ?? fb.historyPeerArchiveUserpicBg,
      historyPeerSavedMessagesBg2: m['historyPeerSavedMessagesBg2'] ?? fb.historyPeerSavedMessagesBg2,
      settingsIconFg: m['settingsIconFg'] ?? fb.settingsIconFg,
      msgInServiceFgSelected: m['msgInServiceFgSelected'] ?? fb.msgInServiceFgSelected,
      msgOutServiceFgSelected: m['msgOutServiceFgSelected'] ?? fb.msgOutServiceFgSelected,
      msgInShadowSelected: m['msgInShadowSelected'] ?? fb.msgInShadowSelected,
      msgOutShadowSelected: m['msgOutShadowSelected'] ?? fb.msgOutShadowSelected,
      msgInDateFgSelected: m['msgInDateFgSelected'] ?? fb.msgInDateFgSelected,
      msgOutDateFgSelected: m['msgOutDateFgSelected'] ?? fb.msgOutDateFgSelected,
      msgInReplyBarSelColor: m['msgInReplyBarSelColor'] ?? fb.msgInReplyBarSelColor,
      msgOutReplyBarSelColor: m['msgOutReplyBarSelColor'] ?? fb.msgOutReplyBarSelColor,
      msgImgReplyBarColor: m['msgImgReplyBarColor'] ?? fb.msgImgReplyBarColor,
      msgInMonoFgSelected: m['msgInMonoFgSelected'] ?? fb.msgInMonoFgSelected,
      msgOutMonoFgSelected: m['msgOutMonoFgSelected'] ?? fb.msgOutMonoFgSelected,
      msgDateImgFg: m['msgDateImgFg'] ?? fb.msgDateImgFg,
      msgFileThumbLinkInFg: m['msgFileThumbLinkInFg'] ?? fb.msgFileThumbLinkInFg,
      msgFileThumbLinkInFgSelected: m['msgFileThumbLinkInFgSelected'] ?? fb.msgFileThumbLinkInFgSelected,
      msgFileThumbLinkOutFg: m['msgFileThumbLinkOutFg'] ?? fb.msgFileThumbLinkOutFg,
      msgFileThumbLinkOutFgSelected: m['msgFileThumbLinkOutFgSelected'] ?? fb.msgFileThumbLinkOutFgSelected,
      msgFileInBgOver: m['msgFileInBgOver'] ?? fb.msgFileInBgOver,
      msgFileInBgSelected: m['msgFileInBgSelected'] ?? fb.msgFileInBgSelected,
      msgFileOutBgSelected: m['msgFileOutBgSelected'] ?? fb.msgFileOutBgSelected,
      historyFileInIconFg: m['historyFileInIconFg'] ?? fb.historyFileInIconFg,
      historyFileInIconFgSelected: m['historyFileInIconFgSelected'] ?? fb.historyFileInIconFgSelected,
      historyFileInRadialFg: m['historyFileInRadialFg'] ?? fb.historyFileInRadialFg,
      historyFileInRadialFgSelected: m['historyFileInRadialFgSelected'] ?? fb.historyFileInRadialFgSelected,
      historyFileOutIconFg: m['historyFileOutIconFg'] ?? fb.historyFileOutIconFg,
      historyFileOutIconFgSelected: m['historyFileOutIconFgSelected'] ?? fb.historyFileOutIconFgSelected,
      historyFileOutRadialFg: m['historyFileOutRadialFg'] ?? fb.historyFileOutRadialFg,
      historyFileOutRadialFgSelected: m['historyFileOutRadialFgSelected'] ?? fb.historyFileOutRadialFgSelected,
      historyFileThumbIconFg: m['historyFileThumbIconFg'] ?? fb.historyFileThumbIconFg,
      historyFileThumbIconFgSelected: m['historyFileThumbIconFgSelected'] ?? fb.historyFileThumbIconFgSelected,
      historyFileThumbRadialFg: m['historyFileThumbRadialFg'] ?? fb.historyFileThumbRadialFg,
      historyFileThumbRadialFgSelected: m['historyFileThumbRadialFgSelected'] ?? fb.historyFileThumbRadialFgSelected,
      historyVideoMessageProgressFg: m['historyVideoMessageProgressFg'] ?? fb.historyVideoMessageProgressFg,
      msgWaveformInActiveSelected: m['msgWaveformInActiveSelected'] ?? fb.msgWaveformInActiveSelected,
      msgWaveformInInactiveSelected: m['msgWaveformInInactiveSelected'] ?? fb.msgWaveformInInactiveSelected,
      msgWaveformOutActiveSelected: m['msgWaveformOutActiveSelected'] ?? fb.msgWaveformOutActiveSelected,
      msgWaveformOutInactiveSelected: m['msgWaveformOutInactiveSelected'] ?? fb.msgWaveformOutInactiveSelected,
      msgBotKbOverBgAdd: m['msgBotKbOverBgAdd'] ?? fb.msgBotKbOverBgAdd,
      msgBotKbIconFg: m['msgBotKbIconFg'] ?? fb.msgBotKbIconFg,
      msgBotKbRippleBg: m['msgBotKbRippleBg'] ?? fb.msgBotKbRippleBg,
      mediaInFg: m['mediaInFg'] ?? fb.mediaInFg,
      mediaInFgSelected: m['mediaInFgSelected'] ?? fb.mediaInFgSelected,
      mediaOutFg: m['mediaOutFg'] ?? fb.mediaOutFg,
      mediaOutFgSelected: m['mediaOutFgSelected'] ?? fb.mediaOutFgSelected,
      youtubePlayIconBg: m['youtubePlayIconBg'] ?? fb.youtubePlayIconBg,
      youtubePlayIconFg: m['youtubePlayIconFg'] ?? fb.youtubePlayIconFg,
      videoPlayIconBg: m['videoPlayIconBg'] ?? fb.videoPlayIconBg,
      videoPlayIconFg: m['videoPlayIconFg'] ?? fb.videoPlayIconFg,
      toastBg: m['toastBg'] ?? fb.toastBg,
      toastFg: m['toastFg'] ?? fb.toastFg,
      historyToDownBgRipple: m['historyToDownBgRipple'] ?? fb.historyToDownBgRipple,
      historyToDownFgOver: m['historyToDownFgOver'] ?? fb.historyToDownFgOver,
      historyToDownShadow: m['historyToDownShadow'] ?? fb.historyToDownShadow,
      historyComposeAreaFgService: m['historyComposeAreaFgService'] ?? fb.historyComposeAreaFgService,
      historySendIconFgOver: m['historySendIconFgOver'] ?? fb.historySendIconFgOver,
      historyReplyCancelFg: m['historyReplyCancelFg'] ?? fb.historyReplyCancelFg,
      historyReplyCancelFgOver: m['historyReplyCancelFgOver'] ?? fb.historyReplyCancelFgOver,
      mapPointDrop: m['mapPointDrop'] ?? fb.mapPointDrop,
      mapPointDot: m['mapPointDot'] ?? fb.mapPointDot,
      overviewCheckBgActive: m['overviewCheckBgActive'] ?? fb.overviewCheckBgActive,
      overviewCheckBorder: m['overviewCheckBorder'] ?? fb.overviewCheckBorder,
      overviewCheckFgActive: m['overviewCheckFgActive'] ?? fb.overviewCheckFgActive,
      overviewPhotoSelectOverlay: m['overviewPhotoSelectOverlay'] ?? fb.overviewPhotoSelectOverlay,
      notificationsBoxMonitorFg: m['notificationsBoxMonitorFg'] ?? fb.notificationsBoxMonitorFg,
      notificationsBoxScreenBg: m['notificationsBoxScreenBg'] ?? fb.notificationsBoxScreenBg,
      notificationSampleUserpicFg: m['notificationSampleUserpicFg'] ?? fb.notificationSampleUserpicFg,
      notificationSampleCloseFg: m['notificationSampleCloseFg'] ?? fb.notificationSampleCloseFg,
      notificationSampleTextFg: m['notificationSampleTextFg'] ?? fb.notificationSampleTextFg,
      notificationSampleNameFg: m['notificationSampleNameFg'] ?? fb.notificationSampleNameFg,
      mainMenuCloudFg: m['mainMenuCloudFg'] ?? fb.mainMenuCloudFg,
      mainMenuCloudBg: m['mainMenuCloudBg'] ?? fb.mainMenuCloudBg,
      mediaPlayerBg: m['mediaPlayerBg'] ?? fb.mediaPlayerBg,
      mediaPlayerActiveFg: m['mediaPlayerActiveFg'] ?? fb.mediaPlayerActiveFg,
      mediaPlayerInactiveFg: m['mediaPlayerInactiveFg'] ?? fb.mediaPlayerInactiveFg,
      mediaPlayerDisabledFg: m['mediaPlayerDisabledFg'] ?? fb.mediaPlayerDisabledFg,
      mediaviewFileBg: m['mediaviewFileBg'] ?? fb.mediaviewFileBg,
      mediaviewFileNameFg: m['mediaviewFileNameFg'] ?? fb.mediaviewFileNameFg,
      mediaviewFileSizeFg: m['mediaviewFileSizeFg'] ?? fb.mediaviewFileSizeFg,
      mediaviewFileExtFg: m['mediaviewFileExtFg'] ?? fb.mediaviewFileExtFg,
      mediaviewMenuBg: m['mediaviewMenuBg'] ?? fb.mediaviewMenuBg,
      mediaviewMenuBgOver: m['mediaviewMenuBgOver'] ?? fb.mediaviewMenuBgOver,
      mediaviewMenuBgRipple: m['mediaviewMenuBgRipple'] ?? fb.mediaviewMenuBgRipple,
      mediaviewMenuFg: m['mediaviewMenuFg'] ?? fb.mediaviewMenuFg,
      mediaviewVideoBg: m['mediaviewVideoBg'] ?? fb.mediaviewVideoBg,
      mediaviewCaptionFg: m['mediaviewCaptionFg'] ?? fb.mediaviewCaptionFg,
      mediaviewTextLinkFg: m['mediaviewTextLinkFg'] ?? fb.mediaviewTextLinkFg,
      mediaviewSaveMsgBg: m['mediaviewSaveMsgBg'] ?? fb.mediaviewSaveMsgBg,
      mediaviewSaveMsgFg: m['mediaviewSaveMsgFg'] ?? fb.mediaviewSaveMsgFg,
      mediaviewPlaybackInactiveOver: m['mediaviewPlaybackInactiveOver'] ?? fb.mediaviewPlaybackInactiveOver,
      mediaviewPlaybackProgressFg: m['mediaviewPlaybackProgressFg'] ?? fb.mediaviewPlaybackProgressFg,
      mediaviewPlaybackIconFg: m['mediaviewPlaybackIconFg'] ?? fb.mediaviewPlaybackIconFg,
      mediaviewPlaybackIconFgOver: m['mediaviewPlaybackIconFgOver'] ?? fb.mediaviewPlaybackIconFgOver,
      mediaviewPlaybackIconRipple: m['mediaviewPlaybackIconRipple'] ?? fb.mediaviewPlaybackIconRipple,
      mediaviewPipControlsFg: m['mediaviewPipControlsFg'] ?? fb.mediaviewPipControlsFg,
      mediaviewPipControlsFgOver: m['mediaviewPipControlsFgOver'] ?? fb.mediaviewPipControlsFgOver,
      mediaviewPipPlaybackActive: m['mediaviewPipPlaybackActive'] ?? fb.mediaviewPipPlaybackActive,
      mediaviewPipPlaybackInactive: m['mediaviewPipPlaybackInactive'] ?? fb.mediaviewPipPlaybackInactive,
      mediaviewTransparentBg: m['mediaviewTransparentBg'] ?? fb.mediaviewTransparentBg,
      mediaviewTransparentFg: m['mediaviewTransparentFg'] ?? fb.mediaviewTransparentFg,
      notificationBg: m['notificationBg'] ?? fb.notificationBg,
      callBg: m['callBg'] ?? fb.callBg,
      callBgOpaque: m['callBgOpaque'] ?? fb.callBgOpaque,
      callBgButton: m['callBgButton'] ?? fb.callBgButton,
      callNameFg: m['callNameFg'] ?? fb.callNameFg,
      callStatusFg: m['callStatusFg'] ?? fb.callStatusFg,
      callIconBg: m['callIconBg'] ?? fb.callIconBg,
      callIconBgActive: m['callIconBgActive'] ?? fb.callIconBgActive,
      callIconFgActive: m['callIconFgActive'] ?? fb.callIconFgActive,
      callIconActiveRipple: m['callIconActiveRipple'] ?? fb.callIconActiveRipple,
      callAnswerBg: m['callAnswerBg'] ?? fb.callAnswerBg,
      callAnswerRipple: m['callAnswerRipple'] ?? fb.callAnswerRipple,
      callAnswerBgOuter: m['callAnswerBgOuter'] ?? fb.callAnswerBgOuter,
      callHangupBg: m['callHangupBg'] ?? fb.callHangupBg,
      callHangupRipple: m['callHangupRipple'] ?? fb.callHangupRipple,
      callMuteRipple: m['callMuteRipple'] ?? fb.callMuteRipple,
      callBarBg: m['callBarBg'] ?? fb.callBarBg,
      callBarMuteRipple: m['callBarMuteRipple'] ?? fb.callBarMuteRipple,
      callBarBgMuted: m['callBarBgMuted'] ?? fb.callBarBgMuted,
      callBarFg: m['callBarFg'] ?? fb.callBarFg,
      importantTooltipFg: m['importantTooltipFg'] ?? fb.importantTooltipFg,
      importantTooltipFgLink: m['importantTooltipFgLink'] ?? fb.importantTooltipFgLink,
      premiumButtonFg: m['premiumButtonFg'] ?? fb.premiumButtonFg,
      premiumIconBg3: m['premiumIconBg3'] ?? fb.premiumIconBg3,
      groupCallBg: m['groupCallBg'] ?? fb.groupCallBg,
      groupCallActiveFg: m['groupCallActiveFg'] ?? fb.groupCallActiveFg,
      groupCallMembersBg: m['groupCallMembersBg'] ?? fb.groupCallMembersBg,
      groupCallMembersBgOver: m['groupCallMembersBgOver'] ?? fb.groupCallMembersBgOver,
      groupCallMembersBgRipple: m['groupCallMembersBgRipple'] ?? fb.groupCallMembersBgRipple,
      groupCallMembersFg: m['groupCallMembersFg'] ?? fb.groupCallMembersFg,
      groupCallMemberActiveIcon: m['groupCallMemberActiveIcon'] ?? fb.groupCallMemberActiveIcon,
      groupCallMemberActiveStatus: m['groupCallMemberActiveStatus'] ?? fb.groupCallMemberActiveStatus,
      groupCallMemberInactiveIcon: m['groupCallMemberInactiveIcon'] ?? fb.groupCallMemberInactiveIcon,
      groupCallMemberInactiveStatus: m['groupCallMemberInactiveStatus'] ?? fb.groupCallMemberInactiveStatus,
      groupCallMemberMutedIcon: m['groupCallMemberMutedIcon'] ?? fb.groupCallMemberMutedIcon,
      groupCallMemberNotJoinedStatus: m['groupCallMemberNotJoinedStatus'] ?? fb.groupCallMemberNotJoinedStatus,
      groupCallIconFg: m['groupCallIconFg'] ?? fb.groupCallIconFg,
      groupCallLive1: m['groupCallLive1'] ?? fb.groupCallLive1,
      groupCallLive2: m['groupCallLive2'] ?? fb.groupCallLive2,
      groupCallMuted1: m['groupCallMuted1'] ?? fb.groupCallMuted1,
      groupCallMuted2: m['groupCallMuted2'] ?? fb.groupCallMuted2,
      groupCallForceMutedBar1: m['groupCallForceMutedBar1'] ?? fb.groupCallForceMutedBar1,
      groupCallForceMutedBar2: m['groupCallForceMutedBar2'] ?? fb.groupCallForceMutedBar2,
      groupCallForceMutedBar3: m['groupCallForceMutedBar3'] ?? fb.groupCallForceMutedBar3,
      groupCallForceMuted1: m['groupCallForceMuted1'] ?? fb.groupCallForceMuted1,
      groupCallForceMuted2: m['groupCallForceMuted2'] ?? fb.groupCallForceMuted2,
      groupCallForceMuted3: m['groupCallForceMuted3'] ?? fb.groupCallForceMuted3,
      groupCallMenuBg: m['groupCallMenuBg'] ?? fb.groupCallMenuBg,
      groupCallMenuBgOver: m['groupCallMenuBgOver'] ?? fb.groupCallMenuBgOver,
      groupCallMenuBgRipple: m['groupCallMenuBgRipple'] ?? fb.groupCallMenuBgRipple,
      groupCallLeaveBg: m['groupCallLeaveBg'] ?? fb.groupCallLeaveBg,
      groupCallLeaveBgRipple: m['groupCallLeaveBgRipple'] ?? fb.groupCallLeaveBgRipple,
      groupCallVideoTextFg: m['groupCallVideoTextFg'] ?? fb.groupCallVideoTextFg,
      groupCallVideoSubTextFg: m['groupCallVideoSubTextFg'] ?? fb.groupCallVideoSubTextFg,
      outdatedFg: m['outdatedFg'] ?? fb.outdatedFg,
      outdateSoonBg: m['outdateSoonBg'] ?? fb.outdateSoonBg,
      outdatedBg: m['outdatedBg'] ?? fb.outdatedBg,
      spellUnderline: m['spellUnderline'] ?? fb.spellUnderline,
      walletTitleBg: m['walletTitleBg'] ?? fb.walletTitleBg,
      walletTitleBgActive: m['walletTitleBgActive'] ?? fb.walletTitleBgActive,
      walletTitleButtonBg: m['walletTitleButtonBg'] ?? fb.walletTitleButtonBg,
      walletTitleButtonFg: m['walletTitleButtonFg'] ?? fb.walletTitleButtonFg,
      walletTitleButtonBgOver: m['walletTitleButtonBgOver'] ?? fb.walletTitleButtonBgOver,
      walletTitleButtonFgOver: m['walletTitleButtonFgOver'] ?? fb.walletTitleButtonFgOver,
      walletTitleButtonBgActive: m['walletTitleButtonBgActive'] ?? fb.walletTitleButtonBgActive,
      walletTitleButtonFgActive: m['walletTitleButtonFgActive'] ?? fb.walletTitleButtonFgActive,
      walletTitleButtonBgActiveOver: m['walletTitleButtonBgActiveOver'] ?? fb.walletTitleButtonBgActiveOver,
      walletTitleButtonFgActiveOver: m['walletTitleButtonFgActiveOver'] ?? fb.walletTitleButtonFgActiveOver,
      walletTitleButtonCloseBg: m['walletTitleButtonCloseBg'] ?? fb.walletTitleButtonCloseBg,
      walletTitleButtonCloseFg: m['walletTitleButtonCloseFg'] ?? fb.walletTitleButtonCloseFg,
      walletTitleButtonCloseBgOver: m['walletTitleButtonCloseBgOver'] ?? fb.walletTitleButtonCloseBgOver,
      walletTitleButtonCloseFgOver: m['walletTitleButtonCloseFgOver'] ?? fb.walletTitleButtonCloseFgOver,
      walletTitleButtonCloseBgActive: m['walletTitleButtonCloseBgActive'] ?? fb.walletTitleButtonCloseBgActive,
      walletTitleButtonCloseFgActive: m['walletTitleButtonCloseFgActive'] ?? fb.walletTitleButtonCloseFgActive,
      walletTitleButtonCloseBgActiveOver: m['walletTitleButtonCloseBgActiveOver'] ?? fb.walletTitleButtonCloseBgActiveOver,
      walletTitleButtonCloseFgActiveOver: m['walletTitleButtonCloseFgActiveOver'] ?? fb.walletTitleButtonCloseFgActiveOver,
      walletTopBg: m['walletTopBg'] ?? fb.walletTopBg,
      walletBalanceFg: m['walletBalanceFg'] ?? fb.walletBalanceFg,
      walletSubBalanceFg: m['walletSubBalanceFg'] ?? fb.walletSubBalanceFg,
      walletTopLabelFg: m['walletTopLabelFg'] ?? fb.walletTopLabelFg,
      walletTopIconFg: m['walletTopIconFg'] ?? fb.walletTopIconFg,
      walletTopIconRipple: m['walletTopIconRipple'] ?? fb.walletTopIconRipple,
      songCoverOverlayFg: m['songCoverOverlayFg'] ?? fb.songCoverOverlayFg,
      photoEditorItemBaseHandleFg: m['photoEditorItemBaseHandleFg'] ?? fb.photoEditorItemBaseHandleFg,
      statisticsChartInactive: m['statisticsChartInactive'] ?? fb.statisticsChartInactive,
      statisticsChartActive: m['statisticsChartActive'] ?? fb.statisticsChartActive,
      statisticsChartLineBlue: m['statisticsChartLineBlue'] ?? fb.statisticsChartLineBlue,
      statisticsChartLineGreen: m['statisticsChartLineGreen'] ?? fb.statisticsChartLineGreen,
      statisticsChartLineRed: m['statisticsChartLineRed'] ?? fb.statisticsChartLineRed,
      statisticsChartLineGolden: m['statisticsChartLineGolden'] ?? fb.statisticsChartLineGolden,
      statisticsChartLineLightblue: m['statisticsChartLineLightblue'] ?? fb.statisticsChartLineLightblue,
      statisticsChartLineLightgreen: m['statisticsChartLineLightgreen'] ?? fb.statisticsChartLineLightgreen,
      statisticsChartLineOrange: m['statisticsChartLineOrange'] ?? fb.statisticsChartLineOrange,
      statisticsChartLineIndigo: m['statisticsChartLineIndigo'] ?? fb.statisticsChartLineIndigo,
      statisticsChartLinePurple: m['statisticsChartLinePurple'] ?? fb.statisticsChartLinePurple,
      statisticsChartLineCyan: m['statisticsChartLineCyan'] ?? fb.statisticsChartLineCyan,
      creditsBg1: m['creditsBg1'] ?? fb.creditsBg1,
      creditsBg2: m['creditsBg2'] ?? fb.creditsBg2,
      creditsBg3: m['creditsBg3'] ?? fb.creditsBg3,
      creditsFg: m['creditsFg'] ?? fb.creditsFg,
      creditsStroke: m['creditsStroke'] ?? fb.creditsStroke,
      currencyFg: m['currencyFg'] ?? fb.currencyFg,
      rankAdminFg: m['rankAdminFg'] ?? fb.rankAdminFg,
      rankOwnerFg: m['rankOwnerFg'] ?? fb.rankOwnerFg,
      rankUserFg: m['rankUserFg'] ?? fb.rankUserFg,
    );

// ── §25.10 Theme Caching ──

class ThemeCacheData {
  final TelegramPalette palette;
  final Uint8List? backgroundImage;
  final bool tileBg;
  final int paletteChecksum;
  final int contentChecksum;
  final CloudThemeMeta? cloudMeta;

  const ThemeCacheData({
    required this.palette,
    this.backgroundImage,
    this.tileBg = false,
    required this.paletteChecksum,
    required this.contentChecksum,
    this.cloudMeta,
  });
}

int? _paletteStructureChecksumCache;

int _paletteStructureChecksum() {
  if (_paletteStructureChecksumCache != null) return _paletteStructureChecksumCache!;
  final buf = StringBuffer();
  for (final entry in paletteToMap(TelegramPalette.dayBlue).entries) {
    buf.write('${entry.key};');
  }
  _paletteStructureChecksumCache = getCrc32(utf8.encode(buf.toString()));
  return _paletteStructureChecksumCache!;
}

ThemeCacheData buildThemeCache(Uint8List themeFileBytes, ThemeFileData parsed) {
  return ThemeCacheData(
    palette: parsed.palette,
    backgroundImage: parsed.backgroundImage,
    tileBg: parsed.backgroundTiled,
    paletteChecksum: _paletteStructureChecksum(),
    contentChecksum: getCrc32(themeFileBytes),
    cloudMeta: parsed.cloudMeta,
  );
}

bool validateThemeCache(ThemeCacheData cache, Uint8List themeFileBytes) {
  if (cache.paletteChecksum != _paletteStructureChecksum()) return false;
  if (getCrc32(themeFileBytes) != cache.contentChecksum) return false;
  return true;
}

void saveThemeCache(String configDir, ThemeCacheData cache) {
  final colorMap = paletteToMap(cache.palette);
  final hexColors = <String, String>{};
  for (final entry in colorMap.entries) {
    hexColors[entry.key] = _colorToHex(entry.value);
  }

  final json = <String, dynamic>{
    'paletteChecksum': cache.paletteChecksum,
    'contentChecksum': cache.contentChecksum,
    'tileBg': cache.tileBg,
    'colors': hexColors,
  };
  if (cache.cloudMeta != null) {
    json['cloudMetaId'] = cache.cloudMeta!.id;
    json['cloudMetaHash'] = cache.cloudMeta!.accessHash;
  }

  try {
    File('$configDir/theme_cache.json').writeAsStringSync(jsonEncode(json));
  } catch (e) {
    debugPrint('THEME: failed to write theme_cache.json: $e');
  }

  if (cache.backgroundImage != null) {
    try {
      File('$configDir/theme_cache_bg.dat').writeAsBytesSync(cache.backgroundImage!);
    } catch (e) {
      debugPrint('THEME: failed to write theme_cache_bg.dat: $e');
    }
  } else {
    try {
      final f = File('$configDir/theme_cache_bg.dat');
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      debugPrint('THEME: failed to delete theme_cache_bg.dat: $e');
    }
  }
}

ThemeCacheData? loadThemeCache(String configDir) {
  try {
    final cacheFile = File('$configDir/theme_cache.json');
    if (!cacheFile.existsSync()) return null;

    final data = jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final paletteChecksum = data['paletteChecksum'] as int? ?? 0;
    final contentChecksum = data['contentChecksum'] as int? ?? 0;
    final tileBg = data['tileBg'] as bool? ?? false;
    final colorsJson = data['colors'] as Map<String, dynamic>?;
    if (colorsJson == null) return null;

    final colorMap = <String, Color>{};
    for (final entry in colorsJson.entries) {
      final c = _parseHexColor(entry.value as String);
      if (c != null) colorMap[entry.key] = c;
    }

    final fallback = TelegramPalette.dayBlue;
    final merged = Map<String, Color>.from(paletteToMap(fallback))..addAll(colorMap);
    final palette = paletteFromMap(merged, fallback);

    Uint8List? bgBytes;
    final bgFile = File('$configDir/theme_cache_bg.dat');
    if (bgFile.existsSync()) {
      // Trust the cache — do NOT re-decode. These bytes were already decoded,
      // size-checked and forced opaque by _decodeOpaqueBackground when the cache
      // was written (applyCustomTheme → buildThemeCache → saveThemeCache), so a
      // full re-decode here would only validate-then-discard. Worse, it would do
      // so SYNCHRONOUSLY on the UI thread: _loadCustomThemeFromCache runs inside
      // _loadWindowPrefs at startup, where a multi-megapixel pure-Dart
      // img.decodeImage blocks for hundreds of ms. AyuGram likewise reads its
      // cached background straight back via QImageReader without re-running the
      // QImageReader::size() / forceOpaque checks (window_theme.cpp:392-400,
      // loadFromCache). The real decode-for-render happens later, off the UI
      // thread, via Flutter's own image codec.
      bgBytes = bgFile.readAsBytesSync();
    }

    CloudThemeMeta? cloudMeta;
    final cmId = data['cloudMetaId'] as int?;
    final cmHash = data['cloudMetaHash'] as int?;
    if (cmId != null && cmHash != null) {
      cloudMeta = CloudThemeMeta(id: cmId, accessHash: cmHash);
    }

    return ThemeCacheData(
      palette: palette,
      backgroundImage: bgBytes,
      tileBg: tileBg,
      paletteChecksum: paletteChecksum,
      contentChecksum: contentChecksum,
      cloudMeta: cloudMeta,
    );
  } catch (e) {
    debugPrint('THEME: failed to load theme cache: $e');
    return null;
  }
}

void clearThemeCache(String configDir) {
  try {
    final f = File('$configDir/theme_cache.json');
    if (f.existsSync()) f.deleteSync();
  } catch (e) {
    debugPrint('THEME: failed to clear theme_cache.json: $e');
  }
  try {
    final f = File('$configDir/theme_cache_bg.dat');
    if (f.existsSync()) f.deleteSync();
  } catch (e) {
    debugPrint('THEME: failed to clear theme_cache_bg.dat: $e');
  }
}
