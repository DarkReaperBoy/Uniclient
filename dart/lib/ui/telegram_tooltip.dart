import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/telegram_palette.dart';

const double _kMaxWidth = 800.0;
const int _kMaxLines = 12;
const double _kCornerRadius = 6.0;
const Duration _kShowDelay = Duration(milliseconds: 1000);
const Duration _kHideDelay = Duration(milliseconds: 10);
const EdgeInsets _kPadding = EdgeInsets.fromLTRB(5, 2, 5, 2);
const Offset _kShift = Offset(-20, 20);
const double _kEdgeSkip = 10.0;

class TelegramTooltip extends StatefulWidget {
  final Widget child;
  final String message;
  final Duration showDelay;

  const TelegramTooltip({
    super.key,
    required this.child,
    required this.message,
    this.showDelay = _kShowDelay,
  });

  @override
  State<TelegramTooltip> createState() => _TelegramTooltipState();
}

class _TelegramTooltipState extends State<TelegramTooltip> {
  Timer? _showTimer;
  Timer? _hideTimer;
  OverlayEntry? _entry;
  Offset _lastPointer = Offset.zero;

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _removeEntry();
    super.dispose();
  }

  @override
  void deactivate() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _removeEntry();
    super.deactivate();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _onEnter(PointerEvent event) {
    _hideTimer?.cancel();
    _hideTimer = null;
    _lastPointer = event.position;
    if (_entry != null) return;
    _showTimer?.cancel();
    _showTimer = Timer(widget.showDelay, _show);
  }

  void _onHover(PointerEvent event) {
    _lastPointer = event.position;
    _entry?.markNeedsBuild();
  }

  void _onExit(PointerEvent _) {
    _showTimer?.cancel();
    _showTimer = null;
    if (_entry != null) {
      _hideTimer?.cancel();
      _hideTimer = Timer(_kHideDelay, _removeEntry);
    }
  }

  void _show() {
    if (!mounted || _entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (_) => _TooltipOverlay(
        message: widget.message,
        pointer: _lastPointer,
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onHover: _onHover,
      onExit: _onExit,
      child: widget.child,
    );
  }
}

class _TooltipOverlay extends StatelessWidget {
  final String message;
  final Offset pointer;

  const _TooltipOverlay({required this.message, required this.pointer});

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final screen = MediaQuery.of(context).size;

