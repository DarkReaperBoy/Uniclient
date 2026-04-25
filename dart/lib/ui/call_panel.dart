import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum CallPanelState { incoming, connecting, active, ended }

class CallPanelInfo {
  final String callerId;
  final String callerName;
  final String callerAvatarUrl;
  final bool isVideo;
  final CallPanelState state;

  const CallPanelInfo({
    required this.callerId,
    required this.callerName,
    this.callerAvatarUrl = '',
    this.isVideo = false,
    this.state = CallPanelState.incoming,
  });
}

class CallPanel extends StatefulWidget {
  final CallPanelInfo info;
  final VoidCallback? onDecline;
  final VoidCallback? onAccept;
  final VoidCallback? onHangup;
  final VoidCallback? onClose;

  const CallPanel({
    super.key,
    required this.info,
    this.onDecline,
    this.onAccept,
    this.onHangup,
    this.onClose,
  });

  static const defaultWidth = 720.0;
  static const defaultHeight = 540.0;
  static const minWidth = 380.0;
  static const minHeight = 520.0;

  @override
  State<CallPanel> createState() => _CallPanelState();
}

class _CallPanelState extends State<CallPanel> with TickerProviderStateMixin {
  List<Color>? _dominantColors;

  @override
  void initState() {
    super.initState();
    _extractDominantColors();
  }

  @override
  void didUpdateWidget(CallPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.callerAvatarUrl != widget.info.callerAvatarUrl ||
        oldWidget.info.callerId != widget.info.callerId) {
      _extractDominantColors();
    }
  }

  void _extractDominantColors() {
    final url = widget.info.callerAvatarUrl;
    if (url.isNotEmpty) {
      _loadImageColors(url);
    } else {
      _setFallbackColors();
    }
  }

  void _setFallbackColors() {
    final id = widget.info.callerId;
    final hash = id.hashCode.abs();
    final hue = (hash % 360).toDouble();
    setState(() {
      _dominantColors = [
        HSLColor.fromAHSL(1.0, hue, 0.5, 0.25).toColor(),
        HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.6, 0.15).toColor(),
      ];
    });
  }

  Future<void> _loadImageColors(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        _setFallbackColors();
        return;
      }
      final provider = FileImage(file);
      final completer = Completer<ui.Image>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (error, _) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final image = await completer.future;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null || !mounted) {
        _setFallbackColors();
        return;
      }

      final pixels = byteData.buffer.asUint8List();
      int totalR = 0, totalG = 0, totalB = 0;
      int darkR = 0, darkG = 0, darkB = 0;
      int darkCount = 0;
      final pixelCount = pixels.length ~/ 4;
      final step = math.max(1, pixelCount ~/ 200);

      for (int i = 0; i < pixels.length; i += step * 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        totalR += r;
        totalG += g;
        totalB += b;
        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        if (luminance < 128) {
          darkR += r;
          darkG += g;
          darkB += b;
          darkCount++;
        }
      }

      final samples = pixelCount ~/ step;
      if (samples == 0) {
        _setFallbackColors();
        return;
      }

      final avgColor = Color.fromARGB(
        255,
        (totalR ~/ samples).clamp(0, 255),
        (totalG ~/ samples).clamp(0, 255),
        (totalB ~/ samples).clamp(0, 255),
      );

      Color darkColor;
      if (darkCount > 0) {
        darkColor = Color.fromARGB(
          255,
          (darkR ~/ darkCount).clamp(0, 255),
          (darkG ~/ darkCount).clamp(0, 255),
          (darkB ~/ darkCount).clamp(0, 255),
        );
      } else {
        final hsl = HSLColor.fromColor(avgColor);
        darkColor = hsl.withLightness((hsl.lightness * 0.4).clamp(0.0, 1.0)).toColor();
      }

      if (mounted) {
        setState(() {
          _dominantColors = [
            _darkenColor(avgColor, 0.6),
            _darkenColor(darkColor, 0.7),
          ];
        });
      }
    } catch (_) {
      _setFallbackColors();
    }
  }

  static Color _darkenColor(Color c, double factor) {
    return Color.fromARGB(
      c.alpha,
      (c.red * factor).round().clamp(0, 255),
      (c.green * factor).round().clamp(0, 255),
      (c.blue * factor).round().clamp(0, 255),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _dominantColors ?? [const Color(0xFF1a1a2e), const Color(0xFF0f0f1a)];

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: CallPanel.minWidth,
        minHeight: CallPanel.minHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

void showCallPanel(BuildContext context, CallPanelInfo info) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (ctx) {
      return Center(
        child: SizedBox(
          width: CallPanel.defaultWidth,
          height: CallPanel.defaultHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CallPanel(
              info: info,
              onClose: () => Navigator.of(ctx).pop(),
              onDecline: () => Navigator.of(ctx).pop(),
              onAccept: () {},
              onHangup: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    },
  );
}
