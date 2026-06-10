import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'debug.dart';

/// Faithful Dart port of AyuGram Desktop's `RCManager`
/// (`ayu/utils/rc_manager.{h,cpp}`) plus the peer-classification helpers from
/// `ayu/utils/telegram_helpers.cpp`.
///
/// It fetches AyuGram's remote config — the donate amounts/username AND the
/// `developers` / `officialChannels` / `supporters` / `supporterChannels` /
/// `customBadges` sets that drive AyuGram's developer / supporter / custom
/// profile badges — refreshes it hourly, and exposes the parsed data through
/// accessors that mirror the C++ singleton 1:1. Previously only the donate
/// fields were consumed and the entire badge data source was dropped on the
/// floor (`_applyRcData` parsed 4 of the 9 response fields); this restores the
/// full `applyResponse` parse so the badge data exists app-wide.
///
/// Like the C++ singleton, this is a global started once at app startup
/// (mirrors `ayu_infra.cpp` `initRCManager()` → `RCManager::start()`), NOT tied
/// to any transient widget — so the developer/supporter sets are populated for
/// badge rendering everywhere, not only when the donate box happens to open.

/// `default_developers` (rc_manager.cpp:21-25). Returned by [developers] until
/// the live RC config is fetched, exactly like the C++ `developers()` accessor
/// falling back to `default_developers` when `!initialized`.
const Set<int> kDefaultDevelopers = {
  139303278, 168769611, 668557709, 880708503, 963080346, 1156270028,
  1282540315, 1348136086, 1374434073, 1752394339, 1773117711, 2135966128,
  5079320635, 5118627360, 5184725450, 5330087923, 5800413909, 6007644928,
  7380551229, 7738913005, 7818249287, 8083933640, 8512951856,
};

/// `default_channels` (rc_manager.cpp:27-31). Returned by [channels] until the
/// live RC config is fetched (C++ `channels()` falls back to `default_channels`
/// when `!initialized`).
const Set<int> kDefaultChannels = {
  1172503281, 1434550607, 1524581881, 1559501352, 1571726392, 1632728092,
  1725670701, 1754537498, 1794457129, 1815864846, 1877362358, 1905581924,
  1947958814, 1976430343, 2130395384, 2331068091, 2401498637, 2562664432,
  2564770112, 2685666919, 3116497667, 3212977677, 3572293253,
};

/// Mirror of the C++ `CustomBadge` struct (rc_manager.h:16-20): the collectible
/// emoji-status custom-emoji id used to draw the badge, plus optional popup text.
class CustomBadge {
  /// `documentId` → `EmojiStatusId` (rc_manager.cpp:176-177). Kept as a decimal
  /// string to match the rest of the Dart engine, which carries custom-emoji /
  /// document ids as strings (e.g. `EmojiStatusWidget.emojiStatusId`).
  final String emojiStatusId;

  /// Optional badge label shown in the badge-click popup (rc_manager.cpp:181-183).
  final String text;

  const CustomBadge({required this.emojiStatusId, this.text = ''});
}

/// Badge precedence resolved by `ComputeExteraBadgeContent`
/// (telegram_helpers.cpp:199-216): custom > developer(official) > supporter.
enum AyuBadgeType { none, developer, supporter, custom }

class RcManager {
  RcManager._();

  /// Singleton — `RCManager::getInstance()` (rc_manager.h:26-29).
  static final RcManager instance = RcManager._();

  // rc_manager.cpp:15-17.
  static const String _primaryUrl =
      'https://update.ayugram.one/rc/current/desktop2';
  static const String _exteraUrl =
      'https://api.exteragram.app/api/v1/profiles/compact';
  static const Duration _fetchTimeout = Duration(seconds: 15);

  bool _initialized = false;

  final Set<int> _developers = {};
  final Set<int> _officialChannels = {};
  final Set<int> _supporters = {};
  final Set<int> _supporterChannels = {};
  final Map<int, CustomBadge> _customBadges = {};

