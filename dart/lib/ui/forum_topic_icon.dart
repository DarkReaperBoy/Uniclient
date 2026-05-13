import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../bridge/engine_service.dart';
import '../models/engine_models.dart';

/// Per-color gradient palette for forum topic bubble icons — spec §22.2.1.
class TopicIconPalette {
  final Color fillTop, fillBottom;
  final Color strokeTop, strokeBottom;
  final Color highlight;
  const TopicIconPalette({
    required this.fillTop,
    required this.fillBottom,
    required this.strokeTop,
    required this.strokeBottom,
    required this.highlight,
  });
}

/// The 6 predefined topic icon color palettes — spec §22.2.1.
/// colorId selects a specific palette (not runtime hue-shift).
const topicIconPalettes = <int, TopicIconPalette>{
  0x6FB9F0: TopicIconPalette(
    fillTop: Color(0xFF4BB7FF), fillBottom: Color(0xFF015EC1),
    strokeTop: Color(0xFF0888DF), strokeBottom: Color(0xFF0042AC),
    highlight: Color(0xFF71D0FF),
  ),
  0xFFD67E: TopicIconPalette(
    fillTop: Color(0xFFFFDB5C), fillBottom: Color(0xFFEA5800),
    strokeTop: Color(0xFFF2A807), strokeBottom: Color(0xFFD93A00),
    highlight: Color(0xFFF9FF71),
  ),
  0xCB86DB: TopicIconPalette(
    fillTop: Color(0xFFE57AFF), fillBottom: Color(0xFFA438BB),
    strokeTop: Color(0xFFB239D1), strokeBottom: Color(0xFF7C279A),
    highlight: Color(0xFFF5BDFF),
  ),
  0x8EEE98: TopicIconPalette(
    fillTop: Color(0xFF97E334), fillBottom: Color(0xFF11B411),
    strokeTop: Color(0xFF48AF18), strokeBottom: Color(0xFF05951A),
    highlight: Color(0xFFC2FF71),
  ),
  0xFF93B2: TopicIconPalette(
    fillTop: Color(0xFFFF7999), fillBottom: Color(0xFFE4215A),
    strokeTop: Color(0xFFF83B72), strokeBottom: Color(0xFFBA0940),
    highlight: Color(0xFFFFC7D6),
  ),
  0xFB6F5F: TopicIconPalette(
    fillTop: Color(0xFFFF714C), fillBottom: Color(0xFFC61505),
    strokeTop: Color(0xFFE12F1F), strokeBottom: Color(0xFFB40101),
    highlight: Color(0xFFFFB47D),
  ),
  0x9AABAB: TopicIconPalette(
    fillTop: Color(0xFFA5A5A5), fillBottom: Color(0xFF616161),
    strokeTop: Color(0xFF737373), strokeBottom: Color(0xFF565656),
    highlight: Color(0xFFB8B8B8),
  ),
};

const _defaultColorId = 0x9AABAB;

/// Forum topic icon — speech-bubble-with-tail with gradient fill/stroke,
/// highlight arc, and centered letter overlay. Spec §22.2 & §22.2.1.
class ForumTopicIcon extends StatelessWidget {
  final int colorId;
  final String title;
  final double size;

  const ForumTopicIcon({
    super.key,
    required this.colorId,
    this.title = '',
    this.size = defaultSize,
  });

  static const defaultSize = 21.0;
  static const normalSize = 19.0;
  static const largeSize = 26.0;
  static const infoSize = 32.0;

  static (double font, double textTop) _specFor(double size) => switch (size) {
    21 => (11, 2),
    19 => (10, 2),
    26 => (13, 3),
    32 => (15, 4),
    _ => (size * 0.5, size * 0.1),
  };