    return CustomSingleChildLayout(
      delegate: _TooltipPositionDelegate(
        pointer: pointer,
        shift: _kShift,
        edgeSkip: _kEdgeSkip,
        screenSize: screen,
      ),
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: _kMaxWidth),
          padding: _kPadding,
          decoration: BoxDecoration(
            color: palette.tooltipBg,
            borderRadius: BorderRadius.circular(_kCornerRadius),
            border: Border.all(color: palette.tooltipBorderFg, width: 1),
          ),
          child: Text(
            message,
            maxLines: _kMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: palette.tooltipFg,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _TooltipPositionDelegate extends SingleChildLayoutDelegate {
  final Offset pointer;
  final Offset shift;
  final double edgeSkip;
  final Size screenSize;

  _TooltipPositionDelegate({
    required this.pointer,
    required this.shift,
    required this.edgeSkip,
    required this.screenSize,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.min(_kMaxWidth, screenSize.width - edgeSkip * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = pointer.dx + shift.dx;
    double y = pointer.dy + shift.dy;

    if (x + childSize.width > screenSize.width - edgeSkip) {
      x = screenSize.width - edgeSkip - childSize.width;
    }
    if (x < edgeSkip) x = edgeSkip;

    if (y + childSize.height > screenSize.height - edgeSkip) {
      y = pointer.dy - childSize.height - 4;
    }
    if (y < edgeSkip) y = edgeSkip;

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_TooltipPositionDelegate oldDelegate) =>
      pointer != oldDelegate.pointer;
}

// ── Important Tooltip ──

enum TooltipSide { top, bottom, left, right }

const double _kArrowHalfWidth = 4.0;
const double _kArrowHeight = 4.0;
const double _kImportantRadius = 4.0;
const double _kImportantShift = 12.0;
const double _kArrowSkipMin = 24.0;
const double _kArrowSkip = 66.0;
const EdgeInsets _kImportantPadding = EdgeInsets.fromLTRB(10, 3, 10, 5);
const EdgeInsets _kImportantMargin = EdgeInsets.all(4);
const Duration _kImportantDuration = Duration(milliseconds: 200);

class ImportantTooltip extends StatefulWidget {
  final Widget child;
  final Rect targetRect;
  final TooltipSide preferredSide;
  final bool visible;
  final VoidCallback? onDismiss;

  const ImportantTooltip({
    super.key,
    required this.child,
    required this.targetRect,
    this.preferredSide = TooltipSide.bottom,
    this.visible = true,
    this.onDismiss,
  });

  @override
  State<ImportantTooltip> createState() => _ImportantTooltipState();
}

class _ImportantTooltipState extends State<ImportantTooltip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: _kImportantDuration,
    );
    if (widget.visible) _anim.forward();
  }

  @override
  void didUpdateWidget(ImportantTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _anim.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _anim.reverse().then((_) {
        widget.onDismiss?.call();
      });
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final screen = MediaQuery.of(context).size;

    final side = _resolveSide(widget.targetRect, screen);
    final arrowPos = _arrowPosition(widget.targetRect, side);

    return FadeTransition(
      opacity: _anim,
      child: CustomSingleChildLayout(
        delegate: _ImportantTooltipDelegate(
          targetRect: widget.targetRect,
          side: side,
          shift: _kImportantShift,
          screenSize: screen,
        ),
        child: CustomPaint(
          foregroundPainter: _ArrowPainter(
            color: palette.importantTooltipBg,
            side: side,
            arrowPosition: arrowPos,
          ),
          child: Container(
            margin: _arrowMargin(side),
            padding: _kImportantPadding,
            decoration: BoxDecoration(
              color: palette.importantTooltipBg,
              borderRadius: BorderRadius.circular(_kImportantRadius),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  TooltipSide _resolveSide(Rect target, Size screen) {
    final side = widget.preferredSide;
    switch (side) {
      case TooltipSide.bottom:
        if (target.bottom + _kImportantShift + 40 < screen.height) return side;
        return TooltipSide.top;
      case TooltipSide.top:
        if (target.top - _kImportantShift - 40 > 0) return side;
        return TooltipSide.bottom;
      case TooltipSide.right:
        if (target.right + _kImportantShift + 100 < screen.width) return side;
        return TooltipSide.left;
      case TooltipSide.left:
        if (target.left - _kImportantShift - 100 > 0) return side;
        return TooltipSide.right;
    }
  }

  double _arrowPosition(Rect target, TooltipSide side) {
    switch (side) {
      case TooltipSide.top:
      case TooltipSide.bottom:
        return target.center.dx;
      case TooltipSide.left:
      case TooltipSide.right:
        return target.center.dy;
    }
  }

  EdgeInsets _arrowMargin(TooltipSide side) {
    switch (side) {
      case TooltipSide.top:
        return const EdgeInsets.only(bottom: _kArrowHeight);
      case TooltipSide.bottom:
        return const EdgeInsets.only(top: _kArrowHeight);
      case TooltipSide.left:
        return const EdgeInsets.only(right: _kArrowHeight);
      case TooltipSide.right:
        return const EdgeInsets.only(left: _kArrowHeight);
    }
  }
}

class _ImportantTooltipDelegate extends SingleChildLayoutDelegate {
  final Rect targetRect;
  final TooltipSide side;
  final double shift;
  final Size screenSize;

  _ImportantTooltipDelegate({
    required this.targetRect,
    required this.side,
    required this.shift,
    required this.screenSize,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: screenSize.width - _kImportantMargin.horizontal * 2,
      maxHeight: screenSize.height - _kImportantMargin.vertical * 2,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x, y;
    switch (side) {
      case TooltipSide.bottom:
        x = targetRect.center.dx - childSize.width / 2;
        y = targetRect.bottom + shift;
      case TooltipSide.top:
        x = targetRect.center.dx - childSize.width / 2;
        y = targetRect.top - shift - childSize.height;
      case TooltipSide.right:
        x = targetRect.right + shift;
        y = targetRect.center.dy - childSize.height / 2;
      case TooltipSide.left:
        x = targetRect.left - shift - childSize.width;
        y = targetRect.center.dy - childSize.height / 2;
    }

    x = x.clamp(_kImportantMargin.left, screenSize.width - childSize.width - _kImportantMargin.right);
    y = y.clamp(_kImportantMargin.top, screenSize.height - childSize.height - _kImportantMargin.bottom);

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_ImportantTooltipDelegate oldDelegate) =>
      targetRect != oldDelegate.targetRect || side != oldDelegate.side;
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  final TooltipSide side;
  final double arrowPosition;

  _ArrowPainter({
    required this.color,
    required this.side,
    required this.arrowPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();

    switch (side) {
      case TooltipSide.bottom:
        final cx = (arrowPosition - 0).clamp(
          _kArrowSkipMin,
          size.width - _kArrowSkipMin,
        );
        final tipX = math.min(cx, _kArrowSkip);
        path.moveTo(tipX - _kArrowHalfWidth, _kArrowHeight);
        path.lineTo(tipX, 0);
        path.lineTo(tipX + _kArrowHalfWidth, _kArrowHeight);
        path.close();
      case TooltipSide.top:
        final cx = (arrowPosition - 0).clamp(
          _kArrowSkipMin,
          size.width - _kArrowSkipMin,
        );
        final tipX = math.min(cx, _kArrowSkip);
        final bottom = size.height;
        path.moveTo(tipX - _kArrowHalfWidth, bottom - _kArrowHeight);
        path.lineTo(tipX, bottom);
        path.lineTo(tipX + _kArrowHalfWidth, bottom - _kArrowHeight);
        path.close();
      case TooltipSide.right:
        final cy = (arrowPosition - 0).clamp(
          _kArrowSkipMin,
          size.height - _kArrowSkipMin,
        );
        final tipY = math.min(cy, _kArrowSkip);
        path.moveTo(_kArrowHeight, tipY - _kArrowHalfWidth);
        path.lineTo(0, tipY);
        path.lineTo(_kArrowHeight, tipY + _kArrowHalfWidth);
        path.close();
      case TooltipSide.left:
        final cy = (arrowPosition - 0).clamp(
          _kArrowSkipMin,
          size.height - _kArrowSkipMin,
        );
        final tipY = math.min(cy, _kArrowSkip);
        final right = size.width;
        path.moveTo(right - _kArrowHeight, tipY - _kArrowHalfWidth);
        path.lineTo(right, tipY);
        path.lineTo(right - _kArrowHeight, tipY + _kArrowHalfWidth);
        path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) =>
      color != oldDelegate.color ||
      side != oldDelegate.side ||
      arrowPosition != oldDelegate.arrowPosition;
}

void showImportantTooltip({
  required BuildContext context,
  required Rect targetRect,
  required String message,
  TooltipSide preferredSide = TooltipSide.bottom,
  Duration? hideAfter,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;

  void remove() {
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final palette = PaletteProvider.of(ctx);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: remove,
            ),
          ),
          ImportantTooltip(
            targetRect: targetRect,
            preferredSide: preferredSide,
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white,
                height: 1.3,
              ),
            ),
          ),
        ],
      );
    },
  );

  overlay.insert(entry);

  if (hideAfter != null) {
    Future.delayed(hideAfter, () {
      if (entry.mounted) remove();
    });
  }
}
