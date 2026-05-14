import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

const int _kFrameCount = 60;
const int _kFramesPerRow = 10;
const int _kRows = 6;
const double _kCanvasSize = 128.0;
const int _kSpriteVariants = 5;
const double _kParticleSizeMin = 1.5;
const double _kParticleSizeMax = 2.0;
const int _kAutoPauseTimeoutMs = 1000;
const int _kColorCacheCapacity = 24;
const double kSpoilerHiddenOpacity = 0.5;
const int _kCacheVersion = 2;
const int _kCacheHeaderSize = 20;
const int _kImageSpoilerDarkenAlpha = 32;

enum SpoilerType { text, image }

class SpoilerSpriteSheet {
  final ui.Image image;
  final double tileSize;
  SpoilerSpriteSheet(this.image, this.tileSize);

  Rect frameRect(int frame) {
    final col = frame % _kFramesPerRow;
    final row = frame ~/ _kFramesPerRow;
    return Rect.fromLTWH(col * tileSize, row * tileSize, tileSize, tileSize);
  }
}

class SpoilerAnimationManager {
  SpoilerAnimationManager._();
  static final instance = SpoilerAnimationManager._();

  static String _cacheDir = '';
  static void setCacheDir(String dir) => _cacheDir = dir;

  SpoilerSpriteSheet? _textSheet;
  SpoilerSpriteSheet? _imageSheet;
  bool _textGenerating = false;
  bool _imageGenerating = false;

  final _textCompleters = <Completer<SpoilerSpriteSheet>>[];
  final _imageCompleters = <Completer<SpoilerSpriteSheet>>[];

  int _activeCount = 0;
  bool _ticking = false;
  int _currentFrame = 0;
  final _listeners = <VoidCallback>{};

  bool powerSavingPaused = false;

  int get currentFrame => _currentFrame;

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);

  void register() {
    _activeCount++;
    _ensureTicking();
  }

  void unregister() {
    _activeCount--;
    if (_activeCount < 0) _activeCount = 0;
  }

  void _ensureTicking() {
    if (_ticking || _activeCount <= 0) return;
    _ticking = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _onFrame(Duration timestamp) {
    _ticking = false;
    if (_activeCount <= 0 || _listeners.isEmpty) return;
    if (!powerSavingPaused) {
      final frame = (timestamp.inMilliseconds ~/ 33) % _kFrameCount;
      if (frame != _currentFrame) {
        _currentFrame = frame;
        for (final cb in List.of(_listeners)) {
          cb();
        }
      }
    }
    if (_activeCount > 0) {
      _ticking = true;
      SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
    }
  }

  Future<SpoilerSpriteSheet> getSheet(SpoilerType type) {
    final existing = type == SpoilerType.text ? _textSheet : _imageSheet;
    if (existing != null) return Future.value(existing);

    final completer = Completer<SpoilerSpriteSheet>();
    if (type == SpoilerType.text) {
      _textCompleters.add(completer);
      if (!_textGenerating) {
        _textGenerating = true;
        _generateSheet(type);
      }
    } else {
      _imageCompleters.add(completer);
      if (!_imageGenerating) {
        _imageGenerating = true;
        _generateSheet(type);
      }
    }
    return completer.future;
  }

  Future<void> _generateSheet(SpoilerType type) async {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final expectedTileSize = (_kCanvasSize * dpr).roundToDouble();
    final cached = await _loadSpoilerCache(type, expectedTileSize);
    final sheet = cached ?? await _renderSpriteSheet(type);
    if (cached == null) {
      _saveSpoilerCache(type, sheet.image);
    }
    if (type == SpoilerType.text) {
      _textSheet = sheet;
      for (final c in _textCompleters) {
        c.complete(sheet);
      }
      _textCompleters.clear();
    } else {
      _imageSheet = sheet;
      for (final c in _imageCompleters) {
        c.complete(sheet);
      }
      _imageCompleters.clear();
    }
  }
}

