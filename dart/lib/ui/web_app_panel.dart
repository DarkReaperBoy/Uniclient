import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/telegram_palette.dart';

const _kPanelWidth = 384.0;
const _kPanelHeight = 694.0;
const _kHeaderHeight = 56.0;
const _kBottomBarHeight = 50.0;
const _kMainButtonHeight = 40.0;
const _kButtonTextTop = 11.0;
const _kProgressSize = 24.0;
const _kProgressStroke = 4.0;
const _kProgressOpacity = 0.3;
const _kProgressFadeDuration = Duration(milliseconds: 200);
const _kMenuMaxHeight = 360.0;
const _kBottomPadding = 12.0;
const _kBottomSkipH = 12.0;
const _kBottomSkipV = 8.0;
const _kCornerRadius = 12.0;
const _kPanelShadowBlur = 16.0;

enum WebAppLoadingState { preOpen, chromeOnly, loading, ready, error }

enum WebAppButtonPosition { top, bottom, left, right }

class WebAppButtonConfig {
  final bool visible;
  final bool active;
  final bool showProgress;
  final String text;
  final Color? textColor;
  final Color? bgColor;

  const WebAppButtonConfig({
    this.visible = false,
    this.active = true,
    this.showProgress = false,
    this.text = '',
    this.textColor,
    this.bgColor,
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

  const WebAppPanelData({
    required this.botName,
    this.botUsername = '',
    this.isVerified = false,
    this.url = '',
    this.headerColor,
    this.bgColor,
    this.bottomBarColor,
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

  WebAppButtonConfig _mainButton = const WebAppButtonConfig();
  WebAppButtonConfig _secondaryButton = const WebAppButtonConfig();
  WebAppButtonPosition _secondaryPosition = WebAppButtonPosition.bottom;

  late final AnimationController _progressFade;
  late final AnimationController _spinnerAnim;

  Color? _headerColor;
  Color? _bgColor;
  Color? _bottomBarColor;

  @override
  void initState() {
    super.initState();
    _headerColor = widget.data.headerColor;
    _bgColor = widget.data.bgColor;
    _bottomBarColor = widget.data.bottomBarColor;

    _progressFade = AnimationController(
      vsync: this,
      duration: _kProgressFadeDuration,
      value: 1.0,
    );
    _spinnerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _simulateLoading();
  }

  void _simulateLoading() {
    setState(() => _loadingState = WebAppLoadingState.loading);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (widget.data.url.isNotEmpty) {
        setState(() => _loadingState = WebAppLoadingState.ready);
        _progressFade.animateTo(0.0, duration: _kProgressFadeDuration * 2);
      } else {
        setState(() => _loadingState = WebAppLoadingState.error);
      }
    });
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
      if (confirmed == true && mounted) Navigator.of(context).pop();
    });
  }

  void _onBack() {}

  void _showMenu(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF17212b) : Colors.white;
    final menuFg = isDark ? Colors.white : Colors.black87;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(button.size.width - 8, _kHeaderHeight), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(maxHeight: _kMenuMaxHeight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: menuBg,
      items: [
        PopupMenuItem<String>(
          value: 'open_bot',
          child: Row(children: [
            Icon(Icons.smart_toy_outlined, size: 20, color: menuFg),
            const SizedBox(width: 12),
            Text('Open Bot', style: TextStyle(color: menuFg, fontSize: 14)),
          ]),
        ),
        if (_hasSettingsButton)
          PopupMenuItem<String>(
            value: 'settings',
            child: Row(children: [
              Icon(Icons.settings_outlined, size: 20, color: menuFg),
              const SizedBox(width: 12),
              Text('Settings', style: TextStyle(color: menuFg, fontSize: 14)),
            ]),
          ),
        PopupMenuItem<String>(
          value: 'remove_menu',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 20, color: menuFg),
            const SizedBox(width: 12),
            Text('Remove from Menu', style: TextStyle(color: menuFg, fontSize: 14)),
          ]),
        ),
      ],
    );
  }

  Color _buttonRippleColor(Color bg) {
    final hsv = HSVColor.fromColor(bg);
    if (hsv.value * 255 > 128) {
      return HSVColor.fromAHSV(hsv.alpha, hsv.hue, hsv.saturation,
          (hsv.value - 32 / 255).clamp(0.0, 1.0)).toColor();
    }
    return HSVColor.fromAHSV(hsv.alpha, hsv.hue, hsv.saturation,
        (hsv.value + 32 / 255).clamp(0.0, 1.0)).toColor();
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

    return Center(
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
                Expanded(child: _buildContent(contentBg, palette, isDark)),
                _buildBottomSection(bottomBg, defaultButtonBg, defaultButtonFg, palette, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color bg, TelegramPalette palette, bool isDark) {
    final titleColor = _headerColor != null
        ? (_headerColor!.computeLuminance() > 0.5 ? Colors.black : Colors.white)
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
                    Icon(Icons.verified, size: 16, color: palette.windowBgActive),
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
    switch (_loadingState) {
      case WebAppLoadingState.preOpen:
      case WebAppLoadingState.chromeOnly:
      case WebAppLoadingState.loading:
        return Container(
          color: bg,
          child: Center(
            child: FadeTransition(
              opacity: _progressFade,
              child: _InfiniteRadialSpinner(
                animation: _spinnerAnim,
                size: _kProgressSize,
                strokeWidth: _kProgressStroke,
                color: (isDark ? Colors.white : palette.windowFg)
                    .withValues(alpha: _kProgressOpacity),
              ),
            ),
          ),
        );
      case WebAppLoadingState.ready:
        return Container(
          color: bg,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.language,
                  size: 64,
                  color: palette.windowFg.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Web App opened externally',
                  style: TextStyle(
                    fontSize: 14,
                    color: palette.windowFg.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.data.url.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      _launchUrl(widget.data.url);
                    },
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('Open in Browser'),
                  ),
              ],
            ),
          ),
        );
      case WebAppLoadingState.error:
        return Container(
          color: bg,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: palette.windowFg.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load Web App',
                  style: TextStyle(
                    fontSize: 14,
                    color: palette.windowFg.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  void _launchUrl(String url) {
    try {
      final uri = url.startsWith('http') ? url : 'https://$url';
      Process.run('xdg-open', [uri]);
    } catch (_) {}
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
            onPressed: () {},
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
            onPressed: () {},
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
                color: isDark
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.black.withValues(alpha: 0.4),
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

  const _WebAppButton({
    required this.text,
    required this.textColor,
    required this.bgColor,
    required this.active,
    required this.showProgress,
    required this.rippleColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kMainButtonHeight,
      width: double.infinity,
      child: Material(
        color: active ? bgColor : bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          splashColor: rippleColor.withValues(alpha: 0.3),
          onTap: active ? onPressed : null,
          child: Center(
            child: showProgress
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(textColor),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: _kButtonTextTop - 8),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: active ? textColor : textColor.withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
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
      progress != oldDelegate.progress;
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
                    onChanged: (v) => setDialogState(() => accepted = v ?? false),
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
