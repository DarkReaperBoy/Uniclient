import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/engine_models.dart';
import '../theme/telegram_palette.dart';

// ─── §36.1 Box/Dialog Infrastructure Constants ───────────────────────────────

const double kBoxWidth = 320;
const double kBoxWideWidth = 364;
const EdgeInsets kBoxPadding = EdgeInsets.fromLTRB(24, 14, 24, 8);
const double kBoxRadius = 8;
const double kBoxTitleHeight = 48;
const double kBoxMaxListHeight = 492;
const double kBoxMediumSkip = 20;
const double kBoxLittleSkip = 10;
const Duration kBoxDuration = Duration(milliseconds: 200);

// ─── showTelegramBox — spec §36.1 animation: 200ms easeOutCirc dim, linear
//     opacity on the box itself ───────────────────────────────────────────────

Future<T?> showTelegramBox<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: kBoxDuration,
    transitionBuilder: (ctx, animation, _, child) {
      final dimAnim = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCirc,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: dimAnim,
                child: const ColoredBox(color: Color(0x8A000000)),
              ),
            ),
          ),
          FadeTransition(
            opacity: animation,
            child: Center(child: child),
          ),
        ],
      );
    },
    pageBuilder: (ctx, _, __) => builder(ctx),
  );
}

// ─── TelegramBoxButton ───────────────────────────────────────────────────────

class TelegramBoxButton {
  final String text;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final bool isLeft;

  const TelegramBoxButton({
    required this.text,
    this.onPressed,
    this.isDestructive = false,
    this.isLeft = false,
  });
}

// ─── TelegramBox — reusable box chrome (§36.1) ──────────────────────────────
//
// 48px title bar (16px semibold at (24,13)), scrollable content 24px h-padding,
// right-aligned button row, 320/364px width, 8px radius, Enter confirms.

class TelegramBox extends StatefulWidget {
  final String? title;
  final Widget? titleTrailing;
  final bool showClose;
  final bool wide;
  final Widget content;
  final List<TelegramBoxButton> buttons;
  final VoidCallback? onConfirm;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final bool scrollableContent;

  const TelegramBox({
    super.key,
    this.title,
    this.titleTrailing,
    this.showClose = false,
    this.wide = false,
    required this.content,
    this.buttons = const [],
    this.onConfirm,
    this.onKeyEvent,
    this.scrollableContent = true,
  });

  @override
  State<TelegramBox> createState() => _TelegramBoxState();
}

