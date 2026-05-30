import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../state/app_state.dart';

enum WallpaperType { solid, gradient, pattern, image }

class WallpaperData {
  final WallpaperType type;
  final List<Color> backgroundColors;
  final int patternIntensity;
  final int gradientRotation;
  final bool blurred;
  final Uint8List? imageBytes;
  final Uint8List? patternBytes;
  final bool tiled;

  const WallpaperData({
    this.type = WallpaperType.solid,
    this.backgroundColors = const [],
    this.patternIntensity = 40,
    this.gradientRotation = 0,
    this.blurred = false,
    this.imageBytes,
    this.patternBytes,
    this.tiled = false,
  });

  static const WallpaperData none = WallpaperData();

  double get patternOpacity => patternIntensity.abs() / 100.0;

  bool get isPattern => type == WallpaperType.pattern;
  bool get isGradient => type == WallpaperType.gradient;
  bool get isImage => type == WallpaperType.image;
  bool get isSolid => type == WallpaperType.solid;

  /// Effective gradient rotation used for rendering, mirroring AyuGram's
  /// `WallPaper::gradientRotation()` (data/data_wall_paper.cpp:260-263):
  /// "In case of complex gradients rotation value is dynamic." — for 3+ color
  /// gradients the stored rotation is ignored and 0 is returned. The raw
  /// [gradientRotation] is kept intact for storage/share-URL round-tripping,
  /// exactly as AyuGram keeps `_rotation` raw and applies this rule only in the
  /// accessor.
  int get effectiveGradientRotation =>
      backgroundColors.length < 3 ? gradientRotation : 0;

  static WallpaperData fromColors(List<Color> colors) {
    if (colors.isEmpty) return none;
    if (colors.length == 1) {
      return WallpaperData(
        type: WallpaperType.solid,
        backgroundColors: colors,
      );
    }
    return WallpaperData(
      type: WallpaperType.gradient,
      backgroundColors: colors,
    );
  }

  static WallpaperData fromImage(Uint8List bytes, {bool tiled = false, bool blur = false}) {
    return WallpaperData(
      type: WallpaperType.image,
      imageBytes: bytes,
      tiled: tiled,
      blurred: blur,
    );
  }

  static WallpaperData fromPattern({
    required Uint8List patternBytes,
    required List<Color> backgroundColors,
    int intensity = 40,
    int rotation = 0,
  }) {
    return WallpaperData(
      type: WallpaperType.pattern,
      patternBytes: patternBytes,
      backgroundColors: backgroundColors,
      patternIntensity: intensity,
      gradientRotation: rotation,
    );
  }

  static WallpaperData? fromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) return null;
    if (pathSegments.first != 'bg' || pathSegments.length < 2) return null;

    final params = uri.queryParameters;
    final bgColor = params['bg_color'] ?? '';
    final intensity = int.tryParse(params['intensity'] ?? '') ?? 40;
    final rotation = int.tryParse(params['rotation'] ?? '') ?? 0;
    final blur = params['mode'] == 'blur';

    final colors = <Color>[];
    final separators = RegExp(r'[~\-]');
    for (final hex in bgColor.split(separators)) {
      if (hex.length == 6) {
        final v = int.tryParse('FF$hex', radix: 16);
        if (v != null) colors.add(Color(v));
      }
    }

    if (colors.isEmpty) return null;

    if (colors.length == 1) {
      return WallpaperData(
        type: WallpaperType.solid,
        backgroundColors: colors,
      );
    }

    return WallpaperData(
      type: WallpaperType.gradient,
      backgroundColors: colors,
      patternIntensity: intensity,
      gradientRotation: _snapRotation(rotation),
      blurred: blur,
    );
  }

  String toUrlParams() {
    final parts = <String>[];
    if (backgroundColors.isNotEmpty) {
      final hexes = backgroundColors.map((c) {
        final hex = (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
        return hex;
      }).join('~');
      parts.add('bg_color=$hexes');
    }
    if (patternIntensity != 0) parts.add('intensity=$patternIntensity');
    if (gradientRotation != 0) parts.add('rotation=$gradientRotation');
    if (blurred) parts.add('mode=blur');
    return parts.join('&');
  }

  Color? get averageColor {
    if (backgroundColors.isNotEmpty) {
      int r = 0, g = 0, b = 0;
      for (final c in backgroundColors) {
        r += c.red;
        g += c.green;
        b += c.blue;
      }
      final n = backgroundColors.length;
      return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
    }
    if (imageBytes != null) {
      return computeAverageColor(imageBytes!);
    }
    return null;
  }

  static int _snapRotation(int degrees) {
    final snapped = ((degrees + 22) ~/ 45) * 45;
    return snapped % 360;
  }
}

