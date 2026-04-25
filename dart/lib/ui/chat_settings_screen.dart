import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _useSystemAccent = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = context.watch<AppState>();

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);

    final currentAccent = _parseHexColor(appState.accentColorHex) ?? accentColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Chat Settings',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: subtextColor),
            color: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onSelected: (value) {
              if (value == 'create_theme') {
                _showCreateThemeDialog(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'create_theme',
                child: Row(
                  children: [
                    Icon(Icons.palette, size: 20, color: textColor),
                    const SizedBox(width: 12),
                    Text(
                      'Create New Theme',
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 10),
          _ThemeCardRow(
            isDark: isDark,
            currentTheme: appState.themeMode == ThemeMode.dark ? 'dark' : 'light',
            accentColor: currentAccent,
            onThemeSelected: (themeId) {
              final targetTheme = themeId == 'dark' || themeId == 'night_blue'
                  ? 'dark'
                  : 'light';
              appState.updateTheme(targetTheme);
            },
          ),
          const SizedBox(height: 8),
          _AccentColorPalette(
            currentColor: currentAccent,
            isDark: isDark,
            onColorSelected: (color) {
              final hex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
              appState.updateAccentColor(hex);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22, right: 22, top: 12, bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _useSystemAccent,
                    onChanged: (v) => setState(() => _useSystemAccent = v ?? false),
                    activeColor: accentColor,
                    side: BorderSide(color: subtextColor, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Use system accent color',
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: dividerColor),
        ],
      ),
    );
  }

  void _showCreateThemeDialog(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          'New Theme',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'Theme name',
            hintStyle: TextStyle(
              color: isDark
                  ? const Color(0xFF6C7883)
                  : const Color(0xFF999999),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accentColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accentColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: accentColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: Text('Create', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  static Color? _parseHexColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final v = int.tryParse(hex, radix: 16);
    return v != null ? Color(v) : null;
  }
}

// ── Theme Presets ──

class _ThemePreset {
  final String id;
  final String label;
  final Color background;
  final Color receivedBubble;
  final Color sentBubble;
  final bool isDarkTheme;

  const _ThemePreset({
    required this.id,
    required this.label,
    required this.background,
    required this.receivedBubble,
    required this.sentBubble,
    required this.isDarkTheme,
  });
}

const _themePresets = [
  _ThemePreset(
    id: 'default',
    label: 'Default',
    background: Color(0xFFDFE7EB),
    receivedBubble: Color(0xFFFFFFFF),
    sentBubble: Color(0xFFEEFFDE),
    isDarkTheme: false,
  ),
  _ThemePreset(
    id: 'day',
    label: 'Day',
    background: Color(0xFFDBEDFC),
    receivedBubble: Color(0xFFFFFFFF),
    sentBubble: Color(0xFFD4F3C6),
    isDarkTheme: false,
  ),
  _ThemePreset(
    id: 'dark',
    label: 'Dark',
    background: Color(0xFF212121),
    receivedBubble: Color(0xFF303030),
    sentBubble: Color(0xFF766AC8),
    isDarkTheme: true,
  ),
  _ThemePreset(
    id: 'night_blue',
    label: 'Night Blue',
    background: Color(0xFF0E1621),
    receivedBubble: Color(0xFF182533),
    sentBubble: Color(0xFF2B5278),
    isDarkTheme: true,
  ),
];

// ── Theme Card Row ──

class _ThemeCardRow extends StatelessWidget {
  final bool isDark;
  final String currentTheme; // 'dark' or 'light'
  final Color accentColor;
  final ValueChanged<String> onThemeSelected;

  const _ThemeCardRow({
    required this.isDark,
    required this.currentTheme,
    required this.accentColor,
    required this.onThemeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: _themePresets.map((preset) {
          final isSelected = (currentTheme == 'dark' && preset.isDarkTheme) ||
              (currentTheme == 'light' && !preset.isDarkTheme);
          final isExactMatch = _isExactMatch(preset);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onThemeSelected(preset.id),
              child: Column(
                children: [
                  _ThemePreviewCard(
                    preset: preset,
                    isSelected: isExactMatch,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    preset.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isExactMatch ? textColor : subtextColor,
                      fontWeight: isExactMatch ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  bool _isExactMatch(_ThemePreset preset) {
    if (currentTheme == 'dark') {
      return preset.id == 'night_blue';
    }
    return preset.id == 'default';
  }
}

// ── Theme Preview Card (80x92px) ──

class _ThemePreviewCard extends StatelessWidget {
  final _ThemePreset preset;
  final bool isSelected;
  final Color accentColor;

  const _ThemePreviewCard({
    required this.preset,
    required this.isSelected,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 80,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? accentColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          size: const Size(76, 88),
          painter: _ThemePreviewPainter(
            preset: preset,
            accentColor: accentColor,
            isSelected: isSelected,
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewPainter extends CustomPainter {
  final _ThemePreset preset;
  final Color accentColor;
  final bool isSelected;

  _ThemePreviewPainter({
    required this.preset,
    required this.accentColor,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background fill.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = preset.background,
    );

    // Mini chat bubbles — spec: 40x14px, 2px radius, positioned at (6, 8).
    final receivedPaint = Paint()..color = preset.receivedBubble;
    final sentPaint = Paint()..color = preset.sentBubble;

    // Received bubble (left-aligned).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 8, 40, 14),
        const Radius.circular(2),
      ),
      receivedPaint,
    );

    // Sent bubble (right-aligned).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 46, 28, 40, 14),
        const Radius.circular(2),
      ),
      sentPaint,
    );

    // Second received bubble.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 48, 32, 14),
        const Radius.circular(2),
      ),
      receivedPaint,
    );

    // Radio dot at bottom — spec: 12px from preview bottom edge.
    final dotCenterX = size.width / 2;
    final dotCenterY = size.height - 12;
    final dotRadius = 6.0;

    if (isSelected) {
      // Filled accent dot with white inner ring.
      canvas.drawCircle(
        Offset(dotCenterX, dotCenterY),
        dotRadius,
        Paint()..color = accentColor,
      );
      canvas.drawCircle(
        Offset(dotCenterX, dotCenterY),
        3.0,
        Paint()..color = preset.background,
      );
      canvas.drawCircle(
        Offset(dotCenterX, dotCenterY),
        2.0,
        Paint()..color = accentColor,
      );
    } else {
      // Empty ring.
      canvas.drawCircle(
        Offset(dotCenterX, dotCenterY),
        dotRadius,
        Paint()
          ..color = preset.isDarkTheme
              ? const Color(0xFF4A4A4A)
              : const Color(0xFFCCCCCC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ThemePreviewPainter oldDelegate) =>
      oldDelegate.isSelected != isSelected ||
      oldDelegate.accentColor != accentColor;
}

// ── Accent Color Palette ──

const _accentColors = [
  Color(0xFF40A7E3), // Blue (default)
  Color(0xFF4FAE4E), // Green
  Color(0xFFF2921C), // Orange
  Color(0xFFEC4F8E), // Pink
  Color(0xFF5C9EDA), // Cyan
  Color(0xFF7B68EE), // Purple
];

class _AccentColorPalette extends StatelessWidget {
  final Color currentColor;
  final bool isDark;
  final ValueChanged<Color> onColorSelected;

  const _AccentColorPalette({
    required this.currentColor,
    required this.isDark,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          ..._accentColors.map((color) {
            final isSelected = _colorsMatch(color, currentColor);
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => onColorSelected(color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: isSelected
                        ? Border.all(
                            color: isDark ? Colors.white : Colors.white,
                            width: 2,
                          )
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            )
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            );
          }),
          // Custom HSL picker dot (gradient circle).
          GestureDetector(
            onTap: () => _showHslPicker(context),
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                ),
              ),
              child: _isCustomColor()
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  bool _isCustomColor() {
    for (final c in _accentColors) {
      if (_colorsMatch(c, currentColor)) return false;
    }
    return true;
  }

  void _showHslPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _HslColorPickerDialog(
        initialColor: currentColor,
        isDark: isDark,
        onColorPicked: onColorSelected,
      ),
    );
  }

  static bool _colorsMatch(Color a, Color b) {
    return (a.r - b.r).abs() < 0.02 &&
        (a.g - b.g).abs() < 0.02 &&
        (a.b - b.b).abs() < 0.02;
  }
}

// ── HSL Color Picker Dialog ──

class _HslColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final bool isDark;
  final ValueChanged<Color> onColorPicked;

  const _HslColorPickerDialog({
    required this.initialColor,
    required this.isDark,
    required this.onColorPicked,
  });

  @override
  State<_HslColorPickerDialog> createState() => _HslColorPickerDialogState();
}

class _HslColorPickerDialogState extends State<_HslColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _lightness;

  @override
  void initState() {
    super.initState();
    final hsl = HSLColor.fromColor(widget.initialColor);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  Color get _currentColor =>
      HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness).toColor();

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return AlertDialog(
      backgroundColor: bgColor,
      title: Text(
        'Choose Color',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color preview.
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentColor,
              ),
            ),
            const SizedBox(height: 20),
            // Hue slider.
            _SliderRow(
              label: 'H',
              value: _hue,
              max: 360,
              isDark: widget.isDark,
              trackGradient: LinearGradient(
                colors: List.generate(
                  7,
                  (i) => HSLColor.fromAHSL(1, i * 60.0, _saturation, _lightness)
                      .toColor(),
                ),
              ),
              onChanged: (v) => setState(() => _hue = v),
              textColor: textColor,
              subtextColor: subtextColor,
            ),
            const SizedBox(height: 12),
            // Saturation slider.
            _SliderRow(
              label: 'S',
              value: _saturation * 100,
              max: 100,
              isDark: widget.isDark,
              trackGradient: LinearGradient(
                colors: [
                  HSLColor.fromAHSL(1, _hue, 0, _lightness).toColor(),
                  HSLColor.fromAHSL(1, _hue, 1, _lightness).toColor(),
                ],
              ),
              onChanged: (v) => setState(() => _saturation = v / 100),
              textColor: textColor,
              subtextColor: subtextColor,
            ),
            const SizedBox(height: 12),
            // Lightness slider.
            _SliderRow(
              label: 'L',
              value: _lightness * 100,
              max: 100,
              isDark: widget.isDark,
              trackGradient: LinearGradient(
                colors: [
                  HSLColor.fromAHSL(1, _hue, _saturation, 0).toColor(),
                  HSLColor.fromAHSL(1, _hue, _saturation, 0.5).toColor(),
                  HSLColor.fromAHSL(1, _hue, _saturation, 1).toColor(),
                ],
              ),
              onChanged: (v) => setState(() => _lightness = v / 100),
              textColor: textColor,
              subtextColor: subtextColor,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: TextStyle(color: _currentColor)),
        ),
        TextButton(
          onPressed: () {
            widget.onColorPicked(_currentColor);
            Navigator.of(context).pop();
          },
          child: Text('Apply',
              style: TextStyle(color: _currentColor)),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final bool isDark;
  final Gradient trackGradient;
  final ValueChanged<double> onChanged;
  final Color textColor;
  final Color subtextColor;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.isDark,
    required this.trackGradient,
    required this.onChanged,
    required this.textColor,
    required this.subtextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: subtextColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _GradientSlider(
            value: value,
            max: max,
            gradient: trackGradient,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ),
      ],
    );
  }
}

// ── Gradient Slider ──

class _GradientSlider extends StatefulWidget {
  final double value;
  final double max;
  final Gradient gradient;
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.value,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  @override
  State<_GradientSlider> createState() => _GradientSliderState();
}

class _GradientSliderState extends State<_GradientSlider> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fraction = widget.max > 0 ? widget.value / widget.max : 0.0;
        final thumbX = fraction * (width - 16) + 8;

        return GestureDetector(
          onHorizontalDragUpdate: (d) => _updateFromX(d.localPosition.dx, width),
          onTapDown: (d) => _updateFromX(d.localPosition.dx, width),
          child: SizedBox(
            height: 28,
            child: CustomPaint(
              size: Size(width, 28),
              painter: _GradientSliderPainter(
                gradient: widget.gradient,
                thumbX: thumbX,
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateFromX(double x, double width) {
    final fraction = ((x - 8) / (width - 16)).clamp(0.0, 1.0);
    widget.onChanged(fraction * widget.max);
  }
}

class _GradientSliderPainter extends CustomPainter {
  final Gradient gradient;
  final double thumbX;

  _GradientSliderPainter({required this.gradient, required this.thumbX});

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 3, size.width, 6),
      const Radius.circular(3),
    );
    final paint = Paint()
      ..shader = gradient.createShader(trackRect.outerRect);
    canvas.drawRRect(trackRect, paint);

    // Thumb.
    canvas.drawCircle(
      Offset(thumbX, size.height / 2),
      7.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(thumbX, size.height / 2),
      7.5,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_GradientSliderPainter old) =>
      old.thumbX != thumbX || old.gradient != gradient;
}
