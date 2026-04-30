import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/engine_models.dart';

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

  const TelegramBox({
    super.key,
    this.title,
    this.titleTrailing,
    this.showClose = false,
    this.wide = false,
    required this.content,
    this.buttons = const [],
    this.onConfirm,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final titleFg =
        isDark ? const Color(0xFFE0E3EA) : const Color(0xFF000000);
    final width = widget.wide ? kBoxWideWidth : kBoxWidth;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Material(
        color: boxBg,
        borderRadius: BorderRadius.circular(kBoxRadius),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.title != null) _buildTitleBar(titleFg),
              Flexible(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: kBoxMaxListHeight),
                  child: SingleChildScrollView(child: widget.content),
                ),
              ),
              if (widget.buttons.isNotEmpty) _buildButtonRow(isDark),
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

  Widget _buildButtonRow(bool isDark) {
    final attnFg =
        isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);
    final accentFg =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final left = widget.buttons.where((b) => b.isLeft).toList();
    final right = widget.buttons.where((b) => !b.isLeft).toList();

    Widget btn(TelegramBoxButton b) {
      final fg = b.isDestructive ? attnFg : accentFg;
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 30),
        child: SizedBox(
          height: 34,
          child: TextButton(
            onPressed: b.onPressed,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              overlayColor:
                  b.isDestructive ? attnFg.withOpacity(0.1) : null,
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
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final textFg =
          isDark ? const Color(0xFFAAAAAA) : const Color(0xFF000000);

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

  const DeleteConfirmResult({
    this.confirmed = false,
    this.revoke = false,
    this.banUser = false,
    this.reportSpam = false,
    this.deleteAll = false,
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
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFg =
        isDark ? const Color(0xFFAAAAAA) : const Color(0xFF000000);
    final checkClr =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

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
