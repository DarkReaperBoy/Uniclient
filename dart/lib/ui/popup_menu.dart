import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double _kMenuMinWidth = 156.0;
const double _kMenuMaxWidth = 300.0;
const double _kCornerRadius = 8.0;
const double _kShadowBlurRadius = 5.0;
const Offset _kShadowOffset = Offset(0, 1);
const double _kShadowOpacity = 0.25;
const Duration _kOpenDuration = Duration(milliseconds: 200);
const Duration _kCloseDuration = Duration(milliseconds: 150);
const double _kScrollPaddingVertical = 8.0;

Color _menuBg(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF17212b) : const Color(0xFFffffff);

Color _shadowColor(Brightness b) =>
    b == Brightness.dark
        ? const Color(0xFF17212b)
        : const Color(0xFF000000);

Future<T?> showTelegramMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<TelegramMenuItem<T>> items,
  bool fullAttention = false,
}) {
  final brightness = Theme.of(context).brightness;
  final mediaQuery = MediaQuery.of(context);
  final screenSize = mediaQuery.size;
  final screenPadding = mediaQuery.padding;

  return Navigator.of(context).push<T>(
    _TelegramMenuRoute<T>(
      position: position,
      items: items,
      brightness: brightness,
      screenSize: screenSize,
      screenPadding: screenPadding,
      fullAttention: fullAttention,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class TelegramMenuItem<T> {
  final T? value;
  final Widget? icon;
  final String label;
  final Color? labelColor;
  final Color? iconColor;
  final bool isSeparator;
  final bool isAttention;

  const TelegramMenuItem({
    this.value,
    this.icon,
    required this.label,
    this.labelColor,
    this.iconColor,
    this.isSeparator = false,
    this.isAttention = false,
  });

  const TelegramMenuItem.separator()
      : value = null,
        icon = null,
        label = '',
        labelColor = null,
        iconColor = null,
        isSeparator = true,
        isAttention = false;
}

class _TelegramMenuRoute<T> extends PopupRoute<T> {
  final Offset position;
  final List<TelegramMenuItem<T>> items;
  final Brightness brightness;
  final Size screenSize;
  final EdgeInsets screenPadding;
  final bool fullAttention;

  _TelegramMenuRoute({
    required this.position,
    required this.items,
    required this.brightness,
    required this.screenSize,
    required this.screenPadding,
    required String barrierLabel,
    this.fullAttention = false,
  }) : _barrierLabel = barrierLabel;

  final String _barrierLabel;

  @override
  String get barrierLabel => _barrierLabel;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => _kOpenDuration;

  @override
  Duration get reverseTransitionDuration => _kCloseDuration;

  @override
  Animation<double> createAnimation() {
    return CurvedAnimation(
      parent: super.createAnimation(),
      curve: const _SineInOutCurve(),
      reverseCurve: Curves.linear,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const SizedBox.shrink();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _TelegramMenuOverlay<T>(
      animation: animation,
      position: position,
      items: items,
      brightness: brightness,
      screenSize: screenSize,
      screenPadding: screenPadding,
      fullAttention: fullAttention,
      onSelected: (T? value) {
        if (value != null) {
          navigator?.pop(value);
        } else {
          navigator?.pop();
        }
      },
    );
  }
}

class _SineInOutCurve extends Curve {
  const _SineInOutCurve();

  @override
  double transformInternal(double t) {
    return 0.5 * (1.0 - math.cos(math.pi * t));
  }
}

class _TelegramMenuOverlay<T> extends StatefulWidget {
  final Animation<double> animation;
  final Offset position;
  final List<TelegramMenuItem<T>> items;
  final Brightness brightness;
  final Size screenSize;
  final EdgeInsets screenPadding;
  final ValueChanged<T?> onSelected;
  final bool fullAttention;

  const _TelegramMenuOverlay({
    required this.animation,
    required this.position,
    required this.items,
    required this.brightness,
    required this.screenSize,
    required this.screenPadding,
    required this.onSelected,
    this.fullAttention = false,
  });

  @override
  State<_TelegramMenuOverlay<T>> createState() =>
      _TelegramMenuOverlayState<T>();
}

class _TelegramMenuOverlayState<T> extends State<_TelegramMenuOverlay<T>> {
  Alignment _origin = Alignment.topLeft;

  @override
  Widget build(BuildContext context) {
    final bg = _menuBg(widget.brightness);
    final shadow = _shadowColor(widget.brightness);

    final menuContent = _TelegramMenuContent<T>(
      items: widget.items,
      brightness: widget.brightness,
      onSelected: widget.onSelected,
      fullAttention: widget.fullAttention,
      routeAnimation: widget.animation,
    );

    return LayoutBuilder(builder: (context, constraints) {
      final menuChild = IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _kMenuMinWidth,
            maxWidth: _kMenuMaxWidth,
          ),
          child: menuContent,
        ),
      );

      const margin = 8.0;

      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelected(null),
              child: const SizedBox.expand(),
            ),
          ),
          _AnimatedMenuPositioner(
            animation: widget.animation,
            position: widget.position,
            screenSize: widget.screenSize,
            margin: margin,
            onOriginResolved: (origin) {
              if (origin != _origin) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _origin = origin);
                });
              }
            },
            child: AnimatedBuilder(
              animation: widget.animation,
              builder: (context, child) {
                final widthFactor =
                    0.5 + 0.5 * _panelCurve(widget.animation.value, 0.6);
                final heightFactor =
                    0.3 + 0.7 * _panelCurve(widget.animation.value, 0.9);
                final opacity =
                    (0.2 + 0.8 * _panelCurve(widget.animation.value, 0.3))
                        .clamp(0.0, 1.0);

                return Opacity(
                  opacity: opacity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kCornerRadius),
                    child: Align(
                      alignment: _origin,
                      widthFactor: widthFactor.clamp(0.0, 1.0),
                      heightFactor: heightFactor.clamp(0.0, 1.0),
                      child: child,
                    ),
                  ),
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(_kCornerRadius),
                  boxShadow: [
                    BoxShadow(
                      color: shadow.withOpacity(_kShadowOpacity),
                      blurRadius: _kShadowBlurRadius,
                      offset: _kShadowOffset,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: _kScrollPaddingVertical),
                    child: menuChild,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  static double _panelCurve(double t, double portion) {
    if (t >= portion) return 1.0;
    return t / portion;
  }
}

class _AnimatedMenuPositioner extends StatelessWidget {
  final Animation<double> animation;
  final Offset position;
  final Size screenSize;
  final double margin;
  final Widget child;
  final ValueChanged<Alignment>? onOriginResolved;

  const _AnimatedMenuPositioner({
    required this.animation,
    required this.position,
    required this.screenSize,
    required this.margin,
    required this.child,
    this.onOriginResolved,
  });

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _MenuPositionDelegate(
        position: position,
        screenSize: screenSize,
        margin: margin,
        onOriginResolved: onOriginResolved,
      ),
      child: child,
    );
  }
}

