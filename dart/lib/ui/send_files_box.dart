import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/engine_models.dart' show ChatType;
import 'popup_menu.dart';
import 'choose_datetime_box.dart';
import 'photo_crop_editor.dart';

const int _kCaptionMaxLength = 4096;
const int _kCaptionWarnThreshold = 3900;

const double _previewWidth = 308;
const double _previewHeightMax = 1280;
const double _rowSkip = 10;
const double _captionMaxHeight = 158;
const int _maxAlbumCount = 10;
const double _thumbCornerRadius = 6;
const double _fileIconSize = 44;
const double _fileIconSkip = 11;
const double _fileIconNameTop = 6;
const double _fileIconStatusTop = 27;
const double _fileThumbSize = 64;
const double _fileThumbSkip = 10;
const double _fileThumbNameTop = 7;
const double _fileThumbStatusTop = 37;
const double _fileThumbRadius = 4;
const double _fileCaptionTopOffset = 6;
const double _fileButtonSkipTop = 2;
const double _fileButtonSkipRight = 5;
const double _fileButtonGap = -1;
const int _kMaxDisplayNameLength = 64;
const double _albumSpacing = 2;
const double _albumMinCellWidth = 50;
const double _shrinkSize = 5;
const int _shrinkDurationMs = 150;
const int _dragDurationMs = 200;
const double _capsuleW = 48;
const double _capsuleH = 26;
const double _capsuleSkipRight = 5;
const double _capsuleSkipTop = 5;
const double _capsuleGap = 8;
const double _capsuleVertW = 30;
const double _capsuleVertH = 50;
const double _capsuleSmallW = 30;
const double _capsuleSmallH = 25;

class SendFilesResult {
  final List<String> paths;
  final String caption;
  final bool silent;
  final DateTime? scheduledDate;
  final List<bool> spoilers;
  final bool sendAsDocuments;
  final bool groupFiles;
  final bool remember;
  final bool sendLargePhotos;
  final bool captionAbove;
  final Map<int, String> perFileCaptions;

  const SendFilesResult({
    required this.paths,
    this.caption = '',
    this.silent = false,
    this.scheduledDate,
    this.spoilers = const [],
    this.sendAsDocuments = false,
    this.groupFiles = true,
    this.remember = false,
    this.sendLargePhotos = true,
    this.captionAbove = false,
    this.perFileCaptions = const {},
  });
}

enum _FileType { photo, video, file }

class _PreparedFile {
  final String path;
  final String name;
  final int size;
  _FileType type;
  bool spoiler;
  double? imageWidth;
  double? imageHeight;
  bool hasThumb;

  _PreparedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.type,
    this.spoiler = false,
    this.hasThumb = false,
  });

  double get aspectRatio {
    if (imageWidth != null && imageHeight != null && imageHeight! > 0) {
      return imageWidth! / imageHeight!;
    }
    return 1.0;
  }

  bool get isThumbedLayout =>
      imageWidth != null && (type == _FileType.photo || type == _FileType.video);

  String get displayName {
    if (name.length <= _kMaxDisplayNameLength) return name;
    final ext = name.contains('.') ? '.${name.split('.').last}' : '';
    final base = name.substring(0, name.length - ext.length);
    final keep = _kMaxDisplayNameLength - ext.length - 1;
    if (keep <= 0) return name.substring(0, _kMaxDisplayNameLength);
    final half = keep ~/ 2;
    return '${base.substring(0, half)}…${base.substring(base.length - (keep - half))}$ext';
  }
}

Future<SendFilesResult?> showSendFilesBox(
  BuildContext context, {
  required List<String> filePaths,
  ChatType chatType = ChatType.dm,
  bool isSelfChat = false,
  int starsPerMessage = 0,
  bool isSlowMode = false,
  bool? overrideSendAsDocuments,
}) {
  return showDialog<SendFilesResult>(
    context: context,
    builder: (ctx) => _SendFilesBoxDialog(
      filePaths: filePaths,
      chatType: chatType,
      isSelfChat: isSelfChat,
      starsPerMessage: starsPerMessage,
      isSlowMode: isSlowMode,
      overrideSendAsDocuments: overrideSendAsDocuments,
    ),
  );
}

class _SendFilesBoxDialog extends StatefulWidget {
  final List<String> filePaths;
  final ChatType chatType;
  final bool isSelfChat;
  final int starsPerMessage;
  final bool isSlowMode;
  final bool? overrideSendAsDocuments;

  const _SendFilesBoxDialog({
    required this.filePaths,
    this.chatType = ChatType.dm,
    this.isSelfChat = false,
    this.starsPerMessage = 0,
    this.isSlowMode = false,
    this.overrideSendAsDocuments,
  });

  @override
  State<_SendFilesBoxDialog> createState() => _SendFilesBoxDialogState();
}

class _SendFilesBoxDialogState extends State<_SendFilesBoxDialog> {
  late List<_PreparedFile> _files;
  final TextEditingController _captionController = TextEditingController();
  late final FocusNode _captionFocus;
  late bool _sendAsDocuments;
  late bool _groupFiles;
  bool _wayRemember = false;
  bool _sendLargePhotos = true;
  bool _captionAbove = false;
  bool _showEmojiPanel = false;
  int _charCount = 0;
  final Map<int, String> _perFileCaptions = {};
  late final bool _initialSendAsDocuments;
  late final bool _initialGroupFiles;

