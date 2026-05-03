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
          final values = list.skip(1).map((v) => (v as num).toDouble()).toList();
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

class StatsChartWidget extends StatelessWidget {
  final StatsChartData data;
  final ThemeData theme;

  const StatsChartWidget({
    super.key,
    required this.data,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            data.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: CustomPaint(
            size: const Size(double.infinity, 200),
            painter: _ChartPainter(
              data: data,
              isDark: theme.brightness == Brightness.dark,
            ),
          ),
        ),
        if (data.lines.length > 1) _buildLegend(),
      ],
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: data.lines.map((line) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: line.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                line.name,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final StatsChartData data;
  final bool isDark;

  _ChartPainter({required this.data, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final chartType = data.chartType;
    switch (chartType) {
      case 'Linear':
      case 'DoubleLinear':
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

  void _paintLinear(Canvas canvas, Size size) {
    if (data.timestamps.isEmpty) return;

    final gridColor = isDark
        ? const Color(0x1AFFFFFF)
        : const Color(0x1A000000);
    final labelColor = isDark
        ? const Color(0x99FFFFFF)
        : const Color(0x99000000);

    const topPad = 10.0;
    const bottomPad = 24.0;
    final chartH = size.height - topPad - bottomPad;
    final chartW = size.width;

    double globalMin = double.infinity;
    double globalMax = double.negativeInfinity;
    for (final line in data.lines) {
      for (final v in line.values) {
        if (v < globalMin) globalMin = v;
        if (v > globalMax) globalMax = v;
      }
    }
    if (globalMax == globalMin) {
      globalMax = globalMin + 1;
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    const gridLines = 5;
    for (int i = 0; i <= gridLines; i++) {
      final y = topPad + chartH * (1 - i / gridLines);
      canvas.drawLine(Offset(0, y), Offset(chartW, y), gridPaint);

      final val = globalMin + (globalMax - globalMin) * i / gridLines;
      final label = _formatValue(val);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 10, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height - 2));
    }

    final n = data.timestamps.length;
    for (final line in data.lines) {
      if (line.values.length < 2) continue;
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final count = math.min(line.values.length, n);
      for (int i = 0; i < count; i++) {
        final x = chartW * i / (count - 1);
        final yNorm = (line.values[i] - globalMin) / (globalMax - globalMin);
        final y = topPad + chartH * (1 - yNorm);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    _paintDateLabels(canvas, size, bottomPad, labelColor);
  }

  void _paintBar(Canvas canvas, Size size) {
    if (data.timestamps.isEmpty || data.lines.isEmpty) return;

    final labelColor = isDark
        ? const Color(0x99FFFFFF)
        : const Color(0x99000000);

    const topPad = 10.0;
    const bottomPad = 24.0;
    final chartH = size.height - topPad - bottomPad;
    final chartW = size.width;
    final n = data.timestamps.length;
    final barCount = data.lines.length;
    final groupWidth = chartW / n;
    final barWidth = (groupWidth * 0.7) / barCount;

    double globalMax = 0;
    for (final line in data.lines) {
      for (final v in line.values) {
        if (v > globalMax) globalMax = v;
      }
    }
    if (globalMax == 0) globalMax = 1;

    for (int i = 0; i < n; i++) {
      final groupX = groupWidth * i + groupWidth * 0.15;
      for (int l = 0; l < barCount; l++) {
        final line = data.lines[l];
        if (i >= line.values.length) continue;
        final val = line.values[i];
        final barH = (val / globalMax) * chartH;
        final x = groupX + barWidth * l;
        final rect = Rect.fromLTWH(x, topPad + chartH - barH, barWidth, barH);
        final paint = Paint()..color = line.color;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          paint,
        );
      }
    }

    _paintDateLabels(canvas, size, bottomPad, labelColor);
  }

  void _paintStackBar(Canvas canvas, Size size) {
    if (data.timestamps.isEmpty || data.lines.isEmpty) return;

    final labelColor = isDark
        ? const Color(0x99FFFFFF)
        : const Color(0x99000000);

    const topPad = 10.0;
    const bottomPad = 24.0;
    final chartH = size.height - topPad - bottomPad;
    final chartW = size.width;
    final n = data.timestamps.length;
    final barWidth = chartW / n;

    List<double> maxSums = List.filled(n, 0);
    for (int i = 0; i < n; i++) {
      double sum = 0;
      for (final line in data.lines) {
        if (i < line.values.length) sum += line.values[i];
      }
      maxSums[i] = sum;
    }
    final globalMax = maxSums.reduce(math.max);
    if (globalMax == 0) return;

    for (int i = 0; i < n; i++) {
      double cumulative = 0;
      for (final line in data.lines) {
        if (i >= line.values.length) continue;
        final val = line.values[i];
        final prevH = (cumulative / globalMax) * chartH;
        cumulative += val;
        final curH = (cumulative / globalMax) * chartH;
        final rect = Rect.fromLTWH(
          barWidth * i + 0.5,
          topPad + chartH - curH,
          barWidth - 1,
          curH - prevH,
        );
        canvas.drawRect(rect, Paint()..color = line.color);
      }
    }

    _paintDateLabels(canvas, size, bottomPad, labelColor);
  }

  void _paintStackLinear(Canvas canvas, Size size) {
    if (data.timestamps.isEmpty || data.lines.isEmpty) return;

    final labelColor = isDark
        ? const Color(0x99FFFFFF)
        : const Color(0x99000000);

    const topPad = 10.0;
    const bottomPad = 24.0;
    final chartH = size.height - topPad - bottomPad;
    final chartW = size.width;
    final n = data.timestamps.length;

    List<double> sums = List.filled(n, 0);
    for (int i = 0; i < n; i++) {
      for (final line in data.lines) {
        if (i < line.values.length) sums[i] += line.values[i];
      }
    }
    final maxSum = sums.reduce(math.max);
    if (maxSum == 0) return;

    List<double> prevY = List.filled(n, topPad + chartH);

    for (final line in data.lines.reversed) {
      final count = math.min(line.values.length, n);
      final path = Path();
      List<double> curY = List.filled(n, topPad + chartH);

      for (int i = 0; i < count; i++) {
        final x = chartW * i / (count - 1);
        final norm = line.values[i] / (sums[i] == 0 ? 1 : sums[i]);
        final h = norm * chartH;
        curY[i] = prevY[i] - h;
        if (i == 0) {
          path.moveTo(x, curY[i]);
        } else {
          path.lineTo(x, curY[i]);
        }
      }

      for (int i = count - 1; i >= 0; i--) {
        final x = chartW * i / (count - 1);
        path.lineTo(x, prevY[i]);
      }
      path.close();

      canvas.drawPath(path, Paint()..color = line.color);
      prevY = List.from(curY);
    }

    _paintDateLabels(canvas, size, bottomPad, labelColor);
  }

  void _paintDateLabels(Canvas canvas, Size size, double bottomPad, Color labelColor) {
    final n = data.timestamps.length;
    if (n < 2) return;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final labelCount = math.min(6, n);
    for (int i = 0; i < labelCount; i++) {
      final idx = (n * i / labelCount).floor();
      if (idx >= n) continue;
      final ts = data.timestamps[idx];
      final dt = DateTime.fromMillisecondsSinceEpoch(ts.abs() > 1e12 ? ts : ts * 1000);
      final label = '${months[dt.month - 1]} ${dt.day}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 10, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = size.width * i / labelCount;
      tp.paint(canvas, Offset(x, size.height - bottomPad + 6));
    }
  }

  String _formatValue(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) => data != oldDelegate.data;
}
