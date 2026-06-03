import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'confirm_box.dart';
import 'popup_menu.dart';


const int kScheduledUntilOnlineTimestamp = 0x7FFFFFFE;

const double _cellW = 48;
const double _cellH = 40;
const double _cellInner = 34;
// AyuGram innerSkip = (cellSize - cellInner) / 2 (calendar_box.cpp:793-794)
const double _cellInnerSkipLeft = (_cellW - _cellInner) / 2;
const double _cellInnerSkipTop = (_cellH - _cellInner) / 2;
const double _daysRowH = 40;
const double _calPadH = 14;
const double _scheduleHeight = 95;
const double _scheduleDateWidth = 136;
const double _scheduleTimeWidth = 72;
const double _scheduleAtSkip = 24;
const double _scheduleDateTop = 38;
const double _scheduleAtTop = 42;
const int _kMinimalSchedule = 10;
const int _kJumpDelay = 700;

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _weekDayNames = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

List<String> _localizedWeekDays() {
  final firstDay = _localeFirstDayOfWeek();
  return List.generate(7, (i) => _weekDayNames[((firstDay - 1) + i) % 7]);
}

int _localeFirstDayOfWeek() {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  const sundayFirst = {'US', 'CA', 'JP', 'IL', 'KR', 'TW', 'PH', 'SA', 'AE', 'BH', 'EG', 'IQ', 'JO', 'KW', 'LY', 'OM', 'QA', 'SY', 'YE'};
  if (sundayFirst.contains(locale.countryCode)) return 7;
  return 1;
}

int _dayOfWeekIndex(int dartWeekday) {
  final first = _localeFirstDayOfWeek();
  return (7 + dartWeekday - first) % 7;
}

const Map<int, String> _repeatPeriods = {
  0: 'Never',
  86400: 'Daily',
  604800: 'Weekly',
  1209600: 'Biweekly',
  2592000: 'Monthly',
  7862400: 'Every 3 months',
  15724800: 'Every 6 months',
  31536000: 'Yearly',
};

// ─── CalendarBox — spec §36.6.1 ─────────────────────────────────────────────

class CalendarDateRange {
  final DateTime start;
  final DateTime end;
  const CalendarDateRange({required this.start, required this.end});
}

typedef CalendarImageSetter = void Function(DateTime date, Uint8List imageBytes);
typedef DynamicImageForDate = void Function(DateTime date, CalendarImageSetter setter);

Future<DateTime?> showCalendarBox(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? minDate,
  DateTime? maxDate,
  DateTime? selectedDate,
  bool allowsSelection = false,
  ValueChanged<CalendarDateRange>? onRangeSelected,
  DynamicImageForDate? dynamicImageForDate,
}) {
  return showTelegramBox<DateTime>(
    context: context,
    builder: (ctx) => _CalendarBoxWidget(
      initialDate: initialDate,
      minDate: minDate ?? DateTime(2013),
      maxDate: maxDate ?? DateTime(2036, 12, 31),
      selectedDate: selectedDate,
      allowsSelection: allowsSelection,
      onRangeSelected: onRangeSelected,
      dynamicImageForDate: dynamicImageForDate,
    ),
  );
}

class _CalendarBoxWidget extends StatefulWidget {
  final DateTime? initialDate;
  final DateTime minDate;
  final DateTime maxDate;
  final DateTime? selectedDate;
  final bool allowsSelection;
  final ValueChanged<CalendarDateRange>? onRangeSelected;
  final DynamicImageForDate? dynamicImageForDate;

  const _CalendarBoxWidget({
    this.initialDate,
    required this.minDate,
    required this.maxDate,
    this.selectedDate,
    this.allowsSelection = false,
    this.onRangeSelected,
    this.dynamicImageForDate,
  });

  @override
  State<_CalendarBoxWidget> createState() => _CalendarBoxWidgetState();
}

