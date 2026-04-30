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

enum _ItemNotificationType { message, reaction, pollVote }

class _NotificationKey {
  final String messageId;
  final _ItemNotificationType type;

  const _NotificationKey(this.messageId, this.type);

  @override
  bool operator ==(Object other) =>
      other is _NotificationKey &&
      other.messageId == messageId &&
      other.type == type;

  @override
  int get hashCode => Object.hash(messageId, type);
}

class NotificationSystem {
  NotificationManager _manager = DummyManager();
  NotificationSettings _settings = const NotificationSettings();
  final NotificationSoundPlayer _soundPlayer = NotificationSoundPlayer();

  // §37.6.1 timing constants
  static const _kMinimalDelay = Duration(milliseconds: 100);
  static const _kMinimalForwardDelay = Duration(milliseconds: 500);
  static const _kMinimalAlertDelay = Duration(milliseconds: 500);
  static const _kWaitingForAllGroupedDelay = Duration(milliseconds: 1000);
  static const _kReactionNotificationEach = Duration(hours: 1);

  // §37.6.3 dedup: threadKey → { (messageId, type) → lastTime }
  final Map<String, Map<_NotificationKey, DateTime>> _whenMaps = {};

  // §37.6.1 sound/flash alert cooldown per thread
  final Map<String, DateTime> _lastAlertPerThread = {};

  // §37.6.2 forward/album grouping buffer
  Timer? _groupedTimer;
  final List<NotificationData> _groupedBuffer = [];

  // §37.6.1 delayed dispatch for non-grouped messages
  final List<Timer> _delayTimers = [];

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

    if (!_passesDedup(data)) return;

    if (_isGroupable(data)) {
      _groupedBuffer.add(data);
      _groupedTimer?.cancel();
      _groupedTimer =
          Timer(_kWaitingForAllGroupedDelay, _flushGroupedBuffer);
      return;
    }

    final delay = _countTiming(data);
    _scheduleDispatch(data, delay);
  }

  bool _shouldNotifyForType(NotificationData data) {
    if (data.isReaction || data.isPollVote) return _settings.reactionsNotify;
    if (data.isChannel) return _settings.channelsNotify;
    if (data.isGroup) return _settings.groupsNotify;
    return _settings.privateChatsNotify;
  }

  _ItemNotificationType _notifType(NotificationData data) {
    if (data.isReaction) return _ItemNotificationType.reaction;
    if (data.isPollVote) return _ItemNotificationType.pollVote;
    return _ItemNotificationType.message;
  }

  bool _passesDedup(NotificationData data) {
    if (data.messageId.isEmpty) return true;

    final threadKey = '${data.accountId}:${data.chatId}';
    final key = _NotificationKey(data.messageId, _notifType(data));
    final now = DateTime.now();

    final threadMap = _whenMaps.putIfAbsent(threadKey, () => {});
    final lastTime = threadMap[key];

    if (lastTime != null) {
      if (key.type == _ItemNotificationType.reaction ||
          key.type == _ItemNotificationType.pollVote) {
        if (now.difference(lastTime) < _kReactionNotificationEach) {
          return false;
        }
      } else {
        return false;
      }
    }

    threadMap[key] = now;

    if (threadMap.length > 500) {
      final cutoff = now.subtract(const Duration(hours: 2));
      threadMap.removeWhere((_, t) => t.isBefore(cutoff));
    }

    return true;
  }

  bool _isGroupable(NotificationData data) {
    if (data.groupedId.isNotEmpty) return true;
    if (data.forwardFrom.isNotEmpty && data.forwardCount <= 1) return true;
    return false;
  }

  Duration _countTiming(NotificationData data) {
    if (_settings.disableNotificationsDelay) return _kMinimalDelay;

    Duration delay = _kMinimalDelay;

    if (data.forwardFrom.isNotEmpty) {
      if (delay < _kMinimalForwardDelay) delay = _kMinimalForwardDelay;
    }

    return delay;
  }

  void _scheduleDispatch(NotificationData data, Duration delay) {
    if (delay <= Duration.zero) {
      _dispatch(data);
      return;
    }
    final timer = Timer(delay, () => _dispatch(data));
    _delayTimers.add(timer);
  }

  void _flushGroupedBuffer() {
    if (_groupedBuffer.isEmpty) return;

    final byChat = <String, List<NotificationData>>{};
    for (final n in _groupedBuffer) {
      byChat.putIfAbsent('${n.accountId}:${n.chatId}', () => []).add(n);
    }
    _groupedBuffer.clear();

    for (final items in byChat.values) {
      final albumGroups = <String, List<NotificationData>>{};
      final forwardGroups = <String, List<NotificationData>>{};
      final ungrouped = <NotificationData>[];

      for (final n in items) {
        if (n.groupedId.isNotEmpty) {
          albumGroups.putIfAbsent(n.groupedId, () => []).add(n);
        } else if (n.forwardFrom.isNotEmpty && n.forwardCount <= 1) {
          final fwdKey = n.forwardFrom;
          final existing = forwardGroups[fwdKey];
          if (existing != null &&
              existing.isNotEmpty &&
              (n.timestamp - existing.last.timestamp).abs() <= 2) {
            existing.add(n);
          } else if (existing == null) {
            forwardGroups[fwdKey] = [n];
          } else {
            ungrouped.add(n);
          }
        } else {
          ungrouped.add(n);
        }
      }

      for (final group in albumGroups.values) {
        if (group.length == 1) {
          _dispatch(group.first);
        } else {
          _dispatch(group.first.copyWith(
            text: 'Album',
            forwardCount: 0,
          ));
        }
      }

      for (final group in forwardGroups.values) {
        if (group.length == 1) {
          _dispatch(group.first);
        } else {
          _dispatch(group.first.copyWith(
            text: '${group.length} forwarded messages',
            forwardCount: group.length,
          ));
        }
      }

      for (final n in ungrouped) {
        _dispatch(n);
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

    final threadKey = '${data.accountId}:${data.chatId}';
    final now = DateTime.now();
    final lastAlert = _lastAlertPerThread[threadKey];
    final alertAllowed =
        lastAlert == null || now.difference(lastAlert) >= _kMinimalAlertDelay;

    if (!_manager.handlesSound && alertAllowed) {
      _soundPlayer.play(settings: _settings, data: data);
      _lastAlertPerThread[threadKey] = now;
    }

    Debug.log('NOTIF',
        'dispatched to ${_manager.type}: ${content.title}');
  }

  void clearForChat(String accountId, String chatId) {
    _manager.clearForChat(accountId, chatId);
    _whenMaps.remove('$accountId:$chatId');
    _lastAlertPerThread.remove('$accountId:$chatId');
  }

  void clearForAccount(String accountId) {
    _manager.clearForAccount(accountId);
    _whenMaps.removeWhere((k, _) => k.startsWith('$accountId:'));
    _lastAlertPerThread.removeWhere((k, _) => k.startsWith('$accountId:'));
  }

  void clearAll() {
    _manager.clearAll();
    _whenMaps.clear();
    _lastAlertPerThread.clear();
  }

  void dispose() {
    _groupedTimer?.cancel();
    _groupedBuffer.clear();
    for (final t in _delayTimers) {
      t.cancel();
    }
    _delayTimers.clear();
    _whenMaps.clear();
    _lastAlertPerThread.clear();
    _soundPlayer.dispose();
    _manager.dispose();
  }
}
