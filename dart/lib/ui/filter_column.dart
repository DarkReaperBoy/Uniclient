import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/chat_state.dart';

/// Spec §1/§2: Vertical folder sidebar, 72px wide.
/// Hamburger menu icon at top, vertical folder buttons (scrollable),
/// "All Chats" default tab, unread badges per folder.
class FilterColumn extends StatelessWidget {
  final VoidCallback? onOpenDrawer;

  const FilterColumn({super.key, this.onOpenDrawer});

  static const width = 72.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = context.watch<ChatState>();
    final folders = chatState.folders;
    final activeFolderId = chatState.activeFolderId;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Hamburger menu button at top.
          const SizedBox(height: 8),
          IconButton(
            icon: const Icon(Icons.menu, size: 22),
            onPressed: onOpenDrawer,
            tooltip: 'Menu',
          ),
          const SizedBox(height: 8),
          // "All Chats" tab (shows all chats for this account, no folder filter).
          _FolderTab(
            icon: Icons.chat,
            label: 'All',
            isActive: activeFolderId == null,
            unreadCount: 0, // no badge on "All" — it's the default
            onTap: () => chatState.setActiveFolder(null),
          ),
          const SizedBox(height: 4),
          // Folder tabs (scrollable).
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: folders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final folder = folders[index];
                final unread = chatState.unreadCountForFolder(folder.id);
                return _FolderTab(
                  icon: _folderIcon(folder.name),
                  label: _shortenLabel(folder.name),
                  isActive: activeFolderId == folder.id,
                  unreadCount: unread,
                  onTap: () => chatState.setActiveFolder(
                    activeFolderId == folder.id ? null : folder.id,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Pick an icon based on folder name keywords.
  static IconData _folderIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('unread')) return Icons.mark_email_unread;
    if (lower.contains('personal')) return Icons.person;
    if (lower.contains('group')) return Icons.group;
    if (lower.contains('channel')) return Icons.campaign;
    if (lower.contains('bot')) return Icons.smart_toy;
    if (lower.contains('work')) return Icons.work;
    return Icons.folder;
  }

  /// Shorten folder name to fit 72px width (max ~8 chars).
  static String _shortenLabel(String name) {
    if (name.length <= 8) return name;
    return '${name.substring(0, 7)}...';
  }
}

/// Single folder tab button in the sidebar.
class _FolderTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final int unreadCount;
  final VoidCallback onTap;

  const _FolderTab({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: isActive
              ? BoxDecoration(
                  color: activeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: isActive ? activeColor : inactiveColor,
                  ),
                  // Unread badge.
                  if (unreadCount > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                        child: Text(
                          unreadCount > 999 ? '999+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? activeColor : inactiveColor,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
