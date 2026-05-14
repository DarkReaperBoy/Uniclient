import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';
import '../theme/theme_file.dart';
import 'color_picker_box.dart';
import 'confirm_box.dart';
import 'telegram_toast.dart';
import '../theme/theme_name_generator.dart';
import '../theme/theme_preview.dart';

class ThemeEditorScreen extends StatefulWidget {
  final TelegramPalette palette;
  final void Function(TelegramPalette palette) onPaletteChanged;
  final CloudThemeInfo? cloudTheme;

  const ThemeEditorScreen({
    super.key,
    required this.palette,
    required this.onPaletteChanged,
    this.cloudTheme,
  });

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late Map<String, Color> _colorMap;
  late TelegramPalette _currentPalette;
  Map<String, String> _referenceChain = {};
  final _searchController = TextEditingController();
  String _filter = '';
  int _focusedIndex = -1;
  final _scrollController = ScrollController();
  final _listFocusNode = FocusNode();
  bool _showPreview = false;
  bool _isDirty = false;
  late Map<String, Color> _originalColorMap;
  Set<String> _explicitTokens = {};
  bool _sortedByAccent = false;
  String? _themeFilePath;

  List<_ListItem>? _cachedItems;

  String? _editingToken;
  Color? _editingColor;
  final _hexEditController = TextEditingController();
  final _menuButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentPalette = widget.palette;
    _colorMap = paletteToMap(_currentPalette);
    _originalColorMap = Map.of(_colorMap);
    _explicitTokens = _colorMap.keys.toSet();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _listFocusNode.dispose();
    _hexEditController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final text = _searchController.text;
    if (text == ':sort-for-accent') {
      _sortByAccentDistance();
      _searchController.clear();
      return;
    }
    setState(() {
      _filter = text.toLowerCase();
      _focusedIndex = -1;
      _cachedItems = null;
    });
  }

  void _sortByAccentDistance() {
    final accent = HSLColor.fromColor(_currentPalette.windowBgActive);
    final entries = _colorMap.entries.toList();
    entries.sort((a, b) {
      final da = _hslDistance(accent, HSLColor.fromColor(a.value));
      final db = _hslDistance(accent, HSLColor.fromColor(b.value));
      return da.compareTo(db);
    });
    final newMap = <String, Color>{};
    for (final e in entries) {
      newMap[e.key] = e.value;
    }
    setState(() {
      _colorMap = newMap;
      _sortedByAccent = true;
      _cachedItems = null;
    });
  }

  double _hslDistance(HSLColor a, HSLColor b) {
    final dh = (a.hue - b.hue).abs();
    final minDh = dh < 180 ? dh : 360 - dh;
    final ds = (a.saturation - b.saturation).abs();
    final dl = (a.lightness - b.lightness).abs();
    return minDh / 360.0 + ds + dl;
  }

  static final _searchSplitter = RegExp(r'[\s\-_+.,;:!#@()\[\]{}<>]+');

  bool _matchesFilter(String key) {
    if (_filter.isEmpty) return true;
    final desc = _tokenDescription(key) ?? '';
    final hex = _colorToHexString(_colorMap[key]!);
    final ref = _referenceChain[key] ?? '';
    final searchText = '$key $ref $desc $hex'.toLowerCase();
    final searchWords = searchText.split(_searchSplitter).where((w) => w.isNotEmpty);
    final queryWords = _filter.split(_searchSplitter).where((w) => w.isNotEmpty);
    return queryWords.every((qw) => searchWords.any((sw) => sw.startsWith(qw)));
  }

  List<_ListItem> get _listItems {
    if (_cachedItems != null) return _cachedItems!;
    final allEntries = _colorMap.entries.toList();
    final existing = <MapEntry<String, Color>>[];
    final newTokens = <MapEntry<String, Color>>[];

    for (final entry in allEntries) {
      if (!_matchesFilter(entry.key)) continue;
      if (_explicitTokens.contains(entry.key)) {
        existing.add(entry);
      } else {
        newTokens.add(entry);
      }
    }

    final items = <_ListItem>[];
    if (existing.isNotEmpty) {
      items.add(_ListItem.header('Existing'));
      for (final e in existing) {
        items.add(_ListItem.entry(e));
      }
    }
    if (newTokens.isNotEmpty) {
      items.add(_ListItem.header('New color scheme keys'));
      for (final e in newTokens) {
        items.add(_ListItem.entry(e));
      }
    }
    _cachedItems = items;
    return items;
  }

  void _updateColor(String token, Color color) {
    setState(() {
      _colorMap[token] = color;
      _currentPalette = paletteFromMap(_colorMap, widget.palette);
      _isDirty = true;
      _explicitTokens.add(token);
      _cachedItems = null;
    });
    widget.onPaletteChanged(_currentPalette);
  }

  void _openColorPicker(String token, Color currentColor) {
    if (_editingToken == token) return;
    setState(() {
      _editingToken = token;
      _editingColor = currentColor;
      _hexEditController.text = _colorToHexString(currentColor);
    });
  }

  void _openColorPickerDialog(String token, Color currentColor) async {
    final result = await showColorPickerBox(
      context: context,
      initialColor: currentColor,
      title: token,
      showOpacity: true,
    );
    if (result != null && mounted) {
      _updateColor(token, result);
      if (_editingToken == token) {
        setState(() {
          _editingColor = result;
          _hexEditController.text = _colorToHexString(result);
        });
      }
    }
  }

  void _closeInlineEditor() {
    setState(() {
      _editingToken = null;
      _editingColor = null;
    });
  }

  void _applyHexEdit() {
    if (_editingToken == null) return;
    final hex = _hexEditController.text.trim();
    final color = _parseHexColor(hex);
    if (color != null) {
      _updateColor(_editingToken!, color);
      setState(() => _editingColor = color);
    }
  }

  Color? _parseHexColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length == 8) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return Color(v);
    }
    return null;
  }

  void _handleClose() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    showConfirmBox(
      context,
      text: 'Are you sure? Unsaved changes will be discarded.',
      confirmText: 'Close',
      onConfirm: () {
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  void _handleExport() async {
    final result = await showDialog<_ExportResult>(
      context: context,
      builder: (ctx) => _SaveThemeBox(palette: _currentPalette),
    );
    if (result == null || !mounted) return;

    final bytes = exportThemeFile(result.data);
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final safeName = result.title
        .replaceAll(RegExp(r'[^\w\-. ]'), '')
        .replaceAll(' ', '_')
        .toLowerCase();
    final fileName = safeName.isNotEmpty ? safeName : 'theme';
    final path = '$dir/$fileName.tdesktop-theme';
    await File(path).writeAsBytes(bytes);
    if (mounted) {
      setState(() {
        _isDirty = false;
        _themeFilePath = path;
      });
      showTelegramToast(context, 'Saved to $path');
    }
  }

  void _handleSaveToCloud() async {
    final existingCloud = widget.cloudTheme;
    final existingMeta = existingCloud != null && existingCloud.id != 0
        ? CloudThemeMeta(id: existingCloud.id, accessHash: 0)
        : null;

    final result = await showDialog<_CloudSaveResult>(
      context: context,
      builder: (ctx) => _SaveThemeBox(
        palette: _currentPalette,
        cloudSave: true,
        cloudMeta: existingMeta,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      final accountId = appState.activeAccountId;
      if (accountId.isEmpty) {
        showTelegramToast(context, 'No active account');
        return;
      }

      final themeBytes = exportThemeFile(ThemeFileData(
        palette: _currentPalette,
        backgroundImage: result.backgroundImage,
        backgroundTiled: result.backgroundTiled,
        cloudMeta: result.cloudMeta,
      ));

      final isUpdate = existingCloud != null && existingCloud.id != 0 && existingCloud.isCreator;
      if (isUpdate) {
        await engine.updateCloudTheme(
          accountId,
          existingCloud.id,
          result.title,
          result.slug,
          themeBytes,
        );
      } else {
        await engine.createCloudTheme(
          accountId,
          result.title,
          result.slug,
          themeBytes,
        );
      }
      if (mounted) {
        setState(() => _isDirty = false);
        showTelegramToast(context, isUpdate ? 'Theme updated' : 'Theme uploaded to cloud');
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Upload failed: $e');
      }
    }
  }

  void _handleImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    Uint8List? bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return;

    final parsed = parseThemeFile(bytes, fallback: widget.palette);
    if (parsed == null) return;

    setState(() {
      _currentPalette = parsed.palette;
      _colorMap = paletteToMap(_currentPalette);
      _referenceChain = parsed.referenceChain;
      _explicitTokens = parsed.explicitTokens.isNotEmpty
          ? parsed.explicitTokens
          : _colorMap.keys.toSet();
      _isDirty = true;
      _sortedByAccent = false;
      _cachedItems = null;
      if (file.path != null) _themeFilePath = file.path;
    });
    widget.onPaletteChanged(_currentPalette);
  }

  void _showMenu() {
    final RenderBox? button = _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final isDark = _currentPalette.isDark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : Colors.black;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;

    showMenu<String>(
      context: context,
      position: position,
      color: bgColor,
      items: [
        PopupMenuItem<String>(
          value: 'export',
          child: Text('Export Theme', style: TextStyle(color: textColor)),
        ),
        PopupMenuItem<String>(
          value: 'import',
          child: Text('Import Theme', style: TextStyle(color: textColor)),
        ),
        PopupMenuItem<String>(
          value: 'show',
          enabled: _themeFilePath != null,
          child: Text('Show in Folder', style: TextStyle(
            color: _themeFilePath != null ? textColor : textColor.withAlpha(100),
          )),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'export':
          _handleExport();
        case 'import':
          _handleImport();
        case 'show':
          _showInFolder();
      }
    });
  }

  void _showInFolder() {
    if (_themeFilePath == null) return;
    final dir = File(_themeFilePath!).parent.path;
    if (Platform.isLinux) {
      Process.run('xdg-open', [dir]);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', _themeFilePath!]);
    } else if (Platform.isWindows) {
      Process.run('explorer', ['/select,', _themeFilePath!]);
    }
  }

  double _estimateRowHeight(String? token) {
    final hasDesc = token != null && (_tokenDescription(token)?.isNotEmpty ?? false);
    const base = _kRowMarginTop + _kSwatchHeight + _kRowMarginBottom;
    if (!hasDesc) return base;
    return base + _kDescriptionSkip + 28.0;
  }

  double _estimateItemHeight(_ListItem item) {
    if (item.type == _ListItemType.header) return 42.0;
    return _estimateRowHeight(item.entry?.key);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final items = _listItems;
    final entryItems =
        items.where((i) => i.type == _ListItemType.entry).toList();
    if (entryItems.isEmpty) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _focusedIndex = (_focusedIndex + 1).clamp(0, entryItems.length - 1);
      });
      _ensureVisible(_focusedIndex, items);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _focusedIndex = (_focusedIndex - 1).clamp(0, entryItems.length - 1);
      });
      _ensureVisible(_focusedIndex, items);
    } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      final viewport = _scrollController.hasClients
          ? _scrollController.position.viewportDimension
          : 400.0;
      final defaultHeight = _estimateRowHeight(null);
      final skipCount = max(1, (viewport / defaultHeight).ceil());
      setState(() {
        _focusedIndex =
            (_focusedIndex + skipCount).clamp(0, entryItems.length - 1);
      });
      _ensureVisible(_focusedIndex, items);
    } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      final viewport = _scrollController.hasClients
          ? _scrollController.position.viewportDimension
          : 400.0;
      final defaultHeight = _estimateRowHeight(null);
      final skipCount = max(1, (viewport / defaultHeight).ceil());
      setState(() {
        _focusedIndex =
            (_focusedIndex - skipCount).clamp(0, entryItems.length - 1);
      });
      _ensureVisible(_focusedIndex, items);
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedIndex >= 0 && _focusedIndex < entryItems.length) {
        final entry = entryItems[_focusedIndex].entry!;
        _openColorPicker(entry.key, entry.value);
      }
    }
  }

  void _ensureVisible(int entryIndex, List<_ListItem> items) {
    if (!_scrollController.hasClients) return;
    var offset = 0.0;
    var currentEntryIdx = -1;
    double targetOffset = 0;
    double targetHeight = _estimateRowHeight(null);

    for (final item in items) {
      final h = _estimateItemHeight(item);
      if (item.type == _ListItemType.entry) {
        currentEntryIdx++;
        if (currentEntryIdx == entryIndex) {
          targetOffset = offset;
          targetHeight = h;
          break;
        }
      }
      offset += h;
    }

    final viewportExtent = _scrollController.position.viewportDimension;
    final current = _scrollController.offset;
    if (targetOffset < current) {
      _scrollController.animateTo(targetOffset,
          duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    } else if (targetOffset + targetHeight > current + viewportExtent) {
      _scrollController.animateTo(
          targetOffset + targetHeight - viewportExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut);
    }
  }

  Widget _buildInlineColorEditor() {
    final token = _editingToken!;
    final color = _editingColor!;
    final bgColor = _currentPalette.topBarBg;
    final textColor = _currentPalette.windowBoldFg;
    final subtextColor = _currentPalette.windowSubTextFg;
    final accentColor = _currentPalette.windowBgActive;
    final shadowColor = _currentPalette.shadowFg;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: shadowColor, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  token,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: subtextColor, size: 18),
                onPressed: _closeInlineEditor,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: shadowColor),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _hexEditController,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: _currentPalette.isDark
                          ? const Color(0xFF242F3D)
                          : const Color(0xFFF1F3F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: accentColor, width: 1),
                      ),
                    ),
                    onSubmitted: (_) => _applyHexEdit(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(Icons.check, color: accentColor, size: 20),
                onPressed: _applyHexEdit,
                tooltip: 'Apply',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: Icon(Icons.palette_outlined, color: accentColor, size: 20),
                onPressed: () => _openColorPickerDialog(token, color),
                tooltip: 'Full editor',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _currentPalette.dialogsBg;
    final bgOver = _currentPalette.dialogsBgOver;
    final textColor = _currentPalette.windowBoldFg;
    final subtextColor = _currentPalette.windowSubTextFg;
    final accentColor = _currentPalette.windowBgActive;
    final shadowColor = _currentPalette.shadowFg;
    final items = _listItems;

    int entryIndex = -1;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: _currentPalette.topBarBg,
              border:
                  Border(bottom: BorderSide(color: shadowColor, width: 1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: textColor, size: 22),
                  onPressed: _handleClose,
                  tooltip: 'Close',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Theme Editor',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showPreview ? Icons.visibility_off : Icons.visibility,
                    color: _showPreview ? accentColor : textColor,
                    size: 22,
                  ),
                  onPressed: () =>
                      setState(() => _showPreview = !_showPreview),
                  tooltip: _showPreview ? 'Hide Preview' : 'Show Preview',
                ),
                IconButton(
                  key: _menuButtonKey,
                  icon: Icon(Icons.more_vert, color: textColor, size: 22),
                  onPressed: _showMenu,
                  tooltip: 'Options',
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _currentPalette.topBarBg,
              border:
                  Border(bottom: BorderSide(color: shadowColor, width: 1)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search tokens...',
                hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                prefixIcon:
                    Icon(Icons.search, color: subtextColor, size: 20),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: subtextColor, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: _currentPalette.isDark
                    ? const Color(0xFF242F3D)
                    : const Color(0xFFF1F3F5),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_showPreview)
            Container(
              decoration: BoxDecoration(
                color: _currentPalette.windowBg,
                border: Border(
                    bottom: BorderSide(color: shadowColor, width: 1)),
              ),
              padding: const EdgeInsets.all(8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: AspectRatio(
                    aspectRatio: 903 / 584,
                    child: ThemePreviewImage(palette: _currentPalette),
                  ),
                ),
              ),
            ),
          Expanded(
            child: KeyboardListener(
              focusNode: _listFocusNode,
              onKeyEvent: _handleKeyEvent,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item.type == _ListItemType.header) {
                    return _SectionHeader(
                      title: item.headerTitle!,
                      palette: _currentPalette,
                    );
                  }
                  entryIndex++;
                  final entry = item.entry!;
                  final isFocused = entryIndex == _focusedIndex;
                  final isEditing = _editingToken == entry.key;
                  final desc = _tokenDescription(entry.key);

                  return _PaletteEntryRow(
                    token: entry.key,
                    color: entry.value,
                    referenceName: _referenceChain[entry.key],
                    description: desc,
                    backgroundColor:
                        isEditing ? accentColor.withAlpha(30) : (isFocused ? bgOver : bgColor),
                    textColor: textColor,
                    subtextColor: subtextColor,
                    hoverColor: bgOver,
                    accentColor: accentColor,
                    onTap: () {
                      final idx = entryIndex;
                      setState(() => _focusedIndex = idx);
                      _listFocusNode.requestFocus();
                      _openColorPicker(entry.key, entry.value);
                    },
                  );
                },
              ),
            ),
          ),
          if (_editingToken != null && _editingColor != null)
            _buildInlineColorEditor(),
          Container(
            decoration: BoxDecoration(
              color: accentColor,
              boxShadow: [
                BoxShadow(
                  color: shadowColor.withAlpha(80),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _handleSaveToCloud,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  child: Text(
                    'SAVE THEME',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _currentPalette.activeButtonFg,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── List item model ──

enum _ListItemType { header, entry }

class _ListItem {
  final _ListItemType type;
  final MapEntry<String, Color>? entry;
  final String? headerTitle;

  _ListItem.header(this.headerTitle)
      : type = _ListItemType.header,
        entry = null;
  _ListItem.entry(this.entry)
      : type = _ListItemType.entry,
        headerTitle = null;
}

// ── Section header ──

class _SectionHeader extends StatelessWidget {
  final String title;
  final TelegramPalette palette;

  const _SectionHeader({required this.title, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(17, 14, 17, 6),
      color: palette.windowBg,
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: palette.windowActiveTextFg,
        ),
      ),
    );
  }
}

// ── Palette entry row ──

const double _kSwatchWidth = 90;
const double _kSwatchHeight = 51;
const double _kRowMarginLeft = 17;
const double _kRowMarginRight = 17;
const double _kRowMarginTop = 10;
const double _kRowMarginBottom = 10;
const double _kDescriptionSkip = 10;

class _PaletteEntryRow extends StatefulWidget {
  final String token;
  final Color color;
  final Color backgroundColor;
  final Color textColor;
  final Color subtextColor;
  final Color hoverColor;
  final Color accentColor;
  final String? referenceName;
  final String? description;
  final VoidCallback onTap;

  const _PaletteEntryRow({
    required this.token,
    required this.color,
    required this.backgroundColor,
    required this.textColor,
    required this.subtextColor,
    required this.hoverColor,
    required this.accentColor,
    required this.onTap,
    this.referenceName,
    this.description,
  });

  @override
  State<_PaletteEntryRow> createState() => _PaletteEntryRowState();
}

class _PaletteEntryRowState extends State<_PaletteEntryRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg =
        _hovered ? widget.hoverColor : widget.backgroundColor;
    final hasDescription =
        widget.description != null && widget.description!.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: widget.onTap,
          splashColor: widget.accentColor.withAlpha(40),
          highlightColor: widget.accentColor.withAlpha(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              _kRowMarginLeft,
              _kRowMarginTop,
              _kRowMarginRight,
              _kRowMarginBottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.token,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: widget.textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.referenceName != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          '= ${widget.referenceName}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: widget.subtextColor.withAlpha(180),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        _colorToHexString(widget.color),
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.subtextColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (hasDescription) ...[
                        SizedBox(height: _kDescriptionSkip),
                        Text(
                          widget.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.subtextColor.withAlpha(150),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ColorSwatch(
                    color: widget.color,
                    width: _kSwatchWidth,
                    height: _kSwatchHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Color swatch ──

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final double width;
  final double height;

  const _ColorSwatch(
      {required this.color, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 3,
              offset: const Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          painter: _SwatchPainter(color),
          size: Size(width, height),
        ),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  final Color color;
  _SwatchPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a < 1.0) {
      const checkerSize = 4.0;
      final lightPaint = Paint()..color = const Color(0xFFCCCCCC);
      final darkPaint = Paint()..color = const Color(0xFF999999);
      for (double y = 0; y < size.height; y += checkerSize) {
        for (double x = 0; x < size.width; x += checkerSize) {
          final isLight =
              ((x ~/ checkerSize) + (y ~/ checkerSize)) % 2 == 0;
          canvas.drawRect(
            Rect.fromLTWH(x, y, checkerSize, checkerSize),
            isLight ? lightPaint : darkPaint,
          );
        }
      }
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => color != old.color;
}

// ── Token description helper ──

String? _tokenDescription(String token) {
  final parts = <String>[];
  final buf = StringBuffer();
  for (int i = 0; i < token.length; i++) {
    final ch = token[i];
    if (ch.toUpperCase() == ch && ch.toLowerCase() != ch && buf.isNotEmpty) {
      parts.add(buf.toString());
      buf.clear();
    }
    buf.write(ch.toLowerCase());
  }
  if (buf.isNotEmpty) parts.add(buf.toString());

  if (parts.length <= 1) return null;

  const abbrevs = {
    'bg': 'background',
    'fg': 'foreground',
    'btn': 'button',
    'msg': 'message',
    'dlg': 'dialog',
    'rpl': 'reply',
    'fwd': 'forward',
    'sel': 'selection',
    'st': 'status',
    'txt': 'text',
    'wp': 'webpage',
    'sb': 'scrollbar',
    'ct': 'contact',
  };
  final expanded = parts.map((p) => abbrevs[p] ?? p).toList();
  final desc = expanded.join(' ');
  return desc[0].toUpperCase() + desc.substring(1);
}

String _colorToHexString(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  final a = (c.a * 255).round();
  if (a == 255) {
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'
      '${a.toRadixString(16).padLeft(2, '0')}';
}

// ── Random slug generation ──

String _generateSlug() {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  const alphanumeric =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const length = 16;
  final rng = Random.secure();
  final buf = StringBuffer();
  buf.write(letters[rng.nextInt(letters.length)]);
  for (int i = 1; i < length; i++) {
    buf.write(alphanumeric[rng.nextInt(alphanumeric.length)]);
  }
  return buf.toString();
}

// ── Export result (local save) ──

class _ExportResult {
  final ThemeFileData data;
  final String title;
  _ExportResult(this.data, this.title);
}

// ── Cloud save result ──

class _CloudSaveResult {
  final String title;
  final String slug;
  final Uint8List? backgroundImage;
  final bool backgroundTiled;
  final CloudThemeMeta? cloudMeta;

  _CloudSaveResult({
    required this.title,
    required this.slug,
    this.backgroundImage,
    this.backgroundTiled = false,
    this.cloudMeta,
  });
}

// ── SaveThemeBox Dialog (spec §25.6.5) ──

const _kBoxWideWidth = 364.0;
const _kMaxSlugSize = 64;
const _kMinSlugSize = 5;
const _kJpegQuality = 87;
const _kSlugPattern = r'^[a-zA-Z0-9_]+$';

Uint8List _encodeAsJpeg87(Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return imageBytes;
  return Uint8List.fromList(img.encodeJpg(decoded, quality: _kJpegQuality));
}

class _SaveThemeBox extends StatefulWidget {
  final TelegramPalette palette;
  final Uint8List? existingBackground;
  final bool existingTiled;
  final CloudThemeMeta? cloudMeta;
  final bool cloudSave;

  const _SaveThemeBox({
    required this.palette,
    this.existingBackground,
    this.existingTiled = false,
    this.cloudMeta,
    this.cloudSave = false,
  });

  @override
  State<_SaveThemeBox> createState() => _SaveThemeBoxState();
}

class _SaveThemeBoxState extends State<_SaveThemeBox> {
  late final TextEditingController _nameController;
  late final TextEditingController _slugController;
  Uint8List? _backgroundImage;
  bool _tiled = false;
  String? _slugError;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final defaultName = widget.cloudMeta != null
        ? ''
        : generateThemeName(widget.palette.windowBgActive);
    _nameController = TextEditingController(text: defaultName);
    _slugController = TextEditingController(text: _generateSlug());
    _backgroundImage = widget.existingBackground;
    _tiled = widget.existingTiled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  bool _validateSlug(String slug) {
    if (slug.isEmpty) {
      setState(() => _slugError = 'Link is required');
      return false;
    }
    if (slug.length < _kMinSlugSize) {
      setState(() => _slugError = 'At least $_kMinSlugSize characters');
      return false;
    }
    if (slug.length > _kMaxSlugSize) {
      setState(() => _slugError = 'At most $_kMaxSlugSize characters');
      return false;
    }
    if (!RegExp(_kSlugPattern).hasMatch(slug)) {
      setState(() => _slugError = 'Only letters, digits, underscores');
      return false;
    }
    setState(() => _slugError = null);
    return true;
  }

  void _pickBackground() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpeg', 'jpg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    Uint8List? bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes != null && mounted) {
      setState(() => _backgroundImage = bytes);
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Theme name is required');
      return;
    }
    setState(() => _nameError = null);

    final slug = _slugController.text.trim();
    if (!_validateSlug(slug)) return;

    Uint8List? bgBytes;
    if (_backgroundImage != null) {
      bgBytes = _encodeAsJpeg87(_backgroundImage!);
    }

    if (widget.cloudSave) {
      Navigator.of(context).pop(_CloudSaveResult(
        title: name,
        slug: slug,
        backgroundImage: bgBytes,
        backgroundTiled: _tiled,
        cloudMeta: widget.cloudMeta,
      ));
    } else {
      final data = ThemeFileData(
        palette: widget.palette,
        backgroundImage: bgBytes,
        backgroundTiled: _tiled,
        cloudMeta: widget.cloudMeta,
      );
      Navigator.of(context).pop(_ExportResult(data, name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.palette.isDark;
    final boxBg = widget.palette.boxBg;
    final titleFg = widget.palette.boxTitleFg;
    final textFg = widget.palette.boxTextFg;
    final subFg = widget.palette.windowSubTextFg;
    final accent = widget.palette.windowBgActive;
    final errorFg = widget.palette.boxTextFgError;
    final inputBg =
        isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F3F5);

    final thumbSize = _computeThumbnailSize(context);
    final isUpdate = widget.cloudMeta != null && widget.cloudMeta!.id != 0;

    return Dialog(
      backgroundColor: boxBg,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: _kBoxWideWidth,
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 17, 22, 0),
                child: Text(
                  isUpdate
                      ? 'Update Theme'
                      : widget.cloudSave
                          ? 'Upload Theme'
                          : 'Create a new theme',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: titleFg,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: TextField(
                  controller: _nameController,
                  style: TextStyle(color: textFg, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Theme name',
                    labelStyle: TextStyle(color: subFg, fontSize: 14),
                    errorText: _nameError,
                    errorStyle: TextStyle(color: errorFg, fontSize: 12),
                    filled: true,
                    fillColor: inputBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: TextField(
                  controller: _slugController,
                  style: TextStyle(color: textFg, fontSize: 14),
                  decoration: InputDecoration(
                    prefixText: 'addtheme/',
                    prefixStyle: TextStyle(color: subFg, fontSize: 14),
                    labelText: 'Link',
                    labelStyle: TextStyle(color: subFg, fontSize: 14),
                    errorText: _slugError,
                    errorStyle: TextStyle(color: errorFg, fontSize: 12),
                    filled: true,
                    fillColor: inputBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9_]')),
                    LengthLimitingTextInputFormatter(_kMaxSlugSize),
                  ],
                  onChanged: (v) {
                    if (_slugError != null) _validateSlug(v);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                child: Text(
                  'Background image',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: SizedBox(
                  height: thumbSize + 4,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: thumbSize,
                          height: thumbSize,
                          child: _backgroundImage != null
                              ? Image.memory(
                                  _backgroundImage!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _PlaceholderThumb(
                                    size: thumbSize,
                                    color: widget.palette.dialogsBg,
                                  ),
                                )
                              : _PlaceholderThumb(
                                  size: thumbSize,
                                  color: widget.palette.dialogsBg,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              _backgroundImage != null
                                  ? 'Image selected'
                                  : 'No image',
                              style: TextStyle(
                                  color: textFg, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: _pickBackground,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize
                                        .shrinkWrap,
                              ),
                              child: Text(
                                'Choose from file',
                                style: TextStyle(
                                    color: accent, fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _tiled,
                                    onChanged: (v) => setState(
                                        () =>
                                            _tiled = v ?? false),
                                    activeColor: accent,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize
                                            .shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => setState(
                                      () => _tiled = !_tiled),
                                  child: Text(
                                    'Tile background',
                                    style: TextStyle(
                                        color: textFg,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 17),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style:
                            TextStyle(color: accent, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor:
                            widget.palette.activeButtonFg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        isUpdate ? 'Update' : (widget.cloudSave ? 'Upload' : 'Save'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _computeThumbnailSize(BuildContext context) {
    const textHeight = 14.0;
    const smallSkip = 6.0;
    const buttonHeight = 30.0;
    const checkboxHeight = 20.0;
    return textHeight + smallSkip + buttonHeight + smallSkip + checkboxHeight;
  }
}

class _PlaceholderThumb extends StatelessWidget {
  final double size;
  final Color color;

  const _PlaceholderThumb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Icon(Icons.image_outlined,
          color: Colors.grey.withValues(alpha: 0.5), size: size * 0.4),
    );
  }
}
