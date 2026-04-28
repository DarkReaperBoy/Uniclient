import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/engine_models.dart' show ChatType;
import 'popup_menu.dart';
import 'choose_datetime_box.dart';

const double _previewWidth = 308;
const double _previewHeightMax = 1280;
const double _rowSkip = 10;
const double _captionMaxHeight = 158;
const int _maxAlbumCount = 10;
const double _thumbCornerRadius = 6;
const double _fileThumbSize = 44;
const double _fileThumbSkip = 11;

class SendFilesResult {
  final List<String> paths;
  final String caption;
  final bool silent;
  final DateTime? scheduledDate;
  final List<bool> spoilers;

  const SendFilesResult({
    required this.paths,
    this.caption = '',
    this.silent = false,
    this.scheduledDate,
    this.spoilers = const [],
  });
}

enum _FileType { photo, video, file }

class _PreparedFile {
  final String path;
  final String name;
  final int size;
  _FileType type;
  bool spoiler;

  _PreparedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.type,
    this.spoiler = false,
  });
}

Future<SendFilesResult?> showSendFilesBox(
  BuildContext context, {
  required List<String> filePaths,
  ChatType chatType = ChatType.dm,
  bool isSelfChat = false,
  int starsPerMessage = 0,
}) {
  return showDialog<SendFilesResult>(
    context: context,
    builder: (ctx) => _SendFilesBoxDialog(
      filePaths: filePaths,
      chatType: chatType,
      isSelfChat: isSelfChat,
      starsPerMessage: starsPerMessage,
    ),
  );
}

class _SendFilesBoxDialog extends StatefulWidget {
  final List<String> filePaths;
  final ChatType chatType;
  final bool isSelfChat;
  final int starsPerMessage;

  const _SendFilesBoxDialog({
    required this.filePaths,
    this.chatType = ChatType.dm,
    this.isSelfChat = false,
    this.starsPerMessage = 0,
  });

  @override
  State<_SendFilesBoxDialog> createState() => _SendFilesBoxDialogState();
}

class _SendFilesBoxDialogState extends State<_SendFilesBoxDialog> {
  late List<_PreparedFile> _files;
  final TextEditingController _captionController = TextEditingController();
  bool _compressImages = true;
  bool _groupAsAlbum = true;

