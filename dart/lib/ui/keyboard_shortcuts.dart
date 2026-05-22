import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'admin_tools.dart' show showAdminLogScreen;
import 'chat_list_panel.dart';
import 'chat_list_row.dart';
import 'chat_view.dart';
import 'compose_entities.dart';
import 'contacts_screen.dart';
import 'media_viewer.dart';
import 'shell.dart';
import '../state/app_state.dart';
import '../state/audio_service.dart';
import '../state/auth_state.dart';
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
  chatSwitchOverlay,
  chatSwitchOverlayReverse,
  recordRound,
}

const _autoRepeatCommands = {
  ShortcutCommand.chatPrevious,
  ShortcutCommand.chatNext,
  ShortcutCommand.chatFirst,
  ShortcutCommand.chatLast,
  ShortcutCommand.mediaPrevious,
  ShortcutCommand.mediaNext,
};

enum ShortcutScope {
  global,
  chatRequired,
  composeRequired,
  mediaViewer,
}

const _commandScopes = <ShortcutCommand, ShortcutScope>{
  ShortcutCommand.closeTelegram: ShortcutScope.global,
  ShortcutCommand.lockTelegram: ShortcutScope.global,
  ShortcutCommand.minimizeTelegram: ShortcutScope.global,
  ShortcutCommand.quitTelegram: ShortcutScope.global,
  ShortcutCommand.search: ShortcutScope.global,
  ShortcutCommand.cancelSearch: ShortcutScope.global,
  ShortcutCommand.chatPrevious: ShortcutScope.global,
  ShortcutCommand.chatNext: ShortcutScope.global,
  ShortcutCommand.chatFirst: ShortcutScope.global,
  ShortcutCommand.chatLast: ShortcutScope.global,
  ShortcutCommand.selfChat: ShortcutScope.global,
  ShortcutCommand.showArchive: ShortcutScope.global,
  ShortcutCommand.showContacts: ShortcutScope.global,
  ShortcutCommand.pinnedChat1: ShortcutScope.global,
  ShortcutCommand.pinnedChat2: ShortcutScope.global,
  ShortcutCommand.pinnedChat3: ShortcutScope.global,
  ShortcutCommand.pinnedChat4: ShortcutScope.global,
  ShortcutCommand.pinnedChat5: ShortcutScope.global,
  ShortcutCommand.pinnedChat6: ShortcutScope.global,
  ShortcutCommand.pinnedChat7: ShortcutScope.global,
  ShortcutCommand.pinnedChat8: ShortcutScope.global,
  ShortcutCommand.account1: ShortcutScope.global,
  ShortcutCommand.account2: ShortcutScope.global,
  ShortcutCommand.account3: ShortcutScope.global,
  ShortcutCommand.account4: ShortcutScope.global,
  ShortcutCommand.account5: ShortcutScope.global,
  ShortcutCommand.account6: ShortcutScope.global,
  ShortcutCommand.allChats: ShortcutScope.global,
  ShortcutCommand.folder1: ShortcutScope.global,
  ShortcutCommand.folder2: ShortcutScope.global,
  ShortcutCommand.folder3: ShortcutScope.global,
  ShortcutCommand.folder4: ShortcutScope.global,
  ShortcutCommand.folder5: ShortcutScope.global,
  ShortcutCommand.folder6: ShortcutScope.global,
  ShortcutCommand.lastFolder: ShortcutScope.global,
  ShortcutCommand.nextFolder: ShortcutScope.global,
  ShortcutCommand.previousFolder: ShortcutScope.global,
  ShortcutCommand.chatSwitchOverlay: ShortcutScope.global,
  ShortcutCommand.chatSwitchOverlayReverse: ShortcutScope.global,
  ShortcutCommand.mediaPlay: ShortcutScope.global,
  ShortcutCommand.mediaPause: ShortcutScope.global,
  ShortcutCommand.mediaPlayPause: ShortcutScope.global,
  ShortcutCommand.mediaStop: ShortcutScope.global,
  ShortcutCommand.mediaPrevious: ShortcutScope.global,
  ShortcutCommand.mediaNext: ShortcutScope.global,
  ShortcutCommand.supportReloadTemplates: ShortcutScope.global,
  ShortcutCommand.supportToggleMuted: ShortcutScope.chatRequired,
  ShortcutCommand.supportScrollToCurrent: ShortcutScope.chatRequired,
  ShortcutCommand.supportHistoryBack: ShortcutScope.global,
  ShortcutCommand.supportHistoryForward: ShortcutScope.global,
  ShortcutCommand.readChat: ShortcutScope.chatRequired,
  ShortcutCommand.recordVoice: ShortcutScope.chatRequired,
  ShortcutCommand.showChatMenu: ShortcutScope.chatRequired,
  ShortcutCommand.showChatPreview: ShortcutScope.chatRequired,
  ShortcutCommand.archiveChat: ShortcutScope.chatRequired,
  ShortcutCommand.showScheduled: ShortcutScope.chatRequired,
  ShortcutCommand.showAdminLog: ShortcutScope.chatRequired,
  ShortcutCommand.replyPrevious: ShortcutScope.chatRequired,
  ShortcutCommand.replyNext: ShortcutScope.chatRequired,
  ShortcutCommand.editLastMessage: ShortcutScope.chatRequired,
  ShortcutCommand.message: ShortcutScope.composeRequired,
  ShortcutCommand.messageSilently: ShortcutScope.composeRequired,
  ShortcutCommand.messageScheduled: ShortcutScope.composeRequired,
  ShortcutCommand.formatBold: ShortcutScope.composeRequired,
  ShortcutCommand.formatItalic: ShortcutScope.composeRequired,
  ShortcutCommand.formatUnderline: ShortcutScope.composeRequired,
  ShortcutCommand.formatStrike: ShortcutScope.composeRequired,
  ShortcutCommand.formatCode: ShortcutScope.composeRequired,
  ShortcutCommand.formatBlockquote: ShortcutScope.composeRequired,
  ShortcutCommand.formatSpoiler: ShortcutScope.composeRequired,
  ShortcutCommand.formatClear: ShortcutScope.composeRequired,
  ShortcutCommand.formatLink: ShortcutScope.composeRequired,
  ShortcutCommand.formatDate: ShortcutScope.composeRequired,
  ShortcutCommand.openFilePicker: ShortcutScope.chatRequired,
  ShortcutCommand.pastePlainText: ShortcutScope.composeRequired,
  ShortcutCommand.recordRound: ShortcutScope.chatRequired,
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
  ShortcutCommand.chatSwitchOverlay: 'chat_switch_overlay',
  ShortcutCommand.chatSwitchOverlayReverse: 'chat_switch_overlay_reverse',
  ShortcutCommand.recordRound: 'record_round',
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
  LogicalKeyboardKey.insert: 'insert',
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
  LogicalKeyboardKey.browserSearch: 'search',
  LogicalKeyboardKey.find: 'find',
};

