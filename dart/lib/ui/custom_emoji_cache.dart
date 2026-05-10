import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';

enum EmojiSizeTag {
  normal,   // 20px frame (inline in text)
  large,    // 27px frame
  isolated, // 43px frame (1-7 emoji messages)
  setIcon,  // 24px frame (sticker set icons)
}

class EmojiSizeConstants {
  static const Map<EmojiSizeTag, double> frameSizes = {
    EmojiSizeTag.normal: 20.0,
    EmojiSizeTag.large: 27.0,
    EmojiSizeTag.isolated: 43.0,
    EmojiSizeTag.setIcon: 24.0,
  };

  static const int kPerRow = 16;
  static const int kMaxFrames = 180;
  static const int kPreloadFrames = 3;
  static const int kMaxPerRequest = 100;

  static double frameSize(EmojiSizeTag tag) => frameSizes[tag] ?? 20.0;

  static double scaledFrameSize(EmojiSizeTag tag, double devicePixelRatio) =>
      (frameSizes[tag] ?? 20.0) * devicePixelRatio;
}

class _InstanceKey {
  final int documentId;
  final EmojiSizeTag sizeTag;

  const _InstanceKey(this.documentId, this.sizeTag);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _InstanceKey &&
          documentId == other.documentId &&
          sizeTag == other.sizeTag;

