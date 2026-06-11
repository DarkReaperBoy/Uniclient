import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/lang_pack.dart';
import '../theme/telegram_palette.dart';

/// Telegram-styled birthday drum picker (day / month / year wheel scrollers),
/// ported from AyuGram's `EditBirthdayBox` (`ui/boxes/edit_birthday_box.cpp`)
/// and its `VerticalDrumPicker` (`ui/widgets/vertical_drum_picker.cpp`).
/// Used both for setting your own birthday (Settings → Information) and for
/// suggesting a contact's date of birth (Edit Contact box, `internal:edit_birthday:suggest`).
///
/// Returns a `(day, month, year)` record on Save (year == 0 means "year not set"),
/// `(0, 0, 0)` when the Remove button is pressed (only shown when [hasExisting]),
/// or null on Cancel / dismiss.
///
/// Future birthdays are blocked exactly like AyuGram: the picker never lets you
/// scroll past `max` (the later of "today" and the existing value), so when the
/// top numeric year is selected the month wheel is capped to the current month and
/// the day wheel to the current day (`edit_birthday_box.cpp:108,146`). When the
/// year is left unset ("—") February still offers 29 days, mirroring AyuGram's
/// `!year` leap short-circuit (`edit_birthday_box.cpp:148-152`).
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
  // Data::Birthday::kYearMin (data_birthday.h:33).
  static const _minYear = 1875;
  // st::settingsWorkingHoursPicker / ...ItemHeight (settings.style:681-682).
  static const double _viewportHeight = 200;
  static const double _itemHeight = 40;
  // st::defaultInputField.borderActive (widgets.style:1063).
  static const double _bandBorder = 2;

  // The maximum selectable birthday: `current.year() ? max(now, current) : now`
  // (edit_birthday_box.cpp:55-61). Birthdays compare as (year, month, day) tuples
  // (data_birthday.cpp: serialize = day + month*100 + year*10000).
  late final int _maxYear;
  late final int _maxMonth;
  late final int _maxDay;
  late final int _yearCount;

  late int _selectedDay;
  late int _selectedMonth;
  late int _selectedYearIndex;
  late int _monthsCount;
  late int _daysCount;

  // Keyboard navigation targets the year wheel only — AyuGram's box-level event
  // filter forwards every KeyPress to `years->handleKeyEvent`
  // (edit_birthday_box.cpp:190-195). A GlobalKey lets [_handleKey] reach the
  // year picker's state to step/page it.
  final _yearKey = GlobalKey<_VerticalDrumPickerState>();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    if (widget.initialYear > 0) {
      final nowVal = now.day + now.month * 100 + now.year * 10000;
      final curVal =
          widget.initialDay + widget.initialMonth * 100 + widget.initialYear * 10000;
      if (curVal > nowVal) {
        _maxYear = widget.initialYear;
        _maxMonth = widget.initialMonth;
        _maxDay = widget.initialDay;
      } else {
        _maxYear = now.year;
        _maxMonth = now.month;
        _maxDay = now.day;
      }
    } else {
      _maxYear = now.year;
      _maxMonth = now.month;
      _maxDay = now.day;
    }
    // yearsCount = (maxYear - minYear + 2); // Last - not set. (edit_birthday_box.cpp:63)
    _yearCount = _maxYear - _minYear + 2;
    _selectedYearIndex = widget.initialYear > 0
        ? (widget.initialYear - _minYear).clamp(0, _yearCount - 2)
        : _yearCount - 1;
    _selectedMonth = widget.initialMonth.clamp(1, 12);
    _selectedDay = widget.initialDay.clamp(1, 31);
    _recomputeCounts();
  }

  /// The numeric year currently selected (0 means the "—" not-set option).
  int get _selectedYear =>
      _selectedYearIndex < _yearCount - 1 ? _minYear + _selectedYearIndex : 0;

  // monthsCount = (year == maxYear) ? max.month() : 12 (edit_birthday_box.cpp:108).
  int _monthsCountFor(int year) => (year == _maxYear) ? _maxMonth : 12;

  // daysCount = (year == maxYear && month == max.month()) ? max.day()
  //   : (month == 2) ? ((!year || leap) ? 29 : 28)
  //   : (month in {4,6,9,11}) ? 30 : 31    (edit_birthday_box.cpp:146-154).
  int _daysCountFor(int month, int year) {
    if (year == _maxYear && month == _maxMonth) return _maxDay;
    if (month == 2) {
      final leap = year == 0 ||
          (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));
      return leap ? 29 : 28;
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) return 30;
    return 31;
  }

  /// Recompute the month/day wheel lengths for the current selection and clamp
  /// the selected month/day down if they fell outside the new (capped) range —
  /// AyuGram does this by `std::clamp`-ing the start index when it recreates the
  /// pickers (edit_birthday_box.cpp:111-118, 155-162).
  void _recomputeCounts() {
    final year = _selectedYear;
    _monthsCount = _monthsCountFor(year);
    if (_selectedMonth > _monthsCount) _selectedMonth = _monthsCount;
    _daysCount = _daysCountFor(_selectedMonth, year);
    if (_selectedDay > _daysCount) _selectedDay = _daysCount;
  }

  void _onYearChanged(int index) {
    setState(() {
      _selectedYearIndex = index;
      _recomputeCounts();
    });
  }

  void _onMonthChanged(int index) {
    setState(() {
      _selectedMonth = index + 1;
      _recomputeCounts();
    });
  }

  void _onDayChanged(int index) {
    setState(() => _selectedDay = index + 1);
  }

  // _itemsVisible.count = ceil(viewport / itemHeight) (vertical_drum_picker.cpp:115);
  // PageUp/PageDown jump a whole page = that many items (cpp:228,232).
  int get _pageItems => (_viewportHeight / _itemHeight).ceil();

  /// Box-level key handler, porting AyuGram's `install_event_filter` on the box
  /// that forwards every KeyPress to `years->handleKeyEvent`
  /// (edit_birthday_box.cpp:190-195 + vertical_drum_picker.cpp:224-234). Only the
  /// year wheel is keyboard-driven, exactly as in AyuGram. Up/Left → previous
  /// (earlier year), Down/Right → next, PageUp/PageDown → jump a page. PageUp/Down
  /// ignore auto-repeat (`!e->isAutoRepeat()`); arrows repeat while held.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final year = _yearKey.currentState;
    if (year == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final initialPress = event is KeyDownEvent; // not auto-repeat
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      year.jumpByItems(-1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      year.jumpByItems(1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.pageUp && initialPress) {
      year.jumpByItems(-_pageItems);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.pageDown && initialPress) {
      year.jumpByItems(_pageItems);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LangPack>();
    // All dialog chrome is theme-derived, exactly like AyuGram's box — never
    // hardcoded hex (which would ignore the user's theme): the surface is
    // `boxBg` (= `windowBg`, colors.palette:135), the title is `windowFg`
    // (st::defaultFlatLabel.textFg — the same color the wheel items use), and
    // every button is created with the box's default button style
    // `getDelegate()->style().button` = `lightButtonFg`, with NO
    // attention/destructive style for the reset button — so Save, Cancel and
    // Remove are all the same blue (edit_birthday_box.cpp:200,210,214 +
    // box_content.cpp:128-168).
    final bgColor = context.palette.windowBg;
    final textColor = context.palette.windowFg;
    final buttonColor = context.palette.lightButtonFg;
    // Items use one uniform font (st::boxTextFont = 14px) and one color
    // (st::defaultFlatLabel.textFg = windowFg); the centered row is set apart
    // only by the opacity fade + vertical squish, not by size/weight/color
    // (vertical_drum_picker.cpp:40-47, edit_birthday_box.cpp:38).
    final itemStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: context.palette.windowFg,
    );
    final bandColor = context.palette.activeLineFg;

    // Box-level keyboard capture: autofocus so arrow/PageUp/PageDown reach
    // [_handleKey] as soon as the dialog opens, mirroring AyuGram installing an
    // event filter on the whole box (edit_birthday_box.cpp:190-195). Unhandled
    // keys return `ignored`, so Tab/Enter still drive the buttons normally.
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Dialog(
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
                height: _viewportHeight,
                child: Stack(
                  children: [
                    // Wheel order matches AyuGram: day | month | year, widths
                    // quarter | half | quarter (edit_birthday_box.cpp:92-99).
                    Row(
                      children: [
                        Flexible(
                          flex: 1,
                          child: _VerticalDrumPicker(
                            key: ValueKey('day-$_daysCount'),
                            itemCount: _daysCount,
                            initialIndex: _selectedDay - 1,
                            viewportHeight: _viewportHeight,
                            itemHeight: _itemHeight,
                            textStyle: itemStyle,
                            labelBuilder: (i) => '${i + 1}',
                            onChanged: _onDayChanged,
                          ),
                        ),
                        Flexible(
                          flex: 2,
                          child: _VerticalDrumPicker(
                            key: ValueKey('month-$_monthsCount'),
                            itemCount: _monthsCount,
                            initialIndex: _selectedMonth - 1,
                            viewportHeight: _viewportHeight,
                            itemHeight: _itemHeight,
                            textStyle: itemStyle,
                            // Localized month names — AyuGram paints
                            // `Lang::Month(index + 1)(tr::now)`
                            // (edit_birthday_box.cpp:119-124), i.e. the cloud
                            // pack's `lng_month1..12` with an English baseline.
                            labelBuilder: (i) => lang.tr('lng_month${i + 1}'),
                            onChanged: _onMonthChanged,
                          ),
                        ),
                        Flexible(
                          flex: 1,
                          child: _VerticalDrumPicker(
                            key: _yearKey,
                            itemCount: _yearCount,
                            initialIndex: _selectedYearIndex,
                            viewportHeight: _viewportHeight,
                            itemHeight: _itemHeight,
                            textStyle: itemStyle,
                            labelBuilder: (i) =>
                                i < _yearCount - 1 ? '${_minYear + i}' : '—',
                            onChanged: _onYearChanged,
                          ),
                        ),
                      ],
                    ),
                    // Selection-frame indicator: two horizontal activeLineFg
                    // lines bracketing the centered item at height/2 ± itemHeight/2
                    // (edit_birthday_box.cpp:181-187).
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (_viewportHeight - _itemHeight) / 2,
                      height: _itemHeight,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.symmetric(
                              horizontal: BorderSide(color: bandColor, width: _bandBorder),
                            ),
                          ),
                        ),
                      ),
                    ),
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
                        child: Text('Remove', style: TextStyle(color: buttonColor)),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: buttonColor)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(
                          (day: _selectedDay, month: _selectedMonth, year: _selectedYear),
                        );
                      },
                      child: Text(widget.saveLabel, style: TextStyle(color: buttonColor)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// A single vertical drum wheel, porting AyuGram's `VerticalDrumPicker`
/// (`ui/widgets/vertical_drum_picker.cpp`). Every item is painted with one
/// uniform [textStyle]; the centered item is distinguished only by a continuous
/// opacity fade (`setOpacity(revProgress)`) and a vertical squish
/// (`yScale = 0.2 + 0.8·easeOutCubic(revProgress)`), exactly as AyuGram's
/// `DefaultPaintCallback` (vertical_drum_picker.cpp:25-50).
class _VerticalDrumPicker extends StatefulWidget {
  final int itemCount;
  final int initialIndex;
  final double viewportHeight;
  final double itemHeight;
  final TextStyle textStyle;
  final String Function(int index) labelBuilder;
  final ValueChanged<int> onChanged;

  const _VerticalDrumPicker({
    super.key,
    required this.itemCount,
    required this.initialIndex,
    required this.viewportHeight,
    required this.itemHeight,
    required this.textStyle,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  State<_VerticalDrumPicker> createState() => _VerticalDrumPickerState();
}

class _VerticalDrumPickerState extends State<_VerticalDrumPicker>
    with SingleTickerProviderStateMixin {
  // kMinYScale (vertical_drum_picker.cpp:19).
  static const double _kMinYScale = 0.2;

  late double _scrollOffset;
  late int _selectedIndex;
  // All movement — drag-end snap, tap-to-select, wheel notch, keyboard step —
  // funnels through this single controller, which interpolates _scrollOffset
  // *linearly* from _animFrom to _animTo over `fadeWrapDuration` (200 ms). This
  // mirrors AyuGram's `PickerAnimation::jumpToOffset`, animated with the default
  // transition `anim::linear` + `anim::interpolateF` (vertical_drum_picker.cpp:
  // 83-87, animations.h:67). The easeOutCubic curve is reserved for the per-item
  // yScale squish in paint (DefaultPaintCallback), NOT the scroll snap.
  late AnimationController _snapController;
  double _animFrom = 0;
  double _animTo = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, widget.itemCount - 1);
    _scrollOffset = _selectedIndex * widget.itemHeight;
    // st::fadeWrapDuration = 200 ms (vertical_drum_picker.cpp:87). The controller
    // value advances linearly and we interpolate linearly — AyuGram's snap is
    // `anim::linear`, not eased (the squish easing lives in paint, below).
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _scrollOffset =
              _animFrom + (_animTo - _animFrom) * _snapController.value;
          _updateSelected();
        });
      });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double get _maxOffset => (widget.itemCount - 1) * widget.itemHeight;

  void _updateSelected() {
    final idx =
        (_scrollOffset / widget.itemHeight).round().clamp(0, widget.itemCount - 1);
    if (idx != _selectedIndex) {
      _selectedIndex = idx;
      widget.onChanged(idx);
    }
  }

  /// Animate _scrollOffset to [targetOffset] (clamped) over 200 ms, linearly —
  /// the Dart-side equivalent of `PickerAnimation::jumpToOffset`.
  void _animateTo(double targetOffset) {
    _snapController.stop();
    _animFrom = _scrollOffset;
    _animTo = targetOffset.clamp(0.0, _maxOffset);
    _snapController.forward(from: 0);
  }

  /// Snap the nearest item to the centre band after a free drag
  /// (vertical_drum_picker.cpp:250-251 — `animationDataFromIndex` + jumpToOffset(0)).
  void _snapToNearest() {
    final nearest = (_scrollOffset / widget.itemHeight).round();
    _animateTo(nearest * widget.itemHeight);
  }

  /// Step the wheel by [delta] items (positive = toward higher indices / "next"),
  /// one decisive animated jump. Used by the mouse wheel (one item per notch) and
  /// the box keyboard handler. Like AyuGram's `jumpToOffset`, repeated jumps
  /// accumulate onto the in-flight destination rather than restarting from the
  /// live offset, so a fast wheel-spin or held arrow key lands cleanly
  /// (vertical_drum_picker.cpp:54-57,200,226-232).
  void jumpByItems(int delta) {
    if (delta == 0 || widget.itemCount <= 1) return;
    final base = _snapController.isAnimating
        ? (_animTo / widget.itemHeight).round()
        : (_scrollOffset / widget.itemHeight).round();
    final target = (base + delta).clamp(0, widget.itemCount - 1);
    _animateTo(target * widget.itemHeight);
  }

  @override
  Widget build(BuildContext context) {
    final itemHeight = widget.itemHeight;
    final viewportHeight = widget.viewportHeight;
    final centerY = viewportHeight / 2;
    final topBase = (viewportHeight - itemHeight) / 2;

    final items = <Widget>[];
    for (var i = 0; i < widget.itemCount; i++) {
      final top = topBase + i * itemHeight - _scrollOffset;
      // Cull items fully outside the viewport (only ~5 are ever visible).
      if (top > viewportHeight || top + itemHeight < 0) continue;

      // distanceFromCenter = ((y + itemHeight/2) - centerY) / centerY
      // (vertical_drum_picker.cpp:148).
      final distance = (top + itemHeight / 2 - centerY) / centerY;
      final revProgress = (1.0 - distance.abs()).clamp(0.0, 1.0);
      final yScale = _kMinYScale + (1.0 - _kMinYScale) * _easeOutCubic(revProgress);

      items.add(Positioned(
        left: 0,
        right: 0,
        top: top,
        height: itemHeight,
        child: Opacity(
          opacity: revProgress,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(1.0, yScale, 1.0),
            child: Center(
              child: Text(widget.labelBuilder(i), style: widget.textStyle),
            ),
          ),
        ),
      ));
    }

    return SizedBox(
      height: viewportHeight,
      child: Listener(
        // One item per wheel notch, animated — AyuGram's `handleWheelEvent` calls
        // `jumpToOffset(direction)` with the discrete `Ui::WheelDirection`, never
        // the raw pixel delta (vertical_drum_picker.cpp:197-201). Using the sign
        // (not the magnitude) of scrollDelta keeps a single notch to one step.
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final dy = event.scrollDelta.dy;
            if (dy > 0) {
              jumpByItems(1);
            } else if (dy < 0) {
              jumpByItems(-1);
            }
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) {
            _snapController.stop();
            setState(() {
              _scrollOffset = (_scrollOffset - d.delta.dy).clamp(0.0, _maxOffset);
              _updateSelected();
            });
          },
          onVerticalDragEnd: (_) => _snapToNearest(),
          // Click any visible row to bring it to the centre band. AyuGram's
          // `handleMouseEvent` release-without-drag computes
          // `toOffset = centerOffset - clickY/itemHeight` and animates to it
          // (vertical_drum_picker.cpp:252-256); the item under the cursor here is
          // `floor((clickY - topBase + scrollOffset) / itemHeight)`, the same
          // target expressed in the Dart scroll model. A drag wins the gesture
          // arena instead, so onTapUp fires only for genuine clicks (AyuGram's
          // `_mouse.clickDisabled` guard).
          onTapUp: (details) {
            final i = ((details.localPosition.dy - topBase + _scrollOffset) /
                    itemHeight)
                .floor()
                .clamp(0, widget.itemCount - 1);
            _animateTo(i * itemHeight);
          },
          child: ClipRect(child: Stack(children: items)),
        ),
      ),
    );
  }

  // anim::easeOutCubic(1., t) == (t-1)^3 + 1 (animation_value.cpp:94-101).
  double _easeOutCubic(double t) {
    final x = t - 1.0;
    return x * x * x + 1.0;
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
