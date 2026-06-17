import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit/media_kit.dart';
import 'package:uniclient/utils/mpv_player.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';
import 'custom_emoji_cache.dart' show CustomEmojiCache, EmojiSizeConstants, EmojiSizeTag;
import 'package:uniclient/utils/debug.dart';

/// Emoji-status animation loop cap. AyuGram plays a custom emoji status at most
/// `kPlayStatusLimit` loops in dialog-list / message / menu contexts, then
/// freezes (via `Ui::Text::LimitedLoopsEmoji`). — history_view_message.cpp:73
const int _kPlayStatusLimit = 12;

// --- Colored mini-stars sparkle field constants (collectible statuses) ---
// 1:1 with AyuGram's CollectibleEmoji. — premium_stars_colored.cpp:19-27
const int _kStarsCount = 16;
const double _kTravelMax = 0.5;
const double _kExcludeRadius = 0.7;
const double _kFadingMs = 200;
const double _kLifetimeMinMs = 1000;
const double _kLifetimeMaxMs = 3 * _kLifetimeMinMs;
const double _kSizeMin = 0.1;
const double _kSizeMax = 0.15;

/// The `:/gui/icons/settings/starmini.svg` mini-star glyph (36×36 viewBox),
/// rendered behind a collectible status. Path copied verbatim from AyuGram.
const String _kStarMiniPath =
    'm14.079 21.23-8.3538-2.2799c-0.52464-0.14318-0.83388-0.68456-0.69069-1.2092 '
    '0.091766-0.33624 0.35445-0.59893 0.69069-0.69069l8.3538-2.2799c0.33624-0.091766 '
    '0.59893-0.35445 0.69069-0.69069l2.2799-8.3538c0.14318-0.52464 0.68456-0.83388 '
    '1.2092-0.69069 0.33624 0.091766 0.59893 0.35445 0.69069 0.69069l2.2799 '
    '8.3538c0.091766 0.33624 0.35445 0.59893 0.69069 0.69069l8.3538 2.2799c0.52464 '
    '0.14318 0.83388 0.68456 0.69069 1.2092-0.091766 0.33624-0.35445 0.59893-0.69069 '
    '0.69069l-8.3538 2.2799c-0.33624 0.091766-0.59893 0.35445-0.69069 0.69069l-2.2799 '
    '8.3538c-0.14318 0.52464-0.68456 0.83388-1.2092 0.69069-0.33624-0.091766-0.59893-0.35445-0.69069-0.69069l-2.2799-8.3538c-0.091766-0.33624-0.35445-0.59893-0.69069-0.69069z';

class EmojiStatusWidget extends StatefulWidget {
  final String emojiStatusId;
  final String accountId;
  final double size;
  final Color? fallbackColor;

  const EmojiStatusWidget({
    super.key,
    required this.emojiStatusId,
    required this.accountId,
    this.size = 20.0,
    this.fallbackColor,
  });

  @override
  State<EmojiStatusWidget> createState() => _EmojiStatusWidgetState();
}

