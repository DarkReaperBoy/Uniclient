import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/telegram_palette.dart';
import 'confirm_box.dart';

const double _kPickerSize = 256;
const double _kSliderWidth = 19;
const double _kSliderSkip = 8;
const double _kEditSkip = 10;
const double _kFieldSkip = 13;
const double _kMarkRadius = 6;
const double _kMarkLine = 1;
const double _kCrosshairRadius = 8;
const double _kCrosshairStroke = 1;
const double _kSwatchWidth = 60;
const double _kSwatchHeight = 34;
const double _kSliderTotalWidth = _kSliderSkip + _kSliderWidth + _kSliderSkip;

Future<Color?> showColorPickerBox({
  required BuildContext context,
  required Color initialColor,
  String title = 'Choose Color',
  bool showOpacity = false,
}) {
  return showTelegramBox<Color>(
    context: context,
    builder: (ctx) => _ColorPickerBox(
      initialColor: initialColor,
      title: title,
      showOpacity: showOpacity,
    ),
  );
}

class _ColorPickerBox extends StatefulWidget {
  final Color initialColor;
  final String title;
  final bool showOpacity;

  const _ColorPickerBox({
    required this.initialColor,
    required this.title,
    this.showOpacity = false,
  });

  @override
  State<_ColorPickerBox> createState() => _ColorPickerBoxState();
}

class _ColorPickerBoxState extends State<_ColorPickerBox> {
  late double _hue;
  late double _saturation;
  late double _brightness;
  late double _opacity;

  late final TextEditingController _hCtrl, _sCtrl, _bCtrl;
  late final TextEditingController _rCtrl, _gCtrl, _blueCtrl;
  late final TextEditingController _hexCtrl;
  late final FocusNode _focusNode;

  bool _updatingFields = false;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _brightness = hsv.value;
    _opacity = hsv.alpha;

    _hCtrl = TextEditingController();
    _sCtrl = TextEditingController();
    _bCtrl = TextEditingController();
    _rCtrl = TextEditingController();
    _gCtrl = TextEditingController();
    _blueCtrl = TextEditingController();
    _hexCtrl = TextEditingController();
    _focusNode = FocusNode();

    _syncAllFields();
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _sCtrl.dispose();
    _bCtrl.dispose();
    _rCtrl.dispose();
    _gCtrl.dispose();
    _blueCtrl.dispose();
    _hexCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Color get _currentColor =>
      HSVColor.fromAHSV(_opacity, _hue, _saturation, _brightness).toColor();

  void _syncAllFields() {
    _updatingFields = true;
    _hCtrl.text = _hue.round().toString();
    _sCtrl.text = (_saturation * 100).round().toString();
    _bCtrl.text = (_brightness * 100).round().toString();
    final c = _currentColor;
    _rCtrl.text = c.red.toString();
    _gCtrl.text = c.green.toString();
    _blueCtrl.text = c.blue.toString();
    _hexCtrl.text =
        c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    _updatingFields = false;
  }

  void _onHSBFieldChanged() {
    if (_updatingFields) return;
    final h = double.tryParse(_hCtrl.text);
    final s = double.tryParse(_sCtrl.text);
    final b = double.tryParse(_bCtrl.text);
    if (h == null && s == null && b == null) return;
    setState(() {
      if (h != null) _hue = h.clamp(0, 360).toDouble();
      if (s != null) _saturation = (s / 100).clamp(0.0, 1.0);
      if (b != null) _brightness = (b / 100).clamp(0.0, 1.0);
      _updatingFields = true;
      final c = _currentColor;
      _rCtrl.text = c.red.toString();
      _gCtrl.text = c.green.toString();
      _blueCtrl.text = c.blue.toString();
      _hexCtrl.text = c.value
          .toRadixString(16)
          .padLeft(8, '0')
          .substring(2)
          .toUpperCase();
      _updatingFields = false;
    });
  }

