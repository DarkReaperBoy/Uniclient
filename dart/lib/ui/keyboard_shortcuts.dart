import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

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

const _commandNames = <ShortcutCommand, String>{
  ShortcutCommand.closeTelegram: 'close_telegram',
  ShortcutCommand.lockTelegram: 'lock_telegram',
  ShortcutCommand.minimizeTelegram: 'minimize_telegram',
  ShortcutCommand.quitTelegram: 'quit_telegram',
  ShortcutCommand.search: 'search',
  ShortcutCommand.cancelSearch: 'cancel_search',
  ShortcutCommand.chatPrevious: 'previous_chat',
  ShortcutCommand.chatNext: 'next_chat',
  ShortcutCommand.chatFirst: 'first_chat',
  ShortcutCommand.chatLast: 'last_chat',
  ShortcutCommand.selfChat: 'self_chat',
  ShortcutCommand.showArchive: 'show_archive',
  ShortcutCommand.showContacts: 'show_contacts',
  ShortcutCommand.pinnedChat1: 'pinned_chat1',
  ShortcutCommand.pinnedChat2: 'pinned_chat2',
  ShortcutCommand.pinnedChat3: 'pinned_chat3',
  ShortcutCommand.pinnedChat4: 'pinned_chat4',
  ShortcutCommand.pinnedChat5: 'pinned_chat5',
  ShortcutCommand.pinnedChat6: 'pinned_chat6',
  ShortcutCommand.pinnedChat7: 'pinned_chat7',
  ShortcutCommand.pinnedChat8: 'pinned_chat8',
  ShortcutCommand.account1: 'account1',
  ShortcutCommand.account2: 'account2',
  ShortcutCommand.account3: 'account3',
  ShortcutCommand.account4: 'account4',
  ShortcutCommand.account5: 'account5',
  ShortcutCommand.account6: 'account6',
  ShortcutCommand.allChats: 'all_chats',
  ShortcutCommand.folder1: 'folder1',
  ShortcutCommand.folder2: 'folder2',
  ShortcutCommand.folder3: 'folder3',
  ShortcutCommand.folder4: 'folder4',
  ShortcutCommand.folder5: 'folder5',
  ShortcutCommand.folder6: 'folder6',
  ShortcutCommand.lastFolder: 'last_folder',
  ShortcutCommand.nextFolder: 'next_folder',
  ShortcutCommand.previousFolder: 'previous_folder',
  ShortcutCommand.readChat: 'read_chat',
  ShortcutCommand.recordVoice: 'record_voice',
  ShortcutCommand.showChatMenu: 'show_chat_menu',
  ShortcutCommand.showChatPreview: 'show_chat_preview',
  ShortcutCommand.archiveChat: 'archive_chat',
  ShortcutCommand.showScheduled: 'show_scheduled',
  ShortcutCommand.showAdminLog: 'show_admin_log',
  ShortcutCommand.message: 'message',
  ShortcutCommand.messageSilently: 'message_silently',
  ShortcutCommand.messageScheduled: 'message_scheduled',
  ShortcutCommand.mediaPlay: 'media_play',
  ShortcutCommand.mediaPause: 'media_pause',
  ShortcutCommand.mediaPlayPause: 'media_playpause',
  ShortcutCommand.mediaStop: 'media_stop',
  ShortcutCommand.mediaPrevious: 'media_previous',
  ShortcutCommand.mediaNext: 'media_next',
  ShortcutCommand.mediaViewerVideoFullscreen: 'media_viewer_video_fullscreen',
  ShortcutCommand.formatBold: 'format_bold',
  ShortcutCommand.formatItalic: 'format_italic',
  ShortcutCommand.formatUnderline: 'format_underline',
  ShortcutCommand.formatStrike: 'format_strike',
  ShortcutCommand.formatCode: 'format_code',
  ShortcutCommand.formatBlockquote: 'format_blockquote',
  ShortcutCommand.formatSpoiler: 'format_spoiler',
  ShortcutCommand.formatClear: 'format_clear',
  ShortcutCommand.formatLink: 'format_link',
  ShortcutCommand.formatDate: 'format_date',
  ShortcutCommand.editLastMessage: 'edit_last_message',
  ShortcutCommand.replyPrevious: 'reply_previous',
  ShortcutCommand.replyNext: 'reply_next',
  ShortcutCommand.openFilePicker: 'open_file_picker',
  ShortcutCommand.pastePlainText: 'paste_plain_text',
  ShortcutCommand.supportReloadTemplates: 'support_reload_templates',
  ShortcutCommand.supportToggleMuted: 'support_toggle_muted',
  ShortcutCommand.supportScrollToCurrent: 'support_scroll_to_current',
  ShortcutCommand.supportHistoryBack: 'support_history_back',
  ShortcutCommand.supportHistoryForward: 'support_history_forward',
};