class _EmojiStatusWidgetState extends State<EmojiStatusWidget>
    with TickerProviderStateMixin {
  AnimationController? _lottieController;
  Uint8List? _decompressedLottie;
  int _lottieLoops = 0;
  bool _powerSaving = false;

  // Animated WEBM (video/webm) statuses — played via media_kit, same as the
  // sibling forum_topic_icon widget.
  Player? _webmPlayer;
  VideoController? _webmController;
  File? _webmTempFile;
  StreamSubscription<bool>? _webmCompletedSub;
  bool _webmInitStarted = false;
  int _webmLoops = 0;

  // Collectible sparkle field state (persists across paints).
  final List<_Star> _stars = [];
  final math.Random _rng = math.Random();
  final ValueNotifier<double> _starClock = ValueNotifier<double>(0);
  Ticker? _starTicker;

  int? _documentId;
  bool _isCollectible = false;
  Color? _collectibleCenterColor;
  Color? _collectibleEdgeColor;

  @override
  void initState() {
    super.initState();
    _parseEmojiStatusId();
    if (_isCollectible) {
      _fillStars(_stars, _rng, widget.size, 0);
    }
    if (_documentId != null) {
      CustomEmojiCache.instance.acquire(_documentId!, EmojiSizeTag.setIcon);
      CustomEmojiCache.instance.addListenerForDoc(_documentId!, _onCacheUpdate);
    }
    _requestIfNeeded();
  }

  @override
  void didUpdateWidget(EmojiStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emojiStatusId != widget.emojiStatusId) {
      final oldDocId = _documentId;
      _lottieController?.dispose();
      _lottieController = null;
      _lottieLoops = 0;
      _decompressedLottie = null;
      _disposeWebm();
      _stopStars();
      if (oldDocId != null) {
        CustomEmojiCache.instance.removeListenerForDoc(oldDocId, _onCacheUpdate);
      }
      _parseEmojiStatusId();
      _stars.clear();
      if (_isCollectible) {
        _fillStars(_stars, _rng, widget.size, 0);
        _starClock.value = 0;
      }
      if (oldDocId != null) {
        CustomEmojiCache.instance.release(oldDocId, EmojiSizeTag.setIcon);
      }
      if (_documentId != null) {
        CustomEmojiCache.instance.acquire(_documentId!, EmojiSizeTag.setIcon);
        CustomEmojiCache.instance.addListenerForDoc(_documentId!, _onCacheUpdate);
      }
      _requestIfNeeded();
    }
  }

  @override
  void dispose() {
    if (_documentId != null) {
      CustomEmojiCache.instance.removeListenerForDoc(_documentId!, _onCacheUpdate);
      CustomEmojiCache.instance.release(_documentId!, EmojiSizeTag.setIcon);
    }
    _lottieController?.dispose();
    _starTicker?.dispose();
    _starClock.dispose();
    _disposeWebm();
    super.dispose();
  }

  void _disposeWebm() {
    _webmCompletedSub?.cancel();
    _webmCompletedSub = null;
    _webmPlayer?.dispose();
    _webmPlayer = null;
    _webmController = null;
    _webmTempFile?.delete().ignore();
    _webmTempFile = null;
    _webmInitStarted = false;
    _webmLoops = 0;
  }

  void _parseEmojiStatusId() {
    final id = widget.emojiStatusId;
    _collectibleCenterColor = null;
    _collectibleEdgeColor = null;
    if (id.isEmpty) {
      _documentId = null;
      _isCollectible = false;
      return;
    }

    if (id.startsWith('collectible:')) {
      _isCollectible = true;
      final parts = id.substring(12).split(':');
      _documentId = int.tryParse(parts[0]);
      if (parts.length >= 3) {
        _collectibleCenterColor = _parseHexColor(parts[1]);
        _collectibleEdgeColor = _parseHexColor(parts[2]);
      }
    } else {
      _documentId = int.tryParse(id);
      _isCollectible = false;
    }
  }

  static Color? _parseHexColor(String hex) {
    if (hex.isEmpty) return null;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final val = int.tryParse(hex, radix: 16);
    return val != null ? Color(val) : null;
  }

  void _onCacheUpdate() {
    if (!mounted || _documentId == null) return;
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(_documentId!);
    if (file != null && file.isTgs && _decompressedLottie == null) {
      _decompressLottie(file.fileData);
    }
    if (file != null && file.isWebm && _webmPlayer == null && !_webmInitStarted) {
      _webmInitStarted = true;
      _initWebmPlayer(file.fileData);
    }
    if (mounted) setState(() {});
  }

  void _requestIfNeeded() {
    if (_documentId == null || widget.accountId.isEmpty) return;
    final cache = CustomEmojiCache.instance;
    if (cache.getThumb(_documentId!) == null &&
        !cache.isPending(_documentId!) &&
        !cache.hasFailed(_documentId!)) {
      final engine = context.read<EngineService>();
      cache.request(_documentId!, widget.accountId, engine);
    }
    if (cache.getFile(_documentId!) == null &&
        !cache.isFilePending(_documentId!) &&
        !cache.hasFileFailed(_documentId!)) {
      final engine = context.read<EngineService>();
      cache.requestFile(_documentId!, widget.accountId, engine);
    }
  }

  void _decompressLottie(Uint8List tgsData) {
    try {
      _decompressedLottie = Uint8List.fromList(gzip.decode(tgsData));
    } catch (e) {
      Debug.log('emoji_status_widget', '_decompressedLottie = Uint8List.fromList(gzip.decode(tgsD...: $e');
    }
  }

  bool _isPowerSaving(BuildContext context) {
    final appState = context.read<AppState>();
    return appState.powerSaving(AppState.kPowerSavingEmojiStatus);
  }

  /// Starts the animation: plays up to [_kPlayStatusLimit] loops then freezes on
  /// the first frame (AyuGram LimitedLoopsEmoji, stopOnLast=false). Under
  /// power-saving the controller is held at frame 0 (paused but real frame).
  void _onLottieLoaded(LottieComposition composition) {
    if (_lottieController != null) return; // already set up; preserve loop count
    final controller =
        AnimationController(vsync: this, duration: composition.duration);
    _lottieController = controller;
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _lottieLoops++;
        if (_lottieLoops < _kPlayStatusLimit && !_powerSaving) {
          controller.forward(from: 0);
        } else {
          controller.value = 0; // freeze on first frame
        }
      }
    });
    if (_powerSaving) {
      controller.value = 0;
    } else {
      controller.forward();
    }
  }

  Future<void> _initWebmPlayer(Uint8List data) async {
    try {
      final dir = Directory.systemTemp;
      final tempFile = File(
          '${dir.path}/emoji_status_${_documentId}_${identityHashCode(this)}.webm');
      await tempFile.writeAsBytes(data, flush: true);
      if (!mounted) {
        tempFile.delete().ignore();
        return;
      }
      _webmTempFile = tempFile;
      final player = createPlayer();
      final controller = VideoController(player);
      // Manual loop counting → cap at kPlayStatusLimit, then freeze, matching
      // AyuGram's LimitedLoopsEmoji. PlaylistMode.none so restarts are ours.
      await player.setPlaylistMode(PlaylistMode.none);
      _webmCompletedSub = player.stream.completed.listen((done) {
        if (!done || !mounted) return;
        _webmLoops++;
        if (_webmLoops < _kPlayStatusLimit && !_powerSaving) {
          player.seek(Duration.zero);
          player.play();
        } else {
          player.pause();
          player.seek(Duration.zero); // freeze on first frame
        }
      });
      await player.open(Media(tempFile.path), play: !_powerSaving);
      if (!mounted) {
        await _webmCompletedSub?.cancel();
        _webmCompletedSub = null;
        await player.dispose();
        tempFile.delete().ignore();
        return;
      }
      setState(() {
        _webmPlayer = player;
        _webmController = controller;
      });
    } catch (e) {
      Debug.log('emoji_status_widget', '_initWebmPlayer: $e');
    }
  }

  void _startStars() {
    _starTicker ??= createTicker((elapsed) {
      _starClock.value = elapsed.inMicroseconds / 1000.0;
    });
    if (!_starTicker!.isTicking) _starTicker!.start();
  }

  void _stopStars() {
    if (_starTicker != null && _starTicker!.isTicking) {
      _starTicker!.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.emojiStatusId.isEmpty || _documentId == null) {
      return const SizedBox.shrink();
    }

    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(_documentId!);
    final powerSaving = _isPowerSaving(context);
    _powerSaving = powerSaving;
    final s = widget.size;
    final fallbackColor =
        widget.fallbackColor ?? context.palette.profileVerifiedCheckBg;
    final cs = EmojiSizeConstants.scaledFrameSize(
            EmojiSizeTag.setIcon, MediaQuery.devicePixelRatioOf(context))
        .round();

    // The emoji glyph itself, painted UNMODIFIED in its original colors. Power-
    // saving only freezes it (it is NOT degraded to a low-res thumbnail).
    Widget content = _buildInnerEmoji(cache, file, cs, fallbackColor);

    // Collectible: an animated colored mini-star sparkle field BEHIND the emoji.
    // The centerColor/edgeColor tint the sparkles via a radial-gradient mask —
    // they never touch the glyph. — premium_stars_colored.cpp:100-219
    if (_isCollectible &&
        _collectibleCenterColor != null &&
        _collectibleEdgeColor != null) {
      if (powerSaving) {
        _stopStars();
      } else {
        _startStars();
      }
      content = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _StarFieldPainter(
                stars: _stars,
                clock: _starClock,
                centerColor: _collectibleCenterColor!,
                edgeColor: _collectibleEdgeColor!,
                frameSize: s,
                rng: _rng,
              ),
            ),
          ),
          content,
        ],
      );
    } else {
      _stopStars();
    }

    // Isolate the animating badge in its own layer so per-frame repaints do not
    // dirty the surrounding name / chat-list row. — info_profile_badge.cpp:90
    return RepaintBoundary(
      child: SizedBox(width: s, height: s, child: content),
    );
  }

  Widget _buildInnerEmoji(
    CustomEmojiCache cache,
    CustomEmojiFileData? file,
    int cacheSize,
    Color fallbackColor,
  ) {
    final s = widget.size;
    if (file != null) {
      if (file.isTgs && _decompressedLottie != null) {
        return Lottie.memory(
          _decompressedLottie!,
          width: s,
          height: s,
          fit: BoxFit.contain,
          controller: _lottieController,
          onLoaded: _onLottieLoaded,
          errorBuilder: (_, __, ___) =>
              _buildThumbOrFallback(cache, cacheSize, fallbackColor),
        );
      } else if (file.isWebp) {
        return Image.memory(
          file.fileData,
          width: s,
          height: s,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              _buildThumbOrFallback(cache, cacheSize, fallbackColor),
        );
      } else if (file.isWebm && _webmController != null) {
        return Video(
          controller: _webmController!,
          width: s,
          height: s,
          fit: BoxFit.contain,
          controls: NoVideoControls,
        );
      }
    }
    return _buildThumbOrFallback(cache, cacheSize, fallbackColor);
  }

  Widget _buildThumbOrFallback(
      CustomEmojiCache cache, int cacheSize, Color fallbackColor) {
    final thumb = cache.getThumb(_documentId!);
    final s = widget.size;
    if (thumb != null) {
      return Image.memory(
        thumb,
        width: s,
        height: s,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _premiumFallback(s, fallbackColor),
      );
    }
    return _premiumFallback(s, fallbackColor);
  }

  Widget _premiumFallback(double s, Color color) {
    // AyuGram's premium/status badge is a star (infoPremiumStar → profile_premium)
    // tinted with premiumFg = profileVerifiedCheckBg (windowBgActive accent),
    // theme-derived and blue by default — not a fixed purple.
    return Icon(Icons.star_rounded, size: s, color: color);
  }
}

