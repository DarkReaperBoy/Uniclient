import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:flutter/services.dart';

import 'confirm_box.dart';

const double _cellW = 48;
const double _cellH = 40;
const double _cellInner = 34;
const double _daysRowH = 40;
const double _calPadH = 14;
const double _scheduleHeight = 95;
const double _scheduleDateWidth = 136;
const double _scheduleTimeWidth = 72;
const double _scheduleAtSkip = 24;
const double _scheduleDateTop = 38;
const double _scheduleAtTop = 42;

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekDays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

const Map<int, String> _repeatPeriods = {
  0: 'Never',
  86400: 'Daily',
  604800: 'Weekly',
  1209600: 'Every 2 weeks',
  2592000: 'Monthly',
  7862400: 'Every 3 months',
  15724800: 'Every 6 months',
  31536000: 'Yearly',
};

// ─── CalendarBox — spec §36.6.1 ─────────────────────────────────────────────

Future<DateTime?> showCalendarBox(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? minDate,
  DateTime? maxDate,
  DateTime? selectedDate,
}) {
  return showTelegramBox<DateTime>(
    context: context,
    builder: (ctx) => _CalendarBoxWidget(
      initialDate: initialDate,
      minDate: minDate ?? DateTime(1970),
      maxDate: maxDate ?? DateTime(2036, 12, 31),
      selectedDate: selectedDate,
    ),
  );
}

class _CalendarBoxWidget extends StatefulWidget {
  final DateTime? initialDate;
  final DateTime minDate;
  final DateTime maxDate;
  final DateTime? selectedDate;

  const _CalendarBoxWidget({
    this.initialDate,
    required this.minDate,
    required this.maxDate,
    this.selectedDate,
  });

  @override
  State<_CalendarBoxWidget> createState() => _CalendarBoxWidgetState();
}

