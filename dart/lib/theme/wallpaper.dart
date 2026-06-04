import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'package:vector_graphics/vector_graphics.dart' as vgfx;
import 'package:uniclient/utils/debug.dart';

enum WallpaperType { solid, gradient, pattern, image }

/// One collectible-gift "symbol" stamped over a gift-pattern wallpaper: a
/// normalized `[0,1]` placement [area] within a single pattern tile plus a
/// [rotation] in degrees. Port of AyuGram `ChatThemeGiftSymbol`
/// (ui/chat/chat_theme.h:29-32). Parsed from the `<g id="GiftPatterns">`
/// cut-out group of the pattern document SVG by [parseGiftSymbolsFromTgv]
/// (port of `ParseGiftSymbols`, ui/chat/chat_theme.cpp:1015-1077).
class WallpaperGiftSymbol {
  /// Placement within ONE pattern tile, normalized to `[0,1]` on both axes
  /// (matches AyuGram's `area.x * w` mapping, chat_theme.cpp:136-142).
  final Rect area;

  /// Clockwise rotation in degrees applied about the symbol's center
  /// (`p.rotate(symbol.rotation)`, chat_theme.cpp:154).
  final double rotation;

  const WallpaperGiftSymbol({required this.area, required this.rotation});
}

class WallpaperData {
  final WallpaperType type;
  final List<Color> backgroundColors;
  final int patternIntensity;
  final int gradientRotation;
  final bool blurred;
  final Uint8List? imageBytes;
  final Uint8List? patternBytes;
  final bool tiled;

  /// Collectible-gift symbol placements over a gift-pattern wallpaper, parsed
  /// from the `GiftPatterns` group of [patternBytes]. Empty for ordinary
  /// (non-gift) patterns. Port of `ChatThemeBackground::giftSymbols`
  /// (ui/chat/chat_theme.h:41).
  final List<WallpaperGiftSymbol> giftSymbols;

  /// Pre-rendered raster of the gift's symbol custom-emoji that is stamped at
  /// each [giftSymbols] placement — AyuGram's `giftSymbolFrame`
  /// (ui/chat/chat_theme.h:42, produced by `PrepareGiftSymbol`). When null and
  /// [giftSymbols] is non-empty the frame is derived from the rendered pattern
  /// SVG itself (the symbol artwork the document carries at those positions).
  final Uint8List? giftSymbolFrame;

  const WallpaperData({
    this.type = WallpaperType.solid,
    this.backgroundColors = const [],
    this.patternIntensity = 50,
    this.gradientRotation = 0,
    this.blurred = false,
    this.imageBytes,
    this.patternBytes,
    this.tiled = false,
    this.giftSymbols = const [],
    this.giftSymbolFrame,
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
    Uint8List? giftSymbolFrame,
  }) {
    return WallpaperData(
      type: WallpaperType.pattern,
      patternBytes: patternBytes,
      backgroundColors: backgroundColors,
      patternIntensity: intensity,
      gradientRotation: rotation,
      // Collectible-gift pattern documents embed a `GiftPatterns` group; parse
      // its symbol placements up-front so the renderer can stamp the gift
      // overlay (chat_theme.cpp:120-202). Empty for ordinary patterns.
      giftSymbols: parseGiftSymbolsFromTgv(patternBytes),
      giftSymbolFrame: giftSymbolFrame,
    );
  }

  /// AyuGram `WallPaper::kDefaultIntensity` (data/data_wall_paper.h:110).
  static const int _kDefaultIntensity = 50;

