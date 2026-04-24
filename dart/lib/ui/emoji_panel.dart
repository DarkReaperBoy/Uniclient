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

const double _kEmojiCellSize = 40.0;
const double _kEmojiGridPadding = 8.0;
const double _kCategoryBarHeight = 38.0;
const double _kEmojiColorsPadding = 8.0;
const double _kEmojiColorsSep = 1.0;
const double _kPopupPad = 4.0;

Map<String, int> _skinTonePrefs = {};

const Set<int> _emojiModifierBases = {
  0x261D, 0x26F9,
  0x270A, 0x270B, 0x270C, 0x270D,
  0x1F385,
  0x1F3C2, 0x1F3C3, 0x1F3C4, 0x1F3C7, 0x1F3CA, 0x1F3CB, 0x1F3CC,
  0x1F442, 0x1F443, 0x1F446, 0x1F447, 0x1F448, 0x1F449, 0x1F44A,
  0x1F44B, 0x1F44C, 0x1F44D, 0x1F44E, 0x1F44F, 0x1F450,
  0x1F466, 0x1F467, 0x1F468, 0x1F469, 0x1F46B, 0x1F46C, 0x1F46D,
  0x1F46E, 0x1F470, 0x1F471, 0x1F472, 0x1F473, 0x1F474, 0x1F475,
  0x1F476, 0x1F477, 0x1F478, 0x1F47C,
  0x1F481, 0x1F482, 0x1F483, 0x1F485, 0x1F486, 0x1F487,
  0x1F4AA,
  0x1F574, 0x1F575, 0x1F57A,
  0x1F590, 0x1F595, 0x1F596,
  0x1F645, 0x1F646, 0x1F647, 0x1F64B, 0x1F64C, 0x1F64D, 0x1F64E, 0x1F64F,
  0x1F6A3, 0x1F6B4, 0x1F6B5, 0x1F6B6, 0x1F6C0, 0x1F6CC,
  0x1F90C, 0x1F90F,
  0x1F918, 0x1F919, 0x1F91A, 0x1F91B, 0x1F91C, 0x1F91D, 0x1F91E, 0x1F91F,
  0x1F926, 0x1F930, 0x1F931, 0x1F932, 0x1F933, 0x1F934, 0x1F935, 0x1F936,
  0x1F937, 0x1F938, 0x1F939, 0x1F93D, 0x1F93E,
  0x1F9B5, 0x1F9B6, 0x1F9B8, 0x1F9B9, 0x1F9BB,
  0x1F9CD, 0x1F9CE, 0x1F9CF,
  0x1F9D1, 0x1F9D2, 0x1F9D3, 0x1F9D4, 0x1F9D5, 0x1F9D6, 0x1F9D7,
  0x1F9D8, 0x1F9D9, 0x1F9DA, 0x1F9DB, 0x1F9DC, 0x1F9DD,
  0x1FAC3, 0x1FAC4, 0x1FAC5,
  0x1FAF0, 0x1FAF1, 0x1FAF2, 0x1FAF3, 0x1FAF4, 0x1FAF5, 0x1FAF6, 0x1FAF7, 0x1FAF8,
};

String _getBaseEmoji(String emoji) {
  final buf = StringBuffer();
  for (final rune in emoji.runes) {
    if (rune >= 0x1F3FB && rune <= 0x1F3FF) continue;
    buf.writeCharCode(rune);
  }
  return buf.toString();
}

String _emojiPrefKey(String emoji) {
  final buf = StringBuffer();
  for (final rune in emoji.runes) {
    if (rune >= 0x1F3FB && rune <= 0x1F3FF) continue;
    if (rune == 0xFE0F) continue;
    buf.writeCharCode(rune);
  }
  return buf.toString();
}

