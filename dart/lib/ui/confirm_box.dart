import 'package:flutter/material.dart';

import '../models/engine_models.dart';

/// Telegram Desktop spec-compliant ConfirmBox (§36.2).
///
/// Dimensions: boxWidth=320, boxPadding=EdgeInsets(24,14,24,8),
/// boxRadius=3, boxBg=white/#17212b, boxLabel=22px lineHeight.
/// Destructive actions use attentionBoxButton (red confirm text).

const double _boxWidth = 320;
const EdgeInsets _boxPadding = EdgeInsets.fromLTRB(24, 14, 24, 8);
const double _boxRadius = 3;
const double _boxTitleHeight = 48;
const double _boxMediumSkip = 20;
const double _boxLittleSkip = 10;

/// Show a Telegram-style ConfirmBox dialog.
///
/// [text] — body message.
/// [confirmText] — confirm button label (default "OK").
/// [cancelText] — cancel button label (default "Cancel").
/// [onConfirm] — callback when confirmed. Dialog closes automatically.
/// [onCancel] — optional callback when cancelled.
/// [isDestructive] — if true, confirm button uses attentionBoxButton (red).
/// [title] — optional title text.
/// [inform] — if true, only show confirm button (no cancel). InformBox mode.
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
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ConfirmBoxDialog(
      text: text,
      confirmText: confirmText ?? (inform ? 'OK' : 'OK'),
      cancelText: cancelText ?? 'Cancel',
      onConfirm: onConfirm,
      onCancel: onCancel,
      isDestructive: isDestructive,
      title: title,
      inform: inform,
    ),
  );
}

class _ConfirmBoxDialog extends StatelessWidget {
  final String text;
  final String confirmText;
  final String cancelText;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool isDestructive;
  final String? title;
  final bool inform;

  const _ConfirmBoxDialog({
    required this.text,
    required this.confirmText,
    required this.cancelText,
    this.onConfirm,
    this.onCancel,
    this.isDestructive = false,
    this.title,
    this.inform = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Spec colors
    final boxBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final boxTitleFg = isDark ? const Color(0xFFE0E3EA) : const Color(0xFF000000);
    final boxTextFg = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF000000);
    // attentionBoxButton: red text for destructive confirm
    final attentionFg = isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);
    // defaultBoxButton: accent blue
    final defaultFg = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final cancelFg = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final confirmColor = isDestructive ? attentionFg : defaultFg;

    return Dialog(
      backgroundColor: boxBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_boxRadius),
      ),
      elevation: 4,
      child: SizedBox(
        width: _boxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Optional title bar
            if (title != null)
              SizedBox(
                height: _boxTitleHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: boxTitleFg,
                      ),
                    ),
                  ),
                ),
              ),
            // Body text — boxLabel style (22px line height)
            Padding(
              padding: title != null
                  ? EdgeInsets.fromLTRB(
                      _boxPadding.left, 0, _boxPadding.right, _boxPadding.bottom)
                  : _boxPadding,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 22 / 14, // boxLabel: 22px line height
                  color: boxTextFg,
                ),
              ),
            ),
            // Button row — right-aligned
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!inform)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onCancel?.call();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: cancelFg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: Text(cancelText),
                    ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onConfirm?.call();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: confirmColor,
                      overlayColor: isDestructive
                          ? attentionFg.withOpacity(0.1)
                          : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: Text(confirmText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Delete / Leave confirmation box — spec §9.5
// ---------------------------------------------------------------------------

enum DeleteBoxMode {
  singleMessage,
  bulkMessages,
  clearHistory,
  leaveChat,
}

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
  return showDialog<DeleteConfirmResult>(
    context: context,
    builder: (ctx) => _DeleteConfirmBoxDialog(
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

class _DeleteConfirmBoxDialog extends StatefulWidget {
  final DeleteBoxMode mode;
  final ChatType chatType;
  final String peerName;
  final int messageCount;
  final bool canRevoke;
  final bool showModeratePanel;
  final bool isSavedMessages;

  const _DeleteConfirmBoxDialog({
    required this.mode,
    required this.chatType,
    required this.peerName,
    required this.messageCount,
    required this.canRevoke,
    required this.showModeratePanel,
    required this.isSavedMessages,
  });

  @override
  State<_DeleteConfirmBoxDialog> createState() =>
      _DeleteConfirmBoxDialogState();
}

class _DeleteConfirmBoxDialogState extends State<_DeleteConfirmBoxDialog> {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final boxTextFg =
        isDark ? const Color(0xFFAAAAAA) : const Color(0xFF000000);
    final attentionFg =
        isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);
    final cancelFg =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final checkColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    return Dialog(
      backgroundColor: boxBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_boxRadius),
      ),
      elevation: 4,
      child: SizedBox(
        width: _boxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _boxPadding,
              child: Text(
                _bodyText,
                style: TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  color: boxTextFg,
                ),
              ),
            ),

            if (widget.showModeratePanel) ...[
              SizedBox(height: _boxMediumSkip),
              _buildCheckbox('Ban User', _banUser, (v) {
                setState(() => _banUser = v ?? false);
              }, checkColor, boxTextFg),
              SizedBox(height: _boxLittleSkip),
              _buildCheckbox('Report Spam', _reportSpam, (v) {
                setState(() => _reportSpam = v ?? false);
              }, checkColor, boxTextFg),
              SizedBox(height: _boxLittleSkip),
              _buildCheckbox(
                'Delete All from ${widget.peerName}',
                _deleteAll,
                (v) => setState(() => _deleteAll = v ?? false),
                checkColor,
                boxTextFg,
              ),
            ],

            if (_revokeLabel != null) ...[
              SizedBox(height: _boxMediumSkip),
              _buildCheckbox(_revokeLabel!, _revoke, (v) {
                setState(() => _revoke = v ?? false);
              }, checkColor, boxTextFg),
            ],

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(const DeleteConfirmResult()),
                    style: TextButton.styleFrom(
                      foregroundColor: cancelFg,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      DeleteConfirmResult(
                        confirmed: true,
                        revoke: _revoke,
                        banUser: _banUser,
                        reportSpam: _reportSpam,
                        deleteAll: _deleteAll,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: attentionFg,
                      overlayColor: attentionFg.withOpacity(0.1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: Text(_confirmLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckbox(
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
