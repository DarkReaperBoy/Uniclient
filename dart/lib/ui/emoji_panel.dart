import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../data/emoji_data.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import 'gesture_utils.dart';
import 'package:uniclient/utils/debug.dart';

const double _kPanelWidth = 345.0;
const double _kPanelMinHeight = 278.0;
const double _kPanelMaxHeight = 640.0;
const double _kPanelMargin = 10.0;
const double _kPanelRadius = 8.0;
const double _kHeightRatio = 0.75;
const Duration _kShowDuration = Duration(milliseconds: 200);
const Duration _kHideTimeout = Duration(milliseconds: 300);
const Duration _kDelayedHideTimeout = Duration(milliseconds: 3000);

const double _kEmojiCellSize = 40.0;
const double _kSkinToneCellSize = 30.0;
const double _kEmojiGridPadding = 8.0;
const double _kCategoryBarHeight = 36.0;
const double _kEmojiColorsPadding = 8.0;
const double _kEmojiColorsSep = 1.0;
const double _kPopupPad = 10.0;
const double _kEmojiColorAllSkip = 9.0; // AyuGram emojiPanColorAllSkip

Map<String, int> _skinTonePrefs = {};
bool _emojiPrefsLoaded = false;
String _emojiPrefsConfigDir = '';

void resetEmojiPrefsForAccountSwitch() {
  _emojiPrefsLoaded = false;
  _skinTonePrefs = {};
  _recentEmojis = [];
  _emojiPrefsConfigDir = '';
}

/// Loads emoji skin-tone preferences and wires them into the keyword-suggestion
/// engine so inline emoji suggestions render with the user's chosen tone
/// (mirrors AyuGram `EmojiKeywords::ApplyVariants`). Idempotent for the same
/// config dir; safe to call at startup.
void initEmojiSuggestionVariants(String configDir) {
  _loadEmojiPrefs(configDir);
}

void _loadEmojiPrefs(String configDir) {
  // Keep inline emoji suggestions in sync with the chosen skin tone — the resolver
  // reads the live _skinTonePrefs, so later selections take effect immediately.
  EmojiKeywords.instance.skinToneResolver = _displayEmoji;
  if (_emojiPrefsLoaded && _emojiPrefsConfigDir == configDir) return;
  if (_emojiPrefsLoaded && _emojiPrefsConfigDir != configDir) {
    _skinTonePrefs = {};
    _recentEmojis = [];
  }
  _emojiPrefsLoaded = true;
  _emojiPrefsConfigDir = configDir;
  if (configDir.isEmpty) return;
  try {
    final file = File('$configDir/emoji_prefs.json');
    if (!file.existsSync()) return;
    final data = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    if (data['recentEmojis'] is List) {
      _recentEmojis = (data['recentEmojis'] as List).cast<String>().toList();
    }
    if (data['skinTonePrefs'] is Map) {
      _skinTonePrefs = (data['skinTonePrefs'] as Map).map(
        (k, v) => MapEntry(k.toString(), v is int ? v : 0),
      );
    }
  } catch (e) {
    Debug.log('emoji_panel', 'final file = File(\'\$configDir/emoji_prefs.json\'): $e');
  }
}

void _saveEmojiPrefs() {
  if (_emojiPrefsConfigDir.isEmpty) return;
  try {
    File('$_emojiPrefsConfigDir/emoji_prefs.json').writeAsStringSync(json.encode({
      'recentEmojis': _recentEmojis,
      'skinTonePrefs': _skinTonePrefs,
    }));
  } catch (e) {
    Debug.log('emoji_panel', 'File(\'\$_emojiPrefsConfigDir/emoji_prefs.json\').writeAsStr...: $e');
  }
}

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
  // Mirror AyuGram Settings::lookupEmojiVariant (core_settings.cpp:1509): the
  // per-emoji choice wins, otherwise the apply-to-all variant (empty-string
  // key, written by saveAllEmojiVariants) applies.
  final pref = _skinTonePrefs[key] ?? _skinTonePrefs[''];
  if (pref != null && pref > 0) return _applySkinTone(emoji, pref);
  return emoji;
}

/// Mirrors AyuGram Settings::hasChosenEmojiVariant (core_settings.cpp:1523): a
/// variant counts as "chosen" if an apply-to-all tone exists (empty-string key)
/// or this specific emoji has a recorded tone (including index 0 = default).
bool _hasChosenEmojiVariant(String emoji) {
  return _skinTonePrefs.containsKey('') ||
      _skinTonePrefs.containsKey(_emojiPrefKey(emoji));
}

/// Mirrors AyuGram Settings::saveAllEmojiVariants (core_settings.cpp:1535):
/// clears every per-emoji tone and records a single apply-to-all tone under the
/// empty-string key so every variant-capable emoji recolors at once.
void _saveAllEmojiVariants(int toneIndex) {
  _skinTonePrefs.clear();
  _skinTonePrefs[''] = toneIndex;
  _saveEmojiPrefs();
}

class _EmptySearchPanel extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _EmptySearchPanel({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconCenter = constraints.maxHeight / 3;
        return Column(
          children: [
            SizedBox(height: (iconCenter - 24).clamp(0, double.infinity)),
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(fontSize: 13, color: color)),
          ],
        );
      },
    );
  }
}

class _EmptyGifPanel extends StatelessWidget {
  final String text;
  final Color color;

  const _EmptyGifPanel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final regionHeight = constraints.maxHeight * 2 / 3 + 13;
        return SizedBox(
          height: regionHeight,
          child: Center(
            child: Text(text, style: TextStyle(fontSize: 13, color: color)),
          ),
        );
      },
    );
  }
}

enum StickerSendMode { normal, silent, schedule }

class EmojiTabbedPanel extends StatefulWidget {
  final bool visible;
  final VoidCallback onHide;
  final ValueChanged<String>? onEmojiSelected;
  final void Function(int documentId, String altText)? onCustomEmojiSelected;
  final void Function(String stickerId, {StickerSendMode mode})? onStickerSend;
  final void Function(String gifFileId, {StickerSendMode mode, String caption})? onGifSend;
  final void Function(int queryId, String resultId)? onInlineResultSend;
  final bool emojiOnly;
  final bool suppressStickerSets;

