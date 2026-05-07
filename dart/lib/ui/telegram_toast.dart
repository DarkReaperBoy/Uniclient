import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

enum ToastAttach { none, left, top, right, bottom }

void showTelegramToast(
  BuildContext context,
  String text, {
  Duration duration = const Duration(milliseconds: 1500),
  bool multiline = false,
  ToastAttach attach = ToastAttach.none,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TelegramToast(
      text: text,
      duration: duration,
      multiline: multiline,
      attach: attach,
      onDone: () {
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

const _kFadeInMs = 200;
const _kFadeOutMs = 1000;
const _kSlideMs = 160;
const _kToastBg = Color(0xB2000000);
const _kToastFg = Color(0xFFFFFFFF);
const _kRadius = 6.0;
const _kMaxWidth = 480.0;
const _kMultilineMinWidth = 160.0;
const _kMultilineMaxWidth = 360.0;
const _kMargin = 13.0;
const _kPadding = EdgeInsets.fromLTRB(19, 13, 19, 12);

class _TelegramToast extends StatefulWidget {
  final String text;
  final Duration duration;
  final bool multiline;
  final ToastAttach attach;
  final VoidCallback onDone;

  const _TelegramToast({
    required this.text,
    required this.duration,
    required this.multiline,
    required this.attach,
    required this.onDone,
  });

  @override
  State<_TelegramToast> createState() => _TelegramToastState();
}

class _TelegramToastState extends State<_TelegramToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _fadeOut;
  late final Animation<Offset> _slideIn;
  late final Animation<Offset> _slideOut;
  Timer? _holdTimer;
  bool _hiding = false;

  bool get _isSlide => widget.attach != ToastAttach.none;

  Offset _slideBegin() {
    switch (widget.attach) {
      case ToastAttach.left:
        return const Offset(-1, 0);
      case ToastAttach.right:
        return const Offset(1, 0);
      case ToastAttach.top:
        return const Offset(0, -1);
      case ToastAttach.bottom:
        return const Offset(0, 1);
      case ToastAttach.none:
        return Offset.zero;
    }
  }

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
          milliseconds: _isSlide ? _kSlideMs : _kFadeInMs),
      reverseDuration: Duration(
          milliseconds: _isSlide ? _kSlideMs : _kFadeOutMs),
    );

    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _fadeOut = CurvedAnimation(
        parent: ReverseAnimation(_ctrl), curve: Curves.easeIn);

    final begin = _slideBegin();
    _slideIn = Tween<Offset>(begin: begin, end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slideOut = Tween<Offset>(begin: Offset.zero, end: begin)
        .animate(CurvedAnimation(
            parent: ReverseAnimation(_ctrl), curve: Curves.easeIn));

    _ctrl.forward().then((_) {
      if (!mounted) return;
      _holdTimer = Timer(widget.duration, _startHide);
    });
  }

  void _startHide() {
    if (!mounted || _hiding) return;
    _hiding = true;
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minW = widget.multiline ? _kMultilineMinWidth : 0.0;
    final maxW = widget.multiline ? _kMultilineMaxWidth : _kMaxWidth;

    final toastChild = Container(
      constraints: BoxConstraints(minWidth: minW, maxWidth: maxW),
      padding: _kPadding,
      decoration: BoxDecoration(
        color: _kToastBg,
        borderRadius: BorderRadius.circular(_kRadius),
      ),
      child: Text(
        widget.text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _kToastFg,
          fontSize: 13,
          fontWeight: FontWeight.normal,
          decoration: TextDecoration.none,
          height: 1.3,
        ),
      ),
    );

    Widget animated;
    if (_isSlide) {
      animated = AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final slide = _hiding ? _slideOut.value : _slideIn.value;
          final opacity = _hiding
              ? _fadeOut.value.clamp(0.0, 1.0)
              : _fadeIn.value.clamp(0.0, 1.0);
          return FractionalTranslation(
            translation: slide,
            child: Opacity(opacity: opacity, child: child),
          );
        },
        child: toastChild,
      );
    } else {
      animated = FadeTransition(
        opacity: _hiding
            ? Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
                parent: ReverseAnimation(_ctrl), curve: Curves.easeIn))
            : _fadeIn,
        child: toastChild,
      );
    }

    final align = _positionForAttach(widget.attach);

    return Positioned(
      left: align.left,
      right: align.right,
      top: align.top,
      bottom: align.bottom,
      child: IgnorePointer(
        child: align.center
            ? Center(child: animated)
            : Align(alignment: align.alignment, child: animated),
      ),
    );
  }
}

