import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/telegram_palette.dart';
import 'forum_topic_icon.dart';

const double _boxMaxHeight = 408;
const double _boxWidth = 364;
const double _boxRadius = 3;
const double _boxTitleHeight = 48;

const double _iconButtonSize = 26;
const double _gridCellSize = 40;
const double _gridIconSize = 26;
const double _gridPadding = 8;

const List<int> _topicColorIds = [
  0x6FB9F0,
  0xFFD67E,
  0xCB86DB,
  0x8EEE98,
  0xFF93B2,
  0xFB6F5F,
];

/// Default topic icon emoji set (inputStickerSetEmojiDefaultTopicIcons).
/// These are free for all users — no Premium required.
const List<String> _defaultTopicEmojiIcons = [
  '\u{1F4AC}', // 💬
  '\u{1F4E2}', // 📢
  '\u{1F4DD}', // 📝
  '\u{1F4CA}', // 📊
  '\u{1F4C1}', // 📁
  '\u{1F4CC}', // 📌
  '\u{1F4A1}', // 💡
  '\u{2B50}',  // ⭐
  '\u{2753}',  // ❓
  '\u{2757}',  // ❗
  '\u{1F514}', // 🔔
  '\u{1F3AF}', // 🎯
  '\u{1F3C6}', // 🏆
  '\u{1F512}', // 🔒
  '\u{2699}',  // ⚙
  '\u{1F4E3}', // 📣
  '\u{1F4D6}', // 📖
  '\u{1F517}', // 🔗
  '\u{1F4F7}', // 📷
  '\u{1F3B5}', // 🎵
  '\u{1F3AE}', // 🎮
  '\u{1F4B0}', // 💰
  '\u{2764}',  // ❤
  '\u{1F680}', // 🚀
];

/// Codepoints of default topic icons — selection of these is free.
final Set<int> _defaultTopicEmojiCodepoints = {
  for (final e in _defaultTopicEmojiIcons) e.runes.first,
};

Future<EditForumTopicResult?> showEditForumTopicBox(
  BuildContext context, {
  String? existingTitle,
  int? existingColorId,
  int? existingIconEmojiId,
  bool isGeneral = false,
  bool isBot = false,
  bool isEditing = false,
  bool isPremium = false,
  List<String>? serverEmojiIcons,
}) {
  return showDialog<EditForumTopicResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EditForumTopicDialog(
      existingTitle: existingTitle,
      existingColorId: existingColorId,
      existingIconEmojiId: existingIconEmojiId,
      isGeneral: isGeneral,
      isBot: isBot,
      isEditing: isEditing,
      isPremium: isPremium,
      serverEmojiIcons: serverEmojiIcons,
    ),
  );
}

class EditForumTopicResult {
  final String title;
  final int colorId;
  final int iconEmojiId;

  const EditForumTopicResult({
    required this.title,
    required this.colorId,
    this.iconEmojiId = 0,
  });
}

class _EditForumTopicDialog extends StatefulWidget {
  final String? existingTitle;
  final int? existingColorId;
  final int? existingIconEmojiId;
  final bool isGeneral;
  final bool isBot;
  final bool isEditing;
  final bool isPremium;
  final List<String>? serverEmojiIcons;

  const _EditForumTopicDialog({
    this.existingTitle,
    this.existingColorId,
    this.existingIconEmojiId,
    this.isGeneral = false,
    this.isBot = false,
    this.isEditing = false,
    this.isPremium = false,
    this.serverEmojiIcons,
  });

  @override
  State<_EditForumTopicDialog> createState() => _EditForumTopicDialogState();
}

