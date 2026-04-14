/// Widget tests for core UI components.
///
/// These test widget rendering without the Go backend (mocked engine).
/// Run: cd dart && flutter test test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:uniclient/models/engine_models.dart';
import 'package:uniclient/state/app_state.dart';
import 'package:uniclient/state/chat_state.dart';
import 'package:uniclient/state/auth_state.dart';
import 'package:uniclient/bridge/engine_service.dart';
import 'package:uniclient/screens/home_screen.dart';
import 'package:uniclient/theme/theme.dart';

/// Wrap a widget with the providers it needs for testing.
Widget _testApp(Widget child, {EngineService? engine}) {
  final eng = engine ?? EngineService();
  return MultiProvider(
    providers: [
      Provider<EngineService>.value(value: eng),
      ChangeNotifierProvider(create: (_) => AppState(eng)),
      ChangeNotifierProvider(create: (_) => ChatState(eng)),
      ChangeNotifierProvider(create: (_) => AuthState(eng)),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: child,
    ),
  );
}

void main() {
  group('HomeScreen widget', () {
    testWidgets('shows loading state before init', (tester) async {
      await tester.pumpWidget(_testApp(const HomeScreen()));
      await tester.pump();

      // Should show loading spinner.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Starting engine...'), findsOneWidget);
    });

    testWidgets('renders without overflow at various sizes', (tester) async {
      // Test at small size.
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(_testApp(const HomeScreen()));
      await tester.pump();
      // Should not throw overflow errors.

      // Test at medium size.
      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();

      // Test at large size.
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pump();

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
