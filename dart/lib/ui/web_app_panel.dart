import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:webview_flutter/webview_flutter.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';
import 'emoji_status_widget.dart';

const _kPanelWidth = 384.0;
const _kPanelHeight = 694.0;
const _kHeaderHeight = 56.0;
const _kBottomBarHeight = 50.0;
const _kMainButtonHeight = 40.0;
const _kButtonTextTop = 11.0;
const _kProgressSize = 24.0;
const _kProgressStroke = 4.0;
const _kProgressFadeDuration = Duration(milliseconds: 200);
const _kMenuMaxHeight = 360.0;
const _kBottomPadding = 12.0;
const _kBottomSkipH = 12.0;
const _kBottomSkipV = 8.0;
const _kCornerRadius = 12.0;
const _kPanelShadowBlur = 16.0;
const _kButtonRadius = 6.0;

enum WebAppLoadingState { preOpen, chromeOnly, loading, ready, error }

enum WebAppButtonPosition { top, bottom, left, right }

class WebAppButtonConfig {
  final bool visible;
  final bool active;
  final bool showProgress;
  final String text;
  final Color? textColor;
  final Color? bgColor;
  final String? iconCustomEmojiId;

  const WebAppButtonConfig({
    this.visible = false,
    this.active = true,
    this.showProgress = false,
    this.text = '',
    this.textColor,
    this.bgColor,
    this.iconCustomEmojiId,
  });
}

class WebAppPanelData {
  final String botName;
  final String botUsername;
  final bool isVerified;
  final String url;
  final Color? headerColor;
  final Color? bgColor;
  final Color? bottomBarColor;
  final String accountId;
  final String botId;
  final bool allowClipboardRead;

  const WebAppPanelData({
    required this.botName,
    this.botUsername = '',
    this.isVerified = false,
    this.url = '',
    this.headerColor,
    this.bgColor,
    this.bottomBarColor,
    this.accountId = '',
    this.botId = '',
    this.allowClipboardRead = false,
  });
}

class WebAppPanel extends StatefulWidget {
  final WebAppPanelData data;

  const WebAppPanel({super.key, required this.data});

  static void open(BuildContext context, {required WebAppPanelData data}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: const Color(0x66000000),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
            child: SlideTransition(
              position: animation.drive(
                Tween(begin: const Offset(0, 0.05), end: Offset.zero)
                    .chain(CurveTween(curve: Curves.easeOut)),
              ),
              child: WebAppPanel(data: data),
            ),
          );
        },
      ),
    );
  }

  @override
  State<WebAppPanel> createState() => _WebAppPanelState();
}

