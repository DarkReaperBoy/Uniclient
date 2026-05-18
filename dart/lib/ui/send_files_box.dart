import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart' show ChatType, MemberInfo, ScheduledMessages;
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';
import 'compose_entities.dart';
import 'emoji_panel.dart' show EmojiTabbedPanel, addRecentEmoji;
import 'popup_menu.dart';
import 'choose_datetime_box.dart';
import 'photo_crop_editor.dart';
import 'telegram_toast.dart' show showTelegramToast;

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

const Set<String> _kPhotoExts = {'jpg', 'jpeg', 'png', 'bmp', 'webp', 'heic', 'heif'};
const Set<String> _kVideoExts = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', '3gp'};
const Set<String> _kMusicExts = {
  'mp3', 'm4a', 'flac', 'ogg', 'wav', 'aac', 'wma', 'opus', 'aiff', 'ape',
};
const Set<String> _kStickerMimes = {'tgs'};

class SendFilesResult {
  final List<String> paths;
  final String caption;
  final String captionEntitiesJson;
  final bool silent;
  final DateTime? scheduledDate;
  final List<bool> spoilers;
  final bool sendAsDocuments;
  final bool groupFiles;
  final bool remember;
  final bool sendLargePhotos;
  final bool captionAbove;
  final Map<int, String> perFileCaptions;
  final Map<int, String> perFileCaptionEntities;
  final bool ctrlShiftEnter;
  final bool sendAsSticker;
  final Map<int, String> videoCoverPaths;

  const SendFilesResult({
    required this.paths,
    this.caption = '',
    this.captionEntitiesJson = '',
    this.silent = false,
    this.scheduledDate,
    this.spoilers = const [],
    this.sendAsDocuments = false,
    this.groupFiles = true,
    this.remember = false,
    this.sendLargePhotos = true,
    this.captionAbove = false,
    this.perFileCaptions = const {},
    this.perFileCaptionEntities = const {},
    this.ctrlShiftEnter = false,
    this.sendAsSticker = false,
    this.videoCoverPaths = const {},
  });
}

enum _FileType { photo, video, music, file }

enum _DragZoneMode { documentOnly, photoOnly, both }

enum MimeDataState { photoFiles, mediaFiles, image, files, none }

/// §48.4: classify files — GIFs are MediaFiles not PhotoFiles.
MimeDataState classifyMimeData(List<String> paths) {
  if (paths.isEmpty) return MimeDataState.files;
  bool allPhoto = true;
  bool allMedia = true;
  for (final p in paths) {
    final name = p.split('/').last;
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'gif') {
      allPhoto = false; // GIFs are media, not photos
    } else {
      final isPhoto = _kPhotoExts.contains(ext);
      final isVideo = _kVideoExts.contains(ext);
      if (!isPhoto) allPhoto = false;
      if (!isPhoto && !isVideo) {
        allMedia = false;
      }
    }
  }
  if (allPhoto) return MimeDataState.photoFiles;
  if (allMedia) return MimeDataState.mediaFiles;
  return MimeDataState.files;
}

class RecentHashtags {
  static final List<String> _tags = [];

  static void addTag(String tag) {
    final lower = tag.toLowerCase();
    _tags.removeWhere((t) => t.toLowerCase() == lower);
    _tags.insert(0, tag);
    if (_tags.length > 40) _tags.removeLast();
  }

  static void extractFromText(String text) {
    for (final m in RegExp(r'#(\w+)').allMatches(text)) {
      addTag(m.group(1)!);
    }
  }

  static List<String> search(String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return _tags.take(5).toList();
    return _tags
        .where((t) => t.toLowerCase().startsWith(q))
        .take(5)
        .toList();
  }
}

class _PreparedFile {
  final String path;
  final String name;
  final int size;
  _FileType type;
  bool spoiler;
  double? imageWidth;
  double? imageHeight;
  bool hasThumb;
  String? audioTitle;
  String? audioPerformer;
  String? videoCoverPath;

  _PreparedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.type,
    this.spoiler = false,
    this.hasThumb = false,
  });

  bool get isGif => name.split('.').last.toLowerCase() == 'gif';

  bool get isSticker {
    final ext = name.split('.').last.toLowerCase();
    return ext == 'tgs' || _kStickerMimes.contains(ext);
  }

  bool get isMediaType => type == _FileType.photo || type == _FileType.video;

  bool get hasGifPreview => isGif && imageWidth != null && imageHeight != null;

  double get aspectRatio {
    if (imageWidth != null && imageHeight != null && imageHeight! > 0) {
      return imageWidth! / imageHeight!;
    }
    return 1.0;
  }

  bool get isThumbedLayout =>
      imageWidth != null && isMediaType;

  String get formattedSongName {
    if (type != _FileType.music) return displayName;
    final title = audioTitle;
    final performer = audioPerformer;
    if (title != null && title.isNotEmpty) {
      if (performer != null && performer.isNotEmpty) {
        return '$performer – $title';
      }
      return title;
    }
    if (performer != null && performer.isNotEmpty) {
      return performer;
    }
    return displayName;
  }

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
  bool? overrideGroupFiles,
  List<MemberInfo> members = const [],
  bool isBroadcast = false,
  String? replyToName,
  String? replyToText,
}) {
  return showGeneralDialog<SendFilesResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'SendFilesBox',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, animation, secondaryAnimation) => _SendFilesBoxDialog(
      filePaths: filePaths,
      chatType: chatType,
      isSelfChat: isSelfChat,
      starsPerMessage: starsPerMessage,
      isSlowMode: isSlowMode,
      overrideSendAsDocuments: overrideSendAsDocuments,
      overrideGroupFiles: overrideGroupFiles,
      members: members,
      isBroadcast: isBroadcast,
      replyToName: replyToName,
      replyToText: replyToText,
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
  final bool? overrideGroupFiles;
  final List<MemberInfo> members;
  final bool isBroadcast;
  final String? replyToName;
  final String? replyToText;

  const _SendFilesBoxDialog({
    required this.filePaths,
    this.chatType = ChatType.dm,
    this.isSelfChat = false,
    this.starsPerMessage = 0,
    this.isSlowMode = false,
    this.overrideSendAsDocuments,
    this.overrideGroupFiles,
    this.members = const [],
    this.isBroadcast = false,
    this.replyToName,
    this.replyToText,
  });

  @override
  State<_SendFilesBoxDialog> createState() => _SendFilesBoxDialogState();
}

