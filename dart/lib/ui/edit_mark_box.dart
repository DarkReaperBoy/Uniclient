import 'package:flutter/material.dart';

import '../theme/telegram_palette.dart';
import 'confirm_box.dart';

Future<void> showEditMarkBox(
  BuildContext context, {
  required String title,
  required String currentValue,
  required String defaultValue,
  required ValueChanged<String> onSave,
}) {
  return showTelegramBox<void>(
    context: context,
    builder: (ctx) => _EditMarkBoxContent(
      title: title,
      currentValue: currentValue,
      defaultValue: defaultValue,
      onSave: onSave,
    ),
  );
}

class _EditMarkBoxContent extends StatefulWidget {
  final String title;
  final String currentValue;
  final String defaultValue;
  final ValueChanged<String> onSave;

  const _EditMarkBoxContent({
    required this.title,
    required this.currentValue,
    required this.defaultValue,
    required this.onSave,
  });

  @override
  State<_EditMarkBoxContent> createState() => _EditMarkBoxContentState();
}

class _EditMarkBoxContentState extends State<_EditMarkBoxContent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_controller.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;

    return TelegramBox(
      title: widget.title,
      onConfirm: _save,
      content: Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
        child: TextField(
          controller: _controller,
          autofocus: true,
          style: TextStyle(fontSize: 14, color: textFg),
          decoration: InputDecoration(
            hintText: widget.defaultValue.isEmpty ? 'edited' : widget.defaultValue,
            border: const UnderlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Reset',
          isLeft: true,
          onPressed: () {
            widget.onSave(widget.defaultValue);
            Navigator.of(context).pop();
          },
        ),
        TelegramBoxButton(
          text: 'Save',
          onPressed: _save,
        ),
      ],
    );
  }
}
