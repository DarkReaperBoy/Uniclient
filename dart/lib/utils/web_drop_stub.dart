import 'package:flutter/widgets.dart';

import 'web_drop.dart';

Widget buildWebDropZone({
  required Widget child,
  void Function(List<String> mimeTypes)? onDragEnter,
  void Function()? onDragLeave,
  void Function(Offset localPosition)? onDragUpdate,
  void Function(List<WebDroppedFile> files)? onDrop,
  void Function(int largestRejectedBytes)? onDropRejected,
}) {
  return child;
}
