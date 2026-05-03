import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ayu_filter.dart';
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

    if (appState.filterEngine.hasPerDialogFilters()) {
      b.addSkip();
      b.addSectionDivider();
      b.addSkip();
      b.addSectionTitle('Per-Dialog Filters');
      final dialogIds = appState.filterEngine.dialogIdsWithFilters();
      for (final dId in dialogIds) {
        final filters = appState.filterEngine.filtersForDialog(dId);
        final exclCount = appState.filterEngine.exclusionsForDialog(dId).length;
        final status = StringBuffer();
        if (filters.isNotEmpty) status.write('${filters.length} filter${filters.length > 1 ? "s" : ""}');
        if (exclCount > 0) {
          if (status.isNotEmpty) status.write(', ');
          status.write('$exclCount excluded');
        }
        b.addWidget(_NavigationButton(
          label: dId.length > 18 ? '${dId.substring(0, 17)}…' : dId,
          subtitle: status.toString(),
          isDark: isDark,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: appState,
              child: _AyuFiltersListScreen(
                mode: _FiltersListMode.perDialog,
                dialogTitle: dId,
                dialogId: dId,
              ),
            ),
          )),
        ));
      }
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
              appState.filterEngine.clearAll();
              for (final id in appState.shadowBanIds.toList()) {
                appState.removeShadowBan(id);
              }
              appState.saveFilterEngine();
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
  final String? subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _NavigationButton({
    required this.label,
    this.subtitle,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF6D7F8F)
                                  : const Color(0xFF999999))),
                    ),
                ],
              ),
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
  final bool showExclude;

  const _AyuFiltersListScreen({
    required this.mode,
    this.dialogTitle,
    this.dialogId,
    this.showExclude = true,
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
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);

    final List<Widget> children;

    if (mode == _FiltersListMode.shadowBan) {
      children = _buildShadowBanContent(appState, isDark, subtitleColor, accentColor);
    } else if (mode == _FiltersListMode.perDialog && !showExclude) {
      children = _buildPickExcludeContent(appState, isDark, subtitleColor, accentColor, context);
    } else {
      children = _buildFilterListContent(appState, isDark, subtitleColor, accentColor, context);
    }

    return ayuSettingsScaffold(
      context: context,
      title: _title,
      children: children,
    );
  }

  List<Widget> _buildShadowBanContent(
      AppState appState, bool isDark, Color subtitleColor, Color accentColor) {
    if (appState.shadowBanIds.isEmpty) {
      return [_emptyState(isDark, subtitleColor, 'No shadow-banned peers.')];
    }
    return [
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
        child: Text('Filters',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: accentColor)),
      ),
      ...appState.shadowBanIds.map((id) => _ShadowBanRow(
            id: id,
            isDark: isDark,
            onDelete: () => appState.removeShadowBan(id),
          )),
      const SizedBox(height: 8),
    ];
  }

  List<Widget> _buildFilterListContent(
      AppState appState, bool isDark, Color subtitleColor, Color accentColor, BuildContext context) {
    final engine = appState.filterEngine;
    final List<RegexFilter> filters;
    final List<RegexFilter> exclusionFilters;

    if (mode == _FiltersListMode.shared) {
      filters = engine.sharedFilters;
      exclusionFilters = [];
    } else {
      filters = engine.filtersForDialog(dialogId!);
      final exclIds = engine.exclusionsForDialog(dialogId!);
      exclusionFilters = engine.sharedFilters
          .where((f) => exclIds.contains(f.id))
          .toList();
    }

    if (filters.isEmpty && exclusionFilters.isEmpty) {
      return [_emptyState(isDark, subtitleColor, 'No filters.')];
    }

    final List<Widget> children = [];

    if (filters.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
        child: Text('Filters',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: accentColor)),
      ));
      for (final f in filters) {
        children.add(_FilterRow(
          filter: f,
          isDark: isDark,
          onEdit: () => _showRegexEditBox(context, appState, f),
          onToggleEnabled: () {
            engine.updateFilter(f.copyWith(enabled: !f.enabled));
            appState.saveFilterEngine();
          },
          onDelete: () {
            engine.deleteFilter(f.id);
            appState.saveFilterEngine();
          },
        ));
      }
    }

    if (exclusionFilters.isNotEmpty) {
      if (filters.isNotEmpty) {
        children.add(_sectionDivider(isDark));
      }
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
        child: Text('Excluded',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: accentColor)),
      ));
      for (final f in exclusionFilters) {
        children.add(_ExclusionRow(
          filter: f,
          isDark: isDark,
          onDelete: () {
            engine.deleteExclusion(dialogId!, f.id);
            appState.saveFilterEngine();
          },
        ));
      }
    }

    if (mode == _FiltersListMode.perDialog) {
      children.add(const SizedBox(height: 12));
      children.add(_sectionDivider(isDark));
      children.add(const SizedBox(height: 4));
      children.add(_AddExclusionButton(
        isDark: isDark,
        onTap: () => _navigateToPickExclude(context, appState),
      ));
    }

    children.add(const SizedBox(height: 8));
    return children;
  }

  List<Widget> _buildPickExcludeContent(
      AppState appState, bool isDark, Color subtitleColor, Color accentColor, BuildContext context) {
    final engine = appState.filterEngine;
    final exclIds = engine.exclusionsForDialog(dialogId!);
    final available = engine.sharedFilters
        .where((f) => !exclIds.contains(f.id))
        .toList();

    if (available.isEmpty) {
      return [_emptyState(isDark, subtitleColor, 'No shared filters available to exclude.')];
    }

    final List<Widget> children = [const SizedBox(height: 8)];
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Text('Tap to exclude a shared filter',
          style: TextStyle(fontSize: 13, color: subtitleColor)),
    ));
    for (final f in available) {
      children.add(_PickExcludeRow(
        filter: f,
        isDark: isDark,
        onTap: () {
          engine.addExclusion(RegexFilterExclusion(
            dialogId: dialogId!,
            filterId: f.id,
          ));
          appState.saveFilterEngine();
          Navigator.of(context).pop();
        },
      ));
    }
    children.add(const SizedBox(height: 8));
    return children;
  }

  Widget _emptyState(bool isDark, Color subtitleColor, String text) {
    return Column(children: [
      const SizedBox(height: 7),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        color: isDark ? const Color(0xFF101921) : const Color(0xFFF0F0F0),
        child: Text(text,
            style: TextStyle(fontSize: 13, color: subtitleColor),
            textAlign: TextAlign.center),
      ),
    ]);
  }

  Widget _sectionDivider(bool isDark) {
    return Container(
      height: 1,
      color: isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0),
    );
  }

  void _showRegexEditBox(BuildContext context, AppState appState, RegexFilter? existing) {
    showDialog(
      context: context,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: appState,
        child: _RegexEditBox(
          filter: existing,
          dialogId: mode == _FiltersListMode.perDialog ? dialogId : null,
        ),
      ),
    );
  }

  void _navigateToPickExclude(BuildContext context, AppState appState) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: appState,
        child: _AyuFiltersListScreen(
          mode: _FiltersListMode.perDialog,
          dialogTitle: dialogTitle,
          dialogId: dialogId,
          showExclude: false,
        ),
      ),
    ));
  }
}

