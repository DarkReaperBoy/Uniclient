import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import 'telegram_toast.dart';

const double _canvasWidth = 540;
const double _canvasHeight = 960;
const double _canvasRadius = 8;
const double _barHeight = 48;
const double _barMaxWidth = 422;
const double _barRadius = 24;
const double _barAnimDuration = 200; // ms
const double _contentMarginH = 20;
const double _contentMarginBottom = 146;
const double _minCanvasZoom = 1.0;
const double _maxCanvasZoom = 8.0;
const double _canvasZoomStep = 1.15;
const double _minBrushSize = 0.1;
const double _maxBrushSize = 1.0;
const double _brushSizeSliderHeight = 280;
const double _stickerMinScale = 0.1;
const double _stickerMaxScale = 10.0;

const List<Color> _paletteColors = [
  Color(0xFF000000),
  Color(0xFFFFFFFF),
  Color(0xFFEA2739),
  Color(0xFFFC964D),
  Color(0xFFFCDE65),
  Color(0xFF80C864),
  Color(0xFF49C5ED),
  Color(0xFF3051E3),
  Color(0xFFDB3AD2),
  Color(0xFFFF72A9),
];

const List<List<Color>> _gradientBackgrounds = [
  [Color(0xFF4158D0), Color(0xFFC850C0)],
  [Color(0xFF0093E9), Color(0xFF80D0C7)],
  [Color(0xFF8EC5FC), Color(0xFFE0C3FC)],
  [Color(0xFFFDCB82), Color(0xFFD1FDFF)],
];

enum _EditorMode { transform, paint, post }

enum _BrushTool { pen, arrow, marker, blur, eraser }

enum _TextAlign { left, center, right }

enum _TextBgStyle { none, filled, outlined, shadowed }

enum StoryPrivacyOption { everyone, contacts, closeFriends, selectedContacts }

class _SceneItem {
  Offset position;
  double scale;
  double rotation;
  bool isText;
  String text;
  Color color;
  double fontSize;
  _TextAlign textAlign;
  _TextBgStyle textBgStyle;
  String fontFamily;
  Uint8List? stickerImageBytes;
  int stickerWidth;
  int stickerHeight;

  _SceneItem({
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.isText = false,
    this.text = '',
    this.color = Colors.white,
    this.fontSize = 32,
    this.textAlign = _TextAlign.center,
    this.textBgStyle = _TextBgStyle.none,
    this.fontFamily = 'sans-serif',
    this.stickerImageBytes,
    this.stickerWidth = 0,
    this.stickerHeight = 0,
  });

  bool get isSticker => stickerImageBytes != null && stickerImageBytes!.isNotEmpty;
}

class _PaintStroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final _BrushTool tool;

  _PaintStroke({
    required this.points,
    required this.color,
    required this.width,
    required this.tool,
  });
}

sealed class _UndoAction {}

class _StrokeAction extends _UndoAction {
  final _PaintStroke stroke;
  _StrokeAction(this.stroke);
}

class _AddItemAction extends _UndoAction {
  final _SceneItem item;
  _AddItemAction(this.item);
}

class _RemoveItemAction extends _UndoAction {
  final _SceneItem item;
  final int index;
  _RemoveItemAction(this.item, this.index);
}

class _MoveItemAction extends _UndoAction {
  final _SceneItem item;
  Offset savedPosition;
  double savedScale;
  double savedRotation;
  _MoveItemAction(this.item, this.savedPosition, this.savedScale, this.savedRotation);
}

Future<void> showStoryEditor(BuildContext context) async {
  await Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (ctx, anim, secondAnim) => const _StoryEditorLayer(),
      transitionsBuilder: (ctx, anim, secondAnim, child) {
        return FadeTransition(opacity: anim, child: child);
      },
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    ),
  );
}

class _StoryEditorLayer extends StatefulWidget {
  const _StoryEditorLayer();

  @override
  State<_StoryEditorLayer> createState() => _StoryEditorLayerState();
}

