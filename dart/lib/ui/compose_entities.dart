import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';

enum FormatType { bold, italic, underline, strike, code, pre, spoiler, blockquote, link, customEmoji, date }

/// Bit flags describing how a [FormatType.date] entity renders, mirroring
/// Telegram's `messageEntityFormattedDate#904ac7c7` flags (AyuGram
/// `api/api_text_entities.cpp:391`, `core/ui_integration.cpp:196`).
class DateFlag {
  static const int relative = 1 << 0;
  static const int shortTime = 1 << 1;
  static const int longTime = 1 << 2;
  static const int shortDate = 1 << 3;
  static const int longDate = 1 << 4;
  static const int dayOfWeek = 1 << 5;
}

class ComposeEntity {
  int offset;
  int length;
  final FormatType type;
  final String? url;
  final String? language;
  final int? documentId;
  final String? altText;
  final int? timestamp;
  final int dateFlags;

  ComposeEntity({required this.offset, required this.length, required this.type, this.url, this.language, this.documentId, this.altText, this.timestamp, this.dateFlags = 0});

  Map<String, dynamic> toJson() {
    final typeStr = switch (type) {
      FormatType.bold => 'bold',
      FormatType.italic => 'italic',
      FormatType.underline => 'underline',
      FormatType.strike => 'strike',
      FormatType.code => 'code',
      FormatType.pre => 'pre',
      FormatType.spoiler => 'spoiler',
      FormatType.blockquote => 'blockquote',
      FormatType.link => 'text_url',
      FormatType.customEmoji => 'custom_emoji',
      FormatType.date => 'formatted_date',
    };
    final m = <String, dynamic>{'type': typeStr, 'offset': offset, 'length': length};
    if (url != null && url!.isNotEmpty) m['url'] = url!;
    if (language != null && language!.isNotEmpty) m['language'] = language!;
    if (documentId != null && documentId != 0) m['document_id'] = documentId!;
    if (altText != null && altText!.isNotEmpty) m['alt_text'] = altText!;
    if (type == FormatType.date) {
      // Serialize as a real `messageEntityFormattedDate` payload the Go core
      // can forward to the wire (date in unix seconds + render flags), instead
      // of an inert `custom_date`+`timestamp` the send path silently dropped.
      m['date'] = timestamp ?? 0;
      if ((dateFlags & DateFlag.relative) != 0) m['relative'] = true;
      if ((dateFlags & DateFlag.shortTime) != 0) m['short_time'] = true;
      if ((dateFlags & DateFlag.longTime) != 0) m['long_time'] = true;
      if ((dateFlags & DateFlag.shortDate) != 0) m['short_date'] = true;
      if ((dateFlags & DateFlag.longDate) != 0) m['long_date'] = true;
      if ((dateFlags & DateFlag.dayOfWeek) != 0) m['day_of_week'] = true;
    }
    return m;
  }
}

typedef CustomEmojiWidgetBuilder = InlineSpan Function(int documentId, String accountId, String altText, int segStart);

class RichTextEditingController extends TextEditingController {
  final List<ComposeEntity> entities = [];
  String accountId = '';
  CustomEmojiWidgetBuilder? customEmojiBuilder;

  static const String _emojiPlaceholder = '￼';

  String _prevText = '';

  RichTextEditingController() {
    addListener(_onTextChanged);
  }

