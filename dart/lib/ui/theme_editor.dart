import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../theme/telegram_palette.dart';
import '../theme/theme_file.dart';
import '../theme/theme_name_generator.dart';

class ThemeEditorScreen extends StatefulWidget {
  final TelegramPalette palette;
  final void Function(TelegramPalette palette) onPaletteChanged;

  const ThemeEditorScreen({
    super.key,
    required this.palette,
    required this.onPaletteChanged,
  });

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late Map<String, Color> _colorMap;
  late TelegramPalette _currentPalette;
  final _searchController = TextEditingController();
  String _filter = '';
  int _focusedIndex = -1;
  int? _editingIndex;
  final _scrollController = ScrollController();
  final _listFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentPalette = widget.palette;
    _colorMap = paletteToMap(_currentPalette);
    _searchController.addListener(() {
      setState(() => _filter = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  List<MapEntry<String, Color>> get _filteredEntries {
    final entries = _colorMap.entries.toList();
    if (_filter.isEmpty) return entries;
    return entries.where((e) => e.key.toLowerCase().contains(_filter)).toList();
  }

  void _updateColor(String token, Color color) {
    setState(() {
      _colorMap[token] = color;
      _currentPalette = paletteFromMap(_colorMap, widget.palette);
    });
    widget.onPaletteChanged(_currentPalette);
  }

  void _handleExport() async {
    final result = await showDialog<ThemeFileData>(
      context: context,
      builder: (ctx) => _SaveThemeBox(palette: _currentPalette),
    );
    if (result == null || !mounted) return;

    final bytes = exportThemeFile(result);
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final safeName = result.cloudMeta != null ? 'custom' : 'custom';
    final path = '$dir/$safeName.tdesktop-theme';
    await File(path).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $path'), duration: const Duration(seconds: 2)),
      );
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
      _editingIndex = null;
    });
    widget.onPaletteChanged(_currentPalette);
  }

