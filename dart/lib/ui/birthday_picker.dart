import 'package:flutter/material.dart';

/// Telegram-styled birthday drum picker (day / month / year wheel scrollers),
/// ported from AyuGram's `EditBirthdayBox` (`ui/boxes/edit_birthday_box.cpp`).
/// Used both for setting your own birthday (Settings → Information) and for
/// suggesting a contact's date of birth (Edit Contact box, `internal:edit_birthday:suggest`).
///
/// Returns a `(day, month, year)` record on Save (year == 0 means "year not set"),
/// `(0, 0, 0)` when the Remove button is pressed (only shown when [hasExisting]),
/// or null on Cancel / dismiss.
class BirthdayDrumPickerDialog extends StatefulWidget {
  final int initialDay;
  final int initialMonth;
  final int initialYear;
  final bool hasExisting;
  final String title;
  final String saveLabel;

  const BirthdayDrumPickerDialog({
    super.key,
    required this.initialDay,
    required this.initialMonth,
    this.initialYear = 0,
    this.hasExisting = false,
    this.title = 'Birthday',
    this.saveLabel = 'Save',
  });

  @override
  State<BirthdayDrumPickerDialog> createState() => _BirthdayDrumPickerDialogState();
}

class _BirthdayDrumPickerDialogState extends State<BirthdayDrumPickerDialog> {
  static const _minYear = 1875;
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late int _maxYear;
  late FixedExtentScrollController _dayController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _yearController;
  late int _selectedDay;
  late int _selectedMonth;
  late int _selectedYearIndex;
  late int _yearCount;

  @override
  void initState() {
    super.initState();
    _maxYear = DateTime.now().year;
    _yearCount = _maxYear - _minYear + 2;
    _selectedDay = widget.initialDay.clamp(1, 31);
    _selectedMonth = widget.initialMonth.clamp(1, 12);
    _selectedYearIndex = widget.initialYear > 0
        ? (widget.initialYear - _minYear).clamp(0, _yearCount - 2)
        : _yearCount - 1;
    _dayController = FixedExtentScrollController(initialItem: _selectedDay - 1);
    _monthController = FixedExtentScrollController(initialItem: _selectedMonth - 1);
    _yearController = FixedExtentScrollController(initialItem: _selectedYearIndex);
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  int _daysInMonth(int month, int yearIndex) {
    final year = yearIndex < _yearCount - 1 ? _minYear + yearIndex : _maxYear;
    if (month == 2) {
      return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28;
    }
    return const [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month];
  }

  void _onMonthChanged(int index) {
    setState(() {
      _selectedMonth = index + 1;
      final maxDay = _daysInMonth(_selectedMonth, _selectedYearIndex);
      if (_selectedDay > maxDay) {
        _selectedDay = maxDay;
        _dayController.jumpToItem(_selectedDay - 1);
      }
    });
  }

  void _onYearChanged(int index) {
    setState(() {
      _selectedYearIndex = index;
      final maxDay = _daysInMonth(_selectedMonth, _selectedYearIndex);
      if (_selectedDay > maxDay) {
        _selectedDay = maxDay;
        _dayController.jumpToItem(_selectedDay - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF3390EC);
    final maxDays = _daysInMonth(_selectedMonth, _selectedYearIndex);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: Row(
                  children: [
                    Flexible(flex: 1, child: _buildWheel(
                      controller: _dayController,
                      itemCount: maxDays,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      labelBuilder: (i) => '${i + 1}',
                      onChanged: (i) => setState(() => _selectedDay = i + 1),
                    )),
                    Flexible(flex: 2, child: _buildWheel(
                      controller: _monthController,
                      itemCount: 12,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      labelBuilder: (i) => _monthNames[i],
                      onChanged: _onMonthChanged,
                    )),
                    Flexible(flex: 1, child: _buildWheel(
                      controller: _yearController,
                      itemCount: _yearCount,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      labelBuilder: (i) => i < _yearCount - 1 ? '${_minYear + i}' : '—',
                      onChanged: _onYearChanged,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (widget.hasExisting)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(
                          (day: 0, month: 0, year: 0),
                        ),
                        child: Text('Remove', style: TextStyle(color: Colors.red[400])),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: subtextColor)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        final year = _selectedYearIndex < _yearCount - 1
                            ? _minYear + _selectedYearIndex
                            : 0;
                        Navigator.of(context).pop(
                          (day: _selectedDay, month: _selectedMonth, year: year),
                        );
                      },
                      child: Text(widget.saveLabel, style: TextStyle(color: accentColor)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required Color textColor,
    required Color subtextColor,
    required String Function(int) labelBuilder,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      perspective: 0.003,
      diameterRatio: 1.5,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          final isSelected = controller.hasClients && controller.selectedItem == index;
          return Center(
            child: Text(
              labelBuilder(index),
              style: TextStyle(
                fontSize: isSelected ? 16 : 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? textColor : subtextColor,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Convenience opener for [BirthdayDrumPickerDialog].
Future<({int day, int month, int year})?> showBirthdayPicker(
  BuildContext context, {
  required int initialDay,
  required int initialMonth,
  int initialYear = 0,
  bool hasExisting = false,
  String title = 'Birthday',
  String saveLabel = 'Save',
}) {
  return showDialog<({int day, int month, int year})>(
    context: context,
    builder: (ctx) => BirthdayDrumPickerDialog(
      initialDay: initialDay,
      initialMonth: initialMonth,
      initialYear: initialYear,
      hasExisting: hasExisting,
      title: title,
      saveLabel: saveLabel,
    ),
  );
}
