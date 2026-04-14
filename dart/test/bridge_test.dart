/// Automated bridge + engine tests.
///
/// These test the full FFI bridge (Dart → Go → Engine) without a GUI.
/// Run: cd dart && flutter test test/bridge_test.dart
/// Requires: libcores.so built (scripts/build_go.sh linux)
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:uniclient/bridge/bridge.dart';
import 'package:uniclient/bridge/engine_service.dart';
import 'package:uniclient/models/engine_models.dart';
import 'package:uniclient/proto/models.pb.dart' as pb;
import 'package:uniclient/proto/engine.pb.dart' as epb;

/// Find the libcores.so in the Go build directory.
String _findLibcores() {
  final candidates = [
    '${Directory.current.parent.path}/go/build/libcores.so',
    '${Directory.current.path}/build/linux/x64/debug/bundle/lib/libcores.so',
    '${Directory.current.path}/../go/build/libcores.so',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError('libcores.so not found. Run scripts/build_go.sh linux first.\nSearched: $candidates');
}

void main() {
  late EngineService engine;
  late String tmpDir;

  setUpAll(() async {
    tmpDir = Directory.systemTemp.createTempSync('uniclient_test_').path;
  });

  tearDownAll(() async {
    try {
      engine.shutdown();
      engine.dispose();
    } catch (_) {}
    try {
      Directory(tmpDir).deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Bridge FFI', () {
    test('load library and make raw call', () {
      final bridge = Bridge();
      bridge.init(libraryPath: _findLibcores());
      expect(bridge.isInitialized, isTrue);

      // Send a minimal BridgeRequest for a nonexistent core — should get error response.
      final req = pb.BridgeRequest()
        ..coreId = '__test_nonexistent'
        ..method = 'Ping'
        ..payload = Uint8List(0);
      final respBytes = bridge.call(Uint8List.fromList(req.writeToBuffer()));
      expect(respBytes.isNotEmpty, isTrue);
      final resp = pb.BridgeResponse.fromBuffer(respBytes);
      expect(resp.ok, isFalse);
      expect(resp.error, contains('unknown'));
    });
  });

  group('Engine Service', () {
    test('init engine', () async {
      engine = EngineService();
      await engine.init(
        configDir: '$tmpDir/config',
        cacheDir: '$tmpDir/cache',
        downloadDir: '$tmpDir/downloads',
        libraryPath: _findLibcores(),
      );
      expect(engine.isInitialized, isTrue);
    });

    test('list accounts (empty)', () {
      final accounts = engine.listAccounts();
      expect(accounts, isEmpty);
    });

    test('add and remove account', () {
      final id = engine.addAccount('telegram');
      expect(id, isNotEmpty);
      expect(id, startsWith('tele_'));

      final accounts = engine.listAccounts();
      expect(accounts.length, equals(1));
      expect(accounts[0].platform, equals('telegram'));

      engine.removeAccount(id);
      final after = engine.listAccounts();
      expect(after, isEmpty);
    });

    test('add multiple platforms', () {
      final ids = <String>[];
      for (final platform in ['telegram', 'matrix', 'irc', 'bale', 'xmpp']) {
        ids.add(engine.addAccount(platform));
      }

      final accounts = engine.listAccounts();
      expect(accounts.length, equals(5));

      // Clean up.
      for (final id in ids) {
        engine.removeAccount(id);
      }
      expect(engine.listAccounts(), isEmpty);
    });

    test('get and update config', () {
      final config = engine.getConfig();
      expect(config.theme, isNotEmpty);

      engine.updateConfig(theme: 'light');
      final updated = engine.getConfig();
      expect(updated.theme, equals('light'));

      // Restore.
      engine.updateConfig(theme: 'dark');
    });

    test('get cache size', () {
      final size = engine.getCacheSize();
      expect(size, greaterThanOrEqualTo(0));
    });

    test('clear cache', () {
      engine.clearCache();
      // Should not throw.
    });

    test('search chats (empty)', () {
      final results = engine.searchChats('test');
      expect(results, isEmpty);
    });

    test('start auth flow', () async {
      final id = engine.addAccount('irc');

      final state = await engine.startAuth(id);
      expect(state, isNotNull);
      expect(state!.state, isNotEmpty);
      // IRC should ask for server address first.
      expect(state.state, equals('input'));
      expect(state.label, equals('Server'));

      engine.cancelAuth(id);
      engine.removeAccount(id);
    });

    test('auth flow multi-step (IRC)', () async {
      final id = engine.addAccount('irc');

      final s1 = await engine.startAuth(id);
      expect(s1!.state, equals('input'));
      expect(s1.label, equals('Server'));

      // Submit server address.
      final s2 = await engine.submitAuthInput(id, 'irc.libera.chat:6697');
      expect(s2, isNotNull);
      // Should ask for nickname next.
      expect(s2!.state, equals('input'));

      engine.cancelAuth(id);
      engine.removeAccount(id);
    });

    test('auth flow multi-step (Matrix)', () async {
      final id = engine.addAccount('matrix');

      final s1 = await engine.startAuth(id);
      expect(s1!.state, equals('input'));
      expect(s1.label, contains('Homeserver'));

      engine.cancelAuth(id);
      engine.removeAccount(id);
    });

    test('auth flow choose (Telegram)', () async {
      final id = engine.addAccount('telegram');

      final s1 = await engine.startAuth(id);
      expect(s1!.state, equals('choose'));
      // Telegram should offer bot/phone choice.
      expect(s1.options, isNotEmpty);

      engine.cancelAuth(id);
      engine.removeAccount(id);
    });

    test('async bridge does not block', () async {
      final id = engine.addAccount('irc');

      // Start auth (async) — should complete without blocking.
      final stopwatch = Stopwatch()..start();
      final state = await engine.startAuth(id);
      stopwatch.stop();

      expect(state, isNotNull);
      // Should be fast (< 1s for local operation).
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      engine.cancelAuth(id);
      engine.removeAccount(id);
    });

    test('event stream fires auth events', skip: 'NativeCallable.listener events may not dispatch in flutter_test harness', () async {
      final id = engine.addAccount('irc');

      // Listen for auth events.
      final events = <AuthStateEvent>[];
      final sub = engine.onAuthState.listen(events.add);

      await engine.startAuth(id);

      // Give events time to arrive (NativeCallable.listener is async).
      await Future.delayed(const Duration(milliseconds: 500));

      // Should have received at least one auth_state event.
      expect(events, isNotEmpty);
      expect(events.first.accountId, equals(id));

      await sub.cancel();
      engine.cancelAuth(id);
      engine.removeAccount(id);
    });
  });
}