class _SendFilesBoxDialogState extends State<_SendFilesBoxDialog>
    with TickerProviderStateMixin {
  static String _preservedCaption = '';

  late List<_PreparedFile> _files;
  final RichTextEditingController _captionController = RichTextEditingController();
  late final FocusNode _captionFocus;
  late final FocusNode _dialogFocus;
  late bool _sendAsDocuments;
  late bool _groupFiles;
  bool _wayRemember = false;
  bool _sendLargePhotos = true;
  bool _captionAbove = false;
  bool _showEmojiPanel = false;
  int _charCount = 0;
  final Map<int, String> _perFileCaptions = {};
  final Map<int, String> _perFileCaptionEntities = {};
  late final bool _initialSendAsDocuments;
  late final bool _initialGroupFiles;
  late int _starsPerMessage;
  bool _photoEditorHintShown = false;
  bool _preparing = false;
  int _preparingTotal = 0;
  int _preparingDone = 0;
  VoidCallback? _whenReadySend;
  bool _isDragOver = false;
  int _dragHoveredZone = 0; // 0=none, 1=document(top), 2=photo(bottom)
  late final AnimationController _dragOverlayAnimCtrl;
  final ScrollController _scrollController = ScrollController();
  bool _showTopShadow = false;
  bool _showBottomShadow = false;
  bool _captionDialogOpen = false;
  List<MemberInfo> _acFilteredMembers = [];
  String _acMentionQuery = '';
  bool _showMentionPanel = false;
  List<String> _acFilteredHashtags = [];
  String _acHashtagQuery = '';
  bool _showHashtagPanel = false;

  @override
  void initState() {
    super.initState();
    _dragOverlayAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scrollController.addListener(_updateScrollShadows);
    _captionFocus = FocusNode(onKeyEvent: _onCaptionKey);
    _dialogFocus = FocusNode(onKeyEvent: _onDialogKey);
    _captionController.addListener(_onCaptionChanged);
    if (_preservedCaption.isNotEmpty) {
      _captionController.text = _preservedCaption;
      _captionController.selection = TextSelection.collapsed(
        offset: _preservedCaption.length,
      );
      _preservedCaption = '';
    }
    _starsPerMessage = widget.starsPerMessage;
    _sendAsDocuments = widget.overrideSendAsDocuments ?? false;
    _groupFiles = widget.overrideGroupFiles ?? true;
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
    if (widget.isSlowMode && _files.length > 1) {
      _files = [_files.first];
    }
    _loadImageDimensions();
  }

  @override
  void dispose() {
    _dragOverlayAnimCtrl.dispose();
    _scrollController.removeListener(_updateScrollShadows);
    _scrollController.dispose();
    _captionController.removeListener(_onCaptionChanged);
    _captionController.dispose();
    _captionFocus.dispose();
    _dialogFocus.dispose();
    super.dispose();
  }

  void _onCaptionChanged() {
    final len = _captionController.text.length;
    if (len != _charCount) {
      setState(() => _charCount = len);
    }
    _detectMentionQuery();
    _detectHashtagQuery();
  }

  void _detectMentionQuery() {
    if (widget.members.isEmpty) {
      if (_showMentionPanel) setState(() => _showMentionPanel = false);
      return;
    }
    final sel = _captionController.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (_showMentionPanel) setState(() => _showMentionPanel = false);
      return;
    }
    final text = _captionController.text;
    final cursor = sel.baseOffset;
    final before = text.substring(0, cursor);
    final match = RegExp(r'@(\w*)$').firstMatch(before);
    if (match == null) {
      if (_showMentionPanel) setState(() => _showMentionPanel = false);
      return;
    }
    final query = match.group(1)!.toLowerCase();
    _acMentionQuery = query;
    final filtered = widget.members.where((m) {
      final name = m.displayName.toLowerCase();
      final uname = m.username.toLowerCase();
      return name.contains(query) || uname.contains(query);
    }).take(5).toList();
    setState(() {
      _acFilteredMembers = filtered;
      _showMentionPanel = filtered.isNotEmpty;
    });
  }

  void _insertMention(MemberInfo member) {
    final text = _captionController.text;
    final cursor = _captionController.selection.baseOffset;
    final before = text.substring(0, cursor);
    final match = RegExp(r'@(\w*)$').firstMatch(before);
    if (match == null) return;
    final start = match.start;
    final insertText = '@${member.username.isNotEmpty ? member.username : member.displayName} ';
    final after = text.substring(cursor);
    final newText = '${text.substring(0, start)}$insertText$after';
    if (newText.length > _kCaptionMaxLength) return;
    _captionController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertText.length),
    );
    setState(() => _showMentionPanel = false);
  }

  void _detectHashtagQuery() {
    final sel = _captionController.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (_showHashtagPanel) setState(() => _showHashtagPanel = false);
      return;
    }
    final text = _captionController.text;
    final cursor = sel.baseOffset;
    final before = text.substring(0, cursor);
    final match = RegExp(r'#(\w*)$').firstMatch(before);
    if (match == null) {
      if (_showHashtagPanel) setState(() => _showHashtagPanel = false);
      return;
    }
    final query = match.group(1)!;
    _acHashtagQuery = query;
    final filtered = RecentHashtags.search(query);
    setState(() {
      _acFilteredHashtags = filtered;
      _showHashtagPanel = filtered.isNotEmpty;
    });
  }

  void _insertHashtag(String hashtag) {
    final text = _captionController.text;
    final cursor = _captionController.selection.baseOffset;
    final before = text.substring(0, cursor);
    final match = RegExp(r'#(\w*)$').firstMatch(before);
    if (match == null) return;
    final start = match.start;
    final insertText = '#$hashtag ';
    final after = text.substring(cursor);
    final newText = '${text.substring(0, start)}$insertText$after';
    if (newText.length > _kCaptionMaxLength) return;
    _captionController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertText.length),
    );
    setState(() => _showHashtagPanel = false);
    RecentHashtags.addTag(hashtag);
  }

  void _updateScrollShadows() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final top = pos.pixels > 0;
    final bottom = pos.pixels < pos.maxScrollExtent;
    if (top != _showTopShadow || bottom != _showBottomShadow) {
      setState(() {
        _showTopShadow = top;
        _showBottomShadow = bottom;
      });
    }
  }

  void _toggleEmojiPanel() {
    setState(() => _showEmojiPanel = !_showEmojiPanel);
  }

  bool _shouldSendOnEnter(bool ctrl, bool shift) {
    if (ctrl && shift) return true;
    final mode = context.read<AppState>().sendBy;
    if (mode == 'enter') return !shift;
    return ctrl;
  }

  void _closePreservingCaption() {
    final parsed = _captionController.getTextWithAppliedMarkdown();
    if (parsed.text.isNotEmpty) {
      _preservedCaption = parsed.text;
    }
    Navigator.of(context).pop(null);
  }

  KeyEventResult _onCaptionKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (isEnter && ctrl && shift) {
      _send(ctrlShiftEnter: true);
      return KeyEventResult.handled;
    }
    if (isEnter && _shouldSendOnEnter(ctrl, shift)) {
      _send();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape && !_captionDialogOpen) {
      _closePreservingCaption();
      return KeyEventResult.handled;
    }

    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyV) {
      _handleCaptionPaste();
      return KeyEventResult.handled;
    }

    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyO) {
      _addMoreFiles();
      return KeyEventResult.handled;
    }

    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyB) {
      _captionController.toggleFormat(FormatType.bold);
      return KeyEventResult.handled;
    }
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyI) {
      _captionController.toggleFormat(FormatType.italic);
      return KeyEventResult.handled;
    }
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyU) {
      _captionController.toggleFormat(FormatType.underline);
      return KeyEventResult.handled;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyM) {
      _captionController.toggleFormat(FormatType.code);
      return KeyEventResult.handled;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyK) {
      _captionController.toggleFormat(FormatType.strike);
      return KeyEventResult.handled;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyP) {
      _captionController.toggleFormat(FormatType.spoiler);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }


  KeyEventResult _onDialogKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (event.logicalKey == LogicalKeyboardKey.escape && !_captionDialogOpen) {
      _closePreservingCaption();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (ctrl && shift) {
        _send(ctrlShiftEnter: true);
        return KeyEventResult.handled;
      }
      if (_shouldSendOnEnter(ctrl, shift)) {
        _send();
        return KeyEventResult.handled;
      }
    }
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyO) {
      _addMoreFiles();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _canMoveCaption =>
      !_sendAsDocuments &&
      _captionController.text.isNotEmpty &&
      _files.any((f) => f.isMediaType);

  Future<void> _handleCaptionPaste() async {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final pasted = await _tryClipboardImage();
        if (pasted) return;
      } catch (_) {}
    }
    if (Platform.isWindows) {
      try {
        final pasted = await _tryClipboardImageWindows();
        if (pasted) return;
      } catch (_) {}
    }
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

  Future<bool> _tryClipboardImage() async {
    String? types;
    String clipTool = 'wl-paste';
    // Try Wayland first
    try {
      final r = await Process.run('wl-paste', ['--list-types']);
      if (r.exitCode == 0) types = r.stdout.toString();
    } catch (_) {}
    // Fallback to X11
    if (types == null || (!types.contains('image/png') && !types.contains('image/jpeg'))) {
      try {
        final r = await Process.run('xclip', ['-selection', 'clipboard', '-t', 'TARGETS', '-o']);
        if (r.exitCode == 0) {
          types = r.stdout.toString();
          clipTool = 'xclip';
        }
      } catch (_) {}
    }
    if (types == null) return false;
    if (!types.contains('image/png') && !types.contains('image/jpeg')) return false;
    if (widget.isSlowMode && _files.isNotEmpty) {
      if (mounted) showTelegramToast(context, 'Only one file can be sent in slow mode');
      return true;
    }
    final ext = types.contains('image/png') ? 'png' : 'jpg';
    final tmpFile = File('${Directory.systemTemp.path}/uniclient_paste_${DateTime.now().millisecondsSinceEpoch}.$ext');
    ProcessResult pasteResult;
    if (clipTool == 'wl-paste') {
      pasteResult = await Process.run('wl-paste', ['--type', 'image/$ext'], stdoutEncoding: null);
    } else {
      pasteResult = await Process.run('xclip', ['-selection', 'clipboard', '-t', 'image/$ext', '-o'], stdoutEncoding: null);
    }
    if (pasteResult.exitCode == 0 && pasteResult.stdout is List<int>) {
      await tmpFile.writeAsBytes(pasteResult.stdout as List<int>);
      if (await tmpFile.exists() && await tmpFile.length() > 0) {
        setState(() {
          final name = tmpFile.uri.pathSegments.last;
          if (widget.isSlowMode) _files.clear();
          _files.add(_PreparedFile(path: tmpFile.path, name: name, size: tmpFile.lengthSync(), type: _detectType(name)));
        });
        _loadImageDimensions();
        return true;
      }
    }
    return false;
  }

  Future<bool> _tryClipboardImageWindows() async {
    final r = await Process.run('powershell', ['-Command', 'Get-Clipboard -Format Image | ForEach-Object { \$_.Save("${Directory.systemTemp.path}\\uniclient_paste_${DateTime.now().millisecondsSinceEpoch}.png") }']);
    if (r.exitCode != 0) return false;
    final tmpFile = File('${Directory.systemTemp.path}\\uniclient_paste_${DateTime.now().millisecondsSinceEpoch}.png');
    if (await tmpFile.exists() && await tmpFile.length() > 0) {
      if (widget.isSlowMode && _files.isNotEmpty) {
        if (mounted) showTelegramToast(context, 'Only one file can be sent in slow mode');
        return true;
      }
      setState(() {
        final name = tmpFile.uri.pathSegments.last;
        if (widget.isSlowMode) _files.clear();
        _files.add(_PreparedFile(path: tmpFile.path, name: name, size: tmpFile.lengthSync(), type: _detectType(name)));
      });
      _loadImageDimensions();
      return true;
    }
    return false;
  }

  Future<void> _showEditCaptionDialog(int fileIndex) async {
    _captionDialogOpen = true;
    final current = _perFileCaptions[fileIndex] ?? '';
    final controller = RichTextEditingController();
    if (current.isNotEmpty) controller.text = current;
    final result = await showDialog<({String text, String entities})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit caption'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CaptionFormattingToolbar(
              controller: controller,
              accentColor: Theme.of(ctx).colorScheme.primary,
              subColor: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: _kCaptionMaxLength,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Caption...',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final parsed = controller.getTextWithAppliedMarkdown();
              Navigator.pop(ctx, (text: parsed.text, entities: parsed.entitiesJson));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _captionDialogOpen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
    });
    if (result == null) return;
    setState(() {
      if (result.text.isEmpty) {
        _perFileCaptions.remove(fileIndex);
        _perFileCaptionEntities.remove(fileIndex);
      } else {
        _perFileCaptions[fileIndex] = result.text;
        _perFileCaptionEntities[fileIndex] = result.entities;
      }
    });
  }

  Future<void> _prepareOneFile(_PreparedFile file) async {
    if (file.type == _FileType.music) {
      await _parseAudioTags(file);
      return;
    }
    if (file.isGif) {
      await _prepareGifFile(file);
      return;
    }
    if (!file.isMediaType || file.imageWidth != null) return;
    try {
      final data = await File(file.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(data);
      if (file.type == _FileType.photo && codec.frameCount > 1) {
        codec.dispose();
        file.type = _FileType.file;
        file.hasThumb = false;
        return;
      }
      final frame = await codec.getNextFrame();
      final w = frame.image.width.toDouble();
      final h = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();
      if (w <= 0 || h <= 0 || math.max(w, h) > 20 * math.min(w, h)) {
        file.type = _FileType.file;
        file.hasThumb = false;
        return;
      }
      file.imageWidth = w;
      file.imageHeight = h;
      file.hasThumb = true;
    } catch (_) {
      if (file.type == _FileType.photo) {
        file.type = _FileType.file;
      }
      file.hasThumb = false;
    }
  }

  Future<void> _prepareGifFile(_PreparedFile file) async {
    if (file.imageWidth != null) return;
    try {
      final data = await File(file.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      final w = frame.image.width.toDouble();
      final h = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();
      if (w > 0 && h > 0 && math.max(w, h) <= 20 * math.min(w, h)) {
        file.imageWidth = w;
        file.imageHeight = h;
        file.hasThumb = true;
      }
    } catch (_) {}
  }

  static Future<void> _parseAudioTags(_PreparedFile file) async {
    try {
      final f = File(file.path);
      final length = await f.length();
      if (length < 128) return;

      final raf = await f.open(mode: FileMode.read);
      try {
        // Try ID3v2 (at start of file)
        final header = await _readBytes(raf, 0, 10);
        if (header.length >= 10 &&
            header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33) {
          final size = ((header[6] & 0x7F) << 21) |
              ((header[7] & 0x7F) << 14) |
              ((header[8] & 0x7F) << 7) |
              (header[9] & 0x7F);
          final version = header[3];
          if (size > 0 && size < length) {
            final tagData = await _readBytes(raf, 10, math.min(size, 4096));
            _parseId3v2Frames(tagData, version, file);
            if (file.audioTitle != null || file.audioPerformer != null) return;
          }
        }

        // Fallback: ID3v1 (last 128 bytes)
        final tailPos = length - 128;
        final tail = await _readBytes(raf, tailPos, 128);
        if (tail.length >= 128 &&
            tail[0] == 0x54 && tail[1] == 0x41 && tail[2] == 0x47) {
          final title = _trimId3v1String(tail.sublist(3, 33));
          final artist = _trimId3v1String(tail.sublist(33, 63));
          if (title.isNotEmpty) file.audioTitle = title;
          if (artist.isNotEmpty) file.audioPerformer = artist;
        }
      } finally {
        await raf.close();
      }
    } catch (_) {}
  }

  static Future<List<int>> _readBytes(
      RandomAccessFile raf, int offset, int count) async {
    await raf.setPosition(offset);
    return await raf.read(count);
  }

  static void _parseId3v2Frames(
      List<int> data, int version, _PreparedFile file) {
    int pos = 0;
    while (pos + 10 <= data.length) {
      final frameId = String.fromCharCodes(data.sublist(pos, pos + 4));
      if (frameId[0] == '\x00') break;

      int frameSize;
      if (version == 4) {
        frameSize = ((data[pos + 4] & 0x7F) << 21) |
            ((data[pos + 5] & 0x7F) << 14) |
            ((data[pos + 6] & 0x7F) << 7) |
            (data[pos + 7] & 0x7F);
      } else {
        frameSize = (data[pos + 4] << 24) |
            (data[pos + 5] << 16) |
            (data[pos + 6] << 8) |
            data[pos + 7];
      }

      if (frameSize <= 0 || pos + 10 + frameSize > data.length) break;

      final frameData = data.sublist(pos + 10, pos + 10 + frameSize);
      if (frameId == 'TIT2' && file.audioTitle == null) {
        file.audioTitle = _decodeId3v2Text(frameData);
      } else if (frameId == 'TPE1' && file.audioPerformer == null) {
        file.audioPerformer = _decodeId3v2Text(frameData);
      }

      if (file.audioTitle != null && file.audioPerformer != null) break;
      pos += 10 + frameSize;
    }
  }

  static String _decodeId3v2Text(List<int> data) {
    if (data.isEmpty) return '';
    final encoding = data[0];
    final textBytes = data.sublist(1);
    if (encoding == 0) {
      return String.fromCharCodes(
          textBytes.takeWhile((b) => b != 0));
    } else if (encoding == 1 || encoding == 2) {
      // UTF-16 (LE/BE with possible BOM)
      final str = StringBuffer();
      int start = 0;
      if (textBytes.length >= 2 &&
          ((textBytes[0] == 0xFF && textBytes[1] == 0xFE) ||
              (textBytes[0] == 0xFE && textBytes[1] == 0xFF))) {
        start = 2;
      }
      final bom = start == 2 && textBytes[0] == 0xFF;
      for (int i = start; i + 1 < textBytes.length; i += 2) {
        final lo = bom ? textBytes[i] : textBytes[i + 1];
        final hi = bom ? textBytes[i + 1] : textBytes[i];
        final ch = (hi << 8) | lo;
        if (ch == 0) break;
        str.writeCharCode(ch);
      }
      return str.toString();
    } else if (encoding == 3) {
      // UTF-8
      try {
        final end = textBytes.indexOf(0);
        final bytes = end >= 0 ? textBytes.sublist(0, end) : textBytes;
        return String.fromCharCodes(bytes);
      } catch (_) {
        return String.fromCharCodes(textBytes.takeWhile((b) => b != 0));
      }
    }
    return String.fromCharCodes(textBytes.takeWhile((b) => b != 0));
  }

  static String _trimId3v1String(List<int> bytes) {
    int end = bytes.length;
    while (end > 0 && (bytes[end - 1] == 0 || bytes[end - 1] == 0x20)) {
      end--;
    }
    return String.fromCharCodes(bytes.sublist(0, end));
  }

  Future<void> _loadImageDimensions() async {
    final toPrep = _files.where(
      (f) => (f.isMediaType && f.imageWidth == null) ||
             (f.isGif && f.imageWidth == null) ||
             (f.type == _FileType.music),
    ).toList();
    if (toPrep.isEmpty) return;

    final immediate = toPrep.take(_maxAlbumCount).toList();
    final queued = toPrep.skip(_maxAlbumCount).toList();

    bool changed = false;
    for (final file in immediate) {
      await _prepareOneFile(file);
      if (file.hasThumb || file.audioTitle != null) changed = true;
    }
    if (changed && mounted) setState(() {});

    if (queued.isNotEmpty && mounted) {
      setState(() {
        _preparing = true;
        _preparingTotal = queued.length;
        _preparingDone = 0;
      });
      for (final file in queued) {
        if (!mounted) return;
        await _prepareOneFile(file);
        if (!mounted) return;
        setState(() => _preparingDone++);
      }
      if (mounted) {
        setState(() => _preparing = false);
        final cb = _whenReadySend;
        if (cb != null) {
          _whenReadySend = null;
          cb();
        }
      }
    }
  }

  void _reorderMediaFiles(int fromIdx, int toIdx) {
    final media = _files.where((f) => f.isMediaType).toList();
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

  void _replaceFile(int idx, _PreparedFile replacement) {
    if (idx < 0 || idx >= _files.length) return;
    if (_files[idx].type == _FileType.photo) _photoEditorHintShown = true;
    setState(() => _files[idx] = replacement);
    _loadImageDimensions();
  }

  void _renameFile(int idx, String newName) {
    if (idx < 0 || idx >= _files.length || newName.isEmpty) return;
    setState(() {
      final f = _files[idx];
      _files[idx] = _PreparedFile(
        path: f.path,
        name: newName,
        size: f.size,
        type: f.type,
        spoiler: f.spoiler,
        hasThumb: f.hasThumb,
      )
        ..imageWidth = f.imageWidth
        ..imageHeight = f.imageHeight
        ..audioTitle = f.audioTitle
        ..audioPerformer = f.audioPerformer;
    });
  }

  void _editFileCaption(int idx) {
    if (idx < 0 || idx >= _files.length) return;
    final existing = _perFileCaptions[idx] ?? '';
    final ctrl = RichTextEditingController();
    if (existing.isNotEmpty) ctrl.text = existing;
    _captionDialogOpen = true;
    showDialog<({String text, String entities})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit caption'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CaptionFormattingToolbar(
              controller: ctrl,
              accentColor: Theme.of(ctx).colorScheme.primary,
              subColor: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: _kCaptionMaxLength,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Add a caption for this file...',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final parsed = ctrl.getTextWithAppliedMarkdown();
              Navigator.of(ctx).pop((text: parsed.text, entities: parsed.entitiesJson));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((result) {
      _captionDialogOpen = false;
      if (result == null) return;
      setState(() {
        if (result.text.isEmpty) {
          _perFileCaptions.remove(idx);
          _perFileCaptionEntities.remove(idx);
        } else {
          _perFileCaptions[idx] = result.text;
          _perFileCaptionEntities[idx] = result.entities;
        }
      });
    });
  }

  static _FileType _detectType(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'gif') return _FileType.file;
    if (_kPhotoExts.contains(ext)) return _FileType.photo;
    if (_kVideoExts.contains(ext)) return _FileType.video;
    if (_kMusicExts.contains(ext)) return _FileType.music;
    return _FileType.file;
  }

  bool get _hasMediaFiles => _files.any((f) => f.isMediaType);

  bool _canUseHighQualityPhoto(_PreparedFile f) {
    if (f.type != _FileType.photo) return false;
    if (f.imageWidth == null || f.imageHeight == null) return false;
    return math.max(f.imageWidth!, f.imageHeight!) > 1280;
  }

  bool get _hasHighQualityOption =>
      !_sendAsDocuments && _files.any(_canUseHighQualityPhoto);

  bool get _hasCompressedStickers =>
      _files.any((f) => f.isSticker);

  bool get _hasGroupOption {
    if (_files.length < 2) return false;
    if (_sendAsDocuments) return true;
    final mediaCount = _files.where((f) => f.isMediaType).length;
    if (mediaCount >= 2) return true;
    return (_files.length - mediaCount) >= 2;
  }

  bool get _canAddCaption {
    if (_files.isEmpty) return false;
    if (_files.every((f) => f.isSticker)) return false;
    return true;
  }

  List<String> get _resultPaths => _files.map((f) => f.path).toList();

  void _removeFile(int index) {
    if (index < 0 || index >= _files.length) return;
    if (_files.length <= 1) {
      _closePreservingCaption();
      return;
    }
    if (_files.length == 2 && _captionController.text.isEmpty) {
      final remainIdx = index == 0 ? 1 : 0;
      final caption = _perFileCaptions[remainIdx];
      if (caption != null && caption.isNotEmpty) {
        _captionController.text = caption;
      }
    }
    setState(() {
      _files.removeAt(index);
      final newCaptions = <int, String>{};
      final newEntities = <int, String>{};
      for (final entry in _perFileCaptions.entries) {
        if (entry.key == index) continue;
        final newIdx = entry.key > index ? entry.key - 1 : entry.key;
        newCaptions[newIdx] = entry.value;
      }
      for (final entry in _perFileCaptionEntities.entries) {
        if (entry.key == index) continue;
        final newIdx = entry.key > index ? entry.key - 1 : entry.key;
        newEntities[newIdx] = entry.value;
      }
      _perFileCaptions
        ..clear()
        ..addAll(newCaptions);
      _perFileCaptionEntities
        ..clear()
        ..addAll(newEntities);
    });
  }

  Future<void> _addMoreFiles() async {
    if (widget.isSlowMode && _files.isNotEmpty) {
      showTelegramToast(context, 'Only one file can be sent in slow mode');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: !widget.isSlowMode);
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
      if (widget.isSlowMode) {
        setState(() => _files
          ..clear()
          ..add(newFiles.first));
      } else {
        setState(() => _files.addAll(newFiles));
      }
      _loadImageDimensions();
    } catch (_) {}
  }

  void _addDroppedFiles(List<String> paths) {
    if (paths.isEmpty) return;
    if (widget.isSlowMode && _files.isNotEmpty) {
      showTelegramToast(context, 'Only one file can be sent in slow mode');
      return;
    }
    final newFiles = paths.where((p) {
      final f = File(p);
      return f.existsSync() && !FileSystemEntity.isDirectorySync(p);
    }).map((p) {
      final file = File(p);
      final name = file.uri.pathSegments.last;
      final size = file.lengthSync();
      return _PreparedFile(
        path: p,
        name: name,
        size: size,
        type: _detectType(name),
      );
    }).toList();
    if (newFiles.isEmpty) return;
    if (widget.isSlowMode) {
      setState(() => _files
        ..clear()
        ..add(newFiles.first));
    } else {
      setState(() => _files.addAll(newFiles));
    }
    _loadImageDimensions();
  }

  _DragZoneMode _computeDragZoneMode() {
    if (_sendAsDocuments) return _DragZoneMode.documentOnly;
    return _DragZoneMode.both;
  }

  bool get _hasPaidPrice => _starsPerMessage > 0;

  bool get _canSpoiler {
    if (_hasPaidPrice) return false;
    if (_files.isEmpty) return false;
    if (_files.every((f) => f.type == _FileType.video)) return true;
    if (_sendAsDocuments) return false;
    return _files.every((f) => f.isMediaType);
  }

  bool get _hasChangedWay =>
      _sendAsDocuments != _initialSendAsDocuments ||
      _groupFiles != _initialGroupFiles;

  bool get _allSpoilered =>
      _files.where((f) => f.isMediaType).every((f) => f.spoiler);

  String get _titleText {
    final count = _files.length;
    if (count > 1) {
      final imagesCount =
          _files.where((f) => f.type == _FileType.photo).length;
      return (imagesCount == count)
          ? 'Send $count images selected'
          : 'Send $count files selected';
    }
    final type = _files.isEmpty ? _FileType.file : _files.first.type;
    return switch (type) {
      _FileType.photo => 'Send image',
      _FileType.video => 'Send video',
      _ => 'Send file',
    };
  }

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
        if (f.isMediaType) {
          f.spoiler = target;
        }
      }
    });
  }

  bool get _canSendAsSticker =>
      _files.length == 1 &&
      _files.first.type == _FileType.photo &&
      !_sendAsDocuments;

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
        if (_canSendAsSticker) ...[
          if (_hasHighQualityOption || _canSpoiler)
            const TelegramMenuItem.separator(),
          const TelegramMenuItem(
            value: 'sticker',
            icon: Icon(Icons.sticky_note_2_outlined),
            label: 'Send as sticker',
          ),
        ],
      ],
    ).then((value) {
      if (value == 'quality') setState(() => _sendLargePhotos = !_sendLargePhotos);
      if (value == 'spoiler') _toggleAllSpoilers();
      if (value == 'sticker') _sendAsSticker();
    });
  }

  Future<void> _sendAsSticker() async {
    _send(asSticker: true);
  }

  void _send({bool silent = false, DateTime? scheduledDate, bool ctrlShiftEnter = false, bool asSticker = false}) {
    if (_captionController.text.length > _kCaptionMaxLength) return;
    if (_preparing) {
      _whenReadySend = () => _send(silent: silent, scheduledDate: scheduledDate, ctrlShiftEnter: ctrlShiftEnter, asSticker: asSticker);
      return;
    }
    _preservedCaption = '';
    final parsed = _captionController.getTextWithAppliedMarkdown();
    RecentHashtags.extractFromText(parsed.text);
    final coverPaths = <int, String>{};
    for (var i = 0; i < _files.length; i++) {
      if (_files[i].videoCoverPath != null) {
        coverPaths[i] = _files[i].videoCoverPath!;
      }
    }
    final spoilers = _files.map((f) {
      if (!f.isMediaType) return false;
      return f.spoiler;
    }).toList();
    Navigator.of(context).pop(SendFilesResult(
      paths: _resultPaths,
      caption: parsed.text,
      captionEntitiesJson: parsed.entitiesJson,
      silent: silent,
      scheduledDate: scheduledDate,
      spoilers: spoilers,
      sendAsDocuments: _sendAsDocuments,
      groupFiles: _groupFiles,
      remember: _wayRemember,
      sendLargePhotos: _sendLargePhotos,
      captionAbove: _captionAbove,
      perFileCaptions: Map.from(_perFileCaptions),
      perFileCaptionEntities: Map.from(_perFileCaptionEntities),
      ctrlShiftEnter: ctrlShiftEnter,
      sendAsSticker: asSticker,
      videoCoverPaths: coverPaths,
    ));
  }

  void _showSendMenu(BuildContext ctx, Offset position) {
    final hasDetailItems = _hasHighQualityOption || _canSpoiler || _canMoveCaption || _canSendAsSticker;
    showTelegramMenu<String>(
      context: ctx,
      position: Offset(position.dx, position.dy - 120),
      items: [
        if (!widget.isSelfChat)
          const TelegramMenuItem(value: 'silent', icon: Icon(Icons.volume_off_outlined), label: 'Send without Sound'),
        TelegramMenuItem(value: 'schedule', icon: const Icon(Icons.schedule_outlined), label: widget.isSelfChat ? 'Set Reminder' : 'Schedule Message'),
        if (widget.chatType == ChatType.dm && !widget.isSelfChat)
          const TelegramMenuItem(value: 'when_online', icon: Icon(Icons.person_outline), label: 'Send When Online'),
        if (hasDetailItems)
          const TelegramMenuItem.separator(),
        if (_hasHighQualityOption)
          TelegramMenuItem(
            value: 'quality',
            icon: Icon(_sendLargePhotos ? Icons.check : Icons.hd_outlined),
            label: _sendLargePhotos
                ? 'Send in standard quality'
                : 'Send in high quality',
          ),
        if (_canSpoiler)
          TelegramMenuItem(
            value: 'spoiler',
            icon: Icon(_allSpoilered ? Icons.check : Icons.blur_on),
            label: 'Spoiler effect',
          ),
        if (_canMoveCaption)
          TelegramMenuItem(
            value: 'caption_pos',
            icon: Icon(_captionAbove ? Icons.arrow_downward : Icons.arrow_upward),
            label: _captionAbove ? 'Move caption down' : 'Move caption up',
          ),
        if (_canSendAsSticker)
          const TelegramMenuItem(
            value: 'sticker',
            icon: Icon(Icons.sticky_note_2_outlined),
            label: 'Send as sticker',
          ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'silent':
          _send(silent: true);
        case 'schedule':
          _pickScheduleDate();
        case 'when_online':
          _send(scheduledDate: DateTime.fromMillisecondsSinceEpoch(
            ScheduledMessages.kScheduledUntilOnlineTimestamp * 1000,
          ));
        case 'quality':
          setState(() => _sendLargePhotos = !_sendLargePhotos);
        case 'spoiler':
          _toggleAllSpoilers();
        case 'caption_pos':
          setState(() => _captionAbove = !_captionAbove);
        case 'sticker':
          _sendAsSticker();
      }
    });
  }

  void _showEditPriceDialog() {
    final ctrl = TextEditingController(text: '$_starsPerMessage');
    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set price'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Stars per message',
            prefixText: '⭐ ',
          ),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null && n > 0) Navigator.pop(ctx, n);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text);
              if (n != null && n > 0) Navigator.pop(ctx, n);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((price) {
      if (price == null) return;
      setState(() => _starsPerMessage = price);
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
      _send(scheduledDate: DateTime.fromMillisecondsSinceEpoch(
        ScheduledMessages.kScheduledUntilOnlineTimestamp * 1000,
      ));
    } else {
      _send(scheduledDate: result.dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = context.palette;
    final boxBg = p.boxBg;
    final textFg = p.boxTextFg;
    final subFg = p.boxTitleAdditionalFg;
    final accentFg = p.windowActiveTextFg;
    final dividerColor = p.boxDividerBg;

    final mediaFiles = _files.where((f) => f.isMediaType).toList();
    final gifFiles = !_sendAsDocuments
        ? _files.where((f) => f.isGif && f.hasGifPreview).toList()
        : <_PreparedFile>[];
    final docFiles = _files.where((f) {
      if (!_sendAsDocuments && f.isGif && f.hasGifPreview) return false;
      return f.type == _FileType.file || f.type == _FileType.music;
    }).toList();

    final showMediaPreview = !_sendAsDocuments && mediaFiles.isNotEmpty;

    return DropTarget(
      onDragEntered: (_) {
        setState(() => _isDragOver = true);
        _dragOverlayAnimCtrl.forward();
      },
      onDragExited: (_) {
        setState(() {
          _isDragOver = false;
          _dragHoveredZone = 0;
        });
        _dragOverlayAnimCtrl.reverse();
      },
      onDragUpdated: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final mode = _computeDragZoneMode();
        if (mode == _DragZoneMode.both) {
          final localY = details.localPosition.dy;
          final h = box.size.height;
          final newZone = localY < h / 2 ? 1 : 2;
          if (newZone != _dragHoveredZone) {
            setState(() => _dragHoveredZone = newZone);
          }
        } else {
          if (_dragHoveredZone != 1) {
            setState(() => _dragHoveredZone = 1);
          }
        }
      },
      onDragDone: (details) {
        final zone = _dragHoveredZone;
        final mode = _computeDragZoneMode();
        setState(() {
          _isDragOver = false;
          _dragHoveredZone = 0;
        });
        _dragOverlayAnimCtrl.reverse();
        final paths = details.files.map((f) => f.path).toList();
        if (paths.isNotEmpty) {
          if (mode == _DragZoneMode.both) {
            final mimeState = classifyMimeData(paths);
            if (zone == 1) {
              setState(() => _sendAsDocuments = true);
            } else if (zone == 2 && mimeState != MimeDataState.files) {
              setState(() => _sendAsDocuments = false);
            }
          }
          _addDroppedFiles(paths);
        }
      },
      child: Dialog(
      backgroundColor: boxBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      elevation: 4,
      insetPadding: const EdgeInsets.all(24),
      child: Focus(
        focusNode: _dialogFocus,
        child: SizedBox(
        width: _previewWidth + 48,
        child: Stack(
          children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _titleText,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textFg,
                      ),
                    ),
                  ),
                  _TopMenuButton(
                    isDark: isDark,
                    onPressed: !(_canSpoiler || _hasHighQualityOption || _canSendAsSticker) ? null : () {
                      final btnBox = context.findRenderObject() as RenderBox;
                      final pos = btnBox.localToGlobal(Offset(btnBox.size.width - 48, 48));
                      _showTopMenu(pos);
                    },
                  ),
                ],
              ),
            ),
            Flexible(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _updateScrollShadows();
                  });
                  return false;
                },
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    const SizedBox(height: 8),
                    if (widget.replyToName != null && widget.replyToName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: accentFg.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.reply, size: 16, color: accentFg),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(
                                      text: widget.replyToName!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: accentFg,
                                      ),
                                    ),
                                    if (widget.replyToText != null && widget.replyToText!.isNotEmpty) ...[
                                      TextSpan(
                                        text: '  ${widget.replyToText!}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: subFg,
                                        ),
                                      ),
                                    ],
                                  ]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (showMediaPreview && mediaFiles.isNotEmpty)
                      Stack(
                        children: [
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
                            onReplace: _replaceFile,
                            onRename: _renameFile,
                            onEditCaption: _editFileCaption,
                            canSpoiler: _canSpoiler,
                            sendLargePhotos: _sendLargePhotos,
                            isBroadcast: widget.isBroadcast,
                            isSelfChat: widget.isSelfChat,
                            onCoverChanged: () => setState(() {}),
                          ),
                          if (_hasPaidPrice)
                            Positioned.fill(
                              child: Center(
                                child: GestureDetector(
                                  onTap: widget.isBroadcast ? _showEditPriceDialog : null,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xCC000000),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '⭐ $_starsPerMessage',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    if (_photoEditorHintShown && showMediaPreview && mediaFiles.any((f) => f.type == _FileType.photo))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Click to open in photo editor',
                          style: TextStyle(fontSize: 11, color: subFg),
                        ),
                      ),
                    if (showMediaPreview && mediaFiles.isNotEmpty &&
                        (gifFiles.isNotEmpty || docFiles.isNotEmpty))
                      SizedBox(height: _rowSkip),
                    for (int gi = 0; gi < gifFiles.length; gi++) ...[
                      if (gi > 0) SizedBox(height: _rowSkip),
                      _GifPreview(
                        file: gifFiles[gi],
                        canRemove: _files.length > 1,
                        onRemove: () {
                          final idx = _files.indexOf(gifFiles[gi]);
                          if (idx >= 0) _removeFile(idx);
                        },
                      ),
                    ],
                    if (gifFiles.isNotEmpty && docFiles.isNotEmpty)
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
                              to < 0 || to >= displayFiles.length ||
                              from == to) return;
                          final movedFile = displayFiles[from];
                          final targetFile = displayFiles[to];
                          final srcIdx = _files.indexOf(movedFile);
                          final dstIdx = _files.indexOf(targetFile);
                          if (srcIdx >= 0 && dstIdx >= 0) {
                            setState(() {
                              _files.removeAt(srcIdx);
                              final adjustedDst = srcIdx < dstIdx ? dstIdx - 1 : dstIdx;
                              _files.insert(adjustedDst, movedFile);
                            });
                          }
                        } : null,
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
                    if (_showTopShadow)
                      Positioned(
                        top: 0, left: 0, right: 0,
                        height: 6,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  isDark ? const Color(0x2017212B) : const Color(0x18000000),
                                  const Color(0x00000000),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_showBottomShadow)
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        height: 6,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  isDark ? const Color(0x2017212B) : const Color(0x18000000),
                                  const Color(0x00000000),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            if (_showMentionPanel && _acFilteredMembers.isNotEmpty)
              _MentionAutocompletePanel(
                members: _acFilteredMembers,
                isDark: isDark,
                onSelect: _insertMention,
              ),
            if (_showHashtagPanel && _acFilteredHashtags.isNotEmpty)
              _HashtagAutocompletePanel(
                hashtags: _acFilteredHashtags,
                isDark: isDark,
                onSelect: _insertHashtag,
              ),
            if (_canAddCaption) ...[
            _CaptionFormattingToolbar(
              controller: _captionController,
              accentColor: accentFg,
              subColor: subFg,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
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
                    onPressed: _toggleEmojiPanel,
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
            ],
            EmojiTabbedPanel(
              visible: _showEmojiPanel && _canAddCaption,
              onHide: () => setState(() => _showEmojiPanel = false),
              onEmojiSelected: (emoji) {
                final sel = _captionController.selection;
                final text = _captionController.text;
                final start = sel.isValid ? sel.start : text.length;
                final end = sel.isValid ? sel.end : text.length;
                final newText = text.replaceRange(start, end, emoji);
                if (newText.length <= _kCaptionMaxLength) {
                  _captionController.value = TextEditingValue(
                    text: newText,
                    selection: TextSelection.collapsed(offset: start + emoji.length),
                  );
                }
                addRecentEmoji(emoji);
                _captionFocus.requestFocus();
              },
              onCustomEmojiSelected: (documentId, altText) {
                _captionController.insertCustomEmoji(documentId, altText);
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
            if (_preparing)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentFg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Preparing files… $_preparingDone/$_preparingTotal',
                      style: TextStyle(fontSize: 12, color: subFg),
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
                    onPressed: _closePreservingCaption,
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
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _dragOverlayAnimCtrl,
            builder: (context, child) {
              if (_dragOverlayAnimCtrl.isDismissed) return const SizedBox.shrink();
              return Opacity(
                opacity: _dragOverlayAnimCtrl.value,
                child: child,
              );
            },
            child: _SendFilesDragOverlay(
              mode: _computeDragZoneMode(),
              hoveredZone: _dragHoveredZone,
            ),
          ),
        ),
          ],
        ),
      ),
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
  final void Function(int index, _PreparedFile replacement)? onReplace;
  final void Function(int index, String newName)? onRename;
  final void Function(int index)? onEditCaption;
  final bool canSpoiler;
  final bool sendLargePhotos;
  final bool isBroadcast;
  final bool isSelfChat;
  final VoidCallback? onCoverChanged;

  const _MediaPreview({
    required this.files,
    required this.allFiles,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.onReorder,
    this.onReplace,
    this.onRename,
    this.onEditCaption,
    required this.canSpoiler,
    required this.sendLargePhotos,
    this.isBroadcast = false,
    this.isSelfChat = false,
    this.onCoverChanged,
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
        onReplace: onReplace,
        onRename: onRename,
        onEditCaption: onEditCaption,
        fileIndex: allFiles.indexOf(files.first),
        isBroadcast: isBroadcast,
        isSelfChat: isSelfChat,
        onCoverChanged: onCoverChanged,
      );
    }
    return _AlbumPreview(
      files: files,
      allFiles: allFiles,
      onRemove: onRemove,
      onToggleSpoiler: onToggleSpoiler,
      onReorder: onReorder,
      onReplace: onReplace,
      onRename: onRename,
      onEditCaption: onEditCaption,
      canSpoiler: canSpoiler,
      sendLargePhotos: sendLargePhotos,
      isBroadcast: isBroadcast,
      isSelfChat: isSelfChat,
      onCoverChanged: onCoverChanged,
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
  final void Function(int index, _PreparedFile replacement)? onReplace;
  final void Function(int index, String newName)? onRename;
  final void Function(int index)? onEditCaption;
  final int fileIndex;
  final bool isBroadcast;
  final bool isSelfChat;
  final VoidCallback? onCoverChanged;

  const _SingleMediaPreview({
    required this.file,
    required this.canRemove,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.canSpoiler,
    required this.sendLargePhotos,
    this.onReplace,
    this.onRename,
    this.onEditCaption,
    this.isBroadcast = false,
    this.isSelfChat = false,
    this.fileIndex = 0,
    this.onCoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showHdBadge = sendLargePhotos && file.type == _FileType.photo;
    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showFullContextMenu(context, details.globalPosition);
      },
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox;
        final center = box.localToGlobal(box.size.center(Offset.zero));
        _showFullContextMenu(context, center);
      },
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

  void _showFullContextMenu(BuildContext context, Offset position) {
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        const TelegramMenuItem(
          value: 'replace',
          icon: Icon(Icons.swap_horiz),
          label: 'Replace attachment',
        ),
        if (file.type == _FileType.photo)
          const TelegramMenuItem(
            value: 'edit',
            icon: Icon(Icons.edit_outlined),
            label: 'Open in photo editor',
          ),
        if (!file.isMediaType)
          const TelegramMenuItem(
            value: 'rename',
            icon: Icon(Icons.drive_file_rename_outline),
            label: 'Rename file',
          ),
        if (!file.isMediaType)
          const TelegramMenuItem(
            value: 'editcaption',
            icon: Icon(Icons.text_fields),
            label: 'Edit caption',
          ),
        if (canSpoiler && file.isMediaType)
          TelegramMenuItem(
            value: 'spoiler',
            icon: Icon(file.spoiler ? Icons.check : Icons.blur_on),
            label: 'Spoiler effect',
          ),
        if (file.type == _FileType.video && (isBroadcast || isSelfChat))
          const TelegramMenuItem(
            value: 'editcover',
            icon: Icon(Icons.image_outlined),
            label: 'Edit cover',
          ),
        if (file.type == _FileType.video && (isBroadcast || isSelfChat) && file.videoCoverPath != null)
          const TelegramMenuItem(
            value: 'clearcover',
            icon: Icon(Icons.cancel_outlined),
            label: 'Clear cover',
          ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'spoiler':
          onToggleSpoiler();
        case 'replace':
          _doReplace();
        case 'edit':
          _doEdit(context);
        case 'rename':
          _doRename(context);
        case 'editcaption':
          onEditCaption?.call(fileIndex);
        case 'editcover':
          _doEditCover(context);
        case 'clearcover':
          _doClearCover();
      }
    });
  }

  Future<void> _doReplace() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final newPath = result.files.first.path!;
      final f = File(newPath);
      if (!f.existsSync()) return;
      final name = f.uri.pathSegments.last;
      onReplace?.call(fileIndex, _PreparedFile(
        path: newPath,
        name: name,
        size: f.lengthSync(),
        type: _SendFilesBoxDialogState._detectType(name),
      ));
    } catch (_) {}
  }

  void _doEdit(BuildContext context) {
    if (file.type != _FileType.photo) return;
    PhotoCropEditor.open(
      context,
      imageFile: File(file.path),
      shape: PhotoCropShape.rect,
      purpose: PhotoEditorPurpose.edit,
      onDone: (croppedFile) async {
        final codec = await ui.instantiateImageCodec(await croppedFile.readAsBytes());
        final frame = await codec.getNextFrame();
        final replacement = _PreparedFile(
          path: croppedFile.path,
          name: file.name,
          size: croppedFile.lengthSync(),
          type: _FileType.photo,
          spoiler: file.spoiler,
        )
          ..imageWidth = frame.image.width.toDouble()
          ..imageHeight = frame.image.height.toDouble()
          ..hasThumb = true;
        onReplace?.call(fileIndex, replacement);
      },
    );
  }

  void _doRename(BuildContext context) {
    final dotIdx = file.name.lastIndexOf('.');
    final ext = dotIdx > 0 ? file.name.substring(dotIdx) : '';
    final nameOnly = dotIdx > 0 ? file.name.substring(0, dotIdx) : file.name;
    final maxNameLen = (_kMaxDisplayNameLength - ext.length).clamp(0, _kMaxDisplayNameLength);
    final ctrl = TextEditingController(text: nameOnly);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename file'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: maxNameLen,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    ).then((newName) {
      if (newName != null && newName.isNotEmpty) {
        final fullName = '$newName$ext';
        if (fullName != file.name) {
          onRename?.call(fileIndex, fullName);
        }
      }
    });
  }

  Future<void> _doEditCover(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final pickedPath = result.files.first.path!;
      final pickedFile = File(pickedPath);
      if (!pickedFile.existsSync()) return;
      final ext = pickedPath.split('.').last.toLowerCase();
      if (!_kPhotoExts.contains(ext)) {
        if (context.mounted) {
          showTelegramToast(context, 'Please select an image file for the cover');
        }
        return;
      }
      if (!context.mounted) return;
      PhotoCropEditor.open(
        context,
        imageFile: pickedFile,
        shape: PhotoCropShape.rect,
        purpose: PhotoEditorPurpose.edit,
        onDone: (croppedFile) async {
          file.videoCoverPath = croppedFile.path;
          onCoverChanged?.call();
        },
      );
    } catch (_) {}
  }

  void _doClearCover() {
    file.videoCoverPath = null;
    onCoverChanged?.call();
  }
}

