import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../models/engine_models.dart';
import '../screens/auth_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/theme.dart';
import '../utils/debug.dart';
import '../utils/safe_string.dart';

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

/// Sidebar — chat list with search, folders, drill-in, and chat items.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  bool _searching = false;
  List<ChatInfo>? _searchResults;

  // Folder filter state
  String _activeFolder = 'all';

  // Custom user-created folders: name + set of chatIds
  final List<({String name, Set<String> chatIds})> _customFolders = [];

  // Drill-in state: when non-null, we show the sub-chat list for this parent.
  ChatInfo? _drillInChat;
  List<ChatInfo>? _drillInTopics; // fetched forum topics for the drill-in parent
  bool _drillInLoading = false;

  // Slide animation for drill-in
  late final AnimationController _slideController;
  late final Animation<Offset> _slideInOffset;
  late final Animation<Offset> _slideOutOffset;
  bool _showDrillIn = false;

  // Reorder state for pinned chats
  List<ChatInfo>? _pinnedOrder;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideInOffset = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _slideOutOffset = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.3, 0),
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _enterDrillIn(ChatInfo parent) {
    setState(() {
      _drillInChat = parent;
      _drillInTopics = null;
      _drillInLoading = true;
      _showDrillIn = true;
    });
    _slideController.forward(from: 0);
    _fetchForumTopics(parent);
  }

  Future<void> _fetchForumTopics(ChatInfo parent) async {
    final engine = context.read<EngineService>();
    final chatState = context.read<ChatState>();
    try {
      final topics = await engine.getForumTopics(parent.accountId, parent.chatId);
      if (!mounted || _drillInChat?.chatId != parent.chatId) return;
      // Also merge into chat state so they appear in the main chat list.
      if (topics.isNotEmpty) {
        for (final t in topics) {
          chatState.mergeChat(t);
        }
        chatState.notifyMerged();
      }
      setState(() {
        // Only use fetched topics if non-empty; otherwise fall back to
        // parentId-based sub-chat filtering in the build method.
        _drillInTopics = topics.isNotEmpty ? topics : null;
        _drillInLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _drillInTopics = null; // fall back to parentId filter
        _drillInLoading = false;
      });
    }
  }

  void _exitDrillIn() {
    _slideController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showDrillIn = false;
          _drillInChat = null;
          _drillInTopics = null;
          _drillInLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = context.watch<ChatState>();
    final appState = context.watch<AppState>();

    // Feature 1: Platform filtering
    final platformFilter = appState.activePlatform;
    final allChats = platformFilter.isNotEmpty
        ? chatState.chatsForPlatform(platformFilter)
        : chatState.chats;

    // Folder filtering
    final folderFiltered = _applyFolderFilter(allChats);

    final chats = _searchResults ?? folderFiltered;

    // Exclude sub-chats from top level (chats with a parentId belong inside their parent)
    final topLevelChats = chats.where((c) => c.parentId.isEmpty).toList();

    // Sort: pinned first, then by lastMsgTime descending
    final pinned = topLevelChats.where((c) => c.isPinned && !c.isArchived).toList()
      ..sort((a, b) => b.lastMsgTime.compareTo(a.lastMsgTime));
    final regular = topLevelChats.where((c) => !c.isPinned && !c.isArchived).toList()
      ..sort((a, b) => b.lastMsgTime.compareTo(a.lastMsgTime));

    // Apply custom pinned order if user reordered
    final displayPinned = _applyPinnedOrder(pinned);

    // Total unread count for the header badge
    final totalUnread = allChats
        .where((c) => !c.isArchived)
        .fold<int>(0, (sum, c) => sum + c.unreadCount);

    return Container(
      color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
      child: Column(
        children: [
          // Header with platform dropdown
          _PlatformHeader(
            platformFilter: platformFilter,
            totalUnread: totalUnread,
          ),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searching
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: _clearSearch,
                        splashRadius: 14,
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),

          const SizedBox(height: 4),

          // Folder tabs
          _FolderTabs(
            activeFolder: _activeFolder,
            customFolders: _customFolders,
            onFolderChanged: (folder) {
              setState(() {
                _activeFolder = folder;
                // Reset drill-in when changing folder
                if (_showDrillIn) _exitDrillIn();
              });
            },
            onAddFolder: _showCreateFolderDialog,
          ),

          // Chat list area with drill-in animation
          Expanded(
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Main chat list (slides left when drilling in)
                  if (!_showDrillIn || _slideController.isAnimating)
                    SlideTransition(
                      position: _slideOutOffset,
                      child: _buildMainChatList(
                        isDark: isDark,
                        pinned: displayPinned,
                        regular: regular,
                        chats: topLevelChats,
                        allChats: allChats,
                      ),
                    ),
                  // Drill-in page (slides in from right)
                  if (_showDrillIn)
                    SlideTransition(
                      position: _slideInOffset,
                      child: _buildDrillInPage(
                        isDark: isDark,
                        allChats: allChats,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // User panel (bottom)
          const _UserPanel(),
        ],
      ),
    );
  }

  Widget _buildMainChatList({
    required bool isDark,
    required List<ChatInfo> pinned,
    required List<ChatInfo> regular,
    required List<ChatInfo> chats,
    required List<ChatInfo> allChats,
  }) {
    final customFolders = _customFolders;
    // Check if there are sub-chats for any group (to show drill-in arrow)
    bool hasSubChats(ChatInfo chat) {
      return allChats.any((c) => c.parentId == chat.chatId);
    }

    if (pinned.isEmpty && regular.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _searching ? 'No results' : 'No chats yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                ),
              ),
              if (!_searching) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _showJoinChannelDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Join Channel'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Pinned section with reorderable list
        if (pinned.isNotEmpty) ...[
          _SectionHeader(title: 'Pinned', count: pinned.length),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: pinned.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final reordered = List<ChatInfo>.from(pinned);
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                _pinnedOrder = reordered;
              });
            },
            proxyDecorator: (child, index, animation) {
              return Material(
                elevation: 4,
                color: Colors.transparent,
                shadowColor: Colors.black45,
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final chat = pinned[index];
              return _ReorderableChatItem(
                key: ValueKey('${chat.accountId}_${chat.chatId}'),
                chat: chat,
                index: index,
                showDrillArrow: hasSubChats(chat),
                onDrillIn: () => _enterDrillIn(chat),
                customFolders: customFolders,
                onAddToFolder: _addChatToFolder,
              );
            },
          ),
        ],
        // Regular section
        if (regular.isNotEmpty) ...[
          if (pinned.isNotEmpty)
            _SectionHeader(title: 'Messages', count: regular.length),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: regular.length,
              itemBuilder: (context, index) {
                final chat = regular[index];
                return _ChatItem(
                  chat: chat,
                  showDrillArrow: hasSubChats(chat),
                  onDrillIn: () => _enterDrillIn(chat),
                  customFolders: customFolders,
                  onAddToFolder: _addChatToFolder,
                );
              },
            ),
          ),
        ] else
          const Spacer(),
      ],
    );
  }

  Widget _buildDrillInPage({
    required bool isDark,
    required List<ChatInfo> allChats,
  }) {
    final parent = _drillInChat;
    if (parent == null) return const SizedBox.shrink();

    // Use fetched topics if available, otherwise fall back to cached sub-chats.
    final subChats = (_drillInTopics ?? allChats.where((c) => c.parentId == parent.chatId).toList())
      ..sort((a, b) => a.title.compareTo(b.title));

    // Separate text and voice channels
    final textChannels = subChats.where((c) => c.type != ChatType.topic || !_looksLikeVoice(c)).toList();
    final voiceChannels = subChats.where((c) => _looksLikeVoice(c)).toList();

    final hue = (parent.chatId.hashCode % 360).abs().toDouble();
    final bgColor = HSLColor.fromAHSL(1, hue, 0.5, isDark ? 0.3 : 0.75).toColor();

    return Container(
      color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
      child: Column(
        children: [
          // Back button + group header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _exitDrillIn,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back, size: 20),
                    const SizedBox(width: 8),
                    // Group avatar
                    Container(
                      width: AppSizes.avatarSizeSmall,
                      height: AppSizes.avatarSizeSmall,
                      decoration: BoxDecoration(
                        color: bgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          safeInitial(parent.title),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            parent.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkText : AppColors.lightText,
                            ),
                          ),
                          if (parent.memberCount > 0)
                            Text(
                              '${parent.memberCount} members',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          // Sub-chats list
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (textChannels.isNotEmpty) ...[
                  _SectionHeader(title: 'Text Channels', count: textChannels.length),
                  for (final ch in textChannels)
                    _ChannelItem(chat: ch, isVoice: false),
                ],
                if (voiceChannels.isNotEmpty) ...[
                  _SectionHeader(title: 'Voice Channels', count: voiceChannels.length),
                  for (final ch in voiceChannels)
                    _ChannelItem(chat: ch, isVoice: true),
                ],
                if (_drillInLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )),
                  )
                else if (subChats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No channels yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Heuristic: channel title containing "voice" or "vc" is treated as voice.
  bool _looksLikeVoice(ChatInfo c) {
    final t = c.title.toLowerCase();
    return t.contains('voice') || t.contains(' vc') || t.startsWith('vc');
  }

  List<ChatInfo> _applyFolderFilter(List<ChatInfo> chats) {
    if (_activeFolder.startsWith('custom_')) {
      final idx = int.tryParse(_activeFolder.substring(7));
      if (idx != null && idx < _customFolders.length) {
        final ids = _customFolders[idx].chatIds;
        return chats.where((c) => ids.contains(c.chatId)).toList();
      }
      return chats;
    }
    return switch (_activeFolder) {
      'dms' => chats.where((c) => c.type == ChatType.dm).toList(),
      'groups' => chats.where((c) => c.type == ChatType.group || c.type == ChatType.topic).toList(),
      'channels' => chats.where((c) => c.type == ChatType.channel).toList(),
      _ => chats,
    };
  }

  List<ChatInfo> _applyPinnedOrder(List<ChatInfo> pinned) {
    if (_pinnedOrder == null) return pinned;
    // Rebuild order based on saved order, adding any new pinned chats at the end
    final ordered = <ChatInfo>[];
    final remaining = List<ChatInfo>.from(pinned);
    for (final saved in _pinnedOrder!) {
      final match = remaining.indexWhere(
        (c) => c.accountId == saved.accountId && c.chatId == saved.chatId,
      );
      if (match != -1) {
        ordered.add(remaining.removeAt(match));
      }
    }
    ordered.addAll(remaining);
    return ordered;
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      _clearSearch();
      return;
    }
    setState(() {
      _searching = true;
      _searchResults = context.read<ChatState>().searchChats(query);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _searchResults = null;
    });
  }

  void _showJoinChannelDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final appState = context.read<AppState>();

    // Find accounts for the active platform that support joining.
    final platform = appState.activePlatform;
    final accounts = appState.accountsForPlatform(platform);
    if (accounts.isEmpty) return;
    final accountId = accounts.first.id;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        title: Text('Join Channel',
          style: TextStyle(color: isDark ? AppColors.darkText : AppColors.lightText)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: platform == 'irc' ? '#channel' : platform == 'mumble' ? 'Channel ID (number)' : 'Channel name',
            hintStyle: TextStyle(color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
          ),
          style: TextStyle(color: isDark ? AppColors.darkText : AppColors.lightText),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.of(ctx).pop(value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    ).then((channelName) {
      if (channelName != null && channelName.isNotEmpty) {
        final engine = context.read<EngineService>();
        engine.joinChat(accountId, channelName);
      }
    });
  }

  Future<void> _showCreateFolderDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('New Folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            isDense: true,
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Create', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;
    setState(() {
      _customFolders.add((name: name, chatIds: {}));
      // Auto-select the new folder
      _activeFolder = 'custom_${_customFolders.length - 1}';
    });
  }

  void _addChatToFolder(int folderIndex, String chatId) {
    setState(() {
      final folder = _customFolders[folderIndex];
      _customFolders[folderIndex] = (
        name: folder.name,
        chatIds: {...folder.chatIds, chatId},
      );
    });
  }

}

// ── Platform Header (replaces PlatformRail) ──

class _PlatformHeader extends StatelessWidget {
  final String platformFilter;
  final int totalUnread;

  const _PlatformHeader({
    required this.platformFilter,
    required this.totalUnread,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = context.watch<AppState>();
    final chatState = context.watch<ChatState>();
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    final meta = _platformMeta[platformFilter];
    final label = meta?.label ?? 'All Chats';
    final icon = meta?.icon ?? Icons.all_inclusive_rounded;
    final color = meta?.color ?? AppColors.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
      child: Row(
        children: [
          // Platform dropdown trigger
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showPlatformPicker(context, appState, chatState),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (totalUnread > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 18),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          totalUnread > 99 ? '99+' : '$totalUnread',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded, size: 18, color: mutedColor),
                  ],
                ),
              ),
            ),
          ),
          // Add platform button
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: () => _showAddPlatformDialog(context),
            tooltip: 'Add platform',
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  void _showPlatformPicker(BuildContext context, AppState appState, ChatState chatState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final platforms = appState.platforms;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // "All Chats" option
          _platformOption(
            ctx: ctx,
            context: context,
            icon: Icons.all_inclusive_rounded,
            color: AppColors.accent,
            label: 'All Chats',
            isActive: platformFilter.isEmpty,
            unread: chatState.totalUnread,
            textColor: textColor,
            mutedColor: mutedColor,
            onTap: () {
              Navigator.pop(ctx);
              appState.setActivePlatform('');
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Divider(height: 1, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          // Each connected platform
          for (final platform in platforms)
            _platformOption(
              ctx: ctx,
              context: context,
              icon: _platformMeta[platform]?.icon ?? Icons.extension_rounded,
              color: _platformMeta[platform]?.color ?? AppColors.accent,
              label: _platformMeta[platform]?.label ?? platform,
              isActive: platformFilter == platform,
              unread: chatState.chatsForPlatform(platform).fold(0, (sum, c) => sum + c.unreadCount),
              connState: _bestConnState(appState, platform),
              textColor: textColor,
              mutedColor: mutedColor,
              onTap: () {
                Navigator.pop(ctx);
                appState.setActivePlatform(platform);
              },
              onLongPress: () {
                Navigator.pop(ctx);
                _showPlatformContextMenu(context, platform);
              },
            ),
        ],
      ),
    );
  }

  Widget _platformOption({
    required BuildContext ctx,
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String label,
    required bool isActive,
    required int unread,
    ConnState connState = ConnState.connected,
    required Color textColor,
    required Color mutedColor,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isActive ? color.withAlpha(20) : null,
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),
            // Connection status indicator
            if (connState != ConnState.connected) ...[
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: switch (connState) {
                    ConnState.connecting || ConnState.unstable || ConnState.authRequired => AppColors.warning,
                    _ => AppColors.danger,
                  },
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Unread badge
            if (unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPlatformContextMenu(BuildContext context, String platform) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final appState = context.read<AppState>();
    final accounts = appState.accountsForPlatform(platform);
    final label = _platformMeta[platform]?.label ?? platform;
    final needsAuth = _bestConnState(appState, platform) == ConnState.authRequired;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(label, style: TextStyle(color: textColor)),
        children: [
          if (needsAuth)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'reauth'),
              child: Row(children: [
                Icon(Icons.lock_open, color: AppColors.warning, size: 18),
                const SizedBox(width: 10),
                Text('Re-authenticate', style: TextStyle(color: AppColors.warning)),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'reconnect'),
            child: Row(children: [
              Icon(Icons.refresh, color: textColor, size: 18),
              const SizedBox(width: 10),
              Text('Reconnect', style: TextStyle(color: textColor)),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'disconnect'),
            child: Row(children: [
              Icon(Icons.power_settings_new, color: AppColors.danger, size: 18),
              const SizedBox(width: 10),
              Text('Disconnect', style: TextStyle(color: AppColors.danger)),
            ]),
          ),
        ],
      ),
    );

    if (!context.mounted || result == null) return;
    final engine = context.read<EngineService>();

    switch (result) {
      case 'reauth':
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
            if (context.mounted) context.read<ChatState>().loadChats();
          });
        }
      case 'reconnect':
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Reconnecting $label...')));
        for (final acc in accounts) {
          engine.connectAccount(acc.id).catchError((_) {});
        }
      case 'disconnect':
        for (final acc in accounts) {
          engine.disconnectAccount(acc.id).catchError((_) {});
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text('Disconnected $label')));
        }
    }
  }

  static void _showAddPlatformDialog(BuildContext context) {
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
                  showDialog<void>(
                    context: context,
                    barrierDismissible: true,
                    builder: (_) => AuthScreen(accountId: id, platform: entry.key),
                  ).then((_) {
                    if (context.mounted) {
                      appState.setActivePlatform(entry.key);
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

  static ConnState _bestConnState(AppState appState, String platform) {
    final accounts = appState.accountsForPlatform(platform);
    if (accounts.isEmpty) return ConnState.disconnected;
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
}

// ── Folder Tabs ──

class _FolderTabs extends StatelessWidget {
  final String activeFolder;
  final List<({String name, Set<String> chatIds})> customFolders;
  final ValueChanged<String> onFolderChanged;
  final VoidCallback onAddFolder;

  const _FolderTabs({
    required this.activeFolder,
    required this.customFolders,
    required this.onFolderChanged,
    required this.onAddFolder,
  });

  static const _builtinFolders = <(String, String, IconData?)>[
    ('all', 'All', null),
    ('dms', 'DMs', null),
    ('groups', 'Groups', null),
    ('channels', 'Channels', null),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allTabs = <(String id, String label, IconData? icon)>[
      ..._builtinFolders,
      for (var i = 0; i < customFolders.length; i++)
        ('custom_$i', customFolders[i].name, Icons.folder_outlined),
    ];
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final (id, label, icon) in allTabs)
              Expanded(
                child: _FolderTab(
                  label: label,
                  icon: icon,
                  isActive: activeFolder == id,
                  isDark: isDark,
                  onTap: () => onFolderChanged(id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FolderTab extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _FolderTab({
    required this.label,
    this.icon,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: isActive
                      ? AppColors.accent
                      : (isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                ),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? AppColors.accent
                        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
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

// ── Section Header ──

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Channel Item (inside drill-in page) ──

class _ChannelItem extends StatelessWidget {
  final ChatInfo chat;
  final bool isVoice;
  const _ChannelItem({required this.chat, required this.isVoice});

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = chatState.activeChat?.chatId == chat.chatId &&
        chatState.activeChat?.accountId == chat.accountId;

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      onLongPressStart: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Material(
        color: isActive
            ? (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt)
            : Colors.transparent,
        child: InkWell(
          onTap: () => chatState.openChat(chat),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  isVoice ? Icons.volume_up : Icons.tag,
                  size: 18,
                  color: isActive
                      ? AppColors.accent
                      : (isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                ),
                if (chat.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 20),
                    decoration: BoxDecoration(
                      color: chat.isMuted ? AppColors.darkTextDim : AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show right-click context menu at the given global position.
  void _showContextMenu(BuildContext context, Offset position) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final menuPosition = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );

    showMenu<String>(
      context: context,
      position: menuPosition,
      color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'mute',
          child: Row(
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 16,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
              const SizedBox(width: 8),
              Text(
                'Mute',
                style: TextStyle(
                    color: isDark ? AppColors.darkText : AppColors.lightText),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'read',
          child: Row(
            children: [
              Icon(
                Icons.done_all,
                size: 16,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
              const SizedBox(width: 8),
              Text(
                'Mark as Read',
                style: TextStyle(
                    color: isDark ? AppColors.darkText : AppColors.lightText),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(
                Icons.edit,
                size: 16,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
              const SizedBox(width: 8),
              Text(
                'Edit Channel',
                style: TextStyle(
                    color: isDark ? AppColors.darkText : AppColors.lightText),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Delete Channel',
                  style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      final chatState = context.read<ChatState>();
      switch (value) {
        case 'mute':
          chatState.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
        case 'read':
          chatState.markChatRead(chat.accountId, chat.chatId);
        case 'edit':
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Edit channel coming soon')),
          );
        case 'delete':
          _showDeleteConfirmation(context);
      }
    });
  }

  /// Show a confirmation dialog before deleting the channel.
  void _showDeleteConfirmation(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete channel'),
        content: Text('Delete "#${chat.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && context.mounted) {
        context.read<ChatState>().leaveChat(chat.accountId, chat.chatId);
      }
    });
  }
}

// ── Reorderable Chat Item (for pinned section) ──

class _ReorderableChatItem extends StatelessWidget {
  final ChatInfo chat;
  final int index;
  final bool showDrillArrow;
  final VoidCallback onDrillIn;
  final List<({String name, Set<String> chatIds})> customFolders;
  final void Function(int folderIndex, String chatId) onAddToFolder;

  const _ReorderableChatItem({
    super.key,
    required this.chat,
    required this.index,
    required this.showDrillArrow,
    required this.onDrillIn,
    required this.customFolders,
    required this.onAddToFolder,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: _ChatItem(
        chat: chat,
        showDrillArrow: showDrillArrow,
        onDrillIn: onDrillIn,
        customFolders: customFolders,
        onAddToFolder: onAddToFolder,
      ),
    );
  }
}

// ── Chat Item ──

class _ChatItem extends StatelessWidget {
  final ChatInfo chat;
  final bool showDrillArrow;
  final VoidCallback? onDrillIn;
  final List<({String name, Set<String> chatIds})> customFolders;
  final void Function(int folderIndex, String chatId)? onAddToFolder;

  const _ChatItem({
    required this.chat,
    this.showDrillArrow = false,
    this.onDrillIn,
    this.customFolders = const [],
    this.onAddToFolder,
  });

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = chatState.activeChat?.chatId == chat.chatId &&
        chatState.activeChat?.accountId == chat.accountId;
    final typing = chatState.typingUserFor(chat.chatId);

    // Determine if this chat can be drilled into
    final canDrillIn = showDrillArrow &&
        (chat.type == ChatType.group || chat.type == ChatType.topic);

    // Right-click context menu via GestureDetector
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      onLongPressStart: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Material(
        color: isActive
            ? (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt)
            : Colors.transparent,
        child: InkWell(
          onTap: () {
            if (canDrillIn) {
              onDrillIn?.call();
            } else {
              chatState.openChat(chat);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Avatar
                _ChatAvatar(chat: chat),
                const SizedBox(width: 12),

                // Name + preview
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Type icon
                          if (chat.type == ChatType.group)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.group,
                                  size: 14,
                                  color: isDark
                                      ? AppColors.darkTextDim
                                      : AppColors.lightTextDim),
                            ),
                          if (chat.type == ChatType.channel)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.campaign,
                                  size: 14,
                                  color: isDark
                                      ? AppColors.darkTextDim
                                      : AppColors.lightTextDim),
                            ),
                          if (chat.type == ChatType.topic)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.forum,
                                  size: 14,
                                  color: isDark
                                      ? AppColors.darkTextDim
                                      : AppColors.lightTextDim),
                            ),
                          // Title
                          Expanded(
                            child: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: chat.unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                              ),
                            ),
                          ),
                          // Time
                          if (chat.lastMsgTime > 0)
                            Text(
                              _formatTime(chat.lastMsgDateTime),
                              style: TextStyle(
                                fontSize: 11,
                                color: chat.unreadCount > 0
                                    ? AppColors.accent
                                    : (isDark
                                        ? AppColors.darkTextDim
                                        : AppColors.lightTextDim),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          // Preview text or typing indicator
                          Expanded(
                            child: typing != null
                                ? Text(
                                    '$typing is typing...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.accent,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  )
                                : Text(
                                    chat.draftText.isNotEmpty
                                        ? 'Draft: ${chat.draftText}'
                                        : _previewText(chat),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: chat.draftText.isNotEmpty
                                          ? AppColors.danger
                                          : (isDark
                                              ? AppColors.darkTextMuted
                                              : AppColors.lightTextMuted),
                                    ),
                                  ),
                          ),
                          // Drill-in arrow
                          if (canDrillIn)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: isDark
                                    ? AppColors.darkTextDim
                                    : AppColors.lightTextDim,
                              ),
                            ),
                          // Unread badge
                          if (chat.unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              constraints: const BoxConstraints(minWidth: 20),
                              decoration: BoxDecoration(
                                color: chat.isMuted
                                    ? AppColors.darkTextDim
                                    : AppColors.accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                chat.unreadCount > 99
                                    ? '99+'
                                    : '${chat.unreadCount}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          // Pin indicator
                          if (chat.isPinned)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.push_pin,
                                  size: 12,
                                  color: isDark
                                      ? AppColors.darkTextDim
                                      : AppColors.lightTextDim),
                            ),
                          // Muted indicator
                          if (chat.isMuted)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.notifications_off,
                                  size: 12,
                                  color: isDark
                                      ? AppColors.darkTextDim
                                      : AppColors.lightTextDim),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show context menu at the given global position.
  void _showContextMenu(BuildContext context, Offset position) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = context.read<ChatState>();
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final menuPosition = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );

    showMenu<String>(
      context: context,
      position: menuPosition,
      color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                size: 16,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
              const SizedBox(width: 8),
              Text(chat.isPinned ? 'Unpin' : 'Pin'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Row(
            children: [
              Icon(
                chat.isMuted ? Icons.notifications : Icons.notifications_off,
                size: 16,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
              const SizedBox(width: 8),
              Text(chat.isMuted ? 'Unmute' : 'Mute'),
            ],
          ),
        ),
        if (chat.unreadCount > 0)
          PopupMenuItem(
            value: 'read',
            child: Row(
              children: [
                Icon(
                  Icons.done_all,
                  size: 16,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
                const SizedBox(width: 8),
                const Text('Mark as read'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'archive',
          child: Row(
            children: [
              Icon(
                Icons.archive_outlined,
                size: 16,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
              const SizedBox(width: 8),
              const Text('Archive'),
            ],
          ),
        ),
        // "Move to folder" entries (only shown when custom folders exist)
        if (customFolders.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (var i = 0; i < customFolders.length; i++)
            PopupMenuItem(
              value: 'folder_$i',
              child: Row(
                children: [
                  Icon(
                    customFolders[i].chatIds.contains(chat.chatId)
                        ? Icons.folder
                        : Icons.folder_outlined,
                    size: 16,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    customFolders[i].chatIds.contains(chat.chatId)
                        ? 'In "${customFolders[i].name}"'
                        : 'Add to "${customFolders[i].name}"',
                    style: TextStyle(
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                ],
              ),
            ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (value.startsWith('folder_')) {
        final idx = int.tryParse(value.substring(7));
        if (idx != null) onAddToFolder?.call(idx, chat.chatId);
        return;
      }
      switch (value) {
        case 'pin':
          chatState.pinChat(chat.accountId, chat.chatId, !chat.isPinned);
        case 'mute':
          chatState.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
        case 'read':
          chatState.openChat(chat);
          chatState.markRead();
        case 'archive':
          chatState.archiveChat(chat.accountId, chat.chatId, true);
        case 'delete':
          if (context.mounted) _showDeleteConfirmation(context, chatState);
      }
    });
  }

  /// Show a confirmation dialog before deleting.
  void _showDeleteConfirmation(BuildContext context, ChatState chatState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete chat'),
        content: Text('Delete "${chat.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        chatState.leaveChat(chat.accountId, chat.chatId);
      }
    });
  }

  String _previewText(ChatInfo chat) {
    if (chat.lastMsgText.isEmpty) return '';
    if (chat.lastMsgSender.isNotEmpty) {
      return '${chat.lastMsgSender}: ${chat.lastMsgText}';
    }
    return chat.lastMsgText;
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }
}

// ── Chat Avatar ──

class _ChatAvatar extends StatelessWidget {
  final ChatInfo chat;
  const _ChatAvatar({required this.chat});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = safeInitial(chat.title);

    // Generate a stable color from the chat ID.
    final hue = (chat.chatId.hashCode % 360).abs().toDouble();
    final bgColor = HSLColor.fromAHSL(1, hue, 0.5, isDark ? 0.3 : 0.75).toColor();

    return SizedBox(
      width: AppSizes.avatarSize,
      height: AppSizes.avatarSize,
      child: Stack(
        children: [
          Container(
            width: AppSizes.avatarSize,
            height: AppSizes.avatarSize,
            decoration: BoxDecoration(
              color: bgColor,
              shape: chat.type == ChatType.channel ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: chat.type == ChatType.channel ? BorderRadius.circular(8) : null,
            ),
            child: Center(
              child: chat.type == ChatType.channel
                  ? const Icon(Icons.campaign, color: Colors.white, size: 20)
                  : Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          // Online dot for DMs
          if (chat.type == ChatType.dm)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.online,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── User Status Enum ──

enum _UserStatus {
  online('Online', AppColors.online),
  away('Away', AppColors.warning),
  dnd('Do Not Disturb', AppColors.danger),
  invisible('Invisible', Color(0xFF5c6573));

  final String label;
  final Color color;
  const _UserStatus(this.label, this.color);
}

// ── User Panel ──

class _UserPanel extends StatefulWidget {
  const _UserPanel();

  @override
  State<_UserPanel> createState() => _UserPanelState();
}

class _UserPanelState extends State<_UserPanel> {
  _UserStatus _status = _UserStatus.online;
  String _customStatus = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = context.watch<AppState>();
    final accounts = appState.accounts;

    // Find the first connected account for display name.
    String displayName = 'User';

    if (accounts.isNotEmpty) {
      AccountInfo? connectedAccount;
      for (final account in accounts) {
        final state = appState.connStateFor(account.id);
        if (state == ConnState.connected) {
          connectedAccount ??= account;
        }
      }
      if (connectedAccount != null && connectedAccount.displayName.isNotEmpty) {
        displayName = connectedAccount.displayName;
      } else if (accounts.first.displayName.isNotEmpty) {
        displayName = accounts.first.displayName;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar with status dot — tapping opens status picker
          GestureDetector(
            onTap: () => _showStatusPicker(context),
            child: SizedBox(
              width: AppSizes.avatarSizeSmall,
              height: AppSizes.avatarSizeSmall,
              child: Stack(
                children: [
                  Container(
                    width: AppSizes.avatarSizeSmall,
                    height: AppSizes.avatarSizeSmall,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.person, color: Colors.white, size: 18),
                    ),
                  ),
                  // Status dot
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _status.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name + status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                Text(
                  _status.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: _status.color,
                  ),
                ),
                if (_customStatus.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showCustomStatusDialog(context),
                    child: Text(
                      _customStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: (isDark ? AppColors.darkText : AppColors.lightText)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Account switcher
          if (accounts.length > 1)
            _AccountSwitcherButton(accounts: accounts),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            splashRadius: 16,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  void _showCustomStatusDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: _customStatus);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text(
            'Custom Status',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 50,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
            decoration: InputDecoration(
              hintText: 'What\'s on your mind?',
              hintStyle: TextStyle(
                fontSize: 13,
                color: (isDark ? AppColors.darkText : AppColors.lightText).withValues(alpha: 0.4),
              ),
              counterStyle: TextStyle(
                fontSize: 11,
                color: (isDark ? AppColors.darkText : AppColors.lightText).withValues(alpha: 0.4),
              ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13,
                  color: (isDark ? AppColors.darkText : AppColors.lightText).withValues(alpha: 0.6),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _customStatus = controller.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 13, color: AppColors.accent),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showStatusPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<_UserStatus>(
      context: context,
      position: position,
      color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        for (final status in _UserStatus.values)
          PopupMenuItem(
            value: status,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: status.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _status == status ? FontWeight.w600 : FontWeight.w400,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                if (_status == status) ...[
                  const Spacer(),
                  const Icon(Icons.check, size: 16, color: AppColors.accent),
                ],
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value != null) {
        setState(() => _status = value);
      }
    });
  }
}

// ── Account Switcher Button ──

class _AccountSwitcherButton extends StatelessWidget {
  final List<AccountInfo> accounts;
  const _AccountSwitcherButton({required this.accounts});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.unfold_more, size: 18),
      onPressed: () => _showAccountSwitcher(context),
      splashRadius: 16,
      tooltip: 'Switch account',
    );
  }

  void _showAccountSwitcher(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = context.read<AppState>();
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        // "All" option to clear platform filter
        PopupMenuItem(
          value: '',
          child: Row(
            children: [
              const Icon(Icons.apps, size: 16),
              const SizedBox(width: 8),
              Text(
                'All Platforms',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: appState.activePlatform.isEmpty
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              if (appState.activePlatform.isEmpty) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16, color: AppColors.accent),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(),
        for (final account in accounts)
          PopupMenuItem(
            value: account.platform,
            child: Row(
              children: [
                Icon(
                  _platformIcon(account.platform),
                  size: 16,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        account.displayName.isNotEmpty
                            ? account.displayName
                            : account.platform,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkText : AppColors.lightText,
                        ),
                      ),
                      Text(
                        _platformName(account.platform),
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                        ),
                      ),
                    ],
                  ),
                ),
                if (appState.activePlatform == account.platform)
                  const Icon(Icons.check, size: 16, color: AppColors.accent),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value != null) {
        appState.setActivePlatform(value);
      }
    });
  }

  IconData _platformIcon(String platform) => switch (platform) {
    'telegram' => Icons.send,
    'bale' => Icons.message,
    'matrix' => Icons.grid_view,
    'irc' => Icons.terminal,
    'xmpp' => Icons.chat,
    'github' => Icons.code,
    'rubika' => Icons.phone_android,
    'deltachat' => Icons.mail,
    'teamspeak' => Icons.headset_mic,
    'mumble' => Icons.mic,
    _ => Icons.chat_bubble,
  };

  String _platformName(String platform) => switch (platform) {
    'telegram' => 'Telegram',
    'bale' => 'Bale',
    'matrix' => 'Matrix',
    'irc' => 'IRC',
    'xmpp' => 'XMPP',
    'github' => 'GitHub',
    'rubika' => 'Rubika',
    'deltachat' => 'Delta Chat',
    'teamspeak' => 'TeamSpeak',
    'mumble' => 'Mumble',
    _ => platform,
  };
}