class _StoryEditorLayerState extends State<_StoryEditorLayer>
    with TickerProviderStateMixin {
  _EditorMode _mode = _EditorMode.transform;
  File? _imageFile;
  ui.Image? _loadedImage;
  int _gradientIndex = 0;
  bool _hasMedia = false;

  // Canvas state
  double _zoom = 1.0;
  Offset _pan = Offset.zero;

  // Paint state
  _BrushTool _currentBrush = _BrushTool.pen;
  double _brushSizeRatio = 0.3;
  Color _brushColor = const Color(0xFFEA2739);
  final List<_PaintStroke> _strokes = [];
  final List<_UndoAction> _undoStack = [];
  final List<_UndoAction> _redoStack = [];
  List<Offset>? _currentStrokePoints;
  bool _showColorPalette = false;
  bool _brushSliderExpanded = false;

  // Text state
  bool _textMode = false;
  final List<_SceneItem> _sceneItems = [];
  _SceneItem? _selectedItem;
  _SceneItem? _editingTextItem;
  final TextEditingController _textEditController = TextEditingController();
  int _selectedFontIndex = 0;
  _TextBgStyle _currentTextBgStyle = _TextBgStyle.none;
  _TextAlign _currentTextAlign = _TextAlign.center;

  // Font size for text tool (§32.15.5: range 14-72pt)
  double _fontSize = _canvasWidth / 15.0;
  bool _fontSizeSliderExpanded = false;

  // Video state (§32.15.3)
  File? _videoFile;
  double _trimStart = 0.0;
  double _trimEnd = 1.0;
  Duration _videoDuration = Duration.zero;
  ui.Image? _videoCoverFrame;

  // Post stage state
  final TextEditingController _captionController = TextEditingController();
  StoryPrivacyOption _privacy = StoryPrivacyOption.everyone;
  int _durationHours = 24;
  bool _saveToProfile = true;
  bool _allowSharing = true;
  bool _posting = false;
  double _uploadProgress = 0;
  bool _posted = false;
  List<String> _selectedContactIds = [];
  List<String> _excludedContactIds = [];

  // Video thumbnails for trim slider
  List<ui.Image?> _videoThumbnails = [];

  // Gesture state for item manipulation
  Offset? _dragStart;
  double? _initialScale;
  double? _initialRotation;

  late AnimationController _barAnimController;
  late Animation<double> _barAnim;
  final FocusNode _keyboardFocusNode = FocusNode();
  final ValueNotifier<List<_PaintStroke>> _strokesNotifier = ValueNotifier([]);

  static const _fonts = [
    'sans-serif',
    'monospace',
    'serif',
    'cursive',
    'Georgia',
    'system-ui',
    'fantasy',
  ];
  static const _fontLabels = [
    'Regular', 'Typewriter', 'Serif', 'Handwriting',
    'Classic', 'Modern', 'Decorative',
  ];

  @override
  void initState() {
    super.initState();
    _barAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _barAnim = CurvedAnimation(
      parent: _barAnimController,
      curve: Curves.easeOutCubic,
    );
    _barAnimController.value = 1.0;
    _pickImage();
  }

  @override
  void dispose() {
    _barAnimController.dispose();
    _textEditController.dispose();
    _captionController.dispose();
    _keyboardFocusNode.dispose();
    _strokesNotifier.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp',
        'mp4', 'mov', 'avi', 'mkv', 'webm',
      ],
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
      final file = File(result.files.first.path!);
      final ext = file.path.split('.').last.toLowerCase();
      final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
      if (isVideo) {
        setState(() {
          _videoFile = file;
          _imageFile = null;
          _hasMedia = true;
          _trimStart = 0.0;
          _trimEnd = 1.0;
          _videoThumbnails = [];
        });
        _readVideoDuration(file);
      } else {
        setState(() {
          _imageFile = file;
          _videoFile = null;
          _hasMedia = true;
        });
        _loadImage(file);
      }
    } else {
      setState(() {
        _hasMedia = false;
        _gradientIndex = 0;
      });
    }
  }

  Future<void> _loadImage(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() => _loadedImage = frame.image);
    }
  }

  Future<void> _readVideoDuration(File file) async {
    final player = Player();
    try {
      final completer = Completer<Duration>();
      StreamSubscription<Duration>? sub;
      sub = player.stream.duration.listen((dur) {
        if (dur > Duration.zero && !completer.isCompleted) {
          completer.complete(dur);
          sub?.cancel();
        }
      });
      await player.open(Media(file.path), play: false);
      final duration = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          final fileSize = file.lengthSync();
          return Duration(seconds: (fileSize / (500 * 1024)).clamp(1, 300).toInt());
        },
      );
      if (mounted) {
        setState(() => _videoDuration = duration);
      }
      await Future.delayed(const Duration(milliseconds: 300));
      final coverBytes = await player.screenshot();
      if (coverBytes != null && coverBytes.isNotEmpty && mounted) {
        try {
          final codec = await ui.instantiateImageCodec(coverBytes);
          final frame = await codec.getNextFrame();
          if (mounted) setState(() => _videoCoverFrame = frame.image);
        } catch (_) {}
      }
      _extractVideoThumbnails(file, duration);
    } finally {
      await player.dispose();
    }
  }

  Future<void> _extractVideoThumbnails(File file, Duration totalDuration) async {
    if (totalDuration.inMilliseconds <= 0) return;
    const frameCount = 12;
    final thumbs = <ui.Image?>[];
    final player = Player();
    try {
      await player.open(Media(file.path), play: false);
      await Future.delayed(const Duration(milliseconds: 300));
      for (var i = 0; i < frameCount; i++) {
        final seekMs = (totalDuration.inMilliseconds * i / frameCount).round();
        await player.seek(Duration(milliseconds: seekMs));
        await Future.delayed(const Duration(milliseconds: 150));
        final screenshot = await player.screenshot();
        if (screenshot != null && screenshot.isNotEmpty) {
          try {
            final codec = await ui.instantiateImageCodec(
              screenshot,
              targetWidth: 48,
              targetHeight: 48,
            );
            final frame = await codec.getNextFrame();
            thumbs.add(frame.image);
          } catch (_) {
            thumbs.add(null);
          }
        } else {
          thumbs.add(null);
        }
      }
    } catch (_) {
      // Fall back to empty thumbnails
    } finally {
      await player.dispose();
    }
    if (mounted && thumbs.isNotEmpty) {
      setState(() => _videoThumbnails = thumbs);
    }
  }

  void _switchMode(_EditorMode newMode) {
    _barAnimController.reverse().then((_) {
      setState(() => _mode = newMode);
      _barAnimController.forward();
    });
  }

  void _handleDone() {
    if (_mode == _EditorMode.paint) {
      _switchMode(_EditorMode.transform);
    } else if (_mode == _EditorMode.transform) {
      _switchMode(_EditorMode.post);
    }
  }

  void _handleCancel() {
    if (_mode == _EditorMode.paint) {
      _switchMode(_EditorMode.transform);
    } else if (_mode == _EditorMode.post) {
      _switchMode(_EditorMode.transform);
    } else {
      _confirmDiscard();
    }
  }

  void _confirmDiscard() {
    if (_strokes.isEmpty && _sceneItems.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard story?'),
        content: const Text('Your edits will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop();
            },
            child: Text('Discard', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }

  Future<void> _postStory() async {
    if (_posting) return;
    setState(() {
      _posting = true;
      _uploadProgress = 0;
    });

    Timer? progressTimer;

    try {
      final appState = context.read<AppState>();
      final accountId = appState.activeAccountId;
      if (accountId == null) throw Exception('No active account');
      final engine = context.read<EngineService>();

      setState(() => _uploadProgress = 0.15);

      progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() {
          if (_uploadProgress < 0.85) {
            _uploadProgress += 0.02;
          }
        });
      });

      if (_videoFile != null) {
        Uint8List? overlayBytes;
        if (_strokes.isNotEmpty || _sceneItems.isNotEmpty) {
          overlayBytes = await _renderCanvasToBytes();
        }
        await engine.sendStoryWithVideoFile(
          accountId,
          _captionController.text,
          _videoFile!.path,
          privacy: _privacy.name,
          durationHours: _durationHours,
          saveToProfile: _saveToProfile,
          allowSharing: _allowSharing,
          selectedContactIds: _selectedContactIds,
          excludedContactIds: _excludedContactIds,
          overlayData: overlayBytes,
          trimStart: _trimStart,
          trimEnd: _trimEnd,
        );
      } else {
        final mediaBytes = await _renderCanvasToBytes();
        await engine.sendStoryWithPhoto(
          accountId,
          _captionController.text,
          mediaBytes,
          privacy: _privacy.name,
          durationHours: _durationHours,
          saveToProfile: _saveToProfile,
          allowSharing: _allowSharing,
          selectedContactIds: _selectedContactIds,
          excludedContactIds: _excludedContactIds,
        );
      }

      progressTimer.cancel();
      setState(() {
        _uploadProgress = 1.0;
        _posted = true;
      });

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      progressTimer?.cancel();
      setState(() => _posting = false);
      if (mounted) {
        showTelegramToast(context, 'Failed to post story: $e');
      }
    }
  }

  Future<Uint8List> _renderCanvasToBytes() async {
    final w = _canvasWidth.toInt();
    final h = _canvasHeight.toInt();
    final canvasBounds = Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight);

    ui.Image bgImage;
    {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, canvasBounds);
      if (_hasMedia && _loadedImage != null) {
        final src = Rect.fromLTWH(0, 0, _loadedImage!.width.toDouble(), _loadedImage!.height.toDouble());
        c.drawImageRect(_loadedImage!, src, canvasBounds, Paint());
      } else if (_hasMedia && _videoCoverFrame != null) {
        final src = Rect.fromLTWH(0, 0, _videoCoverFrame!.width.toDouble(), _videoCoverFrame!.height.toDouble());
        c.drawImageRect(_videoCoverFrame!, src, canvasBounds, Paint());
      } else {
        final colors = _gradientBackgrounds[_gradientIndex % _gradientBackgrounds.length];
        final gradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors);
        c.drawRect(canvasBounds, Paint()..shader = gradient.createShader(canvasBounds));
      }
      bgImage = await rec.endRecording().toImage(w, h);
    }

    final blurStrokes = _strokes.where((s) => s.tool == _BrushTool.blur).toList();
    if (blurStrokes.isNotEmpty) {
      final blurRec = ui.PictureRecorder();
      final bc = Canvas(blurRec, canvasBounds);
      bc.drawImage(bgImage, Offset.zero, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10));
      final blurredImage = await blurRec.endRecording().toImage(w, h);

      final mergeRec = ui.PictureRecorder();
      final mc = Canvas(mergeRec, canvasBounds);
      mc.drawImage(bgImage, Offset.zero, Paint());
      for (final stroke in blurStrokes) {
        final blurPath = Path();
        final r = stroke.width / 2;
        for (final pt in stroke.points) {
          blurPath.addOval(Rect.fromCircle(center: pt, radius: r));
        }
        mc.save();
        mc.clipPath(blurPath);
        mc.drawImage(blurredImage, Offset.zero, Paint());
        mc.restore();
      }
      bgImage = await mergeRec.endRecording().toImage(w, h);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, canvasBounds);
    canvas.drawImage(bgImage, Offset.zero, Paint());

    canvas.saveLayer(canvasBounds, Paint());
    for (final stroke in _strokes) {
      _StrokePainter.paintStroke(canvas, stroke.points, stroke.color, stroke.width, stroke.tool, 1.0);
    }
    canvas.restore();

    for (final item in _sceneItems) {
      canvas.save();
      canvas.translate(
        item.position.dx * _canvasWidth,
        item.position.dy * _canvasHeight,
      );
      canvas.scale(item.scale);
      canvas.rotate(item.rotation);
      if (item.isSticker) {
        try {
          final codec = await ui.instantiateImageCodec(item.stickerImageBytes!);
          final frame = await codec.getNextFrame();
          final stickerImg = frame.image;
          final sw = item.stickerWidth > 0 ? item.stickerWidth.toDouble() : stickerImg.width.toDouble();
          final sh = item.stickerHeight > 0 ? item.stickerHeight.toDouble() : stickerImg.height.toDouble();
          final displaySize = 120.0;
          final sScale = displaySize / math.max(sw, sh);
          final dw = sw * sScale;
          final dh = sh * sScale;
          canvas.drawImageRect(
            stickerImg,
            Rect.fromLTWH(0, 0, stickerImg.width.toDouble(), stickerImg.height.toDouble()),
            Rect.fromLTWH(-dw / 2, -dh / 2, dw, dh),
            Paint(),
          );
        } catch (_) {}
      } else if (item.isText && item.text.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: item.text,
            style: TextStyle(
              color: item.textBgStyle == _TextBgStyle.filled ? Colors.white : item.color,
              fontSize: item.fontSize,
              fontFamily: item.fontFamily,
              fontWeight: FontWeight.bold,
              shadows: item.textBgStyle == _TextBgStyle.shadowed
                  ? [const Shadow(color: Color(0x73000000), blurRadius: 6, offset: Offset(0, 2))]
                  : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: _canvasWidth * 0.8);
        final textOffset = Offset(-tp.width / 2, -tp.height / 2);
        if (item.textBgStyle == _TextBgStyle.filled) {
          final bgRect = Rect.fromLTWH(
            textOffset.dx - 8, textOffset.dy - 4,
            tp.width + 16, tp.height + 8,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
            Paint()..color = item.color.withValues(alpha: 0.4),
          );
        } else if (item.textBgStyle == _TextBgStyle.outlined) {
          final bgRect = Rect.fromLTWH(
            textOffset.dx - 8, textOffset.dy - 4,
            tp.width + 16, tp.height + 8,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
            Paint()
              ..color = item.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
        tp.paint(canvas, textOffset);
      } else if (!item.isText && item.text.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: item.text,
            style: TextStyle(fontSize: item.fontSize),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      }
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(w, h);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final action = _undoStack.removeLast();
    setState(() {
      switch (action) {
        case _StrokeAction(:final stroke):
          _strokes.remove(stroke);
        case _AddItemAction(:final item):
          _sceneItems.remove(item);
        case _RemoveItemAction(:final item, :final index):
          _sceneItems.insert(index.clamp(0, _sceneItems.length), item);
        case _MoveItemAction action:
          final curPos = action.item.position;
          final curScale = action.item.scale;
          final curRot = action.item.rotation;
          action.item.position = action.savedPosition;
          action.item.scale = action.savedScale;
          action.item.rotation = action.savedRotation;
          action.savedPosition = curPos;
          action.savedScale = curScale;
          action.savedRotation = curRot;
      }
      _redoStack.add(action);
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final action = _redoStack.removeLast();
    setState(() {
      switch (action) {
        case _StrokeAction(:final stroke):
          _strokes.add(stroke);
        case _AddItemAction(:final item):
          _sceneItems.add(item);
        case _RemoveItemAction(:final item):
          _sceneItems.remove(item);
        case _MoveItemAction action:
          final curPos = action.item.position;
          final curScale = action.item.scale;
          final curRot = action.item.rotation;
          action.item.position = action.savedPosition;
          action.item.scale = action.savedScale;
          action.item.rotation = action.savedRotation;
          action.savedPosition = curPos;
          action.savedScale = curScale;
          action.savedRotation = curRot;
      }
      _undoStack.add(action);
    });
  }

  double get _effectiveBrushWidth {
    double base = 1 + 24 * _brushSizeRatio;
    if (_currentBrush == _BrushTool.marker) base *= 2.5;
    if (_currentBrush == _BrushTool.blur) base *= 3.0;
    return base;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _keyboardFocusNode..requestFocus(),
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(),
            _buildCanvas(),
            if (_mode == _EditorMode.paint) _buildBrushSizeSlider(),
            _buildChrome(),
            if (_editingTextItem != null) _buildTextEditOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(color: const Color(0xC0101010));
  }

  Widget _buildCanvas() {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth - 2 * _contentMarginH;
          final maxH = constraints.maxHeight - _contentMarginBottom - 20;
          final scale = math.min(maxW / _canvasWidth, maxH / _canvasHeight);
          final w = _canvasWidth * scale;
          final h = _canvasHeight * scale;

          return GestureDetector(
            onScaleStart: _mode == _EditorMode.paint ? null : _onItemScaleStart,
            onScaleUpdate: _mode == _EditorMode.paint ? null : _onItemScaleUpdate,
            onScaleEnd: _mode == _EditorMode.paint ? null : _onItemScaleEnd,
            onTapUp: _onCanvasTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_canvasRadius),
              child: SizedBox(
                width: w,
                height: h,
                child: Transform.scale(
                  scale: _zoom,
                  child: Transform.translate(
                    offset: _pan,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCanvasContent(scale),
                        ..._buildBlurLayers(scale),
                        if (_mode == _EditorMode.paint) _buildPaintLayer(scale),
                        ..._buildSceneItems(scale),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCanvasContent(double scale) {
    if (_hasMedia && _loadedImage != null) {
      return Image.file(
        _imageFile!,
        fit: BoxFit.cover,
        width: _canvasWidth * scale,
        height: _canvasHeight * scale,
      );
    }
    if (_hasMedia && _videoFile != null) {
      if (_videoCoverFrame != null) {
        return RawImage(
          image: _videoCoverFrame,
          fit: BoxFit.cover,
          width: _canvasWidth * scale,
          height: _canvasHeight * scale,
        );
      }
      if (_videoThumbnails.isNotEmpty && _videoThumbnails.first != null) {
        return RawImage(
          image: _videoThumbnails.first,
          fit: BoxFit.cover,
          width: _canvasWidth * scale,
          height: _canvasHeight * scale,
        );
      }
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2),
        ),
      );
    }
    final colors = _gradientBackgrounds[_gradientIndex % _gradientBackgrounds.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
    );
  }

  List<Widget> _buildBlurLayers(double scale) {
    final blurStrokes = _strokes.where((s) => s.tool == _BrushTool.blur).toList();
    final layers = <Widget>[];
    for (final stroke in blurStrokes) {
      layers.add(ClipPath(
        clipper: _BlurStrokeClipper(stroke.points, stroke.width, scale),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: const SizedBox.expand(),
        ),
      ));
    }
    if (_mode == _EditorMode.paint &&
        _currentBrush == _BrushTool.blur &&
        _currentStrokePoints != null &&
        _currentStrokePoints!.length > 1) {
      layers.add(ClipPath(
        clipper: _BlurStrokeClipper(_currentStrokePoints!, _effectiveBrushWidth, scale),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: const SizedBox.expand(),
        ),
      ));
    }
    return layers;
  }

  Widget _buildPaintLayer(double scale) {
    final nonBlurStrokes = _strokes.where((s) => s.tool != _BrushTool.blur).toList();
    final showCurrentNonBlur = _currentBrush != _BrushTool.blur ? _currentStrokePoints : null;
    return Listener(
      onPointerDown: (e) => _startStroke(e.localPosition, scale),
      onPointerMove: (e) => _continueStroke(e.localPosition, scale),
      onPointerUp: (_) => _endStroke(),
      behavior: HitTestBehavior.translucent,
      child: ValueListenableBuilder<List<_PaintStroke>>(
        valueListenable: _strokesNotifier,
        builder: (_, __, ___) => CustomPaint(
          painter: _StrokePainter(
            strokes: nonBlurStrokes,
            currentPoints: showCurrentNonBlur,
            currentColor: _brushColor,
            currentWidth: _effectiveBrushWidth,
            currentTool: _currentBrush,
            scale: scale,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  void _startStroke(Offset pos, double scale) {
    setState(() {
      _currentStrokePoints = [pos / scale];
    });
  }

  void _continueStroke(Offset pos, double scale) {
    if (_currentStrokePoints != null) {
      _currentStrokePoints!.add(pos / scale);
      _strokesNotifier.value = List.from(_strokesNotifier.value);
    }
  }

  void _endStroke() {
    if (_currentStrokePoints != null && _currentStrokePoints!.length > 1) {
      final stroke = _PaintStroke(
        points: List.from(_currentStrokePoints!),
        color: _brushColor,
        width: _effectiveBrushWidth,
        tool: _currentBrush,
      );
      setState(() {
        _strokes.add(stroke);
        _undoStack.add(_StrokeAction(stroke));
        _redoStack.clear();
        _currentStrokePoints = null;
      });
    } else {
      setState(() => _currentStrokePoints = null);
    }
  }

  Offset? _itemDragStartPos;
  double? _itemDragStartScale;
  double? _itemDragStartRot;

  List<Widget> _buildSceneItems(double scale) {
    return _sceneItems.map((item) {
      return Positioned(
        left: item.position.dx * scale,
        top: item.position.dy * scale,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: GestureDetector(
            onTap: () {
              if (item.isText) {
                setState(() {
                  _editingTextItem = item;
                  _textEditController.text = item.text;
                });
              }
            },
            onPanStart: (d) {
              setState(() => _selectedItem = item);
              _itemDragStartPos = item.position;
              _itemDragStartScale = item.scale;
              _itemDragStartRot = item.rotation;
            },
            onPanUpdate: (d) {
              setState(() {
                item.position += d.delta / scale;
              });
            },
            onPanEnd: (_) {
              if (_selectedItem != null && _itemDragStartPos != null) {
                final moved = _selectedItem!.position != _itemDragStartPos! ||
                    _selectedItem!.scale != _itemDragStartScale! ||
                    _selectedItem!.rotation != _itemDragStartRot!;
                if (moved) {
                  _undoStack.add(_MoveItemAction(
                    _selectedItem!,
                    _itemDragStartPos!,
                    _itemDragStartScale!,
                    _itemDragStartRot!,
                  ));
                  _redoStack.clear();
                }
              }
              _itemDragStartPos = null;
            },
            child: Transform.rotate(
              angle: item.rotation,
              child: Transform.scale(
                scale: item.scale,
                child: _buildItemWidget(item),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildItemWidget(_SceneItem item) {
    if (item.isSticker) {
      return Container(
        decoration: _selectedItem == item
            ? BoxDecoration(border: Border.all(color: Colors.white54, width: 1))
            : null,
        child: Image.memory(
          item.stickerImageBytes!,
          width: 120,
          height: 120,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text(
            item.text.isNotEmpty ? item.text : '?',
            style: const TextStyle(fontSize: 64),
          ),
        ),
      );
    }
    if (!item.isText) return const SizedBox.shrink();
    final align = item.textAlign == _TextAlign.left
        ? TextAlign.left
        : item.textAlign == _TextAlign.right
            ? TextAlign.right
            : TextAlign.center;

    Widget textWidget = Text(
      item.text,
      textAlign: align,
      style: TextStyle(
        color: item.color,
        fontSize: item.fontSize,
        fontFamily: item.fontFamily,
        fontWeight: FontWeight.bold,
        shadows: item.textBgStyle == _TextBgStyle.shadowed
            ? [const Shadow(color: Color(0x73000000), blurRadius: 6, offset: Offset(0, 2))]
            : null,
      ),
    );

    if (item.textBgStyle == _TextBgStyle.filled) {
      textWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          item.text,
          textAlign: align,
          style: TextStyle(
            color: Colors.white,
            fontSize: item.fontSize,
            fontFamily: item.fontFamily,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (item.textBgStyle == _TextBgStyle.outlined) {
      textWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: item.color, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: textWidget,
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: _selectedItem == item
          ? BoxDecoration(border: Border.all(color: Colors.white54, width: 1))
          : null,
      child: textWidget,
    );
  }

  void _onCanvasTap(TapUpDetails details) {
    if (_textMode && _mode == _EditorMode.transform) {
      final renderBox = context.findRenderObject() as RenderBox;
      final size = renderBox.size;
      final maxW = size.width - 2 * _contentMarginH;
      final maxH = size.height - _contentMarginBottom - 20;
      final scale = math.min(maxW / _canvasWidth, maxH / _canvasHeight);

      final item = _SceneItem(
        position: details.localPosition / scale,
        isText: true,
        text: '',
        color: _brushColor,
        fontSize: _fontSize,
        textAlign: _currentTextAlign,
        textBgStyle: _currentTextBgStyle,
        fontFamily: _fonts[_selectedFontIndex],
      );
      setState(() {
        _sceneItems.add(item);
        _undoStack.add(_AddItemAction(item));
        _redoStack.clear();
        _editingTextItem = item;
        _textEditController.text = '';
      });
    } else if (_mode == _EditorMode.transform) {
      setState(() => _selectedItem = null);
    }
  }

  Offset? _scaleStartPos;

  void _onItemScaleStart(ScaleStartDetails details) {
    if (_selectedItem != null) {
      _initialScale = _selectedItem!.scale;
      _initialRotation = _selectedItem!.rotation;
      _scaleStartPos = _selectedItem!.position;
    }
  }

  void _onItemScaleUpdate(ScaleUpdateDetails details) {
    if (_selectedItem != null && _initialScale != null) {
      setState(() {
        _selectedItem!.scale = (_initialScale! * details.scale)
            .clamp(_stickerMinScale, _stickerMaxScale);
        _selectedItem!.rotation = _initialRotation! + details.rotation;
      });
    } else if (details.scale != 1.0) {
      setState(() {
        _zoom = (_zoom * details.scale).clamp(_minCanvasZoom, _maxCanvasZoom);
      });
    }
  }

  void _onItemScaleEnd(ScaleEndDetails details) {
    if (_selectedItem != null && _initialScale != null && _scaleStartPos != null) {
      final changed = _selectedItem!.scale != _initialScale! ||
          _selectedItem!.rotation != _initialRotation!;
      if (changed) {
        _undoStack.add(_MoveItemAction(
          _selectedItem!,
          _scaleStartPos!,
          _initialScale!,
          _initialRotation!,
        ));
        _redoStack.clear();
      }
    }
    _initialScale = null;
    _initialRotation = null;
    _scaleStartPos = null;
  }

  Widget _buildBrushSizeSlider() {
    final expandShift = _brushSliderExpanded ? 14.0 : 0.0;
    return Positioned(
      left: expandShift,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onVerticalDragStart: (_) => setState(() => _brushSliderExpanded = true),
          onVerticalDragUpdate: (d) {
            setState(() {
              _brushSizeRatio = (_brushSizeRatio - d.delta.dy / _brushSizeSliderHeight)
                  .clamp(_minBrushSize, _maxBrushSize);
            });
          },
          onVerticalDragEnd: (_) => setState(() => _brushSliderExpanded = false),
          onTapDown: (d) => setState(() => _brushSliderExpanded = true),
          onTapUp: (_) => setState(() => _brushSliderExpanded = false),
          child: SizedBox(
            width: _brushSliderExpanded ? 40 : 20,
            height: _brushSizeSliderHeight + 48,
            child: CustomPaint(
              painter: _BrushSizeSliderPainter(
                sizeRatio: _brushSizeRatio,
                expanded: _brushSliderExpanded,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChrome() {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: _buildTopBar(),
        ),
        const Spacer(),
        _buildBottomArea(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: _handleCancel,
          ),
          const Spacer(),
          if (_mode == _EditorMode.transform) ...[
            _buildTopBarButton(
              icon: Icons.text_fields,
              active: _textMode,
              onTap: () => setState(() => _textMode = !_textMode),
            ),
            const SizedBox(width: 8),
            _buildTopBarButton(
              icon: Icons.emoji_emotions,
              onTap: _showStickerPicker,
            ),
            const SizedBox(width: 8),
            _buildTopBarButton(
              icon: Icons.brush,
              onTap: () => _switchMode(_EditorMode.paint),
            ),
          ],
          if (_mode == _EditorMode.paint) ...[
            _buildTopBarButton(
              icon: Icons.undo,
              onTap: _undoStack.isNotEmpty ? _undo : null,
            ),
            const SizedBox(width: 8),
            _buildTopBarButton(
              icon: Icons.redo,
              onTap: _redoStack.isNotEmpty ? _redo : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBarButton({
    required IconData icon,
    VoidCallback? onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white24 : Colors.transparent,
        ),
        child: Icon(
          icon,
          color: onTap == null ? Colors.white38 : Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildBottomArea() {
    if (_mode == _EditorMode.post) {
      return _buildPostStage();
    }

    return FadeTransition(
      opacity: _barAnim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_videoFile != null && _mode == _EditorMode.transform)
            _VideoTrimSlider(
              trimStart: _trimStart,
              trimEnd: _trimEnd,
              thumbnails: _videoThumbnails,
              onChanged: (start, end) {
                setState(() {
                  _trimStart = start;
                  _trimEnd = end;
                });
              },
            ),
          if (_mode == _EditorMode.paint) _buildPaintToolBar(),
          const SizedBox(height: 6),
          _buildMainBar(),
        ],
      ),
    );
  }

  Widget _buildPaintToolBar() {
    return Container(
      constraints: const BoxConstraints(maxWidth: _barMaxWidth),
      height: _barHeight,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xCC1A1A1A),
        borderRadius: BorderRadius.circular(_barRadius),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          _buildColorButton(),
          const SizedBox(width: 12),
          ..._BrushTool.values.map((tool) => _buildBrushButton(tool)),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildColorButton() {
    return GestureDetector(
      onTap: () => setState(() => _showColorPalette = !_showColorPalette),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          color: _brushColor,
        ),
      ),
    );
  }

  Widget _buildBrushButton(_BrushTool tool) {
    final isActive = _currentBrush == tool;
    final icons = {
      _BrushTool.pen: Icons.edit,
      _BrushTool.arrow: Icons.arrow_forward,
      _BrushTool.marker: Icons.highlight,
      _BrushTool.blur: Icons.blur_on,
      _BrushTool.eraser: Icons.auto_fix_off,
    };
    return GestureDetector(
      onTap: () => setState(() => _currentBrush = tool),
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? Colors.white24 : Colors.transparent,
        ),
        child: Icon(icons[tool], color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildMainBar() {
    return Container(
      constraints: const BoxConstraints(maxWidth: _barMaxWidth),
      height: _barHeight,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xCC1A1A1A),
        borderRadius: BorderRadius.circular(_barRadius),
      ),
      child: Row(
        children: [
          _buildEdgeButton('Cancel', _handleCancel),
          const Spacer(),
          if (_showColorPalette && _mode == _EditorMode.paint)
            Expanded(child: _buildColorPaletteStrip())
          else if (!_hasMedia && _mode == _EditorMode.transform)
            _buildGradientPicker(),
          const Spacer(),
          _buildEdgeButton('Done', _handleDone, isAccent: true),
        ],
      ),
    );
  }

  Widget _buildEdgeButton(String label, VoidCallback onTap, {bool isAccent = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 0),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isAccent ? const Color(0xFF4DB8FF) : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildColorPaletteStrip() {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _paletteColors.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          if (i == _paletteColors.length) {
            return GestureDetector(
              onTap: _openCustomColorPicker,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54, width: 2),
                ),
                child: const Icon(Icons.add, size: 12, color: Colors.white54),
              ),
            );
          }
          final color = _paletteColors[i];
          final isSelected = _brushColor == color;
          return GestureDetector(
            onTap: () => setState(() => _brushColor = color),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: isSelected
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGradientPicker() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_gradientBackgrounds.length, (i) {
        final isActive = _gradientIndex == i;
        return GestureDetector(
          onTap: () => setState(() => _gradientIndex = i),
          child: Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: _gradientBackgrounds[i]),
              border: isActive
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
          ),
        );
      }),
    );
  }

  void _openCustomColorPicker() {
    showDialog(
      context: context,
      builder: (ctx) => _HSLColorPickerDialog(
        initialColor: _brushColor,
        onColorSelected: (c) => setState(() => _brushColor = c),
      ),
    );
  }

  // ── Post Stage ──

  Widget _buildPostStage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPrivacyAndDurationChips(),
          const SizedBox(height: 8),
          _buildToggles(),
          const SizedBox(height: 8),
          _buildCaptionBar(),
        ],
      ),
    );
  }

  Widget _buildPrivacyAndDurationChips() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildChip(_privacyLabel, onTap: _showPrivacyDialog),
        const SizedBox(width: 8),
        _buildChip('${_durationHours}h', onTap: _showDurationMenu),
      ],
    );
  }

  String get _privacyLabel {
    switch (_privacy) {
      case StoryPrivacyOption.everyone:
        return 'Everyone';
      case StoryPrivacyOption.contacts:
        return 'Contacts';
      case StoryPrivacyOption.closeFriends:
        return 'Close Friends';
      case StoryPrivacyOption.selectedContacts:
        return 'Selected Contacts';
    }
  }

  Widget _buildChip(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0x73000000),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildToggles() {
    return Column(
      children: [
        _buildToggleRow(
          icon: Icons.bookmark_outline,
          label: 'Keep on my page',
          subtitle: 'Story will stay on your profile after it expires',
          value: _saveToProfile,
          onChanged: (v) => setState(() => _saveToProfile = v),
        ),
        if (_privacy != StoryPrivacyOption.closeFriends)
          _buildToggleRow(
            icon: Icons.forward_outlined,
            label: 'Allow sharing',
            subtitle: 'Let viewers share your story as a link',
            value: _allowSharing,
            onChanged: (v) => setState(() => _allowSharing = v),
          ),
      ],
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          _StorySwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildCaptionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C333D),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_emotions_outlined, color: Colors.white54, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: TextField(
                controller: _captionController,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Add a caption...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildPostButton(),
        ],
      ),
    );
  }

  Widget _buildPostButton() {
    if (_posted) {
      return Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF4DB8FF),
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 20),
      );
    }
    if (_posting) {
      return SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _uploadProgress,
              strokeWidth: 2,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4DB8FF),
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _postStory,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF4DB8FF),
        ),
        child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PrivacyDialog(
        current: _privacy,
        onSelected: (v) => setState(() => _privacy = v),
        selectedContactIds: _selectedContactIds,
        onContactsSelected: (ids) => setState(() => _selectedContactIds = ids),
        excludedContactIds: _excludedContactIds,
        onExcludedContactsSelected: (ids) => setState(() => _excludedContactIds = ids),
      ),
    );
  }

  void _showDurationMenu() {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + box.size.width / 2 - 80,
        offset.dy + box.size.height - 200,
        offset.dx + box.size.width / 2 + 80,
        offset.dy + box.size.height,
      ),
      items: [
        _durationItem(6),
        _durationItem(12),
        _durationItem(24),
        _durationItem(48),
      ],
    ).then((value) {
      if (value != null) setState(() => _durationHours = value);
    });
  }

  PopupMenuItem<int> _durationItem(int hours) {
    final isPremiumGated = hours == 48;
    return PopupMenuItem(
      value: isPremiumGated ? null : hours,
      onTap: isPremiumGated
          ? () {
              showTelegramToast(context, 'Subscribe to Telegram Premium to set 48h duration.');
            }
          : null,
      child: Row(
        children: [
          if (_durationHours == hours)
            const Icon(Icons.check, size: 18, color: Color(0xFF4DB8FF))
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text('$hours hours'),
          if (isPremiumGated) ...[
            const SizedBox(width: 6),
            const Icon(Icons.lock, size: 14, color: Color(0xFF8E8E93)),
          ],
        ],
      ),
    );
  }

  Widget _buildTextEditOverlay() {
    return Material(
      color: Colors.black54,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        _currentTextAlign == _TextAlign.left
                            ? Icons.format_align_left
                            : _currentTextAlign == _TextAlign.center
                                ? Icons.format_align_center
                                : Icons.format_align_right,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _currentTextAlign = _TextAlign.values[
                              (_currentTextAlign.index + 1) % _TextAlign.values.length];
                          _editingTextItem?.textAlign = _currentTextAlign;
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_color_fill, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _currentTextBgStyle = _TextBgStyle.values[
                              (_currentTextBgStyle.index + 1) % _TextBgStyle.values.length];
                          _editingTextItem?.textBgStyle = _currentTextBgStyle;
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.font_download, color: Colors.white),
                      onPressed: _showFontPicker,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _paletteColors.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final c = _paletteColors[i];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _brushColor = c;
                            _editingTextItem?.color = c;
                          });
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c,
                            border: _brushColor == c
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: TextField(
                    controller: _textEditController,
                    autofocus: true,
                    textAlign: _currentTextAlign == _TextAlign.left
                        ? TextAlign.left
                        : _currentTextAlign == _TextAlign.right
                            ? TextAlign.right
                            : TextAlign.center,
                    style: TextStyle(
                      color: _brushColor,
                      fontSize: _fontSize,
                      fontFamily: _fonts[_selectedFontIndex],
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Type text...',
                      hintStyle: TextStyle(color: Colors.white38),
                    ),
                    onSubmitted: (_) => _commitTextEdit(),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _commitTextEdit,
                  child: const Text('Done', style: TextStyle(color: Color(0xFF4DB8FF), fontSize: 16)),
                ),
              ],
            ),
          ),
          // §32.15.5: Vertical font-size slider (14-72pt)
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onVerticalDragStart: (_) => setState(() => _fontSizeSliderExpanded = true),
                onVerticalDragUpdate: (d) {
                  setState(() {
                    final delta = -d.delta.dy / 280;
                    _fontSize = (_fontSize + delta * (72 - 14)).clamp(14.0, 72.0);
                    _editingTextItem?.fontSize = _fontSize;
                  });
                },
                onVerticalDragEnd: (_) => setState(() => _fontSizeSliderExpanded = false),
                child: SizedBox(
                  width: _fontSizeSliderExpanded ? 40 : 24,
                  height: 280 + 48,
                  child: CustomPaint(
                    painter: _FontSizeSliderPainter(
                      ratio: (_fontSize - 14) / (72 - 14),
                      expanded: _fontSizeSliderExpanded,
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

  void _commitTextEdit() {
    if (_editingTextItem != null) {
      final text = _textEditController.text.trim();
      if (text.isEmpty) {
        final idx = _sceneItems.indexOf(_editingTextItem!);
        final removed = _editingTextItem!;
        _sceneItems.remove(removed);
        _undoStack.add(_RemoveItemAction(removed, idx));
        _redoStack.clear();
      } else {
        _editingTextItem!.text = text;
        _editingTextItem!.color = _brushColor;
        _editingTextItem!.fontFamily = _fonts[_selectedFontIndex];
        _editingTextItem!.textAlign = _currentTextAlign;
        _editingTextItem!.textBgStyle = _currentTextBgStyle;
        _editingTextItem!.fontSize = _fontSize;
      }
    }
    setState(() => _editingTextItem = null);
  }

  void _showFontPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (ctx) => SizedBox(
        height: 60,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _fonts.length,
          itemBuilder: (ctx, i) {
            final isSelected = i == _selectedFontIndex;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFontIndex = i;
                  _editingTextItem?.fontFamily = _fonts[i];
                });
                Navigator.pop(ctx);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isSelected ? const Color(0x334DB8FF) : Colors.transparent,
                ),
                alignment: Alignment.center,
                child: Text(
                  _fontLabels[i],
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF4DB8FF) : Colors.white70,
                    fontFamily: _fonts[i],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (ctx) => _StickerPickerPanel(
        onEmojiSelected: (emoji) {
          Navigator.pop(ctx);
          final center = Offset(
            _canvasWidth / 2,
            _canvasHeight / 2,
          );
          final item = _SceneItem(
            position: center,
            isText: true,
            text: emoji,
            color: Colors.white,
            fontSize: 64,
            textAlign: _TextAlign.center,
            textBgStyle: _TextBgStyle.none,
            fontFamily: 'sans-serif',
          );
          setState(() {
            _sceneItems.add(item);
            _undoStack.add(_AddItemAction(item));
            _redoStack.clear();
          });
        },
        onStickerSelected: (sticker) {
          Navigator.pop(ctx);
          final center = Offset(
            _canvasWidth / 2,
            _canvasHeight / 2,
          );
          Uint8List? imageBytes;
          if (sticker.thumbB64.isNotEmpty) {
            try {
              imageBytes = Uint8List.fromList(base64Decode(sticker.thumbB64));
            } catch (_) {}
          }
          final item = _SceneItem(
            position: center,
            stickerImageBytes: imageBytes,
            stickerWidth: sticker.width,
            stickerHeight: sticker.height,
            text: sticker.emoji,
          );
          setState(() {
            _sceneItems.add(item);
            _undoStack.add(_AddItemAction(item));
            _redoStack.clear();
          });
        },
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_editingTextItem != null) {
        _commitTextEdit();
      } else {
        _handleCancel();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (_mode != _EditorMode.post && _editingTextItem == null) {
        _handleDone();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.keyZ &&
        HardwareKeyboard.instance.isControlPressed) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _redo();
      } else {
        _undo();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_selectedItem != null && _editingTextItem == null) {
        final idx = _sceneItems.indexOf(_selectedItem!);
        final removed = _selectedItem!;
        setState(() {
          _sceneItems.remove(removed);
          _undoStack.add(_RemoveItemAction(removed, idx));
          _redoStack.clear();
          _selectedItem = null;
        });
      }
    }
  }
}

