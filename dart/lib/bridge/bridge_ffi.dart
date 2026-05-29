/// Native FFI bridge implementation (Linux, Windows, macOS, Android).
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io' show File, Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// FFI type signatures for the Go exports
typedef _BridgeCallWithLenC = Pointer<Uint8> Function(
  Pointer<Uint8> data,
  Int32 dataLen,
  Pointer<Int32> outLen,
);
typedef _BridgeCallWithLenDart = Pointer<Uint8> Function(
  Pointer<Uint8> data,
  int dataLen,
  Pointer<Int32> outLen,
);

typedef _BridgeFreeC = Void Function(Pointer<Uint8> ptr);
typedef _BridgeFreeDart = void Function(Pointer<Uint8> ptr);

// BridgeNextEvent blocks in Go until the next async event arrives, returning a
// Go-pinned buffer (freed with BridgeFree). Run only on a dedicated isolate —
// it parks the calling thread until an event is ready.
typedef _BridgeNextEventC = Pointer<Uint8> Function(Pointer<Int32> outLen);
typedef _BridgeNextEventDart = Pointer<Uint8> Function(Pointer<Int32> outLen);

typedef _BridgeStopEventsC = Void Function();
typedef _BridgeStopEventsDart = void Function();

/// The resolved library path, shared with background isolates.
String? _resolvedLibPath;

class BridgeImpl {
  late final DynamicLibrary _lib;
  late final _BridgeCallWithLenDart _callWithLen;
  late final _BridgeFreeDart _free;
  late final _BridgeStopEventsDart _stopEvents;

  // Dedicated isolate that blocks on BridgeNextEvent and forwards each event
  // back to this isolate over [_eventReceivePort].
  Future<Isolate>? _eventIsolate;
  ReceivePort? _eventReceivePort;

  Stream<Uint8List> get events => _globalEventController.stream;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  void init({String? libraryPath}) {
    if (_initialized) return;

    _resolvedLibPath = libraryPath ?? _findLibraryPath();
    _lib = DynamicLibrary.open(_resolvedLibPath!);
    _callWithLen = _lib
        .lookupFunction<_BridgeCallWithLenC, _BridgeCallWithLenDart>(
          'BridgeCallWithLen',
        );
    _free = _lib.lookupFunction<_BridgeFreeC, _BridgeFreeDart>('BridgeFree');
    _stopEvents = _lib
        .lookupFunction<_BridgeStopEventsC, _BridgeStopEventsDart>(
          'BridgeStopEvents',
        );

    _startEventIsolate();
    _initialized = true;
  }

  /// Spawn the dedicated isolate that pulls events from Go.
  ///
  /// The ReceivePort is wired up synchronously before spawning, so no events
  /// are lost: anything Go emits before the isolate connects stays buffered in
  /// Go's event channel and is delivered once the isolate starts pulling.
  void _startEventIsolate() {
    final receivePort = ReceivePort();
    receivePort.listen((msg) {
      if (msg is Uint8List && !_globalEventController.isClosed) {
        _globalEventController.add(msg);
      }
    });
    _eventReceivePort = receivePort;
    _eventIsolate = Isolate.spawn(
      _eventLoop,
      [_resolvedLibPath!, receivePort.sendPort],
      debugName: 'uniclient-events',
    );
  }

  /// Synchronous FFI call (use callAsync for non-blocking).
  Uint8List call(Uint8List requestBytes) {
    if (!_initialized) {
      throw StateError('Bridge not initialized. Call init() first.');
    }
    return _doCall(_callWithLen, _free, requestBytes);
  }

  /// Async FFI call — runs the blocking Go call on a background isolate.
  Future<Uint8List> callAsync(Uint8List requestBytes) async {
    if (!_initialized) {
      throw StateError('Bridge not initialized. Call init() first.');
    }
    final libPath = _resolvedLibPath!;
    return Isolate.run(() => _isolateCall(libPath, requestBytes));
  }