String _applySkinTone(String baseEmoji, int modifierIndex) {
  if (modifierIndex <= 0 || modifierIndex > 5) return baseEmoji;
  final stripped = _getBaseEmoji(baseEmoji);
  final runes = stripped.runes.toList();
  if (runes.isEmpty) return baseEmoji;
  final result = StringBuffer();
  result.writeCharCode(runes[0]);
  var i = 1;
  if (i < runes.length && runes[i] == 0xFE0F) i++;
  result.writeCharCode(0x1F3FA + modifierIndex);
  for (; i < runes.length; i++) {
    result.writeCharCode(runes[i]);
  }
  return result.toString();
}

bool _supportsSkinTone(String emoji) {
  final key = _emojiPrefKey(emoji);
  final runes = key.runes.toList();
  if (runes.isEmpty) return false;
  return _emojiModifierBases.contains(runes[0]);
}

String _displayEmoji(String emoji) {
  if (!_supportsSkinTone(emoji)) return emoji;
  final key = _emojiPrefKey(emoji);
  final pref = _skinTonePrefs[key];
  if (pref != null && pref > 0) return _applySkinTone(emoji, pref);
  return emoji;
}

class EmojiTabbedPanel extends StatefulWidget {
  final bool visible;
  final VoidCallback onHide;
  final ValueChanged<String>? onEmojiSelected;

