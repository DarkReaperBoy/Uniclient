import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/telegram_palette.dart';
import '../theme/theme_file.dart';

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
    final data = ThemeFileData(palette: _currentPalette);
    final bytes = exportThemeFile(data);
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final path = '$dir/custom.tdesktop-theme';
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