  @override
  void initState() {
    super.initState();
    _captionFocus = FocusNode(onKeyEvent: _onCaptionKey);
    _captionController.addListener(_onCaptionChanged);
    _sendAsDocuments = widget.overrideSendAsDocuments ?? false;
    _groupFiles = true;
    _initialSendAsDocuments = _sendAsDocuments;
    _initialGroupFiles = _groupFiles;
    _files = widget.filePaths.map((p) {
      final file = File(p);
      final name = file.uri.pathSegments.last;
      final size = file.existsSync() ? file.lengthSync() : 0;
      return _PreparedFile(
        path: p,
        name: name,
        size: size,
        type: _detectType(name),
        spoiler: widget.starsPerMessage > 0 &&
            (_detectType(name) == _FileType.photo ||
             _detectType(name) == _FileType.video),
      );
    }).toList();
    _loadImageDimensions();
  }

  @override
  void dispose() {
    _captionController.removeListener(_onCaptionChanged);
    _captionController.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  void _onCaptionChanged() {
    final len = _captionController.text.length;
    if (len != _charCount) {
      setState(() => _charCount = len);
    }
  }

  KeyEventResult _onCaptionKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (isEnter && !ctrl && !shift) {
      _send();
      return KeyEventResult.handled;
    }
    if (isEnter && ctrl) {
      _send();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(null);
      return KeyEventResult.handled;
    }

    // Ctrl+V → paste interception (images → add to file list)
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyV) {
      _handleCaptionPaste();
      return KeyEventResult.handled;
    }