  void _onRGBFieldChanged() {
    if (_updatingFields) return;
    final r = int.tryParse(_rCtrl.text);
    final g = int.tryParse(_gCtrl.text);
    final b = int.tryParse(_blueCtrl.text);
    if (r == null && g == null && b == null) return;
    final c = Color.fromARGB(
      (_opacity * 255).round(),
      (r ?? _currentColor.red).clamp(0, 255),
      (g ?? _currentColor.green).clamp(0, 255),
      (b ?? _currentColor.blue).clamp(0, 255),
    );
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
      _updatingFields = true;
      _hCtrl.text = _hue.round().toString();
      _sCtrl.text = (_saturation * 100).round().toString();
      _bCtrl.text = (_brightness * 100).round().toString();
      _hexCtrl.text = c.value
          .toRadixString(16)
          .padLeft(8, '0')
          .substring(2)
          .toUpperCase();
      _updatingFields = false;
    });
  }

  void _onHexFieldChanged() {
    if (_updatingFields) return;
    final hex = _hexCtrl.text.replaceAll('#', '');
    if (hex.length != 6) return;
    final val = int.tryParse(hex, radix: 16);
    if (val == null) return;
    final c = Color(0xFF000000 | val);
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
      _updatingFields = true;
      _hCtrl.text = _hue.round().toString();
      _sCtrl.text = (_saturation * 100).round().toString();
      _bCtrl.text = (_brightness * 100).round().toString();
      _rCtrl.text = c.red.toString();
      _gCtrl.text = c.green.toString();
      _blueCtrl.text = c.blue.toString();
      _updatingFields = false;
    });
  }

  void _submit() => Navigator.of(context).pop(_currentColor);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = context.palette;
    final boxBg = p.boxBg;
    final titleFg = p.boxTitleFg;
    final labelFg = p.boxTitleAdditionalFg;
    final accentFg = p.windowActiveTextFg;

    final sliderCount = widget.showOpacity ? 2 : 1;
    final pickerRowWidth = _kPickerSize +
        _kEditSkip +
        _kSliderTotalWidth * sliderCount +
        (sliderCount > 1 ? _kEditSkip : 0);
    final totalWidth =
        (pickerRowWidth + kBoxPadding.left + kBoxPadding.right)
            .clamp(kBoxWidth, 500.0);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Material(
        color: boxBg,
        borderRadius: BorderRadius.circular(kBoxRadius),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TitleBar(title: widget.title, fg: titleFg),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    kBoxPadding.left, 0, kBoxPadding.right, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPickerRow(),
                    const SizedBox(height: 16),
                    _buildSwatchRow(labelFg),
                    const SizedBox(height: 16),
                    _buildHSBRow(labelFg, isDark),
                    SizedBox(height: _kFieldSkip),
                    _buildRGBRow(labelFg, isDark),
                    SizedBox(height: _kFieldSkip),
                    _buildHexRow(labelFg, isDark),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              _ButtonRow(
                accentFg: accentFg,
                onCancel: () => Navigator.of(context).pop(),
                onApply: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerRow() {
    return SizedBox(
      height: _kPickerSize,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GradientSquare(
            hue: _hue,
            saturation: _saturation,
            brightness: _brightness,
            onChanged: (s, b) {
              setState(() {
                _saturation = s;
                _brightness = b;
                _syncAllFields();
              });
            },
          ),
          SizedBox(width: _kEditSkip),
          _VerticalHueSlider(
            value: _hue / 360,
            onChanged: (v) {
              setState(() {
                _hue = v * 360;
                _syncAllFields();
              });
            },
          ),
          if (widget.showOpacity) ...[
            SizedBox(width: _kEditSkip),
            _VerticalOpacitySlider(
              hue: _hue,
              saturation: _saturation,
              brightness: _brightness,
              value: _opacity,
              onChanged: (v) {
                setState(() {
                  _opacity = v;
                  _syncAllFields();
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwatchRow(Color labelFg) {
    return Row(
      children: [
        _SwatchBox(
          label: 'Current',
          color: widget.initialColor,
          labelFg: labelFg,
        ),
        const SizedBox(width: 12),
        _SwatchBox(label: 'New', color: _currentColor, labelFg: labelFg),
      ],
    );
  }

  Widget _buildHSBRow(Color labelFg, bool isDark) {
    return Row(
      children: [
        _NumericField(
            label: 'H',
            ctrl: _hCtrl,
            max: 360,
            labelFg: labelFg,
            isDark: isDark,
            onChanged: _onHSBFieldChanged,
            onSubmitted: _submit),
        SizedBox(width: _kFieldSkip),
        _NumericField(
            label: 'S',
            ctrl: _sCtrl,
            max: 100,
            labelFg: labelFg,
            isDark: isDark,
            onChanged: _onHSBFieldChanged,
            onSubmitted: _submit),
        SizedBox(width: _kFieldSkip),
        _NumericField(
            label: 'B',
            ctrl: _bCtrl,
            max: 100,
            labelFg: labelFg,
            isDark: isDark,
            onChanged: _onHSBFieldChanged,
            onSubmitted: _submit),
      ],
    );
  }

  Widget _buildRGBRow(Color labelFg, bool isDark) {
    return Row(
      children: [
        _NumericField(
            label: 'R',
            ctrl: _rCtrl,
            max: 255,
            labelFg: labelFg,
            isDark: isDark,
            onChanged: _onRGBFieldChanged,
            onSubmitted: _submit),
        SizedBox(width: _kFieldSkip),
        _NumericField(
            label: 'G',
            ctrl: _gCtrl,
            max: 255,
            labelFg: labelFg,
            isDark: isDark,
            onChanged: _onRGBFieldChanged,
            onSubmitted: _submit),
        SizedBox(width: _kFieldSkip),
        _NumericField(
            label: 'B',
            ctrl: _blueCtrl,
            max: 255,
            labelFg: labelFg,
            isDark: isDark,
            onChanged: _onRGBFieldChanged,
            onSubmitted: _submit),
      ],
    );
  }

  Widget _buildHexRow(Color labelFg, bool isDark) {
    final textFg =
        isDark ? const Color(0xFFE0E3EA) : const Color(0xFF000000);
    final borderColor =
        isDark ? const Color(0xFF3A4655) : const Color(0xFFD9D9D9);
    return Row(
      children: [
        Text('#',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: labelFg)),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: _hexCtrl,
              style: TextStyle(fontSize: 13, color: textFg),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: borderColor)),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) => _onHexFieldChanged(),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Title bar ──────────────────────────────────────────────────────────────

class _TitleBar extends StatelessWidget {
  final String title;
  final Color fg;
  const _TitleBar({required this.title, required this.fg});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kBoxTitleHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, top: 13),
        child: Text(title,
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
      ),
    );
  }
}

// ─── Button row ─────────────────────────────────────────────────────────────

class _ButtonRow extends StatelessWidget {
  final Color accentFg;
  final VoidCallback onCancel;
  final VoidCallback onApply;
  const _ButtonRow(
      {required this.accentFg,
      required this.onCancel,
      required this.onApply});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
              onPressed: onCancel,
              child: Text('Cancel',
                  style: TextStyle(color: accentFg, fontSize: 14))),
          const SizedBox(width: 8),
          TextButton(
              onPressed: onApply,
              child: Text('Apply',
                  style: TextStyle(color: accentFg, fontSize: 14))),
        ],
      ),
    );
  }
}

