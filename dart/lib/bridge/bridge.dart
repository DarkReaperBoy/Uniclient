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
class Bridge {
  final impl.BridgeImpl _impl = impl.BridgeImpl();

  /// Stream of async events from Go (serialized BridgeEvent protos).
  Stream<Uint8List> get events => _impl.events;

  bool get isInitialized => _impl.isInitialized;

  /// Initialize the bridge by loading the native library or WASM module.
  ///
  /// Awaitable, and callers MUST await it before the first [call]/[callAsync]:
  /// on web it completes only once the Go WASM module has loaded and registered
  /// its exports (`window.bridgeReady`); on native it completes synchronously
  /// (the shared library is opened inline).
  Future<void> init({String? libraryPath}) => _impl.init(libraryPath: libraryPath);

  /// Synchronous call — blocks the calling thread. Use for fast ops only.
  Uint8List call(Uint8List requestBytes) => _impl.call(requestBytes);

  /// Async call — for any operation that might block (network calls, auth, etc).
  ///
  /// On native platforms this runs the FFI call on a background worker isolate,
  /// so it never blocks the UI thread. On web (WASM runs on the single JS
  /// thread) there is no background thread: the call is scheduled as an
  /// event-queue task but still blocks that thread while Go runs (see
  /// bridge_web.dart). Prefer it over [call] regardless — the native fast path
  /// stays non-blocking, and the web path at least yields the event loop a turn.
  Future<Uint8List> callAsync(Uint8List requestBytes) => _impl.callAsync(requestBytes);

  /// Clean up resources.
  void dispose() => _impl.dispose();
}