/// One animated sparkle. Mirrors AyuGram's CollectibleEmoji::Star.
class _Star {
  Offset start = Offset.zero;
  Offset delta = Offset.zero;
  double size = 0;
  double birthMs = 0;
  double deathMs = 0;
}

/// Seeds [stars] with [_kStarsCount] sparkles whose lifetimes are randomly
/// phase-shifted so the field looks continuous from the first frame.
/// — premium_stars_colored.cpp:100-113
void _fillStars(List<_Star> stars, math.Random rng, double frameSize, double nowMs) {
  stars.clear();
  for (var i = 0; i < _kStarsCount; i++) {
    final life =
        _kLifetimeMinMs + rng.nextInt((_kLifetimeMaxMs - _kLifetimeMinMs).round());
    final shift =
        rng.nextInt(math.max(1, (life - _kFadingMs).round())).toDouble();
    final star = _Star()
      ..birthMs = nowMs - shift
      ..deathMs = nowMs - shift + life;
    _refillStar(star, rng, frameSize);
    stars.add(star);
  }
}

/// Picks a new outward-travelling trajectory for [star], excluding the central
/// disk (radius kExcludeRadius) where the emoji sits.
/// — premium_stars_colored.cpp:115-145
void _refillStar(_Star star, math.Random rng, double frameSize) {
  final n = math.max(1, (frameSize * 16).round());
  double take() => rng.nextInt(n) / (frameSize * 15.0);
  double stake() => take() * 2.0 - 1.0;
  const exclude = _kExcludeRadius * _kExcludeRadius;

  double square = 0;
  while (true) {
    final sx = stake();
    final sy = stake();
    square = sx * sx + sy * sy;
    if (square > exclude) {
      star.start = Offset(sx * frameSize, sy * frameSize);
      break;
    }
  }
  square *= frameSize * frameSize;
  while (true) {
    final delta = Offset(stake(), stake()) * (_kTravelMax * frameSize);
    final end = star.start + delta;
    if (end.dx * end.dx + end.dy * end.dy > square) {
      star.delta = delta;
      break;
    }
  }
  star.start = (star.start + Offset(frameSize, frameSize)) / 2.0;
  star.size = (_kSizeMin + (_kSizeMax - _kSizeMin) * take()) * frameSize;
}

