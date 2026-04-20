import 'package:flutter/material.dart';

/// Telegram Desktop spec-compliant ConfirmBox (§36.2).
///
/// Dimensions: boxWidth=320, boxPadding=EdgeInsets(24,14,24,8),
/// boxRadius=3, boxBg=white/#17212b, boxLabel=22px lineHeight.
/// Destructive actions use attentionBoxButton (red confirm text).

const double _boxWidth = 320;
const EdgeInsets _boxPadding = EdgeInsets.fromLTRB(24, 14, 24, 8);
const double _boxRadius = 3;
const double _boxTitleHeight = 48;

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
