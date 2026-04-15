/// Full Flutter render test — logs into every platform via the real engine,
/// then pumps the actual widget tree and verifies it renders without crashing.
///
/// This tests the complete pipeline: Go engine → FFI → Dart models → Provider state → widgets.
///
/// Run: cd dart && flutter test test/flutter_render_test.dart --timeout 600s
/// Requires: libcores.so built, Docker containers for Matrix/Mumble/TeamSpeak
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:uniclient/bridge/engine_service.dart';
import 'package:uniclient/models/engine_models.dart';
import 'package:uniclient/state/app_state.dart';
import 'package:uniclient/state/chat_state.dart';
import 'package:uniclient/state/auth_state.dart';
import 'package:uniclient/screens/home_screen.dart';
import 'package:uniclient/theme/theme.dart';

// ── Helpers ──

String _findLibcores() {
  for (final path in [
    '${Directory.current.parent.path}/go/build/libcores.so',
    '${Directory.current.path}/../go/build/libcores.so',
  ]) {
    if (File(path).existsSync()) return path;
  }
  throw StateError('libcores.so not found');
}

String _findProjectRoot() {
  var dir = Directory.current.path;
  if (dir.endsWith('/dart')) return dir.substring(0, dir.length - 5);
  return Directory.current.parent.path;
}

void _seedSession(String tmpDir, String platform, String fileName) {
  final src = File('${_findProjectRoot()}/auth/$fileName');
  if (!src.existsSync()) return;
  final dest = '$tmpDir/config/sessions/$platform';
  Directory(dest).createSync(recursive: true);
  src.copySync('$dest/session_1.json');
}

/// Drive auth flow to completion. Returns true if authed.
Future<bool> _auth(EngineService engine, String accountId, List<String> inputs, {String? choose}) async {
  final s1 = await engine.startAuth(accountId);
  if (s1 == null) return false;

  AuthStateData? cur = s1;

  if (cur!.state == 'choose' && choose != null) {
    cur = await engine.submitAuthInput(accountId, choose);
  }

  int idx = 0;
  while (cur != null && cur.state != 'ready' && cur.state != 'error' && idx < inputs.length) {
    if (cur.state == 'input' || cur.state == 'otp' || cur.state == '2fa') {
      cur = await engine.submitAuthInput(accountId, inputs[idx++]);
    } else {
      break;
    }
  }

  if (cur?.state == 'ready') return true;
  if (cur?.state == 'otp' || cur?.state == '2fa') {
    engine.cancelAuth(accountId);
  }
  return false;
}

/// Build the full app widget tree backed by real engine.
Widget _buildApp(EngineService engine, AppState appState, ChatState chatState, AuthState authState) {
  return MultiProvider(
    providers: [
      Provider<EngineService>.value(value: engine),
      ChangeNotifierProvider.value(value: appState),
      ChangeNotifierProvider.value(value: chatState),
      ChangeNotifierProvider.value(value: authState),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const HomeScreen(),
    ),
  );
}

// ── Test ──

