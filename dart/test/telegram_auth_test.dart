/// Automated Telegram auth flow test.
///
/// Tests the full flow: add account → phone auth → OTP → 2FA → connected.
/// Uses an existing logged-in session to read the OTP code automatically.
///
/// Run: cd dart && flutter test test/telegram_auth_test.dart
/// Requires:
///   - libcores.so built (scripts/build_go.sh linux)
///   - Existing Telegram user session at auth/telegram_user_session.json
///   - Environment vars or defaults for TG_PHONE, TG_2FA_PASSWORD
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:uniclient/bridge/engine_service.dart';
import 'package:uniclient/models/engine_models.dart';
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
  // We're in dart/, so go up one level.
  var dir = Directory.current.path;
  if (dir.endsWith('/dart')) {
    return dir.substring(0, dir.length - 5);
  }
  // Try parent.
  final parent = Directory.current.parent.path;
  if (Directory('$parent/auth').existsSync()) return parent;
  return dir;
}

/// Extract the login code from a Telegram message text.
/// Telegram sends codes like "Login code: 12345" or just the digits.
String? _extractCode(String text) {
  // Match 5-digit codes.
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

  setUpAll(() async {
    projectRoot = _findProjectRoot();
    tmpDir = Directory.systemTemp.createTempSync('uniclient_tg_auth_').path;

    // Pre-seed the existing user session so account #1 (the reader) connects
    // with the existing session. The core factory creates sessions at
    // configDir/sessions/telegram/session_1.json.
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
    // Don't delete tmpDir — keep sessions for debugging.
    Debug.log('TEST', 'Test data at: $tmpDir');
  });

  test('full Telegram phone auth flow with OTP', () async {
    engine = EngineService();
    await engine.init(
      configDir: '$tmpDir/config',
      cacheDir: '$tmpDir/cache',
      downloadDir: '$tmpDir/downloads',
      libraryPath: _findLibcores(),
    );
    Debug.log('TEST', 'Engine initialized');

    // ── Step 1: Add reader account and auth it (uses pre-seeded session) ──
    final readerId = engine.addAccount('telegram');
    Debug.log('TEST', 'Reader account: $readerId');

    // Authenticate the reader through the normal auth flow.
    // Since session_1.json is pre-seeded, IfNecessary will skip OTP.
    final rs1 = await engine.startAuth(readerId);
    expect(rs1, isNotNull);
    Debug.log('TEST', 'Reader auth state: ${rs1!.state}');

    if (rs1.state == 'choose') {
      final rs2 = await engine.submitAuthInput(readerId, 'phone');
      Debug.log('TEST', 'Reader chose phone: ${rs2?.state}');

      // Submit the same phone — session is already auth'd, should skip OTP.
      final rs3 = await engine.submitAuthInput(readerId, phone);
      Debug.log('TEST', 'Reader phone submit: ${rs3?.state}');

      if (rs3?.state == 'otp') {
        // Session wasn't pre-seeded correctly — can't proceed.
        engine.cancelAuth(readerId);
        fail('Reader session not pre-authenticated. Ensure auth/telegram_user_session.json is valid.');
      }
      expect(rs3?.state, equals('ready'), reason: 'Reader should auto-auth from session');
      Debug.log('TEST', 'Reader authenticated: ${rs3?.displayName}');
    }

    // Give it a moment to fully connect.
    await Future.delayed(const Duration(seconds: 3));

    // Verify the reader can fetch messages (sanity check).
    try {
      final testMsgs = await engine.fetchLiveMessages(readerId, '777000', limit: 1);
      Debug.log('TEST', 'Reader can read messages from 777000: ${testMsgs.length} msgs');
    } catch (e) {
      Debug.log('TEST', 'Reader GetMessages test: $e (may be OK if no prior messages)');
    }

    // ── Step 2: Add the NEW account that we'll authenticate ──
    final newId = engine.addAccount('telegram');
    Debug.log('TEST', 'New account: $newId');

    // ── Step 3: Start auth → choose phone ──
    final s1 = await engine.startAuth(newId);
    expect(s1, isNotNull, reason: 'startAuth should return state');
    expect(s1!.state, equals('choose'), reason: 'Telegram should offer choose');
    Debug.log('TEST', 'Auth state: ${s1.state}, options: ${s1.options.map((o) => o.id).toList()}');

    // Choose phone auth.
    final s2 = await engine.submitAuthInput(newId, 'phone');
    expect(s2, isNotNull);
    expect(s2!.state, equals('input'), reason: 'Should ask for phone number');
    expect(s2.label, contains('Phone'));
    Debug.log('TEST', 'Auth state: ${s2.state}, label: ${s2.label}');

    // ── Step 4: Submit phone number → triggers OTP send ──
    Debug.log('TEST', 'Submitting phone: $phone');
    final s3 = await engine.submitAuthInput(newId, phone);
    expect(s3, isNotNull);
    Debug.log('TEST', 'After phone submit: state=${s3!.state}');

    if (s3.state == 'error') {
      Debug.error('TEST', 'Auth failed after phone: ${s3.error}');
      fail('Auth failed: ${s3.error}');
    }
    expect(s3.state, equals('otp'), reason: 'Should ask for OTP after phone');
    Debug.log('TEST', 'OTP requested, sent to: ${s3.sentTo}');

    // ── Step 5: Wait for OTP, then read it from the reader account ──
    Debug.log('TEST', 'Waiting for OTP to arrive...');
    await Future.delayed(const Duration(seconds: 5));

    String? otpCode;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final msgs = await engine.fetchLiveMessages(readerId, '777000', limit: 3);
        Debug.log('TEST', 'Reader got ${msgs.length} messages from 777000');
        for (final msg in msgs) {
          Debug.log('TEST', '  msg: ${msg.contentText.substring(0, msg.contentText.length.clamp(0, 80))}');
          final code = _extractCode(msg.contentText);
          if (code != null) {
            // Check the message is recent (within last 2 minutes).
            final msgTime = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
            final age = DateTime.now().difference(msgTime);
            if (age.inMinutes < 2) {
              otpCode = code;
              Debug.log('TEST', 'Found OTP: $otpCode (age: ${age.inSeconds}s)');
              break;
            } else {
              Debug.log('TEST', 'Code $code too old (${age.inSeconds}s ago)');
            }
          }
        }
        if (otpCode != null) break;
      } catch (e) {
        Debug.log('TEST', 'FetchLiveMessages attempt $attempt failed: $e');
      }

      if (attempt < 5) {
        Debug.log('TEST', 'Waiting 5 more seconds for OTP...');
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    expect(otpCode, isNotNull, reason: 'Should have found OTP code from 777000');
    Debug.log('TEST', 'Submitting OTP: $otpCode');

    // ── Step 6: Submit OTP ──
    final s4 = await engine.submitAuthInput(newId, otpCode!);
    expect(s4, isNotNull);
    Debug.log('TEST', 'After OTP submit: state=${s4!.state}');

    if (s4.state == 'error') {
      Debug.error('TEST', 'Auth failed after OTP: ${s4.error}');
      fail('Auth failed after OTP: ${s4.error}');
    }

    // ── Step 7: Handle 2FA if required ──
    if (s4.state == '2fa') {
      Debug.log('TEST', '2FA required, submitting password');
      final s5 = await engine.submitAuthInput(newId, password2fa);
      expect(s5, isNotNull);
      Debug.log('TEST', 'After 2FA: state=${s5!.state}');

      if (s5.state == 'error') {
        Debug.error('TEST', '2FA failed: ${s5.error}');
        fail('2FA failed: ${s5.error}');
      }
      expect(s5.state, equals('ready'), reason: 'Should be ready after 2FA');
      Debug.log('TEST', 'Auth complete! Display name: ${s5.displayName}');
    } else {
      expect(s4.state, equals('ready'), reason: 'Should be ready after OTP (no 2FA)');
      Debug.log('TEST', 'Auth complete! Display name: ${s4.displayName}');
    }

    // ── Step 8: Verify the account is connected and working ──
    final accounts = engine.listAccounts();
    Debug.log('TEST', 'Total accounts: ${accounts.length}');
    expect(accounts.length, greaterThanOrEqualTo(2));

    // Try to get chat list from the newly authenticated account.
    final chats = engine.getChatList(accountId: newId, limit: 5);
    Debug.log('TEST', 'New account has ${chats.length} chats');

    // Search for something.
    final searchResults = engine.searchChats('Telegram');
    Debug.log('TEST', 'Search "Telegram": ${searchResults.length} results');

    Debug.log('TEST', '=== TELEGRAM AUTH FLOW TEST PASSED ===');

    // Clean up: remove the new account (keep reader).
    engine.cancelAuth(newId);
    engine.removeAccount(newId);
    engine.removeAccount(readerId);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
