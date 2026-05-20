import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double _kMenuMinWidth = 156.0;
const double _kMenuMaxWidth = 300.0;
const double _kCornerRadius = 6.0;
const double _kShadowBlurRadius = 5.0;
const Offset _kShadowOffset = Offset(0, 1);
const double _kShadowOpacity = 0.25;
const Duration _kOpenDuration = Duration(milliseconds: 200);
const Duration _kCloseDuration = Duration(milliseconds: 150);

Color _menuBg(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF17212b) : const Color(0xFFffffff);

Color _shadowColor(Brightness b) => const Color(0xFF000000);

Future<T?> showTelegramMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<TelegramMenuItem<T>> items,
  bool fullAttention = false,
  double? maxHeight,
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
      maxHeight: maxHeight,
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
  final bool isDisabled;
  final String? shortcut;
  final List<TelegramMenuItem<T>>? submenu;

  const TelegramMenuItem({
    this.value,
    this.icon,
    required this.label,
    this.labelColor,
    this.iconColor,
    this.isSeparator = false,
    this.isAttention = false,
    this.isDisabled = false,
    this.shortcut,
    this.submenu,
  });

  const TelegramMenuItem.separator()
      : value = null,
        icon = null,
        label = '',
        labelColor = null,
        iconColor = null,
        isSeparator = true,
        isAttention = false,
        isDisabled = false,
        shortcut = null,
        submenu = null;
}

class _TelegramMenuRoute<T> extends PopupRoute<T> {
  final Offset position;
  final List<TelegramMenuItem<T>> items;
  final Brightness brightness;
  final Size screenSize;
  final EdgeInsets screenPadding;
  final bool fullAttention;
  final double? maxHeight;

