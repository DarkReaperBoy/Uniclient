import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class StatisticalValue {
  final double value;
  final double previousValue;
  final double growthRatePercentage;

  const StatisticalValue({
    required this.value,
    required this.previousValue,
    required this.growthRatePercentage,
  });

  factory StatisticalValue.fromMap(Map<String, dynamic> map) {
    return StatisticalValue(
      value: (map['current'] as num?)?.toDouble() ?? 0,
      previousValue: (map['previous'] as num?)?.toDouble() ?? 0,
      growthRatePercentage: (map['growth'] as num?)?.toDouble() ?? 0,
    );
  }

  double get delta => value - previousValue;
  bool get isPositive => delta >= 0;
  bool get isZero => value == 0 && previousValue == 0;
}

class StatisticalGraph {
  final StatsChartData? chart;
  final String? zoomToken;

  const StatisticalGraph({this.chart, this.zoomToken});

  bool get isPreLoaded => chart != null;
  bool get isDeferred => zoomToken != null && chart == null;

  factory StatisticalGraph.fromMap(Map<String, dynamic> map, {String? parentChartType}) {
    final chart = StatsChartData.fromMap(map, parentChartType: parentChartType);
    final token = map['zoom_token'] as String?;
    return StatisticalGraph(chart: chart, zoomToken: token);
  }
}

class StatsChartData {
  final String title;
  final String chartType;
  final List<int> timestamps;
  final List<ChartLine> lines;
  final List<double> xPercentage;
  final String? zoomToken;
  final int? defaultZoomXIndex;
  final bool weekFormat;
  final bool hasPercentages;
  final bool isFooterHidden;
  final double? dayStringMaxWidth;
  final double? currencyRate;
  final String? currency;

  StatsChartData({
    required this.title,
    required this.chartType,
    required this.timestamps,
    required this.lines,
    List<double>? xPercentage,
    this.zoomToken,
    this.defaultZoomXIndex,
    this.weekFormat = false,
    this.hasPercentages = false,
    this.isFooterHidden = false,
    this.dayStringMaxWidth,
    this.currencyRate,
    this.currency,
  }) : xPercentage = xPercentage ?? _computeXPercentage(timestamps);

  static List<double> _computeXPercentage(List<int> timestamps) {
    if (timestamps.length < 2) return timestamps.map((_) => 0.0).toList();
    final first = timestamps.first.toDouble();
    final last = timestamps.last.toDouble();
    final range = last - first;
    if (range == 0) return timestamps.map((_) => 0.0).toList();
    return timestamps.map((t) => (t - first) / range).toList();
  }

