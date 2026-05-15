import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../l10n/strings.dart';
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

class _AccountSessionState {
  bool isOnline = true;
  int otherOnlineAt = 0;
  int lastSetOnlineAt = 0;
}

class _DndChecker {
  bool _inhibited = false;
  DBusClient? _dbus;
  Timer? _pollTimer;

  bool get isActive => _inhibited;

  void init() {
    if (kIsWeb || !Platform.isLinux) return;
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      _dbus ??= DBusClient.session();
      final proxy = DBusRemoteObject(
        _dbus!,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );
      final val = await proxy.getProperty(
        'org.freedesktop.Notifications',
        'Inhibited',
        signature: DBusSignature('b'),
      );
      _inhibited = val.asBoolean();
    } catch (_) {
      _inhibited = false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _dbus?.close();
    _dbus = null;
  }
}

class NotificationSystem {
  NotificationManager _manager = DummyManager();
  NotificationSettings _settings = const NotificationSettings();
  final NotificationSoundPlayer _soundPlayer = NotificationSoundPlayer();
  final _DndChecker _dndChecker = _DndChecker();

  bool _passcodeLocked = false;
  bool get passcodeLocked => _passcodeLocked;
  set passcodeLocked(bool value) => _passcodeLocked = value;

  String _activeAccountId = '';
  String get activeAccountId => _activeAccountId;
  set activeAccountId(String value) => _activeAccountId = value;

  void Function()? onFlashBounce;

  static const _kMinimalDelay = Duration(milliseconds: 100);
  static const _kMinimalForwardDelay = Duration(milliseconds: 500);
  static const _kMinimalAlertDelay = Duration(milliseconds: 500);
  static const _kWaitingForAllGroupedDelay = Duration(milliseconds: 1000);
  static const _kReactionNotificationEach = Duration(hours: 1);
  Duration _cloudDelay = const Duration(seconds: 30);
  Duration _defaultDelay = const Duration(milliseconds: 1500);
  int _onlineCloudTimeoutSec = 300;

  // §37.6.3 dedup: threadKey → { (messageId, type) → lastTime }
  final Map<String, Map<_NotificationKey, DateTime>> _whenMaps = {};

  // §37.6.1 sound/flash alert cooldown per thread
  final Map<String, DateTime> _lastAlertPerThread = {};

  // §37.6.2 forward/album grouping buffer
  Timer? _groupedTimer;
  final List<NotificationData> _groupedBuffer = [];

  // Pending dispatch timers (cancellable on dispose)
  final List<Timer> _pendingTimers = [];

  // Per-account session state for cross-device dedup
  final Map<String, _AccountSessionState> _accountStates = {};

  // Notifications waiting for mute state resolution, keyed by 'accountId:chatId'
  final Map<String, NotificationData> _settingWaiters = {};

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
    _dndChecker.init();
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

  void updateAll() {
    _manager.updateAll();
  }

  void setServerConfig({
    int? cloudDelayMs,
    int? defaultDelayMs,
    int? onlineCloudTimeoutSec,
  }) {
    if (cloudDelayMs != null) _cloudDelay = Duration(milliseconds: cloudDelayMs);
    if (defaultDelayMs != null) _defaultDelay = Duration(milliseconds: defaultDelayMs);
    if (onlineCloudTimeoutSec != null) _onlineCloudTimeoutSec = onlineCloudTimeoutSec;
  }

  void updateSessionState({
    required String accountId,
    required bool isOnline,
    int otherOnlineAt = 0,
    int lastSetOnlineAt = 0,
  }) {
    final state =
        _accountStates.putIfAbsent(accountId, () => _AccountSessionState());
    state.isOnline = isOnline;
    state.otherOnlineAt = otherOnlineAt;
    state.lastSetOnlineAt = lastSetOnlineAt;
  }