class _FilterRow extends StatelessWidget {
  final RegexFilter filter;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onToggleEnabled;
  final VoidCallback onDelete;

  const _FilterRow({
    required this.filter,
    required this.isDark,
    required this.onEdit,
    required this.onToggleEnabled,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = filter.enabled
        ? (isDark ? Colors.white : Colors.black87)
        : (isDark ? const Color(0xFF5A6A78) : const Color(0xFF999999));

    return InkWell(
      onTap: () => _showPopup(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        child: Text(
          filter.text.replaceAll('\n', ' '),
          style: TextStyle(fontSize: 14, color: labelColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _showPopup(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    final pos = RelativeRect.fromLTRB(
      offset.dx + box.size.width,
      offset.dy,
      offset.dx + box.size.width,
      offset.dy + box.size.height,
    );
    final iconColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    showMenu<String>(
      context: context,
      position: pos,
      color: isDark ? const Color(0xFF1B2836) : Colors.white,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Text('Edit', style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
          ]),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(children: [
            Icon(filter.enabled ? Icons.block : Icons.check_circle_outline,
                size: 20, color: iconColor),
            const SizedBox(width: 12),
            Text(filter.enabled ? 'Disable' : 'Enable',
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Text('Delete', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      ],
    ).then((v) {
      if (v == 'edit') onEdit();
      if (v == 'toggle') onToggleEnabled();
      if (v == 'delete') onDelete();
    });
  }
}

class _ExclusionRow extends StatelessWidget {
  final RegexFilter filter;
  final bool isDark;
  final VoidCallback onDelete;

  const _ExclusionRow({
    required this.filter,
    required this.isDark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showPopup(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        child: Text(
          filter.text.replaceAll('\n', ' '),
          style: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFF5A6A78) : const Color(0xFF999999),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _showPopup(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    final pos = RelativeRect.fromLTRB(
      offset.dx + box.size.width,
      offset.dy,
      offset.dx + box.size.width,
      offset.dy + box.size.height,
    );
    showMenu<String>(
      context: context,
      position: pos,
      color: isDark ? const Color(0xFF1B2836) : Colors.white,
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Text('Delete', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      ],
    ).then((v) {
      if (v == 'delete') onDelete();
    });
  }
}

class _PickExcludeRow extends StatelessWidget {
  final RegexFilter filter;
  final bool isDark;
  final VoidCallback onTap;

  const _PickExcludeRow({
    required this.filter,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        child: Text(
          filter.text.replaceAll('\n', ' '),
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _AddExclusionButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _AddExclusionButton({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(children: [
          Icon(Icons.add, size: 20, color: accentColor),
          const SizedBox(width: 12),
          Text('Exclude a shared filter',
              style: TextStyle(fontSize: 14, color: accentColor)),
        ]),
      ),
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
              child: Row(children: [
                Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 12),
                Text('Delete', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.error)),
              ]),
            ),
          ],
        ).then((v) {
          if (v == 'delete') onDelete();
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: _avatarColor(id),
            child: const Text('U',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('User $id',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87)),
                Text('ID: $id',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999))),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  RelativeRect _getMenuPosition(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    return RelativeRect.fromLTRB(
        offset.dx + box.size.width, offset.dy,
        offset.dx + box.size.width, offset.dy + box.size.height);
  }

  static const _colors = [
    Color(0xFFC03D33), Color(0xFF4FAD2D), Color(0xFFD09306),
    Color(0xFF168ACD), Color(0xFF8544D6), Color(0xFFCD4073), Color(0xFF2996AD),
  ];

  Color _avatarColor(int id) => _colors[id.abs() % 7];
}

class _RegexEditBox extends StatefulWidget {
  final RegexFilter? filter;
  final String? dialogId;

  const _RegexEditBox({this.filter, this.dialogId});

  @override
  State<_RegexEditBox> createState() => _RegexEditBoxState();
}

class _RegexEditBoxState extends State<_RegexEditBox> {
  late TextEditingController _textController;
  late bool _enabled;
  late bool _caseInsensitive;
  late bool _reversed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.filter?.text ?? '');
    _enabled = widget.filter?.enabled ?? true;
    _caseInsensitive = widget.filter?.caseInsensitive ?? false;
    _reversed = widget.filter?.reversed ?? false;
    _textController.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String? _validateRegex(String pattern) {
    if (pattern.isEmpty) return null;
    try {
      RegExp(pattern, caseSensitive: !_caseInsensitive);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  String _generateUuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _save() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final err = _validateRegex(text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }

    final appState = context.read<AppState>();
    final engine = appState.filterEngine;
    final filter = RegexFilter(
      id: widget.filter?.id ?? _generateUuidV4(),
      text: text,
      enabled: _enabled,
      caseInsensitive: _caseInsensitive,
      reversed: _reversed,
      dialogId: widget.dialogId ?? widget.filter?.dialogId,
    );

    if (widget.filter != null) {
      engine.updateFilter(filter);
    } else {
      engine.addFilter(filter);
    }
    appState.saveFilterEngine();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final title = widget.filter != null ? 'Edit Filter' : 'Add Filter';

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1B2836) : Colors.white,
      title: Text(title,
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87)),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              autofocus: true,
              maxLines: null,
              style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Regular expression',
                hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: isDark ? const Color(0xFF3A4A5A) : const Color(0xFFCBCBCB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accentColor),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            _CheckboxRow(
              label: 'Enable',
              value: _enabled,
              isDark: isDark,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            _CheckboxRow(
              label: 'Case-insensitive',
              value: _caseInsensitive,
              isDark: isDark,
              onChanged: (v) => setState(() => _caseInsensitive = v),
            ),
            _CheckboxRow(
              label: 'Reversed',
              value: _reversed,
              isDark: isDark,
              onChanged: (v) => setState(() => _reversed = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: accentColor)),
        ),
        TextButton(
          onPressed: _save,
          child: Text('Save', style: TextStyle(color: accentColor)),
        ),
      ],
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  final String label;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _CheckboxRow({
    required this.label,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC),
              side: BorderSide(
                color: isDark ? const Color(0xFF5A6A78) : const Color(0xFFCBCBCB),
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
        ]),
      ),
    );
  }
}
