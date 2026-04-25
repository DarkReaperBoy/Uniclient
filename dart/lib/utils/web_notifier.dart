import 'web_notifier_stub.dart'
    if (dart.library.js_interop) 'web_notifier_web.dart' as impl;

class WebNotifier {
  final impl.WebNotifierImpl _impl = impl.WebNotifierImpl();

  void init() => _impl.init();
  void updateBadge(int count) => _impl.updateBadge(count);
  Future<void> showNotification(String title, String body) =>
      _impl.showNotification(title, body);
  void dispose() => _impl.dispose();
}
