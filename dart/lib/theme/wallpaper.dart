import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'package:vector_graphics/vector_graphics.dart' as vgfx;

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
    this.patternIntensity = 50,
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
    int intensity = 50,
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
    final intensity = int.tryParse(params['intensity'] ?? '') ?? 50;
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

  /// Mirrors AyuGram `WallPaper::collectShareParams` (data_wall_paper.cpp:269-291)
  /// + `StringFromColors` (:163-173): intensity is emitted only for patterns,
  /// rotation only for exactly-2-color gradients, and the color separator is
  /// `~` for >2 colors / `-` for <=2.
  String toUrlParams() {
    final parts = <String>[];
    if (backgroundColors.isNotEmpty) {
      final sep = backgroundColors.length > 2 ? '~' : '-';
      final hexes = backgroundColors
          .map((c) => (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0'))
          .join(sep);
      parts.add('bg_color=$hexes');
    }
    if (isPattern && patternIntensity != 0) {
      parts.add('intensity=$patternIntensity');
    }
    if (gradientRotation != 0 && backgroundColors.length == 2) {
      parts.add('rotation=$gradientRotation');
    }
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

  /// Mirrors AyuGram `WallPaper::withUrlParams` rotation handling
  /// (data_wall_paper.cpp:417-418): clamp to [0,315] then floor to the nearest
  /// lower multiple of 45 — NOT round-to-nearest-then-wrap.
  static int _snapRotation(int degrees) {
    final clamped = degrees.clamp(0, 315);
    return (clamped ~/ 45) * 45;
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

    // 2 colors → linear (8-direction), 3-4 colors → Telegram's signature
    // 4-point free-flowing complex gradient. Both static + dithered.
    return _RasterGradient(
      colors: colors,
      rotation: wallpaper.effectiveGradientRotation,
      fallbackColor: fallbackColor,
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
        return _RasterGradient(
          colors: colors,
          rotation: wallpaper.effectiveGradientRotation,
          fallbackColor: fallbackColor,
        );
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

// ===========================================================================
// Gradient image generation — ports of AyuGram's `lib_ui/ui/image/image_prepare.cpp`.
//
// AyuGram renders the chat-background gradient as a raster (64px complex gradient
// upscaled, or a linear gradient) which is then dithered. It is STATIC: it does
// not animate on a timer; it only advances one 45° step (with a 200ms fade) when
// an outgoing message is revealed (chat_theme.cpp:638-669). There is no continuous
// timer anywhere in AyuGram, so we render a static, dithered raster image here.
// ===========================================================================

// Complex gradient native size. AyuGram generates at 64px and smooth-upscales;
// we generate at a slightly higher resolution so dithering has an effect, then
// let the GPU smooth-scale to the target (FilterQuality.high).
const int _kComplexGradientSize = 256;
const int _kLinearGradientSize = 512;

/// Port of `GenerateSmallComplexGradient` (image_prepare.cpp:172-291):
/// Telegram's signature multi-point free-flowing gradient. Four control points
/// (taken from an 8-position ring by phase) are blended per-pixel by inverse
/// 4th-power distance, with a swirl distortion applied to the sampling position.
Uint8List _complexGradientPixels(
    List<Color> colors, int rotation, double progress, int size) {
  const positions = <List<double>>[
    [0.80, 0.10],
    [0.60, 0.20],
    [0.35, 0.25],
    [0.25, 0.60],
    [0.20, 0.90],
    [0.40, 0.80],
    [0.65, 0.75],
    [0.75, 0.40],
  ];
  List<List<double>> positionsForPhase(int phase) {
    return List<List<double>>.generate(4, (i) {
      final p = positions[(phase + i * 2) % 8];
      return [p[0], 1.0 - p[1]];
    });
  }

  final phase = rotation.clamp(0, 315) ~/ 45;
  final previous = positionsForPhase((phase + 1) % 8);
  final current = positionsForPhase(phase);

  final n = colors.length;
  final cr = List<double>.generate(n, (i) => colors[i].red.toDouble());
  final cg = List<double>.generate(n, (i) => colors[i].green.toDouble());
  final cb = List<double>.generate(n, (i) => colors[i].blue.toDouble());
  final colorX = List<double>.generate(
      n, (i) => previous[i][0] + (current[i][0] - previous[i][0]) * progress);
  final colorY = List<double>.generate(
      n, (i) => previous[i][1] + (current[i][1] - previous[i][1]) * progress);

  final out = Uint8List(size * size * 4);
  final invsize = 1.0 / size;
  int idx = 0;
  for (int y = 0; y < size; y++) {
    final cdy = (y * invsize) - 0.5;
    final cdy2 = cdy * cdy;
    for (int x = 0; x < size; x++) {
      final cdx = (x * invsize) - 0.5;
      final centerDistance = math.sqrt(cdx * cdx + cdy2);
      final swirl = 0.35 * centerDistance;
      final theta = swirl * swirl * 0.8 * 8.0;
      final st = math.sin(theta);
      final ct = math.cos(theta);
      final pixelX = (0.5 + cdx * ct - cdy * st).clamp(0.0, 1.0);
      final pixelY = (0.5 + cdx * st + cdy * ct).clamp(0.0, 1.0);

      double dsum = 0, r = 0, g = 0, b = 0;
      for (int i = 0; i < n; i++) {
        final dx = pixelX - colorX[i];
        final dy = pixelY - colorY[i];
        final dist = math.max(0.0, 0.9 - math.sqrt(dx * dx + dy * dy));
        final sq = dist * dist;
        final fourth = sq * sq;
        dsum += fourth;
        r += fourth * cr[i];
        g += fourth * cg[i];
        b += fourth * cb[i];
      }
      final inv = dsum > 0 ? 1.0 / dsum : 0.0;
      out[idx++] = (r * inv).round().clamp(0, 255);
      out[idx++] = (g * inv).round().clamp(0, 255);
      out[idx++] = (b * inv).round().clamp(0, 255);
      out[idx++] = 255;
    }
  }
  return out;
}

/// Port of `GenerateLinearGradient` (image_prepare.cpp:916-966): a discrete
/// 8-direction start/finalStop table. `colors[0]` sits at `start`, so for
/// rotation 0 it is at the TOP (`{0,0}`) — fixing the previously-reversed
/// direction.
Uint8List _linearGradientPixels(List<Color> colors, int rotation, int size) {
  final type = rotation.clamp(0, 315) ~/ 45;
  double sx, sy, fx, fy;
  switch (type) {
    case 0:
      sx = 0; sy = 0; fx = 0; fy = 1; break;
    case 1:
      sx = 1; sy = 0; fx = 0; fy = 1; break;
    case 2:
      sx = 1; sy = 0; fx = 0; fy = 0; break;
    case 3:
      sx = 1; sy = 1; fx = 0; fy = 0; break;
    case 4:
      sx = 0; sy = 1; fx = 0; fy = 0; break;
    case 5:
      sx = 0; sy = 1; fx = 1; fy = 0; break;
    case 6:
      sx = 0; sy = 0; fx = 1; fy = 0; break;
    default: // 7
      sx = 0; sy = 0; fx = 1; fy = 1; break;
  }
  final ax = fx - sx;
  final ay = fy - sy;
  final axisLen2 = ax * ax + ay * ay;
  final n = colors.length;
  final out = Uint8List(size * size * 4);
  final denom = size > 1 ? (size - 1).toDouble() : 1.0;
  int idx = 0;
  for (int y = 0; y < size; y++) {
    final ny = y / denom;
    for (int x = 0; x < size; x++) {
      final nx = x / denom;
      double t;
      if (axisLen2 == 0) {
        t = 0;
      } else {
        t = (((nx - sx) * ax + (ny - sy) * ay) / axisLen2).clamp(0.0, 1.0);
      }
      final pos = t * (n - 1);
      int i0 = pos.floor();
      if (i0 < 0) i0 = 0;
      if (i0 > n - 1) i0 = n - 1;
      int i1 = i0 + 1;
      if (i1 > n - 1) i1 = n - 1;
      final f = pos - i0;
      final a = colors[i0];
      final b = colors[i1];
      out[idx++] = (a.red + (b.red - a.red) * f).round().clamp(0, 255);
      out[idx++] = (a.green + (b.green - a.green) * f).round().clamp(0, 255);
      out[idx++] = (a.blue + (b.blue - a.blue) * f).round().clamp(0, 255);
      out[idx++] = 255;
    }
  }
  return out;
}

/// Dither tier (`kBits`) from `DitherImage` (image_prepare.cpp:880-897). The
/// returned value is the template argument `kBits` of `DitherGeneric<kBits>`.
int _ditherBitsForSize(int w, int h) {
  final mn = math.min(w, h);
  final mx = math.max(w, h);
  if (mx >= 1024 && mn >= 512) return 4;
  if (mx >= 512 && mn >= 256) return 3;
  if (mx >= 256 && mn >= 128) return 2;
  if (mn >= 32) return 1;
  return 0;
}

/// Port of `DitherImage` + `DitherGeneric<kBits>` (image_prepare.cpp:101-170,
/// 880-897): each pixel copies from a nearby pixel offset by a random amount
/// inside a `kSquareSide × kSquareSide` window (`kSquareSide = 1 << kBits`),
/// each axis offset lying in `[-kShift, kShift-1]` (`kShift = kSquareSide / 2`)
/// and taken from the low / high nibbles of one random byte — exactly as the
/// C++ does (`shiftx = (shift & kMask) - kShift`,
/// `shifty = ((shift >> 4) & kMask) - kShift`). Breaks up banding on large/dark
/// gradients. Deterministic (seeded) so it never relies on `Math.random`.
Uint8List _ditherPixels(Uint8List src, int w, int h, int seed) {
  final bits = _ditherBitsForSize(w, h);
  if (bits == 0) return src;
  final squareSide = 1 << bits; // kSquareSide
  final shiftHalf = squareSide >> 1; // kShift
  final mask = squareSide - 1; // kMask
  final out = Uint8List(src.length);
  int rng = seed & 0x7fffffff;
  if (rng == 0) rng = 1;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      rng = (rng * 1103515245 + 12345) & 0x7fffffff;
      final rnd = (rng >> 16) & 0xff; // one random byte per pixel (the C++ uchar)
      final dx = (rnd & mask) - shiftHalf; // shiftx ∈ [-kShift, kShift-1]
      final dy = ((rnd >> 4) & mask) - shiftHalf; // shifty ∈ [-kShift, kShift-1]
      int sx = x + dx;
      if (sx < 0) sx = 0; else if (sx >= w) sx = w - 1;
      int sy = y + dy;
      if (sy < 0) sy = 0; else if (sy >= h) sy = h - 1;
      final di = (y * w + x) * 4;
      final si = (sy * w + sx) * 4;
      out[di] = src[si];
      out[di + 1] = src[si + 1];
      out[di + 2] = src[si + 2];
      out[di + 3] = src[si + 3];
    }
  }
  return out;
}

int _gradientSeed(List<Color> colors, int rotation) {
  int h = 17 + rotation;
  for (final c in colors) {
    h = (h * 31 + c.value) & 0x7fffffff;
  }
  return h == 0 ? 1 : h;
}

/// Generates the static, dithered RGBA buffer for a 2-4 color gradient.
Uint8List _generateGradientBytes(List<Color> colors, int rotation, int size) {
  final raw = colors.length > 2
      ? _complexGradientPixels(colors, rotation, 1.0, size)
      : _linearGradientPixels(colors, rotation, size);
  return _ditherPixels(raw, size, size, _gradientSeed(colors, rotation));
}

bool _sameColors(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].value != b[i].value) return false;
  }
  return true;
}

