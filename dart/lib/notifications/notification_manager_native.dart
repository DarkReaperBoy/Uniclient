import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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

      final resized = img.copyResize(image, width: _kPhotoSize, height: _kPhotoSize);
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

  Uint8List? getRawRgba(String key) {
    final existing = _cache[key];
    if (existing != null) {
      existing.lastUsed = DateTime.now();
      return existing.rawRgba;
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
        } catch (_) {}
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
      } catch (_) {}
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

  static String _getInitials(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '?';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return words[0][0].toUpperCase();
  }

  Future<String?> _generatePlaceholderUserpic(String title) async {
    try {
      final cacheKey = '__placeholder:$title';
      final existing = _userpicCache._cache[cacheKey];
      if (existing != null && File(existing.filePath).existsSync()) {
        existing.lastUsed = DateTime.now();
        return existing.filePath;
      }

      final cacheDir = p.join(Directory.systemTemp.path, 'uniclient_userpics');
      await Directory(cacheDir).create(recursive: true);

      // Telegram userpic gradient pairs (color1 top → color2 bottom), from
      // lib_ui/ui/colors.palette (historyPeerN UserpicBg / UserpicBg2).
      const gradients = [
        [[0xff, 0x84, 0x5e], [0xd4, 0x52, 0x46]], // 0 red
        [[0x9a, 0xd1, 0x64], [0x46, 0xba, 0x43]], // 1 green
        [[0xe5, 0xca, 0x77], [0xe5, 0xca, 0x77]], // 2 yellow (unused)
        [[0x5c, 0xaf, 0xfa], [0x40, 0x8a, 0xcf]], // 3 blue
        [[0xb6, 0x94, 0xf9], [0x6c, 0x61, 0xdf]], // 4 purple
        [[0xff, 0x8a, 0xac], [0xd9, 0x55, 0x74]], // 5 pink
        [[0x5b, 0xcb, 0xe3], [0x35, 0x9a, 0xd4]], // 6 sea
        [[0xfe, 0xbb, 0x5b], [0xf6, 0x81, 0x36]], // 7 orange
      ];
      // Name → colour index → palette index, matching EmptyUserpic's
      // ColorIndexToPaletteIndex (chat_style.cpp:1205) over the 7 simple
      // colours (kSimpleColorIndexCount). The notification layer only has a
      // name, not the peer id, so we hash the title to pick the gradient.
      const paletteMap = [0, 7, 4, 1, 6, 3, 5];
      final pair = gradients[paletteMap[title.hashCode.abs() % 7]];
      final top = pair[0];
      final bottom = pair[1];

      const size = 64;
      final image = img.Image(width: size, height: size, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
      // Draw a circular userpic (EmptyUserpic::paintCircle) with a vertical
      // gradient and an anti-aliased edge — transparent corners — instead of
      // the old opaque flat-filled square.
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

      final initials = _getInitials(title);
      final font = img.arial24;
      int textW = 0;
      for (final cu in initials.codeUnits) {
        final ch = font.characters[cu];
        if (ch != null) textW += ch.xAdvance;
      }
      final x = (size - textW) ~/ 2;
      final y = (size - font.lineHeight) ~/ 2;
      img.drawString(image, initials,
          font: font, x: x, y: y,
          color: img.ColorRgba8(255, 255, 255, 255));

      final rawRgba = image.toUint8List();
      final outPath = p.join(cacheDir, 'placeholder_${_randomFileId()}.png');
      await File(outPath).writeAsBytes(Uint8List.fromList(img.encodePng(image)));

      _userpicCache._cache[cacheKey] = _CachedUserpic(
        filePath: outPath,
        rawRgba: rawRgba,
        lastUsed: DateTime.now(),
      );
      _userpicCache._ensureCleanupTimer();

      return outPath;
    } catch (e) {
      Debug.log('NOTIF', 'Placeholder userpic generation failed: $e');
      return null;
    }
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
    } catch (_) {}

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
      if (data.avatarPath.isNotEmpty) {
        await _userpicCache.get(data.avatarPath);
        rawRgba = _userpicCache.getRawRgba(data.avatarPath);
      } else {
        final title = data.chatTitle.isNotEmpty ? data.chatTitle : data.senderName;
        await _generatePlaceholderUserpic(title);
        rawRgba = _userpicCache.getRawRgba('__placeholder:$title');
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
        } catch (_) {}
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
      final parts = notifId.split('_');
      if (parts.length < 3) return;
      final accountId = parts[0];
      final chatId = parts[1];
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
      if (!forceHideDetails && data.avatarPath.isNotEmpty) {
        try {
          final imgPath = await _userpicCache.get(data.avatarPath);
          if (imgPath != null) {
            final pngBytes = await File(imgPath).readAsBytes();
            notifDict[DBusString('icon')] = DBusVariant(
              DBusStruct([
                DBusString('bytes'),
                DBusVariant(DBusArray.byte(pngBytes)),
              ]),
            );
          }
        } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
      } catch (_) {}
    }
    _soundCache.clear();
    _dbus?.close();
    _dbus = null;
    _notifProxy = null;
    _ready = false;
  }
}