class _WebAppPanelState extends State<WebAppPanel>
    with TickerProviderStateMixin {
  WebAppLoadingState _loadingState = WebAppLoadingState.chromeOnly;
  bool _backAllowed = false;
  bool _hasSettingsButton = false;
  bool _closeNeedConfirmation = false;
  bool _fullscreen = false;

  WebAppButtonConfig _mainButton = const WebAppButtonConfig();
  WebAppButtonConfig _secondaryButton = const WebAppButtonConfig();
  WebAppButtonPosition _secondaryPosition = WebAppButtonPosition.left;

  late final AnimationController _progressFade;
  late final AnimationController _spinnerAnim;

  Color? _headerColor;
  Color? _bgColor;
  Color? _bottomBarColor;

  WebViewController? _webController;
  bool _webViewAvailable = false;
  bool _inBlockingRequest = false;
  bool _allowClipboardRead = false;
  bool _hiddenForPayment = false;
  bool _closeConfirmationActive = false;
  DateTime _lastWebviewInteraction = DateTime.fromMillisecondsSinceEpoch(0);
  Size _lastContentSize = Size.zero;

  final Map<String, String?> _deviceStorage = {};
  TelegramPalette? _lastPalette;

  String get _accountId {
    if (widget.data.accountId.isNotEmpty) return widget.data.accountId;
    try {
      return context.read<AppState>().activeAccountId;
    } catch (_) {
      return '';
    }
  }

  String get _botId => widget.data.botId;

  EngineService? get _engine {
    try {
      return context.read<EngineService>();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _headerColor = widget.data.headerColor;
    _bgColor = widget.data.bgColor;
    _bottomBarColor = widget.data.bottomBarColor;
    _allowClipboardRead = widget.data.allowClipboardRead;

    _progressFade = AnimationController(
      vsync: this,
      duration: _kProgressFadeDuration,
      value: 1.0,
    );
    _spinnerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _initWebView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final palette = context.palette;
    if (_lastPalette != null && _lastPalette != palette && _webController != null) {
      _postEventToWebView('theme_changed', {
        'theme_params': _buildThemeParams(palette),
      });
    }
    _lastPalette = palette;
  }

  void _initWebView() {
    if (widget.data.url.isEmpty) {
      _loadingState = WebAppLoadingState.error;
      return;
    }

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel(
          'TelegramWebviewProxy',
          onMessageReceived: _onJsMessage,
        )
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() => _loadingState = WebAppLoadingState.loading);
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              _injectBridgeScript();
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() => _loadingState = WebAppLoadingState.error);
            }
          },
        ))
        ..loadRequest(Uri.parse(widget.data.url));

      _webController = controller;
      _webViewAvailable = true;
      _loadingState = WebAppLoadingState.loading;
    } catch (e) {
      _webViewAvailable = false;
      _loadingState = WebAppLoadingState.ready;
      if (widget.data.url.isNotEmpty) {
        _launchUrl(widget.data.url);
      }
    }
  }

  void _injectBridgeScript() {
    _webController?.runJavaScript('''
(function(){
  window.TelegramWebviewProxy = {
    postEvent: function(eventType, eventData) {
      TelegramWebviewProxy.postMessage(JSON.stringify({
        event: eventType,
        data: eventData || ''
      }));
    }
  };
})();
''');
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final parsed = jsonDecode(message.message) as Map<String, dynamic>;
      final event = parsed['event'] as String? ?? '';
      final rawData = parsed['data'];
      Map<String, dynamic> data;
      if (rawData is Map<String, dynamic>) {
        data = rawData;
      } else if (rawData is String && rawData.isNotEmpty) {
        final decoded = jsonDecode(rawData);
        data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } else {
        data = <String, dynamic>{};
      }
      _handleWebAppEvent(event, data);
    } catch (_) {}
  }

  void _handleWebAppEvent(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'web_app_close':
        Navigator.of(context).pop();
      case 'web_app_ready':
        if (mounted) {
          setState(() => _loadingState = WebAppLoadingState.ready);
          _progressFade.animateTo(0.0, duration: _kProgressFadeDuration * 2);
        }
      case 'web_app_setup_main_button':
        _handleSetupButton(data, isMain: true);
      case 'web_app_setup_secondary_button':
        _handleSetupButton(data, isMain: false);
      case 'web_app_setup_back_button':
        setState(
            () => _backAllowed = data['is_visible'] as bool? ?? _backAllowed);
      case 'web_app_setup_settings_button':
        setState(() =>
            _hasSettingsButton =
                data['is_visible'] as bool? ?? _hasSettingsButton);
      case 'web_app_setup_closing_behavior':
        _closeNeedConfirmation =
            data['need_confirmation'] as bool? ?? false;
      case 'web_app_set_header_color':
        _handleSetHeaderColor(data);
      case 'web_app_set_background_color':
        _handleSetBackgroundColor(data);
      case 'web_app_set_bottom_bar_color':
        _handleSetBottomBarColor(data);
      case 'web_app_request_theme':
        _handleRequestTheme();
      case 'web_app_request_viewport':
        _handleRequestViewport();
      case 'web_app_request_safe_area':
        _postEventToWebView('safe_area_changed',
            {'top': 0, 'bottom': 0, 'left': 0, 'right': 0});
      case 'web_app_request_content_safe_area':
        final mq = MediaQuery.of(context);
        final contentTop = _fullscreen
            ? ((mq.padding.top + _kHeaderHeight) / mq.devicePixelRatio).round()
            : 0;
        _postEventToWebView('content_safe_area_changed',
            {'top': contentTop, 'bottom': 0, 'left': 0, 'right': 0});
      case 'web_app_open_link':
        _handleOpenLink(data);
      case 'web_app_open_tg_link':
        _handleOpenTgLink(data);
      case 'web_app_data_send':
        _handleDataSend(data);
      case 'web_app_switch_inline_query':
        _handleSwitchInlineQuery(data);
      case 'web_app_open_popup':
        _handleOpenPopup(data);
      case 'web_app_open_invoice':
        _handleOpenInvoice(data);
      case 'web_app_open_scan_qr_popup':
        _handleOpenScanQrPopup();
      case 'web_app_share_to_story':
        _handleShareToStory();
      case 'web_app_request_write_access':
        _handleRequestWriteAccess();
      case 'web_app_request_phone':
        _handleRequestPhone();
      case 'web_app_invoke_custom_method':
        _handleInvokeCustomMethod(data);
      case 'web_app_read_text_from_clipboard':
        _handleReadClipboard(data);
      case 'web_app_send_prepared_message':
        _handleSendPreparedMessage(data);
      case 'web_app_request_chat':
        _handleRequestChat(data);
      case 'web_app_set_emoji_status':
        _handleSetEmojiStatus(data);
      case 'web_app_request_emoji_status_access':
        _handleRequestEmojiStatusAccess();
      case 'web_app_device_storage_save_key':
        _handleDeviceStorageSaveKey(data);
      case 'web_app_device_storage_get_key':
        _handleDeviceStorageGetKey(data);
      case 'web_app_device_storage_clear':
        _handleDeviceStorageClear(data);
      case 'web_app_secure_storage_save_key':
      case 'web_app_secure_storage_get_key':
      case 'web_app_secure_storage_restore_key':
      case 'web_app_secure_storage_clear':
        _postEventToWebView('secure_storage_failed', {
          'req_id': data['req_id'] ?? '',
          'error': 'UNSUPPORTED',
        });
      case 'web_app_request_fullscreen':
        if (!_fullscreen) {
          setState(() => _fullscreen = true);
        }
        _postEventToWebView('fullscreen_changed', {'is_fullscreen': _fullscreen});
      case 'web_app_exit_fullscreen':
        if (_fullscreen) {
          setState(() => _fullscreen = false);
        }
        _postEventToWebView('fullscreen_changed', {'is_fullscreen': _fullscreen});
      case 'web_app_request_file_download':
        _handleRequestFileDownload(data);
      case 'web_app_verify_age':
        _handleVerifyAge(data);
      case 'share_score':
        _engine?.callGeneric(
            _accountId, 'BotHandleMenuButton',
            {'bot_id': _botId, 'action': 'share_game'});
      case 'web_app_check_location':
        _postEventToWebView('location_checked', {'available': false});
      case 'web_app_request_location':
        _postEventToWebView('location_requested', {'available': false});
      case 'web_app_biometry_get_info':
        _postEventToWebView('biometry_info_received', {'available': false});
      case 'web_app_check_home_screen':
        _postEventToWebView('home_screen_checked', {'status': 'unsupported'});
      case 'web_app_start_accelerometer':
        _postEventToWebView(
            'accelerometer_failed', {'error': 'UNSUPPORTED'});
      case 'web_app_start_device_orientation':
        _postEventToWebView(
            'device_orientation_failed', {'error': 'UNSUPPORTED'});
      case 'web_app_start_gyroscope':
        _postEventToWebView('gyroscope_failed', {'error': 'UNSUPPORTED'});
    }
  }

  // ── Event handlers ──

  void _handleSetHeaderColor(Map<String, dynamic> data) {
    final c = _parseColor(data['color']) ?? _resolveNamedColor(data['color_key']);
    if (c != null && mounted) setState(() => _headerColor = c);
  }

  void _handleSetBackgroundColor(Map<String, dynamic> data) {
    final c = _parseColor(data['color']) ?? _resolveNamedColor(data['color_key']);
    if (c != null && mounted) setState(() => _bgColor = c);
  }

  void _handleSetBottomBarColor(Map<String, dynamic> data) {
    final c = _parseColor(data['color']) ?? _resolveNamedColor(data['color_key']);
    if (c != null && mounted) setState(() => _bottomBarColor = c);
  }

  void _handleOpenLink(Map<String, dynamic> data) {
    final url = data['url'] as String? ?? '';
    if (url.isEmpty) return;
    final tryIv = data['try_instant_view'] as bool? ?? false;
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotValidateExternalLink',
        {'url': url},
      ).then((result) {
        if (result == null) {
          _close();
          return;
        }
        if (tryIv) {
          engine.callGeneric(
              _accountId, 'BotOpenIvLink', {'url': url});
        } else {
          _launchUrl(url);
        }
      }).catchError((_) {
        _launchUrl(url);
      });
    } else {
      _launchUrl(url);
    }
  }

  void _handleOpenTgLink(Map<String, dynamic> data) {
    final path = data['path_full'] as String? ?? '';
    if (path.isEmpty) {
      _close();
      return;
    }
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotHandleLocalUri',
        {'uri': 'https://t.me$path', 'from_bot': true, 'keep_open': true},
      ).catchError((_) {});
    }
  }

  void _handleDataSend(Map<String, dynamic> data) {
    final payload = data['data'] as String? ?? '';
    if (payload.isEmpty) {
      _close();
      return;
    }
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotSendData',
        {'bot_id': _botId, 'data': payload},
      ).catchError((_) {});
    }
    _close();
  }

  void _handleSwitchInlineQuery(Map<String, dynamic> data) {
    if (!data.containsKey('query')) {
      _close();
      return;
    }
    final query = data['query'] as String? ?? '';
    final validTypes = {'users', 'bots', 'groups', 'channels'};
    final typeArray = (data['chat_types'] as List?)?.cast<String>() ?? [];
    final types = <String>[];
    for (final type in typeArray) {
      if (validTypes.contains(type)) {
        types.add(type);
      } else {
        types.clear();
        break;
      }
    }
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotSwitchInlineQuery',
        {'bot_id': _botId, 'query': query, 'chat_types': types},
      ).catchError((_) {});
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _handleOpenInvoice(Map<String, dynamic> data) {
    final slug = data['slug'] as String? ?? '';
    if (slug.isEmpty) {
      _close();
      return;
    }
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      setState(() => _hiddenForPayment = true);
      engine.callGeneric(
        _accountId,
        'BotHandleInvoice',
        {'bot_id': _botId, 'slug': slug},
      ).then((result) {
        if (!mounted) return;
        final status = result?['status'] as String? ?? 'failed';
        _postEventToWebView('invoice_closed', {'slug': slug, 'status': status});
        setState(() => _hiddenForPayment = false);
      }).catchError((_) {
        if (mounted) {
          _postEventToWebView('invoice_closed', {'slug': slug, 'status': 'failed'});
          setState(() => _hiddenForPayment = false);
        }
      });
    }
  }

  void _handleOpenScanQrPopup() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('QR code scanning is not supported on this platform.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      _postEventToWebView('scan_qr_popup_closed');
    });
  }

  void _handleShareToStory() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Story sharing is not supported.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _handleRequestWriteAccess() {
    if (!mounted) return;
    if (_inBlockingRequest) {
      _postEventToWebView('write_access_requested', {'status': 'cancelled'});
      return;
    }
    _inBlockingRequest = true;
    final engine = _engine;
    if (engine == null || _accountId.isEmpty) {
      _inBlockingRequest = false;
      _postEventToWebView('write_access_requested', {'status': 'cancelled'});
      return;
    }
    engine.callGeneric(
      _accountId,
      'BotCheckWriteAccess',
      {'bot_id': _botId},
    ).then((result) {
      if (!mounted) return;
      if (result != null && result['allowed'] == true) {
        _postEventToWebView('write_access_requested', {'status': 'allowed'});
        return;
      }
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Allow sending messages'),
          content: Text(
              'Do you want to allow ${widget.data.botName} to send you messages?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Allow'),
            ),
          ],
        ),
      ).then((confirmed) {
        if (!mounted) return;
        if (confirmed == true) {
          engine.callGeneric(
            _accountId,
            'BotAllowWriteAccess',
            {'bot_id': _botId},
          ).then((_) {
            _inBlockingRequest = false;
            if (mounted) {
              _postEventToWebView(
                  'write_access_requested', {'status': 'allowed'});
            }
          }).catchError((_) {
            _inBlockingRequest = false;
            if (mounted) {
              _postEventToWebView(
                  'write_access_requested', {'status': 'cancelled'});
            }
          });
        } else {
          _inBlockingRequest = false;
          _postEventToWebView(
              'write_access_requested', {'status': 'cancelled'});
        }
      });
    }).catchError((_) {
      _inBlockingRequest = false;
      if (mounted) {
        _postEventToWebView(
            'write_access_requested', {'status': 'cancelled'});
      }
    });
  }

  void _handleRequestPhone() {
    if (!mounted) return;
    if (_inBlockingRequest) {
      _postEventToWebView('phone_requested', {'status': 'cancelled'});
      return;
    }
    _inBlockingRequest = true;
    final engine = _engine;
    if (engine == null || _accountId.isEmpty) {
      _inBlockingRequest = false;
      _postEventToWebView('phone_requested', {'status': 'cancelled'});
      return;
    }
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share phone number'),
        content: Text(
            '${widget.data.botName} wants to know your phone number. Do you want to share it?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Share'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (!mounted) return;
      if (confirmed == true) {
        engine.callGeneric(
          _accountId,
          'BotSharePhone',
          {'bot_id': _botId},
        ).then((_) {
          _inBlockingRequest = false;
          if (mounted) {
            _postEventToWebView('phone_requested', {'status': 'sent'});
          }
        }).catchError((_) {
          _inBlockingRequest = false;
          if (mounted) {
            _postEventToWebView('phone_requested', {'status': 'cancelled'});
          }
        });
      } else {
        _inBlockingRequest = false;
        _postEventToWebView('phone_requested', {'status': 'cancelled'});
      }
    });
  }

  void _handleInvokeCustomMethod(Map<String, dynamic> data) {
    final reqId = data['req_id'];
    if (reqId == null) return;
    final method = data['method'] as String? ?? '';
    final params = data['params'] as Map<String, dynamic>? ?? {};
    final engine = _engine;
    if (engine == null || _accountId.isEmpty) {
      _postEventToWebView('custom_method_invoked', {
        'req_id': reqId,
        'error': 'ENGINE_UNAVAILABLE',
      });
      return;
    }
    engine.callGeneric(
      _accountId,
      'BotInvokeCustomMethod',
      {'bot_id': _botId, 'method': method, 'params': params},
    ).then((result) {
      if (!mounted) return;
      final response = <String, dynamic>{'req_id': reqId};
      if (result != null && result.containsKey('result')) {
        response['result'] = result['result'];
      } else if (result != null && result.containsKey('error')) {
        response['error'] = result['error'];
      } else {
        response['result'] = result;
      }
      _postEventToWebView('custom_method_invoked', response);
    }).catchError((e) {
      if (mounted) {
        _postEventToWebView('custom_method_invoked', {
          'req_id': reqId,
          'error': e.toString(),
        });
      }
    });
  }

  void _handleReadClipboard(Map<String, dynamic> data) async {
    final reqId = data['req_id'];
    if (reqId == null) return;
    final result = <String, dynamic>{'req_id': reqId};
    final timeSinceInteraction = DateTime.now().difference(_lastWebviewInteraction);
    if (!_allowClipboardRead || timeSinceInteraction.inSeconds > 10) {
      _postEventToWebView('clipboard_text_received', result);
      return;
    }
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipData?.text != null) {
        result['data'] = clipData!.text;
      }
    } catch (_) {}
    _postEventToWebView('clipboard_text_received', result);
  }

  void _handleSendPreparedMessage(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    if (id.isEmpty) {
      _close();
      return;
    }
    final engine = _engine;
    if (engine == null || _accountId.isEmpty) {
      _postEventToWebView('prepared_message_failed', {'error': 'ENGINE_UNAVAILABLE'});
      return;
    }
    engine.callGeneric(
      _accountId,
      'BotSendPreparedMessage',
      {'bot_id': _botId, 'id': id},
    ).then((result) {
      if (!mounted) return;
      if (result != null && result['error'] != null) {
        _postEventToWebView('prepared_message_failed', {
          'error': result['error'].toString(),
        });
      } else {
        _postEventToWebView('prepared_message_sent');
      }
    }).catchError((e) {
      if (mounted) {
        _postEventToWebView('prepared_message_failed', {
          'error': e.toString(),
        });
      }
    });
  }

  void _handleRequestChat(Map<String, dynamic> data) {
    final reqId = data['req_id'] as String? ?? '';
    if (reqId.isEmpty) return;
    final engine = _engine;
    if (engine == null || _accountId.isEmpty) {
      _postEventToWebView('requested_chat_failed', {
        'req_id': reqId,
        'error': 'ENGINE_UNAVAILABLE',
      });
      return;
    }
    engine.callGeneric(
      _accountId,
      'BotRequestChat',
      {'bot_id': _botId, 'req_id': reqId, ...data},
    ).then((result) {
      if (!mounted) return;
      if (result != null && result['error'] != null) {
        _postEventToWebView('requested_chat_failed', {
          'req_id': reqId,
          'error': result['error'].toString(),
        });
      } else {
        _postEventToWebView('requested_chat_sent', {'req_id': reqId});
      }
    }).catchError((e) {
      if (mounted) {
        _postEventToWebView('requested_chat_failed', {
          'req_id': reqId,
          'error': e.toString(),
        });
      }
    });
  }

  void _handleSetEmojiStatus(Map<String, dynamic> data) {
    final emojiId = data['custom_emoji_id']?.toString() ?? '';
    final duration = (data['duration'] as num?)?.toInt() ?? 0;
    if (emojiId.isEmpty || emojiId == '0') {
      _postEventToWebView('emoji_status_failed', {
        'error': 'SUGGESTED_EMOJI_INVALID',
      });
      return;
    }
    if (duration < 0) {
      _postEventToWebView('emoji_status_failed', {
        'error': 'DURATION_INVALID',
      });
      return;
    }
    final engine = _engine;
    if (engine == null || _accountId.isEmpty) {
      _postEventToWebView('emoji_status_failed', {
        'error': 'ENGINE_UNAVAILABLE',
      });
      return;
    }
    engine.callGeneric(
      _accountId,
      'BotSetEmojiStatus',
      {
        'bot_id': _botId,
        'custom_emoji_id': emojiId,
        'duration': duration,
      },
    ).then((result) {
      if (!mounted) return;
      if (result != null && result['error'] != null) {
        _postEventToWebView('emoji_status_failed', {
          'error': result['error'].toString(),
        });
      } else {
        _postEventToWebView('emoji_status_set');
      }
    }).catchError((e) {
      if (mounted) {
        _postEventToWebView('emoji_status_failed', {
          'error': e.toString(),
        });
      }
    });
  }

  void _handleRequestEmojiStatusAccess() {
    if (!mounted) return;
    if (_inBlockingRequest) {
      _postEventToWebView('emoji_status_access_requested', {
        'status': 'cancelled',
      });
      return;
    }
    _inBlockingRequest = true;
    final engine = _engine;
    if (engine == null || _accountId.isEmpty) {
      _inBlockingRequest = false;
      _postEventToWebView('emoji_status_access_requested', {
        'status': 'cancelled',
      });
      return;
    }
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emoji status'),
        content: Text(
            'Do you want to allow ${widget.data.botName} to manage your emoji status?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (!mounted) return;
      if (confirmed != true) {
        _inBlockingRequest = false;
        _postEventToWebView('emoji_status_access_requested', {
          'status': 'cancelled',
        });
        return;
      }
      engine.callGeneric(
        _accountId,
        'BotRequestEmojiStatusAccess',
        {'bot_id': _botId},
      ).then((result) {
        _inBlockingRequest = false;
        if (!mounted) return;
        final allowed = result != null && result['allowed'] == true;
        _postEventToWebView('emoji_status_access_requested', {
          'status': allowed ? 'allowed' : 'cancelled',
        });
      }).catchError((_) {
        _inBlockingRequest = false;
        if (mounted) {
          _postEventToWebView('emoji_status_access_requested', {
            'status': 'cancelled',
          });
        }
      });
    });
  }

  void _handleDeviceStorageSaveKey(Map<String, dynamic> data) {
    final reqId = data['req_id'] ?? '';
    final keyObj = data['key'];
    final valueObj = data['value'];
    if (keyObj is! String) {
      _postEventToWebView('device_storage_failed', {
        'req_id': reqId,
        'error': 'KEY_INVALID',
      });
      return;
    }
    if (valueObj != null && valueObj is! String) {
      _postEventToWebView('device_storage_failed', {
        'req_id': reqId,
        'error': 'VALUE_INVALID',
      });
      return;
    }
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotStorageWrite',
        {'bot_id': _botId, 'key': keyObj, 'value': valueObj},
      ).then((_) {
        if (mounted) {
          _postEventToWebView('device_storage_key_saved', {'req_id': reqId});
        }
      }).catchError((e) {
        if (mounted) {
          final errStr = e.toString().toLowerCase();
          final errorCode = errStr.contains('quota') ? 'QUOTA_EXCEEDED' : 'WRITE_FAILED';
          _postEventToWebView('device_storage_failed', {'req_id': reqId, 'error': errorCode});
        }
      });
    } else {
      _deviceStorage[keyObj] = valueObj as String?;
      _postEventToWebView('device_storage_key_saved', {'req_id': reqId});
    }
  }

  void _handleDeviceStorageGetKey(Map<String, dynamic> data) {
    final reqId = data['req_id'] ?? '';
    final keyObj = data['key'];
    if (keyObj is! String) {
      _postEventToWebView('device_storage_failed', {
        'req_id': reqId,
        'error': 'KEY_INVALID',
      });
      return;
    }
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotStorageRead',
        {'bot_id': _botId, 'key': keyObj},
      ).then((result) {
        if (mounted) {
          _postEventToWebView('device_storage_key_received', {
            'req_id': reqId,
            'value': result?['value'],
          });
        }
      }).catchError((_) {
        if (mounted) {
          _postEventToWebView('device_storage_key_received', {'req_id': reqId, 'value': null});
        }
      });
    } else {
      final value = _deviceStorage[keyObj];
      _postEventToWebView('device_storage_key_received', {
        'req_id': reqId,
        'value': value,
      });
    }
  }

  void _handleDeviceStorageClear(Map<String, dynamic> data) {
    final reqId = data['req_id'] ?? '';
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotStorageClear',
        {'bot_id': _botId},
      ).then((_) {
        if (mounted) {
          _postEventToWebView('device_storage_cleared', {'req_id': reqId});
        }
      }).catchError((_) {
        if (mounted) {
          _postEventToWebView('device_storage_cleared', {'req_id': reqId});
        }
      });
    } else {
      _deviceStorage.clear();
      _postEventToWebView('device_storage_cleared', {'req_id': reqId});
    }
  }

  void _handleRequestFileDownload(Map<String, dynamic> data) {
    final url = data['url'] as String? ?? '';
    final name = data['file_name'] as String? ?? '';
    if (url.isEmpty || name.isEmpty) {
      _close();
      return;
    }
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotDownloadFile',
        {'bot_id': _botId, 'url': url, 'file_name': name},
      ).then((result) {
        if (!mounted) return;
        final started = result != null && result['started'] == true;
        _postEventToWebView('file_download_requested', {
          'status': started ? 'downloading' : 'cancelled',
        });
      }).catchError((_) {
        if (mounted) {
          _postEventToWebView('file_download_requested', {
            'status': 'cancelled',
          });
        }
      });
    } else {
      _postEventToWebView('file_download_requested', {
        'status': 'cancelled',
      });
    }
  }

  void _handleVerifyAge(Map<String, dynamic> data) {
    final passed = data['passed'] as bool? ?? false;
    final detected = data['age'];
    final valid = passed && detected is num;
    final age = valid ? detected.toInt() : 0;
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      engine.callGeneric(
        _accountId,
        'BotVerifyAge',
        {'bot_id': _botId, 'age': age},
      ).catchError((_) {});
    }
  }

  // ── Button setup ──

  void _handleSetupButton(Map<String, dynamic> data, {required bool isMain}) {
    if (data.isEmpty) {
      _close();
      return;
    }
    setState(() {
      final text = (data['text'] as String? ?? '').trim();
      final emojiId = data['icon_custom_emoji_id'] as String?;
      final rawVisible = data['is_visible'] as bool? ?? false;
      final effectiveVisible = rawVisible && (text.isNotEmpty || (emojiId != null && emojiId.isNotEmpty));
      final updated = WebAppButtonConfig(
        visible: effectiveVisible,
        active: data['is_active'] as bool? ?? false,
        showProgress: data['is_progress_visible'] as bool? ?? false,
        text: text,
        textColor: _parseColor(data['text_color']),
        bgColor: _parseColor(data['color']),
        iconCustomEmojiId: emojiId,
      );
      if (isMain) {
        _mainButton = updated;
      } else {
        _secondaryButton = updated;
        if (data.containsKey('position')) {
          _secondaryPosition =
              _parsePosition(data['position'] as String? ?? '');
        }
      }
    });
  }

  WebAppButtonPosition _parsePosition(String position) {
    return switch (position) {
      'top' => WebAppButtonPosition.top,
      'bottom' => WebAppButtonPosition.bottom,
      'right' => WebAppButtonPosition.right,
      _ => WebAppButtonPosition.left,
    };
  }

  void _handleRequestTheme() {
    if (!mounted) return;
    final palette = context.palette;
    _postEventToWebView('theme_changed', {
      'theme_params': _buildThemeParams(palette),
    });
  }

  void _handleRequestViewport() {
    if (!mounted) return;
    _webController?.runJavaScript('''
(function(){
  var h = window.innerHeight || 0;
  var w = window.innerWidth || 0;
  if(window.TelegramGameProxy){
    window.TelegramGameProxy.receiveEvent('viewport_changed',
      {height:h,width:w,is_state_stable:true,is_expanded:true});
  }
})();
''');
  }

  void _handleOpenPopup(Map<String, dynamic> data) {
    final title = data['title'] as String? ?? '';
    final message = data['message'] as String? ?? '';
    final buttons =
        (data['buttons'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (message.isEmpty || buttons.isEmpty) {
      _close();
      return;
    }

    const validTypes = {'default', 'ok', 'close', 'cancel', 'destructive'};
    final validButtons = buttons.where((btn) {
      final type = btn['type'] as String? ?? 'default';
      return validTypes.contains(type);
    }).toList();
    if (validButtons.isEmpty) {
      _close();
      return;
    }

    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: title.isNotEmpty ? Text(title) : null,
        content: Text(message),
        actions: validButtons.map((btn) {
          final id = btn['id'] as String? ?? '';
          final type = btn['type'] as String? ?? 'default';
          final text = btn['text'] as String? ?? '';
          return TextButton(
            onPressed: () => Navigator.of(ctx).pop(id),
            child: Text(text,
                style: TextStyle(
                  color: type == 'destructive' ? Colors.red : null,
                  fontWeight: type == 'ok' ? FontWeight.w600 : null,
                )),
          );
        }).toList(),
      ),
    ).then((buttonId) {
      _postEventToWebView('popup_closed', {'button_id': buttonId ?? ''});
    });
  }

  // ── Color helpers ──

  Map<String, String> _buildThemeParams(TelegramPalette palette) {
    return {
      'bg_color': _colorToHex(palette.windowBg),
      'text_color': _colorToHex(palette.windowFg),
      'hint_color': _colorToHex(palette.windowSubTextFg),
      'link_color': _colorToHex(palette.windowActiveTextFg),
      'button_color': _colorToHex(palette.windowBgActive),
      'button_text_color': _colorToHex(palette.windowFgActive),
      'secondary_bg_color': _colorToHex(palette.windowBgOver),
      'header_bg_color': _colorToHex(_headerColor ?? palette.windowBg),
      'accent_text_color': _colorToHex(palette.windowActiveTextFg),
      'section_bg_color': _colorToHex(palette.windowBg),
      'section_header_text_color': _colorToHex(palette.windowActiveTextFg),
      'subtitle_text_color': _colorToHex(palette.windowSubTextFg),
      'destructive_text_color': _colorToHex(palette.attentionButtonFg),
    };
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  Color? _parseColor(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    if (str.startsWith('#') && str.length >= 7) {
      final intVal = int.tryParse(str.substring(1, 7), radix: 16);
      if (intVal != null) return Color(0xFF000000 | intVal);
    }
    return _resolveNamedColor(str);
  }

  Color? _resolveNamedColor(dynamic key) {
    if (key == null) return null;
    final name = key.toString();
    if (!mounted) return null;
    final palette = context.palette;
    switch (name) {
      case 'bg_color':
        return palette.windowBg;
      case 'secondary_bg_color':
        return palette.boxDividerBg;
      case 'bottom_bar_bg_color':
        return palette.windowBg;
      case 'text_color':
        return palette.windowFg;
      case 'hint_color':
        return palette.windowSubTextFg;
      case 'link_color':
        return palette.windowActiveTextFg;
      case 'button_color':
        return palette.windowBgActive;
      case 'button_text_color':
        return palette.windowFgActive;
      case 'header_bg_color':
        return _headerColor ?? palette.windowBg;
      default:
        return null;
    }
  }

  void _postEventToWebView(String event, [Map<String, dynamic>? data]) {
    final controller = _webController;
    if (controller == null) return;
    final jsonData = data != null ? jsonEncode(data) : '{}';
    try {
      controller.runJavaScript(
        "if(window.TelegramGameProxy)"
        "{window.TelegramGameProxy.receiveEvent('$event',$jsonData);}",
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _progressFade.dispose();
    _spinnerAnim.dispose();
    super.dispose();
  }

  void _close() {
    if (_closeNeedConfirmation) {
      _showCloseConfirmation();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showCloseConfirmation() {
    if (_closeConfirmationActive) return;
    _closeConfirmationActive = true;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Web App'),
        content: const Text('Are you sure you want to close this web app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    ).then((confirmed) {
      _closeConfirmationActive = false;
      if (confirmed == true && mounted) Navigator.of(context).pop();
    });
  }

  void _onBack() {
    _postEventToWebView('back_button_pressed');
  }

  Future<void> _showMenu(BuildContext context) async {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF17212b) : Colors.white;
    final menuFg = isDark ? Colors.white : Colors.black87;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
            Offset(button.size.width - 8, _kHeaderHeight),
            ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    List<Map<String, dynamic>> downloads = [];
    final engine = _engine;
    if (engine != null && _accountId.isNotEmpty) {
      try {
        final dlResult = await engine.callGeneric(
          _accountId,
          'BotGetDownloads',
          {'bot_id': _botId},
        );
        if (dlResult != null && dlResult['downloads'] is List) {
          downloads = (dlResult['downloads'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final menuItems = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'open_bot',
        child: Row(children: [
          Icon(Icons.smart_toy_outlined, size: 20, color: menuFg),
          const SizedBox(width: 12),
          Text('Open Bot',
              style: TextStyle(color: menuFg, fontSize: 14)),
        ]),
      ),
      if (downloads.isNotEmpty) ...[
        const PopupMenuDivider(),
        for (final dl in downloads)
          PopupMenuItem<String>(
            value: 'download_${dl['id'] ?? ''}',
            child: Row(children: [
              Icon(Icons.download_outlined, size: 20, color: menuFg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dl['file_name'] as String? ?? 'Download',
                  style: TextStyle(color: menuFg, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        const PopupMenuDivider(),
      ],
      if (_hasSettingsButton)
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(children: [
            Icon(Icons.settings_outlined, size: 20, color: menuFg),
            const SizedBox(width: 12),
            Text('Settings',
                style: TextStyle(color: menuFg, fontSize: 14)),
          ]),
        ),
      PopupMenuItem<String>(
        value: 'reload',
        child: Row(children: [
          Icon(Icons.refresh, size: 20, color: menuFg),
          const SizedBox(width: 12),
          Text('Reload Page',
              style: TextStyle(color: menuFg, fontSize: 14)),
        ]),
      ),
      PopupMenuItem<String>(
        value: 'terms',
        child: Row(children: [
          Icon(Icons.description_outlined, size: 20, color: menuFg),
          const SizedBox(width: 12),
          Text('Terms of Use',
              style: TextStyle(color: menuFg, fontSize: 14)),
        ]),
      ),
      PopupMenuItem<String>(
        value: 'privacy',
        child: Row(children: [
          Icon(Icons.privacy_tip_outlined, size: 20, color: menuFg),
          const SizedBox(width: 12),
          Text('Privacy Policy',
              style: TextStyle(color: menuFg, fontSize: 14)),
        ]),
      ),
      PopupMenuItem<String>(
        value: 'remove_menu',
        child: Row(children: [
          Icon(Icons.delete_outline, size: 20, color: menuFg),
          const SizedBox(width: 12),
          Text('Remove from Menu',
              style: TextStyle(color: menuFg, fontSize: 14)),
        ]),
      ),
    ];

    final result = await showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(maxHeight: _kMenuMaxHeight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: menuBg,
      items: menuItems,
    );

    if (result == null || !mounted) return;
    if (result.startsWith('download_')) {
      final id = result.substring('download_'.length);
      _engine?.callGeneric(
        _accountId,
        'BotDownloadsAction',
        {'bot_id': _botId, 'id': id, 'action': 'open'},
      ).catchError((_) {});
      return;
    }
    switch (result) {
      case 'open_bot':
        final eng = _engine;
        if (eng != null && _accountId.isNotEmpty) {
          eng.callGeneric(
            _accountId,
            'BotHandleMenuButton',
            {'bot_id': _botId, 'action': 'open_bot'},
          ).catchError((_) {});
        }
      case 'settings':
        _postEventToWebView('settings_button_pressed');
      case 'reload':
        _webController?.reload();
      case 'terms':
        _launchUrl('https://telegram.org/tos/mini-apps');
      case 'privacy':
        _launchUrl(
            'https://telegram.org/privacy-miniapp#mini-apps-privacy-policy');
      case 'remove_menu':
        final eng = _engine;
        if (eng != null && _accountId.isNotEmpty) {
          eng.callGeneric(
            _accountId,
            'BotHandleMenuButton',
            {'bot_id': _botId, 'action': 'remove_from_menu'},
          ).catchError((_) {});
        }
        _close();
    }
  }

  Color _buttonRippleColor(Color bg) {
    final hsv = HSVColor.fromColor(bg);
    if (hsv.value * 255 > 128) {
      return HSVColor.fromAHSV(hsv.alpha, hsv.hue, hsv.saturation,
              (hsv.value - 32 / 255).clamp(0.0, 1.0))
          .toColor();
    }
    return HSVColor.fromAHSV(hsv.alpha, hsv.hue, hsv.saturation,
            (hsv.value + 32 / 255).clamp(0.0, 1.0))
        .toColor();
  }

  void _launchUrl(String url) {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    url_launcher.launchUrl(uri,
        mode: url_launcher.LaunchMode.externalApplication);
  }

  Color _computeBottomLabelColor(Color bgColor) {
    final luminance = 0.2126 * bgColor.r
        + 0.7152 * bgColor.g
        + 0.0722 * bgColor.b;
    final textColor = (luminance > 0.5) ? Colors.black : Colors.white;
    final textLuminance = (luminance > 0.5) ? 0.0 : 1.0;
    const contrast = 2.5;
    final adaptiveOpacity =
        (luminance - textLuminance + contrast) / contrast;
    final opacity = adaptiveOpacity.clamp(0.5, 0.64);
    return textColor.withValues(alpha: opacity);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;

    final panelWidth = _kPanelWidth.clamp(0.0, screenSize.width - 32);
    final panelHeight = _kPanelHeight.clamp(0.0, screenSize.height - 32);

    final headerBg = _headerColor ?? palette.windowBg;
    final contentBg = _bgColor ?? palette.windowBg;
    final bottomBg = _bottomBarColor ?? palette.windowBg;

    final defaultButtonBg = palette.windowBgActive;
    final defaultButtonFg = palette.windowFgActive;

    return Opacity(
      opacity: _hiddenForPayment ? 0.0 : 1.0,
      child: IgnorePointer(
        ignoring: _hiddenForPayment,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: panelWidth,
                height: panelHeight,
                decoration: BoxDecoration(
                  color: contentBg,
                  borderRadius: BorderRadius.circular(_kCornerRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: _kPanelShadowBlur,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildHeader(headerBg, palette, isDark),
                    Expanded(
                        child: _buildContent(contentBg, palette, isDark)),
                    _buildBottomSection(bottomBg, defaultButtonBg,
                        defaultButtonFg, palette, isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color bg, TelegramPalette palette, bool isDark) {
    final titleColor = _headerColor != null
        ? (_headerColor!.computeLuminance() > 0.5
            ? Colors.black
            : Colors.white)
        : (isDark ? Colors.white : Colors.black);
    final iconColor = titleColor.withValues(alpha: 0.7);

    return Container(
      height: _kHeaderHeight,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (_backAllowed)
            _HeaderButton(
              icon: Icons.arrow_back,
              color: iconColor,
              onTap: _onBack,
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.data.botName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (widget.data.isVerified) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified,
                        size: 16, color: palette.windowBgActive),
                  ],
                ],
              ),
            ),
          ),
          _HeaderButton(
            icon: Icons.more_vert,
            color: iconColor,
            onTap: () => _showMenu(context),
          ),
          _HeaderButton(
            icon: Icons.close,
            color: iconColor,
            onTap: _close,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Color bg, TelegramPalette palette, bool isDark) {
    if (_loadingState == WebAppLoadingState.error) {
      return Container(
        color: bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48,
                  color: palette.windowFg.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text('Failed to load Web App',
                  style: TextStyle(
                      fontSize: 14,
                      color: palette.windowFg.withValues(alpha: 0.6))),
            ],
          ),
        ),
      );
    }

    if (_webViewAvailable && _webController != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final newSize = Size(constraints.maxWidth, constraints.maxHeight);
          if (newSize != _lastContentSize) {
            _lastContentSize = newSize;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _handleRequestViewport();
            });
          }
          return Stack(
            children: [
              Listener(
                onPointerDown: (_) =>
                    _lastWebviewInteraction = DateTime.now(),
                behavior: HitTestBehavior.translucent,
                child: WebViewWidget(controller: _webController!),
              ),
              if (_loadingState != WebAppLoadingState.ready)
                Container(
                  color: bg,
                  child: Center(
                    child: FadeTransition(
                      opacity: _progressFade,
                      child: _InfiniteRadialSpinner(
                        animation: _spinnerAnim,
                        size: _kProgressSize,
                        strokeWidth: _kProgressStroke,
                        color: palette.windowSubTextFg,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    return Container(
      color: bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_browser,
                size: 48,
                color: palette.windowFg.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('Opened in browser',
                style: TextStyle(
                    fontSize: 14,
                    color: palette.windowFg.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection(
    Color bottomBg,
    Color defaultButtonBg,
    Color defaultButtonFg,
    TelegramPalette palette,
    bool isDark,
  ) {
    final mainBg = _mainButton.bgColor ?? defaultButtonBg;
    final mainFg = _mainButton.textColor ?? defaultButtonFg;
    final secBg = _secondaryButton.bgColor ?? defaultButtonBg;
    final secFg = _secondaryButton.textColor ?? defaultButtonFg;

    final mainBtn = _mainButton.visible
        ? _WebAppButton(
            text: _mainButton.text,
            textColor: mainFg,
            bgColor: mainBg,
            active: _mainButton.active,
            showProgress: _mainButton.showProgress,
            rippleColor: _buttonRippleColor(mainBg),
            onPressed: () => _postEventToWebView('main_button_pressed'),
            iconCustomEmojiId: _mainButton.iconCustomEmojiId,
            accountId: _accountId,
          )
        : null;

    final secBtn = _secondaryButton.visible
        ? _WebAppButton(
            text: _secondaryButton.text,
            textColor: secFg,
            bgColor: secBg,
            active: _secondaryButton.active,
            showProgress: _secondaryButton.showProgress,
            rippleColor: _buttonRippleColor(secBg),
            onPressed: () =>
                _postEventToWebView('secondary_button_pressed'),
            iconCustomEmojiId: _secondaryButton.iconCustomEmojiId,
            accountId: _accountId,
          )
        : null;

    Widget? buttonArea;
    if (mainBtn != null || secBtn != null) {
      if (mainBtn != null && secBtn != null) {
        final isVertical = _secondaryPosition == WebAppButtonPosition.top ||
            _secondaryPosition == WebAppButtonPosition.bottom;
        if (isVertical) {
          final first = _secondaryPosition == WebAppButtonPosition.top
              ? secBtn
              : mainBtn;
          final second = _secondaryPosition == WebAppButtonPosition.top
              ? mainBtn
              : secBtn;
          buttonArea = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              first,
              SizedBox(height: _kBottomSkipV),
              second,
            ],
          );
        } else {
          final first = _secondaryPosition == WebAppButtonPosition.left
              ? secBtn
              : mainBtn;
          final second = _secondaryPosition == WebAppButtonPosition.left
              ? mainBtn
              : secBtn;
          buttonArea = Row(
            children: [
              Expanded(child: first),
              SizedBox(width: _kBottomSkipH),
              Expanded(child: second),
            ],
          );
        }
      } else {
        buttonArea = mainBtn ?? secBtn;
      }
    }

    final labelColor = _computeBottomLabelColor(bottomBg);

    return Container(
      color: bottomBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (buttonArea != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _kBottomPadding, _kBottomPadding, _kBottomPadding, 0,
              ),
              child: buttonArea,
            ),
          Padding(
            padding: const EdgeInsets.all(_kBottomPadding),
            child: Text(
              widget.data.botUsername.isNotEmpty
                  ? '@${widget.data.botUsername}'
                  : '',
              style: TextStyle(
                fontSize: 12,
                color: labelColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 22, color: color),
        onPressed: onTap,
        splashRadius: 20,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _WebAppButton extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color bgColor;
  final bool active;
  final bool showProgress;
  final Color rippleColor;
  final VoidCallback onPressed;
  final String? iconCustomEmojiId;
  final String accountId;

  const _WebAppButton({
    required this.text,
    required this.textColor,
    required this.bgColor,
    required this.active,
    required this.showProgress,
    required this.rippleColor,
    required this.onPressed,
    this.iconCustomEmojiId,
    this.accountId = '',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kMainButtonHeight,
      width: double.infinity,
      child: Material(
        color: active ? bgColor : bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(_kButtonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kButtonRadius),
          splashColor: rippleColor.withValues(alpha: 0.3),
          onTap: active ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (iconCustomEmojiId != null && iconCustomEmojiId!.isNotEmpty && accountId.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(right: text.isNotEmpty ? 6 : 0),
                        child: EmojiStatusWidget(
                          emojiStatusId: iconCustomEmojiId!,
                          accountId: accountId,
                          size: 20,
                        ),
                      ),
                    if (text.isNotEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(top: _kButtonTextTop - 8),
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: active
                                  ? textColor
                                  : textColor.withValues(alpha: 0.5),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                  ],
                ),
                if (showProgress)
                  Positioned(
                    right: 0,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(textColor),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfiniteRadialSpinner extends StatelessWidget {
  final Animation<double> animation;
  final double size;
  final double strokeWidth;
  final Color color;

  const _InfiniteRadialSpinner({
    required this.animation,
    required this.size,
    required this.strokeWidth,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return CustomPaint(
          size: Size(size, size),
          painter: _SpinnerPainter(
            progress: animation.value,
            color: color,
            strokeWidth: strokeWidth,
          ),
        );
      },
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _SpinnerPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final startAngle = progress * 2 * math.pi - math.pi / 2;
    final sweepAngle = 1.2 + 0.8 * math.sin(progress * math.pi);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth;
}

void showWebAppDisclaimerDialog(
  BuildContext context, {
  required String botName,
  required VoidCallback onAccept,
}) {
  showDialog(
    context: context,
    builder: (ctx) {
      bool accepted = false;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Open $botName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You are about to open a mini app operated by a third-party developer. '
                'The content is not affiliated with Telegram.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: accepted,
                    onChanged: (v) =>
                        setDialogState(() => accepted = v ?? false),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'I understand',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: accepted
                  ? () {
                      Navigator.of(ctx).pop();
                      onAccept();
                    }
                  : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    },
  );
}
