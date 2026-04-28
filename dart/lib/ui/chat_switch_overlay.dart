import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/engine_models.dart';

const _cellWidth = 72.0;
const _cellHeight = 104.0;
const _userpicSize = 46.0;
const _userpicTop = 8.0;
const _nameSkip = 6.0;
const _selectLineWidth = 3.0;
const _panelMargin = 16.0;
const _panelPadding = 12.0;
const _panelRadius = 12.0;
const _maxPerRow = 7;
const _maxRows = 3;

const _avatarColors = [
  Color(0xFFe17076),
  Color(0xFF7bc862),
  Color(0xFFe5ca77),
  Color(0xFF65aadd),
  Color(0xFFa695e7),
  Color(0xFFee7aae),
  Color(0xFF6ec9cb),
];

class ChatSwitchOverlay extends StatefulWidget {
  final List<ChatInfo> chats;
  final int initialIndex;
  final void Function(ChatInfo chat) onChosen;
  final void Function(ChatInfo chat) onRemove;
  final VoidCallback onCancel;

  const ChatSwitchOverlay({
    super.key,
    required this.chats,
    this.initialIndex = 1,
    required this.onChosen,
    required this.onRemove,
    required this.onCancel,
  });

  @override
  State<ChatSwitchOverlay> createState() => _ChatSwitchOverlayState();
}

class _ChatSwitchOverlayState extends State<ChatSwitchOverlay> {
  late int _selected;
  late List<ChatInfo> _list;
  int _shownPerRow = 1;
  int _shownRows = 1;

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.chats);
    _selected = widget.initialIndex.clamp(0, _list.length - 1);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight ||
          event.logicalKey == LogicalKeyboardKey.metaLeft ||
          event.logicalKey == LogicalKeyboardKey.metaRight) {
        _confirm();
        return true;
      }
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _movePrev();
      } else {
        _moveNext();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
      _moveNext();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
      _movePrev();
      return true;
    }
    if (key == LogicalKeyboardKey.keyQ) {
      _removeSelected();
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return true;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _confirm();
      return true;
    }
    return false;
  }

  void _moveNext() {
    if (_list.isEmpty) return;
    final visible = _shownPerRow * _shownRows;
    setState(() {
      _selected = (_selected + 1) % visible.clamp(1, _list.length);
    });
  }

  void _movePrev() {
    if (_list.isEmpty) return;
    final visible = _shownPerRow * _shownRows;
    final max = visible.clamp(1, _list.length);
    setState(() {
      _selected = (_selected - 1 + max) % max;
    });
  }

  void _removeSelected() {
    if (_list.isEmpty || _selected >= _list.length) return;
    final chat = _list[_selected];
    widget.onRemove(chat);
    setState(() {
      _list.removeAt(_selected);
      if (_list.isEmpty) {
        widget.onCancel();
        return;
      }
      if (_selected >= _list.length) _selected = _list.length - 1;
    });
  }

  void _confirm() {
    if (_list.isEmpty || _selected >= _list.length) {
      widget.onCancel();
      return;
    }
    widget.onChosen(_list[_selected]);
  }

  @override
  Widget build(BuildContext context) {
    if (_list.length < 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCancel());
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayColor = Colors.black.withValues(alpha: isDark ? 0.5 : 0.3);
    final boxBg = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final nameColor = isDark ? Colors.white : const Color(0xFF222222);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availWidth = constraints.maxWidth - _panelMargin * 2 - _panelPadding * 2;
        final canPerRow = (availWidth / _cellWidth).floor().clamp(1, _list.length);

        int rows, perRow;
        if (canPerRow > 14) {
          rows = 1;
        } else if (canPerRow > 12) {
          rows = 2;
        } else {
          rows = 3;
        }

        final total = _list.length;
        if (rows > 1 && total <= canPerRow) rows = 1;
        if (rows > 2 && total <= canPerRow * 2) rows = 2;
        rows = rows.clamp(1, _maxRows);

        perRow = (total / rows).ceil().clamp(1, canPerRow);
        if (rows > 1 && perRow > _maxPerRow) perRow = _maxPerRow;
        if (rows > 2 && perRow > 4) perRow = 4;

        _shownPerRow = perRow;
        _shownRows = rows;

        final visible = (perRow * rows).clamp(1, total);
        final innerW = perRow * _cellWidth;
        final innerH = rows * _cellHeight;

        return GestureDetector(
          onTap: widget.onCancel,
          child: Container(
            color: overlayColor,
            child: Center(
              child: Container(
                width: innerW + _panelPadding * 2,
                decoration: BoxDecoration(
                  color: boxBg,
                  borderRadius: BorderRadius.circular(_panelRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(_panelPadding),
                child: Wrap(
                  children: List.generate(visible.clamp(0, _list.length), (i) {
                    final chat = _list[i];
                    final selected = i == _selected;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selected = i);
                        _confirm();
                      },
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _selected = i),
                        child: _ChatSwitchCell(
                          chat: chat,
                          selected: selected,
                          accentColor: accentColor,
                          nameColor: nameColor,
                          isDark: isDark,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChatSwitchCell extends StatelessWidget {
  final ChatInfo chat;
  final bool selected;
  final Color accentColor;
  final Color nameColor;
  final bool isDark;

  const _ChatSwitchCell({
    required this.chat,
    required this.selected,
    required this.accentColor,
    required this.nameColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: _cellWidth,
      height: _cellHeight,
      decoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor, width: _selectLineWidth),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(height: _userpicTop),
          _buildAvatar(),
          const SizedBox(height: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _nameSkip),
              child: Text(
                chat.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: nameColor,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final isSaved = chat.title == 'Saved Messages' && chat.type == ChatType.dm;

    if (isSaved) {
      return Container(
        width: _userpicSize,
        height: _userpicSize,
        decoration: const BoxDecoration(
          color: Color(0xFF65AADD),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.bookmark, color: Colors.white, size: 24),
      );
    }

    if (chat.avatarPath.isNotEmpty) {
      final isBase64 = !chat.avatarPath.startsWith('/');
      return ClipOval(
        child: SizedBox(
          width: _userpicSize,
          height: _userpicSize,
          child: isBase64
              ? Image.memory(base64Decode(chat.avatarPath),
                  width: _userpicSize, height: _userpicSize, fit: BoxFit.cover)
              : Image.file(File(chat.avatarPath),
                  width: _userpicSize, height: _userpicSize, fit: BoxFit.cover),
        ),
      );
    }

    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];
    final initials = _initials(chat.title);

    return Container(
      width: _userpicSize,
      height: _userpicSize,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  static String _initials(String name) {
    if (name.isEmpty) return '';
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return words[0][0].toUpperCase();
  }
}
