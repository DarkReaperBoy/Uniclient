import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Widget buildWebDropZone({required Widget child, void Function(List<String> names)? onDrop}) {
  return _WebDropZone(onDrop: onDrop, child: child);
}

class _WebDropZone extends StatefulWidget {
  final Widget child;
  final void Function(List<String> names)? onDrop;

  const _WebDropZone({required this.child, this.onDrop});

  @override
  State<_WebDropZone> createState() => _WebDropZoneState();
}

class _WebDropZoneState extends State<_WebDropZone> {
  bool _dragOver = false;

  late final JSFunction _onDragOver;
  late final JSFunction _onDrop;
  late final JSFunction _onDragLeave;

  @override
  void initState() {
    super.initState();
    _onDragOver = _handleDragOver.toJS;
    _onDrop = _handleDrop.toJS;
    _onDragLeave = _handleDragLeave.toJS;

    final body = web.document.body!;
    body.addEventListener('dragover', _onDragOver);
    body.addEventListener('drop', _onDrop);
    body.addEventListener('dragleave', _onDragLeave);
  }

  @override
  void dispose() {
    final body = web.document.body!;
    body.removeEventListener('dragover', _onDragOver);
    body.removeEventListener('drop', _onDrop);
    body.removeEventListener('dragleave', _onDragLeave);
    super.dispose();
  }

  void _handleDragOver(web.Event event) {
    event.preventDefault();
    if (!_dragOver) setState(() => _dragOver = true);
  }

  void _handleDragLeave(web.Event event) {
    if (_dragOver) setState(() => _dragOver = false);
  }

  void _handleDrop(web.Event event) {
    event.preventDefault();
    setState(() => _dragOver = false);

    final de = event as web.DragEvent;
    final dt = de.dataTransfer;
    if (dt == null) return;

    final fileNames = <String>[];
    final files = dt.files;
    for (var i = 0; i < files.length; i++) {
      fileNames.add(files.item(i)!.name);
    }
    if (fileNames.isNotEmpty) {
      widget.onDrop?.call(fileNames);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (_dragOver)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0x3340a7e3),
              ),
            ),
          ),
      ],
    );
  }

  Widget get child => widget.child;
}
