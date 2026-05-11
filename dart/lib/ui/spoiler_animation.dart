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

  SpoilerSpriteSheet? _textSheet;
  SpoilerSpriteSheet? _imageSheet;
  bool _textGenerating = false;
  bool _imageGenerating = false;

  final _textCompleters = <Completer<SpoilerSpriteSheet>>[];
  final _imageCompleters = <Completer<SpoilerSpriteSheet>>[];

  int _activeCount = 0;
  bool _callbackScheduled = false;
  int _currentFrame = 0;
  final _listeners = <VoidCallback>{};

  bool powerSavingPaused = false;

  int get currentFrame => _currentFrame;

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);

  void register() {
    _activeCount++;
    if (!_callbackScheduled) {
      _callbackScheduled = true;
      SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
    }
  }

  void unregister() {
    _activeCount--;
    if (_activeCount < 0) _activeCount = 0;
  }

  void _onFrame(Duration timestamp) {
    if (_activeCount <= 0 || _listeners.isEmpty) return;
    if (powerSavingPaused) return;
    final frame = (timestamp.inMilliseconds ~/ 33) % _kFrameCount;
    if (frame != _currentFrame) {
      _currentFrame = frame;
      for (final cb in List.of(_listeners)) {
        cb();
      }
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

Future<SpoilerSpriteSheet?> _loadSpoilerCache(
    SpoilerType type, double expectedTileSize) async {
  try {
    final name = type == SpoilerType.text ? 'text' : 'image';
    final file = File('/tmp/uniclient_spoiler_cache/$name.png');
    if (!file.existsSync()) return null;
    final pngBytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(pngBytes);
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
  try {
    final dir = Directory('/tmp/uniclient_spoiler_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final name = type == SpoilerType.text ? 'text' : 'image';
    final file = File('${dir.path}/$name.png');
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      await file.writeAsBytes(byteData.buffer.asUint8List());
    }
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

Future<SpoilerSpriteSheet> _renderSpriteSheet(SpoilerType type) async {
  final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  final tilePx = (_kCanvasSize * dpr).roundToDouble();
  final sheetW = (tilePx * _kFramesPerRow).toInt();
  final sheetH = (tilePx * _kRows).toInt();

  final frameData = await compute(
    _computeParticleFrameData,
    _ParticleParams(tilePx, dpr, type == SpoilerType.text),
  );

  final sizeRange = _kParticleSizeMax - _kParticleSizeMin;
  final cornerR = _kParticleSizeMin * dpr / 2;
  final spriteRects = <RRect>[];
  for (int i = 0; i < _kSpriteVariants; i++) {
    final mid = _kSpriteVariants ~/ 2;
    double w, h;
    if (i < mid) {
      w = (_kParticleSizeMin + (i + 1) / mid * sizeRange) * dpr;
      h = _kParticleSizeMin * dpr;
    } else if (i > mid) {
      w = _kParticleSizeMin * dpr;
      h = (_kParticleSizeMin + (i - mid) / (_kSpriteVariants - mid - 1) * sizeRange) * dpr;
    } else {
      w = _kParticleSizeMin * dpr;
      h = _kParticleSizeMin * dpr;
    }
    spriteRects.add(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Radius.circular(cornerR),
    ));
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, sheetW.toDouble(), sheetH.toDouble()));
  final paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.fill;

  for (int f = 0; f < _kFrameCount; f++) {
    final col = f % _kFramesPerRow;
    final row = f ~/ _kFramesPerRow;
    final ox = col * tilePx;
    final oy = row * tilePx;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(ox, oy, tilePx, tilePx));

    final cmds = frameData[f];
    for (int j = 0; j < cmds.length; j += 4) {
      paint.color = Color.fromRGBO(255, 255, 255, cmds[j + 2]);
      canvas.drawRRect(
        spriteRects[cmds[j + 3].toInt()].shift(Offset(ox + cmds[j], oy + cmds[j + 1])),
        paint,
      );
    }

    canvas.restore();
    await Future.delayed(Duration.zero);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(sheetW, sheetH);
  picture.dispose();
  return SpoilerSpriteSheet(image, tilePx);
}

class SpoilerTilePainter extends CustomPainter {
  final SpoilerSpriteSheet sheet;
  final int frame;
  final double revealProgress;
  final Color? tintColor;
  final bool isMedia;
  final BorderRadius? borderRadius;

  SpoilerTilePainter({
    required this.sheet,
    required this.frame,
    this.revealProgress = 0.0,
    this.tintColor,
    this.isMedia = false,
    this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress >= 1.0) return;
    final opacity = 1.0 - revealProgress;
    final rect = Offset.zero & size;
    final hasCorners = borderRadius != null && borderRadius != BorderRadius.zero;

    if (hasCorners) {
      canvas.saveLayer(rect, Paint());
    } else {
      canvas.save();
      canvas.clipRect(rect);
    }

    if (isMedia) {
      canvas.drawRect(
        rect,
        Paint()..color = Color.fromRGBO(0, 0, 0, (32 / 255) * opacity),
      );
    }

    final src = sheet.frameRect(frame.clamp(0, _kFrameCount - 1));
    final tile = sheet.tileSize;

    final paint = Paint();
    if (tintColor != null) {
      paint.colorFilter = SpoilerColorCache.instance.getFilter(
        tintColor!.withValues(alpha: opacity * 0.85),
      );
    } else {
      paint.color = Color.fromRGBO(255, 255, 255, opacity * 0.85);
      paint.blendMode = BlendMode.srcOver;
    }

    final fullTilesX = (size.width / tile).floor();
    final fullTilesY = (size.height / tile).floor();
    final edgeW = size.width - fullTilesX * tile;
    final edgeH = size.height - fullTilesY * tile;

    for (int ty = 0; ty < fullTilesY; ty++) {
      for (int tx = 0; tx < fullTilesX; tx++) {
        canvas.drawImageRect(sheet.image, src,
            Rect.fromLTWH(tx * tile, ty * tile, tile, tile), paint);
      }
      if (edgeW > 0) {
        final edgeSrc = Rect.fromLTWH(src.left, src.top, edgeW, tile);
        canvas.drawImageRect(sheet.image, edgeSrc,
            Rect.fromLTWH(fullTilesX * tile, ty * tile, edgeW, tile), paint);
      }
    }
    if (edgeH > 0) {
      final edgeSrcH = Rect.fromLTWH(src.left, src.top, tile, edgeH);
      for (int tx = 0; tx < fullTilesX; tx++) {
        canvas.drawImageRect(sheet.image, edgeSrcH,
            Rect.fromLTWH(tx * tile, fullTilesY * tile, tile, edgeH), paint);
      }
      if (edgeW > 0) {
        final cornerSrc = Rect.fromLTWH(src.left, src.top, edgeW, edgeH);
        canvas.drawImageRect(sheet.image, cornerSrc,
            Rect.fromLTWH(fullTilesX * tile, fullTilesY * tile, edgeW, edgeH), paint);
      }
    }

    if (hasCorners) {
      final rrect = borderRadius!.toRRect(rect);
      canvas.drawRRect(rrect, Paint()
        ..blendMode = BlendMode.dstIn
        ..color = const Color(0xFFFFFFFF));
      canvas.restore();
    } else {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SpoilerTilePainter old) =>
      old.frame != frame ||
      old.revealProgress != revealProgress ||
      old.borderRadius != borderRadius;
}

class SpoilerColorCache {
  SpoilerColorCache._();
  static final instance = SpoilerColorCache._();

  final _cache = <int, ColorFilter>{};
  final _order = <int>[];

  ColorFilter getFilter(Color color) {
    final key = color.value;
    final existing = _cache[key];
    if (existing != null) {
      _order.remove(key);
      _order.add(key);
      return existing;
    }
    final filter = ColorFilter.mode(color, BlendMode.srcIn);
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
  double opacity,
) {
  if (opacity <= 0 || rects.isEmpty) return;
  final src = sheet.frameRect(frame.clamp(0, _kFrameCount - 1));
  final tile = sheet.tileSize;
  final paint = Paint()
    ..colorFilter = SpoilerColorCache.instance.getFilter(
      tintColor.withValues(alpha: opacity * 0.85),
    );

  for (final rect in rects) {
    canvas.save();
    canvas.clipRect(rect);
    final startTX = (rect.left / tile).floor();
    final endTX = (rect.right / tile).ceil();
    final startTY = (rect.top / tile).floor();
    final endTY = (rect.bottom / tile).ceil();
    for (int ty = startTY; ty < endTY; ty++) {
      for (int tx = startTX; tx < endTX; tx++) {
        canvas.drawImageRect(sheet.image, src,
            Rect.fromLTWH(tx * tile, ty * tile, tile, tile), paint);
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
