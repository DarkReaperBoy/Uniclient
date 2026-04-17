import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'chat_list_row.dart';

/// The entire left panel: search bar + chat list.
class ChatListPanel extends StatefulWidget {
  final bool showHamburger;
  final VoidCallback? onOpenDrawer;

  const ChatListPanel({
    super.key,
    this.showHamburger = false,
    this.onOpenDrawer,
  });

  @override
  State<ChatListPanel> createState() => _ChatListPanelState();
}

class _ChatListPanelState extends State<ChatListPanel> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  List<ChatInfo>? _searchResults;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    final chatState = context.read<ChatState>();
    setState(() {
      _searchResults = chatState.searchChats(query);
    });
  }

  void _cancelSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _searchResults = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = context.watch<ChatState>();
    final appState = context.watch<AppState>();

    // Filter chats by active platform/account.
    List<ChatInfo> chats;
    if (appState.activeAccountId.isNotEmpty) {
      chats = chatState.chatsForAccount(appState.activeAccountId);
    } else if (appState.activePlatform.isNotEmpty) {
      chats = chatState.chatsForPlatform(appState.activePlatform);
    } else {
      chats = chatState.chats;
    }

    // Use search results if searching.
    final displayChats = _searchResults ?? chats;

    // Sort: pinned first, then by lastMsgTime descending.
    final sorted = List<ChatInfo>.from(displayChats)
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastMsgTime.compareTo(a.lastMsgTime);
      });

    // Separate archived chats.
    final nonArchived = sorted.where((c) => !c.isArchived).toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Search bar.
          _SearchBar(
            controller: _searchController,
            focusNode: _searchFocus,
            showHamburger: widget.showHamburger,
            searching: _searching,
            onOpenDrawer: widget.onOpenDrawer,
            onFocused: () => setState(() => _searching = true),
            onChanged: _onSearchChanged,
            onCancel: _cancelSearch,
          ),
          // Platform filter chips (when multiple platforms).
          if (appState.platforms.length > 1 && !_searching)
            _PlatformFilter(
              platforms: appState.platforms,
              active: appState.activePlatform,
              onSelect: (p) => appState.setActivePlatform(
                  p == appState.activePlatform ? '' : p),
            ),
          // Chat list.
          Expanded(
            child: nonArchived.isEmpty
                ? _EmptyState(searching: _searching)
                : ListView.builder(
                    itemCount: nonArchived.length,
                    itemBuilder: (context, index) {
                      final chat = nonArchived[index];
                      final isActive =
                          chatState.activeChat?.chatId == chat.chatId &&
                          chatState.activeChat?.accountId == chat.accountId;
                      return ChatListRow(
                        chat: chat,
                        isActive: isActive,
                        typingUser: chatState.typingUserFor(chat.chatId),
                        onTap: () => chatState.openChat(chat),
                        onSecondaryTap: () => _showChatContextMenu(context, chat),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showChatContextMenu(BuildContext context, ChatInfo chat) {
    final chatState = context.read<ChatState>();
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final position = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        PopupMenuItem(value: 'pin', child: Text(chat.isPinned ? 'Unpin' : 'Pin')),
        PopupMenuItem(value: 'mute', child: Text(chat.isMuted ? 'Unmute' : 'Mute')),
        PopupMenuItem(
          value: 'read',
          child: Text(chat.unreadCount > 0 ? 'Mark as Read' : 'Mark as Unread'),
        ),
        PopupMenuItem(value: 'archive', child: Text(chat.isArchived ? 'Unarchive' : 'Archive')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'leave', child: Text('Leave Chat')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'pin':
          chatState.pinChat(chat.accountId, chat.chatId, !chat.isPinned);
        case 'mute':
          chatState.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
        case 'read':
          if (chat.unreadCount > 0) {
            chatState.markChatRead(chat.accountId, chat.chatId);
          }
        case 'archive':
          chatState.archiveChat(chat.accountId, chat.chatId, !chat.isArchived);
        case 'leave':
          chatState.leaveChat(chat.accountId, chat.chatId);
      }
    });
  }
}

/// Search bar at top of sidebar.
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showHamburger;
  final bool searching;
  final VoidCallback? onOpenDrawer;
  final VoidCallback onFocused;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.showHamburger,
    required this.searching,
    this.onOpenDrawer,
    required this.onFocused,
    required this.onChanged,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      child: Row(
        children: [
          if (showHamburger && !searching) ...[
            IconButton(
              icon: const Icon(Icons.menu, size: 20),
              onPressed: onOpenDrawer,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onTap: onFocused,
                onChanged: onChanged,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.brightness == Brightness.dark
                      ? const Color(0xFF1e2430)
                      : const Color(0xFFF0F0F0),
                ),
              ),
            ),
          ),
          if (searching) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal platform filter chips.
class _PlatformFilter extends StatelessWidget {
  final List<String> platforms;
  final String active;
  final ValueChanged<String> onSelect;

  const _PlatformFilter({
    required this.platforms,
    required this.active,
    required this.onSelect,
  });

  static const _platformIcons = <String, IconData>{
    'telegram': Icons.send,
    'matrix': Icons.grid_view,
    'xmpp': Icons.message,
    'irc': Icons.tag,
    'bale': Icons.chat,
    'rubika': Icons.radio_button_checked,
    'deltachat': Icons.email,
    'mumble': Icons.headset_mic,
    'teamspeak': Icons.headset,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        children: [
          // "All" chip.
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: const Text('All'),
              selected: active.isEmpty,
              onSelected: (_) => onSelect(''),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(fontSize: 12, color: active.isEmpty ? Colors.white : null),
              selectedColor: theme.colorScheme.primary,
              showCheckmark: false,
            ),
          ),
          ...platforms.map((p) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              avatar: Icon(_platformIcons[p] ?? Icons.chat, size: 14),
              label: Text(_platformLabel(p)),
              selected: active == p,
              onSelected: (_) => onSelect(p),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(fontSize: 12, color: active == p ? Colors.white : null),
              selectedColor: theme.colorScheme.primary,
              showCheckmark: false,
            ),
          )),
        ],
      ),
    );
  }

  static String _platformLabel(String p) => switch (p) {
    'telegram' => 'Telegram',
    'matrix' => 'Matrix',
    'xmpp' => 'XMPP',
    'irc' => 'IRC',
    'bale' => 'Bale',
    'rubika' => 'Rubika',
    'deltachat' => 'Delta Chat',
    'mumble' => 'Mumble',
    'teamspeak' => 'TeamSpeak',
    _ => p,
  };
}

/// Empty state for chat list.
class _EmptyState extends StatelessWidget {
  final bool searching;

  const _EmptyState({required this.searching});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.search_off : Icons.chat_bubble_outline,
            size: 48,
            color: theme.textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 12),
          Text(
            searching ? 'No results found' : 'No chats yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }
}
