import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../data/ayu_filter.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
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
      final chatState = context.read<ChatState>();
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
        final dialogName = _resolveDialogName(chatState, dId);
        b.addWidget(_NavigationButton(
          label: dialogName,
          subtitle: status.toString(),
          isDark: isDark,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: appState,
              child: _AyuFiltersListScreen(
                mode: _FiltersListMode.perDialog,
                dialogTitle: dialogName,
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

  static String _resolveDialogName(ChatState chatState, String dialogId) {
    for (final chat in chatState.chats) {
      if (chat.chatId == dialogId) {
        final name = chat.title;
        return name.length > 18 ? '${name.substring(0, 17)}…' : name;
      }
    }
    return 'Filters ($dialogId)';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => _SelectChatDialog(
        chatState: chatState,
        appState: appState,
        isDark: isDark,
        parentContext: context,
      ),
    );
  }

  void _showImportDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: appState,
        child: const _ImportFiltersBox(isImport: true),
      ),
    );
  }

  void _showExportDialog(BuildContext context, AppState appState) {
    if (!appState.filterEngine.hasFilters()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No filters to export')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: appState,
        child: const _ImportFiltersBox(isImport: false),
      ),
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

class _SelectChatDialog extends StatefulWidget {
  final ChatState chatState;
  final AppState appState;
  final bool isDark;
  final BuildContext parentContext;
  final void Function(ChatInfo)? onChatSelected;

  const _SelectChatDialog({
    required this.chatState,
    required this.appState,
    required this.isDark,
    required this.parentContext,
    this.onChatSelected,
  });

  @override
  State<_SelectChatDialog> createState() => _SelectChatDialogState();
}

class _SelectChatDialogState extends State<_SelectChatDialog> {
  final _searchController = TextEditingController();
  List<ChatInfo> _results = [];
  bool _hasQuery = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _results = widget.chatState.chats;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = widget.chatState.chats;
        _hasQuery = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _hasQuery = true;
      _loading = true;
    });

    final engineResults = await widget.chatState.searchChats(query);
    if (!mounted) return;
    final lower = query.toLowerCase();
    final localResults = widget.chatState.chats
        .where((c) =>
            c.title.toLowerCase().contains(lower) ||
            c.chatId.contains(lower))
        .toList();

    final mergedIds = <String>{};
    final merged = <ChatInfo>[];
    for (final c in engineResults) {
      if (mergedIds.add(c.chatId)) merged.add(c);
    }
    for (final c in localResults) {
      if (mergedIds.add(c.chatId)) merged.add(c);
    }

    setState(() {
      _results = merged;
      _loading = false;
    });

    if (query.startsWith('@') && query.length > 1) {
      final username = query.substring(1);
      final engine = context.read<EngineService>();
      final accountId = widget.appState.activeAccountId;
      if (accountId.isNotEmpty) {
        engine.resolveUsername(accountId, username).then((chatId) {
          if (!mounted || _searchController.text.trim() != query) return;
          if (chatId != null && chatId.isNotEmpty && !mergedIds.contains(chatId)) {
            final resolved = ChatInfo(
              chatId: chatId,
              title: '@$username',
              accountId: accountId,
            );
            setState(() {
              _results = [resolved, ..._results];
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor =
        widget.isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    return AlertDialog(
      backgroundColor: widget.isDark ? const Color(0xFF1B2836) : Colors.white,
      title: Text('Select Chat',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: widget.isDark ? Colors.white : Colors.black87)),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 300,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(
                  fontSize: 14,
                  color: widget.isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: TextStyle(
                    color: widget.isDark
                        ? const Color(0xFF6D7F8F)
                        : const Color(0xFF999999)),
                prefixIcon: Icon(Icons.search,
                    size: 20,
                    color: widget.isDark
                        ? const Color(0xFF6D7F8F)
                        : const Color(0xFF999999)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: widget.isDark
                          ? const Color(0xFF3A4A5A)
                          : const Color(0xFFCBCBCB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accentColor),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                          _hasQuery ? 'No chats found' : 'No chats loaded',
                          style: TextStyle(
                              fontSize: 13,
                              color: widget.isDark
                                  ? const Color(0xFF6D7F8F)
                                  : const Color(0xFF999999))))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final chat = _results[i];
                        return ListTile(
                          title: Text(chat.title,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: widget.isDark
                                      ? Colors.white
                                      : Colors.black87)),
                          subtitle: Text(chat.chatId,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: widget.isDark
                                      ? const Color(0xFF6D7F8F)
                                      : const Color(0xFF999999))),
                          onTap: () {
                            Navigator.of(context).pop();
                            if (widget.onChatSelected != null) {
                              widget.onChatSelected!(chat);
                            } else {
                              Navigator.of(widget.parentContext)
                                  .push(MaterialPageRoute(
                                builder: (_) => ChangeNotifierProvider.value(
                                  value: widget.appState,
                                  child: _AyuFiltersListScreen(
                                    mode: _FiltersListMode.perDialog,
                                    dialogTitle: chat.title,
                                    dialogId: chat.chatId,
                                  ),
                                ),
                              ));
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: accentColor)),
        ),
      ],
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
    context.select<AppState, List<RegexFilter>>((s) => s.filterEngine.filters);
    context.select<AppState, List<RegexFilterExclusion>>((s) => s.filterEngine.exclusions);
    context.select<AppState, Set<int>>((s) => s.shadowBanIds);
    final appState = context.read<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);

    final items = <Widget Function()>[];

    if (mode == _FiltersListMode.shadowBan) {
      _buildShadowBanItems(items, appState, isDark, subtitleColor, accentColor);
    } else if (mode == _FiltersListMode.perDialog && !showExclude) {
      _buildPickExcludeItems(items, appState, isDark, subtitleColor, accentColor, context);
    } else {
      _buildFilterListItems(items, appState, isDark, subtitleColor, accentColor, context);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: Text(_title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (mode == _FiltersListMode.shadowBan)
            IconButton(
              icon: Icon(Icons.add,
                  color: isDark ? Colors.white : Colors.black87),
              onPressed: () => _showAddShadowBanDialog(context, appState),
            )
          else if (mode != _FiltersListMode.perDialog || showExclude)
            IconButton(
              icon: Icon(Icons.add,
                  color: isDark ? Colors.white : Colors.black87),
              onPressed: () => _showRegexEditBox(context, appState, null),
            ),
        ],
      ),
      body: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        itemBuilder: (ctx, index) => items[index](),
      ),
    );
  }

  void _buildShadowBanItems(List<Widget Function()> items,
      AppState appState, bool isDark, Color subtitleColor, Color accentColor) {
    if (appState.shadowBanIds.isEmpty) {
      items.add(() => _emptyState(isDark, subtitleColor, 'No shadow-banned peers.'));
      return;
    }
    items.add(() => const SizedBox(height: 8));
    items.add(() => Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Text('Filters',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: accentColor)),
    ));
    for (final id in appState.shadowBanIds) {
      items.add(() => _ShadowBanRow(
            id: id,
            isDark: isDark,
            onDelete: () => appState.removeShadowBan(id),
          ));
    }
    items.add(() => const SizedBox(height: 8));
  }

  void _buildFilterListItems(List<Widget Function()> items,
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
      items.add(() => _emptyState(isDark, subtitleColor, 'No filters.'));
      return;
    }

    if (filters.isNotEmpty) {
      items.add(() => const SizedBox(height: 8));
      items.add(() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
        child: Text('Filters',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: accentColor)),
      ));
      for (final f in filters) {
        items.add(() => _FilterRow(
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
        items.add(() => _sectionDivider(isDark));
      }
      items.add(() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
        child: Text('Excluded',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: accentColor)),
      ));
      for (final f in exclusionFilters) {
        items.add(() => _ExclusionRow(
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
      items.add(() => const SizedBox(height: 12));
      items.add(() => _sectionDivider(isDark));
      items.add(() => const SizedBox(height: 4));
      items.add(() => _AddExclusionButton(
        isDark: isDark,
        onTap: () => _navigateToPickExclude(context, appState),
      ));
    }

    items.add(() => const SizedBox(height: 8));
  }

  void _buildPickExcludeItems(List<Widget Function()> items,
      AppState appState, bool isDark, Color subtitleColor, Color accentColor, BuildContext context) {
    final engine = appState.filterEngine;
    final exclIds = engine.exclusionsForDialog(dialogId!);
    final available = engine.sharedFilters
        .where((f) => !exclIds.contains(f.id))
        .toList();

    if (available.isEmpty) {
      items.add(() => _emptyState(isDark, subtitleColor, 'No shared filters available to exclude.'));
      return;
    }

    items.add(() => const SizedBox(height: 8));
    items.add(() => Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Text('Tap to exclude a shared filter',
          style: TextStyle(fontSize: 13, color: subtitleColor)),
    ));
    for (final f in available) {
      items.add(() => _PickExcludeRow(
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
    items.add(() => const SizedBox(height: 8));
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

  void _showAddShadowBanDialog(BuildContext context, AppState appState) {
    final chatState = context.read<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => _SelectChatDialog(
        chatState: chatState,
        appState: appState,
        isDark: isDark,
        parentContext: context,
        onChatSelected: (chat) {
          final id = int.tryParse(chat.chatId);
          if (id != null) {
            appState.addShadowBan(id);
          }
        },
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

class _ShadowBanRow extends StatefulWidget {
  final int id;
  final bool isDark;
  final VoidCallback onDelete;

  const _ShadowBanRow({
    required this.id,
    required this.isDark,
    required this.onDelete,
  });

  @override
  State<_ShadowBanRow> createState() => _ShadowBanRowState();
}

class _ShadowBanRowState extends State<_ShadowBanRow> {
  String? _resolvedName;
  String? _avatarPath;
  bool _avatarExists = false;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _resolvePeerInfo();
  }

  void _resolvePeerInfo() {
    final chatState = context.read<ChatState>();
    final idStr = widget.id.toString();
    for (final chat in chatState.chats) {
      final chatIdAbs = chat.chatId.replaceFirst(RegExp(r'^-100'), '').replaceFirst('-', '');
      if (chat.chatId == idStr || chatIdAbs == idStr) {
        if (mounted) {
          setState(() {
            _resolvedName = chat.title;
            _attempted = true;
          });
          if (chat.avatarPath.isNotEmpty) {
            _updateAvatarExists(chat.avatarPath);
          }
        }
        return;
      }
    }
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isNotEmpty) {
      engine.getUserProfile(accountId, idStr).then((profile) {
        if (!mounted) return;
        setState(() {
          _resolvedName = profile?.displayName;
          _attempted = true;
        });
        engine.downloadSingleAvatar(accountId, idStr).then((path) {
          if (mounted && path != null && path.isNotEmpty) {
            _updateAvatarExists(path);
          }
        });
      });
    } else {
      if (mounted) setState(() => _attempted = true);
    }
  }

  Future<void> _updateAvatarExists(String path) async {
    final exists = await File(path).exists();
    if (mounted) {
      setState(() {
        _avatarPath = path;
        _avatarExists = exists;
      });
    }
  }

  String get _displayName {
    if (_resolvedName != null && _resolvedName!.isNotEmpty) return _resolvedName!;
    return 'UNKNOWN (ID: ${widget.id})';
  }

  String get _avatarLetter {
    if (_resolvedName != null && _resolvedName!.isNotEmpty) {
      return _resolvedName![0].toUpperCase();
    }
    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final pos = _getMenuPosition(context);
        showMenu<String>(
          context: context,
          position: pos,
          color: widget.isDark ? const Color(0xFF1B2836) : Colors.white,
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
          if (v == 'delete') widget.onDelete();
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: context.palette.peerUserpicBg(_colorRemap[widget.id.abs() % 7]),
            backgroundImage: _avatarExists
                ? FileImage(File(_avatarPath!))
                : null,
            child: _avatarExists
                ? null
                : Text(_avatarLetter,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_displayName,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: widget.isDark ? Colors.white : Colors.black87)),
                Text('ID: ${widget.id}',
                    style: TextStyle(
                        fontSize: 12,
                        color: widget.isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999))),
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

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
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
  String? _warning;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.filter?.text ?? '');
    _enabled = widget.filter?.enabled ?? true;
    _caseInsensitive = widget.filter?.caseInsensitive ?? true;
    _reversed = widget.filter?.reversed ?? false;
    _textController.addListener(() {
      if (_error != null || _warning != null) {
        setState(() { _error = null; _warning = null; });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  static final _icuOnlyPatterns = RegExp(
    r'\\[pP]\{|\\[pP][A-Z]|\\[QEGKk]|\[\[:');

  String? _validateRegex(String pattern) {
    if (pattern.isEmpty) return null;
    try {
      RegExp(pattern, caseSensitive: !_caseInsensitive);
      if (_icuOnlyPatterns.hasMatch(pattern)) {
        _warning = 'Uses ICU-specific syntax — may behave differently in AyuGram Desktop';
      }
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

    _warning = null;
    final err = _validateRegex(text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_warning != null) {
      setState(() {});
    }

    final appState = context.read<AppState>();
    final engine = appState.filterEngine;
    final isNew = widget.filter == null;
    final filterId = widget.filter?.id ?? _generateUuidV4();
    final filter = RegexFilter(
      id: filterId,
      text: text,
      enabled: _enabled,
      caseInsensitive: _caseInsensitive,
      reversed: _reversed,
      dialogId: widget.filter?.dialogId,
    );

    if (!isNew) {
      engine.updateFilter(filter);
    } else {
      engine.addFilter(filter);
    }
    appState.saveFilterEngine();

    final dialogId = widget.dialogId;
    if (isNew && dialogId != null && filter.isShared) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: const Text('Filter added. Tap to restrict to this dialog.'),
        action: SnackBarAction(
          label: 'Restrict',
          onPressed: () {
            final updated = filter.copyWith(dialogId: dialogId);
            engine.updateFilter(updated);
            appState.saveFilterEngine();
          },
        ),
      ));
    } else {
      Navigator.of(context).pop();
    }
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
                  : _warning != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_warning!,
                              style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
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

class _ImportFiltersBox extends StatefulWidget {
  final bool isImport;

  const _ImportFiltersBox({required this.isImport});

  @override
  State<_ImportFiltersBox> createState() => _ImportFiltersBoxState();
}

class _ImportFiltersBoxState extends State<_ImportFiltersBox> {
  bool _useUrl = false;
  late TextEditingController _urlController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    if (widget.isImport) {
      _prefillFromClipboard();
    }
  }

  Future<void> _prefillFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.startsWith('http')) {
      _urlController.text = data.text!;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _performAction() async {
    if (_loading) return;
    setState(() => _loading = true);

    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      if (widget.isImport) {
        await _doImport(appState, messenger);
      } else {
        await _doExport(appState, messenger);
      }
    } finally {
      if (mounted) nav.pop();
    }
  }

  Future<void> _doImport(AppState appState, ScaffoldMessengerState messenger) async {
    String jsonText;

    if (_useUrl) {
      final url = _urlController.text.trim();
      if (url.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to fetch filters')),
        );
        return;
      }
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        jsonText = await response.transform(utf8.decoder).join();
        client.close();
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to fetch filters')),
        );
        return;
      }
    } else {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      jsonText = data?.text ?? '';
    }

    if (jsonText.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to import filters')),
      );
      return;
    }

    try {
      final parsed = jsonDecode(jsonText);
      if (parsed is! Map<String, dynamic>) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to import filters')),
        );
        return;
      }

      final engine = appState.filterEngine;
      final ImportChanges changes;
      try {
        changes = engine.previewImport(parsed);
      } on Exception catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
        return;
      }

      final peersRaw = parsed['peers'];
      final peerHints = <String, String>{};
      if (peersRaw is Map<String, dynamic>) {
        for (final entry in peersRaw.entries) {
          final username = entry.value?.toString() ?? '';
          if (username.isNotEmpty) {
            peerHints[entry.key] = username;
          }
        }
      }

      final chatState = context.read<ChatState>();
      final peersToResolve = <String, String>{};
      for (final entry in peerHints.entries) {
        bool loaded = false;
        for (final chat in chatState.chats) {
          if (chat.chatId == entry.key) {
            loaded = true;
            break;
          }
        }
        if (!loaded) {
          peersToResolve[entry.key] = entry.value;
        }
      }

      if (!changes.hasChanges && peersToResolve.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No changes')),
        );
        return;
      }

      if (!mounted) return;
      final confirmed = await _showImportConfirmation(
        newFilters: changes.addedCount,
        updatedFilters: changes.updatedCount,
        removedFilters: changes.removedFiltersCount,
        newExclusions: changes.newExclusionsCount,
        removedExclusions: changes.removedExclusionsCount,
        dialogsToResolve: peersToResolve.length,
      );
      if (confirmed != true) return;

      engine.applyImport(changes);
      appState.saveFilterEngine();

      if (peersToResolve.isNotEmpty) {
        final engineSvc = context.read<EngineService>();
        final accountId = appState.activeAccountId;
        if (accountId.isNotEmpty) {
          for (final entry in peersToResolve.entries) {
            try {
              await engineSvc.resolveUsername(accountId, entry.value);
            } catch (_) {}
          }
        }
      }

      final total = changes.addedCount + changes.updatedCount;
      messenger.showSnackBar(
        SnackBar(content: Text('Imported $total filter${total != 1 ? "s" : ""}'
            '${changes.removedFiltersCount > 0 ? ', removed ${changes.removedFiltersCount}' : ''}'
            '${peersToResolve.isNotEmpty ? ', resolved ${peersToResolve.length} dialog${peersToResolve.length != 1 ? "s" : ""}' : ''}')),
      );
    } on FormatException {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to import filters')),
      );
    } on TypeError {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to import filters')),
      );
    }
  }

  Future<bool?> _showImportConfirmation({
    required int newFilters,
    required int updatedFilters,
    required int removedFilters,
    required int newExclusions,
    required int removedExclusions,
    int dialogsToResolve = 0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    final lines = <String>[];
    if (newFilters > 0) lines.add('$newFilters new filter${newFilters != 1 ? "s" : ""}');
    if (updatedFilters > 0) lines.add('$updatedFilters updated filter${updatedFilters != 1 ? "s" : ""}');
    if (removedFilters > 0) lines.add('$removedFilters removed filter${removedFilters != 1 ? "s" : ""}');
    if (newExclusions > 0) lines.add('$newExclusions new exclusion${newExclusions != 1 ? "s" : ""}');
    if (removedExclusions > 0) lines.add('$removedExclusions removed exclusion${removedExclusions != 1 ? "s" : ""}');
    if (dialogsToResolve > 0) lines.add('$dialogsToResolve dialog${dialogsToResolve != 1 ? "s" : ""} to be resolved');

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B2836) : Colors.white,
        title: Text('Import filters',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The following changes will be applied:',
                style: TextStyle(fontSize: 14, color: subtitleColor)),
            const SizedBox(height: 12),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text('•  ', style: TextStyle(fontSize: 14, color: textColor)),
                    Expanded(child: Text(line,
                        style: TextStyle(fontSize: 14, color: textColor))),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: accentColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Import', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _doExport(AppState appState, ScaffoldMessengerState messenger) async {
    final engine = appState.filterEngine;
    final peers = await _resolvePeerUsernames(appState, engine);

    if (_useUrl) {
      final result = await engine.publishFilters(peers: peers);
      if (result.error != null) {
        messenger.showSnackBar(SnackBar(content: Text(result.error!)));
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Link copied to clipboard')),
        );
      }
    } else {
      final exportData = engine.exportFilters(peers: peers);
      final jsonText = const JsonEncoder.withIndent('  ').convert(exportData);
      await Clipboard.setData(ClipboardData(text: jsonText));
      messenger.showSnackBar(
        const SnackBar(content: Text('Copied to clipboard')),
      );
    }
  }

  Future<Map<String, String>> _resolvePeerUsernames(
      AppState appState, AyuFilterEngine engine) async {
    final dialogIds = <String>{};
    for (final f in engine.filters) {
      if (f.dialogId != null && f.dialogId!.isNotEmpty) {
        dialogIds.add(f.dialogId!);
      }
    }
    final peers = <String, String>{};
    if (dialogIds.isEmpty) return peers;

    final chatState = context.read<ChatState>();
    final engineSvc = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    for (final dId in dialogIds) {
      String? username;
      for (final chat in chatState.chats) {
        if (chat.chatId == dId) {
          if (accountId.isNotEmpty) {
            try {
              final profile = await engineSvc.getUserProfile(accountId, dId);
              if (profile != null && profile.username.isNotEmpty) {
                username = profile.username;
              }
            } catch (_) {}
          }
          break;
        }
      }
      if (username != null && username.isNotEmpty) {
        peers[dId] = username;
      }
    }
    return peers;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    final title = widget.isImport ? 'Import filters' : 'Export filters';

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1B2836) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 20,
                        color: isDark
                            ? const Color(0xFF6D7F8F)
                            : const Color(0xFF999999)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RadioRow(
                    label: 'Clipboard',
                    selected: !_useUrl,
                    isDark: isDark,
                    accentColor: accentColor,
                    onTap: () => setState(() => _useUrl = false),
                  ),
                  _RadioRow(
                    label: 'URL',
                    selected: _useUrl,
                    isDark: isDark,
                    accentColor: accentColor,
                    onTap: () => setState(() => _useUrl = true),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.topCenter,
                    child: (_useUrl && widget.isImport)
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: TextField(
                              controller: _urlController,
                              style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      isDark ? Colors.white : Colors.black87),
                              decoration: InputDecoration(
                                labelText: 'URL',
                                labelStyle: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? const Color(0xFF6D7F8F)
                                        : const Color(0xFF999999)),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: isDark
                                          ? const Color(0xFF3A4A5A)
                                          : const Color(0xFFCBCBCB)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: accentColor),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 14),
                              ),
                              onSubmitted: (_) => _performAction(),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: SizedBox(
                height: 42,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _loading ? null : _performAction,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(widget.isImport ? 'Import' : 'Export',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;

  const _RadioRow({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87)),
        ]),
      ),
    );
  }
}
