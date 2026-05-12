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
        rotation: wallpaper.gradientRotation,
      );
    }

    return _MultiColorGradient(
      colors: colors,
      rotation: wallpaper.gradientRotation,
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
    Widget bg;
    if (colors.length >= 2) {
      bg = _MultiColorGradient(colors: colors, rotation: wallpaper.gradientRotation);
    } else if (colors.isNotEmpty) {
      bg = ColoredBox(color: colors.first);
    } else {
      bg = ColoredBox(color: fallbackColor);
    }

    if (wallpaper.patternBytes == null) return bg;

    final intensity = wallpaper.patternIntensity;
    final opacity = wallpaper.patternOpacity.clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        _PatternOverlay(
          patternBytes: wallpaper.patternBytes!,
          intensity: intensity,
          opacity: opacity,
        ),
      ],
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

class _TiledImage extends StatelessWidget {
  final Uint8List imageBytes;

  const _TiledImage({required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TiledPainter(imageBytes: imageBytes),
      size: Size.infinite,
    );
  }
}

class _TiledPainter extends CustomPainter {
  final Uint8List imageBytes;
  ui.Image? _decoded;
  bool _loading = false;

  _TiledPainter({required this.imageBytes});

  @override
  void paint(Canvas canvas, Size size) {
    if (_decoded == null && !_loading) {
      _loading = true;
      ui.decodeImageFromList(imageBytes, (img) {
        _decoded = img;
      });
    }

    if (_decoded == null) return;

    final img = _decoded!;
    final paint = Paint();
    for (double y = 0; y < size.height; y += img.height) {
      for (double x = 0; x < size.width; x += img.width) {
        canvas.drawImage(img, Offset(x, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TiledPainter old) => old.imageBytes != imageBytes;
}

class _PatternOverlay extends StatelessWidget {
  final Uint8List patternBytes;
  final int intensity;
  final double opacity;

  const _PatternOverlay({
    required this.patternBytes,
    required this.intensity,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    final patternImage = Image.memory(
      patternBytes,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );

    if (intensity >= 0) {
      return Opacity(
        opacity: opacity,
        child: ShaderMask(
          blendMode: BlendMode.softLight,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Colors.white],
          ).createShader(bounds),
          child: patternImage,
        ),
      );
    }

    // §25.8.4 / §25.17.4: negative intensity uses DestinationIn + SourceOver black fill
    return CustomPaint(
      foregroundPainter: _NegativePatternPainter(
        darkenOpacity: intensity > -100 ? 1.0 + (intensity / 100.0) : 0.0,
      ),
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.dstIn),
        child: patternImage,
      ),
    );
  }
}

class _NegativePatternPainter extends CustomPainter {
  final double darkenOpacity;
  _NegativePatternPainter({required this.darkenOpacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (darkenOpacity > 0.0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, darkenOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(_NegativePatternPainter old) =>
      old.darkenOpacity != darkenOpacity;
}

Color computeAverageColor(Uint8List imageBytes) {
  if (imageBytes.length < 4) return const Color(0xFF527C41);

  int r = 0, g = 0, b = 0;
  int count = 0;
  final step = math.max(1, imageBytes.length ~/ 1000);
  for (int i = 0; i + 2 < imageBytes.length; i += step) {
    r += imageBytes[i];
    g += imageBytes[i + 1];
    b += imageBytes[i + 2];
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
  final aspect = image.width / image.height;
  if (aspect > _kMaxAspectRatio || aspect < 1 / _kMaxAspectRatio) {
    return imageBytes;
  }

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