// ── Custom Painters ──

class _StrokePainter extends CustomPainter {
  final List<_PaintStroke> strokes;
  final List<Offset>? currentPoints;
  final Color currentColor;
  final double currentWidth;
  final _BrushTool currentTool;
  final double scale;

  _StrokePainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.currentTool,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in strokes) {
      paintStroke(canvas, stroke.points, stroke.color, stroke.width, stroke.tool, scale);
    }
    if (currentPoints != null && currentPoints!.isNotEmpty) {
      paintStroke(canvas, currentPoints!, currentColor, currentWidth, currentTool, scale);
    }
    canvas.restore();
  }

  static void paintStroke(Canvas canvas, List<Offset> points, Color color, double width, _BrushTool tool, double scale) {
    if (points.length < 2) return;
    if (tool == _BrushTool.blur) return;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * scale;

    final isMarker = tool == _BrushTool.marker;

    switch (tool) {
      case _BrushTool.pen:
      case _BrushTool.arrow:
        paint.color = color;
        break;
      case _BrushTool.marker:
        paint.color = color.withValues(alpha: 0.35);
        paint.blendMode = BlendMode.src;
        break;
      case _BrushTool.blur:
        break;
      case _BrushTool.eraser:
        paint.color = Colors.transparent;
        paint.blendMode = BlendMode.clear;
        break;
    }

    if (isMarker) {
      canvas.saveLayer(null, Paint()..blendMode = BlendMode.srcOver);
    }

    final smoothed = _smoothPoints(points);
    final path = Path();
    if (smoothed.length < 2) {
      if (smoothed.isNotEmpty) {
        path.moveTo(smoothed[0].dx * scale, smoothed[0].dy * scale);
        path.lineTo(smoothed[0].dx * scale, smoothed[0].dy * scale);
      }
    } else {
      path.moveTo(smoothed[0].dx * scale, smoothed[0].dy * scale);
      for (int i = 1; i < smoothed.length; i++) {
        final p0 = smoothed[i - 1] * scale;
        final p1 = smoothed[i] * scale;
        final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
      }
      final last = smoothed.last * scale;
      path.lineTo(last.dx, last.dy);
    }
    canvas.drawPath(path, paint);

    if (tool == _BrushTool.arrow && points.length >= 2) {
      final last = points.last * scale;
      final minDist = width * scale * 1.5;
      var lookback = points[points.length - 2] * scale;
      for (int i = points.length - 2; i >= 0; i--) {
        final candidate = points[i] * scale;
        final dx = last.dx - candidate.dx;
        final dy = last.dy - candidate.dy;
        if (math.sqrt(dx * dx + dy * dy) >= minDist) {
          lookback = candidate;
          break;
        }
      }
      final angle = math.atan2(last.dy - lookback.dy, last.dx - lookback.dx);
      final headLen = width * scale * 2.5;
      const arrowAngle = 26 * math.pi / 180;
      final p1 = Offset(
        last.dx - headLen * math.cos(angle - arrowAngle),
        last.dy - headLen * math.sin(angle - arrowAngle),
      );
      final p2 = Offset(
        last.dx - headLen * math.cos(angle + arrowAngle),
        last.dy - headLen * math.sin(angle + arrowAngle),
      );
      final arrowPath = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(last.dx, last.dy)
        ..lineTo(p2.dx, p2.dy);
      canvas.drawPath(arrowPath, paint..style = PaintingStyle.stroke);
    }
    if (isMarker) {
      canvas.restore();
    }
  }

  static List<Offset> _smoothPoints(List<Offset> raw) {
    if (raw.length < 3) return raw;
    var pts = List<Offset>.from(raw);
    for (int pass = 0; pass < 2; pass++) {
      final smoothed = <Offset>[pts.first];
      for (int i = 1; i < pts.length - 1; i++) {
        smoothed.add(Offset(
          (pts[i - 1].dx + pts[i].dx + pts[i + 1].dx) / 3,
          (pts[i - 1].dy + pts[i].dy + pts[i + 1].dy) / 3,
        ));
      }
      smoothed.add(pts.last);
      pts = smoothed;
    }
    return pts;
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) =>
      old.strokes != strokes ||
      old.currentPoints != currentPoints;
}

