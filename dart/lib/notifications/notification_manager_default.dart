import 'dart:async';
import 'dart:collection';

import 'notification_manager.dart';
import 'notification_types.dart';

typedef NotificationTapCallback = void Function(
    String accountId, String chatId);
typedef NotificationDisplayCallback = void Function(
    DefaultNotificationItem item);
typedef NotificationDismissCallback = void Function(String id);
typedef NotificationStartHidingCallback = void Function(String id);
typedef NotificationUpdateDisplayCallback = void Function(
    DefaultNotificationItem item);

class DefaultNotificationItem {
  final String id;
  NotificationData data;
  final DateTime shownAt;
  bool waitingForInput;

  DefaultNotificationItem({
    required this.id,
    required this.data,
    required this.shownAt,
    this.waitingForInput = true,
  });
}

const _dismissDuration = Duration(milliseconds: 3000);
const _inputCheckInterval = Duration(milliseconds: 300);

class DefaultManager extends NotificationManager {
  @override
  ManagerType get type => ManagerType.defaultPopup;

  final List<DefaultNotificationItem> _active = [];
  final Queue<DefaultNotificationItem> _queue = Queue();
  final Map<String, Timer> _dismissTimers = {};
  Timer? _inputCheckTimer;
  DateTime _lastUserInputTime = DateTime.now();
  int _nextId = 0;
  int _maxVisible = 3;
  NotificationCorner _corner = NotificationCorner.bottomRight;
  bool _lastInputTimeSupported = false;

  NotificationTapCallback? onTap;
  NotificationDisplayCallback? onShow;
  NotificationDismissCallback? onDismiss;
  NotificationStartHidingCallback? onStartHiding;
  NotificationUpdateDisplayCallback? onUpdateDisplay;
  VoidCallbackNoArgs? onHideAllChanged;
  bool Function(String id)? isStickyCheck;

  List<DefaultNotificationItem> get activeNotifications =>
      List.unmodifiable(_active);

  bool get hasQueue => _queue.isNotEmpty;

  bool get showHideAll => _active.length >= 2 || _queue.isNotEmpty;

  NotificationCorner get corner => _corner;

  void onUserInput() {
    _lastInputTimeSupported = true;
    _lastUserInputTime = DateTime.now();
  }

  @override
  void showNotification(NotificationData data, NotificationSettings settings) {
    _maxVisible = settings.maxNotificationCount.clamp(1, 5);
    _corner = settings.corner;

    final item = DefaultNotificationItem(
      id: 'notif_${_nextId++}',
      data: data,
      shownAt: DateTime.now(),
    );

    if (_active.length >= _maxVisible) {
      _queue.addLast(item);
      onHideAllChanged?.call();
      return;
    }

    _displayItem(item);
  }

  void _displayItem(DefaultNotificationItem item) {
    _active.add(item);
    onShow?.call(item);
    onHideAllChanged?.call();
    _checkLastInput();
  }

  void _checkLastInput() {
    final hasReplying =
        _active.any((n) => isStickyCheck != null && isStickyCheck!(n.id));

    if (!_lastInputTimeSupported) {
      for (final item in _active) {
        if (!item.waitingForInput) continue;
        item.waitingForInput = false;
        if (!hasReplying) {
          _startDismissTimer(item.id);
        }
      }
      return;
    }

    var anyWaiting = false;
    for (final item in _active) {
      if (!item.waitingForInput) continue;
      if (_lastUserInputTime.isAfter(item.shownAt)) {
        item.waitingForInput = false;
        if (!hasReplying) {
          _startDismissTimer(item.id);
        }
      } else {
        anyWaiting = true;
      }
    }

    if (anyWaiting) {
      _inputCheckTimer?.cancel();
      _inputCheckTimer = Timer(_inputCheckInterval, _checkLastInput);
    }
  }

  void _startDismissTimer(String id) {
    _dismissTimers[id]?.cancel();
    _dismissTimers[id] = Timer(_dismissDuration, () {
      _dismissTimers.remove(id);
      onStartHiding?.call(id);
    });
  }

  void dismiss(String id) {
    _dismissTimers[id]?.cancel();
    _dismissTimers.remove(id);
    _active.removeWhere((n) => n.id == id);
    onDismiss?.call(id);

    if (_queue.isNotEmpty && _active.length < _maxVisible) {
      _displayItem(_queue.removeFirst());
    }
    onHideAllChanged?.call();
  }

  void startAllHiding() {
    final hasReplying =
        _active.any((n) => isStickyCheck != null && isStickyCheck!(n.id));
    if (hasReplying) return;
    for (final item in _active) {
      if (!_dismissTimers.containsKey(item.id)) {
        _startDismissTimer(item.id);
      }
    }
  }

