import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform, exit;
import 'dart:ui' as ui show Image;
import 'dart:ui' show PointerChange, PointerDeviceKind, PointerData, PointerSignalKind;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'bridge/engine_service.dart';
import 'models/engine_models.dart';
import 'state/app_state.dart';
import 'state/chat_state.dart';
import 'state/audio_service.dart';
import 'state/auth_state.dart';
import 'theme/theme.dart';
import 'ui/call_panel.dart';
import 'ui/call_screen.dart';
import 'ui/chat_list_panel.dart';
import 'ui/chat_list_row.dart';
import 'ui/chat_view.dart';
import 'ui/contacts_screen.dart';
import 'ui/choose_datetime_box.dart';
import 'ui/keyboard_shortcuts.dart';
import 'ui/media_viewer.dart';
import 'ui/shell.dart';
import 'theme/wallpaper.dart';
import 'ui/titlebar.dart';
import 'utils/debug.dart';
import 'utils/system_tray.dart';
import 'utils/system_unlock.dart';
import 'utils/web_notifier.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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
        ChangeNotifierProvider(create: (_) => AudioService()),
      ],
      child: const UniClientApp(),
    ),
  );
}

/// §3.4: Switch theme with cross-fade animation.
/// Call from hamburger drawer instead of appState.updateTheme() directly.
Future<void> switchThemeWithCrossFade(BuildContext context, String theme) =>
    _UniClientAppState.switchThemeWithCrossFade(context, theme);

/// §25.9.4: Revert testing theme with cross-fade animation.
Future<void> revertThemeWithCrossFade(BuildContext context) =>
    _UniClientAppState.revertThemeWithCrossFade(context);

class UniClientApp extends StatefulWidget {
  const UniClientApp({super.key});

  @override
  State<UniClientApp> createState() => _UniClientAppState();
}

