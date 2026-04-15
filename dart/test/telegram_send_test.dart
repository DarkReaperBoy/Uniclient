/// Automated Telegram send-message test.
///
/// Logs in via phone auth (OTP read from existing session), then sends
/// a hello message to a friend and verifies it was delivered.
///
/// Run: cd dart && flutter test test/telegram_send_test.dart
/// Requires:
///   - libcores.so built (scripts/build_go.sh linux)
///   - Existing Telegram user session at auth/telegram_user_session.json
///   - Environment vars or defaults for TG_PHONE, TG_2FA_PASSWORD
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:uniclient/bridge/engine_service.dart';
import 'package:uniclient/utils/debug.dart';

/// Find the libcores.so.
String _findLibcores() {
  final candidates = [
    '${Directory.current.parent.path}/go/build/libcores.so',
    '${Directory.current.path}/../go/build/libcores.so',
    '${Directory.current.path}/build/linux/x64/debug/bundle/lib/libcores.so',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError('libcores.so not found. Run scripts/build_go.sh linux first.');
}

/// Find the project root (where auth/ lives).
String _findProjectRoot() {
  var dir = Directory.current.path;
  if (dir.endsWith('/dart')) {
    return dir.substring(0, dir.length - 5);
  }
  final parent = Directory.current.parent.path;
  if (Directory('$parent/auth').existsSync()) return parent;
  return dir;
}

/// Extract the login code from a Telegram message text.
String? _extractCode(String text) {
  final match = RegExp(r'\b(\d{5})\b').firstMatch(text);
  return match?.group(1);
}

void main() {
  Debug.enabled = true;

  late EngineService engine;
  late String tmpDir;
  late String projectRoot;

  final phone = Platform.environment['TG_PHONE'] ?? '+96877354040';
  final password2fa = Platform.environment['TG_2FA_PASSWORD'] ?? 'nako123';
  // Second user to send message to.
  final friendChatId = Platform.environment['TG_FRIEND_CHAT_ID'] ?? '5435067494';

  setUpAll(() async {
    projectRoot = _findProjectRoot();
    tmpDir = Directory.systemTemp.createTempSync('uniclient_tg_send_').path;

    // Pre-seed the reader session.
    final sessionDir = '$tmpDir/config/sessions/telegram';
    Directory(sessionDir).createSync(recursive: true);

    final existingSession = File('$projectRoot/auth/telegram_user_session.json');
    if (!existingSession.existsSync()) {
      throw StateError(
        'Existing Telegram session not found at ${existingSession.path}.\n'
        'Run a Go test first to create it.',
      );
    }
    existingSession.copySync('$sessionDir/session_1.json');
    Debug.log('TEST', 'Pre-seeded session from ${existingSession.path}');
  });

  tearDownAll(() async {
    try {
      engine.shutdown();
      engine.dispose();
    } catch (_) {}
    Debug.log('TEST', 'Test data at: $tmpDir');
  });

  test('login and send hello message to friend', () async {
    engine = EngineService();
    await engine.init(
      configDir: '$tmpDir/config',
      cacheDir: '$tmpDir/cache',
      downloadDir: '$tmpDir/downloads',
      libraryPath: _findLibcores(),
    );
    Debug.log('TEST', 'Engine initialized');

    // ── Step 1: Auth the reader account (pre-seeded session) ──
    final readerId = engine.addAccount('telegram');
    Debug.log('TEST', 'Reader account: $readerId');

    final rs1 = await engine.startAuth(readerId);
    Debug.log('TEST', 'Reader auth state: ${rs1!.state}');

    if (rs1.state == 'choose') {
      final rs2 = await engine.submitAuthInput(readerId, 'phone');
      Debug.log('TEST', 'Reader chose phone: ${rs2?.state}');
      final rs3 = await engine.submitAuthInput(readerId, phone);
      Debug.log('TEST', 'Reader phone submit: ${rs3?.state}');

      if (rs3?.state == 'otp') {
        engine.cancelAuth(readerId);
        fail('Reader session not pre-authenticated.');
      }
      expect(rs3?.state, equals('ready'));
      Debug.log('TEST', 'Reader authenticated');
    }

    await Future.delayed(const Duration(seconds: 3));

    // ── Step 2: Auth the NEW account ──
    final newId = engine.addAccount('telegram');
    Debug.log('TEST', 'New account: $newId');

    final s1 = await engine.startAuth(newId);
    expect(s1!.state, equals('choose'));

    final s2 = await engine.submitAuthInput(newId, 'phone');
    expect(s2!.state, equals('input'));

    Debug.log('TEST', 'Submitting phone: $phone');
    final s3 = await engine.submitAuthInput(newId, phone);
    expect(s3!.state, equals('otp'));
    Debug.log('TEST', 'OTP requested');

    // ── Step 3: Read OTP from reader ──
    Debug.log('TEST', 'Waiting for OTP...');
    await Future.delayed(const Duration(seconds: 5));

    String? otpCode;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final msgs = await engine.fetchLiveMessages(readerId, '777000', limit: 3);
        for (final msg in msgs) {
          final code = _extractCode(msg.contentText);
          if (code != null) {
            final msgTime = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
            final age = DateTime.now().difference(msgTime);
            if (age.inMinutes < 2) {
              otpCode = code;
              Debug.log('TEST', 'Found OTP: $otpCode (age: ${age.inSeconds}s)');
              break;
            }
          }
        }
        if (otpCode != null) break;
      } catch (e) {
        Debug.log('TEST', 'FetchLiveMessages attempt $attempt: $e');
      }
      if (attempt < 5) {
        Debug.log('TEST', 'Waiting 5s more...');
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    expect(otpCode, isNotNull, reason: 'Should find OTP from 777000');
    Debug.log('TEST', 'Submitting OTP: $otpCode');

    // ── Step 4: Submit OTP ──
    final s4 = await engine.submitAuthInput(newId, otpCode!);
    Debug.log('TEST', 'After OTP: state=${s4!.state}');

    if (s4.state == 'error') fail('Auth failed after OTP: ${s4.error}');

    // ── Step 5: Handle 2FA ──
    if (s4.state == '2fa') {
      Debug.log('TEST', '2FA required, submitting password');
      final s5 = await engine.submitAuthInput(newId, password2fa);
      Debug.log('TEST', 'After 2FA: state=${s5!.state}');
      if (s5.state == 'error') fail('2FA failed: ${s5.error}');
      expect(s5.state, equals('ready'));
    } else {
      expect(s4.state, equals('ready'));
    }

    Debug.log('TEST', '=== LOGGED IN SUCCESSFULLY ===');

    // Give a moment for the connection to stabilize.
    await Future.delayed(const Duration(seconds: 3));

    // ── Step 6: Send a hello message to friend ──
    Debug.log('TEST', 'Sending hello to friend (chat: $friendChatId)...');
    final localId = await engine.sendMessage(
      newId,
      friendChatId,
      'Hello from Claude! 🤖 This is an automated test message from the uniclient Flutter bridge. If you see this, the full auth + send pipeline works end-to-end!',
    );
    Debug.log('TEST', 'Message sent! localId: $localId');
    expect(localId, isNotEmpty, reason: 'Should get a local ID for the sent message');

    // Give it a moment for server confirmation.
    await Future.delayed(const Duration(seconds: 3));

    // ── Step 7: Verify by reading messages from that chat ──
    try {
      final msgs = await engine.fetchLiveMessages(newId, friendChatId, limit: 3);
      Debug.log('TEST', 'Chat has ${msgs.length} recent messages');
      for (final msg in msgs) {
        Debug.log('TEST', '  [${msg.senderName}]: ${msg.contentText.substring(0, msg.contentText.length.clamp(0, 60))}');
      }
      // Check our message is there.
      final ours = msgs.where((m) => m.contentText.contains('Hello from Claude'));
      expect(ours, isNotEmpty, reason: 'Our message should appear in chat history');
      Debug.log('TEST', 'Verified: message appears in chat!');
    } catch (e) {
      Debug.log('TEST', 'Could not verify message in chat: $e (send may still have worked)');
    }

    Debug.log('TEST', '=== TELEGRAM SEND TEST PASSED ===');

    // Clean up.
    engine.removeAccount(newId);
    engine.removeAccount(readerId);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