  const EmojiTabbedPanel({
    super.key,
    required this.visible,
    required this.onHide,
    this.onEmojiSelected,
    this.onCustomEmojiSelected,
    this.onStickerSend,
    this.onGifSend,
    this.onInlineResultSend,
    this.emojiOnly = false,
    this.suppressStickerSets = false,
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
  bool _contextMenuOpen = false;
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

  void _onContextMenuToggle(bool open) {
    _contextMenuOpen = open;
    if (open) {
      _cancelHideTimer();
    }
  }

  void _startHideTimer() {
    _cancelHideTimer();
    final timeout = _contextMenuOpen ? _kDelayedHideTimeout : _kHideTimeout;
    _hideTimer = Timer(timeout, () {
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
        final translateY = (1.0 - t) * 16.0;

        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, translateY),
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
                    width: _kPanelWidth,
                    height: contentHeight,
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
                          if (!widget.emojiOnly)
                            _TabBar(
                              activeTab: _activeTab,
                              onTabChanged: _switchTab,
                            ),
                          Expanded(
                            child: _TabContent(
                              activeTab: widget.emojiOnly ? 0 : _activeTab,
                              prevTab: widget.emojiOnly ? 0 : _prevTab,
                              slideController: _tabSlideController,
                              onEmojiSelected: widget.onEmojiSelected,
                              onCustomEmojiSelected: widget.onCustomEmojiSelected,
                              onContextMenuToggle: _onContextMenuToggle,
                              onStickerSend: widget.emojiOnly ? null : widget.onStickerSend,
                              onGifSend: widget.emojiOnly ? null : widget.onGifSend,
                              onInlineResultSend: widget.emojiOnly ? null : widget.onInlineResultSend,
                            ),
                          ),
                        ],
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
  }
}

class _TabBar extends StatelessWidget {
  final int activeTab;
  final ValueChanged<int> onTabChanged;

  const _TabBar({
    required this.activeTab,
    required this.onTabChanged,
  });

  static const _tabIcons = [
    Icons.emoji_emotions_outlined,
    Icons.sticky_note_2_outlined,
    Icons.gif_box_outlined,
  ];

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
        children: List.generate(_tabIcons.length, (i) {
          final isActive = i == activeTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabChanged(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Icon(
                    _tabIcons[i],
                    size: 22,
                    color: isActive ? activeColor : inactiveColor,
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
  final void Function(int documentId, String altText)? onCustomEmojiSelected;
  final ValueChanged<bool>? onContextMenuToggle;
  final void Function(String stickerId, {StickerSendMode mode})? onStickerSend;
  final void Function(String gifFileId, {StickerSendMode mode, String caption})? onGifSend;
  final void Function(int queryId, String resultId)? onInlineResultSend;

  const _TabContent({
    required this.activeTab,
    required this.prevTab,
    required this.slideController,
    this.onEmojiSelected,
    this.onCustomEmojiSelected,
    this.onContextMenuToggle,
    this.onStickerSend,
    this.onGifSend,
    this.onInlineResultSend,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: slideController,
      builder: (context, _) {
        final direction = activeTab > prevTab ? 1.0 : -1.0;
        final slideProgress = slideController.value;
        final animating = slideProgress < 1.0 && activeTab != prevTab;

        return LayoutBuilder(
          builder: (context, constraints) {
            final panelW = constraints.maxWidth;

            return ClipRect(
              child: Stack(
                children: List.generate(3, (i) {
                  final bool isActive = i == activeTab;
                  final bool isPrev = animating && i == prevTab;
                  final bool visible = isActive || isPrev;

                  double dx = 0.0;
                  double opacity = visible ? 1.0 : 0.0;
                  if (animating) {
                    if (isActive) {
                      dx = direction * (1.0 - slideProgress) * panelW;
                      opacity = slideProgress;
                    } else if (isPrev) {
                      dx = -direction * slideProgress * panelW;
                      opacity = 1.0 - slideProgress;
                    }
                  }

                  Widget tab;
                  if (i == 0) {
                    tab = _EmojiTab(onEmojiSelected: onEmojiSelected, onCustomEmojiSelected: onCustomEmojiSelected);
                  } else if (i == 1) {
                    tab = _StickerTab(onStickerSend: onStickerSend, onContextMenuToggle: onContextMenuToggle, visible: isActive);
                  } else {
                    tab = _GifTab(onGifSend: onGifSend, onContextMenuToggle: onContextMenuToggle, onInlineResultSend: onInlineResultSend, visible: isActive);
                  }

                  return Offstage(
                    offstage: !visible,
                    child: TickerMode(
                      enabled: visible,
                      child: Transform.translate(
                        offset: Offset(dx, 0),
                        child: Opacity(
                          opacity: opacity,
                          child: SizedBox(
                            width: panelW,
                            height: constraints.maxHeight,
                            child: tab,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
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
      '🪸', '🐡', '🐠', '🐟', '🐬', '🐳', '🐋', '🦈', '🐊', '🐅',
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
      '💉', '🩸', '🧬', '🦠', '🧫', '🧪', '🌡️', '🧹', '🪠', '🧺',
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

List<String> getRecentEmojisList() => List.unmodifiable(_recentEmojis);

void addRecentEmoji(String emoji) {
  _recentEmojis.remove(emoji);
  _recentEmojis.insert(0, emoji);
  if (_recentEmojis.length > 54) {
    _recentEmojis = _recentEmojis.sublist(0, 54);
  }
  _saveEmojiPrefs();
  // Feed the single global recent list so inline emoji suggestions prioritize
  // emoji used from the panel too (AyuGram updates `recentEmoji()` from every
  // source — emoji_list_widget.cpp:2473).
  EmojiKeywords.instance.recordRecent(emoji);
}

class _EmojiTab extends StatefulWidget {
  final ValueChanged<String>? onEmojiSelected;
  final void Function(int documentId, String altText)? onCustomEmojiSelected;

  const _EmojiTab({this.onEmojiSelected, this.onCustomEmojiSelected});

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
  // When true the picker is in "apply to all emoji" mode (opened from the
  // People-section color button), mirroring AyuGram's OverButton picker
  // (emoji_list_widget.cpp:2505) — it shows the "Choose color for all emoji"
  // label and writes a single apply-to-all tone via saveAllEmojiVariants.
  bool _skinToneAllMode = false;
  List<CustomEmojiSetSummary> _customPacks = [];
  final Set<int> _expandedPacks = {};
  bool _loadedPacks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final configDir = context.read<AppState>().configDir;
      _loadEmojiPrefs(configDir);
      if (_recentEmojis.isNotEmpty && mounted) setState(() {});
      _fetchCustomPacks();
    });
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
    } catch (e) {
      Debug.log('emoji_panel', 'final appState = context.read<AppState>(): $e');
    }
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
    if (_recentEmojis.length > 54) {
      _recentEmojis = _recentEmojis.sublist(0, 54);
    }
    _saveEmojiPrefs();
    // Mirror AyuGram: a panel pick updates the single global recent list, so
    // inline emoji suggestions prioritize it (emoji_list_widget.cpp:2473).
    EmojiKeywords.instance.recordRecent(emoji);
    widget.onEmojiSelected?.call(emoji);
  }

  void _showSkinTone(String emoji, Offset globalPos, Size size) {
    setState(() {
      _skinToneAllMode = false;
      _skinToneTarget = emoji;
      _skinToneAnchorGlobal = globalPos;
      _skinToneAnchorSize = size;
    });
  }

  // Opens the picker in "apply to all" mode anchored to the People-section
  // color button. Uses the hand-wave emoji 👋 (which has skin-tone variants) as
  // the swatch source, matching AyuGram showPicker's OverButton branch
  // (emoji_list_widget.cpp:2506).
  void _showColorAllPicker(Offset globalPos, Size size) {
    setState(() {
      _skinToneAllMode = true;
      _skinToneTarget = '\u{1F44B}';
      _skinToneAnchorGlobal = globalPos;
      _skinToneAnchorSize = size;
    });
  }

  void _dismissSkinTone() {
    if (_skinToneTarget == null) return;
    setState(() {
      _skinToneTarget = null;
      _skinToneAllMode = false;
    });
  }

  // Handles a swatch tap from the picker. In apply-to-all mode it recolors every
  // emoji at once (saveAllEmojiVariants) without sending anything; otherwise it
  // records the per-emoji tone and sends, like AyuGram colorChosen
  // (emoji_list_widget.cpp:2723).
  void _onPickerToneSelected(String emoji, int index) {
    if (_skinToneAllMode) {
      _saveAllEmojiVariants(index);
      _dismissSkinTone();
      setState(() {}); // repaint the grid with the recolored emoji
      return;
    }
    _onSkinToneSelected(emoji, index);
  }

  void _onSkinToneSelected(String emoji, int index) {
    _skinTonePrefs[_emojiPrefKey(_skinToneTarget!)] = index;
    _saveEmojiPrefs();
    _dismissSkinTone();
    _onEmojiTap(emoji);
  }

  Future<void> _installEmojiPack(CustomEmojiSetSummary pack) async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final acc = appState.activeAccount;
    if (acc == null) return;
    final success = await engine.installStickerSet(acc.id, pack.setId, pack.accessHash);
    if (success && mounted) {
      setState(() {
        for (int i = 0; i < _customPacks.length; i++) {
          if (_customPacks[i].setId == pack.setId) {
            _customPacks[i] = CustomEmojiSetSummary(
              setId: pack.setId,
              accessHash: pack.accessHash,
              title: pack.title,
              shortName: pack.shortName,
              count: pack.count,
              installed: true,
              premium: pack.premium,
              stickers: pack.stickers,
            );
          }
        }
      });
    }
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
                      // AyuGram draws the "Choose color for all emoji" button on
                      // the People section header only (hasColorButton ==
                      // index == Section::People) — emoji_list_widget.cpp:2536.
                      if (_activeCategory == 1)
                        SliverToBoxAdapter(child: _buildColorAllHeader(isDark)),
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
          onInstall: () => _installEmojiPack(pack),
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
            (context, index) {
              final sticker = visibleStickers[index];
              return _CustomEmojiCell(
                sticker: sticker,
                onTap: () {
                  final docId = int.tryParse(sticker.fileId) ?? 0;
                  if (docId != 0 && widget.onCustomEmojiSelected != null) {
                    widget.onCustomEmojiSelected!(docId, sticker.emoji);
                  }
                },
              );
            },
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
    final labelColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);

    final base = _getBaseEmoji(_skinToneTarget!);
    final variants = <String>[
      base,
      for (var i = 1; i <= 5; i++) _applySkinTone(base, i),
    ];

    const cs = _kSkinToneCellSize;
    const sep = _kEmojiColorsSep;
    const gap = _kEmojiColorsPadding;
    const pad = _kPopupPad;
    const labelArea = 18.0;
    final allMode = _skinToneAllMode;
    final popupW = pad * 2 + cs + gap + sep + gap + 5 * cs + 4 * gap;
    final popupH = pad * 2 + cs + (allMode ? labelArea : 0.0);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PopupEmojiCell(
          emoji: variants[0],
          onTap: () => _onPickerToneSelected(variants[0], 0),
        ),
        SizedBox(width: gap),
        Container(
          width: sep,
          height: cs * 0.6,
          color: sepColor,
        ),
        SizedBox(width: gap),
        for (var i = 1; i <= 5; i++) ...[
          if (i > 1) SizedBox(width: gap),
          _PopupEmojiCell(
            emoji: variants[i],
            onTap: () => _onPickerToneSelected(variants[i], i),
          ),
        ],
      ],
    );

    final stackSize = stackBox.size;
    final left = (localAnchor.dx + _skinToneAnchorSize.width / 2 - popupW / 2)
        .clamp(4.0, stackSize.width - popupW - 4);
    // Prefer above the anchor; flip below when there isn't room (the People
    // color button sits near the top), mirroring showAt's flip in
    // emoji_list_widget.cpp:2494.
    final topAbove = localAnchor.dy - popupH - 4;
    final top = topAbove >= 4.0
        ? topAbove
        : (localAnchor.dy + _skinToneAnchorSize.height + 4)
            .clamp(4.0, (stackSize.height - popupH - 4).clamp(4.0, double.infinity));
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
            child: allMode
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: labelArea,
                        width: double.infinity,
                        child: Text(
                          'Choose color for all emoji',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: labelColor),
                        ),
                      ),
                      row,
                    ],
                  )
                : row,
          ),
        ),
      ),
    );
  }

  // The People-section apply-to-all color button (AyuGram colorButtonRect /
  // emojiPanColorAll, emoji_list_widget.cpp:2541). Right-aligned on the header,
  // 9px in from the grid edge; opens the picker in "all" mode.
  Widget _buildColorAllHeader(bool isDark) {
    final iconColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF202b36) : const Color(0xFFf0f0f0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kEmojiGridPadding, 6, _kEmojiGridPadding + _kEmojiColorAllSkip, 1,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: _ColorAllButton(
          iconColor: iconColor,
          hoverBg: hoverBg,
          onTapButton: _showColorAllPicker,
        ),
      ),
    );
  }
}

class _ColorAllButton extends StatefulWidget {
  final Color iconColor;
  final Color hoverBg;
  final void Function(Offset globalPos, Size size) onTapButton;

  const _ColorAllButton({
    required this.iconColor,
    required this.hoverBg,
    required this.onTapButton,
  });

  @override
  State<_ColorAllButton> createState() => _ColorAllButtonState();
}

class _ColorAllButtonState extends State<_ColorAllButton> {
  bool _hovered = false;

  void _handleTap() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    widget.onTapButton(box.localToGlobal(Offset.zero), box.size);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Tooltip(
          message: 'Choose color for all emoji',
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hovered ? widget.hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.palette_outlined, size: 18, color: widget.iconColor),
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
  final VoidCallback? onInstall;

  const _CustomPackHeader({
    required this.title,
    required this.installed,
    required this.premium,
    required this.isDark,
    this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final headerColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    final premiumColor = isDark ? const Color(0xFFa882e8) : const Color(0xFF7B5EBF);

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
              onTap: onInstall,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: premium ? premiumColor : accentColor,
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
  final VoidCallback? onTap;

  const _CustomEmojiCell({required this.sticker, this.onTap});

  @override
  State<_CustomEmojiCell> createState() => _CustomEmojiCellState();
}

class _CustomEmojiCellState extends State<_CustomEmojiCell> with SingleTickerProviderStateMixin {
  bool _hovered = false;
  CustomEmojiFileData? _fileData;
  Uint8List? _decompressedLottie;
  AnimationController? _lottieController;
  bool _loadRequested = false;
  Player? _webmPlayer;
  VideoController? _webmVideoController;
  String? _webmFilePath;

  @override
  void initState() {
    super.initState();
    _maybeLoadFile();
  }

  void _maybeLoadFile() {
    if (_loadRequested) return;
    final mime = widget.sticker.mimeType;
    if (mime != 'application/x-tgsticker' && mime != 'video/webm' && mime != 'image/webp') return;
    final docId = int.tryParse(widget.sticker.fileId);
    if (docId == null || docId == 0) return;
    _loadRequested = true;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final acc = appState.activeAccount;
    if (acc == null) return;
    engine.getCustomEmojiFiles(acc.id, [docId]).then((files) {
      if (!mounted) return;
      if (files.containsKey(docId)) {
        final file = files[docId]!;
        _fileData = file;
        if (file.isTgs) {
          try {
            _decompressedLottie = Uint8List.fromList(gzip.decode(file.fileData));
          } catch (e) {
            Debug.log('emoji_panel', '_decompressedLottie = Uint8List.fromList(gzip.decode(file...: $e');
          }
        } else if (file.isWebm) {
          _initWebmPlayer(file, docId);
        }
        setState(() {});
      }
    });
  }

  Future<void> _initWebmPlayer(CustomEmojiFileData file, int docId) async {
    final dir = Directory.systemTemp;
    final path = '${dir.path}/uniclient_cemoji_$docId.webm';
    await File(path).writeAsBytes(file.fileData);
    if (!mounted) return;
    _webmFilePath = path;
    if (_GifPlayerPool.instance.tryAcquire(this, _createWebmPlayer)) {
      _createWebmPlayer();
    }
  }

  void _createWebmPlayer() {
    if (!mounted || _webmFilePath == null) {
      _GifPlayerPool.instance.release(this);
      return;
    }
    _webmPlayer = Player();
    _webmVideoController = VideoController(_webmPlayer!);
    _webmPlayer!.setVolume(0);
    _webmPlayer!.setPlaylistMode(PlaylistMode.loop);
    _webmPlayer!.open(Media(_webmFilePath!));
    if (mounted) setState(() {});
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(
      vsync: this,
      duration: composition.duration,
    );
    _lottieController!.repeat();
  }

  @override
  void dispose() {
    _lottieController?.dispose();
    _webmPlayer?.dispose();
    _webmPlayer = null;
    _webmVideoController = null;
    _GifPlayerPool.instance.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark ? const Color(0xFF202b36) : const Color(0xFFf0f0f0);
    final powerSaving = context.watch<AppState>().powerSaving(AppState.kPowerSavingEmojiStatus);
    const innerSize = _kEmojiCellSize - 8.0;

    Widget child;
    if (_fileData != null && !powerSaving) {
      if (_fileData!.isTgs && _decompressedLottie != null) {
        child = Padding(
          padding: const EdgeInsets.all(4),
          child: Lottie.memory(
            _decompressedLottie!,
            width: innerSize,
            height: innerSize,
            fit: BoxFit.contain,
            controller: _lottieController,
            onLoaded: _onLottieLoaded,
            errorBuilder: (_, __, ___) => _buildThumb(innerSize),
          ),
        );
      } else if (_fileData!.isWebm && _webmVideoController != null) {
        child = Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: innerSize,
            height: innerSize,
            child: Video(
              controller: _webmVideoController!,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            ),
          ),
        );
      } else if (_fileData!.isWebp) {
        child = Padding(
          padding: const EdgeInsets.all(4),
          child: Image.memory(
            _fileData!.fileData,
            width: innerSize,
            height: innerSize,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            cacheWidth: (innerSize * 2).round(),
            errorBuilder: (_, __, ___) => _buildThumb(innerSize),
          ),
        );
      } else {
        child = _buildThumb(innerSize);
      }
    } else {
      child = _buildThumb(innerSize);
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
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
      ),
    );
  }

  Widget _buildThumb(double size) {
    if (widget.sticker.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(widget.sticker.thumbB64);
        return Padding(
          padding: const EdgeInsets.all(4),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            width: size,
            height: size,
            gaplessPlayback: true,
            cacheWidth: (size * 2).round(),
          ),
        );
      } catch (e) {
        Debug.log('emoji_panel', 'final bytes = _decodeStrippedThumbB64(widget.sticker.thum...: $e');
      }
    }
    return _fallbackEmoji();
  }