  void _showMenuDialog() {
    final isDark = _currentPalette.isDark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : Colors.black;
    final accentColor = _currentPalette.windowBgActive;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: bgColor,
        title: Text('Theme Options', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
        children: [
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); _handleExport(); },
            child: Text('Export Theme', style: TextStyle(color: textColor)),
          ),
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); _handleImport(); },
            child: Text('Import Theme', style: TextStyle(color: textColor)),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final text = _generatePalettePreview();
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Palette copied to clipboard'), backgroundColor: accentColor, duration: const Duration(seconds: 2)),
              );
            },
            child: Text('Copy Palette Text', style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }

  String _generatePalettePreview() {
    final buf = StringBuffer();
    for (final entry in _colorMap.entries) {
      buf.writeln('${entry.key}: ${_colorToHexString(entry.value)};');
    }
    return buf.toString();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final entries = _filteredEntries;
    if (entries.isEmpty) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _focusedIndex = (_focusedIndex + 1).clamp(0, entries.length - 1);
        _editingIndex = null;
      });
      _ensureVisible(_focusedIndex);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _focusedIndex = (_focusedIndex - 1).clamp(0, entries.length - 1);
        _editingIndex = null;
      });
      _ensureVisible(_focusedIndex);
    } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      setState(() {
        _focusedIndex = (_focusedIndex + 10).clamp(0, entries.length - 1);
        _editingIndex = null;
      });
      _ensureVisible(_focusedIndex);
    } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      setState(() {
        _focusedIndex = (_focusedIndex - 10).clamp(0, entries.length - 1);
        _editingIndex = null;
      });
      _ensureVisible(_focusedIndex);
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedIndex >= 0 && _focusedIndex < entries.length) {
        setState(() => _editingIndex = _focusedIndex);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_editingIndex != null) {
        setState(() => _editingIndex = null);
      }
    }
  }

  void _ensureVisible(int index) {
    const rowHeight = 60.0;
    final offset = index * rowHeight;
    final viewportExtent = _scrollController.position.viewportDimension;
    final current = _scrollController.offset;
    if (offset < current) {
      _scrollController.animateTo(offset, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    } else if (offset + rowHeight > current + viewportExtent) {
      _scrollController.animateTo(offset + rowHeight - viewportExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _currentPalette.isDark;
    final bgColor = _currentPalette.dialogsBg;
    final bgOver = _currentPalette.dialogsBgOver;
    final textColor = _currentPalette.windowBoldFg;
    final subtextColor = _currentPalette.windowSubTextFg;
    final accentColor = _currentPalette.windowBgActive;
    final shadowColor = _currentPalette.shadowFg;
    final entries = _filteredEntries;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Header bar
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: _currentPalette.topBarBg,
              border: Border(bottom: BorderSide(color: shadowColor, width: 1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: textColor, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Theme Editor',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.more_vert, color: textColor, size: 22),
                  onPressed: _showMenuDialog,
                  tooltip: 'Options',
                ),
                TextButton(
                  onPressed: _handleExport,
                  child: Text('Save', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: _currentPalette.topBarBg,
              border: Border(bottom: BorderSide(color: shadowColor, width: 1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search tokens...',
                hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: subtextColor, size: 20),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: subtextColor, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F3F5),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Palette entries list
          Expanded(
            child: KeyboardListener(
              focusNode: _listFocusNode,
              onKeyEvent: _handleKeyEvent,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: entries.length,
                itemExtent: 60,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final isFocused = index == _focusedIndex;
                  final isEditing = index == _editingIndex;
                  final rowBg = isEditing
                      ? _currentPalette.dialogsBgActive
                      : isFocused
                          ? bgOver
                          : bgColor;

                  return _PaletteEntryRow(
                    token: entry.key,
                    color: entry.value,
                    backgroundColor: rowBg,
                    textColor: isEditing ? _currentPalette.dialogsNameFgActive : textColor,
                    subtextColor: isEditing ? _currentPalette.dialogsTextFgActive : subtextColor,
                    hoverColor: bgOver,
                    isEditing: isEditing,
                    onTap: () {
                      setState(() {
                        _focusedIndex = index;
                        _editingIndex = index;
                      });
                      _listFocusNode.requestFocus();
                    },
                    onColorChanged: (c) => _updateColor(entry.key, c),
                    onEditDone: () => setState(() => _editingIndex = null),
                    accentColor: accentColor,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteEntryRow extends StatefulWidget {
  final String token;
  final Color color;
  final Color backgroundColor;
  final Color textColor;
  final Color subtextColor;
  final Color hoverColor;
  final Color accentColor;
  final bool isEditing;
  final VoidCallback onTap;
  final void Function(Color) onColorChanged;
  final VoidCallback onEditDone;

  const _PaletteEntryRow({
    required this.token,
    required this.color,
    required this.backgroundColor,
    required this.textColor,
    required this.subtextColor,
    required this.hoverColor,
    required this.isEditing,
    required this.onTap,
    required this.onColorChanged,
    required this.onEditDone,
    required this.accentColor,
  });

  @override
  State<_PaletteEntryRow> createState() => _PaletteEntryRowState();
}

class _PaletteEntryRowState extends State<_PaletteEntryRow> {
  bool _hovered = false;
  late TextEditingController _hexController;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(text: _colorToHexString(widget.color));
  }

  @override
  void didUpdateWidget(_PaletteEntryRow old) {
    super.didUpdateWidget(old);
    if (!widget.isEditing && old.isEditing) {
      _hexError = null;
    }
    if (widget.isEditing && !old.isEditing) {
      _hexController.text = _colorToHexString(widget.color);
      _hexError = null;
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _submitHex() {
    final text = _hexController.text.trim();
    final color = _parseHex(text);
    if (color != null) {
      widget.onColorChanged(color);
      widget.onEditDone();
    } else {
      setState(() => _hexError = 'Invalid hex color');
    }
  }

  Color? _parseHex(String text) {
    var hex = text.replaceFirst('#', '');
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v == null) return null;
      return Color((0xFF << 24) | v);
    } else if (hex.length == 8) {
      final v = int.tryParse(hex, radix: 16);
      if (v == null) return null;
      final r = (v >> 24) & 0xFF;
      final g = (v >> 16) & 0xFF;
      final b = (v >> 8) & 0xFF;
      final a = v & 0xFF;
      return Color((a << 24) | (r << 16) | (g << 8) | b);
    }
    return null;
  }

  void _onHexChanged(String text) {
    final color = _parseHex(text.trim());
    if (color != null) {
      setState(() => _hexError = null);
      widget.onColorChanged(color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _hovered && !widget.isEditing ? widget.hoverColor : widget.backgroundColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 60,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: widget.isEditing
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.token,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 26,
                            child: TextField(
                              controller: _hexController,
                              autofocus: true,
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.textColor,
                                fontFamily: 'monospace',
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide(
                                    color: _hexError != null ? Colors.red : widget.accentColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide(color: widget.accentColor, width: 1.5),
                                ),
                                errorText: _hexError,
                                errorStyle: const TextStyle(fontSize: 0, height: 0),
                              ),
                              onChanged: _onHexChanged,
                              onSubmitted: (_) => _submitHex(),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                                LengthLimitingTextInputFormatter(9),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.token,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _colorToHexString(widget.color),
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.subtextColor,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              _ColorSwatch(color: widget.color, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final double size;

  const _ColorSwatch({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          painter: _SwatchPainter(color),
          size: Size(size, size),
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
    // Checkerboard for transparency
    if (color.a < 1.0) {
      const checkerSize = 4.0;
      final lightPaint = Paint()..color = const Color(0xFFCCCCCC);
      final darkPaint = Paint()..color = const Color(0xFF999999);
      for (double y = 0; y < size.height; y += checkerSize) {
        for (double x = 0; x < size.width; x += checkerSize) {
          final isLight = ((x ~/ checkerSize) + (y ~/ checkerSize)) % 2 == 0;
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

  const _SaveThemeBox({
    required this.palette,
    this.existingBackground,
    this.existingTiled = false,
    this.cloudMeta,
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
    _slugController = TextEditingController();
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
    if (slug.isEmpty) return true;
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
    if (slug.isNotEmpty && !_validateSlug(slug)) return;

    Uint8List? bgBytes;
    if (_backgroundImage != null) {
      bgBytes = _encodeAsJpeg87(_backgroundImage!);
    }

    final data = ThemeFileData(
      palette: widget.palette,
      backgroundImage: bgBytes,
      backgroundTiled: _tiled,
      cloudMeta: widget.cloudMeta,
    );
    Navigator.of(context).pop(data);
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
    final inputBg = isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F3F5);

    final thumbSize = _computeThumbnailSize(context);

    return Dialog(
      backgroundColor: boxBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: _kBoxWideWidth,
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title bar
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 17, 22, 0),
                child: Text(
                  widget.cloudMeta != null ? 'Save Theme' : 'Create a new theme',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: titleFg,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Name field
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Link/slug field
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                    LengthLimitingTextInputFormatter(_kMaxSlugSize),
                  ],
                  onChanged: (v) {
                    if (_slugError != null) _validateSlug(v);
                  },
                ),
              ),
              const SizedBox(height: 16),
              // "Background image" subsection header
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
              // Background section: thumbnail + controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: SizedBox(
                  height: thumbSize + 4,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: thumbSize,
                          height: thumbSize,
                          child: _backgroundImage != null
                              ? Image.memory(
                                  _backgroundImage!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _PlaceholderThumb(
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
                      // Controls column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _backgroundImage != null ? 'Image selected' : 'No image',
                              style: TextStyle(color: textFg, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: _pickBackground,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Choose from file',
                                style: TextStyle(color: accent, fontSize: 13),
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
                                    onChanged: (v) => setState(() => _tiled = v ?? false),
                                    activeColor: accent,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => setState(() => _tiled = !_tiled),
                                  child: Text(
                                    'Tile background',
                                    style: TextStyle(color: textFg, fontSize: 13),
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
              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 17),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: accent, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: widget.palette.activeButtonFg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text('Save', style: TextStyle(fontSize: 14)),
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
      child: Icon(Icons.image_outlined, color: Colors.grey.withValues(alpha: 0.5), size: size * 0.4),
    );
  }
}
