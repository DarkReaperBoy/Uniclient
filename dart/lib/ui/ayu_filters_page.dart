import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'ayu_section_builder.dart';

class AyuFiltersPage extends StatelessWidget {
  const AyuFiltersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip(8);
    b.addSectionTitle('Regex Filters');
    b.addSettingToggle(
      label: 'Enable Regex Filters',
      value: appState.filtersEnabled,
      onChanged: (v) => appState.setFiltersEnabled(v),
    );
    b.addSettingToggle(
      label: 'Enable Shared in Chats',
      subtitle:
          'Apply shared filters in groups and DMs, not just channels',
      value: appState.filtersEnabledInChats,
      onChanged: (v) => appState.setFiltersEnabledInChats(v),
    );
    b.addSettingToggle(
      label: 'Hide from Blocked',
      subtitle: 'Automatically hide messages from blocked users',
      value: appState.hideFromBlocked,
      onChanged: (v) => appState.setHideFromBlocked(v),
    );

    b.addSkip();
    b.addSectionDivider();
    b.addSkip();

    b.addWidget(_NavigationButton(
      label: 'Shared Filters',
      isDark: isDark,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: appState,
          child: const _AyuFiltersListScreen(mode: _FiltersListMode.shared),
        ),
      )),
    ));
    b.addWidget(_NavigationButton(
      label: 'Shadow Ban',
      isDark: isDark,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: appState,
          child:
              const _AyuFiltersListScreen(mode: _FiltersListMode.shadowBan),
        ),
      )),
    ));

    if (appState.shadowBanIds.isNotEmpty) {
      b.addSkip();
      b.addSectionDivider();
      b.addSkip();
      b.addSectionTitle('Per-Dialog Filters');
      b.addDescription(
          '${appState.shadowBanIds.length} shadow-banned peers');
    }

    return ayuSettingsScaffold(
      context: context,
      title: 'Filters',
      actions: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert,
              color: isDark ? Colors.white : Colors.black87),
          color: isDark ? const Color(0xFF1B2836) : Colors.white,
          onSelected: (v) => _onMenuAction(context, appState, v),
          itemBuilder: (_) => [
            _menuItem('select_chat', Icons.search, 'Select Chat', isDark),
            const PopupMenuDivider(),
            _menuItem(
                'import', Icons.archive_outlined, 'Import', isDark),
            _menuItem('export', Icons.unarchive_outlined, 'Export',
                isDark),
            const PopupMenuDivider(),
            _menuItem(
                'clear_all', Icons.clear_all, 'Clear All', isDark),
          ],
        ),
      ],
      children: b.build(),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, bool isDark) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999)),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  void _onMenuAction(
      BuildContext context, AppState appState, String action) {
    switch (action) {
      case 'select_chat':
        _showSelectChatDialog(context, appState);
      case 'import':
        _showImportDialog(context, appState);
      case 'export':
        _showExportDialog(context, appState);
      case 'clear_all':
        _showClearAllDialog(context, appState);
    }
  }

  void _showSelectChatDialog(BuildContext context, AppState appState) {
    final chatState = context.read<ChatState>();
    final chats = chatState.chats;
    if (chats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No chats loaded')),
      );
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B2836) : Colors.white,
        title: Text('Select Chat',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.builder(
            itemCount: chats.length,
            itemBuilder: (_, i) {
              final chat = chats[i];
              return ListTile(
                title: Text(chat.title,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87)),
                subtitle: Text(chat.chatId,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF6D7F8F)
                            : const Color(0xFF999999))),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: appState,
                      child: _AyuFiltersListScreen(
                        mode: _FiltersListMode.perDialog,
                        dialogTitle: chat.title,
                        dialogId: chat.chatId,
                      ),
                    ),
                  ));
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: isDark
                    ? const Color(0xFF6AB2F2)
                    : const Color(0xFF3390EC))),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B2836) : Colors.white,
        title: Text('Import Filters',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
        content: TextField(
          controller: controller,
          maxLines: 6,
          style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Paste JSON here...',
            hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xFF6D7F8F)
                    : const Color(0xFF999999)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: isDark
                    ? const Color(0xFF6AB2F2)
                    : const Color(0xFF3390EC))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Filter import will be available '
                        'when the filter engine is implemented')),
              );
            },
            child: Text('Import',
                style: TextStyle(color: isDark
                    ? const Color(0xFF6AB2F2)
                    : const Color(0xFF3390EC))),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context, AppState appState) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No filters to export')),
    );
  }

  void _showClearAllDialog(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B2836) : Colors.white,
        title: Text('Clear All Filters',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
        content: Text(
            'Are you sure you want to delete all filters and exclusions?',
            style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: isDark
                    ? const Color(0xFF6AB2F2)
                    : const Color(0xFF3390EC))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              for (final id in appState.shadowBanIds.toList()) {
                appState.removeShadowBan(id);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All filters cleared')),
              );
            },
            child: Text('Clear',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _NavigationButton extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _NavigationButton({
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark
                    ? const Color(0xFF6D7F8F)
                    : const Color(0xFF999999)),
          ],
        ),
      ),
    );
  }
}