  Widget _fallbackEmoji() {
    return Text(
      widget.sticker.emoji.isNotEmpty ? widget.sticker.emoji : '?',
      style: const TextStyle(fontSize: 26),
    );
  }

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
  Timer? _skinToneTimer;
  // Set once the color picker has been opened for the current press so the
  // matching tap-up does NOT also send the emoji — mirrors AyuGram, where a
  // press that opens the picker is consumed by it (emoji_list_widget.cpp:2296).
  bool _pickerShownForPress = false;

  String get _shownEmoji => _displayEmoji(widget.emoji);

  @override
  void dispose() {
    _skinToneTimer?.cancel();
    super.dispose();
  }

  void _openPicker() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    widget.onSkinToneLongPress?.call(widget.emoji, pos, box.size);
  }

  // Mirrors AyuGram EmojiListWidget::mousePressEvent (emoji_list_widget.cpp:2296):
  // pressing a variant-capable emoji opens the color picker IMMEDIATELY when no
  // tone has ever been chosen, otherwise it arms a single 500ms kColorPickerDelay
  // timer. The previous port double-delayed (~1s) by stacking a 500ms timer on
  // top of the 500ms long-press recognizer.
  void _handleTapDown() {
    _skinToneTimer?.cancel();
    _pickerShownForPress = false;
    if (!_supportsSkinTone(widget.emoji)) return;
    if (!_hasChosenEmojiVariant(widget.emoji)) {
      _pickerShownForPress = true;
      _openPicker();
    } else {
      _skinToneTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _pickerShownForPress = true;
        _openPicker();
      });
    }
  }

  void _handleTap() {
    _skinToneTimer?.cancel();
    if (_pickerShownForPress) {
      _pickerShownForPress = false;
      return; // the press opened the picker — don't also send the emoji
    }
    widget.onEmojiSelected(_shownEmoji);
  }

  void _handleTapCancel() {
    _skinToneTimer?.cancel();
    _pickerShownForPress = false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark
        ? const Color(0xFF202b36)
        : const Color(0xFFf0f0f0);

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _handleTapDown(),
          onTap: _handleTap,
          onTapCancel: _handleTapCancel,
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
          width: _kSkinToneCellSize,
          height: _kSkinToneCellSize,
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 22),
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
  final void Function(String stickerId, {StickerSendMode mode})? onStickerSend;
  final ValueChanged<bool>? onContextMenuToggle;
  final bool visible;

  const _StickerTab({this.onStickerSend, this.onContextMenuToggle, this.visible = true});

  @override
  State<_StickerTab> createState() => _StickerTabState();
}

class _StickerTabState extends State<_StickerTab> {
  List<StickerPackSummary> _packs = [];
  List<StickerInfoItem> _recentStickers = [];
  // Favorited (starred) stickers — AyuGram's FavedSetId section, shown first
  // (before Recent) in the grid and footer (stickers_list_widget.cpp:2931).
  List<StickerInfoItem> _favedStickers = [];
  List<StickerPackSummary> _featuredPacks = [];
  List<StickerPackSummary> _searchResults = [];
  bool _loaded = false;
  bool _searching = false;
  bool _searchLoading = false;
  String _searchQuery = '';
  int _activePackIndex = 0;
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _footerScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final List<GlobalKey> _sectionKeys = [];
  bool _programmaticScroll = false;
  final Set<int> _viewedFeaturedPacks = {};
  Timer? _searchDebounce;
  static final Map<int, CustomEmojiFileData> _stickerFileCache = {};
  static final Set<int> _stickerFileLoading = {};

