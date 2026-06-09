import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dbus/dbus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../l10n/strings.dart';
import '../utils/debug.dart';
import 'notification_manager.dart';
import 'notification_types.dart';

late final _setenvFn = () {
  final libc = ffi.DynamicLibrary.open('libc.so.6');
  return libc.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32),
      int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int)>('setenv');
}();

void _setEnv(String key, String value) {
  final keyPtr = key.toNativeUtf8(allocator: malloc);
  final valuePtr = value.toNativeUtf8(allocator: malloc);
  try {
    _setenvFn(keyPtr, valuePtr, 1);
  } finally {
    malloc.free(keyPtr);
    malloc.free(valuePtr);
  }
}

final math.Random _fileIdRng = math.Random();

/// Unique, collision-free temp-file id. Mirrors AyuGram's
/// `base::RandomValue<uint64>()` (window/notifications_utilities.cpp:69) — a
/// 32-bit `hashCode` can collide for two distinct avatar/sound source paths,
/// causing one peer's cached file to overwrite another's.
String _randomFileId() {
  final hi = _fileIdRng.nextInt(0x100000000);
  final lo = _fileIdRng.nextInt(0x100000000);
  return hi.toRadixString(16).padLeft(8, '0') +
      lo.toRadixString(16).padLeft(8, '0');
}

typedef NotificationActionCallback = void Function(
    String accountId, String chatId, String action);
typedef NotificationReplyCallback = void Function(
    String accountId, String chatId, String messageId, String replyText);

bool nativeNotificationsSupported() {
  if (kIsWeb) return false;
  return Platform.isLinux;
}

class _CachedUserpic {
  final String filePath;
  final Uint8List rawRgba;
  DateTime lastUsed;

  _CachedUserpic({required this.filePath, required this.rawRgba, required this.lastUsed});
}

class CachedUserpics {
  static const _kDeleteAfterMs = 60000;
  static const _kPhotoSize = 64;

  final Map<String, _CachedUserpic> _cache = {};
  Timer? _cleanupTimer;
  String? _cacheDir;

  Future<String?> get(String avatarPath) async {
    if (avatarPath.isEmpty) return null;

    final existing = _cache[avatarPath];
    if (existing != null && File(existing.filePath).existsSync()) {
      existing.lastUsed = DateTime.now();
      return existing.filePath;
    }

    try {
      _cacheDir ??= p.join(Directory.systemTemp.path, 'uniclient_userpics');
      await Directory(_cacheDir!).create(recursive: true);

      final srcFile = File(avatarPath);
      if (!await srcFile.exists()) return null;

      final bytes = await srcFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // Box-filter downscale (was nearest-neighbour) — matches AyuGram's
      // Qt::SmoothTransformation. (data_peer.cpp:504)
      final scaled = img.copyResize(
        image,
        width: _kPhotoSize,
        height: _kPhotoSize,
        interpolation: img.Interpolation.average,
      );
      // Round the avatar to an anti-aliased circle (transparent corners) before
      // it ships in the image-data hint / portal icon, matching AyuGram
      // GenerateUserpicImage -> Images::Circle. The hint declares 4 channels +
      // alpha, so a 3-channel (JPEG) source must be widened to RGBA first.
      // (data_peer.cpp:517)
      final resized =
          scaled.numChannels == 4 ? scaled : scaled.convert(numChannels: 4);
      _applyCircleMask(resized);
      final rawRgba = resized.toUint8List();
      final pngBytes = Uint8List.fromList(img.encodePng(resized));

      final outPath = p.join(_cacheDir!, 'userpic_${_randomFileId()}.png');
      await File(outPath).writeAsBytes(pngBytes);

      _cache[avatarPath] = _CachedUserpic(
        filePath: outPath,
        rawRgba: rawRgba,
        lastUsed: DateTime.now(),
      );

      _ensureCleanupTimer();
      return outPath;
    } catch (e) {
      Debug.log('NOTIF', 'Userpic cache write failed: $e');
      return null;
    }
  }

  // Multiplies each pixel's alpha by an anti-aliased circular coverage mask so a
  // square avatar bitmap renders as a circle. Same coverage math as the
  // placeholder path: coverage = (radius - dist + 0.5).clamp(0, 1).
  static void _applyCircleMask(img.Image image) {
    final w = image.width;
    final h = image.height;
    final center = (w - 1) / 2.0;
    final radius = w / 2.0;
    for (var py = 0; py < h; py++) {
      for (var px = 0; px < w; px++) {
        final dx = px - center;
        final dy = py - center;
        final dist = math.sqrt(dx * dx + dy * dy);
        final coverage = (radius - dist + 0.5).clamp(0.0, 1.0);
        final pixel = image.getPixel(px, py);
        image.setPixelRgba(
          px,
          py,
          pixel.r,
          pixel.g,
          pixel.b,
          (pixel.a * coverage).round(),
        );
      }
    }
  }

  Uint8List? getRawRgba(String key) {
    final existing = _cache[key];
    if (existing != null) {
      existing.lastUsed = DateTime.now();
      return existing.rawRgba;
    }
    return null;
  }

  // Resolve a generated/cached userpic's on-disk PNG path by its cache key
  // (used by the Flatpak portal branch, which ships the icon as file bytes).
  String? getPath(String key) {
    final existing = _cache[key];
    if (existing != null && File(existing.filePath).existsSync()) {
      existing.lastUsed = DateTime.now();
      return existing.filePath;
    }
    return null;
  }

  void _ensureCleanupTimer() {
    _cleanupTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanup(),
    );
  }

  void _cleanup() {
    final now = DateTime.now();
    final expired = <String>[];

    for (final entry in _cache.entries) {
      if (now.difference(entry.value.lastUsed).inMilliseconds > _kDeleteAfterMs) {
        expired.add(entry.key);
        try {
          File(entry.value.filePath).deleteSync();
        } catch (e) {
          Debug.log('notification_manager_native', 'File(entry.value.filePath).deleteSync(): $e');
        }
      }
    }

    for (final key in expired) {
      _cache.remove(key);
    }

    if (_cache.isEmpty) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
    for (final entry in _cache.values) {
      try {
        File(entry.filePath).deleteSync();
      } catch (e) {
        Debug.log('notification_manager_native', 'File(entry.filePath).deleteSync(): $e');
      }
    }
    _cache.clear();
  }
}

class NativeManager extends NotificationManager {
  @override
  ManagerType get type => ManagerType.native;

  // Whether the native server plays the alert sound itself (via the
  // `sound-file` hint). This is a static capability check, matching AyuGram's
  // `VolumeSupported()` (notifications_manager_linux.cpp:235) — it must NOT
  // gate on inhibition. DND is enforced separately at play time: the server
  // suppresses the sound when `Inhibited`, and NotificationSystem skips its own
  // fallback playback while inhibited (the `invokeIfNotInhibited` analog,
  // notifications_manager_linux.cpp:873-877). Gating this getter on
  // `_inhibited` made it return false under DND, telling callers to play their
  // own audio and defeating Do-Not-Disturb.
  @override
  bool get handlesSound => _capabilities.contains('sound');

  String defaultSoundPath = '';
  final CachedUserpics _userpicCache = CachedUserpics();

  NotificationActionCallback? onAction;
  NotificationReplyCallback? onReply;

  // LRU sound cache: source path → cached temp WAV path. Insertion order is
  // the recency order (oldest first); a cache hit re-inserts to refresh it.
  // Bounded so the temp dir can't grow without limit, the way AyuGram's
  // Media::Audio::LocalDiskCache keeps the audio_cache folder in check
  // (notifications_manager_linux.cpp:337).
  static const int _kMaxSoundCacheEntries = 64;
  final Map<String, String> _soundCache = {};
  String? _soundCacheDir;