final _nameToKey = {
  for (final e in _keyNames.entries) e.value: e.key,
};

String bindingToKeyString(KeyBinding b) {
  final parts = <String>[];
  if (b.control) parts.add('ctrl');
  if (b.shift) parts.add('shift');
  if (b.alt) parts.add('alt');
  if (b.meta) parts.add('meta');
  parts.add(_keyNames[b.trigger] ?? b.trigger.keyLabel.toLowerCase());
  return parts.join('+');
}

KeyBinding? _parseKeyBinding(String keys, ShortcutCommand command) {
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
  return KeyBinding(key, command,
      control: ctrl, shift: shift, alt: alt, meta: meta);
}

class _Handler {
  final int priority;
  final bool Function() callback;
  _Handler(this.priority, this.callback);
}

class KeyBinding {
  final LogicalKeyboardKey trigger;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;
  final ShortcutCommand command;

  const KeyBinding(
    this.trigger,
    this.command, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });
}

const _mediaCommands = {
  ShortcutCommand.mediaPlay,
  ShortcutCommand.mediaPause,
  ShortcutCommand.mediaPlayPause,
  ShortcutCommand.mediaStop,
  ShortcutCommand.mediaPrevious,
  ShortcutCommand.mediaNext,
};

const _supportCommands = {
  ShortcutCommand.supportReloadTemplates,
  ShortcutCommand.supportToggleMuted,
  ShortcutCommand.supportScrollToCurrent,
  ShortcutCommand.supportHistoryBack,
  ShortcutCommand.supportHistoryForward,
};

class ShortcutSystem {
  ShortcutSystem._();
  static final instance = ShortcutSystem._();

  final _handlers = <ShortcutCommand, List<_Handler>>{};
  final _bindings = <KeyBinding>[];
  final _bindingMap = <(LogicalKeyboardKey, bool, bool, bool, bool), List<ShortcutCommand>>{};
  StreamController<ShortcutCommand> _requestController = StreamController<ShortcutCommand>.broadcast();

  Stream<ShortcutCommand> get requests => _requestController.stream;

  bool _paused = false;
  bool get isPaused => _paused;
  String _configDir = '';

  void Function(KeyEvent)? _recordingCallback;
  bool get isRecording => _recordingCallback != null;

  void startRecording(void Function(KeyEvent) callback) {
    _recordingCallback = callback;
  }

  void stopRecording() {
    _recordingCallback = null;
  }

  bool _mediaShortcutsEnabled = false;
  bool get mediaShortcutsEnabled => _mediaShortcutsEnabled;

  bool _supportMode = false;
  bool get supportMode => _supportMode;

  bool _appInFocus = true;
  bool get appInFocus => _appInFocus;
  set appInFocus(bool v) => _appInFocus = v;

