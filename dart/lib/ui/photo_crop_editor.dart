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
                onCancel: _cancel,
                onDone: _done,
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

class _ImageCropArea extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;
        final imgW = image.width.toDouble();
        final imgH = image.height.toDouble();

        final isSwapped = rotationDegrees == 90 || rotationDegrees == 270;
        final effectiveW = isSwapped ? imgH : imgW;
        final effectiveH = isSwapped ? imgW : imgH;

        final scale = math.min(availW / effectiveW, availH / effectiveH);
        final displayW = effectiveW * scale;
        final displayH = effectiveH * scale;

        return Center(
          child: CustomPaint(
            size: Size(displayW, displayH),
            painter: _ImagePainter(
              image: image,
              rotationDegrees: rotationDegrees,
              flipped: flipped,
              scale: scale,
            ),
          ),
        );
      },
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  final int rotationDegrees;
  final bool flipped;
  final double scale;

  _ImagePainter({
    required this.image,
    required this.rotationDegrees,
    required this.flipped,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (flipped) canvas.scale(-1, 1);
    canvas.rotate(rotationDegrees * math.pi / 180);

    final dstW = imgW * scale;
    final dstH = imgH * scale;
    final srcRect = Rect.fromLTWH(0, 0, imgW, imgH);
    final dstRect = Rect.fromLTWH(-dstW / 2, -dstH / 2, dstW, dstH);

    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ImagePainter old) =>
      old.image != image ||
      old.rotationDegrees != rotationDegrees ||
      old.flipped != flipped ||
      old.scale != scale;
}

class _ControlBar extends StatelessWidget {
  final String doneLabel;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  const _ControlBar({
    required this.doneLabel,
    required this.saving,
    required this.onCancel,
    required this.onDone,
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
