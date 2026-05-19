import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';

class _DecodedThumbResult {
  final int documentId;
  final Uint8List? thumb;
  final Uint8List? path;
  const _DecodedThumbResult(this.documentId, this.thumb, this.path);
}

List<_DecodedThumbResult> _decodeThumbBatchIsolate(List<List<dynamic>> entries) {
  final results = <_DecodedThumbResult>[];
  for (final entry in entries) {
    final docId = entry[0] as int;
    final thumbB64 = entry[1] as String;
    final pathB64 = entry[2] as String;
    Uint8List? thumb;
    Uint8List? path;
    if (thumbB64.isNotEmpty) thumb = base64Decode(thumbB64);
    if (pathB64.isNotEmpty) path = base64Decode(pathB64);
    results.add(_DecodedThumbResult(docId, thumb, path));
  }
  return results;
}

enum EmojiSizeTag {
  normal,   // 22px frame (inline in text — AdjustCustomEmojiSize: round(20*1.12))
  large,    // 27px frame
  isolated, // 38px frame (1-7 emoji messages — largeEmojiSize + 2*largeEmojiOutline)
  setIcon,  // 21px frame (sticker set icons — ConvertScale(18*7/6))
}

class EmojiSizeConstants {
  static const Map<EmojiSizeTag, double> frameSizes = {
    EmojiSizeTag.normal: 22.0,
    EmojiSizeTag.large: 27.0,
    EmojiSizeTag.isolated: 38.0,
    EmojiSizeTag.setIcon: 21.0,
  };

  static const int kPerRow = 16;
  static const int kMaxFrames = 180;
  static const int kPreloadFrames = 3;
  static const int kMaxPerRequest = 100;
  static const int kDocPreloadBatch = 48;
  static const int kDocListCap = 200;

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

  final Map<_InstanceKey, Set<int>> _refCounts = {};
  int _nextRefToken = 0;

  String? _diskCacheDir;
  final Set<int> _diskIndex = {};

  final Map<int, Set<VoidCallback>> _listenersByDoc = {};
  final Set<VoidCallback> _globalListeners = {};
  Timer? _batchTimer;
  Timer? _fileBatchTimer;
  final List<_PendingRequest> _batchQueue = [];
  final List<_PendingRequest> _fileBatchQueue = [];
  final Map<int, int> _failedRetryTime = {};
  final Map<int, int> _fileFailedRetryTime = {};
  static const int _retryDelayMs = 0;

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

  void addListener(VoidCallback cb) { _globalListeners.add(cb); }
  void removeListener(VoidCallback cb) { _globalListeners.remove(cb); }

  void addListenerForDoc(int documentId, VoidCallback cb) {
    (_listenersByDoc[documentId] ??= {}).add(cb);
  }

  void removeListenerForDoc(int documentId, VoidCallback cb) {
    _listenersByDoc[documentId]?.remove(cb);
    if (_listenersByDoc[documentId]?.isEmpty ?? false) {
      _listenersByDoc.remove(documentId);
    }
  }

  Uint8List? getThumb(int documentId) => _thumbs[documentId];
  Uint8List? getPath(int documentId) => _paths[documentId];
  CustomEmojiFileData? getFile(int documentId) => _files[documentId];
  bool isPending(int documentId) => _pending.contains(documentId);
  bool hasFailed(int documentId) => _failed.contains(documentId);
  bool hasFileFailed(int documentId) => _fileFailed.contains(documentId);
  bool isFilePending(int documentId) => _filePending.contains(documentId);
  bool hasAnyPreview(int documentId) =>
      _thumbs.containsKey(documentId) || _paths.containsKey(documentId);
  bool hasOnDisk(int documentId) => _diskIndex.contains(documentId);

  int acquireToken(int documentId, EmojiSizeTag sizeTag) {
    final key = _InstanceKey(documentId, sizeTag);
    final token = _nextRefToken++;
    (_refCounts[key] ??= {}).add(token);
    if (!_files.containsKey(documentId) &&
        _diskIndex.contains(documentId) &&
        !_filePending.contains(documentId)) {
      _loadFromDisk(documentId);
    }
    return token;
  }

  void acquire(int documentId, EmojiSizeTag sizeTag) {
    acquireToken(documentId, sizeTag);
  }

  void releaseToken(int documentId, EmojiSizeTag sizeTag, int token) {
    final key = _InstanceKey(documentId, sizeTag);
    _refCounts[key]?.remove(token);
    if (_refCounts[key]?.isEmpty ?? true) {
      _refCounts.remove(key);
    }
    if (_totalRefCount(documentId) == 0) {
      _evictFromMemory(documentId);
    }
  }

  void release(int documentId, EmojiSizeTag sizeTag) {
    final key = _InstanceKey(documentId, sizeTag);
    final tokens = _refCounts[key];
    if (tokens != null && tokens.isNotEmpty) {
      tokens.remove(tokens.first);
      if (tokens.isEmpty) _refCounts.remove(key);
    }
    if (_totalRefCount(documentId) == 0) {
      _evictFromMemory(documentId);
    }
  }

  int _totalRefCount(int documentId) {
    int total = 0;
    for (final tag in EmojiSizeTag.values) {
      total += _refCounts[_InstanceKey(documentId, tag)]?.length ?? 0;
    }
    return total;
  }

  void _evictFromMemory(int documentId) {
    _files.remove(documentId);
    _thumbs.remove(documentId);
    _paths.remove(documentId);
    _fileFailed.remove(documentId);
    _fileFailedRetryTime.remove(documentId);
    _failed.remove(documentId);
    _failedRetryTime.remove(documentId);
    _pending.remove(documentId);
    _filePending.remove(documentId);
  }

