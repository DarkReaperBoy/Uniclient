import 'dart:convert';
import 'dart:io';

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
  12: 15, // animated sticker/dice → TYPE_ANIMATED_STICKER
  13: 19, // emoji-only text → TYPE_EMOJIS
  14: 23, // story → TYPE_STORY
  15: 24, // story mention → TYPE_STORY_MENTION
  16: 26, // giveaway → TYPE_GIVEAWAY
  17: 28, // giveaway results → TYPE_GIVEAWAY_RESULTS
  18: 29, // paid media → TYPE_PAID_MEDIA
  19: 30, // gift stars → TYPE_GIFT_STARS
};

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
    } catch (e) {
      debugPrint('FILTER: entity extraction failed for msg ${msg.msgId}: $e');
    }
  }

  return buf.toString();
}

int _serviceMessageType(CachedMessage msg) {
  if (msg.mediaType == 1) return 11; // service + photo → TYPE_ACTION_PHOTO
  final text = msg.contentText.toLowerCase();
  if (text.contains('call')) return 16; // TYPE_PHONE_CALL
  if (text.contains('suggest') && text.contains('photo')) return 21; // TYPE_SUGGEST_PHOTO
  if (text.contains('wallpaper')) return 22; // TYPE_ACTION_WALLPAPER
  if (text.contains('gift') && text.contains('star')) return 30; // TYPE_GIFT_STARS
  if (text.contains('giveaway') && text.contains('result')) return 28; // TYPE_GIVEAWAY_RESULTS
  if (text.contains('boost')) return 25; // TYPE_GIFT_PREMIUM_CHANNEL
  if (text.contains('premium') || text.contains('gift')) return 18; // TYPE_GIFT_PREMIUM
  if (msg.mediaType == 2) return 8; // service + video/gif → TYPE_GIF
  return 10; // TYPE_DATE (generic service)
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
    buf.write(_extractSingleText(msg, extractedUrls: entityUrls));
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
    final typeId = _mediaTypeNames[msg.mediaType] ?? 0;
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
  final Map<String, bool> _filteredMessagesShown = {};

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

  static const _backupVersion = 2;

  Map<String, dynamic> exportFilters({Map<String, String> peers = const {}}) => {
    'version': _backupVersion,
    'filters': _filters.map((f) => f.toJson()).toList(),
    'exclusions': _exclusions.map((e) => e.toJson()).toList(),
    'removeFiltersById': <String>[],
    'removeExclusions': <Map<String, dynamic>>[],
    'peers': peers,
  };

  ({int added, int updated, int removedFilters, int removedExclusions})
      importFromJson(Map<String, dynamic> data) {
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

    int added = 0, updated = 0;
    for (final f in filters) {
      if (_filters.any((ef) => ef.id == f.id)) {
        updateFilter(f);
        updated++;
      } else {
        addFilter(f);
        added++;
      }
    }
    for (final e in exclusions) {
      addExclusion(e);
    }
    for (final id in removeIds) {
      deleteFilter(id);
    }
    for (final e in removeExcl) {
      deleteExclusion(e.dialogId, e.filterId);
    }
    return (added: added, updated: updated, removedFilters: removeIds.length,
        removedExclusions: removeExcl.length);
  }

  Future<String?> importFromLink(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) return 'Invalid JSON format';
      importFromJson(parsed);
      return null;
    } catch (e) {
      return 'Failed to fetch: $e';
    }
  }

  Future<String?> publishFilters({Map<String, String> peers = const {}}) async {
    final data = exportFilters(peers: peers);
    final jsonText = const JsonEncoder.withIndent('  ').convert(data);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse('https://dpaste.com/api/v2/'));
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
      request.write(body.toString());
      final response = await request.close();
      await response.drain<void>();
      client.close();
      String pasteUrl = '';
      if (response.statusCode == 201 &&
          response.headers['location'] != null &&
          response.headers['location']!.isNotEmpty) {
        pasteUrl = response.headers['location']!.first;
      }
      if (!pasteUrl.startsWith('http')) return null;
      if (!pasteUrl.endsWith('.txt')) pasteUrl = '$pasteUrl.txt';
      await Clipboard.setData(ClipboardData(text: pasteUrl));
      return pasteUrl;
    } catch (_) {
      return null;
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

  bool filteredMessagesShown(String chatId) =>
      _filteredMessagesShown[chatId] ?? false;

  void toggleFilteredMessagesShown(String chatId) {
    _filteredMessagesShown[chatId] = !(_filteredMessagesShown[chatId] ?? false);
    notifyListeners();
  }

  void invalidateMessage(String chatId, String msgId, {String? groupedId}) {
    _messageCache.remove('$chatId:$msgId');
    if (groupedId != null && groupedId.isNotEmpty) {
      _messageCache.removeWhere((key, _) => key.startsWith('$chatId:'));
    }
  }

  bool isFiltered(CachedMessage msg, AppState appState, {ChatType? chatType, List<CachedMessage>? groupMessages}) {
    if (!appState.filtersEnabled) return false;
    if (msg.isOutgoing) return false;

    final dialogId = msg.chatId;
    if (_filteredMessagesShown[dialogId] == true) return false;

    final senderId = _parseSenderId(msg.senderId);
    if (senderId != null && msg.senderId != msg.chatId) {
      if (appState.isShadowBanned(senderId)) return true;
      if (appState.hideFromBlocked && appState.isBlocked(senderId)) return true;
    }

    final fwdId = _parseForwardSenderId(msg.forwardFrom);
    if (fwdId != null) {
      if (appState.isShadowBanned(fwdId)) return true;
      if (appState.hideFromBlocked && appState.isBlocked(fwdId)) return true;
    }

    if (!_isEnabledForChat(chatType, appState)) return false;

    final cacheKey = '${msg.chatId}:${msg.msgId}';
    final cached = _messageCache[cacheKey];
    if (cached != null) return cached;

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

  void _cacheResult(String key, bool value) {
    if (_messageCache.length >= _maxCacheSize) {
      final evictCount = _maxCacheSize ~/ 10;
      final keys = _messageCache.keys.take(evictCount).toList();
      for (final k in keys) {
        _messageCache.remove(k);
      }
    }
    _messageCache[key] = value;
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
