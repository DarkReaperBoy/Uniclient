import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';

class RegexFilter {
  final String id;
  final String text;
  final bool enabled;
  final bool reversed;
  final bool caseInsensitive;
  final String? dialogId;

  const RegexFilter({
    required this.id,
    required this.text,
    this.enabled = true,
    this.reversed = false,
    this.caseInsensitive = false,
    this.dialogId,
  });

  bool get isShared => dialogId == null || dialogId!.isEmpty;

  RegexFilter copyWith({
    String? id,
    String? text,
    bool? enabled,
    bool? reversed,
    bool? caseInsensitive,
    String? dialogId,
  }) => RegexFilter(
    id: id ?? this.id,
    text: text ?? this.text,
    enabled: enabled ?? this.enabled,
    reversed: reversed ?? this.reversed,
    caseInsensitive: caseInsensitive ?? this.caseInsensitive,
    dialogId: dialogId ?? this.dialogId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'enabled': enabled,
    'reversed': reversed,
    'caseInsensitive': caseInsensitive,
    // AyuGram ALWAYS writes the dialogId key, using an explicit JSON null for shared
    // filters (`filterJson["dialogId"] = QJsonValue()`, filters_utils.cpp:475-479). A
    // *missing* key imports as QJsonValue::Undefined, whose isNull() is false, so
    // AyuGram's `if (!dialogIdValue.isNull())` import branch runs and toLongLong()
    // yields 0 — the shared filter is silently filed under byDialogId[0] and never
    // matches. Emit null for shared filters so they round-trip into real AyuGram.
    // (Dart's fromJson reads `j['dialogId']?.toString()`, so null/absent both load as a
    // null dialogId — local persistence is unaffected.) ← filters_utils.cpp:475-479,726-731
    'dialogId': isShared ? null : dialogId,
  };

