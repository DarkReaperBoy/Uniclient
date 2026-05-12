import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';
import '../theme/wallpaper.dart';
import 'color_picker_box.dart';
import 'popup_menu.dart';
import 'settings_style.dart';
import 'shortcuts_settings_screen.dart';
import 'telegram_toast.dart';
import 'theme_editor.dart';

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  int _selfColorId = -1;
  bool _colorLoaded = false;
  List<CloudThemeInfo> _cloudThemes = [];
  bool _cloudThemesLoaded = false;
  bool _showAllCloudThemes = false;
  int _activeCloudThemeId = 0;
  bool _tileBackground = true;
  bool _adaptiveLayout = true;
  String get _sendBy => context.read<AppState>().sendBy;
  bool _sensitiveEnabled = false;
  bool _sensitiveCanChange = false;
  bool _sensitiveLoaded = false;


  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _tileBackground = appState.wallpaper.tiled;
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

  Future<void> _pickFromGallery() async {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final wallpapers = await engine.getWallpapers(account.id);
    if (!mounted) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => _WallpaperBrowser(
        wallpapers: wallpapers,
        isDark: isDark,
      ),
    );

    if (selected != null && mounted) {
      final colors = (selected['colors'] as List<dynamic>?)?.cast<int>() ?? [];
      if (colors.isNotEmpty) {
        final bgColors = colors.map((c) => Color(0xFF000000 | (c & 0xFFFFFF))).toList();
        final rotation = selected['rotation'] as int? ?? 0;
        appState.setWallpaper(WallpaperData(
          type: bgColors.length > 1 ? WallpaperType.gradient : WallpaperType.solid,
          backgroundColors: bgColors,
          gradientRotation: rotation,
          tiled: _tileBackground,
        ));
        setState(() {});
      }
    }
  }

  Future<void> _pickFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpeg', 'jpg', 'png', 'bmp', 'webp'],
    );
    await _applyPickedWallpaper(result);
  }

  Future<void> _applyPickedWallpaper(FilePickerResult? result) async {
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    Uint8List? bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || !mounted) return;
    final processed = encodeWallpaperJpeg(bytes);
    final appState = context.read<AppState>();
    appState.setWallpaper(WallpaperData.fromImage(
      processed,
      tiled: _tileBackground,
    ));
    setState(() {});
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
        context.palette.windowBgActive;
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
                _openThemeEditor(context);
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
              appState.applyTestingTheme(themeId);
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
                    value: appState.useSystemAccent,
                    onChanged: (v) {
                      final enabled = v ?? false;
                      appState.useSystemAccent = enabled;
                      if (enabled) {
                        appState.updateAccentColor('#40a7e3');
                      }
                    },
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
            activeThemeId: _activeCloudThemeId,
            onToggleShowAll: () => setState(() => _showAllCloudThemes = !_showAllCloudThemes),
            onThemeSelected: (theme) {
              setState(() => _activeCloudThemeId = theme.id);
              final targetTheme = theme.isDark ? 'night' : 'day_blue';
              final accentHex = theme.accentColor != 0
                  ? '#${(theme.accentColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
                  : null;
              appState.applyTestingTheme(targetTheme, accentColor: accentHex);
              final account = appState.activeAccount;
              if (account != null) {
                context.read<EngineService>().installCloudTheme(
                  account.id,
                  theme.id,
                  isDark: theme.isDark,
                );
              }
            },
            onEditTheme: () => _openThemeEditor(context),
          ),
          InkWell(
            onTap: () => _openThemeEditor(context),
            hoverColor: isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
            child: Padding(
              padding: SettingsStyle.iconRowPadding,
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, size: 20, color: currentAccent),
                  const SizedBox(width: 12),
                  Text(
                    'Edit Current Theme',
                    style: TextStyle(fontSize: 14, color: currentAccent),
                  ),
                ],
              ),
            ),
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
            currentFont: appState.customFontFamily,
            onFontChanged: (f) {
              appState.customFontFamily = f;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Restart app to apply font changes.')),
              );
            },
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _ChatBackgroundSection(
            isDark: isDark,
            tileBackground: _tileBackground,
            adaptiveLayout: _adaptiveLayout,
            accentColor: currentAccent,
            wallpaper: appState.wallpaper,
            onTileChanged: (v) {
              setState(() => _tileBackground = v);
              final wp = appState.wallpaper;
              if (wp.isImage) {
                appState.setWallpaper(WallpaperData(
                  type: wp.type,
                  backgroundColors: wp.backgroundColors,
                  patternIntensity: wp.patternIntensity,
                  gradientRotation: wp.gradientRotation,
                  blurred: wp.blurred,
                  imageBytes: wp.imageBytes,
                  patternBytes: wp.patternBytes,
                  tiled: v,
                ));
              }
            },
            onAdaptiveChanged: (v) => setState(() => _adaptiveLayout = v),
            onPickGallery: _pickFromGallery,
            onPickFile: _pickFromFile,
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
            largeEmoji: appState.chatLargeEmoji,
            replaceEmojis: appState.chatReplaceEmojis,
            suggestEmoji: appState.chatSuggestEmoji,
            suggestAnimatedEmoji: appState.chatSuggestAnimatedEmoji,
            suggestStickersByEmoji: appState.chatSuggestStickersByEmoji,
            loopAnimatedStickers: appState.chatLoopAnimatedStickers,
            onLargeEmojiChanged: (v) => appState.chatLargeEmoji = v,
            onReplaceEmojisChanged: (v) => appState.chatReplaceEmojis = v,
            onSuggestEmojiChanged: (v) => appState.chatSuggestEmoji = v,
            onSuggestAnimatedEmojiChanged: (v) => appState.chatSuggestAnimatedEmoji = v,
            onSuggestStickersByEmojiChanged: (v) => appState.chatSuggestStickersByEmoji = v,
            onLoopAnimatedStickersChanged: (v) => appState.chatLoopAnimatedStickers = v,
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _MessagesSection(
            isDark: isDark,
            accentColor: currentAccent,
            sendBy: _sendBy,
            doubleClickAction: appState.chatDoubleClickAction,
            doubleClickReaction: appState.chatDoubleClickReaction,
            showReplyButton: appState.chatShowReplyButton,
            showReactionButton: appState.chatShowReactionButton,
            onSendByChanged: (v) {
              appState.sendBy = v;
            },
            onDoubleClickActionChanged: (v) => appState.chatDoubleClickAction = v,
            onDoubleClickReactionChanged: (v) => appState.chatDoubleClickReaction = v,
            onShowReplyButtonChanged: (v) => appState.chatShowReplyButton = v,
            onShowReactionButtonChanged: (v) => appState.chatShowReactionButton = v,
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
                if (v && !_sensitiveEnabled) {
                  showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sensitive Content'),
                      content: const Text(
                        'You must be at least 18 years old to enable sensitive content. '
                        'Are you sure you want to continue?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  ).then((confirmed) {
                    if (confirmed == true && mounted) {
                      setState(() => _sensitiveEnabled = true);
                      final account = appState.activeAccount;
                      if (account != null) {
                        context.read<EngineService>().setContentSettings(account.id, true);
                      }
                    }
                  });
                } else {
                  setState(() => _sensitiveEnabled = v);
                  final account = appState.activeAccount;
                  if (account != null) {
                    context.read<EngineService>().setContentSettings(account.id, v);
                  }
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

  void _openThemeEditor(BuildContext context) {
    final palette = context.palette;
    Navigator.of(context).push(
      settingsPageRoute(
        ThemeEditorScreen(
          palette: palette,
          onPaletteChanged: (_) {},
        ),
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
    receivedBubble: Color(0xFF24292E),
    sentBubble: Color(0xFF265E8C),
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

  void _showHslPicker(BuildContext context) async {
    final result = await showColorPickerBox(
      context: context,
      initialColor: currentColor,
    );
    if (result != null) onColorSelected(result);
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
    final accentColor = context.palette.windowBgActive;

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
        showTelegramToast(context, 'Failed to update color: $e');
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
    final accentColor = context.palette.windowBgActive;

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
    final accentColor = context.palette.windowBgActive;
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
  final int activeThemeId;
  final VoidCallback onToggleShowAll;
  final ValueChanged<CloudThemeInfo> onThemeSelected;
  final VoidCallback? onEditTheme;

  const _CloudThemeSection({
    required this.themes,
    required this.loaded,
    required this.showAll,
    required this.isDark,
    required this.accentColor,
    required this.activeThemeId,
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
            child: _buildGrid(context, visibleThemes, textColor, subtextColor),
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

  Widget _buildGrid(BuildContext ctx, List<CloudThemeInfo> visible, Color textColor, Color subtextColor) {
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
            isActive: visible[i].id == activeThemeId,
            onTap: () => onThemeSelected(visible[i]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const cols = 4;
          const spacing = 8.0;
          final cardWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: visible.map((t) => SizedBox(
              width: cardWidth,
              child: _CloudThemeCard(
                theme: t,
                isDark: isDark,
                accentColor: accentColor,
                textColor: textColor,
                subtextColor: subtextColor,
                isActive: t.id == activeThemeId,
                onTap: () => onThemeSelected(t),
              ),
            )).toList(),
          );
        },
      ),
    );
  }
}

class _CloudThemeCard extends StatefulWidget {
  final CloudThemeInfo theme;
  final bool isDark;
  final Color accentColor;
  final Color textColor;
  final Color subtextColor;
  final bool isActive;
  final VoidCallback onTap;

  const _CloudThemeCard({
    required this.theme,
    required this.isDark,
    required this.accentColor,
    required this.textColor,
    required this.subtextColor,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_CloudThemeCard> createState() => _CloudThemeCardState();
}

class _CloudThemeCardState extends State<_CloudThemeCard> {
  bool _hovering = false;

  Color _argbToColor(int argb) {
    if (argb == 0) return widget.isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    return Color(0xFF000000 | (argb & 0xFFFFFF));
  }

  void _showContextMenu(Offset position) {
    final t = widget.theme;
    final isOwnerAndActive = t.isCreator && widget.isActive;
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(value: 'share', label: 'Share', icon: const Icon(Icons.link, size: 20)),
        if (isOwnerAndActive)
          TelegramMenuItem(value: 'edit', label: 'Edit', icon: const Icon(Icons.edit_outlined, size: 20)),
        TelegramMenuItem(
          value: 'delete',
          label: 'Delete',
          icon: const Icon(Icons.delete_outline, size: 20),
          isAttention: true,
        ),
      ],
    ).then((action) {
      if (action == null || !mounted) return;
      switch (action) {
        case 'share':
          final link = 'https://t.me/addtheme/${t.slug}';
          Clipboard.setData(ClipboardData(text: link));
          showTelegramToast(context, 'Link copied');
        case 'edit':
          final palette = context.palette;
          Navigator.of(context).push(
            settingsPageRoute(
              ThemeEditorScreen(
                palette: palette,
                onPaletteChanged: (_) {},
              ),
            ),
          );
        case 'delete':
          _showDeleteConfirmation();
      }
    });
  }

  void _showDeleteConfirmation() {
    final isDark = widget.isDark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
        title: Text('Delete Theme', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        content: Text(
          'Are you sure you want to delete "${widget.theme.title}"?',
          style: TextStyle(color: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF555555)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: widget.accentColor)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final appState = context.read<AppState>();
                final account = appState.activeAccount;
                if (account != null) {
                  final engine = context.read<EngineService>();
                  await engine.deleteCloudTheme(account.id, widget.theme.id);
                }
                if (mounted) showTelegramToast(context, 'Theme deleted');
              } catch (e) {
                if (mounted) showTelegramToast(context, 'Failed to delete theme');
              }
            },
            child: Text('Delete', style: TextStyle(color: isDark ? const Color(0xFFE53935) : const Color(0xFFDD4B39))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final sent = _argbToColor(t.sentColor);
    final bg = t.bgColor != 0
        ? _argbToColor(t.bgColor)
        : (t.isDark ? const Color(0xFF0E1621) : const Color(0xFFDFE7EB));
    final recv = t.recvColor != 0
        ? _argbToColor(t.recvColor)
        : (t.isDark ? const Color(0xFF24292E) : const Color(0xFFFFFFFF));
    final accent = _argbToColor(t.accentColor);
    final borderColor = widget.isActive ? widget.accentColor : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
        onLongPressStart: (details) => _showContextMenu(details.globalPosition),
        child: Column(
          children: [
            Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 80,
                  height: 92,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      size: const Size(76, 88),
                      painter: _CloudThemePreviewPainter(
                        background: bg,
                        receivedBubble: recv,
                        sentBubble: sent.a > 0 ? sent : accent,
                        isDarkTheme: t.isDark,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: _CloudThemeRadio(
                    isActive: widget.isActive,
                    accentColor: widget.accentColor,
                    isDark: widget.isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 80,
              child: Text(
                t.title,
                style: TextStyle(
                  fontSize: 11,
                  color: widget.isActive ? widget.accentColor : widget.subtextColor,
                  fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudThemeRadio extends StatelessWidget {
  final bool isActive;
  final Color accentColor;
  final bool isDark;

  const _CloudThemeRadio({
    required this.isActive,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? accentColor : Colors.transparent,
        border: Border.all(
          color: isActive ? accentColor : (isDark ? const Color(0xFF5B6A78) : const Color(0xFFBBBBBB)),
          width: 2,
        ),
      ),
      child: isActive
          ? const Center(child: Icon(Icons.check, size: 12, color: Colors.white))
          : null,
    );
  }
}

// ── §14.6.4: Chat Background section ──

class _ChatBackgroundSection extends StatefulWidget {
  final bool isDark;
  final bool tileBackground;
  final bool adaptiveLayout;
  final Color accentColor;
  final WallpaperData wallpaper;
  final ValueChanged<bool> onTileChanged;
  final ValueChanged<bool> onAdaptiveChanged;
  final VoidCallback onPickGallery;
  final VoidCallback onPickFile;

  const _ChatBackgroundSection({
    required this.isDark,
    required this.tileBackground,
    required this.adaptiveLayout,
    required this.accentColor,
    required this.wallpaper,
    required this.onTileChanged,
    required this.onAdaptiveChanged,
    required this.onPickGallery,
    required this.onPickFile,
  });

  @override
  State<_ChatBackgroundSection> createState() => _ChatBackgroundSectionState();
}

class _ChatBackgroundSectionState extends State<_ChatBackgroundSection>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didUpdateWidget(_ChatBackgroundSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallpaper != widget.wallpaper && _loading) {
      setState(() => _loading = false);
      _loadingController.stop();
      _loadingController.reset();
    }
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  void _onPickGallery() {
    setState(() => _loading = true);
    _loadingController.repeat();
    widget.onPickGallery();
  }

  void _onPickFile() {
    setState(() => _loading = true);
    _loadingController.repeat();
    widget.onPickFile();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final wallpaper = widget.wallpaper;
    final accentColor = widget.accentColor;
    final thumbBg = isDark ? const Color(0xFF0E1621) : const Color(0xFFDFE7EB);
    final thumbRecv = isDark ? const Color(0xFF24292E) : const Color(0xFFFFFFFF);
    final thumbSent = isDark ? const Color(0xFF265E8C) : const Color(0xFFEEFFDE);
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
              Stack(
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
                      child: wallpaper.imageBytes != null
                          ? Image.memory(
                              wallpaper.imageBytes!,
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : CustomPaint(
                              size: const Size(76, 76),
                              painter: _BackgroundThumbPainter(
                                background: wallpaper.backgroundColors.isNotEmpty
                                    ? wallpaper.backgroundColors.first
                                    : thumbBg,
                                receivedBubble: thumbRecv,
                                sentBubble: thumbSent,
                              ),
                            ),
                    ),
                  ),
                  if (_loading)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.black26,
                        ),
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _loadingController,
                            builder: (context, child) => SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                value: _loadingController.value,
                                strokeWidth: 3,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _onPickGallery,
                    child: Text(
                      'Choose from gallery',
                      style: TextStyle(fontSize: 14, color: accentColor),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _onPickFile,
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
            value: widget.tileBackground,
            isDark: isDark,
            onChanged: widget.onTileChanged,
          ),
          if (isWide)
            _SettingsCheckbox(
              label: 'Adaptive Layout for Wide Screens',
              value: widget.adaptiveLayout,
              isDark: isDark,
              onChanged: widget.onAdaptiveChanged,
            ),
        ],
      ),
    );
  }
}

class _WallpaperBrowser extends StatelessWidget {
  final List<Map<String, dynamic>> wallpapers;
  final bool isDark;

  const _WallpaperBrowser({required this.wallpapers, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final colorWallpapers = wallpapers.where((w) {
      final colors = w['colors'] as List<dynamic>?;
      return colors != null && colors.isNotEmpty;
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Choose Wallpaper',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: subtextColor),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          Expanded(
            child: colorWallpapers.isEmpty
                ? Center(child: Text('No wallpapers available', style: TextStyle(color: subtextColor)))
                : GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: colorWallpapers.length,
                    itemBuilder: (ctx, i) {
                      final wp = colorWallpapers[i];
                      final colors = (wp['colors'] as List<dynamic>).cast<int>();
                      final flutterColors = colors.map((c) => Color(0xFF000000 | (c & 0xFFFFFF))).toList();
                      final rotation = wp['rotation'] as int? ?? 0;

                      return GestureDetector(
                        onTap: () => Navigator.pop(ctx, wp),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: flutterColors.length > 1
                                ? LinearGradient(
                                    colors: flutterColors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    transform: GradientRotation(rotation * 3.14159 / 180),
                                  )
                                : null,
                            color: flutterColors.length == 1 ? flutterColors.first : null,
                          ),
                        ),
                      );
                    },
                  ),
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
    final accentColor = context.palette.windowBgActive;

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
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

class _QuickActionPreview extends StatefulWidget {
  final String action;
  final bool isDark;
  final Color accentColor;

  const _QuickActionPreview({
    required this.action,
    required this.isDark,
    required this.accentColor,
  });

  @override
  State<_QuickActionPreview> createState() => _QuickActionPreviewState();
}

class _QuickActionPreviewState extends State<_QuickActionPreview>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  String get action => widget.action;
  bool get isDark => widget.isDark;
  Color get accentColor => widget.accentColor;

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
        actionColor = context.palette.windowBgActive;
        actionIcon = Icons.volume_off;
        actionLabel = 'Mute';
      case 'pin':
        actionColor = context.palette.windowBgActive;
        actionIcon = Icons.push_pin;
        actionLabel = 'Pin';
      case 'read':
        actionColor = context.palette.windowBgActive;
        actionIcon = Icons.done_all;
        actionLabel = 'Read';
      case 'archive':
        actionColor = context.palette.windowBgActive;
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
                    AnimatedBuilder(
                      animation: _animCtrl,
                      builder: (_, child) => Transform.scale(
                        scale: 1.0 + _animCtrl.value * 0.15,
                        child: child,
                      ),
                      child: Icon(actionIcon, size: 22, color: Colors.white),
                    ),
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
          label: 'My Stickers',
          isDark: isDark,
          onTap: () => _showInstalledPacks(context, isDark, 'stickers'),
        ),
        _StickerNavButton(
          icon: Icons.emoji_emotions_outlined,
          label: 'Emoji Sets',
          isDark: isDark,
          onTap: () => _showInstalledPacks(context, isDark, 'emoji'),
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
        context.palette.windowBgActive;

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

void _showInstalledPacks(BuildContext context, bool isDark, String type) {
  final appState = context.read<AppState>();
  final account = appState.activeAccount;
  if (account == null) return;
  final engine = context.read<EngineService>();
  final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
  final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
  final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
  final accentColor = context.palette.windowBgActive;
  final title = type == 'stickers' ? 'My Stickers' : 'Emoji Sets';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: bgColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: subtextColor),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<StickerPackSummary>>(
              future: engine.getInstalledStickerPacks(account.id),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: accentColor));
                }
                final packs = snap.data ?? [];
                if (packs.isEmpty) {
                  return Center(
                    child: Text('No ${type == 'stickers' ? 'sticker packs' : 'emoji sets'} installed',
                      style: TextStyle(color: subtextColor)),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: packs.length,
                  itemBuilder: (ctx, i) {
                    final pack = packs[i];
                    return ListTile(
                      leading: pack.stickers.isNotEmpty && pack.stickers.first.fileId.isNotEmpty
                          ? Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(child: Text(pack.stickers.first.emoji, style: const TextStyle(fontSize: 24))),
                            )
                          : Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.sticky_note_2, color: subtextColor),
                            ),
                      title: Text(pack.title, style: TextStyle(color: textColor, fontSize: 14)),
                      subtitle: Text('${pack.count} ${type == 'stickers' ? 'stickers' : 'emoji'}',
                        style: TextStyle(color: subtextColor, fontSize: 12)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
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
  final String doubleClickReaction;
  final bool showReplyButton;
  final bool showReactionButton;
  final ValueChanged<String> onSendByChanged;
  final ValueChanged<String> onDoubleClickActionChanged;
  final ValueChanged<String> onDoubleClickReactionChanged;
  final ValueChanged<bool> onShowReplyButtonChanged;
  final ValueChanged<bool> onShowReactionButtonChanged;

  const _MessagesSection({
    required this.isDark,
    required this.accentColor,
    required this.sendBy,
    required this.doubleClickAction,
    required this.doubleClickReaction,
    required this.showReplyButton,
    required this.showReactionButton,
    required this.onSendByChanged,
    required this.onDoubleClickActionChanged,
    required this.onDoubleClickReactionChanged,
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
          trailing: _ReactionChooserButton(
            currentReaction: doubleClickReaction,
            isDark: isDark,
            onReactionSelected: onDoubleClickReactionChanged,
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
        context.palette.windowBgActive;

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

class _ReactionChooserButton extends StatefulWidget {
  final String currentReaction;
  final bool isDark;
  final ValueChanged<String> onReactionSelected;

  static const _fallbackReactions = ['❤️', '👍', '👎', '🔥', '🎉', '😢', '💩', '👏', '😂', '🤔', '🤯', '😱'];

  const _ReactionChooserButton({
    required this.currentReaction,
    required this.isDark,
    required this.onReactionSelected,
  });

  @override
  State<_ReactionChooserButton> createState() => _ReactionChooserButtonState();
}

class _ReactionChooserButtonState extends State<_ReactionChooserButton> {
  List<String> _reactions = _ReactionChooserButton._fallbackReactions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadReactions();
  }

  void _loadReactions() {
    try {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      final account = appState.activeAccount;
      if (account != null) {
        final tags = engine.getSavedReactionTags(account.id);
        if (tags.isNotEmpty) {
          final fromTags = tags.map((t) => t.emoji).where((e) => e.isNotEmpty).toList();
          if (fromTags.length >= 4) {
            setState(() => _reactions = fromTags);
            return;
          }
        }
      }
    } catch (_) {}
  }

  @override
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showReactionPicker(context),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
        ),
        alignment: Alignment.center,
        child: Text(widget.currentReaction, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  void _showReactionPicker(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose Reaction',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _reactions.map((emoji) {
                  final isSelected = emoji == widget.currentReaction;
                  return GestureDetector(
                    onTap: () {
                      widget.onReactionSelected(emoji);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? (widget.isDark ? const Color(0xFF2B5278) : const Color(0xFFE3F2FD))
                            : (widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF5F5F5)),
                        border: isSelected
                            ? Border.all(color: context.palette.windowBgActive, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
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
    try {
      engine.setArchiveSettings(
        account.id,
        archiveAndMute: _archiveAndMute,
        keepArchivedUnmuted: _keepUnmuted,
        keepArchivedFolders: _keepFolders,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save archive settings: $e')),
        );
      }
    }
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
