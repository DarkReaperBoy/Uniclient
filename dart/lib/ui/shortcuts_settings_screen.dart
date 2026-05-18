import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:flutter/services.dart';

import 'keyboard_shortcuts.dart';
import 'settings_style.dart';

const _commandGroups = <List<(ShortcutCommand, String)>>[
  // 1. App/Window
  [
    (ShortcutCommand.closeTelegram, 'Close Window'),
    (ShortcutCommand.lockTelegram, 'Lock by Passcode'),
    (ShortcutCommand.minimizeTelegram, 'Minimize'),
    (ShortcutCommand.quitTelegram, 'Quit'),
  ],
  // 2. Search
  [
    (ShortcutCommand.search, 'Search'),
  ],
  // 3. Chat Nav
  [
    (ShortcutCommand.chatPrevious, 'Previous Chat'),
    (ShortcutCommand.chatNext, 'Next Chat'),
    (ShortcutCommand.chatFirst, 'First Chat'),
    (ShortcutCommand.chatLast, 'Last Chat'),
    (ShortcutCommand.selfChat, 'Saved Messages'),
  ],
  // 4. Pinned Chats
  [
    (ShortcutCommand.pinnedChat1, 'Pinned Chat #1'),
    (ShortcutCommand.pinnedChat2, 'Pinned Chat #2'),
    (ShortcutCommand.pinnedChat3, 'Pinned Chat #3'),
    (ShortcutCommand.pinnedChat4, 'Pinned Chat #4'),
    (ShortcutCommand.pinnedChat5, 'Pinned Chat #5'),
    (ShortcutCommand.pinnedChat6, 'Pinned Chat #6'),
    (ShortcutCommand.pinnedChat7, 'Pinned Chat #7'),
    (ShortcutCommand.pinnedChat8, 'Pinned Chat #8'),
  ],
  // 5. Accounts
  [
    (ShortcutCommand.account1, 'Account #1'),
    (ShortcutCommand.account2, 'Account #2'),
    (ShortcutCommand.account3, 'Account #3'),
    (ShortcutCommand.account4, 'Account #4'),
    (ShortcutCommand.account5, 'Account #5'),
    (ShortcutCommand.account6, 'Account #6'),
  ],
  // 6. Folders
  [
    (ShortcutCommand.allChats, 'All Chats'),
    (ShortcutCommand.folder1, 'Folder #1'),
    (ShortcutCommand.folder2, 'Folder #2'),
    (ShortcutCommand.folder3, 'Folder #3'),
    (ShortcutCommand.folder4, 'Folder #4'),
    (ShortcutCommand.folder5, 'Folder #5'),
    (ShortcutCommand.folder6, 'Folder #6'),
    (ShortcutCommand.lastFolder, 'Last Folder'),
    (ShortcutCommand.nextFolder, 'Next Folder'),
    (ShortcutCommand.previousFolder, 'Previous Folder'),
    (ShortcutCommand.showArchive, 'Archive'),
    (ShortcutCommand.showContacts, 'Contacts'),
  ],
  // 7. Chat Actions
  [
    (ShortcutCommand.readChat, 'Mark as Read'),
    (ShortcutCommand.archiveChat, 'Archive Chat'),
    (ShortcutCommand.showScheduled, 'Scheduled Messages'),
    (ShortcutCommand.showChatMenu, 'Chat Menu'),
    (ShortcutCommand.showChatPreview, 'Chat Preview'),
  ],
  // 8. Send
  [
    (ShortcutCommand.message, 'Send Message'),
    (ShortcutCommand.messageSilently, 'Send Silently'),
    (ShortcutCommand.messageScheduled, 'Schedule Message'),
  ],
  // 9. Record
  [
    (ShortcutCommand.recordVoice, 'Record Voice'),
    (ShortcutCommand.recordRound, 'Record Video Message'),
  ],
  // 10. Admin Log
  [
    (ShortcutCommand.showAdminLog, 'Admin Log'),
  ],
  // 11. Media Viewer
  [
    (ShortcutCommand.mediaViewerVideoFullscreen, 'Video Fullscreen'),
  ],
  // 12. Media Playback
  [
    (ShortcutCommand.mediaPlay, 'Play'),
    (ShortcutCommand.mediaPause, 'Pause'),
    (ShortcutCommand.mediaPlayPause, 'Play / Pause'),
    (ShortcutCommand.mediaStop, 'Stop'),
    (ShortcutCommand.mediaPrevious, 'Previous Track'),
    (ShortcutCommand.mediaNext, 'Next Track'),
  ],
];

