import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _kCountdownMs = 15999;
const _kUpdateIntervalMs = 100;
const _kWidth = 320.0;
const _kRadius = 12.0;

class ThemeConfirmOverlay extends StatefulWidget {
  final VoidCallback onKeep;
  final VoidCallback onRevert;

  const ThemeConfirmOverlay({
    super.key,
    required this.onKeep,
    required this.onRevert,
  });

  @override
  State<ThemeConfirmOverlay> createState() => _ThemeConfirmOverlayState();
}

class _ThemeConfirmOverlayState extends State<ThemeConfirmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  Timer? _countdownTimer;
  int _remainingMs = _kCountdownMs;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _countdownTimer = Timer.periodic(
      const Duration(milliseconds: _kUpdateIntervalMs),
      (_) {
        _remainingMs -= _kUpdateIntervalMs;
        if (_remainingMs <= 0) {
          _countdownTimer?.cancel();
          _revert();
          return;
        }
        setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _revert() {
    _countdownTimer?.cancel();
    widget.onRevert();
  }

  void _keep() {
    _countdownTimer?.cancel();
    widget.onKeep();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = ((_remainingMs + 999) / 1000).floor();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF8B9AAD) : const Color(0xFF999999);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _revert();
          }
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(_kRadius),
              color: bgColor,
              child: Container(
                width: _kWidth,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to keep this theme?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Theme will revert in $seconds seconds',
                      style: TextStyle(fontSize: 13, color: subtextColor),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: _keep,
                            style: TextButton.styleFrom(
                              backgroundColor:
                                  isDark
                                      ? const Color(0xFF3390EC)
                                      : const Color(0xFF40A7E3),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Keep Changes',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextButton(
                            onPressed: _revert,
                            style: TextButton.styleFrom(
                              foregroundColor: subtextColor,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: subtextColor.withValues(alpha: 0.3),
                                ),
                              ),
                            ),
                            child: const Text(
                              'Revert',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