final _nameToCommand = {
  for (final e in _commandNames.entries) e.value: e.key,
};

final _keyNames = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.keyA: 'a', LogicalKeyboardKey.keyB: 'b',
  LogicalKeyboardKey.keyC: 'c', LogicalKeyboardKey.keyD: 'd',
  LogicalKeyboardKey.keyE: 'e', LogicalKeyboardKey.keyF: 'f',
  LogicalKeyboardKey.keyG: 'g', LogicalKeyboardKey.keyH: 'h',
  LogicalKeyboardKey.keyI: 'i', LogicalKeyboardKey.keyJ: 'j',
  LogicalKeyboardKey.keyK: 'k', LogicalKeyboardKey.keyL: 'l',
  LogicalKeyboardKey.keyM: 'm', LogicalKeyboardKey.keyN: 'n',
  LogicalKeyboardKey.keyO: 'o', LogicalKeyboardKey.keyP: 'p',
  LogicalKeyboardKey.keyQ: 'q', LogicalKeyboardKey.keyR: 'r',
  LogicalKeyboardKey.keyS: 's', LogicalKeyboardKey.keyT: 't',
  LogicalKeyboardKey.keyU: 'u', LogicalKeyboardKey.keyV: 'v',
  LogicalKeyboardKey.keyW: 'w', LogicalKeyboardKey.keyX: 'x',
  LogicalKeyboardKey.keyY: 'y', LogicalKeyboardKey.keyZ: 'z',
  LogicalKeyboardKey.digit0: '0', LogicalKeyboardKey.digit1: '1',
  LogicalKeyboardKey.digit2: '2', LogicalKeyboardKey.digit3: '3',
  LogicalKeyboardKey.digit4: '4', LogicalKeyboardKey.digit5: '5',
  LogicalKeyboardKey.digit6: '6', LogicalKeyboardKey.digit7: '7',
  LogicalKeyboardKey.digit8: '8', LogicalKeyboardKey.digit9: '9',
  LogicalKeyboardKey.f1: 'f1', LogicalKeyboardKey.f2: 'f2',
  LogicalKeyboardKey.f3: 'f3', LogicalKeyboardKey.f4: 'f4',
  LogicalKeyboardKey.f5: 'f5', LogicalKeyboardKey.f6: 'f6',
  LogicalKeyboardKey.f7: 'f7', LogicalKeyboardKey.f8: 'f8',
  LogicalKeyboardKey.f9: 'f9', LogicalKeyboardKey.f10: 'f10',
  LogicalKeyboardKey.f11: 'f11', LogicalKeyboardKey.f12: 'f12',
  LogicalKeyboardKey.escape: 'escape', LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.space: 'space', LogicalKeyboardKey.enter: 'return',
  LogicalKeyboardKey.backspace: 'backspace', LogicalKeyboardKey.delete: 'delete',
  LogicalKeyboardKey.home: 'home', LogicalKeyboardKey.end: 'end',
  LogicalKeyboardKey.pageUp: 'pgup', LogicalKeyboardKey.pageDown: 'pgdown',
  LogicalKeyboardKey.arrowUp: 'up', LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.arrowLeft: 'left', LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.backslash: '\\',
  LogicalKeyboardKey.bracketRight: ']',
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.minus: '-', LogicalKeyboardKey.equal: '=',
  LogicalKeyboardKey.comma: ',', LogicalKeyboardKey.period: '.',
  LogicalKeyboardKey.slash: '/',
  LogicalKeyboardKey.mediaPlay: 'media_play',
  LogicalKeyboardKey.mediaPause: 'media_pause',
  LogicalKeyboardKey.mediaPlayPause: 'media_playpause',
  LogicalKeyboardKey.mediaStop: 'media_stop',
  LogicalKeyboardKey.mediaTrackPrevious: 'media_previous',
  LogicalKeyboardKey.mediaTrackNext: 'media_next',
};