// ─── Color swatch ───────────────────────────────────────────────────────────

class _SwatchBox extends StatelessWidget {
  final String label;
  final Color color;
  final Color labelFg;
  const _SwatchBox(
      {required this.label, required this.color, required this.labelFg});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: labelFg)),
        const SizedBox(height: 4),
        Container(
          width: _kSwatchWidth,
          height: _kSwatchHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

// ─── Numeric input field ────────────────────────────────────────────────────

class _NumericField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final int max;
  final Color labelFg;
  final bool isDark;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  const _NumericField({
    required this.label,
    required this.ctrl,
    required this.max,
    required this.labelFg,
    required this.isDark,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final textFg =
        isDark ? const Color(0xFFE0E3EA) : const Color(0xFF000000);
    final borderColor =
        isDark ? const Color(0xFF3A4655) : const Color(0xFFD9D9D9);
    return Expanded(
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: labelFg)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: ctrl,
                style: TextStyle(fontSize: 13, color: textFg),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: borderColor)),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _MaxValueFormatter(max),
                ],
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaxValueFormatter extends TextInputFormatter {
  final int maxValue;
  _MaxValueFormatter(this.maxValue);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final val = int.tryParse(newValue.text);
    if (val == null) return oldValue;
    if (val > maxValue) {
      final clamped = maxValue.toString();
      return TextEditingValue(
        text: clamped,
        selection: TextSelection.collapsed(offset: clamped.length),
      );
    }
    return newValue;
  }
}

// ─── 2D HSB gradient square ─────────────────────────────────────────────────

class _GradientSquare extends StatelessWidget {
  final double hue;
  final double saturation;
  final double brightness;
  final void Function(double saturation, double brightness) onChanged;

  const _GradientSquare({
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.onChanged,
  });

  void _handle(Offset local) {
    final s = (local.dx / _kPickerSize).clamp(0.0, 1.0);
    final b = 1.0 - (local.dy / _kPickerSize).clamp(0.0, 1.0);
    onChanged(s, b);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handle(e.localPosition),
      onPointerMove: (e) => _handle(e.localPosition),
      child: SizedBox(
        width: _kPickerSize,
        height: _kPickerSize,
        child: CustomPaint(
          painter: _HSBGradientPainter(hue: hue),
          foregroundPainter: _CrosshairPainter(
            x: saturation * _kPickerSize,
            y: (1 - brightness) * _kPickerSize,
          ),
        ),
      ),
    );
  }
}