  factory RegexFilter.fromJson(Map<String, dynamic> j) => RegexFilter(
    id: (j['id']?.toString()) ?? '',
    text: (j['text']?.toString()) ?? '',
    enabled: j['enabled'] as bool? ?? true,
    reversed: j['reversed'] as bool? ?? false,
    caseInsensitive: j['caseInsensitive'] as bool? ?? false,
    dialogId: j['dialogId']?.toString(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegexFilter && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class RegexFilterExclusion {
  final String dialogId;
  final String filterId;

  const RegexFilterExclusion({required this.dialogId, required this.filterId});

  Map<String, dynamic> toJson() => {'dialogId': dialogId, 'filterId': filterId};

  factory RegexFilterExclusion.fromJson(Map<String, dynamic> j) =>
      RegexFilterExclusion(
        dialogId: (j['dialogId']?.toString()) ?? '',
        filterId: (j['filterId']?.toString()) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegexFilterExclusion &&
          dialogId == other.dialogId &&
          filterId == other.filterId;

  @override
  int get hashCode => Object.hash(dialogId, filterId);
}

class ImportChanges {
  final List<RegexFilter> filtersToAdd;
  final List<RegexFilter> filtersToUpdate;
  final List<RegexFilterExclusion> exclusionsToAdd;
  final List<String> filterIdsToRemove;
  final List<RegexFilterExclusion> exclusionsToRemove;
  final List<String> peersToBeResolved;

  const ImportChanges({
    required this.filtersToAdd,
    required this.filtersToUpdate,
    required this.exclusionsToAdd,
    required this.filterIdsToRemove,
    required this.exclusionsToRemove,
    this.peersToBeResolved = const [],
  });

  bool get hasChanges =>
      filtersToAdd.isNotEmpty ||
      filtersToUpdate.isNotEmpty ||
      exclusionsToAdd.isNotEmpty ||
      filterIdsToRemove.isNotEmpty ||
      exclusionsToRemove.isNotEmpty;

  int get addedCount => filtersToAdd.length;
  int get updatedCount => filtersToUpdate.length;
  int get removedFiltersCount => filterIdsToRemove.length;
  int get removedExclusionsCount => exclusionsToRemove.length;
  int get newExclusionsCount => exclusionsToAdd.length;
}

class _CompiledPattern {
  final RegexFilter filter;
  final RegExp? pattern;

  _CompiledPattern(this.filter)
      : pattern = compileFilterPattern(filter.text, filter.caseInsensitive);

  bool matches(String blob) {
    if (blob.isEmpty) return false;
    if (pattern == null) return false;
    final found = pattern!.hasMatch(blob);
    return filter.reversed ? !found : found;
  }
}

final _filterIdRng = Random.secure();
final _hex32 = RegExp(r'^[0-9a-fA-F]{32}$');

/// Generates a filter id in AyuGram's wire format: a 16-byte UUID v4 rendered as a
/// dash-formatted 32-hex string (8-4-4-4-12). AyuGram stores filter ids as 16 raw
/// bytes and serialises them this way (`filters_utils.cpp:445-451,484-492`); its
/// `ParseFilterId` (`filters_utils.cpp:202-213`) strips the dashes and skips any id
/// that isn't exactly 32 hex chars / 16 bytes, so every id we create must match this
/// shape to survive a round-trip through real AyuGram.
String generateFilterId() {
  final bytes = List<int>.generate(16, (_) => _filterIdRng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Canonicalises a filter id into AyuGram's exported wire format. AyuGram hex-encodes
/// the 16 stored bytes and inserts dashes at 8/13/18/23 ("make it look like java's
/// UUID", `filters_utils.cpp:445-451`). We mirror that: any 32-hex id (with or without
/// dashes) becomes a dash-formatted UUID; ids that aren't 16-byte hex are emitted
/// unchanged (real AyuGram's `ParseFilterId` skips them, exactly as it would any
/// malformed id).
String _formatFilterIdForWire(String id) {
  final stripped = id.replaceAll('-', '');
  if (!_hex32.hasMatch(stripped)) return id;
  return '${stripped.substring(0, 8)}-${stripped.substring(8, 12)}-'
      '${stripped.substring(12, 16)}-${stripped.substring(16, 20)}-'
      '${stripped.substring(20)}';
}

final _icuUnicodeEscape = RegExp(r'\\[pPu]\{');
final _braceQuantifier = RegExp(r'\{\d+(?:,\d*)?\}');

// POSIX/ICU character-class names mapped to pure-Dart class bodies. ASCII
// approximations: ICU's classes are Unicode-aware, but these let the pattern compile
// and match instead of being silently dropped (Dart's RegExp has no POSIX classes).
const _posixClassBodies = <String, String>{
  'alpha': 'a-zA-Z',
  'digit': '0-9',
  'alnum': 'a-zA-Z0-9',
  'upper': 'A-Z',
  'lower': 'a-z',
  'space': r'\s',
  'blank': r' \t',
  'word': r'\w',
  'xdigit': '0-9a-fA-F',
  'cntrl': r'\x00-\x1f\x7f',
  'graph': r'\x21-\x7e',
  'print': r'\x20-\x7e',
  'punct': r'''!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~''',
};

/// Compiles a filter pattern the way the running engine does, bridging AyuGram's ICU
/// engine (`UREGEX_MULTILINE` always, plus `UREGEX_CASE_INSENSITIVE` —
/// `filters_cache_controller.cpp:55-59`) and pure Dart's RegExp (no ICU). It translates
/// the ICU-only constructs that appear in shared/imported filters into the closest Dart
/// equivalents (POSIX classes, possessive quantifiers — see `_translateIcuPattern`) and
/// opts into Unicode mode so `\p{...}`/`\u{...}` property escapes resolve like ICU.
/// Attempts run most-faithful → most-permissive so a filter is dropped only when nothing
/// compiles; returns null in that case (the engine then treats the filter as
/// non-matching, matching AyuGram which skips a pattern whose compile fails —
/// `filters_cache_controller.cpp:61-63`).
RegExp? compileFilterPattern(String text, bool caseInsensitive) {
  if (text.isEmpty) return null;
  final translated = _translateIcuPattern(text);
  final candidates = <String>[translated, if (translated != text) text];
  // ICU recognises \p{...}/\u{...} unconditionally; Dart only does in Unicode mode.
  final modes = _icuUnicodeEscape.hasMatch(translated)
      ? const <bool>[true, false]
      : const <bool>[false];
  for (final candidate in candidates) {
    for (final unicode in modes) {
      try {
        return RegExp(candidate,
            multiLine: true, unicode: unicode, caseSensitive: !caseInsensitive);
      } catch (_) {
        // fall through to the next, more permissive, attempt
      }
    }
  }
  debugPrint('FILTER FAILED: $text');
  return null;
}

/// Rewrites the ICU-only regex syntax AyuGram filters may contain into pure-Dart
/// equivalents, in a single escape-aware pass (so literal `\+`, `\[`, … are never
/// mangled). Dart has no ICU, so:
///   • POSIX classes `[[:alpha:]]` (meaningful only inside a `[...]` set) → ASCII ranges.
///   • possessive quantifiers `a++`/`a*+`/`a?+`/`a{n,m}+` → greedy (Dart has no atomic
///     groups; greedy matches the same strings for filtering purposes).
/// `\p{...}`/`\u{...}` escapes are left intact and handled via Unicode mode in
/// `compileFilterPattern`. Returns the text unchanged when no ICU-only construct is found.
String _translateIcuPattern(String text) {
  final out = StringBuffer();
  final n = text.length;
  var i = 0;
  var inClass = false;
  while (i < n) {
    final ch = text[i];
    if (ch == '\\') {
      out.write(ch);
      if (i + 1 < n) out.write(text[i + 1]);
      i += 2;
      continue;
    }
    if (inClass) {
      if (ch == ']') {
        inClass = false;
        out.write(ch);
        i++;
        continue;
      }
      if (ch == '[' && i + 1 < n && text[i + 1] == ':') {
        final close = text.indexOf(':]', i + 2);
        if (close >= 0) {
          var name = text.substring(i + 2, close);
          if (name.startsWith('^')) name = name.substring(1);
          final body = _posixClassBodies[name];
          if (body != null) {
            out.write(body);
            i = close + 2;
            continue;
          }
        }
      }
      out.write(ch);
      i++;
      continue;
    }
    if (ch == '[') {
      inClass = true;
      out.write(ch);
      i++;
      // a leading ^ negates the set; a leading ] (incl. right after ^) is a literal member
      if (i < n && text[i] == '^') {
        out.write('^');
        i++;
      }
      if (i < n && text[i] == ']') {
        out.write(']');
        i++;
      }
      continue;
    }
    if (ch == '*' || ch == '+' || ch == '?') {
      out.write(ch);
      i++;
      if (i < n && text[i] == '+') i++; // possessive marker → greedy
      continue;
    }
    if (ch == '{') {
      final m = _braceQuantifier.matchAsPrefix(text, i);
      if (m != null) {
        out.write(m.group(0));
        i = m.end;
        if (i < n && text[i] == '+') i++; // possessive {n,m}+ → greedy
        continue;
      }
    }
    out.write(ch);
    i++;
  }
  return out.toString();
}

const _mediaTypeNames = <int, int>{
  1: 1,   // image → TYPE_PHOTO
  2: 3,   // video → TYPE_VIDEO
  3: 14,  // audio → TYPE_MUSIC
  4: 2,   // voice → TYPE_VOICE
  5: 5,   // videonote → TYPE_ROUND_VIDEO
  6: 13,  // sticker → TYPE_STICKER
  7: 8,   // gif → TYPE_GIF
  8: 9,   // file → TYPE_FILE
  9: 17,  // poll → TYPE_POLL
  10: 4,  // location → TYPE_GEO
  11: 12, // contact → TYPE_CONTACT
  // 12 = MediaInvoice in Go engine — no filter bucket for invoices
  13: 19, // emoji-only text → TYPE_EMOJIS
  14: 23, // story → TYPE_STORY
  15: 24, // story mention → TYPE_STORY_MENTION
  16: 26, // giveaway → TYPE_GIVEAWAY
  17: 28, // giveaway results → TYPE_GIVEAWAY_RESULTS
  18: 29, // paid media → TYPE_PAID_MEDIA
  19: 30, // gift stars → TYPE_GIFT_STARS
};

int _resolveFilterType(CachedMessage msg) {
  if (msg.mediaType == 6) {
    if (msg.mediaMimeType == 'application/x-tgsticker' ||
        msg.mediaMimeType == 'video/webm') {
      return 15; // TYPE_ANIMATED_STICKER
    }
    return 13; // TYPE_STICKER
  }
  return _mediaTypeNames[msg.mediaType] ?? 0;
}

String _extractSingleText(CachedMessage msg, {Set<String>? extractedUrls}) {
  final buf = StringBuffer();
  buf.write(msg.contentText);

  if (msg.contentRich.isNotEmpty) {
    try {
      final entities = jsonDecode(msg.contentRich) as List;
      for (final e in entities) {
        final m = e as Map<String, dynamic>;
        final type = m['type'] as String? ?? '';
        if (type == 'url' || type == 'text_url') {
          final url = m['url'] as String? ?? '';
          if (url.isNotEmpty) {
            extractedUrls?.add(url);
            buf.write('\n');
            buf.write(url);
          } else {
            final offset = m['offset'] as int? ?? 0;
            final length = m['length'] as int? ?? 0;
            if (offset >= 0 && offset + length <= msg.contentText.length) {
              final extracted = msg.contentText.substring(offset, offset + length);
              extractedUrls?.add(extracted);
              buf.write('\n');
              buf.write(extracted);
            }
          }
        }
      }
    } catch (_) {
      // contentRich that isn't a JSON entities array carries no URL entities to
      // extract; visible-text matching (above) still applies. Silent like every
      // other contentRich consumer (chat_state, message_bubble, notifications).
    }
  }

  return buf.toString();
}

int _serviceMessageType(CachedMessage msg) {
  final tag = _extractServiceAction(msg.contentRaw);
  if (tag.isNotEmpty) {
    switch (tag) {
      case 'phone_call': return 16;
      case 'set_photo': return 11;
      case 'suggest_photo': return 21;
      case 'wallpaper': return 22;
      case 'gift_premium':
        final extra = _extractExtra(msg.contentRaw);
        if (extra?['channel'] == true) return 25;
        return 18;
      case 'gift_premium_channel': return 25;
      case 'gift_stars': return 30;
      case 'giveaway_results': return 28;
      case 'boost': return 10;
      // No 'group_call' case: AyuGram's service branch returns 16 only for a real 1-1
      // media->call(); a group-call action has no MediaCall, so it falls through to
      // TYPE_DATE (10). ← filters_utils.cpp:604-635
    }
  }

  // media->photo() && !isUserpicSuggestion() → TYPE_ACTION_PHOTO (suggest_photo is
  // handled above as 21). A service message with a video has no service path in
  // AyuGram, so it — like everything else — falls through to TYPE_DATE (10).
  // ← filters_utils.cpp:604-635
  if (msg.mediaType == 1) return 11;

  return 10;
}

String _extractServiceAction(String raw) {
  if (raw.isEmpty) return '';
  final extra = _extractExtra(raw);
  return extra?['service_action'] as String? ?? '';
}

Map<String, dynamic>? _extractExtra(String raw) {
  if (raw.isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    if (m is Map<String, dynamic>) {
      return m['extra'] as Map<String, dynamic>?;
    }
  } catch (_) {}
  return null;
}

String extractMatchBlob(CachedMessage msg, {List<CachedMessage>? groupMessages}) {
  final buf = StringBuffer();
  final entityUrls = <String>{};

  if (groupMessages != null && groupMessages.length > 1) {
    for (final gMsg in groupMessages) {
      final text = _extractSingleText(gMsg, extractedUrls: entityUrls).trim();
      if (text.isNotEmpty) {
        buf.write(text);
        buf.write('\n');
      }
    }
  } else {
    // AyuGram trims the single-message text too (`extractSingle(item).trimmed()`,
    // filters_utils.cpp:668); patterns compile multiline, so leading/trailing
    // whitespace on the first/last line would otherwise flip ^…/…$-anchored matches.
    buf.write(_extractSingleText(msg, extractedUrls: entityUrls).trim());
  }

  for (final row in msg.inlineKeyboard) {
    for (final btn in row) {
      buf.write('<button>');
      buf.write(btn.text);
      buf.write(' ');
      buf.write(btn.data);
      buf.write('</button>\n');
    }
  }

  if (msg.isService) {
    final serviceType = _serviceMessageType(msg);
    buf.write('\n<type>$serviceType</type>');
  } else {
    final typeId = _resolveFilterType(msg);
    buf.write('\n<type>$typeId</type>');
  }

  return buf.toString();
}

class AyuFilterEngine extends ChangeNotifier {
  static const _maxCacheSize = 10000;

  List<_CompiledPattern> _sharedPatterns = [];
  final Map<String, List<_CompiledPattern>> _dialogPatterns = {};
  final Map<String, Set<String>> _exclusionsByDialog = {};
  final Map<String, bool> _messageCache = {};
  final Map<String, int> _chatFilteredCount = {};
  final Map<String, bool> _filteredMessagesShown = {};
  final Set<String> _hiddenBlockedChats = {};
  final Map<String, Set<String>> _groupIndex = {};

  List<RegexFilter> _filters = [];
  List<RegexFilterExclusion> _exclusions = [];

  List<RegexFilter> get filters => _filters;
  List<RegexFilterExclusion> get exclusions => _exclusions;

  List<RegexFilter> get sharedFilters =>
      _filters.where((f) => f.isShared).toList();

  List<RegexFilter> filtersForDialog(String dialogId) =>
      _filters.where((f) => f.dialogId == dialogId).toList();

  List<RegexFilter> get enabledSharedFilters =>
      _filters.where((f) => f.isShared && f.enabled).toList();

  Set<String> exclusionsForDialog(String dialogId) =>
      _exclusionsByDialog[dialogId] ?? const {};

  bool hasFilters() => _filters.isNotEmpty;
  // AyuGram's PerDialogFiltersListController::prepare() lists a dialog if it has
  // per-dialog filters OR exclusions (per_dialog_filter.cpp:86-102), so a dialog
  // with only exclusions still surfaces a Per-Dialog section.
  bool hasPerDialogFilters() =>
      _filters.any((f) => !f.isShared) || _exclusions.isNotEmpty;

  Set<String> dialogIdsWithFilters() {
    final ids = <String>{};
    for (final f in _filters) {
      if (f.dialogId != null && f.dialogId!.isNotEmpty) {
        ids.add(f.dialogId!);
      }
    }
    for (final e in _exclusions) {
      if (e.dialogId.isNotEmpty) ids.add(e.dialogId);
    }
    return ids;
  }

  void loadFromJson(Map<String, dynamic> data) {
    final rawFilters = data['regexFilters'] as List<dynamic>?;
    if (rawFilters != null) {
      _filters = rawFilters
          .map((e) => RegexFilter.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final rawExcl = data['regexExclusions'] as List<dynamic>?;
    if (rawExcl != null) {
      _exclusions = rawExcl
          .map((e) => RegexFilterExclusion.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    rebuildCache();
  }

  Map<String, dynamic> toJson() => {
    'regexFilters': _filters.map((f) => f.toJson()).toList(),
    'regexExclusions': _exclusions.map((e) => e.toJson()).toList(),
  };

  static const _backupVersion = 2;

  Map<String, dynamic> exportFilters({Map<String, String> peers = const {}}) => {
    'version': _backupVersion,
    // AyuGram exports each id as a dash-formatted 32-hex UUID and skips anything its
    // ParseFilterId can't decode to 16 bytes, so canonicalise ids on the way out to
    // guarantee filters (and the exclusions that reference them) round-trip into real
    // AyuGram. ← filters_utils.cpp:202-213,445-451,484-492,734-737
    'filters': _filters.map((f) {
      final json = f.toJson();
      json['id'] = _formatFilterIdForWire(f.id);
      return json;
    }).toList(),
    'exclusions': _exclusions.map((e) {
      final json = e.toJson();
      json['filterId'] = _formatFilterIdForWire(e.filterId);
      return json;
    }).toList(),
    'removeFiltersById': <String>[],
    'removeExclusions': <Map<String, dynamic>>[],
    'peers': peers,
  };

  ImportChanges previewImport(Map<String, dynamic> data) {
    final version = data['version'] as int? ?? 0;
    if (version > _backupVersion) {
      throw Exception('Unsupported backup version $version (max $_backupVersion)');
    }
    final filters = (data['filters'] as List<dynamic>?)
        ?.map((e) => RegexFilter.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    final exclusions = (data['exclusions'] as List<dynamic>?)
        ?.map((e) => RegexFilterExclusion.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    final removeIds = (data['removeFiltersById'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ?? [];
    final removeExcl = (data['removeExclusions'] as List<dynamic>?)
        ?.map((e) => RegexFilterExclusion.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];

    final peersJson = data['peers'] as Map<String, dynamic>? ?? {};
    final peersToResolve = <String>[];
    for (final entry in peersJson.entries) {
      final hint = entry.value?.toString() ?? '';
      if (hint.isNotEmpty) {
        peersToResolve.add(hint);
      }
    }

    final toAdd = <RegexFilter>[];
    final toUpdate = <RegexFilter>[];
    for (final f in filters) {
      if (_filters.any((ef) => ef.id == f.id)) {
        toUpdate.add(f);
      } else {
        toAdd.add(f);
      }
    }
    final newExcl = exclusions.where((e) => !_exclusions.contains(e)).toList();

    return ImportChanges(
      filtersToAdd: toAdd,
      filtersToUpdate: toUpdate,
      exclusionsToAdd: newExcl,
      filterIdsToRemove: removeIds,
      exclusionsToRemove: removeExcl,
      peersToBeResolved: peersToResolve,
    );
  }

  void applyImport(ImportChanges changes) {
    for (final f in changes.filtersToAdd) {
      addFilter(f);
    }
    for (final f in changes.filtersToUpdate) {
      updateFilter(f);
    }
    for (final e in changes.exclusionsToAdd) {
      addExclusion(e);
    }
    for (final id in changes.filterIdsToRemove) {
      deleteFilter(id);
    }
    for (final e in changes.exclusionsToRemove) {
      deleteExclusion(e.dialogId, e.filterId);
    }
  }

  Future<({ImportChanges? changes, String? error})> importFromLink(String url) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) {
        return (changes: null, error: 'Failed to import filters');
      }
      final changes = previewImport(parsed);
      if (!changes.hasChanges) return (changes: null, error: 'No changes to import');
      return (changes: changes, error: null);
    } on FormatException {
      return (changes: null, error: 'Failed to import filters');
    } catch (e) {
      return (changes: null, error: 'Failed to fetch filters');
    } finally {
      client.close();
    }
  }

  Future<({String? url, String? error})> publishFilters({Map<String, String> peers = const {}}) async {
    final data = exportFilters(peers: peers);
    final jsonText = const JsonEncoder.withIndent('  ').convert(data);
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse('https://dpaste.com/api/v2/'));
      // dpaste returns the snippet URL in the Location header (HTTP 201/302).
      // Dart's HttpClient follows redirects by default, which consumes the 302 and
      // drops the Location header — disable it so we can read the URL, matching
      // AyuGram's QNetworkReply (no auto-redirect) in FilterUtils::publishFilters
      // (filters_utils.cpp:344-391, success = NoError && location.isValid()).
      request.followRedirects = false;
      final boundary = '----DartFormBoundary${DateTime.now().millisecondsSinceEpoch}';
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      final body = StringBuffer();
      void addField(String name, String value) {
        body.write('--$boundary\r\n');
        body.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
        body.write('$value\r\n');
      }
      addField('content', jsonText);
      addField('syntax', 'json');
      addField('title', 'AyuGram Filters');
      body.write('--$boundary--\r\n');
      request.add(utf8.encode(body.toString()));
      final response = await request.close();
      await response.drain<void>();
      String pasteUrl = '';
      final location = response.headers['location'];
      if (location != null && location.isNotEmpty) {
        pasteUrl = location.first;
      }
      if (!pasteUrl.startsWith('http')) return (url: null, error: 'Failed to publish filters');
      if (!pasteUrl.endsWith('.txt')) pasteUrl = '$pasteUrl.txt';
      await Clipboard.setData(ClipboardData(text: pasteUrl));
      return (url: pasteUrl, error: null);
    } catch (_) {
      return (url: null, error: 'Failed to publish filters');
    } finally {
      client.close();
    }
  }

  void addFilter(RegexFilter filter) {
    _filters = [..._filters, filter];
    rebuildCache();
    notifyListeners();
  }

  void updateFilter(RegexFilter filter) {
    _filters = [
      for (final f in _filters)
        if (f.id == filter.id) filter else f,
    ];
    rebuildCache();
    notifyListeners();
  }

  void deleteFilter(String filterId) {
    _filters = _filters.where((f) => f.id != filterId).toList();
    _exclusions = _exclusions.where((e) => e.filterId != filterId).toList();
    rebuildCache();
    notifyListeners();
  }

  void addExclusion(RegexFilterExclusion exclusion) {
    if (_exclusions.contains(exclusion)) return;
    _exclusions = [..._exclusions, exclusion];
    rebuildCache();
    notifyListeners();
  }

  void deleteExclusion(String dialogId, String filterId) {
    _exclusions = _exclusions
        .where((e) => !(e.dialogId == dialogId && e.filterId == filterId))
        .toList();
    rebuildCache();
    notifyListeners();
  }

  void clearAll() {
    _filters = [];
    _exclusions = [];
    rebuildCache();
    notifyListeners();
  }

  void rebuildCache() {
    _sharedPatterns = [];
    _dialogPatterns.clear();
    _exclusionsByDialog.clear();
    _messageCache.clear();
    _chatFilteredCount.clear();
    _hiddenBlockedChats.clear();
    _groupIndex.clear();

    for (final f in _filters) {
      if (!f.enabled) continue;
      final cp = _CompiledPattern(f);
      if (f.isShared) {
        _sharedPatterns.add(cp);
      } else {
        (_dialogPatterns[f.dialogId!] ??= []).add(cp);
      }
    }

    for (final e in _exclusions) {
      (_exclusionsByDialog[e.dialogId] ??= {}).add(e.filterId);
    }
  }

  bool? filteredMessagesShown(String chatId) {
    if (!_filteredMessagesShown.containsKey(chatId) &&
        !_hasFilteredMessages(chatId)) {
      return null;
    }
    return _filteredMessagesShown[chatId] ?? false;
  }

  bool _hasFilteredMessages(String chatId) {
    if (_hiddenBlockedChats.contains(chatId)) return true;
    return (_chatFilteredCount[chatId] ?? 0) > 0;
  }

  void toggleFilteredMessagesShown(String chatId) {
    _filteredMessagesShown[chatId] = !(_filteredMessagesShown[chatId] ?? false);
    notifyListeners();
  }

  void invalidateMessage(String chatId, String msgId, {String? groupedId, List<String>? groupMemberIds}) {
    _removeCacheEntry('$chatId:$msgId');
    if (groupedId != null && groupedId.isNotEmpty) {
      final groupKey = '$chatId:$groupedId';
      final members = _groupIndex[groupKey];
      if (members != null) {
        for (final memberId in members) {
          if (memberId != msgId) {
            _removeCacheEntry('$chatId:$memberId');
          }
        }
      }
    }
    if (groupMemberIds != null) {
      for (final memberId in groupMemberIds) {
        if (memberId != msgId) {
          _removeCacheEntry('$chatId:$memberId');
        }
      }
    }
  }

  bool isFiltered(CachedMessage msg, AppState appState, {ChatType? chatType, List<CachedMessage>? groupMessages}) {
    if (!appState.filtersEnabled) return false;
    if (msg.isOutgoing) return false;

    final dialogId = msg.chatId;
    if (_filteredMessagesShown[dialogId] == true) return false;

    // AyuGram evaluates filterBlocked() on EVERY call — before isEnabled() and before
    // the regex cache lookup — and never stores the block/shadowban verdict in the
    // per-message cache (it only marks the dialog via putHiddenBlockedMessage). That is
    // what lets blocking/unblocking (or a shadowban change) re-hide/re-show already
    // rendered messages on the next render, instead of leaving them stale until the
    // next rebuildCache(). ← filters_controller.cpp:161-164,
    // filters_cache_controller.cpp:177-180
    if (_filterBlocked(msg, appState)) {
      _hiddenBlockedChats.add(dialogId);
      return true;
    }

    if (!_isEnabledForChat(chatType, appState)) return false;

    // The per-message cache holds only regex verdicts (block verdicts are recomputed
    // every call above), mirroring AyuGram's filteredMessages map, which is checked
    // after isEnabled(). ← filters_controller.cpp:166-171
    final cacheKey = '${msg.chatId}:${msg.msgId}';
    final cached = _messageCache[cacheKey];
    if (cached != null) return cached;

    if (groupMessages != null && groupMessages.length > 1 && msg.groupedId.isNotEmpty) {
      _groupIndex['$dialogId:${msg.groupedId}'] =
          groupMessages.map((m) => m.msgId).toSet();
    }

    final blob = extractMatchBlob(msg, groupMessages: groupMessages);

    final dialogPats = _dialogPatterns[dialogId];
    if (dialogPats != null) {
      for (final p in dialogPats) {
        if (p.matches(blob)) {
          _cacheResult(cacheKey, true);
          return true;
        }
      }
    }

    final excl = _exclusionsByDialog[dialogId];
    for (final p in _sharedPatterns) {
      if (excl != null && excl.contains(p.filter.id)) continue;
      if (p.matches(blob)) {
        _cacheResult(cacheKey, true);
        return true;
      }
    }

    _cacheResult(cacheKey, false);
    return false;
  }

  // AyuGram's filterBlocked()/isBlocked() (filters_controller.cpp:30-37,95-136): the
  // ENTIRE block check — the direct sender AND the forwarded-original-sender branch
  // (both live inside isBlocked) — is gated behind `from() != peer`. So in any chat
  // where the sender IS the peer (1-1 DMs, channel posts, anonymous-admin group posts)
  // nothing is hidden via block/shadowban — not even a message forwarded from a
  // blocked/shadowbanned user. The Go engine leaves SenderID empty when a message has
  // no explicit from_id (exactly the DM/channel-post case, where from()==peer), so
  // "sender is the peer" is `senderId == null || senderId == chatId`. A shadowbanned
  // sender always hides the message; a *blocked* sender hides only when hideFromBlocked
  // is on. filtersEnabled is already guaranteed true by the caller. Not cached.
  bool _filterBlocked(CachedMessage msg, AppState appState) {
    final senderId = _parseSenderId(msg.senderId);
    if (senderId == null || msg.senderId == msg.chatId) return false;
    if (appState.isShadowBanned(senderId)) return true;
    if (appState.hideFromBlocked && appState.isBlocked(senderId)) return true;
    final fwdId = _parseForwardSenderId(msg.forwardFrom);
    if (fwdId != null) {
      if (appState.isShadowBanned(fwdId)) return true;
      if (appState.hideFromBlocked && appState.isBlocked(fwdId)) return true;
    }
    return false;
  }

  void _cacheResult(String key, bool value) {
    if (_messageCache.length >= _maxCacheSize) {
      final evictCount = _maxCacheSize ~/ 10;
      final keys = _messageCache.keys.take(evictCount).toList();
      for (final k in keys) {
        _removeCacheEntry(k);
      }
    }
    _messageCache[key] = value;
    if (value) {
      final chatId = key.substring(0, key.indexOf(':'));
      _chatFilteredCount[chatId] = (_chatFilteredCount[chatId] ?? 0) + 1;
    }
  }

  void _removeCacheEntry(String key) {
    final old = _messageCache.remove(key);
    if (old == true) {
      final chatId = key.substring(0, key.indexOf(':'));
      final count = (_chatFilteredCount[chatId] ?? 1) - 1;
      if (count <= 0) {
        _chatFilteredCount.remove(chatId);
      } else {
        _chatFilteredCount[chatId] = count;
      }
    }
  }

  bool _isEnabledForChat(ChatType? chatType, AppState appState) {
    if (appState.filtersEnabledInChats) return true;
    return chatType == ChatType.channel;
  }

  int? _parseSenderId(String senderId) {
    if (senderId.isEmpty) return null;
    return int.tryParse(senderId);
  }

  static final _forwardIdPattern = RegExp(r'(?:User|Channel|Chat) (\d+)$');

  int? _parseForwardSenderId(String forwardFrom) {
    if (forwardFrom.isEmpty) return null;
    final id = int.tryParse(forwardFrom);
    if (id != null) return id;
    final match = _forwardIdPattern.firstMatch(forwardFrom);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }
}
