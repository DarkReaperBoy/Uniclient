import 'dart:async';

import '../utils/debug.dart';
import 'notification_manager.dart';
import 'notification_manager_default.dart';
import 'notification_manager_native.dart';
import 'notification_sound.dart';
import 'notification_types.dart';

export 'notification_types.dart';
export 'notification_manager.dart';
export 'notification_manager_default.dart';
export 'notification_manager_native.dart';
export 'notification_sound.dart';

class NotificationSystem {
  NotificationManager _manager = DummyManager();
  NotificationSettings _settings = const NotificationSettings();
  final NotificationSoundPlayer _soundPlayer = NotificationSoundPlayer();

  final Map<String, DateTime> _lastNotifPerChat = {};
  final List<DateTime> _recentNotifs = [];

  Timer? _albumGroupTimer;
  final List<NotificationData> _albumBuffer = [];

  static const _perChatCooldown = Duration(seconds: 5);
  static const _globalRateWindow = Duration(seconds: 5);
  static const _globalRateMax = 3;
  static const _albumGroupWindow = Duration(milliseconds: 1000);

  NotificationManager get manager => _manager;
  ManagerType get activeManagerType => _manager.type;
  NotificationSettings get settings => _settings;

  DefaultManager? get defaultManager =>
      _manager is DefaultManager ? _manager as DefaultManager : null;

  NativeManager? get nativeManager =>
      _manager is NativeManager ? _manager as NativeManager : null;

  NotificationSoundPlayer get soundPlayer => _soundPlayer;

  void init(NotificationSettings settings) {
    _settings = settings;
    _soundPlayer.init();
    _selectManager();
    _syncNativeSoundPath();
    Debug.log('NOTIF', 'system init, manager=${_manager.type}');
  }

  void updateSettings(NotificationSettings settings) {
    final oldType = _manager.type;
    _settings = settings;
    _selectManager();
    _manager.updateSettings(settings);
    if (oldType != _manager.type) {
      Debug.log(
          'NOTIF', 'manager switched: $oldType → ${_manager.type}');
    }
  }

  void _selectManager() {
    final wantNative =
        _settings.useNativeNotifications && !_settings.forceCustomNotifications;

    ManagerType targetType;
    if (wantNative && nativeNotificationsSupported()) {
      targetType = ManagerType.native;
    } else if (wantNative && !nativeNotificationsSupported()) {
      targetType = ManagerType.dummy;
    } else {
      targetType = ManagerType.defaultPopup;
    }

    if (_manager.type == targetType) return;

    _manager.dispose();
    switch (targetType) {
      case ManagerType.native:
        _manager = NativeManager();
      case ManagerType.defaultPopup:
        _manager = DefaultManager();
      case ManagerType.dummy:
        _manager = DummyManager();
    }
    _syncNativeSoundPath();
  }

  void _syncNativeSoundPath() {
    final nm = nativeManager;
    if (nm != null) {
      nm.defaultSoundPath = _soundPlayer.defaultSoundPath ?? '';
    }
  }

  void onNewMessage(NotificationData data) {
    if (!_settings.desktopNotify) return;
    if (data.isOutgoing) return;

    if (!_shouldNotifyForType(data)) return;
    if (data.isMuted && !_settings.includeMutedChats) return;
    if (data.isSilent) return;

    if (!_passesRateLimit(data)) return;

    if (data.messageId.isNotEmpty) {
      _albumBuffer.add(data);
      _albumGroupTimer?.cancel();
      _albumGroupTimer = Timer(_albumGroupWindow, _flushAlbumBuffer);
    } else {
      _dispatch(data);
    }
  }

  bool _shouldNotifyForType(NotificationData data) {
    if (data.isChannel) return _settings.channelsNotify;
    if (data.isGroup) return _settings.groupsNotify;
    return _settings.privateChatsNotify;
  }

  bool _passesRateLimit(NotificationData data) {
    final chatKey = '${data.accountId}:${data.chatId}';
    final now = DateTime.now();

    final lastForChat = _lastNotifPerChat[chatKey];
    if (lastForChat != null && now.difference(lastForChat) < _perChatCooldown) {
      return false;
    }

    _recentNotifs.removeWhere((t) => now.difference(t) > _globalRateWindow);
    if (_recentNotifs.length >= _globalRateMax) return false;

    _lastNotifPerChat[chatKey] = now;
    _recentNotifs.add(now);
    return true;
  }

  void _flushAlbumBuffer() {
    if (_albumBuffer.isEmpty) return;

    final grouped = <String, List<NotificationData>>{};
    for (final n in _albumBuffer) {
      grouped.putIfAbsent('${n.accountId}:${n.chatId}', () => []).add(n);
    }
    _albumBuffer.clear();

    for (final entry in grouped.entries) {
      final items = entry.value;
      if (items.length == 1) {
        _dispatch(items.first);
      } else {
        final first = items.first;
        final allMedia = items.every((n) => n.messageType >= 1 && n.messageType <= 2);
        _dispatch(first.copyWith(
          text: allMedia ? 'Album' : '${items.length} new messages',
          isOutgoing: false,
        ));
      }
    }
  }

  void _dispatch(NotificationData data) {
    final content = composeNotificationContent(data, _settings);
    final display = data.copyWith(
      chatTitle: content.title,
      subtitle: content.subtitle,
      text: content.body,
      avatarPath: (!_settings.previewName && !_settings.previewText)
          ? ''
          : data.avatarPath,
    );
    _manager.showNotification(display, _settings);

    if (!_manager.handlesSound) {
      _soundPlayer.play(settings: _settings, data: data);
    }

    Debug.log('NOTIF',
        'dispatched to ${_manager.type}: ${content.title}');
  }

  void clearForChat(String accountId, String chatId) {
    _manager.clearForChat(accountId, chatId);
  }

  void clearForAccount(String accountId) {
    _manager.clearForAccount(accountId);
  }

  void clearAll() {
    _manager.clearAll();
  }

  void dispose() {
    _albumGroupTimer?.cancel();
    _albumBuffer.clear();
    _lastNotifPerChat.clear();
    _recentNotifs.clear();
    _soundPlayer.dispose();
    _manager.dispose();
  }
}