class _TelegramBoxState extends State<TelegramBox> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.onKeyEvent != null) {
      final result = widget.onKeyEvent!(node, event);
      if (result == KeyEventResult.handled) return result;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (widget.onConfirm != null) {
        widget.onConfirm!();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = widget.wide ? kBoxWideWidth : kBoxWidth;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Material(
        color: p.boxBg,
        borderRadius: BorderRadius.circular(kBoxRadius),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.title != null) _buildTitleBar(p.boxTitleFg),
              Flexible(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: kBoxMaxListHeight),
                  child: widget.scrollableContent
                      ? SingleChildScrollView(child: widget.content)
                      : widget.content,
                ),
              ),
              if (widget.buttons.isNotEmpty) _buildButtonRow(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(Color fg) {
    return SizedBox(
      height: kBoxTitleHeight,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 13, 0, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  widget.title!,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          if (widget.titleTrailing != null) widget.titleTrailing!,
          if (widget.showClose)
            SizedBox(
              width: kBoxTitleHeight,
              height: kBoxTitleHeight,
              child: IconButton(
                icon: Icon(Icons.close, size: 20, color: fg),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildButtonRow(TelegramPalette p) {
    final left = widget.buttons.where((b) => b.isLeft).toList();
    final right = widget.buttons.where((b) => !b.isLeft).toList();

    Widget btn(TelegramBoxButton b) {
      final fg = b.isDestructive ? p.attentionButtonFg : p.windowBgActive;
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 30),
        child: SizedBox(
          height: 34,
          child: TextButton(
            onPressed: b.onPressed,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              overlayColor:
                  b.isDestructive ? fg.withOpacity(0.1) : null,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(b.text),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          for (final b in left) ...[btn(b), const SizedBox(width: 4)],
          const Spacer(),
          for (int i = 0; i < right.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            btn(right[i]),
          ],
        ],
      ),
    );
  }
}

// ─── showConfirmBox — §36.2 ConfirmBox ───────────────────────────────────────

Future<void> showConfirmBox(
  BuildContext context, {
  required String text,
  String? confirmText,
  String? cancelText,
  VoidCallback? onConfirm,
  VoidCallback? onCancel,
  bool isDestructive = false,
  String? title,
  bool inform = false,
}) {
  return showTelegramBox<void>(
    context: context,
    builder: (ctx) {
      final textFg = ctx.palette.boxTextFg;

      void confirm() {
        Navigator.of(ctx).pop();
        onConfirm?.call();
      }

      return TelegramBox(
        title: title,
        onConfirm: confirm,
        content: Padding(
          padding: title != null
              ? EdgeInsets.fromLTRB(
                  kBoxPadding.left, 0, kBoxPadding.right, kBoxPadding.bottom)
              : kBoxPadding,
          child: Text(
            text,
            style: TextStyle(fontSize: 14, height: 22 / 14, color: textFg),
          ),
        ),
        buttons: [
          if (!inform)
            TelegramBoxButton(
              text: cancelText ?? 'Cancel',
              onPressed: () {
                Navigator.of(ctx).pop();
                onCancel?.call();
              },
            ),
          TelegramBoxButton(
            text: confirmText ?? 'OK',
            isDestructive: isDestructive,
            onPressed: confirm,
          ),
        ],
      );
    },
  );
}

// ─── Delete / Leave ConfirmBox — §36.2 destructive variant ───────────────────

enum DeleteBoxMode { singleMessage, bulkMessages, clearHistory, leaveChat }

class DeleteConfirmResult {
  final bool confirmed;
  final bool revoke;
  final bool banUser;
  final bool reportSpam;
  final bool deleteAll;
  final bool rememberRevoke;

  const DeleteConfirmResult({
    this.confirmed = false,
    this.revoke = false,
    this.banUser = false,
    this.reportSpam = false,
    this.deleteAll = false,
    this.rememberRevoke = false,
  });
}

Future<DeleteConfirmResult> showDeleteConfirmBox(
  BuildContext context, {
  required DeleteBoxMode mode,
  ChatType chatType = ChatType.dm,
  String peerName = '',
  int messageCount = 1,
  bool canRevoke = false,
  bool showModeratePanel = false,
  bool isSavedMessages = false,
}) {
  return showTelegramBox<DeleteConfirmResult>(
    context: context,
    builder: (ctx) => _DeleteContent(
      mode: mode,
      chatType: chatType,
      peerName: peerName,
      messageCount: messageCount,
      canRevoke: canRevoke,
      showModeratePanel: showModeratePanel,
      isSavedMessages: isSavedMessages,
    ),
  ).then((r) => r ?? const DeleteConfirmResult());
}

class _DeleteContent extends StatefulWidget {
  final DeleteBoxMode mode;
  final ChatType chatType;
  final String peerName;
  final int messageCount;
  final bool canRevoke;
  final bool showModeratePanel;
  final bool isSavedMessages;

  const _DeleteContent({
    required this.mode,
    required this.chatType,
    required this.peerName,
    required this.messageCount,
    required this.canRevoke,
    required this.showModeratePanel,
    required this.isSavedMessages,
  });

  @override
  State<_DeleteContent> createState() => _DeleteContentState();
}

class _DeleteContentState extends State<_DeleteContent> {
  bool _revoke = false;
  bool _revokeRemember = false;
  bool _banUser = false;
  bool _reportSpam = false;
  bool _deleteAll = false;

  String get _bodyText {
    final name = widget.peerName;
    switch (widget.mode) {
      case DeleteBoxMode.singleMessage:
        return 'Are you sure you want to delete this message?';
      case DeleteBoxMode.bulkMessages:
        final n = widget.messageCount;
        if (n == 1) return 'Are you sure you want to delete this message?';
        return 'Are you sure you want to delete $n messages?';
      case DeleteBoxMode.clearHistory:
        if (widget.isSavedMessages) {
          return 'Are you sure you want to delete your Saved Messages?';
        }
        switch (widget.chatType) {
          case ChatType.channel:
            return 'Are you sure you want to delete all message history in "$name"?';
          case ChatType.group:
          case ChatType.topic:
            return 'Are you sure you want to delete all message history in "$name"?';
          case ChatType.dm:
          default:
            return 'Are you sure you want to delete all message history with $name?';
        }
      case DeleteBoxMode.leaveChat:
        if (widget.isSavedMessages) {
          return 'Are you sure you want to delete your Saved Messages?';
        }
        switch (widget.chatType) {
          case ChatType.channel:
            return 'Are you sure you want to leave this channel?';
          case ChatType.group:
          case ChatType.topic:
            return 'Are you sure you want to delete and leave "$name"?';
          case ChatType.dm:
          default:
            return 'Are you sure you want to delete all message history with $name?';
        }
    }
  }

  String get _confirmLabel {
    switch (widget.mode) {
      case DeleteBoxMode.leaveChat:
        if (widget.chatType == ChatType.channel ||
            widget.chatType == ChatType.group ||
            widget.chatType == ChatType.topic) {
          return _revoke ? 'Delete' : 'Leave';
        }
        return 'Delete';
      case DeleteBoxMode.clearHistory:
        return 'Delete';
      case DeleteBoxMode.singleMessage:
      case DeleteBoxMode.bulkMessages:
        final suffix = _deleteAll ? ' (...)' : '';
        return 'Delete$suffix';
    }
  }

  String? get _revokeLabel {
    if (!widget.canRevoke) return null;
    if (widget.mode == DeleteBoxMode.singleMessage ||
        widget.mode == DeleteBoxMode.bulkMessages) {
      if (widget.chatType == ChatType.dm) {
        return 'Also delete for ${widget.peerName}';
      }
      return 'Also delete for everyone';
    }
    return null;
  }

  void _confirm() {
    Navigator.of(context).pop(DeleteConfirmResult(
      confirmed: true,
      revoke: _revoke,
      banUser: _banUser,
      reportSpam: _reportSpam,
      deleteAll: _deleteAll,
      rememberRevoke: _revokeRemember,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;
    final checkClr = p.windowBgActive;

    return TelegramBox(
      onConfirm: _confirm,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: kBoxPadding,
            child: Text(
              _bodyText,
              style: TextStyle(fontSize: 14, height: 22 / 14, color: textFg),
            ),
          ),
          if (widget.showModeratePanel) ...[
            const SizedBox(height: kBoxMediumSkip),
            _checkbox('Ban User', _banUser,
                (v) => setState(() => _banUser = v ?? false), checkClr, textFg),
            const SizedBox(height: kBoxLittleSkip),
            _checkbox(
                'Report Spam',
                _reportSpam,
                (v) => setState(() => _reportSpam = v ?? false),
                checkClr,
                textFg),
            const SizedBox(height: kBoxLittleSkip),
            _checkbox(
              'Delete All from ${widget.peerName}',
              _deleteAll,
              (v) => setState(() => _deleteAll = v ?? false),
              checkClr,
              textFg,
            ),
          ],
          if (_revokeLabel != null) ...[
            const SizedBox(height: kBoxMediumSkip),
            _checkbox(_revokeLabel!, _revoke,
                (v) => setState(() => _revoke = v ?? false), checkClr, textFg),
            if (_revoke) ...[
              const SizedBox(height: kBoxLittleSkip),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: _checkbox('Remember this choice', _revokeRemember,
                    (v) => setState(() => _revokeRemember = v ?? false), checkClr, textFg),
              ),
            ],
          ],
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () =>
              Navigator.of(context).pop(const DeleteConfirmResult()),
        ),
        TelegramBoxButton(
          text: _confirmLabel,
          isDestructive: true,
          onPressed: _confirm,
        ),
      ],
    );
  }

  Widget _checkbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
    Color checkColor,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: checkColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── showSingleChoiceBox — §36.5 SingleChoiceBox ────────────────────────────

Future<int?> showSingleChoiceBox(
  BuildContext context, {
  required String title,
  required List<String> options,
  int initialSelection = 0,
  ValueChanged<int>? onChanged,
}) {
  return showTelegramBox<int>(
    context: context,
    builder: (ctx) => _SingleChoiceContent(
      title: title,
      options: options,
      initialSelection: initialSelection,
      onChanged: onChanged,
    ),
  );
}

class _SingleChoiceContent extends StatefulWidget {
  final String title;
  final List<String> options;
  final int initialSelection;
  final ValueChanged<int>? onChanged;

  const _SingleChoiceContent({
    required this.title,
    required this.options,
    required this.initialSelection,
    this.onChanged,
  });

  @override
  State<_SingleChoiceContent> createState() => _SingleChoiceContentState();
}

class _SingleChoiceContentState extends State<_SingleChoiceContent> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
  }

  void _select(int index) {
    setState(() => _selected = index);
    widget.onChanged?.call(index);
    Navigator.of(context).pop(index);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;
    final accentFg = p.windowBgActive;
    final hoverBg = p.windowBgOver;

    return TelegramBox(
      title: widget.title,
      onConfirm: () => Navigator.of(context).pop(_selected),
      content: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.options.length, (i) {
            return _RadioRow(
              label: widget.options[i],
              selected: _selected == i,
              textColor: textFg,
              accentColor: accentFg,
              hoverColor: hoverBg,
              onTap: () => _select(i),
            );
          }),
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'OK',
          onPressed: () => Navigator.of(context).pop(_selected),
        ),
      ],
    );
  }
}