  @override
  int get hashCode => Object.hash(documentId, sizeTag);
}

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

  final Map<_InstanceKey, int> _refCounts = {};

  String? _diskCacheDir;
  final Set<int> _diskIndex = {};

  final List<VoidCallback> _listeners = [];
  Timer? _batchTimer;
  Timer? _fileBatchTimer;
  final List<_PendingRequest> _batchQueue = [];
  final List<_PendingRequest> _fileBatchQueue = [];

  Future<void> initDiskCache(String cacheDir) async {
    if (kIsWeb) return;
    _diskCacheDir = '$cacheDir/emoji';
    final dir = Directory(_diskCacheDir!);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.dat')) {
          final name = entity.uri.pathSegments.last;
          final docId = int.tryParse(name.replaceAll('.dat', ''));
          if (docId != null) _diskIndex.add(docId);
        }
      }
    } catch (_) {}
  }

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);

  Uint8List? getThumb(int documentId) => _thumbs[documentId];
  Uint8List? getPath(int documentId) => _paths[documentId];
  CustomEmojiFileData? getFile(int documentId) => _files[documentId];
  bool isPending(int documentId) => _pending.contains(documentId);
  bool hasFailed(int documentId) => _failed.contains(documentId);
  bool isFilePending(int documentId) => _filePending.contains(documentId);
  bool hasAnyPreview(int documentId) =>
      _thumbs.containsKey(documentId) || _paths.containsKey(documentId);
  bool hasOnDisk(int documentId) => _diskIndex.contains(documentId);

  // §45.8: Acquire an instance reference for (documentId, sizeTag).
  // Increments refcount. If file was evicted from memory but exists on disk,
  // triggers a reload.
  void acquire(int documentId, EmojiSizeTag sizeTag) {
    final key = _InstanceKey(documentId, sizeTag);
    _refCounts[key] = (_refCounts[key] ?? 0) + 1;
    if (!_files.containsKey(documentId) &&
        _diskIndex.contains(documentId) &&
        !_filePending.contains(documentId)) {
      _loadFromDisk(documentId);
    }
  }

  // §45.8: Release an instance reference. When all references for a documentId
  // drop to zero, the file data is evicted from memory (disk copy retained).
  void release(int documentId, EmojiSizeTag sizeTag) {
    final key = _InstanceKey(documentId, sizeTag);
    final count = (_refCounts[key] ?? 0) - 1;
    if (count <= 0) {
      _refCounts.remove(key);
    } else {
      _refCounts[key] = count;
    }
    if (_totalRefCount(documentId) == 0) {
      _evictFromMemory(documentId);
    }
  }

  int _totalRefCount(int documentId) {
    int total = 0;
    for (final tag in EmojiSizeTag.values) {
      total += _refCounts[_InstanceKey(documentId, tag)] ?? 0;
    }
    return total;
  }

  void _evictFromMemory(int documentId) {
    _files.remove(documentId);
    _fileFailed.remove(documentId);
  }

  // §45.8: Cross-resolution preview — file data loaded at any SizeTag is
  // available for rendering at any other size (Flutter scales natively).
  bool hasFileAtAnySize(int documentId) => _files.containsKey(documentId);

  Future<void> _writeToDisk(int documentId, CustomEmojiFileData data) async {
    if (kIsWeb || _diskCacheDir == null) return;
    try {
      final basePath = '$_diskCacheDir/$documentId';
      await File('$basePath.dat').writeAsBytes(data.fileData, flush: true);
      await File('$basePath.mime').writeAsString(data.mimeType, flush: true);
      _diskIndex.add(documentId);
    } catch (_) {}
  }

  Future<void> _writeThumbToDisk(int documentId, Uint8List data) async {
    if (kIsWeb || _diskCacheDir == null) return;
    try {
      await File('$_diskCacheDir/$documentId.thumb')
          .writeAsBytes(data, flush: true);
    } catch (_) {}
  }

  Future<void> _writePathToDisk(int documentId, Uint8List data) async {
    if (kIsWeb || _diskCacheDir == null) return;
    try {
      await File('$_diskCacheDir/$documentId.path')
          .writeAsBytes(data, flush: true);
    } catch (_) {}
  }

  Future<void> _loadFromDisk(int documentId) async {
    if (kIsWeb || _diskCacheDir == null) return;
    _filePending.add(documentId);
    try {
      final datFile = File('$_diskCacheDir/$documentId.dat');
      final mimeFile = File('$_diskCacheDir/$documentId.mime');
      if (await datFile.exists() && await mimeFile.exists()) {
        final fileData = await datFile.readAsBytes();
        final mimeType = await mimeFile.readAsString();
        _files[documentId] = CustomEmojiFileData(
          mimeType: mimeType.trim(),
          fileData: fileData,
        );
      }
      if (!_thumbs.containsKey(documentId)) {
        final thumbFile = File('$_diskCacheDir/$documentId.thumb');
        if (await thumbFile.exists()) {
          _thumbs[documentId] = await thumbFile.readAsBytes();
        }
      }
      if (!_paths.containsKey(documentId)) {
        final pathFile = File('$_diskCacheDir/$documentId.path');
        if (await pathFile.exists()) {
          _paths[documentId] = await pathFile.readAsBytes();
        }
      }
    } catch (_) {
      _diskIndex.remove(documentId);
    }
    _filePending.remove(documentId);
    _notifyListeners();
  }

  void request(int documentId, String accountId, EngineService engine) {
    if (_thumbs.containsKey(documentId) ||
        _pending.contains(documentId) ||
        _failed.contains(documentId)) return;

    if (!kIsWeb && _diskCacheDir != null) {
      _pending.add(documentId);
      _loadThumbFromDisk(documentId, accountId, engine);
      return;
    }

    _pending.add(documentId);
    _batchQueue.add(_PendingRequest(documentId, accountId, engine));
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 16), _flushBatch);
  }

  Future<void> _loadThumbFromDisk(int documentId, String accountId, EngineService engine) async {
    try {
      final thumbFile = File('$_diskCacheDir/$documentId.thumb');
      if (await thumbFile.exists()) {
        _thumbs[documentId] = await thumbFile.readAsBytes();
        final pathFile = File('$_diskCacheDir/$documentId.path');
        if (await pathFile.exists()) {
          _paths[documentId] = await pathFile.readAsBytes();
        }
        _pending.remove(documentId);
        _notifyListeners();
        return;
      }
    } catch (_) {}
    _batchQueue.add(_PendingRequest(documentId, accountId, engine));
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 16), _flushBatch);
  }

  void requestFile(int documentId, String accountId, EngineService engine) {
    if (_files.containsKey(documentId) ||
        _filePending.contains(documentId) ||
        _fileFailed.contains(documentId)) return;

    if (_diskIndex.contains(documentId)) {
      _loadFromDisk(documentId);
      return;
    }

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
      for (var i = 0; i < ids.length; i += EmojiSizeConstants.kMaxPerRequest) {
        _fetchThumbBatch(
          entry.key,
          ids.sublist(i, math.min(i + EmojiSizeConstants.kMaxPerRequest, ids.length)),
          engine,
        );
      }
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
      for (var i = 0; i < ids.length; i += EmojiSizeConstants.kMaxPerRequest) {
        _fetchFileBatch(
          entry.key,
          ids.sublist(i, math.min(i + EmojiSizeConstants.kMaxPerRequest, ids.length)),
          engine,
        );
      }
    }
  }

  Future<void> _fetchThumbBatch(
      String accountId, List<int> ids, EngineService engine) async {
    try {
      final result = await engine.getCustomEmojiThumbs(accountId, ids);
      for (final entry in result.entries) {
        final data = entry.value;
        if (data.thumbB64.isNotEmpty) {
          final bytes = base64Decode(data.thumbB64);
          _thumbs[entry.key] = bytes;
          _writeThumbToDisk(entry.key, bytes);
        }
        if (data.pathB64.isNotEmpty) {
          final bytes = base64Decode(data.pathB64);
          _paths[entry.key] = bytes;
          _writePathToDisk(entry.key, bytes);
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

  Future<void> _fetchFileBatch(
      String accountId, List<int> ids, EngineService engine) async {
    try {
      final result = await engine.getCustomEmojiFiles(accountId, ids);
      for (final entry in result.entries) {
        _files[entry.key] = entry.value;
        _filePending.remove(entry.key);
        _writeToDisk(entry.key, entry.value);
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