class WallpaperProvider extends InheritedWidget {
  final WallpaperData wallpaper;

  const WallpaperProvider({
    super.key,
    required this.wallpaper,
    required super.child,
  });

  static WallpaperData of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<WallpaperProvider>();
    return provider?.wallpaper ?? WallpaperData.none;
  }

  @override
  bool updateShouldNotify(WallpaperProvider oldWidget) =>
      !identical(wallpaper, oldWidget.wallpaper);
}

class ChatWallpaper extends StatelessWidget {
  final WallpaperData wallpaper;
  final Color fallbackColor;

  const ChatWallpaper({
    super.key,
    required this.wallpaper,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    return switch (wallpaper.type) {
      WallpaperType.solid => _buildSolid(),
      WallpaperType.gradient => _buildGradient(),
      WallpaperType.image => _buildImage(),
      WallpaperType.pattern => _buildPattern(),
    };
  }

  Widget _buildSolid() {
    final color = wallpaper.backgroundColors.isNotEmpty
        ? wallpaper.backgroundColors.first
        : fallbackColor;
    return ColoredBox(color: color);
  }

  Widget _buildGradient() {
    final colors = wallpaper.backgroundColors;
    if (colors.isEmpty) return ColoredBox(color: fallbackColor);
    if (colors.length == 1) return ColoredBox(color: colors.first);

    if (colors.length == 2) {
      return _TwoColorGradient(
        colors: colors,
        rotation: wallpaper.effectiveGradientRotation,
      );
    }

    return _MultiColorGradient(
      colors: colors,
      rotation: wallpaper.effectiveGradientRotation,
    );
  }

  Widget _buildImage() {
    if (wallpaper.imageBytes == null) return ColoredBox(color: fallbackColor);

    Widget img = Image.memory(
      wallpaper.imageBytes!,
      fit: wallpaper.tiled ? BoxFit.none : BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );

    if (wallpaper.tiled) {
      img = _TiledImage(imageBytes: wallpaper.imageBytes!);
    }

    if (wallpaper.blurred) {
      img = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: img,
      );
    }

    return img;
  }

  Widget _buildPattern() {
    final colors = wallpaper.backgroundColors;
    if (wallpaper.patternBytes == null) {
      if (colors.length >= 2) {
        return _MultiColorGradient(colors: colors, rotation: wallpaper.effectiveGradientRotation);
      } else if (colors.isNotEmpty) {
        return ColoredBox(color: colors.first);
      }
      return ColoredBox(color: fallbackColor);
    }

    return _PatternWallpaper(
      backgroundColors: colors,
      gradientRotation: wallpaper.effectiveGradientRotation,
      patternBytes: wallpaper.patternBytes!,
      intensity: wallpaper.patternIntensity,
      opacity: wallpaper.patternOpacity.clamp(0.0, 1.0),
      fallbackColor: fallbackColor,
    );
  }
}

class _TwoColorGradient extends StatelessWidget {
  final List<Color> colors;
  final int rotation;

  const _TwoColorGradient({required this.colors, required this.rotation});

  @override
  Widget build(BuildContext context) {
    final alignment = _rotationToAlignment(rotation);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: alignment.$1,
          end: alignment.$2,
          colors: colors,
        ),
      ),
    );
  }

  static (Alignment, Alignment) _rotationToAlignment(int degrees) {
    final rad = degrees * math.pi / 180.0;
    final dx = math.sin(rad);
    final dy = -math.cos(rad);
    return (Alignment(-dx, -dy), Alignment(dx, dy));
  }
}

class _MultiColorGradient extends StatefulWidget {
  final List<Color> colors;
  final int rotation;

