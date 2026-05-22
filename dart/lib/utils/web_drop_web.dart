import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'web_drop.dart';

Widget buildWebDropZone({
  required Widget child,
  void Function(List<String> mimeTypes)? onDragEnter,
  void Function()? onDragLeave,
  void Function(Offset localPosition)? onDragUpdate,
  void Function(List<WebDroppedFile> files)? onDrop,
  void Function(int rejectedCount)? onDropRejected,
}) {
  return _WebDropZone(
    onDragEnter: onDragEnter,
    onDragLeave: onDragLeave,
    onDragUpdate: onDragUpdate,
    onDrop: onDrop,
    onDropRejected: onDropRejected,
    child: child,
  );
}

class _WebDropZone extends StatefulWidget {
  final Widget child;
  final void Function(List<String> mimeTypes)? onDragEnter;
  final void Function()? onDragLeave;
  final void Function(Offset localPosition)? onDragUpdate;
  final void Function(List<WebDroppedFile> files)? onDrop;
  final void Function(int rejectedCount)? onDropRejected;

  const _WebDropZone({
    required this.child,
    this.onDragEnter,
    this.onDragLeave,
    this.onDragUpdate,
    this.onDrop,
    this.onDropRejected,
  });

  @override
  State<_WebDropZone> createState() => _WebDropZoneState();
}

class _WebDropZoneState extends State<_WebDropZone> {
  bool _active = false;
  int _enterCount = 0;
  DateTime _lastDragUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kDragUpdateThrottleMs = 16; // ~60Hz max
  static const _kMaxConcurrentReads = 4;
  static const _kMaxFileSizeBytes = 4 * 1024 * 1024 * 1024; // 4 GB (premium limit)

  late final JSFunction _onDragEnter;
  late final JSFunction _onDragOver;
  late final JSFunction _onDrop;
  late final JSFunction _onDragLeave;

  @override
  void initState() {
    super.initState();
    _onDragEnter = _handleDragEnter.toJS;
    _onDragOver = _handleDragOver.toJS;
    _onDrop = _handleDrop.toJS;
    _onDragLeave = _handleDragLeave.toJS;

    final body = web.document.body!;
    body.addEventListener('dragenter', _onDragEnter);
    body.addEventListener('dragover', _onDragOver);
    body.addEventListener('drop', _onDrop);
    body.addEventListener('dragleave', _onDragLeave);
  }

  @override
  void dispose() {
    final body = web.document.body!;
    body.removeEventListener('dragenter', _onDragEnter);
    body.removeEventListener('dragover', _onDragOver);
    body.removeEventListener('drop', _onDrop);
    body.removeEventListener('dragleave', _onDragLeave);
    super.dispose();
  }

  void _handleDragEnter(web.Event event) {
    event.preventDefault();
    _enterCount++;
    if (!_active) {
      _active = true;
      final mimeTypes = <String>[];
      final de = event as web.DragEvent;
      final dt = de.dataTransfer;
      if (dt != null) {
        final items = dt.items;
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          if (item.kind == 'file') {
            final t = item.type.toLowerCase();
            if (t.isNotEmpty) mimeTypes.add(t);
          }
        }
      }
      widget.onDragEnter?.call(mimeTypes);
    }
  }

  void _handleDragOver(web.Event event) {
    event.preventDefault();
    final de = event as web.DragEvent;
    if (de.dataTransfer != null) {
      de.dataTransfer!.dropEffect = 'copy';
    }
    final now = DateTime.now();
    if (now.difference(_lastDragUpdate).inMilliseconds < _kDragUpdateThrottleMs) {
      return;
    }
    _lastDragUpdate = now;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final globalPos = Offset(de.clientX.toDouble(), de.clientY.toDouble());
      final localPos = box.globalToLocal(globalPos);
      widget.onDragUpdate?.call(localPos);
    }
  }

  void _handleDragLeave(web.Event event) {
    _enterCount--;
    if (_enterCount <= 0) {
      _enterCount = 0;
      if (_active) {
        _active = false;
        widget.onDragLeave?.call();
      }
    }
  }

  void _handleDrop(web.Event event) {
    event.preventDefault();
    _enterCount = 0;
    _active = false;

    final de = event as web.DragEvent;
    final dt = de.dataTransfer;
    if (dt == null) {
      widget.onDragLeave?.call();
      return;
    }

    final files = dt.files;
    if (files.length == 0) {
      widget.onDragLeave?.call();
      return;
    }

    final webFiles = <web.File>[];
    for (var i = 0; i < files.length; i++) {
      webFiles.add(files.item(i)!);
    }

    _readFiles(webFiles);
  }

  Future<void> _readFiles(List<web.File> webFiles) async {
    final results = <WebDroppedFile>[];
    var sizeRejected = 0;
    for (var i = 0; i < webFiles.length; i += _kMaxConcurrentReads) {
      final batch = webFiles.skip(i).take(_kMaxConcurrentReads);
      final batchResults = await Future.wait(batch.map((wf) async {
        try {
          if (wf.size > _kMaxFileSizeBytes) {
            sizeRejected++;
            return null;
          }
          final bytes = await _readFileBytes(wf);
          return WebDroppedFile(
            name: wf.name,
            size: wf.size,
            mimeType: wf.type,
            bytes: bytes,
          );
        } catch (_) {
          return null;
        }
      }));
      results.addAll(batchResults.whereType<WebDroppedFile>());
    }
    if (!mounted) return;
    if (results.isNotEmpty) {
      widget.onDrop?.call(results);
    } else if (sizeRejected > 0) {
      widget.onDropRejected?.call(sizeRejected);
    } else {
      widget.onDragLeave?.call();
    }
  }

  Future<Uint8List> _readFileBytes(web.File file) {
    final completer = Completer<Uint8List>();
    final reader = web.FileReader();
    reader.onload = (web.Event event) {
      final result = reader.result as JSArrayBuffer;
      completer.complete(result.toDart.asUint8List());
    }.toJS;
    reader.onerror = (web.Event event) {
      completer.completeError(Exception('Failed to read file: ${file.name}'));
    }.toJS;
    reader.readAsArrayBuffer(file);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
