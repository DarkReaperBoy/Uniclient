import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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

class _Particle {
  final double x, y, vx, vy, size;
  final int birthFrame, shape;
  final int fadeIn, shown, fadeOut;
  _Particle(this.x, this.y, this.vx, this.vy, this.size, this.birthFrame,
      this.shape, this.fadeIn, this.shown, this.fadeOut);
}

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
    final sheet = await _renderSpriteSheet(type);
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

Future<SpoilerSpriteSheet> _renderSpriteSheet(SpoilerType type) async {
  final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  final tilePx = (_kCanvasSize * dpr).roundToDouble();
  final sheetW = (tilePx * _kFramesPerRow).toInt();
  final sheetH = (tilePx * _kRows).toInt();

  final isText = type == SpoilerType.text;
  final count = isText ? 9000 : 3000;
  final speedMin = isText ? 4.0 : 10.0;
  final speedMax = isText ? 8.0 : 20.0;
  final fadeInMs = isText ? 200 : 300;
  final shownMs = isText ? 200 : 0;
  final fadeOutMs = isText ? 200 : 300;
  final fadeInFrames = (fadeInMs / 33).round();
  final shownFrames = (shownMs / 33).round();
  final fadeOutFrames = (fadeOutMs / 33).round();
  final totalLifetimeFrames = fadeInFrames + shownFrames + fadeOutFrames;

  final rng = math.Random(42);
  final speedRange = speedMax - speedMin;
  final sizeRange = _kParticleSizeMax - _kParticleSizeMin;

  final particles = List<_Particle>.generate(count, (_) {
    final spd = rng.nextDouble() * speedRange + speedMin;
    final angle = rng.nextDouble() * 2 * math.pi;
    return _Particle(
      rng.nextDouble() * tilePx,
      rng.nextDouble() * tilePx,
      spd * math.cos(angle) * dpr * 0.033,
      spd * math.sin(angle) * dpr * 0.033,
      (_kParticleSizeMin + rng.nextDouble() * sizeRange) * dpr,
      rng.nextInt(_kFrameCount),
      rng.nextInt(_kSpriteVariants),
      fadeInFrames,
      shownFrames,
      fadeOutFrames,
    );
  });

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

    for (final p in particles) {
      int age = (f - p.birthFrame) % _kFrameCount;
      if (age < 0) age += _kFrameCount;
      if (age >= totalLifetimeFrames) continue;

      double alpha;
      if (age < p.fadeIn) {
        alpha = p.fadeIn > 0 ? age / p.fadeIn : 1.0;
      } else if (age < p.fadeIn + p.shown) {
        alpha = 1.0;
      } else {
        final fadeAge = age - p.fadeIn - p.shown;
        alpha = p.fadeOut > 0 ? 1.0 - fadeAge / p.fadeOut : 0.0;
      }
      if (alpha <= 0) continue;

      double px = (p.x + p.vx * age) % tilePx;
      double py = (p.y + p.vy * age) % tilePx;
      if (px < 0) px += tilePx;
      if (py < 0) py += tilePx;

      paint.color = Color.fromRGBO(255, 255, 255, alpha);
      final sprite = spriteRects[p.shape];

      void drawAt(double dx, double dy) {
        canvas.save();
        canvas.translate(ox + dx, oy + dy);
        canvas.drawRRect(sprite, paint);
        canvas.restore();
      }

      drawAt(px, py);
      if (px + p.size > tilePx) drawAt(px - tilePx, py);
      if (py + p.size > tilePx) drawAt(px, py - tilePx);
      if (px + p.size > tilePx && py + p.size > tilePx) {
        drawAt(px - tilePx, py - tilePx);
      }
    }

    canvas.restore();
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
      paint.colorFilter = ColorFilter.mode(
        tintColor!.withValues(alpha: opacity * 0.85),
        BlendMode.srcIn,
      );
    } else {
      paint.color = Color.fromRGBO(255, 255, 255, opacity * 0.85);
      paint.blendMode = BlendMode.plus;
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
      final appState = context.read<AppState>();
      SpoilerAnimationManager.instance.powerSavingPaused =
          appState.powerSaving(AppState.kPowerSavingChatSpoiler);
    } catch (_) {}
  }

  void disposeSpoiler() {
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