  // Defaults match rc_manager.h:102-105 (the username keeps its leading '@').
  String _donateUsername = '@ayugramOwner';
  String _donateAmountUsd = '5.00';
  String _donateAmountTon = '3.50';
  String _donateAmountRub = '386';

  Timer? _timer;
  Future<void>? _inFlight;

  /// True once a live response has been applied — gates the default fallbacks
  /// for [developers] / [channels] exactly like the C++ `initialized` flag.
  bool get initialized => _initialized;

  // --- Accessors (rc_manager.h:38-78) ---------------------------------------

  /// Developer peer ids; falls back to [kDefaultDevelopers] until initialized
  /// (rc_manager.h:38-43).
  Set<int> get developers => _initialized ? _developers : kDefaultDevelopers;

  /// Official-channel peer ids; falls back to [kDefaultChannels] until
  /// initialized (rc_manager.h:45-50).
  Set<int> get channels => _initialized ? _officialChannels : kDefaultChannels;

  /// Supporter peer ids (rc_manager.h:52-54). No default fallback in C++.
  Set<int> get supporters => _supporters;

  /// Supporter-channel peer ids (rc_manager.h:56-58).
  Set<int> get supporterChannels => _supporterChannels;

  /// Per-peer custom badges (rc_manager.h:60-62).
  Map<int, CustomBadge> get supporterCustomBadges => _customBadges;

  String get donateUsername => _donateUsername;
  String get donateAmountUsd => _donateAmountUsd;
  String get donateAmountTon => _donateAmountTon;
  String get donateAmountRub => _donateAmountRub;

  // --- Peer classification (telegram_helpers.cpp:177-216) -------------------

  /// `isExteraPeer` — developer or official channel (telegram_helpers.cpp:177-180).
  bool isExteraPeer(int bareId) =>
      developers.contains(bareId) || channels.contains(bareId);

  /// `isSupporterPeer` (telegram_helpers.cpp:182-185).
  bool isSupporterPeer(int bareId) =>
      _supporters.contains(bareId) || _supporterChannels.contains(bareId);

  /// `isCustomBadgePeer` (telegram_helpers.cpp:187-189).
  bool isCustomBadgePeer(int bareId) => _customBadges.containsKey(bareId);

  /// `getCustomBadge` (telegram_helpers.cpp:191-197) — null when absent.
  CustomBadge? getCustomBadge(int bareId) => _customBadges[bareId];

  /// `ComputeExteraBadgeContent` precedence (telegram_helpers.cpp:199-216):
  /// custom > developer(extera) > supporter.
  AyuBadgeType badgeType(int bareId) {
    if (isCustomBadgePeer(bareId)) return AyuBadgeType.custom;
    if (isExteraPeer(bareId)) return AyuBadgeType.developer;
    if (isSupporterPeer(bareId)) return AyuBadgeType.supporter;
    return AyuBadgeType.none;
  }

  // --- Lifecycle (rc_manager.cpp:33-86) -------------------------------------

  /// `RCManager::start()` (rc_manager.cpp:33-42): fetch immediately, then refresh
  /// every hour. Idempotent — the timer is created only once. No-op on web,
  /// where `dart:io` `HttpClient` is unavailable and AyuGram badges don't render.
  void start() {
    if (kIsWeb) return;
    makeRequest();
    _timer ??= Timer.periodic(const Duration(hours: 1), (_) => makeRequest());
  }

  /// Cancels the hourly refresh timer. The manager is otherwise app-lifetime,
  /// matching the C++ singleton destroyed at app exit.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// `RCManager::makeRequest()` (rc_manager.cpp:44-47). Deduplicated so
  /// concurrent callers share the in-flight request (the C++ side keeps a single
  /// live `_reply` via `clearSentRequest()`).
  Future<void> makeRequest() => _inFlight ??= _sendRequest();

  Future<void> _sendRequest() async {
    try {
      // Primary endpoint first, exteraGram fallback on failure — mirrors
      // `tryRetryWithExteraFallback` (rc_manager.cpp:77-86).
      final data = await _fetch(_primaryUrl) ?? await _fetch(_exteraUrl);
      if (data != null) {
        _applyResponse(data);
      }
    } catch (e) {
      Debug.log('rc_manager', '_sendRequest: $e');
    } finally {
      _inFlight = null;
    }
  }