  void _selectManager() {
    final wantNative =
        _settings.useNativeNotifications && !_settings.forceCustomNotifications;

    ManagerType targetType;
    if (wantNative && nativeNotificationsSupported()) {
      targetType = ManagerType.native;
    } else if (wantNative && !nativeNotificationsSupported()) {
      targetType = ManagerType.defaultPopup;
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
    if (data.isHidden) return;
    if (data.isOutgoing && !data.isScheduled) return;

    if (!_shouldNotifyForType(data)) return;

    // §37.7: Muted chat handling
    var effectiveData = data;
    if (data.isMuted) {
      if (data.isScheduled && data.isOutgoing) {
        effectiveData = data.copyWith(isSilent: true);
      } else if (!data.isSenderMuted) {
        // Sender NOT muted in muted group (e.g. mention): show with sound
      } else {
        return;
      }
    }

    // §37.7: Force silent for reactions/poll votes
    if (effectiveData.isReaction || effectiveData.isPollVote) {
      effectiveData = effectiveData.copyWith(isSilent: true);
    }

    if (!_passesDedup(effectiveData)) return;

    // Buffer notifications with unknown mute state for later processing
    if (effectiveData.muteStateUnknown) {
      final key = '${effectiveData.accountId}:${effectiveData.chatId}';
      _settingWaiters.putIfAbsent(key, () => effectiveData);
      return;
    }

    if (_isGroupable(effectiveData)) {
      _addToGroupBuffer(effectiveData);
      return;
    }

    final delay = _countTiming(effectiveData);
    _scheduleDispatch(effectiveData, delay);
  }

  bool _shouldNotifyForType(NotificationData data) {
    if (!_settings.notifyFromAll &&
        _activeAccountId.isNotEmpty &&
        data.accountId != _activeAccountId) {
      return false;
    }
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
    Duration delay = _kMinimalDelay;

    if (data.forwardFrom.isNotEmpty) {
      if (delay < _kMinimalForwardDelay) delay = _kMinimalForwardDelay;
    }

    if (!_settings.disableNotificationsDelay) {
      final state = _accountStates[data.accountId];
      if (state != null) {
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final otherNotOld =
            state.otherOnlineAt + _onlineCloudTimeoutSec > nowSec;
        final otherLaterThanMe = state.otherOnlineAt * 1000 +
                (DateTime.now().millisecondsSinceEpoch -
                    state.lastSetOnlineAt) >
            nowSec * 1000;

        if (!state.isOnline && otherNotOld && otherLaterThanMe) {
          delay = _cloudDelay;
        } else if (state.otherOnlineAt >= nowSec) {
          delay = _defaultDelay;
        }
      }
    }

    if (_settings.disableNotificationsDelay) {
      delay = _kMinimalDelay;
      if (data.forwardFrom.isNotEmpty && delay < _kMinimalForwardDelay) {
        delay = _kMinimalForwardDelay;
      }
    }

    return delay;
  }

  void _scheduleDispatch(NotificationData data, Duration delay) {
    if (delay <= Duration.zero) {
      _dispatch(data);
      return;
    }
    late final Timer timer;
    timer = Timer(delay, () {
      _pendingTimers.remove(timer);
      _dispatch(data);
    });
    _pendingTimers.add(timer);
  }

  bool _isSameGroup(NotificationData a, NotificationData b) {
    if (a.accountId != b.accountId || a.chatId != b.chatId) return false;
    if (a.groupedId.isNotEmpty && b.groupedId.isNotEmpty) {
      return a.groupedId == b.groupedId;
    }
    if (a.forwardFrom.isNotEmpty && b.forwardFrom.isNotEmpty) {
      return a.senderId == b.senderId &&
          (a.timestamp - b.timestamp).abs() <= 2;
    }
    return false;
  }

  void _addToGroupBuffer(NotificationData data) {
    if (_groupedTimer != null && _groupedTimer!.isActive) {
      _groupedTimer!.cancel();
      if (_groupedBuffer.isNotEmpty && !_isSameGroup(_groupedBuffer.last, data)) {
        _flushGroupedBuffer();
      }
    }
    _groupedBuffer.add(data);
    _groupedTimer =
        Timer(_kWaitingForAllGroupedDelay, _flushGroupedBuffer);
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
          final fwdKey = n.senderId;
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
          _dispatch(group.last.copyWith(text: TrStrings.lngInDlgAlbum()));
        }
      }

