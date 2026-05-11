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
const _kToastBg = Color(0xE52C3033);
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
          return FractionalTranslation(
            translation: slide,
            child: child,
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
      return const _ToastPosition(left: 0, right: 0, top: 0, bottom: 0);
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
  String stickerEmoji = '',
  VoidCallback? onOpenPack,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _StickerToast(
      packName: packName,
      packCount: packCount,
      isReaction: isReaction,
      stickerEmoji: stickerEmoji,
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
  final String stickerEmoji;
  final VoidCallback? onOpenPack;
  final VoidCallback onDone;

  const _StickerToast({
    required this.packName,
    required this.packCount,
    required this.isReaction,
    this.stickerEmoji = '',
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
      _holdTimer = Timer(const Duration(milliseconds: 3000), _startHide);
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

  List<InlineSpan> _buildMessage() {
    const normal = TextStyle(
      color: _kToastFg,
      fontSize: 13,
      fontWeight: FontWeight.normal,
      decoration: TextDecoration.none,
      height: 1.3,
    );
    final bold = normal.copyWith(fontWeight: FontWeight.w600);
    final link = normal.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    if (widget.isReaction) {
      return [
        TextSpan(text: widget.packName, style: bold),
        const TextSpan(text: '\n', style: normal),
        const TextSpan(text: 'This reaction is from the ', style: normal),
        TextSpan(
          text: widget.packName,
          style: link,
          recognizer: TapGestureRecognizer()..onTap = widget.onOpenPack,
        ),
        const TextSpan(text: ' pack.', style: normal),
      ];
    }

    if (widget.packCount > 1) {
      return [
        TextSpan(text: 'Animated Emoji', style: bold),
        const TextSpan(text: '\n', style: normal),
        const TextSpan(text: 'This message contains emoji from ', style: normal),
        TextSpan(
          text: '${widget.packCount} packs',
          style: link,
          recognizer: TapGestureRecognizer()..onTap = widget.onOpenPack,
        ),
        const TextSpan(text: '.', style: normal),
      ];
    }

    return [
      TextSpan(text: 'Animated Emoji', style: bold),
      const TextSpan(text: '\n', style: normal),
      const TextSpan(text: 'This message contains emoji from the ', style: normal),
      TextSpan(
        text: '${widget.packName} pack',
        style: link,
        recognizer: TapGestureRecognizer()..onTap = widget.onOpenPack,
      ),
      const TextSpan(text: '.', style: normal),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const stickerMaxWidth = 380.0;
    final toastChild = Container(
      constraints: const BoxConstraints(maxWidth: stickerMaxWidth),
      padding: _kPadding,
      decoration: BoxDecoration(
        color: _kToastBg,
        borderRadius: BorderRadius.circular(_kRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              widget.stickerEmoji.isNotEmpty
                  ? widget.stickerEmoji
                  : (widget.isReaction ? '✨' : '😀'),
              style: const TextStyle(fontSize: 26, decoration: TextDecoration.none),
            ),
          ),
          Flexible(
            child: Text.rich(
              TextSpan(children: _buildMessage()),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onSecondaryTap: _startHide,
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
