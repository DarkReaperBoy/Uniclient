import 'dart:async';
import 'dart:convert' show Base64Decoder;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui_dart;

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
  int _activeCloudThemeId = 0;
  bool _tileBackground = true;
  String get _sendBy => context.read<AppState>().sendBy;
  bool _sensitiveEnabled = false;
  bool _sensitiveCanChange = false;
  bool _ageVerifyNeeded = false;
  bool _sensitiveLoaded = false;
  Timer? _sensitiveTimer;


  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _tileBackground = appState.wallpaper.tiled;
    _loadSelfColor();
    _loadCloudThemes();
    _loadContentSettings();
    _sensitiveTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _loadContentSettings();
    });
  }

  @override
  void dispose() {
    _sensitiveTimer?.cancel();
    super.dispose();
  }

  static bool _supportsSystemDarkMode() {
    try {
      return Platform.isLinux || Platform.isMacOS || Platform.isWindows ||
             Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  void _restartApp() {
    final exe = Platform.resolvedExecutable;
    final args = Platform.executableArguments;
    Process.start(exe, args, mode: ProcessStartMode.detached).then((_) {
      exit(0);
    }).catchError((_) {
      exit(0);
    });
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
        _ageVerifyNeeded = result.ageVerifyNeeded;
        _sensitiveLoaded = true;
      });
    });
  }

  Future<void> _enableSensitiveContent(AppState appState) async {
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    final settings = await engine.getContentSettings(account.id);
    if (!mounted) return;
    if (settings.ageVerifyNeeded) {
      showTelegramToast(context, 'Age verification is required to change this setting. Please verify your age on one of the official Telegram apps first.');
      return;
    }
    if (!settings.sensitiveCanChange) {
      showTelegramToast(context, 'This option is not available for your account.');
      return;
    }
    setState(() => _sensitiveEnabled = true);
    try {
      await engine.setContentSettings(account.id, true);
    } catch (_) {
      if (mounted) {
        setState(() => _sensitiveEnabled = false);
        showTelegramToast(context, 'Failed to update content settings.');
      }
    }
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
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _cloudThemes = [];
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
      final thumbB64 = selected['thumb_b64'] as String? ?? '';
      final isPattern = selected['is_pattern'] as bool? ?? selected['pattern'] as bool? ?? false;
      final isPhoto = selected['is_photo'] as bool? ?? false;
      final rotation = selected['rotation'] as int? ?? 0;
      final docId = selected['doc_id'] as int? ?? 0;
      final docHash = selected['doc_hash'] as int? ?? 0;
      final docRef = selected['doc_ref'] as String? ?? '';

      if (isPhoto && docId != 0) {
        Uint8List? previewBytes;
        if (thumbB64.isNotEmpty) {
          try {
            previewBytes = Uint8List.fromList(const Base64Decoder().convert(thumbB64));
          } catch (_) {}
        }
        if (!mounted) return;
        final confirmed = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => _BackgroundPreviewBox(
            imageBytes: previewBytes,
            initialBlurred: false,
            initialTiled: _tileBackground,
            isLoading: previewBytes == null,
            onLoadFull: () async {
              final bytes = await engine.downloadWallpaperDocument(
                account.id, docId, docHash, docRef);
              return bytes;
            },
          ),
        );
        if (confirmed != null && mounted) {
          final blurred = confirmed['blurred'] as bool? ?? false;
          final tiled = confirmed['tiled'] as bool? ?? _tileBackground;
          Uint8List? fullBytes = confirmed['full_bytes'] as Uint8List?;
          fullBytes ??= previewBytes;
          if (fullBytes != null) {
            appState.setWallpaper(WallpaperData.fromImage(
              fullBytes,
              tiled: tiled,
              blur: blurred,
            ));
            setState(() => _tileBackground = tiled);
          }
        }
        return;
      }

      if (thumbB64.isNotEmpty) {
        Uint8List? imageBytes;
        try {
          imageBytes = Uint8List.fromList(const Base64Decoder().convert(thumbB64));
        } catch (_) {}
        if (imageBytes != null && mounted) {
          final confirmed = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (ctx) => _BackgroundPreviewBox(
              imageBytes: imageBytes!,
              initialBlurred: false,
              initialTiled: isPattern || _tileBackground,
            ),
          );
          if (confirmed != null && mounted) {
            final blurred = confirmed['blurred'] as bool? ?? false;
            final tiled = confirmed['tiled'] as bool? ?? _tileBackground;
            appState.setWallpaper(WallpaperData.fromImage(
              imageBytes,
              tiled: tiled,
              blur: blurred,
            ));
            setState(() => _tileBackground = tiled);
          }
          return;
        }
      }

      if (colors.isNotEmpty) {
        final bgColors = colors.map((c) => Color(0xFF000000 | (c & 0xFFFFFF))).toList();
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
    final confirmed = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _BackgroundPreviewBox(
        imageBytes: processed,
        initialBlurred: false,
        initialTiled: _tileBackground,
      ),
    );
    if (confirmed != null && mounted) {
      final appState = context.read<AppState>();
      final blurred = confirmed['blurred'] as bool? ?? false;
      final tiled = confirmed['tiled'] as bool? ?? _tileBackground;
      appState.setWallpaper(WallpaperData.fromImage(
        processed,
        tiled: tiled,
        blur: blurred,
      ));
      setState(() => _tileBackground = tiled);
    }
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
              final preset = _themePresets.firstWhere((p) => p.id == themeId);
              final currentIsNight = appState.themeId == 'night' || appState.themeId == 'night_green';
              final targetIsNight = preset.isDarkTheme;
              if (currentIsNight != targetIsNight) {
                showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Switch Mode'),
                    content: Text(
                      targetIsNight
                          ? 'Switch to night mode?'
                          : 'Switch to day mode?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Switch'),
                      ),
                    ],
                  ),
                ).then((confirmed) {
                  if (confirmed == true && mounted) {
                    appState.applyTestingTheme(themeId);
                  }
                });
              } else {
                appState.applyTestingTheme(themeId);
              }
            },
          ),
          const SizedBox(height: 8),
          _AccentColorPalette(
            currentColor: currentAccent,
            isDark: isDark,
            themeId: appState.themeId,
            wallpaper: appState.wallpaper,
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
                        appState.updateAccentColor(_readSystemAccent());
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
            isDark: isDark,
            accentColor: currentAccent,
            activeThemeId: _activeCloudThemeId,
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
            onEditTheme: _activeCloudThemeId != 0 &&
                _cloudThemes.any((t) => t.id == _activeCloudThemeId && t.isCreator && t.documentId != 0)
                ? () => _openThemeEditor(context)
                : null,
            onThemeDeleted: () {
              setState(() {
                _activeCloudThemeId = 0;
              });
              _loadCloudThemes();
            },
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
          if (_supportsSystemDarkMode())
            _AutoNightRow(
              isDark: isDark,
              enabled: appState.systemDarkModeEnabled,
              isEditingTheme: appState.isEditingTheme,
              onChanged: (v) {
                if (v && appState.isEditingTheme) {
                  showTelegramToast(context, 'Cannot change theme mode while editing a theme.');
                  return;
                }
                appState.setSystemDarkMode(v);
              },
            ),
          _FontFamilyRow(
            isDark: isDark,
            currentFont: appState.customFontFamily,
            onFontChanged: (f) {
              appState.customFontFamily = f;
              showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Font Changed'),
                  content: const Text('The app needs to restart to apply the new font.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Later'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Restart Now'),
                    ),
                  ],
                ),
              ).then((restart) {
                if (restart == true && mounted) {
                  _restartApp();
                }
              });
            },
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _ChatBackgroundSection(
            isDark: isDark,
            tileBackground: _tileBackground,
            adaptiveLayout: appState.adaptiveForWide,
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
            onAdaptiveChanged: (v) => appState.adaptiveForWide = v,
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
            isPremium: appState.effectivePremium,
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
          if (_sensitiveLoaded && (_sensitiveCanChange || _ageVerifyNeeded)) ...[
            const SizedBox(height: 7),
            Container(height: 1, color: dividerColor),
            const SizedBox(height: 7),
            _SensitiveContentSection(
              isDark: isDark,
              accentColor: currentAccent,
              enabled: _sensitiveEnabled,
              onChanged: (v) {
                if (v && !_sensitiveEnabled) {
                  _enableSensitiveContent(appState);
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
    final appState = context.read<AppState>();
    Navigator.of(context).push(
      settingsPageRoute(
        ThemeEditorScreen(
          palette: palette,
          onPaletteChanged: (p) => appState.setLivePalette(p),
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

  static String _readSystemAccent() {
    if (Platform.isLinux) {
      try {
        final home = Platform.environment['HOME'] ?? '';
        final file = File('$home/.config/kdeglobals');
        if (file.existsSync()) {
          for (final line in file.readAsLinesSync()) {
            if (line.startsWith('AccentColor=')) {
              final parts = line.substring('AccentColor='.length).split(',');
              if (parts.length >= 3) {
                final r = int.tryParse(parts[0].trim()) ?? 0;
                final g = int.tryParse(parts[1].trim()) ?? 0;
                final b = int.tryParse(parts[2].trim()) ?? 0;
                return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
              }
            }
          }
        }
      } catch (_) {}
    }
    return '#40a7e3';
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
    if (preset.id == currentTheme) return true;
    final isCurrentNight = currentTheme == 'night' || currentTheme == 'night_green' || currentTheme == 'dark';
    final isCurrentDay = !isCurrentNight;
    if (isCurrentNight && preset.isDarkTheme && preset.id == 'night') return true;
    if (isCurrentDay && !preset.isDarkTheme && preset.id == 'day_blue') return true;
    return false;
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
  final WallpaperData? wallpaper;
  final ValueChanged<Color> onColorSelected;

  const _AccentColorPalette({
    required this.currentColor,
    required this.isDark,
    required this.themeId,
    this.wallpaper,
    required this.onColorSelected,
  });

  static const _circleSize = 24.0;
  static const _ringWidth = 2.0;
  static const _ringSkip = 2.0;
  // Outer rendered size of each swatch widget (circle + selection-ring margin),
  // matching _AccentCircle/_CustomColorButton (24 + (2+2)*2 = 32).
  static const _swatchOuterSize = _circleSize + (_ringWidth + _ringSkip) * 2;
  // Cap the even-distribution width so the strip does not over-spread on wide
  // desktop panels; on narrower columns it shrinks to fit (and distributes).
  static const _maxStripWidth = 520.0;
  // Fixed gap used only in the horizontal-scroll fallback (sub-minimum widths).
  static const _scrollGap = 10.0;

  @override
  Widget build(BuildContext context) {
    final presets = TelegramPalette.accentsForTheme(themeId);
    if (presets.isEmpty) return const SizedBox.shrink();

    final swatches = <Widget>[
      for (final color in presets)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onColorSelected(color),
          child: _AccentCircle(
            color: color,
            selected: _colorsMatch(color, currentColor),
            size: _circleSize,
            ringWidth: _ringWidth,
            ringSkip: _ringSkip,
          ),
        ),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showHslPicker(context),
        child: _CustomColorButton(
          size: _circleSize,
          isSelected: _isCustomColor(presets),
          currentColor: currentColor,
        ),
      ),
    ];

    // AyuGram (settings_chat.cpp:404-424) spreads the accent swatches evenly
    // across the available width: skip = (width - size*count) / (count - 1).
    // We replicate that with space-between when the swatches fit, capping the
    // distribution width so it doesn't over-spread on wide desktop panels, and
    // falling back to a horizontal scroll on sub-minimum widths so the row never
    // overflows (the bug this fixes: a fixed-gap Row clipped ~12px at 400px).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxStripWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fits =
                  constraints.maxWidth >= _swatchOuterSize * swatches.length;
              if (fits) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: swatches,
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < swatches.length; i++) ...[
                      if (i > 0) const SizedBox(width: _scrollGap),
                      swatches[i],
                    ],
                  ],
                ),
              );
            },
          ),
        ),
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
    final (lightnessMin, lightnessMax) = _lightnessRangeForTheme(themeId);
    final result = await showColorPickerBox(
      context: context,
      initialColor: currentColor,
      lightnessMin: lightnessMin,
      lightnessMax: lightnessMax,
    );
    if (result != null) onColorSelected(result);
  }

  static (double, double) _lightnessRangeForTheme(String themeId) {
    switch (themeId) {
      case 'night':
      case 'night_green':
        return (64.0 / 255.0, 1.0);
      case 'classic_day':
      case 'day_blue':
      default:
        return (0.0, 160.0 / 255.0);
    }
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
  List<PeerColorEntry>? _serverColors;
  bool _loadingColors = true;
  String _displayName = '';

  static const _fallbackColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
    Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentColorId;
    final accounts = context.read<AppState>().accounts;
    _displayName = accounts
        .where((a) => a.id == widget.accountId)
        .map((a) => a.displayName)
        .firstOrNull ?? '';
    _loadColors();
  }

  Future<void> _loadColors() async {
    try {
      final engine = context.read<EngineService>();
      final colors = await engine.getPeerColors(widget.accountId);
      if (mounted) {
        setState(() {
          _serverColors = colors.where((c) => !c.hidden).toList();
          _loadingColors = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingColors = false);
    }
  }

  Color _colorForEntry(PeerColorEntry entry) {
    final cols = widget.isDark ? entry.nightColors : entry.dayColors;
    if (cols.isNotEmpty) return Color(0xFF000000 | (cols.first & 0xFFFFFF));
    if (entry.colorId < _fallbackColors.length) return _fallbackColors[entry.colorId];
    return _fallbackColors[entry.colorId % _fallbackColors.length];
  }

  Color _selectedColor() {
    if (_serverColors != null) {
      for (final c in _serverColors!) {
        if (c.colorId == _selected) return _colorForEntry(c);
      }
    }
    if (_selected >= 0 && _selected < _fallbackColors.length) return _fallbackColors[_selected];
    return _fallbackColors[0];
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;

    final colors = _serverColors ?? [];
    final displayColors = colors.isEmpty
        ? List.generate(7, (i) => (i, _fallbackColors[i]))
        : colors.map((c) => (c.colorId, _colorForEntry(c))).toList();

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
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
              if (_loadingColors)
                Center(child: SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accentColor)))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: displayColors.map((entry) {
                    final (colorId, color) = entry;
                    final isSelected = colorId == _selected;
                    return GestureDetector(
                      onTap: () => setState(() => _selected = colorId),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(color: accentColor, width: 2.5)
                              : null,
                        ),
                        padding: EdgeInsets.all(isSelected ? 2 : 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(isSelected ? 8 : 12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'A',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
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
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _selectedColor(),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'A',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName.isNotEmpty ? _displayName : 'Your Name',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _selectedColor(),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _displayName.isNotEmpty ? 'Hi there!' : 'Message preview text',
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
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
  final bool isEditingTheme;
  final ValueChanged<bool> onChanged;

  const _AutoNightRow({
    required this.isDark,
    required this.enabled,
    this.isEditingTheme = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auto-Night Mode',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                  Text(
                    enabled ? 'On' : 'Off',
                    style: TextStyle(fontSize: 12, color: subtextColor),
                  ),
                ],
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

List<String> _getAvailableFonts() {
  return ['System Default', 'Roboto', 'Noto Sans', 'Inter', 'Open Sans'];
}

Future<List<String>> _scanSystemFonts() async {
  final fonts = <String>{'System Default'};
  try {
    if (Platform.isLinux) {
      final result = await Process.run('fc-list', ['--format', '%{family}\n']);
      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        for (final line in output.split('\n')) {
          for (final family in line.split(',')) {
            final trimmed = family.trim();
            if (trimmed.isNotEmpty) fonts.add(trimmed);
          }
        }
      }
    } else if (Platform.isMacOS) {
      final result = await Process.run('system_profiler', ['SPFontsDataType', '-detailLevel', 'mini']);
      if (result.exitCode == 0) {
        final re = RegExp(r'^\s{4}(\S.+):$', multiLine: true);
        for (final match in re.allMatches(result.stdout as String)) {
          fonts.add(match.group(1)!.trim());
        }
      }
    } else if (Platform.isWindows) {
      final fontsDir = Directory('C:\\Windows\\Fonts');
      if (fontsDir.existsSync()) {
        final re = RegExp(r'^(.+)\.(ttf|otf|ttc)$', caseSensitive: false);
        for (final entity in fontsDir.listSync()) {
          final match = re.firstMatch(entity.uri.pathSegments.last);
          if (match != null) fonts.add(match.group(1)!.replaceAll(RegExp(r'[-_]'), ' '));
        }
      }
    }
  } catch (_) {}

  if (fonts.length <= 1) {
    if (Platform.isLinux) {
      fonts.addAll(['Noto Sans', 'DejaVu Sans', 'Liberation Sans', 'Ubuntu',
        'Cantarell', 'Roboto', 'Inter', 'Open Sans', 'Fira Sans']);
    } else if (Platform.isMacOS) {
      fonts.addAll(['San Francisco', 'Helvetica Neue', 'Arial', 'Avenir',
        'Georgia', 'Times New Roman', 'SF Mono', 'Menlo']);
    } else if (Platform.isWindows) {
      fonts.addAll(['Segoe UI', 'Arial', 'Calibri', 'Verdana', 'Tahoma',
        'Consolas', 'Cascadia Code']);
    } else {
      fonts.addAll(['Roboto', 'Noto Sans', 'Inter', 'Open Sans']);
    }
  }

  final sorted = fonts.toList()..sort((a, b) {
    if (a == 'System Default') return -1;
    if (b == 'System Default') return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return sorted;
}

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
  List<String> _allFonts = [];
  bool _fontsLoaded = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.currentFont;
    _allFonts = _getAvailableFonts();
    if (!_allFonts.contains(widget.currentFont) && widget.currentFont.isNotEmpty) {
      _allFonts.insert(1, widget.currentFont);
    }
    _scanSystemFonts().then((scanned) {
      if (!mounted) return;
      final list = scanned.toList();
      if (!list.contains(widget.currentFont) && widget.currentFont.isNotEmpty) {
        list.insert(1, widget.currentFont);
      }
      setState(() {
        _allFonts = list;
        _fontsLoaded = true;
      });
    });
  }

  List<String> get _filteredFonts {
    if (_searchQuery.isEmpty) return _allFonts;
    final q = _searchQuery.toLowerCase();
    return _allFonts.where((f) => f.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final previewBg = widget.isDark ? const Color(0xFF17212B) : const Color(0xFFF5F5F5);
    final fonts = _filteredFonts;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, maxHeight: 520),
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
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search fonts...',
                  hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: subtextColor.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accentColor),
                  ),
                ),
                style: TextStyle(fontSize: 14, color: textColor),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: fonts.length,
                  itemBuilder: (ctx, i) {
                    final font = fonts[i];
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
                  },
                ),
              ),
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

class _CloudThemeSection extends StatefulWidget {
  final List<CloudThemeInfo> themes;
  final bool loaded;
  final bool isDark;
  final Color accentColor;
  final int activeThemeId;
  final ValueChanged<CloudThemeInfo> onThemeSelected;
  final VoidCallback? onEditTheme;
  final VoidCallback? onThemeDeleted;

  const _CloudThemeSection({
    required this.themes,
    required this.loaded,
    required this.isDark,
    required this.accentColor,
    required this.activeThemeId,
    required this.onThemeSelected,
    this.onEditTheme,
    this.onThemeDeleted,
  });

  static const _initialVisibleCount = 4;

  @override
  State<_CloudThemeSection> createState() => _CloudThemeSectionState();
}

class _CloudThemeSectionState extends State<_CloudThemeSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.loaded || widget.themes.isEmpty) return const SizedBox.shrink();

    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final hasMore = widget.themes.length > _CloudThemeSection._initialVisibleCount;
    final visibleThemes = _showAll || !hasMore
        ? widget.themes
        : widget.themes.take(_CloudThemeSection._initialVisibleCount).toList();

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
                    color: widget.accentColor,
                  ),
                ),
                const Spacer(),
                if (hasMore && !_showAll)
                  GestureDetector(
                    onTap: () => setState(() => _showAll = true),
                    child: Text(
                      'Show All',
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.accentColor,
                      ),
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
          if (widget.onEditTheme != null)
            InkWell(
              onTap: widget.onEditTheme,
              hoverColor: hoverBg,
              splashColor: hoverBg.withValues(alpha: 0.5),
              child: Padding(
                padding: SettingsStyle.iconRowPadding,
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 20, color: widget.accentColor),
                    const SizedBox(width: 12),
                    Text(
                      'Edit Current Theme',
                      style: TextStyle(fontSize: 14, color: widget.accentColor),
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
    final rows = (count + 3) ~/ 4;
    return rows * 116.0;
  }

  Widget _buildGrid(BuildContext ctx, List<CloudThemeInfo> visible, Color textColor, Color subtextColor) {
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
                isDark: widget.isDark,
                accentColor: widget.accentColor,
                textColor: textColor,
                subtextColor: subtextColor,
                isActive: t.id == widget.activeThemeId,
                onTap: () => widget.onThemeSelected(t),
                onDeleted: widget.onThemeDeleted,
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
  final VoidCallback? onDeleted;

  const _CloudThemeCard({
    required this.theme,
    required this.isDark,
    required this.accentColor,
    required this.textColor,
    required this.subtextColor,
    required this.isActive,
    required this.onTap,
    this.onDeleted,
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
    final isOwnerAndActive = t.isCreator && widget.isActive && t.documentId != 0;
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
          final appState = context.read<AppState>();
          Navigator.of(context).push(
            settingsPageRoute(
              ThemeEditorScreen(
                palette: palette,
                onPaletteChanged: (p) => appState.setLivePalette(p),
                cloudTheme: widget.theme,
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
                  if (widget.isActive) {
                    final defaultTheme = widget.isDark ? 'night' : 'day_blue';
                    appState.applyTestingTheme(defaultTheme);
                  }
                  await engine.deleteCloudTheme(account.id, widget.theme.id);
                }
                widget.onDeleted?.call();
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
  final Future<void> Function() onPickGallery;
  final Future<void> Function() onPickFile;

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

class _ChatBackgroundSectionState extends State<_ChatBackgroundSection> {
  bool _loading = false;

  @override
  void didUpdateWidget(_ChatBackgroundSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallpaper != widget.wallpaper && _loading) {
      setState(() => _loading = false);
    }
  }

  Future<void> _onPickGallery() async {
    setState(() => _loading = true);
    try {
      await widget.onPickGallery();
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _onPickFile() async {
    setState(() => _loading = true);
    try {
      await widget.onPickFile();
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
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
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: accentColor,
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
          if (!wallpaper.isPattern && !wallpaper.isSolid)
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

class _WallpaperBrowser extends StatefulWidget {
  final List<Map<String, dynamic>> wallpapers;
  final bool isDark;

  const _WallpaperBrowser({required this.wallpapers, required this.isDark});

  @override
  State<_WallpaperBrowser> createState() => _WallpaperBrowserState();
}

class _WallpaperBrowserState extends State<_WallpaperBrowser> {
  Map<int, Uint8List> _decodedThumbs = {};

  @override
  void initState() {
    super.initState();
    _decodeAllThumbs();
  }

  @override
  void didUpdateWidget(_WallpaperBrowser old) {
    super.didUpdateWidget(old);
    if (!identical(old.wallpapers, widget.wallpapers)) {
      _decodeAllThumbs();
    }
  }

  void _decodeAllThumbs() {
    final thumbs = <int, Uint8List>{};
    for (var i = 0; i < widget.wallpapers.length; i++) {
      final b64 = widget.wallpapers[i]['thumb_b64'] as String? ?? '';
      if (b64.isNotEmpty) {
        try {
          thumbs[i] = Uint8List.fromList(const Base64Decoder().convert(b64));
        } catch (_) {}
      }
    }
    _decodedThumbs = thumbs;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
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
            child: widget.wallpapers.isEmpty
                ? Center(child: Text('No wallpapers available', style: TextStyle(color: subtextColor)))
                : GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: widget.wallpapers.length,
                    itemBuilder: (ctx, i) {
                      final wp = widget.wallpapers[i];
                      final colors = (wp['colors'] as List<dynamic>?)?.cast<int>() ?? [];
                      final isPattern = (wp['is_pattern'] as bool? ?? wp['pattern'] as bool? ?? false);
                      final isPhoto = wp['is_photo'] as bool? ?? false;
                      final rotation = wp['rotation'] as int? ?? 0;

                      Widget content;
                      final thumbBytes = _decodedThumbs[i];
                      if (thumbBytes != null && isPattern && colors.isNotEmpty) {
                        content = ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _colorTile(colors, rotation),
                              Opacity(
                                opacity: 0.5,
                                child: Image.memory(thumbBytes, fit: BoxFit.cover,
                                    width: double.infinity, height: double.infinity,
                                    color: Colors.white.withValues(alpha: 0.3),
                                    colorBlendMode: BlendMode.modulate),
                              ),
                            ],
                          ),
                        );
                      } else if (thumbBytes != null) {
                        content = ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(thumbBytes, fit: BoxFit.cover,
                              width: double.infinity, height: double.infinity),
                        );
                      } else {
                        content = _colorTile(colors, rotation);
                      }

                      if (isPattern && !isPhoto) {
                        content = Stack(
                          fit: StackFit.expand,
                          children: [
                            content,
                            Positioned(
                              bottom: 4, right: 4,
                              child: Icon(Icons.texture, size: 14,
                                  color: Colors.white.withValues(alpha: 0.7)),
                            ),
                          ],
                        );
                      }

                      return GestureDetector(
                        onTap: () => Navigator.pop(ctx, wp),
                        child: content,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _colorTile(List<int> colors, int rotation) {
    final isDark = widget.isDark;
    if (colors.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF232E3C) : const Color(0xFFE0E0E0),
        ),
        child: Icon(Icons.image, color: isDark ? const Color(0xFF6C7883) : const Color(0xFF999999)),
      );
    }
    final flutterColors = colors.map((c) => Color(0xFF000000 | (c & 0xFFFFFF))).toList();
    return Container(
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

  IconData _iconForAction(String action) {
    for (final (v, _, ic) in _actions) {
      if (v == action) return ic;
    }
    return Icons.block;
  }

  String _labelForAction(String action) {
    for (final (v, l, _) in _actions) {
      if (v == action) return l;
    }
    return 'Disabled';
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return InkWell(
      onTap: () => _showQuickActionChooser(context),
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
              child: Icon(_iconForAction(currentAction),
                  size: SettingsStyle.iconInner, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Chat List Quick Action',
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            Text(
              _labelForAction(currentAction),
              style: TextStyle(fontSize: 14, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickActionChooser(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    String selected = currentAction;

    showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Chat List Quick Action'),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: _QuickActionPreview(
                    action: selected,
                    isDark: isDark,
                    accentColor: accentColor,
                  ),
                ),
                const SizedBox(height: 16),
                for (final (value, label, icon) in _actions)
                  InkWell(
                    onTap: () {
                      setDialogState(() => selected = value);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: 22, top: 6, bottom: 6, right: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Radio<String>(
                              value: value,
                              groupValue: selected,
                              onChanged: (v) {
                                if (v != null) {
                                  setDialogState(() => selected = v);
                                }
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
                            color: value == selected ? accentColor : subtextColor,
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
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    ).then((result) {
      if (result != null) onActionChanged(result);
    });
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

    final triggerLabel = action == 'disabled' ? 'Swipe' : 'Both';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(action),
        constraints: const BoxConstraints(maxWidth: 300),
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
            Positioned(
              bottom: 2,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  triggerLabel,
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? const Color(0xFF6C7883) : const Color(0xFF999999),
                    fontWeight: FontWeight.w500,
                  ),
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
        const Radius.circular(10),
      ),
      recvPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 46, 28, 40, 14),
        const Radius.circular(10),
      ),
      sentPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 48, 32, 14),
        const Radius.circular(10),
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
  final bool isPremium;
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
    this.isPremium = false,
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
            value: suggestAnimatedEmoji && isPremium,
            isDark: isDark,
            onChanged: isPremium ? onSuggestAnimatedEmojiChanged : (_) {},
            nested: true,
            premiumOnly: true,
            enabled: isPremium,
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
  final bool enabled;

  const _StickerCheckbox({
    required this.label,
    required this.value,
    required this.isDark,
    required this.onChanged,
    this.nested = false,
    this.premiumOnly = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final disabledColor = subtextColor.withValues(alpha: 0.5);

    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
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
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                activeColor: accentColor,
                side: BorderSide(
                  color: enabled ? subtextColor : disabledColor,
                  width: 1.5,
                ),
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
                style: TextStyle(
                  fontSize: 14,
                  color: enabled ? textColor : disabledColor,
                ),
              ),
            ),
            if (premiumOnly)
              Icon(
                Icons.lock_outline,
                size: 14,
                color: enabled ? const Color(0xFFFFA500) : disabledColor,
              ),
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
    builder: (ctx) => _StickerPackManager(
      accountId: account.id,
      engine: engine,
      isDark: isDark,
      type: type,
      title: title,
      textColor: textColor,
      subtextColor: subtextColor,
      accentColor: accentColor,
    ),
  );
}

class _StickerPackManager extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final bool isDark;
  final String type;
  final String title;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;

  const _StickerPackManager({
    required this.accountId,
    required this.engine,
    required this.isDark,
    required this.type,
    required this.title,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
  });

  @override
  State<_StickerPackManager> createState() => _StickerPackManagerState();
}

class _StickerPackManagerState extends State<_StickerPackManager> {
  List<StickerPackSummary>? _packs;
  bool _loading = true;
  bool _searchMode = false;
  String _searchQuery = '';
  List<StickerPackSummary>? _searchResults;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.type == 'emoji') {
      try {
        final emojiSets = await widget.engine.getInstalledEmojiSets(widget.accountId);
        final converted = emojiSets.map((e) => StickerPackSummary(
          setId: e.setId,
          accessHash: e.accessHash,
          title: e.title,
          shortName: e.shortName,
          count: e.count,
          installed: e.installed,
          stickers: e.stickers,
        )).toList();
        if (mounted) setState(() { _packs = converted; _loading = false; });
      } catch (_) {
        if (mounted) {
          setState(() { _packs = []; _loading = false; });
          showTelegramToast(context, 'Failed to load emoji sets');
        }
      }
    } else {
      final packs = await widget.engine.getInstalledStickerPacks(widget.accountId);
      if (mounted) setState(() { _packs = packs; _loading = false; });
    }
  }

  Future<void> _removePack(int index) async {
    final pack = _packs![index];
    try {
      await widget.engine.uninstallStickerSet(widget.accountId, pack.setId, pack.accessHash);
      setState(() => _packs!.removeAt(index));
    } catch (_) {
      if (mounted) showTelegramToast(context, 'Failed to remove pack');
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _packs!.removeAt(oldIndex);
      _packs!.insert(newIndex, item);
    });
    if (_packs != null) {
      final order = _packs!.map((p) => p.setId).toList();
      context.read<EngineService>().reorderStickerSets(widget.accountId, order);
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() { _searchResults = null; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await widget.engine.searchStickerSets(widget.accountId, query);
      if (mounted) setState(() { _searchResults = results; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _installPack(StickerPackSummary pack) async {
    try {
      await widget.engine.installStickerSet(widget.accountId, pack.setId, pack.accessHash);
      if (mounted) {
        showTelegramToast(context, '${pack.title} added');
        _load();
      }
    } catch (_) {
      if (mounted) showTelegramToast(context, 'Failed to add pack');
    }
  }

  @override
  Widget build(BuildContext context) {
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
                if (_searchMode)
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      style: TextStyle(color: widget.textColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search ${widget.type}...',
                        hintStyle: TextStyle(color: widget.subtextColor),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) {
                        _searchQuery = v;
                        _search(v);
                      },
                    ),
                  )
                else
                  Text(widget.title, style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: widget.textColor)),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _searchMode ? Icons.close : Icons.add,
                    color: _searchMode ? widget.subtextColor : widget.accentColor,
                  ),
                  onPressed: () => setState(() {
                    _searchMode = !_searchMode;
                    if (!_searchMode) {
                      _searchResults = null;
                      _searchQuery = '';
                    }
                  }),
                ),
                if (!_searchMode)
                  IconButton(
                    icon: Icon(Icons.close, color: widget.subtextColor),
                    onPressed: () => Navigator.pop(ctx),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _searchMode
                ? _buildSearchResults(scrollController)
                : _loading
                ? Center(child: CircularProgressIndicator(color: widget.accentColor))
                : _packs == null || _packs!.isEmpty
                    ? Center(
                        child: Text(
                          'No ${widget.type == 'stickers' ? 'sticker packs' : 'emoji sets'} installed',
                          style: TextStyle(color: widget.subtextColor),
                        ),
                      )
                    : ReorderableListView.builder(
                        scrollController: scrollController,
                        itemCount: _packs!.length,
                        onReorder: _reorder,
                        itemBuilder: (ctx, i) {
                          final pack = _packs![i];
                          return ListTile(
                            key: ValueKey(pack.setId),
                            leading: pack.stickers.isNotEmpty && pack.stickers.first.fileId.isNotEmpty
                                ? Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(child: Text(
                                        pack.stickers.first.emoji,
                                        style: const TextStyle(fontSize: 24))),
                                  )
                                : Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(Icons.sticky_note_2, color: widget.subtextColor),
                                  ),
                            title: Text(pack.title,
                                style: TextStyle(color: widget.textColor, fontSize: 14)),
                            subtitle: Text(
                              '${pack.count} ${widget.type == 'stickers' ? 'stickers' : 'emoji'}',
                              style: TextStyle(color: widget.subtextColor, fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, size: 20,
                                  color: widget.subtextColor),
                              onPressed: () => _removePack(i),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ScrollController scrollController) {
    if (_searching) {
      return Center(child: CircularProgressIndicator(color: widget.accentColor));
    }
    if (_searchQuery.isEmpty) {
      return Center(
        child: Text(
          'Search for ${widget.type} to add',
          style: TextStyle(color: widget.subtextColor),
        ),
      );
    }
    if (_searchResults == null || _searchResults!.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(color: widget.subtextColor),
        ),
      );
    }
    final installedIds = _packs?.map((p) => p.setId).toSet() ?? {};
    return ListView.builder(
      controller: scrollController,
      itemCount: _searchResults!.length,
      itemBuilder: (ctx, i) {
        final pack = _searchResults![i];
        final isInstalled = installedIds.contains(pack.setId);
        return ListTile(
          leading: pack.stickers.isNotEmpty && pack.stickers.first.emoji.isNotEmpty
              ? Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(child: Text(pack.stickers.first.emoji,
                      style: const TextStyle(fontSize: 24))),
                )
              : Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.sticky_note_2, color: widget.subtextColor),
                ),
          title: Text(pack.title,
              style: TextStyle(color: widget.textColor, fontSize: 14)),
          subtitle: Text(
            '${pack.count} ${widget.type == 'stickers' ? 'stickers' : 'emoji'}',
            style: TextStyle(color: widget.subtextColor, fontSize: 12),
          ),
          trailing: isInstalled
              ? Icon(Icons.check, size: 20, color: widget.accentColor)
              : IconButton(
                  icon: Icon(Icons.add, size: 20, color: widget.accentColor),
                  onPressed: () => _installPack(pack),
                ),
        );
      },
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

const _reactionNames = <String, String>{
  '❤️': 'Heart',
  '👍': 'Thumbs Up',
  '👎': 'Thumbs Down',
  '🔥': 'Fire',
  '🎉': 'Party Popper',
  '😢': 'Crying Face',
  '💩': 'Pile of Poo',
  '👏': 'Clapping Hands',
  '😂': 'Laughing',
  '🤔': 'Thinking',
  '🤯': 'Mind Blown',
  '😱': 'Screaming',
  '🥰': 'Smiling with Hearts',
  '😡': 'Pouting Face',
  '😭': 'Sobbing',
  '🤩': 'Star-Struck',
  '🤮': 'Vomiting',
  '💯': 'Hundred',
  '🤣': 'ROFL',
  '⚡': 'Lightning',
  '🍌': 'Banana',
  '🏆': 'Trophy',
  '💔': 'Broken Heart',
  '🤨': 'Raised Eyebrow',
  '😐': 'Neutral Face',
  '🍓': 'Strawberry',
  '🍾': 'Champagne',
  '💋': 'Kiss Mark',
  '🖕': 'Middle Finger',
  '😈': 'Smiling Devil',
  '😴': 'Sleeping',
  '🤓': 'Nerd Face',
  '👻': 'Ghost',
  '👨‍💻': 'Technologist',
  '👀': 'Eyes',
  '🎃': 'Jack-O-Lantern',
  '🙈': 'See-No-Evil',
  '😇': 'Angel',
  '😨': 'Fearful',
  '🤝': 'Handshake',
  '✍️': 'Writing Hand',
  '🤗': 'Hugging Face',
  '🫡': 'Saluting Face',
  '🎅': 'Santa Claus',
  '🎄': 'Christmas Tree',
  '☃️': 'Snowman',
  '💅': 'Nail Polish',
  '🤪': 'Zany Face',
  '🗿': 'Moai',
  '🆒': 'Cool',
  '💘': 'Heart with Arrow',
  '🙉': 'Hear-No-Evil',
  '🦄': 'Unicorn',
  '😘': 'Kissing Face',
  '💊': 'Pill',
  '🙊': 'Speak-No-Evil',
  '😎': 'Cool Face',
  '👾': 'Alien Monster',
  '🤷‍♂️': 'Man Shrugging',
  '🤷': 'Person Shrugging',
  '🤷‍♀️': 'Woman Shrugging',
};

class _ReactionChooserButton extends StatefulWidget {
  final String currentReaction;
  final bool isDark;
  final ValueChanged<String> onReactionSelected;

  const _ReactionChooserButton({
    required this.currentReaction,
    required this.isDark,
    required this.onReactionSelected,
  });

  @override
  State<_ReactionChooserButton> createState() => _ReactionChooserButtonState();
}

class _ReactionChooserButtonState extends State<_ReactionChooserButton> {
  List<String> _reactions = [];
  bool _loaded = false;
  bool _loadError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded && !_loadError) _loadReactions();
  }

  Future<void> _loadReactions() async {
    try {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      final account = appState.activeAccount;
      if (account != null) {
        final available = await engine.getAvailableReactions(account.id);
        if (mounted) {
          setState(() {
            _reactions = available;
            _loaded = true;
          });
          return;
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
    _loaded = true;
  }

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
    final subtextColor = textColor.withValues(alpha: 0.5);
    final accentColor = context.palette.windowBgActive;
    final dividerColor = widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFE8E8E8);
    final hoverColor = widget.isDark ? const Color(0xFF232E3C) : const Color(0xFFF0F0F0);

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
        maxChildSize: 0.85,
        expand: false,
        builder: (sheetCtx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quick Reaction',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
                        const SizedBox(height: 4),
                        Text('Choose a reaction that will be used when you quickly react to messages.',
                          style: TextStyle(fontSize: 13, color: subtextColor)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: subtextColor, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: dividerColor),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: EdgeInsets.zero,
                itemCount: _reactions.length,
                itemBuilder: (lCtx, i) {
                  final emoji = _reactions[i];
                  final isSelected = emoji == widget.currentReaction;
                  return InkWell(
                    onTap: () {
                      widget.onReactionSelected(emoji);
                      final appState = context.read<AppState>();
                      final account = appState.activeAccount;
                      if (account != null) {
                        context.read<EngineService>().setDefaultReaction(account.id, emoji);
                      }
                      Navigator.pop(ctx);
                    },
                    splashColor: hoverColor,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      color: isSelected ? accentColor.withValues(alpha: 0.08) : null,
                      child: Row(
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _reactionNames[emoji] ?? emoji,
                              style: TextStyle(fontSize: 15, color: textColor),
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle, color: accentColor, size: 22),
                        ],
                      ),
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
      builder: (ctx) => ArchiveSettingsBox(
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

class ArchiveSettingsBox extends StatefulWidget {
  final bool isDark;
  final Color accentColor;

  const ArchiveSettingsBox({
    super.key,
    required this.isDark,
    required this.accentColor,
  });

  @override
  State<ArchiveSettingsBox> createState() => _ArchiveSettingsBoxState();
}

class _ArchiveSettingsBoxState extends State<ArchiveSettingsBox> {
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

  Future<void> _save() async {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    try {
      await engine.setArchiveSettings(
        account.id,
        archiveAndMute: _archiveAndMute,
        keepArchivedUnmuted: _keepUnmuted,
        keepArchivedFolders: _keepFolders,
      );
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to save archive settings');
        _loadArchiveSettings();
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
                Expanded(
                  child: Text(
                    'Disable filtering',
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

// ── Background Preview Box (for "Choose from file") ──

class _BackgroundPreviewBox extends StatefulWidget {
  final Uint8List? imageBytes;
  final bool initialBlurred;
  final bool initialTiled;
  final bool isLoading;
  final Future<Uint8List?> Function()? onLoadFull;

  const _BackgroundPreviewBox({
    this.imageBytes,
    required this.initialBlurred,
    required this.initialTiled,
    this.isLoading = false,
    this.onLoadFull,
  });

  @override
  State<_BackgroundPreviewBox> createState() => _BackgroundPreviewBoxState();
}

class _BackgroundPreviewBoxState extends State<_BackgroundPreviewBox>
    with SingleTickerProviderStateMixin {
  late bool _blurred;
  late bool _tiled;
  Uint8List? _fullBytes;
  bool _downloading = false;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _blurred = widget.initialBlurred;
    _tiled = widget.initialTiled;
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.onLoadFull != null) {
      _downloadFull();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _downloadFull() async {
    setState(() => _downloading = true);
    _progressController.forward();
    try {
      final bytes = await widget.onLoadFull!();
      if (mounted && bytes != null) {
        _progressController.stop();
        setState(() {
          _fullBytes = bytes;
          _downloading = false;
        });
      } else if (mounted) {
        _progressController.stop();
        setState(() => _downloading = false);
      }
    } catch (_) {
      if (mounted) {
        _progressController.stop();
        setState(() => _downloading = false);
      }
    }
  }

  Uint8List? get _displayBytes => _fullBytes ?? widget.imageBytes;

  Widget _wrapBlur({required Widget child}) {
    if (!_blurred) return child;
    return ImageFiltered(
      imageFilter: ui_dart.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;
    final displayBytes = _displayBytes;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 550),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Background Preview',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: displayBytes != null
                      ? _wrapBlur(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                displayBytes,
                                fit: _tiled ? BoxFit.none : BoxFit.cover,
                                repeat: _tiled ? ImageRepeat.repeat : ImageRepeat.noRepeat,
                              ),
                              if (_downloading)
                                Container(
                                  color: Colors.black26,
                                  child: Center(
                                    child: AnimatedBuilder(
                                      animation: _progressController,
                                      builder: (context, _) => CircularProgressIndicator(
                                        strokeWidth: 2,
                                        value: Curves.easeOut.transform(_progressController.value) * 0.85,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : Container(
                          color: isDark ? const Color(0xFF232E3C) : const Color(0xFFE0E0E0),
                          child: _downloading
                              ? Center(
                                  child: AnimatedBuilder(
                                    animation: _progressController,
                                    builder: (context, _) => CircularProgressIndicator(
                                      strokeWidth: 2,
                                      value: Curves.easeOut.transform(_progressController.value) * 0.85,
                                    ),
                                  ),
                                )
                              : Icon(Icons.image, size: 48,
                                  color: isDark ? const Color(0xFF6C7883) : const Color(0xFF999999)),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCheckbox(
                label: 'Blur wallpaper',
                value: _blurred,
                isDark: isDark,
                onChanged: (v) => setState(() => _blurred = v),
              ),
              _SettingsCheckbox(
                label: 'Tile wallpaper',
                value: _tiled,
                isDark: isDark,
                onChanged: (v) => setState(() => _tiled = v),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: accentColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop({
                      'blurred': _blurred,
                      'tiled': _tiled,
                      if (_fullBytes != null) 'full_bytes': _fullBytes,
                    }),
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
