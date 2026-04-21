import 'package:flutter/material.dart';

/// Calls History screen (§34). Opened from hamburger drawer "Calls" row.
/// Shows call history list with direction indicators, redial buttons,
/// and a "Create Call" action at top.
/// Empty state: "Your recent calls will appear here."
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final menuIconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

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
          // §34.2: Three-dot menu with "Call Settings" and "Clear All".
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: menuIconColor),
            color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF),
            onSelected: (value) {
              // No-op for now — call settings and clear all require engine support.
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
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // §34.12: Create Call button.
          _CreateCallButton(
            accentColor: accentColor,
            textColor: textColor,
            subtextColor: subtextColor,
            dividerColor: dividerColor,
            isDark: isDark,
          ),
          Divider(height: 1, color: dividerColor),
          // §34.4: Call history list — empty state.
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

/// §34.12: "Create Call" button styled as inviteViaLinkButton.
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
            onTap: () {
              // Conference call creation — requires engine support.
            },
            child: Container(
              color: _hovered ? hoverBg : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Floating icon circle.
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
        // Description text below button.
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
