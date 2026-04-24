import 'dart:async';
import 'package:flutter/material.dart';

const double _kPanelWidth = 345.0;
const double _kPanelMinHeight = 278.0;
const double _kPanelMaxHeight = 640.0;
const double _kPanelMargin = 10.0;
const double _kPanelRadius = 8.0;
const double _kHeightRatio = 0.55;
const Duration _kShowDuration = Duration(milliseconds: 200);
const Duration _kHideTimeout = Duration(milliseconds: 300);

class EmojiTabbedPanel extends StatefulWidget {
  final bool visible;
  final VoidCallback onHide;

  const EmojiTabbedPanel({
    super.key,
    required this.visible,
    required this.onHide,
  });

  @override
  State<EmojiTabbedPanel> createState() => _EmojiTabbedPanelState();
}

class _EmojiTabbedPanelState extends State<EmojiTabbedPanel>
    with TickerProviderStateMixin {
  late final AnimationController _showController;
  late final CurvedAnimation _curve;
  Timer? _hideTimer;
  bool _mouseInside = false;
  int _activeTab = 0;
  late final AnimationController _tabSlideController;
  int _prevTab = 0;

  @override
  void initState() {
    super.initState();
    _showController = AnimationController(
      vsync: this,
      duration: _kShowDuration,
    );
    _curve = CurvedAnimation(
      parent: _showController,
      curve: Curves.easeOutCubic,
    );
    _tabSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.visible) {
      _showController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant EmojiTabbedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _cancelHideTimer();
      _showController.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _showController.reverse();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _showController.dispose();
    _curve.dispose();
    _tabSlideController.dispose();
    super.dispose();
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _startHideTimer() {
    _cancelHideTimer();
    _hideTimer = Timer(_kHideTimeout, () {
      if (!_mouseInside && widget.visible) {
        widget.onHide();
      }
    });
  }

  void _switchTab(int index) {
    if (index == _activeTab) return;
    setState(() {
      _prevTab = _activeTab;
      _activeTab = index;
    });
    _tabSlideController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final windowHeight = MediaQuery.of(context).size.height;
    final contentHeight = (_kHeightRatio * windowHeight)
        .clamp(_kPanelMinHeight, _kPanelMaxHeight);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark
        ? const Color(0xFF17212b)
        : const Color(0xFFFFFFFF);
    final shadowColor = isDark
        ? const Color(0x40000000)
        : const Color(0x26000000);

    return AnimatedBuilder(
      animation: _showController,
      builder: (context, _) {
        if (_showController.isDismissed && !widget.visible) {
          return const SizedBox.shrink();
        }
        final t = _curve.value;
        final w = _kPanelWidth * (0.5 + 0.5 * t);
        final h = contentHeight * (0.3 + 0.7 * t);
        final opacity = (0.2 + 0.8 * t).clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: MouseRegion(
            onEnter: (_) {
              _mouseInside = true;
              _cancelHideTimer();
            },
            onExit: (_) {
              _mouseInside = false;
              _startHideTimer();
            },
            child: Padding(
              padding: const EdgeInsets.all(_kPanelMargin),
              child: Material(
                color: panelBg,
                borderRadius: BorderRadius.circular(_kPanelRadius),
                elevation: 0,
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: panelBg,
                    borderRadius: BorderRadius.circular(_kPanelRadius),
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kPanelRadius),
                    child: Column(
                      children: [
                        _TabBar(
                          activeTab: _activeTab,
                          onTabChanged: _switchTab,
                        ),
                        Expanded(
                          child: _TabContent(
                            activeTab: _activeTab,
                            prevTab: _prevTab,
                            slideController: _tabSlideController,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabBar extends StatelessWidget {
  final int activeTab;
  final ValueChanged<int> onTabChanged;

  const _TabBar({
    required this.activeTab,
    required this.onTabChanged,
  });

  static const _tabs = ['Emoji', 'Stickers', 'GIFs'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);
    final inactiveColor = isDark
        ? const Color(0xFF7e8b93)
        : const Color(0xFF999999);
    final underlineColor = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final isActive = i == activeTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabChanged(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Text(
                    _tabs[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive ? activeColor : inactiveColor,
                    ),
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 2,
                    color: isActive ? underlineColor : Colors.transparent,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  final int activeTab;
  final int prevTab;
  final AnimationController slideController;

  const _TabContent({
    required this.activeTab,
    required this.prevTab,
    required this.slideController,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark
        ? const Color(0xFF7e8b93)
        : const Color(0xFF999999);

    final labels = ['Emoji', 'Stickers', 'GIFs'];
    final icons = [
      Icons.emoji_emotions_outlined,
      Icons.sticky_note_2_outlined,
      Icons.gif_box_outlined,
    ];

    return AnimatedBuilder(
      animation: slideController,
      builder: (context, _) {
        final direction = activeTab > prevTab ? 1.0 : -1.0;
        final slideProgress = slideController.value;

        if (slideProgress >= 1.0 || activeTab == prevTab) {
          return _buildPlaceholder(labels[activeTab], icons[activeTab], placeholderColor);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final panelW = constraints.maxWidth;
            return ClipRect(
              child: Stack(
                children: [
                  Transform.translate(
                    offset: Offset(-direction * slideProgress * panelW, 0),
                    child: Opacity(
                      opacity: 1.0 - slideProgress,
                      child: SizedBox(
                        width: panelW,
                        height: constraints.maxHeight,
                        child: _buildPlaceholder(labels[prevTab], icons[prevTab], placeholderColor),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(direction * (1.0 - slideProgress) * panelW, 0),
                    child: Opacity(
                      opacity: slideProgress,
                      child: SizedBox(
                        width: panelW,
                        height: constraints.maxHeight,
                        child: _buildPlaceholder(labels[activeTab], icons[activeTab], placeholderColor),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaceholder(String label, IconData icon, Color color) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: color.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