  @override
  Widget build(BuildContext context) {
    final palette =
        topicIconPalettes[colorId] ?? topicIconPalettes[_defaultColorId]!;
    final (fontSize, textTop) = _specFor(size);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BubbleIconPainter(
          palette: palette,
          letter: extractTopicLetter(title),
          targetSize: size,
          fontSize: fontSize,
          textTop: textTop,
        ),
      ),
    );
  }
}

/// Spec §22.2.2: extract first non-emoji letter or digit from title.
String extractTopicLetter(String title) {
  if (title.isEmpty) return '';
  final letterDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
  for (final char in title.characters) {
    if (char.length > 1) continue;
    if (letterDigit.hasMatch(char)) return char;
  }
  return '';
}

// --- SVG path data (84×84 viewBox) ---

const _bubblePathD =
    'M42,4.47368421 C52.6535116,4.47368421 62.3029461,8.44172846 '
    '69.286057,14.8715044 C76.2233062,21.2590526 80.5263158,30.0798831 '
    '80.5263158,39.8304382 C80.5263158,49.5809933 76.2233062,58.4018239 '
    '69.286057,64.7893721 C62.3029461,71.219148 52.6535116,75.1871923 '
    '42,75.1871923 C37.5267059,75.1871923 33.2308553,74.4877643 '
    '29.2348341,73.2001187 C29.0182529,73.1303293 28.8019654,73.0586229 '
    '28.5862413,72.9852481 C28.3948519,73.106612 28.2000814,73.2292009 '
    '28.0019297,73.3530173 C26.1800899,74.4914063 24.5768234,75.4183854 '
    '23.1902273,76.1332316 C19.9632993,77.7968433 15.8838664,78.895322 '
    '10.968708,79.4573148 L10.3331597,79.5269374 '
    'C10.8475353,78.5381033 11.3155893,77.6262907 11.7364879,76.7897918 '
    'L12.0856904,76.0911971 '
    'C13.1548056,73.9371347 13.8747553,72.3343394 14.2288664,71.2486595 '
    'C14.8154652,69.4501884 15.1095499,67.6701625 15.2363061,66.0328103 '
    'C15.2549358,65.7921643 15.2704685,65.5479168 15.2812363,65.2994157 '
    'C15.1072303,65.1457013 14.9345381,64.9902431 14.7631844,64.8330639 '
    'C7.79678435,58.4429296 3.47368421,49.6037286 3.47368421,39.8304382 '
    'C3.47368421,30.0798831 7.77669379,21.2590526 14.713943,14.8715044 '
    'C21.6970539,8.44172846 31.3464884,4.47368421 42,4.47368421 Z';

const _highlightPathD =
    'M9.68078613,24.6137047 C9.8721537,24.8136848 10.1894036,24.8206666 '
    '10.3893837,24.629299 C10.3964827,24.6225057 10.4033805,24.6155051 '
    '10.410082,24.6083194 C20.5178445,13.7276637 31.3141669,8.50123177 '
    '42.7990494,8.92902374 C54.2584365,9.35586606 64.9235425,15.3681505 '
    '74.7943671,26.9658769 C75.0309355,27.243826 75.4426222,27.2904538 '
    '75.7353592,27.0724506 C76.0315877,26.8518473 76.1075038,26.440096 '
    '75.9094038,26.1283693 C67.7821181,13.3374534 56.7453333,6.69089625 '
    '42.7990494,6.18869781 C28.8220513,5.68539338 17.7581791,11.5492352 '
    '9.60743269,23.7802233 C9.4336795,24.0409463 9.46416665,24.3873362 '
    '9.68078613,24.6137047 Z';