  @override
  void dispose() {
    removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final newText = text;
    if (newText == _prevText) return;

    final oldLen = _prevText.length;
    final newLen = newText.length;

    if (newLen == 0) {
      entities.clear();
      _prevText = newText;
      return;
    }

    final minLen = oldLen < newLen ? oldLen : newLen;
    var commonPrefix = 0;
    while (commonPrefix < minLen &&
        _prevText.codeUnitAt(commonPrefix) == newText.codeUnitAt(commonPrefix)) {
      commonPrefix++;
    }
    var commonSuffix = 0;
    final maxSuffix = minLen - commonPrefix;
    while (commonSuffix < maxSuffix &&
        _prevText.codeUnitAt(oldLen - 1 - commonSuffix) ==
            newText.codeUnitAt(newLen - 1 - commonSuffix)) {
      commonSuffix++;
    }

    final changePos = commonPrefix;
    final removedLen = oldLen - commonPrefix - commonSuffix;
    final addedLen = newLen - commonPrefix - commonSuffix;

    for (var i = entities.length - 1; i >= 0; i--) {
      final e = entities[i];
      final eEnd = e.offset + e.length;
      final delEnd = changePos + removedLen;

      if (removedLen > 0) {
        if (delEnd <= e.offset) {
          e.offset -= removedLen;
        } else if (changePos >= eEnd) {
          // entity fully before deletion
        } else if (changePos <= e.offset && delEnd >= eEnd) {
          e.offset = changePos;
          e.length = 0;
        } else if (changePos <= e.offset) {
          final removed = delEnd - e.offset;
          e.offset = changePos;
          e.length -= removed;
        } else if (delEnd >= eEnd) {
          e.length = changePos - e.offset;
        } else {
          e.length -= removedLen;
        }
      }

      if (addedLen > 0) {
        if (e.length == 0 && e.offset == changePos) {
          e.length = addedLen;
        } else if (changePos <= e.offset) {
          e.offset += addedLen;
        } else if (changePos < e.offset + e.length) {
          e.length += addedLen;
        }
      }

      if (i < entities.length && entities[i].length <= 0) {
        entities.removeAt(i);
      }
    }

    _prevText = newText;
  }

  bool _hasFullTag(int start, int end, FormatType type) {
    final matching = entities.where((e) => e.type == type).toList();
    for (var pos = start; pos < end;) {
      final cover = matching.where((e) =>
        e.offset <= pos && e.offset + e.length > pos);
      if (cover.isEmpty) return false;
      var furthest = pos;
      for (final e in cover) {
        final eEnd = e.offset + e.length;
        if (eEnd > furthest) furthest = eEnd;
      }
      pos = furthest;
    }
    return true;
  }

  void toggleFormat(FormatType type) {
    // A date is an inline insertion (see insertDateTimestamp / the date picker),
    // not a range format that toggles over a selection. Guard against creating
    // a timestamp-less, doubly-inert date entity — AyuGram inserts dates via the
    // picker, never as a toggle.
    if (type == FormatType.date) return;
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;

    final start = sel.start;
    final end = sel.end;

    if (_hasFullTag(start, end, type)) {
      for (var i = entities.length - 1; i >= 0; i--) {
        final e = entities[i];
        if (e.type != type) continue;
        final eEnd = e.offset + e.length;
        if (eEnd <= start || e.offset >= end) continue;

        if (e.offset >= start && eEnd <= end) {
          entities.removeAt(i);
        } else if (e.offset < start && eEnd > end) {
          entities.add(ComposeEntity(
            offset: end, length: eEnd - end, type: type,
            url: e.url, language: e.language));
          e.length = start - e.offset;
        } else if (e.offset < start) {
          e.length = start - e.offset;
        } else {
          e.offset = end;
          e.length = eEnd - end;
        }
      }
    } else {
      entities.add(ComposeEntity(offset: start, length: end - start, type: type));
    }
    notifyListeners();
  }

  /// Clears character formatting ONLY within the selection, mirroring AyuGram's
  /// `clearSelectionMarkdown` → `RemoveDocumentTags(_st, document(), from, till)`
  /// (`input_field.cpp:5014,978-1008`): the char format is reset solely on
  /// `[start, end]` via `cursor.mergeCharFormat`, so a tag extending past the
  /// selection keeps its formatting on the outside — the tag is split at the
  /// boundary, not nuked wholesale. This matches the sibling `toggleFormat`'s
  /// removal branch instead of removing every overlapping entity.
  void clearFormatting() {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start;
    final end = sel.end;
    for (var i = entities.length - 1; i >= 0; i--) {
      final e = entities[i];
      final eEnd = e.offset + e.length;
      if (eEnd <= start || e.offset >= end) continue; // outside selection — keep

      if (e.offset >= start && eEnd <= end) {
        entities.removeAt(i);
      } else if (e.offset < start && eEnd > end) {
        // Selection sits inside the tag: keep the trailing piece, clip the head.
        entities.add(ComposeEntity(
          offset: end, length: eEnd - end, type: e.type,
          url: e.url, language: e.language,
          documentId: e.documentId, altText: e.altText,
          timestamp: e.timestamp, dateFlags: e.dateFlags));
        e.length = start - e.offset;
      } else if (e.offset < start) {
        e.length = start - e.offset;
      } else {
        e.offset = end;
        e.length = eEnd - end;
      }
    }
    notifyListeners();
  }

