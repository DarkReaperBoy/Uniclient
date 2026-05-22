import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'web_drop_stub.dart'
    if (dart.library.js_interop) 'web_drop_web.dart' as impl;

class WebDroppedFile {
  final String name;
  final int size;
  final String mimeType;
  final Uint8List bytes;
  const WebDroppedFile({
    required this.name,
    required this.size,
    required this.mimeType,
    required this.bytes,
  });
}

Widget buildWebDropZone({
  required Widget child,
  void Function(List<String> mimeTypes)? onDragEnter,
  void Function()? onDragLeave,
  void Function(Offset localPosition)? onDragUpdate,
  void Function(List<WebDroppedFile> files)? onDrop,
  void Function(int rejectedCount)? onDropRejected,
}) {
  return impl.buildWebDropZone(
    child: child,
    onDragEnter: onDragEnter,
    onDragLeave: onDragLeave,
    onDragUpdate: onDragUpdate,
    onDrop: onDrop,
    onDropRejected: onDropRejected,
  );
}
