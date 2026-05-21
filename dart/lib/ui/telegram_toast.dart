import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

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

void showRichTelegramToast(
  BuildContext context,
  TextSpan textSpan, {
  Duration duration = const Duration(milliseconds: 3000),
  ToastAttach attach = ToastAttach.none,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TelegramToast(
      text: '',
      textSpan: textSpan,
      duration: duration,
      multiline: false,
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
  final TextSpan? textSpan;
  final Duration duration;
  final bool multiline;
  final ToastAttach attach;
  final VoidCallback onDone;

  const _TelegramToast({
    required this.text,
    this.textSpan,
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
      child: widget.textSpan != null
          ? Text.rich(widget.textSpan!, textAlign: TextAlign.center)
          : Text(
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
    final content = align.center
        ? Center(child: animated)
        : Align(alignment: align.alignment, child: animated);

    return Positioned(
      left: align.left,
      right: align.right,
      top: align.top,
      bottom: align.bottom,
      child: widget.textSpan != null ? content : IgnorePointer(child: content),
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

enum StickerToastSection { message, topicIcon }

OverlayEntry? _activeStickerEntry;
int _stickerToastCounter = 0;

void showStickerToast(
  BuildContext context, {
  required String packName,
  int packCount = 0,
  bool isReaction = false,
  bool isEmoji = true,
  StickerToastSection section = StickerToastSection.message,
  String stickerEmoji = '',
  String stickerThumbB64 = '',
  Uint8List? stickerLottieData,
  VoidCallback? onOpenPack,
  VoidCallback? onOpenSavedMessages,
  VoidCallback? onShowPremium,
}) {
  if (_activeStickerEntry != null) {
    final oldEntry = _activeStickerEntry;
    _activeStickerEntry = null;
    Future.delayed(const Duration(milliseconds: _kFadeOutMs), () {
      oldEntry?.remove();
    });
  }

  final effectiveIsEmoji =
      section == StickerToastSection.topicIcon || isEmoji;
  final toSaved = effectiveIsEmoji &&
      section == StickerToastSection.message &&
      (++_stickerToastCounter % 2 == 0);

  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _StickerToast(
      packName: packName,
      packCount: packCount,
      isReaction: isReaction,
      isEmoji: effectiveIsEmoji,
      toSaved: toSaved,
      section: section,
      stickerEmoji: stickerEmoji,
      stickerThumbB64: stickerThumbB64,
      stickerLottieData: stickerLottieData,
      onOpenPack: onOpenPack,
      onOpenSavedMessages: onOpenSavedMessages,
      onShowPremium: onShowPremium,
      onDone: () {
        entry.remove();
        if (_activeStickerEntry == entry) _activeStickerEntry = null;
      },
    ),
  );
  _activeStickerEntry = entry;
  overlay.insert(entry);
}

class _StickerToast extends StatefulWidget {
  final String packName;
  final int packCount;
  final bool isReaction;
  final bool isEmoji;
  final bool toSaved;
  final StickerToastSection section;
  final String stickerEmoji;
  final String stickerThumbB64;
  final Uint8List? stickerLottieData;
  final VoidCallback? onOpenPack;
  final VoidCallback? onOpenSavedMessages;
  final VoidCallback? onShowPremium;
  final VoidCallback onDone;

  const _StickerToast({
    required this.packName,
    required this.packCount,
    required this.isReaction,
    required this.isEmoji,
    required this.toSaved,
    required this.section,
    this.stickerEmoji = '',
    this.stickerThumbB64 = '',
    this.stickerLottieData,
    this.onOpenPack,
    this.onOpenSavedMessages,
    this.onShowPremium,
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

    if (widget.toSaved) {
      return [
        TextSpan(text: widget.packName, style: bold),
        const TextSpan(text: '\n', style: normal),
        const TextSpan(
            text: 'Try sending these emoji in Saved Messages for free to test.', style: normal),
      ];
    }

    if (widget.section == StickerToastSection.topicIcon) {
      return [
        TextSpan(text: widget.packName, style: bold),
        const TextSpan(text: '\n', style: normal),
        const TextSpan(
            text: 'This icon is from the ', style: normal),
        TextSpan(
          text: '${widget.packName} pack',
          style: link,
          recognizer: TapGestureRecognizer()..onTap = widget.onOpenPack,
        ),
        const TextSpan(text: '.', style: normal),
      ];
    }

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

    if (!widget.isEmoji) {
      return [
        TextSpan(text: widget.packName, style: bold),
        const TextSpan(text: '\n', style: normal),
        const TextSpan(
            text: 'This set contains premium stickers like this one.', style: normal),
      ];
    }

    if (widget.packCount > 1) {
      return [
        TextSpan(text: 'Animated Emoji', style: bold),
        const TextSpan(text: '\n', style: normal),
        const TextSpan(
            text: 'Subscribe to Telegram Premium to unlock this emoji.', style: normal),
      ];
    }

    return [
      TextSpan(text: 'Animated Emoji', style: bold),
      const TextSpan(text: '\n', style: normal),
      const TextSpan(
          text: 'Subscribe to Telegram Premium to unlock this emoji.', style: normal),
    ];
  }

  Widget _buildPreview() {
    const previewSize = 36.0;

    if (widget.stickerLottieData != null) {
      return SizedBox(
        width: previewSize,
        height: previewSize,
        child: Lottie.memory(
          widget.stickerLottieData!,
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (_, __, ___) => _buildEmojiText(previewSize),
        ),
      );
    }

    if (widget.stickerThumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(widget.stickerThumbB64);
        return Image.memory(
          Uint8List.fromList(bytes),
          width: previewSize,
          height: previewSize,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildEmojiText(previewSize),
        );
      } catch (_) {
        return _buildEmojiText(previewSize);
      }
    }
    return _buildEmojiText(previewSize);
  }

  Widget _buildEmojiText(double size) {
    final emoji = widget.stickerEmoji.isNotEmpty
        ? widget.stickerEmoji
        : (widget.isReaction ? '✨' : '😀');
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          emoji,
          style: TextStyle(
              fontSize: size * 0.72, decoration: TextDecoration.none),
        ),
      ),
    );
  }

  VoidCallback? get _viewCallback {
    if (widget.toSaved) return widget.onOpenSavedMessages;
    if (widget.section == StickerToastSection.topicIcon) {
      return widget.onShowPremium;
    }
    return widget.onOpenPack;
  }

  String get _viewButtonText =>
      widget.toSaved ? 'Open' : 'View';

  @override
  Widget build(BuildContext context) {
    const stickerMaxWidth = 380.0;
    final viewCb = _viewCallback;

    final toastChild = Container(
      constraints: const BoxConstraints(maxWidth: stickerMaxWidth, minWidth: 160.0),
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
            child: _buildPreview(),
          ),
          Flexible(
            child: Text.rich(
              TextSpan(children: _buildMessage()),
              textAlign: TextAlign.left,
            ),
          ),
          if (viewCb != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                viewCb();
                _startHide();
              },
              child: Text(
                _viewButtonText,
                style: const TextStyle(
                  color: Color(0xFF4DB8FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: _kMargin + 56,
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
