import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'chat_list_panel.dart';
import 'chat_list_row.dart';
import 'chat_view.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../utils/system_tray.dart';

enum ShortcutCommand {
  closeTelegram,
  lockTelegram,
  minimizeTelegram,
  quitTelegram,
  search,
  cancelSearch,
  chatPrevious,
  chatNext,
  chatFirst,
  chatLast,
  selfChat,
  showArchive,
  showContacts,
  pinnedChat1,
  pinnedChat2,
  pinnedChat3,
  pinnedChat4,
  pinnedChat5,
  pinnedChat6,
  pinnedChat7,
  pinnedChat8,
  account1,
  account2,
  account3,
  account4,
  account5,
  account6,
  allChats,
  folder1,
  folder2,
  folder3,
  folder4,
  folder5,
  folder6,
  lastFolder,
  nextFolder,
  previousFolder,
  readChat,
  recordVoice,
  showChatMenu,
  showChatPreview,
  archiveChat,
  showScheduled,
  showAdminLog,
  message,
  messageSilently,
  messageScheduled,
  mediaPlay,
  mediaPause,
  mediaPlayPause,
  mediaStop,
  mediaPrevious,
  mediaNext,
  mediaViewerVideoFullscreen,
  formatBold,
  formatItalic,
  formatUnderline,
  formatStrike,
  formatCode,
  formatBlockquote,
  formatSpoiler,
  formatClear,
  formatLink,
  formatDate,
  editLastMessage,
  replyPrevious,
  replyNext,
  openFilePicker,
  pastePlainText,
  supportReloadTemplates,
  supportToggleMuted,
  supportScrollToCurrent,
  supportHistoryBack,
  supportHistoryForward,
}

const _autoRepeatCommands = {
  ShortcutCommand.chatPrevious,
  ShortcutCommand.chatNext,
  ShortcutCommand.chatFirst,
  ShortcutCommand.chatLast,
  ShortcutCommand.mediaPrevious,
  ShortcutCommand.mediaNext,
};

class _Handler {
  final int priority;
  final VoidCallback callback;
  _Handler(this.priority, this.callback);
}

class _KeyBinding {
  final LogicalKeyboardKey trigger;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;
  final ShortcutCommand command;

  const _KeyBinding(
    this.trigger,
    this.command, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });
}

class ShortcutSystem {
  ShortcutSystem._();
  static final instance = ShortcutSystem._();

  final _handlers = <ShortcutCommand, List<_Handler>>{};
  final _bindings = <_KeyBinding>[];
  final _requestController = StreamController<ShortcutCommand>.broadcast();

  Stream<ShortcutCommand> get requests => _requestController.stream;

  bool _paused = false;
  bool get isPaused => _paused;

  void pause() => _paused = true;
  void resume() => _paused = false;

  void init() {
    _bindings.clear();
    _bindings.addAll(_defaultBindings);
  }

  void addBinding(
    LogicalKeyboardKey trigger,
    ShortcutCommand command, {
    bool control = false,
    bool shift = false,
    bool alt = false,
    bool meta = false,
  }) {
    _bindings.add(_KeyBinding(trigger, command,
        control: control, shift: shift, alt: alt, meta: meta));
  }

  void removeBindingsFor(ShortcutCommand command) {
    _bindings.removeWhere((b) => b.command == command);
  }

  void registerHandler(
      ShortcutCommand command, VoidCallback handler, {int priority = 0}) {
    final list = _handlers.putIfAbsent(command, () => []);
    list.add(_Handler(priority, handler));
    list.sort((a, b) => b.priority.compareTo(a.priority));
  }

  void unregisterHandler(ShortcutCommand command, VoidCallback handler) {
    _handlers[command]?.removeWhere((h) => h.callback == handler);
  }

  bool dispatch(ShortcutCommand command) {
    final list = _handlers[command];
    if (list == null || list.isEmpty) return false;
    list.first.callback();
    _requestController.add(command);
    return true;
  }

  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (_paused) return KeyEventResult.ignored;

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final commands = _findCommands(event);
    if (commands.isEmpty) return KeyEventResult.ignored;

