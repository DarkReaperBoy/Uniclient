import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import 'chat_list_row.dart' show SavedMessagesUserpic;
import 'forum_topic_icon.dart';

const _cellWidth = 72.0;
const _cellHeight = 104.0;
const _userpicSize = 56.0;
const _userpicTop = 8.0;
const _nameSkip = 6.0;
const _selectLineWidth = 3.0;
const _panelMargin = 16.0;
const _panelPadding = 12.0;
const _panelRadius = 6.0;
const _maxPerRow = 7;
const _maxRows = 3;

const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

class ChatSwitchOverlay extends StatefulWidget {
  final List<ChatInfo> chats;
  final int initialIndex;

  /// Whether the switcher was opened by the reverse gesture (Ctrl+Shift+Tab).
  /// AyuGram always opens with `_selected = 0` (the current chat, rotated to
  /// front) and then immediately runs the *initiating* Tab/Backtab through
  /// `process(request)` (window_session_controller.cpp:1927), advancing the
  /// selection by one before the first paint: forward (Tab) → index 1 (the
  /// previously-used chat), reverse (Backtab) → the last shown chat
  /// (window_chat_switch_process.cpp:253-266). We replicate that initiating
  /// step on the first layout pass so a single tap-and-release of Ctrl+Tab
  /// lands on the previous chat (classic alt-tab) instead of re-selecting the
  /// current one.
  final bool reverse;

  final void Function(ChatInfo chat) onChosen;
  final void Function(ChatInfo chat) onRemove;
  final VoidCallback onCancel;

