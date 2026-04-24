import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';

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

Uint8List _decodeStrippedThumbB64(String b64) {
  final stripped = base64Decode(b64);
  if (stripped.length < 3 || stripped[0] != 0x01) return stripped;
  final w = stripped[1];
  final h = stripped[2];
  final tmpl = Uint8List.fromList([
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
    0x00, 0x28, 0x1C, 0x1E, 0x23, 0x1E, 0x19, 0x28, 0x23, 0x21, 0x23, 0x2D,
    0x2B, 0x28, 0x30, 0x3C, 0x64, 0x41, 0x3C, 0x37, 0x37, 0x3C, 0x7B, 0x58,
    0x5D, 0x49, 0x64, 0x91, 0x80, 0x99, 0x96, 0x8F, 0x80, 0x8C, 0x8A, 0xA0,
    0xB4, 0xE6, 0xC3, 0xA0, 0xAA, 0xDA, 0xAD, 0x8A, 0x8C, 0xC8, 0xFF, 0xCB,
    0xDA, 0xEE, 0xF5, 0xFF, 0xFF, 0xFF, 0x9B, 0xC1, 0xFF, 0xFF, 0xFF, 0xFA,
    0xFF, 0xE6, 0xFD, 0xFF, 0xF8, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x2B, 0x2D,
    0x2D, 0x3C, 0x35, 0x3C, 0x76, 0x41, 0x41, 0x76, 0xF8, 0xA5, 0x8C, 0xA5,
    0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
    0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
    0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
    0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
    0xF8, 0xF8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x00, 0x00, 0x00, 0x03,
    0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00,
    0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
    0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00,
    0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00,
    0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21,
    0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81,
    0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24,
    0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25,
    0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A,
    0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56,
    0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A,
    0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86,
    0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99,
    0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3,
  ]);
  tmpl[164] = h;
  tmpl[166] = w;
  const footer = [0xFF, 0xD9];
  final buf = Uint8List(tmpl.length + stripped.length - 3 + footer.length);
  buf.setAll(0, tmpl);
  buf.setAll(tmpl.length, stripped.sublist(3));
  buf.setAll(tmpl.length + stripped.length - 3, footer);
  return buf;
}

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_powerSaveSkipAnim) {
          _showController.value = 1.0;
        } else {
          _showController.forward();
        }
      });
    }
  }

  bool get _powerSaveSkipAnim {
    final appState = context.read<AppState>();
    return appState.powerSaving(AppState.kPowerSavingEmojiPanel);
  }

  @override
  void didUpdateWidget(covariant EmojiTabbedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _cancelHideTimer();
      if (_powerSaveSkipAnim) {
        _showController.value = 1.0;
      } else {
        _showController.forward();
      }
    } else if (!widget.visible && oldWidget.visible) {
      if (_powerSaveSkipAnim) {
        _showController.value = 0.0;
      } else {
        _showController.reverse();
      }
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

  Widget _buildTabWidget(int index, Color placeholderColor) {
    if (index == 0) return _EmojiTab(onEmojiSelected: onEmojiSelected);
    if (index == 1) return _StickerTab(onStickerSelected: onEmojiSelected);
    return _GifTab(onGifSelected: onEmojiSelected);
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
          return _buildTabWidget(activeTab, placeholderColor);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final panelW = constraints.maxWidth;
            Widget prevWidget = _buildTabWidget(prevTab, placeholderColor);
            Widget activeWidget = _buildTabWidget(activeTab, placeholderColor);

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
  List<CustomEmojiSetSummary> _customPacks = [];
  final Set<int> _expandedPacks = {};
  bool _loadedPacks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCustomPacks());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomPacks() async {
    if (_loadedPacks) return;
    try {
      final appState = context.read<AppState>();
      final engine = context.read<EngineService>();
      final activeAccount = appState.activeAccount;
      if (activeAccount == null) return;
      final packs = await engine.getInstalledEmojiSets(activeAccount.id);
      if (mounted) {
        setState(() {
          _customPacks = packs;
          _loadedPacks = true;
        });
      }
    } catch (_) {}
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

  void _togglePackExpanded(int setId) {
    setState(() {
      if (_expandedPacks.contains(setId)) {
        _expandedPacks.remove(setId);
      } else {
        _expandedPacks.add(setId);
      }
    });
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
                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(_kEmojiGridPadding),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            childAspectRatio: 1.0,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _EmojiCell(
                              emoji: emojis[index],
                              onEmojiSelected: _onEmojiTap,
                              onSkinToneLongPress: _showSkinTone,
                            ),
                            childCount: emojis.length,
                          ),
                        ),
                      ),
                      for (final pack in _customPacks)
                        ..._buildPackSection(pack, columns, isDark),
                    ],
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

  List<Widget> _buildPackSection(CustomEmojiSetSummary pack, int columns, bool isDark) {
    final isExpanded = _expandedPacks.contains(pack.setId);
    final maxCollapsedItems = columns * 3;
    final stickers = pack.stickers;
    final showCollapsed = !isExpanded && stickers.length > maxCollapsedItems;
    final visibleStickers = showCollapsed ? stickers.sublist(0, maxCollapsedItems) : stickers;
    final hiddenCount = stickers.length - maxCollapsedItems;

    return [
      SliverToBoxAdapter(
        child: _CustomPackHeader(
          title: pack.title,
          installed: pack.installed,
          premium: pack.premium,
          isDark: isDark,
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: _kEmojiGridPadding),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 1.0,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _CustomEmojiCell(sticker: visibleStickers[index]),
            childCount: visibleStickers.length,
          ),
        ),
      ),
      if (showCollapsed && hiddenCount > 0)
        SliverToBoxAdapter(
          child: _OverflowBadge(
            count: hiddenCount,
            isDark: isDark,
            onTap: () => _togglePackExpanded(pack.setId),
          ),
        ),
    ];
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

