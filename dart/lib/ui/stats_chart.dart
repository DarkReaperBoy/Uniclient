import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class StatsChartData {
  final String title;
  final String chartType;
  final List<int> timestamps;
  final List<ChartLine> lines;
  final String? zoomToken;

  StatsChartData({
    required this.title,
    required this.chartType,
    required this.timestamps,
    required this.lines,
    this.zoomToken,
  });

  static StatsChartData? fromMap(Map<String, dynamic> map) {
    final title = map['title'] as String? ?? '';
    final chartType = map['type'] as String? ?? 'Linear';
    final dataStr = map['data'] as String?;
    if (dataStr == null || dataStr.isEmpty) return null;

    try {
      final parsed = json.decode(dataStr) as Map<String, dynamic>;
      final columns = parsed['columns'] as List<dynamic>? ?? [];
      final types = (parsed['types'] as Map<String, dynamic>?) ?? {};
      final names = (parsed['names'] as Map<String, dynamic>?) ?? {};
      final colors = (parsed['colors'] as Map<String, dynamic>?) ?? {};

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
          ));
        }
      }

      if (timestamps.isEmpty || lines.isEmpty) return null;

      return StatsChartData(
        title: title,
        chartType: chartType,
        timestamps: timestamps,
        lines: lines,
        zoomToken: map['zoom_token'] as String?,
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

  ChartLine({
    required this.id,
    required this.name,
    required this.color,
    required this.values,
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
const _kTooltipWidth = 160.0;

class StatsChartWidget extends StatefulWidget {
  final StatsChartData data;
  final ThemeData theme;

  const StatsChartWidget({
    super.key,
    required this.data,
    required this.theme,
  });

  @override
  State<StatsChartWidget> createState() => _StatsChartWidgetState();
}

enum _DragMode { none, leftHandle, rightHandle, panCenter }

class _StatsChartWidgetState extends State<StatsChartWidget>
    with SingleTickerProviderStateMixin {
  double _rangeStart = 0.0;
  double _rangeEnd = 1.0;
  int? _selectedIndex;
  late Map<String, bool> _lineVisible;

  _DragMode _dragMode = _DragMode.none;
  double _dragStartX = 0;
  double _rangeStartAtDrag = 0;
  double _rangeEndAtDrag = 0;

  late AnimationController _animController;
  double _animFromStart = 0, _animToStart = 0;
  double _animFromEnd = 0, _animToEnd = 0;

  @override
  void initState() {
    super.initState();
    _lineVisible = {for (final l in widget.data.lines) l.id: true};
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
  }

  @override
  void didUpdateWidget(StatsChartWidget old) {
    super.didUpdateWidget(old);
    if (widget.data.lines.length != old.data.lines.length) {
      _lineVisible = {
        for (final l in widget.data.lines) l.id: _lineVisible[l.id] ?? true
      };
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.white60 : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _kHeaderHeight,
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
                _visibleDateRange(),
                style: TextStyle(fontSize: 11, color: subtitleColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        SizedBox(
          height: _kChartHeight,
          child: LayoutBuilder(builder: (ctx, box) {
            final w = box.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
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
                    ),
                  ),
                ),
                if (_selectedIndex != null) _buildTooltip(w, isDark),
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
              spacing: 8,
              runSpacing: 6,
              children: widget.data.lines
                  .map((line) => _FilterButton(
                        label: line.name,
                        color: line.color,
                        active: _lineVisible[line.id] ?? true,
                        isDark: isDark,
                        onTap: () => _toggleLine(line.id),
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
    final dateStr =
        '${_weekdays[dt.weekday - 1]}, ${_months[dt.month - 1]} ${dt.day}';

    final visibleLines =
        widget.data.lines.where((l) => _lineVisible[l.id] ?? true).toList();

    const gap = 12.0;
    var left = xPx - _kTooltipWidth - gap;
    if (left < 0) left = xPx + gap;
    if (left + _kTooltipWidth > chartWidth) left = 0;

    return Positioned(
      left: left,
      top: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: _kTooltipWidth,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 11),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(_kTooltipRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dateStr,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fgColor)),
                const SizedBox(height: 6),
                for (var i = 0; i < visibleLines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                          child: Text(visibleLines[i].name,
                              style: TextStyle(fontSize: 12, color: subColor),
                              overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Text(
                        _formatValue(idx < visibleLines[i].values.length
                            ? visibleLines[i].values[idx]
                            : 0),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: visibleLines[i].color),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onChartTap(TapDownDetails details, double chartWidth) {
    final span = _rangeEnd - _rangeStart;
    if (span <= 0) return;
    final xFrac =
        _rangeStart + (details.localPosition.dx / chartWidth) * span;
    final n = widget.data.timestamps.length;
    final idx = (xFrac * (n - 1)).round().clamp(0, n - 1);
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

  void _toggleLine(String lineId) {
    final current = _lineVisible[lineId] ?? true;
    if (current && _lineVisible.values.where((v) => v).length <= 1) return;
    setState(() => _lineVisible[lineId] = !current);
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

  const _FilterButton({
    required this.label,
    required this.color,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
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
              child: active
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : const SizedBox.shrink(),
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
    );
  }
}

class _ChartAreaPainter extends CustomPainter {
  final StatsChartData data;
  final bool isDark;
  final double rangeStart;
  final double rangeEnd;
  final int? selectedIndex;
  final Map<String, bool> lineVisible;

  _ChartAreaPainter({
    required this.data,
    required this.isDark,
    required this.rangeStart,
    required this.rangeEnd,
    this.selectedIndex,
    required this.lineVisible,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  List<ChartLine> get _visibleLines =>
      data.lines.where((l) => lineVisible[l.id] ?? true).toList();

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
    final gridColor = isDark
        ? const Color(0x0FFFFFFF)
        : const Color(0x0F000000);
    final labelColor = isDark
        ? const Color(0x99FFFFFF)
        : const Color(0x99000000);
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
    final labelColor = isDark
        ? const Color(0x99FFFFFF)
        : const Color(0x99000000);

    final visibleCount = ((rangeEnd - rangeStart) * n).round().clamp(2, n);
    final labelCount = math.min(6, visibleCount);
    final step = visibleCount / labelCount;
    final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);

    for (int i = 0; i < labelCount; i++) {
      final idx = (si + (step * i).round()).clamp(0, n - 1);
      final ts = data.timestamps[idx];
      final dt = DateTime.fromMillisecondsSinceEpoch(
          ts.abs() > 1e12 ? ts : ts * 1000);
      final label = '${_months[dt.month - 1]} ${dt.day}';
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(fontSize: 10, color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = _dataXToPixel(idx, n, size.width);
      final px = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(px, size.height - _kBottomCaptionHeight));
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
    final lines = _visibleLines;
    if (lines.isEmpty || data.timestamps.isEmpty) return;

    const topPad = 10.0;
    final chartH = size.height - topPad - _kBottomCaptionHeight -
        _kBottomCaptionSkip;
    final n = data.timestamps.length;
    final (mn, mx) = _visibleYRange(lines);

    _paintRulers(canvas, size, topPad, chartH, mn, mx);

    for (final line in lines) {
      double lineMn = mn, lineMx = mx;
      if (data.chartType == 'DoubleLinear' && lines.length == 2) {
        lineMn = line.values.reduce(math.min);
        lineMx = line.values.reduce(math.max);
        if (lineMx == lineMn) lineMx = lineMn + 1;
      }
      final range = lineMx - lineMn;

      final paint = Paint()
        ..color = line.color
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

    _paintSelectionIndicator(canvas, size, topPad, chartH, mn, mx, lines);
    _paintDateLabels(canvas, size);
  }

  void _paintBar(Canvas canvas, Size size) {
    final lines = _visibleLines;
    if (lines.isEmpty || data.timestamps.isEmpty) return;

    const topPad = 10.0;
    final chartH = size.height - topPad - _kBottomCaptionHeight -
        _kBottomCaptionSkip;
    final n = data.timestamps.length;
    final span = rangeEnd - rangeStart;
    if (span <= 0) return;

    final visibleN = (span * n).ceil().clamp(1, n);
    final groupWidth = size.width / visibleN;
    final barWidth = (groupWidth * 0.7) / lines.length;

    double maxVal = 0;
    final si = (rangeStart * (n - 1)).floor().clamp(0, n - 1);
    final ei = (rangeEnd * (n - 1)).ceil().clamp(0, n - 1);
    for (final l in lines) {
      for (int i = si; i <= ei && i < l.values.length; i++) {
        if (l.values[i] > maxVal) maxVal = l.values[i];
      }
    }
    if (maxVal == 0) maxVal = 1;

    _paintRulers(canvas, size, topPad, chartH, 0, maxVal);

    for (int i = 0; i < n; i++) {
      final cx = _dataXToPixel(i, n, size.width);
      final groupX = cx - groupWidth / 2 + groupWidth * 0.15;
      for (int li = 0; li < lines.length; li++) {
        if (i >= lines[li].values.length) continue;
        final val = lines[li].values[i];
        final barH = (val / maxVal) * chartH;
        final x = groupX + barWidth * li;
        final rect =
            Rect.fromLTWH(x, topPad + chartH - barH, barWidth, barH);
        final alpha =
            (selectedIndex != null && selectedIndex != i) ? 0.4 : 1.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = lines[li].color.withValues(alpha: alpha),
        );
      }
    }

    _paintDateLabels(canvas, size);
  }

  void _paintStackBar(Canvas canvas, Size size) {
    final lines = _visibleLines;
    if (lines.isEmpty || data.timestamps.isEmpty) return;

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
      for (final l in lines) {
        if (i < l.values.length) sum += l.values[i];
      }
      if (sum > maxSum) maxSum = sum;
    }
    if (maxSum == 0) maxSum = 1;

    _paintRulers(canvas, size, topPad, chartH, 0, maxSum);

    for (int i = 0; i < n; i++) {
      final cx = _dataXToPixel(i, n, size.width);
      double cumulative = 0;
      for (final line in lines) {
        if (i >= line.values.length) continue;
        final val = line.values[i];
        final prevH = (cumulative / maxSum) * chartH;
        cumulative += val;
        final curH = (cumulative / maxSum) * chartH;
        final rect = Rect.fromLTWH(cx - barWidth / 2 + 0.5,
            topPad + chartH - curH, barWidth - 1, curH - prevH);
        canvas.drawRect(rect, Paint()..color = line.color);
      }
    }

    _paintDateLabels(canvas, size);
  }

  void _paintStackLinear(Canvas canvas, Size size) {
    final lines = _visibleLines;
    if (lines.isEmpty || data.timestamps.isEmpty) return;

    const topPad = 10.0;
    final chartH = size.height - topPad - _kBottomCaptionHeight -
        _kBottomCaptionSkip;
    final n = data.timestamps.length;

    final sums = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      for (final l in lines) {
        if (i < l.values.length) sums[i] += l.values[i];
      }
    }

    var prevY = List<double>.filled(n, topPad + chartH);
    for (final line in lines.reversed) {
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
      canvas.drawPath(path, Paint()..color = line.color);
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
      lineVisible != old.lineVisible;
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
