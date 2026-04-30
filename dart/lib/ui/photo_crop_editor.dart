import 'dart:async';
import 'dart:io';
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
      setState(() {
        _image = frame.image;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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

  const _ImageCropArea({required this.image, required this.shape});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;
        final imgW = image.width.toDouble();
        final imgH = image.height.toDouble();

        final scale = (imgW / imgH > availW / availH)
            ? availH / imgH
            : availW / imgW;
        final displayW = imgW * scale;
        final displayH = imgH * scale;

        return Center(
          child: SizedBox(
            width: displayW,
            height: displayH,
            child: RawImage(
              image: image,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }
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