class _CustomPackHeader extends StatelessWidget {
  final String title;
  final bool installed;
  final bool premium;
  final bool isDark;

  const _CustomPackHeader({
    required this.title,
    required this.installed,
    required this.premium,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final headerColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kEmojiGridPadding, 12, _kEmojiGridPadding, 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: headerColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!installed)
            GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: premium
                      ? const Color(0xFF7B68EE)
                      : accentColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  premium ? 'Unlock' : 'Add',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomEmojiCell extends StatefulWidget {
  final StickerInfoItem sticker;

  const _CustomEmojiCell({required this.sticker});

  @override
  State<_CustomEmojiCell> createState() => _CustomEmojiCellState();
}

class _CustomEmojiCellState extends State<_CustomEmojiCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark ? const Color(0xFF202b36) : const Color(0xFFf0f0f0);

    Widget child;
    if (widget.sticker.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumb(widget.sticker.thumbB64);
        child = Padding(
          padding: const EdgeInsets.all(4),
          child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
        );
      } catch (_) {
        child = _fallbackEmoji();
      }
    } else {
      child = _fallbackEmoji();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: _hovered ? hoverBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _fallbackEmoji() {
    return Text(
      widget.sticker.emoji.isNotEmpty ? widget.sticker.emoji : '?',
      style: const TextStyle(fontSize: 26),
    );
  }

  static Uint8List _decodeStrippedThumb(String b64) => _decodeStrippedThumbB64(b64);

  static Uint8List _jpegHeader(int w, int h) {
    final tmpl = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x28, 0x1C, 0x1E, 0x23, 0x1E, 0x19, 0x28, 0x23, 0x21, 0x23, 0x2D,
      0x2B, 0x28, 0x30, 0x3C, 0x64, 0x41, 0x3C, 0x37, 0x37, 0x3C, 0x7B, 0x58,
      0x5D, 0x49, 0x64, 0x91, 0x80, 0x99, 0x96, 0x8F, 0x80, 0x8C, 0x8A, 0xA0,
      0xB4, 0xE6, 0xC3, 0xA0, 0xAA, 0xDA, 0xAD, 0x8A, 0x8C, 0xC8, 0xFF, 0xCB,
      0xDA, 0xEE, 0xF5, 0xFF, 0xFF, 0xFF, 0x9B, 0xC1, 0xFF, 0xFF, 0xFF, 0xFA,
      0xFF, 0xE6, 0xFD, 0xFF, 0xF8, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x2B, 0x2D,
      0x2D, 0x3C, 0x35, 0x3C, 0x76, 0x41, 0x41, 0x76, 0xF8, 0xA5, 0x8C, 0xA5,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x00, 0x00, 0x00, 0x03,
      0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00,
      0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
      0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00,
      0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00,
      0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21,
      0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81,
      0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24,
      0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25,
      0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A,
      0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56,
      0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A,
      0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86,
      0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99,
      0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3,
    ]);
    tmpl[164] = h;
    tmpl[166] = w;
    return tmpl;
  }
}

class _OverflowBadge extends StatelessWidget {
  final int count;
  final bool isDark;
  final VoidCallback onTap;

