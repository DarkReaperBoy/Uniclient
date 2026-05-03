import 'package:flutter/material.dart';

class AyuToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isMaterial;

  const AyuToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.isMaterial = true,
  });

  @override
  State<AyuToggle> createState() => _AyuToggleState();
}

class _AyuToggleState extends State<AyuToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  Duration get _duration => widget.isMaterial
      ? const Duration(milliseconds: 150)
      : const Duration(milliseconds: 120);

  @override
  void didUpdateWidget(AyuToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.duration = _duration;
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const md3TrackW = 32.0;
    const md3TrackH = 18.0;
    const md3ThumbD = 14.0;
    const md3Shift = -2.0;
    const md3AnimPad = 2.0;

    const iosTrackW = 36.0;
    const iosTrackH = 20.0;
    const iosThumbD = 16.0;
    const iosShift = 1.0;

    final isMat = widget.isMaterial;
    final trackW = isMat ? md3TrackW : iosTrackW;
    final trackH = isMat ? md3TrackH : iosTrackH;
    final thumbD = isMat ? md3ThumbD : iosThumbD;
    final shift = isMat ? md3Shift : iosShift;
    final curve = isMat ? Curves.easeOutCubic : Curves.linear;

    final inset = (trackH - thumbD) / 2 + shift;

    return GestureDetector(
      onTap: () => widget.onChanged?.call(!widget.value),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = curve.transform(_controller.value);

          const activeColor = Color(0xFF40A7E3);
          final inactiveColor =
              isDark ? const Color(0xFF5A6A78) : const Color(0xFFCBCBCB);
          final trackColor = Color.lerp(inactiveColor, activeColor, t)!;

          var diam = thumbD;
          if (isMat) {
            diam = thumbD - (md3AnimPad * 2) * (1 - t);
          }

          final baseLeft = inset + t * (trackW - thumbD - 2 * inset);
          final left = baseLeft + (thumbD - diam) / 2;
          final top = (trackH - diam) / 2;

          return SizedBox(
            width: trackW,
            height: trackH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(trackH / 2),
                color: trackColor,
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: left,
                    top: top,
                    child: SizedBox(
                      width: diam,
                      height: diam,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