  /// Parses a `t.me/bg/<slug>?<params>` share link, mirroring AyuGram's
  /// `WallPaper::withUrlParams` (data/data_wall_paper.cpp:384-421). Colors are
  /// read **primarily from the path slug** (`ColorsFromString(_slug)`), falling
  /// back to the `bg_color` / `gradient` / `color` / `slug` query params (in
  /// that order) only when the slug yields nothing — so a canonical gradient
  /// link like `t.me/bg/3390ec-aa82e6` (no `bg_color` param) parses correctly.
  static WallpaperData? fromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) return null;
    if (pathSegments.first != 'bg' || pathSegments.length < 2) return null;

    final params = uri.queryParameters;
    final slug = pathSegments[1];

    // Slug first, then the query-param fallbacks (withUrlParams:388-409).
    var colors = _colorsFromString(slug);
    if (colors.isEmpty) colors = _colorsFromString(params['bg_color'] ?? '');
    if (colors.isEmpty) colors = _colorsFromString(params['gradient'] ?? '');
    if (colors.isEmpty) colors = _colorsFromString(params['color'] ?? '');
    if (colors.isEmpty) colors = _colorsFromString(params['slug'] ?? '');
    if (colors.isEmpty) return null;

    // mode is '+'/space-separated; only the `blur` token matters (:390-397).
    final mode = (params['mode'] ?? '').replaceAll('+', ' ');
    final blur = mode.split(' ').contains('blur');

    // intensity only accepted in [-100,100], else default (:410-416).
    var intensity = _kDefaultIntensity;
    final intensityStr = params['intensity'];
    if (intensityStr != null && intensityStr.isNotEmpty) {
      final parsed = int.tryParse(intensityStr);
      if (parsed != null && parsed >= -100 && parsed <= 100) {
        intensity = parsed;
      }
    }

    final rotation = _snapRotation(int.tryParse(params['rotation'] ?? '') ?? 0);

    if (colors.length == 1) {
      return WallpaperData(
        type: WallpaperType.solid,
        backgroundColors: colors,
        blurred: blur,
      );
    }

    return WallpaperData(
      type: WallpaperType.gradient,
      backgroundColors: colors,
      patternIntensity: intensity,
      gradientRotation: rotation,
      blurred: blur,
    );
  }

  /// Mirrors AyuGram `WallPaper::collectShareParams` (data_wall_paper.cpp:269-291):
  /// the **query-string** portion of a share link. `bg_color` + `intensity` are
  /// emitted ONLY for patterns — for solid/gradient wallpapers the colors live
  /// in the URL path slug (see [shareSlug]), never as a `bg_color` param.
  /// `rotation` is emitted only for exactly-2-color gradients; `mode=blur` when
  /// blurred.
  String toUrlParams() {
    final parts = <String>[];
    if (isPattern) {
      if (backgroundColors.isNotEmpty) {
        parts.add('bg_color=${_stringFromColors(backgroundColors)}');
      }
      if (patternIntensity != 0) {
        parts.add('intensity=$patternIntensity');
      }
    }
    if (gradientRotation != 0 && backgroundColors.length == 2) {
      parts.add('rotation=$gradientRotation');
    }
    if (blurred) parts.add('mode=blur');
    return parts.join('&');
  }

  /// The URL **path slug** for a color-based share link — `StringFromColors` of
  /// the background colors (data_wall_paper.cpp:304/445). For solid/gradient
  /// wallpapers this carries the colors (`bg/<slug>`), which [fromUrl] parses
  /// back via the slug-first rule. Empty when there are no background colors.
  String get shareSlug =>
      backgroundColors.isEmpty ? '' : _stringFromColors(backgroundColors);

  /// Port of AyuGram `ColorsFromString` (data/data_wall_paper.cpp:125-145):
  /// parses up to 4 `rrggbb` hex colors joined by `~` (or `-` for exactly 2),
  /// requiring an exact length of `count*7 - 1` (no trailing characters) and a
  /// valid separator at each boundary (`~` always valid; `-` only when
  /// `count <= 2`). Returns an empty list on any malformed input.
  static List<Color> _colorsFromString(String string) {
    const maxColors = 4;
    final count = string.length ~/ 6;
    if (count == 0 || count > maxColors || string.length != count * 7 - 1) {
      return const [];
    }
    final result = <Color>[];
    for (int i = 0; i < count; i++) {
      if (i + 1 < count) {
        final sep = string[i * 7 + 6];
        // Invalid iff sep != '~' AND (count > 2 OR sep != '-').
        if (sep != '~' && (count > 2 || sep != '-')) {
          return const [];
        }
      }
      final c = _colorFromHex6(string.substring(i * 7, i * 7 + 6));
      if (c == null) return const [];
      result.add(c);
    }
    return result;
  }

  /// Port of `ColorFromString` (data_wall_paper.cpp:96-123): strict `rrggbb`
  /// hex (exactly 6 chars, only 0-9/a-f/A-F), alpha forced to 255.
  static Color? _colorFromHex6(String s) {
    if (s.length != 6) return null;
    for (int i = 0; i < 6; i++) {
      final ch = s.codeUnitAt(i);
      final isDigit = ch >= 0x30 && ch <= 0x39;
      final isLower = ch >= 0x61 && ch <= 0x66;
      final isUpper = ch >= 0x41 && ch <= 0x46;
      if (!isDigit && !isLower && !isUpper) return null;
    }
    return Color(0xFF000000 | int.parse(s, radix: 16));
  }

  /// Port of `StringFromColors` (data_wall_paper.cpp:163-173): joins each
  /// color's `rrggbb` hex with `~` (>2 colors) or `-` (<=2 colors).
  static String _stringFromColors(List<Color> colors) {
    final sep = colors.length > 2 ? '~' : '-';
    return colors
        .map((c) => (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0'))
        .join(sep);
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

    // Tiled images repeat a small bitmap; the tile painter must keep every tile
    // at native resolution, so it is never downscaled.
    if (wallpaper.tiled) {
      final Widget tiled = _TiledImage(imageBytes: wallpaper.imageBytes!);
      if (wallpaper.blurred) {
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: tiled,
        );
      }
      return tiled;
    }

    // Full-screen cover image: decode (and optionally pre-blur) at the actual
    // fill resolution instead of holding the stored full-size (≤2960px) source
    // and GPU-blurring it on every composite. Mirrors AyuGram scaling the
    // prepared image down to the chat-background rect (chat_theme.cpp:233-237)
    // and `PrepareBlurredBackground` pre-blurring a ≤900px copy once
    // (chat_theme.cpp:1173-1184).
    return _ScaledWallpaperImage(
      imageBytes: wallpaper.imageBytes!,
      blurred: wallpaper.blurred,
    );
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
      giftSymbols: wallpaper.giftSymbols,
      giftSymbolFrame: wallpaper.giftSymbolFrame,
    );
  }
}

// ===========================================================================
// Gradient image generation — ports of AyuGram's `lib_ui/ui/image/image_prepare.cpp`.
//
// AyuGram renders the chat-background gradient as a raster (64px complex gradient
// upscaled, or a linear gradient) which is then dithered. It never animates on a
// timer; for 3+-color (complex) gradients it advances one 45° step with a 200ms
// fade each time an outgoing message is revealed (chat_theme.cpp:638-669 +
// rotateComplexGradientBackground :822, triggered on `item->out() || isSelf()`).
// We reproduce that here: [_RasterGradient] listens to [ChatBackgroundRotator]
// and cross-fades to the next rotation on each pulse; the resting state is a
// static dithered raster. 2-color/linear gradients never rotate (the gate is
// `colors.size() >= 3`).
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

/// Generates the dithered RGBA buffer for a 2-4 color gradient. [progress]
/// (0..1) interpolates the complex-gradient control points between the previous
/// and current phase — only meaningful for 3+-color gradients (matches
/// `GenerateSmallComplexGradient`'s `progress` arg, image_prepare.cpp:175); it
/// is ignored for 2-color linear gradients.
Uint8List _generateGradientBytes(List<Color> colors, int rotation, int size,
    {double progress = 1.0}) {
  final raw = colors.length > 2
      ? _complexGradientPixels(colors, rotation, progress, size)
      : _linearGradientPixels(colors, rotation, size);
  return _ditherPixels(raw, size, size, _gradientSeed(colors, rotation));
}

/// Serializable argument bundle for the off-thread gradient generation (Color
/// is passed as its packed ARGB int so the message is trivially sendable across
/// the isolate boundary).
class _GradientGenRequest {
  final List<int> colorValues;
  final int rotation;
  final int size;
  final double progress;
  const _GradientGenRequest(
      this.colorValues, this.rotation, this.size, this.progress);
}

/// Top-level [compute] entry point — runs on a background isolate.
Uint8List _generateGradientBytesIsolate(_GradientGenRequest r) {
  final colors = r.colorValues.map((v) => Color(v)).toList();
  return _generateGradientBytes(colors, r.rotation, r.size,
      progress: r.progress);
}