class _BrushSizeSliderPainter extends CustomPainter {
  final double sizeRatio;
  final bool expanded;

  _BrushSizeSliderPainter({required this.sizeRatio, required this.expanded});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final topY = 24.0;
    final bottomY = size.height - 24.0;
    final height = bottomY - topY;

    final expandedTopW = expanded ? 25.0 : 2.0;
    final expandedBottomW = expanded ? 4.0 : 2.0;
    final alpha = expanded ? 176 : 96;

    final paint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 255)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(cx - expandedTopW / 2, topY);
    path.lineTo(cx + expandedTopW / 2, topY);
    path.lineTo(cx + expandedBottomW / 2, bottomY);
    path.lineTo(cx - expandedBottomW / 2, bottomY);
    path.close();
    canvas.drawPath(path, paint);

    final handleY = bottomY - height * sizeRatio;
    final handleR = 4 + (25 - 4) * sizeRatio;
    canvas.drawCircle(
      Offset(cx, handleY),
      handleR / 2,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _BrushSizeSliderPainter old) =>
      old.sizeRatio != sizeRatio || old.expanded != expanded;
}

// ── Dialogs ──

class _PrivacyDialog extends StatefulWidget {
  final StoryPrivacyOption current;
  final ValueChanged<StoryPrivacyOption> onSelected;
  final ValueChanged<List<String>>? onContactsSelected;
  final List<String> selectedContactIds;
  final ValueChanged<List<String>>? onExcludedContactsSelected;
  final List<String> excludedContactIds;

