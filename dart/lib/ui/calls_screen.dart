import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  bool _hasCallHistory = false;

  void _showClearCallHistoryDialog() {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    bool revoke = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text(
                'Clear Call History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete all call history?',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: revoke,
                          onChanged: (v) => setDialogState(() => revoke = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => revoke = !revoke),
                          child: Text(
                            'Also delete for other participants',
                            style: TextStyle(fontSize: 14, color: textColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await engine.clearCallHistory(accountId, revoke: revoke);
                      if (mounted) {
                        setState(() => _hasCallHistory = false);
                      }
                    } catch (_) {}
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: isDark ? const Color(0xFFe85050) : const Color(0xFFdd4b39),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final menuIconColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final attentionColor = isDark ? const Color(0xFFe85050) : const Color(0xFFdd4b39);

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
          'Calls',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: menuIconColor),
            color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF),
            onSelected: (value) {
              switch (value) {
                case 'clear_all':
                  _showClearCallHistoryDialog();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20, color: menuIconColor),
                    const SizedBox(width: 12),
                    Text(
                      'Call Settings',
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ],
                ),
              ),
              if (_hasCallHistory)
                PopupMenuItem<String>(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: attentionColor),
                      const SizedBox(width: 12),
                      Text(
                        'Clear All',
                        style: TextStyle(fontSize: 14, color: attentionColor),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _CreateCallButton(
            accentColor: accentColor,
            textColor: textColor,
            subtextColor: subtextColor,
            dividerColor: dividerColor,
            isDark: isDark,
          ),
          Divider(height: 1, color: dividerColor),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Your recent calls will appear here.',
                  style: TextStyle(
                    fontSize: 14,
                    color: subtextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateCallButton extends StatefulWidget {
  final Color accentColor;
  final Color textColor;
  final Color subtextColor;
  final Color dividerColor;
  final bool isDark;

  const _CreateCallButton({
    required this.accentColor,
    required this.textColor,
    required this.subtextColor,
    required this.dividerColor,
    required this.isDark,
  });

  @override
  State<_CreateCallButton> createState() => _CreateCallButtonState();
}

class _CreateCallButtonState extends State<_CreateCallButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg = widget.isDark
        ? const Color(0xFF202B36)
        : const Color(0xFFF1F1F1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () {},
            child: Container(
              color: _hovered ? hoverBg : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: widget.accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_call,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Create Call',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'You can create a group call for up to 200 participants.',
            style: TextStyle(
              fontSize: 13,
              color: widget.subtextColor,
            ),
          ),
        ),
      ],
    );
  }
}