  Future<Map<String, dynamic>?> _fetch(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _fetchTimeout;
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(_fetchTimeout);
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        // applyResponse rejects a non-object root (rc_manager.cpp:119-122).
        Debug.log('rc_manager', 'not an object received in JSON from $url');
      }
    } catch (e) {
      Debug.log('rc_manager', '_fetch $url: $e');
    } finally {
      client?.close();
    }
    return null;
  }

  /// `RCManager::applyResponse` (rc_manager.cpp:111-214) — parses ALL nine
  /// response fields, not just the four donate fields. A tolerant int parse
  /// mirrors `QJsonValue::toVariant().toLongLong()` (ignore non-numeric / 0).
  void _applyResponse(Map<String, dynamic> root) {
    int? parseId(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    _developers.clear();
    _officialChannels.clear();
    _supporters.clear();
    _supporterChannels.clear();
    _customBadges.clear();

    void fillSet(String key, Set<int> dst) {
      final arr = root[key];
      if (arr is List) {
        for (final e in arr) {
          final id = parseId(e);
          if (id != null && id != 0) dst.add(id);
        }
      }
    }

    // rc_manager.cpp:125-159.
    fillSet('developers', _developers);
    fillSet('officialChannels', _officialChannels);
    fillSet('supporters', _supporters);
    fillSet('supporterChannels', _supporterChannels);

    // customBadges: [{ id, badge: { documentId, text } }] — rc_manager.cpp:161-185.
    // The emoji-status documentId is REQUIRED (entry skipped when 0/missing);
    // text is optional.
    final badges = root['customBadges'];
    if (badges is List) {
      for (final entry in badges) {
        if (entry is! Map) continue;
        final id = parseId(entry['id']);
        if (id == null || id == 0) continue;
        final badge = entry['badge'];
        if (badge is! Map) continue;
        final docId = parseId(badge['documentId']);
        if (docId == null || docId == 0) continue;
        final text = badge['text'];
        _customBadges[id] = CustomBadge(
          emojiStatusId: docId.toString(),
          text: (text is String && text.isNotEmpty) ? text : '',
        );
      }
    }

    // Donate fields: overwrite only on a non-empty STRING, else keep the
    // compiled-in default (rc_manager.cpp:187-206). A JSON number, empty string
    // or null must NOT leak through as "5.0" / "" / "null".
    String? str(dynamic v) => (v is String && v.isNotEmpty) ? v : null;
    final u = str(root['donateUsername']);
    if (u != null) _donateUsername = u;
    final usd = str(root['donateAmountUsd']);
    if (usd != null) _donateAmountUsd = usd;
    final ton = str(root['donateAmountTon']);
    if (ton != null) _donateAmountTon = ton;
    final rub = str(root['donateAmountRub']);
    if (rub != null) _donateAmountRub = rub;

    _initialized = true;
    Debug.log(
      'rc_manager',
      'Loaded ${_developers.length} developers, '
          '${_officialChannels.length} official channels, '
          '${_supporters.length} supporters, '
          '${_supporterChannels.length} supporter channels, '
          '${_customBadges.length} custom badges',
    );
  }
}

/// Converts a uniclient chat id into the bare numeric id that AyuGram's RC
/// config is keyed by (`getBareID`, telegram_helpers.cpp:173-175). The Go
/// engine formats ids as: users → bare user id, channels/supergroups →
/// `"-100" + channelId`, legacy basic groups → `"-" + chatId`
/// (telegram.go:845,866,887). Returns null for an empty/unparseable id.
int? bareIdFromChatId(String chatId) {
  if (chatId.isEmpty) return null;
  if (chatId.startsWith('-100')) {
    return int.tryParse(chatId.substring(4));
  }
  if (chatId.startsWith('-')) {
    return int.tryParse(chatId.substring(1));
  }
  return int.tryParse(chatId);
}