class _GifPreview extends StatelessWidget {
  final _PreparedFile file;
  final bool canRemove;
  final VoidCallback onRemove;

  const _GifPreview({
    required this.file,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
                child: const Icon(Icons.broken_image,
                    color: Colors.white54, size: 48),
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'GIF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (canRemove)
              Positioned(
                top: 5,
                right: 5,
                child: _ThumbButton(
                  icon: Icons.close,
                  onPressed: onRemove,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlbumPreview extends StatefulWidget {
  final List<_PreparedFile> files;
  final List<_PreparedFile> allFiles;
  final void Function(_PreparedFile) onRemove;
  final void Function(_PreparedFile) onToggleSpoiler;
  final void Function(int fromIndex, int toIndex) onReorder;
  final void Function(int index, _PreparedFile replacement)? onReplace;
  final void Function(int index, String newName)? onRename;
  final void Function(int index)? onEditCaption;
  final bool canSpoiler;
  final bool sendLargePhotos;
  final bool isBroadcast;
  final bool isSelfChat;
  final VoidCallback? onCoverChanged;

  const _AlbumPreview({
    required this.files,
    required this.allFiles,
    required this.onRemove,
    required this.onToggleSpoiler,
    required this.onReorder,
    this.onReplace,
    this.onRename,
    this.onEditCaption,
    required this.canSpoiler,
    required this.sendLargePhotos,
    this.isBroadcast = false,
    this.isSelfChat = false,
    this.onCoverChanged,
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
    final allIdx = widget.allFiles.indexOf(file);
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        const TelegramMenuItem(
          value: 'replace',
          icon: Icon(Icons.swap_horiz),
          label: 'Replace attachment',
        ),
        if (file.type == _FileType.photo)
          const TelegramMenuItem(
            value: 'edit',
            icon: Icon(Icons.edit_outlined),
            label: 'Open in photo editor',
          ),
        if (!file.isMediaType)
          const TelegramMenuItem(
            value: 'rename',
            icon: Icon(Icons.drive_file_rename_outline),
            label: 'Rename file',
          ),
        if (!file.isMediaType)
          const TelegramMenuItem(
            value: 'editcaption',
            icon: Icon(Icons.text_fields),
            label: 'Edit caption',
          ),
        if (widget.canSpoiler && file.isMediaType)
          TelegramMenuItem(
            value: 'spoiler',
            icon: Icon(file.spoiler ? Icons.check : Icons.blur_on),
            label: 'Spoiler effect',
          ),
        if (file.type == _FileType.video && (widget.isBroadcast || widget.isSelfChat))
          const TelegramMenuItem(
            value: 'editcover',
            icon: Icon(Icons.image_outlined),
            label: 'Edit cover',
          ),
        if (file.type == _FileType.video && (widget.isBroadcast || widget.isSelfChat) && file.videoCoverPath != null)
          const TelegramMenuItem(
            value: 'clearcover',
            icon: Icon(Icons.cancel_outlined),
            label: 'Clear cover',
          ),
        if (widget.allFiles.length > 1)
          const TelegramMenuItem(
            value: 'remove',
            icon: Icon(Icons.delete_outline),
            label: 'Remove',
          ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'spoiler':
          widget.onToggleSpoiler(file);
        case 'replace':
          _replaceFile(allIdx);
        case 'edit':
          _openEditor(file);
        case 'rename':
          _renameFile(allIdx, file);
        case 'editcaption':
          widget.onEditCaption?.call(allIdx);
        case 'editcover':
          _editCover(context, file, allIdx);
        case 'clearcover':
          file.videoCoverPath = null;
          widget.onCoverChanged?.call();
        case 'remove':
          widget.onRemove(file);
      }
    });
  }

  Future<void> _replaceFile(int idx) async {
    if (idx < 0) return;
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final newPath = result.files.first.path!;
      final f = File(newPath);
      if (!f.existsSync()) return;
      final name = f.uri.pathSegments.last;
      widget.onReplace?.call(idx, _PreparedFile(
        path: newPath,
        name: name,
        size: f.lengthSync(),
        type: _SendFilesBoxDialogState._detectType(name),
      ));
    } catch (_) {}
  }

  void _renameFile(int idx, _PreparedFile file) {
    final dotIdx = file.name.lastIndexOf('.');
    final ext = dotIdx > 0 ? file.name.substring(dotIdx) : '';
    final nameOnly = dotIdx > 0 ? file.name.substring(0, dotIdx) : file.name;
    final maxNameLen = (_kMaxDisplayNameLength - ext.length).clamp(0, _kMaxDisplayNameLength);
    final ctrl = TextEditingController(text: nameOnly);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename file'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: maxNameLen,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    ).then((newName) {
      if (newName != null && newName.isNotEmpty) {
        final fullName = '$newName$ext';
        if (fullName != file.name) {
          widget.onRename?.call(idx, fullName);
        }
      }
    });
  }

  void _openEditor(_PreparedFile file) {
    if (file.type != _FileType.photo) return;
    final allIdx = widget.allFiles.indexOf(file);
    if (allIdx < 0) return;
    PhotoCropEditor.open(
      context,
      imageFile: File(file.path),
      shape: PhotoCropShape.rect,
      purpose: PhotoEditorPurpose.edit,
      onDone: (croppedFile) async {
        if (!mounted) return;
        final codec = await ui.instantiateImageCodec(await croppedFile.readAsBytes());
        final frame = await codec.getNextFrame();
        final replacement = _PreparedFile(
          path: croppedFile.path,
          name: file.name,
          size: croppedFile.lengthSync(),
          type: _FileType.photo,
          spoiler: file.spoiler,
        )
          ..imageWidth = frame.image.width.toDouble()
          ..imageHeight = frame.image.height.toDouble()
          ..hasThumb = true;
        widget.onReplace?.call(allIdx, replacement);
      },
    );
  }

  Future<void> _editCover(BuildContext context, _PreparedFile file, int allIdx) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final pickedPath = result.files.first.path!;
      final pickedFile = File(pickedPath);
      if (!pickedFile.existsSync()) return;
      final ext = pickedPath.split('.').last.toLowerCase();
      if (!_kPhotoExts.contains(ext)) {
        if (context.mounted) {
          showTelegramToast(context, 'Please select an image file for the cover');
        }
        return;
      }
      if (!context.mounted) return;
      PhotoCropEditor.open(
        context,
        imageFile: pickedFile,
        shape: PhotoCropShape.rect,
        purpose: PhotoEditorPurpose.edit,
        onDone: (croppedFile) async {
          file.videoCoverPath = croppedFile.path;
          widget.onCoverChanged?.call();
        },
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_layout.isEmpty) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: _dragDurationMs),
      curve: Curves.easeOutCubic,
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
        onSecondaryTapUp: (details) => _showThumbMenu(context, details.globalPosition, file),
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

List<_LayoutRect> _computeAlbumRects(List<double> ratios) {
  const maxW = _previewWidth;
  const sp = _albumSpacing;
  const rc = _thumbCornerRadius;
  const minCW = _albumMinCellWidth;
  final n = ratios.length;
  if (n == 0) return [];

  BorderRadius c(bool tl, bool tr, bool bl, bool br) => BorderRadius.only(
    topLeft: tl ? const Radius.circular(rc) : Radius.zero,
    topRight: tr ? const Radius.circular(rc) : Radius.zero,
    bottomLeft: bl ? const Radius.circular(rc) : Radius.zero,
    bottomRight: br ? const Radius.circular(rc) : Radius.zero,
  );

  String classify(double r) => r > 1.2 ? 'w' : (r < 0.8 ? 'n' : 'q');

  if (n >= 5 || ratios.any((r) => r > 2.0)) {
    return _complexLayout(ratios, maxW, sp, rc, minCW);
  }

  const maxH = maxW;
  final cr = ratios.map((v) => v.clamp(0.6667, 2.75)).toList();

  if (n == 1) {
    final h = (maxW / cr[0]).clamp(100.0, maxH);
    return [_LayoutRect(0, Rect.fromLTWH(0, 0, maxW, h), BorderRadius.circular(rc))];
  }

  if (n == 2) {
    final p = classify(cr[0]) + classify(cr[1]);
    final avg = (cr[0] + cr[1]) / 2;

    if (p == 'ww' && avg > 1.4 && (cr[1] - cr[0]).abs() < 0.2) {
      final h = math.min(maxW / cr[0], math.min(maxW / cr[1], (maxH - sp) / 2)).roundToDouble();
      return [
        _LayoutRect(0, Rect.fromLTWH(0, 0, maxW, h), c(true, true, false, false)),
        _LayoutRect(1, Rect.fromLTWH(0, h + sp, maxW, h), c(false, false, true, true)),
      ];
    }

    if (p == 'ww' || p == 'qq') {
      final cellW = (maxW - sp) / 2;
      final h = (cellW / math.min(cr[0], cr[1])).clamp(100.0, maxH);
      return [
        _LayoutRect(0, Rect.fromLTWH(0, 0, cellW, h), c(true, false, true, false)),
        _LayoutRect(1, Rect.fromLTWH(cellW + sp, 0, cellW, h), c(false, true, false, true)),
      ];
    }

    final avail = maxW - sp;
    final natural = avail * cr[1] / (cr[0] + cr[1]);
    final secondW = math.min(math.max(0.4 * avail, natural), avail - 1.5 * minCW);
    final firstW = avail - secondW;
    final h = (avail / (cr[0] + cr[1])).clamp(100.0, maxH);
    return [
      _LayoutRect(0, Rect.fromLTWH(0, 0, firstW, h), c(true, false, true, false)),
      _LayoutRect(1, Rect.fromLTWH(firstW + sp, 0, secondW, h), c(false, true, false, true)),
    ];
  }

  if (n == 3) {
    if (classify(cr[0]) == 'n') {
      final leftW = (maxH * cr[0]).clamp(minCW, math.min<double>((maxW - sp) * 0.5, maxW - sp - minCW));
      final rightW = maxW - sp - leftW;
      final invS = 1 / cr[1] + 1 / cr[2];
      final rightAvail = maxH - sp;
      final h1 = rightAvail * (1 / cr[1]) / invS;
      final h2 = rightAvail - h1;
      return [
        _LayoutRect(0, Rect.fromLTWH(0, 0, leftW, maxH.toDouble()), c(true, false, true, false)),
        _LayoutRect(1, Rect.fromLTWH(leftW + sp, 0, rightW, h1), c(false, true, false, false)),
        _LayoutRect(2, Rect.fromLTWH(leftW + sp, h1 + sp, rightW, h2), c(false, false, false, true)),
      ];
    }

    final topH = math.min<double>(maxW / cr[0], (maxH - sp) * 0.66);
    final botH = maxH - sp - topH;
    final bw0 = (botH * cr[1]).clamp(minCW, maxW - sp - minCW);
    final bw1 = maxW - sp - bw0;
    return [
      _LayoutRect(0, Rect.fromLTWH(0, 0, maxW, topH), c(true, true, false, false)),
      _LayoutRect(1, Rect.fromLTWH(0, topH + sp, bw0, botH), c(false, false, true, false)),
      _LayoutRect(2, Rect.fromLTWH(bw0 + sp, topH + sp, bw1, botH), c(false, false, false, true)),
    ];
  }

  if (n == 4) {
    if (classify(cr[0]) == 'w') {
      final topH = math.min<double>(maxW / cr[0], (maxH - sp) * 0.66);
      final botH = maxH - sp - topH;
      final avail3 = maxW - 2 * sp;
      final bw0 = math.max(minCW, math.min(0.4 * avail3, botH * cr[1]));
      final bw2 = math.max(minCW, math.max(0.33 * avail3, botH * cr[3]));
      var bw1 = avail3 - bw0 - bw2;
      if (bw1 < minCW) bw1 = minCW;
      return [
        _LayoutRect(0, Rect.fromLTWH(0, 0, maxW, topH), c(true, true, false, false)),
        _LayoutRect(1, Rect.fromLTWH(0, topH + sp, bw0, botH), c(false, false, true, false)),
        _LayoutRect(2, Rect.fromLTWH(bw0 + sp, topH + sp, bw1, botH), c(false, false, false, false)),
        _LayoutRect(3, Rect.fromLTWH(bw0 + sp + bw1 + sp, topH + sp, bw2, botH), c(false, false, false, true)),
      ];
    }

    final leftW = (maxH * cr[0]).clamp(minCW, math.min<double>((maxW - sp) * 0.5, maxW - sp - minCW));
    final rightW = maxW - sp - leftW;
    final invS = 1 / cr[1] + 1 / cr[2] + 1 / cr[3];
    final rightAvail = maxH - 2 * sp;
    final h1 = rightAvail * (1 / cr[1]) / invS;
    final h2 = rightAvail * (1 / cr[2]) / invS;
    final h3 = rightAvail - h1 - h2;
    return [
      _LayoutRect(0, Rect.fromLTWH(0, 0, leftW, maxH.toDouble()), c(true, false, true, false)),
      _LayoutRect(1, Rect.fromLTWH(leftW + sp, 0, rightW, h1), c(false, true, false, false)),
      _LayoutRect(2, Rect.fromLTWH(leftW + sp, h1 + sp, rightW, h2), c(false, false, false, false)),
      _LayoutRect(3, Rect.fromLTWH(leftW + sp, h1 + sp + h2 + sp, rightW, h3), c(false, false, false, true)),
    ];
  }

  return [];
}

List<_LayoutRect> _complexLayout(
  List<double> ratios,
  double maxW,
  double sp,
  double rc,
  double minCW,
) {
  final n = ratios.length;
  final maxH = maxW * 4 / 3;
  final avg = ratios.fold(0.0, (double s, double r) => s + r) / n;
  final cr = avg > 1.1
      ? ratios.map((r) => r.clamp(1.0, 2.75)).toList()
      : ratios.map((r) => r.clamp(0.6667, 1.0)).toList();

  final allowFourOnLine2 = avg < 0.85;
  double bestScore = double.infinity;
  List<int>? bestSplit;

  for (int k = 2; k <= math.min(4, n); k++) {
    _tryLineSplits(n, k, 0, [], 3, allowFourOnLine2, (split) {
      double totalH = (split.length - 1) * sp;
      bool anyShort = false;
      int start = 0;
      for (final count in split) {
        final sum = cr.sublist(start, start + count).fold(0.0, (double s, double r) => s + r);
        final h = (maxW - (count - 1) * sp) / sum;
        totalH += h;
        if (h < minCW) anyShort = true;
        start += count;
      }

      bool descending = false;
      for (int i = 1; i < split.length; i++) {
        if (split[i - 1] > split[i]) { descending = true; break; }
      }

      var score = (totalH - maxH).abs();
      if (anyShort) score *= 1.5;
      if (descending) score *= 1.5;

      if (score < bestScore) {
        bestScore = score;
        bestSplit = List<int>.from(split);
      }
    });
  }

  bestSplit ??= [n];

  final rects = <_LayoutRect>[];
  double y = 0;
  int idx = 0;
  final numRows = bestSplit!.length;
  for (int ri = 0; ri < numRows; ri++) {
    final count = bestSplit![ri];
    final lineRatios = cr.sublist(idx, idx + count);
    final sum = lineRatios.fold(0.0, (double s, double r) => s + r);
    final lineH = (maxW - (count - 1) * sp) / sum;

    double x = 0;
    for (int ci = 0; ci < count; ci++) {
      double cellW;
      if (ci == count - 1) {
        cellW = maxW - x;
      } else {
        final ideal = lineH * lineRatios[ci];
        final maxCellW = maxW - x - (count - 1 - ci) * (minCW + sp);
        cellW = ideal.clamp(minCW, math.max(minCW, maxCellW));
      }
      rects.add(_LayoutRect(
        idx + ci,
        Rect.fromLTWH(x, y, cellW, lineH),
        BorderRadius.only(
          topLeft: ri == 0 && ci == 0 ? Radius.circular(rc) : Radius.zero,
          topRight: ri == 0 && ci == count - 1 ? Radius.circular(rc) : Radius.zero,
          bottomLeft: ri == numRows - 1 && ci == 0 ? Radius.circular(rc) : Radius.zero,
          bottomRight: ri == numRows - 1 && ci == count - 1 ? Radius.circular(rc) : Radius.zero,
        ),
      ));
      x += cellW + sp;
    }
    y += lineH + sp;
    idx += count;
  }
  return rects;
}

void _tryLineSplits(
  int remaining,
  int linesLeft,
  int lineIdx,
  List<int> current,
  int maxPerLine,
  bool allowFourOnLine2,
  void Function(List<int>) callback,
) {
  if (linesLeft == 0) {
    if (remaining == 0) callback(current);
    return;
  }
  final maxItems = (lineIdx == 1 && allowFourOnLine2) ? 4 : maxPerLine;
  for (int c = 1; c <= math.min(maxItems, remaining - (linesLeft - 1)); c++) {
    current.add(c);
    _tryLineSplits(remaining - c, linesLeft - 1, lineIdx + 1, current, maxPerLine, allowFourOnLine2, callback);
    current.removeLast();
  }
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
      case _FileType.music:
        return const Color(0xFFEF5350);
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
      case _FileType.music:
        return Icons.play_arrow;
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
                          file.type == _FileType.music
                              ? file.formattedSongName
                              : file.displayName,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0x80000000),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'HD',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFFFFFFFF),
          height: 1.2,
        ),
      ),
    );
  }
}