final _nameToKey = {
  for (final e in _keyNames.entries) e.value: e.key,
};

String _bindingToKeyString(_KeyBinding b) {
  final parts = <String>[];
  if (b.control) parts.add('ctrl');
  if (b.shift) parts.add('shift');
  if (b.alt) parts.add('alt');
  if (b.meta) parts.add('meta');
  parts.add(_keyNames[b.trigger] ?? b.trigger.keyLabel.toLowerCase());
  return parts.join('+');
}

_KeyBinding? _parseKeyBinding(String keys, ShortcutCommand command) {
  final parts = keys.toLowerCase().split('+');
  if (parts.isEmpty) return null;
  bool ctrl = false, shift = false, alt = false, meta = false;
  String? keyPart;
  for (final p in parts) {
    switch (p.trim()) {
      case 'ctrl': ctrl = true;
      case 'shift': shift = true;
      case 'alt': alt = true;
      case 'meta': meta = true;
      default: keyPart = p.trim();
    }
  }
  if (keyPart == null) return null;
  final key = _nameToKey[keyPart];
  if (key == null) return null;
  return _KeyBinding(key, command,
      control: ctrl, shift: shift, alt: alt, meta: meta);
}

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
  String _configDir = '';

  void pause() => _paused = true;
  void resume() => _paused = false;

  void init({String configDir = ''}) {
    _bindings.clear();
    _bindings.addAll(_defaultBindings);
    if (kIsWeb) return;
    if (configDir.isEmpty) {
      configDir = _resolveConfigDir();
    }
    _configDir = configDir;
    if (_configDir.isNotEmpty) {
      _writeDefaultsFile();
      _loadCustomFile();
    }
  }

  static String _resolveConfigDir() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/Library/Application Support/uniclient';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? 'C:\\Users\\Default\\AppData\\Roaming';
      return '$appData\\uniclient';
    } else {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/.config/uniclient';
    }
  }

  void _writeDefaultsFile() {
    try {
      final entries = <Map<String, String>>[];
      for (final b in _defaultBindings) {
        final name = _commandNames[b.command];
        if (name == null) continue;
        entries.add({
          'command': name,
          'keys': _bindingToKeyString(b),
        });
      }
      final json = const JsonEncoder.withIndent('  ').convert(entries);
      File('$_configDir/shortcuts-default.json').writeAsStringSync(json);
    } catch (_) {
    }
  }

  void _loadCustomFile() {
    try {
      final file = File('$_configDir/shortcuts-custom.json');
      if (!file.existsSync()) {
        _writeCustomTemplate();
        return;
      }
      final content = file.readAsStringSync().trim();
      if (content.isEmpty) return;
      final list = jsonDecode(content);
      if (list is! List) return;
      final cap = list.length > 2048 ? 2048 : list.length;
      for (int i = 0; i < cap; i++) {
        final entry = list[i];
        if (entry is! Map) continue;
        final keys = entry['keys'];
        if (keys is! String || keys.isEmpty) continue;
        final cmdValue = entry['command'];
        if (cmdValue == null) {
          _bindings.removeWhere((b) => _bindingToKeyString(b) == keys.toLowerCase());
          continue;
        }
        if (cmdValue is! String) continue;
        final cmd = _nameToCommand[cmdValue];
        if (cmd == null) continue;
        final binding = _parseKeyBinding(keys, cmd);
        if (binding != null) _bindings.add(binding);
      }
    } catch (_) {}
  }

  void _writeCustomTemplate() {
    try {
      final lines = <String>[];
      if (Platform.isMacOS) {
        lines.add('// NOTE: On macOS, "ctrl" in key strings maps to the Command key,');
        lines.add('// and "meta" maps to the Control key.');
        lines.add('');
      }
      lines.add('// Custom shortcut overrides. Max 2048 entries.');
      lines.add('// Set "command" to null to disable a key binding.');
      lines.add('// Example:');
      lines.add('// [');
      lines.add('//   { "command": "close_telegram", "keys": "ctrl+f4" },');
      lines.add('//   { "command": null, "keys": "ctrl+w" }');
      lines.add('// ]');
      lines.add('[]');
      File('$_configDir/shortcuts-custom.json').writeAsStringSync(lines.join('\n'));
    } catch (_) {}
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
    final hwCtrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final hwMeta = HardwareKeyboard.instance.isMetaPressed;
    final key = event.logicalKey;

    final ctrl = _isMac ? hwMeta : hwCtrl;
    final meta = _isMac ? hwCtrl : hwMeta;

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
  static final _isMac = !kIsWeb && Platform.isMacOS;

  static String displayModifier(String mod) {
    if (!_isMac) return mod;
    switch (mod) {
      case 'ctrl': return '\u2318';
      case 'shift': return '\u21E7';
      case 'alt': return '\u2325';
      case 'meta': return '\u2303';
      default: return mod;
    }
  }

  static String displayKeyLabel(LogicalKeyboardKey key) {
    if (_isMac) {
      if (key == LogicalKeyboardKey.backspace) return '\u232B';
      if (key == LogicalKeyboardKey.delete) return '\u2326';
      if (key == LogicalKeyboardKey.enter) return '\u21A9';
      if (key == LogicalKeyboardKey.tab) return '\u21E5';
      if (key == LogicalKeyboardKey.escape) return '\u238B';
      if (key == LogicalKeyboardKey.arrowUp) return '\u2191';
      if (key == LogicalKeyboardKey.arrowDown) return '\u2193';
      if (key == LogicalKeyboardKey.arrowLeft) return '\u2190';
      if (key == LogicalKeyboardKey.arrowRight) return '\u2192';
      if (key == LogicalKeyboardKey.space) return '\u2423';
    }
    return _keyNames[key]?.toUpperCase() ?? key.keyLabel;
  }

  static String displayBindingString(_KeyBinding b) {
    final parts = <String>[];
    if (_isMac) {
      if (b.control) parts.add('\u2318');
      if (b.alt) parts.add('\u2325');
      if (b.shift) parts.add('\u21E7');
      if (b.meta) parts.add('\u2303');
      parts.add(displayKeyLabel(b.trigger));
      return parts.join();
    }
    if (b.control) parts.add('Ctrl');
    if (b.alt) parts.add('Alt');
    if (b.shift) parts.add('Shift');
    if (b.meta) parts.add('Meta');
    parts.add(_keyNames[b.trigger]?.toUpperCase() ?? b.trigger.keyLabel);
    return parts.join('+');
  }

  String displayStringForCommand(ShortcutCommand command) {
    for (final b in _bindings) {
      if (b.command == command) return displayBindingString(b);
    }
    return '';
  }

  List<String> allDisplayStringsForCommand(ShortcutCommand command) {
    return _bindings
        .where((b) => b.command == command)
        .map(displayBindingString)
        .toList();
  }

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