/// General topic hash icon path (20×20 viewBox) — for GeneralForumTopicIcon.
const generalTopicPathD =
    'M14.4576257,1.02558449 C15.189053,1.1696007 15.6657078,1.88165413 '
    '15.5222641,2.61600035 L14.8818905,5.62412405 L16.6504058,5.62421139 '
    'C17.3957661,5.62421139 18,6.23085664 18,6.97919149 C18,7.72752633 '
    '17.3957661,8.33417159 16.6504058,8.33417159 L14.3525674,8.33397488 '
    'L13.6850637,11.7513347 L15.3008116,11.7515071 C16.0461719,11.7515071 '
    '16.6504058,12.3581524 16.6504058,13.1064872 C16.6504058,13.8548221 '
    '16.0461719,14.4614673 15.3008116,14.4614673 L13.1557407,14.4614328 '
    'L12.4307242,17.9055215 C12.2872804,18.6398677 11.5780573,19.1184247 '
    '10.84663,18.9744085 C10.1152028,18.8303923 9.63854794,18.1183389 '
    '9.7819917,17.3839927 L10.4051821,14.4614328 L7.75733538,14.4614328 '
    'L7.03234733,17.9055215 C6.90989534,18.5324024 6.37514133,18.9728813 '
    '5.76623746,18.9987859 L5.71387199,19 C5.62631985,19.0002755 '
    '5.53745163,18.9919715 5.44825318,18.9744085 C4.71682589,18.8303923 '
    '4.24017107,18.1183389 4.38361482,17.3839927 L5.00702313,14.4614328 '
    'L3.34959422,14.4614673 C2.60423391,14.4614673 2,13.8548221 '
    '2,13.1064872 C2,12.3581524 2.60423391,11.7515071 3.34959422,11.7515071 '
    'L5.53634616,11.7513347 L6.20384986,8.33397488 L4.69918844,8.33417159 '
    'C3.95382813,8.33417159 3.34959422,7.72752633 3.34959422,6.97919149 '
    'C3.34959422,6.23085664 3.95382813,5.62421139 4.69918844,5.62421139 '
    'L6.73317289,5.62412405 L7.4751547,2.09447154 C7.60110532,1.44967974 '
    '8.16325465,1.00209364 8.79363004,1 L8.84631136,1.00087004 '
    'C8.91674267,1.00340951 8.98789009,1.01153413 9.05924885,1.02558449 '
    'C9.79067614,1.1696007 10.267331,1.88165413 10.1238872,2.61600035 '
    'L9.48348515,5.62412405 L12.1315782,5.62412405 L12.8735316,2.09447154 '
    'C13.0169753,1.36012532 13.7261984,0.881568286 14.4576257,1.02558449 Z '
    'M10.9345052,11.7513347 L11.6020089,8.33397488 L8.95416211,8.33397488 '
    'L8.28665842,11.7513347 L10.9345052,11.7513347 Z';