  const _PrivacyDialog({
    required this.current,
    required this.onSelected,
    this.onContactsSelected,
    this.selectedContactIds = const [],
    this.onExcludedContactsSelected,
    this.excludedContactIds = const [],
  });

  @override
  State<_PrivacyDialog> createState() => _PrivacyDialogState();
}

class _PrivacyDialogState extends State<_PrivacyDialog> {
  late StoryPrivacyOption _selected;
  late List<String> _contactIds;
  late List<String> _excludedIds;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    _contactIds = List<String>.from(widget.selectedContactIds);
    _excludedIds = List<String>.from(widget.excludedContactIds);
  }

  static const _options = [
    (StoryPrivacyOption.everyone, Icons.public, 'Everyone', 'All your subscribers'),
    (StoryPrivacyOption.contacts, Icons.people, 'Contacts', 'Exclude people'),
    (StoryPrivacyOption.closeFriends, Icons.star, 'Close Friends', 'Close friends list'),
    (StoryPrivacyOption.selectedContacts, Icons.person_add, 'Selected Contacts', 'Select allowed users'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white54 : Colors.black45;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                alignment: Alignment.centerLeft,
                child: Text(
                  'Who can view your story?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              for (final (option, icon, label, subtitle) in _options)
                InkWell(
                  onTap: () {
                    setState(() => _selected = option);
                    if (option == StoryPrivacyOption.contacts) {
                      _showExclusionPicker(context);
                    } else if (option == StoryPrivacyOption.selectedContacts) {
                      _showContactPicker(context);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(icon, size: 24, color: const Color(0xFF4DB8FF)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: TextStyle(fontSize: 14, color: textColor)),
                              Text(
                                option == StoryPrivacyOption.contacts && _excludedIds.isNotEmpty
                                    ? 'Excluded ${_excludedIds.length} ${_excludedIds.length == 1 ? 'person' : 'people'}'
                                    : subtitle,
                                style: TextStyle(fontSize: 12, color: subtextColor),
                              ),
                            ],
                          ),
                        ),
                        Radio<StoryPrivacyOption>(
                          value: option,
                          groupValue: _selected,
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selected = v);
                              if (v == StoryPrivacyOption.contacts) {
                                _showExclusionPicker(context);
                              } else if (v == StoryPrivacyOption.selectedContacts) {
                                _showContactPicker(context);
                              }
                            }
                          },
                          activeColor: const Color(0xFF4DB8FF),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: subtextColor)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        widget.onSelected(_selected);
                        widget.onContactsSelected?.call(_contactIds);
                        widget.onExcludedContactsSelected?.call(_excludedIds);
                        Navigator.pop(context);
                      },
                      child: const Text('Save', style: TextStyle(color: Color(0xFF4DB8FF))),
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

  Future<void> _showContactPicker(BuildContext context) async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId == null) return;

    final contacts = await engine.getContacts(accountId);
    if (!context.mounted) return;

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _ContactPickerDialog(
        contacts: contacts,
        selectedIds: _contactIds,
      ),
    );
    if (result != null) {
      setState(() => _contactIds = result);
    }
  }

  Future<void> _showExclusionPicker(BuildContext context) async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId == null) return;

    final contacts = await engine.getContacts(accountId);
    if (!context.mounted) return;

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _ContactPickerDialog(
        contacts: contacts,
        selectedIds: _excludedIds,
        title: 'Exclude People',
      ),
    );
    if (result != null) {
      setState(() => _excludedIds = result);
    }
  }
}

