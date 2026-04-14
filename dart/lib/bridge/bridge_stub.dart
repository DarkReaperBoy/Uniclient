/// Stub implementation — should never be reached at runtime.
/// Conditional imports in bridge.dart select bridge_ffi.dart or bridge_web.dart.
library;

import 'dart:async';
import 'dart:typed_data';

class BridgeImpl {
  Stream<Uint8List> get events => const Stream.empty();
  bool get isInitialized => false;

  void init({String? libraryPath}) {
    throw UnsupportedError('No bridge implementation available for this platform');
  }

  Uint8List call(Uint8List requestBytes) {
    throw UnsupportedError('No bridge implementation available for this platform');
  }

  Future<Uint8List> callAsync(Uint8List requestBytes) {
    throw UnsupportedError('No bridge implementation available for this platform');
  }

  void dispose() {}
}
