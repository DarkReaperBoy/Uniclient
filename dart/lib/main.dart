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
import 'ui/chat_view.dart';
import 'ui/choose_datetime_box.dart';
import 'ui/media_viewer.dart';
import 'ui/shell.dart';
import 'ui/titlebar.dart';
import 'utils/debug.dart';
import 'utils/system_tray.dart';
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

  Future<void> _performThemeCrossFade(
      BuildContext ctx, String theme) async {
    final appState = ctx.read<AppState>();
    final pixelRatio = MediaQuery.of(ctx).devicePixelRatio;

    final boundary = _themeBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) {
      appState.updateTheme(theme);
      return;
    }

    // Capture current frame at screen resolution.
    final image = await boundary.toImage(pixelRatio: pixelRatio);

    // Apply new theme — widgets rebuild underneath.
    if (!mounted) { image.dispose(); return; }
    appState.updateTheme(theme);

    // Show captured old frame as overlay, fade it out.
    _themeFadeCtrl?.dispose();
    _themeFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    setState(() => _themeCrossFadeImage = image);

    // Wait one frame so the new theme renders underneath.
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

    // Debug command poller — reads /tmp/uniclient_debug_cmd.json for
    // programmatic UI interaction (smoke testing on Wayland). Desktop-only.
    if (kDebugMode && !kIsWeb) {
      _debugCmdTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _pollDebugCommand(chatState);
      });
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
    // Pointer down.
    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: Offset(x, y),
      buttons: buttons,
      kind: PointerDeviceKind.mouse,
    ));
    // Pointer up (slight delay via microtask to simulate real tap).
    Future.microtask(() {
      binding.handlePointerEvent(PointerUpEvent(
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
    // Handle modifier combos like "ctrl+f" / "control+f". Flutter's
    // CallbackShortcuts only fire from OS-delivered key events that flow
    // through KeyEventManager → FocusManager; HardwareKeyboard.handleKeyEvent
    // alone does not reach the shortcut dispatch path. So we invoke the same
    // callback the shortcut would invoke, to keep the harness observable.
    final lc = key.toLowerCase();
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
        // Chat list search takes priority: if the user is actively searching
        // (Ctrl+F focused the field, query typed), cancel it. This mirrors
        // what OS-delivered Esc does via the app-level CallbackShortcuts
        // binding — needed here too because HardwareKeyboard.handleKeyEvent
        // does not route through Shortcuts.
        if (ChatListPanel.requestCancelSearch()) {
          return;
        }
        // Dispatch real KeyDownEvent + KeyUpEvent through HardwareKeyboard so
        // Focus(onKeyEvent:) handlers (e.g. ChatView's reply/edit/selection
        // cancel) get a chance to handle it first. If nothing handles it,
        // fall through to the legacy Navigator.maybePop() route so that
        // modal popups/dialogs still dismiss on Escape.
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
    _debugCmdTimer?.cancel();
    if (_unreadListener != null && _chatStateRef != null) {
      _chatStateRef!.removeListener(_unreadListener!);
    }
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

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'UniClient',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: appState.themeMode,
      home: Stack(
        children: [
          RepaintBoundary(
            key: _themeBoundaryKey,
            child: Column(
              children: [
                if (!kIsWeb && Platform.isLinux && !appState.nativeWindowFrame) const CustomTitlebar(),
                // Spec §1: NativeTitleRequiresShadow — 1px shadow under native frame
                // when system window decorations are enabled. Replaces the bottom
                // border that the custom titlebar would normally provide.
                if (!kIsWeb && Platform.isLinux && appState.nativeWindowFrame)
                  Builder(builder: (ctx) {
                    final isDark = Theme.of(ctx).brightness == Brightness.dark;
                    return Container(
                      height: 1,
                      color: isDark
                          ? const Color(0x5604080e) // shadowFg night
                          : const Color(0x18000000), // shadowFg day
                    );
                  }),
                Expanded(
                  child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // Telegram Desktop spec §24.4: Ctrl+F opens search in current context.
          // We focus the chat list search field.
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              ChatListPanel.requestFocusSearch,
          // Esc cancels the chat list search if active. Binding only fires
          // when no descendant intercepts the key first, so ChatView's own
          // Focus(onKeyEvent:) Esc handler (reply/edit/selection cancel)
          // still runs when a chat is open. When the sidebar search field
          // itself has focus, no descendant claims Esc → this fires.
          const SingleActivator(LogicalKeyboardKey.escape):
              () => ChatListPanel.requestCancelSearch(),
          // Telegram Desktop spec §24.7: ArrowUp with empty compose field and
          // no edit/reply active → edit last outgoing message. Only fires when
          // no descendant widget (e.g. a focused TextField moving the cursor)
          // consumes the key first — so the same gesture inside a populated
          // field continues to move the cursor normally.
          const SingleActivator(LogicalKeyboardKey.arrowUp):
              () => ChatView.requestEditLastOutgoing(),
          // Telegram Desktop spec §24.4: Alt+Down / Alt+Up move the active
          // selection to the next / previous chat in the visible, sorted
          // chat list (pinned first, then lastMsgTime desc, archived hidden).
          // Commands: `next_chat` / `previous_chat`.
          const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
              () => ChatListPanel.requestNavigateChat(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
              () => ChatListPanel.requestNavigateChat(-1),
          // Telegram Desktop spec §24.4: Ctrl+PgDn / Ctrl+PgUp navigate chats.
          // Desktop-only (§13.5: browsers reserve Ctrl+PgUp/PgDn for tab
          // switching). Alt+Down/Up above still work on web.
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.pageDown, control: true):
              () => ChatListPanel.requestNavigateChat(1),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.pageUp, control: true):
              () => ChatListPanel.requestNavigateChat(-1),
          // Telegram Desktop spec §24.4: Ctrl+Shift+Down / Ctrl+Shift+Up
          // switch to the next / previous folder tab (`next_folder` /
          // `previous_folder`). Tab order: All Chats, then folders in order.
          const SingleActivator(LogicalKeyboardKey.arrowDown, control: true, shift: true):
              () => ChatListPanel.requestNavigateFolder(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp, control: true, shift: true):
              () => ChatListPanel.requestNavigateFolder(-1),
          // Telegram Desktop spec §24.4 Chat Actions: Ctrl+R marks the
          // currently active chat as read. Desktop-only (§13.5: browser
          // intercepts Ctrl+R for page refresh).
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              () => ChatView.requestMarkActiveChatRead(),
          // Telegram Desktop spec §24.4: Ctrl+Alt+Home / Ctrl+Alt+End jump
          // the active chat selection to the first / last chat in the
          // currently visible, sorted sidebar list (`first_chat` /
          // `last_chat`). No-op when the visible list is empty or the
          // target is already active.
          const SingleActivator(LogicalKeyboardKey.home, control: true, alt: true):
              () => ChatListPanel.requestJumpChat(true),
          const SingleActivator(LogicalKeyboardKey.end, control: true, alt: true):
              () => ChatListPanel.requestJumpChat(false),
          // Telegram Desktop spec §24.4 Folder Switching — Ctrl+1..Ctrl+8
          // switch to folder tab by 1-based index. Desktop-only (§13.5:
          // browsers reserve Ctrl+1-8 for tab switching).
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.digit1, control: true):
              () => ChatListPanel.requestSwitchFolderByIndex(1),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.digit2, control: true):
              () => ChatListPanel.requestSwitchFolderByIndex(2),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.digit3, control: true):
              () => ChatListPanel.requestSwitchFolderByIndex(3),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.digit4, control: true):
              () => ChatListPanel.requestSwitchFolderByIndex(4),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.digit5, control: true):
              () => ChatListPanel.requestSwitchFolderByIndex(5),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.digit6, control: true):
              () => ChatListPanel.requestSwitchFolderByIndex(6),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.digit7, control: true):
              () => ChatListPanel.requestSwitchFolderByIndex(7),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.digit8, control: true):
              () => ChatListPanel.requestSwitchFolderByIndex(8),
          // §24.4 Window shortcuts — desktop-only (§13.5: yield to browser
          // combos on web — Ctrl+W/Q/M/F4 are browser-reserved).
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.keyW, control: true):
              () => SystemTray.hideWindowRequest?.call(),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.f4, control: true):
              () => SystemTray.hideWindowRequest?.call(),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.keyM, control: true):
              () => SystemTray.minimizeWindowRequest?.call(),
          if (!kIsWeb) const SingleActivator(LogicalKeyboardKey.keyQ, control: true):
              () => SystemTray.quitAppRequest?.call(),
          // Telegram Desktop spec §24.4 Chat Actions: Ctrl+\ opens the
          // chat-level action menu (peer menu) anchored at the top-bar
          // more_vert button. No-op when no chat is open.
          const SingleActivator(LogicalKeyboardKey.backslash, control: true):
              () => ChatView.requestShowActiveChatMenu(),
          // Telegram Desktop spec §24.6 lines 2982-2983: Ctrl+Up replies to
          // the previous (older) message; Ctrl+Down replies to the next
          // (newer) message, and cancels the reply when already on the newest.
          // No-op when no chat is open, no messages are loaded, or edit mode
          // is active. OS-delivered keystrokes with the compose field focused
          // hit the TextField's FocusNode.onKeyEvent path directly; this
          // binding covers the case where focus is elsewhere (e.g. nothing
          // focused, message list focused).
          const SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
              () => ChatView.requestCycleReply(1),
          const SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
              () => ChatView.requestCycleReply(-1),
        },
        child: const UniClientShell(),
      ),
              ),
            ],
          ),
        ),
          // §3.4: Theme cross-fade overlay — captured old frame fading out.
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
        ],
      ),
    );
  }
}