class _ContactPickerDialog extends StatefulWidget {
  final List<ContactInfo> contacts;
  final List<String> selectedIds;
  final String title;

  const _ContactPickerDialog({
    required this.contacts,
    required this.selectedIds,
    this.title = 'Select Contacts',
  });

  @override
  State<_ContactPickerDialog> createState() => _ContactPickerDialogState();
}

class _ContactPickerDialogState extends State<_ContactPickerDialog> {
  late Set<String> _selected;
  String _search = '';
  final Map<String, Uint8List> _avatarCache = {};

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
    for (final c in widget.contacts) {
      if (c.avatarB64.isNotEmpty) {
        try {
          _avatarCache[c.userId] = Uint8List.fromList(base64Decode(c.avatarB64));
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white54 : Colors.black45;

    final filtered = widget.contacts.where((c) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return c.displayName.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q);
    }).toList();

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                child: Text(
                  '${widget.title} (${_selected.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: TextStyle(color: textColor, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search contacts...',
                    hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: subtextColor),
                    ),
                    prefixIcon: Icon(Icons.search, size: 18, color: subtextColor),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No contacts found',
                          style: TextStyle(color: subtextColor, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final c = filtered[i];
                          final isSelected = _selected.contains(c.userId);
                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selected.remove(c.userId);
                                } else {
                                  _selected.add(c.userId);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(0xFF4DB8FF),
                                    backgroundImage: _avatarCache.containsKey(c.userId)
                                        ? MemoryImage(_avatarCache[c.userId]!)
                                        : null,
                                    child: !_avatarCache.containsKey(c.userId)
                                        ? Text(
                                            c.displayName.isNotEmpty
                                                ? c.displayName[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(color: Colors.white, fontSize: 14),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.displayName.isNotEmpty ? c.displayName : c.username,
                                          style: TextStyle(fontSize: 14, color: textColor),
                                        ),
                                        if (c.username.isNotEmpty)
                                          Text(
                                            '@${c.username}',
                                            style: TextStyle(fontSize: 12, color: subtextColor),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selected.add(c.userId);
                                        } else {
                                          _selected.remove(c.userId);
                                        }
                                      });
                                    },
                                    activeColor: const Color(0xFF4DB8FF),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: subtextColor)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context, _selected.toList()),
                      child: const Text('Done', style: TextStyle(color: Color(0xFF4DB8FF))),
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
}