  bool _layerShown = false;
  bool get layerShown => _layerShown;

  int _layerCount = 0;

  void pushLayer() {
    _layerCount++;
    _layerShown = _layerCount > 0;
  }

  void popLayer() {
    _layerCount = (_layerCount - 1).clamp(0, 999);
    _layerShown = _layerCount > 0;
  }

  bool Function()? hasActiveChatCallback;
  bool Function()? isComposeFieldFocusedCallback;
  bool Function()? isMediaViewerOpenCallback;

  bool _checkScope(ShortcutCommand command) {
    if (_layerShown) return false;
    final scope = _commandScopes[command] ?? ShortcutScope.global;
    switch (scope) {
      case ShortcutScope.global:
        return true;
      case ShortcutScope.chatRequired:
        return hasActiveChatCallback?.call() ?? false;
      case ShortcutScope.composeRequired:
        return isComposeFieldFocusedCallback?.call() ?? false;
      case ShortcutScope.mediaViewer:
        return isMediaViewerOpenCallback?.call() ?? false;
    }
  }

  void toggleMediaShortcuts(bool enabled) {
    _mediaShortcutsEnabled = enabled;
  }

  void toggleSupportMode(bool enabled) {
    _supportMode = enabled;
  }

  void pause() => _paused = true;
  void resume() => _paused = false;