class _UniClientAppState extends State<UniClientApp>
    with TickerProviderStateMixin {
  bool _initStarted = false;
  final SystemTray _tray = SystemTray();
  final WebNotifier _webNotifier = WebNotifier();
  VoidCallback? _unreadListener;
  ChatState? _chatStateRef;
  Timer? _debugCmdTimer;
  final _navigatorKey = GlobalKey<NavigatorState>();

  // §27.13: In-app notification banner state.
  _NotifBannerData? _notifBanner;
  Timer? _notifDismissTimer;

  // §3.4: Theme cross-fade — capture old frame, overlay, fade out to reveal new theme.
  static _UniClientAppState? _instance;
  final _themeBoundaryKey = GlobalKey();
  ui.Image? _themeCrossFadeImage;
  AnimationController? _themeFadeCtrl;

  @override
  void initState() {
    super.initState();
    _instance = this;
  }

  /// §3.4: Trigger a theme cross-fade. Captures the current frame, applies
  /// the new theme, then fades out the captured overlay to reveal new colors.
  /// Called from hamburger_drawer.dart instead of appState.updateTheme directly.
  static Future<void> switchThemeWithCrossFade(
      BuildContext context, String theme) async {
    final inst = _instance;
    if (inst == null || !inst.mounted) {
      context.read<AppState>().updateTheme(theme);
      return;
    }
    await inst._performThemeCrossFade(context, theme);
  }

  /// §25.9.4: Revert a testing theme with cross-fade animation.
  static Future<void> revertThemeWithCrossFade(BuildContext context) async {
    final inst = _instance;
    if (inst == null || !inst.mounted) {
      context.read<AppState>().revertTheme();
      return;
    }
    await inst._performCrossFadeWith(context, () {
      context.read<AppState>().revertTheme();
    });
  }

  Future<void> _performThemeCrossFade(
      BuildContext ctx, String theme) async {
    await _performCrossFadeWith(ctx, () {
      ctx.read<AppState>().updateTheme(theme);
    });
  }

  Future<void> _performCrossFadeWith(
      BuildContext ctx, VoidCallback applyChange) async {
    final pixelRatio = MediaQuery.of(ctx).devicePixelRatio;

    final boundary = _themeBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) {
      applyChange();
      return;
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) { applyChange(); return; }
    ui.Image image;
    try {
      image = await boundary.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      applyChange();
      return;
    }
    if (!mounted) { image.dispose(); return; }
    applyChange();

    _themeFadeCtrl?.dispose();
    _themeFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    setState(() => _themeCrossFadeImage = image);

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    _themeFadeCtrl!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _themeCrossFadeImage?.dispose();
          _themeCrossFadeImage = null;
        });
        _themeFadeCtrl?.dispose();
        _themeFadeCtrl = null;
      }
    });
    _themeFadeCtrl!.forward();
  }

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
    // On web (§13.5), no filesystem — use empty strings and let the engine
    // handle persistence via IndexedDB / localStorage.
    late final String configDir;
    late final String cacheDir;
    late final String downloadDir;
    if (kIsWeb) {
      configDir = '';
      cacheDir = '';
      downloadDir = '';
    } else if (Platform.isMacOS) {
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

    // Ensure directories exist (desktop-only — no filesystem on web).
    if (!kIsWeb) {
      for (final dir in [configDir, cacheDir, downloadDir]) {
        Directory(dir).createSync(recursive: true);
      }
    }

    await appState.initialize(
      configDir: configDir,
      cacheDir: cacheDir,
      downloadDir: downloadDir,
    );

    // Initialize folder state for the active account.
    if (appState.activeAccountId.isNotEmpty) {
      chatState.switchAccount(appState.activeAccountId);
    }

    // Initialize system tray after engine is ready (desktop-only, §13.5).
    if (!kIsWeb) {
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

    // Web: Notifications API + favicon/title badge instead of tray (§13.5).
    if (kIsWeb) {
      _webNotifier.init();
      _chatStateRef = chatState;
      _unreadListener = () {
        _webNotifier.updateBadge(chatState.totalUnread);
      };
      chatState.addListener(_unreadListener!);
      _webNotifier.updateBadge(chatState.totalUnread);
    }

    // §27.13: Wire up in-app notification callback with passcode-aware content hiding.
    _chatStateRef ??= chatState;
    chatState.onNotification = (accountId, chatId, senderName, text, chatTitle) {
      _showNotificationBanner(appState, chatState, accountId, chatId, senderName, text, chatTitle);
    };

    // Debug command poller — reads /tmp/uniclient_debug_cmd.json for
    // programmatic UI interaction (smoke testing on Wayland). Desktop-only.
    if (kDebugMode && !kIsWeb) {
      _debugCmdTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _pollDebugCommand(chatState);
      });
    }
  }

  void _showNotificationBanner(AppState appState, ChatState chatState,
      String accountId, String chatId, String senderName, String text, String chatTitle) {
    final locked = appState.passcodeLocked;
    _notifDismissTimer?.cancel();
    setState(() {
      _notifBanner = _NotifBannerData(
        title: locked ? 'New message' : (chatTitle.isNotEmpty ? chatTitle : senderName),
        body: locked ? '' : (chatTitle.isNotEmpty && senderName.isNotEmpty ? '$senderName: $text' : text),
        accountId: accountId,
        chatId: chatId,
        isLocked: locked,
      );
    });
    _notifDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _notifBanner = null);
    });
  }

  void _onNotifBannerTap() {
    final data = _notifBanner;
    if (data == null) return;
    _notifDismissTimer?.cancel();
    setState(() => _notifBanner = null);
    if (data.isLocked) {
      _PasscodeLockScreenState._focusPasscode?.call();
    } else {
      final chatState = context.read<ChatState>();
      final chat = chatState.chats.where((c) =>
          c.accountId == data.accountId && c.chatId == data.chatId).firstOrNull;
      if (chat != null) chatState.openChat(chat);
    }
  }

  void _pollDebugCommand(ChatState chatState) {
    final file = File('/tmp/uniclient_debug_cmd.json');
    if (!file.existsSync()) return;
    try {
      final content = file.readAsStringSync().trim();
      file.deleteSync();
      if (content.isEmpty) return;
      final cmd = jsonDecode(content) as Map<String, dynamic>;
      final action = cmd['action'] as String? ?? '';
      Debug.log('DEBUG_CMD', 'action=$action data=$cmd');

      switch (action) {
        case 'openChat':
          // Open a chat by index or chatId.
          final index = cmd['index'] as int?;
          final chatId = cmd['chatId'] as String?;
          if (index != null && index < chatState.chats.length) {
            chatState.openChat(chatState.chats[index]);
          } else if (chatId != null) {
            final chat = chatState.chats.where((c) => c.chatId == chatId).firstOrNull;
            if (chat != null) chatState.openChat(chat);
          }
        case 'listChats':
          // Dump chat list to /tmp/uniclient_debug_out.json.
          final out = chatState.chats.take(20).map((c) => {
            'index': chatState.chats.indexOf(c),
            'chatId': c.chatId,
            'title': c.title,
            'unread': c.unreadCount,
            'accountId': c.accountId,
          }).toList();
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(out),
          );
        case 'sendMessage':
          final text = cmd['text'] as String? ?? '';
          if (text.isNotEmpty) {
            chatState.sendMessage(text);
          }
        case 'setCompose':
          final text = cmd['text'] as String? ?? '';
          final selStart = cmd['selStart'] as int?;
          final selEnd = cmd['selEnd'] as int?;
          ChatView.setComposeRequest?.call(text, selStart: selStart, selEnd: selEnd);
        case 'formatCompose':
          final fmt = cmd['format'] as String? ?? '';
          final type = switch (fmt) {
            'bold' => FormatType.bold,
            'italic' => FormatType.italic,
            'underline' => FormatType.underline,
            'strike' => FormatType.strike,
            'code' => FormatType.code,
            'spoiler' => FormatType.spoiler,
            'blockquote' => FormatType.blockquote,
            'link' => FormatType.link,
            _ => null,
          };
          if (type != null) {
            ChatView.toggleFormatRequest?.call(type);
          }
        case 'getComposeEntities':
          final entities = ChatView.getComposeEntitiesRequest?.call() ?? '';
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            jsonEncode({'entities': entities}),
          );
        case 'getMessages':
          // Dump current messages to output file.
          final out = chatState.messages.take(20).map((m) => {
            'msgId': m.msgId,
            'senderId': m.senderId,
            'senderName': m.senderName,
            'text': m.contentText.length > 40 ? m.contentText.substring(0, 40) : m.contentText,
            'status': m.status.name,
            'isSent': m.isSent,
            'mediaType': m.mediaType,
            'mediaMimeType': m.mediaMimeType,
            'stickerSetShortName': m.stickerSetShortName,
            'stickerSetId': m.stickerSetId,
            'mediaRemoteRef': m.mediaRemoteRef,
          }).toList();
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(out),
          );
        case 'getState':
          // Dump current app state.
          final out = {
            'activeChat': chatState.activeChat?.chatId,
            'activeChatTitle': chatState.activeChat?.title,
            'messageCount': chatState.messages.length,
            'chatCount': chatState.chats.length,
            'loadingMessages': chatState.loadingMessages,
            'folderCount': chatState.folders.length,
            'activeFolderId': chatState.activeFolderId,
            'folders': chatState.folders.map((f) => {
              'id': f.id,
              'name': f.name,
              'chatCount': f.chatIds.length,
            }).toList(),
          };
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(out),
          );
        case 'switchAccount':
          final accountId = cmd['accountId'] as String? ?? '';
          if (accountId.isNotEmpty) {
            final appState = context.read<AppState>();
            appState.setActiveAccountId(accountId);
            chatState.switchAccount(accountId);
          }
        case 'addAccount':
          final platform = cmd['platform'] as String? ?? 'telegram';
          final appState = context.read<AppState>();
          if (appState.canAddAccount) {
            final id = appState.addAccount(platform);
            Debug.log('DEBUG_CMD', 'Added account: $id ($platform)');
            final authState = context.read<AuthState>();
            authState.startAuth(id);
            File('/tmp/uniclient_debug_out.json').writeAsStringSync(
              jsonEncode({'accountId': id, 'platform': platform}),
            );
          }
        case 'listAccounts':
          final appState = context.read<AppState>();
          final out = appState.accounts.map((a) => {
            'id': a.id,
            'platform': a.platform,
            'displayName': a.displayName,
            'active': a.id == appState.activeAccountId,
          }).toList();
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(out),
          );

        // ── Gesture dispatch ──

        case 'tap':
          // Tap at screen coordinates: {"action":"tap","x":500,"y":300}
          final x = (cmd['x'] as num).toDouble();
          final y = (cmd['y'] as num).toDouble();
          _dispatchTap(x, y);

        case 'rightClick':
          // Right-click at coordinates: {"action":"rightClick","x":500,"y":300}
          final x = (cmd['x'] as num).toDouble();
          final y = (cmd['y'] as num).toDouble();
          _dispatchTap(x, y, buttons: kSecondaryMouseButton);

        case 'longPress':
          // Long-press at coordinates: {"action":"longPress","x":500,"y":300}
          final x = (cmd['x'] as num).toDouble();
          final y = (cmd['y'] as num).toDouble();
          _dispatchLongPress(x, y);

        case 'scroll':
          // Scroll at coordinates: {"action":"scroll","x":500,"y":400,"dx":0,"dy":-200}
          final x = (cmd['x'] as num).toDouble();
          final y = (cmd['y'] as num).toDouble();
          final dx = (cmd['dx'] as num?)?.toDouble() ?? 0;
          final dy = (cmd['dy'] as num?)?.toDouble() ?? 0;
          _dispatchScroll(x, y, dx, dy);



        case 'type':
          // Type text into focused field: {"action":"type","text":"hello"}
          final text = cmd['text'] as String? ?? '';
          _dispatchTextInput(text);

        case 'setText':
          // Replace focused field text: {"action":"setText","text":"@foo"}
          final text = cmd['text'] as String? ?? '';
          _dispatchSetText(text);

        case 'key':
          // Send a key event: {"action":"key","key":"enter"} or {"action":"key","key":"backspace"}
          final key = cmd['key'] as String? ?? '';
          _dispatchKey(key);

        case 'doubleClick':
          // Double-click at coordinates: {"action":"doubleClick","x":500,"y":300}
          final x = (cmd['x'] as num).toDouble();
          final y = (cmd['y'] as num).toDouble();
          _dispatchDoubleTap(x, y);

        case 'drag':
          // Drag from (x1,y1) to (x2,y2): {"action":"drag","x1":100,"y1":300,"x2":200,"y2":300}
          final x1 = (cmd['x1'] as num).toDouble();
          final y1 = (cmd['y1'] as num).toDouble();
          final x2 = (cmd['x2'] as num).toDouble();
          final y2 = (cmd['y2'] as num).toDouble();
          final steps = (cmd['steps'] as int?) ?? 10;
          _dispatchDrag(x1, y1, x2, y2, steps);

        case 'hover':
          // Hover at coordinates: {"action":"hover","x":500,"y":300}
          final x = (cmd['x'] as num).toDouble();
          final y = (cmd['y'] as num).toDouble();
          _dispatchHover(x, y);

        // ── UI query commands ──

        case 'findText':
          // Find text on screen and return its bounds: {"action":"findText","text":"Send"}
          final query = cmd['text'] as String? ?? '';
          final results = _findTextOnScreen(query);
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(results),
          );

        case 'getAllText':
          // Dump all visible text with positions: {"action":"getAllText"}
          final results = _getAllVisibleText();
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(results),
          );

        case 'getWindowSize':
          // Get window dimensions: {"action":"getWindowSize"}
          final window = WidgetsBinding.instance.renderViews.first;
          final size = window.size;
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            jsonEncode({'width': size.width, 'height': size.height,
              'pixelRatio': window.flutterView.devicePixelRatio}),
          );

        case 'hitTest':
          // Find what widget is at coordinates: {"action":"hitTest","x":500,"y":300}
          final x = (cmd['x'] as num).toDouble();
          final y = (cmd['y'] as num).toDouble();
          final result = _hitTestAt(x, y);
          File('/tmp/uniclient_debug_out.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(result),
          );

        case 'waitForText':
          // Wait for text to appear, poll every 200ms up to timeout: {"action":"waitForText","text":"SamNet","timeout":5}
          final query = cmd['text'] as String? ?? '';
          final timeoutSec = (cmd['timeout'] as num?)?.toInt() ?? 5;
          _waitForText(query, timeoutSec);

        case 'resize':
          // Resize the window: {"action":"resize","width":1024,"height":768}
          final w = (cmd['width'] as num?)?.toInt();
          final h = (cmd['height'] as num?)?.toInt();
          if (w != null && h != null) {
            const channel = MethodChannel('com.uniclient.app/window');
            channel.invokeMethod('resize', {'width': w, 'height': h});
          }

        case 'toggleScheduled':
          chatState.toggleScheduledView();

        case 'testVideoToast':
          final toastType = cmd['type'] as String? ?? 'tip';
          if (toastType == 'tip') {
            ChatView.testVideoTipToast?.call();
          } else if (toastType == 'published') {
            ChatView.testVideoPublishedToast?.call();
          }

        case 'dismissPopup':
          // Tap at (0,0) to dismiss any popup/dialog/menu
          _dispatchTap(1, 1);

        case 'sendFiles':
          final paths = (cmd['paths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [];
          if (paths.isNotEmpty) {
            ChatView.showSendFilesBoxRequest?.call(paths);
          }

        case 'showCallPanel':
          final state = cmd['state'] as String? ?? 'incoming';
          final callState = switch (state) {
            'connecting' => CallPanelState.connecting,
            'active' => CallPanelState.active,
            'ended' => CallPanelState.ended,
            _ => CallPanelState.incoming,
          };
          final navCtx = _navigatorKey.currentContext;
          if (navCtx != null) {
            final fpRaw = cmd['fingerprintEmoji'];
            final fpEmoji = fpRaw is List
                ? fpRaw.cast<String>().toList()
                : <String>[];
            showCallPanel(navCtx, CallPanelInfo(
              callerId: cmd['callerId'] as String? ?? 'test_user',
              callerName: cmd['callerName'] as String? ?? 'Test Caller',
              callerAvatarUrl: cmd['avatarUrl'] as String? ?? '',
              isVideo: cmd['isVideo'] == true,
              state: callState,
              signalQuality: (cmd['signalQuality'] as num?)?.toInt() ?? -1,
              fingerprintEmoji: fpEmoji,
            ), callId: cmd['callId'] as String?);
          }

        case 'showCallRating':
          final navCtx = _navigatorKey.currentContext;
          if (navCtx != null) {
            showCallRatingDialog(navCtx, callId: cmd['callId'] as String? ?? 'test_call');
          }

        case 'showScheduleBox':
          final navCtx = _navigatorKey.currentContext;
          if (navCtx != null) {
            showChooseDateTimeBox(navCtx).then((result) {
              File('/tmp/uniclient_debug_out.json').writeAsStringSync(
                jsonEncode(result != null
                    ? {'dateTime': result.dateTime.toIso8601String(),
                       'silent': result.silent, 'sendWhenOnline': result.sendWhenOnline,
                       'repeatPeriod': result.repeatPeriod}
                    : {'cancelled': true}),
              );
            });
          }

        case 'testNotification':
          final appState = context.read<AppState>();
          _showNotificationBanner(
            appState, chatState,
            cmd['accountId'] as String? ?? '',
            cmd['chatId'] as String? ?? '',
            cmd['senderName'] as String? ?? 'Test User',
            cmd['text'] as String? ?? 'Test notification message',
            cmd['chatTitle'] as String? ?? 'Test Chat',
          );

        case 'showGroupCallPanel':
          final navCtx = _navigatorKey.currentContext;
          if (navCtx != null) {
            final pRaw = cmd['participants'] as List<dynamic>? ?? [];
            final participants = pRaw.map((p) {
              final m = p as Map<String, dynamic>;
              return GroupCallParticipant(
                userId: m['userId'] as String? ?? '',
                displayName: m['displayName'] as String? ?? '',
                isMuted: m['isMuted'] == true,
                isSpeaking: m['isSpeaking'] == true,
                hasVideo: m['hasVideo'] == true,
              );
            }).toList();
            showGroupCallPanel(
              navCtx,
              GroupCallInfo(
                callId: cmd['callId'] as String? ?? 'test_gc',
                title: cmd['title'] as String? ?? '',
                participantsCount: participants.isNotEmpty
                    ? participants.length
                    : (cmd['participantsCount'] as num?)?.toInt() ?? 0,
                participants: participants,
                active: true,
              ),
              chatTitle: cmd['chatTitle'] as String? ?? 'Test Group',
              isRecording: cmd['isRecording'] == true,
              isSelfMuted: cmd['isSelfMuted'] == true,
              isForceMuted: cmd['isForceMuted'] == true,
            );
          }
      }
    } catch (e) {
      Debug.error('DEBUG_CMD', 'Error processing command', e, null);
    }
  }

  // ── Gesture dispatch helpers ──

  int _pointerCounter = 0;

  void _dispatchTap(double x, double y, {int buttons = kPrimaryButton}) {
    final pointer = _pointerCounter++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerAddedEvent(
      pointer: pointer,
      position: Offset(x, y),
      kind: PointerDeviceKind.mouse,
    ));
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: Offset(x, y),
      buttons: buttons,
      kind: PointerDeviceKind.mouse,
    ));
    Future.delayed(const Duration(milliseconds: 100), () {
      binding.handlePointerEvent(PointerUpEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.mouse,
      ));
      binding.handlePointerEvent(PointerRemovedEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.mouse,
      ));
    });
  }

  void _dispatchLongPress(double x, double y) {
    final pointer = _pointerCounter++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: Offset(x, y),
      buttons: kPrimaryButton,
      kind: PointerDeviceKind.mouse,
    ));
    // Hold for 600ms then release.
    Future.delayed(const Duration(milliseconds: 600), () {
      binding.handlePointerEvent(PointerUpEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.mouse,
      ));
    });
  }

  bool _scrollDeviceAdded = false;

  void _dispatchScroll(double x, double y, double dx, double dy) {
    final binding = GestureBinding.instance;
    if (!_scrollDeviceAdded) {
      binding.handlePointerEvent(const PointerAddedEvent(
        device: 99,
        kind: PointerDeviceKind.mouse,
      ));
      _scrollDeviceAdded = true;
    }
    binding.handlePointerEvent(PointerHoverEvent(
      device: 99,
      position: Offset(x, y),
      kind: PointerDeviceKind.mouse,
    ));
    binding.handlePointerEvent(PointerScrollEvent(
      device: 99,
      position: Offset(x, y),
      scrollDelta: Offset(dx, dy),
      kind: PointerDeviceKind.mouse,
    ));
  }

  void _dispatchTextInput(String text) {
    // Find the focused text field's controller and insert text.
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null) return;
    // Walk up from focus node to find EditableText.
    final ctx = focusNode.context;
    if (ctx == null) return;
    final editableState = ctx.findAncestorStateOfType<EditableTextState>();
    if (editableState != null) {
      final current = editableState.textEditingValue;
      final newText = current.text + text;
      final newValue = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      editableState.updateEditingValue(newValue);
      // Walk ancestors to find the TextField widget and call onChanged,
      // since updateEditingValue may not trigger it in all code paths.
      ctx.visitAncestorElements((element) {
        final widget = element.widget;
        if (widget is TextField) {
          widget.onChanged?.call(newText);
          return false;
        }
        return true;
      });
    }
  }

  void _dispatchSetText(String text) {
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null) return;
    final ctx = focusNode.context;
    if (ctx == null) return;
    final editableState = ctx.findAncestorStateOfType<EditableTextState>();
    if (editableState != null) {
      final newValue = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      editableState.updateEditingValue(newValue);
      ctx.visitAncestorElements((element) {
        if (element.widget is TextField) {
          (element.widget as TextField).onChanged?.call(text);
          return false;
        }
        return true;
      });
    }
  }

  void _dispatchDoubleTap(double x, double y) {
    final binding = GestureBinding.instance;
    // First tap.
    final p1 = _pointerCounter++;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: p1, position: Offset(x, y), buttons: kPrimaryButton, kind: PointerDeviceKind.mouse,
    ));
    binding.handlePointerEvent(PointerUpEvent(
      pointer: p1, position: Offset(x, y), kind: PointerDeviceKind.mouse,
    ));
    // Second tap after minimal delay.
    Future.delayed(const Duration(milliseconds: 50), () {
      final p2 = _pointerCounter++;
      binding.handlePointerEvent(PointerDownEvent(
        pointer: p2, position: Offset(x, y), buttons: kPrimaryButton, kind: PointerDeviceKind.mouse,
      ));
      binding.handlePointerEvent(PointerUpEvent(
        pointer: p2, position: Offset(x, y), kind: PointerDeviceKind.mouse,
      ));
    });
  }

  void _dispatchDrag(double x1, double y1, double x2, double y2, int steps) {
    final pointer = _pointerCounter++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer, position: Offset(x1, y1), buttons: kPrimaryButton, kind: PointerDeviceKind.mouse,
    ));
    // Interpolate move events. Each event carries a non-zero `delta` so
    // HorizontalDragGestureRecognizer / PanGestureRecognizer see real motion
    // (they read `event.delta`, not position-differences).
    var prevX = x1;
    var prevY = y1;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final x = x1 + (x2 - x1) * t;
      final y = y1 + (y2 - y1) * t;
      final dx = x - prevX;
      final dy = y - prevY;
      prevX = x;
      prevY = y;
      Future.delayed(Duration(milliseconds: i * 16), () {
        binding.handlePointerEvent(PointerMoveEvent(
          pointer: pointer,
          position: Offset(x, y),
          delta: Offset(dx, dy),
          buttons: kPrimaryButton,
          kind: PointerDeviceKind.mouse,
        ));
        if (i == steps) {
          binding.handlePointerEvent(PointerUpEvent(
            pointer: pointer, position: Offset(x2, y2), kind: PointerDeviceKind.mouse,
          ));
        }
      });
    }
  }

  static const _hoverPointer = 999999;
  void _dispatchHover(double x, double y) {
    GestureBinding.instance.handlePointerEvent(PointerHoverEvent(
      pointer: _hoverPointer, position: Offset(x, y), kind: PointerDeviceKind.mouse,
    ));
  }

  void _dispatchKey(String key) {
    final lc = key.toLowerCase();

    if (ShortcutSystem.instance.isRecording) {
      _dispatchKeyToRecording(lc);
      return;
    }

    // Handle modifier combos like "ctrl+f" / "control+f". Flutter's
    // CallbackShortcuts only fire from OS-delivered key events that flow
    // through KeyEventManager → FocusManager; HardwareKeyboard.handleKeyEvent
    // alone does not reach the shortcut dispatch path. So we invoke the same
    // callback the shortcut would invoke, to keep the harness observable.
    if (lc == 'ctrl+f' || lc == 'control+f') {
      ChatListPanel.requestFocusSearch();
      return;
    }
    // Telegram Desktop spec §24.4 next_chat/previous_chat. HardwareKeyboard
    // doesn't route through Shortcuts, so invoke the navigation hook
    // directly for the harness path (same trick as ctrl+f above).
    if (lc == 'alt+down' || lc == 'alt+arrowdown') {
      ChatListPanel.requestNavigateChat(1);
      return;
    }
    if (lc == 'alt+up' || lc == 'alt+arrowup') {
      ChatListPanel.requestNavigateChat(-1);
      return;
    }
    // Telegram Desktop spec §24.4: Ctrl+PgDn / Ctrl+PgUp are the primary
    // next_chat / previous_chat shortcuts. Same harness bypass as alt+down/up
    // (HardwareKeyboard doesn't route through Shortcuts).
    if (lc == 'ctrl+pagedown' || lc == 'ctrl+pgdn' ||
        lc == 'control+pagedown' || lc == 'control+pgdn') {
      ChatListPanel.requestNavigateChat(1);
      return;
    }
    if (lc == 'ctrl+pageup' || lc == 'ctrl+pgup' ||
        lc == 'control+pageup' || lc == 'control+pgup') {
      ChatListPanel.requestNavigateChat(-1);
      return;
    }
    // Telegram Desktop spec §24.4 next_folder/previous_folder — Ctrl+Shift+
    // Down/Up switches the active folder tab in the sidebar. Same harness
    // bypass as alt+down/up (HardwareKeyboard doesn't route through
    // Shortcuts).
    if (lc == 'ctrl+shift+down' || lc == 'ctrl+shift+arrowdown' ||
        lc == 'control+shift+down' || lc == 'control+shift+arrowdown') {
      ChatListPanel.requestNavigateFolder(1);
      return;
    }
    if (lc == 'ctrl+shift+up' || lc == 'ctrl+shift+arrowup' ||
        lc == 'control+shift+up' || lc == 'control+shift+arrowup') {
      ChatListPanel.requestNavigateFolder(-1);
      return;
    }
    // Telegram Desktop spec §24.4: Ctrl+R marks the currently active chat
    // as read. HardwareKeyboard doesn't route through Shortcuts, so invoke
    // the hook directly for the harness path (same trick as ctrl+f above).
    if (lc == 'ctrl+r' || lc == 'control+r') {
      ChatView.requestMarkActiveChatRead();
      return;
    }
    // Telegram Desktop spec §24.4 first_chat / last_chat — Ctrl+Alt+Home
    // jumps selection to the first visible chat, Ctrl+Alt+End jumps to the
    // last. Same harness bypass as other shortcuts (HardwareKeyboard doesn't
    // route through Shortcuts).
    if (lc == 'ctrl+alt+home' || lc == 'control+alt+home') {
      ChatListPanel.requestJumpChat(true);
      return;
    }
    if (lc == 'ctrl+alt+end' || lc == 'control+alt+end') {
      ChatListPanel.requestJumpChat(false);
      return;
    }
    // Telegram Desktop spec §24.4 Folder Switching — Ctrl+1..Ctrl+8 switch
    // the active folder tab by 1-based index (1 = All Chats, 2..7 = folders
    // 1..6, 8 = last folder). Same harness bypass as other shortcuts.
    for (var i = 1; i <= 8; i++) {
      if (lc == 'ctrl+$i' || lc == 'control+$i') {
        ChatListPanel.requestSwitchFolderByIndex(i);
        return;
      }
    }
    // Telegram Desktop spec §24.4: Ctrl+W closes the window (minimizes to
    // system tray). No-op when the native tray is unavailable (the hook is
    // only registered in SystemTray.init() after the tray channel responds
    // with isAvailable=true). Same harness bypass as other shortcuts —
    // HardwareKeyboard doesn't route through Shortcuts.
    if (lc == 'ctrl+w' || lc == 'control+w') {
      SystemTray.hideWindowRequest?.call();
      return;
    }
    // Telegram Desktop spec §24.4: Ctrl+F4 is the documented alternate
    // binding for `close_telegram` (hide to tray). Same callback as Ctrl+W.
    if (lc == 'ctrl+f4' || lc == 'control+f4') {
      SystemTray.hideWindowRequest?.call();
      return;
    }
    // Telegram Desktop spec §24.4: Ctrl+M minimizes the window (iconify to
    // taskbar). Unlike Ctrl+W (which hides the window entirely), minimize
    // preserves the taskbar entry so the user can click it to restore.
    // Same harness bypass — HardwareKeyboard doesn't route through Shortcuts.
    if (lc == 'ctrl+m' || lc == 'control+m') {
      SystemTray.minimizeWindowRequest?.call();
      return;
    }
    // Telegram Desktop spec §24.4: Ctrl+Q fully quits the application
    // (unlike Ctrl+W which only hides to tray). Same harness bypass —
    // HardwareKeyboard doesn't route through Shortcuts.
    if (lc == 'ctrl+q' || lc == 'control+q') {
      SystemTray.quitAppRequest?.call();
      return;
    }
    if (lc == 'ctrl+l' || lc == 'control+l') {
      try {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null) ctx.read<AppState>().lockByPasscode();
      } catch (_) {}
      return;
    }
    if (lc == 'ctrl+tab' || lc == 'control+tab') {
      UniClientShell.showChatSwitchRequest?.call();
      return;
    }
    if (lc == 'ctrl+shift+tab' || lc == 'control+shift+tab') {
      UniClientShell.showChatSwitchRequest?.call();
      return;
    }
    if (lc == 'ctrl+0' || lc == 'control+0') {
      final chatState = context.read<ChatState>();
      final saved = chatState.chats.where((c) => isSavedMessages(c)).firstOrNull;
      if (saved != null) chatState.openChat(saved);
      return;
    }
    if (lc == 'ctrl+9' || lc == 'control+9') {
      context.read<AppState>().requestShowArchive();
      return;
    }
    if (lc == 'ctrl+j' || lc == 'control+j') {
      final navCtx = _navigatorKey.currentContext;
      if (navCtx != null) {
        final appState = context.read<AppState>();
        final chatSt = context.read<ChatState>();
        final authSt = context.read<AuthState>();
        Navigator.of(navCtx).push(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: appState,
              child: ChangeNotifierProvider.value(
                value: chatSt,
                child: ChangeNotifierProvider.value(
                  value: authSt,
                  child: const ContactsScreen(),
                ),
              ),
            ),
          ),
        );
      }
      return;
    }
    if (lc == 'ctrl+s' || lc == 'control+s') {
      MediaViewer.save();
      return;
    }
    if (lc == 'ctrl+c' || lc == 'control+c') {
      MediaViewer.copyMedia();
      return;
    }
    // Telegram Desktop spec §24.4 Chat Actions: Ctrl+\ opens the chat-level
    // action menu (`show_chat_menu`, aka the peer menu). Anchored at the
    // top-bar more_vert button. No-op when no chat is open. Same harness
    // bypass as other shortcuts — HardwareKeyboard doesn't route through
    // Shortcuts.
    if (lc == 'ctrl+\\' || lc == 'control+\\' ||
        lc == 'ctrl+backslash' || lc == 'control+backslash') {
      ChatView.requestShowActiveChatMenu();
      return;
    }
    if (lc == 'ctrl+]' || lc == 'control+]' ||
        lc == 'ctrl+bracketright' || lc == 'control+bracketright') {
      ChatView.requestShowChatPreview();
      return;
    }
    if (lc == 'ctrl+r' || lc == 'control+r') {
      ChatView.requestMarkActiveChatRead();
      return;
    }
    // Telegram Desktop spec §24.4 line 2978 — Ctrl+Shift+Enter always sends
    // the compose field regardless of send-by-Enter mode. Real OS-delivered
    // keystrokes route through the TextField's FocusNode.onKeyEvent directly;
    // this harness path invokes the static hook the active ChatView
    // registered in initState so automated tests can exercise the same
    // _sendMessage entry point.
    if (lc == 'ctrl+shift+enter' || lc == 'control+shift+enter') {
      ChatView.requestSendCompose();
      return;
    }
    // Telegram Desktop spec §24.6 lines 2982-2983: Ctrl+Up / Ctrl+Down
    // cycle the reply target in the active chat. Ctrl+Up goes to the older
    // message, Ctrl+Down to the newer one (and cancels when at newest).
    // Same harness bypass as other shortcuts (HardwareKeyboard doesn't
    // route through Shortcuts).
    if (lc == 'ctrl+up' || lc == 'control+up' ||
        lc == 'ctrl+arrowup' || lc == 'control+arrowup') {
      ChatView.requestCycleReply(1);
      return;
    }
    if (lc == 'ctrl+down' || lc == 'control+down' ||
        lc == 'ctrl+arrowdown' || lc == 'control+arrowdown') {
      ChatView.requestCycleReply(-1);
      return;
    }
    if (lc == 'pageup' || lc == 'pgup') {
      ChatView.requestScrollPage(true);
      return;
    }
    if (lc == 'pagedown' || lc == 'pgdown') {
      ChatView.requestScrollPage(false);
      return;
    }
    switch (key) {
      case 'enter':
        final focusNode = FocusManager.instance.primaryFocus;
        if (focusNode == null) return;
        final ctx = focusNode.context;
        if (ctx == null) return;
        final editableState = ctx.findAncestorStateOfType<EditableTextState>();
        if (editableState != null) {
          editableState.performAction(TextInputAction.newline);
        }
      case 'backspace':
        final focusNode = FocusManager.instance.primaryFocus;
        if (focusNode == null) return;
        final ctx = focusNode.context;
        if (ctx == null) return;
        final editableState = ctx.findAncestorStateOfType<EditableTextState>();
        if (editableState != null) {
          final current = editableState.textEditingValue;
          if (current.text.isNotEmpty) {
            final sel = current.selection;
            String newText;
            int newOffset;
            if (sel.isValid && !sel.isCollapsed) {
              newText = current.text.substring(0, sel.start) + current.text.substring(sel.end);
              newOffset = sel.start;
            } else if (sel.isValid && sel.baseOffset > 0) {
              newText = current.text.substring(0, sel.baseOffset - 1) + current.text.substring(sel.baseOffset);
              newOffset = sel.baseOffset - 1;
            } else {
              newText = current.text.substring(0, current.text.length - 1);
              newOffset = newText.length;
            }
            final newValue = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: newOffset),
            );
            editableState.updateEditingValue(newValue);
            ctx.visitAncestorElements((element) {
              if (element.widget is TextField) {
                (element.widget as TextField).onChanged?.call(newText);
                return false;
              }
              return true;
            });
          }
        }
      case 'escape':
        if (ShortcutSystem.instance.isRecording) {
          ShortcutSystem.instance.handleKeyEvent(KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.escape,
            logicalKey: LogicalKeyboardKey.escape,
            timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
          ));
          return;
        }
        if (ChatListPanel.requestCancelSearch()) {
          return;
        }
        final ts = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);
        final handled = HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: ts,
        ));
        HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: ts,
        ));
        if (!handled) {
          final element = WidgetsBinding.instance.rootElement;
          if (element != null) {
            BuildContext? navCtx;
            void findNavigator(Element el) {
              if (navCtx != null) return;
              if (el.widget is Navigator) { navCtx = el; return; }
              el.visitChildren(findNavigator);
            }
            element.visitChildren(findNavigator);
            if (navCtx != null) Navigator.of(navCtx!, rootNavigator: true).maybePop();
          }
        }
      case 'up':
      case 'arrowup':
      case 'arrowUp':
        // CallbackShortcuts at the MaterialApp level binds ArrowUp to
        // ChatView.requestEditLastOutgoing, but that path requires routing
        // through FocusManager (which real OS key events use).
        // HardwareKeyboard.handleKeyEvent from test code doesn't always
        // reach the Shortcuts layer, so invoke the hook directly — same
        // pattern as Ctrl+F above, and it matches what the real Up binding
        // ends up calling anyway.
        ChatView.requestEditLastOutgoing();
      case 'tab':
        final ts = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);
        HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.tab,
          logicalKey: LogicalKeyboardKey.tab,
          timeStamp: ts,
        ));
        HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.tab,
          logicalKey: LogicalKeyboardKey.tab,
          timeStamp: ts,
        ));
      case 'f11':
        MediaViewer.toggleMode();
      case 'rotate':
        MediaViewer.rotate();
      case 'fliph':
        MediaViewer.flipH();
      case 'flipv':
        MediaViewer.flipV();
      case 'save':
        MediaViewer.save();
      case 'copy_media':
        MediaViewer.copyMedia();
      case 'pip':
        MediaViewer.enterPip();
      case 'closepip':
        PipManager.instance.dismiss();
      default:
        if (key.length == 1) {
          final code = key.codeUnitAt(0);
          final physical = code >= 0x30 && code <= 0x39
              ? PhysicalKeyboardKey(0x00070027 + code - 0x39 + 9)
              : PhysicalKeyboardKey(0x00070004 + code - 0x61);
          final logical = LogicalKeyboardKey(code);
          final ts = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);
          HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(
            physicalKey: physical,
            logicalKey: logical,
            character: key,
            timeStamp: ts,
          ));
          HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
            physicalKey: physical,
            logicalKey: logical,
            timeStamp: ts,
          ));
        }
    }
  }

  void _dispatchKeyToRecording(String lc) {
    final parts = lc.split('+');
    final mods = <String>{};
    String base = parts.last;
    for (var i = 0; i < parts.length - 1; i++) {
      mods.add(parts[i]);
    }
    final hasCtrl = mods.contains('ctrl') || mods.contains('control');
    final hasShift = mods.contains('shift');
    final hasAlt = mods.contains('alt');
    final hasMeta = mods.contains('meta') || mods.contains('super');

    final hw = HardwareKeyboard.instance;
    final pressed = hw.physicalKeysPressed;
    final ts = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);

    final pressedCtrl = hasCtrl && !pressed.contains(PhysicalKeyboardKey.controlLeft);
    final pressedShift = hasShift && !pressed.contains(PhysicalKeyboardKey.shiftLeft);
    final pressedAlt = hasAlt && !pressed.contains(PhysicalKeyboardKey.altLeft);
    final pressedMeta = hasMeta && !pressed.contains(PhysicalKeyboardKey.metaLeft);

    if (pressedCtrl) {
      hw.handleKeyEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.controlLeft,
        logicalKey: LogicalKeyboardKey.controlLeft,
        timeStamp: ts,
      ));
    }
    if (pressedShift) {
      hw.handleKeyEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        logicalKey: LogicalKeyboardKey.shiftLeft,
        timeStamp: ts,
      ));
    }
    if (pressedAlt) {
      hw.handleKeyEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.altLeft,
        logicalKey: LogicalKeyboardKey.altLeft,
        timeStamp: ts,
      ));
    }
    if (pressedMeta) {
      hw.handleKeyEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.metaLeft,
        logicalKey: LogicalKeyboardKey.metaLeft,
        timeStamp: ts,
      ));
    }

    final logicalKey = _nameToLogicalKey(base);
    final physicalKey = _nameToPhysicalKey(base);
    ShortcutSystem.instance.handleKeyEvent(KeyDownEvent(
      physicalKey: physicalKey,
      logicalKey: logicalKey,
      timeStamp: ts,
    ));

    if (pressedMeta) {
      hw.handleKeyEvent(KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.metaLeft,
        logicalKey: LogicalKeyboardKey.metaLeft,
        timeStamp: ts,
      ));
    }
    if (pressedAlt) {
      hw.handleKeyEvent(KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.altLeft,
        logicalKey: LogicalKeyboardKey.altLeft,
        timeStamp: ts,
      ));
    }
    if (pressedShift) {
      hw.handleKeyEvent(KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        logicalKey: LogicalKeyboardKey.shiftLeft,
        timeStamp: ts,
      ));
    }
    if (pressedCtrl) {
      hw.handleKeyEvent(KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.controlLeft,
        logicalKey: LogicalKeyboardKey.controlLeft,
        timeStamp: ts,
      ));
    }
  }

  static LogicalKeyboardKey _nameToLogicalKey(String name) {
    switch (name) {
      case 'a': return LogicalKeyboardKey.keyA;
      case 'b': return LogicalKeyboardKey.keyB;
      case 'c': return LogicalKeyboardKey.keyC;
      case 'd': return LogicalKeyboardKey.keyD;
      case 'e': return LogicalKeyboardKey.keyE;
      case 'f': return LogicalKeyboardKey.keyF;
      case 'g': return LogicalKeyboardKey.keyG;
      case 'h': return LogicalKeyboardKey.keyH;
      case 'i': return LogicalKeyboardKey.keyI;
      case 'j': return LogicalKeyboardKey.keyJ;
      case 'k': return LogicalKeyboardKey.keyK;
      case 'l': return LogicalKeyboardKey.keyL;
      case 'm': return LogicalKeyboardKey.keyM;
      case 'n': return LogicalKeyboardKey.keyN;
      case 'o': return LogicalKeyboardKey.keyO;
      case 'p': return LogicalKeyboardKey.keyP;
      case 'q': return LogicalKeyboardKey.keyQ;
      case 'r': return LogicalKeyboardKey.keyR;
      case 's': return LogicalKeyboardKey.keyS;
      case 't': return LogicalKeyboardKey.keyT;
      case 'u': return LogicalKeyboardKey.keyU;
      case 'v': return LogicalKeyboardKey.keyV;
      case 'w': return LogicalKeyboardKey.keyW;
      case 'x': return LogicalKeyboardKey.keyX;
      case 'y': return LogicalKeyboardKey.keyY;
      case 'z': return LogicalKeyboardKey.keyZ;
      case '0': return LogicalKeyboardKey.digit0;
      case '1': return LogicalKeyboardKey.digit1;
      case '2': return LogicalKeyboardKey.digit2;
      case '3': return LogicalKeyboardKey.digit3;
      case '4': return LogicalKeyboardKey.digit4;
      case '5': return LogicalKeyboardKey.digit5;
      case '6': return LogicalKeyboardKey.digit6;
      case '7': return LogicalKeyboardKey.digit7;
      case '8': return LogicalKeyboardKey.digit8;
      case '9': return LogicalKeyboardKey.digit9;
      case 'f1': return LogicalKeyboardKey.f1;
      case 'f2': return LogicalKeyboardKey.f2;
      case 'f3': return LogicalKeyboardKey.f3;
      case 'f4': return LogicalKeyboardKey.f4;
      case 'f5': return LogicalKeyboardKey.f5;
      case 'f6': return LogicalKeyboardKey.f6;
      case 'f7': return LogicalKeyboardKey.f7;
      case 'f8': return LogicalKeyboardKey.f8;
      case 'f9': return LogicalKeyboardKey.f9;
      case 'f10': return LogicalKeyboardKey.f10;
      case 'f11': return LogicalKeyboardKey.f11;
      case 'f12': return LogicalKeyboardKey.f12;
      case 'escape': return LogicalKeyboardKey.escape;
      case 'enter': return LogicalKeyboardKey.enter;
      case 'backspace': return LogicalKeyboardKey.backspace;
      case 'delete': return LogicalKeyboardKey.delete;
      case 'tab': return LogicalKeyboardKey.tab;
      case 'space': return LogicalKeyboardKey.space;
      case 'up': case 'arrowup': return LogicalKeyboardKey.arrowUp;
      case 'down': case 'arrowdown': return LogicalKeyboardKey.arrowDown;
      case 'left': case 'arrowleft': return LogicalKeyboardKey.arrowLeft;
      case 'right': case 'arrowright': return LogicalKeyboardKey.arrowRight;
      case 'home': return LogicalKeyboardKey.home;
      case 'end': return LogicalKeyboardKey.end;
      case 'pageup': case 'pgup': return LogicalKeyboardKey.pageUp;
      case 'pagedown': case 'pgdown': return LogicalKeyboardKey.pageDown;
      case 'insert': return LogicalKeyboardKey.insert;
      case '[': case 'bracketleft': return LogicalKeyboardKey.bracketLeft;
      case ']': case 'bracketright': return LogicalKeyboardKey.bracketRight;
      case '\\': case 'backslash': return LogicalKeyboardKey.backslash;
      case '/': case 'slash': return LogicalKeyboardKey.slash;
      case '-': case 'minus': return LogicalKeyboardKey.minus;
      case '=': case 'equal': return LogicalKeyboardKey.equal;
      default:
        if (name.length == 1) {
          return LogicalKeyboardKey(name.codeUnitAt(0));
        }
        return LogicalKeyboardKey.space;
    }
  }

  static PhysicalKeyboardKey _nameToPhysicalKey(String name) {
    switch (name) {
      case 'a': return PhysicalKeyboardKey.keyA;
      case 'b': return PhysicalKeyboardKey.keyB;
      case 'c': return PhysicalKeyboardKey.keyC;
      case 'd': return PhysicalKeyboardKey.keyD;
      case 'e': return PhysicalKeyboardKey.keyE;
      case 'f': return PhysicalKeyboardKey.keyF;
      case 'g': return PhysicalKeyboardKey.keyG;
      case 'h': return PhysicalKeyboardKey.keyH;
      case 'i': return PhysicalKeyboardKey.keyI;
      case 'j': return PhysicalKeyboardKey.keyJ;
      case 'k': return PhysicalKeyboardKey.keyK;
      case 'l': return PhysicalKeyboardKey.keyL;
      case 'm': return PhysicalKeyboardKey.keyM;
      case 'n': return PhysicalKeyboardKey.keyN;
      case 'o': return PhysicalKeyboardKey.keyO;
      case 'p': return PhysicalKeyboardKey.keyP;
      case 'q': return PhysicalKeyboardKey.keyQ;
      case 'r': return PhysicalKeyboardKey.keyR;
      case 's': return PhysicalKeyboardKey.keyS;
      case 't': return PhysicalKeyboardKey.keyT;
      case 'u': return PhysicalKeyboardKey.keyU;
      case 'v': return PhysicalKeyboardKey.keyV;
      case 'w': return PhysicalKeyboardKey.keyW;
      case 'x': return PhysicalKeyboardKey.keyX;
      case 'y': return PhysicalKeyboardKey.keyY;
      case 'z': return PhysicalKeyboardKey.keyZ;
      case 'escape': return PhysicalKeyboardKey.escape;
      case 'enter': return PhysicalKeyboardKey.enter;
      case 'backspace': return PhysicalKeyboardKey.backspace;
      case 'delete': return PhysicalKeyboardKey.delete;
      case 'tab': return PhysicalKeyboardKey.tab;
      case 'space': return PhysicalKeyboardKey.space;
      default: return PhysicalKeyboardKey(0x00070004);
    }
  }

  // ── UI query helpers ──

  /// Walk the render tree and find all Text widgets, returning their text + screen bounds.
  List<Map<String, dynamic>> _getAllVisibleText() {
    final results = <Map<String, dynamic>>[];
    void visit(Element element) {
      if (element.widget is Text) {
        final text = (element.widget as Text).data ?? (element.widget as Text).textSpan?.toPlainText() ?? '';
        if (text.isNotEmpty) {
          final renderObj = element.findRenderObject();
          if (renderObj is RenderBox && renderObj.hasSize) {
            final topLeft = renderObj.localToGlobal(Offset.zero);
            final size = renderObj.size;
            results.add({
              'text': text.length > 80 ? '${text.substring(0, 80)}...' : text,
              'x': topLeft.dx.round(),
              'y': topLeft.dy.round(),
              'w': size.width.round(),
              'h': size.height.round(),
              'cx': (topLeft.dx + size.width / 2).round(),
              'cy': (topLeft.dy + size.height / 2).round(),
            });
          }
        }
      }
      element.visitChildren(visit);
    }
    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return results;
  }

  /// Find text matching a query (case-insensitive substring) and return matches with coordinates.
  List<Map<String, dynamic>> _findTextOnScreen(String query) {
    final all = _getAllVisibleText();
    final q = query.toLowerCase();
    return all.where((e) => (e['text'] as String).toLowerCase().contains(q)).toList();
  }

  /// Hit-test at coordinates and return the widget chain.
  Map<String, dynamic> _hitTestAt(double x, double y) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, Offset(x, y),
      WidgetsBinding.instance.renderViews.first.flutterView.viewId);
    final entries = <String>[];
    for (final entry in result.path) {
      final target = entry.target;
      entries.add(target.runtimeType.toString());
      if (entries.length >= 10) break; // limit depth
    }
    return {'x': x, 'y': y, 'widgets': entries};
  }

  /// Poll for text to appear on screen, write result when found or timed out.
  void _waitForText(String query, int timeoutSec) {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSec));
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final found = _findTextOnScreen(query);
      if (found.isNotEmpty) {
        timer.cancel();
        File('/tmp/uniclient_debug_out.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({'found': true, 'matches': found}),
        );
      } else if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        File('/tmp/uniclient_debug_out.json').writeAsStringSync(
          jsonEncode({'found': false, 'query': query}),
        );
      }
    });
  }

  @override
  void dispose() {
    _notifDismissTimer?.cancel();
    _debugCmdTimer?.cancel();
    if (_unreadListener != null && _chatStateRef != null) {
      _chatStateRef!.removeListener(_unreadListener!);
    }
    if (_chatStateRef != null) _chatStateRef!.onNotification = null;
    _themeFadeCtrl?.dispose();
    _themeCrossFadeImage?.dispose();
    _instance = null;
    _tray.dispose();
    _webNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    var palette = appState.customPalette ?? switch (appState.themeId) {
      'classic_day' => TelegramPalette.classicDay,
      'day_blue' => TelegramPalette.dayBlue,
      'night_green' => TelegramPalette.nightGreen,
      _ => TelegramPalette.night,
    };
    final accentHex = appState.accentColorHex;
    if (accentHex.length >= 7) {
      final hex = accentHex.replaceFirst('#', '');
      final v = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
      if (v != null) {
        final accentColor = Color(v);
        if (!TelegramPalette.colorEq(accentColor, palette.windowBgActive)) {
          palette = palette.colorize(accentColor);
        }
      }
    }

    if (appState.wallpaper.backgroundColors.isNotEmpty || appState.wallpaper.imageBytes != null) {
      palette = palette.adjustServiceColorsForWallpaper(appState.wallpaper);
    }

    return WallpaperProvider(
      wallpaper: appState.wallpaper,
      child: PaletteProvider(
      palette: palette,
      child: MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [ShortcutLayerObserver()],
      title: 'UniClient',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPalette(palette),
      darkTheme: AppTheme.fromPalette(palette),
      themeMode: ThemeMode.light,
      builder: (context, navigator) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => appState.updateNonIdle(),
          onPointerMove: (_) => appState.updateNonIdle(),
          onPointerSignal: (_) => appState.updateNonIdle(),
          child: Stack(
          children: [
            RepaintBoundary(
              key: _themeBoundaryKey,
              child: Column(
                children: [
                  if (!kIsWeb && Platform.isLinux && !appState.nativeWindowFrame) const CustomTitlebar(),
                  if (!kIsWeb && Platform.isLinux && appState.nativeWindowFrame)
                    Builder(builder: (ctx) {
                      final isDark = Theme.of(ctx).brightness == Brightness.dark;
                      return Container(
                        height: 1,
                        color: isDark
                            ? const Color(0x5604080e)
                            : const Color(0x18000000),
                      );
                    }),
                  Expanded(
                    child: ShortcutListener(
                      child: navigator ?? const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
            if (_themeCrossFadeImage != null && _themeFadeCtrl != null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _themeFadeCtrl!,
                  builder: (context, child) => Opacity(
                    opacity: 1.0 - _themeFadeCtrl!.value,
                    child: child,
                  ),
                  child: RawImage(
                    image: _themeCrossFadeImage,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ListenableBuilder(
              listenable: PipManager.instance,
              builder: (context, _) {
                final pip = PipManager.instance;
                if (!pip.isActive) return const SizedBox.shrink();
                final d = pip.data!;
                return PipOverlayWidget(
                  key: ValueKey(d.message.msgId),
                  player: d.player,
                  videoController: d.videoController,
                  playerSubs: d.playerSubs,
                  message: d.message,
                  mediaMessages: d.mediaMessages,
                  initialVolume: d.volume,
                  initialSpeed: d.playbackSpeed,
                  initialPosition: d.position,
                  initialDuration: d.duration,
                  initialPlaying: d.isPlaying,
                );
              },
            ),
            const _ThemeRevertOverlay(),
            const Positioned.fill(child: _PasscodeLockScreen()),
            if (_notifBanner != null)
              _InAppNotificationBanner(
                data: _notifBanner!,
                onTap: _onNotifBannerTap,
                onDismiss: () {
                  _notifDismissTimer?.cancel();
                  setState(() => _notifBanner = null);
                },
              ),
          ],
        ),
        );
      },
      home: const UniClientShell(),
    ),
    ),
    );
  }
}

/// §25.9.3: Theme switch confirmation overlay with 16s auto-revert countdown.
class _ThemeRevertOverlay extends StatefulWidget {
  const _ThemeRevertOverlay();

  @override
  State<_ThemeRevertOverlay> createState() => _ThemeRevertOverlayState();
}

class _ThemeRevertOverlayState extends State<_ThemeRevertOverlay> {
  static const _totalMs = 15999;
  static const _boxWidth = 320.0;
  static const _boxRadius = 12.0;

  final _escapeFocus = FocusNode();
  Timer? _countdownTimer;
  int _remainingMs = _totalMs;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final testing = context.watch<AppState>().isTestingTheme;
    if (testing && !_visible) {
      _startCountdown();
    } else if (!testing && _visible) {
      _dismiss();
    }
  }

  void _startCountdown() {
    _visible = true;
    _remainingMs = _totalMs;
    _escapeFocus.requestFocus();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _remainingMs -= 100;
      if (_remainingMs <= 0) {
        _revert();
      } else {
        setState(() {});
      }
    });
  }

  void _dismiss() {
    _visible = false;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    setState(() {});
  }

  void _keep() {
    context.read<AppState>().keepAppliedTheme();
  }

  void _revert() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    revertThemeWithCrossFade(context);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _escapeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testing = context.watch<AppState>().isTestingTheme;
    if (!testing && !_visible) return const SizedBox.shrink();

    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Center(
            child: KeyboardListener(
              focusNode: _escapeFocus,
              onKeyEvent: (event) {
                if (event is! KeyDownEvent) return;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _revert();
                } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                  _keep();
                }
              },
              child: _buildBox(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBox(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF222222);
    final subColor = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF666666);
    final accentColor = Theme.of(context).colorScheme.primary;
    final seconds = (_remainingMs / 1000).ceil();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: _boxWidth,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        decoration: BoxDecoration(
          color: boxBg,
          borderRadius: BorderRadius.circular(_boxRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Keep this theme?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Theme will revert in $seconds second${seconds == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 13, color: subColor),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _revert,
                    style: TextButton.styleFrom(
                      foregroundColor: subColor,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Revert'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: _keep,
                    style: TextButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Keep Changes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PasscodeLockScreen extends StatefulWidget {
  const _PasscodeLockScreen();

  @override
  State<_PasscodeLockScreen> createState() => _PasscodeLockScreenState();
}

class _PasscodeLockScreenState extends State<_PasscodeLockScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _duration = Duration(milliseconds: 180);
  static const _errorDuration = Duration(milliseconds: 150);
  static const _curveIn = Curves.easeOutCirc;
  static const _curveOut = Curves.easeInCirc;
  static const _systemUnlockCooldown = Duration(milliseconds: 1000);

  static VoidCallback? _focusPasscode;

  late final AnimationController _anim;
  late final AnimationController _errorAnim;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _obscure = true;
  String _error = '';
  bool _visible = false;
  late final SystemUnlockStatus _unlockStatus;
  bool _systemUnlockEnabled = false;
  DateTime _lastSystemUnlockAttempt = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _unlockStatus = getSystemUnlockStatus();
    WidgetsBinding.instance.addObserver(this);
    _focusPasscode = () => _focusNode.requestFocus();
    _anim = AnimationController(vsync: this, duration: _duration);
    _errorAnim = AnimationController(vsync: this, duration: _errorDuration);
    _anim.addStatusListener(_onAnimStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locked = context.read<AppState>().passcodeLocked;
      if (locked) {
        _visible = true;
        _anim.value = 1.0;
        _focusNode.requestFocus();
      }
      _loadSystemUnlockPref();
    });
  }

  Future<void> _loadSystemUnlockPref() async {
    final appState = context.read<AppState>();
    final dir = appState.configDir;
    if (dir.isEmpty) return;
    final file = File('$dir/local_passcode.json');
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _systemUnlockEnabled = data['systemUnlockEnabled'] as bool? ?? false;
        });
      }
    } catch (_) {}
  }

  bool get _showSystemUnlockButton =>
      _unlockStatus.unlockType != UnlockType.none && _systemUnlockEnabled;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locked = context.watch<AppState>().passcodeLocked;
    if (locked && !_visible) {
      _visible = true;
      _controller.clear();
      _error = '';
      _anim.forward(from: 0.0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    } else if (!locked && _visible && _anim.status != AnimationStatus.reverse) {
      _anim.reverse(from: 1.0);
    }
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_focusPasscode == _focusNode.requestFocus) _focusPasscode = null;
    _anim.removeStatusListener(_onAnimStatus);
    _anim.dispose();
    _errorAnim.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final appState = context.read<AppState>();
    final entered = _controller.text;
    if (entered.isEmpty) {
      _showError('Please enter your passcode');
      return;
    }
    if (!appState.passcodeCanTry()) {
      _showError('Please try again later');
      return;
    }
    if (appState.checkPasscode(entered)) {
      return;
    }
    _showError('Wrong passcode');
  }

  void _showError(String msg) {
    setState(() => _error = msg);
    _errorAnim.forward(from: 0.0);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _focusNode.requestFocus();
  }

  void _clearError() {
    if (_error.isEmpty) return;
    setState(() => _error = '');
    _errorAnim.reverse();
  }

  void _triggerSystemUnlock() {
    final now = DateTime.now();
    if (now.difference(_lastSystemUnlockAttempt) < _systemUnlockCooldown) return;
    _lastSystemUnlockAttempt = now;
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final errorColor = isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final isForward = _anim.status != AnimationStatus.reverse;
        final curve = isForward ? _curveIn : _curveOut;
        final t = curve.transform(_anim.value);
        final slideOffset = Offset((1.0 - t) * 0.15, 0.0);
        return FractionalTranslation(
          translation: slideOffset,
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Material(
        color: bgColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inputY = constraints.maxHeight / 3;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: inputY - 80,
                  child: Text(
                    'Please enter your passcode',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 19, color: textColor),
                  ),
                ),
                Positioned(
                  left: (constraints.maxWidth - 225) / 2,
                  top: inputY,
                  child: SizedBox(
                    width: 225,
                    child: AnimatedBuilder(
                      animation: _errorAnim,
                      builder: (context, _) {
                        final t = _errorAnim.value;
                        final enabledColor = Color.lerp(subtextColor, errorColor, t)!;
                        final focusedColor = Color.lerp(accentColor, errorColor, t)!;
                        return TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          obscureText: _obscure,
                          onChanged: (_) => _clearError(),
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: 'Your passcode',
                            hintStyle: TextStyle(color: subtextColor),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_off : Icons.visibility,
                                color: subtextColor,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: enabledColor),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: focusedColor, width: 2),
                            ),
                            contentPadding: const EdgeInsets.fromLTRB(1, 27, 1, 6),
                          ),
                          style: TextStyle(fontSize: 16, color: textColor),
                        );
                      },
                    ),
                  ),
                ),
                if (_error.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: inputY + 70,
                    child: Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: errorColor),
                    ),
                  ),
                Positioned(
                  left: (constraints.maxWidth - 225) / 2,
                  top: inputY + 70 + (_error.isNotEmpty ? 25 : 0),
                  child: SizedBox(
                    width: 225,
                    height: 42,
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        'Submit',
                        style: TextStyle(fontSize: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                if (_showSystemUnlockButton)
                  Positioned(
                    left: (constraints.maxWidth - 48) / 2,
                    top: inputY + 70 + (_error.isNotEmpty ? 25 : 0) + 42 + 12,
                    child: IconButton(
                      iconSize: 28,
                      style: IconButton.styleFrom(
                        fixedSize: const Size(48, 48),
                        shape: const CircleBorder(),
                      ),
                      icon: Icon(
                        _unlockStatus.unlockType == UnlockType.biometrics
                            ? Icons.fingerprint
                            : Icons.lock_open_outlined,
                        color: accentColor,
                      ),
                      tooltip: getSystemUnlockLabel(_unlockStatus.unlockType),
                      onPressed: _triggerSystemUnlock,
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: inputY + 70 + (_error.isNotEmpty ? 25 : 0) + 42 + 16 + (_showSystemUnlockButton ? 52 : 0),
                  child: GestureDetector(
                    onTap: () {
                      // Log out not implemented — just show info
                    },
                    child: Text(
                      'Log out',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: accentColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotifBannerData {
  final String title;
  final String body;
  final String accountId;
  final String chatId;
  final bool isLocked;
  const _NotifBannerData({
    required this.title,
    required this.body,
    required this.accountId,
    required this.chatId,
    required this.isLocked,
  });
}

class _InAppNotificationBanner extends StatelessWidget {
  final _NotifBannerData data;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _InAppNotificationBanner({
    required this.data,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2B3A4A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF8899A6) : const Color(0xFF666666);
    final shadowColor = isDark ? const Color(0x40000000) : const Color(0x20000000);

    return Positioned(
      top: 8,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: onTap,
        onVerticalDragEnd: (d) {
          if (d.velocity.pixelsPerSecond.dy < -50) onDismiss();
        },
        child: Material(
          elevation: 0,
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: shadowColor, blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3),
                  ),
                  child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.title,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (data.body.isNotEmpty)
                        Text(
                          data.body,
                          style: TextStyle(fontSize: 12, color: subtextColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(Icons.close, size: 16, color: subtextColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

