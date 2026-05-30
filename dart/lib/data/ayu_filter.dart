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
    if (blob.isEmpty) return false;
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
    } catch (e) {
      debugPrint('FILTER: entity extraction failed for msg ${msg.msgId}: $e');
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
      case 'group_call': return 16;
    }
  }

  if (msg.mediaType == 1) return 11;
  if (msg.mediaType == 2) return 8;

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
    'filters': _filters.map((f) => f.toJson()).toList(),
    'exclusions': _exclusions.map((e) => e.toJson()).toList(),
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

    final cacheKey = '${msg.chatId}:${msg.msgId}';
    final cached = _messageCache[cacheKey];
    if (cached != null) return cached;

    if (groupMessages != null && groupMessages.length > 1 && msg.groupedId.isNotEmpty) {
      _groupIndex['$dialogId:${msg.groupedId}'] =
          groupMessages.map((m) => m.msgId).toSet();
    }

    final senderId = _parseSenderId(msg.senderId);
    if (senderId != null && msg.senderId != msg.chatId) {
      if (appState.isShadowBanned(senderId)) {
        _hiddenBlockedChats.add(dialogId);
        _cacheResult(cacheKey, true);
        return true;
      }
      if (appState.hideFromBlocked && appState.isBlocked(senderId)) {
        _hiddenBlockedChats.add(dialogId);
        _cacheResult(cacheKey, true);
        return true;
      }
    }

    final fwdId = _parseForwardSenderId(msg.forwardFrom);
    if (fwdId != null) {
      if (appState.isShadowBanned(fwdId)) {
        _hiddenBlockedChats.add(dialogId);
        _cacheResult(cacheKey, true);
        return true;
      }
      if (appState.hideFromBlocked && appState.isBlocked(fwdId)) {
        _hiddenBlockedChats.add(dialogId);
        _cacheResult(cacheKey, true);
        return true;
      }
    }

    if (!_isEnabledForChat(chatType, appState)) return false;

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