  @override
  void initState() {
    super.initState();
    _gridScrollController.addListener(_onGridScroll);
    _searchController.addListener(_onSearchChanged);
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    }
  }

  @override
  void didUpdateWidget(covariant _StickerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible && !_loaded) {
      _loadData();
    }
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
        engine.getFavedStickers(activeAccount.id),
      ]);
      if (mounted) {
        final packs = results[0] as List<StickerPackSummary>;
        final recent = results[1] as List<StickerInfoItem>;
        final featured = results[2] as List<StickerPackSummary>;
        final faved = results[3] as List<StickerInfoItem>;
        _favedStickers = faved;
        _rebuildSectionKeys(recent, packs);
        setState(() {
          _packs = packs;
          _recentStickers = recent;
          _featuredPacks = featured;
          _favedStickers = faved;
          _loaded = true;
          _activePackIndex = 0;
        });
      }
    } catch (e) {
      Debug.log('emoji_panel', 'final appState = context.read<AppState>(): $e');
    }
  }

  void _loadStickerFile(int docId) {
    if (_stickerFileCache.containsKey(docId) || _stickerFileLoading.contains(docId)) return;
    _stickerFileLoading.add(docId);
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final acc = appState.activeAccount;
    if (acc == null) return;
    engine.getStickerFiles(acc.id, [docId]).then((files) {
      _stickerFileLoading.remove(docId);
      if (!mounted) return;
      if (files.containsKey(docId)) {
        setState(() {
          _stickerFileCache[docId] = files[docId]!;
        });
      }
    });
  }

  CustomEmojiFileData? getStickerFile(int docId) => _stickerFileCache[docId];

  void _rebuildSectionKeys(List<StickerInfoItem> recent, List<StickerPackSummary> packs) {
    _sectionKeys.clear();
    final totalSections = (_favedStickers.isNotEmpty ? 1 : 0) +
        (recent.isNotEmpty ? 1 : 0) +
        packs.length;
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
        _searchLoading = false;
        _searchQuery = '';
        _searchResults = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchLoading = true;
    });
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
        _searchLoading = false;
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
      duration: const Duration(milliseconds: 400),
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

  void _showStickerContextMenu(BuildContext context, Offset position, StickerInfoItem sticker, {String? setShortName, bool isCustomEmojiSet = false, bool isRecentSection = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF1e2c3a) : Colors.white;
    final textColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    final dangerColor = isDark ? const Color(0xFFe53935) : const Color(0xFFdd4b39);
    final faveLabel = sticker.isFaved ? 'Unfave' : 'Fave';
    widget.onContextMenuToggle?.call(true);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(value: 'send_silent', child: Text('Send Without Sound', style: TextStyle(fontSize: 13, color: textColor))),
        PopupMenuItem(value: 'schedule', child: Text('Schedule', style: TextStyle(fontSize: 13, color: textColor))),
        PopupMenuItem(value: 'fave', child: Text(faveLabel, style: TextStyle(fontSize: 13, color: textColor))),
        PopupMenuItem(value: 'view_set', child: Text('View Set', style: TextStyle(fontSize: 13, color: textColor))),
        if (isRecentSection)
          PopupMenuItem(value: 'remove_recent', child: Text('Remove from Recent', style: TextStyle(fontSize: 13, color: dangerColor))),
        if (isCustomEmojiSet && setShortName != null && setShortName.isNotEmpty)
          PopupMenuItem(value: 'copy_link', child: Text('Copy Link', style: TextStyle(fontSize: 13, color: textColor))),
      ],
    ).then((value) {
      widget.onContextMenuToggle?.call(false);
      if (value == 'send_silent') {
        widget.onStickerSend?.call(sticker.fileId, mode: StickerSendMode.silent);
      } else if (value == 'schedule') {
        widget.onStickerSend?.call(sticker.fileId, mode: StickerSendMode.schedule);
      } else if (value == 'fave') {
        final engine = context.read<EngineService>();
        final appState = context.read<AppState>();
        final acc = appState.activeAccount;
        if (acc != null && sticker.fileId.isNotEmpty) {
          final id = int.tryParse(sticker.fileId) ?? 0;
          final willUnfave = sticker.isFaved;
          engine.faveSticker(acc.id, id, unfave: willUnfave);
          setState(() {
            _updateStickerFaved(sticker.fileId, !willUnfave);
          });
        }
      } else if (value == 'view_set') {
        String? resolvedName = setShortName;
        if (resolvedName == null || resolvedName.isEmpty) {
          for (final pack in _packs) {
            if (pack.stickers.any((s) => s.fileId == sticker.fileId)) {
              resolvedName = pack.shortName;
              break;
            }
          }
        }
        if (resolvedName != null && resolvedName.isNotEmpty) {
          _viewStickerSet(context, sticker, resolvedName);
        }
      } else if (value == 'remove_recent') {
        final engine = context.read<EngineService>();
        final appState = context.read<AppState>();
        final acc = appState.activeAccount;
        if (acc != null && sticker.fileId.isNotEmpty) {
          final id = int.tryParse(sticker.fileId) ?? 0;
          engine.removeRecentSticker(acc.id, id);
        }
        setState(() {
          _recentStickers.removeWhere((s) => s.fileId == sticker.fileId);
          _rebuildSectionKeys(_recentStickers, _packs);
        });
      } else if (value == 'copy_link' && setShortName != null) {
        final prefix = isCustomEmojiSet ? 'addemoji' : 'addstickers';
        Clipboard.setData(ClipboardData(text: 'https://t.me/$prefix/$setShortName'));
      }
    });
  }

  void _updateStickerFaved(String fileId, bool newFaved) {
    for (int i = 0; i < _recentStickers.length; i++) {
      if (_recentStickers[i].fileId == fileId) {
        _recentStickers[i] = _recentStickers[i].copyWith(isFaved: newFaved);
      }
    }
    for (final pack in _packs) {
      for (int i = 0; i < pack.stickers.length; i++) {
        if (pack.stickers[i].fileId == fileId) {
          pack.stickers[i] = pack.stickers[i].copyWith(isFaved: newFaved);
        }
      }
    }
    // Keep the Faved section live: a newly faved sticker joins it, an unfaved
    // one leaves it. Rebuild section keys so the footer/grid stay aligned.
    final wasFaved = _favedStickers.any((s) => s.fileId == fileId);
    if (newFaved && !wasFaved) {
      StickerInfoItem? src;
      for (final s in _recentStickers) {
        if (s.fileId == fileId) { src = s; break; }
      }
      if (src == null) {
        for (final pack in _packs) {
          for (final s in pack.stickers) {
            if (s.fileId == fileId) { src = s; break; }
          }
          if (src != null) break;
        }
      }
      if (src != null) {
        _favedStickers = [src.copyWith(isFaved: true), ..._favedStickers];
        _rebuildSectionKeys(_recentStickers, _packs);
      }
    } else if (!newFaved && wasFaved) {
      _favedStickers = _favedStickers.where((s) => s.fileId != fileId).toList();
      _rebuildSectionKeys(_recentStickers, _packs);
    }
  }

  void _showStickerPreview(BuildContext context, Offset position, StickerInfoItem sticker) {
    final overlay = Overlay.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF17212b) : Colors.white;
    final docId = int.tryParse(sticker.fileId) ?? 0;
    CustomEmojiFileData? file = _stickerFileCache[docId];

    if (file == null && docId != 0) {
      _loadStickerFile(docId);
    }

    late OverlayEntry entry;
    void updateEntry() {
      final updatedFile = _stickerFileCache[docId];
      if (updatedFile != null && updatedFile != file) {
        file = updatedFile;
        entry.markNeedsBuild();
      }
    }
    entry = OverlayEntry(
      builder: (ctx) => _StickerPreviewOverlay(
        sticker: sticker,
        fileData: _stickerFileCache[docId],
        position: position,
        bg: bg,
        isDark: isDark,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    if (file == null && docId != 0) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (entry.mounted) updateEntry();
      });
    }
  }

  void _viewStickerSet(BuildContext context, StickerInfoItem sticker, String? setShortName) async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final acc = appState.activeAccount;
    if (acc == null) return;
    final setInfo = await engine.getStickerSetInfo(
      acc.id,
      shortName: setShortName ?? '',
    );
    if (setInfo == null || !mounted) return;
    if (!context.mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => _StickerSetDialog(
        setInfo: setInfo,
        isDark: isDark,
        onInstall: () {
          _installPack(StickerPackSummary(
            setId: setInfo.setId,
            accessHash: setInfo.accessHash,
            title: setInfo.title,
            shortName: setInfo.shortName,
            count: setInfo.count,
            animated: setInfo.animated,
            video: setInfo.video,
            thumbB64: '',
            stickers: setInfo.stickers,
            installed: false,
          ));
          Navigator.of(ctx).pop();
        },
        onStickerTap: (fileId) {
          widget.onStickerSend?.call(fileId);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _uninstallPack(StickerPackSummary pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove sticker set'),
        content: Text('Remove "${pack.title}" from your sticker sets?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final activeAccount = appState.activeAccount;
    if (activeAccount == null) return;
    final success = await engine.uninstallStickerSet(activeAccount.id, pack.setId, pack.accessHash);
    if (success && mounted) {
      setState(() {
        _packs.removeWhere((p) => p.setId == pack.setId);
        _rebuildSectionKeys(_recentStickers, _packs);
      });
    }
  }

  // Opens the sticker-set management box from the footer's settings gear
  // (AyuGram StickersBox — stickers_list_widget.cpp:354). Lets the user remove
  // installed sets and add trending ones; the panel reloads on close.
  void _showStickerSettings() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final acc = context.read<AppState>().activeAccount;
    if (acc == null) return;
    final engine = context.read<EngineService>();
    showDialog(
      context: context,
      builder: (ctx) => _ManageStickersDialog(
        accountId: acc.id,
        engine: engine,
        installed: List<StickerPackSummary>.from(_packs),
        featured: List<StickerPackSummary>.from(_featuredPacks),
        isDark: isDark,
      ),
    ).then((_) {
      if (mounted) {
        _loaded = false;
        _loadData();
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
            hasFaved: _favedStickers.isNotEmpty,
            hasRecent: _recentStickers.isNotEmpty,
            activeIndex: _activePackIndex,
            scrollController: _footerScrollController,
            onPackTapped: _scrollToSection,
            onSettings: _showStickerSettings,
            isDark: isDark,
            hasUnreadFeatured: _featuredPacks.any((p) => !p.installed && !_viewedFeaturedPacks.contains(p.setId)),
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
    final labelColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    if (_searchLoading) {
      return Center(
        child: Text('Loading...', style: TextStyle(fontSize: 13, color: labelColor)),
      );
    }
    final packs = _searchQuery.isEmpty ? _featuredPacks : _searchResults;
    if (packs.isEmpty) {
      if (_searchQuery.isEmpty) {
        return Center(
          child: Text('Popular sticker packs', style: TextStyle(fontSize: 13, color: labelColor)),
        );
      }
      return _EmptySearchPanel(
        icon: Icons.sticky_note_2_outlined,
        text: 'No stickers found',
        color: labelColor,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: packs.length,
      itemBuilder: (context, index) {
        final p = packs[index];
        return _FeaturedPackRow(
          pack: p,
          isDark: isDark,
          onAdd: () {
            _viewedFeaturedPacks.add(p.setId);
            _installPack(p);
          },
          unread: !p.installed && !_viewedFeaturedPacks.contains(p.setId),
        );
      },
    );
  }

  Widget _buildGrid(bool isDark) {
    if (_packs.isEmpty && _recentStickers.isEmpty && _favedStickers.isEmpty) {
      if (_featuredPacks.isNotEmpty) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: _featuredPacks.length,
          itemBuilder: (context, index) {
            final p = _featuredPacks[index];
            return _FeaturedPackRow(
              pack: p,
              isDark: isDark,
              onAdd: () {
                _viewedFeaturedPacks.add(p.setId);
                _installPack(p);
              },
              unread: !p.installed && !_viewedFeaturedPacks.contains(p.setId),
            );
          },
        );
      }
      final labelColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
      return _EmptySearchPanel(
        icon: Icons.sticky_note_2_outlined,
        text: 'No stickers installed',
        color: labelColor,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 2 * _kStickerGridPadding;
        final colCount = (availableWidth / _kStickerCellSize).floor().clamp(1, 10);
        final cellSize = availableWidth / colCount;

        final slivers = <Widget>[];
        int sectionIdx = 0;

        // Faved (starred) stickers are AyuGram's first grid section, before
        // Recent (stickers_list_widget.cpp:2931).
        if (_favedStickers.isNotEmpty) {
          slivers.addAll(_buildSectionSlivers(
            key: _sectionKeys.length > sectionIdx ? _sectionKeys[sectionIdx] : null,
            title: 'Favorite',
            stickers: _favedStickers,
            colCount: colCount,
            cellSize: cellSize,
            isDark: isDark,
          ));
          sectionIdx++;
        }

        if (_recentStickers.isNotEmpty) {
          slivers.addAll(_buildSectionSlivers(
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
          slivers.addAll(_buildSectionSlivers(
            key: sectionIdx < _sectionKeys.length ? _sectionKeys[sectionIdx] : null,
            title: pack.title,
            stickers: pack.stickers,
            colCount: colCount,
            cellSize: cellSize,
            isDark: isDark,
            setShortName: pack.shortName,
            pack: pack,
          ));
          sectionIdx++;
        }

        return CustomScrollView(
          controller: _gridScrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: _kStickerGridPadding, vertical: 4),
              sliver: SliverMainAxisGroup(slivers: slivers),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildSectionSlivers({
    Key? key,
    required String title,
    required List<StickerInfoItem> stickers,
    required int colCount,
    required double cellSize,
    required bool isDark,
    String? setShortName,
    bool isCustomEmojiSet = false,
    StickerPackSummary? pack,
  }) {
    final headerColor = isDark ? const Color(0xFF8899a6) : const Color(0xFF666666);
    final removeColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final rowCount = (stickers.length / colCount).ceil();
    final isRecent = title == 'Recent';

    return [
      SliverToBoxAdapter(
        key: key,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4, left: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: headerColor),
                ),
              ),
              if (pack != null)
                GestureDetector(
                  onTap: () => _uninstallPack(pack),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.close, size: 16, color: removeColor),
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, rowIdx) {
            final start = rowIdx * colCount;
            final end = (start + colCount).clamp(0, stickers.length);
            final rowStickers = stickers.sublist(start, end);
            return Row(
              children: [
                for (final s in rowStickers)
                  SizedBox(
                    width: cellSize,
                    height: cellSize,
                    child: _StickerCell(
                      sticker: s,
                      fileData: _stickerFileCache[int.tryParse(s.fileId) ?? 0],
                      onRequestFile: () {
                        final docId = int.tryParse(s.fileId);
                        if (docId != null) _loadStickerFile(docId);
                      },
                      onTap: () {
                        widget.onStickerSend?.call(s.fileId);
                      },
                      onContextMenu: (pos) => _showStickerContextMenu(
                        context, pos, s,
                        setShortName: setShortName,
                        isCustomEmojiSet: isCustomEmojiSet,
                        isRecentSection: isRecent,
                      ),
                      onLongPress: (pos) => _showStickerPreview(context, pos, s),
                    ),
                  ),
                if (rowStickers.length < colCount)
                  SizedBox(width: cellSize * (colCount - rowStickers.length)),
              ],
            );
          },
          childCount: rowCount,
        ),
      ),
    ];
  }
}

class _FeaturedPackRow extends StatefulWidget {
  final StickerPackSummary pack;
  final bool isDark;
  final VoidCallback onAdd;
  final bool unread;

  const _FeaturedPackRow({required this.pack, required this.isDark, required this.onAdd, this.unread = false});

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
          child: Image.memory(bytes, fit: BoxFit.cover, width: 48, height: 48, gaplessPlayback: true, cacheWidth: 96),
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
          child: Image.memory(bytes, fit: BoxFit.cover, width: 48, height: 48, gaplessPlayback: true, cacheWidth: 96),
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
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.unread)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        GestureDetector(
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
                      ],
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
  final void Function(Offset)? onLongPress;
  final CustomEmojiFileData? fileData;
  final VoidCallback? onRequestFile;

  const _StickerCell({
    required this.sticker,
    required this.onTap,
    this.onContextMenu,
    this.onLongPress,
    this.fileData,
    this.onRequestFile,
  });

  @override
  State<_StickerCell> createState() => _StickerCellState();
}

class _StickerCellState extends State<_StickerCell> with SingleTickerProviderStateMixin {
  bool _hovered = false;
  AnimationController? _lottieController;
  Uint8List? _decompressedLottie;
  bool _fileRequested = false;
  Player? _webmPlayer;
  VideoController? _webmVideoController;
  String? _webmFilePath;

  @override
  void initState() {
    super.initState();
    _maybeRequestFile();
  }

  @override
  void didUpdateWidget(_StickerCell old) {
    super.didUpdateWidget(old);
    if (widget.fileData != old.fileData && widget.fileData != null) {
      _prepareAnimatedContent(widget.fileData!);
    }
    _maybeRequestFile();
  }

  void _maybeRequestFile() {
    if (!_fileRequested && widget.fileData == null && widget.onRequestFile != null) {
      final mime = widget.sticker.mimeType;
      if (mime == 'application/x-tgsticker' || mime == 'video/webm') {
        _fileRequested = true;
        widget.onRequestFile!();
      }
    }
  }

  void _prepareAnimatedContent(CustomEmojiFileData file) {
    if (file.isTgs && _decompressedLottie == null) {
      try {
        _decompressedLottie = Uint8List.fromList(gzip.decode(file.fileData));
      } catch (e) {
        Debug.log('emoji_panel', '_decompressedLottie = Uint8List.fromList(gzip.decode(file...: $e');
      }
    }
    if (file.isWebm && _webmPlayer == null) {
      _initWebmPlayer(file);
    }
  }

  Future<void> _initWebmPlayer(CustomEmojiFileData file) async {
    final docId = int.tryParse(widget.sticker.fileId) ?? 0;
    final dir = Directory.systemTemp;
    final path = '${dir.path}/uniclient_sticker_$docId.webm';
    await File(path).writeAsBytes(file.fileData);
    if (!mounted) return;
    _webmFilePath = path;
    if (_GifPlayerPool.instance.tryAcquire(this, _createWebmPlayer)) {
      _createWebmPlayer();
    }
  }

  void _createWebmPlayer() {
    if (!mounted || _webmFilePath == null) {
      _GifPlayerPool.instance.release(this);
      return;
    }
    _webmPlayer = Player();
    _webmVideoController = VideoController(_webmPlayer!);
    _webmPlayer!.setVolume(0);
    _webmPlayer!.setPlaylistMode(PlaylistMode.loop);
    _webmPlayer!.open(Media(_webmFilePath!));
    if (mounted) setState(() {});
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(
      vsync: this,
      duration: composition.duration,
    );
    _lottieController!.repeat();
  }

  @override
  void dispose() {
    _lottieController?.dispose();
    _webmPlayer?.dispose();
    _webmPlayer = null;
    _webmVideoController = null;
    _GifPlayerPool.instance.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark ? const Color(0xFF202b36) : const Color(0xFFf0f0f0);
    final stickerPanelPowerSave = context.watch<AppState>().powerSaving(AppState.kPowerSavingStickersPanel);
    final cellInner = _kStickerCellSize - 8;

    Widget child;
    final file = widget.fileData;
    if (file != null && !stickerPanelPowerSave) {
      if (file.isTgs && _decompressedLottie != null) {
        child = Lottie.memory(
          _decompressedLottie!,
          width: cellInner,
          height: cellInner,
          fit: BoxFit.contain,
          controller: _lottieController,
          onLoaded: _onLottieLoaded,
          errorBuilder: (_, __, ___) => _buildThumb(cellInner),
        );
      } else if (file.isWebm && _webmVideoController != null) {
        child = SizedBox(
          width: cellInner,
          height: cellInner,
          child: Video(
            controller: _webmVideoController!,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
        );
      } else if (file.isWebp) {
        child = Image.memory(
          file.fileData,
          width: cellInner,
          height: cellInner,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheWidth: (cellInner * 2).round(),
          errorBuilder: (_, __, ___) => _buildThumb(cellInner),
        );
      } else {
        child = _buildThumb(cellInner);
      }
    } else {
      child = _buildThumb(cellInner);
    }

    final hoverDuration = stickerPanelPowerSave ? Duration.zero : const Duration(milliseconds: 100);

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: PlatformGestureDetector(
          onTap: widget.onTap,
          onSecondaryTapUp: widget.onContextMenu != null
              ? (details) => widget.onContextMenu!(details.globalPosition)
              : null,
          onLongPressStart: widget.onLongPress != null
              ? (details) => widget.onLongPress!(details.globalPosition)
              : (widget.onContextMenu != null
                  ? (details) => widget.onContextMenu!(details.globalPosition)
                  : null),
          child: AnimatedContainer(
            duration: hoverDuration,
            decoration: BoxDecoration(
              color: _hovered ? hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildThumb(double size) {
    if (widget.sticker.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(widget.sticker.thumbB64);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          width: size,
          height: size,
          gaplessPlayback: true,
          cacheWidth: (size * 2).round(),
        );
      } catch (e) {
        Debug.log('emoji_panel', 'final bytes = _decodeStrippedThumbB64(widget.sticker.thum...: $e');
      }
    }
    return _stickerFallback();
  }

  Widget _stickerFallback() {
    return Text(
      widget.sticker.emoji.isNotEmpty ? widget.sticker.emoji : '\u{1F5BC}',
      style: const TextStyle(fontSize: 32),
    );
  }
}

// Sticker-set management box opened from the footer settings gear. Mirrors
// AyuGram's StickersBox (Installed + Featured/Trending): remove your sets, add
// trending ones. Self-contained so the parent only reloads on close.
class _ManageStickersDialog extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final List<StickerPackSummary> installed;
  final List<StickerPackSummary> featured;
  final bool isDark;

  const _ManageStickersDialog({
    required this.accountId,
    required this.engine,
    required this.installed,
    required this.featured,
    required this.isDark,
  });

  @override
  State<_ManageStickersDialog> createState() => _ManageStickersDialogState();
}

class _ManageStickersDialogState extends State<_ManageStickersDialog> {
  late List<StickerPackSummary> _installed;
  late List<StickerPackSummary> _featured;

  @override
  void initState() {
    super.initState();
    _installed = List<StickerPackSummary>.from(widget.installed);
    _featured = List<StickerPackSummary>.from(widget.featured);
  }

  Future<void> _remove(StickerPackSummary pack) async {
    final ok = await widget.engine.uninstallStickerSet(widget.accountId, pack.setId, pack.accessHash);
    if (ok && mounted) {
      setState(() => _installed.removeWhere((p) => p.setId == pack.setId));
    }
  }

  Future<void> _add(StickerPackSummary pack) async {
    final ok = await widget.engine.installStickerSet(widget.accountId, pack.setId, pack.accessHash);
    if (ok && mounted) {
      setState(() {
        _featured.removeWhere((p) => p.setId == pack.setId);
        if (!_installed.any((p) => p.setId == pack.setId)) _installed.add(pack);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF17212b) : Colors.white;
    final textColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    final labelColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8);
    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Sticker Sets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor))),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: labelColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  if (_installed.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      child: Text('YOUR STICKERS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: labelColor)),
                    ),
                    for (final pack in _installed)
                      _ManageStickerRow(pack: pack, isDark: isDark, installed: true, onAction: () => _remove(pack)),
                  ],
                  if (_featured.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                      child: Text('TRENDING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: labelColor)),
                    ),
                    for (final pack in _featured)
                      _ManageStickerRow(pack: pack, isDark: isDark, installed: false, onAction: () => _add(pack)),
                  ],
                  if (_installed.isEmpty && _featured.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text('No sticker sets', style: TextStyle(fontSize: 13, color: labelColor))),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageStickerRow extends StatelessWidget {
  final StickerPackSummary pack;
  final bool isDark;
  final bool installed;
  final VoidCallback onAction;

  const _ManageStickerRow({
    required this.pack,
    required this.isDark,
    required this.installed,
    required this.onAction,
  });

  Widget _fallbackThumb(Color color) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Icon(Icons.sticky_note_2_outlined, size: 20, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    final subtitleColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    final dangerColor = isDark ? const Color(0xFFe53935) : const Color(0xFFdd4b39);

    Widget thumb;
    if (pack.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(pack.thumbB64);
        thumb = ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(bytes, fit: BoxFit.cover, width: 40, height: 40, gaplessPlayback: true, cacheWidth: 80),
        );
      } catch (_) {
        thumb = _fallbackThumb(subtitleColor);
      }
    } else {
      thumb = _fallbackThumb(subtitleColor);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: installed ? Colors.transparent : accentColor,
                border: installed ? Border.all(color: dangerColor) : null,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                installed ? 'Remove' : 'Add',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: installed ? dangerColor : Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerPackFooter extends StatelessWidget {
  final List<StickerPackSummary> packs;
  final bool hasFaved;
  final bool hasRecent;
  final int activeIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onPackTapped;
  final VoidCallback? onSettings;
  final bool isDark;
  final bool hasUnreadFeatured;

  const _StickerPackFooter({
    required this.packs,
    required this.hasFaved,
    required this.hasRecent,
    required this.activeIndex,
    required this.scrollController,
    required this.onPackTapped,
    this.onSettings,
    required this.isDark,
    this.hasUnreadFeatured = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8);
    final activeBg = isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8);
    final inactiveColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);

    final items = <Widget>[];
    int itemIdx = 0;

    // Faved (starred) section icon — AyuGram fillIcons emits FavedSetId first,
    // before Recent (stickers_list_widget.cpp:2931).
    if (hasFaved) {
      final isActive = activeIndex == itemIdx;
      items.add(_footerIcon(
        index: itemIdx,
        isActive: isActive,
        activeBg: activeBg,
        child: Icon(Icons.star, size: 22, color: isActive ? accentColor : inactiveColor),
      ));
      itemIdx++;
    }

    if (hasRecent) {
      final isActive = activeIndex == itemIdx;
      items.add(_footerIcon(
        index: itemIdx,
        isActive: isActive,
        activeBg: activeBg,
        child: Icon(Icons.access_time, size: 22, color: isActive ? accentColor : inactiveColor),
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
            child: Image.memory(bytes, fit: BoxFit.cover, width: 26, height: 26, gaplessPlayback: true, cacheWidth: 52),
          );
        } catch (_) {
          iconWidget = Icon(Icons.sticky_note_2_outlined, size: 22, color: isActive ? accentColor : inactiveColor);
        }
      } else {
        iconWidget = Icon(Icons.sticky_note_2_outlined, size: 22, color: isActive ? accentColor : inactiveColor);
      }
      items.add(_footerIcon(
        index: itemIdx,
        isActive: isActive,
        activeBg: activeBg,
        child: iconWidget,
        showBadge: itemIdx == 0 && hasUnreadFeatured,
      ));
      itemIdx++;
    }

    return Container(
      height: _kStickerFooterHeight,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          // Settings / manage-sets gear, fixed at the far left — opens the
          // sticker-set management box (stickers_list_footer.cpp:301).
          GestureDetector(
            onTap: onSettings,
            behavior: HitTestBehavior.opaque,
            child: Tooltip(
              message: 'Manage sticker sets',
              waitDuration: const Duration(milliseconds: 400),
              child: SizedBox(
                width: _kStickerFooterHeight,
                height: _kStickerFooterHeight,
                child: Icon(Icons.settings_outlined, size: 22, color: inactiveColor),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (_, _lvI) => items[_lvI],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerIcon({required int index, required bool isActive, required Color activeBg, required Widget child, bool showBadge = false}) {
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
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
        child: showBadge
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  child,
                  Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              )
            : child,
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

// AyuGram's fixed GIF-search fallback (GifSearchEmojiFallback,
// stickers_list_footer.cpp:98), used until the server-driven app-config list
// (gif_search_emojies) resolves and when that key is absent.
const List<String> _kGifSearchEmojiFallback = [
  '👍', '😘', '😍', '😡', '🥳', '😂', '😮', '🙄', '😎', '👎',
];

class _GifTab extends StatefulWidget {
  final void Function(String gifFileId, {StickerSendMode mode, String caption})? onGifSend;
  final ValueChanged<bool>? onContextMenuToggle;
  final void Function(int queryId, String resultId)? onInlineResultSend;
  final bool visible;

  const _GifTab({this.onGifSend, this.onContextMenuToggle, this.onInlineResultSend, this.visible = true});

  @override
  State<_GifTab> createState() => _GifTabState();
}

class _GifTabState extends State<_GifTab> {
  List<GifInfoItem> _gifs = [];
  bool _loaded = false;
  bool _searching = false;
  String _searchQuery = '';
  List<InlineBotResult> _searchResults = [];
  int _lastQueryId = 0;
  String _nextOffset = '';
  bool _loadingMore = false;
  int _activeCategoryIndex = -1;
  // Server-driven GIF-search category emoji (app-config gif_search_emojies),
  // initialized to AyuGram's fallback until the engine resolves the live list.
  List<String> _gifCategoryEmojis = _kGifSearchEmojiFallback;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String? _gifBotId;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadData();
        _resolveGifBot();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _GifTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      if (!_loaded) _loadData();
      _resolveGifBot();
    }
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
    } catch (e) {
      Debug.log('emoji_panel', 'final gifs = await engine.getSavedGifs(activeAccount.id): $e');
    }
    // Resolve the server-driven GIF-search category row (gif_search_emojies);
    // the engine applies AyuGram's fallback when the app-config key is absent.
    try {
      final emojies = await engine.getGifSearchEmojies(activeAccount.id);
      if (mounted && emojies.isNotEmpty) {
        setState(() => _gifCategoryEmojis = emojies);
      }
    } catch (e) {
      Debug.log('emoji_panel', 'getGifSearchEmojies: $e');
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
        _lastQueryId = 0;
        _nextOffset = '';
        _loadingMore = false;
        _activeCategoryIndex = -1;
      });
      return;
    }
    if (_activeCategoryIndex < 0 || (_activeCategoryIndex < _gifCategoryEmojis.length && query != _gifCategoryEmojis[_activeCategoryIndex])) {
      setState(() { _activeCategoryIndex = -1; });
    }
    if (_gifBotId != null) {
      setState(() => _searching = true);
    }
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
    if (index >= _gifCategoryEmojis.length) return;
    final emoji = _gifCategoryEmojis[index];
    _activeCategoryIndex = index;
    _searchController.text = emoji;
    _searchController.selection = TextSelection.collapsed(offset: emoji.length);
  }

  Future<void> _resolveGifBot() async {
    if (_gifBotId != null) return;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final activeAccount = appState.activeAccount;
    if (activeAccount == null) return;
    final username = appState.config.gifSearchUsername;
    final resolved = await engine.resolveUsername(activeAccount.id, username);
    if (resolved != null && mounted) {
      _gifBotId = resolved;
    }
  }

  Future<void> _performSearch(String query, {String offset = ''}) async {
    if (!mounted) return;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final activeAccount = appState.activeAccount;
    if (activeAccount == null) return;
    if (_gifBotId == null) {
      await _resolveGifBot();
      if (_gifBotId == null || !mounted) return;
    }
    if (mounted && !_searching && offset.isEmpty) {
      setState(() => _searching = true);
    }
    final results = await engine.getInlineBotResults(
      activeAccount.id, _gifBotId!, query, offset: offset,
    );
    if (results != null && mounted && _searchController.text.trim() == query) {
      setState(() {
        _searchQuery = query;
        _lastQueryId = results.queryId;
        _nextOffset = results.nextOffset;
        if (offset.isNotEmpty) {
          _searchResults = [..._searchResults, ...results.results];
        } else {
          _searchResults = results.results;
        }
        _searching = true;
        _loadingMore = false;
      });
    }
  }

  void _onGifTap(String fileId) {
    widget.onGifSend?.call(fileId);
  }

  void _onSearchResultTap(InlineBotResult result) {
    if (_lastQueryId != 0 && widget.onInlineResultSend != null) {
      widget.onInlineResultSend!(_lastQueryId, result.id);
    }
  }

  void _loadMoreSearchResults() {
    if (_loadingMore || _nextOffset.isEmpty || _searchQuery.isEmpty) return;
    _loadingMore = true;
    _performSearch(_searchQuery, offset: _nextOffset);
  }

  void _onSavedGifContextMenu(GifInfoItem gif, Offset globalPos) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    final dangerColor = isDark ? const Color(0xFFe53935) : const Color(0xFFdd4b39);
    final menuBg = isDark ? const Color(0xFF1e2c3a) : Colors.white;
    widget.onContextMenuToggle?.call(true);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      color: menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(value: 'send_silent', child: Text('Send Without Sound', style: TextStyle(fontSize: 13, color: textColor))),
        PopupMenuItem(value: 'schedule', child: Text('Schedule', style: TextStyle(fontSize: 13, color: textColor))),
        // AyuGram includes lng_send_gif_with_caption between schedule and
        // add/delete in the saved-GIF menu — gifs_list_widget.cpp:430.
        PopupMenuItem(value: 'send_caption', child: Text('Send GIF with caption', style: TextStyle(fontSize: 13, color: textColor))),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete GIF', style: TextStyle(fontSize: 13, color: dangerColor)),
        ),
      ],
    );
    widget.onContextMenuToggle?.call(false);
    if (result == 'send_silent' && mounted) {
      widget.onGifSend?.call(gif.fileId, mode: StickerSendMode.silent);
    } else if (result == 'schedule' && mounted) {
      widget.onGifSend?.call(gif.fileId, mode: StickerSendMode.schedule);
    } else if (result == 'send_caption' && mounted) {
      final caption = await _promptGifCaption();
      if (caption != null && caption.isNotEmpty && mounted) {
        widget.onGifSend?.call(gif.fileId, caption: caption);
      }
    } else if (result == 'delete' && mounted) {
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

  // Prompts for a caption to attach to the GIF, mirroring AyuGram's
  // SendGifWithCaptionBox. Returns the text, or null if cancelled.
  Future<String?> _promptGifCaption() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF17212b) : Colors.white;
    final textColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    final accent = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    final controller = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        title: Text('Send GIF with caption', style: TextStyle(fontSize: 16, color: textColor)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          style: TextStyle(fontSize: 14, color: textColor),
          decoration: InputDecoration(
            hintText: 'Add a caption...',
            hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: textColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text('Send', style: TextStyle(color: accent)),
          ),
        ],
      ),
    );
    controller.dispose();
    return caption;
  }

  void _onSearchResultContextMenu(InlineBotResult result, Offset globalPos) async {
    if (result.documentId == 0) return;
    widget.onContextMenuToggle?.call(true);
    final menuResult = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      items: [
        const PopupMenuItem(value: 'save', child: Text('Save GIF')),
      ],
    );
    widget.onContextMenuToggle?.call(false);
    if (menuResult == 'save' && mounted) {
      final appState = context.read<AppState>();
      final engine = context.read<EngineService>();
      final activeAccount = appState.activeAccount;
      if (activeAccount == null) return;
      await engine.saveGif(activeAccount.id, result.documentId, extra: result.documentExtra);
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
          emojis: _gifCategoryEmojis,
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
      return _EmptyGifPanel(text: 'You have no saved GIFs yet.', color: color);
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
      if (_searchQuery.isNotEmpty) {
        return _EmptyGifPanel(text: 'No results.', color: color);
      }
      return const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 200) {
          _loadMoreSearchResults();
        }
        return false;
      },
      child: LayoutBuilder(
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
            itemCount: rows.length + (_nextOffset.isNotEmpty ? 1 : 0),
            itemBuilder: (context, rowIdx) {
              if (rowIdx >= rows.length) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
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
                            onTap: () => _onSearchResultTap(row.items[i].inlineResult!),
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
      ),
    );
  }
}