  @override
  void initState() {
    super.initState();
    _files = widget.filePaths.map((p) {
      final file = File(p);
      final name = file.uri.pathSegments.last;
      final size = file.existsSync() ? file.lengthSync() : 0;
      return _PreparedFile(
        path: p,
        name: name,
        size: size,
        type: _detectType(name),
      );
    }).toList();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  static _FileType _detectType(String name) {
    final ext = name.split('.').last.toLowerCase();
    const photoExts = {'jpg', 'jpeg', 'png', 'bmp', 'webp', 'heic', 'heif'};
    const videoExts = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', '3gp'};
    if (photoExts.contains(ext)) return _FileType.photo;
    if (videoExts.contains(ext)) return _FileType.video;
    return _FileType.file;
  }

  bool get _hasMediaFiles =>
      _files.any((f) => f.type == _FileType.photo || f.type == _FileType.video);

  bool get _hasGroupOption => _files.length >= 2 && _hasMediaFiles;

  List<String> get _resultPaths => _files.map((f) => f.path).toList();

  void _removeFile(int index) {
    if (_files.length <= 1) return;
    setState(() => _files.removeAt(index));
  }

  Future<void> _addMoreFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;
      final newFiles = result.files
          .where((f) => f.path != null)
          .map((f) {
        final file = File(f.path!);
        final name = file.uri.pathSegments.last;
        final size = file.existsSync() ? file.lengthSync() : 0;
        return _PreparedFile(
          path: f.path!,
          name: name,
          size: size,
          type: _detectType(name),
        );
      }).toList();
      setState(() {
        for (final f in newFiles) {
          if (_files.length < _maxAlbumCount) _files.add(f);
        }
      });
    } catch (_) {}
  }

  bool get _canSpoiler =>
      _compressImages && _files.any((f) => f.type == _FileType.photo || f.type == _FileType.video);

  bool get _allSpoilered =>
      _files.where((f) => f.type == _FileType.photo || f.type == _FileType.video)
          .every((f) => f.spoiler);

  bool get _anySpoilered =>
      _files.any((f) => f.spoiler);

  void _toggleSpoiler(int index) {
    setState(() => _files[index].spoiler = !_files[index].spoiler);
  }

  void _toggleAllSpoilers() {
    final target = !_allSpoilered;
    setState(() {
      for (final f in _files) {
        if (f.type == _FileType.photo || f.type == _FileType.video) {
          f.spoiler = target;
        }
      }
    });
  }

  void _showTopMenu(Offset position) {
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'spoiler',
          icon: Icon(_allSpoilered ? Icons.check : Icons.blur_on),
          label: _anySpoilered ? 'Remove spoiler' : 'Hide with spoiler',
        ),
      ],
    ).then((value) {
      if (value == 'spoiler') _toggleAllSpoilers();
    });
  }

  void _send({bool silent = false, DateTime? scheduledDate}) {
    Navigator.of(context).pop(SendFilesResult(
      paths: _resultPaths,
      caption: _captionController.text,
      silent: silent,
      scheduledDate: scheduledDate,
      spoilers: _files.map((f) => f.spoiler).toList(),
    ));
  }

  void _showSendMenu(BuildContext ctx, Offset position) {
    showTelegramMenu<String>(
      context: ctx,
      position: Offset(position.dx, position.dy - 120),
      items: [
        if (!widget.isSelfChat)
          const TelegramMenuItem(value: 'silent', icon: Icon(Icons.volume_off_outlined), label: 'Send without Sound'),
        TelegramMenuItem(value: 'schedule', icon: const Icon(Icons.schedule_outlined), label: widget.isSelfChat ? 'Set Reminder' : 'Schedule Message'),
        if (widget.chatType == ChatType.dm && !widget.isSelfChat)
          const TelegramMenuItem(value: 'when_online', icon: Icon(Icons.person_outline), label: 'Send When Online'),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'silent':
          _send(silent: true);
        case 'schedule':
          _pickScheduleDate();
        case 'when_online':
          _send();
      }
    });
  }

  Future<void> _pickScheduleDate() async {
    final result = await showChooseDateTimeBox(
      context,
      isSelfChat: widget.isSelfChat,
      isScheduledToUser: widget.chatType == ChatType.dm && !widget.isSelfChat,
    );
    if (result == null || !mounted) return;
    if (result.sendWhenOnline) {
      _send();
    } else {
      _send(scheduledDate: result.dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final textFg = isDark ? const Color(0xFFE0E3EA) : const Color(0xFF222222);
    final subFg = isDark ? const Color(0xFF8B9BAA) : const Color(0xFF999999);
    final accentFg = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final dividerColor = isDark ? const Color(0xFF243441) : const Color(0xFFE0E0E0);

    final mediaFiles = _files.where(
        (f) => f.type == _FileType.photo || f.type == _FileType.video).toList();
    final docFiles = _files.where((f) => f.type == _FileType.file).toList();

    final showMediaPreview = _compressImages && mediaFiles.isNotEmpty;

    return Dialog(
      backgroundColor: boxBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      elevation: 4,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: _previewWidth + 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _files.length == 1 ? 'Send file' : 'Send ${_files.length} files',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textFg,
                      ),
                    ),
                  ),
                  _TopMenuButton(
                    isDark: isDark,
                    onPressed: !_canSpoiler ? null : () {
                      final btnBox = context.findRenderObject() as RenderBox;
                      final pos = btnBox.localToGlobal(Offset(btnBox.size.width - 48, 48));
                      _showTopMenu(pos);
                    },
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    if (showMediaPreview && mediaFiles.isNotEmpty)
                      _MediaPreview(
                        files: mediaFiles,
                        allFiles: _files,
                        onRemove: (file) {
                          final idx = _files.indexOf(file);
                          if (idx >= 0) _removeFile(idx);
                        },
                        onToggleSpoiler: (file) {
                          final idx = _files.indexOf(file);
                          if (idx >= 0) _toggleSpoiler(idx);
                        },
                        canSpoiler: _canSpoiler,
                      ),
                    if (showMediaPreview && mediaFiles.isNotEmpty && docFiles.isNotEmpty)
                      SizedBox(height: _rowSkip),
                    if (docFiles.isNotEmpty || !_compressImages)
                      _FileListPreview(
                        files: _compressImages ? docFiles : _files,
                        allFiles: _files,
                        isDark: isDark,
                        textFg: textFg,
                        subFg: subFg,
                        onRemove: (file) {
                          final idx = _files.indexOf(file);
                          if (idx >= 0) _removeFile(idx);
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _captionMaxHeight),
                child: TextField(
                  controller: _captionController,
                  maxLines: null,
                  maxLength: 4096,
                  style: TextStyle(fontSize: 14, color: textFg),
                  decoration: InputDecoration(
                    hintText: 'Add a caption...',
                    hintStyle: TextStyle(fontSize: 14, color: subFg),
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
            ),
            if (_hasMediaFiles)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 20, 0),
                child: Column(
                  children: [
                    _CheckboxRow(
                      label: 'Compress images',
                      value: _compressImages,
                      accentColor: accentFg,
                      textColor: textFg,
                      onChanged: (v) => setState(() => _compressImages = v),
                    ),
                    if (_hasGroupOption)
                      _CheckboxRow(
                        label: 'Group as album',
                        value: _groupAsAlbum,
                        accentColor: accentFg,
                        textColor: textFg,
                        onChanged: (v) => setState(() => _groupAsAlbum = v),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _addMoreFiles,
                    style: TextButton.styleFrom(
                      foregroundColor: accentFg,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    child: const Text('Add'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                      foregroundColor: accentFg,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  _SendMenuButton(
                    accentColor: accentFg,
                    starsPerMessage: widget.starsPerMessage,
                    fileCount: _files.length,
                    onSend: _send,
                    onShowMenu: _showSendMenu,
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

class _TopMenuButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback? onPressed;

  const _TopMenuButton({required this.isDark, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        icon: Icon(Icons.more_vert,
            color: onPressed != null
                ? (isDark ? const Color(0xFF8B9BAA) : const Color(0xFF999999))
                : (isDark ? const Color(0xFF4A5560) : const Color(0xFFCCCCCC))),
        onPressed: onPressed,
        splashRadius: 21,
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  final List<_PreparedFile> files;
  final List<_PreparedFile> allFiles;
  final void Function(_PreparedFile) onRemove;
  final void Function(_PreparedFile) onToggleSpoiler;
  final bool canSpoiler;

  const _MediaPreview({
    required this.files,
    required this.allFiles,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.canSpoiler,
  });

  @override
  Widget build(BuildContext context) {
    if (files.length == 1) {
      return _SingleMediaPreview(
        file: files.first,
        canRemove: allFiles.length > 1,
        onRemove: () => onRemove(files.first),
        onToggleSpoiler: () => onToggleSpoiler(files.first),
        canSpoiler: canSpoiler,
      );
    }
    return _AlbumPreview(
      files: files,
      allFiles: allFiles,
      onRemove: onRemove,
      onToggleSpoiler: onToggleSpoiler,
      canSpoiler: canSpoiler,
    );
  }
}

class _SingleMediaPreview extends StatelessWidget {
  final _PreparedFile file;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onToggleSpoiler;
  final bool canSpoiler;

  const _SingleMediaPreview({
    required this.file,
    required this.canRemove,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.canSpoiler,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: canSpoiler ? (details) {
        _showThumbContextMenu(context, details.globalPosition);
      } : null,
      onLongPress: canSpoiler ? () {
        final box = context.findRenderObject() as RenderBox;
        final center = box.localToGlobal(box.size.center(Offset.zero));
        _showThumbContextMenu(context, center);
      } : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_thumbCornerRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _previewWidth,
            maxHeight: _previewWidth,
          ),
          child: Stack(
            children: [
              Image.file(
                File(file.path),
                width: _previewWidth,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: _previewWidth,
                  height: 200,
                  color: Colors.grey[800],
                  child: const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                ),
              ),
              if (file.spoiler)
                const Positioned.fill(child: _SpoilerOverlay()),
              if (canRemove)
                Positioned(
                  top: 5,
                  right: 5,
                  child: _ThumbButton(
                    icon: Icons.close,
                    onPressed: onRemove,
                  ),
                ),
              if (file.type == _FileType.video)
                const Positioned.fill(
                  child: Center(
                    child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 48),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showThumbContextMenu(BuildContext context, Offset position) {
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'spoiler',
          icon: Icon(file.spoiler ? Icons.check : Icons.blur_on),
          label: 'Spoiler effect',
        ),
      ],
    ).then((value) {
      if (value == 'spoiler') onToggleSpoiler();
    });
  }
}

class _AlbumPreview extends StatelessWidget {
  final List<_PreparedFile> files;
  final List<_PreparedFile> allFiles;
  final void Function(_PreparedFile) onRemove;
  final void Function(_PreparedFile) onToggleSpoiler;
  final bool canSpoiler;

  const _AlbumPreview({
    required this.files,
    required this.allFiles,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.canSpoiler,
  });

  @override
  Widget build(BuildContext context) {
    final count = files.length;
    if (count <= 0) return const SizedBox.shrink();

    final rows = _layoutAlbum(count);

    return SizedBox(
      width: _previewWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int rowIdx = 0; rowIdx < rows.length; rowIdx++) ...[
            if (rowIdx > 0) const SizedBox(height: 2),
            SizedBox(
              height: rows[rowIdx].height,
              child: Row(
                children: [
                  for (int colIdx = 0; colIdx < rows[rowIdx].items.length; colIdx++) ...[
                    if (colIdx > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: rows[rowIdx].items[colIdx].flex,
                      child: _AlbumThumb(
                        file: files[rows[rowIdx].items[colIdx].fileIndex],
                        height: rows[rowIdx].height,
                        canRemove: allFiles.length > 1,
                        onRemove: () => onRemove(files[rows[rowIdx].items[colIdx].fileIndex]),
                        onToggleSpoiler: () => onToggleSpoiler(files[rows[rowIdx].items[colIdx].fileIndex]),
                        canSpoiler: canSpoiler,
                        cornerRadius: _cornerForPosition(
                          rowIdx, colIdx,
                          rows.length, rows[rowIdx].items.length,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  BorderRadius _cornerForPosition(int row, int col, int totalRows, int totalCols) {
    final isTop = row == 0;
    final isBottom = row == totalRows - 1;
    final isLeft = col == 0;
    final isRight = col == totalCols - 1;

    return BorderRadius.only(
      topLeft: isTop && isLeft ? const Radius.circular(_thumbCornerRadius) : Radius.zero,
      topRight: isTop && isRight ? const Radius.circular(_thumbCornerRadius) : Radius.zero,
      bottomLeft: isBottom && isLeft ? const Radius.circular(_thumbCornerRadius) : Radius.zero,
      bottomRight: isBottom && isRight ? const Radius.circular(_thumbCornerRadius) : Radius.zero,
    );
  }
}

class _AlbumRow {
  final double height;
  final List<_AlbumItem> items;
  _AlbumRow(this.height, this.items);
}

class _AlbumItem {
  final int fileIndex;
  final int flex;
  _AlbumItem(this.fileIndex, {this.flex = 1});
}

List<_AlbumRow> _layoutAlbum(int count) {
  const maxH = _previewWidth;
  const spacing = 2.0;

  switch (count) {
    case 1:
      return [_AlbumRow(maxH, [_AlbumItem(0)])];
    case 2:
      final h = (maxH - spacing) / 2;
      return [
        _AlbumRow(h, [_AlbumItem(0)]),
        _AlbumRow(h, [_AlbumItem(1)]),
      ];
    case 3:
      final topH = (maxH - spacing) * 0.66;
      final botH = maxH - spacing - topH;
      return [
        _AlbumRow(topH, [_AlbumItem(0)]),
        _AlbumRow(botH, [_AlbumItem(1), _AlbumItem(2)]),
      ];
    case 4:
      final topH = (maxH - spacing) * 0.66;
      final botH = maxH - spacing - topH;
      return [
        _AlbumRow(topH, [_AlbumItem(0), _AlbumItem(1)]),
        _AlbumRow(botH, [_AlbumItem(2), _AlbumItem(3)]),
      ];
    default:
      final rows = <_AlbumRow>[];
      int idx = 0;
      final totalSpacing = (((count - 1) / 2).ceil()) * spacing;
      final rowH = math.max(60.0, (maxH - totalSpacing) / ((count / 2).ceil()));
      while (idx < count) {
        final remaining = count - idx;
        if (remaining >= 3 && remaining != 4) {
          rows.add(_AlbumRow(rowH, [_AlbumItem(idx), _AlbumItem(idx + 1), _AlbumItem(idx + 2)]));
          idx += 3;
        } else if (remaining >= 2) {
          rows.add(_AlbumRow(rowH, [_AlbumItem(idx), _AlbumItem(idx + 1)]));
          idx += 2;
        } else {
          rows.add(_AlbumRow(rowH, [_AlbumItem(idx)]));
          idx += 1;
        }
      }
      return rows;
  }
}

class _AlbumThumb extends StatelessWidget {
  final _PreparedFile file;
  final double height;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onToggleSpoiler;
  final bool canSpoiler;
  final BorderRadius cornerRadius;

  const _AlbumThumb({
    required this.file,
    required this.height,
    required this.canRemove,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.canSpoiler,
    required this.cornerRadius,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: canSpoiler ? (details) {
        _showThumbContextMenu(context, details.globalPosition);
      } : null,
      onLongPress: canSpoiler ? () {
        final box = context.findRenderObject() as RenderBox;
        final center = box.localToGlobal(box.size.center(Offset.zero));
        _showThumbContextMenu(context, center);
      } : null,
      child: ClipRRect(
        borderRadius: cornerRadius,
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(file.path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.broken_image, color: Colors.white54, size: 32),
                ),
              ),
              if (file.spoiler)
                const _SpoilerOverlay(),
              if (canRemove)
                Positioned(
                  top: 5,
                  right: 5,
                  child: _ThumbButton(
                    icon: Icons.close,
                    onPressed: onRemove,
                    size: 22,
                  ),
                ),
              if (file.type == _FileType.video)
                const Center(
                  child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showThumbContextMenu(BuildContext context, Offset position) {
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'spoiler',
          icon: Icon(file.spoiler ? Icons.check : Icons.blur_on),
          label: 'Spoiler effect',
        ),
      ],
    ).then((value) {
      if (value == 'spoiler') onToggleSpoiler();
    });
  }
}

class _ThumbButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  const _ThumbButton({
    required this.icon,
    required this.onPressed,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.6),
      ),
    );
  }
}

class _FileListPreview extends StatelessWidget {
  final List<_PreparedFile> files;
  final List<_PreparedFile> allFiles;
  final bool isDark;
  final Color textFg;
  final Color subFg;
  final void Function(_PreparedFile) onRemove;

  const _FileListPreview({
    required this.files,
    required this.allFiles,
    required this.isDark,
    required this.textFg,
    required this.subFg,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < files.length; i++) ...[
          if (i > 0) SizedBox(height: _rowSkip),
          _FileCard(
            file: files[i],
            isDark: isDark,
            textFg: textFg,
            subFg: subFg,
            canRemove: allFiles.length > 1,
            onRemove: () => onRemove(files[i]),
          ),
        ],
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  final _PreparedFile file;
  final bool isDark;
  final Color textFg;
  final Color subFg;
  final bool canRemove;
  final VoidCallback onRemove;

  const _FileCard({
    required this.file,
    required this.isDark,
    required this.textFg,
    required this.subFg,
    required this.canRemove,
    required this.onRemove,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _extBadge(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return '';
    return parts.last.toUpperCase();
  }

  Color _iconBgColor() {
    switch (file.type) {
      case _FileType.photo:
        return const Color(0xFF4CAF50);
      case _FileType.video:
        return const Color(0xFF2196F3);
      case _FileType.file:
        return isDark ? const Color(0xFF3F6C93) : const Color(0xFF5BA0D0);
    }
  }

  IconData _iconData() {
    switch (file.type) {
      case _FileType.photo:
        return Icons.image;
      case _FileType.video:
        return Icons.videocam;
      case _FileType.file:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _fileThumbSize + 12,
      child: Row(
        children: [
          Container(
            width: _fileThumbSize,
            height: _fileThumbSize,
            decoration: BoxDecoration(
              color: _iconBgColor(),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(_iconData(), color: Colors.white, size: 22),
                if (_extBadge(file.name).isNotEmpty)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: _iconBgColor(),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: isDark ? const Color(0xFF17212B) : Colors.white,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _extBadge(file.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: _fileThumbSkip),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textFg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatSize(file.size),
                  style: TextStyle(fontSize: 12, color: subFg),
                ),
              ],
            ),
          ),
          if (canRemove)
            _ThumbButton(
              icon: Icons.close,
              onPressed: onRemove,
              size: 22,
            ),
        ],
      ),
    );
  }
}

class _SpoilerOverlay extends StatelessWidget {
  const _SpoilerOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x80000000),
      child: const Center(
        child: Icon(Icons.blur_on, color: Colors.white70, size: 36),
      ),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  final String label;
  final bool value;
  final Color accentColor;
  final Color textColor;
  final ValueChanged<bool> onChanged;

  const _CheckboxRow({
    required this.label,
    required this.value,
    required this.accentColor,
    required this.textColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendMenuButton extends StatelessWidget {
  final Color accentColor;
  final int starsPerMessage;
  final int fileCount;
  final void Function({bool silent, DateTime? scheduledDate}) onSend;
  final void Function(BuildContext ctx, Offset position) onShowMenu;

  const _SendMenuButton({
    required this.accentColor,
    required this.starsPerMessage,
    required this.fileCount,
    required this.onSend,
    required this.onShowMenu,
  });

  String get _label {
    if (starsPerMessage > 0) {
      final total = starsPerMessage * fileCount;
      return '\u2B50 $total';
    }
    return 'Send';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => onSend(),
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox;
        final pos = box.localToGlobal(Offset(box.size.width, 0));
        onShowMenu(context, pos);
      },
      onSecondaryTapUp: (details) {
        onShowMenu(context, details.globalPosition);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          _label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: accentColor,
          ),
        ),
      ),
    );
  }
}
