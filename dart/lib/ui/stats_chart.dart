import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class StatsChartData {
  final String title;
  final String chartType;
  final List<int> timestamps;
  final List<ChartLine> lines;
  final String? zoomToken;
  final bool weekFormat;
  final bool hasPercentages;
  final double? currencyRate;
  final String? currency;

  StatsChartData({
    required this.title,
    required this.chartType,
    required this.timestamps,
    required this.lines,
    this.zoomToken,
    this.weekFormat = false,
    this.hasPercentages = false,
    this.currencyRate,
    this.currency,
  });

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
          final colorHex = colors[id] as String? ?? '#3DC23F';
          lines.add(ChartLine(
            id: id,
            name: names[id] as String? ?? id,
            color: _parseColor(colorHex),
            values: values,
            isHiddenOnStart: hiddenSet.contains(id),
          ));
        }
      }

      if (timestamps.isEmpty || lines.isEmpty) return null;

      final percentage = parsed['percentage'] as bool? ?? false;
      bool weekFmt = false;
      if (timestamps.length >= 2) {
        final ms0 =
            timestamps[0].abs() > 1e12 ? timestamps[0] : timestamps[0] * 1000;
        final ms1 =
            timestamps[1].abs() > 1e12 ? timestamps[1] : timestamps[1] * 1000;
        weekFmt = (ms1 - ms0).abs() >= 6 * 24 * 3600 * 1000;
      }

      return StatsChartData(
        title: title,
        chartType: chartType,
        timestamps: timestamps,
        lines: lines,
        zoomToken: map['zoom_token'] as String?,
        weekFormat: weekFmt,
        hasPercentages: percentage,
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
  final List<double> values;
  final bool isHiddenOnStart;

  ChartLine({
    required this.id,
    required this.name,
    required this.color,
    required this.values,
    this.isHiddenOnStart = false,
  });
}