      for (final group in forwardGroups.values) {
        if (group.length == 1) {
          _dispatch(group.first);
        } else {
          _dispatch(group.first.copyWith(
            text: TrStrings.lngForwardMessages(group.length),
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
    // §37.12: Apply privacy levels — passcode-locked forces HideAll
    var effectiveSettings = _settings;
    if (_passcodeLocked) {
      effectiveSettings = _settings.copyWith(
        previewName: false,
        previewText: false,
      );
    }

    final content = composeNotificationContent(data, effectiveSettings);
    final forceHideDetails = !effectiveSettings.previewName && !effectiveSettings.previewText;
    final display = data.copyWith(
      chatTitle: content.title,
      subtitle: content.subtitle,
      text: content.body,
      avatarPath: forceHideDetails ? '' : data.avatarPath,
    );

    final dnd = _dndChecker.isActive;

    if (_manager is DefaultManager && dnd) {
      Debug.log('NOTIF', 'DND active, skipping custom toast');
    } else {
      _manager.showNotification(display, effectiveSettings);
    }

    final forceSilent = data.isSilent || data.soundNone || dnd;

    final threadKey = '${data.accountId}:${data.chatId}';
    final now = DateTime.now();
    final lastAlert = _lastAlertPerThread[threadKey];
    final alertAllowed =
        lastAlert == null || now.difference(lastAlert) >= _kMinimalAlertDelay;

    if (!_manager.handlesSound && alertAllowed && !forceSilent) {
      _soundPlayer.play(settings: _settings, data: data);
      _lastAlertPerThread[threadKey] = now;
    }

    if (_settings.flashBounce && !dnd && alertAllowed && !forceSilent) {
      onFlashBounce?.call();
    }

    Debug.log('NOTIF',
        'dispatched to ${_manager.type}: ${content.title}'
        '${forceSilent ? " (silent)" : ""}'
        '${dnd ? " (DND)" : ""}'
        '${_passcodeLocked ? " (locked)" : ""}');
  }

  void checkDelayed() {
    if (_settingWaiters.isEmpty) return;

    final promoted = <NotificationData>[];
    final toRemove = <String>[];
    for (final entry in _settingWaiters.entries) {
      final data = entry.value;
      if (data.muteStateUnknown) continue;
      toRemove.add(entry.key);
      if (data.isMuted && data.isSenderMuted) continue;
      promoted.add(data);
    }
    for (final key in toRemove) {
      _settingWaiters.remove(key);
    }

    for (final data in promoted) {
      if (_isGroupable(data)) {
        _addToGroupBuffer(data);
      } else {
        final delay = _countTiming(data);
        _scheduleDispatch(data, delay);
      }
    }
  }

  void resolveDelayedMuteState({
    required String accountId,
    required String chatId,
    required bool isMuted,
    bool isSenderMuted = true,
  }) {
    final key = '$accountId:$chatId';
    final data = _settingWaiters[key];
    if (data != null) {
      _settingWaiters[key] = data.copyWith(
        muteStateUnknown: false,
        isMuted: isMuted,
        isSenderMuted: isSenderMuted,
      );
    }
    checkDelayed();
  }

  void clearForChat(String accountId, String chatId) {
    _manager.clearForChat(accountId, chatId);
    _whenMaps.remove('$accountId:$chatId');
    _lastAlertPerThread.remove('$accountId:$chatId');
    _settingWaiters.remove('$accountId:$chatId');
    _groupedBuffer.removeWhere(
        (n) => n.accountId == accountId && n.chatId == chatId);
    if (_groupedBuffer.isEmpty) {
      _groupedTimer?.cancel();
      _groupedTimer = null;
    }
  }

  void clearIncomingFromChat(String accountId, String chatId) {
    _manager.clearForChat(accountId, chatId);
    _lastAlertPerThread.remove('$accountId:$chatId');
  }

  void clearIncomingFromTopic(
      String accountId, String chatId, String topicRootId) {
    _manager.clearForTopic(accountId, chatId, topicRootId);
    _lastAlertPerThread.remove('$accountId:$chatId:$topicRootId');
  }

  void clearIncomingFromSublist(
      String accountId, String chatId, String sublistPeerId) {
    _manager.clearForSublist(accountId, chatId, sublistPeerId);
    _lastAlertPerThread.remove('$accountId:$chatId:$sublistPeerId');
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
    _settingWaiters.clear();
  }

  void dispose() {
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    _groupedTimer?.cancel();
    _groupedBuffer.clear();
    _settingWaiters.clear();
    _whenMaps.clear();
    _lastAlertPerThread.clear();
    _accountStates.clear();
    _soundPlayer.dispose();
    _dndChecker.dispose();
    _manager.dispose();
  }
}