class _CalendarBoxWidgetState extends State<_CalendarBoxWidget> {
  late int _year;
  late int _month;
  late int _focusDay;
  DateTime? _selected;
  Timer? _fastJumpTimer;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedDate;
    final base = widget.initialDate ?? widget.selectedDate ?? DateTime.now();
    _year = base.year;
    _month = base.month;
    _focusDay = base.day;
  }

  @override
  void dispose() {
    _fastJumpTimer?.cancel();
    super.dispose();
  }

  bool _canGoPrev() {
    return _year > widget.minDate.year ||
        (_year == widget.minDate.year && _month > widget.minDate.month);
  }

  bool _canGoNext() {
    return _year < widget.maxDate.year ||
        (_year == widget.maxDate.year && _month < widget.maxDate.month);
  }

  void _prevMonth() {
    if (!_canGoPrev()) return;
    setState(() {
      _month--;
      if (_month < 1) {
        _month = 12;
        _year--;
      }
      _clampFocusDay();
    });
  }

  void _nextMonth() {
    if (!_canGoNext()) return;
    setState(() {
      _month++;
      if (_month > 12) {
        _month = 1;
        _year++;
      }
      _clampFocusDay();
    });
  }

  void _clampFocusDay() {
    final maxDay = DateTime(_year, _month + 1, 0).day;
    if (_focusDay > maxDay) _focusDay = maxDay;
  }

  bool _isDayDisabled(DateTime date) {
    final dayOnly = DateTime(date.year, date.month, date.day);
    final minOnly =
        DateTime(widget.minDate.year, widget.minDate.month, widget.minDate.day);
    final maxOnly =
        DateTime(widget.maxDate.year, widget.maxDate.month, widget.maxDate.day);
    return dayOnly.isBefore(minOnly) || dayOnly.isAfter(maxOnly);
  }

  void _selectDay(int day) {
    final date = DateTime(_year, _month, day);
    if (_isDayDisabled(date)) return;
    Navigator.of(context).pop(date);
  }

  void _startFastJump(void Function() action) {
    _fastJumpTimer?.cancel();
    _fastJumpTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      action();
    });
  }

  void _stopFastJump() {
    _fastJumpTimer?.cancel();
    _fastJumpTimer = null;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveFocus(1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-7);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(7);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _selectDay(_focusDay);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveFocus(int delta) {
    setState(() {
      final newDay = _focusDay + delta;
      final daysInMonth = DateTime(_year, _month + 1, 0).day;
      if (newDay < 1) {
        if (_canGoPrev()) {
          _month--;
          if (_month < 1) {
            _month = 12;
            _year--;
          }
          final prevDays = DateTime(_year, _month + 1, 0).day;
          _focusDay = prevDays + newDay;
        }
      } else if (newDay > daysInMonth) {
        if (_canGoNext()) {
          _focusDay = newDay - daysInMonth;
          _month++;
          if (_month > 12) {
            _month = 1;
            _year++;
          }
        }
      } else {
        _focusDay = newDay;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFg = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextFg =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentFg =
        context.palette.windowBgActive;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final disabledFg = subtextFg.withValues(alpha: 0.4);

    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final startWeekday = DateTime(_year, _month, 1).weekday;
    final offset = startWeekday - 1;
    final now = DateTime.now();

    return TelegramBox(
      wide: true,
      title: '${_monthNames[_month - 1]} $_year',
      titleTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavArrow(
            icon: Icons.chevron_left,
            enabled: _canGoPrev(),
            color: textFg,
            disabledColor: subtextFg,
            onTap: _prevMonth,
            onLongPressStart: () => _startFastJump(_prevMonth),
            onLongPressEnd: _stopFastJump,
          ),
          _NavArrow(
            icon: Icons.chevron_right,
            enabled: _canGoNext(),
            color: textFg,
            disabledColor: subtextFg,
            onTap: _nextMonth,
            onLongPressStart: () => _startFastJump(_nextMonth),
            onLongPressEnd: _stopFastJump,
          ),
          const SizedBox(width: 4),
        ],
      ),
      onConfirm: () => _selectDay(_focusDay),
      content: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _calPadH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _daysRowH,
                child: Row(
                  children: _weekDays.map((d) {
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
              _buildDayGrid(
                offset,
                daysInMonth,
                now,
                textFg,
                subtextFg,
                accentFg,
                hoverBg,
                disabledFg,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildDayGrid(
    int offset,
    int daysInMonth,
    DateTime now,
    Color textFg,
    Color subtextFg,
    Color accentFg,
    Color hoverBg,
    Color disabledFg,
  ) {
    final rows = <Widget>[];
    var day = 1;

    for (var row = 0; row < 6 && day <= daysInMonth; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        final cellIndex = row * 7 + col;
        if (cellIndex < offset || day > daysInMonth) {
          cells.add(const SizedBox(width: _cellW, height: _cellH));
        } else {
          final thisDay = day;
          final date = DateTime(_year, _month, thisDay);
          final isDisabled = _isDayDisabled(date);
          final isSelected = _selected != null &&
              _selected!.year == _year &&
              _selected!.month == _month &&
              _selected!.day == thisDay;
          final isFocused = _focusDay == thisDay;
          final isToday = now.year == _year &&
              now.month == _month &&
              now.day == thisDay;

          cells.add(_DayCell(
            day: thisDay,
            isSelected: isSelected,
            isFocused: isFocused,
            isToday: isToday,
            isDisabled: isDisabled,
            textColor: textFg,
            accentColor: accentFg,
            hoverColor: hoverBg,
            disabledColor: disabledFg,
            onTap: isDisabled ? null : () => _selectDay(thisDay),
          ));
          day++;
        }
      }
      rows.add(Row(children: cells));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final Color color;
  final Color disabledColor;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  const _NavArrow({
    required this.icon,
    required this.enabled,
    required this.color,
    required this.disabledColor,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: enabled ? (_) => onLongPressStart() : null,
      onLongPressEnd: enabled ? (_) => onLongPressEnd() : null,
      child: IconButton(
        icon: Icon(icon, color: enabled ? color : disabledColor, size: 24),
        onPressed: enabled ? onTap : null,
        splashRadius: 16,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}

class _DayCell extends StatefulWidget {
  final int day;
  final bool isSelected;
  final bool isFocused;
  final bool isToday;
  final bool isDisabled;
  final Color textColor;
  final Color accentColor;
  final Color hoverColor;
  final Color disabledColor;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isFocused,
    required this.isToday,
    required this.isDisabled,
    required this.textColor,
    required this.accentColor,
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

    if (widget.isSelected) {
      decoration =
          BoxDecoration(shape: BoxShape.circle, color: widget.accentColor);
      fg = Colors.white;
    } else if (widget.isToday) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: widget.accentColor, width: 1.5),
      );
      fg = widget.textColor;
    } else if (_hovering && !widget.isDisabled) {
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
        onTap: widget.onTap,
        child: SizedBox(
          width: _cellW,
          height: _cellH,
          child: Center(
            child: Container(
              width: _cellInner,
              height: _cellInner,
              decoration: decoration,
              alignment: Alignment.center,
              child: Text(
                '${widget.day}',
                style: TextStyle(fontSize: 13, color: fg),
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
  bool isPremium = false,
}) {
  return showTelegramBox<ChooseDateTimeResult>(
    context: context,
    builder: (ctx) => _ChooseDateTimeDialog(
      initialDate: initialDate,
      isSelfChat: isSelfChat,
      isScheduledToUser: isScheduledToUser,
      isPremium: isPremium,
    ),
  );
}

class _ChooseDateTimeDialog extends StatefulWidget {
  final DateTime? initialDate;
  final bool isSelfChat;
  final bool isScheduledToUser;
  final bool isPremium;

  const _ChooseDateTimeDialog({
    this.initialDate,
    this.isSelfChat = false,
    this.isScheduledToUser = false,
    this.isPremium = false,
  });

  @override
  State<_ChooseDateTimeDialog> createState() => _ChooseDateTimeDialogState();
}

class _ChooseDateTimeDialogState extends State<_ChooseDateTimeDialog>
    with SingleTickerProviderStateMixin {
  late DateTime _selectedDate;
  late TextEditingController _hourController;
  late TextEditingController _minuteController;
  late FocusNode _hourFocus;
  late FocusNode _minuteFocus;
  int _repeatPeriod = 0;
  bool _timeError = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

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

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    _shakeController.dispose();
    super.dispose();
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
    if (dt.isBefore(DateTime.now())) {
      _showTimeError();
      return false;
    }
    return true;
  }

  void _showTimeError() {
    setState(() => _timeError = true);
    _shakeController.forward(from: 0).then((_) {
      if (mounted) setState(() => _timeError = false);
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

  void _sendWhenOnline() {
    Navigator.of(context).pop(ChooseDateTimeResult(
      dateTime: DateTime(2099),
      sendWhenOnline: true,
    ));
  }

  Future<void> _openCalendar() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = today.add(const Duration(days: 365));
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
    final maxDate = today.add(const Duration(days: 365));
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
    if (!widget.isPremium) return;
    final box = context.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset(0, box.size.height));
    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx + 40,
        position.dy - 40,
        position.dx + 200,
        position.dy,
      ),
      items: _repeatPeriods.entries
          .map((e) => PopupMenuItem<int>(value: e.key, child: Text(e.value)))
          .toList(),
    ).then((value) {
      if (value != null && mounted) {
        setState(() => _repeatPeriod = value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleFg =
        isDark ? const Color(0xFFE0E3EA) : const Color(0xFF000000);
    final accentFg =
        context.palette.windowBgActive;
    final fieldBg =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0);
    final fieldBorder =
        isDark ? const Color(0xFF2B3845) : const Color(0xFFDADADA);
    final fieldBorderActive =
        context.palette.windowBgActive;
    const errorBorder = Color(0xFFE53935);
    final separatorFg =
        isDark ? const Color(0xFF8B95A5) : const Color(0xFF999999);

    return TelegramBox(
      wide: true,
      title: widget.isSelfChat ? 'Set a reminder' : 'Schedule message',
      titleTrailing: widget.isScheduledToUser
          ? IconButton(
              icon: Icon(Icons.more_vert,
                  color: separatorFg, size: 20),
              onPressed: () {
                final box = context.findRenderObject() as RenderBox;
                final pos =
                    box.localToGlobal(Offset(box.size.width - 8, 40));
                showMenu<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(
                      pos.dx - 200, pos.dy, pos.dx, pos.dy + 48),
                  items: [
                    const PopupMenuItem(
                      value: 'when_online',
                      child: Row(
                        children: [
                          Icon(Icons.person_outline, size: 20),
                          SizedBox(width: 12),
                          Text('Send when online'),
                        ],
                      ),
                    ),
                  ],
                ).then((v) {
                  if (v == 'when_online') _sendWhenOnline();
                });
              },
            )
          : null,
      onConfirm: () => _submit(),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _scheduleHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const atText = 'at';
                final atWidth = _measureTextWidth(
                  atText,
                  TextStyle(fontSize: 14, color: separatorFg),
                );
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
                        child: GestureDetector(
                          onTap: _openCalendar,
                          child: Container(
                            width: _scheduleDateWidth,
                            height: 30,
                            decoration: BoxDecoration(
                              color: fieldBg,
                              border:
                                  Border.all(color: fieldBorder, width: 1),
                              borderRadius: BorderRadius.circular(2),
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
                        animation: _shakeAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_shakeAnimation.value, 0),
                            child: child,
                          );
                        },
                        child: _TimeInputField(
                          hourController: _hourController,
                          minuteController: _minuteController,
                          hourFocus: _hourFocus,
                          minuteFocus: _minuteFocus,
                          width: _scheduleTimeWidth,
                          fieldBg: fieldBg,
                          fieldBorder:
                              _timeError ? errorBorder : fieldBorder,
                          fieldBorderActive: _timeError
                              ? errorBorder
                              : fieldBorderActive,
                          textColor: titleFg,
                          separatorColor: separatorFg,
                          onSubmit: () => _submit(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: GestureDetector(
              onTap: widget.isPremium ? _showRepeatMenu : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Repeat: ${_repeatPeriods[_repeatPeriod] ?? "Never"}',
                    style: TextStyle(fontSize: 13, color: accentFg),
                  ),
                  const SizedBox(width: 4),
                  if (widget.isPremium)
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
          text: 'Schedule',
          onPressed: () {
            final isCtrlHeld = HardwareKeyboard.instance.isControlPressed;
            _submit(silent: isCtrlHeld);
          },
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
    final idx = v.indexOf(initialValue);
    if (idx >= 0) initialIndex = idx;
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

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _scrollOffset = widget.initialIndex * _drumItemHeight;
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFg = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final dimFg = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final bandColor = context.palette.windowBgActive;
    final centerY = (_drumHeight - _drumItemHeight) / 2;

    return TelegramBox(
      title: widget.title,
      onKeyEvent: _handleKey,
      scrollableContent: false,
      onConfirm: () => Navigator.of(context).pop(widget.values[_selectedIndex]),
      content: SizedBox(
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
  final Color fieldBg;
  final Color fieldBorder;
  final Color fieldBorderActive;
  final Color textColor;
  final Color separatorColor;
  final VoidCallback onSubmit;

  const _TimeInputField({
    required this.hourController,
    required this.minuteController,
    required this.hourFocus,
    required this.minuteFocus,
    required this.width,
    required this.fieldBg,
    required this.fieldBorder,
    required this.fieldBorderActive,
    required this.textColor,
    required this.separatorColor,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 30,
      decoration: BoxDecoration(
        color: fieldBg,
        border: Border.all(color: fieldBorder, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              ':',
              style: TextStyle(fontSize: 14, color: separatorColor),
            ),
          ),
          SizedBox(
            width: 24,
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
        ],
      ),
    );
  }
}
