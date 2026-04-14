/// FFI bridge to the Go shared library.
///
/// Handles loading the native library, calling Go functions via FFI,
/// and receiving async events from Go.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;
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

/// The main bridge to the Go backend.
///
/// Usage:
/// ```dart
/// final bridge = Bridge();
/// bridge.init();
/// final response = bridge.call(requestBytes);
/// bridge.events.listen((eventBytes) { ... });
/// bridge.dispose();
/// ```
class Bridge {
  late final DynamicLibrary _lib;
  late final _BridgeCallWithLenDart _callWithLen;
  late final _BridgeFreeDart _free;
  late final _BridgeSetEventCallbackDart _setEventCallback;

  /// Stream of async events from Go (serialized BridgeEvent protos).
  Stream<Uint8List> get events => _globalEventController.stream;

  bool _initialized = false;

  /// Initialize the bridge by loading the native library.
  void init({String? libraryPath}) {
    if (_initialized) return;

    _lib = _loadLibrary(libraryPath);
    _callWithLen = _lib
        .lookupFunction<_BridgeCallWithLenC, _BridgeCallWithLenDart>(
          'BridgeCallWithLen',
        );
    _free = _lib.lookupFunction<_BridgeFreeC, _BridgeFreeDart>('BridgeFree');
    _setEventCallback = _lib
        .lookupFunction<_BridgeSetEventCallbackC, _BridgeSetEventCallbackDart>(
          'BridgeSetEventCallback',
        );

    // Set up event callback
    _setEventCallback(_eventCallbackPointer);

    _initialized = true;
  }

  /// Call a Go bridge method with a serialized BridgeRequest proto.
  /// Returns the serialized BridgeResponse proto.
  Uint8List call(Uint8List requestBytes) {
    assert(_initialized, 'Bridge not initialized. Call init() first.');

    // Allocate and copy request data to native memory
    final reqPtr = calloc<Uint8>(requestBytes.length);
    final reqList = reqPtr.asTypedList(requestBytes.length);
    reqList.setAll(0, requestBytes);

    final outLenPtr = calloc<Int32>();

    try {
      final resultPtr = _callWithLen(reqPtr, requestBytes.length, outLenPtr);
      final resultLen = outLenPtr.value;

      if (resultPtr == nullptr || resultLen == 0) {
        return Uint8List(0);
      }

      try {
        // Copy result to Dart memory
        final result = Uint8List.fromList(
          resultPtr.asTypedList(resultLen),
        );
        return result;
      } finally {
        _free(resultPtr);
      }
    } finally {
      calloc.free(reqPtr);
      calloc.free(outLenPtr);
    }
  }

  /// Clean up resources.
  void dispose() {
    if (!_initialized) return;
    // Clear the event callback
    _setEventCallback(nullptr);
    _initialized = false;
  }

  /// Load the native library based on platform.
  static DynamicLibrary _loadLibrary(String? path) {
    if (path != null) return DynamicLibrary.open(path);

    if (Platform.isLinux) return DynamicLibrary.open('libcores.so');
    if (Platform.isMacOS) return DynamicLibrary.open('libcores.dylib');
    if (Platform.isWindows) return DynamicLibrary.open('cores.dll');
    if (Platform.isAndroid) return DynamicLibrary.open('libcores.so');

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

// Static event callback that forwards events to all Bridge instances.
// Since Go only supports one callback, we use a global stream.
final _globalEventController = StreamController<Uint8List>.broadcast();

/// Native callback invoked by Go for async events.
void _onEvent(Pointer<Void> data, int len) {
  if (len <= 0) return;
  final bytes = Uint8List.fromList(
    data.cast<Uint8>().asTypedList(len),
  );
  _globalEventController.add(bytes);
}

final _eventCallbackPointer =
    Pointer.fromFunction<_EventCallbackC>(_onEvent);