  void stopAllHiding() {
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
  }

  void hideAll() {
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    final ids = _active.map((n) => n.id).toList();
    _active.clear();
    _queue.clear();
    for (final id in ids) {
      onStartHiding?.call(id);
    }
    Timer(const Duration(milliseconds: 150), () {
      for (final id in ids) {
        onDismiss?.call(id);
      }
    });
    onHideAllChanged?.call();
  }

  @override
  void clearForChat(String accountId, String chatId) {
    final toRemove = _active
        .where(
            (n) => n.data.accountId == accountId && n.data.chatId == chatId)
        .map((n) => n.id)
        .toList();
    for (final id in toRemove) {
      dismiss(id);
    }
    _queue.removeWhere(
        (n) => n.data.accountId == accountId && n.data.chatId == chatId);
  }

  @override
  void clearForItem(String accountId, String chatId, String messageId) {
    final toRemove = _active
        .where((n) =>
            n.data.accountId == accountId &&
            n.data.chatId == chatId &&
            n.data.messageId == messageId)
        .map((n) => n.id)
        .toList();
    for (final id in toRemove) {
      dismiss(id);
    }
    _queue.removeWhere((n) =>
        n.data.accountId == accountId &&
        n.data.chatId == chatId &&
        n.data.messageId == messageId);
  }

  @override
  void clearForTopic(String accountId, String chatId, String topicRootId) {
    final toRemove = _active
        .where((n) =>
            n.data.accountId == accountId &&
            n.data.chatId == chatId &&
            n.data.isForumTopic &&
            n.data.topicRootId == topicRootId)
        .map((n) => n.id)
        .toList();
    for (final id in toRemove) {
      dismiss(id);
    }
    _queue.removeWhere((n) =>
        n.data.accountId == accountId &&
        n.data.chatId == chatId &&
        n.data.isForumTopic &&
        n.data.topicRootId == topicRootId);
  }

  @override
  void clearForSublist(String accountId, String chatId, String sublistPeerId) {
    final toRemove = _active
        .where((n) =>
            n.data.accountId == accountId &&
            n.data.chatId == chatId &&
            n.data.isMonoforumSublist &&
            n.data.sublistPeerId == sublistPeerId)
        .map((n) => n.id)
        .toList();
    for (final id in toRemove) {
      dismiss(id);
    }
    _queue.removeWhere((n) =>
        n.data.accountId == accountId &&
        n.data.chatId == chatId &&
        n.data.isMonoforumSublist &&
        n.data.sublistPeerId == sublistPeerId);
  }

  @override
  void clearForAccount(String accountId) {
    final toRemove = _active
        .where((n) => n.data.accountId == accountId)
        .map((n) => n.id)
        .toList();
    for (final id in toRemove) {
      dismiss(id);
    }
    _queue.removeWhere((n) => n.data.accountId == accountId);
  }

  @override
  void updateAll() {
    for (final item in _active) {
      onUpdateDisplay?.call(item);
    }
  }

  void updateAvatar(String notifId, String newPath) {
    final item = _active.where((n) => n.id == notifId).firstOrNull;
    if (item == null) return;
    item.data = item.data.copyWith(avatarPath: newPath);
    onUpdateDisplay?.call(item);
  }

  void updateAvatarForPeer(String accountId, String chatId, String newPath) {
    for (final item in _active) {
      if (item.data.accountId == accountId && item.data.chatId == chatId) {
        item.data = item.data.copyWith(avatarPath: newPath);
        onUpdateDisplay?.call(item);
      }
    }
  }

  @override
  void clearAll() => hideAll();

  @override
  void clearAllFast() {
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    _inputCheckTimer?.cancel();
    final ids = _active.map((n) => n.id).toList();
    _active.clear();
    _queue.clear();
    for (final id in ids) {
      onDismiss?.call(id);
    }
    onHideAllChanged?.call();
  }

  @override
  void updateSettings(NotificationSettings settings) {
    _maxVisible = settings.maxNotificationCount.clamp(1, 5);
    _corner = settings.corner;

    while (_active.length > _maxVisible) {
      final excess = _active.first;
      dismiss(excess.id);
    }

    while (_queue.isNotEmpty && _active.length < _maxVisible) {
      _displayItem(_queue.removeFirst());
    }
    onHideAllChanged?.call();
  }

  @override
  void dispose() {
    _inputCheckTimer?.cancel();
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    _active.clear();
    _queue.clear();
  }
}

typedef VoidCallbackNoArgs = void Function();