class _HSLColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const _HSLColorPickerDialog({required this.initialColor, required this.onColorSelected});

  @override
  State<_HSLColorPickerDialog> createState() => _HSLColorPickerDialogState();
}

class _HSLColorPickerDialogState extends State<_HSLColorPickerDialog> {
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
      HSLColor.fromAHSL(1, _hue, _saturation, _lightness).toColor();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose Color'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _currentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 16),
            _sliderRow('H', _hue, 360, (v) => setState(() => _hue = v)),
            _sliderRow('S', _saturation * 100, 100, (v) => setState(() => _saturation = v / 100)),
            _sliderRow('L', _lightness * 100, 100, (v) => setState(() => _lightness = v / 100)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            widget.onColorSelected(_currentColor);
            Navigator.pop(context);
          },
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _sliderRow(String label, double value, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(
          child: Slider(value: value, max: max, onChanged: onChanged),
        ),
        SizedBox(width: 36, child: Text(value.toInt().toString())),
      ],
    );
  }
}

class _StorySwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _StorySwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: value ? const Color(0xFF4DB8FF) : const Color(0x26FFFFFF),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// §32.15.5: Vertical font-size slider painter (14-72pt)
class _FontSizeSliderPainter extends CustomPainter {
  final double ratio;
  final bool expanded;

  _FontSizeSliderPainter({required this.ratio, required this.expanded});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final topY = 24.0;
    final bottomY = size.height - 24.0;
    final height = bottomY - topY;

    final expandedTopW = expanded ? 25.0 : 2.0;
    final expandedBottomW = expanded ? 4.0 : 2.0;
    final alpha = expanded ? 176 : 96;

    final paint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 255)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(cx - expandedTopW / 2, topY);
    path.lineTo(cx + expandedTopW / 2, topY);
    path.lineTo(cx + expandedBottomW / 2, bottomY);
    path.lineTo(cx - expandedBottomW / 2, bottomY);
    path.close();
    canvas.drawPath(path, paint);

    final handleY = bottomY - height * ratio;
    final handleR = 4 + (25 - 4) * ratio;
    canvas.drawCircle(
      Offset(cx, handleY),
      handleR / 2,
      Paint()..color = Colors.white,
    );

    final label = '${(14 + (72 - 14) * ratio).round()}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, handleY - tp.height - 6));
  }

  @override
  bool shouldRepaint(covariant _FontSizeSliderPainter old) =>
      old.ratio != ratio || old.expanded != expanded;
}

// §32.15.3: Video trim slider with draggable handles
class _VideoTrimSlider extends StatefulWidget {
  final double trimStart;
  final double trimEnd;
  final void Function(double start, double end) onChanged;
  final List<ui.Image?> thumbnails;

  const _VideoTrimSlider({
    required this.trimStart,
    required this.trimEnd,
    required this.onChanged,
    this.thumbnails = const [],
  });

  @override
  State<_VideoTrimSlider> createState() => _VideoTrimSliderState();
}

class _VideoTrimSliderState extends State<_VideoTrimSlider> {
  static const _kHeight = 48.0;
  static const _kFrameCount = 12;
  static const _kMinDuration = 1.0 / 60.0;

