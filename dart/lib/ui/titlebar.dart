import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/telegram_palette.dart';

class _ButtonLayout {
  final List<_ButtonType> left;
  final List<_ButtonType> right;

  const _ButtonLayout({this.left = const [], this.right = const []});

  static const fallback = _ButtonLayout(
    right: [_ButtonType.minimize, _ButtonType.maximize, _ButtonType.close],
  );

  factory _ButtonLayout.parse(String layout) {
    final parts = layout.split(':');
    final leftStr = parts.isNotEmpty ? parts[0] : '';
    final rightStr = parts.length > 1 ? parts[1] : '';
    return _ButtonLayout(
      left: _parseButtons(leftStr),
      right: _parseButtons(rightStr),
    );
  }

  _ButtonLayout get consolidated {
    if (left.isEmpty || right.isEmpty) return this;
    if (left.contains(_ButtonType.close)) {
      return _ButtonLayout(left: [...left, ...right], right: const []);
    } else if (right.contains(_ButtonType.close)) {
      return _ButtonLayout(left: const [], right: [...left, ...right]);
    } else if (left.length > right.length) {
      return _ButtonLayout(left: [...left, ...right], right: const []);
    }
    return _ButtonLayout(left: const [], right: [...left, ...right]);
  }

  static List<_ButtonType> _parseButtons(String side) {
    if (side.trim().isEmpty) return [];
    final result = <_ButtonType>[];
    for (final token in side.split(',')) {
      final t = token.trim().toLowerCase();
      switch (t) {
        case 'minimize':
          result.add(_ButtonType.minimize);
        case 'maximize':
          result.add(_ButtonType.maximize);
        case 'close':
          result.add(_ButtonType.close);
      }
    }
    return result;
  }
}

enum _ButtonType { minimize, maximize, close }

/// Custom client-side titlebar for Linux.
/// Matches AyuGram Desktop: height 24px, button width 36px.
class CustomTitlebar extends StatefulWidget {
  const CustomTitlebar({super.key});

  static const channel = MethodChannel('com.uniclient.app/window');
  static const double height = 24.0;
  static const double buttonWidth = 36.0;

  @override
  State<CustomTitlebar> createState() => _CustomTitlebarState();
}

class _CustomTitlebarState extends State<CustomTitlebar> {
  static final Set<_CustomTitlebarState> _instances = {};

  bool _isMaximized = false;
  bool _isActive = true;
  bool _oneSideControls = false;
  bool _resizeEnabled = true;
  bool _mousePressed = false;
  _ButtonLayout _layout = _ButtonLayout.fallback;

  @override
  void initState() {
    super.initState();
    _instances.add(this);
    if (_instances.length == 1) {
      CustomTitlebar.channel.setMethodCallHandler(_onNativeCallStatic);
    }
    _queryMaximized();
    _queryButtonLayout();
    _queryOneSideControls();
    _queryResizeEnabled();
  }