  final Map<String, Map<String, int>> _notifications = {};
  final Map<int, NotificationData> _nativeIdToData = {};
  final Map<String, Map<String, NotificationData>> _portalNotifData = {};

  DBusClient? _dbus;
  DBusRemoteObject? _notifProxy;
  Set<String> _capabilities = {};
  bool _inhibited = false;
  bool get inhibited => _inhibited;
  String _imageDataKey = 'icon_data';
  bool _ready = false;

  StreamSubscription<DBusSignal>? _actionSub;
  StreamSubscription<DBusSignal>? _closedSub;
  StreamSubscription<DBusSignal>? _replySub;
  StreamSubscription<DBusSignal>? _activationTokenSub;
  StreamSubscription<DBusSignal>? _serviceWatcherSub;
  bool _isFlatpak = false;
  String _desktopEntry = 'uniclient';

  bool get byDefault {
    if (!_ready) return false;
    const required = {'body', 'actions', 'inline-reply'};
    if (!required.every(_capabilities.contains)) return false;
    return _capabilities.contains('sound') ||
        _capabilities.contains('inhibitions');
  }

  void Function()? onInitComplete;

  NativeManager({this.onInitComplete}) {
    if (!kIsWeb && Platform.isLinux) {
      _initLinuxDBus();
    }
  }

  String _resolveDesktopEntry() {
    final fromEnv = Platform.environment['GIO_LAUNCHED_DESKTOP_FILE'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      final basename = p.basenameWithoutExtension(fromEnv);
      if (basename.isNotEmpty) return basename;
    }
    return p.basenameWithoutExtension(Platform.resolvedExecutable);
  }

  // Telegram userpic gradient pairs (color1 top → color2 bottom), from
  // lib_ui/ui/colors.palette (historyPeerN UserpicBg / UserpicBg2). Indexed by
  // palette slot (historyPeer1 == 0 … historyPeer8 == 7).
  static const List<List<List<int>>> _userpicGradients = [
    [[0xff, 0x84, 0x5e], [0xd4, 0x52, 0x46]], // 0 red
    [[0x9a, 0xd1, 0x64], [0x46, 0xba, 0x43]], // 1 green
    [[0xe5, 0xca, 0x77], [0xe5, 0xca, 0x77]], // 2 yellow (unused)
    [[0x5c, 0xaf, 0xfa], [0x40, 0x8a, 0xcf]], // 3 blue
    [[0xb6, 0x94, 0xf9], [0x6c, 0x61, 0xdf]], // 4 purple
    [[0xff, 0x8a, 0xac], [0xd9, 0x55, 0x74]], // 5 pink
    [[0x5b, 0xcb, 0xe3], [0x35, 0x9a, 0xd4]], // 6 sea
    [[0xfe, 0xbb, 0x5b], [0xf6, 0x81, 0x36]], // 7 orange
  ];
  // ColorIndexToPaletteIndex (chat_style.cpp:1205) over the 7 simple colours
  // (kSimpleColorIndexCount): colorIndex (0..6) → palette slot above. Byte-exact
  // with the in-app `_colorRemap` used by chat_list_panel.dart's avatars.
  static const List<int> _paletteMap = [0, 7, 4, 1, 6, 3, 5];

  // Unicode letter-or-number test (Qt QChar::isLetterOrNumber → categories
  // L*/N*). Prefers Dart's Unicode-aware property escapes; if the engine rejects
  // \p{...} it stays null and a range fallback is used so notifications can't
  // break.
  static final RegExp? _letterOrNumberRe = _tryUnicodeClass(r'[\p{L}\p{N}]');

  static RegExp? _tryUnicodeClass(String pattern) {
    try {
      final re = RegExp(pattern, unicode: true);
      return re.hasMatch('A') ? re : null;
    } catch (_) {
      return null;
    }
  }

  static bool _isLetterOrNumber(int r) {
    final re = _letterOrNumberRe;
    if (re != null) return re.hasMatch(String.fromCharCode(r));
    // Fallback: common BMP letter/number ranges.
    if (r >= 0x30 && r <= 0x39) return true; // 0-9
    if (r >= 0x41 && r <= 0x5A) return true; // A-Z
    if (r >= 0x61 && r <= 0x7A) return true; // a-z
    if (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7) return true; // Latin
    if (r >= 0x370 && r <= 0x3FF) return true; // Greek
    if (r >= 0x400 && r <= 0x4FF) return true; // Cyrillic
    if (r >= 0x531 && r <= 0x58F) return true; // Armenian
    if (r >= 0x5D0 && r <= 0x5EA) return true; // Hebrew
    if (r >= 0x620 && r <= 0x64A) return true; // Arabic
    if (r >= 0x660 && r <= 0x669) return true; // Arabic-Indic digits
    if (r >= 0x0E00 && r <= 0x0E7F) return true; // Thai
    if (r >= 0x3040 && r <= 0x30FF) return true; // Kana
    if (r >= 0x4E00 && r <= 0x9FFF) return true; // CJK
    if (r >= 0xAC00 && r <= 0xD7A3) return true; // Hangul
    return false;
  }

  // Ui::Text::IsDiacritic (text.cpp:2042): non-spacing combining marks plus a
  // couple of Arabic code points. Range-based so it needs no regex support.
  static bool _isDiacritic(int r) {
    if (r == 0x0674) return true; // Arabic Hamza above
    if (r >= 0xFC5E && r <= 0xFC63) return true; // Arabic shadda ligatures
    return (r >= 0x0300 && r <= 0x036F) || // Combining Diacritical Marks
        (r >= 0x0483 && r <= 0x0489) || // Cyrillic combining
        (r >= 0x0591 && r <= 0x05BD) || // Hebrew points
        (r >= 0x0610 && r <= 0x061A) || // Arabic marks
        (r >= 0x064B && r <= 0x065F) || // Arabic marks
        r == 0x0670 || // Arabic superscript alef
        (r >= 0x06D6 && r <= 0x06DC) ||
        (r >= 0x1AB0 && r <= 0x1AFF) || // Combining Diacritical Marks Extended
        (r >= 0x1DC0 && r <= 0x1DFF) || // Combining Diacritical Marks Supplement
        (r >= 0x20D0 && r <= 0x20FF) || // Combining Marks for Symbols
        (r >= 0xFE20 && r <= 0xFE2F); // Combining Half Marks
  }

  // Emoji keycap sequence (e.g. "1️⃣"): base [0-9 # *] + optional VS16 (U+FE0F)
  // + U+20E3. Returns its length in runes, or 0 if it is not a keycap. Mirrors
  // the leading Ui::Emoji::Find skip so a keycap digit isn't taken as an initial.
  static int _keycapLength(List<int> runes, int i) {
    final r = runes[i];
    final isBase = (r >= 0x30 && r <= 0x39) || r == 0x23 || r == 0x2A;
    if (!isBase) return 0;
    var j = i + 1;
    if (j < runes.length && runes[j] == 0xFE0F) j++;
    if (j < runes.length && runes[j] == 0x20E3) return (j - i) + 1;
    return 0;
  }

