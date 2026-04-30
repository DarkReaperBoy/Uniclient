import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'notification_manager.dart';
import 'notification_types.dart';

bool nativeNotificationsSupported() {
  if (kIsWeb) return false;
  return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
}

class NativeManager extends NotificationManager {
  @override
  ManagerType get type => ManagerType.native;

  final Map<String, Map<String, int>> _notifications = {};
  int _nextNativeId = 1;

  @override
  void showNotification(NotificationData data, NotificationSettings settings) {
    final contextKey = '${data.accountId}:${data.chatId}';
    _notifications.putIfAbsent(contextKey, () => {});
    _notifications[contextKey]![data.messageId] = _nextNativeId++;

    // Platform-specific delivery will be implemented in §37.2 items
    // (Linux DBus, Windows WinRT, macOS NSUserNotification).
    // For now this tracks the notification but does not deliver it.
  }

  @override
  void clearForChat(String accountId, String chatId) {
    final contextKey = '$accountId:$chatId';
    _notifications.remove(contextKey);
  }

  @override
  void clearForAccount(String accountId) {
    _notifications
        .removeWhere((key, _) => key.startsWith('$accountId:'));
  }

  @override
  void clearAll() {
    _notifications.clear();
  }

  @override
  void dispose() {
    _notifications.clear();
  }
}