const _kHeaderHeight = 36.0;
const _kChartHeight = 200.0;
const _kFooterHeight = 42.0;
const _kHandleWidth = 10.0;
const _kHandleRadius = 6.0;
const _kMinRangeFrac = 0.02;
const _kLineWidth = 2.0;
const _kDotRadius = 5.0;
const _kBottomCaptionHeight = 15.0;
const _kBottomCaptionSkip = 6.0;
const _kTooltipRadius = 8.0;
const _kTooltipWidth = 180.0;

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

  late AnimationController _rulerAnimController;
  double _prevRulerMn = 0, _prevRulerMx = 1;
  double _curRulerMn = 0, _curRulerMx = 1;
  double _rulerCrossfade = 1.0;

  late AnimationController _pieAnimController;
  int? _pieDataIndex;
  int _pieHoverSlice = -1;

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
      duration: const Duration(milliseconds: 150),
    )..addListener(() {
        final t = Curves.easeInOutSine.transform(_animController.value);
        setState(() {
          _rangeStart = _animFromStart + (_animToStart - _animFromStart) * t;
          _rangeEnd = _animFromEnd + (_animToEnd - _animFromEnd) * t;
        });
      });
    _rulerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _rulerCrossfade =
              Curves.easeInCubic.transform(_rulerAnimController.value);
        });
      });
    _pieAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() => setState(() {}));
    _serverZoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(StatsChartWidget old) {
    super.didUpdateWidget(old);
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
    _rulerAnimController.dispose();
    _pieAnimController.dispose();
    _serverZoomAnim.dispose();
    for (final c in _lineAlphaControllers.values) {
      c.dispose();
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

  void _updateRulerRange() {
    final (mn, mx) = _computeYRange();
    final range = (_curRulerMx - _curRulerMn).abs();
    final threshold = range > 0 ? range * 0.05 : 0.001;
    if ((mn - _curRulerMn).abs() > threshold ||
        (mx - _curRulerMx).abs() > threshold) {
      if (!_rulerAnimController.isAnimating) {
        _prevRulerMn = _curRulerMn;
        _prevRulerMx = _curRulerMx;
      }
      _curRulerMn = mn;
      _curRulerMx = mx;
      if (!_rulerAnimController.isAnimating) {
        _rulerCrossfade = 0;
        _rulerAnimController.forward(from: 0);
      }
    } else {
      _curRulerMn = mn;
      _curRulerMx = mx;
      if (!_rulerAnimController.isAnimating) _rulerCrossfade = 1.0;
    }
  }

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
    _updateRulerRange();
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
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: 1.0 - pieT,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _onChartTap(d, w),
                    child: CustomPaint(
                      size: Size(w, _kChartHeight),
                      painter: _ChartAreaPainter(
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
                      ),
                    ),
                  ),
                ),
                if (pieT > 0 && _pieDataIndex != null)
                  Opacity(
                    opacity: pieT,
                    child: MouseRegion(
                      onHover: (e) => _onPieHover(e.localPosition, w),
                      onExit: (_) => setState(() => _pieHoverSlice = -1),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => _onPieHover(d.localPosition, w),
                        child: CustomPaint(
                          size: Size(w, _kChartHeight),
                          painter: _PieChartPainter(
                            data: widget.data,
                            dataIndex: _pieDataIndex!,
                            lineVisible: _lineVisible,
                            isDark: isDark,
                            hoverSlice: _pieHoverSlice,
                            animProgress: pieT,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_selectedIndex != null && !_isPieActive)
                  _buildTooltip(w, isDark),
              ],
            );
          }),
        ),
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
                ),
              ),
            );
          }),
        ),
        if (widget.data.lines.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Wrap(
              children: widget.data.lines
                  .map((line) => _FilterButton(
                        label: line.name,
                        color: line.color,
                        active: _lineVisible[line.id] ?? true,
                        isDark: isDark,
                        onTap: () => _toggleLine(line.id),
                        onLongPress: () => _longPressLine(line.id),
                      ))
                  .toList(),
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

    const gap = 12.0;
    var left = xPx - _kTooltipWidth - gap;
    if (left < 0) left = xPx + gap;
    if (left + _kTooltipWidth > chartWidth) left = 0;

    final allLines = widget.data.lines;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 11),
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
                  child: Icon(Icons.chevron_right, size: 14, color: subColor),
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
                              color: allLines[i].color),
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
                          color: allLines[i].color),
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
          child: SizedBox(width: _kTooltipWidth, child: content),
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
    setState(() {
      switch (_dragMode) {
        case _DragMode.leftHandle:
          _rangeStart = (_rangeStartAtDrag + dFrac)
              .clamp(0.0, _rangeEnd - _kMinRangeFrac);
        case _DragMode.rightHandle:
          _rangeEnd = (_rangeEndAtDrag + dFrac)
              .clamp(_rangeStart + _kMinRangeFrac, 1.0);
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
        if (_pieHoverSlice != i) setState(() => _pieHoverSlice = i);
        return;
      }
      cumAngle += sweep;
    }
    setState(() => _pieHoverSlice = -1);
  }

  void _toggleLine(String lineId) {
    final current = _lineVisible[lineId] ?? true;
    if (current) {
      if (_lineVisible.values.where((v) => v).length <= 1) return;
      setState(() => _lineVisible[lineId] = false);
      _lineAlphaControllers[lineId]?.reverse();
    } else {
      setState(() => _lineVisible[lineId] = true);
      _lineAlphaControllers[lineId]?.forward();
    }
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

  const _FilterButton({
    required this.label,
    required this.color,
    required this.active,
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 5),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          decoration: BoxDecoration(
            color: active
                ? color
                : (isDark
                    ? const Color(0xFF1A2633)
                    : const Color(0xFFEEEEEE)),
            borderRadius: BorderRadius.circular(14),
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
                  color: active
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
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
      double mx) {
    if (rulerCrossfade < 1.0 &&
        (prevRulerMn != mn || prevRulerMx != mx)) {
      _drawRulerSet(canvas, size, top, chartH, prevRulerMn, prevRulerMx,
          1.0 - rulerCrossfade);
    }
    final alpha = rulerCrossfade < 1.0 ? rulerCrossfade : 1.0;
    _drawRulerSet(canvas, size, top, chartH, mn, mx, alpha);
  }

  void _drawRulerSet(Canvas canvas, Size size, double top, double chartH,
      double mn, double mx, double alpha) {
    final gridColor = isDark
        ? Colors.white.withValues(alpha: 0.06 * alpha)
        : Colors.black.withValues(alpha: 0.06 * alpha);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6 * alpha)
        : Colors.black.withValues(alpha: 0.6 * alpha);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    const rulerCount = 5;
    for (int i = 0; i <= rulerCount; i++) {
      final y = top + chartH * (1 - i / rulerCount);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final val = mn + (mx - mn) * i / rulerCount;
      final tp = TextPainter(
        text: TextSpan(
            text: _formatShort(val),
            style: TextStyle(fontSize: 10, color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height - 4));
    }
  }

  void _paintDateLabels(Canvas canvas, Size size) {
    final n = data.timestamps.length;
    if (n < 2) return;

    final span = rangeEnd - rangeStart;
    if (span <= 0) return;
    final pxPerPoint = size.width / (span * (n - 1));

    final sampleTp = TextPainter(
      text: TextSpan(
          text: 'May 00',
          style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white60 : Colors.black54)),
      textDirection: TextDirection.ltr,
    )..layout();
    final minSpacing = sampleTp.width + 20;

    int step = 1;
    while (step * pxPerPoint < minSpacing && step < n) {
      step *= 2;
    }

    final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    final firstLabel = ((si + step - 1) ~/ step) * step;
    const edgeFade = 30.0;
    final y = size.height - _kBottomCaptionHeight;

    for (int idx = firstLabel; idx <= ei; idx += step) {
      final x = _dataXToPixel(idx, n, size.width);
      if (x < -50 || x > size.width + 50) continue;

      double alpha = 1.0;
      if (x < edgeFade) alpha = (x / edgeFade).clamp(0.0, 1.0);
      if (x > size.width - edgeFade) {
        alpha = ((size.width - x) / edgeFade).clamp(0.0, 1.0);
      }

      final ts = data.timestamps[idx];
      final dt = DateTime.fromMillisecondsSinceEpoch(
          ts.abs() > 1e12 ? ts : ts * 1000);
      final label = '${_months[dt.month - 1]} ${dt.day}';
      final labelColor = isDark
          ? Colors.white.withValues(alpha: 0.6 * alpha)
          : Colors.black.withValues(alpha: 0.6 * alpha);
      final tp = TextPainter(
        text: TextSpan(
            text: label, style: TextStyle(fontSize: 10, color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
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
        ..color = isDark ? Colors.white24 : Colors.black12
        ..strokeWidth = 1,
    );

    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    for (final line in lines) {
      if (selectedIndex! >= line.values.length) continue;
      final yNorm = (line.values[selectedIndex!] - mn) / (mx - mn);
      final y = top + chartH * (1 - yNorm);
      canvas.drawCircle(
          Offset(x, y), _kDotRadius, Paint()..color = line.color);
      canvas.drawCircle(
          Offset(x, y), _kDotRadius - 1.5, Paint()..color = bgColor);
      canvas.drawCircle(
          Offset(x, y), _kDotRadius - 2.5, Paint()..color = line.color);
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
    final (mn, mx) = _visibleYRange(visLines);

    _paintRulers(canvas, size, topPad, chartH, mn, mx);

    for (final (line, alpha) in rLines) {
      double lineMn = mn, lineMx = mx;
      if (data.chartType == 'DoubleLinear' && visLines.length == 2) {
        lineMn = line.values.reduce(math.min);
        lineMx = line.values.reduce(math.max);
        if (lineMx == lineMn) lineMx = lineMn + 1;
      }
      final range = lineMx - lineMn;

      final paint = Paint()
        ..color = line.color.withValues(alpha: alpha)
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

    _paintSelectionIndicator(canvas, size, topPad, chartH, mn, mx, visLines);
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

    _paintRulers(canvas, size, topPad, chartH, 0, maxVal);

    for (int i = 0; i < n; i++) {
      final cx = _dataXToPixel(i, n, size.width);
      final groupX = cx - groupWidth / 2 + groupWidth * 0.15;
      for (int li = 0; li < rLines.length; li++) {
        final (line, lineAlpha) = rLines[li];
        if (i >= line.values.length) continue;
        final val = line.values[i];
        final barH = (val / maxVal) * chartH;
        final x = groupX + barWidth * li;
        final rect =
            Rect.fromLTWH(x, topPad + chartH - barH, barWidth, barH);
        final selAlpha =
            (selectedIndex != null && selectedIndex != i) ? 0.4 : 1.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..color =
                line.color.withValues(alpha: selAlpha * lineAlpha),
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

    _paintRulers(canvas, size, topPad, chartH, 0, maxSum);

    for (int i = 0; i < n; i++) {
      final cx = _dataXToPixel(i, n, size.width);
      double cumulative = 0;
      for (final (line, alpha) in rLines) {
        if (i >= line.values.length) continue;
        final val = line.values[i];
        final prevH = (cumulative / maxSum) * chartH;
        cumulative += val;
        final curH = (cumulative / maxSum) * chartH;
        final rect = Rect.fromLTWH(cx - barWidth / 2 + 0.5,
            topPad + chartH - curH, barWidth - 1, curH - prevH);
        canvas.drawRect(
            rect, Paint()..color = line.color.withValues(alpha: alpha));
      }
    }

    _paintDateLabels(canvas, size);
  }

  void _paintStackLinear(Canvas canvas, Size size) {
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
          path, Paint()..color = line.color.withValues(alpha: alpha));
      prevY = curY;
    }

    _paintDateLabels(canvas, size);
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
      rulerCrossfade != old.rulerCrossfade;
}

class _FooterPainter extends CustomPainter {
  final StatsChartData data;
  final bool isDark;
  final double rangeStart;
  final double rangeEnd;
  final Map<String, bool> lineVisible;
  final Color accentColor;

  _FooterPainter({
    required this.data,
    required this.isDark,
    required this.rangeStart,
    required this.rangeEnd,
    required this.lineVisible,
    required this.accentColor,
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
    final dimColor = isDark
        ? const Color(0x88000000)
        : const Color(0x44AAAAAA);

    if (leftX > 0) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, leftX, h), Paint()..color = dimColor);
    }
    if (rightX < w) {
      canvas.drawRect(Rect.fromLTWH(rightX, 0, w - rightX, h),
          Paint()..color = dimColor);
    }

    final handlePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.7);
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
          double mn = double.infinity, mx = double.negativeInfinity;
          for (final v in line.values) {
            if (v < mn) mn = v;
            if (v > mx) mx = v;
          }
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
                ..color = line.color
                ..strokeWidth = 1
                ..style = PaintingStyle.stroke);
        }

      case 'Bar':
        double mx = 0;
        for (final l in lines) {
          for (final v in l.values) {
            if (v > mx) mx = v;
          }
        }
        if (mx == 0) mx = 1;
        final barWidth = w / n / lines.length;
        for (int i = 0; i < n; i++) {
          for (int j = 0; j < lines.length; j++) {
            if (i >= lines[j].values.length) continue;
            final barH = (lines[j].values[i] / mx) * h;
            canvas.drawRect(
              Rect.fromLTWH(
                  w * i / n + barWidth * j, h - barH, barWidth, barH),
              Paint()..color = lines[j].color,
            );
          }
        }

      case 'StackBar':
        double mx = 0;
        for (int i = 0; i < n; i++) {
          double s = 0;
          for (final l in lines) {
            if (i < l.values.length) s += l.values[i];
          }
          if (s > mx) mx = s;
        }
        if (mx == 0) return;
        final barWidth = w / n;
        for (int i = 0; i < n; i++) {
          double cum = 0;
          for (final l in lines) {
            if (i >= l.values.length) continue;
            final prev = cum / mx * h;
            cum += l.values[i];
            final cur = cum / mx * h;
            canvas.drawRect(
              Rect.fromLTWH(barWidth * i, h - cur, barWidth, cur - prev),
              Paint()..color = l.color,
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
          canvas.drawPath(path, Paint()..color = l.color);
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
      lineVisible != old.lineVisible;
}

class _PieChartPainter extends CustomPainter {
  final StatsChartData data;
  final int dataIndex;
  final Map<String, bool> lineVisible;
  final bool isDark;
  final int hoverSlice;
  final double animProgress;

  static const _popOut = 8.0;
  static const _labelFontSize = 20.0;

  _PieChartPainter({
    required this.data,
    required this.dataIndex,
    required this.lineVisible,
    required this.isDark,
    required this.hoverSlice,
    required this.animProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lines =
        data.lines.where((l) => lineVisible[l.id] ?? true).toList();
    if (lines.isEmpty) return;

    double total = 0;
    for (final l in lines) {
      if (dataIndex < l.values.length) total += l.values[dataIndex];
    }
    if (total == 0) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) * 0.75 * animProgress;

    double startAngle = -math.pi / 2;
    for (int i = 0; i < lines.length; i++) {
      final val =
          dataIndex < lines[i].values.length ? lines[i].values[dataIndex] : 0.0;
      final sweep = (val / total) * 2 * math.pi;
      if (sweep <= 0) continue;

      final midAngle = startAngle + sweep / 2;
      double offsetX = 0, offsetY = 0;
      if (i == hoverSlice) {
        offsetX = math.cos(midAngle) * _popOut * animProgress;
        offsetY = math.sin(midAngle) * _popOut * animProgress;
      }

      final rect = Rect.fromCircle(
        center: Offset(cx + offsetX, cy + offsetY),
        radius: radius,
      );
      canvas.drawArc(rect, startAngle, sweep, true, Paint()..color = lines[i].color);

      if (animProgress > 0.5) {
        final pct = (val / total * 100).round();
        if (pct >= 3) {
          final labelR = radius * 0.65;
          final lx = cx + offsetX + math.cos(midAngle) * labelR;
          final ly = cy + offsetY + math.sin(midAngle) * labelR;
          final tp = TextPainter(
            text: TextSpan(
              text: '$pct%',
              style: TextStyle(
                fontSize: _labelFontSize * animProgress,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
        }
      }

      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter old) =>
      dataIndex != old.dataIndex ||
      hoverSlice != old.hoverSlice ||
      animProgress != old.animProgress ||
      lineVisible != old.lineVisible;
}
