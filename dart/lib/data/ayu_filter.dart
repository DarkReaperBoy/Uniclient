import 'dart:convert';

import 'package:flutter/foundation.dart';

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
    if (dialogId != null && dialogId!.isNotEmpty) 'dialogId': dialogId,
  };

  factory RegexFilter.fromJson(Map<String, dynamic> j) => RegexFilter(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    enabled: j['enabled'] as bool? ?? true,
    reversed: j['reversed'] as bool? ?? false,
    caseInsensitive: j['caseInsensitive'] as bool? ?? false,
    dialogId: j['dialogId'] as String?,
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
        dialogId: j['dialogId'] as String? ?? '',
        filterId: j['filterId'] as String? ?? '',
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

class _CompiledPattern {
  final RegexFilter filter;
  final RegExp? pattern;

  _CompiledPattern(this.filter)
      : pattern = _tryCompile(filter.text, filter.caseInsensitive);

  static RegExp? _tryCompile(String text, bool caseInsensitive) {
    if (text.isEmpty) return null;
    try {
      return RegExp(text, multiLine: true, caseSensitive: !caseInsensitive);
    } catch (e) {
      debugPrint('FILTER FAILED: $text — $e');
      return null;
    }
  }

  bool matches(String blob) {
    if (pattern == null) return false;
    final found = pattern!.hasMatch(blob);
    return filter.reversed ? !found : found;
  }
}

const _mediaTypeNames = <int, int>{
  1: 1,   // image → PHOTO
  2: 3,   // video → VIDEO
  3: 14,  // audio → AUDIO
  4: 15,  // voice → VOICE
  5: 12,  // videonote → ROUND_VIDEO
  6: 13,  // sticker → STICKER
  7: 11,  // gif → GIF
  8: 9,   // file → DOCUMENT
};

String extractMatchBlob(CachedMessage msg) {
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
            buf.write('\n');
            buf.write(url);
          } else {
            final offset = m['offset'] as int? ?? 0;
            final length = m['length'] as int? ?? 0;
            if (offset >= 0 && offset + length <= msg.contentText.length) {
              buf.write('\n');
              buf.write(msg.contentText.substring(offset, offset + length));
            }
          }
        }
      }
    } catch (_) {}
  }

  for (final row in msg.inlineKeyboard) {
    for (final btn in row) {
      buf.write('\n<button>${btn.text} ${btn.data}</button>');
    }
  }
  if (msg.replyKeyboard != null) {
    for (final row in msg.replyKeyboard!.rows) {
      for (final btn in row) {
        buf.write('\n<button>${btn.text}</button>');
      }
    }
  }

  final typeId = _mediaTypeNames[msg.mediaType] ?? 0;
  if (typeId > 0) {
    buf.write('\n<type>$typeId</type>');
  }

  return buf.toString();
}

class AyuFilterEngine extends ChangeNotifier {
  List<_CompiledPattern> _sharedPatterns = [];
  final Map<String, List<_CompiledPattern>> _dialogPatterns = {};
  final Map<String, Set<String>> _exclusionsByDialog = {};
  final Map<String, bool> _messageCache = {};

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
  bool hasPerDialogFilters() => _filters.any((f) => !f.isShared);

  Set<String> dialogIdsWithFilters() {
    final ids = <String>{};
    for (final f in _filters) {
      if (f.dialogId != null && f.dialogId!.isNotEmpty) {
        ids.add(f.dialogId!);
      }
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

  void invalidateMessage(String chatId, String msgId) {
    _messageCache.remove('$chatId:$msgId');
  }

  bool isFiltered(CachedMessage msg, AppState appState, {ChatType? chatType}) {
    if (!appState.filtersEnabled) return false;
    if (msg.isOutgoing) return false;

    final senderId = _parseSenderId(msg.senderId);
    if (senderId != null) {
      if (appState.isShadowBanned(senderId)) return true;
    }

    if (!_isEnabledForChat(chatType, appState)) return false;

    final cacheKey = '${msg.chatId}:${msg.msgId}';
    final cached = _messageCache[cacheKey];
    if (cached != null) return cached;

    final blob = extractMatchBlob(msg);
    final dialogId = msg.chatId;

    final dialogPats = _dialogPatterns[dialogId];
    if (dialogPats != null) {
      for (final p in dialogPats) {
        if (p.matches(blob)) {
          _messageCache[cacheKey] = true;
          return true;
        }
      }
    }

    final excl = _exclusionsByDialog[dialogId];
    for (final p in _sharedPatterns) {
      if (excl != null && excl.contains(p.filter.id)) continue;
      if (p.matches(blob)) {
        _messageCache[cacheKey] = true;
        return true;
      }
    }

    _messageCache[cacheKey] = false;
    return false;
  }

  bool _isEnabledForChat(ChatType? chatType, AppState appState) {
    if (appState.filtersEnabledInChats) return true;
    return chatType == ChatType.channel;
  }

  int? _parseSenderId(String senderId) {
    if (senderId.isEmpty) return null;
    return int.tryParse(senderId);
  }
}