final _modifierKeys = {
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

final _serviceKeys = {
  LogicalKeyboardKey.escape, LogicalKeyboardKey.tab,
  LogicalKeyboardKey.backspace, LogicalKeyboardKey.enter,
  LogicalKeyboardKey.insert, LogicalKeyboardKey.delete,
  LogicalKeyboardKey.pause, LogicalKeyboardKey.printScreen,
  LogicalKeyboardKey.home, LogicalKeyboardKey.end,
  LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.pageUp, LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.capsLock, LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
};

bool _allowWithoutModifiers(LogicalKeyboardKey key) {
  if (_serviceKeys.contains(key)) return false;
  if (_modifierKeys.contains(key)) return false;
  final label = key.keyLabel;
  if (label.length == 1) {
    final c = label.codeUnitAt(0);
    if (c >= 0x20 && c <= 0x7E) return false;
  }
  return true;
}

class ShortcutsSettingsScreen extends StatefulWidget {
  const ShortcutsSettingsScreen({super.key});

  @override
  State<ShortcutsSettingsScreen> createState() =>
      _ShortcutsSettingsScreenState();
}

class _ShortcutsSettingsScreenState extends State<ShortcutsSettingsScreen> {
  final _currentBindings = <ShortcutCommand, List<KeyBinding>>{};
  ShortcutCommand? _recordingCommand;
  int _recordingIndex = -1;
  final _removedKeys = <ShortcutCommand, Set<String>>{};

  @override
  void initState() {
    super.initState();
    _loadBindings();
  }

  @override
  void dispose() {
    if (_recordingCommand != null) {
      ShortcutSystem.instance.stopRecording();
    }
    super.dispose();
  }

  void _loadBindings() {
    _currentBindings.clear();
    for (final b in ShortcutSystem.instance.currentBindings) {
      _currentBindings.putIfAbsent(b.command, () => []).add(b);
    }
  }

  bool get _isModified {
    final defaultByCmd = <ShortcutCommand, List<String>>{};
    for (final b in ShortcutSystem.defaultBindingsList) {
      defaultByCmd
          .putIfAbsent(b.command, () => [])
          .add(bindingToKeyString(b));
    }
    for (final cmd in ShortcutCommand.values) {
      final removed = _removedKeys[cmd];
      final currKeys = (_currentBindings[cmd] ?? [])
          .map(bindingToKeyString)
          .where((k) => removed == null || !removed.contains(k))
          .toList()
        ..sort();
      final defKeys = (defaultByCmd[cmd] ?? [])..sort();
      if (currKeys.length != defKeys.length) return true;
      for (int i = 0; i < currKeys.length; i++) {
        if (currKeys[i] != defKeys[i]) return true;
      }
    }
    return false;
  }

  bool get _isRecording => _recordingCommand != null;

  void _startRecording(ShortcutCommand cmd, int index) {
    setState(() {
      _recordingCommand = cmd;
      _recordingIndex = index;
      _removedKeys.clear();
    });
    ShortcutSystem.instance.startRecording(_onRecordingKeyEvent);
  }

  void _cancelRecording() {
    setState(() {
      _recordingCommand = null;
      _recordingIndex = -1;
    });
    ShortcutSystem.instance.stopRecording();
  }

  void _assignBinding(KeyBinding newBinding) {
    final keyStr = bindingToKeyString(newBinding);
    setState(() {
      for (final entry in _currentBindings.entries) {
        if (entry.key == _recordingCommand) continue;
        for (final b in entry.value) {
          if (bindingToKeyString(b) == keyStr) {
            _removedKeys.putIfAbsent(entry.key, () => {}).add(keyStr);
          }
        }
      }
      final bindings =
          _currentBindings.putIfAbsent(_recordingCommand!, () => []);
      if (_recordingIndex < bindings.length) {
        bindings[_recordingIndex] = newBinding;
      } else {
        bindings.add(newBinding);
      }
      _recordingCommand = null;
      _recordingIndex = -1;
    });
    ShortcutSystem.instance.stopRecording();
    _syncToSystem();
  }

  void _clearBinding(ShortcutCommand cmd, int index) {
    setState(() {
      final bindings = _currentBindings[cmd];
      if (bindings != null && index < bindings.length) {
        bindings.removeAt(index);
        if (bindings.isEmpty) _currentBindings.remove(cmd);
      }
      _recordingCommand = null;
      _recordingIndex = -1;
    });
    ShortcutSystem.instance.stopRecording();
    _syncToSystem();
  }

  void _addAnotherBinding(ShortcutCommand cmd) {
    final bindings = _currentBindings.putIfAbsent(cmd, () => []);
    final newIndex = bindings.length;
    _startRecording(cmd, newIndex);
  }

  void _showContextMenu(ShortcutCommand cmd, Offset globalPosition) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuText = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx, globalPosition.dy,
        globalPosition.dx, globalPosition.dy,
      ),
      items: [
        PopupMenuItem<void>(
          onTap: () => _addAnotherBinding(cmd),
          child: Row(
            children: [
              Icon(Icons.add, size: 20, color: menuText),
              const SizedBox(width: 12),
              Text('Add another binding',
                style: TextStyle(fontSize: 14, color: menuText)),
            ],
          ),
        ),
      ],
    );
  }

  void _resetToDefaults() {
    if (_isRecording) _cancelRecording();
    setState(() {
      _currentBindings.clear();
      _removedKeys.clear();
      for (final b in ShortcutSystem.defaultBindingsList) {
        _currentBindings.putIfAbsent(b.command, () => []).add(b);
      }
    });
    _syncToSystem();
  }

  void _syncToSystem() {
    final sys = ShortcutSystem.instance;
    final allBindings = <KeyBinding>[];
    for (final entry in _currentBindings.entries) {
      final removed = _removedKeys[entry.key];
      for (final b in entry.value) {
        if (removed != null && removed.contains(bindingToKeyString(b))) continue;
        allBindings.add(b);
      }
    }
    sys.replaceAllBindings(allBindings);
    sys.saveToCustomFile();
  }

  void _onRecordingKeyEvent(KeyEvent event) {
    if (!_isRecording) return;
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (_modifierKeys.contains(key)) return;

    final hwCtrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final hwMeta = HardwareKeyboard.instance.isMetaPressed;

    if (key == LogicalKeyboardKey.escape &&
        !hwCtrl && !shift && !alt && !hwMeta) {
      _cancelRecording();
      return;
    }

    if ((key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete) &&
        !hwCtrl && !shift && !alt && !hwMeta) {
      _clearBinding(_recordingCommand!, _recordingIndex);
      return;
    }

    final hasModifier = hwCtrl || alt || hwMeta;
    if (!hasModifier && !shift && !_allowWithoutModifiers(key)) {
      _cancelRecording();
      return;
    }

    final isMac = !kIsWeb && Platform.isMacOS;
    final ctrl = isMac ? hwMeta : hwCtrl;
    final meta = isMac ? hwCtrl : hwMeta;

    _assignBinding(KeyBinding(
      key,
      _recordingCommand!,
      control: ctrl,
      shift: shift,
      alt: alt,
      meta: meta,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final goodColor = const Color(0xFF4CAF50);
    final attentionColor =
        isDark ? const Color(0xFFE53935) : const Color(0xFFDF3F40);
    final modified = _isModified;

    return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: textColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Keyboard Shortcuts',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: modified
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(height: 1, color: dividerColor),
                        const SizedBox(height: 7),
                        _ResetButton(
                          bgColor: bgColor,
                          textColor: accentColor,
                          hoverBg: hoverBg,
                          onTap: _resetToDefaults,
                        ),
                        const SizedBox(height: 7),
                        Container(height: 1, color: dividerColor),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            for (int gi = 0; gi < _commandGroups.length; gi++) ...[
              if (gi > 0) ...[
                const SizedBox(height: 7),
                Container(height: 1, color: dividerColor),
                const SizedBox(height: 7),
              ],
              for (final (cmd, label) in _commandGroups[gi])
                ..._buildCommandRows(
                  cmd,
                  label,
                  textColor: textColor,
                  subtextColor: subtextColor,
                  hoverBg: hoverBg,
                  goodColor: goodColor,
                  attentionColor: attentionColor,
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
    );
  }

  List<Widget> _buildCommandRows(
    ShortcutCommand cmd,
    String label, {
    required Color textColor,
    required Color subtextColor,
    required Color hoverBg,
    required Color goodColor,
    required Color attentionColor,
  }) {
    final bindings = _currentBindings[cmd] ?? [];
    if (bindings.isEmpty) {
      return [
        _ShortcutRow(
          label: label,
          keyLabel: '',
          keyColor: subtextColor,
          isRecording:
              _recordingCommand == cmd && _recordingIndex == 0,
          recordingColor: goodColor,
          textColor: textColor,
          hoverBg: hoverBg,
          onTap: () => _startRecording(cmd, 0),
          onSecondaryTapUp: (pos) => _showContextMenu(cmd, pos),
        ),
      ];
    }

    final rows = <Widget>[];
    for (int i = 0; i < bindings.length; i++) {
      final b = bindings[i];
      final keyStr = ShortcutSystem.displayBindingString(b);
      final isConflictSource =
          _removedKeys[cmd]?.contains(bindingToKeyString(b)) ?? false;

      rows.add(_ShortcutRow(
        label: label,
        keyLabel: keyStr,
        keyColor: isConflictSource ? attentionColor : subtextColor,
        strikethrough: isConflictSource,
        isRecording: _recordingCommand == cmd && _recordingIndex == i,
        recordingColor: goodColor,
        textColor: textColor,
        hoverBg: hoverBg,
        onTap: () => _startRecording(cmd, i),
        onSecondaryTapUp: (pos) => _showContextMenu(cmd, pos),
      ));
    }

    if (_recordingCommand == cmd && _recordingIndex >= bindings.length) {
      rows.add(_ShortcutRow(
        label: label,
        keyLabel: '',
        keyColor: subtextColor,
        isRecording: true,
        recordingColor: goodColor,
        textColor: textColor,
        hoverBg: hoverBg,
        onTap: () {},
        onSecondaryTapUp: (_) {},
      ));
    }

    return rows;
  }
}

class _ResetButton extends StatelessWidget {
  final Color bgColor;
  final Color textColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _ResetButton({
    required this.bgColor,
    required this.textColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      child: Padding(
        padding: SettingsStyle.noIconPadding,
        child: SizedBox(
          height: SettingsStyle.rowHeight - 20,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Reset to defaults',
              style: TextStyle(
                fontSize: SettingsStyle.buttonFontSize,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String label;
  final String keyLabel;
  final Color keyColor;
  final bool strikethrough;
  final bool isRecording;
  final Color recordingColor;
  final Color textColor;
  final Color hoverBg;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onSecondaryTapUp;

  const _ShortcutRow({
    required this.label,
    required this.keyLabel,
    required this.keyColor,
    this.strikethrough = false,
    required this.isRecording,
    required this.recordingColor,
    required this.textColor,
    required this.hoverBg,
    required this.onTap,
    required this.onSecondaryTapUp,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) => onSecondaryTapUp(details.globalPosition),
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverBg,
        child: Padding(
          padding: SettingsStyle.noIconPadding,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              if (isRecording)
                Text(
                  'Recording...',
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    fontStyle: FontStyle.italic,
                    color: recordingColor,
                  ),
                )
              else
                Text(
                  keyLabel,
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    color: keyColor,
                    decoration: strikethrough
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: keyColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