/// Parses an SVG path supporting both absolute and relative M/L/H/V/C/Z
/// commands (the starmini glyph uses relative m/l/c/z).
Path _parseSvgPath(String d) {
  final path = Path();
  final re = RegExp(r'[MmLlHhVvCcZz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?');
  final toks = re.allMatches(d).map((m) => m.group(0)!).toList();
  double cx = 0, cy = 0, sx = 0, sy = 0;
  String? cmd;
  var i = 0;
  double num() => double.parse(toks[i++]);
  bool isCmd(String t) => t.length == 1 && RegExp(r'[A-Za-z]').hasMatch(t);
  while (i < toks.length) {
    if (isCmd(toks[i])) {
      cmd = toks[i];
      i++;
      if (cmd == 'Z' || cmd == 'z') {
        path.close();
        cx = sx;
        cy = sy;
        cmd = null;
        continue;
      }
    }
    if (cmd == null) {
      i++;
      continue;
    }
    switch (cmd) {
      case 'm':
        cx += num();
        cy += num();
        path.moveTo(cx, cy);
        sx = cx;
        sy = cy;
        cmd = 'l';
      case 'M':
        cx = num();
        cy = num();
        path.moveTo(cx, cy);
        sx = cx;
        sy = cy;
        cmd = 'L';
      case 'l':
        cx += num();
        cy += num();
        path.lineTo(cx, cy);
      case 'L':
        cx = num();
        cy = num();
        path.lineTo(cx, cy);
      case 'h':
        cx += num();
        path.lineTo(cx, cy);
      case 'H':
        cx = num();
        path.lineTo(cx, cy);
      case 'v':
        cy += num();
        path.lineTo(cx, cy);
      case 'V':
        cy = num();
        path.lineTo(cx, cy);
      case 'c':
        final dx1 = num();
        final dy1 = num();
        final dx2 = num();
        final dy2 = num();
        final dx = num();
        final dy = num();
        path.cubicTo(cx + dx1, cy + dy1, cx + dx2, cy + dy2, cx + dx, cy + dy);
        cx += dx;
        cy += dy;
      case 'C':
        final x1 = num();
        final y1 = num();
        final x2 = num();
        final y2 = num();
        final x = num();
        final y = num();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x;
        cy = y;
      default:
        i++;
    }
  }
  return path;
}

