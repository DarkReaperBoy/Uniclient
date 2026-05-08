import 'notification_types.dart';

abstract class NotificationManager {
  ManagerType get type;

  bool get handlesSound => false;

  void showNotification(NotificationData data, NotificationSettings settings);

  void clearForChat(String accountId, String chatId);

  void clearForItem(String accountId, String chatId, String messageId);

  void clearForTopic(String accountId, String chatId, String topicRootId);

  void clearForSublist(String accountId, String chatId, String sublistPeerId);

  void clearForAccount(String accountId);

  void clearAll();

  void updateAll() {}

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
  void clearForItem(String accountId, String chatId, String messageId) {}

  @override
  void clearForTopic(String accountId, String chatId, String topicRootId) {}

  @override
  void clearForSublist(String accountId, String chatId, String sublistPeerId) {}

  @override
  void clearForAccount(String accountId) {}

  @override
  void clearAll() {}
}
