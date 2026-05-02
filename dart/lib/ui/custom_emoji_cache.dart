import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';

class CustomEmojiCache {
  static final CustomEmojiCache instance = CustomEmojiCache._();
  CustomEmojiCache._();

  final Map<int, Uint8List> _thumbs = {};
  final Map<int, Uint8List> _paths = {};
  final Map<int, CustomEmojiFileData> _files = {};
  final Set<int> _pending = {};
  final Set<int> _filePending = {};
  final Set<int> _failed = {};
  final Set<int> _fileFailed = {};
  final List<VoidCallback> _listeners = [];
  Timer? _batchTimer;
  Timer? _fileBatchTimer;
  final List<_PendingRequest> _batchQueue = [];
  final List<_PendingRequest> _fileBatchQueue = [];

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);

  Uint8List? getThumb(int documentId) => _thumbs[documentId];
  Uint8List? getPath(int documentId) => _paths[documentId];
  CustomEmojiFileData? getFile(int documentId) => _files[documentId];
  bool isPending(int documentId) => _pending.contains(documentId);
  bool hasFailed(int documentId) => _failed.contains(documentId);
  bool isFilePending(int documentId) => _filePending.contains(documentId);
  bool hasAnyPreview(int documentId) => _thumbs.containsKey(documentId) || _paths.containsKey(documentId);

  void request(int documentId, String accountId, EngineService engine) {
    if (_thumbs.containsKey(documentId) || _pending.contains(documentId) || _failed.contains(documentId)) return;
    _pending.add(documentId);
    _batchQueue.add(_PendingRequest(documentId, accountId, engine));
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 16), _flushBatch);
  }

  void requestFile(int documentId, String accountId, EngineService engine) {
    if (_files.containsKey(documentId) || _filePending.contains(documentId) || _fileFailed.contains(documentId)) return;
    _filePending.add(documentId);
    _fileBatchQueue.add(_PendingRequest(documentId, accountId, engine));
    _fileBatchTimer?.cancel();
    _fileBatchTimer = Timer(const Duration(milliseconds: 50), _flushFileBatch);
  }

  void _flushBatch() {
    if (_batchQueue.isEmpty) return;
    final batch = List<_PendingRequest>.from(_batchQueue);
    _batchQueue.clear();
    final byAccount = <String, List<_PendingRequest>>{};
    for (final req in batch) {
      (byAccount[req.accountId] ??= []).add(req);
    }
    for (final entry in byAccount.entries) {
      final ids = entry.value.map((r) => r.documentId).toList();
      final engine = entry.value.first.engine;
      _fetchThumbBatch(entry.key, ids, engine);
    }
  }

  void _flushFileBatch() {
    if (_fileBatchQueue.isEmpty) return;
    final batch = List<_PendingRequest>.from(_fileBatchQueue);
    _fileBatchQueue.clear();
    final byAccount = <String, List<_PendingRequest>>{};
    for (final req in batch) {
      (byAccount[req.accountId] ??= []).add(req);
    }
    for (final entry in byAccount.entries) {
      final ids = entry.value.map((r) => r.documentId).toList();
      final engine = entry.value.first.engine;
      for (var i = 0; i < ids.length; i += 100) {
        _fetchFileBatch(entry.key, ids.sublist(i, math.min(i + 100, ids.length)), engine);
      }
    }
  }

  Future<void> _fetchThumbBatch(String accountId, List<int> ids, EngineService engine) async {
    try {
      final result = await engine.getCustomEmojiThumbs(accountId, ids);
      for (final entry in result.entries) {
        final data = entry.value;
        if (data.thumbB64.isNotEmpty) {
          _thumbs[entry.key] = base64Decode(data.thumbB64);
        }
        if (data.pathB64.isNotEmpty) {
          _paths[entry.key] = base64Decode(data.pathB64);
        }
        _pending.remove(entry.key);
      }
      for (final id in ids) {
        if (!_thumbs.containsKey(id) && !_paths.containsKey(id)) {
          _pending.remove(id);
          _failed.add(id);
        } else {
          _pending.remove(id);
        }
      }
    } catch (_) {
      for (final id in ids) {
        _pending.remove(id);
        _failed.add(id);
      }
    }
    _notifyListeners();
  }

  Future<void> _fetchFileBatch(String accountId, List<int> ids, EngineService engine) async {
    try {
      final result = await engine.getCustomEmojiFiles(accountId, ids);
      for (final entry in result.entries) {
        _files[entry.key] = entry.value;
        _filePending.remove(entry.key);
      }
      for (final id in ids) {
        if (!_files.containsKey(id)) {
          _filePending.remove(id);
          _fileFailed.add(id);
        }
      }
    } catch (_) {
      for (final id in ids) {
        _filePending.remove(id);
        _fileFailed.add(id);
      }
    }
    _notifyListeners();
  }

  void _notifyListeners() {
    for (final cb in List<VoidCallback>.from(_listeners)) {
      cb();
    }
  }
}

class _PendingRequest {
  final int documentId;
  final String accountId;
  final EngineService engine;
  const _PendingRequest(this.documentId, this.accountId, this.engine);
}