class _GifCategoryFooter extends StatelessWidget {
  final List<String> emojis;
  final int activeIndex;
  final ValueChanged<int> onCategoryTap;
  final bool isDark;

  const _GifCategoryFooter({
    required this.emojis,
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
        itemCount: emojis.length + 1,
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
                emojis[catIdx],
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

class _GifPlayerPool {
  static const int maxConcurrent = 4;
  static final _GifPlayerPool instance = _GifPlayerPool._();
  _GifPlayerPool._();

  final Set<Object> _active = {};
  final List<(Object, VoidCallback)> _waiting = [];

  bool tryAcquire(Object owner, VoidCallback onReady) {
    if (_active.length < maxConcurrent) {
      _active.add(owner);
      return true;
    }
    _waiting.add((owner, onReady));
    return false;
  }

  void release(Object owner) {
    final wasActive = _active.remove(owner);
    _waiting.removeWhere((e) => e.$1 == owner);
    if (wasActive) {
      while (_waiting.isNotEmpty && _active.length < maxConcurrent) {
        final (next, callback) = _waiting.removeAt(0);
        _active.add(next);
        callback();
      }
    }
  }
}

class _GifCell extends StatefulWidget {
  final GifInfoItem gif;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  const _GifCell({required this.gif, required this.onTap, required this.onContextMenu});

  @override
  State<_GifCell> createState() => _GifCellState();
}

class _GifCellState extends State<_GifCell> {
  Player? _player;
  VideoController? _videoController;
  String? _filePath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadGif();
  }

  Future<void> _loadGif() async {
    final fileId = widget.gif.fileId;
    if (fileId.isEmpty) return;
    final docId = int.tryParse(fileId);
    if (docId == null) return;

    final cached = _gifFileCache[docId];
    if (cached != null) {
      _filePath = cached;
      _requestPlayer();
      return;
    }

    setState(() => _loading = true);
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final files = await engine.getGifFiles(accountId, [docId]);
    if (!mounted) return;
    final data = files[docId];
    if (data == null || data.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final dir = Directory.systemTemp;
    final path = '${dir.path}/uniclient_gif_$docId.mp4';
    await File(path).writeAsBytes(data);
    _gifFileCacheSet(docId, path);
    if (!mounted) return;
    _filePath = path;
    _requestPlayer();
  }

  void _requestPlayer() {
    if (_filePath == null) return;
    if (_GifPlayerPool.instance.tryAcquire(this, _createPlayer)) {
      _createPlayer();
    }
  }

  void _createPlayer() {
    if (!mounted || _filePath == null) {
      _GifPlayerPool.instance.release(this);
      return;
    }
    _player = Player();
    _videoController = VideoController(_player!);
    _player!.setVolume(0);
    _player!.setPlaylistMode(PlaylistMode.loop);
    _player!.open(Media(_filePath!));
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _player?.dispose();
    _player = null;
    _videoController = null;
    _GifPlayerPool.instance.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget content;
    if (_videoController != null && _filePath != null) {
      content = Video(
        controller: _videoController!,
        controls: NoVideoControls,
        fit: BoxFit.cover,
      );
    } else if (widget.gif.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(widget.gif.thumbB64);
        content = Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 200),
            if (_loading)
              const Center(child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))),
          ],
        );
      } catch (_) {
        content = _gifPlaceholder(isDark);
      }
    } else {
      content = _gifPlaceholder(isDark);
    }
    return PlatformGestureDetector(
      onTap: widget.onTap,
      onSecondaryTapUp: (d) => widget.onContextMenu(d.globalPosition),
      onLongPressStart: (d) => widget.onContextMenu(d.globalPosition),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: content,
      ),
    );
  }
}

