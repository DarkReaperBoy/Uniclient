import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/telegram_palette.dart';

/// Parsed window button layout from the desktop environment.
/// Format: "left_buttons:right_buttons" where each side has comma-separated
/// button names (minimize, maximize, close). Unknown tokens (appmenu, icon,
/// spacer, menu) are ignored.
class _ButtonLayout {
  final List<_ButtonType> left;
  final List<_ButtonType> right;

  const _ButtonLayout({this.left = const [], this.right = const []});

  /// Default fallback: right-side [Minimize, Maximize, Close] (Windows/KDE style).
  static const fallback = _ButtonLayout(
    right: [_ButtonType.minimize, _ButtonType.maximize, _ButtonType.close],
  );

  /// Parse a GTK decoration-layout string like "close,minimize,maximize:"
  /// or "appmenu:close" or ":minimize,maximize,close".
  factory _ButtonLayout.parse(String layout) {
    final parts = layout.split(':');
    final leftStr = parts.isNotEmpty ? parts[0] : '';
    final rightStr = parts.length > 1 ? parts[1] : '';
    return _ButtonLayout(
      left: _parseButtons(leftStr),
      right: _parseButtons(rightStr),
    );
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
        // appmenu, icon, spacer, menu → Unknown, render nothing (spec §1).
      }
    }
    return result;
  }
}

enum _ButtonType { minimize, maximize, close }

/// Custom client-side titlebar for Linux.
/// Spec §1: custom titlebar by default, with window control buttons.
/// Height: 28px. Buttons: 46x28px each. Button layout read from DE at runtime.
class CustomTitlebar extends StatefulWidget {
  const CustomTitlebar({super.key});

  static const channel = MethodChannel('com.uniclient.app/window');
  static const double height = 28.0;
  static const double buttonWidth = 46.0;

  @override
  State<CustomTitlebar> createState() => _CustomTitlebarState();
}

class _CustomTitlebarState extends State<CustomTitlebar> {
  bool _isMaximized = false;
  _ButtonLayout _layout = _ButtonLayout.fallback;

  @override
  void initState() {
    super.initState();
    _queryMaximized();
    _queryButtonLayout();
    CustomTitlebar.channel.setMethodCallHandler(_onNativeCall);
  }

  @override
  void dispose() {
    CustomTitlebar.channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'maximizeChanged') {
      if (mounted) setState(() => _isMaximized = call.arguments as bool);
    } else if (call.method == 'buttonLayoutChanged') {
      if (mounted) {
        setState(() => _layout = _ButtonLayout.parse(call.arguments as String));
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

  Future<void> _minimize() async {
    try {
      await CustomTitlebar.channel.invokeMethod('minimize');
    } catch (_) {}
  }

  Future<void> _toggleMaximize() async {
    try {
      await CustomTitlebar.channel.invokeMethod('maximize');
      await _queryMaximized();
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

  Widget _buildButton(_ButtonType type, Color iconColor, Color hoverBg) {
    switch (type) {
      case _ButtonType.minimize:
        return _WinButton(
          icon: Icons.remove,
          onTap: _minimize,
          hoverBg: hoverBg,
          iconColor: iconColor,
        );
      case _ButtonType.maximize:
        return _WinButton(
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          iconSize: _isMaximized ? 12 : 14,
          onTap: _toggleMaximize,
          hoverBg: hoverBg,
          iconColor: iconColor,
        );
      case _ButtonType.close:
        return _WinButton(
          icon: Icons.close,
          onTap: _close,
          hoverBg: const Color(0xFFE81123),
          hoverIconColor: Colors.white,
          iconColor: iconColor,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isLinux) return const SizedBox.shrink();

    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = palette.titleBg;
    final iconColor = palette.titleFg;
    final sepColor = palette.shadowFg;

    final hoverBg = palette.windowBgOver;
    final leftButtons = _layout.left
        .map((t) => _buildButton(t, iconColor, hoverBg))
        .toList();
    final rightButtons = _layout.right
        .map((t) => _buildButton(t, iconColor, hoverBg))
        .toList();

    return Container(
      height: CustomTitlebar.height,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: sepColor, width: 1)),
      ),
      child: Row(
        children: [
          ...leftButtons,
          // Draggable area fills remaining space.
          Expanded(
            child: GestureDetector(
              onPanStart: (_) => _startDrag(),
              onDoubleTap: _toggleMaximize,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          ...rightButtons,
        ],
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color hoverBg;
  final Color iconColor;
  final Color? hoverIconColor;

  const _WinButton({
    required this.icon,
    this.iconSize = 14,
    required this.onTap,
    required this.hoverBg,
    required this.iconColor,
    this.hoverIconColor,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: CustomTitlebar.buttonWidth,
          height: CustomTitlebar.height,
          color: _hovered ? widget.hoverBg : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hovered && widget.hoverIconColor != null
                ? widget.hoverIconColor
                : widget.iconColor,
          ),
        ),
      ),
    );
  }
}