/// Generates the dithered gradient pixel buffer **on a background isolate** via
/// [compute], instead of blocking the UI thread. The 256×256 complex gradient
/// (per-pixel sqrt/sin/cos × N colors) or 512×512 linear gradient PLUS the
/// full per-pixel dither pass is heavy enough to drop frames if run inline —
/// and it fires on every wallpaper change AND every send-triggered
/// complex-gradient rotation, i.e. exactly during the "background shifts when
/// you send" animation. Mirrors AyuGram, which runs the whole `CacheBackground`
/// (gradient + dither) on a worker thread via `crl::async` and marshals the
/// result back with `crl::on_main` (ui/chat/chat_theme.cpp:704-728).
///
/// On platforms without isolate support (web) [compute] transparently falls
/// back to a synchronous call, so behaviour is preserved there.
Future<Uint8List> _generateGradientBytesAsync(
    List<Color> colors, int rotation, int size,
    {double progress = 1.0}) {
  return compute(
    _generateGradientBytesIsolate,
    _GradientGenRequest(
        colors.map((c) => c.value).toList(), rotation, size, progress),
  );
}

/// The fixed 4-color default Telegram chat wallpaper, from AyuGram
/// `WallPaper::ConstructDefault` (data/data_wall_paper.cpp:710-715). These are
/// palette-independent — the default chat background looks the same under any
/// theme palette that does not embed its own background image.
const List<Color> kDefaultWallpaperColors = [
  Color(0xFFDBDDBB),
  Color(0xFF6BA587),
  Color(0xFFD5D88D),
  Color(0xFF88B884),
];

/// Static dithered RGBA8888 pixel buffer (`size`×`size`) for the default chat
/// wallpaper gradient — for callers that paint the wallpaper themselves into a
/// `Canvas` (e.g. the theme preview's history background) rather than mounting a
/// [ChatWallpaper] widget. Reuses the same complex-gradient + dither pipeline the
/// live renderer uses for [kDefaultWallpaperColors].
Uint8List defaultWallpaperGradientPixels({int size = 256}) =>
    _generateGradientBytes(kDefaultWallpaperColors, 0, size);