  const _MultiColorGradient({required this.colors, required this.rotation});

  @override
  State<_MultiColorGradient> createState() => _MultiColorGradientState();
}

class _MultiColorGradientState extends State<_MultiColorGradient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final powerSaving = context.watch<AppState>().powerSaving(AppState.kPowerSavingChatBackground);
    if (powerSaving && _ctrl.isAnimating) {
      _ctrl.stop();
    } else if (!powerSaving && !_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _MultiGradientPainter(
            colors: widget.colors,
            baseRotation: widget.rotation,
            progress: _ctrl.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _MultiGradientPainter extends CustomPainter {
  final List<Color> colors;
  final int baseRotation;
  final double progress;

  _MultiGradientPainter({
    required this.colors,
    required this.baseRotation,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    if (colors.length == 1) {
      canvas.drawRect(Offset.zero & size, Paint()..color = colors.first);
      return;
    }

    final realRotation = (baseRotation * 2) % 720;
    final phase = (realRotation ~/ 360).isOdd;
    final t = phase ? 1.0 - progress * 0.5 : 0.5 + progress * 0.5;
    final angle = (realRotation % 360 + t * 360) * math.pi / 180.0;

    final cx = size.width / 2;
    final cy = size.height / 2;

    final stops = <double>[];
    for (int i = 0; i < colors.length; i++) {
      stops.add(i / (colors.length - 1));
    }

    final dx = math.sin(angle);
    final dy = -math.cos(angle);
    final halfDiag = math.sqrt(cx * cx + cy * cy);
    final startX = cx - dx * halfDiag;
    final startY = cy - dy * halfDiag;
    final endX = cx + dx * halfDiag;
    final endY = cy + dy * halfDiag;

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(startX, startY),
        Offset(endX, endY),
        colors,
        stops,
      );

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_MultiGradientPainter old) =>
      old.progress != progress ||
      old.baseRotation != baseRotation ||
      old.colors != colors;
}

class _TiledImage extends StatefulWidget {
  final Uint8List imageBytes;

  const _TiledImage({required this.imageBytes});

  @override
  State<_TiledImage> createState() => _TiledImageState();
}

class _TiledImageState extends State<_TiledImage> {
  ui.Image? _decoded;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(_TiledImage old) {
    super.didUpdateWidget(old);
    if (!identical(old.imageBytes, widget.imageBytes)) {
      _decodeImage();
    }
  }

  void _decodeImage() {
    ui.decodeImageFromList(widget.imageBytes, (image) {
      if (mounted) setState(() => _decoded = image);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_decoded == null) return const SizedBox.shrink();
    return CustomPaint(
      painter: _TiledPainter(image: _decoded!),
      size: Size.infinite,
    );
  }
}

class _TiledPainter extends CustomPainter {
  final ui.Image image;

  _TiledPainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (double y = 0; y < size.height; y += image.height) {
      for (double x = 0; x < size.width; x += image.width) {
        canvas.drawImage(image, Offset(x, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TiledPainter old) => !identical(old.image, image);
}

class _PatternWallpaper extends StatefulWidget {
  final List<Color> backgroundColors;
  final int gradientRotation;
  final Uint8List patternBytes;
  final int intensity;
  final double opacity;
  final Color fallbackColor;

  const _PatternWallpaper({
    required this.backgroundColors,
    required this.gradientRotation,
    required this.patternBytes,
    required this.intensity,
    required this.opacity,
    required this.fallbackColor,
  });

  @override
  State<_PatternWallpaper> createState() => _PatternWallpaperState();
}

class _PatternWallpaperState extends State<_PatternWallpaper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  ui.Image? _patternImage;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _decodePattern();
  }

  @override
  void didUpdateWidget(_PatternWallpaper old) {
    super.didUpdateWidget(old);
    if (!identical(old.patternBytes, widget.patternBytes)) {
      _decodePattern();
    }
  }

  void _decodePattern() {
    ui.decodeImageFromList(widget.patternBytes, (image) {
      if (mounted) setState(() => _patternImage = image);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final powerSaving = context.watch<AppState>().powerSaving(AppState.kPowerSavingChatBackground);
    if (powerSaving && _ctrl.isAnimating) {
      _ctrl.stop();
    } else if (!powerSaving && !_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _PatternWallpaperPainter(
            colors: widget.backgroundColors,
            baseRotation: widget.gradientRotation,
            progress: _ctrl.value,
            patternImage: _patternImage,
            intensity: widget.intensity,
            opacity: widget.opacity,
            fallbackColor: widget.fallbackColor,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _PatternWallpaperPainter extends CustomPainter {
  final List<Color> colors;
  final int baseRotation;
  final double progress;
  final ui.Image? patternImage;
  final int intensity;
  final double opacity;
  final Color fallbackColor;

  _PatternWallpaperPainter({
    required this.colors,
    required this.baseRotation,
    required this.progress,
    required this.patternImage,
    required this.intensity,
    required this.opacity,
    required this.fallbackColor,
  });

  static const _invertColorFilter = ColorFilter.matrix(<double>[
    0, 0, 0, 1, 0,
    0, 0, 0, 1, 0,
    0, 0, 0, 1, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    if (patternImage == null) {
      _drawGradient(canvas, size);
      return;
    }

    final rect = Offset.zero & size;

    if (intensity >= 0) {
      _drawGradient(canvas, size);
      canvas.saveLayer(
        rect,
        Paint()
          ..blendMode = BlendMode.softLight
          ..color = Color.fromARGB((opacity * 255).round(), 255, 255, 255),
      );
      final paint = Paint();
      if (_isPatternInverted()) {
        paint.colorFilter = _invertColorFilter;
      }
      _tilePattern(canvas, size, patternImage!, paint);
      canvas.restore();
    } else {
      canvas.saveLayer(rect, Paint());
      _drawGradient(canvas, size);
      _tilePattern(
        canvas, size, patternImage!,
        Paint()..blendMode = BlendMode.dstIn,
      );
      if (intensity > -100) {
        final blackOpacity = 1.0 + (intensity / 100.0);
        canvas.drawRect(
          rect,
          Paint()..color = Color.fromRGBO(0, 0, 0, blackOpacity),
        );
      }
      canvas.restore();
    }
  }

  void _drawGradient(Canvas canvas, Size size) {
    if (colors.isEmpty) {
      canvas.drawRect(Offset.zero & size, Paint()..color = fallbackColor);
      return;
    }
    if (colors.length == 1) {
      canvas.drawRect(Offset.zero & size, Paint()..color = colors.first);
      return;
    }

    final realRotation = (baseRotation * 2) % 720;
    final phase = (realRotation ~/ 360).isOdd;
    final t = phase ? 1.0 - progress * 0.5 : 0.5 + progress * 0.5;
    final angle = (realRotation % 360 + t * 360) * math.pi / 180.0;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final stops = <double>[];
    for (int i = 0; i < colors.length; i++) {
      stops.add(i / (colors.length - 1));
    }
    final dx = math.sin(angle);
    final dy = -math.cos(angle);
    final halfDiag = math.sqrt(cx * cx + cy * cy);

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - dx * halfDiag, cy - dy * halfDiag),
        Offset(cx + dx * halfDiag, cy + dy * halfDiag),
        colors,
        stops,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _tilePattern(Canvas canvas, Size size, ui.Image pattern, Paint paint) {
    final scaleY = size.height / pattern.height;
    final scaledW = pattern.width * scaleY;
    final src = Rect.fromLTWH(
      0, 0, pattern.width.toDouble(), pattern.height.toDouble(),
    );
    final minCols = (size.width / scaledW).ceil();
    final cols = ((minCols ~/ 2) * 2) + 1;
    final totalWidth = cols * scaledW;
    final xOffset = (size.width - totalWidth) / 2;

    for (int x = 0; x < cols; x++) {
      final dst = Rect.fromLTWH(
        xOffset + x * scaledW, 0, scaledW, size.height,
      );
      canvas.drawImageRect(pattern, src, dst, paint);
    }
  }

  bool _isPatternInverted() {
    if (intensity <= 0 || colors.isEmpty) return false;
    int r = 0, g = 0, b = 0;
    for (final c in colors) {
      r += c.red;
      g += c.green;
      b += c.blue;
    }
    final n = colors.length;
    final avg = Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
    final hsv = HSVColor.fromColor(avg);
    return hsv.value <= 0.3;
  }

  @override
  bool shouldRepaint(_PatternWallpaperPainter old) =>
      old.progress != progress ||
      old.baseRotation != baseRotation ||
      old.colors != colors ||
      old.patternImage != patternImage ||
      old.intensity != intensity ||
      old.opacity != opacity;
}

Color computeAverageColor(Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return const Color(0xFF527C41);

  final total = decoded.width * decoded.height;
  if (total == 0) return const Color(0xFF527C41);

  // Average the DECODED pixels, mirroring AyuGram's Ui::CountAverageColor
  // (ui/chat/chat_theme.cpp:880-902), which sums every pixel's R/G/B and divides
  // by the pixel count. We sample up to ~1000 evenly-spaced pixels for speed
  // (small images < 1000px are averaged in full). The previous implementation
  // averaged the raw *encoded* JPEG/PNG bytes — compressed data unrelated to the
  // visible color — which produced a wrong wallpaper tint for image backgrounds.
  final stride = math.max(1, total ~/ 1000);
  int r = 0, g = 0, b = 0, count = 0;
  for (int idx = 0; idx < total; idx += stride) {
    final px = decoded.getPixel(idx % decoded.width, idx ~/ decoded.width);
    r += px.r.toInt();
    g += px.g.toInt();
    b += px.b.toInt();
    count++;
  }

  if (count == 0) return const Color(0xFF527C41);
  return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
}

Color themeAdjustedColor(Color base, Color wallpaperAverage) {
  final baseHsl = HSLColor.fromColor(base);
  final avgHsl = HSLColor.fromColor(wallpaperAverage);
  return HSLColor.fromAHSL(
    baseHsl.alpha,
    avgHsl.hue,
    avgHsl.saturation.clamp(0.0, 1.0),
    baseHsl.lightness,
  ).toColor();
}

const _kJpegQuality = 87;
const _kThumbSize = 320;
const _kMaxWallpaperSize = 2960;
const _kMaxAspectRatio = 40.0;

Uint8List encodeWallpaperJpeg(Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return imageBytes;

  var image = decoded;

  // Crop overly wide/tall images down to the max aspect ratio, center-cropped,
  // exactly like AyuGram's Ui::PreprocessBackgroundImage
  // (ui/chat/chat_theme.cpp:949-957) — it crops, it does NOT skip the image.
  if (image.width > _kMaxAspectRatio * image.height) {
    final w = (_kMaxAspectRatio * image.height).round();
    image = img.copyCrop(image,
      x: (image.width - w) ~/ 2, y: 0, width: w, height: image.height);
  } else if (image.height > _kMaxAspectRatio * image.width) {
    final h = (_kMaxAspectRatio * image.width).round();
    image = img.copyCrop(image,
      x: 0, y: (image.height - h) ~/ 2, width: image.width, height: h);
  }

  // Scale down so the longest side is at most kMaxSize (2960), matching
  // image.scaled(kMaxSize, kMaxSize, KeepAspectRatio) (chat_theme.cpp:958-964).
  final longest = math.max(image.width, image.height);
  if (longest > _kMaxWallpaperSize) {
    final scale = _kMaxWallpaperSize / longest;
    image = img.copyResize(image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: _kJpegQuality));
}

Uint8List generateWallpaperThumb(Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return imageBytes;

  final longest = math.max(decoded.width, decoded.height);
  if (longest <= _kThumbSize) {
    return Uint8List.fromList(img.encodeJpg(decoded, quality: _kJpegQuality));
  }

  final scale = _kThumbSize / longest;
  final thumb = img.copyResize(decoded,
    width: (decoded.width * scale).round(),
    height: (decoded.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );
  return Uint8List.fromList(img.encodeJpg(thumb, quality: _kJpegQuality));
}

Uint8List? blurWallpaperImage(Uint8List imageBytes, {int radius = 24}) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;
  final blurred = img.gaussianBlur(decoded, radius: radius);
  return Uint8List.fromList(img.encodePng(blurred));
}