  @override
  void dispose() {
    _instances.remove(this);
    if (_instances.isEmpty) {
      CustomTitlebar.channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  static Future<dynamic> _onNativeCallStatic(MethodCall call) async {
    for (final instance in List.of(_instances)) {
      instance._handleNativeCall(call);
    }
  }

  void _handleNativeCall(MethodCall call) {
    switch (call.method) {
      case 'maximizeChanged':
        if (mounted) setState(() => _isMaximized = call.arguments as bool);
      case 'buttonLayoutChanged':
        if (mounted) {
          setState(
              () => _layout = _ButtonLayout.parse(call.arguments as String));
        }
      case 'windowFocusChanged':
        if (mounted) setState(() => _isActive = call.arguments as bool);
      case 'oneSideControlsChanged':
        if (mounted) {
          setState(() => _oneSideControls = call.arguments as bool);
        }
      case 'resizeEnabledChanged':
        if (mounted) {
          setState(() => _resizeEnabled = call.arguments as bool);
        }
    }
  }

  Future<void> _queryMaximized() async {
    try {
      final result =
          await CustomTitlebar.channel.invokeMethod<bool>('isMaximized');
      if (mounted) setState(() => _isMaximized = result ?? false);
    } catch (_) {}
  }

  Future<void> _queryButtonLayout() async {
    try {
      final result =
          await CustomTitlebar.channel.invokeMethod<String>('getButtonLayout');
      if (result != null && mounted) {
        setState(() => _layout = _ButtonLayout.parse(result));
      }
    } catch (_) {}
  }

  Future<void> _queryOneSideControls() async {
    try {
      final result =
          await CustomTitlebar.channel.invokeMethod<bool>('getOneSideControls');
      if (mounted) setState(() => _oneSideControls = result ?? false);
    } catch (_) {}
  }

  Future<void> _queryResizeEnabled() async {
    try {
      final result =
          await CustomTitlebar.channel.invokeMethod<bool>('getResizeEnabled');
      if (mounted) setState(() => _resizeEnabled = result ?? true);
    } catch (_) {}
  }

  Future<void> _minimize() async {
    try {
      await CustomTitlebar.channel.invokeMethod('minimize');
    } catch (_) {}
  }

  Future<void> _toggleMaximize() async {
    try {
      await CustomTitlebar.channel.invokeMethod('maximize');
    } catch (_) {}
  }

  Future<void> _close() async {
    try {
      await CustomTitlebar.channel.invokeMethod('close');
    } catch (_) {}
  }

  Future<void> _startDrag() async {
    try {
      await CustomTitlebar.channel.invokeMethod('startDrag');
    } catch (_) {}
  }

  Future<void> _showWindowMenu() async {
    try {
      await CustomTitlebar.channel.invokeMethod('showWindowMenu');
    } catch (_) {}
  }

  Widget _buildButton(_ButtonType type, TelegramPalette palette) {
    if (type == _ButtonType.maximize && !_resizeEnabled) {
      return const SizedBox.shrink();
    }
    final isClose = type == _ButtonType.close;

    final Color bg, bgOver, fg, fgOver;
    if (isClose) {
      bg = _isActive
          ? palette.titleButtonCloseBgActive
          : palette.titleButtonCloseBg;
      bgOver = _isActive
          ? palette.titleButtonCloseBgActiveOver
          : palette.titleButtonCloseBgOver;
      fg = _isActive
          ? palette.titleButtonCloseFgActive
          : palette.titleButtonCloseFg;
      fgOver = _isActive
          ? palette.titleButtonCloseFgActiveOver
          : palette.titleButtonCloseFgOver;
    } else {
      bg = _isActive ? palette.titleButtonBgActive : palette.titleButtonBg;
      bgOver = _isActive
          ? palette.titleButtonBgActiveOver
          : palette.titleButtonBgOver;
      fg = _isActive ? palette.titleButtonFgActive : palette.titleButtonFg;
      fgOver = _isActive
          ? palette.titleButtonFgActiveOver
          : palette.titleButtonFgOver;
    }

    return _WinButton(
      type: type,
      isMaximized: type == _ButtonType.maximize && _isMaximized,
      onTap: switch (type) {
        _ButtonType.minimize => _minimize,
        _ButtonType.maximize => _toggleMaximize,
        _ButtonType.close => _close,
      },
      bgColor: bg,
      bgOverColor: bgOver,
      fgColor: fg,
      fgOverColor: fgOver,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isLinux) return const SizedBox.shrink();

    final palette = context.palette;
    final bgColor = _isActive ? palette.titleBgActive : palette.titleBg;
    final sepColor = palette.titleShadow;

    final effectiveLayout =
        _oneSideControls ? _layout.consolidated : _layout;
    final leftButtons =
        effectiveLayout.left.map((t) => _buildButton(t, palette)).toList();
    final rightButtons =
        effectiveLayout.right.map((t) => _buildButton(t, palette)).toList();

    return Container(
      height: CustomTitlebar.height,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: sepColor, width: 1)),
      ),
      child: Row(
        children: [
          ...leftButtons,
          Expanded(
            child: Listener(
              onPointerDown: (e) {
                if (e.buttons & 0x02 != 0) {
                  _showWindowMenu();
                } else if (e.buttons & 0x01 != 0) {
                  _mousePressed = true;
                }
              },
              onPointerUp: (_) => _mousePressed = false,
              onPointerMove: (_) {
                if (_mousePressed) {
                  _mousePressed = false;
                  _startDrag();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: GestureDetector(
                onDoubleTap: _toggleMaximize,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          ...rightButtons,
        ],
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  final _ButtonType type;
  final bool isMaximized;
  final VoidCallback onTap;
  final Color bgColor;
  final Color bgOverColor;
  final Color fgColor;
  final Color fgOverColor;

  const _WinButton({
    required this.type,
    required this.isMaximized,
    required this.onTap,
    required this.bgColor,
    required this.bgOverColor,
    required this.fgColor,
    required this.fgOverColor,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _TitleButtonPainter extends CustomPainter {
  final _ButtonType type;
  final bool isMaximized;
  final Color color;

  _TitleButtonPainter({
    required this.type,
    required this.isMaximized,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    switch (type) {
      case _ButtonType.minimize:
        final y = size.height / 2;
        canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), paint);
      case _ButtonType.maximize:
        if (isMaximized) {
          canvas.drawRect(const Rect.fromLTWH(0, 2, 7, 7), paint);
          final path = Path()
            ..moveTo(2, 2)
            ..lineTo(2, 0)
            ..lineTo(9, 0)
            ..lineTo(9, 7)
            ..lineTo(7, 7);
          canvas.drawPath(path, paint);
        } else {
          canvas.drawRect(
            Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
            paint,
          );
        }
      case _ButtonType.close:
        canvas.drawLine(
          const Offset(1, 1),
          Offset(size.width - 1, size.height - 1),
          paint,
        );
        canvas.drawLine(
          Offset(size.width - 1, 1),
          Offset(1, size.height - 1),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_TitleButtonPainter old) =>
      type != old.type || isMaximized != old.isMaximized || color != old.color;
}

class _WinButtonState extends State<_WinButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          widget.onTap();
          setState(() => _hovered = false);
        },
        child: Container(
          width: CustomTitlebar.buttonWidth,
          height: CustomTitlebar.height,
          color: _hovered ? widget.bgOverColor : widget.bgColor,
          alignment: Alignment.center,
          child: CustomPaint(
            size: const Size(10, 10),
            painter: _TitleButtonPainter(
              type: widget.type,
              isMaximized: widget.isMaximized,
              color: _hovered ? widget.fgOverColor : widget.fgColor,
            ),
          ),
        ),
      ),
    );
  }
}