  // Port of EmptyUserpic::fillString (ui/empty_userpic.cpp:613-672): derives one
  // or two initials from a PEER NAME, iterating Unicode CODE POINTS (not UTF-16
  // code units), skipping emoji + non-BMP scraps. A SECOND initial is taken ONLY
  // after a space (which resets letterFound); a hyphen bumps level to 1 but keeps
  // letterFound set, so its level-1 capture is dead code (matching AyuGram) and a
  // hyphenated-only name like "Anna-Maria" yields a single "A". Returns '' when
  // the name has no usable letter — AyuGram then draws a bare gradient circle.
  static String _getInitials(String name) {
    final runes = name.runes.toList(growable: false);
    final letters = <String>[];
    final levels = <int>[];
    var level = 0;
    var letterFound = false;
    var i = 0;
    while (i < runes.length) {
      final r = runes[i];
      final kc = _keycapLength(runes, i);
      if (kc > 0) {
        i += kc;
      } else if (r > 0xFFFF) {
        // Non-BMP (emoji or astral char): AyuGram skips the surrogate pair and
        // never derives an initial from it — so "🔥Squad" yields "S".
        i++;
      } else if (!letterFound && _isLetterOrNumber(r)) {
        letterFound = true;
        if (i + 1 < runes.length &&
            runes[i + 1] <= 0xFFFF &&
            _isDiacritic(runes[i + 1])) {
          letters.add(String.fromCharCodes([r, runes[i + 1]]));
          levels.add(level);
          i += 2;
        } else {
          letters.add(String.fromCharCode(r));
          levels.add(level);
          i++;
        }
      } else {
        if (r == 0x20) {
          level = 0;
          letterFound = false;
        } else if (letterFound && r == 0x2D) {
          // AyuGram keeps letterFound = true here (empty_userpic.cpp:650). That
          // makes the post-hyphen capture UNREACHABLE: the only reset of
          // letterFound is a space (which also zeroes level), so no letter is
          // ever taken while level == 1 — the level-1 branch is dead code. A
          // hyphenated-only name therefore yields a SINGLE initial: "Anna-Maria"
          // → "A" (not "AM"). Setting this to false would capture a second
          // initial after the hyphen and diverge from AyuGram.
          level = 1;
          letterFound = true;
        }
        i++;
      }
    }

    if (letters.isEmpty) return '';
    // Prefer the second letter to be after ' ', but it can also be after '-'.
    var result = letters.first;
    var bestIndex = 0;
    var bestLevel = 2;
    for (var k = letters.length; k != 1;) {
      k--;
      if (levels[k] < bestLevel) {
        bestIndex = k;
        bestLevel = levels[k];
      }
    }
    if (bestIndex > 0) {
      result += letters[bestIndex];
    }
    return result.toUpperCase();
  }

  // AyuGram GenerateUserpic (notifications_utilities.cpp:26-32): the self-chat
  // (Saved Messages) gets the dedicated bookmark glyph, the Replies chat gets the
  // dedicated reply-arrow glyph, every other avatar-less peer gets the
  // colored-initials placeholder. Returns the cache key for the generated userpic
  // (rawRgba via _userpicCache.getRawRgba, path via getPath), or null on failure.
  Future<String?> _generateUserpicGlyph(NotificationData data) async {
    if (data.isSelf) {
      return _generateSavedMessagesUserpic();
    }
    // peer->isRepliesChat() → EmptyUserpic::GenerateRepliesMessages, BEFORE the
    // placeholder fallthrough (notifications_utilities.cpp:29-30).
    if (data.isReplies) {
      return _generateRepliesUserpic();
    }
    final name = data.chatTitle.isNotEmpty ? data.chatTitle : data.senderName;
    final peerId = data.chatTitle.isNotEmpty ? data.chatId : data.senderId;
    return _generatePlaceholderUserpic(name, peerId);
  }

