import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double _boxWideWidth = 364;
const double _boxRadius = 3;
const double _scheduleHeight = 95;
const double _scheduleDateWidth = 136;
const double _scheduleTimeWidth = 72;
const double _scheduleAtSkip = 24;
const double _scheduleDateTop = 38;
const double _scheduleAtTop = 42;
const int _kScheduledUntilOnlineTimestamp = 0x7FFFFFFE;

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
  return showDialog<ChooseDateTimeResult>(
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
    final initial = widget.initialDate ??
        DateTime.now().add(const Duration(minutes: 10));
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now)
          ? now
          : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
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
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final now = DateTime.now();
    if (date.year == now.year) {
      return '${months[date.month - 1]} ${date.day}';
    }
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
      items: _repeatPeriods.entries.map((e) => PopupMenuItem<int>(
        value: e.key,
        child: Text(e.value),
      )).toList(),
    ).then((value) {
      if (value != null && mounted) {
        setState(() => _repeatPeriod = value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final titleFg = isDark ? const Color(0xFFE0E3EA) : const Color(0xFF000000);
    final textFg = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF666666);
    final accentFg = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final fieldBg = isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0);
    final fieldBorder = isDark ? const Color(0xFF2B3845) : const Color(0xFFDADADA);
    final fieldBorderActive = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final errorBorder = const Color(0xFFE53935);
    final separatorFg = isDark ? const Color(0xFF8B95A5) : const Color(0xFF999999);

    return Dialog(
      backgroundColor: boxBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_boxRadius),
      ),
      elevation: 4,
      child: SizedBox(
        width: _boxWideWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar with optional "Send when online" menu
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.isSelfChat
                              ? 'Set a reminder'
                              : 'Schedule message',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: titleFg,
                          ),
                        ),
                      ),
                    ),
                    if (widget.isScheduledToUser)
                      IconButton(
                        icon: Icon(Icons.more_vert, color: textFg, size: 20),
                        onPressed: () {
                          final box =
                              context.findRenderObject() as RenderBox;
                          final pos = box.localToGlobal(
                              Offset(box.size.width - 8, 40));
                          showMenu<String>(
                            context: context,
                            position: RelativeRect.fromLTRB(
                              pos.dx - 200,
                              pos.dy,
                              pos.dx,
                              pos.dy + 48,
                            ),
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
                      ),
                  ],
                ),
              ),
            ),

            // Date + "at" + Time row
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
                  final leftPad =
                      (constraints.maxWidth - totalWidth) / 2;

                  return Stack(
                    children: [
                      // Date field
                      Positioned(
                        left: leftPad,
                        top: _scheduleDateTop,
                        child: Listener(
                          onPointerSignal: (event) {
                            if (event is PointerScrollEvent) {
                              _scrollDate(
                                  event.scrollDelta.dy > 0 ? -1 : 1);
                            }
                          },
                          child: GestureDetector(
                            onTap: _openCalendar,
                            child: Container(
                              width: _scheduleDateWidth,
                              height: 30,
                              decoration: BoxDecoration(
                                color: fieldBg,
                                border: Border.all(
                                  color: fieldBorder,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _formatDate(_selectedDate),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: titleFg,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // "at" label
                      Positioned(
                        left: leftPad +
                            _scheduleDateWidth +
                            _scheduleAtSkip,
                        top: _scheduleAtTop,
                        child: Text(
                          atText,
                          style: TextStyle(
                            fontSize: 14,
                            color: separatorFg,
                          ),
                        ),
                      ),
                      // Time field
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
                              offset:
                                  Offset(_shakeAnimation.value, 0),
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
                            fieldBorder: _timeError
                                ? errorBorder
                                : fieldBorder,
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

            // Repeat period row
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: GestureDetector(
                onTap: widget.isPremium ? _showRepeatMenu : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Repeat: ${_repeatPeriods[_repeatPeriod] ?? "Never"}',
                      style: TextStyle(
                        fontSize: 13,
                        color: accentFg,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (widget.isPremium)
                      Icon(Icons.arrow_drop_down,
                          size: 18, color: accentFg)
                    else
                      Icon(Icons.lock_outline,
                          size: 14, color: accentFg),
                  ],
                ),
              ),
            ),

            // Button row
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: accentFg,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final isCtrlHeld =
                          HardwareKeyboard.instance.isControlPressed;
                      _submit(silent: isCtrlHeld);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: accentFg,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Schedule'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