  void setLink(String url) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start;
    final end = sel.end;
    final length = end - start;
    entities.removeWhere((e) =>
      e.type == FormatType.link && e.offset == start && e.length == length);
    if (url.isNotEmpty) {
      entities.add(ComposeEntity(
        offset: start, length: length, type: FormatType.link, url: url));
    }
    notifyListeners();
  }

  void setLinkWithText(String newText, String url) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start;
    final end = sel.end;
    final before = _prevText.substring(0, start < _prevText.length ? start : _prevText.length);
    final after = end <= _prevText.length ? _prevText.substring(end) : '';
    final fullText = '$before$newText$after';
    final lengthDiff = newText.length - (end - start);

    entities.removeWhere((e) =>
      e.type == FormatType.link && e.offset <= start && e.offset + e.length >= end);
    for (var i = entities.length - 1; i >= 0; i--) {
      final e = entities[i];
      final eEnd = e.offset + e.length;
      if (e.offset >= end) {
        e.offset += lengthDiff;
      } else if (eEnd > start && e.offset < end) {
        if (e.offset >= start && eEnd <= end) {
          entities.removeAt(i);
        } else if (e.offset < start) {
          e.length = start - e.offset;
        } else {
          final removed = end - e.offset;
          e.offset = start + newText.length;
          e.length -= removed;
        }
      }
      if (i < entities.length && entities[i].length <= 0) {
        entities.removeAt(i);
      }
    }

    if (url.isNotEmpty) {
      entities.add(ComposeEntity(
        offset: start, length: newText.length, type: FormatType.link, url: url));
    }
    _prevText = fullText;
    value = TextEditingValue(
      text: fullText,
      selection: TextSelection(baseOffset: start, extentOffset: start + newText.length),
    );
  }

  String? getLinkUrl() {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return null;
    final start = sel.start;
    final end = sel.end;
    for (final e in entities) {
      if (e.type == FormatType.link && e.offset <= start &&
          e.offset + e.length >= end) {
        return e.url;
      }
    }
    return null;
  }

  String? getCodeLanguage() {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return null;
    final start = sel.start;
    final end = sel.end;
    for (final e in entities) {
      if (e.type == FormatType.code && e.offset <= start &&
          e.offset + e.length >= end) {
        return e.language ?? '';
      }
    }
    return null;
  }

  void setCodeLanguage(String language) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start;
    final end = sel.end;
    final length = end - start;
    final trimmed = language.trim();
    entities.removeWhere((e) =>
      e.type == FormatType.code && e.offset == start && e.length == length);
    entities.add(ComposeEntity(
      offset: start, length: length, type: FormatType.code,
      language: trimmed.isNotEmpty ? trimmed : null));
    notifyListeners();
  }

  void insertDateTimestamp(DateTime date) {
    final ts = date.millisecondsSinceEpoch ~/ 1000;
    final formatted = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final sel = selection;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final before = _prevText.substring(0, pos < _prevText.length ? pos : _prevText.length);
    final after = pos <= _prevText.length ? _prevText.substring(pos) : '';
    _prevText = '$before$formatted$after';
    for (final e in entities) {
      if (e.offset >= pos) {
        e.offset += formatted.length;
      } else if (e.offset + e.length > pos) {
        e.length += formatted.length;
      }
    }
    entities.add(ComposeEntity(
      offset: pos,
      length: formatted.length,
      type: FormatType.date,
      timestamp: ts,
      dateFlags: DateFlag.shortDate,
    ));
    super.text = _prevText;
    selection = TextSelection.collapsed(offset: pos + formatted.length);
  }

  void insertCustomEmoji(int documentId, String altText) {
    final sel = selection;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final end = sel.isValid ? sel.extentOffset : text.length;
    final before = _prevText.substring(0, pos < _prevText.length ? pos : _prevText.length);
    final after = end <= _prevText.length ? _prevText.substring(end) : '';
    _prevText = '$before$_emojiPlaceholder$after';
    for (final e in entities) {
      if (e.offset >= pos) {
        e.offset += 1 - (end - pos);
      } else if (e.offset + e.length > pos) {
        e.length += 1 - (end - pos);
      }
    }
    entities.add(ComposeEntity(
      offset: pos,
      length: 1,
      type: FormatType.customEmoji,
      documentId: documentId,
      altText: altText,
    ));
    value = TextEditingValue(
      text: _prevText,
      selection: TextSelection.collapsed(offset: pos + 1),
    );
  }

  bool hasFormat(FormatType type) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    return _hasFullTag(sel.start, sel.end, type);
  }

  String get entitiesJson {
    if (entities.isEmpty) return '';
    return jsonEncode(entities.map((e) => e.toJson()).toList());
  }

  static final RegExp _languagePattern = RegExp(r'^[A-Za-z0-9+#._-]+$');

  // ── Markdown separator guards ──────────────────────────────────────────────
  // A faithful port of AyuGram's `Separators()` (text_entity.cpp:48-57) plus
  // `Quotes()` (text_entity.cpp:39-41): the set of characters that may legally
  // border a markdown delimiter. It is whitespace, punctuation, the Qt frame /
  // paragraph / line separators, and typographic quotes — deliberately NO
  // alphanumerics, so `config__settings__backup`, `a**b**`, and other
  // snake_case / emphasis-less prose stay verbatim instead of being mangled.
  static const String _mdSeparatorsBase =
      ' \x10\n\r\t.,:;<>|\'"[]{}!?%^()-+='
      '\uFDD0\uFDD1\u2029\u2028' // QTextBeginning/EndOfFrame, Paragraph/Line sep
      '\u00AB\u00BB\u201C\u201D\u2018\u2019\u2026';

  // Per-tag GoodBefore/GoodAfter sets = base + the tag-specific additions from
  // SeparatorsBold/Italic/Mono/Spoiler (text_entity.cpp:59-77). The extra
  // delimiter chars (`` ` ``, `*`, `~`, `/`, `|`) let adjacent markdown nest
  // (e.g. `**__bold italic__**`).
  static final String _mdSepBold = _mdSeparatorsBase + '`~/';
  static final String _mdSepItalic = _mdSeparatorsBase + '`*~/'; // also strike-out
  static final String _mdSepMono = _mdSeparatorsBase + '*~/'; // code + pre
  static final String _mdSepSpoiler = _mdSeparatorsBase + '|*~/';

  /// Mirrors AyuGram's `TagSearchItem::check` (`input_field.cpp:508-527`): tests
  /// whether a markdown delimiter occupying `[pos, pos+delimLen)` is a valid OPEN
  /// (`isOpen` true) or CLOSE edge. The OUTER border (the char before an open /
  /// the char after a close) must be a separator drawn from [goodBefore] /
  /// [goodAfter] (an empty set ⇒ always good — the StrikeOut close case); the
  /// INNER border (the char after an open / the char before a close) must NOT be
  /// in the rejection set [bad] (`badAfter` / `badBefore`). [isPre] additionally
  /// enforces the `kTagPre` rule that the char before the fence be a newline
  /// (`input_field.cpp:511`), anchoring fenced blocks to line starts at BOTH
  /// edges.
  static bool _markdownEdgeOk({
    required String src,
    required int pos,
    required int delimLen,
    required bool isOpen,
    required String goodBefore,
    required String goodAfter,
    required String bad,
    required bool isPre,
  }) {
    if (pos > 0) {
      final before = src[pos - 1];
      if (isPre && before != '\n' && before != '\r') return false;
      if (isOpen) {
        if (goodBefore.isNotEmpty && !goodBefore.contains(before)) return false;
      } else {
        if (bad.contains(before)) return false;
      }
    }
    final afterPos = pos + delimLen;
    if (afterPos < src.length) {
      final after = src[afterPos];
      if (isOpen) {
        if (bad.contains(after)) return false;
      } else {
        if (goodAfter.isNotEmpty && !goodAfter.contains(after)) return false;
      }
    }
    return true;
  }

  /// Pure extractor — mirrors AyuGram's `const InputField::getTextWithAppliedMarkdown()`
  /// (`input_field.cpp:3775`): it NEVER mutates [text] or the live [entities]
  /// list. It trims the text, re-bases a working copy of the entities by the
  /// leading-whitespace shift, expands custom-emoji placeholders, and applies
  /// typed markdown (`**bold**`, ```` ```pre ```` , …), returning a fresh
  /// (clean text, entities JSON). A second call (save-retry after a network
  /// error, or leading-whitespace + toolbar formatting) therefore always sees
  /// the original offsets, never corrupted ones.
  ({String text, String entitiesJson}) getTextWithAppliedMarkdown() {
    final raw = text;
    final leftTrimmed = raw.trimLeft();
    final leading = raw.length - leftTrimmed.length;
    var src = leftTrimmed.trimRight();
    if (src.isEmpty) return (text: '', entitiesJson: '');

    // Build re-based COPIES of the entities so we never touch field state. The
    // leading `trim()` shifts every offset left by [leading]; clamp into range.
    final working = <ComposeEntity>[];
    for (final e in entities) {
      var off = e.offset - leading;
      var len = e.length;
      if (off < 0) {
        len += off;
        off = 0;
      }
      if (len <= 0 || off >= src.length) continue;
      if (off + len > src.length) len = src.length - off;
      if (len <= 0) continue;
      working.add(ComposeEntity(
        offset: off, length: len, type: e.type,
        url: e.url, language: e.language,
        documentId: e.documentId, altText: e.altText,
        timestamp: e.timestamp, dateFlags: e.dateFlags));
    }

    // Expand custom-emoji entities. A freshly-inserted emoji occupies a single
    // placeholder char (_emojiPlaceholder) that must be swapped for its alt text
    // before sending; a server-loaded emoji already carries its real text in the
    // field (AyuGram stores the real text, not a placeholder —
    // input_field.cpp:886) so we leave that untouched, which is what stops a
    // re-saved note from silently dropping the emoji.
    final emojiEnts = working.where((e) => e.type == FormatType.customEmoji).toList()
      ..sort((a, b) => b.offset.compareTo(a.offset));
    for (final ce in emojiEnts) {
      if (ce.offset < 0 || ce.offset >= src.length || ce.offset + ce.length > src.length) continue;
      final covered = src.substring(ce.offset, ce.offset + ce.length);
      if (covered != _emojiPlaceholder) continue; // real text present — preserve
      final alt = ce.altText ?? '';
      if (alt.isEmpty) continue; // nothing to substitute; keep the placeholder
      src = src.substring(0, ce.offset) + alt + src.substring(ce.offset + ce.length);
      final delta = alt.length - ce.length;
      for (final e in working) {
        if (identical(e, ce)) {
          ce.length = alt.length;
          continue;
        }
        if (e.offset > ce.offset) e.offset += delta;
      }
    }

    final urlRanges = <({int start, int end})>[];
    final urlPattern = RegExp(r'(?:https?://|ftp://|www\.)\S+', caseSensitive: false);
    for (final m in urlPattern.allMatches(src)) {
      urlRanges.add((start: m.start, end: m.end));
    }

    // Each tag carries its AyuGram TagStartExpression guard sets: goodBefore /
    // goodAfter (separators that may border the OUTER edges) and bad (the
    // badAfter/badBefore rejection chars at the INNER edges). StrikeOut's
    // goodAfter is empty (always good), matching `TagStartExpressions()`
    // (input_field.cpp:567-618).
    final mdDelimiters = <({String delim, FormatType type, bool isBlock, String goodBefore, String goodAfter, String bad, bool isPre})>[
      (delim: '```', type: FormatType.pre, isBlock: true, goodBefore: _mdSepMono, goodAfter: _mdSepMono, bad: '`', isPre: true),
      (delim: '**', type: FormatType.bold, isBlock: false, goodBefore: _mdSepBold, goodAfter: _mdSepBold, bad: '*', isPre: false),
      (delim: '__', type: FormatType.italic, isBlock: false, goodBefore: _mdSepItalic, goodAfter: _mdSepItalic, bad: '_', isPre: false),
      (delim: '~~', type: FormatType.strike, isBlock: false, goodBefore: _mdSepItalic, goodAfter: '', bad: '~', isPre: false),
      (delim: '||', type: FormatType.spoiler, isBlock: false, goodBefore: _mdSepSpoiler, goodAfter: _mdSepSpoiler, bad: '|', isPre: false),
      (delim: '`', type: FormatType.code, isBlock: false, goodBefore: _mdSepMono, goodAfter: _mdSepMono, bad: '`\n\r', isPre: false),
    ];

    final strips = <({int start, int delimLen, int contentStart, int contentEnd, FormatType type, String? language})>[];
    final used = List<bool>.filled(src.length, false);

    for (final md in mdDelimiters) {
      final d = md.delim;
      final dLen = d.length;
      // Inline code never spans a newline (DoesTagFinishByNewline == kTagCode).
      final finishesByNewline = md.type == FormatType.code;
      var searchFrom = 0;
      while (searchFrom < src.length) {
        final openIdx = src.indexOf(d, searchFrom);
        if (openIdx < 0 || openIdx + dLen >= src.length) break;
        if (used[openIdx]) { searchFrom = openIdx + 1; continue; }

        // OPEN-edge separator guard (AyuGram TagSearchItem::check, Edge::Open):
        // the char before the opening delimiter must be a separator (or start of
        // text) and the char after must not be a rejection char — so
        // `config__settings`, `a**b`, snake_case, and filenames stay verbatim
        // instead of being mangled into formatting.
        if (!_markdownEdgeOk(
            src: src, pos: openIdx, delimLen: dLen, isOpen: true,
            goodBefore: md.goodBefore, goodAfter: md.goodAfter,
            bad: md.bad, isPre: md.isPre)) {
          searchFrom = openIdx + 1;
          continue;
        }

        final contentStart0 = openIdx + dLen;
        final firstNewline =
            finishesByNewline ? src.indexOf('\n', contentStart0) : -1;

        // Find the first CLOSE delimiter that also passes the close-edge guard
        // (Edge::Close: char after must be a separator, char before must not be
        // a rejection char). A delimiter that fails the guard is skipped, so the
        // scan keeps looking for a legitimate closer.
        var closeIdx = -1;
        var probe = contentStart0;
        while (true) {
          final c = src.indexOf(d, probe);
          if (c < 0) break;
          if (firstNewline >= 0 && firstNewline < c) break; // newline-terminated
          if (used[c]) { probe = c + dLen; continue; }
          if (c == contentStart0) break; // empty content — no valid pair
          if (!_markdownEdgeOk(
              src: src, pos: c, delimLen: dLen, isOpen: false,
              goodBefore: md.goodBefore, goodAfter: md.goodAfter,
              bad: md.bad, isPre: md.isPre)) {
            probe = c + dLen;
            continue;
          }
          closeIdx = c;
          break;
        }
        if (closeIdx < 0) {
          searchFrom = contentStart0;
          continue;
        }

        var contentStart = contentStart0;
        final tagEnd = closeIdx + dLen;
        final overlapsUrl = urlRanges.any((u) =>
            u.start < tagEnd && u.end > openIdx &&
            (u.end > tagEnd || u.start < openIdx));
        if (overlapsUrl) {
          searchFrom = tagEnd;
          continue;
        }

        // Fenced ``` block → Pre (block code), not inline code. An optional
        // language on the opening line (```lang\n…) becomes the Pre entity's
        // language and is stripped from the content (AyuGram parses ``` as
        // kTagPre → MessageEntityPre with language, text_entity.cpp:2179).
        String? language;
        if (md.type == FormatType.pre) {
          final nl = src.indexOf('\n', contentStart);
          if (nl >= 0 && nl < closeIdx) {
            final candidate = src.substring(contentStart, nl).trim();
            if (candidate.isNotEmpty && _languagePattern.hasMatch(candidate)) {
              language = candidate;
            }
            // Strip the opening line (language token + newline) for fenced blocks.
            for (var i = contentStart; i < nl + 1; i++) used[i] = true;
            contentStart = nl + 1;
          }
        }
        if (contentStart >= closeIdx) {
          searchFrom = tagEnd;
          continue;
        }

        for (var i = openIdx; i < openIdx + dLen; i++) used[i] = true;
        for (var i = closeIdx; i < closeIdx + dLen; i++) used[i] = true;
        strips.add((start: openIdx, delimLen: dLen, contentStart: contentStart, contentEnd: closeIdx, type: md.type, language: language));
        searchFrom = closeIdx + dLen;
      }
    }

    if (strips.isEmpty) {
      final json = working.isEmpty ? '' : jsonEncode(working.map((e) => e.toJson()).toList());
      return (text: src, entitiesJson: json);
    }

    strips.sort((a, b) => a.start.compareTo(b.start));

    final offsetMap = List<int>.filled(src.length + 1, 0);
    var totalStripped = 0;
    for (var i = 0; i < src.length; i++) {
      if (used[i]) totalStripped++;
      offsetMap[i + 1] = totalStripped;
    }

    final buf = StringBuffer();
    for (var i = 0; i < src.length; i++) {
      if (!used[i]) buf.writeCharCode(src.codeUnitAt(i));
    }
    final cleanText = buf.toString();

    final mdEntities = <ComposeEntity>[];
    for (final s in strips) {
      final newOffset = s.contentStart - offsetMap[s.contentStart];
      final newLength = (s.contentEnd - offsetMap[s.contentEnd]) - newOffset;
      if (newLength > 0) {
        mdEntities.add(ComposeEntity(offset: newOffset, length: newLength, type: s.type, language: s.language));
      }
    }

    final adjustedExisting = <ComposeEntity>[];
    for (final e in working) {
      final oStart = e.offset;
      final oEnd = e.offset + e.length;
      if (oStart >= src.length || oEnd > src.length) continue;
      final newStart = oStart - offsetMap[oStart];
      final newEnd = oEnd - offsetMap[oEnd];
      final newLen = newEnd - newStart;
      if (newLen > 0) {
        adjustedExisting.add(ComposeEntity(
          offset: newStart, length: newLen, type: e.type,
          url: e.url, language: e.language,
          documentId: e.documentId, altText: e.altText,
          timestamp: e.timestamp, dateFlags: e.dateFlags));
      }
    }

    final allEntities = [...adjustedExisting, ...mdEntities];
    final json = allEntities.isEmpty ? '' : jsonEncode(allEntities.map((e) => e.toJson()).toList());
    return (text: cleanText, entitiesJson: json);
  }

  static FormatType? _parseFormatType(String? type) {
    switch (type) {
      case 'bold': return FormatType.bold;
      case 'italic': return FormatType.italic;
      case 'underline': return FormatType.underline;
      case 'strike': return FormatType.strike;
      case 'code': return FormatType.code;
      case 'pre': return FormatType.pre;
      case 'spoiler': return FormatType.spoiler;
      case 'blockquote': return FormatType.blockquote;
      case 'text_url': return FormatType.link;
      case 'custom_emoji': return FormatType.customEmoji;
      case 'formatted_date':
      case 'custom_date': return FormatType.date;
      default: return null;
    }
  }

  /// Loads [newText] together with formatting [entitiesJson] (same shape as
  /// [ComposeEntity.toJson] / the Go `TextEntity`), so a previously-saved
  /// rich note round-trips its bold/italic/spoiler/custom-emoji formatting
  /// into the editor.
  void setTextWithEntities(String newText, String entitiesJson) {
    entities.clear();
    if (entitiesJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(entitiesJson);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final type = _parseFormatType(item['type'] as String?);
            if (type == null) continue;
            final offset = (item['offset'] as num?)?.toInt() ?? 0;
            final length = (item['length'] as num?)?.toInt() ?? 0;
            if (length <= 0 || offset < 0) continue;
            var dateFlags = 0;
            if (item['relative'] == true) dateFlags |= DateFlag.relative;
            if (item['short_time'] == true) dateFlags |= DateFlag.shortTime;
            if (item['long_time'] == true) dateFlags |= DateFlag.longTime;
            if (item['short_date'] == true) dateFlags |= DateFlag.shortDate;
            if (item['long_date'] == true) dateFlags |= DateFlag.longDate;
            if (item['day_of_week'] == true) dateFlags |= DateFlag.dayOfWeek;
            entities.add(ComposeEntity(
              offset: offset,
              length: length,
              type: type,
              url: item['url'] as String?,
              language: item['language'] as String?,
              documentId: (item['document_id'] as num?)?.toInt(),
              altText: item['alt_text'] as String?,
              timestamp: (item['date'] as num?)?.toInt() ?? (item['timestamp'] as num?)?.toInt(),
              dateFlags: dateFlags,
            ));
          }
        }
      } catch (_) {}
    }
    _prevText = newText;
    super.text = newText;
  }

  @override
  void clear() {
    entities.clear();
    _prevText = '';
    super.clear();
  }

  @override
  set text(String newText) {
    entities.clear();
    _prevText = newText;
    super.text = newText;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (entities.isEmpty) {
      return super.buildTextSpan(
        context: context, style: style, withComposing: withComposing);
    }

    final t = text;
    final palette = PaletteProvider.of(context);

    final monoFg = palette.msgInMonoFg;
    final codeBg = Color.alphaBlend(palette.msgInMonoFg.withValues(alpha: 0.08), palette.windowBg);
    // Quote background tint, matching the _ComposeFormattingOverlay outline
    // accent (windowBgActive @ 8%). Fields without that overlay (contact notes,
    // file captions) rely solely on this for the in-field quote styling.
    final quoteBg = Color.alphaBlend(palette.windowBgActive.withValues(alpha: 0.08), palette.windowBg);
    final linkFg = palette.historyLinkInFg;
    final spoilerFg = style?.color;

    final breakpoints = SplayTreeSet<int>();
    breakpoints.add(0);
    breakpoints.add(t.length);
    for (final e in entities) {
      final eStart = e.offset.clamp(0, t.length);
      final eEnd = (e.offset + e.length).clamp(0, t.length);
      if (eEnd > eStart) {
        breakpoints.add(eStart);
        breakpoints.add(eEnd);
      }
    }

    final points = breakpoints.toList();
    final spans = <InlineSpan>[];

    for (var i = 0; i < points.length - 1; i++) {
      final segStart = points[i];
      final segEnd = points[i + 1];
      if (segEnd <= segStart) continue;

      final active = <FormatType>{};
      String? linkUrl;
      ComposeEntity? emojiEntity;
      for (final e in entities) {
        final eStart = e.offset.clamp(0, t.length);
        final eEnd = (e.offset + e.length).clamp(0, t.length);
        if (eStart <= segStart && eEnd >= segEnd) {
          active.add(e.type);
          if (e.type == FormatType.link) linkUrl = e.url;
          if (e.type == FormatType.customEmoji) emojiEntity = e;
        }
      }

      if (emojiEntity != null && emojiEntity.documentId != null && accountId.isNotEmpty) {
        if (customEmojiBuilder != null) {
          spans.add(customEmojiBuilder!(emojiEntity.documentId!, accountId, emojiEntity.altText ?? '', segStart));
        } else {
          spans.add(TextSpan(text: emojiEntity.altText ?? t.substring(segStart, segEnd)));
        }
      } else if (active.isEmpty) {
        spans.add(TextSpan(text: t.substring(segStart, segEnd)));
      } else {
        // Pre (block code) and inline code both render monospace.
        final hasCode = active.contains(FormatType.code) || active.contains(FormatType.pre);
        var merged = const TextStyle();

        if (hasCode) {
          merged = merged.copyWith(
            fontFamily: 'monospace', color: monoFg, backgroundColor: codeBg);
        } else {
          if (active.contains(FormatType.bold)) {
            merged = merged.copyWith(fontWeight: FontWeight.bold);
          }
          if (active.contains(FormatType.italic)) {
            merged = merged.copyWith(fontStyle: FontStyle.italic);
          }
        }

        final decorations = <TextDecoration>[];
        if (active.contains(FormatType.underline)) {
          decorations.add(TextDecoration.underline);
        }
        if (active.contains(FormatType.strike)) {
          decorations.add(TextDecoration.lineThrough);
        }
        if (active.contains(FormatType.link)) {
          decorations.add(TextDecoration.underline);
          if (!hasCode) merged = merged.copyWith(color: linkFg);
        }
        if (active.contains(FormatType.date)) {
          if (!hasCode) merged = merged.copyWith(color: linkFg);
        }
        if (decorations.isNotEmpty) {
          merged = merged.copyWith(
            decoration: TextDecoration.combine(decorations));
        }

        if (active.contains(FormatType.spoiler)) {
          merged = merged.copyWith(color: spoilerFg);
        }
        if (active.contains(FormatType.blockquote) && !hasCode) {
          // Quote background + line height, mirroring AyuGram's in-field quote
          // block (QuoteStyle / SetBlockMargins, input_field.cpp:933-959). The
          // left outline bar + quote icon are drawn by _ComposeFormattingOverlay
          // where present; here the background gives the styling on its own.
          merged = merged.copyWith(height: 1.4, backgroundColor: quoteBg);
        }

        spans.add(TextSpan(text: t.substring(segStart, segEnd), style: merged));
      }
    }

    return TextSpan(style: style, children: spans);
  }
}
