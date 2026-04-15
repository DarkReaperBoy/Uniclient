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

typedef _EventCallbackC = Void Function(Pointer<Void> data, Int32 len);
typedef _BridgeSetEventCallbackC = Void Function(
  Pointer<NativeFunction<_EventCallbackC>> cb,
);
typedef _BridgeSetEventCallbackDart = void Function(
  Pointer<NativeFunction<_EventCallbackC>> cb,
);

/// The resolved library path, shared with background isolates.
String? _resolvedLibPath;

class BridgeImpl {
  late final DynamicLibrary _lib;
  late final _BridgeCallWithLenDart _callWithLen;
  late final _BridgeFreeDart _free;
  late final _BridgeSetEventCallbackDart _setEventCallback;

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
    _setEventCallback = _lib
        .lookupFunction<_BridgeSetEventCallbackC, _BridgeSetEventCallbackDart>(
          'BridgeSetEventCallback',
        );

    _setEventCallback(_eventCallbackPointer);
    _initialized = true;
  }

  /// Synchronous FFI call (use callAsync for non-blocking).
  Uint8List call(Uint8List requestBytes) {
    assert(_initialized, 'Bridge not initialized. Call init() first.');
    return _doCall(_callWithLen, _free, requestBytes);
  }

  /// Async FFI call — runs the blocking Go call on a background isolate.
  Future<Uint8List> callAsync(Uint8List requestBytes) async {
    assert(_initialized, 'Bridge not initialized. Call init() first.');
    final libPath = _resolvedLibPath!;
    return Isolate.run(() => _isolateCall(libPath, requestBytes));
  }

  void dispose() {
    if (!_initialized) return;
    _setEventCallback(nullptr);
    _initialized = false;
  }

  static String _findLibraryPath() {
    if (Platform.isLinux) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundlePath = '$exeDir/lib/libcores.so';
      if (File(bundlePath).existsSync()) return bundlePath;
      return 'libcores.so';
    }
    if (Platform.isMacOS) return 'libcores.dylib';
    if (Platform.isWindows) return 'cores.dll';
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

void _onEvent(Pointer<Void> data, int len) {
  if (len <= 0) return;
  // Copy bytes first, then free the C-allocated memory.
  // Go's C.CBytes uses C.malloc; we must free here because
  // NativeCallable.listener runs asynchronously — Go can't free
  // the pointer before Dart has read it.
  final bytes = Uint8List.fromList(data.cast<Uint8>().asTypedList(len));
  malloc.free(data);
  _globalEventController.add(bytes);
}

// Use NativeCallable.listener so Go can call this from any goroutine/thread.
// Unlike Pointer.fromFunction, .listener marshals the call back to the Dart
// isolate, avoiding "Cannot invoke native callback outside an isolate" crashes.
final _eventCallable = NativeCallable<_EventCallbackC>.listener(_onEvent);
final _eventCallbackPointer = _eventCallable.nativeFunction;