class _MenuPositionDelegate extends SingleChildLayoutDelegate {
  final Offset position;
  final Size screenSize;
  final double margin;
  final ValueChanged<Alignment>? onOriginResolved;

  _MenuPositionDelegate({
    required this.position,
    required this.screenSize,
    required this.margin,
    this.onOriginResolved,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(Size(
      _kMenuMaxWidth,
      screenSize.height - margin * 2,
    ));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = position.dx;
    double y = position.dy;

    bool flippedX = false;
    bool flippedY = false;

    if (x + childSize.width > screenSize.width - margin) {
      x = screenSize.width - childSize.width - margin;
      flippedX = x + childSize.width < position.dx;
    }
    if (x < margin) x = margin;

    if (y + childSize.height > screenSize.height - margin) {
      y = screenSize.height - childSize.height - margin;
      flippedY = y + childSize.height < position.dy;
    }
    if (y < margin) y = margin;

    final origin = Alignment(
      flippedX ? 1.0 : -1.0,
      flippedY ? 1.0 : -1.0,
    );
    onOriginResolved?.call(origin);

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuPositionDelegate oldDelegate) =>
      position != oldDelegate.position ||
      screenSize != oldDelegate.screenSize;
}

class _TelegramMenuContent<T> extends StatefulWidget {
  final List<TelegramMenuItem<T>> items;
  final Brightness brightness;
  final ValueChanged<T?> onSelected;
  final bool fullAttention;
  final Animation<double>? routeAnimation;

  const _TelegramMenuContent({
    required this.items,
    required this.brightness,
    required this.onSelected,
    this.fullAttention = false,
    this.routeAnimation,
  });

  @override
  State<_TelegramMenuContent<T>> createState() =>
      _TelegramMenuContentState<T>();
}

class _TelegramMenuContentState<T> extends State<_TelegramMenuContent<T>> {
  int _focusedIndex = -1;
  late final List<int> _selectableIndices;

  @override
  void initState() {
    super.initState();
    _selectableIndices = <int>[];
    for (int i = 0; i < widget.items.length; i++) {
      if (!widget.items[i].isSeparator) _selectableIndices.add(i);
    }
    HardwareKeyboard.instance.addHandler(_handleRawKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRawKey);
    super.dispose();
  }

