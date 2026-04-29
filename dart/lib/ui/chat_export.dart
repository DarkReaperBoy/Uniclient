import 'package:flutter/material.dart';

const double _exportPanelWidth = 364;
const double _exportPanelHeight = 480;
const double _boxRadius = 8;
const double _titleBarHeight = 48;

enum ExportMode { full, perChat, perTopic }

enum ExportPhase { settings, processing, completed, error }

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

  String get settingsTitle {
    switch (mode) {
      case ExportMode.full:
        return 'Export Your Data';
      case ExportMode.perChat:
        return 'Export Chat History';
      case ExportMode.perTopic:
        return 'Export Topic History';
    }
  }

  String get panelTitle => settingsTitle;
}

void showExportPanel(BuildContext context, ExportTarget target) {
  showDialog(
    context: context,
    barrierDismissible: false,
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

class _ExportPanelDialog extends StatefulWidget {
  final ExportTarget target;

  const _ExportPanelDialog({required this.target});

  @override
  State<_ExportPanelDialog> createState() => _ExportPanelDialogState();
}

class _ExportPanelDialogState extends State<_ExportPanelDialog>
    with WidgetsBindingObserver {
  ExportPhase _phase = ExportPhase.settings;

  String get _title {
    switch (_phase) {
      case ExportPhase.processing:
        return 'Exporting Data...';
      case ExportPhase.completed:
      case ExportPhase.error:
        return widget.target.settingsTitle;
      case ExportPhase.settings:
        return widget.target.settingsTitle;
    }
  }

  bool get _hideOnDeactivate => _phase == ExportPhase.processing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_hideOnDeactivate && state == AppLifecycleState.inactive) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleClose() async {
    if (_phase == ExportPhase.processing) {
      final confirmed = await _showStopConfirmation();
      if (confirmed && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _showStopConfirmation() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final boxTextFg =
        isDark ? const Color(0xFFAAAAAA) : const Color(0xFF000000);
    final attentionFg =
        isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);
    final cancelFg =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: boxBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
        elevation: 4,
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
                child: Text(
                  'Are you sure you want to stop exporting your data?',
                  style: TextStyle(
                    fontSize: 14,
                    height: 22 / 14,
                    color: boxTextFg,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
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
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: attentionFg,
                        overlayColor: attentionFg.withValues(alpha: 0.1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  @visibleForTesting
  void setPhase(ExportPhase phase) {
    setState(() => _phase = phase);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final borderColor =
        isDark ? const Color(0xFF0E1621) : const Color(0xFFE0E0E0);

    return PopScope(
      canPop: _phase != ExportPhase.processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleClose();
      },
      child: Center(
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_boxRadius),
              child: Column(
                children: [
                  _buildTitleBar(
                      titleColor, subtextColor, borderColor),
                  Expanded(
                    child: _buildContent(subtextColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(
      Color titleColor, Color subtextColor, Color borderColor) {
    return Container(
      height: _titleBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: subtextColor),
            onPressed: _handleClose,
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Color subtextColor) {
    switch (_phase) {
      case ExportPhase.settings:
        return _buildSettingsPlaceholder(subtextColor);
      case ExportPhase.processing:
        return _buildProcessingPlaceholder(subtextColor);
      case ExportPhase.completed:
        return _buildCompletedPlaceholder(subtextColor);
      case ExportPhase.error:
        return _buildErrorPlaceholder(subtextColor);
    }
  }

  Widget _buildSettingsPlaceholder(Color subtextColor) {
    return Center(
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
            widget.target.mode == ExportMode.full
                ? 'Export settings will appear here.'
                : 'Chat export settings will appear here.',
            style: TextStyle(fontSize: 14, color: subtextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingPlaceholder(Color subtextColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: subtextColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Please wait, export is in progress.',
            style: TextStyle(fontSize: 14, color: subtextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedPlaceholder(Color subtextColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: accentColor),
          const SizedBox(height: 16),
          Text(
            'Your data was successfully exported.',
            style: TextStyle(fontSize: 14, color: subtextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder(Color subtextColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorColor =
        isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: errorColor),
          const SizedBox(height: 16),
          Text(
            'Export failed.',
            style: TextStyle(fontSize: 14, color: errorColor),
            textAlign: TextAlign.center,
          ),
        ],
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
