import 'dart:io' show Directory, Platform, exit;

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
import 'utils/system_tray.dart';
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
  final SystemTray _tray = SystemTray();
  VoidCallback? _unreadListener;
  ChatState? _chatStateRef;

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
    final chatState = context.read<ChatState>();
    // Platform-appropriate directories — uniconfig file lives in configDir.
    late final String configDir;
    late final String cacheDir;
    late final String downloadDir;
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      configDir = '$home/Library/Application Support/uniclient';
      cacheDir = '$home/Library/Caches/uniclient';
      downloadDir = '$home/Downloads/uniclient';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? 'C:\\Users\\Default\\AppData\\Roaming';
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? 'C:\\Users\\Default\\AppData\\Local';
      configDir = '$appData\\uniclient';
      cacheDir = '$localAppData\\uniclient\\cache';
      downloadDir = '${Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default'}\\Downloads\\uniclient';
    } else {
      // Linux / other Unix
      final home = Platform.environment['HOME'] ?? '/tmp';
      configDir = '$home/.config/uniclient';
      cacheDir = '$home/.cache/uniclient';
      downloadDir = '$home/Downloads/uniclient';
    }

    // Ensure directories exist.
    for (final dir in [configDir, cacheDir, downloadDir]) {
      Directory(dir).createSync(recursive: true);
    }

    await appState.initialize(
      configDir: configDir,
      cacheDir: cacheDir,
      downloadDir: downloadDir,
    );

    // Initialize system tray after engine is ready.
    await _tray.init();
    _tray.onQuit = () => exit(0);

    // Track unread count changes and update tray tooltip.
    if (_tray.isAvailable) {
      _chatStateRef = chatState;
      _unreadListener = () {
        _tray.updateUnread(chatState.totalUnread);
      };
      chatState.addListener(_unreadListener!);
      // Set initial tooltip.
      _tray.updateUnread(chatState.totalUnread);
    }
  }

  @override
  void dispose() {
    if (_unreadListener != null && _chatStateRef != null) {
      _chatStateRef!.removeListener(_unreadListener!);
    }
    _tray.dispose();
    super.dispose();
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