    // Ctrl+O → add files
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyO) {
      _addMoreFiles();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool get _canMoveCaption =>
      !_sendAsDocuments &&
      _captionController.text.isNotEmpty &&
      _files.any((f) => f.type == _FileType.photo || f.type == _FileType.video);

  Future<void> _handleCaptionPaste() async {
    try {
      final result = await Process.run('wl-paste', ['--list-types']);
      final types = result.stdout.toString();
      if (types.contains('image/png') || types.contains('image/jpeg')) {
        final tmpDir = Directory.systemTemp;
        final ext = types.contains('image/png') ? 'png' : 'jpg';
        final tmpFile = File('${tmpDir.path}/uniclient_paste_${DateTime.now().millisecondsSinceEpoch}.$ext');
        final pasteResult = await Process.run('wl-paste', ['--type', 'image/$ext'],
            stdoutEncoding: null);
        if (pasteResult.exitCode == 0 && pasteResult.stdout is List<int>) {
          await tmpFile.writeAsBytes(pasteResult.stdout as List<int>);
          if (await tmpFile.exists() && await tmpFile.length() > 0) {
            setState(() {
              if (_files.length < _maxAlbumCount) {
                final name = tmpFile.uri.pathSegments.last;
                _files.add(_PreparedFile(
                  path: tmpFile.path,
                  name: name,
                  size: tmpFile.lengthSync(),
                  type: _detectType(name),
                ));
              }
            });
            _loadImageDimensions();
            return;
          }
        }
      }
    } catch (_) {}
    // Fallback: just let normal paste happen
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      final sel = _captionController.selection;
      final text = _captionController.text;
      final newText = text.replaceRange(
        sel.start,
        sel.end,
        data.text!,
      );
      if (newText.length <= _kCaptionMaxLength) {
        _captionController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: sel.start + data.text!.length),
        );
      }
    }
  }

  Future<void> _showEditCaptionDialog(int fileIndex) async {
    final current = _perFileCaptions[fileIndex] ?? '';
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit caption'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: _kCaptionMaxLength,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Caption...',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    setState(() {
      if (result.isEmpty) {
        _perFileCaptions.remove(fileIndex);
      } else {
        _perFileCaptions[fileIndex] = result;
      }
    });
  }

  Future<void> _loadImageDimensions() async {
    bool changed = false;
    for (final file in _files) {
      if ((file.type == _FileType.photo || file.type == _FileType.video) &&
          file.imageWidth == null) {
        try {
          final data = await File(file.path).readAsBytes();
          final codec = await ui.instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          file.imageWidth = frame.image.width.toDouble();
          file.imageHeight = frame.image.height.toDouble();
          file.hasThumb = true;
          frame.image.dispose();
          codec.dispose();
          changed = true;
        } catch (_) {
          file.hasThumb = false;
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _reorderMediaFiles(int fromIdx, int toIdx) {
    final media = _files
        .where((f) => f.type == _FileType.photo || f.type == _FileType.video)
        .toList();
    if (fromIdx < 0 || fromIdx >= media.length ||
        toIdx < 0 || toIdx >= media.length ||
        fromIdx == toIdx) return;
    final fA = media[fromIdx];
    final fB = media[toIdx];
    final idxA = _files.indexOf(fA);
    final idxB = _files.indexOf(fB);
    if (idxA >= 0 && idxB >= 0) {
      setState(() {
        _files[idxA] = fB;
        _files[idxB] = fA;
      });
    }
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

  bool get _hasHighQualityOption =>
      !_sendAsDocuments && _files.any((f) => f.type == _FileType.photo);

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

  bool get _hasPaidPrice => widget.starsPerMessage > 0;

  bool get _canSpoiler =>
      !_hasPaidPrice &&
      !_sendAsDocuments &&
      _files.any((f) => f.type == _FileType.photo || f.type == _FileType.video);

  bool get _hasChangedWay =>
      _sendAsDocuments != _initialSendAsDocuments ||
      _groupFiles != _initialGroupFiles;

  bool get _allSpoilered =>
      _files.where((f) => f.type == _FileType.photo || f.type == _FileType.video)
          .every((f) => f.spoiler);

  bool get _anySpoilered =>
      _files.any((f) => f.spoiler);

  void _toggleSpoiler(int index) {
    if (_hasPaidPrice) return;
    setState(() => _files[index].spoiler = !_files[index].spoiler);
  }

  void _toggleAllSpoilers() {
    if (_hasPaidPrice) return;
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
        if (_hasHighQualityOption)
          TelegramMenuItem(
            value: 'quality',
            icon: Icon(_sendLargePhotos ? Icons.hd_outlined : Icons.sd_outlined),
            label: _sendLargePhotos
                ? 'Send in standard quality'
                : 'Send in high quality',
          ),
        if (_canSpoiler)
          TelegramMenuItem(
            value: 'spoiler',
            icon: Icon(_allSpoilered ? Icons.check : Icons.blur_on),
            label: _anySpoilered ? 'Remove spoiler' : 'Hide with spoiler',
          ),
      ],
    ).then((value) {
      if (value == 'quality') setState(() => _sendLargePhotos = !_sendLargePhotos);
      if (value == 'spoiler') _toggleAllSpoilers();
    });
  }

  void _send({bool silent = false, DateTime? scheduledDate}) {
    if (_captionController.text.length > _kCaptionMaxLength) return;
    Navigator.of(context).pop(SendFilesResult(
      paths: _resultPaths,
      caption: _captionController.text,
      silent: silent,
      scheduledDate: scheduledDate,
      spoilers: _files.map((f) => f.spoiler).toList(),
      sendAsDocuments: _sendAsDocuments,
      groupFiles: _groupFiles,
      remember: _wayRemember,
      sendLargePhotos: _sendLargePhotos,
      captionAbove: _captionAbove,
      perFileCaptions: Map.from(_perFileCaptions),
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

    final showMediaPreview = !_sendAsDocuments && mediaFiles.isNotEmpty;

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
                    onPressed: !(_canSpoiler || _hasHighQualityOption) ? null : () {
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
                        onReorder: _reorderMediaFiles,
                        canSpoiler: _canSpoiler,
                        sendLargePhotos: _sendLargePhotos,
                      ),
                    if (showMediaPreview && mediaFiles.isNotEmpty && docFiles.isNotEmpty)
                      SizedBox(height: _rowSkip),
                    if (docFiles.isNotEmpty || _sendAsDocuments)
                      _FileListPreview(
                        files: _sendAsDocuments ? _files : docFiles,
                        allFiles: _files,
                        isDark: isDark,
                        textFg: textFg,
                        subFg: subFg,
                        onRemove: (file) {
                          final idx = _files.indexOf(file);
                          if (idx >= 0) _removeFile(idx);
                        },
                        perFileCaptions: _perFileCaptions,
                        onEditCaption: _sendAsDocuments ? (file) {
                          final idx = _files.indexOf(file);
                          if (idx >= 0) _showEditCaptionDialog(idx);
                        } : null,
                        onReorder: _files.length > 1 ? (from, to) {
                          final displayFiles = _sendAsDocuments ? _files : docFiles;
                          if (from < 0 || from >= displayFiles.length ||
                              to < 0 || to >= displayFiles.length) return;
                          final fA = displayFiles[from];
                          final fB = displayFiles[to];
                          final idxA = _files.indexOf(fA);
                          final idxB = _files.indexOf(fB);
                          if (idxA >= 0 && idxB >= 0) {
                            setState(() {
                              _files[idxA] = fB;
                              _files[idxB] = fA;
                            });
                          }
                        } : null,
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: _captionMaxHeight),
                      child: TextField(
                        controller: _captionController,
                        focusNode: _captionFocus,
                        maxLines: null,
                        maxLength: _kCaptionMaxLength,
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
                  _EmojiToggleButton(
                    active: _showEmojiPanel,
                    accentColor: accentFg,
                    subColor: subFg,
                    onPressed: () => setState(() => _showEmojiPanel = !_showEmojiPanel),
                  ),
                ],
              ),
            ),
            if (_charCount > _kCaptionWarnThreshold)
              _CharactersLimitLabel(
                current: _charCount,
                max: _kCaptionMaxLength,
                accentColor: accentFg,
              ),
            if (_showEmojiPanel)
              _EmojiQuickPanel(
                isDark: isDark,
                onPick: (emoji) {
                  final sel = _captionController.selection;
                  final text = _captionController.text;
                  final newText = text.replaceRange(sel.start, sel.end, emoji);
                  if (newText.length <= _kCaptionMaxLength) {
                    _captionController.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(offset: sel.start + emoji.length),
                    );
                  }
                  _captionFocus.requestFocus();
                },
              ),
            if (_hasMediaFiles || _hasGroupOption || _canMoveCaption)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 20, 0),
                child: Column(
                  children: [
                    if (_hasGroupOption && !widget.isSlowMode)
                      _CheckboxRow(
                        label: 'Group files',
                        value: _groupFiles,
                        accentColor: accentFg,
                        textColor: textFg,
                        onChanged: (v) => setState(() => _groupFiles = v),
                      ),
                    if (_hasMediaFiles)
                      _CheckboxRow(
                        label: mediaFiles.length == 1
                            ? 'Send as document'
                            : 'Send as documents',
                        value: _sendAsDocuments,
                        accentColor: accentFg,
                        textColor: textFg,
                        onChanged: (v) => setState(() => _sendAsDocuments = v),
                      ),
                    if (_canMoveCaption)
                      _CheckboxRow(
                        label: 'Caption above',
                        value: _captionAbove,
                        accentColor: accentFg,
                        textColor: textFg,
                        onChanged: (v) => setState(() => _captionAbove = v),
                      ),
                    if (_hasChangedWay)
                      _CheckboxRow(
                        label: 'Remember',
                        value: _wayRemember,
                        accentColor: accentFg,
                        textColor: textFg,
                        onChanged: (v) => setState(() => _wayRemember = v),
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
  final void Function(int, int) onReorder;
  final bool canSpoiler;
  final bool sendLargePhotos;

  const _MediaPreview({
    required this.files,
    required this.allFiles,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.onReorder,
    required this.canSpoiler,
    required this.sendLargePhotos,
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
        sendLargePhotos: sendLargePhotos,
      );
    }
    return _AlbumPreview(
      files: files,
      allFiles: allFiles,
      onRemove: onRemove,
      onToggleSpoiler: onToggleSpoiler,
      onReorder: onReorder,
      canSpoiler: canSpoiler,
      sendLargePhotos: sendLargePhotos,
    );
  }
}

class _SingleMediaPreview extends StatelessWidget {
  final _PreparedFile file;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onToggleSpoiler;
  final bool canSpoiler;
  final bool sendLargePhotos;

  const _SingleMediaPreview({
    required this.file,
    required this.canRemove,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.canSpoiler,
    required this.sendLargePhotos,
  });

  @override
  Widget build(BuildContext context) {
    final showHdBadge = sendLargePhotos && file.type == _FileType.photo;
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
              if (showHdBadge)
                const Positioned(
                  bottom: 3,
                  right: 3,
                  child: _HdBadge(),
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

class _AlbumPreview extends StatefulWidget {
  final List<_PreparedFile> files;
  final List<_PreparedFile> allFiles;
  final void Function(_PreparedFile) onRemove;
  final void Function(_PreparedFile) onToggleSpoiler;
  final void Function(int fromIndex, int toIndex) onReorder;
  final bool canSpoiler;
  final bool sendLargePhotos;

  const _AlbumPreview({
    required this.files,
    required this.allFiles,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.onReorder,
    required this.canSpoiler,
    required this.sendLargePhotos,
  });

  @override
  State<_AlbumPreview> createState() => _AlbumPreviewState();
}

class _AlbumPreviewState extends State<_AlbumPreview>
    with SingleTickerProviderStateMixin {
  List<_LayoutRect> _layout = [];
  double _totalHeight = 0;
  int? _dragIndex;
  Offset _dragOffset = Offset.zero;
  late AnimationController _shrinkAnim;

  @override
  void initState() {
    super.initState();
    _shrinkAnim = AnimationController(
      duration: const Duration(milliseconds: _shrinkDurationMs),
      vsync: this,
    )..addListener(() => setState(() {}));
    _recompute();
  }

  @override
  void didUpdateWidget(covariant _AlbumPreview old) {
    super.didUpdateWidget(old);
    _recompute();
  }

  @override
  void dispose() {
    _shrinkAnim.dispose();
    super.dispose();
  }

  void _recompute() {
    final ratios = widget.files.map((f) => f.aspectRatio).toList();
    _layout = _computeAlbumRects(ratios);
    _totalHeight =
        _layout.isEmpty ? 0 : _layout.map((l) => l.rect.bottom).reduce(math.max);
  }

  void _onPanStart(int index, DragStartDetails details) {
    setState(() {
      _dragIndex = index;
      _dragOffset = Offset.zero;
    });
    _shrinkAnim.forward();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragIndex == null) return;
    setState(() => _dragOffset += details.delta);
    final dragCenter = _layout[_dragIndex!].rect.center + _dragOffset;
    int? closest;
    double minDist = double.infinity;
    for (int i = 0; i < _layout.length; i++) {
      if (i == _dragIndex) continue;
      final c = _layout[i].rect.center;
      final d = (c.dx - dragCenter.dx).abs() + (c.dy - dragCenter.dy).abs();
      if (d < minDist) {
        minDist = d;
        closest = i;
      }
    }
    if (closest != null) {
      final targetRect = _layout[closest].rect;
      if (targetRect.contains(dragCenter) ||
          minDist < targetRect.shortestSide * 0.8) {
        widget.onReorder(_dragIndex!, closest);
        setState(() {
          _dragIndex = closest;
          _dragOffset = Offset.zero;
        });
        _recompute();
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _shrinkAnim.reverse();
    setState(() {
      _dragIndex = null;
      _dragOffset = Offset.zero;
    });
  }

  void _showThumbMenu(BuildContext context, Offset position, _PreparedFile file) {
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
      if (value == 'spoiler') widget.onToggleSpoiler(file);
    });
  }

  void _openEditor(_PreparedFile file) {
    if (file.type != _FileType.photo) return;
    PhotoCropEditor.open(
      context,
      imageFile: File(file.path),
      shape: PhotoCropShape.rect,
      doneLabel: 'Done',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_layout.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: _previewWidth,
      height: _totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < _layout.length; i++)
            if (i != _dragIndex) _buildThumb(i, false),
          if (_dragIndex != null) _buildThumb(_dragIndex!, true),
        ],
      ),
    );
  }

  Widget _buildThumb(int index, bool isDragged) {
    final item = _layout[index];
    final file = widget.files[item.index];
    final shrink = isDragged ? _shrinkAnim.value * _shrinkSize : 0.0;
    final dx = isDragged ? _dragOffset.dx : 0.0;
    final dy = isDragged ? _dragOffset.dy : 0.0;
    final thumbW = item.rect.width - shrink * 2;
    final thumbH = item.rect.height - shrink * 2;

    return AnimatedPositioned(
      duration: Duration(milliseconds: isDragged ? 0 : _dragDurationMs),
      curve: Curves.easeOutCubic,
      left: item.rect.left + dx + shrink,
      top: item.rect.top + dy + shrink,
      width: thumbW,
      height: thumbH,
      child: GestureDetector(
        onPanStart: (d) => _onPanStart(index, d),
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onSecondaryTapUp: widget.canSpoiler
            ? (details) => _showThumbMenu(context, details.globalPosition, file)
            : null,
        onDoubleTap: () => _openEditor(file),
        child: ClipRRect(
          borderRadius: item.corners,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(file.path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.broken_image,
                      color: Colors.white54, size: 32),
                ),
              ),
              if (file.spoiler) const _SpoilerOverlay(),
              if (file.type == _FileType.video)
                const Center(
                  child:
                      Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
                ),
              if (widget.sendLargePhotos && file.type == _FileType.photo)
                const Positioned(
                  bottom: 3,
                  right: 3,
                  child: _HdBadge(),
                ),
              _ThumbCapsule(
                thumbWidth: thumbW,
                thumbHeight: thumbH,
                canRemove: widget.allFiles.length > 1,
                onEdit: () => _openEditor(file),
                onRemove: () => widget.onRemove(file),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutRect {
  final int index;
  final Rect rect;
  final BorderRadius corners;
  const _LayoutRect(this.index, this.rect, this.corners);
}

class _AlbumRowSpec {
  final double height;
  final List<_AlbumCellSpec> items;
  const _AlbumRowSpec(this.height, this.items);
}

class _AlbumCellSpec {
  final int index;
  final double width;
  const _AlbumCellSpec(this.index, this.width);
}

List<_LayoutRect> _computeAlbumRects(List<double> ratios) {
  const w = _previewWidth;
  const s = _albumSpacing;
  const rc = _thumbCornerRadius;
  final n = ratios.length;
  if (n == 0) return [];

  final cr = ratios.map((v) => v.clamp(0.6667, 2.75)).toList();

  List<_LayoutRect> buildRects(List<_AlbumRowSpec> rows) {
    final result = <_LayoutRect>[];
    double y = 0;
    for (int ri = 0; ri < rows.length; ri++) {
      double x = 0;
      final row = rows[ri];
      for (int ci = 0; ci < row.items.length; ci++) {
        final cell = row.items[ci];
        final isTop = ri == 0;
        final isBot = ri == rows.length - 1;
        final isLeft = ci == 0;
        final isRight = ci == row.items.length - 1;
        result.add(_LayoutRect(
          cell.index,
          Rect.fromLTWH(x, y, cell.width, row.height),
          BorderRadius.only(
            topLeft: isTop && isLeft ? const Radius.circular(rc) : Radius.zero,
            topRight:
                isTop && isRight ? const Radius.circular(rc) : Radius.zero,
            bottomLeft:
                isBot && isLeft ? const Radius.circular(rc) : Radius.zero,
            bottomRight:
                isBot && isRight ? const Radius.circular(rc) : Radius.zero,
          ),
        ));
        x += cell.width + s;
      }
      y += row.height + s;
    }
    return result;
  }

  if (n == 1) {
    final h = (w / cr[0]).clamp(100.0, w);
    return [
      _LayoutRect(0, Rect.fromLTWH(0, 0, w, h), BorderRadius.circular(rc))
    ];
  }

  if (n == 2) {
    final allWide = cr[0] > 1.2 && cr[1] > 1.2;
    final avg = (cr[0] + cr[1]) / 2;
    if (allWide && avg > 1.4 && (cr[1] - cr[0]).abs() < 0.2) {
      final totalH = w;
      final h0 = (totalH - s) / (1 + cr[1] / cr[0]);
      final h1 = totalH - s - h0;
      return buildRects([
        _AlbumRowSpec(h0, [_AlbumCellSpec(0, w)]),
        _AlbumRowSpec(h1, [_AlbumCellSpec(1, w)]),
      ]);
    }
    final h = ((w - s) / (cr[0] + cr[1])).clamp(100.0, w);
    final w0 = h * cr[0];
    final w1 = w - s - w0;
    return buildRects([
      _AlbumRowSpec(h, [_AlbumCellSpec(0, w0), _AlbumCellSpec(1, w1)]),
    ]);
  }

  if (n == 3) {
    final totalH = w;
    final topH = (totalH - s) * 0.66;
    final botH = totalH - s - topH;
    final bw0 = (botH * cr[1]).clamp(_albumMinCellWidth, w - s - _albumMinCellWidth);
    final bw1 = w - s - bw0;
    return buildRects([
      _AlbumRowSpec(topH, [_AlbumCellSpec(0, w)]),
      _AlbumRowSpec(botH, [_AlbumCellSpec(1, bw0), _AlbumCellSpec(2, bw1)]),
    ]);
  }

  if (n == 4) {
    final totalH = w;
    final topH = (totalH - s) * 0.66;
    final botH = totalH - s - topH;
    final tw0 =
        (topH * cr[0]).clamp(_albumMinCellWidth, w - s - _albumMinCellWidth);
    final tw1 = w - s - tw0;
    final bw0 =
        (botH * cr[2]).clamp(_albumMinCellWidth, w - s - _albumMinCellWidth);
    final bw1 = w - s - bw0;
    return buildRects([
      _AlbumRowSpec(topH, [_AlbumCellSpec(0, tw0), _AlbumCellSpec(1, tw1)]),
      _AlbumRowSpec(botH, [_AlbumCellSpec(2, bw0), _AlbumCellSpec(3, bw1)]),
    ]);
  }

  // 5-10 items: multi-row layout
  final rows = <_AlbumRowSpec>[];
  int idx = 0;
  while (idx < n) {
    final remaining = n - idx;
    int rowCount;
    if (remaining >= 5) {
      rowCount = 3;
    } else if (remaining == 4) {
      rowCount = 2;
    } else {
      rowCount = remaining > 3 ? 3 : remaining;
    }
    final rowRatios = cr.sublist(idx, idx + rowCount);
    final totalRatio = rowRatios.fold(0.0, (double sum, double r) => sum + r);
    final nRows = (n / 2.5).ceil();
    final totalSpacing = (nRows - 1) * s;
    final h = ((w * 4 / 3 - totalSpacing) / nRows)
        .clamp(60.0, w * 0.5);
    final cells = <_AlbumCellSpec>[];
    double x = 0;
    for (int j = 0; j < rowCount; j++) {
      double cellW;
      if (j == rowCount - 1) {
        cellW = w - x;
      } else {
        final ideal = (w - (rowCount - 1) * s) * rowRatios[j] / totalRatio;
        final maxCellW =
            w - x - (rowCount - 1 - j) * (_albumMinCellWidth + s);
        cellW = ideal.clamp(_albumMinCellWidth, maxCellW);
      }
      cells.add(_AlbumCellSpec(idx + j, cellW));
      x += cellW + s;
    }
    rows.add(_AlbumRowSpec(h, cells));
    idx += rowCount;
  }
  return buildRects(rows);
}

class _ThumbCapsule extends StatelessWidget {
  final double thumbWidth;
  final double thumbHeight;
  final bool canRemove;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ThumbCapsule({
    required this.thumbWidth,
    required this.thumbHeight,
    required this.canRemove,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    double cW, cH;
    bool isVertical = false;
    bool isSmall = false;

    if (thumbWidth >= _capsuleW + _capsuleSkipRight * 2 + 10) {
      cW = _capsuleW;
      cH = _capsuleH;
    } else if (thumbHeight >= _capsuleVertH + _capsuleSkipTop * 2 + 10) {
      cW = _capsuleVertW;
      cH = _capsuleVertH;
      isVertical = true;
    } else {
      cW = _capsuleSmallW;
      cH = _capsuleSmallH;
      isSmall = true;
    }

    Widget capsuleContent;
    if (isSmall) {
      capsuleContent = Center(
        child: _CapsuleIcon(
          icon: canRemove ? Icons.close : Icons.edit,
          onTap: canRemove ? onRemove : onEdit,
        ),
      );
    } else if (isVertical) {
      capsuleContent = Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CapsuleIcon(icon: Icons.edit, onTap: onEdit),
          if (canRemove) _CapsuleIcon(icon: Icons.close, onTap: onRemove),
        ],
      );
    } else {
      capsuleContent = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CapsuleIcon(icon: Icons.edit, onTap: onEdit),
          if (canRemove) ...[
            const SizedBox(width: _capsuleGap),
            _CapsuleIcon(icon: Icons.close, onTap: onRemove),
          ],
        ],
      );
    }

    return Positioned(
      top: _capsuleSkipTop,
      right: _capsuleSkipRight,
      child: Container(
        width: cW,
        height: cH,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(cH / 2),
        ),
        child: capsuleContent,
      ),
    );
  }
}

class _CapsuleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CapsuleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
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

class _FileListPreview extends StatefulWidget {
  final List<_PreparedFile> files;
  final List<_PreparedFile> allFiles;
  final bool isDark;
  final Color textFg;
  final Color subFg;
  final void Function(_PreparedFile) onRemove;
  final Map<int, String> perFileCaptions;
  final void Function(_PreparedFile)? onEditCaption;
  final void Function(int fromIndex, int toIndex)? onReorder;

  const _FileListPreview({
    required this.files,
    required this.allFiles,
    required this.isDark,
    required this.textFg,
    required this.subFg,
    required this.onRemove,
    this.perFileCaptions = const {},
    this.onEditCaption,
    this.onReorder,
  });

  @override
  State<_FileListPreview> createState() => _FileListPreviewState();
}

class _FileListPreviewState extends State<_FileListPreview> {
  int? _dragFromIndex;
  int? _dragOverIndex;

  void _onDragAccepted(int fromIndex, int toIndex) {
    if (widget.onReorder != null && fromIndex != toIndex) {
      widget.onReorder!(fromIndex, toIndex);
    }
    setState(() {
      _dragFromIndex = null;
      _dragOverIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < widget.files.length; i++) ...[
          if (i > 0) SizedBox(height: _rowSkip),
          DragTarget<int>(
            onWillAcceptWithDetails: (details) {
              setState(() => _dragOverIndex = i);
              return details.data != i;
            },
            onLeave: (_) => setState(() => _dragOverIndex = null),
            onAcceptWithDetails: (details) => _onDragAccepted(details.data, i),
            builder: (ctx, candidateData, rejectedData) {
              final isOver = _dragOverIndex == i && candidateData.isNotEmpty;
              final file = widget.files[i];
              final caption = widget.perFileCaptions[
                  widget.allFiles.indexOf(file)];
              final cardOnly = _FileCard(
                file: file,
                isDark: widget.isDark,
                textFg: widget.textFg,
                subFg: widget.subFg,
                canRemove: false,
                onRemove: () {},
                caption: caption,
              );
              final hasEdit = widget.onEditCaption != null;
              final hasRemove = widget.allFiles.length > 1;
              final thumbed = file.isThumbedLayout;
              final thumbSize = thumbed ? _fileThumbSize : _fileIconSize;
              final hasCaption = caption != null && caption.isNotEmpty;
              final cardHeight = hasCaption
                  ? thumbSize + _fileCaptionTopOffset + 18
                  : thumbSize;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isOver
                      ? (widget.isDark
                          ? const Color(0x20FFFFFF)
                          : const Color(0x15000000))
                      : null,
                ),
                child: SizedBox(
                  height: cardHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      LongPressDraggable<int>(
                        data: i,
                        axis: Axis.vertical,
                        feedback: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: _previewWidth,
                            child: Opacity(opacity: 0.85, child: cardOnly),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3, child: cardOnly),
                        child: cardOnly,
                      ),
                      if (hasEdit || hasRemove)
                        Positioned(
                          top: _fileButtonSkipTop,
                          right: _fileButtonSkipRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasEdit)
                                _FileActionButton(
                                  icon: Icons.edit_outlined,
                                  isDark: widget.isDark,
                                  onPressed: () =>
                                      widget.onEditCaption!(file),
                                ),
                              if (hasEdit && hasRemove)
                                Transform.translate(
                                  offset: const Offset(_fileButtonGap, 0),
                                  child: _FileActionButton(
                                    icon: Icons.close,
                                    isDark: widget.isDark,
                                    onPressed: () =>
                                        widget.onRemove(file),
                                  ),
                                )
                              else if (hasRemove)
                                _FileActionButton(
                                  icon: Icons.close,
                                  isDark: widget.isDark,
                                  onPressed: () =>
                                      widget.onRemove(file),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
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
  final String? caption;

  const _FileCard({
    required this.file,
    required this.isDark,
    required this.textFg,
    required this.subFg,
    required this.canRemove,
    required this.onRemove,
    this.caption,
  });

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
    final thumbed = file.isThumbedLayout;
    final thumbSize = thumbed ? _fileThumbSize : _fileIconSize;
    final thumbGap = thumbed ? _fileThumbSkip : _fileIconSkip;
    final nameTop = thumbed ? _fileThumbNameTop : _fileIconNameTop;
    final statusTop = thumbed ? _fileThumbStatusTop : _fileIconStatusTop;
    final hasCaption = caption != null && caption!.isNotEmpty;
    final totalHeight = hasCaption
        ? thumbSize + _fileCaptionTopOffset + 18
        : thumbSize;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumbed)
                ClipRRect(
                  borderRadius: BorderRadius.circular(_fileThumbRadius),
                  child: SizedBox(
                    width: _fileThumbSize,
                    height: _fileThumbSize,
                    child: Image.file(
                      File(file.path),
                      width: _fileThumbSize,
                      height: _fileThumbSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.broken_image,
                            color: Colors.white54, size: 24),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: _fileIconSize,
                  height: _fileIconSize,
                  decoration: BoxDecoration(
                    color: _iconBgColor(),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconData(), color: Colors.white, size: 22),
                ),
              SizedBox(width: thumbGap),
              Expanded(
                child: SizedBox(
                  height: thumbSize,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 52,
                        top: nameTop,
                        child: Text(
                          file.displayName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textFg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: statusTop,
                        child: Text(
                          thumbed
                              ? '${file.imageWidth!.toInt()} × ${file.imageHeight!.toInt()}'
                              : formatSize(file.size),
                          style: TextStyle(fontSize: 12, color: subFg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (hasCaption)
            Positioned(
              left: thumbSize + thumbGap,
              top: thumbSize + _fileCaptionTopOffset,
              right: 0,
              child: Text(
                caption!,
                style: TextStyle(fontSize: 12, color: subFg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _FileActionButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;

  const _FileActionButton({
    required this.icon,
    required this.isDark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(icon, size: 16,
            color: isDark ? const Color(0xFF8B9BAA) : const Color(0xFF999999)),
      ),
    );
  }
}

class _HdBadge extends StatelessWidget {
  const _HdBadge();

  @override
  Widget build(BuildContext context) {
    const text = 'HD';
    const fontSize = 11.0;
    const hPadding = 2.0;
    const strokeWidth = 1.0;
    const style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
      height: 1.2,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: hPadding + strokeWidth),
      decoration: BoxDecoration(
        color: const Color(0x80000000),
        borderRadius: BorderRadius.circular((fontSize * 1.2 + strokeWidth * 2) / 3),
      ),
      child: const Text(text, style: style),
    );
  }
}

class _SpoilerOverlay extends StatefulWidget {
  const _SpoilerOverlay();

  @override
  State<_SpoilerOverlay> createState() => _SpoilerOverlayState();
}

class _SpoilerOverlayState extends State<_SpoilerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return CustomPaint(
          painter: _SpoilerParticlePainter(_ctrl.value),
          child: child,
        );
      },
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(color: const Color(0x20000000)),
      ),
    );
  }
}

class _SpoilerParticlePainter extends CustomPainter {
  final double phase;
  _SpoilerParticlePainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x40FFFFFF);
    final rng = math.Random(42);
    const count = 80;
    for (int i = 0; i < count; i++) {
      final baseX = rng.nextDouble();
      final baseY = rng.nextDouble();
      final speed = 0.3 + rng.nextDouble() * 0.7;
      final r = 1.0 + rng.nextDouble() * 1.5;
      final offset = (phase * speed) % 1.0;
      final x = ((baseX + offset) % 1.0) * size.width;
      final y = ((baseY + offset * 0.5) % 1.0) * size.height;
      final alpha = (0.3 + 0.7 * math.sin((phase + i * 0.05) * math.pi * 2)).clamp(0.0, 1.0);
      paint.color = Color.fromRGBO(255, 255, 255, alpha * 0.35);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_SpoilerParticlePainter old) => old.phase != phase;
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

class _EmojiToggleButton extends StatelessWidget {
  final bool active;
  final Color accentColor;
  final Color subColor;
  final VoidCallback onPressed;

  const _EmojiToggleButton({
    required this.active,
    required this.accentColor,
    required this.subColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(
          active ? Icons.keyboard : Icons.emoji_emotions_outlined,
          color: active ? accentColor : subColor,
          size: 22,
        ),
        onPressed: onPressed,
        splashRadius: 18,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _CharactersLimitLabel extends StatelessWidget {
  final int current;
  final int max;
  final Color accentColor;

  const _CharactersLimitLabel({
    required this.current,
    required this.max,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = max - current;
    final isOver = remaining < 0;
    final color = isOver
        ? const Color(0xFFDD4B39)
        : remaining < 100
            ? const Color(0xFFE5A100)
            : accentColor;
    return Padding(
      padding: const EdgeInsets.only(right: 48, top: 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$remaining',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _EmojiQuickPanel extends StatelessWidget {
  final bool isDark;
  final void Function(String emoji) onPick;

  const _EmojiQuickPanel({
    required this.isDark,
    required this.onPick,
  });

  static const _recentEmojis = [
    '\u{1F600}', '\u{1F602}', '\u{1F60D}', '\u{1F622}', '\u{1F44D}',
    '\u{1F44F}', '\u{1F525}', '\u{2764}', '\u{1F389}', '\u{1F60E}',
    '\u{1F914}', '\u{1F631}', '\u{1F4AF}', '\u{1F60A}', '\u{1F642}',
    '\u{1F609}', '\u{1F618}', '\u{1F60B}', '\u{1F61C}', '\u{1F60F}',
    '\u{1F44C}', '\u{270C}', '\u{1F4AA}', '\u{1F64F}', '\u{1F680}',
    '\u{1F31F}', '\u{1F381}', '\u{1F3B6}', '\u{1F48E}', '\u{1F319}',
  ];

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1E2C38) : const Color(0xFFF5F5F5);
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _recentEmojis.length,
        itemBuilder: (ctx, i) {
          return GestureDetector(
            onTap: () => onPick(_recentEmojis[i]),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Text(
                _recentEmojis[i],
                style: const TextStyle(fontSize: 22),
              ),
            ),
          );
        },
      ),
    );
  }
}
