/// Widget tests for voice message rendering in MessageBubble.
///
/// CLAUDE.md hard-bans static placeholder waveforms. Voice messages now render
/// as an honest mic badge + "Voice message" label + duration + size. These
/// tests lock that behavior in place and guard against a fake waveform ever
/// coming back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uniclient/models/engine_models.dart';
import 'package:uniclient/theme/theme.dart';
import 'package:uniclient/ui/message_bubble.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: Center(child: child)),
      );

  group('MessageBubble voice indicator', () {
    testWidgets('renders "Voice message" label with duration and size',
        (tester) async {
      final msg = CachedMessage(
        accountId: 'a',
        chatId: 'c',
        msgId: 'm',
        senderId: 's',
        senderName: 'Alice',
        contentText: '',
        timestamp: 1700000000000,
        mediaType: 4, // voice
        mediaDuration: 65, // 1:05
        mediaFileSize: 125000, // 122.1 KB
        hasMedia: true,
      );

      await tester.pumpWidget(wrap(MessageBubble(message: msg)));

      expect(find.text('Voice message'), findsOneWidget);
      expect(find.text('1:05'), findsOneWidget);
      expect(find.text('122.1 KB'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('renders duration alone when size is zero', (tester) async {
      final msg = CachedMessage(
        accountId: 'a',
        chatId: 'c',
        msgId: 'm',
        senderId: 's',
        senderName: 'Alice',
        contentText: '',
        timestamp: 1700000000000,
        mediaType: 4,
        mediaDuration: 7,
        mediaFileSize: 0,
        hasMedia: true,
      );

      await tester.pumpWidget(wrap(MessageBubble(message: msg)));

      expect(find.text('Voice message'), findsOneWidget);
      expect(find.text('0:07'), findsOneWidget);
      // No size label, no separator dot.
      expect(find.text(' · '), findsNothing);
    });

    testWidgets('no fake waveform CustomPaint in voice bubble',
        (tester) async {
      final msg = CachedMessage(
        accountId: 'a',
        chatId: 'c',
        msgId: 'm',
        senderId: 's',
        senderName: 'Alice',
        contentText: '',
        timestamp: 1700000000000,
        mediaType: 4,
        mediaDuration: 10,
        hasMedia: true,
      );

      await tester.pumpWidget(wrap(MessageBubble(message: msg)));

      // The removed placeholder was `_WaveformPainter`. Any CustomPaint with a
      // painter whose type name contains "waveform" is a regression.
      final paints = find.byWidgetPredicate((w) {
        if (w is CustomPaint && w.painter != null) {
          return w.painter.runtimeType
              .toString()
              .toLowerCase()
              .contains('waveform');
        }
        return false;
      });
      expect(paints, findsNothing);
    });
  });
}
