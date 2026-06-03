import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';

enum FormatType { bold, italic, underline, strike, code, spoiler, blockquote, link, customEmoji, date }

class ComposeEntity {
  int offset;
  int length;
  final FormatType type;
  final String? url;
  final String? language;
  final int? documentId;
  final String? altText;
  final int? timestamp;

  ComposeEntity({required this.offset, required this.length, required this.type, this.url, this.language, this.documentId, this.altText, this.timestamp});

  Map<String, dynamic> toJson() {
    final typeStr = switch (type) {
      FormatType.bold => 'bold',
      FormatType.italic => 'italic',
      FormatType.underline => 'underline',
      FormatType.strike => 'strike',
      FormatType.code => 'code',
      FormatType.spoiler => 'spoiler',
      FormatType.blockquote => 'blockquote',
      FormatType.link => 'text_url',
      FormatType.customEmoji => 'custom_emoji',
      FormatType.date => 'custom_date',
    };
    final m = <String, dynamic>{'type': typeStr, 'offset': offset, 'length': length};
    if (url != null && url!.isNotEmpty) m['url'] = url!;
    if (language != null && language!.isNotEmpty) m['language'] = language!;
    if (documentId != null && documentId != 0) m['document_id'] = documentId!;
    if (timestamp != null) m['timestamp'] = timestamp!;
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

  void clearFormatting() {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start;
    final end = sel.end;
    entities.removeWhere((e) =>
      e.offset < end && e.offset + e.length > start);
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

  ({String text, String entitiesJson}) getTextWithAppliedMarkdown() {
    var src = text.trim();
    if (src.isEmpty) return (text: src, entitiesJson: entitiesJson);

    final emojiEnts = entities.where((e) => e.type == FormatType.customEmoji).toList()
      ..sort((a, b) => b.offset.compareTo(a.offset));
    for (final ce in emojiEnts) {
      if (ce.offset < 0 || ce.offset >= src.length || ce.offset + ce.length > src.length) continue;
      final alt = ce.altText ?? '';
      src = src.substring(0, ce.offset) + alt + src.substring(ce.offset + ce.length);
      final delta = alt.length - ce.length;
      for (final e in entities) {
        if (e == ce) {
          e.length = alt.length;
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

    final mdDelimiters = <({String delim, FormatType type, bool isBlock})>[
      (delim: '```', type: FormatType.code, isBlock: true),
      (delim: '**', type: FormatType.bold, isBlock: false),
      (delim: '__', type: FormatType.italic, isBlock: false),
      (delim: '~~', type: FormatType.strike, isBlock: false),
      (delim: '||', type: FormatType.spoiler, isBlock: false),
      (delim: '`', type: FormatType.code, isBlock: false),
    ];

    final strips = <({int start, int delimLen, int contentStart, int contentEnd, FormatType type})>[];
    final used = List<bool>.filled(src.length, false);

    for (final md in mdDelimiters) {
      final d = md.delim;
      final dLen = d.length;
      var searchFrom = 0;
      while (searchFrom < src.length) {
        final openIdx = src.indexOf(d, searchFrom);
        if (openIdx < 0 || openIdx + dLen >= src.length) break;
        if (used[openIdx]) { searchFrom = openIdx + 1; continue; }

        final contentStart = openIdx + dLen;
        int closeIdx;
        if (md.isBlock) {
          closeIdx = src.indexOf(d, contentStart);
        } else if (d == '`') {
          final nl = src.indexOf('\n', contentStart);
          final tick = src.indexOf('`', contentStart);
          if (tick < 0) break;
          if (nl >= 0 && nl < tick) { searchFrom = nl + 1; continue; }
          closeIdx = tick;
        } else {
          closeIdx = src.indexOf(d, contentStart);
        }
        if (closeIdx < 0 || closeIdx == contentStart) {
          searchFrom = contentStart;
          continue;
        }

        final tagEnd = closeIdx + dLen;
        final overlapsUrl = urlRanges.any((u) =>
            u.start < tagEnd && u.end > openIdx &&
            (u.end > tagEnd || u.start < openIdx));
        if (overlapsUrl) {
          searchFrom = tagEnd;
          continue;
        }

        for (var i = openIdx; i < openIdx + dLen; i++) used[i] = true;
        for (var i = closeIdx; i < closeIdx + dLen; i++) used[i] = true;
        strips.add((start: openIdx, delimLen: dLen, contentStart: contentStart, contentEnd: closeIdx, type: md.type));
        searchFrom = closeIdx + dLen;
      }
    }

    if (strips.isEmpty) return (text: src, entitiesJson: entitiesJson);

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
        mdEntities.add(ComposeEntity(offset: newOffset, length: newLength, type: s.type));
      }
    }

    final adjustedExisting = <ComposeEntity>[];
    for (final e in entities) {
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
          timestamp: e.timestamp));
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
      case 'code':
      case 'pre': return FormatType.code;
      case 'spoiler': return FormatType.spoiler;
      case 'blockquote': return FormatType.blockquote;
      case 'text_url': return FormatType.link;
      case 'custom_emoji': return FormatType.customEmoji;
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
            entities.add(ComposeEntity(
              offset: offset,
              length: length,
              type: type,
              url: item['url'] as String?,
              language: item['language'] as String?,
              documentId: (item['document_id'] as num?)?.toInt(),
              altText: item['alt_text'] as String?,
              timestamp: (item['timestamp'] as num?)?.toInt(),
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
        final hasCode = active.contains(FormatType.code);
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
          merged = merged.copyWith(height: 1.4);
        }

        spans.add(TextSpan(text: t.substring(segStart, segEnd), style: merged));
      }
    }

    return TextSpan(style: style, children: spans);
  }
}