  bool hasFileAtAnySize(int documentId) => _files.containsKey(documentId);

  CustomEmojiFileData? prepareNonExactPreview(int documentId, EmojiSizeTag requestedTag) {
    if (_files.containsKey(documentId)) return _files[documentId];
    if (_diskIndex.contains(documentId) && !_filePending.contains(documentId)) {
      _loadFromDisk(documentId);
    }
    return _files[documentId];
  }

  void preloadBatch(List<int> documentIds, String accountId, EngineService engine) {
    final toRequest = <int>[];
    for (var i = 0; i < documentIds.length && i < EmojiSizeConstants.kDocListCap; i++) {
      final id = documentIds[i];
      if (!_thumbs.containsKey(id) && !_pending.contains(id) && !_failed.contains(id)) {
        toRequest.add(id);
      }
    }
    final preloadCount = math.min(toRequest.length, EmojiSizeConstants.kDocPreloadBatch);
    for (var i = 0; i < preloadCount; i++) {
      request(toRequest[i], accountId, engine);
    }
  }

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
    _notifyListeners({documentId});
  }

  void request(int documentId, String accountId, EngineService engine) {
    if (_thumbs.containsKey(documentId) || _pending.contains(documentId)) return;
    if (_failed.contains(documentId)) {
      final retryAt = _failedRetryTime[documentId] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch < retryAt) return;
      _failed.remove(documentId);
      _failedRetryTime.remove(documentId);
    }

    if (!kIsWeb && _diskCacheDir != null) {
      _pending.add(documentId);
      _loadThumbFromDisk(documentId, accountId, engine);
      return;
    }

    _pending.add(documentId);
    _batchQueue.add(_PendingRequest(documentId, accountId, engine));
    if (_batchTimer == null) {
      _batchTimer = Timer(Duration.zero, () {
        _batchTimer = null;
        _flushBatch();
      });
    }
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
        _notifyListeners({documentId});
        return;
      }
    } catch (_) {}
    _batchQueue.add(_PendingRequest(documentId, accountId, engine));
    if (_batchTimer == null) {
      _batchTimer = Timer(Duration.zero, () {
        _batchTimer = null;
        _flushBatch();
      });
    }
  }

  void requestFile(int documentId, String accountId, EngineService engine) {
    if (_files.containsKey(documentId) || _filePending.contains(documentId)) return;
    if (_fileFailed.contains(documentId)) {
      final retryAt = _fileFailedRetryTime[documentId] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch < retryAt) return;
      _fileFailed.remove(documentId);
      _fileFailedRetryTime.remove(documentId);
    }

    if (_diskIndex.contains(documentId)) {
      _loadFromDisk(documentId);
      return;
    }

    _filePending.add(documentId);
    _fileBatchQueue.add(_PendingRequest(documentId, accountId, engine));
    if (_fileBatchTimer == null) {
      _fileBatchTimer = Timer(Duration.zero, () {
        _fileBatchTimer = null;
        _flushFileBatch();
      });
    }
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
    final Set<int> changedIds = {};
    try {
      final result = await engine.getCustomEmojiThumbs(accountId, ids);
      final isolateInput = <List<dynamic>>[];
      for (final entry in result.entries) {
        final data = entry.value;
        isolateInput.add([entry.key, data.thumbB64, data.pathB64]);
      }
      final decoded = await compute(_decodeThumbBatchIsolate, isolateInput);
      for (final item in decoded) {
        if (item.thumb != null) {
          _thumbs[item.documentId] = item.thumb!;
          _writeThumbToDisk(item.documentId, item.thumb!);
        }
        if (item.path != null) {
          _paths[item.documentId] = item.path!;
          _writePathToDisk(item.documentId, item.path!);
        }
        _pending.remove(item.documentId);
        changedIds.add(item.documentId);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final id in ids) {
        if (!_thumbs.containsKey(id) && !_paths.containsKey(id)) {
          _pending.remove(id);
          _failed.add(id);
          _failedRetryTime[id] = now + _retryDelayMs;
        } else {
          _pending.remove(id);
        }
      }
    } catch (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final id in ids) {
        _pending.remove(id);
        _failed.add(id);
        _failedRetryTime[id] = now + _retryDelayMs;
      }
    }
    _notifyListeners(changedIds);
  }

  Future<void> _fetchFileBatch(
      String accountId, List<int> ids, EngineService engine) async {
    final Set<int> changedIds = {};
    try {
      final result = await engine.getCustomEmojiFiles(accountId, ids);
      for (final entry in result.entries) {
        _files[entry.key] = entry.value;
        _filePending.remove(entry.key);
        _writeToDisk(entry.key, entry.value);
        changedIds.add(entry.key);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final id in ids) {
        if (!_files.containsKey(id)) {
          _filePending.remove(id);
          _fileFailed.add(id);
          _fileFailedRetryTime[id] = now + _retryDelayMs;
        }
      }
    } catch (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final id in ids) {
        _filePending.remove(id);
        _fileFailed.add(id);
        _fileFailedRetryTime[id] = now + _retryDelayMs;
      }
    }
    _notifyListeners(changedIds);
  }

  void _notifyListeners([Set<int>? changedDocIds]) {
    if (changedDocIds != null && changedDocIds.isNotEmpty) {
      for (final docId in changedDocIds) {
        final docListeners = _listenersByDoc[docId];
        if (docListeners != null) {
          for (final cb in Set<VoidCallback>.from(docListeners)) {
            cb();
          }
        }
      }
    }
    for (final cb in Set<VoidCallback>.from(_globalListeners)) {
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