class _RadioRow extends StatefulWidget {
  final String label;
  final bool selected;
  final Color textColor;
  final Color accentColor;
  final Color hoverColor;
  final VoidCallback onTap;

  const _RadioRow({
    required this.label,
    required this.selected,
    required this.textColor,
    required this.accentColor,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  State<_RadioRow> createState() => _RadioRowState();
}

class _RadioRowState extends State<_RadioRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovering ? widget.hoverColor : null,
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Radio<bool>(
                  value: true,
                  groupValue: widget.selected,
                  onChanged: (_) => widget.onTap(),
                  activeColor: widget.accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── §36.12 Permission Request Dialogs ──────────────────────────────────────

enum PermissionType { microphone, camera }

enum PermissionStatus { granted, canRequest, denied }

Future<PermissionStatus> getPermissionStatus(PermissionType type) async {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    return PermissionStatus.granted;
  }
  try {
    if (type == PermissionType.microphone) {
      final result = await Process.run('pactl', ['list', 'sources', 'short']);
      if (result.exitCode != 0) return PermissionStatus.denied;
      final output = result.stdout as String;
      if (output.trim().isEmpty) return PermissionStatus.denied;
      return PermissionStatus.granted;
    } else {
      final result = await Process.run('ls', ['/dev/video0']);
      return result.exitCode == 0
          ? PermissionStatus.granted
          : PermissionStatus.denied;
    }
  } catch (_) {
    return PermissionStatus.canRequest;
  }
}

void openSystemSettingsForPermission(PermissionType type) {
  if (Platform.isLinux) {
    Process.run('xdg-open', ['gnome-control-center://sound']).catchError((_) {
      Process.run('xdg-open', ['x-settings://sound']);
    });
  } else if (Platform.isMacOS) {
    final pane = type == PermissionType.microphone
        ? 'Privacy_Microphone'
        : 'Privacy_Camera';
    Process.run(
      'open',
      ['x-apple.systempreferences:com.apple.preference.security?$pane'],
    );
  } else if (Platform.isWindows) {
    final page = type == PermissionType.microphone
        ? 'ms-settings:privacy-microphone'
        : 'ms-settings:privacy-webcam';
    Process.run('cmd', ['/c', 'start', page]);
  }
}

String _permissionLabel(PermissionType type) {
  return switch (type) {
    PermissionType.microphone => 'microphone',
    PermissionType.camera => 'camera',
  };
}

Future<bool> showPermissionDeniedBox(
  BuildContext context,
  PermissionType type,
) async {
  final text = type == PermissionType.microphone
      ? 'UniClient needs microphone access so that you can make calls and record voice messages.'
      : 'UniClient needs camera access so that you can make video calls.';

  bool openedSettings = false;
  await showConfirmBox(
    context,
    text: text,
    confirmText: 'Settings',
    cancelText: 'Cancel',
    onConfirm: () {
      openedSettings = true;
      openSystemSettingsForPermission(type);
    },
  );
  return openedSettings;
}

Future<bool> requestPermissionOrFail(
  BuildContext context,
  PermissionType type, {
  VoidCallback? onDenied,
}) async {
  final status = await getPermissionStatus(type);
  switch (status) {
    case PermissionStatus.granted:
      return true;
    case PermissionStatus.canRequest:
      final recheck = await getPermissionStatus(type);
      if (recheck == PermissionStatus.granted) return true;
      onDenied?.call();
      if (context.mounted) {
        await showPermissionDeniedBox(context, type);
      }
      return false;
    case PermissionStatus.denied:
      onDenied?.call();
      if (context.mounted) {
        await showPermissionDeniedBox(context, type);
      }
      return false;
  }
}

Future<bool> requestCallPermissions(
  BuildContext context, {
  bool video = false,
  VoidCallback? onDenied,
}) async {
  final micOk = await requestPermissionOrFail(
    context,
    PermissionType.microphone,
    onDenied: onDenied,
  );
  if (!micOk) return false;
  if (video) {
    final camOk = await requestPermissionOrFail(
      context,
      PermissionType.camera,
      onDenied: onDenied,
    );
    if (!camOk) return false;
  }
  return true;
}

// ─── §36.12 Screen Share Chooser ────────────────────────────────────────────

class ScreenShareSource {
  final String id;
  final String name;
  final bool isScreen;

  const ScreenShareSource({
    required this.id,
    required this.name,
    this.isScreen = false,
  });
}

class ScreenShareResult {
  final ScreenShareSource source;
  final bool withAudio;

  const ScreenShareResult({required this.source, this.withAudio = false});
}

Future<ScreenShareResult?> showScreenShareChooser(BuildContext context) {
  return showTelegramBox<ScreenShareResult>(
    context: context,
    builder: (ctx) => const _ScreenShareChooser(),
  );
}

class _ScreenShareChooser extends StatefulWidget {
  const _ScreenShareChooser();

  @override
  State<_ScreenShareChooser> createState() => _ScreenShareChooserState();
}

class _ScreenShareChooserState extends State<_ScreenShareChooser> {
  List<ScreenShareSource> _sources = [];
  bool _loading = true;
  int _selectedIndex = -1;
  bool _withAudio = false;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    final sources = <ScreenShareSource>[];
    try {
      final xrandr = await Process.run('xrandr', ['--listmonitors']);
      if (xrandr.exitCode == 0) {
        final lines = (xrandr.stdout as String).split('\n');
        for (int i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          final parts = line.split(RegExp(r'\s+'));
          final name = parts.length > 1 ? parts.last : 'Screen $i';
          sources.add(ScreenShareSource(
            id: 'screen:${i - 1}',
            name: name,
            isScreen: true,
          ));
        }
      }
    } catch (_) {
      sources.add(const ScreenShareSource(
        id: 'screen:0',
        name: 'Entire Screen',
        isScreen: true,
      ));
    }

    if (sources.isEmpty) {
      sources.add(const ScreenShareSource(
        id: 'screen:0',
        name: 'Entire Screen',
        isScreen: true,
      ));
    }

    if (mounted) {
      setState(() {
        _sources = sources;
        _loading = false;
        if (sources.isNotEmpty) _selectedIndex = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final subTextColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowActiveTextFg;
    final selectedBorder = accentColor;
    final cardBg = p.boxSearchBg;

    return TelegramBox(
      title: 'Choose what to share',
      wide: true,
      scrollableContent: false,
      content: SizedBox(
        height: 340,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _sources.isEmpty
                          ? Center(
                              child: Text(
                                'No sources available',
                                style: TextStyle(
                                    color: subTextColor, fontSize: 14),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 16 / 10,
                              ),
                              itemCount: _sources.length,
                              itemBuilder: (ctx, i) {
                                final source = _sources[i];
                                final selected = i == _selectedIndex;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedIndex = i),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected
                                            ? selectedBorder
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          source.isScreen
                                              ? Icons.desktop_windows
                                              : Icons.web_asset,
                                          size: 40,
                                          color: selected
                                              ? accentColor
                                              : subTextColor,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          source.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: textColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _withAudio,
                            onChanged: (v) =>
                                setState(() => _withAudio = v ?? false),
                            activeColor: accentColor,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _withAudio = !_withAudio),
                          child: Text(
                            'SHARE AUDIO',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'START SHARING',
          onPressed: _selectedIndex >= 0
              ? () {
                  Navigator.of(context).pop(ScreenShareResult(
                    source: _sources[_selectedIndex],
                    withAudio: _withAudio,
                  ));
                }
              : null,
        ),
      ],
    );
  }
}

// ─── §36.13 Report Flow ─────────────────────────────────────────────────────

enum ReportTarget { message, channel, group, bot, story, profilePhoto, user }

Future<String?> showReportReasonBox(
  BuildContext context, {
  ReportTarget target = ReportTarget.message,
}) {
  String title;
  switch (target) {
    case ReportTarget.channel:
      title = 'Report Channel';
    case ReportTarget.group:
      title = 'Report Group';
    case ReportTarget.bot:
      title = 'Report Bot';
    case ReportTarget.story:
      title = 'Report Story';
    case ReportTarget.profilePhoto:
      title = 'Report Profile Photo';
    case ReportTarget.user:
      title = 'Report User';
    case ReportTarget.message:
      title = 'Report Message';
  }

  return showTelegramBox<String>(
    context: context,
    builder: (ctx) => _ReportReasonBox(title: title),
  );
}

class _ReportReasonBox extends StatelessWidget {
  final String title;
  const _ReportReasonBox({required this.title});

  static const _reasons = [
    ('Spam', 'spam'),
    ('Fake Account', 'fake'),
    ('Violence', 'violence'),
    ('Child Abuse', 'child_abuse'),
    ('Pornography', 'pornography'),
    ('Copyright', 'copyright'),
    ('Illegal Drugs', 'illegal_drugs'),
    ('Personal Details', 'personal_details'),
    ('Other', 'other'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;
    final hoverBg = p.windowBgOver;

    return TelegramBox(
      title: title,
      showClose: true,
      content: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _reasons.map((r) {
            return InkWell(
              onTap: () => Navigator.of(context).pop(r.$2),
              hoverColor: hoverBg,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 11, 24, 11),
                child: Text(
                  r.$1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: textFg,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      scrollableContent: true,
    );
  }
}

Future<String?> showReportDetailsBox(
  BuildContext context, {
  bool optional = true,
}) {
  return showTelegramBox<String>(
    context: context,
    builder: (ctx) => _ReportDetailsBox(optional: optional),
  );
}

class _ReportDetailsBox extends StatefulWidget {
  final bool optional;
  const _ReportDetailsBox({required this.optional});

  @override
  State<_ReportDetailsBox> createState() => _ReportDetailsBoxState();
}

class _ReportDetailsBoxState extends State<_ReportDetailsBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.optional && _controller.text.trim().isEmpty) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final textFg = context.palette.boxTextFg;

    return TelegramBox(
      title: 'Report',
      onConfirm: _submit,
      content: Padding(
        padding: kBoxPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please enter any additional details relevant to your report.',
              style: TextStyle(fontSize: 14, color: textFg),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.optional
                    ? 'Add Comment (Optional)'
                    : 'Add Comment',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'REPORT',
          isDestructive: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

Future<bool> showReportReactionBox(BuildContext context) async {
  final result = await showTelegramBox<bool>(
    context: context,
    builder: (ctx) {
      final textFg = ctx.palette.boxTextFg;

      return TelegramBox(
        title: 'Report Reactions',
        content: Padding(
          padding: kBoxPadding,
          child: Text(
            'Are you sure you want to report reactions from this user?',
            style: TextStyle(fontSize: 14, color: textFg),
          ),
        ),
        buttons: [
          TelegramBoxButton(
            text: 'CANCEL',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          TelegramBoxButton(
            text: 'BAN USER',
            isDestructive: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        onConfirm: () => Navigator.of(ctx).pop(true),
      );
    },
  );
  return result ?? false;
}
