import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
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
const double _kArrowHalf = 3.5;
const double _kEditWidth = 390;
const double _kMinFieldWidth = 60;

/// Mirrors AyuGram's `ColorEditor::Mode` (`ui/widgets/color_editor.h`).
///
/// * [rgba] — saturation×brightness picker square + vertical hue slider
///   (+ optional opacity slider). HSV color space.
/// * [hsl] — hue×saturation picker square + horizontal lightness slider, no
///   hue slider, no opacity. HSL color space; lightness is bounded to
///   [lightnessMin]…[lightnessMax].
enum ColorEditorMode { rgba, hsl }

Future<Color?> showColorPickerBox({
  required BuildContext context,
  required Color initialColor,
  String title = 'Choose Color',
  bool showOpacity = false,
  ColorEditorMode mode = ColorEditorMode.rgba,
  double? lightnessMin,
  double? lightnessMax,
}) {
  return showTelegramBox<Color>(
    context: context,
    builder: (ctx) => _ColorPickerBox(
      initialColor: initialColor,
      title: title,
      showOpacity: showOpacity,
      mode: mode,
      lightnessMin: lightnessMin,
      lightnessMax: lightnessMax,
    ),
  );
}

class _ColorPickerBox extends StatefulWidget {
  final Color initialColor;
  final String title;
  final bool showOpacity;
  final ColorEditorMode mode;
  final double? lightnessMin;
  final double? lightnessMax;