  const _OverflowBadge({
    required this.count,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '+$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
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

const double _kStickerCellSize = 64.0;
const double _kStickerGridPadding = 11.0;
const double _kStickerFooterHeight = 44.0;
const int _kVisibleIconsCount = 8;
const Duration _kSearchDebounce = Duration(milliseconds: 400);

class _StickerTab extends StatefulWidget {
  final ValueChanged<String>? onStickerSelected;

  const _StickerTab({this.onStickerSelected});

  @override
  State<_StickerTab> createState() => _StickerTabState();
}

class _StickerTabState extends State<_StickerTab> {
  List<StickerPackSummary> _packs = [];
  List<StickerInfoItem> _recentStickers = [];
  List<StickerPackSummary> _featuredPacks = [];
  List<StickerPackSummary> _searchResults = [];
  bool _loaded = false;
  bool _searching = false;
  String _searchQuery = '';
  int _activePackIndex = 0;
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _footerScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final List<GlobalKey> _sectionKeys = [];
  bool _programmaticScroll = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _gridScrollController.addListener(_onGridScroll);
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _gridScrollController.removeListener(_onGridScroll);
    _gridScrollController.dispose();
    _footerScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_loaded) return;
    try {
      final appState = context.read<AppState>();
      final engine = context.read<EngineService>();
      final activeAccount = appState.activeAccount;
      if (activeAccount == null) return;
      final results = await Future.wait([
        engine.getInstalledStickerPacks(activeAccount.id),
        engine.getRecentStickers(activeAccount.id),
        engine.getFeaturedStickerPacks(activeAccount.id),
      ]);
      if (mounted) {
        final packs = results[0] as List<StickerPackSummary>;
        final recent = results[1] as List<StickerInfoItem>;
        final featured = results[2] as List<StickerPackSummary>;
        _rebuildSectionKeys(recent, packs);
        setState(() {
          _packs = packs;
          _recentStickers = recent;
          _featuredPacks = featured;
          _loaded = true;
          _activePackIndex = 0;
        });
      }
    } catch (_) {}
  }

  void _rebuildSectionKeys(List<StickerInfoItem> recent, List<StickerPackSummary> packs) {
    _sectionKeys.clear();
    final totalSections = (recent.isNotEmpty ? 1 : 0) + packs.length;
    for (int i = 0; i < totalSections; i++) {
      _sectionKeys.add(GlobalKey());
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _searchQuery = '';
        _searchResults = [];
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(_kSearchDebounce, () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final activeAccount = appState.activeAccount;
    if (activeAccount == null) return;
    final results = await engine.searchStickerSets(activeAccount.id, query);
    if (mounted && _searchController.text.trim() == query) {
      setState(() {
        _searchQuery = query;
        _searchResults = results;
      });
    }
  }

  Future<void> _installPack(StickerPackSummary pack) async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final activeAccount = appState.activeAccount;
    if (activeAccount == null) return;
    final success = await engine.installStickerSet(activeAccount.id, pack.setId, pack.accessHash);
    if (success && mounted) {
      setState(() {
        for (int i = 0; i < _featuredPacks.length; i++) {
          if (_featuredPacks[i].setId == pack.setId) {
            _featuredPacks[i] = StickerPackSummary(
              setId: pack.setId, accessHash: pack.accessHash,
              title: pack.title, shortName: pack.shortName,
              count: pack.count, animated: pack.animated, video: pack.video,
              thumbB64: pack.thumbB64, stickers: pack.stickers, installed: true,
            );
          }
        }
        for (int i = 0; i < _searchResults.length; i++) {
          if (_searchResults[i].setId == pack.setId) {
            _searchResults[i] = StickerPackSummary(
              setId: pack.setId, accessHash: pack.accessHash,
              title: pack.title, shortName: pack.shortName,
              count: pack.count, animated: pack.animated, video: pack.video,
              thumbB64: pack.thumbB64, stickers: pack.stickers, installed: true,
            );
          }
        }
      });
      _loaded = false;
      _loadData();
    }
  }

  void _onGridScroll() {
    if (_programmaticScroll || !_loaded || _searching) return;
    int bestIndex = 0;
    double bestDistance = double.infinity;
    for (int i = 0; i < _sectionKeys.length; i++) {
      final keyContext = _sectionKeys[i].currentContext;
      if (keyContext == null) continue;
      final box = keyContext.findRenderObject() as RenderBox;
      final pos = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
      final dist = pos.dy.abs();
      if (dist < bestDistance) {
        bestDistance = dist;
        bestIndex = i;
      }
    }
    if (bestIndex != _activePackIndex) {
      setState(() => _activePackIndex = bestIndex);
      _scrollFooterToIndex(bestIndex);
    }
  }

  void _scrollFooterToIndex(int index) {
    if (!_footerScrollController.hasClients) return;
    final iconWidth = _kStickerFooterHeight;
    final targetOffset = (index * iconWidth - _footerScrollController.position.viewportDimension / 2 + iconWidth / 2)
        .clamp(0.0, _footerScrollController.position.maxScrollExtent);
    _footerScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToSection(int index) {
    if (index < 0 || index >= _sectionKeys.length) return;
    setState(() => _activePackIndex = index);
    _scrollFooterToIndex(index);
    final keyContext = _sectionKeys[index].currentContext;
    if (keyContext == null) return;
    _programmaticScroll = true;
    Scrollable.ensureVisible(
      keyContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    ).then((_) {
      _programmaticScroll = false;
    });
  }

  void _showStickerContextMenu(BuildContext context, Offset position, StickerInfoItem sticker) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF1e2c3a) : Colors.white;
    final textColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(value: 'fave', child: Text('Fave', style: TextStyle(fontSize: 13, color: textColor))),
        PopupMenuItem(value: 'view_set', child: Text('View Set', style: TextStyle(fontSize: 13, color: textColor))),
      ],
    ).then((value) {
      if (value == 'fave') {
        final engine = context.read<EngineService>();
        final appState = context.read<AppState>();
        final acc = appState.activeAccount;
        if (acc != null && sticker.fileId.isNotEmpty) {
          final id = int.tryParse(sticker.fileId) ?? 0;
          engine.faveSticker(acc.id, id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_loaded) {
      return Center(
        child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd)),
        ),
      );
    }

    return Column(
      children: [
        _buildSearchBar(isDark),
        Expanded(child: _searching ? _buildSearchResults(isDark) : _buildGrid(isDark)),
        if (!_searching)
          _StickerPackFooter(
            packs: _packs,
            hasRecent: _recentStickers.isNotEmpty,
            activeIndex: _activePackIndex,
            scrollController: _footerScrollController,
            onPackTapped: _scrollToSection,
            isDark: isDark,
          ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    final bgColor = isDark ? const Color(0xFF242f3d) : const Color(0xFFefeff4);
    final textColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    final hintColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: SizedBox(
        height: 32,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(fontSize: 13, color: textColor),
          decoration: InputDecoration(
            hintText: 'Search stickers',
            hintStyle: TextStyle(fontSize: 13, color: hintColor),
            prefixIcon: Icon(Icons.search, size: 18, color: hintColor),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                    },
                    child: Icon(Icons.close, size: 16, color: hintColor),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(minWidth: 32),
            filled: true,
            fillColor: bgColor,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    final packs = _searchQuery.isEmpty ? _featuredPacks : _searchResults;
    if (packs.isEmpty) {
      final msg = _searchQuery.isEmpty ? 'Popular sticker packs' : 'No results for "$_searchQuery"';
      return Center(
        child: Text(msg, style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: packs.length,
      itemBuilder: (context, index) => _FeaturedPackRow(
        pack: packs[index],
        isDark: isDark,
        onAdd: () => _installPack(packs[index]),
      ),
    );
  }

  Widget _buildGrid(bool isDark) {
    if (_packs.isEmpty && _recentStickers.isEmpty) {
      if (_featuredPacks.isNotEmpty) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: _featuredPacks.length,
          itemBuilder: (context, index) => _FeaturedPackRow(
            pack: _featuredPacks[index],
            isDark: isDark,
            onAdd: () => _installPack(_featuredPacks[index]),
          ),
        );
      }
      return Center(
        child: Text(
          'No stickers installed',
          style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 2 * _kStickerGridPadding;
        final colCount = (availableWidth / _kStickerCellSize).floor().clamp(1, 10);
        final cellSize = availableWidth / colCount;

        final sections = <Widget>[];
        int sectionIdx = 0;

        if (_recentStickers.isNotEmpty) {
          sections.add(_buildSection(
            key: _sectionKeys.length > sectionIdx ? _sectionKeys[sectionIdx] : null,
            title: 'Recent',
            stickers: _recentStickers,
            colCount: colCount,
            cellSize: cellSize,
            isDark: isDark,
          ));
          sectionIdx++;
        }

        for (final pack in _packs) {
          sections.add(_buildSection(
            key: sectionIdx < _sectionKeys.length ? _sectionKeys[sectionIdx] : null,
            title: pack.title,
            stickers: pack.stickers,
            colCount: colCount,
            cellSize: cellSize,
            isDark: isDark,
          ));
          sectionIdx++;
        }

        return ListView(
          controller: _gridScrollController,
          padding: const EdgeInsets.symmetric(horizontal: _kStickerGridPadding, vertical: 4),
          children: sections,
        );
      },
    );
  }

  Widget _buildSection({
    Key? key,
    required String title,
    required List<StickerInfoItem> stickers,
    required int colCount,
    required double cellSize,
    required bool isDark,
  }) {
    final headerColor = isDark ? const Color(0xFF8899a6) : const Color(0xFF666666);
    final rows = <Widget>[];
    for (int i = 0; i < stickers.length; i += colCount) {
      final end = (i + colCount).clamp(0, stickers.length);
      final rowStickers = stickers.sublist(i, end);
      rows.add(Row(
        children: [
          for (final s in rowStickers)
            SizedBox(
              width: cellSize,
              height: cellSize,
              child: _StickerCell(
                sticker: s,
                onTap: () {
                  widget.onStickerSelected?.call(s.emoji.isNotEmpty ? s.emoji : s.fileId);
                },
                onContextMenu: (pos) => _showStickerContextMenu(context, pos, s),
              ),
            ),
          if (rowStickers.length < colCount)
            SizedBox(width: cellSize * (colCount - rowStickers.length)),
        ],
      ));
    }

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4, left: 2),
          child: Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: headerColor),
          ),
        ),
        ...rows,
      ],
    );
  }
}

