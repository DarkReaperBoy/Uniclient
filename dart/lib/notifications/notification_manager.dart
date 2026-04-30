import 'notification_types.dart';

abstract class NotificationManager {
  ManagerType get type;

  void showNotification(NotificationData data, NotificationSettings settings);

  void clearForChat(String accountId, String chatId);

  void clearForAccount(String accountId);

  void clearAll();

  void updateSettings(NotificationSettings settings) {}

  void dispose() {}
}

class DummyManager extends NotificationManager {
  @override
  ManagerType get type => ManagerType.dummy;

  @override
  void showNotification(NotificationData data, NotificationSettings settings) {}

  @override
  void clearForChat(String accountId, String chatId) {}

  @override
  void clearForAccount(String accountId) {}

  @override
  void clearAll() {}
}
