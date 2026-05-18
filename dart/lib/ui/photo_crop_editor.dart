import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../models/engine_models.dart';
import 'color_picker_box.dart';

const double _kContentMarginLeft = 20;
const double _kContentMarginTop = 20;
const double _kContentMarginRight = 20;
const double _kContentMarginBottom = 146;
const EdgeInsets _kContentMargins = EdgeInsets.fromLTRB(
  _kContentMarginLeft,
  _kContentMarginTop,
  _kContentMarginRight,
  _kContentMarginBottom,
);

const Color _kDimColorLight = Color.fromARGB(192, 16, 16, 16);
const Color _kDimColorDark = Color.fromARGB(128, 16, 16, 16);
const double _kBlurSigma = 24;

const double _kControlBarHeight = 48;
const double _kControlBarWidth = 422;
const Color _kCaptionFg = Color(0xFFFFFFFF);
const Color _kCancelFg = Color(0xFFFFFFFF);
const Color _kCancelBg = Color(0x33FFFFFF);
const Color _kDoneLinkFg = Color(0xFF71BAF7);
const Color _kIconFgIdle = Color(0xDDFFFFFF);
const Color _kIconFgActive = Color(0xFF6AB2F2);
const Color _kIconFgInactive = Color(0x4DFFFFFF);

const Duration _kTransitionDuration = Duration(milliseconds: 200);
const Duration _kBgCrossFadeDuration = Duration(milliseconds: 200);
const Duration _kBgDebouncefast = Duration(milliseconds: 200);
const Duration _kBgDebounceFull = Duration(milliseconds: 1000);

const int _kProfilePhotoSize = 640;
const double _kExtremeRatioLimit = 10.0;

const double _kCropHandleSize = 10.0;
const double _kCropMinSize = 20.0;
const double _kCropBorderWidth = 2.0;
const double _kCropCornerWidth = 4.0;
const Color _kCropPointFg = Color(0xFFFFFFFF);
const Color _kCropFadeBg = Color(0x99000000);
const double _kForumRadiusMultiplier = 0.3;

const List<Color> _kPaletteColors = [
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
const double _kPaletteItemSize = 20.0;
const double _kPaletteGap = 6.0;
const double _kMinBrushSize = 1.0;
const double _kMaxBrushSize = 25.0;
const double _kArrowHeadAngleDeg = 26.0;
const double _kArrowHeadLengthFactor = 2.5;
const double _kArrowHeadMinDistFactor = 1.5;
const double _kMarkerOpacity = 0.35;
const double _kMarkerSizeMultiplier = 2.5;
const Color _kControlBarPillBg = Color(0x33000000);

const double _kBrushSizeControlHeight = 280.0;
const double _kBrushSizeControlCollapsedWidth = 2.0;
const double _kBrushSizeControlExpandedTopWidth = 25.0;
const double _kBrushSizeControlExpandedBottomWidth = 4.0;
const double _kBrushSizeControlExpandShift = 14.0;
const double _kBrushSizeControlHitPadding = 24.0;
const Duration _kBrushSizeControlAnimDuration = Duration(milliseconds: 200);

const Map<_PaintTool, Color> _kDefaultToolColors = {
  _PaintTool.pen: Color(0xFFEA2739),
  _PaintTool.arrow: Color(0xFFFC964D),
  _PaintTool.marker: Color(0xFFFCDE65),
  _PaintTool.blur: Color(0xFF000000),
  _PaintTool.eraser: Color(0xFF000000),
};
const Set<_PaintTool> _kFixedColorTools = {_PaintTool.blur, _PaintTool.eraser};

const double _kMinCanvasZoom = 1.0;
const double _kMaxCanvasZoom = 8.0;
const double _kCanvasZoomStep = 1.15;
const double _kCanvasZoomStepFine = 1.015;

const double _kBlurSigmaFactor = 0.8;
const double _kAnnotationHandleSize = 8.0;
const double _kAnnotationHitSlop = 20.0;
const double _kAnnotationMinScale = 0.2;
const double _kAnnotationMaxScale = 5.0;

const double _kRainbowRingSize = 28.0;
const double _kRainbowRingBorder = 3.0;
const double _kToolButtonSize = 36.0;
const Duration _kToolSelectDuration = Duration(milliseconds: 200);
const Duration _kColorButtonSwitchDuration = Duration(milliseconds: 140);
const double _kPlusCircleSize = 20.0;

enum _Edge {
  none,
  topLeft, topRight, bottomLeft, bottomRight,
  top, bottom, left, right,
  move,
}

enum _PaintTool { pen, arrow, marker, blur, eraser }

enum _UndoKind { stroke, text }

class _ToolBrush {
  Color color;
  double sizeRatio;
  _ToolBrush({required this.color, this.sizeRatio = 0.125});
}

class _PaintStroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final _PaintTool tool;

  _PaintStroke({
    required this.points,
    required this.color,
    required this.width,
    this.tool = _PaintTool.pen,
  });
}

class _TextAnnotation {
  Offset position;
  String text;
  Color color;
  double fontSize;
  double scale;

  _TextAnnotation({
    required this.position,
    required this.text,
    required this.color,
    this.fontSize = 24,
    this.scale = 1.0,
  });

  _TextAnnotation copy() => _TextAnnotation(
    position: position,
    text: text,
    color: color,
    fontSize: fontSize,
    scale: scale,
  );
}

enum _CornerLevel {
  large(0.3, 'Large'),
  medium(0.2, 'Medium'),
  small(0.1, 'Small'),
  none(0.0, 'None');

  final double multiplier;
  final String label;
  const _CornerLevel(this.multiplier, this.label);
}

enum PhotoCropShape { ellipse, roundedRect, rect }

enum _EditorMode { transform, paint }

enum _IconState { idle, active, inactive }

enum PhotoEditorPurpose {
  setPhoto,
  suggest,
  edit;

  String get doneLabel => switch (this) {
    setPhoto => 'Set Photo',
    suggest => 'Suggest',
    edit => 'Done',
  };
}

enum _CropAspect {
  original, square, ratio3x2, ratio16x9, ratio3x4, ratio9x16, free;

  String get label => switch (this) {
    original => 'Original',
    square => 'Square',
    ratio3x2 => '3:2',
    ratio3x4 => '3:4',
    ratio16x9 => '16:9',
    ratio9x16 => '9:16',
    free => 'Free',
  };

  double? ratioValue(double imageRatio) => switch (this) {
    original => imageRatio,
    square => 1.0,
    ratio3x2 => 3.0 / 2.0,
    ratio3x4 => 3.0 / 4.0,
    ratio16x9 => 16.0 / 9.0,
    ratio9x16 => 9.0 / 16.0,
    free => null,
  };
}

class PhotoCropEditor extends StatefulWidget {
  final File imageFile;
  final PhotoCropShape shape;
  final String? aboutText;
  final PhotoEditorPurpose purpose;
  final Future<void> Function(File croppedFile)? onDone;

  static bool Function(String keyCombo)? _activeKeyHandler;

  static bool handleKey(String keyCombo) =>
      _activeKeyHandler?.call(keyCombo) ?? false;

  String get doneLabel => purpose.doneLabel;

  const PhotoCropEditor({
    super.key,
    required this.imageFile,
    this.shape = PhotoCropShape.ellipse,
    this.aboutText,
    this.purpose = PhotoEditorPurpose.setPhoto,
    this.onDone,
  });

  static Future<void> open(
    BuildContext context, {
    required File imageFile,
    PhotoCropShape shape = PhotoCropShape.ellipse,
    String? aboutText,
    PhotoEditorPurpose purpose = PhotoEditorPurpose.setPhoto,
    Future<void> Function(File croppedFile)? onDone,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        barrierDismissible: false,
        transitionDuration: _kTransitionDuration,
        reverseTransitionDuration: _kTransitionDuration,
        pageBuilder: (context, animation, secondaryAnimation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: PhotoCropEditor(
              imageFile: imageFile,
              shape: shape,
              aboutText: aboutText,
              purpose: purpose,
              onDone: onDone,
            ),
          );
        },
      ),
    );
  }

  @override
  State<PhotoCropEditor> createState() => _PhotoCropEditorState();
}

class _PhotoCropEditorState extends State<PhotoCropEditor> {
  ui.Image? _image;
  bool _loading = true;
  bool _saving = false;
  int _rotationDegrees = 0;
  bool _flipped = false;
  _EditorMode _editorMode = _EditorMode.transform;
  _CropAspect _selectedAspect = _CropAspect.free;
  final _focusNode = FocusNode();
  final _cropKey = GlobalKey<_ImageCropAreaState>();
  final List<_PaintStroke> _paintStrokes = [];
  final List<_PaintStroke> _undoneStrokes = [];
  Color _brushColor = const Color(0xFFEA2739);
  double _brushWidth = 4.0;
  double _forumCornerMultiplier = _kForumRadiusMultiplier;
  _PaintTool _currentPaintTool = _PaintTool.pen;
  final List<_TextAnnotation> _textAnnotations = [];
  final List<_TextAnnotation> _undoneAnnotations = [];
  final List<_UndoKind> _undoTracker = [];
  final List<_UndoKind> _redoTracker = [];
  late final Map<_PaintTool, _ToolBrush> _toolBrushes;
  List<_PaintStroke>? _paintSnapshot;
  List<_TextAnnotation>? _textSnapshot;
  List<_UndoKind>? _undoSnapshot;
  bool _paletteVisible = false;
  int _selectedAnnotation = -1;
  double _canvasZoom = 1.0;
  Offset _canvasOffset = Offset.zero;

  bool get _isProfilePhoto => widget.shape != PhotoCropShape.rect;

  double get _originalImageRatio {
    if (_image == null) return 1.0;
    final w = _image!.width.toDouble();
    final h = _image!.height.toDouble();
    final isSwapped = _rotationDegrees == 90 || _rotationDegrees == 270;
    return isSwapped ? h / w : w / h;
  }

  double? get _enforceRatio {
    if (_isProfilePhoto) return 1.0;
    return _selectedAspect.ratioValue(_originalImageRatio);
  }

  @override
  void initState() {
    super.initState();
    PhotoCropEditor._activeKeyHandler = _handleKeyCombo;
    _toolBrushes = {
      for (final tool in _PaintTool.values)
        tool: _ToolBrush(color: _kDefaultToolColors[tool]!),
    };
    _brushColor = _kDefaultToolColors[_PaintTool.pen]!;
    _loadImage();
  }

  @override
  void dispose() {
    if (PhotoCropEditor._activeKeyHandler == _handleKeyCombo) {
      PhotoCropEditor._activeKeyHandler = null;
    }
    _focusNode.dispose();
    super.dispose();
  }