class _SpoilerOverlay extends StatefulWidget {
  const _SpoilerOverlay({super.key});

  @override
  State<_SpoilerOverlay> createState() => _SpoilerOverlayState();
}

class _SpoilerOverlayState extends State<_SpoilerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late int _seed;

  @override
  void initState() {
    super.initState();
    _seed = identityHashCode(this);
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
          painter: _SpoilerParticlePainter(_ctrl.value, seed: _seed),
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
  final int seed;
  _SpoilerParticlePainter(this.phase, {this.seed = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x40FFFFFF);
    final rng = math.Random(seed);
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


class _SendFilesDragOverlay extends StatelessWidget {
  final _DragZoneMode mode;
  final int hoveredZone;

  const _SendFilesDragOverlay({
    required this.mode,
    required this.hoveredZone,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final boxBg = p.boxBg;
    final shadowColor = p.windowShadowFg;
    final restColor = p.windowSubTextFg;
    final activeColor = p.windowActiveTextFg;

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        color: const Color(0x80000000),
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: mode == _DragZoneMode.both
            ? Column(
                children: [
                  Expanded(
                    child: _SendFilesDragCard(
                      title: 'Drop files here',
                      subtitle: 'to send them without compression',
                      isHovered: hoveredZone == 1,
                      boxBg: boxBg,
                      shadowColor: shadowColor,
                      restColor: restColor,
                      activeColor: activeColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _SendFilesDragCard(
                      title: 'Drop photos here',
                      subtitle: 'to send them in a quick way',
                      isHovered: hoveredZone == 2,
                      boxBg: boxBg,
                      shadowColor: shadowColor,
                      restColor: restColor,
                      activeColor: activeColor,
                    ),
                  ),
                ],
              )
            : _SendFilesDragCard(
                title: 'Drop files here',
                subtitle: 'to send them as documents',
                isHovered: hoveredZone == 1,
                boxBg: boxBg,
                shadowColor: shadowColor,
                restColor: restColor,
                activeColor: activeColor,
              ),
      ),
    );
  }
}

class _SendFilesDragCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isHovered;
  final Color boxBg;
  final Color shadowColor;
  final Color restColor;
  final Color activeColor;

  const _SendFilesDragCard({
    required this.title,
    required this.subtitle,
    required this.isHovered,
    required this.boxBg,
    required this.shadowColor,
    required this.restColor,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isHovered ? activeColor : restColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionFormattingToolbar extends StatelessWidget {
  final RichTextEditingController controller;
  final Color accentColor;
  final Color subColor;

  const _CaptionFormattingToolbar({
    required this.controller,
    required this.accentColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasSel = controller.selection.isValid && !controller.selection.isCollapsed;
        if (!hasSel) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _fmtBtn(Icons.format_bold, FormatType.bold),
              _fmtBtn(Icons.format_italic, FormatType.italic),
              _fmtBtn(Icons.format_underlined, FormatType.underline),
              _fmtBtn(Icons.format_strikethrough, FormatType.strike),
              _fmtBtn(Icons.code, FormatType.code),
              _fmtBtn(Icons.blur_on, FormatType.spoiler),
              const SizedBox(width: 4),
              _iconBtn(Icons.format_clear, () => controller.clearFormatting()),
            ],
          ),
        );
      },
    );
  }

  Widget _fmtBtn(IconData icon, FormatType type) {
    final active = controller.hasFormat(type);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SizedBox(
        width: 28, height: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: Icon(icon, color: active ? accentColor : subColor),
          onPressed: () => controller.toggleFormat(type),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SizedBox(
        width: 28, height: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: Icon(icon, color: subColor),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _MentionAutocompletePanel extends StatelessWidget {
  final List<MemberInfo> members;
  final bool isDark;
  final void Function(MemberInfo) onSelect;

  const _MentionAutocompletePanel({
    required this.members,
    required this.isDark,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      color: bg,
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: members.length,
        itemBuilder: (ctx, i) {
          final m = members[i];
          return InkWell(
            onTap: () => onSelect(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: isDark ? const Color(0xFF3E546A) : const Color(0xFFDDE4EB),
                    child: Text(
                      m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?',
                      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(m.displayName, style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                        if (m.username.isNotEmpty)
                          Text('@${m.username}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HashtagAutocompletePanel extends StatelessWidget {
  final List<String> hashtags;
  final bool isDark;
  final void Function(String) onSelect;

  const _HashtagAutocompletePanel({
    required this.hashtags,
    required this.isDark,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? Colors.white : Colors.black87;
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      color: bg,
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: hashtags.length,
        itemBuilder: (ctx, i) {
          final tag = hashtags[i];
          return InkWell(
            onTap: () => onSelect(tag),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '#$tag',
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          );
        },
      ),
    );
  }
}