Color _averageOf(List<Color> colors, Color fallback) {
  if (colors.isEmpty) return fallback;
  int r = 0, g = 0, b = 0;
  for (final c in colors) {
    r += c.red;
    g += c.green;
    b += c.blue;
  }
  final n = colors.length;
  return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
}

class _RasterGradient extends StatefulWidget {
  final List<Color> colors;
  final int rotation;
  final Color fallbackColor;

  const _RasterGradient({
    required this.colors,
    required this.rotation,
    required this.fallbackColor,
  });

  @override
  State<_RasterGradient> createState() => _RasterGradientState();
}

class _RasterGradientState extends State<_RasterGradient> {
  ui.Image? _image;
  int _genToken = 0;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void didUpdateWidget(_RasterGradient old) {
    super.didUpdateWidget(old);
    if (old.rotation != widget.rotation ||
        !_sameColors(old.colors, widget.colors)) {
      _generate();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _generate() {
    final colors = List<Color>.from(widget.colors);
    final size =
        colors.length > 2 ? _kComplexGradientSize : _kLinearGradientSize;
    final bytes = _generateGradientBytes(colors, widget.rotation, size);
    final token = ++_genToken;
    ui.decodeImageFromPixels(bytes, size, size, ui.PixelFormat.rgba8888, (image) {
      if (!mounted || token != _genToken) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RasterGradientPainter(
        image: _image,
        fallback: _averageOf(widget.colors, widget.fallbackColor),
      ),
      size: Size.infinite,
    );
  }
}

class _RasterGradientPainter extends CustomPainter {
  final ui.Image? image;
  final Color fallback;

  _RasterGradientPainter({required this.image, required this.fallback});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final image = this.image;
    if (image == null) {
      canvas.drawRect(rect, Paint()..color = fallback);
      return;
    }
    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(
      image,
      src,
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_RasterGradientPainter old) =>
      !identical(old.image, image) || old.fallback != fallback;
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

class _PatternWallpaperState extends State<_PatternWallpaper> {
  ui.Image? _gradientImage;
  ui.Image? _patternImage;
  int _gradToken = 0;
  int _patToken = 0;

  @override
  void initState() {
    super.initState();
    _generateGradient();
    _decodePattern();
  }

  @override
  void didUpdateWidget(_PatternWallpaper old) {
    super.didUpdateWidget(old);
    if (old.gradientRotation != widget.gradientRotation ||
        !_sameColors(old.backgroundColors, widget.backgroundColors)) {
      _generateGradient();
    }
    if (!identical(old.patternBytes, widget.patternBytes)) {
      _decodePattern();
    }
  }

  @override
  void dispose() {
    _gradientImage?.dispose();
    _patternImage?.dispose();
    super.dispose();
  }

  void _generateGradient() {
    final colors = List<Color>.from(widget.backgroundColors);
    if (colors.length < 2) {
      final token = ++_gradToken;
      // No multi-stop gradient needed; painter fills solid / fallback.
      if (_gradientImage != null) {
        setState(() {
          _gradientImage?.dispose();
          _gradientImage = null;
        });
      }
      _gradToken = token;
      return;
    }
    final size =
        colors.length > 2 ? _kComplexGradientSize : _kLinearGradientSize;
    final bytes = _generateGradientBytes(colors, widget.gradientRotation, size);
    final token = ++_gradToken;
    ui.decodeImageFromPixels(bytes, size, size, ui.PixelFormat.rgba8888, (image) {
      if (!mounted || token != _gradToken) {
        image.dispose();
        return;
      }
      setState(() {
        _gradientImage?.dispose();
        _gradientImage = image;
      });
    });
  }

  Future<void> _decodePattern() async {
    final token = ++_patToken;
    final image = await _decodePatternBytes(widget.patternBytes);
    if (!mounted || token != _patToken) {
      image?.dispose();
      return;
    }
    setState(() {
      _patternImage?.dispose();
      _patternImage = image;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PatternWallpaperPainter(
        colors: widget.backgroundColors,
        gradientImage: _gradientImage,
        patternImage: _patternImage,
        intensity: widget.intensity,
        opacity: widget.opacity,
        fallbackColor: widget.fallbackColor,
      ),
      size: Size.infinite,
    );
  }
}

/// Decodes a Telegram wallpaper-pattern document. Pattern documents are
/// `application/x-tgwallpattern`, i.e. a gzipped SVG (chat_theme.cpp:1079-1090
/// `ReadBackgroundImage` un-gzips then rasterizes the SVG). Raster documents
/// (jpg/png) fall through to the normal image decoder.
Future<ui.Image?> _decodePatternBytes(Uint8List bytes) async {
  var data = bytes;
  // Gunzip if gzip-framed (magic 1f 8b).
  if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
    try {
      data = Uint8List.fromList(GZipDecoder().decodeBytes(data));
    } catch (_) {}
  }
  if (_looksLikeSvg(data)) {
    return _rasterizeSvg(data);
  }
  return _decodeRaster(data);
}

bool _looksLikeSvg(Uint8List b) {
  int i = 0;
  while (i < b.length &&
      (b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0a || b[i] == 0x0d || b[i] == 0xef || b[i] == 0xbb || b[i] == 0xbf)) {
    i++;
  }
  if (i >= b.length || b[i] != 0x3c /* '<' */) return false;
  final head =
      String.fromCharCodes(b.sublist(i, math.min(b.length, i + 512))).toLowerCase();
  return head.contains('<svg') || head.contains('<?xml');
}

Future<ui.Image?> _rasterizeSvg(Uint8List bytes) async {
  try {
    final svg = utf8.decode(bytes, allowMalformed: true);
    final info = await vgfx.vg.loadPicture(SvgStringLoader(svg), null);
    const target = 512;
    int w = target, h = target;
    final sz = info.size;
    if (sz.width > 0 && sz.height > 0) {
      if (sz.width >= sz.height) {
        w = target;
        h = math.max(1, (target * sz.height / sz.width).round());
      } else {
        h = target;
        w = math.max(1, (target * sz.width / sz.height).round());
      }
    }
    final image = await info.picture.toImage(w, h);
    info.picture.dispose();
    return image;
  } catch (_) {
    return null;
  }
}

Future<ui.Image?> _decodeRaster(Uint8List bytes) {
  final completer = Completer<ui.Image?>();
  try {
    ui.decodeImageFromList(bytes, (image) {
      if (!completer.isCompleted) completer.complete(image);
    });
  } catch (_) {
    if (!completer.isCompleted) completer.complete(null);
  }
  return completer.future;
}

class _PatternWallpaperPainter extends CustomPainter {
  final List<Color> colors;
  final ui.Image? gradientImage;
  final ui.Image? patternImage;
  final int intensity;
  final double opacity;
  final Color fallbackColor;

  _PatternWallpaperPainter({
    required this.colors,
    required this.gradientImage,
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
    final rect = Offset.zero & size;
    final pattern = patternImage;
    if (pattern == null) {
      _drawGradient(canvas, size);
      return;
    }

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
      _tilePattern(canvas, size, pattern, paint);
      canvas.restore();
    } else {
      canvas.saveLayer(rect, Paint());
      _drawGradient(canvas, size);
      _tilePattern(
        canvas,
        size,
        pattern,
        Paint()..blendMode = BlendMode.dstIn,
      );
      if (intensity > -100) {
        final blackOpacity = (1.0 + intensity / 100.0).clamp(0.0, 1.0);
        canvas.drawRect(
          rect,
          Paint()..color = Color.fromRGBO(0, 0, 0, blackOpacity),
        );
      }
      canvas.restore();
    }
  }

  void _drawGradient(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = gradientImage;
    if (gradient != null) {
      final src = Rect.fromLTWH(
          0, 0, gradient.width.toDouble(), gradient.height.toDouble());
      canvas.drawImageRect(
        gradient,
        src,
        rect,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else if (colors.length == 1) {
      canvas.drawRect(rect, Paint()..color = colors.first);
    } else {
      canvas.drawRect(rect, Paint()..color = fallbackColor);
    }
  }

  /// Port of the pattern tiling in `chat_theme.cpp:122-210`: the pattern is
  /// scaled (KeepAspectRatio) to fit a square the height of the area, then tiled
  /// across BOTH rows and columns. The column count is forced odd and centered
  /// (`((cx/2)*2)+1`), matching AyuGram's pattern layout.
  void _tilePattern(Canvas canvas, Size size, ui.Image pattern, Paint paint) {
    final scale = size.height / math.max(pattern.width, pattern.height);
    final tw = pattern.width * scale;
    final th = pattern.height * scale;
    if (tw <= 0 || th <= 0) return;
    final src = Rect.fromLTWH(
        0, 0, pattern.width.toDouble(), pattern.height.toDouble());
    final cx = (size.width / tw).ceil();
    final cy = (size.height / th).ceil();
    final cols = ((cx ~/ 2) * 2) + 1;
    final rows = cy;
    final xshift = (size.width - cols * tw) / 2;
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final dst = Rect.fromLTWH(xshift + x * tw, y * th, tw, th);
        canvas.drawImageRect(pattern, src, dst, paint);
      }
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
      !identical(old.gradientImage, gradientImage) ||
      !identical(old.patternImage, patternImage) ||
      old.colors != colors ||
      old.intensity != intensity ||
      old.opacity != opacity ||
      old.fallbackColor != fallbackColor;
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
        interpolation: img.Interpolation.linear);
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
      interpolation: img.Interpolation.linear);
  return Uint8List.fromList(img.encodeJpg(thumb, quality: _kJpegQuality));
}

Uint8List? blurWallpaperImage(Uint8List imageBytes, {int radius = 24}) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;
  final blurred = img.gaussianBlur(decoded, radius: radius);
  return Uint8List.fromList(img.encodePng(blurred));
}