class _CalendarBoxWidgetState extends State<_CalendarBoxWidget>
    with TickerProviderStateMixin {
  late final ScrollController _scrollController;
  late int _gridStartYear, _gridStartMonth, _gridStartDay;
  late int _totalWeeks;
  late int _visibleYear;
  late int _visibleMonth;

  DateTime? _selected;
  Timer? _jumpTimer;

  bool _selectionMode = false;
  DateTime? _selectionStart;
  DateTime? _selectionEnd;
  // Fixed anchor of the active range (calendar_box.cpp startSelection),
  // separate from start/end so drag & shift+click extend from the origin.
  DateTime? _selectionAnchor;
  // AyuGram _twoPressSelectionStarted: a completed selection is restarted by
  // the next plain tap instead of being extended (calendar_box.cpp:996).
  bool _twoPressSelectionStarted = false;
  bool _selectionDragActive = false;
  final GlobalKey _gridKey = GlobalKey();

  final Map<DateTime, _DynamicImageState> _dynamicImages = {};
  final List<String> _loadedMonthKeys = [];

  static const double _scrollViewportHeight = 6 * _cellH;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedDate;
    final base = widget.initialDate ?? widget.selectedDate ?? DateTime.now();
    _visibleYear = base.year;
    _visibleMonth = base.month;
    _computeGrid();
    final initialWeek = _weekIndexForMonth(_visibleYear, _visibleMonth);
    _scrollController = ScrollController(initialScrollOffset: initialWeek * _cellH);
    _scrollController.addListener(_onScroll);
    _loadDynamicImages();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _jumpTimer?.cancel();
    for (final s in _dynamicImages.values) {
      s.fadeController?.dispose();
    }
    super.dispose();
  }

  void _computeGrid() {
    final firstOfMinMonth = DateTime(widget.minDate.year, widget.minDate.month, 1);
    final firstDow = _dayOfWeekIndex(firstOfMinMonth.weekday);
    final gs = DateTime(widget.minDate.year, widget.minDate.month, 1 - firstDow);
    _gridStartYear = gs.year;
    _gridStartMonth = gs.month;
    _gridStartDay = gs.day;
    final lastOfMaxMonth = DateTime(widget.maxDate.year, widget.maxDate.month + 1, 0);
    final lastDow = _dayOfWeekIndex(lastOfMaxMonth.weekday);
    final ge = DateTime(lastOfMaxMonth.year, lastOfMaxMonth.month, lastOfMaxMonth.day + (6 - lastDow));
    final gsUtc = DateTime.utc(_gridStartYear, _gridStartMonth, _gridStartDay);
    final geUtc = DateTime.utc(ge.year, ge.month, ge.day);
    _totalWeeks = geUtc.difference(gsUtc).inDays ~/ 7;
  }

  DateTime _dateForGridIndex(int weekIndex, int dayInWeek) {
    return DateTime(_gridStartYear, _gridStartMonth, _gridStartDay + weekIndex * 7 + dayInWeek);
  }

  int _weekIndexForMonth(int year, int month) {
    final firstOfMonth = DateTime(year, month, 1);
    final dayOffset = _dayOfWeekIndex(firstOfMonth.weekday);
    final ws = DateTime(year, month, 1 - dayOffset);
    final gsUtc = DateTime.utc(_gridStartYear, _gridStartMonth, _gridStartDay);
    final wsUtc = DateTime.utc(ws.year, ws.month, ws.day);
    return wsUtc.difference(gsUtc).inDays ~/ 7;
  }

  void _onScroll() {
    final centerY = _scrollController.offset + _scrollViewportHeight / 2;
    final centerWeek = (centerY / _cellH).floor().clamp(0, _totalWeeks - 1);
    final centerDate = _dateForGridIndex(centerWeek, 3);
    if (centerDate.year != _visibleYear || centerDate.month != _visibleMonth) {
      setState(() {
        _visibleYear = centerDate.year;
        _visibleMonth = centerDate.month;
      });
      _loadDynamicImages();
    }
  }

  void _scrollToMonth(int year, int month, {bool animate = true}) {
    final weekIdx = _weekIndexForMonth(year, month);
    final target = weekIdx * _cellH;
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final clamped = target.clamp(0.0, max);
    if (animate) {
      _scrollController.animateTo(clamped, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  void _loadDynamicImages() {
    if (widget.dynamicImageForDate == null) return;
    final key = '$_visibleYear-$_visibleMonth';
    if (_loadedMonthKeys.contains(key)) return;
    _loadedMonthKeys.add(key);
    while (_loadedMonthKeys.length > 3) {
      final evictKey = _loadedMonthKeys.removeAt(0);
      final parts = evictKey.split('-');
      final ey = int.parse(parts[0]);
      final em = int.parse(parts[1]);
      _dynamicImages.removeWhere((k, state) {
        if (k.year == ey && k.month == em) {
          state.fadeController?.dispose();
          return true;
        }
        return false;
      });
    }
    final daysInMonth = DateTime(_visibleYear, _visibleMonth + 1, 0).day;
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_visibleYear, _visibleMonth, d);
      final dateKey = DateTime(date.year, date.month, date.day);
      if (_dynamicImages.containsKey(dateKey)) continue;
      _dynamicImages[dateKey] = _DynamicImageState();
      widget.dynamicImageForDate!(date, (rDate, bytes) {
        if (!mounted) return;
        final rKey = DateTime(rDate.year, rDate.month, rDate.day);
        final state = _dynamicImages[rKey];
        if (state == null) return;
        state.imageBytes = bytes;
        state.fadeController = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..forward();
        setState(() {});
      });
    }
  }

  bool _canGoPrev() {
    return _visibleYear > widget.minDate.year ||
        (_visibleYear == widget.minDate.year && _visibleMonth > widget.minDate.month);
  }

  bool _canGoNext() {
    return _visibleYear < widget.maxDate.year ||
        (_visibleYear == widget.maxDate.year && _visibleMonth < widget.maxDate.month);
  }

  void _goPrevMonth() {
    if (!_canGoPrev()) return;
    var y = _visibleYear, m = _visibleMonth - 1;
    if (m < 1) { m = 12; y--; }
    _scrollToMonth(y, m);
  }

  void _goNextMonth() {
    if (!_canGoNext()) return;
    var y = _visibleYear, m = _visibleMonth + 1;
    if (m > 12) { m = 1; y++; }
    _scrollToMonth(y, m);
  }

  void _jumpToMin() {
    _scrollToMonth(widget.minDate.year, widget.minDate.month);
  }

  void _jumpToMax() {
    _scrollToMonth(widget.maxDate.year, widget.maxDate.month);
  }

  void _startJump(bool isPrev) {
    _jumpTimer?.cancel();
    _jumpTimer = Timer(const Duration(milliseconds: _kJumpDelay), () {
      if (isPrev) {
        _jumpToMin();
      } else {
        _jumpToMax();
      }
    });
  }

  void _cancelJump() {
    _jumpTimer?.cancel();
    _jumpTimer = null;
  }

  bool _isDayDisabled(DateTime date) {
    final dayOnly = DateTime(date.year, date.month, date.day);
    final minOnly =
        DateTime(widget.minDate.year, widget.minDate.month, widget.minDate.day);
    final maxOnly =
        DateTime(widget.maxDate.year, widget.maxDate.month, widget.maxDate.day);
    return dayOnly.isBefore(minOnly) || dayOnly.isAfter(maxOnly);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Non-selection mode: a plain tap on an enabled day picks it.
  void _pickDate(DateTime date) {
    if (_isDayDisabled(date)) return;
    Navigator.of(context).pop(date);
  }

  // Maps a global pointer position onto a calendar day (col 0-6, week row),
  // mirroring CalendarBox::Inner mouse handling which works in cell units.
  DateTime? _dateAtGlobal(Offset globalPos) {
    final ctx = _gridKey.currentContext;
    if (ctx == null || !_scrollController.hasClients) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(globalPos);
    final col = (local.dx / _cellW).floor().clamp(0, 6);
    final contentY = _scrollController.offset + local.dy;
    final weekIndex = (contentY / _cellH).floor().clamp(0, _totalWeeks - 1);
    return _dateForGridIndex(weekIndex, col);
  }

  // CalendarBox::Inner::mousePressEvent (calendar_box.cpp:990-1006): start a
  // fresh selection, OR extend the existing one when Shift is held or the
  // current selection is still a single collapsed day from the previous press.
  void _onSelectionPointerDown(Offset globalPos) {
    final date = _dateAtGlobal(globalPos);
    if (date == null || _isDayDisabled(date)) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final hasSelection = _selectionStart != null && _selectionEnd != null;
    final collapsed = hasSelection && _isSameDay(_selectionStart!, _selectionEnd!);
    if (hasSelection && (shift || (_twoPressSelectionStarted && collapsed))) {
      _updateSelection(date);
      _twoPressSelectionStarted = false;
    } else {
      _startSelection(date);
      _twoPressSelectionStarted = true;
    }
    _selectionDragActive = true;
  }

  // CalendarBox::Inner::mouseMoveEvent (calendar_box.cpp:914-927): drag extends
  // the range while the button is held.
  void _onSelectionPointerMove(Offset globalPos) {
    if (!_selectionDragActive) return;
    final date = _dateAtGlobal(globalPos);
    if (date == null) return;
    _updateSelection(date);
  }

  void _onSelectionPointerUp() {
    _selectionDragActive = false;
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectionStart = null;
        _selectionEnd = null;
        _selectionAnchor = null;
        _twoPressSelectionStarted = false;
        _selectionDragActive = false;
      }
    });
  }

  void _startSelection(DateTime date) {
    setState(() {
      _selectionAnchor = date;
      _selectionStart = date;
      _selectionEnd = date;
    });
    _notifyRangeSelection();
  }

  void _updateSelection(DateTime date) {
    final anchor = _selectionAnchor ?? _selectionStart;
    if (anchor == null) return;
    DateTime min, max;
    if (date.isBefore(anchor)) {
      min = date;
      max = anchor;
    } else {
      min = anchor;
      max = date;
    }
    final minOnly = DateTime(widget.minDate.year, widget.minDate.month, widget.minDate.day);
    final maxOnly = DateTime(widget.maxDate.year, widget.maxDate.month, widget.maxDate.day);
    if (min.isBefore(minOnly)) min = minOnly;
    if (max.isAfter(maxOnly)) max = maxOnly;
    setState(() {
      _selectionStart = min;
      _selectionEnd = max;
    });
    _notifyRangeSelection();
  }

  void _notifyRangeSelection() {
    if (_selectionStart != null && _selectionEnd != null && widget.onRangeSelected != null) {
      widget.onRangeSelected!(CalendarDateRange(start: _selectionStart!, end: _selectionEnd!));
    }
  }

  bool _isInSelectionRange(DateTime date) {
    if (_selectionStart == null || _selectionEnd == null) return false;
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(_selectionStart!.year, _selectionStart!.month, _selectionStart!.day);
    final e = DateTime(_selectionEnd!.year, _selectionEnd!.month, _selectionEnd!.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _goPrevMonth();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown) {
      _goNextMonth();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.home) {
      _jumpToMin();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.end) {
      _jumpToMax();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      if (_selectionMode) {
        _toggleSelectionMode();
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showMonthYearPicker() {
    showTelegramBox<DateTime>(
      context: context,
      builder: (ctx) => _MonthYearPickerDialog(
        currentYear: _visibleYear,
        currentMonth: _visibleMonth,
        minDate: widget.minDate,
        maxDate: widget.maxDate,
      ),
    ).then((result) {
      if (result != null && mounted) {
        _scrollToMonth(result.year, result.month);
      }
    });
  }

  int get _selectionDayCount {
    if (_selectionStart == null || _selectionEnd == null) return 0;
    return _selectionEnd!.difference(_selectionStart!).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFg = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextFg =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentFg =
        context.palette.dialogsBgActive;
    // Range selection pill (calendar_box.cpp:802 activeButtonBg / activeButtonFg).
    final rangeBg = context.palette.activeButtonBg;
    final rangeFg = context.palette.activeButtonFg;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final disabledFg = subtextFg.withValues(alpha: 0.4);
    final weekDays = _localizedWeekDays();

    // Title: month/year in normal mode, selection count in selection mode
    Widget titleContent;
    if (_selectionMode) {
      final count = _selectionDayCount;
      titleContent = Text(
        count == 0 ? 'Select days' : '$count days',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textFg),
      );
    } else {
      titleContent = GestureDetector(
        onTap: _showMonthYearPicker,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(8, 10),
              painter: _TriangleArrowPainter(color: subtextFg),
            ),
            const SizedBox(width: 4),
            Text(
              '${_monthNames[_visibleMonth - 1]} $_visibleYear',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: textFg,
              ),
            ),
          ],
        ),
      );
    }

    // Buttons: AyuGram createButtons() logic
    final List<TelegramBoxButton> buttons;
    if (!widget.allowsSelection) {
      buttons = [
        TelegramBoxButton(text: 'Close', onPressed: () => Navigator.of(context).pop()),
      ];
    } else if (!_selectionMode) {
      buttons = [
        TelegramBoxButton(text: 'Select days', onPressed: _toggleSelectionMode),
        TelegramBoxButton(text: 'Close', onPressed: () => Navigator.of(context).pop()),
      ];
    } else {
      buttons = [
        TelegramBoxButton(text: 'Cancel', onPressed: _toggleSelectionMode),
      ];
    }

    // Floating date service bubble colors
    final serviceBubbleBg = isDark ? const Color(0x7F000000) : const Color(0xB2FFFFFF);
    final serviceBubbleFg = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

    return TelegramBox(
      wide: true,
      title: null,
      titleWidget: titleContent,
      titleTrailing: _selectionMode ? null : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavArrow(
            // AyuGram calendarPrevious = "calendar_down-flip_vertical" (up)
            // for the vertically-scrolling calendar (boxes.style:419).
            icon: Icons.keyboard_arrow_up,
            enabled: _canGoPrev(),
            color: textFg,
            disabledColor: subtextFg,
            tooltip: 'To the beginning',
            onTap: () {
              _cancelJump();
              _goPrevMonth();
            },
            onPointerDown: () => _startJump(true),
            onPointerUp: _cancelJump,
          ),
          _NavArrow(
            // AyuGram calendarNext = "calendar_down" (down chevron)
            // (boxes.style:428).
            icon: Icons.keyboard_arrow_down,
            enabled: _canGoNext(),
            color: textFg,
            disabledColor: subtextFg,
            tooltip: 'To the end',
            onTap: () {
              _cancelJump();
              _goNextMonth();
            },
            onPointerDown: () => _startJump(false),
            onPointerUp: _cancelJump,
          ),
          const SizedBox(width: 4),
        ],
      ),
      content: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _calPadH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Weekday header + floating date overlay
              Stack(
                children: [
                  SizedBox(
                    height: _daysRowH,
                    child: Row(
                      children: weekDays.map((d) {
                        return SizedBox(
                          width: _cellW,
                          height: _daysRowH,
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 13,
                                color: subtextFg,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_selectionMode)
                    Positioned.fill(
                      child: Center(
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: serviceBubbleBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_monthNames[_visibleMonth - 1]} $_visibleYear',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: serviceBubbleFg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Vertically scrollable all-months grid. The Listener captures
              // mouse-drag selection (mouse is not a scroll-drag device on
              // desktop, so wheel scrolling via the controller still works).
              Listener(
                onPointerDown:
                    _selectionMode ? (e) => _onSelectionPointerDown(e.position) : null,
                onPointerMove:
                    _selectionMode ? (e) => _onSelectionPointerMove(e.position) : null,
                onPointerUp:
                    _selectionMode ? (_) => _onSelectionPointerUp() : null,
                child: SizedBox(
                  key: _gridKey,
                  height: _scrollViewportHeight,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _totalWeeks,
                    itemExtent: _cellH,
                    itemBuilder: (ctx, weekIndex) => _buildWeekRow(
                      weekIndex, textFg, subtextFg, accentFg, rangeBg, rangeFg,
                      hoverBg, disabledFg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      buttons: buttons,
    );
  }

  Widget _buildWeekRow(
    int weekIndex,
    Color textFg,
    Color subtextFg,
    Color accentFg,
    Color rangeBg,
    Color rangeFg,
    Color hoverBg,
    Color disabledFg,
  ) {
    // Find the contiguous in-range span within this row so it can be painted
    // as one continuous rounded pill (calendar_box.cpp:800-820) rather than
    // a string of separate circles.
    int? firstSel, lastSel;
    if (_selectionMode) {
      for (var c = 0; c < 7; c++) {
        if (_isInSelectionRange(_dateForGridIndex(weekIndex, c))) {
          firstSel ??= c;
          lastSel = c;
        }
      }
    }

    final row = Row(
      children: List.generate(7, (dayInWeek) {
        final date = _dateForGridIndex(weekIndex, dayInWeek);
        final isCurrentMonth = date.year == _visibleYear && date.month == _visibleMonth;
        final isDisabled = _isDayDisabled(date);
        final isHighlighted = !_selectionMode && _selected != null &&
            _selected!.year == date.year &&
            _selected!.month == date.month &&
            _selected!.day == date.day;
        final isInRange = _isInSelectionRange(date);
        final dateKey = DateTime(date.year, date.month, date.day);
        final dynImage = _dynamicImages[dateKey];

        // AyuGram paints grayed-out (adjacent-month) days in full-opacity
        // windowSubTextFg (boxes.style:480 dayTextGrayedOutColor).
        final effectiveTextColor = isCurrentMonth ? textFg : subtextFg;

        return _DayCell(
          day: date.day,
          isSelected: isHighlighted,
          isFocused: false,
          isDisabled: isDisabled,
          isInRange: isInRange,
          selectionMode: _selectionMode,
          dynamicImageBytes: dynImage?.imageBytes,
          dynamicImageOpacity: dynImage?.fadeController?.value ?? (dynImage?.imageBytes != null ? 1.0 : 0.0),
          textColor: effectiveTextColor,
          accentColor: accentFg,
          rangeTextColor: rangeFg,
          hoverColor: hoverBg,
          disabledColor: disabledFg,
          onTap: (isDisabled || _selectionMode) ? null : () => _pickDate(date),
        );
      }),
    );

    if (firstSel == null) return row;

    final count = lastSel! - firstSel + 1;
    return Stack(
      children: [
        // Continuous range pill spanning the selected columns of this row.
        Positioned(
          left: firstSel * _cellW + _cellInnerSkipLeft - 1,
          top: _cellInnerSkipTop - 1,
          child: Container(
            width: (count - 1) * _cellW + 2 + _cellInner,
            height: _cellInner + 2,
            decoration: BoxDecoration(
              color: rangeBg,
              borderRadius: BorderRadius.circular(_cellInner / 2 + 1),
            ),
          ),
        ),
        row,
      ],
    );
  }
}

// ─── MonthYearPicker — dual drum picker for jumping to any month/year ──────

class _MonthYearPickerDialog extends StatefulWidget {
  final int currentYear;
  final int currentMonth;
  final DateTime minDate;
  final DateTime maxDate;

  const _MonthYearPickerDialog({
    required this.currentYear,
    required this.currentMonth,
    required this.minDate,
    required this.maxDate,
  });

  @override
  State<_MonthYearPickerDialog> createState() => _MonthYearPickerDialogState();
}

class _MonthYearPickerDialogState extends State<_MonthYearPickerDialog>
    with TickerProviderStateMixin {
  late int _selectedMonth;
  late int _selectedYear;

  late double _monthOffset;
  late AnimationController _monthSnapCtrl;
  double _monthSnapFrom = 0;
  double _monthSnapTo = 0;

  late double _yearOffset;
  late AnimationController _yearSnapCtrl;
  double _yearSnapFrom = 0;
  double _yearSnapTo = 0;

  bool _yearColumnFocused = false;

  static const double _itemHeight = 40.0;
  static const double _drumHeight = _itemHeight * 5;
  static const double _centerY = (_drumHeight - _itemHeight) / 2;

  int get _minMonth {
    if (_selectedYear == widget.minDate.year) return widget.minDate.month;
    return 1;
  }

  int get _maxMonth {
    if (_selectedYear == widget.maxDate.year) return widget.maxDate.month;
    return 12;
  }

  int get _validMonthCount => _maxMonth - _minMonth + 1;

  List<int> get _years {
    final result = <int>[];
    for (var y = widget.minDate.year; y <= widget.maxDate.year; y++) {
      result.add(y);
    }
    return result;
  }

  double get _monthMaxOffset => (_validMonthCount - 1) * _itemHeight;
  double get _yearMaxOffset => (_years.length - 1) * _itemHeight;
  int get _yearIndex => _years.indexOf(_selectedYear).clamp(0, _years.length - 1);

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.currentMonth;
    _selectedYear = widget.currentYear;
    _monthOffset = (_selectedMonth - _minMonth) * _itemHeight;

    final years = _years;
    final yearIdx = years.indexOf(_selectedYear);
    _yearOffset = (yearIdx >= 0 ? yearIdx : 0) * _itemHeight;

    _monthSnapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _monthOffset = _monthSnapFrom +
              (_monthSnapTo - _monthSnapFrom) *
                  Curves.easeOutCubic.transform(_monthSnapCtrl.value);
          _selectedMonth =
              (_monthOffset / _itemHeight).round().clamp(0, _validMonthCount - 1) + _minMonth;
        });
      });

    _yearSnapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final years = _years;
        setState(() {
          _yearOffset = _yearSnapFrom +
              (_yearSnapTo - _yearSnapFrom) *
                  Curves.easeOutCubic.transform(_yearSnapCtrl.value);
          final idx =
              (_yearOffset / _itemHeight).round().clamp(0, years.length - 1);
          final prevYear = _selectedYear;
          _selectedYear = years[idx];
          if (_selectedYear != prevYear) {
            _selectedMonth = _clampMonth(_selectedMonth, _selectedYear);
            final clampedIdx = (_selectedMonth - _minMonth).clamp(0, _validMonthCount - 1);
            _monthOffset = clampedIdx * _itemHeight;
          }
        });
      });
  }

  @override
  void dispose() {
    _monthSnapCtrl.dispose();
    _yearSnapCtrl.dispose();
    super.dispose();
  }

  int _clampMonth(int month, int year) {
    if (year == widget.minDate.year && month < widget.minDate.month) {
      return widget.minDate.month;
    }
    if (year == widget.maxDate.year && month > widget.maxDate.month) {
      return widget.maxDate.month;
    }
    return month;
  }

  void _snapMonth() {
    final target = (_monthOffset / _itemHeight).round() * _itemHeight;
    _monthSnapFrom = _monthOffset;
    _monthSnapTo = target.clamp(0.0, _monthMaxOffset);
    _monthSnapCtrl.forward(from: 0);
  }

  void _snapYear() {
    final target = (_yearOffset / _itemHeight).round() * _itemHeight;
    _yearSnapFrom = _yearOffset;
    _yearSnapTo = target.clamp(0.0, _yearMaxOffset);
    _yearSnapCtrl.forward(from: 0);
  }

  void _goToMonthIndex(int index) {
    _monthSnapFrom = _monthOffset;
    _monthSnapTo = index.clamp(0, _validMonthCount - 1) * _itemHeight;
    _monthSnapCtrl.forward(from: 0);
  }

  void _goToYearIndex(int index) {
    _yearSnapFrom = _yearOffset;
    _yearSnapTo = index.clamp(0, _years.length - 1) * _itemHeight;
    _yearSnapCtrl.forward(from: 0);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_yearColumnFocused) {
        _goToYearIndex(_yearIndex - 1);
      } else {
        _goToMonthIndex(_selectedMonth - 2);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_yearColumnFocused) {
        _goToYearIndex(_yearIndex + 1);
      } else {
        _goToMonthIndex(_selectedMonth);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _yearColumnFocused = false);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _yearColumnFocused = true);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFg = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final dimFg = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    // Selection band lines use activeLineFg (calendar_box.cpp:174), not windowBgActive.
    final bandColor = context.palette.activeLineFg;
    final years = _years;

    return TelegramBox(
      title: null,
      scrollableContent: false,
      onKeyEvent: _handleKey,
      content: SizedBox(
        height: _drumHeight,
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: _DrumColumn(
                    offset: _monthOffset,
                    maxOffset: _monthMaxOffset,
                    itemCount: _validMonthCount,
                    selectedIndex: _selectedMonth - _minMonth,
                    labelBuilder: (i) => _monthNames[i + _minMonth - 1],
                    textFg: textFg,
                    dimFg: dimFg,
                    onScroll: (delta) {
                      _monthSnapCtrl.stop();
                      setState(() {
                        _monthOffset =
                            (_monthOffset + delta).clamp(0.0, _monthMaxOffset);
                        _selectedMonth = (_monthOffset / _itemHeight)
                                .round()
                                .clamp(0, _validMonthCount - 1) +
                            _minMonth;
                      });
                    },
                    onScrollEnd: _snapMonth,
                  ),
                ),
                Expanded(
                  child: _DrumColumn(
                    offset: _yearOffset,
                    maxOffset: _yearMaxOffset,
                    itemCount: years.length,
                    selectedIndex: _yearIndex,
                    labelBuilder: (i) => '${years[i]}',
                    textFg: textFg,
                    dimFg: dimFg,
                    onScroll: (delta) {
                      _yearSnapCtrl.stop();
                      setState(() {
                        _yearOffset =
                            (_yearOffset + delta).clamp(0.0, _yearMaxOffset);
                        final idx = (_yearOffset / _itemHeight)
                            .round()
                            .clamp(0, years.length - 1);
                        _selectedYear = years[idx];
                      });
                    },
                    onScrollEnd: _snapYear,
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              top: _centerY,
              child: IgnorePointer(
                child: Container(height: 2, color: bandColor),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: _centerY + _itemHeight,
              child: IgnorePointer(
                child: Container(height: 2, color: bandColor),
              ),
            ),
          ],
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'Show',
          onPressed: () {
            final month = _clampMonth(_selectedMonth, _selectedYear);
            Navigator.of(context).pop(DateTime(_selectedYear, month));
          },
        ),
      ],
    );
  }
}