  const EmojiTabbedPanel({
    super.key,
    required this.visible,
    required this.onHide,
    this.onEmojiSelected,
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
                            onEmojiSelected: widget.onEmojiSelected,
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
  final ValueChanged<String>? onEmojiSelected;

  const _TabContent({
    required this.activeTab,
    required this.prevTab,
    required this.slideController,
    this.onEmojiSelected,
  });

  Widget _buildTab(int index) {
    if (index == 0) {
      return _EmojiTab(onEmojiSelected: onEmojiSelected);
    }
    final isDark = false; // will be resolved per-build
    final placeholderColor = const Color(0xFF999999);
    final labels = ['Emoji', 'Stickers', 'GIFs'];
    final icons = [
      Icons.emoji_emotions_outlined,
      Icons.sticky_note_2_outlined,
      Icons.gif_box_outlined,
    ];
    return _buildPlaceholder(labels[index], icons[index], placeholderColor);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark
        ? const Color(0xFF7e8b93)
        : const Color(0xFF999999);

    return AnimatedBuilder(
      animation: slideController,
      builder: (context, _) {
        final direction = activeTab > prevTab ? 1.0 : -1.0;
        final slideProgress = slideController.value;

        if (slideProgress >= 1.0 || activeTab == prevTab) {
          if (activeTab == 0) {
            return _EmojiTab(onEmojiSelected: onEmojiSelected);
          }
          final labels = ['Emoji', 'Stickers', 'GIFs'];
          final icons = [
            Icons.emoji_emotions_outlined,
            Icons.sticky_note_2_outlined,
            Icons.gif_box_outlined,
          ];
          return _buildPlaceholder(labels[activeTab], icons[activeTab], placeholderColor);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final panelW = constraints.maxWidth;
            Widget prevWidget;
            Widget activeWidget;

            if (prevTab == 0) {
              prevWidget = _EmojiTab(onEmojiSelected: onEmojiSelected);
            } else {
              final labels = ['Emoji', 'Stickers', 'GIFs'];
              final icons = [Icons.emoji_emotions_outlined, Icons.sticky_note_2_outlined, Icons.gif_box_outlined];
              prevWidget = _buildPlaceholder(labels[prevTab], icons[prevTab], placeholderColor);
            }

            if (activeTab == 0) {
              activeWidget = _EmojiTab(onEmojiSelected: onEmojiSelected);
            } else {
              final labels = ['Emoji', 'Stickers', 'GIFs'];
              final icons = [Icons.emoji_emotions_outlined, Icons.sticky_note_2_outlined, Icons.gif_box_outlined];
              activeWidget = _buildPlaceholder(labels[activeTab], icons[activeTab], placeholderColor);
            }

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
                        child: prevWidget,
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
                        child: activeWidget,
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

enum _EmojiCategory {
  recent,
  smileys,
  nature,
  food,
  activities,
  travel,
  objects,
  symbols,
}

class _EmojiCategoryData {
  final _EmojiCategory category;
  final IconData icon;
  final String label;
  final List<String> emojis;

  const _EmojiCategoryData({
    required this.category,
    required this.icon,
    required this.label,
    required this.emojis,
  });
}

final List<_EmojiCategoryData> _emojiCategories = [
  _EmojiCategoryData(
    category: _EmojiCategory.recent,
    icon: Icons.access_time,
    label: 'Recent',
    emojis: [],
  ),
  const _EmojiCategoryData(
    category: _EmojiCategory.smileys,
    icon: Icons.emoji_emotions_outlined,
    label: 'Smileys',
    emojis: [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
      '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
      '🥲', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫',
      '🤔', '🫡', '🤐', '🤨', '😐', '😑', '😶', '🫥', '😏', '😒',
      '🙄', '😬', '🤥', '🫨', '😌', '😔', '😪', '🤤', '😴', '😷',
      '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯',
      '🤠', '🥳', '🥸', '😎', '🤓', '🧐', '😕', '🫤', '😟', '🙁',
      '😮', '😯', '😲', '😳', '🥺', '🥹', '😦', '😧', '😨', '😰',
      '😥', '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫',
      '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️', '💩',
      '🤡', '👹', '👺', '👻', '👽', '👾', '🤖', '😺', '😸', '😹',
      '😻', '😼', '😽', '🙀', '😿', '😾', '🫶', '👋', '🤚', '🖐️',
      '✋', '🖖', '🫱', '🫲', '🫳', '🫴', '👌', '🤌', '🤏', '✌️',
      '🤞', '🫰', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇',
      '☝️', '🫵', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌',
      '🫶', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳', '💪', '🦾',
    ],
  ),
  const _EmojiCategoryData(
    category: _EmojiCategory.nature,
    icon: Icons.pets_outlined,
    label: 'Nature',
    emojis: [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐻‍❄️', '🐨',
      '🐯', '🦁', '🐮', '🐷', '🐽', '🐸', '🐵', '🙈', '🙉', '🙊',
      '🐒', '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉',
      '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🪱', '🐛', '🦋', '🐌',
      '🐞', '🐜', '🪰', '🪲', '🪳', '🦟', '🦗', '🕷️', '🕸️', '🦂',
      '🐢', '🐍', '🦎', '🦖', '🦕', '🐙', '🦑', '🦐', '🦞', '🦀',
      '🪸', '🐡', '���', '🐟', '🐬', '🐳', '🐋', '🦈', '🐊', '🐅',
      '🐆', '🦓', '🫏', '🦍', '🦧', '🐘', '🦣', '🦛', '🦏', '🐪',
      '🐫', '🦒', '🦘', '🦬', '🐃', '🐂', '🐄', '🐎', '🐖', '🐏',
      '🐑', '🦙', '🐐', '🦌', '🐕', '🐩', '🦮', '🐕‍🦺', '🐈', '🐈‍⬛',
      '🌸', '💮', '🏵️', '🌹', '🥀', '🌺', '🌻', '🌼', '🌷', '🪻',
      '🌱', '🪴', '🌲', '🌳', '🌴', '🌵', '🌾', '🌿', '☘️', '🍀',
      '🍁', '🍂', '🍃', '🪹', '🪺', '🍄', '🌰', '🦀', '🌍', '🌎',
      '🌏', '🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘', '🌙',
      '🌚', '🌛', '🌜', '☀️', '🌝', '🌞', '⭐', '🌟', '🌠', '☁️',
      '⛅', '⛈️', '🌤️', '🌥️', '🌦️', '🌧️', '🌨️', '🌩️', '🌪️', '🌫️',
    ],
  ),
  const _EmojiCategoryData(
    category: _EmojiCategory.food,
    icon: Icons.restaurant_outlined,
    label: 'Food',
    emojis: [
      '🍇', '🍈', '🍉', '🍊', '🍋', '🍌', '🍍', '🥭', '🍎', '🍏',
      '🍐', '🍑', '🍒', '🍓', '🫐', '🥝', '🍅', '🫒', '🥥', '🥑',
      '🍆', '🥔', '🥕', '🌽', '🌶️', '🫑', '🥒', '🥬', '🥦', '🧄',
      '🧅', '🥜', '🫘', '🌰', '🫚', '🫛', '🍞', '🥐', '🥖', '🫓',
      '🥨', '🥯', '🥞', '🧇', '🧀', '🍖', '🍗', '🥩', '🥓', '🍔',
      '🍟', '🍕', '🌭', '🥪', '🌮', '🌯', '🫔', '🥙', '🧆', '🥚',
      '🍳', '🥘', '🍲', '🫕', '🥣', '🥗', '🍿', '🧈', '🧂', '🥫',
      '🍱', '🍘', '🍙', '🍚', '🍛', '🍜', '🍝', '🍠', '🍢', '🍣',
      '🍤', '🍥', '🥮', '🍡', '🥟', '🥠', '🥡', '🦀', '🦞', '🦐',
      '🦑', '🦪', '🍦', '🍧', '🍨', '🍩', '🍪', '🎂', '🍰', '🧁',
      '🥧', '🍫', '🍬', '🍭', '🍮', '🍯', '🍼', '🥛', '☕', '🫖',
      '🍵', '🍶', '🍾', '🍷', '🍸', '🍹', '🍺', '🍻', '🥂', '🥃',
      '🫗', '🥤', '🧋', '🧃', '🧉', '🧊', '🥢', '🍽️', '🍴', '🥄',
    ],
  ),
  const _EmojiCategoryData(
    category: _EmojiCategory.activities,
    icon: Icons.sports_soccer_outlined,
    label: 'Activities',
    emojis: [
      '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
      '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳',
      '🪁', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷',
      '⛸️', '🥌', '🎿', '⛷️', '🏂', '🪂', '🏋️', '🤼', '🤸', '⛹️',
      '🤺', '🏇', '🧘', '🏄', '🏊', '🤽', '🚣', '🧗', '🚵', '🚴',
      '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🏵️', '🎗️', '🎪', '🤹',
      '🎭', '🩰', '🎨', '🎬', '🎤', '🎧', '🎼', '🎹', '🥁', '🪘',
      '🎷', '🎺', '🪗', '🎸', '🎻', '🪕', '🎲', '♟️', '🎯', '🎳',
      '🎮', '🕹️', '🎰', '🧩', '🪅', '🪩', '🪆', '♠️', '♥️', '♦️',
      '♣️', '🃏', '🀄', '🎴', '🎭', '🖼️', '🎨', '🧵', '🪡', '🧶',
    ],
  ),
  const _EmojiCategoryData(
    category: _EmojiCategory.travel,
    icon: Icons.directions_car_outlined,
    label: 'Travel',
    emojis: [
      '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐',
      '🛻', '🚚', '🚛', '🚜', '🦯', '🦽', '🦼', '🛴', '🚲', '🛵',
      '🏍️', '🛺', '🚨', '🚔', '🚍', '🚘', '🚖', '🛞', '🚡', '🚠',
      '🚟', '🚃', '🚋', '🚞', '🚝', '🚄', '🚅', '🚆', '🚇', '🚈',
      '🚉', '🚊', '🚁', '🛩️', '✈️', '🛫', '🛬', '🪂', '💺', '🛰️',
      '🚀', '🛸', '🚢', '⛵', '🛥️', '🚤', '🛳️', '⛴️', '🚢', '⚓',
      '🛟', '🪝', '⛽', '🚧', '🚦', '🚥', '🛑', '🚏', '🗺️', '🗿',
      '🗽', '🗼', '🏰', '🏯', '🏟️', '🎡', '🎢', '🎠', '⛲', '⛱️',
      '🏖️', '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🗻', '🏕️', '⛺', '🛖',
      '🏠', '🏡', '🏘️', '🏚️', '🏗️', '🏭', '🏢', '🏬', '🏣', '🏤',
      '🏥', '🏦', '🏨', '🏪', '🏫', '🏩', '💒', '🏛️', '⛪', '🕌',
      '🕍', '🛕', '🕋', '⛩️', '🛤️', '🛣️', '🗾', '🎑', '🏞️', '🌅',
      '🌄', '🌠', '🎇', '🎆', '🌇', '🌆', '🏙️', '🌃', '🌌', '🌉',
    ],
  ),
  const _EmojiCategoryData(
    category: _EmojiCategory.objects,
    icon: Icons.lightbulb_outline,
    label: 'Objects',
    emojis: [
      '⌚', '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️', '🕹️',
      '🗜️', '💽', '💾', '💿', '📀', '📼', '📷', '📸', '📹', '🎥',
      '📽️', '🎞️', '📞', '☎️', '📟', '📠', '📺', '📻', '🎙️', '🎚️',
      '🎛️', '🧭', '⏱️', '⏲️', '⏰', '🕰️', '⌛', '⏳', '📡', '🔋',
      '🪫', '🔌', '💡', '🔦', '🕯️', '🪔', '🧯', '🛢️', '💸', '💵',
      '💴', '💶', '💷', '🪙', '💰', '💳', '💎', '⚖️', '🪜', '🧰',
      '🪛', '🔧', '🔨', '⚒️', '🛠️', '⛏️', '🪚', '🔩', '⚙️', '🪤',
      '🧱', '⛓️', '🧲', '🔫', '💣', '🧨', '🪓', '🔪', '🗡️', '⚔️',
      '🛡️', '🚬', '⚰️', '🪦', '⚱️', '🏺', '🔮', '📿', '🧿', '🪬',
      '💈', '⚗️', '🔭', '🔬', '🕳️', '🩹', '🩺', '🩻', '🩼', '💊',
      '💉', '🩸', '����', '🦠', '🧫', '🧪', '🌡️', '🧹', '🪠', '🧺',
      '🧻', '🚽', '🚰', '🚿', '🛁', '🛀', '🧼', '🪥', '🪒', '🧽',
      '📦', '📫', '📪', '📬', '📭', '📮', '📯', '📜', '📃', '📄',
      '📑', '🧾', '📊', '📈', '📉', '🗒️', '🗓️', '📆', '📅', '🗑️',
      '📇', '🗃️', '🗳️', '🗄️', '📋', '📁', '📂', '🗂️', '🗞️', '📰',
      '📓', '📔', '📒', '📕', '📗', '📘', '📙', '📚', '📖', '🔖',
    ],
  ),
  const _EmojiCategoryData(
    category: _EmojiCategory.symbols,
    icon: Icons.tag,
    label: 'Symbols',
    emojis: [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
      '❤️‍🔥', '❤️‍🩹', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝',
      '💟', '☮️', '✝️', '☪️', '🕉️', '☸️', '✡️', '🔯', '🕎', '☯️',
      '☦️', '🛐', '⛎', '♈', '♉', '♊', '♋', '♌', '♍', '♎',
      '♏', '♐', '♑', '♒', '♓', '🆔', '⚛️', '🉑', '☢️', '☣️',
      '📴', '📳', '🈶', '🈚', '🈸', '🈺', '🈷️', '✴️', '🆚', '💮',
      '🉐', '㊙️', '㊗️', '🈴', '🈵', '🈹', '🈲', '🅰️', '🅱️', '🆎',
      '🆑', '🅾️', '🆘', '❌', '⭕', '🛑', '⛔', '📛', '🚫', '💯',
      '💢', '♨️', '🚷', '🚯', '🚳', '🚱', '🔞', '📵', '🚭', '❗',
      '❕', '❓', '❔', '‼️', '⁉️', '🔅', '🔆', '〽️', '⚠️', '🚸',
      '🔱', '⚜️', '🔰', '♻️', '✅', '🈯', '💹', '❇️', '✳️', '❎',
      '🌐', '💠', 'Ⓜ️', '🌀', '💤', '🏧', '🚾', '♿', '🅿️', '🛗',
      '🈳', '🈂️', '🛂', '🛃', '🛄', '🛅', '🚹', '🚺', '🚻', '🚼',
      '🚮', '🎦', '📶', '🈁', '🔣', 'ℹ️', '🔤', '🔡', '🔠', '🆖',
      '🆗', '🆙', '🆒', '🆕', '🆓', '0️⃣', '1️⃣', '2️⃣', '3️⃣', '4️⃣',
      '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟', '🔢', '#️⃣', '*️⃣', '⏏️',
    ],
  ),
];

List<String> _recentEmojis = [];

class _EmojiTab extends StatefulWidget {
  final ValueChanged<String>? onEmojiSelected;

  const _EmojiTab({this.onEmojiSelected});

  @override
  State<_EmojiTab> createState() => _EmojiTabState();
}

class _EmojiTabState extends State<_EmojiTab> {
  int _activeCategory = 1;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _stackKey = GlobalKey();
  String? _skinToneTarget;
  Offset _skinToneAnchorGlobal = Offset.zero;
  Size _skinToneAnchorSize = Size.zero;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectCategory(int index) {
    if (index == 0 && _recentEmojis.isEmpty) return;
    _dismissSkinTone();
    setState(() => _activeCategory = index);
    _scrollController.jumpTo(0);
  }

  void _onEmojiTap(String emoji) {
    if (_supportsSkinTone(emoji)) {
      final key = _emojiPrefKey(emoji);
      _recentEmojis.removeWhere((e) => _emojiPrefKey(e) == key);
    } else {
      _recentEmojis.remove(emoji);
    }
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 50) {
      _recentEmojis = _recentEmojis.sublist(0, 50);
    }
    widget.onEmojiSelected?.call(emoji);
  }

  void _showSkinTone(String emoji, Offset globalPos, Size size) {
    setState(() {
      _skinToneTarget = emoji;
      _skinToneAnchorGlobal = globalPos;
      _skinToneAnchorSize = size;
    });
  }

  void _dismissSkinTone() {
    if (_skinToneTarget == null) return;
    setState(() => _skinToneTarget = null);
  }

  void _onSkinToneSelected(String emoji, int index) {
    _skinTonePrefs[_emojiPrefKey(_skinToneTarget!)] = index;
    _dismissSkinTone();
    _onEmojiTap(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeCategory = _emojiCategories[_activeCategory];
    final emojis = _activeCategory == 0 ? _recentEmojis : activeCategory.emojis;

    return Stack(
      key: _stackKey,
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = ((constraints.maxWidth - 2 * _kEmojiGridPadding) / _kEmojiCellSize).floor().clamp(1, 20);
                  return GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(_kEmojiGridPadding),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: emojis.length,
                    itemBuilder: (context, index) {
                      return _EmojiCell(
                        emoji: emojis[index],
                        onEmojiSelected: _onEmojiTap,
                        onSkinToneLongPress: _showSkinTone,
                      );
                    },
                  );
                },
              ),
            ),
            _EmojiCategoryBar(
              activeIndex: _activeCategory,
              onCategoryChanged: _selectCategory,
              hasRecent: _recentEmojis.isNotEmpty,
            ),
          ],
        ),
        if (_skinToneTarget != null) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissSkinTone,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          _buildSkinTonePopup(context),
        ],
      ],
    );
  }

  Widget _buildSkinTonePopup(BuildContext context) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return const SizedBox.shrink();

    final localAnchor = stackBox.globalToLocal(_skinToneAnchorGlobal);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFFFFFFF);
    final sepColor = isDark ? const Color(0xFF2d3d4d) : const Color(0xFFdadada);

    final base = _getBaseEmoji(_skinToneTarget!);
    final variants = <String>[
      base,
      for (var i = 1; i <= 5; i++) _applySkinTone(base, i),
    ];

    const cs = _kEmojiCellSize;
    const sep = _kEmojiColorsSep;
    const gap = _kEmojiColorsPadding;
    const pad = _kPopupPad;
    final popupW = pad * 2 + cs + sep + 5 * cs + 4 * gap;
    const popupH = pad * 2 + cs;

    final stackSize = stackBox.size;
    final left = (localAnchor.dx + _skinToneAnchorSize.width / 2 - popupW / 2)
        .clamp(4.0, stackSize.width - popupW - 4);
    final top = (localAnchor.dy - popupH - 4).clamp(4.0, double.infinity);
    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        elevation: 4,
        shadowColor: isDark
            ? const Color(0x80000000)
            : const Color(0x40000000),
        child: SizedBox(
          width: popupW,
          height: popupH,
          child: Padding(
            padding: const EdgeInsets.all(pad),
            child: Row(
              children: [
                _PopupEmojiCell(
                  emoji: variants[0],
                  onTap: () => _onSkinToneSelected(variants[0], 0),
                ),
                Container(
                  width: sep,
                  height: cs * 0.6,
                  color: sepColor,
                ),
                for (var i = 1; i <= 5; i++) ...[
                  if (i > 1) SizedBox(width: gap),
                  _PopupEmojiCell(
                    emoji: variants[i],
                    onTap: () => _onSkinToneSelected(variants[i], i),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiCell extends StatefulWidget {
  final String emoji;
  final ValueChanged<String> onEmojiSelected;
  final void Function(String emoji, Offset globalPos, Size size)? onSkinToneLongPress;

  const _EmojiCell({
    required this.emoji,
    required this.onEmojiSelected,
    this.onSkinToneLongPress,
  });

  @override
  State<_EmojiCell> createState() => _EmojiCellState();
}

class _EmojiCellState extends State<_EmojiCell> {
  bool _hovered = false;

  String get _shownEmoji => _displayEmoji(widget.emoji);

  void _handleLongPress() {
    if (!_supportsSkinTone(widget.emoji)) return;
    final box = context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    widget.onSkinToneLongPress?.call(widget.emoji, pos, box.size);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark
        ? const Color(0xFF202b36)
        : const Color(0xFFf0f0f0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onEmojiSelected(_shownEmoji),
        onLongPress: _supportsSkinTone(widget.emoji) ? _handleLongPress : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            _shownEmoji,
            style: const TextStyle(fontSize: 26),
          ),
        ),
      ),
    );
  }
}

class _PopupEmojiCell extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _PopupEmojiCell({super.key, required this.emoji, required this.onTap});

  @override
  State<_PopupEmojiCell> createState() => _PopupEmojiCellState();
}

class _PopupEmojiCellState extends State<_PopupEmojiCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark
        ? const Color(0xFF2b3d4f)
        : const Color(0xFFf0f0f0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: _kEmojiCellSize,
          height: _kEmojiCellSize,
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 26),
          ),
        ),
      ),
    );
  }
}

class _EmojiCategoryBar extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onCategoryChanged;
  final bool hasRecent;

  const _EmojiCategoryBar({
    required this.activeIndex,
    required this.onCategoryChanged,
    required this.hasRecent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);
    final inactiveColor = isDark
        ? const Color(0xFF7e8b93)
        : const Color(0xFF999999);
    final borderColor = isDark
        ? const Color(0xFF1e2c3a)
        : const Color(0xFFe8e8e8);

    return Container(
      height: _kCategoryBarHeight,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: Row(
        children: List.generate(_emojiCategories.length, (i) {
          final cat = _emojiCategories[i];
          final isActive = i == activeIndex;
          final isDisabled = i == 0 && !hasRecent;

          return Expanded(
            child: GestureDetector(
              onTap: isDisabled ? null : () => onCategoryChanged(i),
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isActive ? activeBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    cat.icon,
                    size: 20,
                    color: isActive
                        ? Colors.white
                        : isDisabled
                            ? inactiveColor.withValues(alpha: 0.4)
                            : inactiveColor,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