  // EmptyUserpic's colored-initials placeholder for an avatar-less peer. The
  // gradient is keyed by the peer's colorIndex (DecideColorIndex(id) =
  // id % kSimpleColorIndexCount, chat_style.cpp:1198-1199) parsed from [peerId]
  // exactly the way the in-app avatars do (chat_list_panel.dart:3307), so the
  // notification background matches what the UI shows for that chat. Initials
  // come from the PEER NAME via fillString. Returns the cache key or null.
  Future<String?> _generatePlaceholderUserpic(String name, String peerId) async {
    try {
      final numId = int.tryParse(peerId) ?? peerId.hashCode.abs();
      final colorIndex = numId.abs() % 7;
      final initials = _getInitials(name);
      final cacheKey = '__placeholder:$colorIndex:$initials';
      final existing = _userpicCache._cache[cacheKey];
      if (existing != null && File(existing.filePath).existsSync()) {
        existing.lastUsed = DateTime.now();
        return cacheKey;
      }

      final cacheDir = p.join(Directory.systemTemp.path, 'uniclient_userpics');
      await Directory(cacheDir).create(recursive: true);

      const size = 64;
      final image = img.Image(width: size, height: size, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
      final pair = _userpicGradients[_paletteMap[colorIndex]];
      _drawGradientCircle(image, pair[0], pair[1], size);

      if (initials.isNotEmpty) {
        await _drawInitials(image, initials, size);
      }

      await _storeGeneratedUserpic(cacheKey, cacheDir, image, 'placeholder');
      return cacheKey;
    } catch (e) {
      Debug.log('NOTIF', 'Placeholder userpic generation failed: $e');
      return null;
    }
  }

  // Saved Messages bookmark userpic for the self-chat, mirroring AyuGram's
  // GenerateUserpic → EmptyUserpic::GenerateSavedMessages
  // (notifications_utilities.cpp:27, empty_userpic.cpp:394-431): a white bookmark
  // glyph on the saved-messages blue gradient (historyPeerSavedMessagesBg, which
  // aliases historyPeer4UserpicBg = palette slot 3). Returns the cache key.
  Future<String?> _generateSavedMessagesUserpic() async {
    const cacheKey = '__saved_messages';
    try {
      final existing = _userpicCache._cache[cacheKey];
      if (existing != null && File(existing.filePath).existsSync()) {
        existing.lastUsed = DateTime.now();
        return cacheKey;
      }
      final cacheDir = p.join(Directory.systemTemp.path, 'uniclient_userpics');
      await Directory(cacheDir).create(recursive: true);

      const size = 64;
      final image = img.Image(width: size, height: size, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
      final pair = _userpicGradients[3]; // historyPeer4UserpicBg (blue)
      _drawGradientCircle(image, pair[0], pair[1], size);
      _drawSavedMessagesBookmark(image, size);

      await _storeGeneratedUserpic(cacheKey, cacheDir, image, 'saved');
      return cacheKey;
    } catch (e) {
      Debug.log('NOTIF', 'Saved Messages userpic generation failed: $e');
      return null;
    }
  }

  // Replies-chat userpic, mirroring AyuGram's GenerateUserpic →
  // EmptyUserpic::GenerateRepliesMessages (notifications_utilities.cpp:29-30,
  // empty_userpic.cpp:147-161,433-470): a white reply-arrow glyph
  // (st::dialogsRepliesUserpic) on the SAME saved-messages blue gradient AyuGram
  // uses for both (PaintRepliesMessages :441-442 == PaintSavedMessages :402-403,
  // historyPeerSavedMessagesBg → Bg2 == palette slot 3). Returns the cache key.
  Future<String?> _generateRepliesUserpic() async {
    const cacheKey = '__replies';
    try {
      final existing = _userpicCache._cache[cacheKey];
      if (existing != null && File(existing.filePath).existsSync()) {
        existing.lastUsed = DateTime.now();
        return cacheKey;
      }
      final cacheDir = p.join(Directory.systemTemp.path, 'uniclient_userpics');
      await Directory(cacheDir).create(recursive: true);

      const size = 64;
      final image = img.Image(width: size, height: size, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
      final pair = _userpicGradients[3]; // historyPeerSavedMessagesBg (blue)
      _drawGradientCircle(image, pair[0], pair[1], size);
      _drawRepliesIcon(image, size);

      await _storeGeneratedUserpic(cacheKey, cacheDir, image, 'replies');
      return cacheKey;
    } catch (e) {
      Debug.log('NOTIF', 'Replies userpic generation failed: $e');
      return null;
    }
  }

  // EmptyUserpic::paintCircle background: a vertical gradient (top→bottom) clipped
  // to a circle with an anti-aliased edge (transparent corners).
  static void _drawGradientCircle(
      img.Image image, List<int> top, List<int> bottom, int size) {
    final center = (size - 1) / 2.0;
    final radius = size / 2.0;
    for (var py = 0; py < size; py++) {
      final t = py / (size - 1);
      final r = (top[0] + (bottom[0] - top[0]) * t).round();
      final g = (top[1] + (bottom[1] - top[1]) * t).round();
      final b = (top[2] + (bottom[2] - top[2]) * t).round();
      for (var px = 0; px < size; px++) {
        final dx = px - center;
        final dy = py - center;
        final dist = math.sqrt(dx * dx + dy * dy);
        final coverage = (radius - dist + 0.5).clamp(0.0, 1.0);
        if (coverage <= 0) continue;
        image.setPixelRgba(px, py, r, g, b, (coverage * 255).round());
      }
    }
  }

  // EmptyUserpic::paint's initials text (empty_userpic.cpp:305-337): the peer's
  // initials, drawn centered in white over the gradient circle. AyuGram draws them
  // with `st::historyPeerUserpicFont` (semiboldFont == font(13px semibold),
  // basic.style:53 / chat.style:448) at pixel size `(size*13)/33`, via Qt's
  // `p.setFont(font); p.drawText(QRect(x,y,size,size), _string, al_center)` — a
  // FULL-UNICODE font, so the letter always appears.
  //
  // The `image` package's only text path (`img.drawString` + `img.arial24`) embeds
  // a BMFont with ONLY 92 glyphs (ASCII U+0020-U+007E plus U+2116 №); `drawString`
  // silently skips every other code point, so Cyrillic / Greek / Arabic / Hebrew /
  // Thai / Kana / CJK / Hangul / accented-Latin initials would render as a bare
  // colored circle with no letter — the bulk of Telegram's real user base. We
  // instead rasterize the initials through dart:ui (the platform font stack, full
  // Unicode + per-script fallback, exactly like Qt's drawText) and alpha-composite
  // the result over the circle.
  static Future<void> _drawInitials(img.Image image, String text, int size) async {
    try {
      final fontSize = (size * 13) / 33; // EmptyUserpic::paint fontsize formula
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        fontSize: fontSize,
        fontWeight: ui.FontWeight.w600, // semibold (basic.style:53 semiboldFont)
        maxLines: 1,
      ))
        ..pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF), // historyPeerUserpicFg == windowFgActive
          fontSize: fontSize,
          fontWeight: ui.FontWeight.w600,
        ))
        ..addText(text);
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: size.toDouble()));

      // al_center centers vertically too; ParagraphBuilder lays out from the top,
      // so shift down by the leftover height to center within the size×size box.
      final dy = (size - paragraph.height) / 2.0;

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawParagraph(paragraph, ui.Offset(0, dy));
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(size, size);
      picture.dispose();
      final bytes =
          await rendered.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      rendered.dispose();
      if (bytes == null) return;
      final pixels = bytes.buffer.asUint8List();

      // Straight-alpha "over": out = src*a + dst*(1-a). The text is white and sits
      // well inside the opaque circle, so only its anti-aliased edges blend.
      for (var py = 0; py < size; py++) {
        for (var px = 0; px < size; px++) {
          final o = (py * size + px) * 4;
          final sa = pixels[o + 3];
          if (sa == 0) continue;
          final fa = sa / 255.0;
          final inv = 1.0 - fa;
          final bg = image.getPixel(px, py);
          image.setPixelRgba(
            px,
            py,
            (pixels[o] * fa + bg.r * inv).round().clamp(0, 255),
            (pixels[o + 1] * fa + bg.g * inv).round().clamp(0, 255),
            (pixels[o + 2] * fa + bg.b * inv).round().clamp(0, 255),
            (sa + bg.a * inv).round().clamp(0, 255),
          );
        }
      }
    } catch (e) {
      // Best-effort: on any rasterization failure keep the gradient circle (still
      // a valid placeholder) rather than aborting the whole userpic.
      Debug.log('NOTIF', 'Initials render failed: $e');
    }
  }

  // Paints EmptyUserpic's Saved Messages bookmark outline (PaintSavedMessagesInner,
  // empty_userpic.cpp:44-116) in white over the already-painted gradient circle.
  // The geometry uses AyuGram's exact size-relative formulas; the outline is the
  // closed rectangle-with-bottom-notch, stroked as an anti-aliased polyline via
  // distance-to-segment (round joins, sub-pixel-faithful at this size).
  static void _drawSavedMessagesBookmark(img.Image image, int size) {
    final thickness = (size * 0.055).round();
    final increment = (thickness % 2) + (size % 2);
    final bw = (size * 0.15).round() * 2 + increment;
    final bh = (size * 0.19).round() * 2 + increment;
    final add = (size * 0.064).round();

    final left = ((size - bw) ~/ 2).toDouble();
    final top = ((size - bh) ~/ 2).toDouble();
    final right = left + bw;
    final bottom = top + bh;
    final midX = (left + right) / 2.0;

    // Bookmark outline: rectangle with a triangular notch cut into the bottom.
    final pts = <List<double>>[
      [left, top],
      [right, top],
      [right, bottom],
      [midX, bottom - add],
      [left, bottom],
    ];

    final half = thickness / 2.0;
    for (var py = 0; py < size; py++) {
      for (var px = 0; px < size; px++) {
        final fx = px.toDouble();
        final fy = py.toDouble();
        var best = double.infinity;
        for (var s = 0; s < pts.length; s++) {
          final a = pts[s];
          final b = pts[(s + 1) % pts.length];
          final d = _distToSegment(fx, fy, a[0], a[1], b[0], b[1]);
          if (d < best) best = d;
        }
        final coverage = (half - best + 0.5).clamp(0.0, 1.0);
        if (coverage <= 0) continue;
        final bg = image.getPixel(px, py);
        final inv = 1.0 - coverage;
        final outA = (coverage * 255).round();
        image.setPixelRgba(
          px,
          py,
          (bg.r * inv + 255 * coverage).round(),
          (bg.g * inv + 255 * coverage).round(),
          (bg.b * inv + 255 * coverage).round(),
          bg.a < outA ? outA : bg.a.toInt(),
        );
      }
    }
  }

  // Paints EmptyUserpic's Replies glyph (PaintRepliesMessagesInner,
  // empty_userpic.cpp:147-161 → st::dialogsRepliesUserpic) in white over the
  // already-painted gradient circle. Ports the reply-arrow glyph used by the chat
  // list's _RepliesIconPainter (chat_list_row.dart:1953-1996) into the raster img
  // pipeline, using the same per-pixel distance-to-segment test as
  // _drawSavedMessagesBookmark — which yields the round caps/joins the chat-list
  // painter draws with StrokeCap.round / StrokeJoin.round. Geometry constants are
  // byte-identical to that painter (stroke s*0.06, arrowSize s*0.16, leftX
  // cx-s*0.08, tip at cy-s*0.06).
  static void _drawRepliesIcon(img.Image image, int size) {
    final s = size.toDouble();
    final stroke = s * 0.06;
    final half = stroke / 2.0;
    final arrowSize = s * 0.16;
    final cx = s / 2.0;
    final cy = s / 2.0;
    final leftX = cx - s * 0.08;
    final tipX = leftX - arrowSize; // arrowhead apex
    final tipY = cy - s * 0.06;

    // Glyph as a list of line segments (x0,y0,x1,y1). Round caps/joins emerge
    // from the per-pixel min-distance test below.
    final segs = <List<double>>[
      // Arrowhead: apex → upper-right, apex → lower-right.
      [tipX, tipY, leftX, tipY - arrowSize * 0.7],
      [tipX, tipY, leftX, tipY + arrowSize * 0.7],
      // Body: horizontal stem from the apex to the curve start.
      [tipX, tipY, leftX + s * 0.12, tipY],
    ];
    // Body curve: quadratic bezier (leftX+0.12s, tipY) ctrl (leftX+0.2s, tipY)
    // → (leftX+0.2s, cy+0.04s), decomposed into short segments.
    final p0x = leftX + s * 0.12, p0y = tipY;
    final ctlx = leftX + s * 0.2, ctly = tipY;
    final p2x = leftX + s * 0.2, p2y = cy + s * 0.04;
    const steps = 12;
    var prevX = p0x, prevY = p0y;
    for (var k = 1; k <= steps; k++) {
      final t = k / steps;
      final mt = 1.0 - t;
      final x = mt * mt * p0x + 2 * mt * t * ctlx + t * t * p2x;
      final y = mt * mt * p0y + 2 * mt * t * ctly + t * t * p2y;
      segs.add([prevX, prevY, x, y]);
      prevX = x;
      prevY = y;
    }
    // Vertical tail.
    segs.add([p2x, p2y, p2x, cy + s * 0.12]);

    for (var py = 0; py < size; py++) {
      for (var px = 0; px < size; px++) {
        final fx = px.toDouble();
        final fy = py.toDouble();
        var best = double.infinity;
        for (final seg in segs) {
          final d = _distToSegment(fx, fy, seg[0], seg[1], seg[2], seg[3]);
          if (d < best) best = d;
        }
        final coverage = (half - best + 0.5).clamp(0.0, 1.0);
        if (coverage <= 0) continue;
        final bg = image.getPixel(px, py);
        final inv = 1.0 - coverage;
        final outA = (coverage * 255).round();
        image.setPixelRgba(
          px,
          py,
          (bg.r * inv + 255 * coverage).round(),
          (bg.g * inv + 255 * coverage).round(),
          (bg.b * inv + 255 * coverage).round(),
          bg.a < outA ? outA : bg.a.toInt(),
        );
      }
    }
  }

  static double _distToSegment(
      double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    var t = lenSq > 0 ? ((px - ax) * dx + (py - ay) * dy) / lenSq : 0.0;
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final ex = px - cx;
    final ey = py - cy;
    return math.sqrt(ex * ex + ey * ey);
  }

  // Encodes [image] to a temp PNG, stores it + its raw RGBA under [cacheKey], and
  // arms the cleanup timer. Shared by the placeholder + Saved Messages paths.
  Future<void> _storeGeneratedUserpic(
      String cacheKey, String cacheDir, img.Image image, String prefix) async {
    final rawRgba = image.toUint8List();
    final outPath = p.join(cacheDir, '${prefix}_${_randomFileId()}.png');
    await File(outPath).writeAsBytes(Uint8List.fromList(img.encodePng(image)));
    _userpicCache._cache[cacheKey] = _CachedUserpic(
      filePath: outPath,
      rawRgba: rawRgba,
      lastUsed: DateTime.now(),
    );
    _userpicCache._ensureCleanupTimer();
  }

  Future<void> _initLinuxDBus() async {
    try {
      _isFlatpak = File('/.flatpak-info').existsSync() ||
          Platform.environment.containsKey('FLATPAK_ID');
      _desktopEntry = _resolveDesktopEntry();
      _dbus ??= DBusClient.session();
      _notifProxy = DBusRemoteObject(
        _dbus!,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );

      try {
        final capsResult = await _notifProxy!.callMethod(
          'org.freedesktop.Notifications',
          'GetCapabilities',
          [],
          replySignature: DBusSignature('as'),
        );
        _capabilities = capsResult.returnValues[0].asStringArray().toSet();
        Debug.log('NOTIF', 'DBus capabilities: $_capabilities');
      } catch (e) {
        Debug.log('NOTIF', 'GetCapabilities failed: $e');
      }

      try {
        final infoResult = await _notifProxy!.callMethod(
          'org.freedesktop.Notifications',
          'GetServerInformation',
          [],
          replySignature: DBusSignature('ssss'),
        );
        final specVersion = infoResult.returnValues[3].asString();
        final specParts = specVersion.split('.');
        final specMajor = int.tryParse(specParts.isNotEmpty ? specParts[0] : '0') ?? 0;
        final specMinor = int.tryParse(specParts.length > 1 ? specParts[1] : '0') ?? 0;
        if (specMajor > 1 || (specMajor == 1 && specMinor >= 2)) {
          _imageDataKey = 'image-data';
        } else if (specMajor == 1 && specMinor == 1) {
          _imageDataKey = 'image_data';
        } else {
          _imageDataKey = 'icon_data';
        }
        Debug.log('NOTIF',
            'Server: ${infoResult.returnValues[0].asString()} '
            'v${infoResult.returnValues[2].asString()}, '
            'spec $specVersion, imageKey=$_imageDataKey');
      } catch (e) {
        Debug.log('NOTIF', 'GetServerInformation failed: $e');
      }

      try {
        final inhibVal = await _notifProxy!.getProperty(
          'org.freedesktop.Notifications',
          'Inhibited',
          signature: DBusSignature('b'),
        );
        _inhibited = inhibVal.asBoolean();
        Debug.log('NOTIF', 'Inhibited (DND): $_inhibited');
      } catch (_) {
        _inhibited = false;
      }

      final notifPath = DBusObjectPath('/org/freedesktop/Notifications');

      _actionSub = DBusSignalStream(
        _dbus!,
        interface: 'org.freedesktop.Notifications',
        name: 'ActionInvoked',
        path: notifPath,
      ).listen(_onActionInvoked);

      _closedSub = DBusSignalStream(
        _dbus!,
        interface: 'org.freedesktop.Notifications',
        name: 'NotificationClosed',
        path: notifPath,
      ).listen(_onNotificationClosed);

      if (_capabilities.contains('inline-reply')) {
        _replySub = DBusSignalStream(
          _dbus!,
          interface: 'org.freedesktop.Notifications',
          name: 'NotificationReplied',
          path: notifPath,
        ).listen(_onNotificationReplied);
      }

      _activationTokenSub = DBusSignalStream(
        _dbus!,
        interface: 'org.freedesktop.Notifications',
        name: 'ActivationToken',
        path: notifPath,
      ).listen(_onActivationToken);

      _serviceWatcherSub = DBusSignalStream(
        _dbus!,
        sender: 'org.freedesktop.DBus',
        interface: 'org.freedesktop.DBus',
        name: 'NameOwnerChanged',
        path: DBusObjectPath('/org/freedesktop/DBus'),
      ).listen(_onServiceOwnerChanged);

      _ready = true;
      Debug.log('NOTIF', 'Linux DBus backend initialized');
      onInitComplete?.call();
    } catch (e) {
      Debug.log('NOTIF', 'Linux DBus init failed: $e');
      _ready = false;
      onInitComplete?.call();
    }
  }

  void _onActionInvoked(DBusSignal signal) {
    if (signal.values.length < 2) return;
    final nativeId = signal.values[0].asUint32();
    final actionKey = signal.values[1].asString();
    final data = _nativeIdToData[nativeId];
    if (data == null) return;

    Debug.log('NOTIF', 'ActionInvoked: $actionKey for ${data.chatTitle}');

    switch (actionKey) {
      case 'default':
        onAction?.call(data.accountId, data.chatId, 'open');
      case 'mail-mark-read':
        onAction?.call(data.accountId, data.chatId, 'markRead');
    }

    _removeNativeId(nativeId);
  }

  void _onNotificationClosed(DBusSignal signal) {
    if (signal.values.length < 2) return;
    final nativeId = signal.values[0].asUint32();
    final reason = signal.values[1].asUint32();
    // reason 1=expired, 2=user dismissed, 3=CloseNotification called, 4=reserved
    // Only remove tracking when user dismissed (reason 2). For other reasons,
    // keep the entry so clearFromHistory can still call CloseNotification to
    // remove stale entries from the notification center's history.
    if (reason == 2) {
      _removeNativeId(nativeId);
    }
  }

  void _evictStaleEntries() {
    for (final contextMap in _notifications.values) {
      contextMap.removeWhere((_, nativeId) => !_nativeIdToData.containsKey(nativeId));
    }
    _notifications.removeWhere((_, map) => map.isEmpty);
  }

  void _onNotificationReplied(DBusSignal signal) {
    if (signal.values.length < 2) return;
    final nativeId = signal.values[0].asUint32();
    final replyText = signal.values[1].asString();
    final data = _nativeIdToData[nativeId];
    if (data == null) return;

    Debug.log('NOTIF', 'Reply: "$replyText" for ${data.chatTitle}');
    onReply?.call(data.accountId, data.chatId, data.messageId, replyText);
    _removeNativeId(nativeId);
  }

  void _onActivationToken(DBusSignal signal) {
    if (signal.values.length < 2) return;
    final nativeId = signal.values[0].asUint32();
    final token = signal.values[1].asString();
    if (_nativeIdToData.containsKey(nativeId)) {
      _setEnv('XDG_ACTIVATION_TOKEN', token);
    }
  }

  void _onServiceOwnerChanged(DBusSignal signal) {
    if (signal.values.length < 3) return;
    final name = signal.values[0].asString();
    if (name != 'org.freedesktop.Notifications') return;
    final newOwner = signal.values[2].asString();
    if (newOwner.isNotEmpty) {
      Debug.log('NOTIF', 'Notification service restarted, reconnecting');
      _reconnect();
    } else {
      Debug.log('NOTIF', 'Notification service died, clearing stale IDs');
      _notifications.clear();
      _nativeIdToData.clear();
    }
  }

  Future<void> _reconnect() async {
    _actionSub?.cancel();
    _closedSub?.cancel();
    _replySub?.cancel();
    _activationTokenSub?.cancel();
    _serviceWatcherSub?.cancel();
    _notifications.clear();
    _nativeIdToData.clear();
    _ready = false;
    _notifProxy = null;
    await _initLinuxDBus();
  }

  void _removeNativeId(int nativeId) {
    _nativeIdToData.remove(nativeId);
    for (final contextMap in _notifications.values) {
      contextMap.removeWhere((_, id) => id == nativeId);
    }
    _notifications.removeWhere((_, map) => map.isEmpty);
  }

  @override
  void showNotification(NotificationData data, NotificationSettings settings) {
    if (!kIsWeb && Platform.isLinux) {
      _showLinuxDBusNotification(data, settings);
    }
  }

  Future<void> _showLinuxDBusNotification(
      NotificationData data, NotificationSettings settings) async {
    if (!_ready || _notifProxy == null) {
      if (_isFlatpak) {
        await _showFlatpakPortalNotification(data, settings);
      }
      return;
    }

    try {
      final v = await _notifProxy!.getProperty(
        'org.freedesktop.Notifications',
        'Inhibited',
        signature: DBusSignature('b'),
      );
      _inhibited = v.asBoolean();
    } catch (e) {
      Debug.log('notification_manager_native', 'final v = await _notifProxy!.getProperty(: $e');
    }

    final contextKey = '${data.accountId}:${data.chatId}';

    final actions = <DBusValue>[];
    if (_capabilities.contains('actions')) {
      actions.addAll([
        DBusString('default'),
        DBusString(TrStrings.lngOpenLink()),
      ]);
      if (!data.hideMarkAsRead) {
        actions.addAll([
          DBusString('mail-mark-read'),
          DBusString(TrStrings.lngContextMarkRead()),
        ]);
      }
      final hideReply = shouldHideReplyButton(data, settings);
      if (_capabilities.contains('inline-reply') && !hideReply) {
        actions.addAll([
          DBusString('inline-reply'),
          DBusString(TrStrings.lngNotificationReply()),
        ]);
      }
    }

    final hints = <DBusValue, DBusValue>{
      DBusString('category'): DBusVariant(DBusString('im.received')),
    };

    if (_capabilities.contains('action-icons')) {
      hints[DBusString('action-icons')] = DBusVariant(DBusBoolean(true));
    }

    if (_capabilities.contains('x-canonical-append')) {
      hints[DBusString('x-canonical-append')] =
          DBusVariant(DBusString('true'));
    }

    hints[DBusString('desktop-entry')] =
        DBusVariant(DBusString(_desktopEntry));

    final forceHideDetails = !settings.previewName && !settings.previewText;
    var imageHintSet = false;
    if (!forceHideDetails) {
      Uint8List? rawRgba;
      if (!data.isSelf && data.avatarPath.isNotEmpty) {
        await _userpicCache.get(data.avatarPath);
        rawRgba = _userpicCache.getRawRgba(data.avatarPath);
      } else {
        // Self-chat → Saved Messages bookmark glyph; any other avatar-less peer
        // → colored-initials placeholder (GenerateUserpic,
        // notifications_utilities.cpp:26-32).
        final key = await _generateUserpicGlyph(data);
        rawRgba = key != null ? _userpicCache.getRawRgba(key) : null;
      }
      if (rawRgba != null) {
        hints[DBusString(_imageDataKey)] = DBusVariant(
          _buildImageHintFromRgba(rawRgba),
        );
        imageHintSet = true;
      }
    }

    if (settings.allowSound &&
        !_inhibited &&
        !data.isSilent &&
        !data.soundNone &&
        _capabilities.contains('sound')) {
      final rawPath = data.soundDocumentPath.isNotEmpty
          ? data.soundDocumentPath
          : defaultSoundPath;
      final soundPath =
          rawPath.isNotEmpty ? await _cachedSoundPath(rawPath) : null;
      if (soundPath != null) {
        hints[DBusString('sound-file')] =
            DBusVariant(DBusString(soundPath));
      } else {
        hints[DBusString('suppress-sound')] = DBusVariant(DBusBoolean(true));
      }
    } else {
      hints[DBusString('suppress-sound')] = DBusVariant(DBusBoolean(true));
    }

    int replacesId = 0;
    final existingIds = _notifications[contextKey];
    if (existingIds != null && existingIds.containsKey(data.messageId)) {
      replacesId = existingIds[data.messageId]!;
    }

    try {
      final result = await _notifProxy!.callMethod(
        'org.freedesktop.Notifications',
        'Notify',
        [
          DBusString('UniClient'),
          DBusUint32(replacesId),
          // app_icon: empty when an image-data hint carries the userpic;
          // otherwise fall back to the app icon so the notification is never
          // icon-less (notifications_manager_linux.cpp:772-773 —
          // `!hasImage ? ApplicationIconName() : ""`). A decode failure or a
          // missing avatar file leaves no image hint even with previews on.
          DBusString(imageHintSet ? '' : _desktopEntry),
          DBusString(
              data.chatTitle.isNotEmpty ? data.chatTitle : data.senderName),
          DBusString(_buildBody(data)),
          DBusArray(DBusSignature('s'), actions),
          DBusDict(DBusSignature('s'), DBusSignature('v'), hints),
          DBusInt32(-1),
        ],
        replySignature: DBusSignature('u'),
      );

      final nativeId = result.returnValues[0].asUint32();

      _notifications.putIfAbsent(contextKey, () => {});
      _notifications[contextKey]![data.messageId] = nativeId;
      _nativeIdToData[nativeId] = data;

      Debug.log('NOTIF', 'DBus notify id=$nativeId: ${data.chatTitle}');
    } catch (e) {
      Debug.log('NOTIF', 'DBus Notify failed: $e');
    }
  }

  String _buildBody(NotificationData data) {
    if (_capabilities.contains('body-markup')) {
      if (data.subtitle.isNotEmpty) {
        return '<b>${_escapeHtml(data.subtitle)}</b>\n${_escapeHtml(data.text)}';
      }
      return _escapeHtml(data.text);
    }
    if (data.subtitle.isNotEmpty) {
      return TrStrings.lngDialogsTextWithFrom(data.subtitle, data.text);
    }
    return data.text;
  }

  Future<String?> _cachedSoundPath(String sourcePath) async {
    if (sourcePath.isEmpty) return null;
    final cached = _soundCache[sourcePath];
    if (cached != null && File(cached).existsSync()) {
      // Refresh recency: re-insert so this entry becomes most-recently-used.
      _soundCache.remove(sourcePath);
      _soundCache[sourcePath] = cached;
      return cached;
    }
    try {
      final srcFile = File(sourcePath);
      if (!await srcFile.exists()) return null;
      _soundCacheDir ??=
          p.join(Directory.systemTemp.path, 'uniclient_audio_cache');
      await Directory(_soundCacheDir!).create(recursive: true);
      final ext = p.extension(sourcePath).isNotEmpty
          ? p.extension(sourcePath)
          : '.wav';
      final outPath = p.join(_soundCacheDir!, 'TD_${_randomFileId()}$ext');
      await srcFile.copy(outPath);
      _soundCache[sourcePath] = outPath;
      _evictSoundCacheIfNeeded();
      return outPath;
    } catch (e) {
      Debug.log('NOTIF', 'Sound cache failed: $e');
      return null;
    }
  }

  // Drop least-recently-used sounds (and their temp files) once the cache
  // exceeds its bound, so the audio cache directory stays bounded.
  void _evictSoundCacheIfNeeded() {
    while (_soundCache.length > _kMaxSoundCacheEntries) {
      final oldestKey = _soundCache.keys.first;
      final oldestPath = _soundCache.remove(oldestKey);
      if (oldestPath != null) {
        try {
          File(oldestPath).deleteSync();
        } catch (e) {
          Debug.log('notification_manager_native', 'File(oldestPath).deleteSync(): $e');
        }
      }
    }
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static DBusStruct _buildImageHintFromRgba(Uint8List rawRgba, {int size = 64}) {
    return DBusStruct([
      DBusInt32(size),
      DBusInt32(size),
      DBusInt32(size * 4),
      DBusBoolean(true),
      DBusInt32(8),
      DBusInt32(4),
      DBusArray.byte(rawRgba),
    ]);
  }

  StreamSubscription<DBusSignal>? _portalActionSub;

  void _ensurePortalActionListener() {
    if (_portalActionSub != null) return;
    final dbus = _dbus;
    if (dbus == null) return;
    _portalActionSub = DBusSignalStream(
      dbus,
      interface: 'org.freedesktop.portal.Notification',
      name: 'ActionInvoked',
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    ).listen((signal) {
      if (signal.values.length < 3) return;
      final notifId = signal.values[0].asString();
      final action = signal.values[1].asString();
      // Recover the real (accountId, chatId) the way AyuGram's
      // dictToNotificationId does (notifications_manager_linux.cpp:371): read the
      // typed values carried IN the notification, NEVER by string-splitting the
      // id. Engine account ids contain an underscore (e.g. "tele_a1b2c3d4",
      // go/engine/accounts.go:40), so splitting "${accountId}_${chatId}_${messageId}"
      // yields garbage (parts[0]='tele', parts[1]='a1b2c3d4'). Primary source: the
      // action target — signal.values[2], the `av` we set as default-action-target
      // / button target below. Fallback: the cached NotificationData keyed by
      // notifId in _portalNotifData (mirrors the native path's _nativeIdToData
      // lookup in _onActionInvoked).
      String? accountId;
      String? chatId;
      try {
        final params = signal.values[2].asVariantArray().toList();
        if (params.isNotEmpty) {
          final target = params.first.asStringArray().toList();
          if (target.length >= 2) {
            accountId = target[0];
            chatId = target[1];
          }
        }
      } catch (e) {
        Debug.log('notification_manager_native',
            'portal action target parse failed: $e');
      }
      if (accountId == null || chatId == null) {
        final data = _findPortalData(notifId);
        if (data != null) {
          accountId = data.accountId;
          chatId = data.chatId;
        }
      }
      if (accountId == null || chatId == null) {
        Debug.log('NOTIF',
            'Portal ActionInvoked: cannot resolve target for $notifId');
        return;
      }
      Debug.log('NOTIF', 'Portal ActionInvoked: $action for $notifId');
      switch (action) {
        case 'default':
        case 'app.notification-activate':
          onAction?.call(accountId, chatId, 'open');
        case 'app.notification-mark-as-read':
          onAction?.call(accountId, chatId, 'markRead');
      }
    });
  }

  /// Locate the NotificationData backing a portal notification by its unique
  /// notifId, scanning every context bucket. Fallback for when the action
  /// target variant is missing/malformed — mirrors the native DBus path which
  /// resolves data via _nativeIdToData rather than parsing the id string.
  NotificationData? _findPortalData(String notifId) {
    for (final contextMap in _portalNotifData.values) {
      final data = contextMap[notifId];
      if (data != null) return data;
    }
    return null;
  }

  Future<void> _showFlatpakPortalNotification(
      NotificationData data, NotificationSettings settings) async {
    try {
      final dbus = _dbus ?? DBusClient.session();
      if (_dbus == null) _dbus = dbus;
      _ensurePortalActionListener();
      final portalProxy = DBusRemoteObject(
        dbus,
        name: 'org.freedesktop.portal.Desktop',
        path: DBusObjectPath('/org/freedesktop/portal/desktop'),
      );
      final notifId = '${data.accountId}_${data.chatId}_${data.messageId}';
      final title = data.chatTitle.isNotEmpty ? data.chatTitle : data.senderName;

      final body = data.subtitle.isNotEmpty
          ? '${data.subtitle}: ${data.text}'
          : data.text;

      final notifDict = <DBusValue, DBusValue>{
        DBusString('title'): DBusVariant(DBusString(title)),
        DBusString('body'): DBusVariant(DBusString(body)),
        DBusString('priority'): DBusVariant(DBusString('high')),
        DBusString('default-action'): DBusVariant(DBusString('app.notification-activate')),
        DBusString('default-action-target'):
            DBusVariant(DBusArray(DBusSignature('s'), [
              DBusString(data.accountId),
              DBusString(data.chatId),
              DBusString(data.messageId),
            ])),
      };

      final forceHideDetails = !settings.previewName && !settings.previewText;
      if (!forceHideDetails) {
        try {
          // Avatar peers -> rounded cloud userpic; self-chat -> Saved Messages
          // bookmark glyph; any other avatar-less peer -> colored-initials
          // placeholder (EmptyUserpic), mirroring the DBus branch and AyuGram's
          // GenerateUserpic which always renders an icon inside !hideNameAndPhoto.
          // (notifications_utilities.cpp:26-32, notifications_manager_linux.cpp:691)
          final String? imgPath;
          if (!data.isSelf && data.avatarPath.isNotEmpty) {
            imgPath = await _userpicCache.get(data.avatarPath);
          } else {
            final key = await _generateUserpicGlyph(data);
            imgPath = key != null ? _userpicCache.getPath(key) : null;
          }
          if (imgPath != null) {
            final pngBytes = await File(imgPath).readAsBytes();
            notifDict[DBusString('icon')] = DBusVariant(
              DBusStruct([
                DBusString('bytes'),
                DBusVariant(DBusArray.byte(pngBytes)),
              ]),
            );
          }
        } catch (e) {
          Debug.log('notification_manager_native', 'final String? imgPath: $e');
        }
      }

      if (!data.hideMarkAsRead) {
        notifDict[DBusString('buttons')] = DBusVariant(
          DBusArray(DBusSignature('a{sv}'), [
            DBusDict(DBusSignature('s'), DBusSignature('v'), {
              DBusString('label'): DBusVariant(DBusString(TrStrings.lngContextMarkRead())),
              DBusString('action'): DBusVariant(DBusString('app.notification-mark-as-read')),
              DBusString('target'): DBusVariant(DBusArray(DBusSignature('s'), [
                DBusString(data.accountId),
                DBusString(data.chatId),
                DBusString(data.messageId),
              ])),
            }),
          ]),
        );
      }

      await portalProxy.callMethod(
        'org.freedesktop.portal.Notification',
        'AddNotification',
        [
          DBusString(notifId),
          DBusDict(DBusSignature('s'), DBusSignature('v'), notifDict),
        ],
      );
      final contextKey = '${data.accountId}:${data.chatId}';
      _portalNotifData.putIfAbsent(contextKey, () => {})[notifId] = data;
      Debug.log('NOTIF', 'Flatpak portal notification sent: $title');
    } catch (e) {
      Debug.log('NOTIF', 'Flatpak portal notification failed: $e');
    }
  }

  Future<void> _closeNotification(int nativeId) async {
    try {
      await _notifProxy?.callMethod(
        'org.freedesktop.Notifications',
        'CloseNotification',
        [DBusUint32(nativeId)],
      );
    } catch (e) {
      Debug.log('notification_manager_native', 'await _notifProxy?.callMethod(: $e');
    }
  }

  Future<void> _removePortalNotification(String notifId) async {
    try {
      final dbus = _dbus;
      if (dbus == null) return;
      final portalProxy = DBusRemoteObject(
        dbus,
        name: 'org.freedesktop.portal.Desktop',
        path: DBusObjectPath('/org/freedesktop/portal/desktop'),
      );
      await portalProxy.callMethod(
        'org.freedesktop.portal.Notification',
        'RemoveNotification',
        [DBusString(notifId)],
      );
    } catch (e) {
      Debug.log('notification_manager_native', 'final dbus = _dbus: $e');
    }
  }

  @override
  void clearForChat(String accountId, String chatId) {
    final contextKey = '$accountId:$chatId';
    final ids = _notifications[contextKey];
    if (ids != null) {
      for (final nativeId in ids.values) {
        _closeNotification(nativeId);
        _nativeIdToData.remove(nativeId);
      }
      _notifications.remove(contextKey);
    }
    final portalMap = _portalNotifData.remove(contextKey);
    if (portalMap != null) {
      for (final notifId in portalMap.keys) {
        _removePortalNotification(notifId);
      }
    }
  }

  @override
  void clearForItem(String accountId, String chatId, String messageId) {
    final contextKey = '$accountId:$chatId';
    final ids = _notifications[contextKey];
    if (ids != null) {
      final nativeId = ids.remove(messageId);
      if (nativeId != null) {
        _closeNotification(nativeId);
        _nativeIdToData.remove(nativeId);
      }
      if (ids.isEmpty) {
        _notifications.remove(contextKey);
      }
    }
    final portalMap = _portalNotifData[contextKey];
    if (portalMap != null) {
      final portalNotifId = '${accountId}_${chatId}_$messageId';
      if (portalMap.remove(portalNotifId) != null) {
        _removePortalNotification(portalNotifId);
      }
      if (portalMap.isEmpty) _portalNotifData.remove(contextKey);
    }
  }

  @override
  void clearForTopic(String accountId, String chatId, String topicRootId) {
    final contextKey = '$accountId:$chatId';
    final ids = _notifications[contextKey];
    if (ids != null) {
      final toRemove = <String>[];
      for (final entry in ids.entries) {
        final data = _nativeIdToData[entry.value];
        if (data != null && data.isForumTopic && data.topicRootId == topicRootId) {
          _closeNotification(entry.value);
          _nativeIdToData.remove(entry.value);
          toRemove.add(entry.key);
        }
      }
      for (final key in toRemove) {
        ids.remove(key);
      }
      if (ids.isEmpty) _notifications.remove(contextKey);
    }
    final portalMap = _portalNotifData[contextKey];
    if (portalMap != null) {
      final portalToRemove = <String>[];
      for (final entry in portalMap.entries) {
        if (entry.value.isForumTopic && entry.value.topicRootId == topicRootId) {
          portalToRemove.add(entry.key);
        }
      }
      for (final id in portalToRemove) {
        portalMap.remove(id);
        _removePortalNotification(id);
      }
      if (portalMap.isEmpty) _portalNotifData.remove(contextKey);
    }
  }

  @override
  void clearForSublist(String accountId, String chatId, String sublistPeerId) {
    final contextKey = '$accountId:$chatId';
    final ids = _notifications[contextKey];
    if (ids != null) {
      final toRemove = <String>[];
      for (final entry in ids.entries) {
        final data = _nativeIdToData[entry.value];
        if (data != null && data.isMonoforumSublist && data.sublistPeerId == sublistPeerId) {
          _closeNotification(entry.value);
          _nativeIdToData.remove(entry.value);
          toRemove.add(entry.key);
        }
      }
      for (final key in toRemove) {
        ids.remove(key);
      }
      if (ids.isEmpty) _notifications.remove(contextKey);
    }
    final portalMap = _portalNotifData[contextKey];
    if (portalMap != null) {
      final portalToRemove = <String>[];
      for (final entry in portalMap.entries) {
        if (entry.value.isMonoforumSublist && entry.value.sublistPeerId == sublistPeerId) {
          portalToRemove.add(entry.key);
        }
      }
      for (final id in portalToRemove) {
        portalMap.remove(id);
        _removePortalNotification(id);
      }
      if (portalMap.isEmpty) _portalNotifData.remove(contextKey);
    }
  }

  @override
  void clearForAccount(String accountId) {
    final toRemove = <String>[];
    for (final entry in _notifications.entries) {
      if (entry.key.startsWith('$accountId:')) {
        for (final nativeId in entry.value.values) {
          _closeNotification(nativeId);
          _nativeIdToData.remove(nativeId);
        }
        toRemove.add(entry.key);
      }
    }
    for (final key in toRemove) {
      _notifications.remove(key);
    }
    final portalToRemove = <String>[];
    for (final entry in _portalNotifData.entries) {
      if (entry.key.startsWith('$accountId:')) {
        for (final notifId in entry.value.keys) {
          _removePortalNotification(notifId);
        }
        portalToRemove.add(entry.key);
      }
    }
    for (final key in portalToRemove) {
      _portalNotifData.remove(key);
    }
  }

  @override
  void clearAll() {
    for (final contextMap in _notifications.values) {
      for (final nativeId in contextMap.values) {
        _closeNotification(nativeId);
      }
    }
    _notifications.clear();
    _nativeIdToData.clear();
    for (final map in _portalNotifData.values) {
      for (final notifId in map.keys) {
        _removePortalNotification(notifId);
      }
    }
    _portalNotifData.clear();
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    _closedSub?.cancel();
    _replySub?.cancel();
    _activationTokenSub?.cancel();
    _serviceWatcherSub?.cancel();
    _portalActionSub?.cancel();
    clearAll();
    _userpicCache.dispose();
    for (final path in _soundCache.values) {
      try {
        File(path).deleteSync();
      } catch (e) {
        Debug.log('notification_manager_native', 'File(path).deleteSync(): $e');
      }
    }
    _soundCache.clear();
    _dbus?.close();
    _dbus = null;
    _notifProxy = null;
    _ready = false;
  }
}
