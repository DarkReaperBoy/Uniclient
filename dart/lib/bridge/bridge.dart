/// FFI/WASM bridge to the Go shared library.
///
/// Uses conditional imports: dart:ffi on native platforms,
/// dart:js_interop on web (WASM).
library;

import 'dart:typed_data';

import 'bridge_stub.dart'
    if (dart.library.ffi) 'bridge_ffi.dart'
    if (dart.library.js_interop) 'bridge_web.dart' as impl;

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
  final impl.BridgeImpl _impl = impl.BridgeImpl();

  /// Stream of async events from Go (serialized BridgeEvent protos).
  Stream<Uint8List> get events => _impl.events;

  bool get isInitialized => _impl.isInitialized;

  /// Initialize the bridge by loading the native library or WASM module.
  void init({String? libraryPath}) => _impl.init(libraryPath: libraryPath);

  /// Call a Go bridge method with a serialized BridgeRequest proto.
  /// Returns the serialized BridgeResponse proto.
  Uint8List call(Uint8List requestBytes) => _impl.call(requestBytes);

  /// Clean up resources.
  void dispose() => _impl.dispose();
}
