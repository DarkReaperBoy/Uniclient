import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

enum _Edge {
  none,
  topLeft, topRight, bottomLeft, bottomRight,
  top, bottom, left, right,
  move,
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
  original, square, ratio3x2, ratio16x9, ratio9x16, free;

  String get label => switch (this) {
    original => 'Original',
    square => 'Square',
    ratio3x2 => '3:2',
    ratio16x9 => '16:9',
    ratio9x16 => '9:16',
    free => 'Free',
  };

  double? ratioValue(double imageRatio) => switch (this) {
    original => imageRatio,
    square => 1.0,
    ratio3x2 => 3.0 / 2.0,
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
      setState(() => _editorMode = _EditorMode.transform);
      _focusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop();
  }

  void _paintUndo() {
    // Will be connected when paint strokes are implemented.
  }

  void _paintRedo() {
    // Will be connected when paint strokes are implemented.
  }

  void _togglePaintMode() {
    setState(() {
      _editorMode = _editorMode == _EditorMode.transform
          ? _EditorMode.paint
          : _EditorMode.transform;
    });
    _focusNode.requestFocus();
  }

  void _setAspect(_CropAspect aspect) {
    setState(() => _selectedAspect = aspect);
  }

  Future<void> _done() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (widget.onDone != null) {
        await widget.onDone!(widget.imageFile);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
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
                  ClipRect(
                    child: AnimatedSlide(
                      duration: _kTransitionDuration,
                      curve: Curves.easeOutCubic,
                      offset: _editorMode == _EditorMode.paint
                          ? Offset.zero
                          : const Offset(0, -1),
                      child: AnimatedAlign(
                        duration: _kTransitionDuration,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        heightFactor:
                            _editorMode == _EditorMode.paint ? 1.0 : 0.0,
                        child: const _PaintTopBar(),
                      ),
                    ),
                  ),
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
                                image: _image!,
                                shape: widget.shape,
                                rotationDegrees: _rotationDegrees,
                                flipped: _flipped,
                                enforceRatio: _enforceRatio,
                              ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _kContentMarginBottom,
              child: ClipRect(
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

  const _ImageCropArea({
    required this.image,
    required this.shape,
    required this.rotationDegrees,
    required this.flipped,
    this.enforceRatio,
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

  void _onPointerDown(PointerDownEvent event) {
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
    if (_activeEdge == _Edge.none) return;
    setState(() => _activeEdge = _Edge.none);
    _gridController.reverse();
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

  _CropPainter({
    required this.image,
    required this.rotationDegrees,
    required this.flipped,
    required this.scale,
    required this.cropRect,
    required this.shape,
    required this.gridOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawImage(canvas, size);
    _drawOverlay(canvas, size);
    _drawBorder(canvas);
    _drawCorners(canvas);
    if (gridOpacity > 0) _drawGrid(canvas);
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
            _kForumRadiusMultiplier;
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
            _kForumRadiusMultiplier;
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
      old.gridOpacity != gridOpacity;
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
          icon: Icons.brush,
          state: _IconState.active,
          onPressed: onTogglePaintMode,
          tooltip: 'Paint',
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
          child: SizedBox(
            height: _kControlBarHeight,
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
  const _PaintTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kControlBarWidth),
        child: SizedBox(
          height: _kControlBarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BarIconButton(
                icon: Icons.undo,
                state: _IconState.inactive,
                onPressed: () {},
                tooltip: 'Undo',
              ),
              const SizedBox(width: 6),
              _BarIconButton(
                icon: Icons.redo,
                state: _IconState.inactive,
                onPressed: () {},
                tooltip: 'Redo',
              ),
            ],
          ),
        ),
      ),
    );
  }
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