String _spoilerCacheDir() {
  if (SpoilerAnimationManager._cacheDir.isEmpty) return '';
  return '${SpoilerAnimationManager._cacheDir}/spoiler';
}

int _fnv1a32(Uint8List data) {
  int hash = 0x811c9dc5;
  for (int i = 0; i < data.length; i++) {
    hash ^= data[i];
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

Future<SpoilerSpriteSheet?> _loadSpoilerCache(
    SpoilerType type, double expectedTileSize) async {
  final cacheBase = _spoilerCacheDir();
  if (cacheBase.isEmpty) return null;
  try {
    final name = type == SpoilerType.text ? 'text' : 'image';
    final file = File('$cacheBase/$name.bin');
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length <= _kCacheHeaderSize) return null;

    final header = ByteData.sublistView(bytes, 0, _kCacheHeaderSize);
    final version = header.getUint32(0, Endian.little);
    final framesCount = header.getUint32(4, Endian.little);
    final canvasSize = header.getUint32(8, Endian.little);
    final dataLen = header.getUint32(12, Endian.little);
    final storedHash = header.getUint32(16, Endian.little);

    if (version != _kCacheVersion ||
        framesCount != _kFrameCount ||
        canvasSize != expectedTileSize.round() ||
        _kCacheHeaderSize + dataLen != bytes.length) {
      return null;
    }

    final pngData = Uint8List.sublistView(bytes, _kCacheHeaderSize);
    if (_fnv1a32(pngData) != storedHash) return null;

    final codec = await ui.instantiateImageCodec(pngData);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final tileSize = image.width.toDouble() / _kFramesPerRow;
    if ((tileSize - expectedTileSize).abs() > 0.5) {
      image.dispose();
      return null;
    }
    return SpoilerSpriteSheet(image, tileSize);
  } catch (_) {
    return null;
  }
}

Future<void> _saveSpoilerCache(SpoilerType type, ui.Image image) async {
  final cacheBase = _spoilerCacheDir();
  if (cacheBase.isEmpty) return;
  try {
    final dir = Directory(cacheBase);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final name = type == SpoilerType.text ? 'text' : 'image';
    final file = File('${dir.path}/$name.bin');
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final pngData = byteData.buffer.asUint8List();
    final tileSize = image.width ~/ _kFramesPerRow;

    final header = ByteData(_kCacheHeaderSize);
    header.setUint32(0, _kCacheVersion, Endian.little);
    header.setUint32(4, _kFrameCount, Endian.little);
    header.setUint32(8, tileSize, Endian.little);
    header.setUint32(12, pngData.length, Endian.little);
    header.setUint32(16, _fnv1a32(pngData), Endian.little);

    final out = Uint8List(_kCacheHeaderSize + pngData.length);
    out.setRange(0, _kCacheHeaderSize, header.buffer.asUint8List());
    out.setRange(_kCacheHeaderSize, out.length, pngData);
    await file.writeAsBytes(out);
  } catch (_) {}
}

class _ParticleParams {
  final double tilePx, dpr;
  final bool isText;
  const _ParticleParams(this.tilePx, this.dpr, this.isText);
}

List<Float64List> _computeParticleFrameData(_ParticleParams params) {
  final tilePx = params.tilePx;
  final dpr = params.dpr;
  final isText = params.isText;

  final count = isText ? 9000 : 3000;
  final speedMin = isText ? 4.0 : 10.0;
  final speedMax = isText ? 8.0 : 20.0;
  final fadeInFrames = ((isText ? 200 : 300) / 33).round();
  final shownFrames = ((isText ? 200 : 0) / 33).round();
  final fadeOutFrames = ((isText ? 200 : 300) / 33).round();
  final totalLifetimeFrames = fadeInFrames + shownFrames + fadeOutFrames;

  final rng = math.Random(42);
  final speedRange = speedMax - speedMin;
  final sizeRange = _kParticleSizeMax - _kParticleSizeMin;

  final px = Float64List(count);
  final py = Float64List(count);
  final pvx = Float64List(count);
  final pvy = Float64List(count);
  final psize = Float64List(count);
  final pbirth = Int32List(count);
  final pshape = Int32List(count);

  for (int i = 0; i < count; i++) {
    final spd = rng.nextDouble() * speedRange + speedMin;
    final xDir = rng.nextDouble() * 2.0 - 1.0;
    final yDir = math.sqrt((1.0 - xDir * xDir).clamp(0.0, 1.0)) *
        (rng.nextBool() ? 1.0 : -1.0);
    px[i] = rng.nextDouble() * tilePx;
    py[i] = rng.nextDouble() * tilePx;
    pvx[i] = spd * xDir * dpr * 0.033;
    pvy[i] = spd * yDir * dpr * 0.033;
    psize[i] = (_kParticleSizeMin + rng.nextDouble() * sizeRange) * dpr;
    pbirth[i] = (i * _kFrameCount) ~/ count;
    pshape[i] = rng.nextInt(_kSpriteVariants);
  }

  return List<Float64List>.generate(_kFrameCount, (f) {
    final cmds = <double>[];
    for (int i = 0; i < count; i++) {
      int age = (f - pbirth[i]) % _kFrameCount;
      if (age < 0) age += _kFrameCount;
      if (age >= totalLifetimeFrames) continue;

      double alpha;
      if (age < fadeInFrames) {
        alpha = fadeInFrames > 0 ? age / fadeInFrames : 1.0;
      } else if (age < fadeInFrames + shownFrames) {
        alpha = 1.0;
      } else {
        final fadeAge = age - fadeInFrames - shownFrames;
        alpha = fadeOutFrames > 0 ? 1.0 - fadeAge / fadeOutFrames : 0.0;
      }
      if (alpha <= 0) continue;

      double ppx = (px[i] + pvx[i] * age) % tilePx;
      double ppy = (py[i] + pvy[i] * age) % tilePx;
      if (ppx < 0) ppx += tilePx;
      if (ppy < 0) ppy += tilePx;

      cmds.addAll([ppx, ppy, alpha, pshape[i].toDouble()]);
      if (ppx + psize[i] > tilePx) {
        cmds.addAll([ppx - tilePx, ppy, alpha, pshape[i].toDouble()]);
      }
      if (ppy + psize[i] > tilePx) {
        cmds.addAll([ppx, ppy - tilePx, alpha, pshape[i].toDouble()]);
      }
      if (ppx + psize[i] > tilePx && ppy + psize[i] > tilePx) {
        cmds.addAll([ppx - tilePx, ppy - tilePx, alpha, pshape[i].toDouble()]);
      }
    }
    return Float64List.fromList(cmds);
  });
}

class _ParticleStamp {
  final int w, h;
  final Uint8List alphas;
  _ParticleStamp(this.w, this.h, this.alphas);
}

class _SpriteGenParams {
  final double tilePx, dpr;
  final bool isText, isImage;
  final int sheetW, sheetH;
  const _SpriteGenParams(
      this.tilePx, this.dpr, this.isText, this.isImage, this.sheetW, this.sheetH);
}

List<_ParticleStamp> _buildParticleStamps(double dpr) {
  final sizeRange = _kParticleSizeMax - _kParticleSizeMin;
  final cornerR = _kParticleSizeMin * dpr / 2;
  final mid = _kSpriteVariants ~/ 2;
  final stamps = <_ParticleStamp>[];

  for (int i = 0; i < _kSpriteVariants; i++) {
    double w, h;
    if (i < mid) {
      w = (_kParticleSizeMin + (i + 1) / mid * sizeRange) * dpr;
      h = _kParticleSizeMin * dpr;
    } else if (i > mid) {
      w = _kParticleSizeMin * dpr;
      h = (_kParticleSizeMin +
              (i - mid) / (_kSpriteVariants - mid - 1) * sizeRange) *
          dpr;
    } else {
      w = _kParticleSizeMin * dpr;
      h = _kParticleSizeMin * dpr;
    }

    final pw = (w + 2).ceil();
    final ph = (h + 2).ceil();
    final alphas = Uint8List(pw * ph);
    final cx = pw / 2.0;
    final cy = ph / 2.0;
    final hw = w / 2;
    final hh = h / 2;

    for (int py = 0; py < ph; py++) {
      for (int px = 0; px < pw; px++) {
        final qx = (px + 0.5 - cx).abs() - hw + cornerR;
        final qy = (py + 0.5 - cy).abs() - hh + cornerR;
        final double d;
        if (qx > 0 && qy > 0) {
          d = math.sqrt(qx * qx + qy * qy) - cornerR;
        } else {
          d = math.max(qx, qy) - cornerR;
        }
        alphas[py * pw + px] = ((0.5 - d).clamp(0.0, 1.0) * 255).round();
      }
    }
    stamps.add(_ParticleStamp(pw, ph, alphas));
  }
  return stamps;
}

Uint8List _generateSpriteSheetPixels(_SpriteGenParams p) {
  final frameData =
      _computeParticleFrameData(_ParticleParams(p.tilePx, p.dpr, p.isText));
  final stamps = _buildParticleStamps(p.dpr);
  final pixels = Uint8List(p.sheetW * p.sheetH * 4);
  final stride = p.sheetW * 4;

  for (int f = 0; f < _kFrameCount; f++) {
    final col = f % _kFramesPerRow;
    final row = f ~/ _kFramesPerRow;
    final tileX = (col * p.tilePx).round();
    final tileY = (row * p.tilePx).round();
    final tileW = p.tilePx.round();
    final tileH = p.tilePx.round();

    if (p.isImage) {
      final yEnd = math.min(tileY + tileH, p.sheetH);
      final xEnd = math.min(tileX + tileW, p.sheetW);
      for (int y = tileY; y < yEnd; y++) {
        for (int x = tileX; x < xEnd; x++) {
          pixels[y * stride + x * 4 + 3] = _kImageSpoilerDarkenAlpha;
        }
      }
    }

    final cmds = frameData[f];
    for (int j = 0; j < cmds.length; j += 4) {
      final pa = (cmds[j + 2] * 255).round();
      if (pa <= 0) continue;
      final si = cmds[j + 3].toInt();
      if (si < 0 || si >= stamps.length) continue;

      final stamp = stamps[si];
      final sx = (cmds[j] + tileX - stamp.w * 0.5).round();
      final sy = (cmds[j + 1] + tileY - stamp.h * 0.5).round();
      final x0 = math.max(sx, tileX);
      final y0 = math.max(sy, tileY);
      final x1 = math.min(sx + stamp.w, math.min(tileX + tileW, p.sheetW));
      final y1 = math.min(sy + stamp.h, math.min(tileY + tileH, p.sheetH));

      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final sa = stamp.alphas[(y - sy) * stamp.w + (x - sx)];
          if (sa == 0) continue;
          final srcA = (sa * pa) ~/ 255;
          if (srcA == 0) continue;

          final idx = y * stride + x * 4;
          final dstA = pixels[idx + 3];
          if (dstA == 0) {
            pixels[idx] = 255;
            pixels[idx + 1] = 255;
            pixels[idx + 2] = 255;
            pixels[idx + 3] = srcA;
          } else {
            final outA = srcA + dstA - (srcA * dstA) ~/ 255;
            if (outA <= 0) continue;
            final dstW = dstA * (255 - srcA) ~/ 255;
            pixels[idx] = (255 * srcA + pixels[idx] * dstW) ~/ outA;
            pixels[idx + 1] = (255 * srcA + pixels[idx + 1] * dstW) ~/ outA;
            pixels[idx + 2] = (255 * srcA + pixels[idx + 2] * dstW) ~/ outA;
            pixels[idx + 3] = outA;
          }
        }
      }
    }
  }
  return pixels;
}

