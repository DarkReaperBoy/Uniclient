import 'dart:async';
import 'dart:collection';

import 'notification_manager.dart';
import 'notification_types.dart';

typedef NotificationTapCallback = void Function(
    String accountId, String chatId);
typedef NotificationDisplayCallback = void Function(
    DefaultNotificationItem item);
typedef NotificationDismissCallback = void Function(String id);

class DefaultNotificationItem {
  final String id;
  final NotificationData data;
  final DateTime shownAt;

  DefaultNotificationItem({
    required this.id,
    required this.data,
    required this.shownAt,
  });
}

class DefaultManager extends NotificationManager {
  @override
  ManagerType get type => ManagerType.defaultPopup;

  final List<DefaultNotificationItem> _active = [];
  final Queue<DefaultNotificationItem> _queue = Queue();
  final Map<String, Timer> _dismissTimers = {};
  int _nextId = 0;
  int _maxVisible = 3;
  NotificationCorner _corner = NotificationCorner.bottomRight;

  NotificationTapCallback? onTap;
  NotificationDisplayCallback? onShow;
  NotificationDismissCallback? onDismiss;
  VoidCallbackNoArgs? onHideAllChanged;

  List<DefaultNotificationItem> get activeNotifications =>
      List.unmodifiable(_active);

  bool get hasQueue => _queue.isNotEmpty;

  bool get showHideAll => _active.length >= 2 || _queue.isNotEmpty;

  NotificationCorner get corner => _corner;

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

    _dismissTimers[item.id] = Timer(const Duration(seconds: 5), () {
      dismiss(item.id);
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

  void pauseDismissTimer(String id) {
    _dismissTimers[id]?.cancel();
  }

  void resumeDismissTimer(String id) {
    _dismissTimers[id] = Timer(const Duration(seconds: 5), () {
      dismiss(id);
    });
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
      onDismiss?.call(id);
    }
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
  void clearAll() => hideAll();

  @override
  void updateSettings(NotificationSettings settings) {
    _maxVisible = settings.maxNotificationCount.clamp(1, 5);
    _corner = settings.corner;
  }

  @override
  void dispose() {
    for (final t in _dismissTimers.values) {
      t.cancel();
    }
    _dismissTimers.clear();
    _active.clear();
    _queue.clear();
  }
}

typedef VoidCallbackNoArgs = void Function();
