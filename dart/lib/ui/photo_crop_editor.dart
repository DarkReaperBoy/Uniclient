import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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

const Duration _kTransitionDuration = Duration(milliseconds: 200);

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

class PhotoCropEditor extends StatefulWidget {
  final File imageFile;
  final PhotoCropShape shape;
  final String? aboutText;
  final String doneLabel;
  final Future<void> Function(File croppedFile)? onDone;

  const PhotoCropEditor({
    super.key,
    required this.imageFile,
    this.shape = PhotoCropShape.ellipse,
    this.aboutText,
    this.doneLabel = 'Set Photo',
    this.onDone,
  });

  static Future<void> open(
    BuildContext context, {
    required File imageFile,
    PhotoCropShape shape = PhotoCropShape.ellipse,
    String? aboutText,
    String doneLabel = 'Set Photo',
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
              doneLabel: doneLabel,
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

  bool get _isProfilePhoto => widget.shape != PhotoCropShape.rect;

  @override
  void initState() {
    super.initState();
    _loadImage();
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
    Navigator.of(context).pop();
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
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _done();
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

            Padding(
              padding: _kContentMargins,
              child: Column(
                children: [
                  if (widget.aboutText != null) ...[
                    Padding(
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
                  ],

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
              child: _ControlBar(
                doneLabel: widget.doneLabel,
                saving: _saving,
                flipped: _flipped,
                onCancel: _cancel,
                onDone: _done,
                onFlip: toggleFlip,
                onRotate: rotate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredBackground extends StatelessWidget {
  final Color dimColor;

  const _BlurredBackground({required this.dimColor});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: _kBlurSigma,
          sigmaY: _kBlurSigma,
        ),
        child: ColoredBox(
          color: dimColor,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ImageCropArea extends StatefulWidget {
  final ui.Image image;
  final PhotoCropShape shape;
  final int rotationDegrees;
  final bool flipped;

  const _ImageCropArea({
    required this.image,
    required this.shape,
    required this.rotationDegrees,
    required this.flipped,
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

  bool get _keepAspectRatio => widget.shape != PhotoCropShape.rect;

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
  }

  void _initCrop(Size displaySize) {
    _displaySize = displaySize;
    if (_keepAspectRatio) {
      final side = math.min(displaySize.width, displaySize.height);
      _cropRect = Rect.fromCenter(
        center: Offset(displaySize.width / 2, displaySize.height / 2),
        width: side,
        height: side,
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
    if (_keepAspectRatio) {
      final s = math.min(sx, sy);
      final side = _cropRect.width * s;
      _cropRect = Rect.fromCenter(
        center: Offset(_cropRect.center.dx * sx, _cropRect.center.dy * sy),
        width: side,
        height: side,
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

    if (!_keepAspectRatio) {
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

    if (_keepAspectRatio) {
      final origSide = _cropAtDragStart.width;
      double ds;
      switch (_activeEdge) {
        case _Edge.topLeft:
          ds = (-delta.dx - delta.dy) / 2;
          l = r - (origSide + ds);
          t = b - (origSide + ds);
        case _Edge.topRight:
          ds = (delta.dx - delta.dy) / 2;
          r = l + (origSide + ds);
          t = b - (origSide + ds);
        case _Edge.bottomLeft:
          ds = (-delta.dx + delta.dy) / 2;
          l = r - (origSide + ds);
          b = t + (origSide + ds);
        case _Edge.bottomRight:
          ds = (delta.dx + delta.dy) / 2;
          r = l + (origSide + ds);
          b = t + (origSide + ds);
        default:
          return;
      }
      final side = r - l;
      if (side < _kCropMinSize) return;
      if (l < 0) { l = 0; r = side; }
      if (t < 0) { t = 0; b = side; }
      if (r > bw) { r = bw; l = bw - side; }
      if (b > bh) { b = bh; t = bh - side; }
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
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onFlip;
  final VoidCallback onRotate;

  const _ControlBar({
    required this.doneLabel,
    required this.saving,
    required this.flipped,
    required this.onCancel,
    required this.onDone,
    required this.onFlip,
    required this.onRotate,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: _kControlBarWidth,
        height: _kControlBarHeight,
        child: Row(
          children: [
            TextButton(
              onPressed: onCancel,
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
            _BarIconButton(
              icon: Icons.flip,
              active: flipped,
              onPressed: onFlip,
              tooltip: 'Flip',
            ),
            const SizedBox(width: 6),
            _BarIconButton(
              icon: Icons.rotate_right,
              active: false,
              onPressed: onRotate,
              tooltip: 'Rotate',
            ),
            const Spacer(),
            if (saving)
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
                onPressed: onDone,
                style: TextButton.styleFrom(
                  foregroundColor: _kDoneLinkFg,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Text(doneLabel),
              ),
          ],
        ),
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final String tooltip;

  const _BarIconButton({
    required this.icon,
    required this.active,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(
          icon,
          color: active ? _kDoneLinkFg : _kCancelFg,
          size: 24,
        ),
      ),
    );
  }
}