class _FeaturedPackRow extends StatefulWidget {
  final StickerPackSummary pack;
  final bool isDark;
  final VoidCallback onAdd;

  const _FeaturedPackRow({required this.pack, required this.isDark, required this.onAdd});

  @override
  State<_FeaturedPackRow> createState() => _FeaturedPackRowState();
}

class _FeaturedPackRowState extends State<_FeaturedPackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final isDark = widget.isDark;
    final hoverBg = isDark ? const Color(0xFF202b36) : const Color(0xFFf4f4f4);
    final titleColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    final subtitleColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);

    Widget thumb;
    if (pack.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(pack.thumbB64);
        thumb = ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(bytes, fit: BoxFit.cover, width: 48, height: 48, gaplessPlayback: true),
        );
      } catch (_) {
        thumb = Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8), borderRadius: BorderRadius.circular(6)),
          child: Icon(Icons.sticky_note_2_outlined, size: 24, color: subtitleColor),
        );
      }
    } else if (pack.stickers.isNotEmpty && pack.stickers.first.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(pack.stickers.first.thumbB64);
        thumb = ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(bytes, fit: BoxFit.cover, width: 48, height: 48, gaplessPlayback: true),
        );
      } catch (_) {
        thumb = Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8), borderRadius: BorderRadius.circular(6)),
          child: Icon(Icons.sticky_note_2_outlined, size: 24, color: subtitleColor),
        );
      }
    } else {
      thumb = Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8), borderRadius: BorderRadius.circular(6)),
        child: Icon(Icons.sticky_note_2_outlined, size: 24, color: subtitleColor),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _hovered ? hoverBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            thumb,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: titleColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${pack.count} sticker${pack.count != 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: subtitleColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 26,
              child: pack.installed
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8)),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Text('Added', style: TextStyle(fontSize: 12, color: subtitleColor)),
                    )
                  : GestureDetector(
                      onTap: widget.onAdd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerCell extends StatefulWidget {
  final StickerInfoItem sticker;
  final VoidCallback onTap;
  final void Function(Offset)? onContextMenu;

  const _StickerCell({required this.sticker, required this.onTap, this.onContextMenu});

  @override
  State<_StickerCell> createState() => _StickerCellState();
}

class _StickerCellState extends State<_StickerCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark ? const Color(0xFF202b36) : const Color(0xFFf0f0f0);

    Widget child;
    if (widget.sticker.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(widget.sticker.thumbB64);
        child = Image.memory(
          bytes,
          fit: BoxFit.contain,
          width: _kStickerCellSize - 8,
          height: _kStickerCellSize - 8,
          gaplessPlayback: true,
        );
      } catch (_) {
        child = _stickerFallback();
      }
    } else {
      child = _stickerFallback();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onContextMenu != null
            ? (details) => widget.onContextMenu!(details.globalPosition)
            : null,
        onLongPressStart: widget.onContextMenu != null
            ? (details) => widget.onContextMenu!(details.globalPosition)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _stickerFallback() {
    return Text(
      widget.sticker.emoji.isNotEmpty ? widget.sticker.emoji : '🖼',
      style: const TextStyle(fontSize: 32),
    );
  }
}