class _DrumColumn extends StatelessWidget {
  final double offset;
  final double maxOffset;
  final int itemCount;
  final int selectedIndex;
  final String Function(int) labelBuilder;
  final Color textFg;
  final Color dimFg;
  final bool Function(int)? isDisabled;
  final void Function(double delta) onScroll;
  final VoidCallback onScrollEnd;

  static const double _itemHeight = 40.0;
  static const double _drumHeight = _itemHeight * 5;
  static const double _centerY = (_drumHeight - _itemHeight) / 2;

  const _DrumColumn({
    required this.offset,
    required this.maxOffset,
    required this.itemCount,
    required this.selectedIndex,
    required this.labelBuilder,
    required this.textFg,
    required this.dimFg,
    this.isDisabled,
    required this.onScroll,
    required this.onScrollEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          onScroll(event.scrollDelta.dy);
          onScrollEnd();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => onScroll(-d.delta.dy),
        onVerticalDragEnd: (_) => onScrollEnd(),
        child: ClipRect(
          child: Stack(
            children: [
              for (int i = 0; i < itemCount; i++)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _centerY + (i * _itemHeight) - offset,
                  height: _itemHeight,
                  child: Center(
                    child: Text(
                      labelBuilder(i),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: i == selectedIndex
                            ? FontWeight.w500
                            : FontWeight.normal,
                        color: (isDisabled != null && isDisabled!(i))
                            ? dimFg.withValues(alpha: 0.4)
                            : (i == selectedIndex ? textFg : dimFg),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final Color color;
  final Color disabledColor;
  final VoidCallback onTap;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final String tooltip;

  const _NavArrow({
    required this.icon,
    required this.enabled,
    required this.color,
    required this.disabledColor,
    required this.onTap,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled ? tooltip : '',
      waitDuration: const Duration(milliseconds: 350),
      child: Listener(
        onPointerDown: enabled ? (_) => onPointerDown() : null,
        onPointerUp: enabled ? (_) => onPointerUp() : null,
        child: IconButton(
          icon: Icon(icon, color: enabled ? color : disabledColor, size: 24),
          onPressed: enabled ? onTap : null,
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ),
    );
  }
}

class _DynamicImageState {
  Uint8List? imageBytes;
  AnimationController? fadeController;
}

class _DayCell extends StatefulWidget {
  final int day;
  final bool isSelected;
  final bool isFocused;
  final bool isDisabled;
  final bool isInRange;
  final bool selectionMode;
  final Uint8List? dynamicImageBytes;
  final double dynamicImageOpacity;
  final Color textColor;
  final Color accentColor;
  final Color rangeTextColor;
  final Color hoverColor;
  final Color disabledColor;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isFocused,
    required this.isDisabled,
    this.isInRange = false,
    this.selectionMode = false,
    this.dynamicImageBytes,
    this.dynamicImageOpacity = 0.0,
    required this.textColor,
    required this.accentColor,
    this.rangeTextColor = Colors.white,
    required this.hoverColor,
    required this.disabledColor,
    this.onTap,
  });

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    BoxDecoration? decoration;
    Color fg;

    // Hover/ripple are suppressed in selection mode, matching AyuGram
    // (highlightedIndex is impossible and ripples are skipped — calendar_box.cpp:783,884).
    final showHover = _hovering && !widget.isDisabled && !widget.selectionMode;

    if (widget.isSelected) {
      // Single highlighted day → filled circle (dialogsBgActive).
      decoration =
          BoxDecoration(shape: BoxShape.circle, color: widget.accentColor);
      fg = Colors.white;
    } else if (widget.isInRange) {
      // In-range day → text only; the continuous pill is painted behind by the row.
      fg = widget.rangeTextColor;
    } else if (showHover) {
      decoration =
          BoxDecoration(shape: BoxShape.circle, color: widget.hoverColor);
      fg = widget.textColor;
    } else {
      fg = widget.isDisabled ? widget.disabledColor : widget.textColor;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _cellW,
          height: _cellH,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                splashColor: widget.accentColor.withValues(alpha: 0.2),
                highlightColor: widget.accentColor.withValues(alpha: 0.1),
                child: SizedBox(
                  width: _cellInner,
                  height: _cellInner,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (decoration != null)
                        Container(
                          width: _cellInner,
                          height: _cellInner,
                          decoration: decoration,
                        ),
                      if (widget.dynamicImageBytes != null && widget.dynamicImageOpacity > 0)
                        Opacity(
                          opacity: widget.dynamicImageOpacity * (widget.isDisabled ? 0.4 : 1.0),
                          child: ClipOval(
                            child: Stack(
                              children: [
                                Image.memory(
                                  widget.dynamicImageBytes!,
                                  width: _cellInner,
                                  height: _cellInner,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                                Container(
                                  width: _cellInner,
                                  height: _cellInner,
                                  color: Colors.black.withValues(alpha: 0.15),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        '${widget.day}',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.dynamicImageBytes != null && widget.dynamicImageOpacity > 0.5
                              ? Colors.white
                              : fg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── ChooseDateTimeBox — spec §36.6.2 ───────────────────────────────────────

class ChooseDateTimeResult {
  final DateTime dateTime;
  final bool silent;
  final int repeatPeriod;
  final bool sendWhenOnline;

  const ChooseDateTimeResult({
    required this.dateTime,
    this.silent = false,
    this.repeatPeriod = 0,
    this.sendWhenOnline = false,
  });
}

Future<ChooseDateTimeResult?> showChooseDateTimeBox(
  BuildContext context, {
  DateTime? initialDate,
  bool isSelfChat = false,
  bool isScheduledToUser = false,
  String? title,
  String? submitText,
  bool showRepeat = true,
}) {
  return showTelegramBox<ChooseDateTimeResult>(
    context: context,
    builder: (ctx) => _ChooseDateTimeDialog(
      initialDate: initialDate,
      isSelfChat: isSelfChat,
      isScheduledToUser: isScheduledToUser,
      titleOverride: title,
      submitTextOverride: submitText,
      showRepeat: showRepeat,
    ),
  );
}

class _ChooseDateTimeDialog extends StatefulWidget {
  final DateTime? initialDate;
  final bool isSelfChat;
  final bool isScheduledToUser;
  final String? titleOverride;
  final String? submitTextOverride;
  final bool showRepeat;

  const _ChooseDateTimeDialog({
    this.initialDate,
    this.isSelfChat = false,
    this.isScheduledToUser = false,
    this.titleOverride,
    this.submitTextOverride,
    this.showRepeat = true,
  });

  @override
  State<_ChooseDateTimeDialog> createState() => _ChooseDateTimeDialogState();
}

class _ChooseDateTimeDialogState extends State<_ChooseDateTimeDialog>
    with TickerProviderStateMixin {
  late DateTime _selectedDate;
  late TextEditingController _hourController;
  late TextEditingController _minuteController;
  late FocusNode _hourFocus;
  late FocusNode _minuteFocus;
  late FocusNode _dateFocus;
  int _repeatPeriod = 0;
  bool _timeError = false;
  late AnimationController _errorBorderController;
  late AnimationController _premiumToastController;
  Timer? _premiumToastTimer;
  late final double _cachedAtWidth;
  final _repeatRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialDate ?? DateTime.now().add(const Duration(minutes: 10));
    _selectedDate = DateTime(initial.year, initial.month, initial.day);
    _hourController =
        TextEditingController(text: initial.hour.toString().padLeft(2, '0'));
    _minuteController =
        TextEditingController(text: initial.minute.toString().padLeft(2, '0'));
    _hourFocus = FocusNode();
    _minuteFocus = FocusNode();
    _dateFocus = FocusNode();
    _dateFocus.addListener(_onDateFocusChanged);

    _errorBorderController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _premiumToastController = AnimationController(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _cachedAtWidth = _measureTextWidth(
      'at',
      const TextStyle(fontSize: 14),
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    _dateFocus.removeListener(_onDateFocusChanged);
    _dateFocus.dispose();
    _errorBorderController.dispose();
    _premiumToastTimer?.cancel();
    _premiumToastController.dispose();
    super.dispose();
  }

  void _onDateFocusChanged() {
    if (_dateFocus.hasFocus) {
      _openCalendar();
    }
  }

  DateTime get _combinedDateTime {
    final h = int.tryParse(_hourController.text) ?? 0;
    final m = int.tryParse(_minuteController.text) ?? 0;
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      h.clamp(0, 23),
      m.clamp(0, 59),
    );
  }

  bool _validateTime() {
    final h = int.tryParse(_hourController.text);
    final m = int.tryParse(_minuteController.text);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      _showTimeError();
      return false;
    }
    final dt = _combinedDateTime;
    final minTime = DateTime.now().add(const Duration(seconds: _kMinimalSchedule));
    if (dt.isBefore(minTime)) {
      _showTimeError();
      return false;
    }
    return true;
  }

  void _showTimeError() {
    setState(() => _timeError = true);
    _errorBorderController.forward(from: 0).then((_) {
      if (mounted) {
        _errorBorderController.reverse().then((_) {
          if (mounted) setState(() => _timeError = false);
        });
      }
    });
  }

  void _submit({bool silent = false}) {
    if (!_validateTime()) return;
    Navigator.of(context).pop(ChooseDateTimeResult(
      dateTime: _combinedDateTime,
      silent: silent,
      repeatPeriod: _repeatPeriod,
    ));
  }

  // AyuGram's shared submit lambda applies the Ctrl→silent flag on every
  // submit path — the Schedule button, the box's default confirm, and Enter
  // inside the time field (history_view_schedule_box.cpp:97,
  // choose_date_time.cpp:220-229).
  void _submitWithCtrl() {
    _submit(silent: HardwareKeyboard.instance.isControlPressed);
  }

  void _sendWhenOnline() {
    Navigator.of(context).pop(ChooseDateTimeResult(
      dateTime: DateTime.fromMillisecondsSinceEpoch(
        kScheduledUntilOnlineTimestamp * 1000,
      ),
      sendWhenOnline: true,
    ));
  }

  Future<void> _openCalendar() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = DateTime(today.year + 1, today.month, today.day);
    final picked = await showCalendarBox(
      context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      selectedDate: _selectedDate,
      minDate: today,
      maxDate: maxDate,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _minuteFocus.requestFocus();
    }
  }

  void _scrollDate(int delta) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = DateTime(today.year + 1, today.month, today.day);
    final newDate = _selectedDate.add(Duration(days: delta));
    if (!newDate.isBefore(today) && !newDate.isAfter(maxDate)) {
      setState(() => _selectedDate = newDate);
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year) {
      return '${_monthNames[date.month - 1]} ${date.day}';
    }
    return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showRepeatMenu() {
    final box = _repeatRowKey.currentContext!.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset(0, box.size.height));
    showTelegramMenu<int>(
      context: context,
      position: position,
      items: _repeatPeriods.entries
          .map((e) => TelegramMenuItem<int>(value: e.key, label: e.value))
          .toList(),
    ).then((value) {
      if (value != null && mounted) {
        setState(() => _repeatPeriod = value);
      }
    });
  }

  bool get _isPremium {
    try {
      return context.read<AppState>().effectivePremium;
    } catch (_) {
      return false;
    }
  }

  void _onRepeatTap() {
    if (_isPremium) {
      _showRepeatMenu();
    } else {
      _showPremiumToast();
    }
  }

  void _showPremiumToast() {
    _premiumToastTimer?.cancel();
    _premiumToastController.forward(from: 0).then((_) {
      if (!mounted) return;
      _premiumToastTimer = Timer(const Duration(milliseconds: 3000), () {
        if (mounted) {
          _premiumToastController.reverse();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleFg =
        isDark ? const Color(0xFFE0E3EA) : const Color(0xFF000000);
    // Repeat label + dropdown/lock icons use the link color windowActiveTextFg
    // (scheduleRepeatDropdownLock/Arrow, boxes.style:919/923 + choose_date_time.cpp:313),
    // NOT windowBgActive.
    final accentFg =
        context.palette.windowActiveTextFg;
    // Date field is an underline-only InputField (scheduleDateField, no fill);
    // the bottom line uses the field border color.
    final fieldBorder =
        isDark ? const Color(0xFF2B3845) : const Color(0xFFDADADA);
    const errorBorder = Color(0xFFE53935);
    final separatorFg =
        isDark ? const Color(0xFF8B95A5) : const Color(0xFF999999);

    const toastNormal = TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 13,
      fontWeight: FontWeight.normal,
      decoration: TextDecoration.none,
      height: 1.3,
    );

    final dialogBody = TelegramBox(
      wide: true,
      title: widget.titleOverride ?? (widget.isSelfChat ? 'Remind me on...' : 'Send this message on...'),
      titleTrailing: widget.isScheduledToUser
          ? SizedBox(
              width: 34,
              height: 34,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    final box = context.findRenderObject() as RenderBox;
                    final pos = box.localToGlobal(
                      Offset(box.size.width, 0),
                    );
                    showTelegramMenu<String>(
                      context: context,
                      position: pos,
                      items: [
                        TelegramMenuItem(
                          value: 'when_online',
                          label: 'Send when online',
                          icon: const Icon(Icons.person_outline, size: 20),
                        ),
                      ],
                    ).then((v) {
                      if (v == 'when_online') _sendWhenOnline();
                    });
                  },
                  child: Icon(Icons.more_vert,
                      color: separatorFg, size: 20),
                ),
              ),
            )
          : null,
      onConfirm: _submitWithCtrl,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _scheduleHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const atText = 'at';
                final atWidth = _cachedAtWidth;
                final totalWidth = _scheduleDateWidth +
                    _scheduleAtSkip +
                    atWidth +
                    _scheduleAtSkip +
                    _scheduleTimeWidth;
                final leftPad = (constraints.maxWidth - totalWidth) / 2;

                return Stack(
                  children: [
                    Positioned(
                      left: leftPad,
                      top: _scheduleDateTop,
                      child: Listener(
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent) {
                            _scrollDate(event.scrollDelta.dy > 0 ? -1 : 1);
                          }
                        },
                        child: Focus(
                          focusNode: _dateFocus,
                          child: GestureDetector(
                            onTap: _openCalendar,
                            child: Container(
                              width: _scheduleDateWidth,
                              height: 30,
                              // scheduleDateField: underline-only InputField
                              // (borderRadius 0 ⇒ bottom line, no fill) —
                              // input_field.cpp:2397, boxes.style:893.
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom:
                                      BorderSide(color: fieldBorder, width: 1),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _formatDate(_selectedDate),
                                style:
                                    TextStyle(fontSize: 14, color: titleFg),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: leftPad + _scheduleDateWidth + _scheduleAtSkip,
                      top: _scheduleAtTop,
                      child: Text(
                        atText,
                        style:
                            TextStyle(fontSize: 14, color: separatorFg),
                      ),
                    ),
                    Positioned(
                      left: leftPad +
                          _scheduleDateWidth +
                          _scheduleAtSkip +
                          atWidth +
                          _scheduleAtSkip,
                      top: _scheduleDateTop,
                      child: AnimatedBuilder(
                        animation: _errorBorderController,
                        builder: (context, child) {
                          // scheduleTimeField is borderless (border:0,
                          // borderActive:0, no fill — boxes.style:899), so the
                          // validation error flashes the digits red instead of
                          // a (non-existent) border.
                          final t =
                              _timeError ? _errorBorderController.value : 0.0;
                          final textCol = Color.lerp(titleFg, errorBorder, t)!;
                          final sepCol =
                              Color.lerp(separatorFg, errorBorder, t)!;
                          return _TimeInputField(
                            hourController: _hourController,
                            minuteController: _minuteController,
                            hourFocus: _hourFocus,
                            minuteFocus: _minuteFocus,
                            width: _scheduleTimeWidth,
                            textColor: textCol,
                            separatorColor: sepCol,
                            onSubmit: _submitWithCtrl,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (widget.showRepeat)
            Padding(
              key: _repeatRowKey,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: GestureDetector(
                onTap: _onRepeatTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Repeat: ${_repeatPeriods[_repeatPeriod] ?? "Never"}',
                      style: TextStyle(fontSize: 13, color: accentFg),
                    ),
                    const SizedBox(width: 4),
                    if (_isPremium)
                      Icon(Icons.arrow_drop_down, size: 18, color: accentFg)
                    else
                      Icon(Icons.lock_outline, size: 14, color: accentFg),
                  ],
                ),
              ),
            ),
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: widget.submitTextOverride ?? 'Schedule',
          onPressed: _submitWithCtrl,
        ),
      ],
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        dialogBody,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedBuilder(
            animation: _premiumToastController,
            builder: (_, __) {
              final value = _premiumToastController.value;
              if (value == 0) return const SizedBox.shrink();
              return Opacity(
                opacity: value,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, 8 + 16 * (1 - value)),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 480),
                      padding: const EdgeInsets.fromLTRB(19, 13, 19, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xE52C3033),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Subscribe to ', style: toastNormal),
                            TextSpan(
                              text: 'Telegram Premium',
                              style: toastNormal.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  final appState = context.read<AppState>();
                                  final accountId = appState.activeAccount?.id;
                                  if (accountId != null) {
                                    appState.engine.openPremiumSubscription(accountId, ref: 'schedule_repeat');
                                  }
                                },
                            ),
                            const TextSpan(text: ' to schedule repeating messages.', style: toastNormal),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static double _measureTextWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}

// ─── TimePickerBox — spec §36.6.4 ──────────────────────────────────────────

const double _drumItemHeight = 40;
const int _drumVisibleCount = 5;
const double _drumHeight = _drumItemHeight * _drumVisibleCount;
const double _drumBandBorder = 2;

const List<int> kDefaultTimePickerValues = [
  900, 1800, 3600, 7200, 10800, 14400, 28800, 43200,
  86400, 172800, 259200, 604800, 1209600, 2678400, 5356800, 8035200,
];

const List<String> _defaultTimePickerLabels = [
  '15 minutes', '30 minutes', '1 hour', '2 hours', '3 hours', '4 hours',
  '8 hours', '12 hours', '1 day', '2 days', '3 days', '1 week', '2 weeks',
  '1 month', '2 months', '3 months',
];

int _lowerBoundIndex(List<int> values, int target) {
  if (values.isEmpty) return 0;
  var lo = 0;
  var hi = values.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (values[mid] < target) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo == 0) return 0;
  if (lo >= values.length) return values.length - 1;
  final leftDist = (target - values[lo - 1]).abs();
  final rightDist = (values[lo] - target).abs();
  return leftDist < rightDist ? lo - 1 : lo;
}

Future<int?> showTimePickerBox(
  BuildContext context, {
  String title = 'Auto-Delete Timer',
  List<int>? values,
  List<String>? labels,
  int? initialValue,
}) {
  final v = values ?? kDefaultTimePickerValues;
  final l = labels ?? _defaultTimePickerLabels;
  assert(v.length == l.length);
  int initialIndex = 0;
  if (initialValue != null) {
    initialIndex = _lowerBoundIndex(v, initialValue);
  }
  return showTelegramBox<int>(
    context: context,
    builder: (ctx) => _TimePickerBoxWidget(
      title: title,
      values: v,
      labels: l,
      initialIndex: initialIndex,
    ),
  );
}

class _TimePickerBoxWidget extends StatefulWidget {
  final String title;
  final List<int> values;
  final List<String> labels;
  final int initialIndex;

  const _TimePickerBoxWidget({
    required this.title,
    required this.values,
    required this.labels,
    required this.initialIndex,
  });

  @override
  State<_TimePickerBoxWidget> createState() => _TimePickerBoxWidgetState();
}

class _TimePickerBoxWidgetState extends State<_TimePickerBoxWidget>
    with SingleTickerProviderStateMixin {
  late double _scrollOffset;
  late int _selectedIndex;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;
  double _snapFrom = 0;
  double _snapTo = 0;
  late final double _cachedDrumWidth;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _scrollOffset = widget.initialIndex * _drumItemHeight;
    _cachedDrumWidth = _maxLabelWidth(const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)) + 32;
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _scrollOffset =
              _snapFrom + (_snapTo - _snapFrom) * Curves.easeOutCubic.transform(_snapController.value);
          _selectedIndex = (_scrollOffset / _drumItemHeight).round().clamp(0, widget.values.length - 1);
        });
      });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double get _maxOffset => (widget.values.length - 1) * _drumItemHeight;

  void _snapToNearest() {
    final target = (_scrollOffset / _drumItemHeight).round() * _drumItemHeight;
    final clamped = target.clamp(0.0, _maxOffset);
    _snapFrom = _scrollOffset;
    _snapTo = clamped;
    _snapController.forward(from: 0);
  }

  void _goToIndex(int index) {
    final clamped = index.clamp(0, widget.values.length - 1);
    _snapFrom = _scrollOffset;
    _snapTo = clamped * _drumItemHeight;
    _snapController.forward(from: 0);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _goToIndex(_selectedIndex - 1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _goToIndex(_selectedIndex + 1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double _maxLabelWidth(TextStyle style) {
    double max = 0;
    for (final label in widget.labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width > max) max = painter.width;
    }
    return max;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFg = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final dimFg = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    // Selection band lines use activeLineFg (time_picker_box.cpp:109), not windowBgActive.
    final bandColor = context.palette.activeLineFg;
    final centerY = (_drumHeight - _drumItemHeight) / 2;
    final labelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final drumWidth = _cachedDrumWidth;

    return TelegramBox(
      title: widget.title,
      onKeyEvent: _handleKey,
      scrollableContent: false,
      onConfirm: () => Navigator.of(context).pop(widget.values[_selectedIndex]),
      content: Center(
        child: SizedBox(
          width: drumWidth,
          height: _drumHeight,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _snapController.stop();
                setState(() {
                  _scrollOffset = (_scrollOffset + event.scrollDelta.dy).clamp(0.0, _maxOffset);
                  _selectedIndex = (_scrollOffset / _drumItemHeight).round().clamp(0, widget.values.length - 1);
                });
                _snapToNearest();
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) {
                _snapController.stop();
                setState(() {
                  _scrollOffset = (_scrollOffset - d.delta.dy).clamp(0.0, _maxOffset);
                  _selectedIndex = (_scrollOffset / _drumItemHeight).round().clamp(0, widget.values.length - 1);
                });
              },
              onVerticalDragEnd: (_) => _snapToNearest(),
              child: ClipRect(
                child: Stack(
                  children: [
                    for (int i = 0; i < widget.labels.length; i++)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: centerY + (i * _drumItemHeight) - _scrollOffset,
                        height: _drumItemHeight,
                        child: Center(
                          child: Text(
                            widget.labels[i],
                            style: TextStyle(
                              fontSize: 14,
                              color: i == _selectedIndex ? textFg : dimFg,
                              fontWeight: i == _selectedIndex ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: centerY,
                      child: IgnorePointer(
                        child: Container(
                          height: _drumItemHeight,
                          decoration: BoxDecoration(
                            border: Border.symmetric(
                              horizontal: BorderSide(
                                color: bandColor,
                                width: _drumBandBorder,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'Done',
          onPressed: () => Navigator.of(context).pop(widget.values[_selectedIndex]),
        ),
      ],
    );
  }
}

class _TimeInputField extends StatelessWidget {
  final TextEditingController hourController;
  final TextEditingController minuteController;
  final FocusNode hourFocus;
  final FocusNode minuteFocus;
  final double width;
  final Color textColor;
  final Color separatorColor;
  final VoidCallback onSubmit;

  const _TimeInputField({
    required this.hourController,
    required this.minuteController,
    required this.hourFocus,
    required this.minuteFocus,
    required this.width,
    required this.textColor,
    required this.separatorColor,
    required this.onSubmit,
  });

  void _scrollHour(double dy) {
    final cur = int.tryParse(hourController.text) ?? 0;
    final next = dy > 0 ? (cur - 1).clamp(0, 23) : (cur + 1).clamp(0, 23);
    hourController.text = next.toString().padLeft(2, '0');
    hourController.selection = TextSelection.collapsed(offset: hourController.text.length);
  }

  void _scrollMinute(double dy) {
    final cur = int.tryParse(minuteController.text) ?? 0;
    final step = 10;
    final next = dy > 0 ? (cur - step).clamp(0, 59) : (cur + step).clamp(0, 59);
    minuteController.text = next.toString().padLeft(2, '0');
    minuteController.selection = TextSelection.collapsed(offset: minuteController.text.length);
  }

  KeyEventResult _handleMinuteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final sel = minuteController.selection;
      if (sel.baseOffset == 0 && sel.extentOffset == 0) {
        hourFocus.requestFocus();
        hourController.selection = TextSelection.collapsed(offset: hourController.text.length);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (minuteController.text.isEmpty) {
        final hText = hourController.text;
        if (hText.isNotEmpty) {
          hourController.text = hText.substring(0, hText.length - 1);
          hourController.selection = TextSelection.collapsed(offset: hourController.text.length);
        }
        hourFocus.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // scheduleTimeField: borderless, no fill (border:0, borderActive:0 —
    // boxes.style:899).
    return SizedBox(
      width: width,
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) _scrollHour(event.scrollDelta.dy);
              },
              child: TextField(
                controller: hourController,
                focusNode: hourFocus,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                onChanged: (v) {
                  if (v.length == 2) minuteFocus.requestFocus();
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              ':',
              style: TextStyle(fontSize: 14, color: separatorColor),
            ),
          ),
          SizedBox(
            width: 24,
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) _scrollMinute(event.scrollDelta.dy);
              },
              child: Focus(
                onKeyEvent: _handleMinuteKey,
                child: TextField(
                  controller: minuteController,
                  focusNode: minuteFocus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TriangleArrowPainter extends CustomPainter {
  final Color color;
  _TriangleArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TriangleArrowPainter old) => old.color != color;
}
