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

// Promise created in web/index.html and resolved once the Go WASM module has run
// go.run() and registered bridgeCall / bridgeSetEventCallback on globalThis.
// Nullable: a host page that does not define it (e.g. a bare test harness)
// leaves the readiness gate a no-op. Awaited in init() — see the note there.
@JS('bridgeReady')
external JSPromise<JSAny?>? get _jsBridgeReady;

class BridgeImpl {
  Stream<Uint8List> get events => _eventController.stream;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  final _eventController = StreamController<Uint8List>.broadcast();

  Future<void> init({String? libraryPath}) async {
    if (_initialized) return;

    // The Go WASM module is fetched + instantiated asynchronously by
    // web/index.html, and Flutter bootstraps independently (its async
    // <script>) — there is NO ordering guarantee that Go main() has registered
    // bridgeCall / bridgeSetEventCallback on globalThis before this runs. A
    // multi-MB cores.wasm commonly finishes loading after Flutter starts, so
    // touching those functions now would throw "TypeError:
    // bridgeSetEventCallback is not a function". Awaiting window.bridgeReady
    // blocks init() until go.run() has registered the exports, mirroring the
    // native bridge where DynamicLibrary.open makes them available synchronously
    // inside init(). Skipped only if the host page omits the promise (null).
    final ready = _jsBridgeReady;
    if (ready != null) {
      await ready.toDart;
    }

    // Exports are now guaranteed present — set the event callback on the JS side.
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

  /// Async bridge call.
  ///
  /// Unlike the native bridge — which offloads to a worker isolate so the call
  /// never touches the UI thread (see [Bridge.callAsync]) — WASM here runs on
  /// the single JS/UI thread. There is no background thread to move work to, so
  /// the Go call WILL block the UI for its full duration; genuine
  /// off-main-thread execution would require hosting the WASM module in a Web
  /// Worker, which this on-main-thread setup does not provide.
  ///
  /// We still schedule it as an event-queue task (`Future(...)`, NOT
  /// `Future.microtask`): event-queue tasks run after pending microtasks AND
  /// queued I/O/timer callbacks, so the event loop gets one turn to drain an
  /// in-flight frame and queued callbacks before the blocking call starts.
  /// Microtasks have strictly higher priority than the event queue, so the
  /// former `Future.microtask` actually scheduled the blocking call *ahead* of
  /// those callbacks, not after them — the opposite of what its comment claimed.
  Future<Uint8List> callAsync(Uint8List requestBytes) =>
      Future(() => call(requestBytes));

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