Future<SpoilerSpriteSheet> _renderSpriteSheet(SpoilerType type) async {
  final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  final tilePx = (_kCanvasSize * dpr).roundToDouble();
  final sheetW = (tilePx * _kFramesPerRow).toInt();
  final sheetH = (tilePx * _kRows).toInt();

  final pixels = await compute(
    _generateSpriteSheetPixels,
    _SpriteGenParams(tilePx, dpr, type == SpoilerType.text,
        type == SpoilerType.image, sheetW, sheetH),
  );

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, sheetW, sheetH, ui.PixelFormat.rgba8888, completer.complete);
  return SpoilerSpriteSheet(await completer.future, tilePx);
}

class SpoilerTilePainter extends CustomPainter {
  final SpoilerSpriteSheet sheet;
  final int frame;
  final double revealProgress;
  final Color? tintColor;
  final bool isMedia;
  final BorderRadius? borderRadius;
  final Offset originShift;

  SpoilerTilePainter({
    required this.sheet,
    required this.frame,
    this.revealProgress = 0.0,
    this.tintColor,
    this.isMedia = false,
    this.borderRadius,
    this.originShift = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress >= 1.0) return;
    final opacity = 1.0 - revealProgress;
    final rect = Offset.zero & size;
    final hasCorners = borderRadius != null && borderRadius != BorderRadius.zero;

    canvas.save();
    if (hasCorners) {
      canvas.clipRRect(borderRadius!.toRRect(rect));
    } else {
      canvas.clipRect(rect);
    }

    final src = sheet.frameRect(frame.clamp(0, _kFrameCount - 1));
    final tile = sheet.tileSize;

    final paint = Paint();
    if (tintColor != null) {
      paint.colorFilter = SpoilerColorCache.instance.getFilter(tintColor!);
      paint.color = Color.fromRGBO(255, 255, 255, opacity * 0.85);
    } else {
      paint.color = Color.fromRGBO(255, 255, 255, opacity * 0.85);
      paint.blendMode = BlendMode.srcOver;
    }

    final ox = -(originShift.dx % tile);
    final oy = -(originShift.dy % tile);
    for (double y = oy; y < size.height; y += tile) {
      for (double x = ox; x < size.width; x += tile) {
        canvas.drawImageRect(sheet.image, src,
            Rect.fromLTWH(x, y, tile, tile), paint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(SpoilerTilePainter old) =>
      old.frame != frame ||
      old.revealProgress != revealProgress ||
      old.borderRadius != borderRadius ||
      old.tintColor != tintColor ||
      old.isMedia != isMedia ||
      old.originShift != originShift;
}

class SpoilerColorCache {
  SpoilerColorCache._();
  static final instance = SpoilerColorCache._();

  final _cache = <int, ColorFilter>{};
  final _order = <int>[];

  ColorFilter getFilter(Color color) {
    final opaque = color.withValues(alpha: 1.0);
    final key = opaque.value;
    final existing = _cache[key];
    if (existing != null) {
      _order.remove(key);
      _order.add(key);
      return existing;
    }
    final filter = ColorFilter.mode(opaque, BlendMode.srcIn);
    _cache[key] = filter;
    _order.add(key);
    while (_cache.length > _kColorCacheCapacity) {
      _cache.remove(_order.removeAt(0));
    }
    return filter;
  }

  void clear() {
    _cache.clear();
    _order.clear();
  }
}

void tileSpoilerOnRects(
  Canvas canvas,
  SpoilerSpriteSheet sheet,
  int frame,
  List<Rect> rects,
  Color tintColor,
  double opacity, {
  Offset originShift = Offset.zero,
}) {
  if (opacity <= 0 || rects.isEmpty) return;
  final src = sheet.frameRect(frame.clamp(0, _kFrameCount - 1));
  final tile = sheet.tileSize;
  final paint = Paint()
    ..colorFilter = SpoilerColorCache.instance.getFilter(tintColor)
    ..color = Color.fromRGBO(255, 255, 255, opacity * 0.85);

  for (final rect in rects) {
    canvas.save();
    canvas.clipRect(rect);
    final shiftX = originShift.dx % tile;
    final shiftY = originShift.dy % tile;
    final startTX = ((rect.left - shiftX) / tile).floor();
    final endTX = ((rect.right - shiftX) / tile).ceil();
    final startTY = ((rect.top - shiftY) / tile).floor();
    final endTY = ((rect.bottom - shiftY) / tile).ceil();
    for (int ty = startTY; ty < endTY; ty++) {
      for (int tx = startTX; tx < endTX; tx++) {
        canvas.drawImageRect(sheet.image, src,
            Rect.fromLTWH(shiftX + tx * tile, shiftY + ty * tile, tile, tile), paint);
      }
    }
    canvas.restore();
  }
}

class SpoilerRevealManager extends ChangeNotifier {
  SpoilerRevealManager._();
  static final instance = SpoilerRevealManager._();

  void hideAll() {
    notifyListeners();
  }
}

mixin SpoilerAnimationMixin<T extends StatefulWidget> on State<T> {
  SpoilerSpriteSheet? spoilerSheet;
  bool spoilerRegistered = false;
  int _lastQueryMs = 0;
  bool _autoPaused = false;
  AppState? _spoilerAppState;

  int get spoilerFrame {
    _lastQueryMs = DateTime.now().millisecondsSinceEpoch;
    if (_autoPaused && spoilerRegistered) {
      _autoPaused = false;
      SpoilerAnimationManager.instance.register();
      SpoilerAnimationManager.instance.addListener(_onSpoilerFrame);
    }
    return SpoilerAnimationManager.instance.currentFrame;
  }

  void initSpoiler(SpoilerType type) {
    _lastQueryMs = DateTime.now().millisecondsSinceEpoch;
    _autoPaused = false;
    SpoilerAnimationManager.instance.register();
    spoilerRegistered = true;
    SpoilerAnimationManager.instance.addListener(_onSpoilerFrame);
    SpoilerAnimationManager.instance.getSheet(type).then((s) {
      if (mounted) setState(() => spoilerSheet = s);
    });
    _syncPowerSaving();
  }

  void _syncPowerSaving() {
    try {
      if (_spoilerAppState == null) {
        _spoilerAppState = context.read<AppState>();
        _spoilerAppState!.addListener(_onPowerSavingChanged);
      }
      SpoilerAnimationManager.instance.powerSavingPaused =
          _spoilerAppState!.powerSaving(AppState.kPowerSavingChatSpoiler);
    } catch (_) {}
  }

  void _onPowerSavingChanged() {
    if (!mounted) return;
    try {
      SpoilerAnimationManager.instance.powerSavingPaused =
          _spoilerAppState!.powerSaving(AppState.kPowerSavingChatSpoiler);
    } catch (_) {}
  }

  void disposeSpoiler() {
    _spoilerAppState?.removeListener(_onPowerSavingChanged);
    _spoilerAppState = null;
    if (spoilerRegistered) {
      SpoilerAnimationManager.instance.removeListener(_onSpoilerFrame);
      if (!_autoPaused) {
        SpoilerAnimationManager.instance.unregister();
      }
      spoilerRegistered = false;
      _autoPaused = false;
    }
  }

  void _onSpoilerFrame() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastQueryMs > _kAutoPauseTimeoutMs) {
      _autoPaused = true;
      SpoilerAnimationManager.instance.removeListener(_onSpoilerFrame);
      SpoilerAnimationManager.instance.unregister();
      return;
    }
    setState(() {});
  }
}