  bool _draggingLeft = false;
  bool _draggingRight = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kHeight,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalW = constraints.maxWidth;
          final startX = widget.trimStart * totalW;
          final endX = widget.trimEnd * totalW;

          return GestureDetector(
            onHorizontalDragStart: (d) {
              final x = d.localPosition.dx;
              if ((x - startX).abs() < 20) {
                _draggingLeft = true;
              } else if ((x - endX).abs() < 20) {
                _draggingRight = true;
              }
            },
            onHorizontalDragUpdate: (d) {
              final x = d.localPosition.dx / totalW;
              if (_draggingLeft) {
                final newStart = x.clamp(0.0, widget.trimEnd - _kMinDuration);
                widget.onChanged(newStart, widget.trimEnd);
              } else if (_draggingRight) {
                final newEnd = x.clamp(widget.trimStart + _kMinDuration, 1.0);
                widget.onChanged(widget.trimStart, newEnd);
              }
            },
            onHorizontalDragEnd: (_) {
              _draggingLeft = false;
              _draggingRight = false;
            },
            child: CustomPaint(
              painter: _VideoTrimPainter(
                trimStart: widget.trimStart,
                trimEnd: widget.trimEnd,
                frameCount: _kFrameCount,
                thumbnails: widget.thumbnails,
              ),
              size: Size(totalW, _kHeight),
            ),
          );
        },
      ),
    );
  }
}

class _VideoTrimPainter extends CustomPainter {
  final double trimStart;
  final double trimEnd;
  final int frameCount;
  final List<ui.Image?> thumbnails;

  _VideoTrimPainter({
    required this.trimStart,
    required this.trimEnd,
    required this.frameCount,
    this.thumbnails = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final frameW = size.width / frameCount;
    final frameH = size.height - 12;
    final frameY = 6.0;

    for (var i = 0; i < frameCount; i++) {
      final x = i * frameW;
      final frameRect = Rect.fromLTWH(x + 1, frameY, frameW - 2, frameH);
      final rrect = RRect.fromRectAndRadius(frameRect, const Radius.circular(4));

      if (i < thumbnails.length && thumbnails[i] != null) {
        final img = thumbnails[i]!;
        canvas.save();
        canvas.clipRRect(rrect);
        final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
        canvas.drawImageRect(img, src, frameRect, Paint());
        canvas.restore();
      } else {
        final t = i / frameCount;
        final gray = (30 + t * 15).toInt();
        canvas.drawRRect(rrect, Paint()..color = Color.fromRGBO(gray, gray, gray + 5, 1.0));
      }
    }

    final darken = Paint()..color = const Color(0x73000000);
    final startX = trimStart * size.width;
    final endX = trimEnd * size.width;

    if (startX > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, startX, size.height), darken);
    }
    if (endX < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(endX, 0, size.width - endX, size.height),
        darken,
      );
    }

    final handlePaint = Paint()..color = Colors.white;
    final leftHandle = RRect.fromRectAndRadius(
      Rect.fromLTWH(startX - 4, 0, 8, size.height),
      const Radius.circular(4),
    );
    final rightHandle = RRect.fromRectAndRadius(
      Rect.fromLTWH(endX - 4, 0, 8, size.height),
      const Radius.circular(4),
    );
    canvas.drawRRect(leftHandle, handlePaint);
    canvas.drawRRect(rightHandle, handlePaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      Rect.fromLTWH(startX, 0, endX - startX, size.height),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoTrimPainter old) =>
      old.trimStart != trimStart || old.trimEnd != trimEnd ||
      old.thumbnails != thumbnails;
}

class _StickerPickerPanel extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<StickerInfoItem>? onStickerSelected;

  const _StickerPickerPanel({required this.onEmojiSelected, this.onStickerSelected});

  @override
  State<_StickerPickerPanel> createState() => _StickerPickerPanelState();
}

class _StickerPickerPanelState extends State<_StickerPickerPanel> {
  int _activeTab = 0;
  List<StickerPackSummary>? _stickerPacks;
  bool _loadingPacks = false;
  final Map<String, Uint8List> _stickerThumbCache = {};

  static const _emojiCategories = [
    ['😀', '😂', '🥹', '😍', '🥰', '😎', '🤩', '🥳',
     '😇', '🤔', '😏', '😴', '🤯', '😱', '🥺', '😭',
     '🤗', '😤', '🫡', '🫶', '💀', '👻', '🤖', '👽'],
    ['🐱', '🐶', '🦊', '🐻', '🐼', '🐸', '🦁', '🐧',
     '🌸', '🌺', '🌻', '🌹', '🍀', '🍁', '🌈', '⭐'],
    ['🔥', '💥', '❤️', '💜', '💙', '💚', '💛', '🖤',
     '👍', '👎', '✌️', '🤞', '👏', '🙌', '💪', '🫰'],
    ['🎉', '🎊', '🎁', '🏆', '🎯', '🎸', '🎵', '🎨',
     '🚀', '💡', '🔔', '📌', '✅', '❌', '⚡', '🌟'],
  ];

  List<String> get _allEmojis => _emojiCategories.expand((c) => c).toList();

  void _loadStickerPacks() {
    if (_loadingPacks || _stickerPacks != null) return;
    _loadingPacks = true;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId == null) {
      setState(() => _loadingPacks = false);
      return;
    }
    engine.getInstalledStickerPacks(accountId).then((packs) {
      if (mounted) {
        for (final pack in packs) {
          for (final sticker in pack.stickers) {
            if (sticker.thumbB64.isNotEmpty && !_stickerThumbCache.containsKey(sticker.fileId)) {
              try {
                _stickerThumbCache[sticker.fileId] = Uint8List.fromList(base64Decode(sticker.thumbB64));
              } catch (_) {}
            }
          }
        }
        setState(() {
          _stickerPacks = packs;
          _loadingPacks = false;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _stickerPacks = [];
          _loadingPacks = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _activeTab = 0),
                  child: Text(
                    'Emoji',
                    style: TextStyle(
                      color: _activeTab == 0 ? const Color(0xFF4DB8FF) : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () {
                    setState(() => _activeTab = 1);
                    _loadStickerPacks();
                  },
                  child: Text(
                    'Stickers',
                    style: TextStyle(
                      color: _activeTab == 1 ? const Color(0xFF4DB8FF) : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _activeTab == 0 ? _buildEmojiGrid() : _buildStickerGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiGrid() {
    final emojis = _allEmojis;
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: emojis.length,
      itemBuilder: (ctx, i) {
        return GestureDetector(
          onTap: () => widget.onEmojiSelected(emojis[i]),
          child: Center(
            child: Text(emojis[i], style: const TextStyle(fontSize: 28)),
          ),
        );
      },
    );
  }

  Widget _buildStickerGrid() {
    if (_loadingPacks) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4DB8FF)),
      );
    }
    final packs = _stickerPacks;
    if (packs == null || packs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sticky_note_2_outlined, color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text(
              'No sticker packs installed',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final allStickers = <(StickerInfoItem, String)>[];
    for (final pack in packs) {
      for (final sticker in pack.stickers) {
        allStickers.add((sticker, pack.title));
      }
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: allStickers.length,
      itemBuilder: (ctx, i) {
        final (sticker, _) = allStickers[i];
        Widget stickerWidget;
        final cachedThumb = _stickerThumbCache[sticker.fileId];
        if (cachedThumb != null) {
          stickerWidget = Image.memory(
            cachedThumb,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Text(
                sticker.emoji.isNotEmpty ? sticker.emoji : '?',
                style: const TextStyle(fontSize: 32),
              ),
            ),
          );
        } else {
          stickerWidget = Center(
            child: Text(
              sticker.emoji.isNotEmpty ? sticker.emoji : '?',
              style: const TextStyle(fontSize: 32),
            ),
          );
        }
        return GestureDetector(
          onTap: () {
            if (widget.onStickerSelected != null) {
              widget.onStickerSelected!(sticker);
            } else {
              widget.onEmojiSelected(
                sticker.emoji.isNotEmpty ? sticker.emoji : '?',
              );
            }
          },
          child: stickerWidget,
        );
      },
    );
  }
}

class _BlurStrokeClipper extends CustomClipper<Path> {
  final List<Offset> points;
  final double width;
  final double scale;

  _BlurStrokeClipper(this.points, this.width, this.scale);

  @override
  Path getClip(Size size) {
    final path = Path();
    final r = width * scale / 2;
    for (final pt in points) {
      path.addOval(Rect.fromCircle(center: Offset(pt.dx * scale, pt.dy * scale), radius: r));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _BlurStrokeClipper old) =>
      old.points != points || old.width != width || old.scale != scale;
}