void main() {
  late EngineService engine;
  late AppState appState;
  late ChatState chatState;
  late AuthState authState;
  late String tmpDir;
  final authedAccounts = <String, String>{}; // platform → accountId

  setUpAll(() async {
    tmpDir = Directory.systemTemp.createTempSync('uniclient_render_test_').path;

    engine = EngineService();
    await engine.init(
      configDir: '$tmpDir/config',
      cacheDir: '$tmpDir/cache',
      downloadDir: '$tmpDir/downloads',
      libraryPath: _findLibcores(),
    );

    appState = AppState(engine);
    chatState = ChatState(engine);
    authState = AuthState(engine);

    // Seed sessions for platforms that need them.
    _seedSession(tmpDir, 'xmpp', 'xmpp_session.json');
    _seedSession(tmpDir, 'mumble', 'mumble_session.json');
    _seedSession(tmpDir, 'teamspeak', 'teamspeak_session.json');
    _seedSession(tmpDir, 'deltachat', 'deltachat_interop_session.json');
    _seedSession(tmpDir, 'telegram', 'telegram_user_session.json');
  });

  tearDownAll(() async {
    // Clean up all accounts.
    for (final id in authedAccounts.values) {
      try { engine.removeAccount(id); } catch (_) {}
    }
    try { engine.shutdown(); } catch (_) {}
    try { engine.dispose(); } catch (_) {}
    try { Directory(tmpDir).deleteSync(recursive: true); } catch (_) {}
  });

  // ── Phase 1: Log into every platform ──

  group('Login', () {
    test('IRC (anonymous)', () async {
      final id = engine.addAccount('irc');
      final nick = 'uctest_${DateTime.now().millisecondsSinceEpoch % 100000}';
      final ok = await _auth(engine, id, ['irc.libera.chat:6697', nick, '']);
      print('  IRC: ${ok ? "OK" : "FAIL"}');
      if (ok) authedAccounts['irc'] = id;
    });

    test('GitHub (token)', () async {
      final id = engine.addAccount('github');
      final token = Platform.environment['GITHUB_TOKEN'] ?? '';
      final ok = await _auth(engine, id, [token]);
      print('  GitHub: ${ok ? "OK" : "FAIL"}');
      if (ok) authedAccounts['github'] = id;
    });

    test('XMPP (password)', () async {
      final id = engine.addAccount('xmpp');
      final jid = Platform.environment['XMPP_JID'] ?? 'uctest1776076689@yax.im';
      final pw = Platform.environment['XMPP_PASSWORD'] ?? 'testpass123';
      final ok = await _auth(engine, id, [jid, pw]);
      print('  XMPP: ${ok ? "OK" : "FAIL"}');
      if (ok) authedAccounts['xmpp'] = id;
    });

    test('Telegram (session)', () async {
      final id = engine.addAccount('telegram');
      final phone = Platform.environment['TG_PHONE'] ?? '+96877354040';
      final ok = await _auth(engine, id, [phone], choose: 'phone');
      print('  Telegram: ${ok ? "OK (session valid)" : "SKIP (OTP needed)"}');
      if (ok) {
        authedAccounts['telegram'] = id;
      } else {
        engine.removeAccount(id);
      }
    });

    test('DeltaChat (IMAP)', () async {
      final id = engine.addAccount('deltachat');
      final email = Platform.environment['DC_B_EMAIL'] ?? 'epmy2e7k6@nine.testrun.org';
      final pw = Platform.environment['DC_B_PASSWORD'] ?? r'DV*1~:~Kxg90';
      final ok = await _auth(engine, id, [email, pw]);
      print('  DeltaChat: ${ok ? "OK" : "FAIL"}');
      if (ok) authedAccounts['deltachat'] = id;
    });

    test('Matrix (local Dendrite)', () async {
      final id = engine.addAccount('matrix');
      final hs = Platform.environment['MATRIX_HOMESERVER'] ?? 'http://localhost:8008';
      final user = Platform.environment['MATRIX_USERNAME'] ?? 'uniclient1';
      final pw = Platform.environment['MATRIX_PASSWORD'] ?? 'testpass123';
      // Matrix: homeserver → username → password (no choose step)
      final s1 = await engine.startAuth(id);
      AuthStateData? cur = s1;
      cur = await engine.submitAuthInput(id, hs);
      if (cur?.state == 'choose') {
        cur = await engine.submitAuthInput(id, 'password');
      }
      if (cur?.state == 'input') {
        cur = await engine.submitAuthInput(id, user);
      }
      if (cur?.state == 'input') {
        cur = await engine.submitAuthInput(id, pw);
      }
      final ok = cur?.state == 'ready';
      print('  Matrix: ${ok ? "OK" : "FAIL (${cur?.state})"}');
      if (ok) authedAccounts['matrix'] = id;
    });

    test('Mumble (local Docker)', () async {
      final id = engine.addAccount('mumble');
      final ok = await _auth(engine, id, ['localhost:64738', 'uctest_render']);
      print('  Mumble: ${ok ? "OK" : "FAIL"}');
      if (ok) authedAccounts['mumble'] = id;
    });

    test('TeamSpeak (local Docker)', () async {
      final id = engine.addAccount('teamspeak');
      final ok = await _auth(engine, id, ['localhost:9987', 'uctest_render']);
      print('  TeamSpeak: ${ok ? "OK" : "FAIL"}');
      if (ok) authedAccounts['teamspeak'] = id;
    });
  });

  // ── Phase 2: Let sync happen, then snapshot the data ──

  test('wait for sync', () async {
    await Future.delayed(const Duration(seconds: 5));
    // Refresh the app state so it picks up all accounts.
    final accounts = engine.listAccounts();
    print('  Accounts after sync: ${accounts.length}');
    for (final a in accounts) {
      print('    - ${a.platform}: ${a.displayName} (${a.connState.name})');
    }
  });

  // ── Phase 3: Load chats + messages for every platform ──

  group('Load data', () {
    test('load chats for all platforms', () {
      for (final entry in authedAccounts.entries) {
        final chats = engine.getChatList(accountId: entry.value, limit: 20);
        print('  ${entry.key}: ${chats.length} chats');
        for (final c in chats.take(3)) {
          print('    - ${c.title} (${c.type.name}) members=${c.memberCount}');
        }
      }
    });

    test('load messages from first chat of each platform', () {
      for (final entry in authedAccounts.entries) {
        final chats = engine.getChatList(accountId: entry.value, limit: 1);
        if (chats.isEmpty) {
          print('  ${entry.key}: no chats, skipping messages');
          continue;
        }
        final chat = chats.first;
        final msgs = engine.getMessages(entry.value, chat.chatId, limit: 10);
        print('  ${entry.key} → "${chat.title}": ${msgs.length} messages');
        for (final m in msgs.take(3)) {
          final sender = m.senderName.isNotEmpty ? m.senderName : (m.isSent ? 'me' : '?');
          final preview = m.contentText.length > 60
              ? '${m.contentText.substring(0, 60)}...'
              : m.contentText;
          print('    [$sender] $preview');
          // Verify message fields are sane
          expect(m.accountId, isNotEmpty);
          expect(m.chatId, isNotEmpty);
          expect(m.msgId, isNotEmpty);
          expect(m.timestamp, greaterThan(0));
        }
      }
    });
  });

  // ── Phase 4: Render the full Flutter UI ──

  group('Render', () {
    testWidgets('HomeScreen renders with real engine (loading state)', (tester) async {
      // First, test that the loading state renders.
      final freshAppState = AppState(engine);
      await tester.pumpWidget(_buildApp(engine, freshAppState, chatState, authState));
      await tester.pump();

      // Should show loading spinner (engine not yet initialized via appState).
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Starting engine...'), findsOneWidget);
    });

    testWidgets('HomeScreen renders with initialized engine', (tester) async {
      // Mark appState as ready by calling initForTest — engine is already running from setUpAll.
      // Don't call full initialize() which triggers connectAllAccounts() and blocks.
      appState.initForTest(engine.listAccounts());

      await tester.pumpWidget(_buildApp(engine, appState, chatState, authState));
      await tester.pump(const Duration(seconds: 1));

      // HomeScreen should be rendered — look for the scaffold.
      expect(find.byType(Scaffold), findsWidgets);
      // Platform rail should be present.
      expect(find.byType(HomeScreen), findsOneWidget);

      print('  HomeScreen rendered OK with ${authedAccounts.length} accounts');
    });

    testWidgets('HomeScreen renders at narrow width (mobile)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildApp(engine, appState, chatState, authState));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(HomeScreen), findsOneWidget);
      print('  Narrow layout (400px) rendered OK');

      // Reset view size.
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('HomeScreen renders at wide width (desktop)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildApp(engine, appState, chatState, authState));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(HomeScreen), findsOneWidget);
      print('  Wide layout (1400px) rendered OK');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('load chat list via ChatState and render', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      // Load chats into ChatState.
      chatState.loadChats();

      await tester.pumpWidget(_buildApp(engine, appState, chatState, authState));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(HomeScreen), findsOneWidget);

      final totalChats = chatState.chats.length;
      print('  ChatState loaded $totalChats chats across all platforms');

      // Each chat should be a ListTile or similar in the sidebar.
      if (totalChats > 0) {
        print('  First chat: "${chatState.chats.first.title}" (${chatState.chats.first.type.name})');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('open a chat and render messages', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      // Find a chat with messages to open.
      ChatInfo? chatToOpen;
      for (final entry in authedAccounts.entries) {
        final chats = engine.getChatList(accountId: entry.value, limit: 5);
        for (final c in chats) {
          final msgs = engine.getMessages(entry.value, c.chatId, limit: 1);
          if (msgs.isNotEmpty) {
            chatToOpen = c;
            break;
          }
        }
        if (chatToOpen != null) break;
      }

      if (chatToOpen != null) {
        chatState.openChat(chatToOpen);
      }

      await tester.pumpWidget(_buildApp(engine, appState, chatState, authState));
      await tester.pump(const Duration(seconds: 1));

      if (chatToOpen != null) {
        print('  Opened chat: "${chatToOpen.title}" with ${chatState.messages.length} messages');
        expect(find.byType(HomeScreen), findsOneWidget);
        if (chatState.messages.isNotEmpty) {
          final msg = chatState.messages.first;
          print('  Latest message: "${msg.contentText.length > 50 ? '${msg.contentText.substring(0, 50)}...' : msg.contentText}"');
        }
        chatState.closeChat(); // Stop polling timer
      } else {
        print('  No chats with messages found — skipping open chat test');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('open Mumble voice channel and render', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      final mumbleId = authedAccounts['mumble'];
      if (mumbleId == null) {
        print('  [SKIP] Mumble not connected');
        return;
      }

      final chats = engine.getChatList(accountId: mumbleId, limit: 10);
      print('  Mumble channels: ${chats.length}');
      for (final c in chats) {
        print('    - ${c.title} (${c.type.name}) members=${c.memberCount}');
      }

      if (chats.isNotEmpty) {
        chatState.openChat(chats.first);
      }

      await tester.pumpWidget(_buildApp(engine, appState, chatState, authState));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(HomeScreen), findsOneWidget);
      print('  Mumble voice channel rendered OK');
      chatState.closeChat(); // Stop polling timer

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('open TeamSpeak channels and render', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      final tsId = authedAccounts['teamspeak'];
      if (tsId == null) {
        print('  [SKIP] TeamSpeak not connected');
        return;
      }

      final chats = engine.getChatList(accountId: tsId, limit: 10);
      print('  TeamSpeak channels: ${chats.length}');
      for (final c in chats) {
        print('    - ${c.title} (${c.type.name})');
      }

      // Open each channel and verify rendering.
      for (final c in chats) {
        chatState.openChat(c);

        await tester.pumpWidget(_buildApp(engine, appState, chatState, authState));
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(HomeScreen), findsOneWidget);
        print('    Rendered: ${c.title} OK');
      }
      chatState.closeChat(); // Stop polling timer

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('render DeltaChat DM with messages', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      final dcId = authedAccounts['deltachat'];
      if (dcId == null) {
        print('  [SKIP] DeltaChat not connected');
        return;
      }

      final chats = engine.getChatList(accountId: dcId, limit: 10);
      print('  DeltaChat chats: ${chats.length}');

      for (final c in chats) {
        chatState.openChat(c);

        final msgs = chatState.messages;
        print('    "${c.title}": ${msgs.length} messages');

        await tester.pumpWidget(_buildApp(engine, appState, chatState, authState));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(HomeScreen), findsOneWidget);
        print('    Rendered OK');

        // Check message timestamps are valid.
        for (final m in msgs) {
          expect(m.timestamp, greaterThan(0), reason: 'Message ${m.msgId} has zero timestamp');
          final dt = m.dateTime;
          expect(dt.year, greaterThan(2000), reason: 'Message ${m.msgId} has year ${dt.year}');
        }
      }
      chatState.closeChat(); // Stop polling timer

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