class _StickerPackFooter extends StatelessWidget {
  final List<StickerPackSummary> packs;
  final bool hasRecent;
  final int activeIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onPackTapped;
  final bool isDark;

  const _StickerPackFooter({
    required this.packs,
    required this.hasRecent,
    required this.activeIndex,
    required this.scrollController,
    required this.onPackTapped,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8);
    final activeBg = isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8);
    final inactiveColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);

    final items = <Widget>[];
    int itemIdx = 0;

    if (hasRecent) {
      final isActive = activeIndex == itemIdx;
      items.add(_footerIcon(
        index: itemIdx,
        isActive: isActive,
        activeBg: activeBg,
        child: Icon(Icons.access_time, size: 22, color: isActive ? (isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd)) : inactiveColor),
      ));
      itemIdx++;
    }

    for (final pack in packs) {
      final isActive = activeIndex == itemIdx;
      Widget iconWidget;
      if (pack.thumbB64.isNotEmpty) {
        try {
          final bytes = _decodeStrippedThumbB64(pack.thumbB64);
          iconWidget = ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(bytes, fit: BoxFit.cover, width: 26, height: 26, gaplessPlayback: true),
          );
        } catch (_) {
          iconWidget = Icon(Icons.sticky_note_2_outlined, size: 22, color: isActive ? (isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd)) : inactiveColor);
        }
      } else {
        iconWidget = Icon(Icons.sticky_note_2_outlined, size: 22, color: isActive ? (isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd)) : inactiveColor);
      }
      items.add(_footerIcon(
        index: itemIdx,
        isActive: isActive,
        activeBg: activeBg,
        child: iconWidget,
      ));
      itemIdx++;
    }

    return Container(
      height: _kStickerFooterHeight,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: ListView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        children: items,
      ),
    );
  }

  Widget _footerIcon({required int index, required bool isActive, required Color activeBg, required Widget child}) {
    return GestureDetector(
      onTap: () => onPackTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _kStickerFooterHeight,
        height: _kStickerFooterHeight,
        decoration: BoxDecoration(
          color: isActive ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: child,
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

const double _kGifPadLeft = 9.0;
const double _kGifPadTop = 5.0;
const double _kGifPadRight = 3.0;
const double _kGifPadBottom = 9.0;
const double _kGifItemSkip = 3.0;
const double _kGifRowBaseHeight = 100.0;
const double _kGifFooterHeight = 44.0;

const List<String> _kGifCategoryEmojis = [
  '😂', '😍', '😘', '❤️', '🥳', '😡',
  '👍', '🤔', '👏', '🙄', '😎', '💃',
  '🐶', '🐱', '🎮', '🏆', '🎄', '⚽',
];

class _GifTab extends StatefulWidget {
  final ValueChanged<String>? onGifSelected;

  const _GifTab({this.onGifSelected});

  @override
  State<_GifTab> createState() => _GifTabState();
}

class _GifTabState extends State<_GifTab> {
  List<GifInfoItem> _gifs = [];
  bool _loaded = false;
  bool _searching = false;
  String _searchQuery = '';
  List<InlineBotResult> _searchResults = [];
  int _activeCategoryIndex = -1; // -1 = saved GIFs (no category active)
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_loaded) return;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final activeAccount = appState.activeAccount;
    if (activeAccount == null) return;
    try {
      final gifs = await engine.getSavedGifs(activeAccount.id);
      if (mounted) {
        setState(() {
          _gifs = gifs;
          _loaded = true;
        });
      }
    } catch (_) {}
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _searchQuery = '';
        _searchResults = [];
        _activeCategoryIndex = -1;
      });
      return;
    }
    if (_activeCategoryIndex < 0 || (_activeCategoryIndex < _kGifCategoryEmojis.length && query != _kGifCategoryEmojis[_activeCategoryIndex])) {
      _activeCategoryIndex = -1;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(_kSearchDebounce, () => _performSearch(query));
  }

  void _onCategoryTap(int index) {
    if (index < 0) {
      _searchController.clear();
      _searchFocusNode.unfocus();
      setState(() {
        _searching = false;
        _searchQuery = '';
        _searchResults = [];
        _activeCategoryIndex = -1;
      });
      return;
    }
    final emoji = _kGifCategoryEmojis[index];
    _activeCategoryIndex = index;
    _searchController.text = emoji;
    _searchController.selection = TextSelection.collapsed(offset: emoji.length);
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final activeAccount = appState.activeAccount;
    if (activeAccount == null) return;
    final results = await engine.getInlineBotResults(
      activeAccount.id, 'gif', query,
    );
    if (results != null && mounted && _searchController.text.trim() == query) {
      setState(() {
        _searchQuery = query;
        _searchResults = results.results;
      });
    }
  }

  void _onGifTap(String fileId) {
    widget.onGifSelected?.call(fileId);
  }

  void _onSavedGifContextMenu(GifInfoItem gif, Offset globalPos) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'Delete GIF',
            style: TextStyle(
              color: isDark ? const Color(0xFFe53935) : const Color(0xFFdd4b39),
            ),
          ),
        ),
      ],
    );
    if (result == 'delete' && mounted) {
      final appState = context.read<AppState>();
      final engine = context.read<EngineService>();
      final activeAccount = appState.activeAccount;
      if (activeAccount == null) return;
      final fileId = int.tryParse(gif.fileId) ?? 0;
      final ok = await engine.saveGif(activeAccount.id, fileId, unsave: true);
      if (ok && mounted) {
        setState(() {
          _gifs.removeWhere((g) => g.fileId == gif.fileId);
        });
      }
    }
  }

  void _onSearchResultContextMenu(InlineBotResult result, Offset globalPos) async {
    final menuResult = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      items: [
        const PopupMenuItem(value: 'save', child: Text('Save GIF')),
      ],
    );
    if (menuResult == 'save' && mounted) {
      final appState = context.read<AppState>();
      final engine = context.read<EngineService>();
      final activeAccount = appState.activeAccount;
      if (activeAccount == null) return;
      final fileId = int.tryParse(result.id) ?? 0;
      await engine.saveGif(activeAccount.id, fileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        _buildSearchBar(isDark),
        Expanded(
          child: _searching
              ? _buildSearchResults(isDark)
              : _buildSavedGifs(isDark),
        ),
        _GifCategoryFooter(
          activeIndex: _activeCategoryIndex,
          onCategoryTap: _onCategoryTap,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    final barBg = isDark ? const Color(0xFF1c2733) : const Color(0xFFe8ecf0);
    final hintColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      child: SizedBox(
        height: 30,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black,
          ),
          decoration: InputDecoration(
            hintText: 'Search GIFs',
            hintStyle: TextStyle(fontSize: 13, color: hintColor),
            prefixIcon: Icon(Icons.search, size: 18, color: hintColor),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                    },
                    child: Icon(Icons.close, size: 16, color: hintColor),
                  )
                : null,
            filled: true,
            fillColor: barBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _buildSavedGifs(bool isDark) {
    if (!_loaded) {
      return const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_gifs.isEmpty) {
      final color = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
      return Center(
        child: Text('No saved GIFs', style: TextStyle(fontSize: 13, color: color)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth - _kGifPadLeft - _kGifPadRight;
        final rows = _packGifRows(_gifs.map((g) => _GifLayoutItem(
          width: g.width > 0 ? g.width : 100,
          height: g.height > 0 ? g.height : 100,
          gif: g,
        )).toList(), availW);
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(
            left: _kGifPadLeft, top: _kGifPadTop,
            right: _kGifPadRight, bottom: _kGifPadBottom,
          ),
          itemCount: rows.length,
          itemBuilder: (context, rowIdx) {
            final row = rows[rowIdx];
            return Padding(
              padding: EdgeInsets.only(bottom: rowIdx < rows.length - 1 ? _kGifItemSkip : 0),
              child: SizedBox(
                height: row.height,
                child: Row(
                  children: [
                    for (int i = 0; i < row.items.length; i++) ...[
                      if (i > 0) const SizedBox(width: _kGifItemSkip),
                      SizedBox(
                        width: row.itemWidths[i],
                        height: row.height,
                        child: _GifCell(
                          gif: row.items[i].gif!,
                          onTap: () => _onGifTap(row.items[i].gif!.fileId),
                          onContextMenu: (pos) => _onSavedGifContextMenu(row.items[i].gif!, pos),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchResults(bool isDark) {
    if (_searchResults.isEmpty) {
      final color = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
      return Center(
        child: _searchQuery.isNotEmpty
            ? Text('No results', style: TextStyle(fontSize: 13, color: color))
            : const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth - _kGifPadLeft - _kGifPadRight;
        final rows = _packGifRows(_searchResults.map((r) => _GifLayoutItem(
          width: r.thumbW > 0 ? r.thumbW : 100,
          height: r.thumbH > 0 ? r.thumbH : 100,
          inlineResult: r,
        )).toList(), availW);
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(
            left: _kGifPadLeft, top: _kGifPadTop,
            right: _kGifPadRight, bottom: _kGifPadBottom,
          ),
          itemCount: rows.length,
          itemBuilder: (context, rowIdx) {
            final row = rows[rowIdx];
            return Padding(
              padding: EdgeInsets.only(bottom: rowIdx < rows.length - 1 ? _kGifItemSkip : 0),
              child: SizedBox(
                height: row.height,
                child: Row(
                  children: [
                    for (int i = 0; i < row.items.length; i++) ...[
                      if (i > 0) const SizedBox(width: _kGifItemSkip),
                      SizedBox(
                        width: row.itemWidths[i],
                        height: row.height,
                        child: _GifSearchCell(
                          result: row.items[i].inlineResult!,
                          onTap: () => _onGifTap(row.items[i].inlineResult!.id),
                          onContextMenu: (pos) => _onSearchResultContextMenu(row.items[i].inlineResult!, pos),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GifCategoryFooter extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onCategoryTap;
  final bool isDark;

  const _GifCategoryFooter({
    required this.activeIndex,
    required this.onCategoryTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8);
    final activeBg = isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8);
    final inactiveColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final activeAccent = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);

    return Container(
      height: _kGifFooterHeight,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _kGifCategoryEmojis.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            final isActive = activeIndex < 0;
            return GestureDetector(
              onTap: () => onCategoryTap(-1),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _kGifFooterHeight,
                height: _kGifFooterHeight,
                decoration: BoxDecoration(
                  color: isActive ? activeBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.access_time, size: 22, color: isActive ? activeAccent : inactiveColor),
              ),
            );
          }
          final catIdx = i - 1;
          final isActive = activeIndex == catIdx;
          return GestureDetector(
            onTap: () => onCategoryTap(catIdx),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _kGifFooterHeight,
              height: _kGifFooterHeight,
              decoration: BoxDecoration(
                color: isActive ? activeBg : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                _kGifCategoryEmojis[catIdx],
                style: const TextStyle(fontSize: 22),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GifLayoutItem {
  final int width;
  final int height;
  final GifInfoItem? gif;
  final InlineBotResult? inlineResult;

  _GifLayoutItem({required this.width, required this.height, this.gif, this.inlineResult});

  double get aspect => width > 0 && height > 0 ? width / height : 1.0;
}

class _GifRow {
  final List<_GifLayoutItem> items;
  final List<double> itemWidths;
  final double height;

  _GifRow({required this.items, required this.itemWidths, required this.height});
}

List<_GifRow> _packGifRows(List<_GifLayoutItem> items, double availableWidth) {
  if (items.isEmpty) return [];
  final rows = <_GifRow>[];
  int i = 0;
  while (i < items.length) {
    final rowItems = <_GifLayoutItem>[];
    double totalAspect = 0;
    int j = i;
    while (j < items.length) {
      final item = items[j];
      final newAspect = totalAspect + item.aspect;
      final gaps = rowItems.length * _kGifItemSkip;
      final rowH = (availableWidth - gaps) / newAspect;
      if (rowItems.isNotEmpty && rowH < _kGifRowBaseHeight * 0.6) break;
      rowItems.add(item);
      totalAspect = newAspect;
      j++;
      if (rowH <= _kGifRowBaseHeight) break;
    }
    if (rowItems.isEmpty) {
      rowItems.add(items[i]);
      totalAspect = items[i].aspect;
      j = i + 1;
    }
    final gaps = (rowItems.length - 1) * _kGifItemSkip;
    final rowH = ((availableWidth - gaps) / totalAspect).clamp(40.0, 200.0);
    final widths = rowItems.map((it) => it.aspect * rowH).toList();
    final widthSum = widths.fold(0.0, (a, b) => a + b) + gaps;
    if (widthSum > 0) {
      final scale = (availableWidth) / widthSum;
      for (int k = 0; k < widths.length; k++) {
        widths[k] *= scale;
      }
    }
    rows.add(_GifRow(items: rowItems, itemWidths: widths, height: rowH));
    i = j;
  }
  return rows;
}

class _GifCell extends StatelessWidget {
  final GifInfoItem gif;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  const _GifCell({required this.gif, required this.onTap, required this.onContextMenu});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget thumb;
    if (gif.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(gif.thumbB64);
        thumb = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {
        thumb = _gifPlaceholder(isDark);
      }
    } else {
      thumb = _gifPlaceholder(isDark);
    }
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      onLongPressStart: (d) => onContextMenu(d.globalPosition),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: thumb,
      ),
    );
  }
}

class _GifSearchCell extends StatelessWidget {
  final InlineBotResult result;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  const _GifSearchCell({required this.result, required this.onTap, required this.onContextMenu});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget thumb;
    if (result.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(result.thumbB64);
        thumb = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {
        thumb = _gifPlaceholder(isDark);
      }
    } else {
      thumb = _gifPlaceholder(isDark);
    }
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      onLongPressStart: (d) => onContextMenu(d.globalPosition),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: thumb,
      ),
    );
  }
}

Widget _gifPlaceholder(bool isDark) {
  return Container(
    color: isDark ? const Color(0xFF1c2733) : const Color(0xFFe8ecf0),
    child: Center(
      child: Icon(
        Icons.gif_box_outlined,
        size: 24,
        color: isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999),
      ),
    ),
  );
}
