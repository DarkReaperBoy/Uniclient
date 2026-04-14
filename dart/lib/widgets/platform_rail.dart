import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/engine_models.dart';
import '../theme/theme.dart';

/// Platform icons and their brand colors.
const _platformMeta = <String, ({IconData icon, Color color, String label})>{
  'telegram':  (icon: Icons.send_rounded,           color: Color(0xFF2AABEE), label: 'Telegram'),
  'bale':      (icon: Icons.chat_rounded,            color: Color(0xFF00B862), label: 'Bale'),
  'matrix':    (icon: Icons.grid_view_rounded,       color: Color(0xFF0DBD8B), label: 'Matrix'),
  'irc':       (icon: Icons.terminal_rounded,        color: Color(0xFF8B5CF6), label: 'IRC'),
  'xmpp':      (icon: Icons.hub_rounded,             color: Color(0xFFF97316), label: 'XMPP'),
  'github':    (icon: Icons.code_rounded,            color: Color(0xFFE0E0E0), label: 'GitHub'),
  'rubika':    (icon: Icons.diamond_rounded,         color: Color(0xFFE91E63), label: 'Rubika'),
  'deltachat': (icon: Icons.mail_rounded,            color: Color(0xFF338BFF), label: 'Delta Chat'),
  'teamspeak': (icon: Icons.headset_rounded,         color: Color(0xFF2580C3), label: 'TeamSpeak'),
  'mumble':    (icon: Icons.mic_rounded,             color: Color(0xFF7C7C7C), label: 'Mumble'),
};

/// Vertical platform rail — left edge of the app.
class PlatformRail extends StatelessWidget {
  const PlatformRail({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: AppSizes.railWidth,
      color: isDark ? AppColors.darkRail : AppColors.lightRail,
      child: Column(
        children: [
          const SizedBox(height: 8),

          // "All" button — shows unified chat list
          _RailIcon(
            icon: Icons.all_inclusive_rounded,
            color: AppColors.accent,
            label: 'All',
            isActive: appState.activePlatform.isEmpty,
            onTap: () => appState.setActivePlatform(''),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),

          // Platform icons
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final platform in appState.platforms)
                  _RailIcon(
                    icon: _platformMeta[platform]?.icon ?? Icons.extension_rounded,
                    color: _platformMeta[platform]?.color ?? AppColors.accent,
                    label: _platformMeta[platform]?.label ?? platform,
                    isActive: appState.activePlatform == platform,
                    connState: _bestConnState(appState, platform),
                    unreadCount: appState.unreadForPlatform(platform),
                    onTap: () => appState.setActivePlatform(platform),
                  ),
              ],
            ),
          ),

          // Add platform button
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RailIcon(
              icon: Icons.add_rounded,
              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
              label: 'Add',
              isActive: false,
              onTap: () => _showAddPlatformDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  ConnState _bestConnState(AppState appState, String platform) {
    final accounts = appState.accountsForPlatform(platform);
    if (accounts.isEmpty) return ConnState.disconnected;
    // If any account is connected, show connected.
    for (final a in accounts) {
      if (appState.connStateFor(a.id) == ConnState.connected) return ConnState.connected;
    }
    for (final a in accounts) {
      if (appState.connStateFor(a.id) == ConnState.connecting) return ConnState.connecting;
    }
    return ConnState.disconnected;
  }

  void _showAddPlatformDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add Platform'),
        children: [
          for (final entry in _platformMeta.entries)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<AppState>().addAccount(entry.key);
              },
              child: Row(
                children: [
                  Icon(entry.value.icon, color: entry.value.color, size: 24),
                  const SizedBox(width: 12),
                  Text(entry.value.label),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Single icon in the platform rail.
class _RailIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool isActive;
  final ConnState connState;
  final int unreadCount;
  final VoidCallback onTap;

  const _RailIcon({
    required this.icon,
    required this.color,
    required this.label,
    required this.isActive,
    this.connState = ConnState.connected,
    this.unreadCount = 0,
    required this.onTap,
  });

  @override
  State<_RailIcon> createState() => _RailIconState();
}

class _RailIconState extends State<_RailIcon> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: widget.label,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 500),
        child: Center(
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Icon container with hover/active animation
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: AppSizes.railIconSize,
                    height: AppSizes.railIconSize,
                    decoration: BoxDecoration(
                      color: widget.isActive
                          ? widget.color.withAlpha(40)
                          : _hovering
                              ? (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        widget.isActive || _hovering ? 14 : 24,
                      ),
                      border: widget.isActive
                          ? Border.all(color: widget.color.withAlpha(100), width: 2)
                          : null,
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 22),
                  ),

                  // Connection status dot
                  if (widget.connState != ConnState.connected && widget.label != 'All' && widget.label != 'Add')
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: switch (widget.connState) {
                            ConnState.connecting => AppColors.warning,
                            ConnState.unstable => AppColors.warning,
                            _ => AppColors.danger,
                          },
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? AppColors.darkRail : AppColors.lightRail,
                            width: 2,
                          ),
                        ),
                      ),
                    ),

                  // Unread badge
                  if (widget.unreadCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 18),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