  _TelegramMenuRoute({
    required this.position,
    required this.items,
    required this.brightness,
    required this.screenSize,
    required this.screenPadding,
    required String barrierLabel,
    this.fullAttention = false,
    this.maxHeight,
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
      maxHeight: maxHeight,
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
  final double? maxHeight;

  const _TelegramMenuOverlay({
    required this.animation,
    required this.position,
    required this.items,
    required this.brightness,
    required this.screenSize,
    required this.screenPadding,
    required this.onSelected,
    this.fullAttention = false,
    this.maxHeight,
  });

  @override
  State<_TelegramMenuOverlay<T>> createState() =>
      _TelegramMenuOverlayState<T>();
}

class _TelegramMenuOverlayState<T> extends State<_TelegramMenuOverlay<T>>
    with WidgetsBindingObserver {
  Alignment _origin = Alignment.topLeft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      widget.onSelected(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _menuBg(widget.brightness);
    final shadow = _shadowColor(widget.brightness);
    final hasIcons =
        widget.items.any((item) => !item.isSeparator && item.icon != null);
    final scrollPadding = hasIcons ? 5.0 : 8.0;

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
            maxHeight: widget.maxHeight,
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
                    0.45 + 0.55 * _panelCurve(widget.animation.value, 0.9);
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
                    padding: EdgeInsets.symmetric(vertical: scrollPadding),
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
  final double? maxHeight;

  const _AnimatedMenuPositioner({
    required this.animation,
    required this.position,
    required this.screenSize,
    required this.margin,
    required this.child,
    this.onOriginResolved,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _MenuPositionDelegate(
        position: position,
        screenSize: screenSize,
        margin: margin,
        onOriginResolved: onOriginResolved,
        maxHeight: maxHeight,
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
  final double? maxHeight;
  final bool isRtl;

  _MenuPositionDelegate({
    required this.position,
    required this.screenSize,
    required this.margin,
    this.onOriginResolved,
    this.maxHeight,
    this.isRtl = false,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final screenMax = screenSize.height - margin * 2;
    final effectiveMax = maxHeight != null
        ? math.min(maxHeight!, screenMax)
        : screenMax;
    return BoxConstraints.loose(Size(
      _kMenuMaxWidth,
      effectiveMax,
    ));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = isRtl ? position.dx - childSize.width : position.dx;
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
      screenSize != oldDelegate.screenSize ||
      maxHeight != oldDelegate.maxHeight ||
      isRtl != oldDelegate.isRtl;
}

class _AnimatedSubmenuReveal extends StatefulWidget {
  final Widget child;
  final Alignment origin;

  const _AnimatedSubmenuReveal({
    required this.child,
    this.origin = Alignment.topLeft,
  });

  @override
  State<_AnimatedSubmenuReveal> createState() => _AnimatedSubmenuRevealState();
}

class _AnimatedSubmenuRevealState extends State<_AnimatedSubmenuReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _kOpenDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = const _SineInOutCurve().transform(_controller.value);
        final widthFactor = 0.5 + 0.5 * _panelCurve(t, 0.6);
        final heightFactor = 0.45 + 0.55 * _panelCurve(t, 0.9);
        final opacity = (0.2 + 0.8 * _panelCurve(t, 0.3)).clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kCornerRadius),
            child: Align(
              alignment: widget.origin,
              widthFactor: widthFactor.clamp(0.0, 1.0),
              heightFactor: heightFactor.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }

  static double _panelCurve(double t, double portion) {
    if (t >= portion) return 1.0;
    return t / portion;
  }
}

class _TelegramMenuContent<T> extends StatefulWidget {
  final List<TelegramMenuItem<T>> items;
  final Brightness brightness;
  final ValueChanged<T?> onSelected;
  final bool fullAttention;
  final Animation<double>? routeAnimation;
  final VoidCallback? onEscape;

  const _TelegramMenuContent({
    required this.items,
    required this.brightness,
    required this.onSelected,
    this.fullAttention = false,
    this.routeAnimation,
    this.onEscape,
  });

  @override
  State<_TelegramMenuContent<T>> createState() =>
      _TelegramMenuContentState<T>();
}

class _TelegramMenuContentState<T> extends State<_TelegramMenuContent<T>> {
  int _focusedIndex = -1;
  late final List<int> _selectableIndices;
  final Map<int, GlobalKey> _itemKeys = {};
  OverlayEntry? _submenuOverlay;
  int _activeSubmenuIndex = -1;

  @override
  void initState() {
    super.initState();
    _selectableIndices = <int>[];
    for (int i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      if (!item.isSeparator && !item.isDisabled) _selectableIndices.add(i);
      if (item.submenu != null) _itemKeys[i] = GlobalKey();
    }
    HardwareKeyboard.instance.addHandler(_handleRawKey);
  }

  @override
  void dispose() {
    _hideSubmenu();
    HardwareKeyboard.instance.removeHandler(_handleRawKey);
    super.dispose();
  }

  void _handleSelection(T? value) {
    _hideSubmenu();
    widget.onSelected(value);
  }

  void _showSubmenu(int index) {
    if (!mounted) return;
    if (_activeSubmenuIndex == index) return;
    _hideSubmenu();

    final items = widget.items[index].submenu!;
    final key = _itemKeys[index];
    if (key == null) return;

    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final itemPos = box.localToGlobal(Offset.zero);
    final itemSize = box.size;
    final brightness = widget.brightness;
    final hasIcons = items.any((i) => !i.isSeparator && i.icon != null);
    final pad = hasIcons ? 5.0 : 8.0;
    final bg = _menuBg(brightness);
    final shadow = _shadowColor(brightness);

    setState(() => _activeSubmenuIndex = index);

    _submenuOverlay = OverlayEntry(
      builder: (ctx) {
        final screenSize = MediaQuery.of(ctx).size;
        final rtl = Directionality.of(ctx) == TextDirection.rtl;
        return CustomSingleChildLayout(
          delegate: _MenuPositionDelegate(
            position: rtl
                ? Offset(itemPos.dx, itemPos.dy - pad)
                : Offset(itemPos.dx + itemSize.width, itemPos.dy - pad),
            screenSize: screenSize,
            margin: 8.0,
            isRtl: rtl,
          ),
          child: _AnimatedSubmenuReveal(
            origin: rtl ? Alignment.topRight : Alignment.topLeft,
            child: IntrinsicWidth(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: _kMenuMinWidth,
                  maxWidth: _kMenuMaxWidth,
                ),
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
                      padding: EdgeInsets.symmetric(vertical: pad),
                      child: _TelegramMenuContent<T>(
                        items: items,
                        brightness: brightness,
                        onSelected: _handleSelection,
                        onEscape: _hideSubmenu,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_submenuOverlay!);
  }

  void _hideSubmenu() {
    _submenuOverlay?.remove();
    _submenuOverlay = null;
    if (_activeSubmenuIndex >= 0) {
      _activeSubmenuIndex = -1;
      if (mounted) setState(() {});
    }
  }

  bool _handleRawKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final closeKey = isRtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    final openKey = isRtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;

    if (key == closeKey) {
      if (_activeSubmenuIndex >= 0) {
        _hideSubmenu();
        return true;
      }
      if (widget.onEscape != null) {
        widget.onEscape!();
        return true;
      }
      return false;
    }

    if (_activeSubmenuIndex >= 0) return false;

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1);
      return true;
    }
    if (key == openKey) {
      if (_focusedIndex >= 0 &&
          _focusedIndex < widget.items.length &&
          widget.items[_focusedIndex].submenu != null) {
        _showSubmenu(_focusedIndex);
        return true;
      }
      return false;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_focusedIndex >= 0 && _focusedIndex < widget.items.length) {
        final item = widget.items[_focusedIndex];
        if (item.submenu != null) {
          _showSubmenu(_focusedIndex);
        } else {
          _handleSelection(item.value);
        }
      }
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (widget.onEscape != null) {
        widget.onEscape!();
      } else {
        _handleSelection(null);
      }
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

    int effectiveLength = widget.items.length;
    while (effectiveLength > 0 &&
        widget.items[effectiveLength - 1].isSeparator) {
      effectiveLength--;
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(effectiveLength, (i) {
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

          if (item.isDisabled) {
            return _TelegramDisabledItem<T>(
              item: item,
              brightness: widget.brightness,
            );
          }

          return _TelegramRippleItem<T>(
            key: _itemKeys[i],
            item: item,
            brightness: widget.brightness,
            onSelected: _handleSelection,
            fullAttention: widget.fullAttention,
            routeAnimation: widget.routeAnimation,
            isFocused: _focusedIndex == i,
            isSubmenuActive: _activeSubmenuIndex == i,
            onHover: (hovering) {
              if (hovering) {
                setState(() => _focusedIndex = i);
                if (item.submenu != null) {
                  _showSubmenu(i);
                } else {
                  _hideSubmenu();
                }
              }
            },
          );
        }),
      ),
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
  final bool isSubmenuActive;
  final ValueChanged<bool>? onHover;

  const _TelegramRippleItem({
    super.key,
    required this.item,
    required this.brightness,
    required this.onSelected,
    this.fullAttention = false,
    this.routeAnimation,
    this.isFocused = false,
    this.isSubmenuActive = false,
    this.onHover,
  });

  @override
  State<_TelegramRippleItem<T>> createState() => _TelegramRippleItemState<T>();
}

class _TelegramRippleItemState<T> extends State<_TelegramRippleItem<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rippleController;
  bool _hovering = false;
  Offset _tapPosition = Offset.zero;

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

  void _onTapDown(TapDownDetails details) {
    _tapPosition = details.localPosition;
    _rippleController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.item.submenu != null) {
      widget.onHover?.call(true);
    } else {
      widget.onSelected(widget.item.value);
    }
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
    final shortcutColor = isDark
        ? const Color(0xFF8d9ba4)
        : const Color(0xFF999999);
    final shortcutColorHover = isDark
        ? const Color(0xFFa0b0b8)
        : const Color(0xFF888888);

    final item = widget.item;
    final hasIcon = item.icon != null;
    final attentionColor = isDark
        ? const Color(0xFFec3942)
        : const Color(0xFFd14e4e);
    final useRedText = item.isAttention && (widget.fullAttention || !hasIcon);
    final hasCustomColor = item.labelColor != null || item.iconColor != null ||
        item.isAttention;
    final anim = widget.routeAnimation;
    final highlighted =
        _hovering || widget.isFocused || widget.isSubmenuActive;

    Widget buildItemContent(double colorT) {
      final targetTextColor =
          item.labelColor ?? (useRedText ? attentionColor : textColor);
      final isHighlighted = highlighted;
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

      return Row(
        children: [
          Expanded(
            child: Stack(
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
            ),
          ),
          if (item.shortcut != null) ...[
            const SizedBox(width: 6),
            Text(
              item.shortcut!,
              style: TextStyle(
                fontSize: 13,
                color: isHighlighted ? shortcutColorHover : shortcutColor,
              ),
            ),
          ],
          if (item.submenu != null) ...[
            const SizedBox(width: 6),
            CustomPaint(
              size: const Size(5, 8),
              painter: _SubmenuArrowPainter(
                isHighlighted ? iconColorHover : iconColorResting,
              ),
            ),
          ],
        ],
      );
    }

    final contentChild = (anim != null && hasCustomColor)
        ? AnimatedBuilder(
            animation: anim,
            builder: (context, _) => buildItemContent(anim.value),
          )
        : buildItemContent(1.0);

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
            return CustomPaint(
              foregroundPainter: _rippleController.value > 0
                  ? _RippleCirclePainter(
                      progress: _rippleController.value,
                      center: _tapPosition,
                      color: rippleColor,
                    )
                  : null,
              child: Container(
                height: hasIcon ? 29 : 28,
                color: highlighted ? hoverColor : null,
                padding: hasIcon
                    ? const EdgeInsets.only(
                        left: 54, top: 8, right: 17, bottom: 8)
                    : const EdgeInsets.only(
                        left: 17, top: 8, right: 17, bottom: 7),
                child: child,
              ),
            );
          },
          child: contentChild,
        ),
      ),
    );
  }
}

class _RippleCirclePainter extends CustomPainter {
  final double progress;
  final Offset center;
  final Color color;

  _RippleCirclePainter({
    required this.progress,
    required this.center,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxRadius = math.sqrt(
      math.max(
        center.dx * center.dx + center.dy * center.dy,
        math.max(
          (size.width - center.dx) * (size.width - center.dx) +
              center.dy * center.dy,
          math.max(
            center.dx * center.dx +
                (size.height - center.dy) * (size.height - center.dy),
            (size.width - center.dx) * (size.width - center.dx) +
                (size.height - center.dy) * (size.height - center.dy),
          ),
        ),
      ),
    );
    final radius = maxRadius * progress;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withOpacity(color.opacity * (1.0 - progress * 0.3)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RippleCirclePainter old) =>
      progress != old.progress ||
      center != old.center ||
      color != old.color;
}

class _TelegramDisabledItem<T> extends StatelessWidget {
  final TelegramMenuItem<T> item;
  final Brightness brightness;

  const _TelegramDisabledItem({
    required this.item,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final textColor = isDark
        ? const Color(0xFF6c7883)
        : const Color(0xFFcccccc);
    final iconColor = isDark
        ? const Color(0xFF6c7883)
        : const Color(0xFFcccccc);
    final hasIcon = item.icon != null;

    return IgnorePointer(
      child: Container(
        height: hasIcon ? 29 : 28,
        padding: hasIcon
            ? const EdgeInsets.only(left: 54, top: 8, right: 17, bottom: 8)
            : const EdgeInsets.only(left: 17, top: 8, right: 17, bottom: 7),
        child: Row(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (hasIcon)
                    Positioned(
                      left: -54 + 15,
                      top: -8 + 5,
                      child: IconTheme(
                        data: IconThemeData(color: iconColor, size: 20),
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
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (item.shortcut != null) ...[
              const SizedBox(width: 6),
              Text(
                item.shortcut!,
                style: TextStyle(fontSize: 13, color: textColor),
              ),
            ],
            if (item.submenu != null) ...[
              const SizedBox(width: 6),
              CustomPaint(
                size: const Size(5, 8),
                painter: _SubmenuArrowPainter(iconColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubmenuArrowPainter extends CustomPainter {
  final Color color;
  _SubmenuArrowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SubmenuArrowPainter old) => color != old.color;
}