class _ToastPosition {
  final double? left, right, top, bottom;
  final bool center;
  final Alignment alignment;
  const _ToastPosition({
    this.left,
    this.right,
    this.top,
    this.bottom,
    this.center = true,
    this.alignment = Alignment.center,
  });
}

_ToastPosition _positionForAttach(ToastAttach attach) {
  switch (attach) {
    case ToastAttach.none:
      return const _ToastPosition(left: 0, right: 0, bottom: _kMargin * 4);
    case ToastAttach.bottom:
      return const _ToastPosition(
          left: _kMargin, right: _kMargin, bottom: _kMargin);
    case ToastAttach.top:
      return const _ToastPosition(
          left: _kMargin, right: _kMargin, top: _kMargin);
    case ToastAttach.left:
      return const _ToastPosition(
        left: _kMargin,
        top: 0,
        bottom: 0,
        center: false,
        alignment: Alignment.centerLeft,
      );
    case ToastAttach.right:
      return const _ToastPosition(
        right: _kMargin,
        top: 0,
        bottom: 0,
        center: false,
        alignment: Alignment.centerRight,
      );
  }
}

// ─── Sticker / Emoji Pack Toast — spec §36.15 ──────────────────────────────

void showStickerToast(
  BuildContext context, {
  required String packName,
  int packCount = 0,
  bool isReaction = false,
  VoidCallback? onOpenPack,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _StickerToast(
      packName: packName,
      packCount: packCount,
      isReaction: isReaction,
      onOpenPack: onOpenPack,
      onDone: () {
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _StickerToast extends StatefulWidget {
  final String packName;
  final int packCount;
  final bool isReaction;
  final VoidCallback? onOpenPack;
  final VoidCallback onDone;

  const _StickerToast({
    required this.packName,
    required this.packCount,
    required this.isReaction,
    this.onOpenPack,
    required this.onDone,
  });

  @override
  State<_StickerToast> createState() => _StickerToastState();
}

class _StickerToastState extends State<_StickerToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _holdTimer;
  bool _hiding = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kFadeInMs),
      reverseDuration: const Duration(milliseconds: _kFadeOutMs),
    );
    _ctrl.forward().then((_) {
      if (!mounted) return;
      _holdTimer = Timer(const Duration(milliseconds: 1500), _startHide);
    });
  }

  void _startHide() {
    if (!mounted || _hiding) return;
    _hiding = true;
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  TextSpan _buildMessage() {
    const normal = TextStyle(
      color: _kToastFg,
      fontSize: 13,
      fontWeight: FontWeight.normal,
      decoration: TextDecoration.none,
      height: 1.3,
    );
    final link = normal.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    if (widget.isReaction) {
      return TextSpan(
        style: normal,
        children: [
          const TextSpan(text: 'This reaction is from the '),
          TextSpan(
            text: widget.packName,
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = widget.onOpenPack,
          ),
          const TextSpan(text: ' pack.'),
        ],
      );
    }

    if (widget.packCount > 1) {
      return TextSpan(
        style: normal,
        children: [
          const TextSpan(text: 'This message contains emoji from '),
          TextSpan(
            text: '${widget.packCount} packs',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = widget.onOpenPack,
          ),
          const TextSpan(text: '.'),
        ],
      );
    }

    return TextSpan(
      style: normal,
      children: [
        const TextSpan(text: 'This message contains emoji from '),
        TextSpan(
          text: '${widget.packName} pack',
          style: link,
          recognizer: TapGestureRecognizer()
            ..onTap = widget.onOpenPack,
        ),
        const TextSpan(text: '.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final toastChild = Container(
      constraints: const BoxConstraints(maxWidth: _kMaxWidth),
      padding: _kPadding,
      decoration: BoxDecoration(
        color: _kToastBg,
        borderRadius: BorderRadius.circular(_kRadius),
      ),
      child: Text.rich(
        _buildMessage(),
        textAlign: TextAlign.center,
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: _kMargin * 4,
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: FadeTransition(
            opacity: _hiding
                ? Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
                    parent: ReverseAnimation(_ctrl), curve: Curves.easeIn))
                : CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
            child: toastChild,
          ),
        ),
      ),
    );
  }
}
