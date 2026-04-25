import 'package:flutter/widgets.dart';

import 'web_drop_stub.dart'
    if (dart.library.js_interop) 'web_drop_web.dart' as impl;

Widget buildWebDropZone({required Widget child, void Function(List<String> names)? onDrop}) {
  return impl.buildWebDropZone(child: child, onDrop: onDrop);
}
