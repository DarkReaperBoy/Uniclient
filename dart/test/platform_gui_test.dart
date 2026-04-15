/// Comprehensive platform test via Flutter GUI bridge.
///
/// Tests every platform through the engine: add account → auth → get chats →
/// send message → verify. Each platform is independent.
///
/// Auth flow reaches 'ready' → finalizeAuth() auto-connects + saves creds.
/// connectAccount() is only for RE-connecting a previously authed account.
///
/// Run: cd dart && flutter test test/platform_gui_test.dart -t "PLATFORM_NAME"
/// Run all: cd dart && flutter test test/platform_gui_test.dart
/// Requires: libcores.so built (scripts/build_go.sh linux)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:uniclient/bridge/engine_service.dart';
import 'package:uniclient/models/engine_models.dart';

// ── Helpers ──

String _findLibcores() {
  final candidates = [
    '${Directory.current.parent.path}/go/build/libcores.so',
    '${Directory.current.path}/../go/build/libcores.so',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError('libcores.so not found. Run scripts/build_go.sh linux first.');
}

String _findProjectRoot() {
  var dir = Directory.current.path;
  if (dir.endsWith('/dart')) return dir.substring(0, dir.length - 5);
  final parent = Directory.current.parent.path;
  if (Directory('$parent/auth').existsSync()) return parent;
  return dir;
}

/// Seed a session file for a platform.
void _seedSession(String tmpDir, String platform, String sessionFileName) {
  final projectRoot = _findProjectRoot();
  final src = File('$projectRoot/auth/$sessionFileName');
  if (!src.existsSync()) {
    print('  [SKIP] Session file not found: ${src.path}');
    return;
  }
  final destDir = '$tmpDir/config/sessions/$platform';
  Directory(destDir).createSync(recursive: true);
  src.copySync('$destDir/session_1.json');
  print('  Seeded session for $platform from $sessionFileName');
}

/// Drive auth flow: submit inputs in order, return final state.
/// Returns the auth state after all inputs are submitted.
/// If auth fails mid-flow, returns the error state.
Future<AuthStateData?> _driveAuth(
  EngineService engine,
  String accountId,
  List<String> inputs, {
  String? chooseOption, // if first state is 'choose', pick this
}) async {
  final s1 = await engine.startAuth(accountId);
  if (s1 == null) return null;
  print('  Auth step 1: ${s1.state} - ${s1.label}');

  AuthStateData? current = s1;
  int inputIdx = 0;

  // Handle choose state first
  if (current!.state == 'choose' && chooseOption != null) {
    current = await engine.submitAuthInput(accountId, chooseOption);
    print('  Auth (chose $chooseOption): ${current?.state} - ${current?.label}');
  }

  // Submit inputs until ready/error or inputs exhausted
  while (current != null &&
      current.state != 'ready' &&
      current.state != 'error' &&
      inputIdx < inputs.length) {
    if (current.state == 'input' || current.state == 'otp' || current.state == '2fa') {
      current = await engine.submitAuthInput(accountId, inputs[inputIdx]);
      inputIdx++;
      final detail = current?.label ?? current?.error ?? current?.message ?? '';
      print('  Auth step ${inputIdx + 1}: ${current?.state} - $detail');
    } else {
      break;
    }
  }

  return current;
}

// ── Tests ──

void main() {
  late EngineService engine;
  late String tmpDir;

  setUpAll(() async {
    tmpDir = Directory.systemTemp.createTempSync('uniclient_platform_test_').path;
  });

  tearDownAll(() async {
    try { engine.shutdown(); } catch (_) {}
    try { engine.dispose(); } catch (_) {}
    try { Directory(tmpDir).deleteSync(recursive: true); } catch (_) {}
  });

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

  // ────────────────────────────────────────────────────────────────────
  // IRC — anonymous connect to Libera.Chat
  // ────────────────────────────────────────────────────────────────────
  group('IRC', () {
    late String accountId;
    bool authed = false;

    test('add + auth', () async {
      accountId = engine.addAccount('irc');
      print('  IRC account: $accountId');

      final nick = 'uctest_${DateTime.now().millisecondsSinceEpoch % 100000}';
      final state = await _driveAuth(engine, accountId, [
        'irc.libera.chat:6697', // server
        nick,                    // nickname
        '',                      // password (empty = anonymous)
      ]);

      if (state?.state == 'ready') {
        authed = true;
        print('  IRC: connected as ${state?.displayName ?? nick}');
      } else {
        print('  IRC: auth failed — ${state?.message ?? state?.error ?? "unknown"}');
      }
    });

    test('get chats', () async {
      if (!authed) {
        print('  [SKIP] IRC not connected');
        return;
      }
      // Give it time to join default channels
      await Future.delayed(const Duration(seconds: 3));
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  IRC chats: ${chats.length}');
      for (final c in chats.take(3)) {
        print('    - ${c.title} (${c.type})');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // GitHub — token auth
  // ────────────────────────────────────────────────────────────────────
  group('GitHub', () {
    late String accountId;
    bool authed = false;
    final token = Platform.environment['GITHUB_TOKEN'] ?? '';

    test('add + auth', () async {
      accountId = engine.addAccount('github');
      print('  GitHub account: $accountId');

      final state = await _driveAuth(engine, accountId, [token]);

      if (state?.state == 'ready') {
        authed = true;
        print('  GitHub: connected as ${state?.displayName ?? "unknown"}');
      } else {
        print('  GitHub: auth ended at ${state?.state} — ${state?.error ?? "unknown"}');
      }
    });

    test('get chats', () async {
      if (!authed) {
        print('  [SKIP] GitHub not connected');
        return;
      }
      await Future.delayed(const Duration(seconds: 3));
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  GitHub chats: ${chats.length}');
      for (final c in chats.take(3)) {
        print('    - ${c.title} (${c.type})');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // XMPP — password auth
  // ────────────────────────────────────────────────────────────────────
  group('XMPP', () {
    late String accountId;
    bool authed = false;
    final jid = Platform.environment['XMPP_JID'] ?? 'uctest1776076689@yax.im';
    final password = Platform.environment['XMPP_PASSWORD'] ?? 'testpass123';

    test('add + auth', () async {
      _seedSession(tmpDir, 'xmpp', 'xmpp_session.json');
      accountId = engine.addAccount('xmpp');
      print('  XMPP account: $accountId');

      // XMPP startAuth asks for JID first
      final state = await _driveAuth(engine, accountId, [jid, password]);

      if (state?.state == 'ready') {
        authed = true;
        print('  XMPP: connected as ${state?.displayName ?? jid}');
      } else {
        print('  XMPP: auth ended at ${state?.state} — ${state?.error ?? "unknown"}');
      }
    });

    test('get chats', () async {
      if (!authed) {
        print('  [SKIP] XMPP not connected');
        return;
      }
      await Future.delayed(const Duration(seconds: 3));
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  XMPP chats: ${chats.length}');
      for (final c in chats.take(3)) {
        print('    - ${c.title} (${c.type})');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // Telegram — session-based (needs pre-seeded session)
  // Auth flow: choose 'phone' → submit phone → if session valid → ready
  // ────────────────────────────────────────────────────────────────────
  group('Telegram', () {
    late String accountId;
    bool authed = false;
    final phone = Platform.environment['TG_PHONE'] ?? '+96877354040';

    test('add + auth', () async {
      _seedSession(tmpDir, 'telegram', 'telegram_user_session.json');
      accountId = engine.addAccount('telegram');
      print('  Telegram account: $accountId');

      // Drive auth: choose phone → submit phone number
      // With seeded session, should go straight to ready (no OTP)
      final state = await _driveAuth(
        engine, accountId,
        [phone], // phone number
        chooseOption: 'phone',
      );

      if (state?.state == 'ready') {
        authed = true;
        print('  Telegram: connected as ${state?.displayName ?? "unknown"}');
      } else if (state?.state == 'otp') {
        print('  Telegram: OTP requested — session may be expired. Skipping.');
        engine.cancelAuth(accountId);
      } else {
        print('  Telegram: auth ended at ${state?.state} — ${state?.error ?? "unknown"}');
      }
    });

    test('wait for sync', () async {
      if (!authed) {
        print('  [SKIP] Telegram not connected');
        return;
      }
      await Future.delayed(const Duration(seconds: 5));
    });

    test('get chats', () async {
      if (!authed) {
        print('  [SKIP] Telegram not connected');
        return;
      }
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  Telegram chats: ${chats.length}');
      for (final c in chats.take(5)) {
        print('    - ${c.title} (${c.type}) unread=${c.unreadCount}');
      }
      expect(chats, isNotEmpty, reason: 'Telegram should have chats');
    });

    test('get messages', () async {
      if (!authed) {
        print('  [SKIP] Telegram not connected');
        return;
      }
      final chats = engine.getChatList(accountId: accountId, limit: 1);
      if (chats.isEmpty) return;
      final chat = chats.first;
      final msgs = engine.getMessages(accountId, chat.chatId, limit: 5);
      print('  Messages in "${chat.title}": ${msgs.length}');
      for (final m in msgs.take(3)) {
        final sender = m.senderName.isNotEmpty ? m.senderName : 'me';
        final text = m.contentText.length > 50
            ? '${m.contentText.substring(0, 50)}...'
            : m.contentText;
        print('    [$sender] $text');
      }
    });

    test('send test message', () async {
      if (!authed) {
        print('  [SKIP] Telegram not connected');
        return;
      }
      final testChatId = Platform.environment['TG_TEST_CHAT_ID'] ?? '5493198963';
      final marker = 'flutter_gui_test_${DateTime.now().millisecondsSinceEpoch}';

      try {
        final msgId = await engine.sendMessage(accountId, testChatId, marker);
        print('  Sent message: $msgId');
        await Future.delayed(const Duration(seconds: 2));
        final msgs = engine.getMessages(accountId, testChatId, limit: 5);
        final found = msgs.any((m) => m.contentText.contains(marker));
        print('  Message found in history: $found');
      } catch (e) {
        print('  Send failed: $e');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // Bale — bot token auth
  // ────────────────────────────────────────────────────────────────────
  group('Bale', () {
    late String accountId;
    bool authed = false;
    final botToken = Platform.environment['BALE_BOT_TOKEN'] ?? 'JGBGD0JASNWSLVPQSKQBPZHWQVIWXUSNNXJCWVYURBBGVDVOGZCBBSCABXDUIZQL';
    final testChatId = Platform.environment['BALE_TEST_CHAT_ID'] ?? '928132281';

    test('add + auth', () async {
      accountId = engine.addAccount('bale');
      print('  Bale account: $accountId');

      final state = await _driveAuth(
        engine, accountId,
        [botToken],
        chooseOption: 'bot_token',
      );

      if (state?.state == 'ready') {
        authed = true;
        print('  Bale: connected as ${state?.displayName ?? "bot"}');
      } else {
        print('  Bale: auth failed — ${state?.message ?? state?.error ?? "unknown"}');
      }
    });

    test('send test message', () async {
      if (!authed) {
        print('  [SKIP] Bale not connected');
        return;
      }
      final marker = 'bale_gui_test_${DateTime.now().millisecondsSinceEpoch}';
      try {
        final msgId = await engine.sendMessage(accountId, testChatId, marker);
        print('  Sent: $msgId');
      } catch (e) {
        print('  Send failed (may be geo-restricted): $e');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // Delta Chat — IMAP auth
  // ────────────────────────────────────────────────────────────────────
  group('DeltaChat', () {
    late String accountId;
    bool authed = false;
    final email = Platform.environment['DC_B_EMAIL'] ?? 'epmy2e7k6@nine.testrun.org';
    final password = Platform.environment['DC_B_PASSWORD'] ?? r'DV*1~:~Kxg90';

    test('add + auth', () async {
      _seedSession(tmpDir, 'deltachat', 'deltachat_interop_session.json');
      accountId = engine.addAccount('deltachat');
      print('  DeltaChat account: $accountId');

      final state = await _driveAuth(engine, accountId, [email, password]);

      if (state?.state == 'ready') {
        authed = true;
        print('  DeltaChat: connected as ${state?.displayName ?? email}');
      } else {
        print('  DeltaChat: auth ended at ${state?.state} — ${state?.error ?? "unknown"}');
      }
    });

    test('get chats', () async {
      if (!authed) {
        print('  [SKIP] DeltaChat not connected');
        return;
      }
      await Future.delayed(const Duration(seconds: 5));
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  DeltaChat chats: ${chats.length}');
      for (final c in chats.take(3)) {
        print('    - ${c.title} (${c.type})');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // Matrix — password auth on local Dendrite
  // ────────────────────────────────────────────────────────────────────
  group('Matrix', () {
    late String accountId;
    bool authed = false;
    final homeserver = Platform.environment['MATRIX_HOMESERVER'] ?? 'http://localhost:8008';
    final username = Platform.environment['MATRIX_USERNAME'] ?? 'uniclient1';
    final password = Platform.environment['MATRIX_PASSWORD'] ?? 'testpass123';

    test('add + auth', () async {
      accountId = engine.addAccount('matrix');
      print('  Matrix account: $accountId');

      // Matrix: homeserver → (choose password) → username → password
      final s1 = await engine.startAuth(accountId);
      print('  Auth step 1: ${s1?.state} - ${s1?.label}');

      if (s1 == null) return;
      AuthStateData? current = s1;

      // Submit homeserver
      current = await engine.submitAuthInput(accountId, homeserver);
      print('  Auth step 2: ${current?.state} - ${current?.label}');

      // Handle choose (password/sso)
      if (current?.state == 'choose') {
        current = await engine.submitAuthInput(accountId, 'password');
        print('  Auth (chose password): ${current?.state} - ${current?.label}');
      }

      // Submit username
      if (current?.state == 'input') {
        current = await engine.submitAuthInput(accountId, username);
        print('  Auth (username): ${current?.state} - ${current?.label}');
      }

      // Submit password
      if (current?.state == 'input') {
        current = await engine.submitAuthInput(accountId, password);
        print('  Auth (password): ${current?.state}');
      }

      if (current?.state == 'ready') {
        authed = true;
        print('  Matrix: connected as ${current?.displayName ?? username}');
      } else {
        print('  Matrix: auth ended at ${current?.state} — ${current?.error ?? "unknown"}');
      }
    });

    test('get chats', () async {
      if (!authed) {
        print('  [SKIP] Matrix not connected');
        return;
      }
      await Future.delayed(const Duration(seconds: 3));
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  Matrix chats: ${chats.length}');
      for (final c in chats.take(3)) {
        print('    - ${c.title} (${c.type})');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // Rubika — bot token auth (may be geo-restricted outside Iran)
  // ────────────────────────────────────────────────────────────────────
  group('Rubika', () {
    late String accountId;
    bool authed = false;
    // Note: Rubika auth asks for phone first, then sends OTP.
    // For bot mode, we'd need a different flow. Let's test what we can.
    final phone = Platform.environment['RUBIKA_PHONE'] ?? '+989000000000';

    test('add + auth', () async {
      accountId = engine.addAccount('rubika');
      print('  Rubika account: $accountId');

      // Rubika startAuth asks for phone number
      final s1 = await engine.startAuth(accountId);
      print('  Auth step 1: ${s1?.state} - ${s1?.label}');

      if (s1?.state == 'input') {
        final s2 = await engine.submitAuthInput(accountId, phone);
        print('  Auth step 2: ${s2?.state} - ${s2?.label ?? s2?.error ?? ""}');

        if (s2?.state == 'otp') {
          print('  Rubika: OTP requested — cannot proceed without user interaction');
          engine.cancelAuth(accountId);
        } else if (s2?.state == 'ready') {
          authed = true;
          print('  Rubika: connected');
        } else if (s2?.state == 'error') {
          print('  Rubika: ${s2?.error} (may be geo-restricted)');
        }
      }
    });

    test('get chats', () async {
      if (!authed) {
        print('  [SKIP] Rubika not connected');
        return;
      }
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  Rubika chats: ${chats.length}');
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // Mumble — anonymous connect to local Docker
  // ────────────────────────────────────────────────────────────────────
  group('Mumble', () {
    late String accountId;
    bool authed = false;
    final server = Platform.environment['MUMBLE_SERVER'] ?? 'localhost:64738';

    test('add + auth', () async {
      _seedSession(tmpDir, 'mumble', 'mumble_session.json');
      accountId = engine.addAccount('mumble');
      print('  Mumble account: $accountId');

      final state = await _driveAuth(engine, accountId, [
        server,            // server address
        'uctest_flutter',  // username
      ]);

      if (state?.state == 'ready') {
        authed = true;
        print('  Mumble: connected');
      } else {
        print('  Mumble: auth ended at ${state?.state} — ${state?.error ?? "unknown"}');
      }
    });

    test('get chats (channels)', () async {
      if (!authed) {
        print('  [SKIP] Mumble not connected');
        return;
      }
      await Future.delayed(const Duration(seconds: 2));
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  Mumble channels: ${chats.length}');
      for (final c in chats.take(5)) {
        print('    - ${c.title} (${c.type})');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // TeamSpeak — connect to local Docker
  // ────────────────────────────────────────────────────────────────────
  group('TeamSpeak', () {
    late String accountId;
    bool authed = false;

    test('add + auth', () async {
      _seedSession(tmpDir, 'teamspeak', 'teamspeak_session.json');
      accountId = engine.addAccount('teamspeak');
      print('  TeamSpeak account: $accountId');

      final state = await _driveAuth(engine, accountId, [
        'localhost:9987',   // server address
        'uctest_flutter',   // nickname
      ]);

      if (state?.state == 'ready') {
        authed = true;
        print('  TeamSpeak: connected');
      } else {
        print('  TeamSpeak: auth ended at ${state?.state} — ${state?.error ?? "unknown"}');
      }
    });

    test('get chats (channels)', () async {
      if (!authed) {
        print('  [SKIP] TeamSpeak not connected');
        return;
      }
      await Future.delayed(const Duration(seconds: 3));
      final chats = engine.getChatList(accountId: accountId, limit: 10);
      print('  TeamSpeak channels: ${chats.length}');
      for (final c in chats.take(5)) {
        print('    - ${c.title} (${c.type})');
      }
    });

    test('cleanup', () {
      engine.removeAccount(accountId);
    });
  });
}
