import 'package:flutter/material.dart';

const double _exportPanelWidth = 364;
const double _exportPanelHeight = 480;
const double _boxRadius = 8;
const double _titleBarHeight = 48;

enum ExportMode { full, perChat, perTopic }

class ExportTarget {
  final ExportMode mode;
  final String? accountId;
  final String? chatId;
  final String? chatTitle;
  final int? topicRootId;
  final String? topicTitle;

  const ExportTarget({
    required this.mode,
    this.accountId,
    this.chatId,
    this.chatTitle,
    this.topicRootId,
    this.topicTitle,
  });

  String get panelTitle {
    switch (mode) {
      case ExportMode.full:
        return 'Export Your Data';
      case ExportMode.perChat:
        return 'Export Chat History';
      case ExportMode.perTopic:
        return 'Export Topic History';
    }
  }
}

void showExportPanel(BuildContext context, ExportTarget target) {
  showDialog(
    context: context,
    builder: (ctx) => _ExportPanelDialog(target: target),
  );
}

void showExportSuggestBox(BuildContext context, {VoidCallback? onStart}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExportSuggestBox(onStart: onStart),
  );
}

class _ExportPanelDialog extends StatelessWidget {
  final ExportTarget target;

  const _ExportPanelDialog({required this.target});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _exportPanelWidth,
          height: _exportPanelHeight,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(_boxRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                height: _titleBarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? const Color(0xFF0E1621)
                          : const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        target.panelTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: subtextColor),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_upload_outlined,
                        size: 64,
                        color: subtextColor.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        target.mode == ExportMode.full
                            ? 'Export settings will appear here.'
                            : 'Chat export settings will appear here.',
                        style: TextStyle(
                          fontSize: 14,
                          color: subtextColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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

class _ExportSuggestBox extends StatelessWidget {
  final VoidCallback? onStart;

  const _ExportSuggestBox({this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final textColor = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF555555);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export Your Data',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You can export your data from Telegram, including chats, '
                'messages, and media. The export will be processed by '
                'Telegram servers and may take some time.',
                style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onStart?.call();
                    },
                    child: Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