  bool _handleKeyCombo(String keyCombo) {
    switch (keyCombo) {
      case 'escape':
        _cancel();
        return true;
      case 'enter':
        _done();
        return true;
      case 'ctrl+z':
        if (_editorMode == _EditorMode.paint) {
          _paintUndo();
          return true;
        }
        return false;
      case 'ctrl+y' || 'ctrl+shift+z':
        if (_editorMode == _EditorMode.paint) {
          _paintRedo();
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;

      final w = frame.image.width;
      final h = frame.image.height;

      if (w / h > _kExtremeRatioLimit || h / w > _kExtremeRatioLimit) {
        frame.image.dispose();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bad photo!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }

      ui.Image img = frame.image;
      if (_isProfilePhoto &&
          w < _kProfilePhotoSize &&
          h < _kProfilePhotoSize) {
        img = await _upscaleImage(img);
      }

      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() {
        _image = img;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<ui.Image> _upscaleImage(ui.Image source) async {
    final w = source.width;
    final h = source.height;
    final scale = math.max(
      _kProfilePhotoSize / w,
      _kProfilePhotoSize / h,
    );
    final targetW = (w * scale).round();
    final targetH = (h * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
    );
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(targetW, targetH);
    picture.dispose();
    source.dispose();
    return result;
  }

  void rotate() {
    setState(() {
      _rotationDegrees = (_rotationDegrees + 90) % 360;
    });
  }

  void toggleFlip() {
    setState(() {
      _flipped = !_flipped;
    });
  }

  void _cancel() {
    if (_editorMode == _EditorMode.paint) {
      setState(() {
        if (_paintSnapshot != null) {
          _paintStrokes
            ..clear()
            ..addAll(_paintSnapshot!);
        }
        if (_textSnapshot != null) {
          _textAnnotations
            ..clear()
            ..addAll(_textSnapshot!);
        }
        if (_undoSnapshot != null) {
          _undoTracker
            ..clear()
            ..addAll(_undoSnapshot!);
        }
        _undoneStrokes.clear();
        _undoneAnnotations.clear();
        _redoTracker.clear();
        _paintSnapshot = null;
        _textSnapshot = null;
        _undoSnapshot = null;
        _selectedAnnotation = -1;
        _canvasZoom = 1.0;
        _canvasOffset = Offset.zero;
        _editorMode = _EditorMode.transform;
      });
      _focusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop();
  }

  void _paintUndo() {
    if (_undoTracker.isEmpty) return;
    setState(() {
      final kind = _undoTracker.removeLast();
      _redoTracker.add(kind);
      if (kind == _UndoKind.stroke && _paintStrokes.isNotEmpty) {
        _undoneStrokes.add(_paintStrokes.removeLast());
      } else if (kind == _UndoKind.text && _textAnnotations.isNotEmpty) {
        _undoneAnnotations.add(_textAnnotations.removeLast());
      }
    });
  }

  void _paintRedo() {
    if (_redoTracker.isEmpty) return;
    setState(() {
      final kind = _redoTracker.removeLast();
      _undoTracker.add(kind);
      if (kind == _UndoKind.stroke && _undoneStrokes.isNotEmpty) {
        _paintStrokes.add(_undoneStrokes.removeLast());
      } else if (kind == _UndoKind.text && _undoneAnnotations.isNotEmpty) {
        _textAnnotations.add(_undoneAnnotations.removeLast());
      }
    });
  }

  bool get _canUndo => _undoTracker.isNotEmpty;
  bool get _canRedo => _redoTracker.isNotEmpty;

  void _paintDone() {
    setState(() {
      _paintSnapshot = null;
      _textSnapshot = null;
      _undoSnapshot = null;
      _selectedAnnotation = -1;
      _canvasZoom = 1.0;
      _canvasOffset = Offset.zero;
      _editorMode = _EditorMode.transform;
    });
    _focusNode.requestFocus();
  }

  void _addPaintStroke(_PaintStroke stroke) {
    setState(() {
      _paintStrokes.add(stroke);
      _undoneStrokes.clear();
      _undoTracker.add(_UndoKind.stroke);
      _redoTracker.clear();
      _undoneAnnotations.clear();
    });
  }

  void _togglePaintMode() {
    setState(() {
      if (_editorMode == _EditorMode.transform) {
        _paintSnapshot = _paintStrokes.map((s) => _PaintStroke(
          points: List.of(s.points), color: s.color, width: s.width, tool: s.tool,
        )).toList();
        _textSnapshot = _textAnnotations.map((a) => a.copy()).toList();
        _undoSnapshot = List.of(_undoTracker);
        _editorMode = _EditorMode.paint;
      } else {
        _selectedAnnotation = -1;
        _canvasZoom = 1.0;
        _canvasOffset = Offset.zero;
        _editorMode = _EditorMode.transform;
      }
    });
    _focusNode.requestFocus();
  }

  void _setAspect(_CropAspect aspect) {
    setState(() => _selectedAspect = aspect);
  }

  void _setCornerLevel(_CornerLevel level) {
    setState(() => _forumCornerMultiplier = level.multiplier);
  }

  _CornerLevel get _currentCornerLevel {
    for (final level in _CornerLevel.values) {
      if ((level.multiplier - _forumCornerMultiplier).abs() < 0.01) {
        return level;
      }
    }
    return _CornerLevel.large;
  }

  void _openTextTool([String initialText = '']) {
    final controller = TextEditingController(text: initialText);
    showDialog<String>(
      context: context,
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xE6222222),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Enter text...',
                      hintStyle: TextStyle(color: Color(0x66FFFFFF)),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (v) => Navigator.of(ctx).pop(v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel', style: TextStyle(color: Color(0x99FFFFFF))),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(controller.text),
                        child: const Text('Done', style: TextStyle(color: _kDoneLinkFg)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((text) {
      if (text != null && text.isNotEmpty) {
        _addTextAnnotation(text);
      }
    });
  }

  void _addTextAnnotation(String text) {
    final cropState = _cropKey.currentState;
    if (cropState == null) return;
    final center = cropState._cropRect.center;
    final shortSide = math.min(
      cropState._displaySize.width,
      cropState._displaySize.height,
    );
    final fontSize = (shortSide / 15).clamp(16.0, 72.0);
    setState(() {
      _textAnnotations.add(_TextAnnotation(
        position: center,
        text: text,
        color: _brushColor,
        fontSize: fontSize,
      ));
      _undoTracker.add(_UndoKind.text);
      _redoTracker.clear();
      _undoneStrokes.clear();
      _undoneAnnotations.clear();
    });
  }

  void _openStickersTool() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xF0222222),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _EditorStickerPicker(
        onSelected: (emoji) {
          Navigator.of(ctx).pop(emoji);
        },
      ),
    ).then((emoji) {
      if (emoji != null && emoji.isNotEmpty) {
        _addStickerAnnotation(emoji);
      }
    });
  }

  void _addStickerAnnotation(String emoji) {
    final cropState = _cropKey.currentState;
    if (cropState == null) return;
    final center = cropState._cropRect.center;
    final shortSide = math.min(
      cropState._displaySize.width,
      cropState._displaySize.height,
    );
    final fontSize = (shortSide / 6).clamp(32.0, 120.0);
    setState(() {
      _textAnnotations.add(_TextAnnotation(
        position: center,
        text: emoji,
        color: Colors.white,
        fontSize: fontSize,
      ));
      _undoTracker.add(_UndoKind.text);
      _redoTracker.clear();
      _undoneStrokes.clear();
      _undoneAnnotations.clear();
    });
  }

  void _setBrushColor(Color color) {
    if (_kFixedColorTools.contains(_currentPaintTool)) return;
    setState(() => _brushColor = color);
  }

  void _setPaintTool(_PaintTool tool) {
    setState(() {
      _toolBrushes[_currentPaintTool]!
        ..color = _brushColor
        ..sizeRatio = ((_brushWidth - _kMinBrushSize) /
            (_kMaxBrushSize - _kMinBrushSize)).clamp(0.0, 1.0);
      _currentPaintTool = tool;
      final brush = _toolBrushes[tool]!;
      _brushColor = brush.color;
      _brushWidth = _kMinBrushSize + brush.sizeRatio * (_kMaxBrushSize - _kMinBrushSize);
    });
  }

  void _setBrushWidth(double width) {
    setState(() => _brushWidth = width.clamp(_kMinBrushSize, _kMaxBrushSize));
  }

  void _selectAnnotation(int index) {
    setState(() => _selectedAnnotation = index);
  }

  void _moveAnnotation(int index, Offset delta) {
    if (index < 0 || index >= _textAnnotations.length) return;
    setState(() {
      _textAnnotations[index].position += delta;
    });
  }

  void _scaleAnnotation(int index, double scaleDelta) {
    if (index < 0 || index >= _textAnnotations.length) return;
    setState(() {
      final ann = _textAnnotations[index];
      ann.scale = (ann.scale * scaleDelta).clamp(
        _kAnnotationMinScale, _kAnnotationMaxScale,
      );
    });
  }

  void _deleteSelectedAnnotation() {
    if (_selectedAnnotation < 0 || _selectedAnnotation >= _textAnnotations.length) return;
    setState(() {
      _textAnnotations.removeAt(_selectedAnnotation);
      _selectedAnnotation = -1;
    });
  }

  void _editAnnotation(int index) {
    if (index < 0 || index >= _textAnnotations.length) return;
    final ann = _textAnnotations[index];
    _openTextTool(ann.text);
    setState(() {
      _textAnnotations.removeAt(index);
      _selectedAnnotation = -1;
    });
  }

  void _onCanvasZoom(double zoomDelta) {
    setState(() {
      _canvasZoom = (_canvasZoom * zoomDelta).clamp(_kMinCanvasZoom, _kMaxCanvasZoom);
    });
  }

  Future<void> _done() async {
    if (_saving) return;
    if (_editorMode == _EditorMode.paint) {
      _paintDone();
      return;
    }
    setState(() => _saving = true);
    try {
      final croppedFile = await _applyCropAndExport();
      if (widget.onDone != null) {
        await widget.onDone!(croppedFile);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<File> _applyCropAndExport() async {
    if (_image == null) return widget.imageFile;

    final cropState = _cropKey.currentState;
    if (cropState == null) return widget.imageFile;

    final cropRect = cropState._cropRect;
    final displaySize = cropState._displaySize;

    if (displaySize.width <= 0 || displaySize.height <= 0) {
      return widget.imageFile;
    }

    final imgW = _image!.width.toDouble();
    final imgH = _image!.height.toDouble();
    final isSwapped = _rotationDegrees == 90 || _rotationDegrees == 270;
    final effectiveW = isSwapped ? imgH : imgW;
    final effectiveH = isSwapped ? imgW : imgH;
    final scale = math.min(
        displaySize.width / effectiveW, displaySize.height / effectiveH);

    final srcLeft = cropRect.left / scale;
    final srcTop = cropRect.top / scale;
    final srcWidth = cropRect.width / scale;
    final srcHeight = cropRect.height / scale;

    final outW = math.max(1, srcWidth.round());
    final outH = math.max(1, srcHeight.round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );

    canvas.translate(outW / 2.0, outH / 2.0);
    if (_flipped) canvas.scale(-1, 1);
    canvas.rotate(_rotationDegrees * math.pi / 180);

    final dstW = imgW * scale;
    final dstH = imgH * scale;
    final offsetX = -(cropRect.left + cropRect.width / 2);
    final offsetY = -(cropRect.top + cropRect.height / 2);

    canvas.drawImageRect(
      _image!,
      Rect.fromLTWH(0, 0, imgW, imgH),
      Rect.fromLTWH(
        offsetX + (displaySize.width - dstW) / 2,
        offsetY + (displaySize.height - dstH) / 2,
        dstW,
        dstH,
      ),
      Paint()..filterQuality = FilterQuality.high,
    );

    final exportOffset = Offset(
      -cropRect.left - cropRect.width / 2 + outW / 2,
      -cropRect.top - cropRect.height / 2 + outH / 2,
    );

    for (final stroke in _paintStrokes) {
      if (stroke.tool == _PaintTool.blur) continue;
      if (stroke.tool == _PaintTool.eraser) continue;
      _CropPainter.drawSingleStroke(canvas, stroke, exportOffset);
    }

    final hasEraser = _paintStrokes.any((s) => s.tool == _PaintTool.eraser);
    if (hasEraser) {
      canvas.saveLayer(null, Paint());
      for (final stroke in _paintStrokes.where(
        (s) => s.tool != _PaintTool.blur && s.tool != _PaintTool.eraser,
      )) {
        _CropPainter.drawSingleStroke(canvas, stroke, exportOffset);
      }
      for (final stroke in _paintStrokes.where((s) => s.tool == _PaintTool.eraser)) {
        final erasePaint = Paint()
          ..blendMode = BlendMode.clear
          ..strokeWidth = stroke.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        final path = Path();
        final pts = stroke.points.map((p) => p + exportOffset).toList();
        for (int i = 0; i < pts.length; i++) {
          if (i == 0) path.moveTo(pts[i].dx, pts[i].dy);
          else path.lineTo(pts[i].dx, pts[i].dy);
        }
        canvas.drawPath(path, erasePaint);
      }
      canvas.restore();
    }

    for (final ann in _textAnnotations) {
      final effectiveFontSize = ann.fontSize * ann.scale;
      final tp = TextPainter(
        text: TextSpan(
          text: ann.text,
          style: TextStyle(
            fontSize: effectiveFontSize,
            color: ann.color,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(
        ann.position.dx - tp.width / 2 + exportOffset.dx,
        ann.position.dy - tp.height / 2 + exportOffset.dy,
      ));
    }

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(outW, outH);
    picture.dispose();

    final byteData =
        await outImage.toByteData(format: ui.ImageByteFormat.png);
    outImage.dispose();
    if (byteData == null) return widget.imageFile;

    final outFile = File(
      '/tmp/crop_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await outFile.writeAsBytes(Uint8List.view(byteData.buffer));
    return outFile;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dimColor = isDark ? _kDimColorDark : _kDimColorLight;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final ctrl = HardwareKeyboard.instance.isControlPressed;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        final key = event.logicalKey;
        String combo;
        if (key == LogicalKeyboardKey.escape) {
          combo = 'escape';
        } else if (key == LogicalKeyboardKey.enter) {
          combo = 'enter';
        } else if (ctrl && shift && key == LogicalKeyboardKey.keyZ) {
          combo = 'ctrl+shift+z';
        } else if (ctrl && key == LogicalKeyboardKey.keyZ) {
          combo = 'ctrl+z';
        } else if (ctrl && key == LogicalKeyboardKey.keyY) {
          combo = 'ctrl+y';
        } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
          if (_editorMode == _EditorMode.paint && _selectedAnnotation >= 0) {
            _deleteSelectedAnnotation();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        } else {
          return KeyEventResult.ignored;
        }
        return _handleKeyCombo(combo)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _BlurredBackground(dimColor: dimColor),

            Padding(
              padding: _kContentMargins,
              child: Column(
                children: [
                  if (widget.aboutText != null)
                    _FadeWrap(
                      visible: _editorMode == _EditorMode.transform,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          widget.aboutText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: _kCaptionFg,
                          ),
                        ),
                      ),
                    ),

                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        : _image == null
                            ? const Center(
                                child: Text(
                                  'Failed to load image',
                                  style: TextStyle(color: _kCaptionFg),
                                ),
                              )
                            : _ImageCropArea(
                                key: _cropKey,
                                image: _image!,
                                shape: widget.shape,
                                rotationDegrees: _rotationDegrees,
                                flipped: _flipped,
                                enforceRatio: _enforceRatio,
                                forumCornerMultiplier: _forumCornerMultiplier,
                                paintStrokes: _paintStrokes,
                                textAnnotations: _textAnnotations,
                                brushColor: _brushColor,
                                brushWidth: _brushWidth,
                                currentPaintTool: _currentPaintTool,
                                isPaintMode: _editorMode == _EditorMode.paint,
                                onStrokeAdded: _addPaintStroke,
                                selectedAnnotation: _selectedAnnotation,
                                onAnnotationSelected: _selectAnnotation,
                                onAnnotationMoved: _moveAnnotation,
                                onAnnotationScaled: _scaleAnnotation,
                                onAnnotationDoubleTap: _editAnnotation,
                                canvasZoom: _canvasZoom,
                                canvasOffset: _canvasOffset,
                                onZoomChanged: _onCanvasZoom,
                              ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: 0,
              top: 0,
              bottom: _kContentMarginBottom,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _VerticalBrushSizeControl(
                  value: _brushWidth,
                  onChanged: _setBrushWidth,
                  visible: _editorMode == _EditorMode.paint,
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _kContentMarginBottom,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ClipRect(
                    child: AnimatedSlide(
                      duration: _kTransitionDuration,
                      curve: Curves.easeOutCubic,
                      offset: _editorMode == _EditorMode.paint
                          ? Offset.zero
                          : const Offset(0, 1),
                      child: AnimatedAlign(
                        duration: _kTransitionDuration,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        heightFactor:
                            _editorMode == _EditorMode.paint ? 1.0 : 0.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedCrossFade(
                              firstChild: _ColorPaletteRow(
                                colors: _kPaletteColors,
                                selected: _brushColor,
                                onChanged: _setBrushColor,
                                onCustomColor: () async {
                                  final c = await showColorPickerBox(
                                    context: context,
                                    initialColor: _brushColor,
                                    title: 'Choose Color',
                                  );
                                  if (c != null) _setBrushColor(c);
                                },
                              ),
                              secondChild: const SizedBox(height: 0),
                              crossFadeState: _paletteVisible
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              duration: _kColorButtonSwitchDuration,
                            ),
                            const SizedBox(height: 4),
                            _PaintToolRow(
                              currentTool: _currentPaintTool,
                              brushColor: _brushColor,
                              isFixedColorTool: _kFixedColorTools.contains(_currentPaintTool),
                              paletteVisible: _paletteVisible,
                              onToolChanged: _setPaintTool,
                              onTogglePalette: () {
                                setState(() => _paletteVisible = !_paletteVisible);
                              },
                            ),
                            const SizedBox(height: 4),
                            _PaintTopBar(
                              canUndo: _canUndo,
                              canRedo: _canRedo,
                              onUndo: _paintUndo,
                              onRedo: _paintRedo,
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ClipRect(
                    child: AnimatedSwitcher(
                      duration: _kTransitionDuration,
                      transitionBuilder: (child, animation) {
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          )),
                          child: child,
                        );
                      },
                      child: _ControlBar(
                        key: ValueKey(_editorMode),
                        doneLabel: widget.doneLabel,
                        saving: _saving,
                        flipped: _flipped,
                        isProfilePhoto: _isProfilePhoto,
                        editorMode: _editorMode,
                        selectedAspect: _selectedAspect,
                        onCancel: _cancel,
                        onDone: _done,
                        onFlip: toggleFlip,
                        onRotate: rotate,
                        onTogglePaintMode: _togglePaintMode,
                        onAspectChanged: _setAspect,
                        shape: widget.shape,
                        cornerLevel: _currentCornerLevel,
                        onCornerLevelChanged: widget.shape == PhotoCropShape.roundedRect
                            ? _setCornerLevel
                            : null,
                        onTextTool: _openTextTool,
                        onStickersTool: _openStickersTool,
                        currentPaintTool: _currentPaintTool,
                        onPaintToolChanged: _setPaintTool,
                      ),
                    ),
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

class _BlurredBackground extends StatefulWidget {
  final Color dimColor;

  const _BlurredBackground({required this.dimColor});

  @override
  State<_BlurredBackground> createState() => _BlurredBackgroundState();
}

class _BlurredBackgroundState extends State<_BlurredBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  Size _lastSize = Size.zero;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: _kBgCrossFadeDuration,
      value: 0.0,
    );
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onSizeChanged(Size newSize) {
    if (_lastSize == Size.zero) {
      _lastSize = newSize;
      return;
    }
    if (newSize == _lastSize) return;
    _lastSize = newSize;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_kBgDebouncefast, () {
      if (!mounted) return;
      _fadeCtrl.value = 0.6;
      _fadeCtrl.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _onSizeChanged(size));
          return AnimatedBuilder(
            animation: _fadeCtrl,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeCtrl.value,
                child: child,
              );
            },
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: _kBlurSigma,
                sigmaY: _kBlurSigma,
              ),
              child: ColoredBox(
                color: widget.dimColor,
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ImageCropArea extends StatefulWidget {
  final ui.Image image;
  final PhotoCropShape shape;
  final int rotationDegrees;
  final bool flipped;
  final double? enforceRatio;
  final double forumCornerMultiplier;
  final List<_PaintStroke> paintStrokes;
  final List<_TextAnnotation> textAnnotations;
  final Color brushColor;
  final double brushWidth;
  final _PaintTool currentPaintTool;
  final bool isPaintMode;
  final ValueChanged<_PaintStroke>? onStrokeAdded;
  final int selectedAnnotation;
  final ValueChanged<int>? onAnnotationSelected;
  final void Function(int index, Offset delta)? onAnnotationMoved;
  final void Function(int index, double scaleDelta)? onAnnotationScaled;
  final ValueChanged<int>? onAnnotationDoubleTap;
  final double canvasZoom;
  final Offset canvasOffset;
  final ValueChanged<double>? onZoomChanged;

  const _ImageCropArea({
    super.key,
    required this.image,
    required this.shape,
    required this.rotationDegrees,
    required this.flipped,
    this.enforceRatio,
    this.forumCornerMultiplier = _kForumRadiusMultiplier,
    this.paintStrokes = const [],
    this.textAnnotations = const [],
    this.brushColor = const Color(0xFFEA2739),
    this.brushWidth = 4.0,
    this.currentPaintTool = _PaintTool.pen,
    this.isPaintMode = false,
    this.onStrokeAdded,
    this.selectedAnnotation = -1,
    this.onAnnotationSelected,
    this.onAnnotationMoved,
    this.onAnnotationScaled,
    this.onAnnotationDoubleTap,
    this.canvasZoom = 1.0,
    this.canvasOffset = Offset.zero,
    this.onZoomChanged,
  });

  @override
  State<_ImageCropArea> createState() => _ImageCropAreaState();
}

class _ImageCropAreaState extends State<_ImageCropArea>
    with SingleTickerProviderStateMixin {
  Rect _cropRect = Rect.zero;
  Size _displaySize = Size.zero;
  bool _needsInitCrop = true;

  _Edge _activeEdge = _Edge.none;
  Offset _dragStart = Offset.zero;
  Rect _cropAtDragStart = Rect.zero;
  MouseCursor _cursor = SystemMouseCursors.basic;

  late AnimationController _gridController;

  List<Offset>? _currentStrokePoints;
  bool _draggingAnnotation = false;
  Offset _lastDragPos = Offset.zero;
  DateTime? _lastTapTime;
  int _lastTapAnnotation = -1;

  bool get _hasLockedRatio => widget.enforceRatio != null;

  @override
  void initState() {
    super.initState();
    _gridController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _gridController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ImageCropArea old) {
    super.didUpdateWidget(old);
    if (old.rotationDegrees != widget.rotationDegrees ||
        old.flipped != widget.flipped ||
        old.image != widget.image) {
      _needsInitCrop = true;
    }
    if (old.enforceRatio != widget.enforceRatio && !_needsInitCrop) {
      _applyNewRatio();
    }
  }

  void _applyNewRatio() {
    if (widget.enforceRatio == null) return;
    final ratio = widget.enforceRatio!;
    final center = _cropRect.center;
    final currentArea = _cropRect.width * _cropRect.height;
    var newW = math.sqrt(currentArea * ratio);
    var newH = newW / ratio;
    if (newW > _displaySize.width) { newW = _displaySize.width; newH = newW / ratio; }
    if (newH > _displaySize.height) { newH = _displaySize.height; newW = newH * ratio; }
    if (newW < _kCropMinSize) newW = _kCropMinSize;
    if (newH < _kCropMinSize) newH = _kCropMinSize;
    setState(() {
      _cropRect = Rect.fromCenter(center: center, width: newW, height: newH);
      _cropRect = _clampCrop(_cropRect, _displaySize);
    });
  }

  void _initCrop(Size displaySize) {
    _displaySize = displaySize;
    if (_hasLockedRatio) {
      final ratio = widget.enforceRatio!;
      double w, h;
      if (ratio >= 1) {
        w = math.min(displaySize.width, displaySize.height * ratio);
        h = w / ratio;
      } else {
        h = math.min(displaySize.height, displaySize.width / ratio);
        w = h * ratio;
      }
      if (w > displaySize.width) { w = displaySize.width; h = w / ratio; }
      if (h > displaySize.height) { h = displaySize.height; w = h * ratio; }
      _cropRect = Rect.fromCenter(
        center: Offset(displaySize.width / 2, displaySize.height / 2),
        width: w,
        height: h,
      );
    } else {
      _cropRect = Offset.zero & displaySize;
    }
    _needsInitCrop = false;
  }

  void _rescaleCrop(Size newSize) {
    if (_displaySize.width <= 0 || _displaySize.height <= 0) return;
    final sx = newSize.width / _displaySize.width;
    final sy = newSize.height / _displaySize.height;
    if (_hasLockedRatio) {
      final ratio = widget.enforceRatio!;
      final s = math.min(sx, sy);
      var w = _cropRect.width * s;
      var h = w / ratio;
      if (h > newSize.height) { h = newSize.height; w = h * ratio; }
      _cropRect = Rect.fromCenter(
        center: Offset(_cropRect.center.dx * sx, _cropRect.center.dy * sy),
        width: w,
        height: h,
      );
    } else {
      _cropRect = Rect.fromLTRB(
        _cropRect.left * sx, _cropRect.top * sy,
        _cropRect.right * sx, _cropRect.bottom * sy,
      );
    }
    _cropRect = _clampCrop(_cropRect, newSize);
    _displaySize = newSize;
  }

  Rect _clampCrop(Rect crop, Size bounds) {
    var l = crop.left, t = crop.top, r = crop.right, b = crop.bottom;
    if (l < 0) { r -= l; l = 0; }
    if (t < 0) { b -= t; t = 0; }
    if (r > bounds.width) { l -= r - bounds.width; r = bounds.width; }
    if (b > bounds.height) { t -= b - bounds.height; b = bounds.height; }
    return Rect.fromLTRB(
      l.clamp(0.0, bounds.width),
      t.clamp(0.0, bounds.height),
      r.clamp(0.0, bounds.width),
      b.clamp(0.0, bounds.height),
    );
  }

  _Edge _hitTest(Offset pos) {
    final c = _cropRect;
    const hs = _kCropHandleSize * 1.5;

    if ((pos - c.topLeft).distance < hs) return _Edge.topLeft;
    if ((pos - c.topRight).distance < hs) return _Edge.topRight;
    if ((pos - c.bottomLeft).distance < hs) return _Edge.bottomLeft;
    if ((pos - c.bottomRight).distance < hs) return _Edge.bottomRight;

    if (!_hasLockedRatio) {
      if (pos.dy >= c.top - hs && pos.dy <= c.top + hs &&
          pos.dx > c.left + hs && pos.dx < c.right - hs) return _Edge.top;
      if (pos.dy >= c.bottom - hs && pos.dy <= c.bottom + hs &&
          pos.dx > c.left + hs && pos.dx < c.right - hs) return _Edge.bottom;
      if (pos.dx >= c.left - hs && pos.dx <= c.left + hs &&
          pos.dy > c.top + hs && pos.dy < c.bottom - hs) return _Edge.left;
      if (pos.dx >= c.right - hs && pos.dx <= c.right + hs &&
          pos.dy > c.top + hs && pos.dy < c.bottom - hs) return _Edge.right;
    }

    if (c.contains(pos)) return _Edge.move;
    return _Edge.none;
  }

  MouseCursor _cursorForEdge(_Edge edge) {
    switch (edge) {
      case _Edge.topLeft:
      case _Edge.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _Edge.topRight:
      case _Edge.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case _Edge.top:
      case _Edge.bottom:
        return SystemMouseCursors.resizeUpDown;
      case _Edge.left:
      case _Edge.right:
        return SystemMouseCursors.resizeLeftRight;
      case _Edge.move:
        return SystemMouseCursors.move;
      case _Edge.none:
        return SystemMouseCursors.basic;
    }
  }

  int _hitTestAnnotations(Offset pos) {
    for (int i = widget.textAnnotations.length - 1; i >= 0; i--) {
      final ann = widget.textAnnotations[i];
      final tp = TextPainter(
        text: TextSpan(
          text: ann.text,
          style: TextStyle(fontSize: ann.fontSize * ann.scale, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
        center: ann.position,
        width: tp.width + _kAnnotationHitSlop,
        height: tp.height + _kAnnotationHitSlop,
      );
      if (rect.contains(pos)) return i;
    }
    return -1;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.isPaintMode) {
      final hitIdx = _hitTestAnnotations(event.localPosition);
      if (hitIdx >= 0) {
        final now = DateTime.now();
        if (_lastTapAnnotation == hitIdx &&
            _lastTapTime != null &&
            now.difference(_lastTapTime!).inMilliseconds < 400) {
          widget.onAnnotationDoubleTap?.call(hitIdx);
          _lastTapTime = null;
          _lastTapAnnotation = -1;
          return;
        }
        _lastTapTime = now;
        _lastTapAnnotation = hitIdx;
        _draggingAnnotation = true;
        _lastDragPos = event.localPosition;
        widget.onAnnotationSelected?.call(hitIdx);
        return;
      }
      widget.onAnnotationSelected?.call(-1);
      setState(() {
        _currentStrokePoints = [event.localPosition];
      });
      return;
    }
    final edge = _hitTest(event.localPosition);
    if (edge == _Edge.none) return;
    setState(() {
      _activeEdge = edge;
      _dragStart = event.localPosition;
      _cropAtDragStart = _cropRect;
      _cursor = _cursorForEdge(edge);
    });
    _gridController.value = 1.0;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (widget.isPaintMode) {
      if (_draggingAnnotation && widget.selectedAnnotation >= 0) {
        final delta = event.localPosition - _lastDragPos;
        _lastDragPos = event.localPosition;
        widget.onAnnotationMoved?.call(widget.selectedAnnotation, delta);
        return;
      }
      if (_currentStrokePoints != null) {
        setState(() {
          _currentStrokePoints!.add(event.localPosition);
        });
      }
      return;
    }
    if (_activeEdge == _Edge.none) {
      final edge = _hitTest(event.localPosition);
      final c = _cursorForEdge(edge);
      if (c != _cursor) setState(() => _cursor = c);
      return;
    }
    final delta = event.localPosition - _dragStart;
    setState(() {
      if (_activeEdge == _Edge.move) {
        _performMove(delta);
      } else {
        _performResize(delta);
      }
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (widget.isPaintMode) {
      if (_draggingAnnotation) {
        _draggingAnnotation = false;
        return;
      }
      if (_currentStrokePoints != null && _currentStrokePoints!.isNotEmpty) {
        final tool = widget.currentPaintTool;
        final effectiveWidth = tool == _PaintTool.marker
            ? widget.brushWidth * _kMarkerSizeMultiplier
            : widget.brushWidth;
        final effectiveColor = tool == _PaintTool.marker
            ? widget.brushColor.withValues(alpha: _kMarkerOpacity)
            : (tool == _PaintTool.eraser || tool == _PaintTool.blur)
                ? const Color(0x00000000)
                : widget.brushColor;
        widget.onStrokeAdded?.call(_PaintStroke(
          points: List.from(_currentStrokePoints!),
          color: effectiveColor,
          width: effectiveWidth,
          tool: tool,
        ));
      }
      setState(() => _currentStrokePoints = null);
      return;
    }
    if (_activeEdge == _Edge.none) return;
    setState(() => _activeEdge = _Edge.none);
    _gridController.reverse();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!widget.isPaintMode) return;
    if (event is PointerScrollEvent) {
      if (widget.selectedAnnotation >= 0) {
        final scale = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
        widget.onAnnotationScaled?.call(widget.selectedAnnotation, scale);
      } else {
        final shift = HardwareKeyboard.instance.isShiftPressed;
        final step = shift ? _kCanvasZoomStepFine : _kCanvasZoomStep;
        final factor = event.scrollDelta.dy < 0 ? step : 1.0 / step;
        widget.onZoomChanged?.call(factor);
      }
    }
  }

  void _performMove(Offset delta) {
    var moved = _cropAtDragStart.shift(delta);
    final bw = _displaySize.width;
    final bh = _displaySize.height;
    double dx = 0, dy = 0;
    if (moved.left < 0) dx = -moved.left;
    if (moved.top < 0) dy = -moved.top;
    if (moved.right > bw) dx = bw - moved.right;
    if (moved.bottom > bh) dy = bh - moved.bottom;
    _cropRect = moved.shift(Offset(dx, dy));
  }

  void _performResize(Offset delta) {
    final bw = _displaySize.width;
    final bh = _displaySize.height;
    var l = _cropAtDragStart.left;
    var t = _cropAtDragStart.top;
    var r = _cropAtDragStart.right;
    var b = _cropAtDragStart.bottom;

    if (_hasLockedRatio) {
      final ratio = widget.enforceRatio!;
      final origW = _cropAtDragStart.width;
      final origH = _cropAtDragStart.height;

      double dxSign, dySign;
      switch (_activeEdge) {
        case _Edge.topLeft:     dxSign = -1; dySign = -1;
        case _Edge.topRight:    dxSign =  1; dySign = -1;
        case _Edge.bottomLeft:  dxSign = -1; dySign =  1;
        case _Edge.bottomRight: dxSign =  1; dySign =  1;
        default: return;
      }

      final scaleFactor =
          (dxSign * delta.dx / origW + dySign * delta.dy / origH) / 2;
      final newW = origW * (1 + scaleFactor);
      final newH = newW / ratio;

      if (newW < _kCropMinSize || newH < _kCropMinSize) return;

      switch (_activeEdge) {
        case _Edge.topLeft:     l = r - newW; t = b - newH;
        case _Edge.topRight:    r = l + newW; t = b - newH;
        case _Edge.bottomLeft:  l = r - newW; b = t + newH;
        case _Edge.bottomRight: r = l + newW; b = t + newH;
        default: break;
      }

      if (l < 0) { l = 0; r = newW; }
      if (t < 0) { t = 0; b = newH; }
      if (r > bw) { r = bw; l = bw - newW; }
      if (b > bh) { b = bh; t = bh - newH; }
      if (l < 0 || t < 0) return;
    } else {
      switch (_activeEdge) {
        case _Edge.topLeft:    l += delta.dx; t += delta.dy;
        case _Edge.topRight:   r += delta.dx; t += delta.dy;
        case _Edge.bottomLeft: l += delta.dx; b += delta.dy;
        case _Edge.bottomRight: r += delta.dx; b += delta.dy;
        case _Edge.top:    t += delta.dy;
        case _Edge.bottom: b += delta.dy;
        case _Edge.left:   l += delta.dx;
        case _Edge.right:  r += delta.dx;
        default: return;
      }
      if (r - l < _kCropMinSize) {
        if (l != _cropAtDragStart.left) l = r - _kCropMinSize;
        else r = l + _kCropMinSize;
      }
      if (b - t < _kCropMinSize) {
        if (t != _cropAtDragStart.top) t = b - _kCropMinSize;
        else b = t + _kCropMinSize;
      }
      l = l.clamp(0.0, bw - _kCropMinSize);
      t = t.clamp(0.0, bh - _kCropMinSize);
      r = r.clamp(_kCropMinSize, bw);
      b = b.clamp(_kCropMinSize, bh);
    }

    _cropRect = Rect.fromLTRB(l, t, r, b);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;
        final imgW = widget.image.width.toDouble();
        final imgH = widget.image.height.toDouble();

        final isSwapped =
            widget.rotationDegrees == 90 || widget.rotationDegrees == 270;
        final effectiveW = isSwapped ? imgH : imgW;
        final effectiveH = isSwapped ? imgW : imgH;

        final scale = math.min(availW / effectiveW, availH / effectiveH);
        final displayW = effectiveW * scale;
        final displayH = effectiveH * scale;
        final displaySize = Size(displayW, displayH);

        if (_needsInitCrop) {
          _initCrop(displaySize);
        } else if (_displaySize != displaySize) {
          _rescaleCrop(displaySize);
        }

        return Center(
          child: MouseRegion(
            cursor: _cursor,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerSignal: _onPointerSignal,
              child: AnimatedBuilder(
                animation: _gridController,
                builder: (context, _) {
                  return CustomPaint(
                    size: displaySize,
                    painter: _CropPainter(
                      image: widget.image,
                      rotationDegrees: widget.rotationDegrees,
                      flipped: widget.flipped,
                      scale: scale,
                      cropRect: _cropRect,
                      shape: widget.shape,
                      gridOpacity: _gridController.value,
                      forumCornerMultiplier: widget.forumCornerMultiplier,
                      paintStrokes: widget.paintStrokes,
                      textAnnotations: widget.textAnnotations,
                      currentStroke: _currentStrokePoints != null
                          ? _PaintStroke(
                              points: _currentStrokePoints!,
                              color: widget.currentPaintTool == _PaintTool.marker
                                  ? widget.brushColor.withValues(alpha: _kMarkerOpacity)
                                  : (widget.currentPaintTool == _PaintTool.eraser ||
                                     widget.currentPaintTool == _PaintTool.blur)
                                      ? const Color(0x00000000)
                                      : widget.brushColor,
                              width: widget.currentPaintTool == _PaintTool.marker
                                  ? widget.brushWidth * _kMarkerSizeMultiplier
                                  : widget.brushWidth,
                              tool: widget.currentPaintTool,
                            )
                          : null,
                      isPaintMode: widget.isPaintMode,
                      selectedAnnotation: widget.selectedAnnotation,
                      canvasZoom: widget.canvasZoom,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final int rotationDegrees;
  final bool flipped;
  final double scale;
  final Rect cropRect;
  final PhotoCropShape shape;
  final double gridOpacity;
  final double forumCornerMultiplier;
  final List<_PaintStroke> paintStrokes;
  final List<_TextAnnotation> textAnnotations;
  final _PaintStroke? currentStroke;
  final bool isPaintMode;
  final int selectedAnnotation;
  final double canvasZoom;

  _CropPainter({
    required this.image,
    required this.rotationDegrees,
    required this.flipped,
    required this.scale,
    required this.cropRect,
    required this.shape,
    required this.gridOpacity,
    this.forumCornerMultiplier = _kForumRadiusMultiplier,
    this.paintStrokes = const [],
    this.textAnnotations = const [],
    this.currentStroke,
    this.isPaintMode = false,
    this.selectedAnnotation = -1,
    this.canvasZoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isPaintMode && canvasZoom != 1.0) {
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(canvasZoom);
      canvas.translate(-size.width / 2, -size.height / 2);
    }

    _drawImage(canvas, size);
    _drawBlurStrokes(canvas, size);
    _drawRegularStrokes(canvas);
    _drawTextAnnotations(canvas);

    if (isPaintMode && canvasZoom != 1.0) {
      canvas.restore();
    }

    if (!isPaintMode) {
      _drawOverlay(canvas, size);
      _drawBorder(canvas);
      _drawCorners(canvas);
      if (gridOpacity > 0) _drawGrid(canvas);
    }
  }

  static void drawSingleStroke(Canvas canvas, _PaintStroke stroke, [Offset offset = Offset.zero]) {
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final pts = offset == Offset.zero
        ? stroke.points
        : stroke.points.map((p) => p + offset).toList();

    if (pts.length == 1) {
      canvas.drawCircle(pts[0], stroke.width / 2,
          paint..style = PaintingStyle.fill);
      return;
    }

    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      if (i == 0) {
        path.moveTo(pts[i].dx, pts[i].dy);
      } else {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }
    canvas.drawPath(path, paint);

    if (stroke.tool == _PaintTool.arrow && pts.length >= 2) {
      final tip = pts.last;
      final prev = pts[pts.length - 2];
      final dir = tip - prev;
      final dist = dir.distance;
      final headLen = stroke.width * _kArrowHeadLengthFactor;
      final minDist = stroke.width * _kArrowHeadMinDistFactor;
      if (dist >= minDist) {
        final norm = dir / dist;
        final angleDeg = _kArrowHeadAngleDeg;
        final angleRad = angleDeg * math.pi / 180;
        final cosA = math.cos(angleRad);
        final sinA = math.sin(angleRad);
        final leftDx = -norm.dx * cosA + norm.dy * sinA;
        final leftDy = -norm.dx * sinA - norm.dy * cosA;
        final rightDx = -norm.dx * cosA - norm.dy * sinA;
        final rightDy = norm.dx * sinA - norm.dy * cosA;
        final arrowPaint = Paint()
          ..color = stroke.color
          ..strokeWidth = stroke.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          tip,
          tip + Offset(leftDx * headLen, leftDy * headLen),
          arrowPaint,
        );
        canvas.drawLine(
          tip,
          tip + Offset(rightDx * headLen, rightDy * headLen),
          arrowPaint,
        );
      }
    }
  }

  void _drawBlurStrokes(Canvas canvas, Size size) {
    final allStrokes = [...paintStrokes, if (currentStroke != null) currentStroke!];
    final blurStrokes = allStrokes.where((s) => s.tool == _PaintTool.blur).toList();
    if (blurStrokes.isEmpty) return;

    final bounds = Offset.zero & size;
    for (final stroke in blurStrokes) {
      if (stroke.points.isEmpty) continue;
      canvas.saveLayer(bounds, Paint());
      final maskPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < stroke.points.length; i++) {
        if (i == 0) path.moveTo(stroke.points[i].dx, stroke.points[i].dy);
        else path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points[0], stroke.width / 2,
            maskPaint..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(path, maskPaint);
      }
      canvas.saveLayer(bounds, Paint()
        ..blendMode = BlendMode.srcIn
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: stroke.width * _kBlurSigmaFactor,
          sigmaY: stroke.width * _kBlurSigmaFactor,
        ));
      _drawImage(canvas, size);
      canvas.restore();
      canvas.restore();
    }
  }

  void _drawRegularStrokes(Canvas canvas) {
    final allStrokes = [...paintStrokes, if (currentStroke != null) currentStroke!];
    final hasEraser = allStrokes.any((s) => s.tool == _PaintTool.eraser);
    final regularStrokes = allStrokes.where(
      (s) => s.tool != _PaintTool.blur && s.tool != _PaintTool.eraser,
    ).toList();
    final eraserStrokes = allStrokes.where((s) => s.tool == _PaintTool.eraser).toList();

    if (hasEraser) {
      canvas.saveLayer(null, Paint());
      for (final stroke in regularStrokes) {
        drawSingleStroke(canvas, stroke);
      }
      for (final stroke in eraserStrokes) {
        _drawEraserStroke(canvas, stroke);
      }
      canvas.restore();
    } else {
      for (final stroke in regularStrokes) {
        drawSingleStroke(canvas, stroke);
      }
    }
  }

  void _drawEraserStroke(Canvas canvas, _PaintStroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..blendMode = BlendMode.clear
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < stroke.points.length; i++) {
      if (i == 0) {
        path.moveTo(stroke.points[i].dx, stroke.points[i].dy);
      } else {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
    }
    canvas.drawPath(path, paint);
    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points[0], stroke.width / 2,
          paint..style = PaintingStyle.fill);
    }
  }

  void _drawTextAnnotations(Canvas canvas) {
    for (int i = 0; i < textAnnotations.length; i++) {
      final ann = textAnnotations[i];
      final effectiveFontSize = ann.fontSize * ann.scale;
      final tp = TextPainter(
        text: TextSpan(
          text: ann.text,
          style: TextStyle(
            fontSize: effectiveFontSize,
            color: ann.color,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final origin = Offset(
        ann.position.dx - tp.width / 2,
        ann.position.dy - tp.height / 2,
      );
      tp.paint(canvas, origin);

      if (i == selectedAnnotation && isPaintMode) {
        final selRect = Rect.fromLTWH(
          origin.dx - 4, origin.dy - 4,
          tp.width + 8, tp.height + 8,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(selRect, const Radius.circular(4)),
          Paint()
            ..color = const Color(0x66FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        final corners = [selRect.topLeft, selRect.topRight,
                         selRect.bottomLeft, selRect.bottomRight];
        for (final c in corners) {
          canvas.drawCircle(c, _kAnnotationHandleSize / 2, Paint()
            ..color = const Color(0xCCFFFFFF)
            ..style = PaintingStyle.fill);
        }
      }
    }
  }

  void _drawImage(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (flipped) canvas.scale(-1, 1);
    canvas.rotate(rotationDegrees * math.pi / 180);

    final dstW = imgW * scale;
    final dstH = imgH * scale;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, imgW, imgH),
      Rect.fromLTWH(-dstW / 2, -dstH / 2, dstW, dstH),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  Path _cropPath() {
    switch (shape) {
      case PhotoCropShape.ellipse:
        return Path()..addOval(cropRect);
      case PhotoCropShape.roundedRect:
        final r = math.min(cropRect.width, cropRect.height) *
            forumCornerMultiplier;
        return Path()
          ..addRRect(RRect.fromRectAndRadius(cropRect, Radius.circular(r)));
      case PhotoCropShape.rect:
        return Path()..addRect(cropRect);
    }
  }

  void _drawOverlay(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final overlay = Path.combine(PathOperation.difference, full, _cropPath());
    canvas.drawPath(overlay, Paint()..color = _kCropFadeBg);
  }

  void _drawBorder(Canvas canvas) {
    final paint = Paint()
      ..color = _kCropPointFg
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kCropBorderWidth
      ..strokeJoin = StrokeJoin.miter
      ..strokeCap = StrokeCap.square;

    switch (shape) {
      case PhotoCropShape.ellipse:
        canvas.drawOval(cropRect, paint);
      case PhotoCropShape.roundedRect:
        final r = math.min(cropRect.width, cropRect.height) *
            forumCornerMultiplier;
        canvas.drawRRect(
            RRect.fromRectAndRadius(cropRect, Radius.circular(r)), paint);
      case PhotoCropShape.rect:
        canvas.drawRect(cropRect, paint);
    }
  }

  void _drawCorners(Canvas canvas) {
    final paint = Paint()
      ..color = _kCropPointFg
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kCropCornerWidth
      ..strokeCap = StrokeCap.square;

    final len = math.min(
      _kCropHandleSize * 2,
      math.min(cropRect.width, cropRect.height) / 2,
    );

    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * len, 0), paint);
      canvas.drawLine(o, o + Offset(0, dy * len), paint);
    }

    corner(cropRect.topLeft, 1, 1);
    corner(cropRect.topRight, -1, 1);
    corner(cropRect.bottomLeft, 1, -1);
    corner(cropRect.bottomRight, -1, -1);
  }

  void _drawGrid(Canvas canvas) {
    final alpha = (255 * gridOpacity).round();
    final paint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 255)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.save();
    canvas.clipPath(_cropPath());

    final thirdW = cropRect.width / 3;
    final thirdH = cropRect.height / 3;
    for (int i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(cropRect.left + thirdW * i, cropRect.top),
        Offset(cropRect.left + thirdW * i, cropRect.bottom),
        paint,
      );
      canvas.drawLine(
        Offset(cropRect.left, cropRect.top + thirdH * i),
        Offset(cropRect.right, cropRect.top + thirdH * i),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.rotationDegrees != rotationDegrees ||
      old.flipped != flipped ||
      old.scale != scale ||
      old.cropRect != cropRect ||
      old.shape != shape ||
      old.gridOpacity != gridOpacity ||
      old.forumCornerMultiplier != forumCornerMultiplier ||
      old.paintStrokes != paintStrokes ||
      old.textAnnotations != textAnnotations ||
      old.currentStroke != currentStroke ||
      old.isPaintMode != isPaintMode ||
      old.selectedAnnotation != selectedAnnotation ||
      old.canvasZoom != canvasZoom;
}

class _ControlBar extends StatelessWidget {
  final String doneLabel;
  final bool saving;
  final bool flipped;
  final bool isProfilePhoto;
  final _EditorMode editorMode;
  final _CropAspect selectedAspect;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onFlip;
  final VoidCallback onRotate;
  final VoidCallback onTogglePaintMode;
  final ValueChanged<_CropAspect> onAspectChanged;
  final PhotoCropShape shape;
  final _CornerLevel cornerLevel;
  final ValueChanged<_CornerLevel>? onCornerLevelChanged;
  final VoidCallback? onTextTool;
  final VoidCallback? onStickersTool;
  final _PaintTool currentPaintTool;
  final ValueChanged<_PaintTool>? onPaintToolChanged;

  const _ControlBar({
    super.key,
    required this.doneLabel,
    required this.saving,
    required this.flipped,
    required this.isProfilePhoto,
    required this.editorMode,
    required this.selectedAspect,
    required this.onCancel,
    required this.onDone,
    required this.onFlip,
    required this.onRotate,
    required this.onTogglePaintMode,
    required this.onAspectChanged,
    this.shape = PhotoCropShape.ellipse,
    this.cornerLevel = _CornerLevel.large,
    this.onCornerLevelChanged,
    this.onTextTool,
    this.onStickersTool,
    this.currentPaintTool = _PaintTool.pen,
    this.onPaintToolChanged,
  });

  Widget _buildSavingIndicator() => const SizedBox(
    width: 48,
    height: 48,
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: _kDoneLinkFg),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final confirmLabel =
        editorMode == _EditorMode.paint ? 'Done' : doneLabel;

    final List<Widget> children;
    if (editorMode == _EditorMode.paint) {
      children = [
        _EdgeButton(label: 'Cancel', color: _kCancelFg, onPressed: onCancel),
        _BarIconButton(
          icon: Icons.brush_outlined,
          state: _IconState.active,
          onPressed: () {},
          tooltip: 'Paint',
        ),
        _BarIconButton(
          icon: Icons.emoji_emotions_outlined,
          state: _IconState.idle,
          onPressed: onStickersTool ?? () {},
          tooltip: 'Stickers',
        ),
        _BarIconButton(
          icon: Icons.text_fields,
          state: _IconState.idle,
          onPressed: onTextTool ?? () {},
          tooltip: 'Text',
        ),
        saving
            ? _buildSavingIndicator()
            : _EdgeButton(
                label: confirmLabel,
                color: _kDoneLinkFg,
                onPressed: onDone,
              ),
      ];
    } else {
      children = [
        _EdgeButton(label: 'Cancel', color: _kCancelFg, onPressed: onCancel),
        _BarIconButton(
          icon: Icons.flip,
          state: flipped ? _IconState.active : _IconState.idle,
          onPressed: onFlip,
          tooltip: 'Flip',
        ),
        _BarIconButton(
          icon: Icons.rotate_90_degrees_ccw_outlined,
          state: _IconState.idle,
          onPressed: onRotate,
          tooltip: 'Rotate',
        ),
        _BarIconButton(
          icon: Icons.brush_outlined,
          state: _IconState.idle,
          onPressed: onTogglePaintMode,
          tooltip: 'Paint',
        ),
        if (!isProfilePhoto)
          _AspectRatioButton(
            selected: selectedAspect,
            onChanged: onAspectChanged,
          ),
        if (shape == PhotoCropShape.roundedRect && onCornerLevelChanged != null)
          _CornersButton(
            selected: cornerLevel,
            onChanged: onCornerLevelChanged!,
          ),
        saving
            ? _buildSavingIndicator()
            : _EdgeButton(
                label: confirmLabel,
                color: _kDoneLinkFg,
                onPressed: onDone,
              ),
      ];
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kControlBarWidth),
          child: Container(
            height: _kControlBarHeight,
            decoration: BoxDecoration(
              color: _kControlBarPillBg,
              borderRadius: BorderRadius.circular(_kControlBarHeight / 2),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _EdgeButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: _kCancelBg,
        padding: const EdgeInsets.all(4),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(label),
    );
  }
}

class _BarIconButton extends StatefulWidget {
  final IconData icon;
  final _IconState state;
  final VoidCallback onPressed;
  final String tooltip;

  const _BarIconButton({
    required this.icon,
    required this.state,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  State<_BarIconButton> createState() => _BarIconButtonState();
}

class _BarIconButtonState extends State<_BarIconButton> {
  bool _hovering = false;

  Color get _iconColor {
    if (widget.state == _IconState.inactive) return _kIconFgInactive;
    if (widget.state == _IconState.active) return _kIconFgActive;
    return _hovering ? _kCancelFg : _kIconFgIdle;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          onPressed:
              widget.state == _IconState.inactive ? null : widget.onPressed,
          tooltip: widget.tooltip,
          icon: Icon(widget.icon, color: _iconColor, size: 24),
        ),
      ),
    );
  }
}

class _AspectRatioButton extends StatefulWidget {
  final _CropAspect selected;
  final ValueChanged<_CropAspect> onChanged;

  const _AspectRatioButton({
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_AspectRatioButton> createState() => _AspectRatioButtonState();
}

class _AspectRatioButtonState extends State<_AspectRatioButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        width: 48,
        height: 48,
        child: PopupMenuButton<_CropAspect>(
          onSelected: widget.onChanged,
          offset: const Offset(0, -300),
          color: const Color(0xFF2B2B2B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          itemBuilder: (_) => _CropAspect.values
              .map((a) => PopupMenuItem<_CropAspect>(
                    value: a,
                    height: 40,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: a == widget.selected
                              ? const Icon(Icons.check,
                                  size: 18, color: _kDoneLinkFg)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(a.label,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ))
              .toList(),
          child: Center(
            child: Icon(
              Icons.crop,
              color: _hovering ? _kCancelFg : _kIconFgIdle,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _CornersButton extends StatefulWidget {
  final _CornerLevel selected;
  final ValueChanged<_CornerLevel> onChanged;

  const _CornersButton({
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_CornersButton> createState() => _CornersButtonState();
}

class _CornersButtonState extends State<_CornersButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        width: 48,
        height: 48,
        child: PopupMenuButton<_CornerLevel>(
          onSelected: widget.onChanged,
          offset: const Offset(0, -250),
          color: const Color(0xFF2B2B2B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          itemBuilder: (_) => [
            const PopupMenuItem<_CornerLevel>(
              enabled: false,
              height: 50,
              child: Text(
                'Set the radius of the corners for the forum-style photo.',
                style: TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
              ),
            ),
            const PopupMenuDivider(height: 1),
            ..._CornerLevel.values.map((level) => PopupMenuItem<_CornerLevel>(
              value: level,
              height: 40,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: level == widget.selected
                        ? const Icon(Icons.check,
                            size: 18, color: _kDoneLinkFg)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(level.label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                ],
              ),
            )),
          ],
          child: Center(
            child: Icon(
              Icons.rounded_corner,
              color: _hovering ? _kCancelFg : _kIconFgIdle,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeWrap extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _FadeWrap({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedOpacity(
        duration: _kTransitionDuration,
        opacity: visible ? 1.0 : 0.0,
        child: AnimatedAlign(
          duration: _kTransitionDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          heightFactor: visible ? 1.0 : 0.0,
          child: child,
        ),
      ),
    );
  }
}

class _PaintTopBar extends StatelessWidget {
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  const _PaintTopBar({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kControlBarWidth),
      child: SizedBox(
        height: _kControlBarHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BarIconButton(
              icon: Icons.undo,
              state: canUndo ? _IconState.idle : _IconState.inactive,
              onPressed: onUndo,
              tooltip: 'Undo',
            ),
            const Spacer(),
            _BarIconButton(
              icon: Icons.redo,
              state: canRedo ? _IconState.idle : _IconState.inactive,
              onPressed: onRedo,
              tooltip: 'Redo',
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPaletteRow extends StatelessWidget {
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onChanged;
  final VoidCallback? onCustomColor;

  const _ColorPaletteRow({
    required this.colors,
    required this.selected,
    required this.onChanged,
    this.onCustomColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kPaletteItemSize + 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < colors.length; i++) ...[
            if (i > 0) SizedBox(width: _kPaletteGap),
            GestureDetector(
              onTap: () => onChanged(colors[i]),
              child: Container(
                width: _kPaletteItemSize,
                height: _kPaletteItemSize,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: _colorsMatch(colors[i], selected)
                      ? Border.all(color: Colors.white, width: 2)
                      : (colors[i].r == 0 && colors[i].g == 0 && colors[i].b == 0)
                          ? Border.all(
                              color: const Color(0x66FFFFFF), width: 1)
                          : null,
                ),
              ),
            ),
          ],
          if (onCustomColor != null) ...[
            SizedBox(width: _kPaletteGap),
            GestureDetector(
              onTap: onCustomColor,
              child: Container(
                width: _kPlusCircleSize,
                height: _kPlusCircleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x99FFFFFF),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.add, size: 14, color: Color(0x99FFFFFF)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static bool _colorsMatch(Color a, Color b) {
    return (a.r - b.r).abs() < 0.01 &&
        (a.g - b.g).abs() < 0.01 &&
        (a.b - b.b).abs() < 0.01;
  }
}

class _PaintToolRow extends StatelessWidget {
  final _PaintTool currentTool;
  final Color brushColor;
  final bool isFixedColorTool;
  final bool paletteVisible;
  final ValueChanged<_PaintTool> onToolChanged;
  final VoidCallback onTogglePalette;

  const _PaintToolRow({
    required this.currentTool,
    required this.brushColor,
    required this.isFixedColorTool,
    required this.paletteVisible,
    required this.onToolChanged,
    required this.onTogglePalette,
  });

  static const _tools = [
    (_PaintTool.pen, Icons.edit, 'Pen'),
    (_PaintTool.arrow, Icons.arrow_right_alt, 'Arrow'),
    (_PaintTool.marker, Icons.format_paint, 'Marker'),
    (_PaintTool.blur, Icons.blur_on, 'Blur'),
    (_PaintTool.eraser, Icons.auto_fix_high, 'Eraser'),
  ];

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kControlBarWidth),
      child: SizedBox(
        height: _kToolButtonSize + 4,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _RainbowColorButton(
              currentColor: brushColor,
              isActive: paletteVisible,
              onTap: onTogglePalette,
            ),
            const SizedBox(width: 8),
            ..._tools.map((t) {
              final isSelected = currentTool == t.$1;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _ToolButton(
                  icon: t.$2,
                  label: t.$3,
                  isSelected: isSelected,
                  onTap: () => onToolChanged(t.$1),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectCtrl;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _selectCtrl = AnimationController(
      vsync: this,
      duration: _kToolSelectDuration,
      value: widget.isSelected ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_ToolButton old) {
    super.didUpdateWidget(old);
    if (old.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        _selectCtrl.forward();
      } else {
        _selectCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _selectCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _selectCtrl,
          builder: (context, _) {
            final t = Curves.easeOutCirc.transform(_selectCtrl.value);
            return Container(
              width: _kToolButtonSize,
              height: _kToolButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  Colors.transparent,
                  const Color(0x33FFFFFF),
                  t,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: Color.lerp(
                  _hovering ? _kCancelFg : _kIconFgIdle,
                  _kIconFgActive,
                  t,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RainbowColorButton extends StatelessWidget {
  final Color currentColor;
  final bool isActive;
  final VoidCallback onTap;

  const _RainbowColorButton({
    required this.currentColor,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: _kColorButtonSwitchDuration,
        width: _kRainbowRingSize,
        height: _kRainbowRingSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? Colors.white : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: CustomPaint(
          size: const Size(_kRainbowRingSize - 3, _kRainbowRingSize - 3),
          painter: _RainbowRingPainter(
            innerColor: currentColor,
            ringWidth: _kRainbowRingBorder,
          ),
        ),
      ),
    );
  }
}

class _RainbowRingPainter extends CustomPainter {
  final Color innerColor;
  final double ringWidth;

  _RainbowRingPainter({required this.innerColor, required this.ringWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = math.min(size.width, size.height) / 2;
    final innerR = outerR - ringWidth;

    final rainbowPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0.26,
        colors: const [
          Color(0xFFEB4B4B),
          Color(0xFFFFA500),
          Color(0xFFFFFF00),
          Color(0xFF8FCE00),
          Color(0xFF00FFFF),
          Color(0xFF6080E4),
          Color(0xFFEE82EE),
          Color(0xFFEB4B4B),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerR))
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;

    canvas.drawCircle(center, outerR - ringWidth / 2, rainbowPaint);

    canvas.drawCircle(center, innerR - 1.5, Paint()
      ..color = innerColor
      ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_RainbowRingPainter old) =>
      old.innerColor != innerColor || old.ringWidth != ringWidth;
}

class _EditorStickerPicker extends StatefulWidget {
  final ValueChanged<String> onSelected;

  const _EditorStickerPicker({required this.onSelected});

  @override
  State<_EditorStickerPicker> createState() => _EditorStickerPickerState();
}

class _EditorStickerPickerState extends State<_EditorStickerPicker> {
  int _tab = 0;
  List<StickerPackSummary>? _packs;
  bool _loadingPacks = false;
  int _selectedPack = -1;

  static const _emojiGroups = [
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

  static List<int> _decodeThumb(String b64) {
    try { return base64Decode(b64); } catch (_) { return []; }
  }

  void _loadPacks() {
    if (_loadingPacks || _packs != null) return;
    _loadingPacks = true;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId == null) {
      setState(() => _loadingPacks = false);
      return;
    }
    engine.getInstalledStickerPacks(accountId).then((packs) {
      if (mounted) setState(() { _packs = packs; _loadingPacks = false; });
    }).catchError((_) {
      if (mounted) setState(() { _packs = []; _loadingPacks = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: Column(
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 12),
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
                  onTap: () => setState(() => _tab = 0),
                  child: Text('Emoji', style: TextStyle(
                    color: _tab == 0 ? const Color(0xFF4DB8FF) : Colors.white38,
                    fontSize: 14, fontWeight: FontWeight.w600,
                  )),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () {
                    setState(() => _tab = 1);
                    _loadPacks();
                  },
                  child: Text('Stickers', style: TextStyle(
                    color: _tab == 1 ? const Color(0xFF4DB8FF) : Colors.white38,
                    fontSize: 14, fontWeight: FontWeight.w600,
                  )),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _tab == 0 ? _buildEmojiGrid() : _buildStickerGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiGrid() {
    final allEmoji = _emojiGroups.expand((g) => g).toList();
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8, childAspectRatio: 1,
      ),
      itemCount: allEmoji.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => widget.onSelected(allEmoji[i]),
        child: Center(child: Text(allEmoji[i], style: const TextStyle(fontSize: 28))),
      ),
    );
  }

  Widget _buildStickerGrid() {
    if (_loadingPacks) {
      return const Center(child: CircularProgressIndicator(color: Colors.white38));
    }
    if (_packs == null || _packs!.isEmpty) {
      return const Center(child: Text('No sticker packs installed',
        style: TextStyle(color: Colors.white38)));
    }
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _packs!.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final sel = i == _selectedPack;
              return GestureDetector(
                onTap: () => setState(() => _selectedPack = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0x33FFFFFF) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _packs![i].title,
                    style: TextStyle(
                      color: sel ? Colors.white : Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _selectedPack < 0
              ? const Center(child: Text('Select a pack',
                  style: TextStyle(color: Colors.white38, fontSize: 13)))
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5, childAspectRatio: 1,
                  ),
                  itemCount: _packs![_selectedPack].stickers.length,
                  itemBuilder: (_, i) {
                    final sticker = _packs![_selectedPack].stickers[i];
                    return GestureDetector(
                      onTap: () => widget.onSelected(sticker.emoji),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: sticker.thumbB64.isNotEmpty
                            ? Image.memory(
                                Uint8List.fromList(
                                  _decodeThumb(sticker.thumbB64),
                                ),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(sticker.emoji,
                                    style: const TextStyle(fontSize: 32)),
                                ),
                              )
                            : Center(child: Text(sticker.emoji,
                                style: const TextStyle(fontSize: 32))),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _VerticalBrushSizeControl extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final bool visible;

  const _VerticalBrushSizeControl({
    required this.value,
    required this.onChanged,
    this.visible = false,
  });

  @override
  State<_VerticalBrushSizeControl> createState() =>
      _VerticalBrushSizeControlState();
}

class _VerticalBrushSizeControlState extends State<_VerticalBrushSizeControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandController;
  bool _hovered = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: _kBrushSizeControlAnimDuration,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _setExpanded(bool expanded) {
    if (expanded) {
      _expandController.forward();
    } else if (!_dragging) {
      _expandController.reverse();
    }
  }

  double _ratioFromValue(double v) {
    return ((v - _kMinBrushSize) / (_kMaxBrushSize - _kMinBrushSize))
        .clamp(0.0, 1.0);
  }

  double _valueFromRatio(double ratio) {
    return _kMinBrushSize + ratio * (_kMaxBrushSize - _kMinBrushSize);
  }

  double get _sliderTop =>
      _kBrushSizeControlHitPadding + _kBrushSizeControlExpandedTopWidth / 2;
  double get _sliderBottom =>
      _kBrushSizeControlHeight -
      _kBrushSizeControlHitPadding -
      _kBrushSizeControlExpandedBottomWidth / 2;
  double get _sliderRange => _sliderBottom - _sliderTop;

  double _yFromRatio(double ratio) {
    return _sliderTop + (1.0 - ratio) * _sliderRange;
  }

  void _updateFromY(double localY) {
    final ratio =
        1.0 - ((localY - _sliderTop) / _sliderRange).clamp(0.0, 1.0);
    widget.onChanged(_valueFromRatio(ratio));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: SizedBox(
          width: _kBrushSizeControlHitPadding * 2 +
              _kBrushSizeControlExpandShift +
              _kBrushSizeControlExpandedTopWidth,
          height: _kBrushSizeControlHeight,
          child: MouseRegion(
            onEnter: (_) {
              _hovered = true;
              _setExpanded(true);
            },
            onExit: (_) {
              _hovered = false;
              _setExpanded(false);
            },
            child: GestureDetector(
              onVerticalDragStart: (d) {
                _dragging = true;
                _setExpanded(true);
                _updateFromY(d.localPosition.dy);
              },
              onVerticalDragUpdate: (d) => _updateFromY(d.localPosition.dy),
              onVerticalDragEnd: (_) {
                _dragging = false;
                if (!_hovered) _setExpanded(false);
              },
              onVerticalDragCancel: () {
                _dragging = false;
                if (!_hovered) _setExpanded(false);
              },
              child: AnimatedBuilder(
                animation: _expandController,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(
                      _kBrushSizeControlHitPadding * 2 +
                          _kBrushSizeControlExpandShift +
                          _kBrushSizeControlExpandedTopWidth,
                      _kBrushSizeControlHeight,
                    ),
                    painter: _BrushSizeControlPainter(
                      expandProgress: Curves.easeOutCirc
                          .transform(_expandController.value),
                      ratio: _ratioFromValue(widget.value),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrushSizeControlPainter extends CustomPainter {
  final double expandProgress;
  final double ratio;

  _BrushSizeControlPainter({
    required this.expandProgress,
    required this.ratio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = _kBrushSizeControlHitPadding +
        _kBrushSizeControlExpandShift * expandProgress +
        _kBrushSizeControlExpandedTopWidth / 2;

    final topY = _kBrushSizeControlHitPadding +
        _kBrushSizeControlExpandedTopWidth / 2;
    final bottomY = _kBrushSizeControlHeight -
        _kBrushSizeControlHitPadding -
        _kBrushSizeControlExpandedBottomWidth / 2;

    final collapsedHalf = _kBrushSizeControlCollapsedWidth / 2;
    final expandedTopHalf = _kBrushSizeControlExpandedTopWidth / 2;
    final expandedBottomHalf = _kBrushSizeControlExpandedBottomWidth / 2;

    final topRadius =
        collapsedHalf + (expandedTopHalf - collapsedHalf) * expandProgress;
    final bottomRadius =
        collapsedHalf + (expandedBottomHalf - collapsedHalf) * expandProgress;

    final alpha = (96 + (176 - 96) * expandProgress).round();
    final trackPaint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 255)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.addArc(
      Rect.fromCircle(center: Offset(centerX, topY), radius: topRadius),
      math.pi,
      math.pi,
    );
    path.lineTo(centerX + bottomRadius, bottomY);
    path.addArc(
      Rect.fromCircle(center: Offset(centerX, bottomY), radius: bottomRadius),
      0,
      math.pi,
    );
    path.lineTo(centerX - topRadius, topY);
    path.close();
    canvas.drawPath(path, trackPaint);

    final handleY = topY + (1.0 - ratio) * (bottomY - topY);
    final handleRadius = 4.0 + ratio * 6.0;
    final handlePaint = Paint()
      ..color = const Color(0xF4FFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, handleY), handleRadius, handlePaint);
  }

  @override
  bool shouldRepaint(_BrushSizeControlPainter old) =>
      expandProgress != old.expandProgress || ratio != old.ratio;
}

// ── §39.9 Sticker/Emoji Avatar Builder ──

const List<List<Color>> _kGradientPresets = [
  [Color(0xFF6C93FF), Color(0xFF976FFF)],
  [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
  [Color(0xFF3EC1D3), Color(0xFF1ABC9C)],
  [Color(0xFFFCA311), Color(0xFFE76F51)],
  [Color(0xFFA855F7), Color(0xFFEC4899)],
  [Color(0xFF14B8A6), Color(0xFF0EA5E9)],
  [Color(0xFFF97316), Color(0xFFFBBF24)],
  [Color(0xFFEF4444), Color(0xFFDB2777)],
];

const List<String> _kSuggestedEmoji = [
  '😀', '😎', '🥰', '🤗', '🤩', '😇', '🤠', '🥳',
  '🦊', '🐱', '🐶', '🐼', '🦁', '🐸', '🐵', '🦄',
  '🌸', '🌺', '🌻', '🍀', '⭐', '🌙', '☀️', '🌈',
  '❤️', '💜', '💙', '💚', '🧡', '💛', '🖤', '🤍',
];

const double _kPreviewSize = 200;
const double _kGradientPickerSize = 40;
const double _kEmojiGridCellSize = 48;
const Duration _kSuggestedCycleDuration = Duration(milliseconds: 1500);

class EmojiAvatarBuilder extends StatefulWidget {
  final PhotoCropShape shape;
  final Future<void> Function(File renderedFile)? onDone;

  const EmojiAvatarBuilder({
    super.key,
    this.shape = PhotoCropShape.ellipse,
    this.onDone,
  });

  static Future<void> open(
    BuildContext context, {
    PhotoCropShape shape = PhotoCropShape.ellipse,
    Future<void> Function(File renderedFile)? onDone,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        barrierDismissible: false,
        transitionDuration: _kTransitionDuration,
        reverseTransitionDuration: _kTransitionDuration,
        pageBuilder: (context, animation, secondaryAnimation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: EmojiAvatarBuilder(
              shape: shape,
              onDone: onDone,
            ),
          );
        },
      ),
    );
  }

  @override
  State<EmojiAvatarBuilder> createState() => _EmojiAvatarBuilderState();
}

class _EmojiAvatarBuilderState extends State<EmojiAvatarBuilder> {
  int _gradientIndex = 0;
  String _selectedEmoji = _kSuggestedEmoji[0];
  int _suggestedIndex = 0;
  Timer? _cycleTimer;
  bool _saving = false;
  bool _userPicked = false;

  @override
  void initState() {
    super.initState();
    _startCycleTimer();
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    super.dispose();
  }

  void _startCycleTimer() {
    _cycleTimer?.cancel();
    _cycleTimer = Timer.periodic(_kSuggestedCycleDuration, (_) {
      if (_userPicked) return;
      setState(() {
        _suggestedIndex = (_suggestedIndex + 1) % _kSuggestedEmoji.length;
        _selectedEmoji = _kSuggestedEmoji[_suggestedIndex];
      });
    });
  }

  void _selectEmoji(String emoji) {
    setState(() {
      _selectedEmoji = emoji;
      _userPicked = true;
    });
    _cycleTimer?.cancel();
  }

  void _selectGradient(int index) {
    setState(() => _gradientIndex = index);
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final file = await _renderToFile();
      if (widget.onDone != null) {
        await widget.onDone!(file);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<File> _renderToFile() async {
    const size = _kProfilePhotoSize;
    const sizeD = size * 1.0;
    final rect = Rect.fromLTWH(0, 0, sizeD, sizeD);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);

    final gradient = _kGradientPresets[_gradientIndex];
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, sizeD),
        gradient,
      );

    if (widget.shape == PhotoCropShape.ellipse) {
      canvas.drawOval(rect, paint);
    } else if (widget.shape == PhotoCropShape.roundedRect) {
      final r = sizeD * _kForumRadiusMultiplier;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r)),
        paint,
      );
    } else {
      canvas.drawRect(rect, paint);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: _selectedEmoji,
        style: TextStyle(fontSize: sizeD * 0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        (size - tp.width) / 2,
        (size - tp.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) throw Exception('Failed to render emoji avatar');

    final file = File(
      '/tmp/emoji_avatar_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(Uint8List.view(byteData.buffer));
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dimColor = isDark ? _kDimColorDark : _kDimColorLight;
    final gradient = _kGradientPresets[_gradientIndex];
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 640;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _save();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _BlurredBackground(dimColor: dimColor),

            SafeArea(
              child: Column(
                children: [
                  // Back button
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton(
                        onPressed: _cancel,
                        icon: const Icon(Icons.arrow_back, color: _kCaptionFg),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Live circular preview
                  _EmojiPreview(
                    gradient: gradient,
                    emoji: _selectedEmoji,
                    shape: widget.shape,
                    size: isMobile ? _kPreviewSize * 0.8 : _kPreviewSize,
                  ),

                  const SizedBox(height: 24),

                  // Gradient color picker
                  _GradientPicker(
                    presets: _kGradientPresets,
                    selectedIndex: _gradientIndex,
                    onSelect: _selectGradient,
                  ),

                  const SizedBox(height: 24),

                  // Emoji selector grid
                  Expanded(
                    child: _EmojiGrid(
                      selectedEmoji: _selectedEmoji,
                      onSelect: _selectEmoji,
                      isMobile: isMobile,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _kControlBarHeight + 20,
              child: Center(
                child: SizedBox(
                  width: _kControlBarWidth,
                  height: _kControlBarHeight,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _cancel,
                        style: TextButton.styleFrom(
                          foregroundColor: _kCancelFg,
                          backgroundColor: _kCancelBg,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      if (_saving)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kDoneLinkFg,
                          ),
                        )
                      else
                        TextButton(
                          onPressed: _save,
                          style: TextButton.styleFrom(
                            foregroundColor: _kDoneLinkFg,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: const Text('Save'),
                        ),
                    ],
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

class _EmojiPreview extends StatelessWidget {
  final List<Color> gradient;
  final String emoji;
  final PhotoCropShape shape;
  final double size;

  const _EmojiPreview({
    required this.gradient,
    required this.emoji,
    required this.shape,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradient,
        ),
        shape: shape == PhotoCropShape.ellipse
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius: shape == PhotoCropShape.roundedRect
            ? BorderRadius.circular(size * _kForumRadiusMultiplier)
            : shape == PhotoCropShape.rect
                ? BorderRadius.zero
                : null,
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          emoji,
          key: ValueKey(emoji),
          style: TextStyle(fontSize: size * 0.5),
        ),
      ),
    );
  }
}

class _GradientPicker extends StatelessWidget {
  final List<List<Color>> presets;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _GradientPicker({
    required this.presets,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kGradientPickerSize + 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < presets.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _kGradientPickerSize,
                height: _kGradientPickerSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: presets[i],
                  ),
                  shape: BoxShape.circle,
                  border: i == selectedIndex
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmojiGrid extends StatelessWidget {
  final String selectedEmoji;
  final ValueChanged<String> onSelect;
  final bool isMobile;

  const _EmojiGrid({
    required this.selectedEmoji,
    required this.onSelect,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final crossCount = isMobile ? 6 : 8;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 68),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          childAspectRatio: 1,
        ),
        itemCount: _kSuggestedEmoji.length,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          final emoji = _kSuggestedEmoji[index];
          final isSelected = emoji == selectedEmoji;
          return GestureDetector(
            onTap: () => onSelect(emoji),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              decoration: BoxDecoration(
                color:
                    isSelected ? Colors.white24 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: isMobile ? 24 : 28,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