    if (event is KeyRepeatEvent) {
      bool any = false;
      for (final cmd in commands) {
        if (_autoRepeatCommands.contains(cmd)) {
          if (dispatch(cmd)) any = true;
        }
      }
      return any ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    bool any = false;
    for (final cmd in commands) {
      if (dispatch(cmd)) any = true;
    }
    return any ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  List<ShortcutCommand> _findCommands(KeyEvent event) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final key = event.logicalKey;

    final result = <ShortcutCommand>[];
    for (final b in _bindings) {
      if (b.trigger == key &&
          b.control == ctrl &&
          b.shift == shift &&
          b.alt == alt &&
          b.meta == meta) {
        result.add(b.command);
      }
    }
    return result;
  }

  void dispose() {
    _handlers.clear();
    _requestController.close();
  }

  static final _isDesktop = !kIsWeb;

  static final List<_KeyBinding> _defaultBindings = [
    const _KeyBinding(LogicalKeyboardKey.keyF, ShortcutCommand.search,
        control: true),
    const _KeyBinding(
        LogicalKeyboardKey.escape, ShortcutCommand.cancelSearch),
    const _KeyBinding(LogicalKeyboardKey.arrowDown, ShortcutCommand.chatNext,
        alt: true),
    const _KeyBinding(
        LogicalKeyboardKey.arrowUp, ShortcutCommand.chatPrevious,
        alt: true),
    if (_isDesktop)
      const _KeyBinding(
          LogicalKeyboardKey.pageDown, ShortcutCommand.chatNext,
          control: true),
    if (_isDesktop)
      const _KeyBinding(
          LogicalKeyboardKey.pageUp, ShortcutCommand.chatPrevious,
          control: true),
    const _KeyBinding(
        LogicalKeyboardKey.arrowDown, ShortcutCommand.nextFolder,
        control: true, shift: true),
    const _KeyBinding(
        LogicalKeyboardKey.arrowUp, ShortcutCommand.previousFolder,
        control: true, shift: true),
    const _KeyBinding(LogicalKeyboardKey.home, ShortcutCommand.chatFirst,
        control: true, alt: true),
    const _KeyBinding(LogicalKeyboardKey.end, ShortcutCommand.chatLast,
        control: true, alt: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.keyR, ShortcutCommand.readChat,
          control: true),
    const _KeyBinding(
        LogicalKeyboardKey.backslash, ShortcutCommand.showChatMenu,
        control: true),
    const _KeyBinding(
        LogicalKeyboardKey.arrowUp, ShortcutCommand.replyPrevious,
        control: true),
    const _KeyBinding(LogicalKeyboardKey.arrowDown, ShortcutCommand.replyNext,
        control: true),
    const _KeyBinding(
        LogicalKeyboardKey.arrowUp, ShortcutCommand.editLastMessage),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.digit1, ShortcutCommand.allChats,
          control: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.digit2, ShortcutCommand.folder1,
          control: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.digit3, ShortcutCommand.folder2,
          control: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.digit4, ShortcutCommand.folder3,
          control: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.digit5, ShortcutCommand.folder4,
          control: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.digit6, ShortcutCommand.folder5,
          control: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.digit7, ShortcutCommand.folder6,
          control: true),
    if (_isDesktop)
      const _KeyBinding(
          LogicalKeyboardKey.digit8, ShortcutCommand.lastFolder,
          control: true),
    if (_isDesktop)
      const _KeyBinding(
          LogicalKeyboardKey.keyW, ShortcutCommand.closeTelegram,
          control: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.f4, ShortcutCommand.closeTelegram,
          control: true),
    if (_isDesktop)
      const _KeyBinding(
          LogicalKeyboardKey.keyM, ShortcutCommand.minimizeTelegram,
          control: true),
    if (_isDesktop)
      const _KeyBinding(
          LogicalKeyboardKey.keyQ, ShortcutCommand.quitTelegram,
          control: true),
    if (_isDesktop)
      const _KeyBinding(LogicalKeyboardKey.digit0, ShortcutCommand.selfChat,
          control: true),
    if (_isDesktop)
      const _KeyBinding(
          LogicalKeyboardKey.digit9, ShortcutCommand.showArchive,
          control: true),
    const _KeyBinding(
        LogicalKeyboardKey.keyJ, ShortcutCommand.showContacts,
        control: true),
  ];
}