const int _kGifFileCacheMax = 200;
final Map<int, String> _gifFileCache = {};

void _gifFileCacheSet(int docId, String path) {
  _gifFileCache[docId] = path;
  if (_gifFileCache.length > _kGifFileCacheMax) {
    final keysToRemove = _gifFileCache.keys
        .take(_gifFileCache.length - _kGifFileCacheMax)
        .toList();
    for (final k in keysToRemove) {
      final old = _gifFileCache.remove(k);
      if (old != null) {
        try { File(old).deleteSync(); } catch (e) {
          Debug.log('emoji_panel', 'File(old).deleteSync(): $e');
        }
      }
    }
  }
}

class _GifSearchCell extends StatefulWidget {
  final InlineBotResult result;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  const _GifSearchCell({required this.result, required this.onTap, required this.onContextMenu});

  @override
  State<_GifSearchCell> createState() => _GifSearchCellState();
}

class _GifSearchCellState extends State<_GifSearchCell> {
  Player? _player;
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    _requestPlayer();
  }

  void _requestPlayer() {
    final url = widget.result.contentUrl;
    if (url.isEmpty) return;
    if (_GifPlayerPool.instance.tryAcquire(this, _createPlayer)) {
      _createPlayer();
    }
  }

  void _createPlayer() {
    if (!mounted) {
      _GifPlayerPool.instance.release(this);
      return;
    }
    final url = widget.result.contentUrl;
    if (url.isEmpty) return;
    _player = Player();
    _videoController = VideoController(_player!);
    _player!.setVolume(0);
    _player!.setPlaylistMode(PlaylistMode.loop);
    _player!.open(Media(url));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player?.dispose();
    _player = null;
    _videoController = null;
    _GifPlayerPool.instance.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget content;
    if (_videoController != null) {
      content = Video(
        controller: _videoController!,
        controls: NoVideoControls,
        fit: BoxFit.cover,
      );
    } else if (widget.result.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(widget.result.thumbB64);
        content = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 200);
      } catch (_) {
        content = _gifPlaceholder(isDark);
      }
    } else {
      content = _gifPlaceholder(isDark);
    }
    return PlatformGestureDetector(
      onTap: widget.onTap,
      onSecondaryTapUp: (d) => widget.onContextMenu(d.globalPosition),
      onLongPressStart: (d) => widget.onContextMenu(d.globalPosition),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: content,
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

class _StickerPreviewOverlay extends StatefulWidget {
  final StickerInfoItem sticker;
  final CustomEmojiFileData? fileData;
  final Offset position;
  final Color bg;
  final bool isDark;
  final VoidCallback onDismiss;

  const _StickerPreviewOverlay({
    required this.sticker,
    this.fileData,
    required this.position,
    required this.bg,
    required this.isDark,
    required this.onDismiss,
  });

  @override
  State<_StickerPreviewOverlay> createState() => _StickerPreviewOverlayState();
}

class _StickerPreviewOverlayState extends State<_StickerPreviewOverlay> with SingleTickerProviderStateMixin {
  AnimationController? _lottieController;
  Uint8List? _decompressedLottie;
  Player? _webmPlayer;
  VideoController? _webmVideoController;

  @override
  void initState() {
    super.initState();
    if (widget.fileData != null && widget.fileData!.isTgs) {
      try {
        _decompressedLottie = Uint8List.fromList(gzip.decode(widget.fileData!.fileData));
      } catch (e) {
        Debug.log('emoji_panel', '_decompressedLottie = Uint8List.fromList(gzip.decode(widg...: $e');
      }
    } else if (widget.fileData != null && widget.fileData!.isWebm) {
      _initWebmPlayer(widget.fileData!);
    }
  }

  Future<void> _initWebmPlayer(CustomEmojiFileData file) async {
    final docId = int.tryParse(widget.sticker.fileId) ?? 0;
    final dir = Directory.systemTemp;
    final path = '${dir.path}/uniclient_preview_$docId.webm';
    await File(path).writeAsBytes(file.fileData);
    if (!mounted) return;
    _webmPlayer = Player();
    _webmVideoController = VideoController(_webmPlayer!);
    _webmPlayer!.setVolume(0);
    _webmPlayer!.setPlaylistMode(PlaylistMode.loop);
    _webmPlayer!.open(Media(path));
    if (mounted) setState(() {});
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(
      vsync: this,
      duration: composition.duration,
    );
    _lottieController!.repeat();
  }

  @override
  void dispose() {
    _lottieController?.dispose();
    _webmPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const previewSize = 200.0;
    final screenSize = MediaQuery.sizeOf(context);
    final left = (widget.position.dx - previewSize / 2).clamp(8.0, screenSize.width - previewSize - 8);
    final top = (widget.position.dy - previewSize - 20).clamp(8.0, screenSize.height - previewSize - 8);

    Widget content;
    final file = widget.fileData;
    if (file != null && file.isTgs && _decompressedLottie != null) {
      content = Lottie.memory(
        _decompressedLottie!,
        width: previewSize - 24,
        height: previewSize - 24,
        fit: BoxFit.contain,
        controller: _lottieController,
        onLoaded: _onLottieLoaded,
      );
    } else if (file != null && file.isWebm && _webmVideoController != null) {
      content = SizedBox(
        width: previewSize - 24,
        height: previewSize - 24,
        child: Video(
          controller: _webmVideoController!,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
      );
    } else if (file != null && file.isWebp) {
      content = Image.memory(
        file.fileData,
        width: previewSize - 24,
        height: previewSize - 24,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else if (widget.sticker.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(widget.sticker.thumbB64);
        content = Image.memory(
          bytes,
          width: previewSize - 24,
          height: previewSize - 24,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      } catch (_) {
        content = Text(
          widget.sticker.emoji.isNotEmpty ? widget.sticker.emoji : '\u{1F5BC}',
          style: const TextStyle(fontSize: 80),
        );
      }
    } else {
      content = Text(
        widget.sticker.emoji.isNotEmpty ? widget.sticker.emoji : '\u{1F5BC}',
        style: const TextStyle(fontSize: 80),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            onPanEnd: (_) => widget.onDismiss(),
            child: Container(color: Colors.black26),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: widget.bg,
            borderRadius: BorderRadius.circular(12),
            elevation: 8,
            child: SizedBox(
              width: previewSize,
              height: previewSize,
              child: Center(child: content),
            ),
          ),
        ),
        Positioned(
          left: left,
          top: top + previewSize + 4,
          child: Material(
            color: widget.bg,
            borderRadius: BorderRadius.circular(8),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                widget.sticker.emoji,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StickerSetDialog extends StatefulWidget {
  final StickerSetInfo setInfo;
  final bool isDark;
  final VoidCallback onInstall;
  final void Function(String fileId) onStickerTap;

  const _StickerSetDialog({
    required this.setInfo,
    required this.isDark,
    required this.onInstall,
    required this.onStickerTap,
  });

  @override
  State<_StickerSetDialog> createState() => _StickerSetDialogState();
}

class _StickerSetDialogState extends State<_StickerSetDialog> {
  final Map<int, CustomEmojiFileData> _fileCache = {};
  final Set<int> _loading = {};

  @override
  void initState() {
    super.initState();
    _loadStickerFiles();
  }

  Future<void> _loadStickerFiles() async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final acc = appState.activeAccount;
    if (acc == null) return;
    final docIds = <int>[];
    for (final s in widget.setInfo.stickers) {
      final id = int.tryParse(s.fileId) ?? 0;
      if (id != 0 && (s.mimeType == 'application/x-tgsticker' || s.mimeType == 'video/webm')) {
        docIds.add(id);
      }
    }
    if (docIds.isEmpty) return;
    _loading.addAll(docIds);
    final files = await engine.getStickerFiles(acc.id, docIds);
    if (!mounted) return;
    setState(() {
      _fileCache.addAll(files);
      _loading.removeAll(docIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF17212b) : Colors.white;
    final titleColor = isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222);
    final subtitleColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.setInfo.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: titleColor)),
                        const SizedBox(height: 2),
                        Text('${widget.setInfo.count} sticker${widget.setInfo.count != 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: subtitleColor)),
                      ],
                    ),
                  ),
                  if (!widget.setInfo.installed)
                    GestureDetector(
                      onTap: widget.onInstall,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(14)),
                        child: const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
                itemCount: widget.setInfo.stickers.length,
                itemBuilder: (context, index) {
                  final s = widget.setInfo.stickers[index];
                  final docId = int.tryParse(s.fileId) ?? 0;
                  final file = _fileCache[docId];
                  return GestureDetector(
                    onTap: () => widget.onStickerTap(s.fileId),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _StickerSetDialogCell(sticker: s, fileData: file),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerSetDialogCell extends StatefulWidget {
  final StickerInfoItem sticker;
  final CustomEmojiFileData? fileData;

  const _StickerSetDialogCell({required this.sticker, this.fileData});

  @override
  State<_StickerSetDialogCell> createState() => _StickerSetDialogCellState();
}

class _StickerSetDialogCellState extends State<_StickerSetDialogCell> with SingleTickerProviderStateMixin {
  AnimationController? _lottieController;
  Uint8List? _decompressedLottie;
  Player? _webmPlayer;
  VideoController? _webmVideoController;
  String? _webmFilePath;

  @override
  void initState() {
    super.initState();
    _prepareContent();
  }

  @override
  void didUpdateWidget(_StickerSetDialogCell old) {
    super.didUpdateWidget(old);
    if (widget.fileData != old.fileData && widget.fileData != null) {
      _prepareContent();
    }
  }

  void _prepareContent() {
    final file = widget.fileData;
    if (file == null) return;
    if (file.isTgs && _decompressedLottie == null) {
      try {
        _decompressedLottie = Uint8List.fromList(gzip.decode(file.fileData));
        if (mounted) setState(() {});
      } catch (e) {
        Debug.log('emoji_panel', '_decompressedLottie = Uint8List.fromList(gzip.decode(file...: $e');
      }
    } else if (file.isWebm && _webmPlayer == null) {
      _initWebmPlayer(file);
    }
  }

  Future<void> _initWebmPlayer(CustomEmojiFileData file) async {
    final docId = int.tryParse(widget.sticker.fileId) ?? 0;
    final dir = Directory.systemTemp;
    final path = '${dir.path}/uniclient_setdlg_$docId.webm';
    await File(path).writeAsBytes(file.fileData);
    if (!mounted) return;
    _webmFilePath = path;
    if (_GifPlayerPool.instance.tryAcquire(this, _createWebmPlayer)) {
      _createWebmPlayer();
    }
  }

  void _createWebmPlayer() {
    if (!mounted || _webmFilePath == null) {
      _GifPlayerPool.instance.release(this);
      return;
    }
    _webmPlayer = Player();
    _webmVideoController = VideoController(_webmPlayer!);
    _webmPlayer!.setVolume(0);
    _webmPlayer!.setPlaylistMode(PlaylistMode.loop);
    _webmPlayer!.open(Media(_webmFilePath!));
    if (mounted) setState(() {});
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(vsync: this, duration: composition.duration);
    _lottieController!.repeat();
  }

  @override
  void dispose() {
    _lottieController?.dispose();
    _webmPlayer?.dispose();
    _webmPlayer = null;
    _webmVideoController = null;
    _GifPlayerPool.instance.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.fileData;
    if (file != null && file.isTgs && _decompressedLottie != null) {
      return Lottie.memory(
        _decompressedLottie!,
        fit: BoxFit.contain,
        controller: _lottieController,
        onLoaded: _onLottieLoaded,
        errorBuilder: (_, __, ___) => _buildThumb(),
      );
    }
    if (file != null && file.isWebm && _webmVideoController != null) {
      return Video(
        controller: _webmVideoController!,
        controls: NoVideoControls,
        fit: BoxFit.contain,
      );
    }
    if (file != null && file.isWebp) {
      return Image.memory(file.fileData, fit: BoxFit.contain, gaplessPlayback: true, cacheWidth: 120);
    }
    return _buildThumb();
  }

  Widget _buildThumb() {
    if (widget.sticker.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumbB64(widget.sticker.thumbB64);
        return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true, cacheWidth: 120);
      } catch (e) {
        Debug.log('emoji_panel', 'final bytes = _decodeStrippedThumbB64(widget.sticker.thum...: $e');
      }
    }
    return Text(widget.sticker.emoji.isNotEmpty ? widget.sticker.emoji : '?', style: const TextStyle(fontSize: 28));
  }
}