class _EditForumTopicDialogState extends State<_EditForumTopicDialog>
    with TickerProviderStateMixin {
  late final TextEditingController _titleController;
  late int _colorId;
  late int _iconEmojiId;
  String? _selectedEmojiStr;
  late List<int> _remainingColors;
  late List<String> _emojiIcons;
  bool _titleError = false;

  final GlobalKey _iconButtonKey = GlobalKey();
  OverlayEntry? _flyOverlay;
  AnimationController? _flyController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingTitle ?? '');
    _colorId = widget.existingColorId ?? _topicColorIds[0];
    _iconEmojiId = widget.existingIconEmojiId ?? 0;
    _emojiIcons = widget.serverEmojiIcons ?? _defaultTopicEmojiIcons;
    if (_iconEmojiId != 0) {
      _selectedEmojiStr = String.fromCharCode(_iconEmojiId);
    }
    _remainingColors = List.of(_topicColorIds)..remove(_colorId);
    _titleController.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _flyOverlay?.remove();
    _flyOverlay = null;
    _flyController?.stop();
    _flyController?.dispose();
    _flyController = null;
    super.dispose();
  }

  void _onTitleChanged() {
    if (_titleError) {
      setState(() => _titleError = false);
    }
    setState(() {});
  }

  void _cycleColor() {
    if (_iconEmojiId != 0) return;
    if (widget.isEditing) return;

    setState(() {
      if (_remainingColors.isEmpty) {
        _remainingColors = List.of(_topicColorIds)..remove(_colorId);
      }
      final idx = math.Random().nextInt(_remainingColors.length);
      _colorId = _remainingColors.removeAt(idx);
    });
  }

  void _selectColorFromGrid(int colorId) {
    setState(() {
      _colorId = colorId;
      _iconEmojiId = 0;
      _selectedEmojiStr = null;
      _remainingColors = List.of(_topicColorIds)..remove(_colorId);
    });
  }

  void _startFlyAnimation(BuildContext gridCellContext, String emoji) {
    final buttonBox = _iconButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final cellBox = gridCellContext.findRenderObject() as RenderBox?;
    if (buttonBox == null || cellBox == null) return;
    if (!buttonBox.hasSize || !cellBox.hasSize) return;

    final cellPos = cellBox.localToGlobal(Offset.zero);
    final buttonPos = buttonBox.localToGlobal(Offset.zero);

    if (cellPos.dx.isNaN || cellPos.dy.isNaN || cellPos.dx.isInfinite || cellPos.dy.isInfinite) return;
    if (buttonPos.dx.isNaN || buttonPos.dy.isNaN || buttonPos.dx.isInfinite || buttonPos.dy.isInfinite) return;

    final overlay = Overlay.of(context);
    final cellSize = cellBox.size;
    final buttonSize = buttonBox.size;

    final startCenter = cellPos + Offset(cellSize.width / 2, cellSize.height / 2);
    final endCenter = buttonPos + Offset(buttonSize.width / 2, buttonSize.height / 2);

    _flyOverlay?.remove();
    _flyOverlay = null;
    _flyController?.stop();
    _flyController?.dispose();
    _flyController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    final posAnim = Tween<Offset>(begin: startCenter, end: endCenter)
        .animate(CurvedAnimation(parent: _flyController!, curve: Curves.easeInOutCubic));
    final scaleAnim = Tween<double>(begin: 1.0, end: _iconButtonSize / _gridIconSize)
        .animate(CurvedAnimation(parent: _flyController!, curve: Curves.easeInOutCubic));

    _flyOverlay = OverlayEntry(builder: (ctx) {
      return AnimatedBuilder(
        animation: _flyController!,
        builder: (_, __) {
          final pos = posAnim.value;
          final scale = scaleAnim.value;
          final iconSize = _gridIconSize * scale;
          final left = pos.dx - iconSize / 2;
          final top = pos.dy - iconSize / 2;
          if (left.isNaN || top.isNaN || left.isInfinite || top.isInfinite) {
            return const SizedBox.shrink();
          }
          return Positioned(
            left: left,
            top: top,
            child: IgnorePointer(
              child: Opacity(
                opacity: 1.0 - _flyController!.value * 0.3,
                child: SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: Center(
                    child: Text(emoji, style: TextStyle(fontSize: iconSize * 0.85)),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
    overlay.insert(_flyOverlay!);

    _flyController!.forward().then((_) {
      if (mounted) {
        _flyOverlay?.remove();
        _flyOverlay = null;
      }
    });
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    Navigator.of(context).pop(EditForumTopicResult(
      title: title,
      colorId: _colorId,
      iconEmojiId: _iconEmojiId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = context.palette.boxBg;

    final String dialogTitle;
    if (widget.isEditing) {
      dialogTitle = widget.isBot ? 'Edit Thread' : 'Edit Topic';
    } else {
      dialogTitle = widget.isBot ? 'New Thread' : 'New Topic';
    }

    final bool canCycleColor = _iconEmojiId == 0 && !widget.isEditing;

    return Dialog(
      backgroundColor: boxBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_boxRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _boxWidth,
          maxHeight: _boxMaxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTitleBar(dialogTitle, isDark),
            _buildPinnedTop(isDark, canCycleColor),
            if (!widget.isGeneral) _buildDividerText(isDark),
            if (!widget.isGeneral) _buildShadowSeparator(isDark),
            if (!widget.isGeneral)
              Flexible(child: _buildIconSelectorPanel(isDark)),
            _buildButtons(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(String title, bool isDark) {
    return Container(
      height: _boxTitleHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20,
              color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999)),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedTop(bool isDark, bool canCycleColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 22, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canCycleColor ? _cycleColor : null,
            child: MouseRegion(
              cursor: canCycleColor
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: KeyedSubtree(
                  key: _iconButtonKey,
                  child: widget.isGeneral
                      ? GeneralForumTopicIcon(
                          size: _iconButtonSize,
                          iconContext: GeneralIconContext.profile,
                        )
                      : (_iconEmojiId != 0 && _selectedEmojiStr != null)
                          ? SizedBox(
                              width: _iconButtonSize,
                              height: _iconButtonSize,
                              child: Center(
                                child: Text(
                                  _selectedEmojiStr!,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            )
                          : ForumTopicIcon(
                              colorId: _colorId,
                              title: _titleController.text,
                              size: _iconButtonSize,
                            ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _titleController,
              autofocus: true,
              maxLength: 128,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                hintText: widget.isBot ? 'Bot Thread Title' : 'Topic Name',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999),
                ),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3a4a5c) : const Color(0xFFdadce0),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: _titleError
                        ? const Color(0xFFe53935)
                        : const Color(0xFF40a7e3),
                    width: 2,
                  ),
                ),
                errorBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFe53935), width: 2),
                ),
                focusedErrorBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFe53935), width: 2),
                ),
                errorText: _titleError ? 'Please enter a topic name' : null,
                errorStyle: const TextStyle(fontSize: 12, color: Color(0xFFe53935)),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDividerText(bool isDark) {
    final text = widget.isBot
        ? 'Choose a title for the thread'
        : 'Choose a title and an icon for the topic';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
      color: isDark ? const Color(0xFF0e1621) : const Color(0xFFF1F3F5),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999),
        ),
      ),
    );
  }

  Widget _buildShadowSeparator(bool isDark) {
    return Container(
      height: 1,
      color: context.palette.shadowFg,
    );
  }

  void _selectEmoji(BuildContext cellContext, String emoji) {
    final codePoint = emoji.runes.first;
    if (!_defaultTopicEmojiCodepoints.contains(codePoint) && !widget.isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This icon requires Telegram Premium'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    _startFlyAnimation(cellContext, emoji);
    setState(() {
      _iconEmojiId = codePoint;
      _selectedEmojiStr = emoji;
    });
  }

  Widget _buildIconSelectorPanel(bool isDark) {
    final sectionLabelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.all(_gridPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text('Default Icons', style: sectionLabelStyle),
          ),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final colorId in _topicColorIds)
                _buildGridCell(colorId, isDark),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text('Topic Icons', style: sectionLabelStyle),
          ),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final emoji in _emojiIcons)
                _buildEmojiGridCell(emoji, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiGridCell(String emoji, bool isDark) {
    final codePoint = emoji.runes.first;
    final isSelected = _iconEmojiId == codePoint;
    final isFree = _defaultTopicEmojiCodepoints.contains(codePoint);
    return Builder(
      builder: (cellContext) => GestureDetector(
        onTap: () => _selectEmoji(cellContext, emoji),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: _gridCellSize,
            height: _gridCellSize,
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isDark
                        ? const Color(0xFF2b5278)
                        : const Color(0xFFE3F2FD),
                  )
                : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                if (!isFree && !widget.isPremium)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Icon(Icons.lock, size: 10,
                      color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridCell(int colorId, bool isDark) {
    final isSelected = _iconEmojiId == 0 && _colorId == colorId;
    return GestureDetector(
      onTap: () => _selectColorFromGrid(colorId),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: _gridCellSize,
          height: _gridCellSize,
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isDark
                      ? const Color(0xFF2b5278)
                      : const Color(0xFFE3F2FD),
                )
              : null,
          child: Center(
            child: ForumTopicIcon(
              colorId: colorId,
              title: _titleController.text,
              size: _gridIconSize,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF40a7e3),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _submit,
            child: Text(
              widget.isEditing ? 'Save' : 'Create',
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF40a7e3),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
