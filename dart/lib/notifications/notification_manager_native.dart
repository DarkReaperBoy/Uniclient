import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;

import '../utils/debug.dart';
import 'notification_manager.dart';
import 'notification_types.dart';

typedef NotificationActionCallback = void Function(
    String accountId, String chatId, String action);
typedef NotificationReplyCallback = void Function(
    String accountId, String chatId, String messageId, String replyText);

bool nativeNotificationsSupported() {
  if (kIsWeb) return false;
  return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
}

class NativeManager extends NotificationManager {
  @override
  ManagerType get type => ManagerType.native;

  NotificationActionCallback? onAction;
  NotificationReplyCallback? onReply;

  final Map<String, Map<String, int>> _notifications = {};
  final Map<int, NotificationData> _nativeIdToData = {};

  DBusClient? _dbus;
  DBusRemoteObject? _notifProxy;
  Set<String> _capabilities = {};
  bool _inhibited = false;
  String _imageDataKey = 'image-data';
  bool _ready = false;

  StreamSubscription<DBusSignal>? _actionSub;
  StreamSubscription<DBusSignal>? _closedSub;
  StreamSubscription<DBusSignal>? _replySub;

  NativeManager() {
    if (!kIsWeb && Platform.isLinux) {
      _initLinuxDBus();
    }
  }

  Future<void> _initLinuxDBus() async {
    try {
      _dbus = DBusClient.session();
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
        if (specVersion.compareTo('1.1') >= 0) {
          _imageDataKey = 'image-data';
        } else if (specVersion.compareTo('1.0') >= 0) {
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

      _ready = true;
      Debug.log('NOTIF', 'Linux DBus backend initialized');
    } catch (e) {
      Debug.log('NOTIF', 'Linux DBus init failed: $e');
      _ready = false;
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
    if (signal.values.isEmpty) return;
    final nativeId = signal.values[0].asUint32();
    _removeNativeId(nativeId);
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
    if (!_ready || _notifProxy == null) return;

    final contextKey = '${data.accountId}:${data.chatId}';

    final actions = <DBusValue>[
      DBusString('default'),
      DBusString('Open'),
      DBusString('mail-mark-read'),
      DBusString('Mark as Read'),
    ];
    if (_capabilities.contains('inline-reply')) {
      actions.addAll([
        DBusString('inline-reply'),
        DBusString('Reply'),
      ]);
    }

    final hints = <DBusValue, DBusValue>{
      DBusString('category'): DBusVariant(DBusString('im.received')),
      DBusString('urgency'): DBusVariant(DBusByte(1)),
    };

    if (data.avatarPath.isNotEmpty) {
      final imageHint = await _buildImageHint(data.avatarPath);
      if (imageHint != null) {
        hints[DBusString(_imageDataKey)] = DBusVariant(imageHint);
      }
    }

    if (settings.allowSound &&
        !_inhibited &&
        _capabilities.contains('sound-file')) {
      hints[DBusString('suppress-sound')] = DBusVariant(DBusBoolean(false));
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
          DBusString(''),
          DBusString(
              data.chatTitle.isNotEmpty ? data.chatTitle : data.senderName),
          DBusString(_buildBody(data)),
          DBusArray(DBusSignature('s'), actions),
          DBusDict(DBusSignature('s'), DBusSignature('v'), hints),
          DBusInt32(5000),
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
    if (data.subtitle.isNotEmpty) {
      return '${data.subtitle}: ${data.text}';
    }
    return data.text;
  }

  Future<DBusStruct?> _buildImageHint(String avatarPath) async {
    try {
      final file = File(avatarPath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final resized = img.copyResize(image, width: 64, height: 64);
      final width = resized.width;
      final height = resized.height;
      final rowstride = width * 4;

      final rgbaBytes = <DBusValue>[];
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = resized.getPixel(x, y);
          rgbaBytes.add(DBusByte(pixel.r.toInt()));
          rgbaBytes.add(DBusByte(pixel.g.toInt()));
          rgbaBytes.add(DBusByte(pixel.b.toInt()));
          rgbaBytes.add(DBusByte(pixel.a.toInt()));
        }
      }

      return DBusStruct([
        DBusInt32(width),
        DBusInt32(height),
        DBusInt32(rowstride),
        DBusBoolean(true),
        DBusInt32(8),
        DBusInt32(4),
        DBusArray(DBusSignature('y'), rgbaBytes),
      ]);
    } catch (e) {
      Debug.log('NOTIF', 'Image hint build failed: $e');
      return null;
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
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    _closedSub?.cancel();
    _replySub?.cancel();
    clearAll();
    _dbus?.close();
    _dbus = null;
    _notifProxy = null;
    _ready = false;
  }
}