class _HSBGradientPainter extends CustomPainter {
  final double hue;
  _HSBGradientPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pureColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    final satShader = LinearGradient(
      colors: [Colors.white, pureColor],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = satShader);

    final brightShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = brightShader);
  }

  @override
  bool shouldRepaint(_HSBGradientPainter old) => old.hue != hue;
}

class _CrosshairPainter extends CustomPainter {
  final double x, y;
  _CrosshairPainter({required this.x, required this.y});

  @override
  void paint(Canvas canvas, Size size) {
    final pos = Offset(x, y);
    canvas.drawCircle(
        pos,
        _kCrosshairRadius + _kCrosshairStroke,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kCrosshairStroke
          ..color = const Color(0x4D000000));
    canvas.drawCircle(
        pos,
        _kCrosshairRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kCrosshairStroke
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.x != x || old.y != y;
}

// ─── Vertical hue slider ────────────────────────────────────────────────────

class _VerticalHueSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _VerticalHueSlider({required this.value, required this.onChanged});

  void _handle(Offset local) {
    onChanged((local.dy / _kPickerSize).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handle(e.localPosition),
      onPointerMove: (e) => _handle(e.localPosition),
      child: SizedBox(
        width: _kSliderTotalWidth,
        height: _kPickerSize,
        child: CustomPaint(
          painter: _HueSliderPainter(value: value),
        ),
      ),
    );
  }
}

class _HueSliderPainter extends CustomPainter {
  final double value;
  _HueSliderPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final barRect = Rect.fromLTWH(_kSliderSkip, 0, _kSliderWidth, size.height);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: List.generate(
          7, (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor()),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(4)),
      Paint()..shader = gradient.createShader(barRect),
    );

    final markY = value * size.height;
    final markX = size.width / 2;
    canvas.drawCircle(
        Offset(markX, markY),
        _kMarkRadius + _kMarkLine,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kMarkLine
          ..color = const Color(0x4D000000));
    canvas.drawCircle(
        Offset(markX, markY),
        _kMarkRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kMarkLine * 2
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_HueSliderPainter old) => old.value != value;
}

// ─── Vertical opacity slider ────────────────────────────────────────────────

class _VerticalOpacitySlider extends StatelessWidget {
  final double hue, saturation, brightness;
  final double value;
  final ValueChanged<double> onChanged;
  const _VerticalOpacitySlider({
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.value,
    required this.onChanged,
  });

  void _handle(Offset local) {
    onChanged((local.dy / _kPickerSize).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final pure =
        HSVColor.fromAHSV(1, hue, saturation, brightness).toColor();
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handle(e.localPosition),
      onPointerMove: (e) => _handle(e.localPosition),
      child: SizedBox(
        width: _kSliderTotalWidth,
        height: _kPickerSize,
        child: CustomPaint(
          painter: _OpacitySliderPainter(color: pure, value: value),
        ),
      ),
    );
  }
}

class _OpacitySliderPainter extends CustomPainter {
  final Color color;
  final double value;
  _OpacitySliderPainter({required this.color, required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final barRect = Rect.fromLTWH(_kSliderSkip, 0, _kSliderWidth, size.height);
    final rrect = RRect.fromRectAndRadius(barRect, const Radius.circular(4));

    // Checkerboard background for transparency indication
    canvas.save();
    canvas.clipRRect(rrect);
    const checkSize = 4.0;
    final checkPaint1 = Paint()..color = const Color(0xFFCCCCCC);
    final checkPaint2 = Paint()..color = Colors.white;
    for (var y = 0.0; y < size.height; y += checkSize) {
      for (var x = _kSliderSkip; x < _kSliderSkip + _kSliderWidth;
          x += checkSize) {
        final isOdd = ((x - _kSliderSkip) ~/ checkSize + y ~/ checkSize) % 2 ==
            0;
        canvas.drawRect(Rect.fromLTWH(x, y, checkSize, checkSize),
            isOdd ? checkPaint1 : checkPaint2);
      }
    }

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withAlpha(0), color],
    );
    canvas.drawRRect(
        rrect, Paint()..shader = gradient.createShader(barRect));
    canvas.restore();

    final markY = value * size.height;
    final markX = size.width / 2;
    canvas.drawCircle(
        Offset(markX, markY),
        _kMarkRadius + _kMarkLine,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kMarkLine
          ..color = const Color(0x4D000000));
    canvas.drawCircle(
        Offset(markX, markY),
        _kMarkRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kMarkLine * 2
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_OpacitySliderPainter old) =>
      old.color != color || old.value != value;
}
