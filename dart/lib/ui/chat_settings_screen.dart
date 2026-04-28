import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';
import 'settings_style.dart';
import 'shortcuts_settings_screen.dart';

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _useSystemAccent = false;
  int _selfColorId = -1;
  bool _colorLoaded = false;
  String _fontFamily = 'Inter';
  List<CloudThemeInfo> _cloudThemes = [];
  bool _cloudThemesLoaded = false;
  bool _showAllCloudThemes = false;
  bool _tileBackground = true;
  bool _adaptiveLayout = true;
  bool _largeEmoji = true;
  bool _replaceEmojis = true;
  bool _suggestEmoji = true;
  bool _suggestAnimatedEmoji = true;
  bool _suggestStickersByEmoji = true;
  bool _loopAnimatedStickers = true;
  String get _sendBy => context.read<AppState>().sendBy;
  String _doubleClickAction = 'reply';
  bool _showReplyButton = true;
  bool _showReactionButton = true;
  bool _sensitiveEnabled = false;
  bool _sensitiveCanChange = false;
  bool _sensitiveLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSelfColor();
    _loadCloudThemes();
    _loadContentSettings();
  }

  void _loadSelfColor() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.getSelfColorAndChannel(account.id).then((result) {
      if (!mounted) return;
      setState(() {
        _selfColorId = result.colorId;
        _colorLoaded = true;
      });
    });
  }

  void _loadContentSettings() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.getContentSettings(account.id).then((result) {
      if (!mounted) return;
      setState(() {
        _sensitiveEnabled = result.sensitiveEnabled;
        _sensitiveCanChange = result.sensitiveCanChange;
        _sensitiveLoaded = true;
      });
    });
  }

  void _loadCloudThemes() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.getCloudThemes(account.id).then((themes) {
      if (!mounted) return;
      setState(() {
        _cloudThemes = themes;
        _cloudThemesLoaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = context.watch<AppState>();

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);

    final currentAccent = _parseHexColor(appState.accentColorHex) ?? accentColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Chat Settings',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: subtextColor),
            color: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onSelected: (value) {
              if (value == 'create_theme') {
                _showCreateThemeDialog(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'create_theme',
                child: Row(
                  children: [
                    Icon(Icons.palette, size: 20, color: textColor),
                    const SizedBox(width: 12),
                    Text(
                      'Create New Theme',
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        primary: true,
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 10),
          _ThemeCardRow(
            isDark: isDark,
            currentTheme: appState.themeId,
            accentColor: currentAccent,
            onThemeSelected: (themeId) {
              appState.updateTheme(themeId);
            },
          ),
          const SizedBox(height: 8),
          _AccentColorPalette(
            currentColor: currentAccent,
            isDark: isDark,
            themeId: appState.themeId,
            onColorSelected: (color) {
              final hex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
              appState.updateAccentColor(hex);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22, right: 22, top: 12, bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _useSystemAccent,
                    onChanged: (v) => setState(() => _useSystemAccent = v ?? false),
                    activeColor: accentColor,
                    side: BorderSide(color: subtextColor, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Use system accent color',
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ],
            ),
          ),
          _CloudThemeSection(
            themes: _cloudThemes,
            loaded: _cloudThemesLoaded,
            showAll: _showAllCloudThemes,
            isDark: isDark,
            accentColor: currentAccent,
            onToggleShowAll: () => setState(() => _showAllCloudThemes = !_showAllCloudThemes),
            onThemeSelected: (theme) {
              final targetTheme = theme.isDark ? 'night' : 'day_blue';
              appState.updateTheme(targetTheme);
              if (theme.accentColor != 0) {
                final hex = '#${(theme.accentColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
                appState.updateAccentColor(hex);
              }
            },
            onEditTheme: _cloudThemes.any((t) => t.isCreator) ? () {
              _showCreateThemeDialog(context);
            } : null,
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _YourColorRow(
            colorId: _selfColorId,
            isDark: isDark,
            loaded: _colorLoaded,
            accountId: appState.activeAccount?.id,
            onColorChanged: (newId) => setState(() => _selfColorId = newId),
          ),
          _AutoNightRow(
            isDark: isDark,
            enabled: appState.systemDarkModeEnabled,
            onChanged: (v) => appState.setSystemDarkMode(v),
          ),
          _FontFamilyRow(
            isDark: isDark,
            currentFont: _fontFamily,
            onFontChanged: (f) => setState(() => _fontFamily = f),
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _ChatBackgroundSection(
            isDark: isDark,
            tileBackground: _tileBackground,
            adaptiveLayout: _adaptiveLayout,
            accentColor: currentAccent,
            onTileChanged: (v) => setState(() => _tileBackground = v),
            onAdaptiveChanged: (v) => setState(() => _adaptiveLayout = v),
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _ChatListQuickActionSection(
            isDark: isDark,
            currentAction: appState.swipeAction,
            accentColor: currentAccent,
            onActionChanged: (action) {
              appState.swipeAction = action;
            },
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _StickersEmojiSection(
            isDark: isDark,
            accentColor: currentAccent,
            largeEmoji: _largeEmoji,
            replaceEmojis: _replaceEmojis,
            suggestEmoji: _suggestEmoji,
            suggestAnimatedEmoji: _suggestAnimatedEmoji,
            suggestStickersByEmoji: _suggestStickersByEmoji,
            loopAnimatedStickers: _loopAnimatedStickers,
            onLargeEmojiChanged: (v) => setState(() => _largeEmoji = v),
            onReplaceEmojisChanged: (v) => setState(() => _replaceEmojis = v),
            onSuggestEmojiChanged: (v) => setState(() => _suggestEmoji = v),
            onSuggestAnimatedEmojiChanged: (v) => setState(() => _suggestAnimatedEmoji = v),
            onSuggestStickersByEmojiChanged: (v) => setState(() => _suggestStickersByEmoji = v),
            onLoopAnimatedStickersChanged: (v) => setState(() => _loopAnimatedStickers = v),
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _MessagesSection(
            isDark: isDark,
            accentColor: currentAccent,
            sendBy: _sendBy,
            doubleClickAction: _doubleClickAction,
            showReplyButton: _showReplyButton,
            showReactionButton: _showReactionButton,
            onSendByChanged: (v) {
              context.read<AppState>().sendBy = v;
              setState(() {});
            },
            onDoubleClickActionChanged: (v) => setState(() => _doubleClickAction = v),
            onShowReplyButtonChanged: (v) => setState(() => _showReplyButton = v),
            onShowReactionButtonChanged: (v) => setState(() => _showReactionButton = v),
          ),
          if (_sensitiveLoaded && _sensitiveCanChange) ...[
            const SizedBox(height: 7),
            Container(height: 1, color: dividerColor),
            const SizedBox(height: 7),
            _SensitiveContentSection(
              isDark: isDark,
              accentColor: currentAccent,
              enabled: _sensitiveEnabled,
              onChanged: (v) {
                setState(() => _sensitiveEnabled = v);
                final account = appState.activeAccount;
                if (account != null) {
                  context.read<EngineService>().setContentSettings(account.id, v);
                }
              },
            ),
          ],
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _ShortcutsArchiveSection(isDark: isDark, accentColor: currentAccent),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
        ],
      ),
    );
  }

  void _showCreateThemeDialog(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          'New Theme',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'Theme name',
            hintStyle: TextStyle(
              color: isDark
                  ? const Color(0xFF6C7883)
                  : const Color(0xFF999999),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accentColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accentColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: accentColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: Text('Create', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  static Color? _parseHexColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final v = int.tryParse(hex, radix: 16);
    return v != null ? Color(v) : null;
  }
}

// ── Theme Presets ──

class _ThemePreset {
  final String id;
  final String label;
  final Color background;
  final Color receivedBubble;
  final Color sentBubble;
  final bool isDarkTheme;

  const _ThemePreset({
    required this.id,
    required this.label,
    required this.background,
    required this.receivedBubble,
    required this.sentBubble,
    required this.isDarkTheme,
  });
}

const _themePresets = [
  _ThemePreset(
    id: 'classic_day',
    label: 'Classic',
    background: Color(0xFF9BD494),
    receivedBubble: Color(0xFFFFFFFF),
    sentBubble: Color(0xFFEAFFDC),
    isDarkTheme: false,
  ),
  _ThemePreset(
    id: 'day_blue',
    label: 'Day Blue',
    background: Color(0xFF7EC4EA),
    receivedBubble: Color(0xFFFFFFFF),
    sentBubble: Color(0xFFD7F0FF),
    isDarkTheme: false,
  ),
  _ThemePreset(
    id: 'night',
    label: 'Night',
    background: Color(0xFF485761),
    receivedBubble: Color(0xFF182533),
    sentBubble: Color(0xFF2B5278),
    isDarkTheme: true,
  ),
  _ThemePreset(
    id: 'night_green',
    label: 'Night Green',
    background: Color(0xFF485761),
    receivedBubble: Color(0xFF33393F),
    sentBubble: Color(0xFF2A2F33),
    isDarkTheme: true,
  ),
];

// ── Theme Card Row ──

class _ThemeCardRow extends StatelessWidget {
  final bool isDark;
  final String currentTheme; // 'dark' or 'light'
  final Color accentColor;
  final ValueChanged<String> onThemeSelected;

  const _ThemeCardRow({
    required this.isDark,
    required this.currentTheme,
    required this.accentColor,
    required this.onThemeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: _themePresets.map((preset) {
          final isSelected = (currentTheme == 'dark' && preset.isDarkTheme) ||
              (currentTheme == 'light' && !preset.isDarkTheme);
          final isExactMatch = _isExactMatch(preset);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onThemeSelected(preset.id),
              child: Column(
                children: [
                  _ThemePreviewCard(
                    preset: preset,
                    isSelected: isExactMatch,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    preset.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isExactMatch ? textColor : subtextColor,
                      fontWeight: isExactMatch ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  bool _isExactMatch(_ThemePreset preset) {
    return preset.id == currentTheme;
  }
}

// ── Theme Preview Card (80x92px) ──

class _ThemePreviewCard extends StatelessWidget {
  final _ThemePreset preset;
  final bool isSelected;
  final Color accentColor;

  const _ThemePreviewCard({
    required this.preset,
    required this.isSelected,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 80,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? accentColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          size: const Size(76, 88),
          painter: _ThemePreviewPainter(
            preset: preset,
            accentColor: accentColor,
            isSelected: isSelected,
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewPainter extends CustomPainter {
  final _ThemePreset preset;
  final Color accentColor;
  final bool isSelected;

  _ThemePreviewPainter({
    required this.preset,
    required this.accentColor,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background fill.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = preset.background,
    );

    // Mini chat bubbles — spec: 40x14px, 2px radius, positioned at (6, 8).
    final receivedPaint = Paint()..color = preset.receivedBubble;
    final sentPaint = Paint()..color = preset.sentBubble;

    // Received bubble (left-aligned).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 8, 40, 14),
        const Radius.circular(2),
      ),
      receivedPaint,
    );

    // Sent bubble (right-aligned).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 46, 28, 40, 14),
        const Radius.circular(2),
      ),
      sentPaint,
    );

    // Second received bubble.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 48, 32, 14),
        const Radius.circular(2),
      ),
      receivedPaint,
    );

    // Radio dot at bottom — spec: 12px from preview bottom edge.
    final dotCenterX = size.width / 2;
    final dotCenterY = size.height - 12;
    final dotRadius = 6.0;

    if (isSelected) {
      // Filled accent dot with white inner ring.
      canvas.drawCircle(
        Offset(dotCenterX, dotCenterY),
        dotRadius,
        Paint()..color = accentColor,
      );
      canvas.drawCircle(
        Offset(dotCenterX, dotCenterY),
        3.0,
        Paint()..color = preset.background,
      );
      canvas.drawCircle(
        Offset(dotCenterX, dotCenterY),
        2.0,
        Paint()..color = accentColor,
      );
    } else {
      // Empty ring.
      canvas.drawCircle(
        Offset(dotCenterX, dotCenterY),
        dotRadius,
        Paint()
          ..color = preset.isDarkTheme
              ? const Color(0xFF4A4A4A)
              : const Color(0xFFCCCCCC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ThemePreviewPainter oldDelegate) =>
      oldDelegate.isSelected != isSelected ||
      oldDelegate.accentColor != accentColor;
}

// ── Accent Color Palette ──

// Removed: static _accentColors. Per-theme presets now in TelegramPalette.accentsForTheme().

class _AccentColorPalette extends StatelessWidget {
  final Color currentColor;
  final bool isDark;
  final String themeId;
  final ValueChanged<Color> onColorSelected;

  const _AccentColorPalette({
    required this.currentColor,
    required this.isDark,
    required this.themeId,
    required this.onColorSelected,
  });

  static const _circleSize = 22.0;
  static const _ringWidth = 2.0;
  static const _ringSkip = 2.0;

  @override
  Widget build(BuildContext context) {
    final presets = TelegramPalette.accentsForTheme(themeId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          ...presets.map((color) {
            final selected = _colorsMatch(color, currentColor);
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onColorSelected(color),
                child: _AccentCircle(
                  color: color,
                  selected: selected,
                  size: _circleSize,
                  ringWidth: _ringWidth,
                  ringSkip: _ringSkip,
                ),
              ),
            );
          }),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showHslPicker(context),
            child: _CustomColorButton(
              size: _circleSize,
              isSelected: _isCustomColor(presets),
              currentColor: currentColor,
            ),
          ),
        ],
      ),
    );
  }

  bool _isCustomColor(List<Color> presets) {
    for (final c in presets) {
      if (_colorsMatch(c, currentColor)) return false;
    }
    return true;
  }

  void _showHslPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _HslColorPickerDialog(
        initialColor: currentColor,
        isDark: isDark,
        onColorPicked: onColorSelected,
      ),
    );
  }

  static bool _colorsMatch(Color a, Color b) {
    return (a.r - b.r).abs() < 0.02 &&
        (a.g - b.g).abs() < 0.02 &&
        (a.b - b.b).abs() < 0.02;
  }
}

class _AccentCircle extends StatelessWidget {
  final Color color;
  final bool selected;
  final double size;
  final double ringWidth;
  final double ringSkip;

  const _AccentCircle({
    required this.color,
    required this.selected,
    required this.size,
    required this.ringWidth,
    required this.ringSkip,
  });

  @override
  Widget build(BuildContext context) {
    final outerSize = size + (ringWidth + ringSkip) * 2;
    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: CustomPaint(
        painter: _AccentCirclePainter(
          color: color,
          selected: selected,
          ringWidth: ringWidth,
          ringSkip: ringSkip,
        ),
      ),
    );
  }
}

class _AccentCirclePainter extends CustomPainter {
  final Color color;
  final bool selected;
  final double ringWidth;
  final double ringSkip;

  _AccentCirclePainter({
    required this.color,
    required this.selected,
    required this.ringWidth,
    required this.ringSkip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final innerRadius = (size.width - (ringWidth + ringSkip) * 2) / 2;

    if (selected) {
      canvas.drawCircle(
        center,
        innerRadius + ringSkip + ringWidth / 2,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth,
      );
    }

    canvas.drawCircle(center, innerRadius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AccentCirclePainter old) =>
      old.color != color || old.selected != selected;
}

class _CustomColorButton extends StatelessWidget {
  final double size;
  final bool isSelected;
  final Color currentColor;

  const _CustomColorButton({
    required this.size,
    required this.isSelected,
    required this.currentColor,
  });

  @override
  Widget build(BuildContext context) {
    final outerSize = size + 8;
    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: CustomPaint(
        painter: _SevenCirclePainter(
          isSelected: isSelected,
          currentColor: currentColor,
          dotSize: size / 8,
        ),
      ),
    );
  }
}

class _SevenCirclePainter extends CustomPainter {
  final bool isSelected;
  final Color currentColor;
  final double dotSize;

  _SevenCirclePainter({
    required this.isSelected,
    required this.currentColor,
    required this.dotSize,
  });

  static const _hues = [0.0, 60.0, 120.0, 180.0, 240.0, 300.0];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = dotSize;
    final orbitR = size.width / 2 - r;

    if (isSelected) {
      canvas.drawCircle(
        center,
        size.width / 2,
        Paint()
          ..color = currentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    canvas.drawCircle(
      center,
      r,
      Paint()..color = isSelected ? currentColor : HSLColor.fromAHSL(1, 0, 0.8, 0.5).toColor(),
    );

    for (var i = 0; i < 6; i++) {
      final angle = (i * 60.0 - 90) * math.pi / 180;
      final pos = Offset(
        center.dx + orbitR * 0.72 * math.cos(angle),
        center.dy + orbitR * 0.72 * math.sin(angle),
      );
      canvas.drawCircle(
        pos,
        r,
        Paint()..color = HSLColor.fromAHSL(1, _hues[i], 0.8, 0.55).toColor(),
      );
    }
  }

  @override
  bool shouldRepaint(_SevenCirclePainter old) =>
      old.isSelected != isSelected || old.currentColor != currentColor;
}

// ── HSL Color Picker Dialog ──

class _HslColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final bool isDark;
  final ValueChanged<Color> onColorPicked;

  const _HslColorPickerDialog({
    required this.initialColor,
    required this.isDark,
    required this.onColorPicked,
  });

  @override
  State<_HslColorPickerDialog> createState() => _HslColorPickerDialogState();
}

class _HslColorPickerDialogState extends State<_HslColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _lightness;

  @override
  void initState() {
    super.initState();
    final hsl = HSLColor.fromColor(widget.initialColor);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  Color get _currentColor =>
      HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness).toColor();

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return AlertDialog(
      backgroundColor: bgColor,
      title: Text(
        'Choose Color',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color preview.
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentColor,
              ),
            ),
            const SizedBox(height: 20),
            // Hue slider.
            _SliderRow(
              label: 'H',
              value: _hue,
              max: 360,
              isDark: widget.isDark,
              trackGradient: LinearGradient(
                colors: List.generate(
                  7,
                  (i) => HSLColor.fromAHSL(1, i * 60.0, _saturation, _lightness)
                      .toColor(),
                ),
              ),
              onChanged: (v) => setState(() => _hue = v),
              textColor: textColor,
              subtextColor: subtextColor,
            ),
            const SizedBox(height: 12),
            // Saturation slider.
            _SliderRow(
              label: 'S',
              value: _saturation * 100,
              max: 100,
              isDark: widget.isDark,
              trackGradient: LinearGradient(
                colors: [
                  HSLColor.fromAHSL(1, _hue, 0, _lightness).toColor(),
                  HSLColor.fromAHSL(1, _hue, 1, _lightness).toColor(),
                ],
              ),
              onChanged: (v) => setState(() => _saturation = v / 100),
              textColor: textColor,
              subtextColor: subtextColor,
            ),
            const SizedBox(height: 12),
            // Lightness slider.
            _SliderRow(
              label: 'L',
              value: _lightness * 100,
              max: 100,
              isDark: widget.isDark,
              trackGradient: LinearGradient(
                colors: [
                  HSLColor.fromAHSL(1, _hue, _saturation, 0).toColor(),
                  HSLColor.fromAHSL(1, _hue, _saturation, 0.5).toColor(),
                  HSLColor.fromAHSL(1, _hue, _saturation, 1).toColor(),
                ],
              ),
              onChanged: (v) => setState(() => _lightness = v / 100),
              textColor: textColor,
              subtextColor: subtextColor,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: TextStyle(color: _currentColor)),
        ),
        TextButton(
          onPressed: () {
            widget.onColorPicked(_currentColor);
            Navigator.of(context).pop();
          },
          child: Text('Apply',
              style: TextStyle(color: _currentColor)),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final bool isDark;
  final Gradient trackGradient;
  final ValueChanged<double> onChanged;
  final Color textColor;
  final Color subtextColor;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.isDark,
    required this.trackGradient,
    required this.onChanged,
    required this.textColor,
    required this.subtextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: subtextColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _GradientSlider(
            value: value,
            max: max,
            gradient: trackGradient,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ),
      ],
    );
  }
}

// ── Gradient Slider ──

class _GradientSlider extends StatefulWidget {
  final double value;
  final double max;
  final Gradient gradient;
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.value,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  @override
  State<_GradientSlider> createState() => _GradientSliderState();
}

class _GradientSliderState extends State<_GradientSlider> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fraction = widget.max > 0 ? widget.value / widget.max : 0.0;
        final thumbX = fraction * (width - 16) + 8;

        return GestureDetector(
          onHorizontalDragUpdate: (d) => _updateFromX(d.localPosition.dx, width),
          onTapDown: (d) => _updateFromX(d.localPosition.dx, width),
          child: SizedBox(
            height: 28,
            child: CustomPaint(
              size: Size(width, 28),
              painter: _GradientSliderPainter(
                gradient: widget.gradient,
                thumbX: thumbX,
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateFromX(double x, double width) {
    final fraction = ((x - 8) / (width - 16)).clamp(0.0, 1.0);
    widget.onChanged(fraction * widget.max);
  }
}

class _GradientSliderPainter extends CustomPainter {
  final Gradient gradient;
  final double thumbX;

  _GradientSliderPainter({required this.gradient, required this.thumbX});

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 3, size.width, 6),
      const Radius.circular(3),
    );
    final paint = Paint()
      ..shader = gradient.createShader(trackRect.outerRect);
    canvas.drawRRect(trackRect, paint);

    // Thumb.
    canvas.drawCircle(
      Offset(thumbX, size.height / 2),
      7.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(thumbX, size.height / 2),
      7.5,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_GradientSliderPainter old) =>
      old.thumbX != thumbX || old.gradient != gradient;
}

// ── §14.6.2: Your Color row ──

class _YourColorRow extends StatelessWidget {
  final int colorId;
  final bool isDark;
  final bool loaded;
  final String? accountId;
  final ValueChanged<int> onColorChanged;

  const _YourColorRow({
    required this.colorId,
    required this.isDark,
    required this.loaded,
    required this.accountId,
    required this.onColorChanged,
  });

  static const _baseColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
    Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];

  Color get _currentColor {
    final idx = colorId >= 0 && colorId < _baseColors.length
        ? colorId
        : (accountId?.hashCode.abs() ?? 0) % 7;
    return _baseColors[idx];
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return InkWell(
      onTap: () => _openEditPeerColorBox(context),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: _currentColor,
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.palette, size: SettingsStyle.iconInner, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _currentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Your Color',
                        style: TextStyle(fontSize: 14, color: textColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Name Color',
                    style: TextStyle(fontSize: 13, color: subtextColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditPeerColorBox(BuildContext context) {
    final acctId = accountId;
    if (acctId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => _EditPeerColorBox(
        isDark: isDark,
        currentColorId: colorId >= 0 ? colorId : (acctId.hashCode.abs() % 7),
        accountId: acctId,
        onColorSaved: onColorChanged,
      ),
    );
  }
}

// ── §14.6.2: EditPeerColorBox ──

class _EditPeerColorBox extends StatefulWidget {
  final bool isDark;
  final int currentColorId;
  final String accountId;
  final ValueChanged<int> onColorSaved;

  const _EditPeerColorBox({
    required this.isDark,
    required this.currentColorId,
    required this.accountId,
    required this.onColorSaved,
  });

  @override
  State<_EditPeerColorBox> createState() => _EditPeerColorBoxState();
}

class _EditPeerColorBoxState extends State<_EditPeerColorBox> {
  late int _selected;
  bool _saving = false;

  static const _baseColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
    Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentColorId.clamp(0, 6);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = widget.isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Name Color',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(7, (i) {
                  final isSelected = i == _selected;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: accentColor, width: 2.5)
                            : null,
                      ),
                      padding: EdgeInsets.all(isSelected ? 3 : 0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _baseColors[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? const Color(0xFF17212B)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: _baseColors[_selected],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Your Name',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _baseColors[_selected],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: accentColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                          )
                        : Text('Save', style: TextStyle(color: accentColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final engine = context.read<EngineService>();
      await engine.updateNameColor(widget.accountId, _selected);
      widget.onColorSaved(_selected);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update color: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _saving = false);
      }
    }
  }
}

// ── §14.6.2: Auto-Night Mode toggle ──

class _AutoNightRow extends StatelessWidget {
  final bool isDark;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AutoNightRow({
    required this.isDark,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    return InkWell(
      onTap: () => onChanged(!enabled),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3E546A) : const Color(0xFF9E9E9E),
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              alignment: Alignment.center,
              child: Icon(
                isDark ? Icons.dark_mode : Icons.brightness_2,
                size: SettingsStyle.iconInner,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Auto-Night Mode',
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            SizedBox(
              height: 24,
              child: Switch(
                value: enabled,
                onChanged: onChanged,
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── §14.6.2: Font Family row ──

const _availableFonts = [
  'Inter',
  'Roboto',
  'Open Sans',
  'Noto Sans',
  'System Default',
];

class _FontFamilyRow extends StatelessWidget {
  final bool isDark;
  final String currentFont;
  final ValueChanged<String> onFontChanged;

  const _FontFamilyRow({
    required this.isDark,
    required this.currentFont,
    required this.onFontChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return InkWell(
      onTap: () => _openChooseFontBox(context),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3E546A) : const Color(0xFF9E9E9E),
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.text_fields, size: SettingsStyle.iconInner, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Font Family',
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            Text(
              currentFont,
              style: TextStyle(fontSize: 14, color: subtextColor),
            ),
          ],
        ),
      ),
    );
  }

  void _openChooseFontBox(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ChooseFontBox(
        isDark: isDark,
        currentFont: currentFont,
        onFontSelected: (f) {
          onFontChanged(f);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
}

// ── §14.6.2: ChooseFontBox dialog ──

class _ChooseFontBox extends StatefulWidget {
  final bool isDark;
  final String currentFont;
  final ValueChanged<String> onFontSelected;

  const _ChooseFontBox({
    required this.isDark,
    required this.currentFont,
    required this.onFontSelected,
  });

  @override
  State<_ChooseFontBox> createState() => _ChooseFontBoxState();
}

class _ChooseFontBoxState extends State<_ChooseFontBox> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentFont;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = widget.isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final previewBg = widget.isDark ? const Color(0xFF17212B) : const Color(0xFFF5F5F5);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose Font',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: previewBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'The quick brown fox jumps over the lazy dog.',
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                    fontFamily: _selected == 'System Default' ? null : _selected,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ..._availableFonts.map((font) {
                final isSelected = font == _selected;
                return InkWell(
                  onTap: () => setState(() => _selected = font),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Radio<String>(
                            value: font,
                            groupValue: _selected,
                            onChanged: (v) {
                              if (v != null) setState(() => _selected = v);
                            },
                            activeColor: accentColor,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          font,
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                            fontFamily: font == 'System Default' ? null : font,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: accentColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => widget.onFontSelected(_selected),
                    child: Text('Apply', style: TextStyle(color: accentColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── §14.6.3: Cloud Themes section ──

class _CloudThemeSection extends StatelessWidget {
  final List<CloudThemeInfo> themes;
  final bool loaded;
  final bool showAll;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onToggleShowAll;
  final ValueChanged<CloudThemeInfo> onThemeSelected;
  final VoidCallback? onEditTheme;

  const _CloudThemeSection({
    required this.themes,
    required this.loaded,
    required this.showAll,
    required this.isDark,
    required this.accentColor,
    required this.onToggleShowAll,
    required this.onThemeSelected,
    this.onEditTheme,
  });

  @override
  Widget build(BuildContext context) {
    if (!loaded || themes.isEmpty) return const SizedBox.shrink();

    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final visibleThemes = showAll ? themes : themes.take(8).toList();

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Text(
                  'Cloud Themes',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                const Spacer(),
                if (themes.length > 8)
                  GestureDetector(
                    onTap: onToggleShowAll,
                    child: Text(
                      showAll ? 'Show Less' : 'Show All',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: _gridHeight(visibleThemes.length),
            child: _buildGrid(visibleThemes, textColor, subtextColor),
          ),
          if (onEditTheme != null)
            InkWell(
              onTap: onEditTheme,
              hoverColor: hoverBg,
              splashColor: hoverBg.withValues(alpha: 0.5),
              child: Padding(
                padding: SettingsStyle.iconRowPadding,
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 20, color: accentColor),
                    const SizedBox(width: 12),
                    Text(
                      'Edit Current Theme',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _gridHeight(int count) {
    final rows = showAll ? ((count + 3) ~/ 4) : 1;
    return rows * 116.0;
  }

  Widget _buildGrid(List<CloudThemeInfo> visible, Color textColor, Color subtextColor) {
    if (!showAll) {
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: visible.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _CloudThemeCard(
            theme: visible[i],
            isDark: isDark,
            accentColor: accentColor,
            textColor: textColor,
            subtextColor: subtextColor,
            onTap: () => onThemeSelected(visible[i]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: visible.map((t) => _CloudThemeCard(
          theme: t,
          isDark: isDark,
          accentColor: accentColor,
          textColor: textColor,
          subtextColor: subtextColor,
          onTap: () => onThemeSelected(t),
        )).toList(),
      ),
    );
  }
}

class _CloudThemeCard extends StatelessWidget {
  final CloudThemeInfo theme;
  final bool isDark;
  final Color accentColor;
  final Color textColor;
  final Color subtextColor;
  final VoidCallback onTap;

  const _CloudThemeCard({
    required this.theme,
    required this.isDark,
    required this.accentColor,
    required this.textColor,
    required this.subtextColor,
    required this.onTap,
  });

  Color _argbToColor(int argb) {
    if (argb == 0) return isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    return Color(0xFF000000 | (argb & 0xFFFFFF));
  }

  @override
  Widget build(BuildContext context) {
    final accent = _argbToColor(theme.accentColor);
    final sent = _argbToColor(theme.sentColor);
    final bg = theme.bgColor != 0
        ? _argbToColor(theme.bgColor)
        : (theme.isDark ? const Color(0xFF0E1621) : const Color(0xFFDFE7EB));
    final recv = theme.recvColor != 0
        ? _argbToColor(theme.recvColor)
        : (theme.isDark ? const Color(0xFF182533) : const Color(0xFFFFFFFF));

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.transparent, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                size: const Size(76, 88),
                painter: _CloudThemePreviewPainter(
                  background: bg,
                  receivedBubble: recv,
                  sentBubble: sent.a > 0 ? sent : accent,
                  isDarkTheme: theme.isDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 80,
            child: Text(
              theme.title,
              style: TextStyle(fontSize: 11, color: subtextColor),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── §14.6.4: Chat Background section ──

class _ChatBackgroundSection extends StatelessWidget {
  final bool isDark;
  final bool tileBackground;
  final bool adaptiveLayout;
  final Color accentColor;
  final ValueChanged<bool> onTileChanged;
  final ValueChanged<bool> onAdaptiveChanged;

  const _ChatBackgroundSection({
    required this.isDark,
    required this.tileBackground,
    required this.adaptiveLayout,
    required this.accentColor,
    required this.onTileChanged,
    required this.onAdaptiveChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final thumbBg = isDark ? const Color(0xFF0E1621) : const Color(0xFFDFE7EB);
    final thumbRecv = isDark ? const Color(0xFF182533) : const Color(0xFFFFFFFF);
    final thumbSent = isDark ? const Color(0xFF2B5278) : const Color(0xFFEEFFDE);
    final windowWidth = MediaQuery.of(context).size.width;
    final isWide = windowWidth >= 880;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: thumbBg,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    size: const Size(76, 76),
                    painter: _BackgroundThumbPainter(
                      background: thumbBg,
                      receivedBubble: thumbRecv,
                      sentBubble: thumbSent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {},
                    child: Text(
                      'Choose from gallery',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {},
                    child: Text(
                      'Choose from file',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsCheckbox(
            label: 'Tile Background',
            value: tileBackground,
            isDark: isDark,
            onChanged: onTileChanged,
          ),
          if (isWide)
            _SettingsCheckbox(
              label: 'Adaptive Layout for Wide Screens',
              value: adaptiveLayout,
              isDark: isDark,
              onChanged: onAdaptiveChanged,
            ),
        ],
      ),
    );
  }
}

class _BackgroundThumbPainter extends CustomPainter {
  final Color background;
  final Color receivedBubble;
  final Color sentBubble;

  _BackgroundThumbPainter({
    required this.background,
    required this.receivedBubble,
    required this.sentBubble,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = background,
    );

    final recvPaint = Paint()..color = receivedBubble;
    final sentPaint = Paint()..color = sentBubble;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 8, 32, 10),
        const Radius.circular(2),
      ),
      recvPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 37, 24, 32, 10),
        const Radius.circular(2),
      ),
      sentPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 40, 26, 10),
        const Radius.circular(2),
      ),
      recvPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 31, 56, 26, 10),
        const Radius.circular(2),
      ),
      sentPaint,
    );
  }

  @override
  bool shouldRepaint(_BackgroundThumbPainter old) =>
      old.background != background ||
      old.receivedBubble != receivedBubble ||
      old.sentBubble != sentBubble;
}

class _SettingsCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _SettingsCheckbox({
    required this.label,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: accentColor,
                side: BorderSide(color: subtextColor, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── §14.6.5: Chat List Quick Action ──

class _ChatListQuickActionSection extends StatelessWidget {
  final bool isDark;
  final String currentAction;
  final Color accentColor;
  final ValueChanged<String> onActionChanged;

  const _ChatListQuickActionSection({
    required this.isDark,
    required this.currentAction,
    required this.accentColor,
    required this.onActionChanged,
  });

  static const _actions = [
    ('mute', 'Mute', Icons.volume_off),
    ('pin', 'Pin', Icons.push_pin),
    ('read', 'Read', Icons.done_all),
    ('archive', 'Archive', Icons.archive),
    ('delete', 'Delete', Icons.delete),
    ('disabled', 'Disabled', Icons.block),
  ];

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 4, bottom: 8),
          child: Text(
            'Chat list quick action',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        Center(
          child: _QuickActionPreview(
            action: currentAction,
            isDark: isDark,
            accentColor: accentColor,
          ),
        ),
        const SizedBox(height: 12),
        for (final (value, label, icon) in _actions)
          InkWell(
            onTap: () => onActionChanged(value),
            child: Padding(
              padding: const EdgeInsets.only(
                  left: 22, top: 5, bottom: 5, right: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Radio<String>(
                      value: value,
                      groupValue: currentAction,
                      onChanged: (v) {
                        if (v != null) onActionChanged(v);
                      },
                      activeColor: accentColor,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    icon,
                    size: 20,
                    color: value == currentAction ? accentColor : subtextColor,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickActionPreview extends StatelessWidget {
  final String action;
  final bool isDark;
  final Color accentColor;

  const _QuickActionPreview({
    required this.action,
    required this.isDark,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final chatRowBg =
        isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final chatRowHover =
        isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    Color actionColor;
    IconData actionIcon;
    String actionLabel;
    switch (action) {
      case 'mute':
        actionColor = const Color(0xFF40A7E3);
        actionIcon = Icons.volume_off;
        actionLabel = 'Mute';
      case 'pin':
        actionColor = const Color(0xFF40A7E3);
        actionIcon = Icons.push_pin;
        actionLabel = 'Pin';
      case 'read':
        actionColor = const Color(0xFF40A7E3);
        actionIcon = Icons.done_all;
        actionLabel = 'Read';
      case 'archive':
        actionColor = const Color(0xFF40A7E3);
        actionIcon = Icons.archive;
        actionLabel = 'Archive';
      case 'delete':
        actionColor = const Color(0xFFE53935);
        actionIcon = Icons.delete;
        actionLabel = 'Delete';
      default:
        actionColor = const Color(0xFF999999);
        actionIcon = Icons.block;
        actionLabel = 'Disabled';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(action),
        width: 260,
        height: 62,
        decoration: BoxDecoration(
          color: chatRowBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF2B3A4A) : const Color(0xFFE0E0E0),
          ),
        ),
        child: Stack(
          children: [
            // The revealed action area (right side).
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 80,
              child: Container(
                decoration: BoxDecoration(
                  color: actionColor,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(9),
                    bottomRight: Radius.circular(9),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(actionIcon, size: 22, color: Colors.white),
                    const SizedBox(height: 2),
                    Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The chat row sliding left.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              right: 30,
              child: Container(
                decoration: BoxDecoration(
                  color: chatRowHover,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(9),
                    bottomLeft: Radius.circular(9),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withValues(alpha: 0.3),
                      ),
                      child: Icon(Icons.person, size: 24,
                          color: accentColor.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 10,
                            width: 80,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF4A5568)
                                  : const Color(0xFFBDBDBD),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 8,
                            width: 110,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF3A4558)
                                  : const Color(0xFFD5D5D5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudThemePreviewPainter extends CustomPainter {
  final Color background;
  final Color receivedBubble;
  final Color sentBubble;
  final bool isDarkTheme;

  _CloudThemePreviewPainter({
    required this.background,
    required this.receivedBubble,
    required this.sentBubble,
    required this.isDarkTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = background,
    );

    final recvPaint = Paint()..color = receivedBubble;
    final sentPaint = Paint()..color = sentBubble;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 8, 40, 14),
        const Radius.circular(2),
      ),
      recvPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 46, 28, 40, 14),
        const Radius.circular(2),
      ),
      sentPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 48, 32, 14),
        const Radius.circular(2),
      ),
      recvPaint,
    );
  }

  @override
  bool shouldRepaint(_CloudThemePreviewPainter old) =>
      old.background != background ||
      old.receivedBubble != receivedBubble ||
      old.sentBubble != sentBubble;
}

// ── §14.6.6: Stickers & Emoji ──

class _StickersEmojiSection extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final bool largeEmoji;
  final bool replaceEmojis;
  final bool suggestEmoji;
  final bool suggestAnimatedEmoji;
  final bool suggestStickersByEmoji;
  final bool loopAnimatedStickers;
  final ValueChanged<bool> onLargeEmojiChanged;
  final ValueChanged<bool> onReplaceEmojisChanged;
  final ValueChanged<bool> onSuggestEmojiChanged;
  final ValueChanged<bool> onSuggestAnimatedEmojiChanged;
  final ValueChanged<bool> onSuggestStickersByEmojiChanged;
  final ValueChanged<bool> onLoopAnimatedStickersChanged;

  const _StickersEmojiSection({
    required this.isDark,
    required this.accentColor,
    required this.largeEmoji,
    required this.replaceEmojis,
    required this.suggestEmoji,
    required this.suggestAnimatedEmoji,
    required this.suggestStickersByEmoji,
    required this.loopAnimatedStickers,
    required this.onLargeEmojiChanged,
    required this.onReplaceEmojisChanged,
    required this.onSuggestEmojiChanged,
    required this.onSuggestAnimatedEmojiChanged,
    required this.onSuggestStickersByEmojiChanged,
    required this.onLoopAnimatedStickersChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 4, bottom: 8),
          child: Text(
            'Stickers and Emoji',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        _StickerCheckbox(
          label: 'Large Emoji',
          value: largeEmoji,
          isDark: isDark,
          onChanged: onLargeEmojiChanged,
        ),
        _StickerCheckbox(
          label: 'Replace Emojis',
          value: replaceEmojis,
          isDark: isDark,
          onChanged: onReplaceEmojisChanged,
        ),
        _StickerCheckbox(
          label: 'Suggest Emoji',
          value: suggestEmoji,
          isDark: isDark,
          onChanged: onSuggestEmojiChanged,
        ),
        if (suggestEmoji)
          _StickerCheckbox(
            label: 'Suggest Animated Emoji',
            value: suggestAnimatedEmoji,
            isDark: isDark,
            onChanged: onSuggestAnimatedEmojiChanged,
            nested: true,
            premiumOnly: true,
          ),
        _StickerCheckbox(
          label: 'Suggest Stickers by Emoji',
          value: suggestStickersByEmoji,
          isDark: isDark,
          onChanged: onSuggestStickersByEmojiChanged,
        ),
        _StickerCheckbox(
          label: 'Loop Animated Stickers',
          value: loopAnimatedStickers,
          isDark: isDark,
          onChanged: onLoopAnimatedStickersChanged,
        ),
        const SizedBox(height: 4),
        _StickerNavButton(
          icon: Icons.sticky_note_2_outlined,
          label: 'Your Stickers',
          isDark: isDark,
          onTap: () {},
        ),
        _StickerNavButton(
          icon: Icons.emoji_emotions_outlined,
          label: 'Emoji Sets',
          isDark: isDark,
          onTap: () {},
        ),
      ],
    );
  }
}

class _StickerCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;
  final bool nested;
  final bool premiumOnly;

  const _StickerCheckbox({
    required this.label,
    required this.value,
    required this.isDark,
    required this.onChanged,
    this.nested = false,
    this.premiumOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.only(
          left: nested ? 44 : 22,
          top: 10,
          right: 10,
          bottom: 10,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: accentColor,
                side: BorderSide(color: subtextColor, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            if (premiumOnly)
              Icon(Icons.star, size: 14, color: const Color(0xFFFFA500)),
          ],
        ),
      ),
    );
  }
}

class _StickerNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _StickerNavButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 21,
          top: 11,
          right: 20,
          bottom: 9,
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: iconColor),
          ],
        ),
      ),
    );
  }
}

// ── §14.6.7: Messages ──

class _MessagesSection extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final String sendBy;
  final String doubleClickAction;
  final bool showReplyButton;
  final bool showReactionButton;
  final ValueChanged<String> onSendByChanged;
  final ValueChanged<String> onDoubleClickActionChanged;
  final ValueChanged<bool> onShowReplyButtonChanged;
  final ValueChanged<bool> onShowReactionButtonChanged;

  const _MessagesSection({
    required this.isDark,
    required this.accentColor,
    required this.sendBy,
    required this.doubleClickAction,
    required this.showReplyButton,
    required this.showReactionButton,
    required this.onSendByChanged,
    required this.onDoubleClickActionChanged,
    required this.onShowReplyButtonChanged,
    required this.onShowReactionButtonChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final ctrlLabel = isMac ? 'Cmd+Enter' : 'Ctrl+Enter';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 4, bottom: 4),
          child: Text(
            'Send by',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        _SendTypeRadio(
          value: 'enter',
          groupValue: sendBy,
          label: 'Enter',
          isDark: isDark,
          accentColor: accentColor,
          onChanged: onSendByChanged,
        ),
        _SendTypeRadio(
          value: 'ctrl_enter',
          groupValue: sendBy,
          label: ctrlLabel,
          isDark: isDark,
          accentColor: accentColor,
          onChanged: onSendByChanged,
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 4, bottom: 4),
          child: Text(
            'Double-click action',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        _SendTypeRadio(
          value: 'reply',
          groupValue: doubleClickAction,
          label: 'Reply',
          isDark: isDark,
          accentColor: accentColor,
          onChanged: onDoubleClickActionChanged,
        ),
        _SendTypeRadio(
          value: 'react',
          groupValue: doubleClickAction,
          label: 'React',
          isDark: isDark,
          accentColor: accentColor,
          onChanged: onDoubleClickActionChanged,
          trailing: Icon(
            Icons.favorite,
            size: 18,
            color: const Color(0xFFE53935),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(height: 1, color: dividerColor),
        ),
        const SizedBox(height: 4),
        _MessageCheckbox(
          label: 'Show reply button in corner',
          value: showReplyButton,
          isDark: isDark,
          onChanged: onShowReplyButtonChanged,
        ),
        _MessageCheckbox(
          label: 'Show reaction button in corner',
          value: showReactionButton,
          isDark: isDark,
          onChanged: onShowReactionButtonChanged,
        ),
      ],
    );
  }
}

class _SendTypeRadio extends StatelessWidget {
  final String value;
  final String groupValue;
  final String label;
  final bool isDark;
  final Color accentColor;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  const _SendTypeRadio({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.isDark,
    required this.accentColor,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);

    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.only(left: 22, top: 5, right: 10, bottom: 5),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Radio<String>(
                value: value,
                groupValue: groupValue,
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _MessageCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _MessageCheckbox({
    required this.label,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(left: 22, top: 10, right: 10, bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: accentColor,
                side: BorderSide(color: subtextColor, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── §14.6.9: Shortcuts & Archive ──

class _ShortcutsArchiveSection extends StatelessWidget {
  final bool isDark;
  final Color accentColor;

  const _ShortcutsArchiveSection({
    required this.isDark,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShortcutsArchiveButton(
          icon: Icons.keyboard_outlined,
          label: 'Keyboard Shortcuts',
          isDark: isDark,
          hoverBg: hoverBg,
          textColor: textColor,
          onTap: () => _showKeyboardShortcuts(context),
        ),
        _ShortcutsArchiveButton(
          icon: Icons.archive_outlined,
          label: 'Archive Settings',
          isDark: isDark,
          hoverBg: hoverBg,
          textColor: textColor,
          onTap: () => _showArchiveSettingsBox(context),
        ),
      ],
    );
  }

  void _showKeyboardShortcuts(BuildContext context) {
    Navigator.of(context).push(
      settingsPageRoute(const ShortcutsSettingsScreen()),
    );
  }

  void _showArchiveSettingsBox(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ArchiveSettingsBox(
        isDark: isDark,
        accentColor: accentColor,
      ),
    );
  }
}

class _ShortcutsArchiveButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Color hoverBg;
  final Color textColor;
  final VoidCallback onTap;

  const _ShortcutsArchiveButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.hoverBg,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.only(
            left: 22, top: 10, right: 22, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: iconColor),
          ],
        ),
      ),
    );
  }
}

class _ArchiveSettingsBox extends StatefulWidget {
  final bool isDark;
  final Color accentColor;

  const _ArchiveSettingsBox({
    required this.isDark,
    required this.accentColor,
  });

  @override
  State<_ArchiveSettingsBox> createState() => _ArchiveSettingsBoxState();
}

class _ArchiveSettingsBoxState extends State<_ArchiveSettingsBox> {
  bool _archiveAndMute = false;
  bool _keepUnmuted = false;
  bool _keepFolders = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadArchiveSettings();
  }

  void _loadArchiveSettings() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.getArchiveSettings(account.id).then((result) {
      if (!mounted) return;
      setState(() {
        _archiveAndMute = result.archiveAndMute;
        _keepUnmuted = result.keepArchivedUnmuted;
        _keepFolders = result.keepArchivedFolders;
        _loaded = true;
      });
    });
  }

  void _save() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.setArchiveSettings(
      account.id,
      archiveAndMute: _archiveAndMute,
      keepArchivedUnmuted: _keepUnmuted,
      keepArchivedFolders: _keepFolders,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return AlertDialog(
      backgroundColor: bgColor,
      title: Text(
        'Archive Settings',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      content: SizedBox(
        width: 364,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _archiveCheckbox(
              label: 'Archive and Mute',
              value: _archiveAndMute,
              textColor: textColor,
              subtextColor: subtextColor,
              onChanged: (v) {
                setState(() => _archiveAndMute = v);
                _save();
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Automatically archive and mute new chats from non-contacts.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
            const SizedBox(height: 12),
            _archiveCheckbox(
              label: 'Keep archived unmuted',
              value: _keepUnmuted,
              textColor: textColor,
              subtextColor: subtextColor,
              onChanged: (v) {
                setState(() => _keepUnmuted = v);
                _save();
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Keep unmuted chats in the Archive when they get a new message.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
            const SizedBox(height: 12),
            _archiveCheckbox(
              label: 'Keep archived folders',
              value: _keepFolders,
              textColor: textColor,
              subtextColor: subtextColor,
              onChanged: (v) {
                setState(() => _keepFolders = v);
                _save();
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Keep chats pinned in folders in the Archive when they get a new message.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: widget.accentColor)),
        ),
      ],
    );
  }

  Widget _archiveCheckbox({
    required String label,
    required bool value,
    required Color textColor,
    required Color subtextColor,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: _loaded ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: _loaded ? (v) => onChanged(v ?? false) : null,
                activeColor: widget.accentColor,
                side: BorderSide(color: subtextColor, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── §14.6.8: Sensitive Content ──

class _SensitiveContentSection extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SensitiveContentSection({
    required this.isDark,
    required this.accentColor,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 4, bottom: 8),
          child: Text(
            'Sensitive content',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        InkWell(
          onTap: () => onChanged(!enabled),
          child: Padding(
            padding: const EdgeInsets.only(
                left: 22, top: 10, right: 22, bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: enabled,
                    onChanged: (v) => onChanged(v ?? false),
                    activeColor: accentColor,
                    side: BorderSide(color: subtextColor, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Disable filtering',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22, right: 22, bottom: 4),
          child: Text(
            'Display sensitive media in public channels on all your Telegram devices.',
            style: TextStyle(fontSize: 13, color: subtextColor),
          ),
        ),
      ],
    );
  }
}
