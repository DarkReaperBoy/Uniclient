/// Native FFI bridge implementation (Linux, Windows, macOS, Android).
library;

import 'dart:async';
import 'dart:collection';
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
  // Not `late final`: init() may run again after dispose() (engine hot-restart,
  // multi-account teardown), and re-assigning a `final` field would throw.
  late DynamicLibrary _lib;
  late _BridgeCallWithLenDart _callWithLen;
  late _BridgeFreeDart _free;
  late _BridgeStopEventsDart _stopEvents;

  // Dedicated isolate that blocks on BridgeNextEvent and forwards each event
  // back to this isolate over [_eventReceivePort].
  Future<Isolate>? _eventIsolate;
  ReceivePort? _eventReceivePort;

  // Per-instance event stream. Recreated by init() when a prior dispose() closed
  // it, so the bridge can be re-initialized without leaving `events` pointing at
  // a dead (already-closed) stream.
  StreamController<Uint8List> _eventController =
      StreamController<Uint8List>.broadcast();

  // Bounded pool of reusable worker isolates serving async FFI calls, so the
  // RPC hot path no longer spawns a fresh isolate (and re-opens the library)
  // per call. Created in init(), torn down in dispose().
  _RpcWorkerPool? _pool;

  Stream<Uint8List> get events => _eventController.stream;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // Async to satisfy the Bridge.init contract (web awaits WASM readiness). The
  // native body runs synchronously to completion — there is no `await` — so the
  // shared library is opened and the Go exports are resolved before the returned
  // future completes, preserving the "exports ready before first call()"
  // guarantee callers rely on.
  Future<void> init({String? libraryPath}) async {
    if (_initialized) return;

    // A previous dispose() closed the event stream; give callers a live one.
    if (_eventController.isClosed) {
      _eventController = StreamController<Uint8List>.broadcast();
    }

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

    _pool = _RpcWorkerPool(_resolvedLibPath!, _poolSize());
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
      if (msg is Uint8List && !_eventController.isClosed) {
        _eventController.add(msg);
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

  /// Async FFI call — runs the blocking Go call on a pooled worker isolate.
  ///
  /// The pool reuses a bounded set of long-lived isolates (each opens the shared
  /// library and looks up the Go exports once), instead of spawning a brand-new
  /// isolate per call. Concurrency is preserved up to the pool bound; bursts
  /// beyond it queue and dispatch as workers free up, avoiding head-of-line
  /// blocking that a single shared worker would impose.
  Future<Uint8List> callAsync(Uint8List requestBytes) async {
    if (!_initialized) {
      throw StateError('Bridge not initialized. Call init() first.');
    }
    return _pool!.run(requestBytes);
  }

  void dispose() {
    if (!_initialized) return;
    _initialized = false;
    // Unblock BridgeNextEvent so the event isolate's loop ends, then tear it
    // down and stop forwarding events.
    _stopEvents();
    _eventIsolate?.then((iso) => iso.kill(priority: Isolate.beforeNextEvent));
    _eventIsolate = null;
    _eventReceivePort?.close();
    _eventReceivePort = null;
    // Shut down the worker pool (kills its isolates, fails any pending calls).
    _pool?.dispose();
    _pool = null;
    // Close this instance's event stream; init() recreates it on re-use.
    _eventController.close();
  }

  /// Worker-pool bound: grows on demand up to this many concurrent FFI calls.
  /// Scales with the CPU count (work is largely I/O-bound in Go), floored so
  /// low-core devices still absorb a chat-open burst (history + members + pins +
  /// presence in parallel) and capped so idle isolates don't pile up memory.
  static int _poolSize() {
    final n = Platform.numberOfProcessors;
    if (n < 4) return 4;
    if (n > 12) return 12;
    return n;
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

/// Perform the actual FFI call (used by both sync and worker paths).
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

// ── Async worker-isolate pool ────────────────────────────────────────────────

/// A queued async call awaiting a free worker.
class _PendingRpc {
  _PendingRpc(this.requestBytes, this.completer);
  final Uint8List requestBytes;
  final Completer<Uint8List> completer;
}

/// A live worker isolate and its ports.
class _IsolateRpcWorker {
  _IsolateRpcWorker(this.isolate, this.commandPort, this.responsePort);

  /// The isolate handle (for kill on dispose).
  final Isolate isolate;

  /// Send request bytes here; send `null` to stop the worker.
  final SendPort commandPort;

  /// Worker replies (result bytes, or an error string) arrive here.
  final ReceivePort responsePort;

  /// The call currently being served by this worker, if any.
  Completer<Uint8List>? inFlight;
}

/// Bounded pool of reusable worker isolates for blocking FFI calls.
///
/// Workers are spawned lazily as concurrent demand rises, up to [_maxWorkers],
/// and then reused for the lifetime of the bridge. Each worker opens the shared
/// library and resolves the Go exports exactly once (the OS dlopen is
/// reference-counted, so this is cheap), amortising that cost across every call
/// it serves instead of paying it per call as the old `Isolate.run` path did.
class _RpcWorkerPool {
  _RpcWorkerPool(this._libPath, this._maxWorkers);

  final String _libPath;
  final int _maxWorkers;

  final List<_IsolateRpcWorker> _workers = [];
  final List<_IsolateRpcWorker> _idle = [];
  final Queue<_PendingRpc> _queue = Queue<_PendingRpc>();

  /// Workers currently being spawned (counted so we never overshoot the bound).
  int _spawning = 0;
  bool _disposed = false;

  Future<Uint8List> run(Uint8List requestBytes) {
    if (_disposed) {
      return Future.error(StateError('Bridge disposed; cannot make calls.'));
    }
    final completer = Completer<Uint8List>();
    _queue.add(_PendingRpc(requestBytes, completer));
    _dispatch();
    return completer.future;
  }

  void _dispatch() {
    // Hand queued calls to any idle workers.
    while (_queue.isNotEmpty && _idle.isNotEmpty) {
      final worker = _idle.removeLast();
      final pending = _queue.removeFirst();
      worker.inFlight = pending.completer;
      worker.commandPort.send(pending.requestBytes);
    }
    // Grow the pool to cover the remaining backlog, up to the bound. Workers
    // already spawning will pick up part of the queue once they connect.
    var toSpawn = _queue.length - _spawning;
    final room = _maxWorkers - _workers.length - _spawning;
    if (toSpawn > room) toSpawn = room;
    for (var i = 0; i < toSpawn; i++) {
      _spawning++;
      _spawnWorker();
    }
  }

  Future<void> _spawnWorker() async {
    final setupPort = ReceivePort();
    final responsePort = ReceivePort();
    final ready = setupPort.first;
    try {
      final isolate = await Isolate.spawn(
        _rpcWorkerEntry,
        [_libPath, setupPort.sendPort, responsePort.sendPort],
        debugName: 'uniclient-rpc-worker',
      );
      final commandPort = (await ready) as SendPort;
      setupPort.close();
      _spawning--;

      if (_disposed) {
        responsePort.close();
        isolate.kill(priority: Isolate.immediate);
        return;
      }

      final worker = _IsolateRpcWorker(isolate, commandPort, responsePort);
      responsePort.listen((msg) => _onResult(worker, msg));
      _workers.add(worker);
      _idle.add(worker);
      _dispatch();
    } catch (e) {
      setupPort.close();
      responsePort.close();
      _spawning--;
      // Only fail the backlog if nothing else can possibly serve it. The main
      // isolate already validated the library path in init(), so a worker
      // failing here is a genuine, rare resource error.
      if (!_disposed && _workers.isEmpty && _spawning == 0) {
        _failQueue(e);
      }
    }
  }

  void _onResult(_IsolateRpcWorker worker, dynamic msg) {
    final completer = worker.inFlight;
    worker.inFlight = null;
    if (completer != null && !completer.isCompleted) {
      if (msg is Uint8List) {
        completer.complete(msg);
      } else {
        completer.completeError(StateError(msg.toString()));
      }
    }
    if (_disposed) return;
    _idle.add(worker);
    _dispatch();
  }

  void _failQueue(Object error) {
    while (_queue.isNotEmpty) {
      final pending = _queue.removeFirst();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final cancelled = StateError('Bridge disposed; pending call cancelled.');
    for (final worker in _workers) {
      worker.commandPort.send(null); // ask the worker loop to stop
      worker.responsePort.close();
      worker.isolate.kill(priority: Isolate.beforeNextEvent);
      // Fail whatever this worker was mid-serving: its responsePort is now
      // closed, so _onResult can never fire to complete the call. Without this
      // the awaiting Future would hang forever across a dispose→re-init cycle.
      final inFlight = worker.inFlight;
      worker.inFlight = null;
      if (inFlight != null && !inFlight.isCompleted) {
        inFlight.completeError(cancelled);
      }
    }
    _workers.clear();
    _idle.clear();
    _failQueue(cancelled);
  }
}

/// RPC worker isolate entry point. Opens the shared library and resolves the Go
/// exports once, then serves many calls over [commandPort], replying on the
/// pool-provided response port. A `null` command stops the worker.
///
/// args: [libPath (String), setupPort (SendPort), responsePort (SendPort)].
void _rpcWorkerEntry(List<dynamic> args) {
  final libPath = args[0] as String;
  final setupPort = args[1] as SendPort;
  final responsePort = args[2] as SendPort;

  final lib = DynamicLibrary.open(libPath);
  final callWithLen = lib
      .lookupFunction<_BridgeCallWithLenC, _BridgeCallWithLenDart>(
        'BridgeCallWithLen',
      );
  final free = lib.lookupFunction<_BridgeFreeC, _BridgeFreeDart>('BridgeFree');

  // Hand our command port back to the pool, then serve requests on it.
  final commandPort = ReceivePort();
  setupPort.send(commandPort.sendPort);

  commandPort.listen((msg) {
    if (msg == null) {
      commandPort.close(); // stop signal from the pool
      return;
    }
    final requestBytes = msg as Uint8List;
    try {
      responsePort.send(_doCall(callWithLen, free, requestBytes));
    } catch (e) {
      // Surface the failure to the awaiting caller rather than dropping it.
      responsePort.send('rpc worker call failed: $e');
    }
  });
}

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