/// Decodes a raw RGBA8888 pixel buffer into a [ui.Image] (a `Future`-returning
/// wrapper over the callback-based [ui.decodeImageFromPixels]).
Future<ui.Image> decodeRgbaPixels(Uint8List bytes, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      bytes, width, height, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

/// Builds the default chat wallpaper as a single prepared [ui.Image]: the
/// 4-colour default gradient ([kDefaultWallpaperColors]) with the Telegram
/// doodle pattern overlaid at intensity 50 (soft-light, opacity 0.5). A Dart
/// port of AyuGram's
/// `PreparePatternImage(ReadBackgroundImage(":/gui/art/background.tgv"),
/// DefaultWallPaper().backgroundColors(), gradientRotation()=0,
/// patternOpacity()=0.5)` (ui/chat/chat_theme.cpp:1135 → GenerateBackgroundImage
/// :1103), as used by the theme-preview history background
/// (window/themes/window_theme_preview.cpp:468-480). [tgvBytes] is the gzipped
/// doodle SVG (`assets/images/background.tgv`). Returns null if the doodle can't
/// be decoded, so callers fall back to the plain gradient.
Future<ui.Image?> prepareDefaultPatternImage(Uint8List tgvBytes) async {
  // The doodle: gunzip + rasterize the SVG (≡ ReadBackgroundImage gzipSvg=true).
  final pattern = await _decodePatternBytes(tgvBytes);
  if (pattern == null) return null;
  final w = pattern.width;
  final h = pattern.height;
  if (w <= 0 || h <= 0) {
    pattern.dispose();
    return null;
  }

  // The base 4-colour default gradient, dithered — GenerateBackgroundImage
  // dithers when `bg.size() > 1 && patternOpacity >= 0` (our case). It is
  // generated square and stretched to the doodle's size, exactly as AyuGram
  // generates the gradient at `pattern.size()`.
  final gradient = await decodeRgbaPixels(
      defaultWallpaperGradientPixels(size: _kComplexGradientSize),
      _kComplexGradientSize,
      _kComplexGradientSize);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final dst = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  final hq = Paint()..filterQuality = FilterQuality.high;

  canvas.drawImageRect(
    gradient,
    Rect.fromLTWH(0, 0, gradient.width.toDouble(), gradient.height.toDouble()),
    dst,
    hq,
  );

  // Doodle overlay: soft-light at 0.5 opacity (intensity 50, patternOpacity >= 0
  // branch of GenerateBackgroundImage / _PatternWallpaperPainter). The default
  // colours are light, so IsPatternInverted() is false → the doodle's alpha is
  // not inverted; it is drawn once filling the whole rect (PreparePatternImage's
  // `p.drawImage(QRect(QPoint(), pattern.size()), pattern)`), not tiled.
  const patternOpacity = 0.5; // WallPaper::kDefaultIntensity (50) / 100.
  canvas.saveLayer(
    dst,
    Paint()
      ..blendMode = BlendMode.softLight
      ..color = Color.fromARGB((patternOpacity * 255).round(), 255, 255, 255),
  );
  canvas.drawImageRect(
    pattern,
    Rect.fromLTWH(0, 0, pattern.width.toDouble(), pattern.height.toDouble()),
    dst,
    hq,
  );
  canvas.restore();

  final image = await recorder.endRecording().toImage(w, h);
  gradient.dispose();
  pattern.dispose();
  return image;
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

/// Global signal that advances the chat-background complex-gradient rotation by
/// one step. Mirrors AyuGram's `ChatTheme::rotateComplexGradientBackground()`
/// (ui/chat/chat_theme.cpp:822), which is invoked when an outgoing message is
/// revealed in the active chat (history_widget.cpp:4096/7718,
/// history_view_list_widget.cpp:2131 — gated on `item->out() || peer->isSelf()`).
/// Live complex-gradient renderers ([_RasterGradient] with 3+ colors) listen and
/// step their rotation by one 45° phase with a 200ms cross-fade on each pulse;
/// solid / 2-color / image wallpapers ignore it.
class ChatBackgroundRotator extends ChangeNotifier {
  ChatBackgroundRotator._();
  static final ChatBackgroundRotator instance = ChatBackgroundRotator._();

  /// Advance the chat-background gradient one step. Call when an outgoing
  /// message is revealed in the active chat.
  void rotate() => notifyListeners();
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

class _RasterGradientState extends State<_RasterGradient>
    with SingleTickerProviderStateMixin {
  ui.Image? _image; // current rotation — fades IN on top
  ui.Image? _prevImage; // previous rotation — held underneath during the fade
  int _genToken = 0;
  int _doubled = 0; // doubled rotation accumulator in [0,720) (complex only)
  late final AnimationController _fade;

  // AyuGram `kBackgroundFadeDuration` (ui/chat/chat_theme.cpp:30).
  static const _kFadeDuration = Duration(milliseconds: 200);
  // AyuGram `kAddRotationDoubled` (chat_theme.cpp:646): one 45° step per send.
  static const _kAddRotationDoubled = 720 - 45;

  bool get _isComplex => widget.colors.length >= 3;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: _kFadeDuration,
      value: 1.0,
    )..addStatusListener(_onFadeStatus);
    if (_isComplex) {
      ChatBackgroundRotator.instance.addListener(_onRotate);
    }
    _generate(crossFade: false);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _prevImage != null) {
      setState(() {
        _prevImage?.dispose();
        _prevImage = null;
      });
    }
  }

  @override
  void didUpdateWidget(_RasterGradient old) {
    super.didUpdateWidget(old);
    final wasComplex = old.colors.length >= 3;
    if (wasComplex != _isComplex) {
      if (_isComplex) {
        ChatBackgroundRotator.instance.addListener(_onRotate);
      } else {
        ChatBackgroundRotator.instance.removeListener(_onRotate);
      }
    }
    if (old.rotation != widget.rotation ||
        !_sameColors(old.colors, widget.colors)) {
      // A genuine wallpaper change: snap back to the resting rotation and swap
      // without the send-style cross-fade.
      _doubled = 0;
      _generate(crossFade: false);
    }
  }

  @override
  void dispose() {
    ChatBackgroundRotator.instance.removeListener(_onRotate);
    _fade.dispose();
    _image?.dispose();
    _prevImage?.dispose();
    super.dispose();
  }

  /// One outgoing-message reveal → advance the complex gradient by one 45° step
  /// (mirrors `ChatTheme::rotateComplexGradientBackground`, chat_theme.cpp:822,
  /// stepping `gradientRotation` by `kAddRotationDoubled` mod 720, :663-665).
  void _onRotate() {
    if (!mounted || !_isComplex) return;
    _doubled = (_doubled + _kAddRotationDoubled) % 720;
    _generate(crossFade: true);
  }

  void _generate({required bool crossFade}) {
    final colors = List<Color>.from(widget.colors);
    final size =
        colors.length > 2 ? _kComplexGradientSize : _kLinearGradientSize;

    // For complex gradients the displayed rotation+progress are derived from the
    // doubled accumulator, mirroring `ComputeRealRotation`/`ComputeRealProgress`
    // (chat_theme.cpp:40-57). 2-color gradients use the static linear direction.
    final int rotation;
    final double progress;
    if (_isComplex) {
      final doubled = _doubled % 720;
      final odd = doubled.isOdd;
      rotation = ((odd ? (doubled - 45) : doubled) ~/ 2) % 360;
      progress = odd ? 0.5 : 1.0;
    } else {
      rotation = widget.rotation;
      progress = 1.0;
    }

    final token = ++_genToken;
    // Heavy gradient + dither generation runs OFF the UI thread (mirrors
    // AyuGram's `cacheBackgroundAsync` → `crl::async`, chat_theme.cpp:704-728);
    // a newer _generate() supersedes this one via the token check after the
    // await, so a burst of send-rotations never piles up stale frames.
    _generateGradientBytesAsync(colors, rotation, size, progress: progress)
        .then((bytes) {
      if (!mounted || token != _genToken) return;
      ui.decodeImageFromPixels(bytes, size, size, ui.PixelFormat.rgba8888,
          (image) {
        if (!mounted || token != _genToken) {
          image.dispose();
          return;
        }
        setState(() {
          if (crossFade && _image != null) {
            _prevImage?.dispose();
            _prevImage = _image;
            _image = image;
            _fade.forward(from: 0.0);
          } else {
            _prevImage?.dispose();
            _prevImage = null;
            _image?.dispose();
            _image = image;
            _fade.value = 1.0;
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RasterGradientPainter(
        prevImage: _prevImage,
        image: _image,
        fade: _fade,
        fallback: _averageOf(widget.colors, widget.fallbackColor),
      ),
      size: Size.infinite,
    );
  }
}

class _RasterGradientPainter extends CustomPainter {
  final ui.Image? prevImage;
  final ui.Image? image;
  final Animation<double> fade;
  final Color fallback;

  _RasterGradientPainter({
    required this.prevImage,
    required this.image,
    required this.fade,
    required this.fallback,
  }) : super(repaint: fade);

  void _drawImage(Canvas canvas, Rect rect, ui.Image image, double opacity) {
    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (opacity < 1.0) {
      paint.color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    }
    canvas.drawImageRect(image, src, rect, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final image = this.image;
    if (image == null) {
      canvas.drawRect(rect, Paint()..color = fallback);
      return;
    }
    final shown = fade.value;
    // Previous rotation underneath (opaque), new rotation fading in on top —
    // matching AyuGram's `_backgroundState.was` + `now` drawn at `shown` opacity.
    if (prevImage != null && shown < 1.0) {
      _drawImage(canvas, rect, prevImage!, 1.0);
      _drawImage(canvas, rect, image, shown);
    } else {
      _drawImage(canvas, rect, image, 1.0);
    }
  }

  @override
  bool shouldRepaint(_RasterGradientPainter old) =>
      !identical(old.image, image) ||
      !identical(old.prevImage, prevImage) ||
      old.fallback != fallback;
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

/// Full-screen chat-background image, decoded — and, when requested, blurred —
/// at the actual fill resolution rather than the stored full size. Ports two
/// AyuGram optimisations the naive `Image.memory` + per-frame `ImageFiltered`
/// path skipped:
///
///  * **Scale-to-fill** — AyuGram scales the prepared image down to the chat
///    background rect before painting (`ComputeChatBackgroundRects` + `scaled`,
///    chat_theme.cpp:230-238). Stored wallpapers are capped at 2960px, so a
///    full-screen image shown at ~400–1280px would otherwise decode/retain ~8×
///    the pixels actually drawn. We decode to the cover size for the current
///    fill area (never upscaling past the source).
///  * **Cached ≤900px pre-blur** — AyuGram blurs a downscaled (≤900px) copy
///    ONCE and caches it (`PrepareBlurredBackground`, chat_theme.cpp:1173-1184)
///    instead of GPU-blurring the full-res image every frame. We pre-blur the
///    decoded image into a cached [ui.Image] and just blit it afterwards.
class _ScaledWallpaperImage extends StatefulWidget {
  final Uint8List imageBytes;
  final bool blurred;

  const _ScaledWallpaperImage({
    required this.imageBytes,
    required this.blurred,
  });

  @override
  State<_ScaledWallpaperImage> createState() => _ScaledWallpaperImageState();
}

class _ScaledWallpaperImageState extends State<_ScaledWallpaperImage> {
  // AyuGram PrepareBlurredBackground kSize / kRadius (chat_theme.cpp:1174-1175).
  static const int kBlurMaxSize = 900;
  static const double kBlurSigma = 24;

  ui.Image? _image;
  int _token = 0;
  Size _decodedFor = Size.zero; // completed decode target (device px)
  Size _pendingFor = Size.zero; // in-flight decode target (device px)

  @override
  void didUpdateWidget(_ScaledWallpaperImage old) {
    super.didUpdateWidget(old);
    if (!identical(old.imageBytes, widget.imageBytes) ||
        old.blurred != widget.blurred) {
      _token++; // drop any in-flight decode for the previous config
      _decodedFor = Size.zero;
      _pendingFor = Size.zero;
      // The fresh decode is kicked off by the build() that follows this call.
    }
  }

  @override
  void dispose() {
    _token++;
    _image?.dispose();
    super.dispose();
  }

  void _ensureDecoded(Size targetDevicePx) {
    if (targetDevicePx.width <= 0 || targetDevicePx.height <= 0) return;
    // Decode when we have nothing yet, or the fill area grew meaningfully (a
    // 10%+8px tolerance avoids a decode storm while a window is being resized).
    final grew = targetDevicePx.width > _decodedFor.width * 1.1 + 8 ||
        targetDevicePx.height > _decodedFor.height * 1.1 + 8;
    if (_image != null && !grew) return;
    if (_pendingFor == targetDevicePx) return; // already decoding this size
    _pendingFor = targetDevicePx;
    final token = ++_token;
    _decodeScaledWallpaper(widget.imageBytes, targetDevicePx, widget.blurred)
        .then((decoded) {
      if (!mounted || token != _token) {
        decoded?.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = decoded;
        _decodedFor = targetDevicePx;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
      // setState (inside _ensureDecoded) only fires after the decode's first
      // await, i.e. a later turn — never during this build.
      _ensureDecoded(Size(w * dpr, h * dpr));
      final image = _image;
      if (image == null) return const SizedBox.expand();
      return CustomPaint(size: Size.infinite, painter: _CoverImagePainter(image));
    });
  }
}

/// Decodes [bytes] scaled down to cover [fillDevicePx] (never upscaling past the
/// source), and — when [blur] — downsizes to ≤900px and bakes a one-time blur
/// into the returned cached image. Uses [ui.ImageDescriptor] so the source is
/// only ever rasterised at the size actually needed.
Future<ui.Image?> _decodeScaledWallpaper(
    Uint8List bytes, Size fillDevicePx, bool blur) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final iw = descriptor.width, ih = descriptor.height;
    if (iw <= 0 || ih <= 0) return null;
    // Cover scale: fill the area on both axes, clamped so we never decode the
    // source larger than it actually is.
    double s = math.max(fillDevicePx.width / iw, fillDevicePx.height / ih);
    if (s > 1.0 || !s.isFinite) s = 1.0;
    int tw = math.max(1, (iw * s).round());
    int th = math.max(1, (ih * s).round());
    // Blurred copies are downscaled to ≤900px before blurring (cheap + cached).
    if (blur) {
      final longest = math.max(tw, th);
      if (longest > _ScaledWallpaperImageState.kBlurMaxSize) {
        final bs = _ScaledWallpaperImageState.kBlurMaxSize / longest;
        tw = math.max(1, (tw * bs).round());
        th = math.max(1, (th * bs).round());
      }
    }
    codec = await descriptor.instantiateCodec(targetWidth: tw, targetHeight: th);
    final frame = await codec.getNextFrame();
    var image = frame.image;
    if (blur) {
      final blurred = _preBlurImage(image, _ScaledWallpaperImageState.kBlurSigma);
      image.dispose();
      image = blurred;
    }
    return image;
  } catch (e) {
    Debug.log('wallpaper', '_decodeScaledWallpaper: $e');
    return null;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Bakes a one-time gaussian blur into a cached [ui.Image] (the Dart equivalent
/// of AyuGram caching `Images::BlurLargeImage`, chat_theme.cpp:1183), so the
/// composite never re-runs the blur on every frame.
ui.Image _preBlurImage(ui.Image src, double sigma) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(
    src,
    Offset.zero,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp)
      ..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final out = picture.toImageSync(src.width, src.height);
  picture.dispose();
  return out;
}

/// Paints a pre-scaled [ui.Image] with `BoxFit.cover` semantics (fill, then
/// center-crop the overflow) — matching AyuGram's chat-background fill rect.
class _CoverImagePainter extends CustomPainter {
  final ui.Image image;

  _CoverImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) return;
    final scale = math.max(size.width / iw, size.height / ih);
    final dw = iw * scale, dh = ih * scale;
    final dx = (size.width - dw) / 2, dy = (size.height - dh) / 2;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH(dx, dy, dw, dh),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_CoverImagePainter old) => !identical(old.image, image);
}

class _PatternWallpaper extends StatefulWidget {
  final List<Color> backgroundColors;
  final int gradientRotation;
  final Uint8List patternBytes;
  final int intensity;
  final double opacity;
  final Color fallbackColor;
  final List<WallpaperGiftSymbol> giftSymbols;
  final Uint8List? giftSymbolFrame;

  const _PatternWallpaper({
    required this.backgroundColors,
    required this.gradientRotation,
    required this.patternBytes,
    required this.intensity,
    required this.opacity,
    required this.fallbackColor,
    this.giftSymbols = const [],
    this.giftSymbolFrame,
  });

  @override
  State<_PatternWallpaper> createState() => _PatternWallpaperState();
}

class _PatternWallpaperState extends State<_PatternWallpaper> {
  ui.Image? _gradientImage;
  ui.Image? _patternImage;
  ui.Image? _giftFrameImage;
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
    if (!identical(old.patternBytes, widget.patternBytes) ||
        !identical(old.giftSymbols, widget.giftSymbols) ||
        !identical(old.giftSymbolFrame, widget.giftSymbolFrame)) {
      _decodePattern();
    }
  }

  @override
  void dispose() {
    _gradientImage?.dispose();
    _patternImage?.dispose();
    _giftFrameImage?.dispose();
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
    final token = ++_gradToken;
    // Off-thread gradient + dither generation (chat_theme.cpp:704-728), so the
    // pattern's underlying gradient never janks the UI thread on a wallpaper
    // change.
    _generateGradientBytesAsync(colors, widget.gradientRotation, size)
        .then((bytes) {
      if (!mounted || token != _gradToken) return;
      ui.decodeImageFromPixels(bytes, size, size, ui.PixelFormat.rgba8888,
          (image) {
        if (!mounted || token != _gradToken) {
          image.dispose();
          return;
        }
        setState(() {
          _gradientImage?.dispose();
          _gradientImage = image;
        });
      });
    });
  }

  Future<void> _decodePattern() async {
    final token = ++_patToken;
    ui.Image? tile;
    ui.Image? frame;
    if (widget.giftSymbols.isNotEmpty) {
      // Collectible-gift pattern: cut the `GiftPatterns` group out of the tile
      // and supply the gift symbol frame (chat_theme.cpp:120-202).
      final result = await _decodeGiftPattern(
          widget.patternBytes, widget.giftSymbols, widget.giftSymbolFrame);
      tile = result.$1;
      frame = result.$2;
    } else {
      tile = await _decodePatternBytes(widget.patternBytes);
    }
    if (!mounted || token != _patToken) {
      tile?.dispose();
      frame?.dispose();
      return;
    }
    setState(() {
      _patternImage?.dispose();
      _patternImage = tile;
      _giftFrameImage?.dispose();
      _giftFrameImage = frame;
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
        giftSymbols: widget.giftSymbols,
        giftFrame: _giftFrameImage,
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
    } catch (e) {
      Debug.log('wallpaper', 'data = Uint8List.fromList(GZipDecoder().decodeBytes(data)): $e');
    }
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

// ===========================================================================
// Collectible-gift pattern wallpapers — ports of AyuGram's gift-symbol tiling
// (ui/chat/chat_theme.cpp:59-202) and the `GiftPatterns` SVG cut-out
// (lib_ui/ui/image/image_prepare.cpp:404-413).
//
// A gift wallpaper's pattern document embeds a `<g id="GiftPatterns"> … </g>`
// group of `<rect>` placeholders (each a normalized position + optional
// rotation) that mark where the gift's symbol custom-emoji should be stamped.
// AyuGram cuts that group out of the tiled pattern and re-stamps the gift's
// emoji frame at each position — rotated, at 0.8 opacity — skipping the
// most-central slot for the live gift itself, which it overlays separately.
// ===========================================================================

/// Locates the `<g id="GiftPatterns" …> … </g>` group inside a (gzipped)
/// pattern document and returns its raw inner content plus the SVG viewBox used
/// to normalize coordinates. Mirrors the `svgCutOutId = "GiftPatterns"` lookup
/// in `Images::Read` (image_prepare.cpp:404-409) — the `id` must be the first
/// attribute on the `<g>`, exactly as AyuGram requires. Returns null for an
/// ordinary (non-gift) pattern.
({String content, double vbW, double vbH})? _extractGiftPatternsGroup(
    Uint8List bytes) {
  var data = bytes;
  if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
    try {
      data = Uint8List.fromList(GZipDecoder().decodeBytes(data));
    } catch (_) {
      return null;
    }
  }
  if (!_looksLikeSvg(data)) return null;
  final svg = utf8.decode(data, allowMalformed: true);
  final start = svg.indexOf('<g id="GiftPatterns"');
  if (start < 0) return null;
  final end = svg.indexOf('</g>', start);
  if (end < 0) return null;
  final vb = _svgViewBox(svg);
  if (vb == null) return null;
  return (content: svg.substring(start, end + 4), vbW: vb.$1, vbH: vb.$2);
}

/// SVG root user-unit dimensions (viewBox, else width/height) used to normalize
/// gift-symbol rects into `[0,1]`.
(double, double)? _svgViewBox(String svg) {
  final vbMatch = RegExp(r'viewBox\s*=\s*"([^"]*)"').firstMatch(svg);
  if (vbMatch != null) {
    final parts = vbMatch.group(1)!.trim().split(RegExp(r'[\s,]+'));
    if (parts.length == 4) {
      final w = double.tryParse(parts[2]);
      final h = double.tryParse(parts[3]);
      if (w != null && h != null && w > 0 && h > 0) return (w, h);
    }
  }
  final wMatch = RegExp(r'<svg[^>]*\bwidth\s*=\s*"([\d.]+)').firstMatch(svg);
  final hMatch = RegExp(r'<svg[^>]*\bheight\s*=\s*"([\d.]+)').firstMatch(svg);
  final w = wMatch != null ? double.tryParse(wMatch.group(1)!) : null;
  final h = hMatch != null ? double.tryParse(hMatch.group(1)!) : null;
  if (w != null && h != null && w > 0 && h > 0) return (w, h);
  return null;
}

/// Port of `ParseGiftSymbols` (chat_theme.cpp:1015-1077): parses each
/// `<rect x=".." y=".." width=".." height=".." [transform=rotate(deg)]/>` in the
/// cut-out `GiftPatterns` group into a normalized [WallpaperGiftSymbol]. Rect
/// coordinates are SVG user units divided by the viewBox, so `area` ends up in
/// `[0,1]` within a tile (equivalent to AyuGram's `cw = scale / size.width`).
List<WallpaperGiftSymbol> parseGiftSymbolsFromTgv(Uint8List bytes) {
  final group = _extractGiftPatternsGroup(bytes);
  if (group == null) return const [];
  final cw = 1.0 / group.vbW;
  final ch = 1.0 / group.vbH;
  final rectRe = RegExp(r'<rect\b([^>]*?)/?>', dotAll: true);
  final xRe = RegExp(r'\bx\s*=\s*"([-\d.eE]+)"');
  final yRe = RegExp(r'\by\s*=\s*"([-\d.eE]+)"');
  final wRe = RegExp(r'\bwidth\s*=\s*"([-\d.eE]+)"');
  final hRe = RegExp(r'\bheight\s*=\s*"([-\d.eE]+)"');
  final rotRe = RegExp(r'rotate\(\s*([-\d.eE]+)');
  final result = <WallpaperGiftSymbol>[];
  for (final m in rectRe.allMatches(group.content)) {
    final attrs = m.group(1)!;
    final x = double.tryParse(xRe.firstMatch(attrs)?.group(1) ?? '');
    final y = double.tryParse(yRe.firstMatch(attrs)?.group(1) ?? '');
    final w = double.tryParse(wRe.firstMatch(attrs)?.group(1) ?? '');
    final h = double.tryParse(hRe.firstMatch(attrs)?.group(1) ?? '');
    if (x == null || y == null || w == null || h == null) continue;
    final rot =
        double.tryParse(rotRe.firstMatch(attrs)?.group(1) ?? '') ?? 0.0;
    result.add(WallpaperGiftSymbol(
      area: Rect.fromLTWH(x * cw, y * ch, w * cw, h * ch),
      rotation: rot,
    ));
  }
  return result;
}

/// Port of `ChooseGiftSymbolSkip` (chat_theme.cpp:59-78): selects the symbol
/// whose center is most central AND whose area is largest — the slot reserved
/// for the gift itself (left empty in the center tile, drawn as a distinct
/// overlay). Returns -1 for an empty list.
int chooseGiftSymbolSkip(List<WallpaperGiftSymbol> symbols) {
  if (symbols.isEmpty) return -1;
  var maxIndex = -1;
  var maxValue = 0.0;
  for (int i = 0; i < symbols.length; i++) {
    final c = symbols[i].area.center;
    final value = math.min(c.dx, 1.0 - c.dx) *
        math.min(c.dy, 1.0 - c.dy) *
        math.min(symbols[i].area.width, symbols[i].area.height);
    if (maxIndex < 0 || maxValue < value) {
      maxIndex = i;
      maxValue = value;
    }
  }
  return maxIndex;
}

/// Decodes a gift-pattern document into `(tile, frame)`:
///  * **tile** — the pattern SVG with its `GiftPatterns` group removed, so the
///    placeholder rects are not double-drawn under the stamped symbols
///    (mirrors the `svgCutOutId` removal, image_prepare.cpp:410).
///  * **frame** — the gift symbol raster: the explicit gift custom-emoji frame
///    when supplied, otherwise derived from the document itself by rasterizing
///    the full SVG and cropping the most-central symbol's region.
Future<(ui.Image?, ui.Image?)> _decodeGiftPattern(Uint8List bytes,
    List<WallpaperGiftSymbol> symbols, Uint8List? explicitFrame) async {
  var data = bytes;
  if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
    try {
      data = Uint8List.fromList(GZipDecoder().decodeBytes(data));
    } catch (e) {
      Debug.log('wallpaper', '_decodeGiftPattern gunzip: $e');
    }
  }
  if (!_looksLikeSvg(data)) {
    // Raster gift pattern (no SVG cut-out possible): tile it plainly and use
    // the explicit frame if any.
    final tile = await _decodePatternBytes(bytes);
    final frame =
        explicitFrame != null ? await _decodeRaster(explicitFrame) : null;
    return (tile, frame);
  }

  final svg = utf8.decode(data, allowMalformed: true);
  var tileSvg = svg;
  final start = svg.indexOf('<g id="GiftPatterns"');
  if (start >= 0) {
    final end = svg.indexOf('</g>', start);
    if (end >= 0) {
      tileSvg = svg.substring(0, start) + svg.substring(end + 4);
    }
  }
  final tile = await _rasterizeSvg(Uint8List.fromList(utf8.encode(tileSvg)));

  ui.Image? frame;
  if (explicitFrame != null) {
    frame = await _decodeRaster(explicitFrame);
  } else {
    final full = await _rasterizeSvg(data);
    if (full != null) {
      final skip = chooseGiftSymbolSkip(symbols);
      if (skip >= 0) {
        frame = _cropSymbolFrame(full, symbols[skip].area);
      }
      full.dispose();
    }
  }
  return (tile, frame);
}

/// Crops the normalized [normArea] region out of a rendered pattern image,
/// producing the gift symbol frame to stamp. Used when no explicit gift emoji
/// frame is available — the artwork comes straight from the document.
ui.Image? _cropSymbolFrame(ui.Image full, Rect normArea) {
  final fw = full.width.toDouble();
  final fh = full.height.toDouble();
  final sx = normArea.left * fw;
  final sy = normArea.top * fh;
  final sw = normArea.width * fw;
  final sh = normArea.height * fh;
  final outW = sw.round();
  final outH = sh.round();
  if (outW <= 0 || outH <= 0) return null;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    full,
    Rect.fromLTWH(sx, sy, sw, sh),
    Rect.fromLTWH(0, 0, sw, sh),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final out = picture.toImageSync(outW, outH);
  picture.dispose();
  return out;
}

class _PatternWallpaperPainter extends CustomPainter {
  final List<Color> colors;
  final ui.Image? gradientImage;
  final ui.Image? patternImage;
  final int intensity;
  final double opacity;
  final Color fallbackColor;
  final List<WallpaperGiftSymbol> giftSymbols;
  final ui.Image? giftFrame;

  _PatternWallpaperPainter({
    required this.colors,
    required this.gradientImage,
    required this.patternImage,
    required this.intensity,
    required this.opacity,
    required this.fallbackColor,
    this.giftSymbols = const [],
    this.giftFrame,
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

    // Collectible-gift symbols are stamped only over positive-intensity
    // (soft-light) patterns, exactly as AyuGram only paints them on the
    // `isPattern` tile (chat_theme.cpp:120-202).
    final hasGifts =
        giftFrame != null && giftSymbols.isNotEmpty && intensity >= 0;

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
      _tilePattern(canvas, size, pattern, paint, stampGifts: hasGifts);
      canvas.restore();
      // The reserved center slot is filled by the gift itself, drawn distinct
      // (full opacity, outside the soft-light layer) like AyuGram overlaying the
      // live gift custom-emoji at `giftArea` (chat_theme.cpp:189-202).
      if (hasGifts) {
        _drawGiftOverlay(canvas, size, pattern);
      }
    } else {
      canvas.saveLayer(rect, Paint());
      _drawGradient(canvas, size);
      _tilePattern(
        canvas,
        size,
        pattern,
        Paint()..blendMode = BlendMode.dstIn,
        stampGifts: false,
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

  /// Pattern tile geometry (`chat_theme.cpp:122-185`): the pattern scaled
  /// (KeepAspectRatio) to a square the height of the area, the odd/centered
  /// column count, the row count, and the centering x-shift.
  _PatternTiling? _computeTiling(Size size, ui.Image pattern) {
    final scale = size.height / math.max(pattern.width, pattern.height);
    final tw = pattern.width * scale;
    final th = pattern.height * scale;
    if (tw <= 0 || th <= 0) return null;
    final cx = (size.width / tw).ceil();
    final cy = (size.height / th).ceil();
    final cols = ((cx ~/ 2) * 2) + 1;
    final rows = cy;
    final xshift = (size.width - cols * tw) / 2;
    return _PatternTiling(tw: tw, th: th, xshift: xshift, cols: cols, rows: rows);
  }

  /// Port of the pattern tiling in `chat_theme.cpp:122-210`: the pattern is
  /// scaled (KeepAspectRatio) to fit a square the height of the area, then tiled
  /// across BOTH rows and columns. The column count is forced odd and centered
  /// (`((cx/2)*2)+1`), matching AyuGram's pattern layout. When [stampGifts] is
  /// set, the gift symbol frame is stamped (rotated, 0.8 opacity) at every
  /// symbol position on every tile — except the most-central symbol on the
  /// center-top tile, whose slot is reserved for the gift overlay
  /// (chat_theme.cpp:162-210).
  void _tilePattern(Canvas canvas, Size size, ui.Image pattern, Paint paint,
      {required bool stampGifts}) {
    final t = _computeTiling(size, pattern);
    if (t == null) return;
    final src = Rect.fromLTWH(
        0, 0, pattern.width.toDouble(), pattern.height.toDouble());
    final skipCol = t.cols ~/ 2;
    final skip = stampGifts ? chooseGiftSymbolSkip(giftSymbols) : -1;
    for (int y = 0; y < t.rows; y++) {
      for (int x = 0; x < t.cols; x++) {
        final tileX = t.xshift + x * t.tw;
        final tileY = y * t.th;
        canvas.drawImageRect(
            pattern, src, Rect.fromLTWH(tileX, tileY, t.tw, t.th), paint);
        if (stampGifts) {
          for (int i = 0; i < giftSymbols.length; i++) {
            if (x == skipCol && y == 0 && i == skip) continue;
            _stampGiftSymbol(canvas, tileX, tileY, t.tw, t.th, giftSymbols[i],
                opacity: 0.8);
          }
        }
      }
    }
  }

  /// Draws the gift symbol frame for one [symbol] within the tile at
  /// (`tileX`,`tileY`): scaled so its width fills the symbol rect and rotated
  /// about the rect center — the Dart equivalent of `giftSymbolPaint`
  /// (chat_theme.cpp:143-160). [opacity] modulates the frame alpha (0.8 for the
  /// tiled symbols, 1.0 for the center gift overlay).
  void _stampGiftSymbol(Canvas canvas, double tileX, double tileY, double tw,
      double th, WallpaperGiftSymbol symbol,
      {required double opacity}) {
    final frame = giftFrame;
    if (frame == null || frame.width <= 0) return;
    final left = tileX + symbol.area.left * tw;
    final top = tileY + symbol.area.top * th;
    final w = symbol.area.width * tw;
    if (w <= 0) return;
    final h = w * frame.height / frame.width; // square emoji → h == w
    final centerX = left + w / 2;
    final centerY = top + h / 2;
    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.rotate(symbol.rotation * math.pi / 180.0);
    canvas.translate(-centerX, -centerY);
    canvas.drawImageRect(
      frame,
      Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
      Rect.fromLTWH(left, top, w, h),
      Paint()
        ..filterQuality = FilterQuality.high
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    canvas.restore();
  }

  /// Draws the gift itself in the reserved center-top slot (the symbol skipped
  /// in [_tilePattern]) — full opacity, normal blend, so the collectible gift
  /// stands distinct from the soft-light-tinted tiled symbols, mirroring
  /// AyuGram overlaying the live gift custom-emoji at `giftArea`
  /// (chat_theme.cpp:189-202).
  void _drawGiftOverlay(Canvas canvas, Size size, ui.Image pattern) {
    final skip = chooseGiftSymbolSkip(giftSymbols);
    if (skip < 0) return;
    final t = _computeTiling(size, pattern);
    if (t == null) return;
    final tileX = t.xshift + (t.cols ~/ 2) * t.tw;
    _stampGiftSymbol(canvas, tileX, 0.0, t.tw, t.th, giftSymbols[skip],
        opacity: 1.0);
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
      !identical(old.giftFrame, giftFrame) ||
      !identical(old.giftSymbols, giftSymbols) ||
      old.colors != colors ||
      old.intensity != intensity ||
      old.opacity != opacity ||
      old.fallbackColor != fallbackColor;
}

/// Resolved pattern tile geometry shared by [_PatternWallpaperPainter] between
/// the pattern tiling and the gift-symbol stamping.
class _PatternTiling {
  final double tw;
  final double th;
  final double xshift;
  final int cols;
  final int rows;

  const _PatternTiling({
    required this.tw,
    required this.th,
    required this.xshift,
    required this.cols,
    required this.rows,
  });
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