  static StatsChartData? fromMap(Map<String, dynamic> map, {String? parentChartType}) {
    final title = map['title'] as String? ?? '';
    final rawType = map['type'] as String? ?? '';
    final chartType = rawType.isNotEmpty ? rawType : (parentChartType ?? 'Linear');
    final dataStr = map['data'] as String?;
    if (dataStr == null || dataStr.isEmpty) return null;

    try {
      final parsed = json.decode(dataStr) as Map<String, dynamic>;
      final columns = parsed['columns'] as List<dynamic>? ?? [];
      final types = (parsed['types'] as Map<String, dynamic>?) ?? {};
      final names = (parsed['names'] as Map<String, dynamic>?) ?? {};
      final colors = (parsed['colors'] as Map<String, dynamic>?) ?? {};
      final hiddenSet = (parsed['hidden'] as List<dynamic>?)
              ?.cast<String>()
              .toSet() ??
          <String>{};

      List<int> timestamps = [];
      List<ChartLine> lines = [];

      for (final col in columns) {
        final list = col as List<dynamic>;
        if (list.isEmpty) continue;
        final id = list[0] as String;
        if (types[id] == 'x') {
          timestamps = list.skip(1).map((v) => (v as num).toInt()).toList();
        } else {
          final values =
              list.skip(1).map((v) => (v as num).toDouble()).toList();
          final colorStr = colors[id] as String? ?? '#3DC23F';
          final colorKeyMatch = RegExp(r'(.*)(#.*)').firstMatch(colorStr);
          final colorKey = colorKeyMatch?.group(1) ?? '';
          final colorHex = colorKeyMatch?.group(2) ?? colorStr;
          final lineName = (names[id] as String? ?? id).replaceAll('-', '—');
          lines.add(ChartLine(
            id: id,
            name: lineName,
            color: _parseColor(colorHex),
            colorKey: colorKey,
            values: values,
            isHiddenOnStart: hiddenSet.contains(id),
          ));
        }
      }

      if (timestamps.isEmpty || lines.isEmpty) return null;

      final percentage = parsed['percentage'] as bool? ?? false;
      final dayStrWidth = (parsed['dayStringMaxWidth'] as num?)?.toDouble();

      final subchart = (parsed['subchart'] as Map<String, dynamic>?) ?? {};
      final subchartShow = subchart['show'];
      final footerHidden = subchartShow is bool ? !subchartShow : false;

      int? defaultZoom;
      final defaultZoomArr = subchart['defaultZoom'];
      if (defaultZoomArr is List && defaultZoomArr.isNotEmpty) {
        final minTs = (defaultZoomArr.first as num).toDouble();
        for (int i = 0; i < timestamps.length; i++) {
          if (timestamps[i].toDouble() == minTs) {
            defaultZoom = i;
            break;
          }
        }
      }

      final tooltipFormatter = parsed['xTooltipFormatter'] as String?;
      final weekFmt = tooltipFormatter != null && tooltipFormatter.contains("'week'");

      return StatsChartData(
        title: title,
        chartType: chartType,
        timestamps: timestamps,
        lines: lines,
        zoomToken: map['zoom_token'] as String?,
        defaultZoomXIndex: defaultZoom,
        weekFormat: weekFmt,
        hasPercentages: percentage,
        isFooterHidden: footerHidden,
        dayStringMaxWidth: dayStrWidth,
        currencyRate: (parsed['rate'] as num?)?.toDouble(),
        currency: parsed['currency'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static Color _parseColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

class ChartLine {
  final String id;
  final String name;
  final Color color;
  final String colorKey;
  final List<double> values;
  final bool isHiddenOnStart;

  ChartLine({
    required this.id,
    required this.name,
    required this.color,
    this.colorKey = '',
    required this.values,
    this.isHiddenOnStart = false,
  });
}

const _kThemeLineColors = <String, Color>{
  'BLUE': Color(0xFF327FE5),
  'GREEN': Color(0xFF61C752),
  'RED': Color(0xFFE05356),
  'GOLDEN': Color(0xFFEBA52D),
  'LIGHTBLUE': Color(0xFF58A8ED),
  'LIGHTGREEN': Color(0xFF8FCF39),
  'ORANGE': Color(0xFFF28C39),
  'INDIGO': Color(0xFF7F79F3),
  'PURPLE': Color(0xFF9F79E8),
  'CYAN': Color(0xFF40D0CA),
};

Color _resolveLineColor(ChartLine line) {
  if (line.colorKey.isNotEmpty) {
    final themed = _kThemeLineColors[line.colorKey];
    if (themed != null) return themed;
  }
  return line.color;
}

const _kHeaderHeight = 36.0;
const _kChartHeight = 200.0;
const _kFooterHeight = 42.0;
const _kHandleWidth = 10.0;
const _kHandleRadius = 6.0;
const _kHandleSepPx = 5.0;
const _kLineWidth = 2.0;
const _kDotRadius = 5.0;
const _kBottomCaptionHeight = 15.0;
const _kBottomCaptionSkip = 6.0;
const _kTooltipRadius = 8.0;
const _kTooltipPadH = 18.0;
const _kTooltipPadTop = 14.0;
const _kTooltipPadBottom = 17.0;
const _kXExpandDuration = 200;
const _kDtHeightSpeed1 = 0.06;
const _kDtHeightSpeed2 = 0.06;
const _kDtHeightSpeed3 = 0.09;
const _kFilterSpeedDivisor = 1.2;
const _kInstantSnapRatio = 0.97;
const _kDtHeightSpeedThreshold1 = 0.7;
const _kDtHeightSpeedThreshold2 = 0.1;
const _kFastAlphaSpeed = 0.85;

double _sineInOut(double t) => 0.5 - 0.5 * math.cos(math.pi * t);
const _kDateLabelFrameSpeed = 1.0 / 12.0;

class StatsChartWidget extends StatefulWidget {
  final StatsChartData data;
  final ThemeData theme;
  final void Function(int index)? onZoom;
  final Future<StatsChartData?> Function(String token, int timestamp)? onLoadZoomData;
  final bool hideHeader;

  const StatsChartWidget({
    super.key,
    required this.data,
    required this.theme,
    this.onZoom,
    this.onLoadZoomData,
    this.hideHeader = false,
  });

  @override
  State<StatsChartWidget> createState() => _StatsChartWidgetState();
}

enum _DragMode { none, leftHandle, rightHandle, panCenter }

class _StatsChartWidgetState extends State<StatsChartWidget>
    with TickerProviderStateMixin {
  double _rangeStart = 0.0;
  double _rangeEnd = 1.0;
  int? _selectedIndex;
  late Map<String, bool> _lineVisible;
  late Map<String, AnimationController> _lineAlphaControllers;

  _DragMode _dragMode = _DragMode.none;
  double _dragStartX = 0;
  double _rangeStartAtDrag = 0;
  double _rangeEndAtDrag = 0;

  late AnimationController _animController;
  double _animFromStart = 0, _animToStart = 0;
  double _animFromEnd = 0, _animToEnd = 0;

  late Ticker _chartTicker;
  Duration _prevTickDuration = Duration.zero;
  double _smoothFPS = 60.0;

  double _prevRulerMn = 0, _prevRulerMx = 1;
  double _curRulerMn = 0, _curRulerMx = 1;
  double _yProgress = 1.0;
  double _ySpeed = _kDtHeightSpeed1;
  bool _yFromFilter = false;
  double _rulerCrossfade = 1.0;

  double _footerPrevMax = 0, _footerCurMax = 0;
  double _footerYProgress = 1.0;
  bool _footerInitialized = false;

  double _dateLabelAlpha = 1.0;
  double _dateLabelProgress = 1.0;
  int _prevDateStep = 1;
  int _curDateStep = 1;

  late AnimationController _pieAnimController;
  int? _pieDataIndex;
  int _pieHoverSlice = -1;
  Map<int, double> _pieSliceHoverProgress = {};
  final Map<String, TextPainter> _textPainterCache = {};

  late AnimationController _shakeController;

  double _chartWidth = 400.0;

  int? _tooltipCachedIdx;
  bool _tooltipCachedHasCurrency = false;
  double _tooltipMaxNameW = 0, _tooltipMaxValW = 0, _tooltipMaxPctW = 0;

  StatsChartData? _serverZoomedData;
  bool _serverZoomLoading = false;
  late AnimationController _serverZoomAnim;

  @override
  void initState() {
    super.initState();
    _lineVisible = {
      for (final l in widget.data.lines) l.id: !l.isHiddenOnStart
    };
    _lineAlphaControllers = {
      for (final l in widget.data.lines)
        l.id: AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
          value: l.isHiddenOnStart ? 0.0 : 1.0,
        )..addListener(() => setState(() {}))
    };
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kXExpandDuration),
    )..addListener(() {
        final t = _sineInOut(_animController.value);
        setState(() {
          _rangeStart = _animFromStart + (_animToStart - _animFromStart) * t;
          _rangeEnd = _animFromEnd + (_animToEnd - _animFromEnd) * t;
        });
        _updateRulerRange();
        _updateFooterYRange();
        _updateDateStep();
      });
    _chartTicker = createTicker(_onChartTick);
    _pieAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() => setState(() {}));
    _serverZoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() => setState(() {}));
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() => setState(() {}));
    _updateRulerRange();
    _updateFooterYRange();
  }

  @override
  void didUpdateWidget(StatsChartWidget old) {
    super.didUpdateWidget(old);
    if (widget.data != old.data || widget.theme.brightness != old.theme.brightness) {
      for (final tp in _textPainterCache.values) tp.dispose();
      _textPainterCache.clear();
    }
    if (widget.data.lines.length != old.data.lines.length) {
      for (final key in _lineAlphaControllers.keys.toList()) {
        if (!widget.data.lines.any((l) => l.id == key)) {
          _lineAlphaControllers[key]!.dispose();
          _lineAlphaControllers.remove(key);
        }
      }
      for (final l in widget.data.lines) {
        if (!_lineAlphaControllers.containsKey(l.id)) {
          _lineAlphaControllers[l.id] = AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 200),
            value: l.isHiddenOnStart ? 0.0 : 1.0,
          )..addListener(() => setState(() {}));
        }
      }
      _lineVisible = {
        for (final l in widget.data.lines)
          l.id: _lineVisible[l.id] ?? !l.isHiddenOnStart
      };
    }
  }

  Map<String, double> get _lineAlphas => {
        for (final e in _lineAlphaControllers.entries) e.key: e.value.value
      };

  bool get _isPieActive =>
      _pieDataIndex != null && widget.data.chartType == 'StackLinear';

  bool get _isServerZoomed => _serverZoomedData != null;

  void _enterPieMode(int dataIndex) {
    setState(() {
      _pieDataIndex = dataIndex;
      _pieHoverSlice = -1;
    });
    _pieAnimController.forward(from: 0);
  }

  void _exitPieMode() {
    _pieSliceHoverProgress.clear();
    _pieAnimController.reverse().then((_) {
      if (mounted) setState(() => _pieDataIndex = null);
    });
  }

  void _requestServerZoom(int index) async {
    final token = widget.data.zoomToken;
    if (token == null || token.isEmpty) return;
    if (widget.onLoadZoomData == null) {
      widget.onZoom?.call(index);
      return;
    }

    final ts = widget.data.timestamps[index];
    final timestamp = ts.abs() > 1e12 ? ts ~/ 1000 : ts;

    setState(() => _serverZoomLoading = true);
    try {
      final data = await widget.onLoadZoomData!(token, timestamp);
      if (!mounted) return;
      if (data == null) {
        setState(() => _serverZoomLoading = false);
        return;
      }
      setState(() {
        _serverZoomedData = data;
        _serverZoomLoading = false;
        _selectedIndex = null;
      });
      _serverZoomAnim.forward(from: 0);
    } catch (_) {
      if (mounted) setState(() => _serverZoomLoading = false);
    }
  }

  void _exitServerZoom() {
    _serverZoomAnim.reverse().then((_) {
      if (mounted) setState(() => _serverZoomedData = null);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _chartTicker.dispose();
    _pieAnimController.dispose();
    _serverZoomAnim.dispose();
    _shakeController.dispose();
    for (final c in _lineAlphaControllers.values) {
      c.dispose();
    }
    for (final tp in _textPainterCache.values) {
      tp.dispose();
    }
    super.dispose();
  }

  (double, double) _computeYRange() {
    final d = widget.data;
    final n = d.timestamps.length;
    if (n == 0) return (0, 1);
    final lines =
        d.lines.where((l) => _lineVisible[l.id] ?? true).toList();
    if (lines.isEmpty) return (0, 1);
    final si = (_rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final ei = (_rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    switch (d.chartType) {
      case 'Bar':
        double mx = 0;
        for (final l in lines) {
          for (int i = si; i <= ei && i < l.values.length; i++) {
            if (l.values[i] > mx) mx = l.values[i];
          }
        }
        return (0, mx == 0 ? 1 : mx);
      case 'StackBar':
        double mx = 0;
        for (int i = si; i <= ei; i++) {
          double s = 0;
          for (final l in lines) {
            if (i < l.values.length) s += l.values[i];
          }
          if (s > mx) mx = s;
        }
        return (0, mx == 0 ? 1 : mx);
      case 'StackLinear':
        return (0, 1);
      default:
        double mn = double.infinity, mx = double.negativeInfinity;
        for (final l in lines) {
          for (int i = si; i <= ei && i < l.values.length; i++) {
            if (l.values[i] < mn) mn = l.values[i];
            if (l.values[i] > mx) mx = l.values[i];
          }
        }
        if (mn == double.infinity) return (0, 1);
        if (mx == mn) return (mn, mn + 1);
        return (mn, mx);
    }
  }

  void _updateRulerRange({bool fromFilter = false}) {
    final (mn, mx) = _computeYRange();
    final range = (_curRulerMx - _curRulerMn).abs();
    final threshold = range > 0 ? range * 0.05 : 0.001;
    if ((mn - _curRulerMn).abs() > threshold ||
        (mx - _curRulerMx).abs() > threshold) {
      final maxExtent = math.max(range, (mx - mn).abs());
      final changeAmount =
          math.max((mn - _curRulerMn).abs(), (mx - _curRulerMx).abs());
      final ratio = maxExtent > 0 ? changeAmount / maxExtent : 0.0;

      if (ratio > _kInstantSnapRatio) {
        _prevRulerMn = mn;
        _prevRulerMx = mx;
        _curRulerMn = mn;
        _curRulerMx = mx;
        _rulerCrossfade = 1.0;
        _yProgress = 1.0;
        return;
      }

      if (_yFromFilter) {
        _ySpeed = _kDtHeightSpeed1 / _kFilterSpeedDivisor;
      } else if (ratio > _kDtHeightSpeedThreshold1) {
        _ySpeed = _kDtHeightSpeed1;
      } else if (ratio < _kDtHeightSpeedThreshold2) {
        _ySpeed = _kDtHeightSpeed2;
      } else {
        _ySpeed = _kDtHeightSpeed3;
      }

      if (_yProgress >= 1.0) {
        _prevRulerMn = _curRulerMn;
        _prevRulerMx = _curRulerMx;
      }
      _curRulerMn = mn;
      _curRulerMx = mx;
      _yProgress = 0.0;
      _rulerCrossfade = 0.0;
      _yFromFilter = fromFilter;
      _ensureTickerRunning();
    } else {
      _curRulerMn = mn;
      _curRulerMx = mx;
      if (_yProgress >= 1.0) _rulerCrossfade = 1.0;
    }
  }

  void _updateFooterYRange() {
    final d = widget.data;
    final lines =
        d.lines.where((l) => _lineVisible[l.id] ?? true).toList();
    if (lines.isEmpty) return;

    double newMax = 0;
    switch (d.chartType) {
      case 'Bar':
        for (final l in lines) {
          for (final v in l.values) {
            if (v > newMax) newMax = v;
          }
        }
      case 'StackBar':
        for (int i = 0; i < d.timestamps.length; i++) {
          double s = 0;
          for (final l in lines) {
            if (i < l.values.length) s += l.values[i];
          }
          if (s > newMax) newMax = s;
        }
      default:
        return;
    }
    if (newMax == 0) newMax = 1;

    if (!_footerInitialized) {
      _footerPrevMax = newMax;
      _footerCurMax = newMax;
      _footerYProgress = 1.0;
      _footerInitialized = true;
      return;
    }

    if ((newMax - _footerCurMax).abs() > 0.001) {
      _footerPrevMax = _footerCurMax;
      _footerCurMax = newMax;
      _footerYProgress = 0.0;
      _ensureTickerRunning();
    }
  }

  void _ensureTickerRunning() {
    if (!_chartTicker.isActive) {
      _prevTickDuration = Duration.zero;
      _chartTicker.start();
    }
  }

  int _computeDateStep() {
    final n = widget.data.timestamps.length;
    if (n < 2) return 1;
    final span = _rangeEnd - _rangeStart;
    if (span <= 0) return 1;
    final pxPerPoint = _chartWidth / (span * (n - 1));
    final minSpacing = 70.0;
    int step = 1;
    while (step * pxPerPoint < minSpacing && step < n) {
      step *= 2;
    }
    return step;
  }

  void _updateDateStep() {
    final newStep = _computeDateStep();
    if (newStep != _curDateStep) {
      _prevDateStep = _curDateStep;
      _curDateStep = newStep;
      _dateLabelProgress = 0.0;
      _dateLabelAlpha = 0.0;
      _ensureTickerRunning();
    }
  }

  void _onChartTick(Duration elapsed) {
    if (_prevTickDuration == Duration.zero) {
      _prevTickDuration = elapsed;
      return;
    }

    final dtSec =
        (elapsed - _prevTickDuration).inMicroseconds / 1000000.0;
    _prevTickDuration = elapsed;

    if (dtSec > 0) {
      _smoothFPS = _smoothFPS * 0.8 + (1.0 / dtSec) * 0.2;
    }
    double fpsM = 60.0 / _smoothFPS;
    if (_smoothFPS < 30) fpsM *= 2.0;

    bool dirty = false;

    if (_yProgress < 1.0) {
      final speed = _ySpeed * fpsM;
      _yProgress = (_yProgress + speed).clamp(0.0, 1.0);
      if (_yProgress > _kInstantSnapRatio) _yProgress = 1.0;
      _rulerCrossfade = Curves.easeInCubic.transform(_yProgress);
      dirty = true;
    }

    if (_footerYProgress < 1.0) {
      final speed = _kDtHeightSpeed3 * fpsM;
      _footerYProgress = (_footerYProgress + speed).clamp(0.0, 1.0);
      if (_footerYProgress > _kInstantSnapRatio) _footerYProgress = 1.0;
      dirty = true;
    }

    if (_dateLabelProgress < 1.0) {
      final speed = _kDateLabelFrameSpeed * fpsM;
      _dateLabelProgress = (_dateLabelProgress + speed).clamp(0.0, 1.0);
      _dateLabelAlpha = Curves.easeInCubic.transform(_dateLabelProgress);
      dirty = true;
    }

    if (_pieSliceHoverProgress.isNotEmpty || _pieHoverSlice >= 0) {
      const hoverSpeed = 1.0 / 18.0;
      final spd = hoverSpeed * fpsM;
      if (_pieHoverSlice >= 0 &&
          !_pieSliceHoverProgress.containsKey(_pieHoverSlice)) {
        _pieSliceHoverProgress[_pieHoverSlice] = 0.0;
      }
      for (final key in _pieSliceHoverProgress.keys.toList()) {
        if (key == _pieHoverSlice) {
          _pieSliceHoverProgress[key] =
              (_pieSliceHoverProgress[key]! + spd).clamp(0.0, 1.0);
        } else {
          final v = (_pieSliceHoverProgress[key]! - spd).clamp(0.0, 1.0);
          if (v <= 0) {
            _pieSliceHoverProgress.remove(key);
          } else {
            _pieSliceHoverProgress[key] = v;
          }
        }
      }
      if (_pieSliceHoverProgress.values.any((v) => v > 0 && v < 1)) {
        dirty = true;
      }
    }

    if (dirty) {
      setState(() {});
    }

    final pieHoverDone = _pieSliceHoverProgress.isEmpty ||
        _pieSliceHoverProgress.values.every((v) => v >= 1.0 || v <= 0.0);
    if (_yProgress >= 1.0 &&
        _footerYProgress >= 1.0 &&
        _dateLabelProgress >= 1.0 &&
        pieHoverDone) {
      _chartTicker.stop();
      _prevTickDuration = Duration.zero;
    }
  }

  double get _animatedYMn =>
      _prevRulerMn +
      (_curRulerMn - _prevRulerMn) *
          Curves.easeInCubic.transform(_yProgress);
  double get _animatedYMx =>
      _prevRulerMx +
      (_curRulerMx - _prevRulerMx) *
          Curves.easeInCubic.transform(_yProgress);
  double get _footerAnimatedMax =>
      _footerPrevMax +
      (_footerCurMax - _footerPrevMax) *
          Curves.easeInCubic.transform(_footerYProgress);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  DateTime _toDate(int ts) =>
      DateTime.fromMillisecondsSinceEpoch(ts.abs() > 1e12 ? ts : ts * 1000);

  String _visibleDateRange() {
    final n = widget.data.timestamps.length;
    if (n < 2) return '';
    final si = (_rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final ei = (_rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    final ds = _toDate(widget.data.timestamps[si]);
    final de = _toDate(widget.data.timestamps[ei]);
    return '${ds.day} ${_months[ds.month - 1]} ${ds.year}'
        ' – '
        '${de.day} ${_months[de.month - 1]} ${de.year}';
  }

  String _zoomedDateRange() {
    if (_serverZoomedData == null) return '';
    final zd = _serverZoomedData!;
    if (zd.timestamps.isEmpty) return '';
    final ds = _toDate(zd.timestamps.first);
    final de = _toDate(zd.timestamps.last);
    return '${ds.day} ${_months[ds.month - 1]} ${ds.year}'
        ' – '
        '${de.day} ${_months[de.month - 1]} ${de.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.white60 : Colors.black54;

    final pieT = _isPieActive
        ? Curves.easeOutCirc.transform(_pieAnimController.value)
        : (_pieDataIndex != null ? Curves.easeOutCirc.transform(_pieAnimController.value) : 0.0);

    final serverZoomT = (_isServerZoomed || _serverZoomAnim.isAnimating)
        ? Curves.easeOutCirc.transform(_serverZoomAnim.value)
        : 0.0;

    final showZoomOut = _isPieActive || _isServerZoomed;

    String subtitleText = _visibleDateRange();
    if (_isServerZoomed) {
      subtitleText = _zoomedDateRange();
    } else if (_isPieActive && _pieDataIndex != null) {
      final dt = _toDate(widget.data.timestamps[_pieDataIndex!]);
      if (widget.data.weekFormat) {
        final dtEnd = dt.add(const Duration(days: 6));
        subtitleText =
            '${dt.day} ${_months[dt.month - 1]} ${dt.year} – ${dtEnd.day} ${_months[dtEnd.month - 1]} ${dtEnd.year}';
      } else {
        subtitleText = '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.hideHeader)
          SizedBox(
            height: _kHeaderHeight,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.data.title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitleText,
                        style: TextStyle(fontSize: 11, color: subtitleColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_serverZoomLoading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (showZoomOut)
                  GestureDetector(
                    onTap: _isServerZoomed ? _exitServerZoom : _exitPieMode,
                    child: Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: widget.theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Zoom Out',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (serverZoomT < 1.0) ...[
          Opacity(
            opacity: _isServerZoomed ? 1.0 - serverZoomT : 1.0,
            child: _buildOriginalChartBody(isDark, pieT),
          ),
        ],
        if (_serverZoomedData != null && serverZoomT > 0)
          Opacity(
            opacity: serverZoomT,
            child: StatsChartWidget(
              key: ValueKey('zoomed_${widget.data.title}'),
              data: _serverZoomedData!,
              theme: widget.theme,
              hideHeader: true,
            ),
          ),
      ],
    );
  }

  Widget _buildOriginalChartBody(bool isDark, double pieT) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _kChartHeight,
          child: LayoutBuilder(builder: (ctx, box) {
            final w = box.maxWidth;
            _chartWidth = w;
            final isStackLinear = widget.data.chartType == 'StackLinear';
            final chartPainter = _ChartAreaPainter(
              data: widget.data,
              isDark: isDark,
              rangeStart: _rangeStart,
              rangeEnd: _rangeEnd,
              selectedIndex: _selectedIndex,
              lineVisible: _lineVisible,
              lineAlphas: _lineAlphas,
              rulerCrossfade: _rulerCrossfade,
              prevRulerMn: _prevRulerMn,
              prevRulerMx: _prevRulerMx,
              animatedYMn: _animatedYMn,
              animatedYMx: _animatedYMx,
              dateLabelAlpha: _dateLabelAlpha,
              prevDateStep: _prevDateStep,
              curDateStep: _curDateStep,
              pieProgress: isStackLinear ? pieT : 0.0,
              pieDataIndex: isStackLinear ? _pieDataIndex : null,
              pieHoverSlice: _pieHoverSlice,
              pieSliceHoverProgress: _pieSliceHoverProgress,
              textCache: _textPainterCache,
              selectionLineColor: widget.theme.colorScheme.onSurface.withValues(alpha: 0.15),
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    if (_isPieActive) {
                      _onPieHover(d.localPosition, w);
                    } else {
                      _onChartTap(d, w);
                    }
                  },
                  child: MouseRegion(
                    onHover: _isPieActive
                        ? (e) => _onPieHover(e.localPosition, w)
                        : null,
                    onExit: _isPieActive
                        ? (_) => setState(() => _pieHoverSlice = -1)
                        : null,
                    child: CustomPaint(
                      size: Size(w, _kChartHeight),
                      painter: chartPainter,
                    ),
                  ),
                ),
                if (_selectedIndex != null && !_isPieActive)
                  _buildTooltip(w, isDark),
              ],
            );
          }),
        ),
        if (!widget.data.isFooterHidden) ...[
          const SizedBox(height: 11),
          SizedBox(
            height: _kFooterHeight,
            child: LayoutBuilder(builder: (ctx, box) {
              final w = box.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _onFooterPanStart(d, w),
                onPanUpdate: (d) => _onFooterPanUpdate(d, w),
                onPanEnd: (_) => _dragMode = _DragMode.none,
                onTapUp: (d) => _onFooterTap(d, w),
                child: CustomPaint(
                  size: Size(w, _kFooterHeight),
                  painter: _FooterPainter(
                    data: widget.data,
                    isDark: isDark,
                    rangeStart: _rangeStart,
                    rangeEnd: _rangeEnd,
                    lineVisible: _lineVisible,
                    accentColor: widget.theme.colorScheme.primary,
                    lineAlphas: _lineAlphas,
                    animatedFooterYMax: _footerAnimatedMax,
                    dimOverlayColor: isDark ? const Color(0x99182533) : const Color(0x99e2eef9),
                  ),
                ),
              );
            }),
          ),
        ],
        if (widget.data.lines.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Wrap(
              children: widget.data.lines.map((line) {
                    final isShaking = _shakeLineId == line.id &&
                        _shakeController.isAnimating;
                    final shakeOff = isShaking
                        ? math.sin(_shakeController.value * math.pi * 4) * 6
                        : 0.0;
                    return _FilterButton(
                      label: line.name,
                      color: _resolveLineColor(line),
                      active: _lineVisible[line.id] ?? true,
                      isDark: isDark,
                      onTap: () => _toggleLine(line.id),
                      onLongPress: () => _longPressLine(line.id),
                      shakeOffset: shakeOff,
                    );
                  }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildTooltip(double chartWidth, bool isDark) {
    final idx = _selectedIndex!;
    final n = widget.data.timestamps.length;
    if (n == 0) return const SizedBox.shrink();
    final span = _rangeEnd - _rangeStart;
    if (span <= 0) return const SizedBox.shrink();

    final bgColor = isDark ? const Color(0xFF2B3744) : Colors.white;
    final fgColor = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    final xFrac = n > 1 ? idx / (n - 1) : 0.5;
    final xPx = ((xFrac - _rangeStart) / span) * chartWidth;

    final dt = _toDate(widget.data.timestamps[idx]);
    String dateStr;
    if (widget.data.weekFormat) {
      final dtEnd = dt.add(const Duration(days: 6));
      dateStr =
          '${dt.day} ${_months[dt.month - 1]} – ${dtEnd.day} ${_months[dtEnd.month - 1]}';
    } else {
      dateStr =
          '${_weekdays[dt.weekday - 1]}, ${_months[dt.month - 1]} ${dt.day}';
    }

    double totalAtIdx = 0;
    if (widget.data.hasPercentages) {
      for (final l in widget.data.lines) {
        if (idx < l.values.length) totalAtIdx += l.values[idx];
      }
    }

    final zoomEnabled = widget.data.zoomToken != null &&
        widget.data.zoomToken!.isNotEmpty;
    final hasCurrency = widget.data.currency != null &&
        widget.data.currencyRate != null &&
        widget.data.currencyRate! > 0;

    final allLines = widget.data.lines;

    if (_tooltipCachedIdx != idx || _tooltipCachedHasCurrency != hasCurrency) {
      final nameStyle = TextStyle(fontSize: 12, color: subColor);
      final valStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fgColor);
      final pctStyle = TextStyle(fontSize: 12, color: subColor);
      double mxName = 0, mxVal = 0, mxPct = 0;
      for (final line in allLines) {
        final ntp = TextPainter(
          text: TextSpan(text: line.name, style: nameStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        if (ntp.width > mxName) mxName = ntp.width;
        ntp.dispose();

        final val = idx < line.values.length ? line.values[idx] : 0.0;
        final vText = hasCurrency
            ? '${_formatValue(val)} ${widget.data.currency}'
            : _formatValue(val);
        final vtp = TextPainter(
          text: TextSpan(text: vText, style: valStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        if (vtp.width > mxVal) mxVal = vtp.width;
        vtp.dispose();

        if (widget.data.hasPercentages && totalAtIdx > 0) {
          final pText = '${(val / totalAtIdx * 100).toStringAsFixed(0)}%';
          final ptp = TextPainter(
            text: TextSpan(text: pText, style: pctStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          if (ptp.width > mxPct) mxPct = ptp.width;
          ptp.dispose();
        }
      }
      _tooltipCachedIdx = idx;
      _tooltipCachedHasCurrency = hasCurrency;
      _tooltipMaxNameW = mxName;
      _tooltipMaxValW = mxVal;
      _tooltipMaxPctW = mxPct;
    }
    final maxNameW = _tooltipMaxNameW;
    final maxValW = _tooltipMaxValW;
    final maxPctW = _tooltipMaxPctW;

    double tooltipWidth = _kTooltipPadH * 2 + maxNameW + 8.0 + maxValW;
    if (widget.data.hasPercentages && totalAtIdx > 0) {
      tooltipWidth += 4.0 + maxPctW;
    }
    tooltipWidth = math.max(tooltipWidth, 140.0);

    const gap = 12.0;
    var left = xPx - tooltipWidth - gap;
    if (left < 0) left = xPx + gap;
    if (left + tooltipWidth > chartWidth) left = 0;
    left = left.clamp(0.0, math.max(0.0, chartWidth - tooltipWidth));

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
          _kTooltipPadH, _kTooltipPadTop, _kTooltipPadH, _kTooltipPadBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(dateStr,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fgColor)),
              ),
              if (zoomEnabled)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: CustomPaint(
                    size: const Size(7, 10),
                    painter: _ZoomArrowPainter(color: subColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < allLines.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            AnimatedOpacity(
              opacity:
                  (_lineVisible[allLines[i].id] ?? true) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Row(
                children: [
                  Expanded(
                      child: Text(allLines[i].name,
                          style: TextStyle(fontSize: 12, color: subColor),
                          overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  if (hasCurrency) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_formatValue(idx < allLines[i].values.length ? allLines[i].values[idx] : 0)} ${widget.data.currency}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _resolveLineColor(allLines[i])),
                        ),
                        Text(
                          '≈ \$${_formatValue((idx < allLines[i].values.length ? allLines[i].values[idx] : 0) * widget.data.currencyRate!)}',
                          style: TextStyle(fontSize: 10, color: subColor),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      _formatValue(idx < allLines[i].values.length
                          ? allLines[i].values[idx]
                          : 0),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _resolveLineColor(allLines[i])),
                    ),
                    if (widget.data.hasPercentages && totalAtIdx > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${(idx < allLines[i].values.length ? allLines[i].values[idx] / totalAtIdx * 100 : 0).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final shadow = BoxDecoration(
      borderRadius: BorderRadius.circular(_kTooltipRadius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );

    Widget card = DecoratedBox(
      decoration: shadow,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(_kTooltipRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: zoomEnabled ? () => _requestServerZoom(idx) : null,
          borderRadius: BorderRadius.circular(_kTooltipRadius),
          child: SizedBox(width: tooltipWidth, child: content),
        ),
      ),
    );

    return Positioned(
      left: left,
      top: 0,
      child: zoomEnabled ? card : IgnorePointer(child: card),
    );
  }

  void _onChartTap(TapDownDetails details, double chartWidth) {
    final span = _rangeEnd - _rangeStart;
    if (span <= 0) return;
    final xFrac =
        _rangeStart + (details.localPosition.dx / chartWidth) * span;
    final n = widget.data.timestamps.length;
    final idx = (xFrac * (n - 1)).round().clamp(0, n - 1);
    if (widget.data.chartType == 'StackLinear' && !_isPieActive) {
      _enterPieMode(idx);
      return;
    }
    setState(() => _selectedIndex = _selectedIndex == idx ? null : idx);
  }

  void _onFooterPanStart(DragStartDetails details, double width) {
    _animController.stop();
    final x = details.localPosition.dx;
    final leftX = _rangeStart * width;
    final rightX = _rangeEnd * width;

    if ((x - leftX).abs() <= _kHandleWidth + 5) {
      _dragMode = _DragMode.leftHandle;
    } else if ((x - rightX).abs() <= _kHandleWidth + 5) {
      _dragMode = _DragMode.rightHandle;
    } else if (x > leftX && x < rightX) {
      _dragMode = _DragMode.panCenter;
    } else {
      _dragMode = _DragMode.none;
    }
    _dragStartX = x;
    _rangeStartAtDrag = _rangeStart;
    _rangeEndAtDrag = _rangeEnd;
  }

  void _onFooterPanUpdate(DragUpdateDetails details, double width) {
    if (_dragMode == _DragMode.none || width <= 0) return;
    final dFrac = (details.localPosition.dx - _dragStartX) / width;
    final minFrac = _kHandleSepPx / width;
    setState(() {
      switch (_dragMode) {
        case _DragMode.leftHandle:
          _rangeStart = (_rangeStartAtDrag + dFrac)
              .clamp(0.0, _rangeEnd - minFrac);
        case _DragMode.rightHandle:
          _rangeEnd = (_rangeEndAtDrag + dFrac)
              .clamp(_rangeStart + minFrac, 1.0);
        case _DragMode.panCenter:
          final span = _rangeEndAtDrag - _rangeStartAtDrag;
          var newStart = _rangeStartAtDrag + dFrac;
          var newEnd = _rangeEndAtDrag + dFrac;
          if (newStart < 0) {
            newStart = 0;
            newEnd = span;
          }
          if (newEnd > 1) {
            newEnd = 1;
            newStart = 1 - span;
          }
          _rangeStart = newStart;
          _rangeEnd = newEnd;
        case _DragMode.none:
          break;
      }
    });
    _updateRulerRange();
    _updateFooterYRange();
    _updateDateStep();
  }

  void _onFooterTap(TapUpDetails details, double width) {
    if (width <= 0) return;
    final x = details.localPosition.dx;
    final leftX = _rangeStart * width;
    final rightX = _rangeEnd * width;

    if (x < leftX - _kHandleWidth || x > rightX + _kHandleWidth) {
      final span = _rangeEnd - _rangeStart;
      final targetCenter = (x / width).clamp(span / 2, 1.0 - span / 2);
      _animFromStart = _rangeStart;
      _animToStart = targetCenter - span / 2;
      _animFromEnd = _rangeEnd;
      _animToEnd = targetCenter + span / 2;
      _animController.forward(from: 0);
      _dateLabelProgress = 0.0;
      _dateLabelAlpha = 0.0;
      _ensureTickerRunning();
    }
  }

  void _onPieHover(Offset pos, double chartWidth) {
    if (_pieDataIndex == null) return;
    final lines = widget.data.lines
        .where((l) => _lineVisible[l.id] ?? true)
        .toList();
    if (lines.isEmpty) return;

    final idx = _pieDataIndex!;
    double total = 0;
    for (final l in lines) {
      if (idx < l.values.length) total += l.values[idx];
    }
    if (total == 0) {
      setState(() => _pieHoverSlice = -1);
      return;
    }

    final cx = chartWidth / 2;
    const cy = _kChartHeight / 2;
    final radius = math.min(cx, cy) * 0.75;
    final dx = pos.dx - cx;
    final dy = pos.dy - cy;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist > radius + 20) {
      setState(() => _pieHoverSlice = -1);
      return;
    }

    var angle = math.atan2(dy, dx);
    if (angle < -math.pi / 2) angle += 2 * math.pi;
    final normAngle = angle + math.pi / 2;
    final clampAngle = normAngle < 0 ? normAngle + 2 * math.pi : normAngle;

    double cumAngle = 0;
    for (int i = 0; i < lines.length; i++) {
      final val = idx < lines[i].values.length ? lines[i].values[idx] : 0.0;
      final sweep = (val / total) * 2 * math.pi;
      if (clampAngle >= cumAngle && clampAngle < cumAngle + sweep) {
        if (_pieHoverSlice != i) {
          setState(() => _pieHoverSlice = i);
          _ensureTickerRunning();
        }
        return;
      }
      cumAngle += sweep;
    }
    if (_pieHoverSlice != -1) {
      setState(() => _pieHoverSlice = -1);
      _ensureTickerRunning();
    }
  }

  String? _shakeLineId;

  void _toggleLine(String lineId) {
    final current = _lineVisible[lineId] ?? true;
    if (current) {
      if (_lineVisible.values.where((v) => v).length <= 1) {
        _shakeLineId = lineId;
        _shakeController.forward(from: 0);
        return;
      }
      setState(() => _lineVisible[lineId] = false);
      _lineAlphaControllers[lineId]?.reverse();
    } else {
      setState(() => _lineVisible[lineId] = true);
      _lineAlphaControllers[lineId]?.forward();
    }
    _updateRulerRange(fromFilter: true);
    _updateFooterYRange();
  }

  void _longPressLine(String lineId) {
    final allVisible =
        _lineVisible.entries.where((e) => e.value).map((e) => e.key).toSet();
    if (allVisible.length == 1 && allVisible.contains(lineId)) {
      for (final l in widget.data.lines) {
        if (!(_lineVisible[l.id] ?? true)) {
          setState(() => _lineVisible[l.id] = true);
          _lineAlphaControllers[l.id]?.forward();
        }
      }
    } else {
      for (final l in widget.data.lines) {
        if (l.id == lineId) {
          if (!(_lineVisible[l.id] ?? true)) {
            setState(() => _lineVisible[l.id] = true);
            _lineAlphaControllers[l.id]?.forward();
          }
        } else if (_lineVisible[l.id] ?? true) {
          setState(() => _lineVisible[l.id] = false);
          _lineAlphaControllers[l.id]?.reverse();
        }
      }
    }
    _updateRulerRange(fromFilter: true);
    _updateFooterYRange();
  }

  static String _formatValue(double v) {
    final a = v.abs();
    if (a >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (a >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
  }
}

class _FilterButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double shakeOffset;

  const _FilterButton({
    required this.label,
    required this.color,
    required this.active,
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
    this.shakeOffset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveBg = Theme.of(context).colorScheme.surface;
    final inactiveText = color;
    Widget btn = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: active ? color : inactiveBg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: active ? 14 : 0,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _CheckMarkPainter(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
          ),
          if (active) const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: active ? Colors.white : inactiveText,
            ),
          ),
        ],
      ),
    );
    if (shakeOffset != 0) {
      btn = Transform.translate(offset: Offset(shakeOffset, 0), child: btn);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 5),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: btn,
      ),
    );
  }
}

class _CheckMarkPainter extends CustomPainter {
  final double strokeWidth;
  final Color color;

  _CheckMarkPainter({required this.strokeWidth, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.5)
      ..lineTo(size.width * 0.4, size.height * 0.75)
      ..lineTo(size.width * 0.85, size.height * 0.25);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckMarkPainter old) =>
      strokeWidth != old.strokeWidth || color != old.color;
}

class _ZoomArrowPainter extends CustomPainter {
  final Color color;
  _ZoomArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const shift = 3.0;
    const stroke = 1.5;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final midY = size.height / 2;
    canvas.drawLine(Offset(0, 0), Offset(shift, midY), paint);
    canvas.drawLine(Offset(0, size.height), Offset(shift, midY), paint);
  }

  @override
  bool shouldRepaint(_ZoomArrowPainter old) => color != old.color;
}

class _ChartAreaPainter extends CustomPainter {
  final StatsChartData data;
  final bool isDark;
  final double rangeStart;
  final double rangeEnd;
  final int? selectedIndex;
  final Map<String, bool> lineVisible;
  final Map<String, double> lineAlphas;
  final double rulerCrossfade;
  final double prevRulerMn;
  final double prevRulerMx;
  final double animatedYMn;
  final double animatedYMx;
  final double dateLabelAlpha;
  final int prevDateStep;
  final int curDateStep;
  final double pieProgress;
  final int? pieDataIndex;
  final int pieHoverSlice;
  final Map<int, double> pieSliceHoverProgress;
  final Map<String, TextPainter> textCache;
  final Color selectionLineColor;

  _ChartAreaPainter({
    required this.data,
    required this.isDark,
    required this.rangeStart,
    required this.rangeEnd,
    this.selectedIndex,
    required this.lineVisible,
    required this.lineAlphas,
    this.rulerCrossfade = 1.0,
    this.prevRulerMn = 0,
    this.prevRulerMx = 1,
    this.animatedYMn = 0,
    this.animatedYMx = 1,
    this.dateLabelAlpha = 1.0,
    this.prevDateStep = 1,
    this.curDateStep = 1,
    this.pieProgress = 0.0,
    this.pieDataIndex,
    this.pieHoverSlice = -1,
    this.pieSliceHoverProgress = const {},
    this.textCache = const {},
    required this.selectionLineColor,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  List<ChartLine> get _visibleLines =>
      data.lines.where((l) => lineVisible[l.id] ?? true).toList();

  List<(ChartLine, double)> get _renderLines => data.lines
      .where((l) => (lineAlphas[l.id] ?? 0) > 0.01)
      .map((l) => (l, lineAlphas[l.id] ?? 1.0))
      .toList();

  (double, double) _lineRange(ChartLine line, int si, int ei) {
    double mn = double.infinity, mx = double.negativeInfinity;
    for (int i = si; i <= ei && i < line.values.length; i++) {
      if (line.values[i] < mn) mn = line.values[i];
      if (line.values[i] > mx) mx = line.values[i];
    }
    if (mn == double.infinity) { mn = 0; mx = 1; }
    if (mx == mn) mx = mn + 1;
    return (mn, mx);
  }

  TextPainter _cachedTP(String text, TextStyle style) {
    final key = '$text|${style.fontSize}|${style.color?.value}';
    var tp = textCache[key];
    if (tp == null) {
      tp = TextPainter(textDirection: TextDirection.ltr);
      textCache[key] = tp;
    }
    final span = TextSpan(text: text, style: style);
    if (tp.text != span) {
      tp.text = span;
      tp.layout();
    }
    return tp;
  }

  static int _computeRulerLineCount(double mn, double mx) {
    const kMinLines = 2;
    const kMaxLines = 6;
    final range = (mx - mn).abs();
    if (range == 0) return kMinLines;
    final v = range > 100 ? _roundRuler(range) : range;
    if (v < kMaxLines) {
      return math.max(2, v.toInt() + 1);
    } else if (v / 2 < kMaxLines) {
      var n = (v ~/ 2) + 1;
      if (v.toInt() % 2 != 0) n++;
      return n.clamp(kMinLines, kMaxLines);
    }
    return kMaxLines;
  }

  static double _roundRuler(double maxValue) {
    final k = (maxValue / 5).toInt();
    return (k % 10 == 0) ? maxValue : (((maxValue ~/ 10) + 1) * 10).toDouble();
  }

  double _dataXToPixel(int i, int n, double width) {
    if (n <= 1) return width / 2;
    final frac = i / (n - 1);
    final span = rangeEnd - rangeStart;
    if (span <= 0) return width / 2;
    return ((frac - rangeStart) / span) * width;
  }

  (double, double) _visibleYRange(List<ChartLine> lines) {
    final n = data.timestamps.length;
    final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    double mn = double.infinity, mx = double.negativeInfinity;
    for (final l in lines) {
      for (int i = si; i <= ei && i < l.values.length; i++) {
        if (l.values[i] < mn) mn = l.values[i];
        if (l.values[i] > mx) mx = l.values[i];
      }
    }
    if (mn == double.infinity) {
      mn = 0;
      mx = 1;
    }
    if (mx == mn) mx = mn + 1;
    return (mn, mx);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    switch (data.chartType) {
      case 'Linear' || 'DoubleLinear':
        _paintLinear(canvas, size);
      case 'Bar':
        _paintBar(canvas, size);
      case 'StackBar':
        _paintStackBar(canvas, size);
      case 'StackLinear':
        _paintStackLinear(canvas, size);
      default:
        _paintLinear(canvas, size);
    }
  }

  void _paintRulers(
      Canvas canvas, Size size, double top, double chartH, double mn,
      double mx, {double? currencyRate, String? currency}) {
    if (rulerCrossfade < 1.0 &&
        (prevRulerMn != mn || prevRulerMx != mx)) {
      _drawRulerSet(canvas, size, top, chartH, prevRulerMn, prevRulerMx,
          1.0 - rulerCrossfade, currencyRate: currencyRate, currency: currency);
    }
    final alpha = rulerCrossfade < 1.0 ? rulerCrossfade : 1.0;
    _drawRulerSet(canvas, size, top, chartH, mn, mx, alpha,
        currencyRate: currencyRate, currency: currency);
  }

  void _drawRulerSet(Canvas canvas, Size size, double top, double chartH,
      double mn, double mx, double alpha,
      {Color? leftColor, Color? rightColor, double? rightMn, double? rightMx,
      double? currencyRate, String? currency}) {
    final gridColor = isDark
        ? Colors.white.withValues(alpha: 0.06 * alpha)
        : Colors.black.withValues(alpha: 0.06 * alpha);
    final defaultLabelColor = isDark
        ? Colors.white.withValues(alpha: 0.6 * alpha)
        : Colors.black.withValues(alpha: 0.6 * alpha);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    final leftLabelColor = leftColor?.withValues(alpha: alpha) ?? defaultLabelColor;
    final rightLabelColor = rightColor?.withValues(alpha: alpha) ?? defaultLabelColor;

    final rulerCount = _computeRulerLineCount(mn, mx);
    for (int i = 0; i <= rulerCount; i++) {
      final y = top + chartH * (1 - i / rulerCount);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final val = mn + (mx - mn) * i / rulerCount;
      final tp = _cachedTP(
          _formatShort(val), TextStyle(fontSize: 10, color: leftLabelColor));
      tp.paint(canvas, Offset(0, y - tp.height - 4));

      if (rightMn != null && rightMx != null) {
        final rVal = rightMn + (rightMx - rightMn) * i / rulerCount;
        final rTp = _cachedTP(
            _formatShort(rVal), TextStyle(fontSize: 10, color: rightLabelColor));
        rTp.paint(canvas, Offset(size.width - rTp.width, y - rTp.height - 4));
      } else if (currencyRate != null && currencyRate > 0) {
        final cVal = val * currencyRate;
        final cTp = _cachedTP(
            '\$${_formatShort(cVal)}', TextStyle(fontSize: 10, color: rightLabelColor));
        cTp.paint(canvas, Offset(size.width - cTp.width, y - cTp.height - 4));
      }
    }
  }

  void _paintDateLabels(Canvas canvas, Size size) {
    final n = data.timestamps.length;
    if (n < 2) return;

    final span = rangeEnd - rangeStart;
    if (span <= 0) return;
    final pxPerPoint = size.width / (span * (n - 1));

    double captionMaxWidth;
    if (data.dayStringMaxWidth != null && data.dayStringMaxWidth! > 0) {
      captionMaxWidth = data.dayStringMaxWidth!;
    } else {
      final labelStyle = TextStyle(
          fontSize: 10, color: isDark ? Colors.white60 : Colors.black54);
      double maxW = 0;
      final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
      final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
      final sampleCount = math.min(10, ei - si + 1);
      final sampleStep = math.max(1, (ei - si + 1) ~/ sampleCount);
      for (int i = si; i <= ei; i += sampleStep) {
        final ts = data.timestamps[i];
        final dt = DateTime.fromMillisecondsSinceEpoch(
            ts.abs() > 1e12 ? ts : ts * 1000);
        final label = '${_months[dt.month - 1]} ${dt.day}';
        final tp = _cachedTP(label, labelStyle);
        if (tp.width > maxW) maxW = tp.width;
      }
      captionMaxWidth = maxW + 16;
    }

    int step = 1;
    while (step * pxPerPoint < captionMaxWidth && step < n) {
      step *= 2;
    }

    final edgeFade = captionMaxWidth / 4;
    final captionOffset = step > 0 ? (captionMaxWidth / (step * pxPerPoint)).ceil() : 0;

    if (prevDateStep != curDateStep && dateLabelAlpha < 1.0) {
      final prevAlpha = math.max((1.0 - dateLabelAlpha) - _kFastAlphaSpeed, 0.0);
      _paintDateLabelsAtStep(
          canvas, size, prevDateStep, prevAlpha, edgeFade, captionOffset);
      _paintDateLabelsAtStep(
          canvas, size, curDateStep, dateLabelAlpha, edgeFade, captionOffset);
    } else {
      _paintDateLabelsAtStep(
          canvas, size, step, dateLabelAlpha, edgeFade, captionOffset);
    }
  }

  void _paintDateLabelsAtStep(Canvas canvas, Size size, int step,
      double baseAlpha, double edgeFade, int captionOffset) {
    final n = data.timestamps.length;
    if (n < 2 || step < 1) return;
    final y = size.height - _kBottomCaptionHeight;
    final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    final firstLabel = (((si + captionOffset) + step - 1) ~/ step) * step;

    for (int idx = firstLabel; idx <= ei; idx += step) {
      final x = _dataXToPixel(idx, n, size.width);
      if (x < -50 || x > size.width + 50) continue;

      double alpha = baseAlpha;
      if (x < edgeFade) alpha *= (x / edgeFade).clamp(0.0, 1.0);
      if (x > size.width - edgeFade) {
        alpha *= ((size.width - x) / edgeFade).clamp(0.0, 1.0);
      }

      final ts = data.timestamps[idx];
      final dt = DateTime.fromMillisecondsSinceEpoch(
          ts.abs() > 1e12 ? ts : ts * 1000);
      final label = '${_months[dt.month - 1]} ${dt.day}';
      final labelColor = isDark
          ? Colors.white.withValues(alpha: 0.6 * alpha)
          : Colors.black.withValues(alpha: 0.6 * alpha);
      final tp = _cachedTP(label, TextStyle(fontSize: 10, color: labelColor));
      tp.paint(canvas, Offset(x - tp.width / 2, y));
    }
  }

  void _paintSelectionIndicator(Canvas canvas, Size size, double top,
      double chartH, double mn, double mx, List<ChartLine> lines) {
    if (selectedIndex == null) return;
    final n = data.timestamps.length;
    final x = _dataXToPixel(selectedIndex!, n, size.width);
    if (x < -20 || x > size.width + 20) return;

    canvas.drawLine(
      Offset(x, top),
      Offset(x, top + chartH),
      Paint()
        ..color = selectionLineColor
        ..strokeWidth = 1,
    );

    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    for (final line in lines) {
      if (selectedIndex! >= line.values.length) continue;
      final yNorm = (line.values[selectedIndex!] - mn) / (mx - mn);
      final y = top + chartH * (1 - yNorm);
      final c = _resolveLineColor(line);
      canvas.drawCircle(Offset(x, y), _kDotRadius, Paint()..color = c);
      canvas.drawCircle(
          Offset(x, y), _kDotRadius - 1.5, Paint()..color = bgColor);
      canvas.drawCircle(Offset(x, y), _kDotRadius - 2.5, Paint()..color = c);
    }
  }

  void _paintLinear(Canvas canvas, Size size) {
    final visLines = _visibleLines;
    final rLines = _renderLines;
    if (visLines.isEmpty || data.timestamps.isEmpty) return;

    const topPad = 10.0;
    final chartH = size.height - topPad - _kBottomCaptionHeight -
        _kBottomCaptionSkip;
    final n = data.timestamps.length;
    final (targetMn, targetMx) = _visibleYRange(visLines);

    final isDouble = data.chartType == 'DoubleLinear' && visLines.length == 2;
    if (isDouble) {
      final l0 = visLines[0], l1 = visLines[1];
      final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
      final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
      final (l0Mn, l0Mx) = _lineRange(l0, si, ei);
      final (l1Mn, l1Mx) = _lineRange(l1, si, ei);
      _drawRulerSet(canvas, size, topPad, chartH, l0Mn, l0Mx, 1.0,
          leftColor: _resolveLineColor(l0), rightColor: _resolveLineColor(l1),
          rightMn: l1Mn, rightMx: l1Mx);
    } else {
      _paintRulers(canvas, size, topPad, chartH, targetMn, targetMx,
          currencyRate: data.currencyRate, currency: data.currency);
    }

    final renderMn = animatedYMn;
    final renderMx = animatedYMx;

    for (final (line, alpha) in rLines) {
      double lineMn = renderMn, lineMx = renderMx;
      if (isDouble) {
        final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
        final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
        final (lMn, lMx) = _lineRange(line, si, ei);
        lineMn = lMn;
        lineMx = lMx;
      }
      final range = lineMx - lineMn;
      if (range == 0) continue;

      final paint = Paint()
        ..color = _resolveLineColor(line).withValues(alpha: alpha)
        ..strokeWidth = _kLineWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final count = math.min(line.values.length, n);
      for (int i = 0; i < count; i++) {
        final x = _dataXToPixel(i, n, size.width);
        final yNorm = (line.values[i] - lineMn) / range;
        final y = topPad + chartH * (1 - yNorm);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    _paintSelectionIndicator(
        canvas, size, topPad, chartH, renderMn, renderMx, visLines);
    _paintDateLabels(canvas, size);
  }

  void _paintBar(Canvas canvas, Size size) {
    final visLines = _visibleLines;
    final rLines = _renderLines;
    if (visLines.isEmpty || data.timestamps.isEmpty) return;

    const topPad = 10.0;
    final chartH = size.height - topPad - _kBottomCaptionHeight -
        _kBottomCaptionSkip;
    final n = data.timestamps.length;
    final span = rangeEnd - rangeStart;
    if (span <= 0) return;

    final visibleN = (span * n).ceil().clamp(1, n);
    final groupWidth = size.width / visibleN;
    final barWidth = (groupWidth * 0.7) / rLines.length.clamp(1, 999);

    double maxVal = 0;
    final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    for (final l in visLines) {
      for (int i = si; i <= ei && i < l.values.length; i++) {
        if (l.values[i] > maxVal) maxVal = l.values[i];
      }
    }
    if (maxVal == 0) maxVal = 1;

    final renderMax = animatedYMx > 0 ? animatedYMx : maxVal;
    _paintRulers(canvas, size, topPad, chartH, 0, maxVal);

    for (int i = 0; i < n; i++) {
      final cx = _dataXToPixel(i, n, size.width);
      final groupX = cx - groupWidth / 2 + groupWidth * 0.15;
      for (int li = 0; li < rLines.length; li++) {
        final (line, lineAlpha) = rLines[li];
        if (i >= line.values.length) continue;
        final val = line.values[i];
        final barH = (val / renderMax) * chartH;
        final x = groupX + barWidth * li;
        final rect =
            Rect.fromLTWH(x, topPad + chartH - barH, barWidth, barH);
        final selAlpha =
            (selectedIndex != null && selectedIndex != i) ? 0.4 : 1.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..color =
                _resolveLineColor(line).withValues(alpha: selAlpha * lineAlpha),
        );
      }
    }

    _paintDateLabels(canvas, size);
  }

  void _paintStackBar(Canvas canvas, Size size) {
    final visLines = _visibleLines;
    final rLines = _renderLines;
    if (visLines.isEmpty || data.timestamps.isEmpty) return;

    const topPad = 10.0;
    final chartH = size.height - topPad - _kBottomCaptionHeight -
        _kBottomCaptionSkip;
    final n = data.timestamps.length;
    final span = rangeEnd - rangeStart;
    if (span <= 0) return;

    final visibleN = (span * n).ceil().clamp(1, n);
    final barWidth = size.width / visibleN;

    double maxSum = 0;
    final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    for (int i = si; i <= ei; i++) {
      double sum = 0;
      for (final l in visLines) {
        if (i < l.values.length) sum += l.values[i];
      }
      if (sum > maxSum) maxSum = sum;
    }
    if (maxSum == 0) maxSum = 1;

    final renderMax = animatedYMx > 0 ? animatedYMx : maxSum;
    _paintRulers(canvas, size, topPad, chartH, 0, maxSum);

    for (int i = 0; i < n; i++) {
      final cx = _dataXToPixel(i, n, size.width);
      double cumulative = 0;
      for (final (line, alpha) in rLines) {
        if (i >= line.values.length) continue;
        final val = line.values[i];
        final prevH = (cumulative / renderMax) * chartH;
        cumulative += val;
        final curH = (cumulative / renderMax) * chartH;
        final rect = Rect.fromLTWH(cx - barWidth / 2 + 0.5,
            topPad + chartH - curH, barWidth - 1, curH - prevH);
        canvas.drawRect(
            rect, Paint()..color = _resolveLineColor(line).withValues(alpha: alpha));
      }
    }

    _paintDateLabels(canvas, size);
  }

  void _paintStackLinear(Canvas canvas, Size size) {
    if (pieProgress > 0 && pieDataIndex != null) {
      _paintStackLinearMorphToPie(canvas, size);
      return;
    }

    final rLines = _renderLines;
    if (rLines.isEmpty || data.timestamps.isEmpty) return;

    const topPad = 10.0;
    final chartH = size.height - topPad - _kBottomCaptionHeight -
        _kBottomCaptionSkip;
    final n = data.timestamps.length;

    final sums = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      for (final (l, _) in rLines) {
        if (i < l.values.length) sums[i] += l.values[i];
      }
    }

    var prevY = List<double>.filled(n, topPad + chartH);
    for (final (line, alpha) in rLines.reversed) {
      final count = math.min(line.values.length, n);
      final path = Path();
      final curY = List<double>.from(prevY);

      for (int i = 0; i < count; i++) {
        final x = _dataXToPixel(i, n, size.width);
        final norm =
            line.values[i] / (sums[i] == 0 ? 1 : sums[i]);
        curY[i] = prevY[i] - norm * chartH;
        if (i == 0) {
          path.moveTo(x, curY[i]);
        } else {
          path.lineTo(x, curY[i]);
        }
      }
      for (int i = count - 1; i >= 0; i--) {
        path.lineTo(_dataXToPixel(i, n, size.width), prevY[i]);
      }
      path.close();
      canvas.drawPath(
          path, Paint()..color = _resolveLineColor(line).withValues(alpha: alpha));
      prevY = curY;
    }

    _paintDateLabels(canvas, size);
  }

  void _paintStackLinearMorphToPie(Canvas canvas, Size size) {
    final rLines = _renderLines;
    if (rLines.isEmpty || data.timestamps.isEmpty) return;

    final t = pieProgress;
    final idx = pieDataIndex!;
    final n = data.timestamps.length;

    const topPad = 10.0;
    final chartH = size.height - topPad - _kBottomCaptionHeight -
        _kBottomCaptionSkip;
    final chartBottom = topPad + chartH;
    final cx = size.width / 2;
    final cy = size.height / 2;
    const kCircleSizeRatio = 0.42;
    final pieRadius = (size.width / 2) * kCircleSizeRatio;

    final sums = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      for (final (l, _) in rLines) {
        if (i < l.values.length) sums[i] += l.values[i];
      }
    }

    double total = 0;
    for (final (l, _) in rLines) {
      if (idx < l.values.length) total += l.values[idx];
    }
    if (total == 0) total = 1;

    // Clip path morphs from chart rectangle to circle
    canvas.save();
    if (t > 0 && t < 1.0) {
      final r = 1.0 + (kCircleSizeRatio - 1.0) * t;
      final clipSide = (size.width / 2) * r;
      final cornerRadius = clipSide * t;
      final clipPath = Path()..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy),
            width: clipSide * 2,
            height: clipSide * 2),
        Radius.circular(cornerRadius),
      ));
      canvas.clipPath(clipPath);
    }

    // Pre-compute pie wedge angles for each line (in rLines order)
    final pieStartAngles = List<double>.filled(rLines.length, 0);
    final pieSweepAngles = List<double>.filled(rLines.length, 0);
    {
      double cumAngle = -math.pi / 2;
      for (int k = 0; k < rLines.length; k++) {
        final (line, _) = rLines[k];
        final val = idx < line.values.length ? line.values[idx] : 0.0;
        final sweep = (val / total) * 2 * math.pi;
        pieStartAngles[k] = cumAngle;
        pieSweepAngles[k] = sweep;
        cumAngle += sweep;
      }
    }

    if (t >= 1.0) {
      for (int k = 0; k < rLines.length; k++) {
        final (line, alpha) = rLines[k];
        final sweep = pieSweepAngles[k];
        if (sweep <= 0) continue;

        final midAngle = pieStartAngles[k] + sweep / 2;
        final hoverProgress = pieSliceHoverProgress[k] ?? 0.0;
        final offsetDist = 8.0 * hoverProgress;
        final offsetX = math.cos(midAngle) * offsetDist;
        final offsetY = math.sin(midAngle) * offsetDist;

        final rect = Rect.fromCircle(
          center: Offset(cx + offsetX, cy + offsetY),
          radius: pieRadius,
        );
        canvas.drawArc(rect, pieStartAngles[k], sweep, true,
            Paint()..color = _resolveLineColor(line).withValues(alpha: alpha));
      }
    } else {
      // Geometric morph: stacked area paths deform into pie wedge shapes.
      // Each data point interpolates from its stacked position toward
      // its corresponding point on the pie wedge arc.
      var prevStackY = List<double>.filled(n, chartBottom);

      // Iterate reversed (bottom layer first) matching stacked area order.
      // rLines[last] is drawn first (bottom), rLines[0] is drawn last (top).
      for (int revIdx = rLines.length - 1; revIdx >= 0; revIdx--) {
        final (line, alpha) = rLines[revIdx];
        if (alpha <= 0) continue;
        final count = math.min(line.values.length, n);

        final pieSA = pieStartAngles[revIdx];
        final pieSW = pieSweepAngles[revIdx];

        // Compute this layer's stacked top positions
        final topY = List<double>.filled(count, 0);
        for (int i = 0; i < count; i++) {
          final norm = line.values[i] / (sums[i] == 0 ? 1 : sums[i]);
          topY[i] = prevStackY[i] - norm * chartH;
        }

        final path = Path();

        // Top edge: interpolate from stacked top → outer pie arc
        for (int i = 0; i < count; i++) {
          final x0 = _dataXToPixel(i, n, size.width);
          final y0 = topY[i];

          final frac = count > 1 ? i / (count - 1) : 0.5;
          final targetAngle = pieSA + frac * pieSW;
          final x1 = cx + pieRadius * math.cos(targetAngle);
          final y1 = cy + pieRadius * math.sin(targetAngle);

          final x = x0 + (x1 - x0) * t;
          final y = y0 + (y1 - y0) * t;

          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }

        // Bottom edge (reverse): interpolate from stacked bottom → pie center
        for (int i = count - 1; i >= 0; i--) {
          final x0 = _dataXToPixel(i, n, size.width);
          final y0 = prevStackY[i];

          final x = x0 + (cx - x0) * t;
          final y = y0 + (cy - y0) * t;

          path.lineTo(x, y);
        }

        path.close();
        canvas.drawPath(path,
            Paint()..color = _resolveLineColor(line).withValues(alpha: alpha));

        for (int i = 0; i < count; i++) {
          prevStackY[i] = topY[i];
        }
      }
    }

    canvas.restore();

    // Pie labels fade in during the last 40% of the transition
    const kAlphaTextPart = 0.6;
    if (t > kAlphaTextPart) {
      final labelProgress = ((t - kAlphaTextPart) / (1.0 - kAlphaTextPart))
          .clamp(0.0, 1.0);
      _paintPieLabelsInternal(
          canvas, size, rLines, total, pieRadius * t, cx, cy, labelProgress);
    }

    if (t < 1.0) {
      _paintDateLabels(canvas, size);
    }
  }

  void _paintPieLabelsInternal(Canvas canvas, Size size,
      List<(ChartLine, double)> rLines, double total, double side,
      double cx, double cy, double t) {
    const baseFontSize = 20.0;
    final maxScale = side / (baseFontSize * 2);
    final minScale = maxScale * 0.3;
    const kMinPercentage = 0.039;
    const kPieAngleOffset = 90.0;
    final pieLabelColor = isDark ? Colors.white : Colors.white;

    double startAngleDeg = -180.0;
    final idx = pieDataIndex!;
    for (int i = 0; i < rLines.length; i++) {
      final (line, _) = rLines[i];
      final val = idx < line.values.length ? line.values[idx] : 0.0;
      final percentage = val / total;
      final sweepDeg = percentage * 360.0;
      if (sweepDeg <= 0 || percentage <= kMinPercentage) {
        startAngleDeg += sweepDeg;
        continue;
      }

      final rText = side * math.sqrt(1.0 - percentage);
      final textAngle = startAngleDeg + kPieAngleOffset + sweepDeg / 2;
      final textRadians = textAngle * math.pi / 180.0;
      final scale = (maxScale == minScale)
          ? 0.0
          : minScale + percentage * (maxScale - minScale);

      final pct = (percentage * 100).round();
      final tp = _cachedTP('$pct%', TextStyle(
        fontSize: baseFontSize,
        fontWeight: FontWeight.w600,
        color: pieLabelColor,
      ));
      final textXShift = tp.width / 2;
      final textYShift = tp.height / 2;

      final labelCx = cx +
          (rText - textXShift * (1.0 - scale)) * math.cos(textRadians);
      final labelCy = cy +
          (rText - textYShift * (1.0 - scale)) * math.sin(textRadians);

      canvas.save();
      canvas.translate(labelCx, labelCy);
      canvas.scale(scale * t, scale * t);
      canvas.translate(-labelCx, -labelCy);
      tp.paint(canvas, Offset(labelCx - textXShift, labelCy - textYShift));
      canvas.restore();

      startAngleDeg += sweepDeg;
    }
  }

  static String _formatShort(double v) {
    final a = v.abs();
    if (a >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (a >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_ChartAreaPainter old) =>
      data != old.data ||
      isDark != old.isDark ||
      rangeStart != old.rangeStart ||
      rangeEnd != old.rangeEnd ||
      selectedIndex != old.selectedIndex ||
      lineVisible != old.lineVisible ||
      lineAlphas != old.lineAlphas ||
      rulerCrossfade != old.rulerCrossfade ||
      animatedYMn != old.animatedYMn ||
      animatedYMx != old.animatedYMx ||
      dateLabelAlpha != old.dateLabelAlpha ||
      prevDateStep != old.prevDateStep ||
      curDateStep != old.curDateStep ||
      pieProgress != old.pieProgress ||
      pieDataIndex != old.pieDataIndex ||
      pieHoverSlice != old.pieHoverSlice ||
      pieSliceHoverProgress != old.pieSliceHoverProgress ||
      selectionLineColor != old.selectionLineColor;
}

class _FooterPainter extends CustomPainter {
  final StatsChartData data;
  final bool isDark;
  final double rangeStart;
  final double rangeEnd;
  final Map<String, bool> lineVisible;
  final Color accentColor;
  final Map<String, double> lineAlphas;
  final double animatedFooterYMax;
  final Color dimOverlayColor;

  _FooterPainter({
    required this.data,
    required this.isDark,
    required this.rangeStart,
    required this.rangeEnd,
    required this.lineVisible,
    required this.accentColor,
    this.lineAlphas = const {},
    this.animatedFooterYMax = 0,
    required this.dimOverlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lines =
        data.lines.where((l) => lineVisible[l.id] ?? true).toList();
    if (lines.isEmpty || data.timestamps.isEmpty) return;

    final w = size.width;
    final h = size.height;

    _paintMiniChart(canvas, size, lines);

    final leftX = rangeStart * w;
    final rightX = rangeEnd * w;
    final dimColor = dimOverlayColor;

    if (leftX > 0) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, leftX, h), Paint()..color = dimColor);
    }
    if (rightX < w) {
      canvas.drawRect(Rect.fromLTWH(rightX, 0, w - rightX, h),
          Paint()..color = dimColor);
    }

    final handlePaint = Paint()
      ..color = const Color(0xD8BACCD9);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(leftX, 0, _kHandleWidth, h),
        topLeft: const Radius.circular(_kHandleRadius),
        bottomLeft: const Radius.circular(_kHandleRadius),
      ),
      handlePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(rightX - _kHandleWidth, 0, _kHandleWidth, h),
        topRight: const Radius.circular(_kHandleRadius),
        bottomRight: const Radius.circular(_kHandleRadius),
      ),
      handlePaint,
    );

    final gripPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final cy = h / 2;
    canvas.drawLine(Offset(leftX + _kHandleWidth / 2, cy - 5),
        Offset(leftX + _kHandleWidth / 2, cy + 5), gripPaint);
    canvas.drawLine(Offset(rightX - _kHandleWidth / 2, cy - 5),
        Offset(rightX - _kHandleWidth / 2, cy + 5), gripPaint);

    final borderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.3)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(leftX + _kHandleWidth, 0),
        Offset(rightX - _kHandleWidth, 0), borderPaint);
    canvas.drawLine(Offset(leftX + _kHandleWidth, h),
        Offset(rightX - _kHandleWidth, h), borderPaint);
  }

  void _paintMiniChart(Canvas canvas, Size size, List<ChartLine> lines) {
    final n = data.timestamps.length;
    final w = size.width;
    final h = size.height;

    switch (data.chartType) {
      case 'Linear' || 'DoubleLinear':
        for (final line in lines) {
          final alpha = lineAlphas[line.id] ?? 1.0;
          if (alpha < 0.01) continue;
          double mn = double.infinity, mx = double.negativeInfinity;
          for (final v in line.values) {
            if (v < mn) mn = v;
            if (v > mx) mx = v;
          }
          if (mn == double.infinity) { mn = 0; mx = 1; }
          if (mx == mn) mx = mn + 1;
          final count = math.min(line.values.length, n);
          if (count < 2) continue;
          final path = Path();
          for (int i = 0; i < count; i++) {
            final x = w * i / (count - 1);
            final y = h * (1 - (line.values[i] - mn) / (mx - mn));
            if (i == 0) {
              path.moveTo(x, y);
            } else {
              path.lineTo(x, y);
            }
          }
          canvas.drawPath(
              path,
              Paint()
                ..color = _resolveLineColor(line).withValues(alpha: alpha)
                ..strokeWidth = 1
                ..style = PaintingStyle.stroke);
        }

      case 'Bar':
        double mx = animatedFooterYMax > 0 ? animatedFooterYMax : 0;
        if (mx <= 0) {
          for (final l in lines) {
            for (final v in l.values) {
              if (v > mx) mx = v;
            }
          }
        }
        if (mx == 0) mx = 1;
        final barWidth = w / n / lines.length;
        for (int i = 0; i < n; i++) {
          for (int j = 0; j < lines.length; j++) {
            if (i >= lines[j].values.length) continue;
            final alpha = lineAlphas[lines[j].id] ?? 1.0;
            if (alpha < 0.01) continue;
            final barH = (lines[j].values[i] / mx) * h;
            canvas.drawRect(
              Rect.fromLTWH(
                  w * i / n + barWidth * j, h - barH, barWidth, barH),
              Paint()..color = _resolveLineColor(lines[j]).withValues(alpha: alpha),
            );
          }
        }

      case 'StackBar':
        double mx = animatedFooterYMax > 0 ? animatedFooterYMax : 0;
        if (mx <= 0) {
          for (int i = 0; i < n; i++) {
            double s = 0;
            for (final l in lines) {
              if (i < l.values.length) s += l.values[i];
            }
            if (s > mx) mx = s;
          }
        }
        if (mx == 0) return;
        final barWidth = w / n;
        for (int i = 0; i < n; i++) {
          double cum = 0;
          for (final l in lines) {
            if (i >= l.values.length) continue;
            final alpha = lineAlphas[l.id] ?? 1.0;
            final prev = cum / mx * h;
            cum += l.values[i];
            final cur = cum / mx * h;
            canvas.drawRect(
              Rect.fromLTWH(barWidth * i, h - cur, barWidth, cur - prev),
              Paint()..color = _resolveLineColor(l).withValues(alpha: alpha),
            );
          }
        }

      case 'StackLinear':
        final sums = List<double>.filled(n, 0);
        for (int i = 0; i < n; i++) {
          for (final l in lines) {
            if (i < l.values.length) sums[i] += l.values[i];
          }
        }
        var prevY = List<double>.filled(n, h);
        for (final l in lines.reversed) {
          final alpha = lineAlphas[l.id] ?? 1.0;
          if (alpha < 0.01) continue;
          final c = math.min(l.values.length, n);
          if (c < 2) continue;
          final path = Path();
          final curY = List<double>.from(prevY);
          for (int i = 0; i < c; i++) {
            final x = w * i / (c - 1);
            curY[i] =
                prevY[i] - (l.values[i] / (sums[i] == 0 ? 1 : sums[i])) * h;
            if (i == 0) {
              path.moveTo(x, curY[i]);
            } else {
              path.lineTo(x, curY[i]);
            }
          }
          for (int i = c - 1; i >= 0; i--) {
            path.lineTo(w * i / (c - 1), prevY[i]);
          }
          path.close();
          canvas.drawPath(
              path, Paint()..color = _resolveLineColor(l).withValues(alpha: alpha));
          prevY = curY;
        }
    }
  }

  @override
  bool shouldRepaint(_FooterPainter old) =>
      data != old.data ||
      isDark != old.isDark ||
      rangeStart != old.rangeStart ||
      rangeEnd != old.rangeEnd ||
      lineVisible != old.lineVisible ||
      lineAlphas != old.lineAlphas ||
      animatedFooterYMax != old.animatedFooterYMax ||
      dimOverlayColor != old.dimOverlayColor;
}

