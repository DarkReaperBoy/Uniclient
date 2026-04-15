import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../models/engine_models.dart';
import '../screens/auth_screen.dart';
import '../theme/theme.dart';
import '../utils/debug.dart';

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
class PlatformRail extends StatefulWidget {
  const PlatformRail({super.key});

  @override
  State<PlatformRail> createState() => _PlatformRailState();
}

class _PlatformRailState extends State<PlatformRail> {
  /// Local display order — kept in sync with AppState.platforms.
  List<String> _orderedPlatforms = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final statePlatforms = context.read<AppState>().platforms;
    // Merge: preserve existing order, append new platforms, drop removed ones.
    final current = _orderedPlatforms.where(statePlatforms.contains).toList();
    final added = statePlatforms.where((p) => !current.contains(p)).toList();
    _orderedPlatforms = [...current, ...added];
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _orderedPlatforms.removeAt(oldIndex);
      _orderedPlatforms.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep _orderedPlatforms in sync when AppState changes.
    final appState = context.watch<AppState>();
    final chatState = context.watch<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Sync without setState (we're already in build).
    final statePlatforms = appState.platforms;
    final current = _orderedPlatforms.where(statePlatforms.contains).toList();
    final added = statePlatforms.where((p) => !current.contains(p)).toList();
    if (added.isNotEmpty || current.length != _orderedPlatforms.length) {
      _orderedPlatforms = [...current, ...added];
    }

    final railBg = isDark ? AppColors.darkRail : AppColors.lightRail;
    final dividerColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      width: AppSizes.railWidth,
      color: railBg,
      child: Column(
        children: [
          // Top padding + "All" button + divider — fixed, never reordered.
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _RailIcon(
              icon: Icons.all_inclusive_rounded,
              color: AppColors.accent,
              label: 'All',
              isActive: appState.activePlatform.isEmpty,
              unreadCount: chatState.totalUnread,
              onTap: () => appState.setActivePlatform(''),
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: dividerColor,
          ),

          // Reorderable platform icons.
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _orderedPlatforms.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final elevation = animation.value * 8.0;
                    return Material(
                      elevation: elevation,
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final platform = _orderedPlatforms[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(platform),
                  index: index,
                  child: _RailIcon(
                    icon: _platformMeta[platform]?.icon ?? Icons.extension_rounded,
                    color: _platformMeta[platform]?.color ?? AppColors.accent,
                    label: _platformMeta[platform]?.label ?? platform,
                    isActive: appState.activePlatform == platform,
                    connState: _bestConnState(appState, platform),
                    unreadCount: chatState.chatsForPlatform(platform).fold(0, (sum, c) => sum + c.unreadCount),
                    onTap: () => appState.setActivePlatform(platform),
                    onSecondaryTapUp: (details) =>
                        _showPlatformContextMenu(context, platform, details.globalPosition),
                  ),
                );
              },
            ),
          ),

          // Divider + "Add" button — fixed at the bottom.
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: dividerColor,
          ),
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

  Future<void> _showPlatformContextMenu(
    BuildContext context,
    String platform,
    Offset position,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;

    final appState = context.read<AppState>();
    final needsAuth = _bestConnState(appState, platform) == ConnState.authRequired;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        if (needsAuth)
          PopupMenuItem<String>(
            value: 'reauth',
            child: Row(
              children: [
                Icon(Icons.lock_open, color: AppColors.warning, size: 18),
                const SizedBox(width: 10),
                Text('Re-authenticate', style: TextStyle(color: AppColors.warning)),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'reconnect',
          child: Row(
            children: [
              Icon(Icons.refresh, color: textColor, size: 18),
              const SizedBox(width: 10),
              Text('Reconnect', style: TextStyle(color: textColor)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'disconnect',
          child: Row(
            children: [
              Icon(Icons.power_settings_new,
                  color: AppColors.danger, size: 18),
              const SizedBox(width: 10),
              Text('Disconnect',
                  style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings, color: textColor, size: 18),
              const SizedBox(width: 10),
              Text('Settings', style: TextStyle(color: textColor)),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted || result == null) return;

    final engine = context.read<EngineService>();
    final label = _platformMeta[platform]?.label ?? platform;
    final accounts = appState.accountsForPlatform(platform);

    switch (result) {
      case 'reauth':
        // Open auth dialog for the first account needing re-auth.
        final acc = accounts.firstWhere(
          (a) => appState.connStateFor(a.id) == ConnState.authRequired,
          orElse: () => accounts.first,
        );
        if (context.mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (_) => AuthScreen(accountId: acc.id, platform: acc.platform),
          ).then((_) {
            if (context.mounted) {
              context.read<ChatState>().loadChats();
            }
          });
        }
      case 'reconnect':
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Reconnecting $label...')));
        for (final acc in accounts) {
          engine.connectAccount(acc.id).catchError((e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Reconnect failed: $e')),
              );
            }
          });
        }
      case 'disconnect':
        for (final acc in accounts) {
          engine.disconnectAccount(acc.id).catchError((e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Disconnect failed: $e')),
              );
            }
          });
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text('Disconnected $label')));
        }
      case 'settings':
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(content: Text('Platform settings coming soon')));
        }
    }
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
    for (final a in accounts) {
      if (appState.connStateFor(a.id) == ConnState.authRequired) return ConnState.authRequired;
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
                Debug.log('UI', 'Add platform: ${entry.key}');
                Navigator.pop(ctx);
                try {
                  final appState = context.read<AppState>();
                  final id = appState.addAccount(entry.key);
                  Debug.log('UI', 'Opening auth dialog for $id (${entry.key})');
                  showDialog<void>(
                    context: context,
                    barrierDismissible: true,
                    builder: (_) => AuthScreen(accountId: id, platform: entry.key),
                  ).then((_) {
                    Debug.log('UI', 'Auth dialog closed for ${entry.key}');
                    if (context.mounted) {
                      appState.setActivePlatform(entry.key);
                      // Load chats after auth completes.
                      context.read<ChatState>().loadChats();
                    }
                  });
                } catch (e, stack) {
                  Debug.error('UI', 'Add platform failed', e, stack);
                }
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
  final void Function(TapUpDetails)? onSecondaryTapUp;

  const _RailIcon({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.isActive,
    this.connState = ConnState.connected,
    this.unreadCount = 0,
    required this.onTap,
    this.onSecondaryTapUp,
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
              onSecondaryTapUp: widget.onSecondaryTapUp,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Icon container with hover/active animation
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
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
                            ConnState.authRequired => AppColors.warning,
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
