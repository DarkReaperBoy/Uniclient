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
  final _focusNode = FocusNode();
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
    _controller.addListener(() {
      if (_showError && _controller.text.trim().isNotEmpty) {
        setState(() => _showError = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isEmpty) {
      _focusNode.requestFocus();
      setState(() => _showError = true);
    } else {
      _save();
    }
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
      onConfirm: _submit,
      content: Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          style: TextStyle(fontSize: 14, color: textFg),
          decoration: InputDecoration(
            hintText: widget.title,
            hintStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                color: _showError ? const Color(0xFFe53935) : Colors.grey,
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: _showError ? const Color(0xFFe53935) : const Color(0xFF40a7e3),
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Reset',
          isLeft: true,
          onPressed: () {
            _controller.text = widget.defaultValue;
          },
        ),
        TelegramBoxButton(
          text: 'Save',
          onPressed: _submit,
        ),
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