  void dispose() {
    if (!_initialized) return;
    // Unblock BridgeNextEvent so the event isolate's loop ends, then tear it
    // down and stop forwarding events.
    _stopEvents();
    _eventIsolate?.then((iso) => iso.kill(priority: Isolate.beforeNextEvent));
    _eventIsolate = null;
    _eventReceivePort?.close();
    _eventReceivePort = null;
    _initialized = false;
    _globalEventController.close();
  }

  static String _findLibraryPath() {
    if (Platform.isLinux) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      for (final candidate in [
        '$exeDir/lib/libcores.so',
        '$exeDir/libcores.so',
      ]) {
        if (File(candidate).existsSync()) return candidate;
      }
      return 'libcores.so';
    }
    if (Platform.isMacOS) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final frameworkPath = '$exeDir/../Frameworks/libcores.dylib';
      if (File(frameworkPath).existsSync()) return frameworkPath;
      return 'libcores.dylib';
    }
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final localPath = '$exeDir/cores.dll';
      if (File(localPath).existsSync()) return localPath;
      return 'cores.dll';
    }
    if (Platform.isAndroid) return 'libcores.so';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

/// Perform the actual FFI call (used by both sync and isolate paths).
Uint8List _doCall(
  _BridgeCallWithLenDart callWithLen,
  _BridgeFreeDart free,
  Uint8List requestBytes,
) {
  final reqPtr = calloc<Uint8>(requestBytes.length);
  final reqList = reqPtr.asTypedList(requestBytes.length);
  reqList.setAll(0, requestBytes);

  final outLenPtr = calloc<Int32>();

  try {
    final resultPtr = callWithLen(reqPtr, requestBytes.length, outLenPtr);
    final resultLen = outLenPtr.value;

    if (resultPtr == nullptr || resultLen == 0) {
      return Uint8List(0);
    }

    try {
      final result = Uint8List.fromList(resultPtr.asTypedList(resultLen));
      return result;
    } finally {
      free(resultPtr);
    }
  } finally {
    calloc.free(reqPtr);
    calloc.free(outLenPtr);
  }
}

/// Top-level function for Isolate.run — opens the shared lib and makes the call.
/// DynamicLibrary.open with the same path reuses the process-wide handle (cheap).
Uint8List _isolateCall(String libPath, Uint8List requestBytes) {
  final lib = DynamicLibrary.open(libPath);
  final callWithLen = lib
      .lookupFunction<_BridgeCallWithLenC, _BridgeCallWithLenDart>(
        'BridgeCallWithLen',
      );
  final free = lib.lookupFunction<_BridgeFreeC, _BridgeFreeDart>('BridgeFree');
  return _doCall(callWithLen, free, requestBytes);
}

// Global event controller shared across bridge instances.
final _globalEventController = StreamController<Uint8List>.broadcast();

/// Event-isolate entry point. Opens the shared lib, then loops calling the
/// blocking BridgeNextEvent and forwarding each event back to the main isolate.
/// Exits when BridgeNextEvent returns null/empty (after BridgeStopEvents).
///
/// args: [libPath (String), sendPort (SendPort)].
void _eventLoop(List<dynamic> args) {
  final libPath = args[0] as String;
  final sendPort = args[1] as SendPort;

  final lib = DynamicLibrary.open(libPath);
  final nextEvent = lib
      .lookupFunction<_BridgeNextEventC, _BridgeNextEventDart>(
        'BridgeNextEvent',
      );
  final free = lib.lookupFunction<_BridgeFreeC, _BridgeFreeDart>('BridgeFree');

  final outLen = calloc<Int32>();
  try {
    while (true) {
      final ptr = nextEvent(outLen); // blocks in Go until an event is ready
      final len = outLen.value;
      if (ptr == nullptr || len <= 0) break; // stop signal
      final bytes = Uint8List.fromList(ptr.cast<Uint8>().asTypedList(len));
      free(ptr);
      sendPort.send(bytes);
    }
  } finally {
    calloc.free(outLen);
  }
}