enum _FiltersListMode { shared, shadowBan, perDialog }

class _AyuFiltersListScreen extends StatelessWidget {
  final _FiltersListMode mode;
  final String? dialogTitle;
  final String? dialogId;

  const _AyuFiltersListScreen({
    required this.mode,
    this.dialogTitle,
    this.dialogId,
  });

  String get _title {
    switch (mode) {
      case _FiltersListMode.shared:
        return 'Shared filters';
      case _FiltersListMode.shadowBan:
        return 'Shadow ban';
      case _FiltersListMode.perDialog:
        final t = dialogTitle ?? 'Dialog';
        return t.length > 18 ? '${t.substring(0, 17)}…' : t;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    final List<Widget> children;

    if (mode == _FiltersListMode.shadowBan &&
        appState.shadowBanIds.isNotEmpty) {
      children = [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
          child: Text('Filters',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? const Color(0xFF6AB2F2)
                      : const Color(0xFF3390EC))),
        ),
        ...appState.shadowBanIds.map((id) => _ShadowBanRow(
              id: id,
              isDark: isDark,
              onDelete: () => appState.removeShadowBan(id),
            )),
        const SizedBox(height: 8),
      ];
    } else {
      children = [
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          color: isDark ? const Color(0xFF101921) : const Color(0xFFF0F0F0),
          child: Text(
            mode == _FiltersListMode.shadowBan
                ? 'No shadow-banned peers.'
                : 'No filters.',
            style: TextStyle(fontSize: 13, color: subtitleColor),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }

    return ayuSettingsScaffold(
      context: context,
      title: _title,
      children: children,
    );
  }
}

class _ShadowBanRow extends StatelessWidget {
  final int id;
  final bool isDark;
  final VoidCallback onDelete;

  const _ShadowBanRow({
    required this.id,
    required this.isDark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final pos = _getMenuPosition(context);
        showMenu<String>(
          context: context,
          position: pos,
          color: isDark ? const Color(0xFF1B2836) : Colors.white,
          items: [
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 12),
                  Text('Delete',
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.error)),
                ],
              ),
            ),
          ],
        ).then((v) {
          if (v == 'delete') onDelete();
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: _avatarColor(id),
              child: Text(
                'U',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('User $id',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87)),
                  Text('ID: $id',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF6D7F8F)
                              : const Color(0xFF999999))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  RelativeRect _getMenuPosition(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    return RelativeRect.fromLTRB(
        offset.dx + box.size.width,
        offset.dy,
        offset.dx + box.size.width,
        offset.dy + box.size.height);
  }

  static const _colors = [
    Color(0xFFC03D33),
    Color(0xFF4FAD2D),
    Color(0xFFD09306),
    Color(0xFF168ACD),
    Color(0xFF8544D6),
    Color(0xFFCD4073),
    Color(0xFF2996AD),
  ];

  Color _avatarColor(int id) => _colors[id.abs() % 7];
}
