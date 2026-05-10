import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../theme/telegram_palette.dart';
import 'confirm_box.dart';

const double _kPickerSize = 256;
const double _kSliderWidth = 19;
const double _kSliderSkip = 8;
const double _kEditSkip = 10;
const double _kCrosshairRadius = 6;
const double _kCrosshairStroke = 1;
const double _kSwatchHeight = 34;
const double _kFieldHeight = 26;
const double _kSliderTotalWidth = _kSliderSkip + _kSliderWidth + _kSliderSkip;
const double _kArrowHalf = 4;
const double _kEditWidth = 390;

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

  late final FocusNode _dialogFocus;
  late final FocusNode _hFocus, _sFocus, _bFocus;
  late final FocusNode _rFocus, _gFocus, _blueFocus;
  late final FocusNode _hexFocus;
  late final List<FocusNode> _fieldOrder;
  late final List<TextEditingController> _fieldCtrls;

  bool _updatingFields = false;

  FocusNode _makeNumericFocus(TextEditingController ctrl, int max, int idx) {
    return FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _changeFieldValue(ctrl, max, 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _changeFieldValue(ctrl, max, -1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _advanceFocus(idx);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  void _changeFieldValue(TextEditingController ctrl, int max, int delta) {
    final cur = int.tryParse(ctrl.text) ?? 0;
    final val = (cur + delta).clamp(0, max);
    ctrl.text = val.toString();
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    setState(() {
      if (ctrl == _hCtrl || ctrl == _sCtrl || ctrl == _bCtrl) {
        if (ctrl == _hCtrl) _hue = val.toDouble();
        if (ctrl == _sCtrl) _saturation = val / 100;
        if (ctrl == _bCtrl) _brightness = val / 100;
        _updatingFields = true;
        final c = _currentColor;
        _rCtrl.text = c.red.toString();
        _gCtrl.text = c.green.toString();
        _blueCtrl.text = c.blue.toString();
        _hexCtrl.text = _hexString(c);
        _updatingFields = false;
      } else {
        _onRGBFieldChanged();
      }
    });
  }

  void _advanceFocus(int idx) {
    if (idx < _fieldOrder.length - 1) {
      final next = _fieldOrder[idx + 1];
      next.requestFocus();
      final nextCtrl = _fieldCtrls[idx + 1];
      nextCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: nextCtrl.text.length);
    } else {
      _submit();
    }
  }

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

    _dialogFocus = FocusNode();
    _hFocus = _makeNumericFocus(_hCtrl, 360, 0);
    _sFocus = _makeNumericFocus(_sCtrl, 100, 1);
    _bFocus = _makeNumericFocus(_bCtrl, 100, 2);
    _rFocus = _makeNumericFocus(_rCtrl, 255, 3);
    _gFocus = _makeNumericFocus(_gCtrl, 255, 4);
    _blueFocus = _makeNumericFocus(_blueCtrl, 255, 5);
    _hexFocus = FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _submit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _fieldOrder = [
      _hFocus, _sFocus, _bFocus, _rFocus, _gFocus, _blueFocus, _hexFocus
    ];
    _fieldCtrls = [
      _hCtrl, _sCtrl, _bCtrl, _rCtrl, _gCtrl, _blueCtrl, _hexCtrl
    ];

    _syncAllFields();
  }

  @override
  void dispose() {
    for (final c
        in [_hCtrl, _sCtrl, _bCtrl, _rCtrl, _gCtrl, _blueCtrl, _hexCtrl]) {
      c.dispose();
    }
    _dialogFocus.dispose();
    for (final f in _fieldOrder) {
      f.dispose();
    }
    super.dispose();
  }

  Color get _currentColor =>
      HSVColor.fromAHSV(_opacity, _hue, _saturation, _brightness).toColor();

  static String _hex2(int v) => v.toRadixString(16).padLeft(2, '0');

  String _hexString(Color c) {
    if (widget.showOpacity) {
      return '${_hex2(c.red)}${_hex2(c.green)}${_hex2(c.blue)}${_hex2((_opacity * 255).round())}'
          .toUpperCase();
    }
    return '${_hex2(c.red)}${_hex2(c.green)}${_hex2(c.blue)}'.toUpperCase();
  }

  void _syncAllFields() {
    _updatingFields = true;
    _hCtrl.text = _hue.round().toString();
    _sCtrl.text = (_saturation * 100).round().toString();
    _bCtrl.text = (_brightness * 100).round().toString();
    final c = _currentColor;
    _rCtrl.text = c.red.toString();
    _gCtrl.text = c.green.toString();
    _blueCtrl.text = c.blue.toString();
    _hexCtrl.text = _hexString(c);
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
      _hexCtrl.text = _hexString(c);
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
      _hexCtrl.text = _hexString(c);
      _updatingFields = false;
    });
  }

  void _onHexFieldChanged() {
    if (_updatingFields) return;
    final hex = _hexCtrl.text.replaceAll('#', '');
    if (hex.length != 6 && hex.length != 8) return;
    final val = int.tryParse(hex, radix: 16);
    if (val == null) return;

    Color c;
    if (hex.length == 8) {
      final r = (val >> 24) & 0xFF;
      final g = (val >> 16) & 0xFF;
      final b = (val >> 8) & 0xFF;
      final a = val & 0xFF;
      c = Color.fromARGB(a, r, g, b);
    } else {
      c = Color(0xFF000000 | val);
    }

    final hsv = HSVColor.fromColor(c);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
      if (hex.length == 8) _opacity = c.alpha / 255;
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

  void _resetToOriginal() {
    final hsv = HSVColor.fromColor(widget.initialColor);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
      _opacity = hsv.alpha;
      _syncAllFields();
    });
  }

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
    final accentFg = p.windowActiveTextFg;
    final totalWidth = _kEditWidth + kBoxPadding.left + kBoxPadding.right;

    return Focus(
      focusNode: _dialogFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Material(
        color: p.boxBg,
        borderRadius: BorderRadius.circular(kBoxRadius),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TitleBar(title: widget.title, fg: p.boxTitleFg),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    kBoxPadding.left, 0, kBoxPadding.right, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
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
                                arrowColor: accentFg,
                                onChanged: (v) {
                                  setState(() {
                                    _hue = v * 360;
                                    _syncAllFields();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        if (widget.showOpacity) ...[
                          const SizedBox(height: 2),
                          _HorizontalOpacitySlider(
                            hue: _hue,
                            saturation: _saturation,
                            brightness: _brightness,
                            value: _opacity,
                            arrowColor: accentFg,
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
                    SizedBox(width: _kEditSkip),
                    Expanded(
                      child: _buildFieldColumn(
                          p.boxTitleAdditionalFg, isDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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

  Widget _buildFieldColumn(Color labelFg, bool isDark) {
    final textFg =
        isDark ? const Color(0xFFE0E3EA) : const Color(0xFF000000);
    final borderColor =
        isDark ? const Color(0xFF3A4655) : const Color(0xFFD9D9D9);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: _kSwatchHeight,
          decoration: BoxDecoration(
            color: _currentColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: _resetToOriginal,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              height: _kSwatchHeight,
              decoration: BoxDecoration(
                color: widget.initialColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _numField('H', _hCtrl, 360, _hFocus, 0, labelFg, textFg, borderColor,
            _onHSBFieldChanged),
        const SizedBox(height: 3),
        _numField('S', _sCtrl, 100, _sFocus, 1, labelFg, textFg, borderColor,
            _onHSBFieldChanged),
        const SizedBox(height: 3),
        _numField('B', _bCtrl, 100, _bFocus, 2, labelFg, textFg, borderColor,
            _onHSBFieldChanged),
        const SizedBox(height: 6),
        _numField('R', _rCtrl, 255, _rFocus, 3, labelFg, textFg, borderColor,
            _onRGBFieldChanged),
        const SizedBox(height: 3),
        _numField('G', _gCtrl, 255, _gFocus, 4, labelFg, textFg, borderColor,
            _onRGBFieldChanged),
        const SizedBox(height: 3),
        _numField('B', _blueCtrl, 255, _blueFocus, 5, labelFg, textFg,
            borderColor, _onRGBFieldChanged),
        const SizedBox(height: 6),
        _hexField(labelFg, textFg, borderColor),
      ],
    );
  }

  Widget _numField(
    String label,
    TextEditingController ctrl,
    int max,
    FocusNode focusNode,
    int idx,
    Color labelFg,
    Color textFg,
    Color borderColor,
    VoidCallback onChanged,
  ) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && focusNode.hasFocus) {
          final delta = event.scrollDelta.dy < 0 ? 5 : -5;
          _changeFieldValue(ctrl, max, delta);
        }
      },
      child: SizedBox(
        height: _kFieldHeight,
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
              child: TextField(
                controller: ctrl,
                focusNode: focusNode,
                style: TextStyle(fontSize: 13, color: textFg),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                onSubmitted: (_) => _advanceFocus(idx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hexField(Color labelFg, Color textFg, Color borderColor) {
    return SizedBox(
      height: _kFieldHeight,
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text('#',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: labelFg)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _hexCtrl,
              focusNode: _hexFocus,
              style: TextStyle(fontSize: 13, color: textFg),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: borderColor)),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(8),
              ],
              onChanged: (_) => _onHexFieldChanged(),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
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

// ─── Max value formatter ────────────────────────────────────────────────────

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
            hue: hue,
            saturation: saturation,
            brightness: brightness,
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
  final double hue, saturation, brightness;
  _CrosshairPainter({
    required this.x,
    required this.y,
    required this.hue,
    required this.saturation,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pos = Offset(x, y);
    final c = HSVColor.fromAHSV(1, hue, saturation, brightness).toColor();
    final lum =
        0.2989 * c.red / 255 + 0.5870 * c.green / 255 + 0.1140 * c.blue / 255;
    final fg =
        lum > 0.6 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final shadow =
        lum > 0.6 ? const Color(0x4DFFFFFF) : const Color(0x4D000000);

    canvas.drawCircle(
        pos,
        _kCrosshairRadius + _kCrosshairStroke,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kCrosshairStroke
          ..color = shadow);
    canvas.drawCircle(
        pos,
        _kCrosshairRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kCrosshairStroke
          ..color = fg);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) =>
      old.x != x ||
      old.y != y ||
      old.hue != hue ||
      old.saturation != saturation ||
      old.brightness != brightness;
}

// ─── Vertical hue slider ────────────────────────────────────────────────────

class _VerticalHueSlider extends StatelessWidget {
  final double value;
  final Color arrowColor;
  final ValueChanged<double> onChanged;
  const _VerticalHueSlider({
    required this.value,
    required this.arrowColor,
    required this.onChanged,
  });

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
          painter: _HueSliderPainter(value: value, arrowColor: arrowColor),
        ),
      ),
    );
  }
}

class _HueSliderPainter extends CustomPainter {
  final double value;
  final Color arrowColor;
  _HueSliderPainter({required this.value, required this.arrowColor});

  @override
  void paint(Canvas canvas, Size size) {
    final barRect =
        Rect.fromLTWH(_kSliderSkip, 0, _kSliderWidth, size.height);
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
    final paint = Paint()..color = arrowColor;

    final left = Path()
      ..moveTo(0, markY - _kArrowHalf)
      ..lineTo(_kSliderSkip, markY)
      ..lineTo(0, markY + _kArrowHalf)
      ..close();
    canvas.drawPath(left, paint);

    final right = Path()
      ..moveTo(size.width, markY - _kArrowHalf)
      ..lineTo(size.width - _kSliderSkip, markY)
      ..lineTo(size.width, markY + _kArrowHalf)
      ..close();
    canvas.drawPath(right, paint);
  }

  @override
  bool shouldRepaint(_HueSliderPainter old) =>
      old.value != value || old.arrowColor != arrowColor;
}

// ─── Horizontal opacity slider ──────────────────────────────────────────────

class _HorizontalOpacitySlider extends StatelessWidget {
  final double hue, saturation, brightness;
  final double value;
  final Color arrowColor;
  final ValueChanged<double> onChanged;
  const _HorizontalOpacitySlider({
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.value,
    required this.arrowColor,
    required this.onChanged,
  });

  void _handle(Offset local) {
    onChanged((local.dx / _kPickerSize).clamp(0.0, 1.0));
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
        width: _kPickerSize,
        height: _kSliderTotalWidth,
        child: CustomPaint(
          painter: _HorizontalOpacityPainter(
              color: pure, value: value, arrowColor: arrowColor),
        ),
      ),
    );
  }
}

class _HorizontalOpacityPainter extends CustomPainter {
  final Color color;
  final double value;
  final Color arrowColor;
  _HorizontalOpacityPainter({
    required this.color,
    required this.value,
    required this.arrowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barRect =
        Rect.fromLTWH(0, _kSliderSkip, size.width, _kSliderWidth);
    final rrect = RRect.fromRectAndRadius(barRect, const Radius.circular(4));

    canvas.save();
    canvas.clipRRect(rrect);
    const checkSize = 4.0;
    final cp1 = Paint()..color = const Color(0xFFCCCCCC);
    final cp2 = Paint()..color = Colors.white;
    for (var y = _kSliderSkip; y < _kSliderSkip + _kSliderWidth;
        y += checkSize) {
      for (var x = 0.0; x < size.width; x += checkSize) {
        final odd =
            (x ~/ checkSize + (y - _kSliderSkip) ~/ checkSize) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, checkSize, checkSize),
            odd ? cp1 : cp2);
      }
    }

    final gradient = LinearGradient(
      colors: [color.withAlpha(0), color],
    );
    canvas.drawRRect(rrect, Paint()..shader = gradient.createShader(barRect));
    canvas.restore();

    final markX = value * size.width;
    final paint = Paint()..color = arrowColor;

    final top = Path()
      ..moveTo(markX - _kArrowHalf, 0)
      ..lineTo(markX, _kSliderSkip)
      ..lineTo(markX + _kArrowHalf, 0)
      ..close();
    canvas.drawPath(top, paint);

    final bottom = Path()
      ..moveTo(markX - _kArrowHalf, size.height)
      ..lineTo(markX, size.height - _kSliderSkip)
      ..lineTo(markX + _kArrowHalf, size.height)
      ..close();
    canvas.drawPath(bottom, paint);
  }

  @override
  bool shouldRepaint(_HorizontalOpacityPainter old) =>
      old.color != color || old.value != value || old.arrowColor != arrowColor;
}