  bool _handleRawKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1);
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_focusedIndex >= 0 && _focusedIndex < widget.items.length) {
        widget.onSelected(widget.items[_focusedIndex].value);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onSelected(null);
      return true;
    }
    return false;
  }

  void _moveFocus(int direction) {
    if (_selectableIndices.isEmpty) return;
    final currentPos = _selectableIndices.indexOf(_focusedIndex);
    int nextPos;
    if (currentPos < 0) {
      nextPos = direction > 0 ? 0 : _selectableIndices.length - 1;
    } else {
      nextPos = (currentPos + direction) % _selectableIndices.length;
      if (nextPos < 0) nextPos += _selectableIndices.length;
    }
    setState(() => _focusedIndex = _selectableIndices[nextPos]);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = widget.brightness == Brightness.dark;
    final separatorColor = isDark
        ? const Color(0xFF232f39)
        : const Color(0xFFf1f1f1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(widget.items.length, (i) {
        final item = widget.items[i];
        if (item.isSeparator) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Container(
              height: 1,
              color: separatorColor,
            ),
          );
        }

        return _TelegramRippleItem<T>(
          item: item,
          brightness: widget.brightness,
          onSelected: widget.onSelected,
          fullAttention: widget.fullAttention,
          routeAnimation: widget.routeAnimation,
          isFocused: _focusedIndex == i,
          onHover: (hovering) {
            if (hovering) {
              setState(() => _focusedIndex = i);
            }
          },
        );
      }),
    );
  }
}

class _TelegramRippleItem<T> extends StatefulWidget {
  final TelegramMenuItem<T> item;
  final Brightness brightness;
  final ValueChanged<T?> onSelected;
  final bool fullAttention;
  final Animation<double>? routeAnimation;
  final bool isFocused;
  final ValueChanged<bool>? onHover;

  const _TelegramRippleItem({
    required this.item,
    required this.brightness,
    required this.onSelected,
    this.fullAttention = false,
    this.routeAnimation,
    this.isFocused = false,
    this.onHover,
  });

  @override
  State<_TelegramRippleItem<T>> createState() => _TelegramRippleItemState<T>();
}

class _TelegramRippleItemState<T> extends State<_TelegramRippleItem<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rippleController;
  bool _hovering = false;

  static const _kRippleShowDuration = Duration(milliseconds: 650);
  static const _kRippleHideDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: _kRippleShowDuration,
      reverseDuration: _kRippleHideDuration,
    );
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _rippleController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    widget.onSelected(widget.item.value);
    _rippleController.reverse();
  }

  void _onTapCancel() {
    _rippleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final hoverColor = isDark
        ? const Color(0xFF232e3c)
        : const Color(0xFFf1f1f1);
    final rippleColor = isDark
        ? const Color(0xFF24303d)
        : const Color(0xFFe5e5e5);
    final textColor = isDark
        ? const Color(0xFFf5f5f5)
        : const Color(0xFF000000);
    final iconColorResting = isDark
        ? const Color(0xFF6c7883)
        : const Color(0xFF999999);
    final iconColorHover = isDark
        ? const Color(0xFFdcdcdc)
        : const Color(0xFF8a8a8a);

    final item = widget.item;
    final hasIcon = item.icon != null;
    final attentionColor = isDark
        ? const Color(0xFFec3942)
        : const Color(0xFFd14e4e);
    final useRedText = item.isAttention && (widget.fullAttention || !hasIcon);
    final hasCustomColor = item.labelColor != null || item.iconColor != null ||
        item.isAttention;
    final anim = widget.routeAnimation;

    Widget buildItemContent(double colorT) {
      final targetTextColor =
          item.labelColor ?? (useRedText ? attentionColor : textColor);
      final isHighlighted = _hovering || widget.isFocused;
      final targetIconColor =
          item.iconColor ?? (item.isAttention
              ? attentionColor
              : (isHighlighted ? iconColorHover : iconColorResting));
      final effectiveTextColor = hasCustomColor
          ? Color.lerp(textColor, targetTextColor, colorT)!
          : targetTextColor;
      final effectiveIconColor = hasCustomColor
          ? Color.lerp(iconColorResting, targetIconColor, colorT)!
          : targetIconColor;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasIcon)
            Positioned(
              left: -54 + 15,
              top: -8 + 5,
              child: IconTheme(
                data: IconThemeData(
                  color: effectiveIconColor,
                  size: 20,
                ),
                child: item.icon!,
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: effectiveTextColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    final contentChild = (anim != null && hasCustomColor)
        ? AnimatedBuilder(
            animation: anim,
            builder: (context, _) => buildItemContent(anim.value),
          )
        : buildItemContent(1.0);

    final highlighted = _hovering || widget.isFocused;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovering = true);
        widget.onHover?.call(true);
      },
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedBuilder(
          animation: _rippleController,
          builder: (context, child) {
            return Container(
              height: hasIcon ? 29 : 28,
              color: _rippleController.value > 0
                  ? Color.lerp(
                      highlighted ? hoverColor : null,
                      rippleColor,
                      _rippleController.value,
                    )
                  : (highlighted ? hoverColor : null),
              padding: hasIcon
                  ? const EdgeInsets.only(
                      left: 54, top: 8, right: 17, bottom: 8)
                  : const EdgeInsets.only(
                      left: 17, top: 8, right: 17, bottom: 7),
              child: child,
            );
          },
          child: contentChild,
        ),
      ),
    );
  }
}