  const ChatSwitchOverlay({
    super.key,
    required this.chats,
    this.initialIndex = 0,
    this.reverse = false,
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

  /// AyuGram opens with `_selected = 0` and immediately runs the initiating
  /// Tab/Backtab through `process()` before the first paint, advancing the
  /// selection by one. We apply that single step on the first layout pass
  /// (when the real shown-cell count is known) — see [ChatSwitchOverlay.reverse].
  bool _pendingInitialStep = true;

  final Map<String, Uint8List> _avatarCache = {};
  /// Cached ChatState ref captured when the listener is added, so dispose() can
  /// remove the listener from the exact same object without a context provider
  /// lookup — looking up an inherited widget via context in dispose() throws
  /// "deactivated widget's ancestor is unsafe".
  ChatState? _chatStateRef;

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.chats);
    _selected = widget.initialIndex.clamp(0, _list.length - 1);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenToChatState();
    });
  }

  void _listenToChatState() {
    final chatState = context.read<ChatState>();
    _chatStateRef = chatState;
    chatState.addListener(_onChatStateChanged);
  }

  void _onChatStateChanged() {
    if (!mounted) return;
    final chatState = context.read<ChatState>();
    final currentIds = chatState.chats.map((c) => c.chatId).toSet();
    final removed = _list.where((c) => !currentIds.contains(c.chatId)).toList();
    if (removed.isEmpty) {
      setState(() {});
      return;
    }
    setState(() {
      for (final chat in removed) {
        final idx = _list.indexOf(chat);
        if (idx < 0) continue;
        _list.removeAt(idx);
        if (_selected > idx) {
          _selected--;
        } else if (_selected == idx) {
          if (_list.isEmpty) {
            widget.onCancel();
            return;
          }
          _selected = (_selected > 0 ? _selected - 1 : 0)
              .clamp(0, _list.length - 1);
        }
      }
      if (_list.isEmpty) {
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _chatStateRef?.removeListener(_onChatStateChanged);
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
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveNext();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _movePrev();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveDown();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveUp();
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
    final count = _shownCount;
    setState(() {
      _selected = (_selected + 1) % count;
    });
  }

  void _movePrev() {
    if (_list.isEmpty) return;
    final count = _shownCount;
    setState(() {
      _selected = (_selected - 1 + count) % count;
    });
  }

  void _moveDown() {
    if (_list.isEmpty) return;
    final count = _shownCount;
    setState(() {
      final now = _selected + _shownPerRow;
      _selected = (now >= count) ? (now - count) : now;
    });
  }

  void _moveUp() {
    if (_list.isEmpty) return;
    final count = _shownCount;
    setState(() {
      final now = _selected - _shownPerRow;
      _selected = (now < 0) ? (count + now) : now;
    });
  }

  int get _shownCount => (_shownPerRow * _shownRows).clamp(1, _list.length);

  void _removeSelected() {
    if (_list.isEmpty || _selected < 0 || _selected >= _list.length) return;
    final chat = _list[_selected];
    widget.onRemove(chat);
    setState(() {
      _list.removeAt(_selected);
      if (_list.isEmpty) {
        widget.onCancel();
        return;
      }
      _selected = (_selected > 0 ? _selected - 1 : 0)
          .clamp(0, _shownCount.clamp(1, _list.length) - 1);
    });
  }

  void _confirm() {
    if (_list.isEmpty || _selected < 0 || _selected >= _list.length) {
      widget.onCancel();
      return;
    }
    widget.onChosen(_list[_selected]);
  }

  Uint8List _decodeAvatar(String base64Str) {
    return _avatarCache.putIfAbsent(base64Str, () => base64Decode(base64Str));
  }

  @override
  Widget build(BuildContext context) {
    if (_list.length < 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCancel());
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = context.palette;
    final boxBg = p.boxBg;
    final accentColor = p.windowBgActive;
    final nameColor = p.boxTextFg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availWidth = constraints.maxWidth - _panelMargin * 2 - _panelPadding * 2;
        final canPerRow = (availWidth / _cellWidth).floor().clamp(1, _list.length);

        final count = _list.length;
        final canRows = (canPerRow > 2 * 7)
            ? 1
            : (canPerRow > 3 * 4)
                ? 2
                : 3;

        var rows = (count + canPerRow - 1) ~/ canPerRow;
        if (rows > canRows) rows = canRows;
        var perRow = count ~/ rows;
        if (perRow > canPerRow) perRow = canPerRow;

        if (rows > 2) {
          if (perRow * 2 > rows * 4) {
            rows = 2;
          } else if (perRow > 4) {
            perRow = 4;
          }
        }
        if (rows > 1) {
          if (perRow > rows * 7) {
            rows = 1;
          } else if (perRow > 7) {
            perRow = 7;
          }
        }
        rows = rows.clamp(1, _maxRows);
        if (perRow < 1) perRow = 1;

        final visible = (perRow * rows).clamp(1, count);

        // Run AyuGram's initiating Tab (forward) / Backtab (reverse) the moment
        // the switcher opens — the keypress that opened it was consumed by the
        // global shortcut handler, so the overlay must advance the selection off
        // the current chat (index 0) itself. Done here on the first build, when
        // the real shown-cell count (`visible`) is finally known, so there is no
        // extra frame and no flash of the current chat being pre-selected.
        // forward → index 1 (previously-used chat); reverse → last shown chat;
        // a single shown cell stays at 0 (matches window_chat_switch_process.cpp
        // :253-266 with `_shownCount == 1`).
        if (_pendingInitialStep) {
          _pendingInitialStep = false;
          if (visible > 1) {
            _selected = widget.reverse
                ? (_selected - 1 + visible) % visible
                : (_selected + 1) % visible;
          } else {
            _selected = 0;
          }
        }

        final innerW = perRow * _cellWidth;

        if (_shownPerRow != perRow || _shownRows != rows) {
          final newPerRow = perRow;
          final newRows = rows;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                (_shownPerRow != newPerRow || _shownRows != newRows)) {
              setState(() {
                _shownPerRow = newPerRow;
                _shownRows = newRows;
              });
            }
          });
        }

        final effectiveSelected = _selected >= visible ? visible - 1 : _selected;
        if (_selected != effectiveSelected) {
          final clamped = effectiveSelected;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selected != clamped) {
              setState(() => _selected = clamped);
            }
          });
        }

        return GestureDetector(
          // AyuGram draws NO whole-window dim: setupWidget only shows the widget
          // and installs a mouse-press-to-close handler with no background paint
          // (window_chat_switch_process.cpp:298-316), and setupView's paint
          // handler draws only the panel rect — `_outer` drop shadow + `_bg`
          // rounded box (:403-411). The rest of the UI stays at full brightness
          // with the panel floating above it. HitTestBehavior.opaque preserves
          // tap-anywhere-to-close without painting a dimming layer.
          behavior: HitTestBehavior.opaque,
          onTap: widget.onCancel,
          child: Center(
            // AyuGram absorbs every MouseButtonPress that lands on the panel:
            // _view's event handler accept()s the press
            // (window_chat_switch_process.cpp:413-417), so only presses on the
            // surrounding _widget (outside the panel) fire _closeRequests
            // (:307-313). Cells tile edge-to-edge with no inter-cell gaps, so the
            // 12px padding ring is the only non-cell region of the panel — without
            // this absorber a tap there bubbles up to the outer onTap and wrongly
            // cancels the switcher. The empty onTap wins the gesture arena over
            // the outer detector (the innermost tap recognizer takes the sweep),
            // so a click on the panel padding is a no-op instead of a close.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
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
                    final selected = i == effectiveSelected;

                    Uint8List? decodedParentAvatar;
                    if (chat.type == ChatType.topic && chat.parentId.isNotEmpty) {
                      final chatState = context.read<ChatState>();
                      final parentChat = chatState.chats.cast<ChatInfo?>().firstWhere(
                        (c) => c!.chatId == chat.parentId && c.accountId == chat.accountId,
                        orElse: () => null,
                      );
                      if (parentChat != null &&
                          parentChat.avatarPath.isNotEmpty &&
                          !parentChat.avatarPath.startsWith('/')) {
                        decodedParentAvatar = _decodeAvatar(parentChat.avatarPath);
                      }
                    }

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
                          decodedAvatar: chat.avatarPath.isNotEmpty &&
                                  !chat.avatarPath.startsWith('/')
                              ? _decodeAvatar(chat.avatarPath)
                              : null,
                          decodedParentAvatar: decodedParentAvatar,
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
  final Uint8List? decodedAvatar;
  final Uint8List? decodedParentAvatar;

  const _ChatSwitchCell({
    required this.chat,
    required this.selected,
    required this.accentColor,
    required this.nameColor,
    required this.isDark,
    this.decodedAvatar,
    this.decodedParentAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cellWidth,
      height: _cellHeight,
      child: Stack(
        children: [
          AnimatedOpacity(
            opacity: selected ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accentColor, width: _selectLineWidth),
              ),
            ),
          ),
          Column(
            children: [
              SizedBox(height: _userpicTop),
              _buildAvatar(context, context.palette),
              Expanded(
                child: Center(
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
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBaseUserpic(TelegramPalette palette, double size) {
    if (chat.avatarPath.isNotEmpty) {
      if (decodedAvatar != null) {
        return ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: Image.memory(decodedAvatar!,
                width: size, height: size, fit: BoxFit.cover),
          ),
        );
      }
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.file(File(chat.avatarPath),
              width: size, height: size, fit: BoxFit.cover),
        ),
      );
    }

    final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
    final color = palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
    final initials = _initials(chat.title);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, TelegramPalette palette) {
    if (chat.isSelf) {
      return const SavedMessagesUserpic(size: _userpicSize);
    }

    if (chat.type == ChatType.topic) {
      final topicId = int.tryParse(chat.chatId) ?? 0;
      final isGeneral = topicId == 1;
      final chatState = context.read<ChatState>();
      final engine = context.read<EngineService>();
      final topics = chat.parentId.isNotEmpty
          ? chatState.recentTopicsFor(chat.accountId, chat.parentId)
          : <ForumTopic>[];
      final forumTopic = topics.cast<ForumTopic?>().firstWhere(
        (t) => t!.id == chat.chatId,
        orElse: () => null,
      );
      final topicColorId = forumTopic?.colorId ?? 0x6FB9F0;

      Widget primaryIcon;
      if (forumTopic != null && forumTopic.hasCustomIcon) {
        primaryIcon = CustomEmojiTopicIcon(
          documentId: forumTopic.iconEmojiId,
          accountId: chat.accountId,
          engine: engine,
          size: _userpicSize,
        );
      } else if (isGeneral) {
        primaryIcon = GeneralForumTopicIcon(size: _userpicSize);
      } else {
        primaryIcon = ForumTopicIcon(
          colorId: topicColorId,
          title: chat.title,
          size: _userpicSize,
        );
      }

      final parentChat = chat.parentId.isNotEmpty
          ? chatState.chats.cast<ChatInfo?>().firstWhere(
              (c) => c!.chatId == chat.parentId && c.accountId == chat.accountId,
              orElse: () => null,
            )
          : null;

      Widget parentBadge;
      if (parentChat != null && parentChat.avatarPath.isNotEmpty) {
        if (!parentChat.avatarPath.startsWith('/')) {
          parentBadge = ClipOval(
            child: Image.memory(
                decodedParentAvatar ?? base64Decode(parentChat.avatarPath),
                width: 20, height: 20, fit: BoxFit.cover),
          );
        } else {
          parentBadge = ClipOval(
            child: Image.file(File(parentChat.avatarPath),
                width: 20, height: 20, fit: BoxFit.cover),
          );
        }
      } else {
        final pTitle = parentChat?.title ?? '';
        final numId = parentChat != null
            ? (int.tryParse(parentChat.chatId) ?? parentChat.chatId.hashCode.abs())
            : 0;
        final color = palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
        parentBadge = Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            pTitle.isNotEmpty ? pTitle[0].toUpperCase() : '#',
            style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500,
            ),
          ),
        );
      }

      return SizedBox(
        width: _userpicSize,
        height: _userpicSize,
        child: Stack(
          children: [
            SizedBox(
              width: _userpicSize,
              height: _userpicSize,
              child: primaryIcon,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.boxBg, width: 2),
                ),
                alignment: Alignment.center,
                child: parentBadge,
              ),
            ),
          ],
        ),
      );
    }

    if (chat.parentId.isNotEmpty && chat.type == ChatType.dm) {
      return SizedBox(
        width: _userpicSize,
        height: _userpicSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: _buildBaseUserpic(palette, 40),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.boxBg, width: 2),
                ),
                child: SavedMessagesUserpic(size: 24),
              ),
            ),
          ],
        ),
      );
    }

    return _buildBaseUserpic(palette, _userpicSize);
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
