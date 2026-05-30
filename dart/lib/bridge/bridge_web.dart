/// Web (WASM) bridge implementation.
///
/// cores.wasm is loaded by the Go wasm_exec.js runtime in web/index.html, whose
/// main() (go/cmd/bridge/main_js.go) registers `bridgeCall` and
/// `bridgeSetEventCallback` on globalThis via syscall/js. We call them through
/// JS interop below. Unlike native FFI there are no pointers: bytes cross the
/// boundary as JS Uint8Array values, and async events are delivered by a JS
/// callback (push) rather than the native BridgeNextEvent pull loop, because the
/// single-threaded JS event loop cannot block to pull.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

// JS interop bindings to the functions registered on globalThis by the Go WASM
// runtime (go/cmd/bridge/main_js.go).

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
