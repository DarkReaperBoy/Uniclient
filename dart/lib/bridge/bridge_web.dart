/// Web (WASM) bridge implementation.
///
/// Loads cores.wasm via the Go wasm_exec.js runtime, then calls
/// the exported BridgeCall/BridgeSetEventCallback functions via JS interop.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

// JS interop bindings to the Go WASM exports.
// These are set on globalThis by the Go WASM runtime.

@JS('bridgeCall')
external JSUint8Array _jsBridgeCall(JSUint8Array data);

@JS('bridgeSetEventCallback')
external void _jsBridgeSetEventCallback(JSFunction? cb);

class BridgeImpl {
  Stream<Uint8List> get events => _eventController.stream;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  final _eventController = StreamController<Uint8List>.broadcast();

  void init({String? libraryPath}) {
    if (_initialized) return;

    // Set the event callback on the JS side.
    _jsBridgeSetEventCallback(_onEventFromGo.toJS);
    _initialized = true;
  }

  Uint8List call(Uint8List requestBytes) {
    if (!_initialized) {
      throw StateError('Bridge not initialized. Call init() first.');
    }

    final jsReq = requestBytes.toJS;
    final jsResp = _jsBridgeCall(jsReq);
    return jsResp.toDart;
  }

  /// Async bridge call. WASM runs on the main JS thread so the Go call still
  /// blocks during execution, but wrapping in Future.microtask ensures pending
  /// microtasks and I/O callbacks are processed before the blocking call starts.
  Future<Uint8List> callAsync(Uint8List requestBytes) =>
      Future.microtask(() => call(requestBytes));

  void dispose() {
    if (!_initialized) return;
    _jsBridgeSetEventCallback(null);
    _eventController.close();
    _initialized = false;
  }

  void _onEventFromGo(JSUint8Array data) {
    _eventController.add(data.toDart);
  }
}