  void init({String configDir = ''}) {
    if (_requestController.isClosed) {
      _requestController = StreamController<ShortcutCommand>.broadcast();
    }
    _bindings.clear();
    _bindingMap.clear();
    _bindings.addAll(_defaultBindings);
    _rebuildBindingMap();
    if (kIsWeb) return;
    if (configDir.isEmpty) {
      configDir = _resolveConfigDir();
    }
    _configDir = configDir;
    if (_configDir.isNotEmpty) {
      _writeDefaultsFile();
      _loadCustomFile();
      _rebuildBindingMap();
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

  void _ensureConfigDir() {
    if (_configDir.isNotEmpty) {
      Directory(_configDir).createSync(recursive: true);
    }
  }

  void _writeDefaultsFile() {
    try {
      _ensureConfigDir();
      final entries = <Map<String, String>>[];
      for (final b in _defaultBindings) {
        final name = _commandNames[b.command];
        if (name == null) continue;
        entries.add({
          'command': name,
          'keys': bindingToKeyString(b),
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
      var content = file.readAsStringSync().trim();
      if (content.isEmpty) return;
      content = content.split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n')
          .trim();
      if (content.isEmpty) return;
      final list = jsonDecode(content);
      if (list is! List) return;
      final cap = list.length > 2048 ? 2048 : list.length;
      for (int i = 0; i < cap; i++) {
        final entry = list[i];
        if (entry is! Map) continue;
        final keys = entry['keys'];
        if (keys is! String || keys.isEmpty) continue;
        final removed = entry['removed'];
        if (removed == true) {
          final cmdValue = entry['command'];
          if (cmdValue is String) {
            final cmd = _nameToCommand[cmdValue];
            if (cmd != null) {
              _bindings.removeWhere((b) =>
                  b.command == cmd && bindingToKeyString(b) == keys.toLowerCase());
            }
          } else {
            _bindings.removeWhere((b) => bindingToKeyString(b) == keys.toLowerCase());
          }
          continue;
        }
        final cmdValue = entry['command'];
        if (cmdValue == null) {
          _bindings.removeWhere((b) => bindingToKeyString(b) == keys.toLowerCase());
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
      _ensureConfigDir();
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
    _bindings.add(KeyBinding(trigger, command,
        control: control, shift: shift, alt: alt, meta: meta));
    _rebuildBindingMap();
  }

  void removeBindingsFor(ShortcutCommand command) {
    _bindings.removeWhere((b) => b.command == command);
    _rebuildBindingMap();
  }

  void registerHandler(
      ShortcutCommand command, bool Function() handler, {int priority = 0}) {
    final list = _handlers.putIfAbsent(command, () => []);
    list.add(_Handler(priority, handler));
    list.sort((a, b) => b.priority.compareTo(a.priority));
  }

  void unregisterHandler(ShortcutCommand command, bool Function() handler) {
    _handlers[command]?.removeWhere((h) => h.callback == handler);
  }

  bool dispatch(ShortcutCommand command) {
    final list = _handlers[command];
    if (list == null || list.isEmpty) return false;
    for (final h in list) {
      if (h.callback()) {
        _requestController.add(command);
        return true;
      }
    }
    return false;
  }

  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (_recordingCallback != null) {
      _recordingCallback!(event);
      return KeyEventResult.handled;
    }
    if (_paused) return KeyEventResult.ignored;

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    var commands = _findCommands(event);
    if (commands.isEmpty) return KeyEventResult.ignored;

    if (!_appInFocus) {
      commands = commands.where((c) => _mediaCommands.contains(c)).toList();
      if (commands.isEmpty) return KeyEventResult.ignored;
    }

    if (!_mediaShortcutsEnabled) {
      commands = commands.where((c) => !_mediaCommands.contains(c)).toList();
      if (commands.isEmpty) return KeyEventResult.ignored;
    }

    if (!_supportMode) {
      commands = commands.where((c) => !_supportCommands.contains(c)).toList();
      if (commands.isEmpty) return KeyEventResult.ignored;
    }

    commands = commands.where(_checkScope).toList();
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

    for (final cmd in commands) {
      if (dispatch(cmd)) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _rebuildBindingMap() {
    _bindingMap.clear();
    for (final b in _bindings) {
      final key = (b.trigger, b.control, b.shift, b.alt, b.meta);
      (_bindingMap[key] ??= []).add(b.command);
    }
  }

  List<ShortcutCommand> _findCommands(KeyEvent event) {
    final hwCtrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final hwMeta = HardwareKeyboard.instance.isMetaPressed;

    final ctrl = _isMac ? hwMeta : hwCtrl;
    final meta = _isMac ? hwCtrl : hwMeta;

    final key = (event.logicalKey, ctrl, shift, alt, meta);
    return _bindingMap[key] ?? const [];
  }

  List<KeyBinding> get currentBindings => List.unmodifiable(_bindings);

  static List<KeyBinding> get defaultBindingsList =>
      List.unmodifiable(_defaultBindings);

  void replaceAllBindings(List<KeyBinding> newBindings) {
    _bindings.clear();
    _bindings.addAll(newBindings);
    _rebuildBindingMap();
  }

  void saveToCustomFile() {
    if (_configDir.isEmpty) return;
    try {
      _ensureConfigDir();
      final defaultsByKey = <String, Set<ShortcutCommand>>{};
      for (final b in _defaultBindings) {
        defaultsByKey
            .putIfAbsent(bindingToKeyString(b), () => {})
            .add(b.command);
      }
      final currentsByKey = <String, Set<ShortcutCommand>>{};
      for (final b in _bindings) {
        currentsByKey
            .putIfAbsent(bindingToKeyString(b), () => {})
            .add(b.command);
      }
      final allKeys = {...defaultsByKey.keys, ...currentsByKey.keys};
      final entries = <Map<String, dynamic>>[];
      for (final key in allKeys) {
        final defs = defaultsByKey[key] ?? {};
        final currs = currentsByKey[key] ?? {};
        if (defs.length == currs.length && defs.containsAll(currs)) continue;
        if (defs.isNotEmpty) {
          entries.add({'command': null, 'keys': key});
        }
        for (final cmd in currs) {
          entries.add({'command': _commandNames[cmd], 'keys': key});
        }
      }
      final json = const JsonEncoder.withIndent('  ').convert(entries);
      File('$_configDir/shortcuts-custom.json').writeAsStringSync(json);
    } catch (_) {}
  }

  void dispose() {
    _handlers.clear();
    _requestController.close();
    _layerCount = 0;
    _layerShown = false;
    _appInFocus = true;
    hasActiveChatCallback = null;
    isComposeFieldFocusedCallback = null;
    isMediaViewerOpenCallback = null;
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

  static String displayBindingString(KeyBinding b) {
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

  static final List<KeyBinding> _defaultBindings = [
    const KeyBinding(LogicalKeyboardKey.keyF, ShortcutCommand.search,
        control: true),
    const KeyBinding(LogicalKeyboardKey.browserSearch, ShortcutCommand.search),
    const KeyBinding(LogicalKeyboardKey.find, ShortcutCommand.search),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.tab, ShortcutCommand.chatSwitchOverlay,
          control: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.tab, ShortcutCommand.chatSwitchOverlayReverse,
          control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.arrowDown, ShortcutCommand.chatNext,
        alt: true),
    const KeyBinding(
        LogicalKeyboardKey.arrowUp, ShortcutCommand.chatPrevious,
        alt: true),
    if (_isDesktop)
      const KeyBinding(
          LogicalKeyboardKey.pageDown, ShortcutCommand.chatNext,
          control: true),
    if (_isDesktop)
      const KeyBinding(
          LogicalKeyboardKey.pageUp, ShortcutCommand.chatPrevious,
          control: true),
    const KeyBinding(
        LogicalKeyboardKey.arrowDown, ShortcutCommand.nextFolder,
        control: true, shift: true),
    const KeyBinding(
        LogicalKeyboardKey.arrowUp, ShortcutCommand.previousFolder,
        control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.home, ShortcutCommand.chatFirst,
        control: true, alt: true),
    const KeyBinding(LogicalKeyboardKey.end, ShortcutCommand.chatLast,
        control: true, alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.keyR, ShortcutCommand.readChat,
          control: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.keyR, ShortcutCommand.recordVoice,
          control: true, shift: true),
    const KeyBinding(
        LogicalKeyboardKey.backslash, ShortcutCommand.showChatMenu,
        control: true),
    if (_isDesktop)
      const KeyBinding(
          LogicalKeyboardKey.bracketRight, ShortcutCommand.showChatPreview,
          control: true),
    const KeyBinding(
        LogicalKeyboardKey.arrowUp, ShortcutCommand.replyPrevious,
        control: true),
    const KeyBinding(LogicalKeyboardKey.arrowDown, ShortcutCommand.replyNext,
        control: true),
    const KeyBinding(
        LogicalKeyboardKey.arrowUp, ShortcutCommand.editLastMessage),
    if (_isDesktop && !_isMac)
      const KeyBinding(LogicalKeyboardKey.digit1, ShortcutCommand.allChats,
          control: true),
    if (_isDesktop && _isMac)
      const KeyBinding(LogicalKeyboardKey.digit1, ShortcutCommand.allChats,
          meta: true),
    if (_isDesktop && !_isMac)
      const KeyBinding(LogicalKeyboardKey.digit2, ShortcutCommand.folder1,
          control: true),
    if (_isDesktop && _isMac)
      const KeyBinding(LogicalKeyboardKey.digit2, ShortcutCommand.folder1,
          meta: true),
    if (_isDesktop && !_isMac)
      const KeyBinding(LogicalKeyboardKey.digit3, ShortcutCommand.folder2,
          control: true),
    if (_isDesktop && _isMac)
      const KeyBinding(LogicalKeyboardKey.digit3, ShortcutCommand.folder2,
          meta: true),
    if (_isDesktop && !_isMac)
      const KeyBinding(LogicalKeyboardKey.digit4, ShortcutCommand.folder3,
          control: true),
    if (_isDesktop && _isMac)
      const KeyBinding(LogicalKeyboardKey.digit4, ShortcutCommand.folder3,
          meta: true),
    if (_isDesktop && !_isMac)
      const KeyBinding(LogicalKeyboardKey.digit5, ShortcutCommand.folder4,
          control: true),
    if (_isDesktop && _isMac)
      const KeyBinding(LogicalKeyboardKey.digit5, ShortcutCommand.folder4,
          meta: true),
    if (_isDesktop && !_isMac)
      const KeyBinding(LogicalKeyboardKey.digit6, ShortcutCommand.folder5,
          control: true),
    if (_isDesktop && _isMac)
      const KeyBinding(LogicalKeyboardKey.digit6, ShortcutCommand.folder5,
          meta: true),
    if (_isDesktop && !_isMac)
      const KeyBinding(LogicalKeyboardKey.digit7, ShortcutCommand.folder6,
          control: true),
    if (_isDesktop && _isMac)
      const KeyBinding(LogicalKeyboardKey.digit7, ShortcutCommand.folder6,
          meta: true),
    if (_isDesktop && !_isMac)
      const KeyBinding(LogicalKeyboardKey.digit8, ShortcutCommand.lastFolder,
          control: true),
    if (_isDesktop && _isMac)
      const KeyBinding(LogicalKeyboardKey.digit8, ShortcutCommand.lastFolder,
          meta: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit1, ShortcutCommand.pinnedChat1,
          alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit2, ShortcutCommand.pinnedChat2,
          alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit3, ShortcutCommand.pinnedChat3,
          alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit4, ShortcutCommand.pinnedChat4,
          alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit5, ShortcutCommand.pinnedChat5,
          alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit6, ShortcutCommand.pinnedChat6,
          alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit7, ShortcutCommand.pinnedChat7,
          alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit8, ShortcutCommand.pinnedChat8,
          alt: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.keyL, ShortcutCommand.lockTelegram,
          control: true),
    if (_isDesktop)
      const KeyBinding(
          LogicalKeyboardKey.keyW, ShortcutCommand.closeTelegram,
          control: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.f4, ShortcutCommand.closeTelegram,
          control: true),
    if (_isDesktop)
      const KeyBinding(
          LogicalKeyboardKey.keyM, ShortcutCommand.minimizeTelegram,
          control: true),
    if (_isDesktop)
      const KeyBinding(
          LogicalKeyboardKey.keyQ, ShortcutCommand.quitTelegram,
          control: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.digit0, ShortcutCommand.selfChat,
          control: true),
    if (_isDesktop)
      const KeyBinding(
          LogicalKeyboardKey.digit9, ShortcutCommand.showArchive,
          control: true),
    const KeyBinding(
        LogicalKeyboardKey.keyJ, ShortcutCommand.showContacts,
        control: true),
    const KeyBinding(LogicalKeyboardKey.keyO, ShortcutCommand.openFilePicker,
        control: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.f5, ShortcutCommand.supportReloadTemplates),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.delete, ShortcutCommand.supportToggleMuted,
          control: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.insert, ShortcutCommand.supportScrollToCurrent,
          control: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.keyX, ShortcutCommand.supportHistoryBack,
          control: true, shift: true),
    if (_isDesktop)
      const KeyBinding(LogicalKeyboardKey.keyC, ShortcutCommand.supportHistoryForward,
          control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.mediaPlay, ShortcutCommand.mediaPlay),
    const KeyBinding(LogicalKeyboardKey.mediaPause, ShortcutCommand.mediaPause),
    const KeyBinding(LogicalKeyboardKey.mediaPlayPause, ShortcutCommand.mediaPlayPause),
    const KeyBinding(LogicalKeyboardKey.mediaStop, ShortcutCommand.mediaStop),
    const KeyBinding(LogicalKeyboardKey.mediaTrackPrevious, ShortcutCommand.mediaPrevious),
    const KeyBinding(LogicalKeyboardKey.mediaTrackNext, ShortcutCommand.mediaNext),
    const KeyBinding(LogicalKeyboardKey.keyB, ShortcutCommand.formatBold,
        control: true),
    const KeyBinding(LogicalKeyboardKey.keyI, ShortcutCommand.formatItalic,
        control: true),
    const KeyBinding(LogicalKeyboardKey.keyU, ShortcutCommand.formatUnderline,
        control: true),
    const KeyBinding(LogicalKeyboardKey.keyX, ShortcutCommand.formatStrike,
        control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.keyM, ShortcutCommand.formatCode,
        control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.period, ShortcutCommand.formatBlockquote,
        control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.keyP, ShortcutCommand.formatSpoiler,
        control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.keyN, ShortcutCommand.formatClear,
        control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.keyK, ShortcutCommand.formatLink,
        control: true),
    const KeyBinding(LogicalKeyboardKey.keyD, ShortcutCommand.formatDate,
        control: true, shift: true),
  ];
}

class ShortcutLayerObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute || route.opaque == false) {
      ShortcutSystem.instance.pushLayer();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute || route.opaque == false) {
      ShortcutSystem.instance.popLayer();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute || route.opaque == false) {
      ShortcutSystem.instance.popLayer();
    }
  }
}

class ShortcutListener extends StatefulWidget {
  final Widget child;
  const ShortcutListener({super.key, required this.child});

  @override
  State<ShortcutListener> createState() => _ShortcutListenerState();
}

class _ShortcutListenerState extends State<ShortcutListener>
    with WidgetsBindingObserver {
  AudioService? _audioService;

  void _onAudioChanged() {
    final audio = _audioService;
    if (audio == null) return;
    final hasActivePlayer = audio.currentMsgId.isNotEmpty;
    ShortcutSystem.instance.toggleMediaShortcuts(hasActivePlayer);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ShortcutSystem.instance.appInFocus =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final sys = ShortcutSystem.instance;
    sys.init();

    sys.hasActiveChatCallback = () {
      try {
        return context.read<ChatState>().activeChat != null;
      } catch (_) {
        return false;
      }
    };
    sys.isComposeFieldFocusedCallback = () {
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null) return false;
      final ctx = focus.context;
      if (ctx == null) return false;
      return ctx.findAncestorWidgetOfExactType<EditableText>() != null &&
          ctx.findAncestorWidgetOfExactType<ChatView>() != null;
    };
    sys.isMediaViewerOpenCallback = () => MediaViewer.isOpen;

    sys.registerHandler(ShortcutCommand.search, () {
      ChatListPanel.requestFocusSearch();
      return true;
    });
    sys.registerHandler(ShortcutCommand.cancelSearch, () {
      return ChatListPanel.requestCancelSearch();
    });
    sys.registerHandler(ShortcutCommand.chatNext, () {
      ChatListPanel.requestNavigateChat(1);
      return true;
    });
    sys.registerHandler(ShortcutCommand.chatPrevious, () {
      ChatListPanel.requestNavigateChat(-1);
      return true;
    });
    sys.registerHandler(ShortcutCommand.chatSwitchOverlay, () {
      UniClientShell.showChatSwitchRequest?.call();
      return true;
    });
    sys.registerHandler(ShortcutCommand.chatSwitchOverlayReverse, () {
      UniClientShell.showChatSwitchRequest?.call(reverse: true);
      return true;
    });
    sys.registerHandler(ShortcutCommand.chatFirst, () {
      ChatListPanel.requestJumpChat(true);
      return true;
    });
    sys.registerHandler(ShortcutCommand.chatLast, () {
      ChatListPanel.requestJumpChat(false);
      return true;
    });
    sys.registerHandler(ShortcutCommand.nextFolder, () {
      ChatListPanel.requestNavigateFolder(1);
      return true;
    });
    sys.registerHandler(ShortcutCommand.previousFolder, () {
      ChatListPanel.requestNavigateFolder(-1);
      return true;
    });
    sys.registerHandler(ShortcutCommand.readChat, () {
      ChatView.requestMarkActiveChatRead();
      return true;
    });
    sys.registerHandler(ShortcutCommand.showChatMenu, () {
      ChatView.requestShowActiveChatMenu();
      return true;
    });
    sys.registerHandler(ShortcutCommand.recordVoice, () {
      return ChatView.startRecordVoiceRequest?.call() ?? false;
    });
    sys.registerHandler(ShortcutCommand.showChatPreview, () {
      return ChatView.requestShowChatPreview();
    });
    sys.registerHandler(ShortcutCommand.archiveChat, () {
      return ChatView.requestArchiveActiveChat();
    });
    sys.registerHandler(ShortcutCommand.showScheduled, () {
      return ChatView.requestShowScheduled();
    });
    sys.registerHandler(ShortcutCommand.showAdminLog, () {
      return ChatView.requestShowAdminLog();
    });
    sys.registerHandler(ShortcutCommand.replyPrevious, () {
      ChatView.requestCycleReply(1);
      return true;
    });
    sys.registerHandler(ShortcutCommand.replyNext, () {
      ChatView.requestCycleReply(-1);
      return true;
    });
    sys.registerHandler(ShortcutCommand.editLastMessage, () {
      ChatView.requestEditLastOutgoing();
      return true;
    });
    sys.registerHandler(ShortcutCommand.lockTelegram, () {
      try {
        context.read<AppState>().lockByPasscode();
      } catch (_) {}
      return true;
    });
    sys.registerHandler(ShortcutCommand.closeTelegram, () {
      SystemTray.hideWindowRequest?.call();
      return true;
    });
    sys.registerHandler(ShortcutCommand.minimizeTelegram, () {
      SystemTray.minimizeWindowRequest?.call();
      return true;
    });
    sys.registerHandler(ShortcutCommand.quitTelegram, () {
      SystemTray.quitAppRequest?.call();
      return true;
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
        return ChatListPanel.requestSwitchFolderByIndex(i + 1);
      });
    }

    for (int i = 0; i < 8; i++) {
      final pinnedCmd = [
        ShortcutCommand.pinnedChat1,
        ShortcutCommand.pinnedChat2,
        ShortcutCommand.pinnedChat3,
        ShortcutCommand.pinnedChat4,
        ShortcutCommand.pinnedChat5,
        ShortcutCommand.pinnedChat6,
        ShortcutCommand.pinnedChat7,
        ShortcutCommand.pinnedChat8,
      ][i];
      sys.registerHandler(pinnedCmd, () {
        return ChatListPanel.requestOpenPinnedChat(i);
      });
    }

    for (int i = 0; i < 6; i++) {
      final accountCmd = [
        ShortcutCommand.account1,
        ShortcutCommand.account2,
        ShortcutCommand.account3,
        ShortcutCommand.account4,
        ShortcutCommand.account5,
        ShortcutCommand.account6,
      ][i];
      sys.registerHandler(accountCmd, () {
        final appState = context.read<AppState>();
        final accounts = appState.accounts;
        if (i >= accounts.length) return false;
        appState.setActiveAccountId(accounts[i].id);
        return true;
      });
    }

    sys.registerHandler(ShortcutCommand.selfChat, () {
      final chatState = context.read<ChatState>();
      final saved = chatState.chats
          .where((c) => isSavedMessages(c))
          .firstOrNull;
      if (saved != null) {
        chatState.openChat(saved);
        return true;
      }
      final appState = context.read<AppState>();
      final selfId = appState.activeAccount?.selfUserId ?? '';
      if (selfId.isNotEmpty) {
        chatState.openChatById(selfId);
        return true;
      }
      return false;
    });
    sys.registerHandler(ShortcutCommand.showArchive, () {
      context.read<AppState>().requestShowArchive();
      return true;
    });
    sys.registerHandler(ShortcutCommand.showContacts, () {
      showContactsBox(context);
      return true;
    });

    sys.registerHandler(ShortcutCommand.mediaPlay, () {
      final audio = context.read<AudioService>();
      if (audio.currentMsgId.isEmpty) return false;
      if (!audio.playing) audio.togglePlayback();
      return true;
    });
    sys.registerHandler(ShortcutCommand.mediaPause, () {
      final audio = context.read<AudioService>();
      if (audio.currentMsgId.isEmpty) return false;
      if (audio.playing) audio.togglePlayback();
      return true;
    });
    sys.registerHandler(ShortcutCommand.mediaPlayPause, () {
      final audio = context.read<AudioService>();
      if (audio.currentMsgId.isEmpty) return false;
      audio.togglePlayback();
      return true;
    });
    sys.registerHandler(ShortcutCommand.mediaStop, () {
      final audio = context.read<AudioService>();
      if (audio.currentMsgId.isEmpty) return false;
      audio.stop();
      return true;
    });
    sys.registerHandler(ShortcutCommand.mediaPrevious, () {
      final audio = context.read<AudioService>();
      if (audio.currentMsgId.isEmpty) return false;
      audio.previous();
      return true;
    });
    sys.registerHandler(ShortcutCommand.mediaNext, () {
      final audio = context.read<AudioService>();
      if (audio.currentMsgId.isEmpty) return false;
      audio.next();
      return true;
    });

    sys.registerHandler(ShortcutCommand.supportReloadTemplates, () {
      final chatState = context.read<ChatState>();
      chatState.reloadSupportTemplates();
      return true;
    });
    sys.registerHandler(ShortcutCommand.supportToggleMuted, () {
      final chatState = context.read<ChatState>();
      final chat = chatState.activeChat;
      if (chat == null) return false;
      chatState.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
      return true;
    });
    sys.registerHandler(ShortcutCommand.supportScrollToCurrent, () {
      final chatState = context.read<ChatState>();
      if (chatState.activeChat == null) return false;
      ChatListPanel.requestScrollToActiveChat();
      return true;
    });
    sys.registerHandler(ShortcutCommand.supportHistoryBack, () {
      final chatState = context.read<ChatState>();
      return chatState.navigateChatHistory(-1);
    });
    sys.registerHandler(ShortcutCommand.supportHistoryForward, () {
      final chatState = context.read<ChatState>();
      return chatState.navigateChatHistory(1);
    });

    sys.registerHandler(ShortcutCommand.formatBold, () {
      ChatView.toggleFormatRequest?.call(FormatType.bold);
      return ChatView.toggleFormatRequest != null;
    });
    sys.registerHandler(ShortcutCommand.formatItalic, () {
      ChatView.toggleFormatRequest?.call(FormatType.italic);
      return ChatView.toggleFormatRequest != null;
    });
    sys.registerHandler(ShortcutCommand.formatUnderline, () {
      ChatView.toggleFormatRequest?.call(FormatType.underline);
      return ChatView.toggleFormatRequest != null;
    });
    sys.registerHandler(ShortcutCommand.formatStrike, () {
      ChatView.toggleFormatRequest?.call(FormatType.strike);
      return ChatView.toggleFormatRequest != null;
    });
    sys.registerHandler(ShortcutCommand.formatCode, () {
      ChatView.toggleFormatRequest?.call(FormatType.code);
      return ChatView.toggleFormatRequest != null;
    });
    sys.registerHandler(ShortcutCommand.formatBlockquote, () {
      ChatView.toggleFormatRequest?.call(FormatType.blockquote);
      return ChatView.toggleFormatRequest != null;
    });
    sys.registerHandler(ShortcutCommand.formatSpoiler, () {
      ChatView.toggleFormatRequest?.call(FormatType.spoiler);
      return ChatView.toggleFormatRequest != null;
    });
    sys.registerHandler(ShortcutCommand.formatClear, () {
      if (ChatView.clearFormattingRequest == null) return false;
      ChatView.clearFormattingRequest!();
      return true;
    });
    sys.registerHandler(ShortcutCommand.formatLink, () {
      ChatView.showLinkDialogRequest?.call();
      return ChatView.showLinkDialogRequest != null;
    });
    sys.registerHandler(ShortcutCommand.formatDate, () {
      ChatView.toggleFormatRequest?.call(FormatType.date);
      return ChatView.toggleFormatRequest != null;
    });

    sys.registerHandler(ShortcutCommand.message, () {
      return ChatView.requestSendCompose();
    });
    sys.registerHandler(ShortcutCommand.messageSilently, () {
      return ChatView.requestSendSilentCompose();
    });
    sys.registerHandler(ShortcutCommand.messageScheduled, () {
      return ChatView.requestSendScheduledCompose();
    });

    sys.registerHandler(ShortcutCommand.openFilePicker, () {
      return ChatView.openFilePickerRequest?.call() ?? false;
    });

    sys.registerHandler(ShortcutCommand.pastePlainText, () {
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null) return false;
      final ctx = focus.context;
      if (ctx == null) return false;
      final editable = ctx.findAncestorStateOfType<EditableTextState>();
      if (editable == null) return false;
      Clipboard.getData(Clipboard.kTextPlain).then((data) {
        if (data?.text == null || data!.text!.isEmpty) return;
        final val = editable.currentTextEditingValue;
        final newVal = val.replaced(val.selection, data.text!);
        editable.userUpdateTextEditingValue(newVal, SelectionChangedCause.keyboard);
      });
      return true;
    });

    sys.registerHandler(ShortcutCommand.recordRound, () {
      return ChatView.startRecordRoundRequest?.call() ?? false;
    });

    _audioService = context.read<AudioService>();
    _audioService!.addListener(_onAudioChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioService?.removeListener(_onAudioChanged);
    final sys = ShortcutSystem.instance;
    sys.hasActiveChatCallback = null;
    sys.isComposeFieldFocusedCallback = null;
    sys.isMediaViewerOpenCallback = null;
    sys.dispose();
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