/// Renders the colored mini-stars sparkle frame. Stars are drawn white, then
/// masked by a radial gradient (centerColor→edgeColor) via SourceIn, exactly as
/// AyuGram's CollectibleEmoji::prepareFrame. — premium_stars_colored.cpp:155-207
class _StarFieldPainter extends CustomPainter {
  final List<_Star> stars;
  final ValueListenable<double> clock;
  final Color centerColor;
  final Color edgeColor;
  final double frameSize;
  final math.Random rng;

  static Path? _starPath;

  _StarFieldPainter({
    required this.stars,
    required this.clock,
    required this.centerColor,
    required this.edgeColor,
    required this.frameSize,
    required this.rng,
  }) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    final starPath = _starPath ??= _parseSvgPath(_kStarMiniPath);
    final nowMs = clock.value;
    final rect = Rect.fromLTWH(0, 0, frameSize, frameSize);
    final white = Paint()
      ..color = Colors.white
      ..isAntiAlias = true;

    canvas.saveLayer(rect, Paint());
    canvas.clipRect(rect);
    for (final star in stars) {
      if (star.deathMs <= nowMs) {
        final life = _kLifetimeMinMs +
            rng.nextInt((_kLifetimeMaxMs - _kLifetimeMinMs).round());
        star.birthMs = nowMs;
        star.deathMs = nowMs + life;
        _refillStar(star, rng, frameSize);
      }
      final span = star.deathMs - star.birthMs;
      if (span <= 0) continue;
      final time = (nowMs - star.birthMs) / span;
      final position = star.start + star.delta * time;
      final age = nowMs - star.birthMs;
      final remaining = star.deathMs - nowMs;
      final scale = age < _kFadingMs
          ? age / _kFadingMs
          : (remaining < _kFadingMs ? remaining / _kFadingMs : 1.0);
      if (scale <= 0) continue;
      final sz = star.size * scale;
      final r = Rect.fromCenter(center: position, width: sz * 2, height: sz * 2);
      final sc = (sz * 2) / 36.0;
      canvas.save();
      canvas.translate(r.left, r.top);
      canvas.scale(sc);
      canvas.drawPath(starPath, white);
      canvas.restore();
    }
    final gradPaint = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        frameSize / 2,
        [centerColor, edgeColor],
      )
      ..blendMode = BlendMode.srcIn;
    canvas.drawRect(rect, gradPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StarFieldPainter old) =>
      centerColor != old.centerColor ||
      edgeColor != old.edgeColor ||
      frameSize != old.frameSize ||
      !identical(stars, old.stars);
}