Path _parseSvgPath(String d) {
  final path = Path();
  final re = RegExp(r'[MCLZ]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
  final tokens = re.allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  String? cmd;
  while (i < tokens.length) {
    final t = tokens[i];
    if (t == 'M' || t == 'C' || t == 'L' || t == 'Z') {
      cmd = t;
      if (t == 'Z') {
        path.close();
        i++;
        continue;
      }
      i++;
    }
    if (cmd == null || i >= tokens.length) break;
    switch (cmd) {
      case 'M':
        path.moveTo(double.parse(tokens[i]), double.parse(tokens[i + 1]));
        i += 2;
        cmd = 'L';
      case 'L':
        path.lineTo(double.parse(tokens[i]), double.parse(tokens[i + 1]));
        i += 2;
      case 'C':
        path.cubicTo(
          double.parse(tokens[i]),
          double.parse(tokens[i + 1]),
          double.parse(tokens[i + 2]),
          double.parse(tokens[i + 3]),
          double.parse(tokens[i + 4]),
          double.parse(tokens[i + 5]),
        );
        i += 6;
    }
  }
  return path;
}

class _BubbleIconPainter extends CustomPainter {
  final TopicIconPalette palette;
  final String letter;
  final double targetSize;
  final double fontSize;
  final double textTop;

  static Path? _rawBubble;
  static Path? _rawHighlight;

  _BubbleIconPainter({
    required this.palette,
    required this.letter,
    required this.targetSize,
    required this.fontSize,
    required this.textTop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _rawBubble ??= _parseSvgPath(_bubblePathD);
    _rawHighlight ??= _parseSvgPath(_highlightPathD);

    final s = targetSize / 84.0;
    final mat = Float64List.fromList([
      s, 0, 0, 0, //
      0, s, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    final bubble = _rawBubble!.transform(mat);
    final highlight = _rawHighlight!.transform(mat);

    canvas.drawPath(
      bubble,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(42 * s, 0),
          Offset(42 * s, 84 * s),
          [palette.fillTop, palette.fillBottom],
        )
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      bubble,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(42 * s, 0),
          Offset(42 * s, 84 * s),
          [palette.strokeTop, palette.strokeBottom],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.94736842 * s,
    );

    canvas.drawPath(
      highlight,
      Paint()
        ..color = palette.highlight.withValues(alpha: 0.375)
        ..style = PaintingStyle.fill,
    );

    if (letter.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: letter,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((targetSize - tp.width) / 2, textTop),
      );
    }
  }

  @override
  bool shouldRepaint(_BubbleIconPainter old) =>
      palette != old.palette ||
      letter != old.letter ||
      targetSize != old.targetSize ||
      fontSize != old.fontSize ||
      textTop != old.textTop;
}

enum GeneralIconContext { normal, hover, active, profile }

class GeneralForumTopicIcon extends StatelessWidget {
  final double size;
  final GeneralIconContext iconContext;
  final Color? colorOverride;

  const GeneralForumTopicIcon({
    super.key,
    this.size = ForumTopicIcon.defaultSize,
    this.iconContext = GeneralIconContext.normal,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = colorOverride ?? _resolveColor(isDark);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GeneralIconPainter(color: color, targetSize: size),
      ),
    );
  }

  Color _resolveColor(bool isDark) => switch (iconContext) {
    GeneralIconContext.normal =>
      isDark ? const Color(0xFF7F91A4) : const Color(0xFF999999),
    GeneralIconContext.hover =>
      isDark ? const Color(0xFF91A3B5) : const Color(0xFF919191),
    GeneralIconContext.active =>
      const Color(0xFFFFFFFF),
    GeneralIconContext.profile =>
      isDark ? const Color(0xFF7F91A4) : const Color(0xFF999999),
  };
}

class _GeneralIconPainter extends CustomPainter {
  final Color color;
  final double targetSize;

  static Path? _rawPath;

  _GeneralIconPainter({required this.color, required this.targetSize});

  @override
  void paint(Canvas canvas, Size size) {
    _rawPath ??= _parseSvgPath(generalTopicPathD);
    final s = targetSize / 20.0;
    final mat = Float64List.fromList([
      s, 0, 0, 0,
      0, s, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    final path = _rawPath!.transform(mat);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GeneralIconPainter old) =>
      color != old.color || targetSize != old.targetSize;
}

// ── Global custom emoji caches ──

final _customEmojiThumbCache = <int, String>{};
final _customEmojiFileCache = <int, CustomEmojiFileData>{};
final _customEmojiLottieCache = <int, Uint8List>{};
final _customEmojiPendingRequests = <int, Future<void>>{};

Future<void> _fetchCustomEmojiData(EngineService engine, String accountId, int documentId) async {
  if (_customEmojiFileCache.containsKey(documentId)) return;
  if (_customEmojiPendingRequests.containsKey(documentId)) {
    return _customEmojiPendingRequests[documentId];
  }
  final future = () async {
    final files = await engine.getCustomEmojiFiles(accountId, [documentId]);
    if (files.containsKey(documentId)) {
      final file = files[documentId]!;
      _customEmojiFileCache[documentId] = file;
      if (file.isTgs) {
        try {
          _customEmojiLottieCache[documentId] = Uint8List.fromList(gzip.decode(file.fileData));
        } catch (_) {}
      }
    } else {
      final thumbs = await engine.getCustomEmojiThumbs(accountId, [documentId]);
      if (thumbs.containsKey(documentId)) {
        _customEmojiThumbCache[documentId] = thumbs[documentId]!.thumbB64;
      }
    }
    _customEmojiPendingRequests.remove(documentId);
  }();
  _customEmojiPendingRequests[documentId] = future;
  return future;
}

class CustomEmojiTopicIcon extends StatefulWidget {
  final int documentId;
  final String accountId;
  final EngineService engine;
  final double size;

  const CustomEmojiTopicIcon({
    super.key,
    required this.documentId,
    required this.accountId,
    required this.engine,
    this.size = ForumTopicIcon.defaultSize,
  });

  @override
  State<CustomEmojiTopicIcon> createState() => _CustomEmojiTopicIconState();
}

class _CustomEmojiTopicIconState extends State<CustomEmojiTopicIcon>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 200);
  bool _active = true;
  Timer? _releaseTimer;
  AnimationController? _lottieController;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(CustomEmojiTopicIcon old) {
    super.didUpdateWidget(old);
    if (old.documentId != widget.documentId) {
      _lottieController?.dispose();
      _lottieController = null;
      _loadData();
    }
  }

  @override
  void deactivate() {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(_slideDuration, () {
      _customEmojiFileCache.remove(widget.documentId);
      _customEmojiLottieCache.remove(widget.documentId);
      _customEmojiThumbCache.remove(widget.documentId);
      _active = false;
    });
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (!_active) {
      _active = true;
      _loadData();
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _lottieController?.dispose();
    super.dispose();
  }

  void _loadData() {
    _fetchCustomEmojiData(widget.engine, widget.accountId, widget.documentId).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(
      vsync: this,
      duration: composition.duration,
    );
    _lottieController!.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final lottieBytes = _customEmojiLottieCache[widget.documentId];
    if (lottieBytes != null) {
      return SizedBox(
        width: s,
        height: s,
        child: Lottie.memory(
          lottieBytes,
          width: s,
          height: s,
          fit: BoxFit.contain,
          controller: _lottieController,
          onLoaded: _onLottieLoaded,
          errorBuilder: (_, __, ___) => _buildFallback(s),
        ),
      );
    }
    final file = _customEmojiFileCache[widget.documentId];
    if (file != null && (file.isWebp || file.isWebm)) {
      return SizedBox(
        width: s,
        height: s,
        child: Image.memory(
          file.fileData,
          width: s,
          height: s,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _buildFallback(s),
        ),
      );
    }
    return _buildFallback(s);
  }

  Widget _buildFallback(double s) {
    final thumbB64 = _customEmojiThumbCache[widget.documentId];
    if (thumbB64 != null && thumbB64.isNotEmpty) {
      final bytes = base64Decode(thumbB64);
      return SizedBox(
        width: s,
        height: s,
        child: Image.memory(
          Uint8List.fromList(bytes),
          width: s,
          height: s,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }
    return SizedBox(width: s, height: s);
  }
}

class TopicIconWidget extends StatelessWidget {
  final ForumTopic topic;
  final double size;
  final String accountId;
  final EngineService engine;
  final GeneralIconContext generalContext;

  const TopicIconWidget({
    super.key,
    required this.topic,
    required this.accountId,
    required this.engine,
    this.size = ForumTopicIcon.defaultSize,
    this.generalContext = GeneralIconContext.normal,
  });

  @override
  Widget build(BuildContext context) {
    if (topic.isGeneral) {
      return GeneralForumTopicIcon(
        size: size,
        iconContext: generalContext,
      );
    }
    if (topic.hasCustomIcon) {
      return CustomEmojiTopicIcon(
        documentId: topic.iconEmojiId,
        accountId: accountId,
        engine: engine,
        size: size,
      );
    }
    return ForumTopicIcon(
      colorId: topic.colorId,
      title: topic.title,
      size: size,
    );
  }
}
