import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'bridge/engine_service.dart';
import 'state/app_state.dart';
import 'state/chat_state.dart';
import 'state/auth_state.dart';
import 'screens/home_screen.dart';
import 'theme/theme.dart';
import 'utils/debug.dart';
import 'widgets/notification_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch all Flutter framework errors and print to stderr.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Debug.error('FLUTTER', details.exceptionAsString(),
      details.exception, details.stack);
  };

  // Catch uncaught async errors.
  PlatformDispatcher.instance.onError = (error, stack) {
    Debug.error('ASYNC', error.toString(), error, stack);
    return true;
  };

  final engineService = EngineService();

  runApp(
    MultiProvider(
      providers: [
        Provider<EngineService>.value(value: engineService),
        ChangeNotifierProvider(create: (_) => AppState(engineService)),
        ChangeNotifierProvider(create: (_) => ChatState(engineService)),
        ChangeNotifierProvider(create: (_) => AuthState(engineService)),
      ],
      child: const UniClientApp(),
    ),
  );
}

class UniClientApp extends StatefulWidget {
  const UniClientApp({super.key});

  @override
  State<UniClientApp> createState() => _UniClientAppState();
}

class _UniClientAppState extends State<UniClientApp> {
  bool _initStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initStarted) {
      _initStarted = true;
      _initEngine();
    }
  }

  Future<void> _initEngine() async {
    final appState = context.read<AppState>();
    final home = Platform.environment['HOME'] ?? '/tmp';
    final configDir = '$home/.config/uniclient';
    final cacheDir = '$home/.cache/uniclient';
    final downloadDir = '$home/Downloads/uniclient';

    // Ensure directories exist.
    for (final dir in [configDir, cacheDir, downloadDir]) {
      Directory(dir).createSync(recursive: true);
    }

    await appState.initialize(
      configDir: configDir,
      cacheDir: cacheDir,
      downloadDir: downloadDir,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MaterialApp(
      title: 'UniClient',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: appState.themeMode,
      home: const NotificationOverlay(child: HomeScreen()),
    );
  }
}