class ShortcutListener extends StatefulWidget {
  final Widget child;
  const ShortcutListener({super.key, required this.child});

  @override
  State<ShortcutListener> createState() => _ShortcutListenerState();
}

class _ShortcutListenerState extends State<ShortcutListener> {
  @override
  void initState() {
    super.initState();
    final sys = ShortcutSystem.instance;
    sys.init();

    sys.registerHandler(ShortcutCommand.search, () {
      ChatListPanel.requestFocusSearch();
    });
    sys.registerHandler(ShortcutCommand.cancelSearch, () {
      ChatListPanel.requestCancelSearch();
    });
    sys.registerHandler(ShortcutCommand.chatNext, () {
      ChatListPanel.requestNavigateChat(1);
    });
    sys.registerHandler(ShortcutCommand.chatPrevious, () {
      ChatListPanel.requestNavigateChat(-1);
    });
    sys.registerHandler(ShortcutCommand.chatFirst, () {
      ChatListPanel.requestJumpChat(true);
    });
    sys.registerHandler(ShortcutCommand.chatLast, () {
      ChatListPanel.requestJumpChat(false);
    });
    sys.registerHandler(ShortcutCommand.nextFolder, () {
      ChatListPanel.requestNavigateFolder(1);
    });
    sys.registerHandler(ShortcutCommand.previousFolder, () {
      ChatListPanel.requestNavigateFolder(-1);
    });
    sys.registerHandler(ShortcutCommand.readChat, () {
      ChatView.requestMarkActiveChatRead();
    });
    sys.registerHandler(ShortcutCommand.showChatMenu, () {
      ChatView.requestShowActiveChatMenu();
    });
    sys.registerHandler(ShortcutCommand.replyPrevious, () {
      ChatView.requestCycleReply(1);
    });
    sys.registerHandler(ShortcutCommand.replyNext, () {
      ChatView.requestCycleReply(-1);
    });
    sys.registerHandler(ShortcutCommand.editLastMessage, () {
      ChatView.requestEditLastOutgoing();
    });
    sys.registerHandler(ShortcutCommand.closeTelegram, () {
      SystemTray.hideWindowRequest?.call();
    });
    sys.registerHandler(ShortcutCommand.minimizeTelegram, () {
      SystemTray.minimizeWindowRequest?.call();
    });
    sys.registerHandler(ShortcutCommand.quitTelegram, () {
      SystemTray.quitAppRequest?.call();
    });

    for (int i = 0; i < 8; i++) {
      final folderCmd = [
        ShortcutCommand.allChats,
        ShortcutCommand.folder1,
        ShortcutCommand.folder2,
        ShortcutCommand.folder3,
        ShortcutCommand.folder4,
        ShortcutCommand.folder5,
        ShortcutCommand.folder6,
        ShortcutCommand.lastFolder,
      ][i];
      sys.registerHandler(folderCmd, () {
        ChatListPanel.requestSwitchFolderByIndex(i + 1);
      });
    }

    sys.registerHandler(ShortcutCommand.selfChat, () {
      final chatState = context.read<ChatState>();
      final saved = chatState.chats
          .where((c) => isSavedMessages(c))
          .firstOrNull;
      if (saved != null) chatState.openChat(saved);
    });
    sys.registerHandler(ShortcutCommand.showArchive, () {
      context.read<AppState>().requestShowArchive();
    });
  }

  @override
  void dispose() {
    ShortcutSystem.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: false,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => ShortcutSystem.instance.handleKeyEvent(event),
      child: widget.child,
    );
  }
}