  const _ColorPickerBox({
    required this.initialColor,
    required this.title,
    this.showOpacity = false,
    this.mode = ColorEditorMode.rgba,
    this.lightnessMin,
    this.lightnessMax,
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
  final List<int> _wheelAccum = List.filled(7, 0);

  bool get _isHsl => widget.mode == ColorEditorMode.hsl;

  // Lightness limits (HSL mode only), as fractions 0..1. Mirror AyuGram's
  // `_lightnessMin`/`_lightnessMax` (bytes 0..255 there). Default = full range.
  double get _lightnessMinV => widget.lightnessMin ?? 0.0;
  double get _lightnessMaxV => widget.lightnessMax ?? 1.0;

  double _clampLightness(double v) {
    final lo = _lightnessMinV;
    final hi = _lightnessMaxV;
    return hi > lo ? v.clamp(lo, hi) : lo;
  }

  // Position of the lightness slider arrow within its [min..max] range.
  // Mirrors `Slider::valueFromColor` for `Type::Lightness`.
  double get _lightnessSliderValue {
    final range = _lightnessMaxV - _lightnessMinV;
    if (range <= 0) return 0;
    return ((_brightness - _lightnessMinV) / range).clamp(0.0, 1.0);
  }

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
        if (ctrl == _bCtrl) {
          _brightness = _isHsl ? _clampLightness(val / 100) : val / 100;
        }
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
    if (_isHsl) {
      final hsl = HSLColor.fromColor(widget.initialColor);
      _hue = hsl.hue;
      _saturation = hsl.saturation;
      _brightness = _clampLightness(hsl.lightness);
      _opacity = 1.0;
    } else {
      final hsv = HSVColor.fromColor(widget.initialColor);
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
      _opacity = hsv.alpha;
    }

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hexFocus.requestFocus();
      _hexCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _hexCtrl.text.length);
    });
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

  // In HSL mode `_brightness` holds the HSL *lightness*, already bounded to
  // [_lightnessMinV.._lightnessMaxV] by the slider range and the L-field clamp
  // (so the crosshair/slider/swatch never disagree with the result — the bug
  // the old output-only clamp caused). In RGBA mode it is the HSV value.
  Color get _currentColor => _isHsl
      ? HSLColor.fromAHSL(1.0, _hue, _saturation, _clampLightness(_brightness))
          .toColor()
      : HSVColor.fromAHSV(_opacity, _hue, _saturation, _brightness).toColor();

  static String _hex2(int v) => v.toRadixString(16).padLeft(2, '0');

  String _hexString(Color c) {
    final base = '${_hex2(c.red)}${_hex2(c.green)}${_hex2(c.blue)}';
    if (widget.showOpacity && (_opacity * 255).round() != 255) {
      return '$base${_hex2((_opacity * 255).round())}'.toUpperCase();
    }
    return base.toUpperCase();
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
      if (b != null) {
        _brightness = _isHsl
            ? _clampLightness(b / 100)
            : (b / 100).clamp(0.0, 1.0);
      }
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
      _isHsl ? 255 : (_opacity * 255).round(),
      (r ?? _currentColor.red).clamp(0, 255),
      (g ?? _currentColor.green).clamp(0, 255),
      (b ?? _currentColor.blue).clamp(0, 255),
    );
    setState(() {
      if (_isHsl) {
        final hsl = HSLColor.fromColor(c);
        _hue = hsl.hue;
        _saturation = hsl.saturation;
        _brightness = _clampLightness(hsl.lightness);
      } else {
        final hsv = HSVColor.fromColor(c);
        _hue = hsv.hue;
        _saturation = hsv.saturation;
        _brightness = hsv.value;
      }
      _updatingFields = true;
      _hCtrl.text = _hue.round().toString();
      _sCtrl.text = (_saturation * 100).round().toString();
      _bCtrl.text = (_brightness * 100).round().toString();
      // HSL clamps lightness, so the hex must reflect the bounded result.
      _hexCtrl.text = _hexString(_isHsl ? _currentColor : c);
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

    setState(() {
      if (_isHsl) {
        final hsl = HSLColor.fromColor(c);
        _hue = hsl.hue;
        _saturation = hsl.saturation;
        _brightness = _clampLightness(hsl.lightness);
      } else {
        final hsv = HSVColor.fromColor(c);
        _hue = hsv.hue;
        _saturation = hsv.saturation;
        _brightness = hsv.value;
        if (hex.length == 8) _opacity = c.alpha / 255;
      }
      final display = _isHsl ? _currentColor : c;
      _updatingFields = true;
      _hCtrl.text = _hue.round().toString();
      _sCtrl.text = (_saturation * 100).round().toString();
      _bCtrl.text = (_brightness * 100).round().toString();
      _rCtrl.text = display.red.toString();
      _gCtrl.text = display.green.toString();
      _blueCtrl.text = display.blue.toString();
      _updatingFields = false;
    });
  }

  void _submit() => Navigator.of(context).pop(_currentColor);

  void _resetToOriginal() {
    setState(() {
      if (_isHsl) {
        final hsl = HSLColor.fromColor(widget.initialColor);
        _hue = hsl.hue;
        _saturation = hsl.saturation;
        _brightness = _clampLightness(hsl.lightness);
        _opacity = 1.0;
      } else {
        final hsv = HSVColor.fromColor(widget.initialColor);
        _hue = hsv.hue;
        _saturation = hsv.saturation;
        _brightness = hsv.value;
        _opacity = hsv.alpha;
      }
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
    final p = context.palette;
    final accentFg = p.windowActiveTextFg;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = _kEditWidth + kBoxPadding.left + kBoxPadding.right;
    final totalWidth = maxWidth > screenWidth ? screenWidth - 16 : maxWidth;
    final innerWidth =
        totalWidth - kBoxPadding.left - kBoxPadding.right;
    // Right-hand column width. In HSL mode the absent hue slider frees
    // `colorEditSkip` of width, which AyuGram folds into the column:
    // fieldWidth = colorSampleSize.width (60) + colorEditSkip (10) = 70 in HSL,
    // 60 in RGBA. (color_editor.cpp:1053-1054)
    final fieldWidth = _kMinFieldWidth + (_isHsl ? _kEditSkip : 0);
    // RGBA reserves room for the vertical hue slider beside the square; HSL has
    // no hue slider, so the square can use that width.
    final pickerSize = (_isHsl
            ? (innerWidth - _kEditSkip - fieldWidth)
            : (innerWidth -
                _kSliderTotalWidth -
                2 * _kEditSkip -
                _kMinFieldWidth))
        .clamp(150.0, _kPickerSize);

    return Focus(
      focusNode: _dialogFocus,
      autofocus: false,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      // AyuGram centers the picker+sliders+fields cluster within
                      // the 390px editor: left = (width - fullwidth) / 2, giving
                      // symmetric margins instead of dumping the slack on the
                      // right. (color_editor.cpp:1026)
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: pickerSize,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DecoratedBox(
                                    decoration: const BoxDecoration(
                                      boxShadow: [
                                        BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2)),
                                      ],
                                    ),
                                    child: _GradientSquare(
                                      pickerSize: pickerSize,
                                      mode: widget.mode,
                                      hue: _hue,
                                      saturation: _saturation,
                                      brightness: _brightness,
                                      onChanged: (x, y) {
                                        setState(() {
                                          if (_isHsl) {
                                            // x = hue, y = saturation
                                            _hue = x * 360;
                                            _saturation = 1.0 - y;
                                          } else {
                                            // x = saturation, y = brightness
                                            _saturation = x;
                                            _brightness = 1.0 - y;
                                          }
                                          _syncAllFields();
                                        });
                                      },
                                    ),
                                  ),
                                  if (!_isHsl) ...[
                                    // The slider widget already carries an 8px
                                    // internal _kSliderSkip before its bar, so a
                                    // (colorEditSkip - colorSliderSkip) = 2px
                                    // spacer lands the bar exactly colorEditSkip
                                    // (10px) from the picker edge — matching
                                    // AyuGram. (color_editor.cpp:1030)
                                    SizedBox(width: _kEditSkip - _kSliderSkip),
                                    _VerticalHueSlider(
                                      pickerSize: pickerSize,
                                      value: 1.0 - _hue / 360,
                                      arrowColor: p.sliderBgActive,
                                      onChanged: (v) {
                                        setState(() {
                                          _hue = (1.0 - v) * 360;
                                          _syncAllFields();
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (_isHsl) ...[
                              const SizedBox(height: 2),
                              _HorizontalLightnessSlider(
                                pickerSize: pickerSize,
                                hue: _hue,
                                saturation: _saturation,
                                lightnessMin: _lightnessMinV,
                                lightnessMax: _lightnessMaxV,
                                value: _lightnessSliderValue,
                                arrowColor: p.sliderBgActive,
                                onChanged: (v) {
                                  setState(() {
                                    _brightness = _clampLightness(_lightnessMinV +
                                        v * (_lightnessMaxV - _lightnessMinV));
                                    _syncAllFields();
                                  });
                                },
                              ),
                            ] else if (widget.showOpacity) ...[
                              const SizedBox(height: 2),
                              _HorizontalOpacitySlider(
                                pickerSize: pickerSize,
                                hue: _hue,
                                saturation: _saturation,
                                brightness: _brightness,
                                value: _opacity,
                                arrowColor: p.sliderBgActive,
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
                        SizedBox(
                          width: fieldWidth,
                          child: _buildFieldColumn(
                              p.boxTitleAdditionalFg, p.boxTextFg, p.inputBorderFg),
                        ),
                      ],
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

  Widget _buildCheckerboard(double height) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _CheckerboardPainter(),
    );
  }

  Widget _buildSwatch(Color color, {bool isCurrent = true}) {
    final showChecker = widget.showOpacity && color.alpha < 255;
    final content = Container(
      height: _kSwatchHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (showChecker)
            Positioned.fill(child: _buildCheckerboard(_kSwatchHeight)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: color),
            ),
          ),
        ],
      ),
    );
    if (!isCurrent) {
      return GestureDetector(
        onTap: _resetToOriginal,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: content,
        ),
      );
    }
    return content;
  }

  Widget _buildFieldColumn(Color labelFg, Color textFg, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSwatch(_currentColor, isCurrent: true),
              _buildSwatch(widget.initialColor, isCurrent: false),
            ],
          ),
        ),
        const SizedBox(height: 13),
        _numField('H', _hCtrl, 360, _hFocus, 0, labelFg, textFg, borderColor,
            _onHSBFieldChanged, suffix: '°'),
        _numField('S', _sCtrl, 100, _sFocus, 1, labelFg, textFg, borderColor,
            _onHSBFieldChanged, suffix: '%'),
        _numField(_isHsl ? 'L' : 'B', _bCtrl, 100, _bFocus, 2, labelFg, textFg,
            borderColor, _onHSBFieldChanged, suffix: '%'),
        const SizedBox(height: 13),
        _numField('R', _rCtrl, 255, _rFocus, 3, labelFg, textFg, borderColor,
            _onRGBFieldChanged),
        _numField('G', _gCtrl, 255, _gFocus, 4, labelFg, textFg, borderColor,
            _onRGBFieldChanged),
        _numField('B', _blueCtrl, 255, _blueFocus, 5, labelFg, textFg,
            borderColor, _onRGBFieldChanged),
        const SizedBox(height: _kSliderSkip),
        if (widget.showOpacity)
          SizedBox(
            height: _kFieldHeight,
            child: OverflowBox(
              maxWidth: _kMinFieldWidth + _kEditSkip + _kSliderWidth,
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _kMinFieldWidth + _kEditSkip + _kSliderWidth,
                child: _hexField(labelFg, textFg, borderColor),
              ),
            ),
          )
        else
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
    VoidCallback onChanged, {
    String? suffix,
  }) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && focusNode.hasFocus) {
          var deltaX = -event.scrollDelta.dx.toInt();
          final deltaY = -event.scrollDelta.dy.toInt();
          if (defaultTargetPlatform == TargetPlatform.macOS) {
            deltaX = -deltaX;
          }
          final raw = (deltaX.abs() > deltaY.abs()) ? deltaX : deltaY;
          _wheelAccum[idx] += raw * 3;
          const kStep = 5;
          final steps = _wheelAccum[idx] ~/ kStep;
          if (steps != 0) {
            _wheelAccum[idx] -= steps * kStep;
            _changeFieldValue(ctrl, max, steps);
          }
        }
      },
      child: SizedBox(
        height: _kFieldHeight,
        child: Stack(
          children: [
            TextField(
              controller: ctrl,
              focusNode: focusNode,
              style: TextStyle(fontSize: 13, color: textFg),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.only(left: 16, top: 3, right: 6, bottom: 2),
                suffixText: suffix,
                suffixStyle: TextStyle(fontSize: 13, color: labelFg),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(
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
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: labelFg)),
                ),
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
                focusedBorder: OutlineInputBorder(
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

// ─── 2D picker square (RGBA: sat×bri @ hue · HSL: hue×sat @ lightness) ───────

class _GradientSquare extends StatefulWidget {
  final double pickerSize;
  final ColorEditorMode mode;
  final double hue;
  final double saturation;
  final double brightness; // HSV value (RGBA) or HSL lightness (HSL)
  // Reports the normalized pointer position (x, y), each 0..1. The owner maps
  // it to colour components according to [mode].
  final void Function(double x01, double y01) onChanged;

  const _GradientSquare({
    required this.pickerSize,
    required this.mode,
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.onChanged,
  });

  @override
  State<_GradientSquare> createState() => _GradientSquareState();
}

class _GradientSquareState extends State<_GradientSquare> {
  final ValueNotifier<Offset?> _cursorNotifier = ValueNotifier(null);

  void _handle(Offset local) {
    final x = (local.dx / widget.pickerSize).clamp(0.0, 1.0);
    final y = (local.dy / widget.pickerSize).clamp(0.0, 1.0);
    widget.onChanged(x, y);
  }

  @override
  void dispose() {
    _cursorNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHsl = widget.mode == ColorEditorMode.hsl;
    // Normalized crosshair position and the colour shown beneath it.
    final crossX01 = isHsl ? (widget.hue / 360) : widget.saturation;
    final crossY01 =
        isHsl ? (1.0 - widget.saturation) : (1.0 - widget.brightness);
    final markColor = isHsl
        ? HSLColor.fromAHSL(1, widget.hue, widget.saturation, widget.brightness)
            .toColor()
        : HSVColor.fromAHSV(1, widget.hue, widget.saturation, widget.brightness)
            .toColor();
    final CustomPainter bgPainter = isHsl
        ? _HSLGradientPainter(lightness: widget.brightness)
        : _HSBGradientPainter(hue: widget.hue);
    return MouseRegion(
      cursor: SystemMouseCursors.none,
      onHover: (e) => _cursorNotifier.value = e.localPosition,
      onExit: (_) => _cursorNotifier.value = null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _cursorNotifier.value = e.localPosition;
          _handle(e.localPosition);
        },
        onPointerMove: (e) {
          _cursorNotifier.value = e.localPosition;
          _handle(e.localPosition);
        },
        child: SizedBox(
          width: widget.pickerSize,
          height: widget.pickerSize,
          child: CustomPaint(
            painter: bgPainter,
            foregroundPainter: _CrosshairAndCursorPainter(
              crossX: crossX01 * widget.pickerSize,
              crossY: crossY01 * widget.pickerSize,
              markColor: markColor,
              cursorNotifier: _cursorNotifier,
            ),
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

class _CrosshairAndCursorPainter extends CustomPainter {
  final double crossX, crossY;
  final Color markColor;
  final ValueNotifier<Offset?> cursorNotifier;
  _CrosshairAndCursorPainter({
    required this.crossX,
    required this.crossY,
    required this.markColor,
    required this.cursorNotifier,
  }) : super(repaint: cursorNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    final pos = Offset(crossX, crossY);
    final lum = 0.2989 * markColor.red / 255 +
        0.5870 * markColor.green / 255 +
        0.1140 * markColor.blue / 255;
    final fg =
        lum > 0.6 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    canvas.drawCircle(
        pos,
        _kCrosshairRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kCrosshairStroke
          ..color = fg);

    final cursorPos = cursorNotifier.value;
    if (cursorPos != null) {
      const diameter = 16.0;
      const lineW = 1.0;
      canvas.drawCircle(
          cursorPos,
          diameter / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * lineW
            ..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(
          cursorPos,
          diameter / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = lineW
            ..color = const Color(0xFF000000));
    }
  }

  @override
  bool shouldRepaint(_CrosshairAndCursorPainter old) =>
      old.crossX != crossX ||
      old.crossY != crossY ||
      old.markColor != markColor;
}

// ─── 2D HSL gradient square (hue × saturation, at fixed lightness) ───────────
//
// Mirrors AyuGram `Picker::preparePaletteHSL`: x = hue (0→360 left→right),
// y = saturation (full at top → 0 at bottom), all at the current lightness.
class _HSLGradientPainter extends CustomPainter {
  final double lightness; // 0..1
  _HSLGradientPainter({required this.lightness});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Horizontal full-saturation rainbow at the current lightness.
    final hueStops = <Color>[
      for (var i = 0; i <= 12; i++)
        HSLColor.fromAHSL(1, (i * 30).toDouble(), 1, lightness).toColor(),
    ];
    final hueShader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: hueStops,
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = hueShader);

    // Desaturate downward toward the neutral gray at this lightness. Blending
    // gray with alpha = (1 - saturation) yields exactly HSL(hue, sat, L).
    final gray = HSLColor.fromAHSL(1, 0, 0, lightness).toColor();
    final satShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [gray.withAlpha(0), gray],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = satShader);
  }

  @override
  bool shouldRepaint(_HSLGradientPainter old) => old.lightness != lightness;
}

class _CheckerboardPainter extends CustomPainter {
  static const _checkSize = 4.0;
  static final _light = Paint()..color = Colors.white;
  static final _dark = Paint()..color = const Color(0xFFCCCCCC);

  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0.0; y < size.height; y += _checkSize) {
      for (var x = 0.0; x < size.width; x += _checkSize) {
        final odd = ((x ~/ _checkSize) + (y ~/ _checkSize)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, _checkSize, _checkSize),
          odd ? _dark : _light,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Vertical hue slider ────────────────────────────────────────────────────

class _VerticalHueSlider extends StatelessWidget {
  final double pickerSize;
  final double value;
  final Color arrowColor;
  final ValueChanged<double> onChanged;
  const _VerticalHueSlider({
    required this.pickerSize,
    required this.value,
    required this.arrowColor,
    required this.onChanged,
  });

  void _handle(Offset local) {
    onChanged((local.dy / pickerSize).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handle(e.localPosition),
      onPointerMove: (e) => _handle(e.localPosition),
      child: SizedBox(
        width: _kSliderTotalWidth,
        height: pickerSize,
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
    final rrect = RRect.fromRectAndRadius(barRect, const Radius.circular(4));

    final shadowPaint = Paint()
      ..color = const Color(0x2B000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(rrect, shadowPaint);

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: List.generate(
          7, (i) => HSVColor.fromAHSV(1, (6 - i) * 60.0, 1, 1).toColor()),
    );
    canvas.drawRRect(rrect, Paint()..shader = gradient.createShader(barRect));

    final markY = value * size.height;
    _drawArrow(canvas, 0, markY, _kSliderSkip, true, arrowColor);
    _drawArrow(canvas, size.width, markY, _kSliderSkip, false, arrowColor);
  }

  static void _drawArrow(Canvas canvas, double baseX, double tipY, double depth, bool pointsRight, Color color) {
    final dir = pointsRight ? 1.0 : -1.0;
    final path = Path()
      ..moveTo(baseX, tipY - _kArrowHalf)
      ..quadraticBezierTo(baseX + dir * depth * 0.5, tipY - _kArrowHalf * 0.3, baseX + dir * depth, tipY)
      ..quadraticBezierTo(baseX + dir * depth * 0.5, tipY + _kArrowHalf * 0.3, baseX, tipY + _kArrowHalf)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HueSliderPainter old) =>
      old.value != value || old.arrowColor != arrowColor;
}

// ─── Horizontal opacity slider ──────────────────────────────────────────────

class _HorizontalOpacitySlider extends StatelessWidget {
  final double pickerSize;
  final double hue, saturation, brightness;
  final double value;
  final Color arrowColor;
  final ValueChanged<double> onChanged;
  const _HorizontalOpacitySlider({
    required this.pickerSize,
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.value,
    required this.arrowColor,
    required this.onChanged,
  });

  void _handle(Offset local) {
    onChanged((local.dx / pickerSize).clamp(0.0, 1.0));
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
        width: pickerSize,
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

  static final Map<Size, ui.Picture> _checkerCacheMap = {};

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

    final shadowPaint = Paint()
      ..color = const Color(0x2B000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(rrect, shadowPaint);

    canvas.save();
    canvas.clipRRect(rrect);

    final cached = _checkerCacheMap[size];
    if (cached != null) {
      canvas.drawPicture(cached);
    } else {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      const checkSize = 4.0;
      final cp1 = Paint()..color = const Color(0xFFCCCCCC);
      final cp2 = Paint()..color = Colors.white;
      for (var y = _kSliderSkip; y < _kSliderSkip + _kSliderWidth;
          y += checkSize) {
        for (var x = 0.0; x < size.width; x += checkSize) {
          final odd =
              (x ~/ checkSize + (y - _kSliderSkip) ~/ checkSize) % 2 == 0;
          c.drawRect(Rect.fromLTWH(x, y, checkSize, checkSize),
              odd ? cp1 : cp2);
        }
      }
      final pic = rec.endRecording();
      _checkerCacheMap[size] = pic;
      canvas.drawPicture(pic);
    }

    final gradient = LinearGradient(
      colors: [color.withAlpha(0), color],
    );
    canvas.drawRRect(rrect, Paint()..shader = gradient.createShader(barRect));
    canvas.restore();

    final markX = value * size.width;
    _drawArrow(canvas, markX, 0, _kSliderSkip, true, arrowColor);
    _drawArrow(canvas, markX, size.height, _kSliderSkip, false, arrowColor);
  }

  static void _drawArrow(Canvas canvas, double tipX, double baseY, double depth, bool pointsDown, Color color) {
    final dir = pointsDown ? 1.0 : -1.0;
    final path = Path()
      ..moveTo(tipX - _kArrowHalf, baseY)
      ..quadraticBezierTo(tipX - _kArrowHalf * 0.3, baseY + dir * depth * 0.5, tipX, baseY + dir * depth)
      ..quadraticBezierTo(tipX + _kArrowHalf * 0.3, baseY + dir * depth * 0.5, tipX + _kArrowHalf, baseY)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HorizontalOpacityPainter old) =>
      old.color != color || old.value != value || old.arrowColor != arrowColor;
}

// ─── Horizontal lightness slider (HSL mode) ─────────────────────────────────
//
// Mirrors AyuGram `Slider` with `Type::Lightness`: a horizontal ramp from
// `lightnessMin` to `lightnessMax` at the current hue/saturation. Its range IS
// the limit window, so the produced lightness can never escape [min..max].
class _HorizontalLightnessSlider extends StatelessWidget {
  final double pickerSize;
  final double hue, saturation;
  final double lightnessMin, lightnessMax;
  final double value; // 0..1 within [min..max]
  final Color arrowColor;
  final ValueChanged<double> onChanged;
  const _HorizontalLightnessSlider({
    required this.pickerSize,
    required this.hue,
    required this.saturation,
    required this.lightnessMin,
    required this.lightnessMax,
    required this.value,
    required this.arrowColor,
    required this.onChanged,
  });

  void _handle(Offset local) {
    onChanged((local.dx / pickerSize).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handle(e.localPosition),
      onPointerMove: (e) => _handle(e.localPosition),
      child: SizedBox(
        width: pickerSize,
        height: _kSliderTotalWidth,
        child: CustomPaint(
          painter: _HorizontalLightnessPainter(
            hue: hue,
            saturation: saturation,
            lightnessMin: lightnessMin,
            lightnessMax: lightnessMax,
            value: value,
            arrowColor: arrowColor,
          ),
        ),
      ),
    );
  }
}

class _HorizontalLightnessPainter extends CustomPainter {
  final double hue, saturation;
  final double lightnessMin, lightnessMax;
  final double value;
  final Color arrowColor;

  _HorizontalLightnessPainter({
    required this.hue,
    required this.saturation,
    required this.lightnessMin,
    required this.lightnessMax,
    required this.value,
    required this.arrowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barRect = Rect.fromLTWH(0, _kSliderSkip, size.width, _kSliderWidth);
    final rrect = RRect.fromRectAndRadius(barRect, const Radius.circular(4));

    final shadowPaint = Paint()
      ..color = const Color(0x2B000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(rrect, shadowPaint);

    const steps = 12;
    final stops = <Color>[
      for (var i = 0; i <= steps; i++)
        HSLColor.fromAHSL(
          1,
          hue,
          saturation,
          lightnessMin + (i / steps) * (lightnessMax - lightnessMin),
        ).toColor(),
    ];
    final gradient = LinearGradient(colors: stops);
    canvas.drawRRect(rrect, Paint()..shader = gradient.createShader(barRect));

    final markX = value * size.width;
    _drawArrow(canvas, markX, 0, _kSliderSkip, true, arrowColor);
    _drawArrow(canvas, markX, size.height, _kSliderSkip, false, arrowColor);
  }

  static void _drawArrow(Canvas canvas, double tipX, double baseY, double depth,
      bool pointsDown, Color color) {
    final dir = pointsDown ? 1.0 : -1.0;
    final path = Path()
      ..moveTo(tipX - _kArrowHalf, baseY)
      ..quadraticBezierTo(tipX - _kArrowHalf * 0.3, baseY + dir * depth * 0.5,
          tipX, baseY + dir * depth)
      ..quadraticBezierTo(tipX + _kArrowHalf * 0.3, baseY + dir * depth * 0.5,
          tipX + _kArrowHalf, baseY)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HorizontalLightnessPainter old) =>
      old.hue != hue ||
      old.saturation != saturation ||
      old.lightnessMin != lightnessMin ||
      old.lightnessMax != lightnessMax ||
      old.value != value ||
      old.arrowColor != arrowColor;
}
