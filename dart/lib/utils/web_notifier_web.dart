import 'dart:js_interop';

import 'package:web/web.dart' as web;

class WebNotifierImpl {
  static const _baseTitle = 'UniClient';
  bool _permissionGranted = false;

  void init() {
    final perm = web.Notification.permission;
    if (perm == 'granted') {
      _permissionGranted = true;
    } else if (perm == 'default') {
      web.Notification.requestPermission().toDart.then((result) {
        _permissionGranted = (result.toDart == 'granted');
      });
    }
  }

  void updateBadge(int count) {
    web.document.title = count > 0 ? '($count) $_baseTitle' : _baseTitle;
  }

  Future<void> showNotification(String title, String body) async {
    if (!_permissionGranted) {
      final result = await web.Notification.requestPermission().toDart;
      _permissionGranted = (result.toDart == 'granted');
    }
    if (_permissionGranted) {
      web.Notification(title, web.NotificationOptions(body: body));
    }
  }

  void dispose() {
    web.document.title = _baseTitle;
  }
}
