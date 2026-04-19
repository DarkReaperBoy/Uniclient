import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'chat_list_row.dart';

/// The entire left panel: search bar + chat list.
/// When [collapsed] is true, renders in avatar-only narrow mode (spec §1:
/// dialogs dragged below 130px snap to collapsed showing only avatars).
class ChatListPanel extends StatefulWidget {
  final bool showHamburger;
  final VoidCallback? onOpenDrawer;
  final bool filterSidebarVisible;
  final bool collapsed;

  const ChatListPanel({
    super.key,
    this.showHamburger = false,
    this.onOpenDrawer,
    this.filterSidebarVisible = false,
    this.collapsed = false,
  });

  /// Global hook used by app-level keyboard shortcuts (Ctrl+F) to focus the
  /// currently mounted ChatListPanel's search field. The live state registers
  /// its `_focusSearch` callback on mount and clears it on dispose.
  static VoidCallback? focusSearchRequest;

  /// Global hook used by app-level Esc handling. Returns true if the live
  /// panel was actively searching and the search was cancelled (so Esc is
  /// "consumed"); returns false if nothing to cancel.
  static bool Function()? cancelSearchRequest;

  /// Global hook used by app-level Alt+Down/Alt+Up (Telegram Desktop spec
  /// §24.4 `next_chat` / `previous_chat`). The live panel state registers a
  /// handler that opens the adjacent chat in the currently visible, sorted
  /// list (direction: +1 = next, -1 = previous).
  static void Function(int direction)? navigateChatRequest;

  /// Global hook used by app-level Ctrl+Shift+Down / Ctrl+Shift+Up (Telegram
  /// Desktop spec §24.4 `next_folder` / `previous_folder`). The live panel
  /// state registers a handler that switches the active folder in the tab
  /// order (direction: +1 = next, -1 = previous).
  static void Function(int direction)? navigateFolderRequest;

  /// Global hook used by app-level Ctrl+Alt+Home / Ctrl+Alt+End (Telegram
  /// Desktop spec §24.4 `first_chat` / `last_chat`). The live panel state
  /// registers a handler that jumps the active chat selection to the first
  /// (`toFirst=true`) or last (`toFirst=false`) chat in the currently visible
  /// sorted list.
  static void Function(bool toFirst)? jumpChatRequest;

  /// Global hook used by app-level Ctrl+1..Ctrl+8 (Telegram Desktop spec
  /// §24.4 `all_chats`/`folder1`..`folder6`/`last_folder`). `oneIndex` is
  /// 1-based: 1 → All Chats (null), 2..7 → folders[oneIndex-2], 8 → last
  /// folder. No-op when the target doesn't exist.
  static void Function(int oneIndex)? switchFolderByIndexRequest;

  /// Focus the chat list search field. Safe to call when no panel is mounted.
  static void requestFocusSearch() => focusSearchRequest?.call();

  /// Cancel the chat list search if active. Returns true if it was cancelled.
  static bool requestCancelSearch() => cancelSearchRequest?.call() ?? false;

  /// Move active chat selection by [direction] (+1 = next, -1 = previous).
  /// Safe to call when no panel is mounted.
  static void requestNavigateChat(int direction) =>
      navigateChatRequest?.call(direction);

  /// Move active folder selection by [direction] (+1 = next, -1 = previous).
  /// Safe to call when no panel is mounted.
  static void requestNavigateFolder(int direction) =>
      navigateFolderRequest?.call(direction);

  /// Jump to the first (`toFirst=true`) or last (`toFirst=false`) chat in the
  /// currently visible sorted list. Safe to call when no panel is mounted.
  static void requestJumpChat(bool toFirst) =>
      jumpChatRequest?.call(toFirst);

  /// Switch to the folder tab at 1-based [oneIndex]: 1 → All Chats, 2..7 →
  /// folders[oneIndex-2], 8 → last folder. Safe to call when no panel is
  /// mounted. No-op when the target folder doesn't exist for the active
  /// account.
  static void requestSwitchFolderByIndex(int oneIndex) =>
      switchFolderByIndexRequest?.call(oneIndex);

  @override
  State<ChatListPanel> createState() => _ChatListPanelState();
}

class _ChatListPanelState extends State<ChatListPanel> {
  final _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;
  List<ChatInfo>? _searchResults;

  @override
  void initState() {
    super.initState();
    ChatListPanel.focusSearchRequest = _focusSearch;
    ChatListPanel.cancelSearchRequest = _cancelSearchIfActive;
    ChatListPanel.navigateChatRequest = _navigateChat;
    ChatListPanel.navigateFolderRequest = _navigateFolder;
    ChatListPanel.jumpChatRequest = _jumpChat;
    ChatListPanel.switchFolderByIndexRequest = _switchFolderByIndex;
  }

  /// Jump to first or last visible chat. Uses the same sorted, non-archived,
  /// folder/search-filtered list `_navigateChat` builds so the jump target
  /// exactly matches what the user sees in the sidebar.
  void _jumpChat(bool toFirst) {
    if (!mounted) return;
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();

    final accountChats = chatState.chatsForAccount(appState.activeAccountId);
    final base = chatState.activeFolderId != null
        ? chatState.chatsForFolder(chatState.activeFolderId)
        : accountChats;
    final displayChats = _searchResults ?? base;
    final sorted = List<ChatInfo>.from(displayChats)
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastMsgTime.compareTo(a.lastMsgTime);
      });
    final visible = sorted.where((c) => !c.isArchived).toList();
    if (visible.isEmpty) return;
    final target = toFirst ? visible.first : visible.last;
    final active = chatState.activeChat;
    if (active != null &&
        active.chatId == target.chatId &&
        active.accountId == target.accountId) {
      return; // already at target
    }
    chatState.openChat(target);
  }

  /// Open the chat adjacent to the currently active one in the visible list.
  /// Rebuilds the same sorted, non-archived list the ListView renders, so
  /// navigation order exactly matches what the user sees. If no chat is
  /// active, opens the first (direction +1) or last (direction -1) visible
  /// chat. No-op when the visible list is empty.
  void _navigateChat(int direction) {
    if (!mounted) return;
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();

    final accountChats = chatState.chatsForAccount(appState.activeAccountId);
    final base = chatState.activeFolderId != null
        ? chatState.chatsForFolder(chatState.activeFolderId)
        : accountChats;
    // Search results take priority when actively searching, to match what
    // the user currently sees in the sidebar.
    final displayChats = _searchResults ?? base;
    final sorted = List<ChatInfo>.from(displayChats)
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastMsgTime.compareTo(a.lastMsgTime);
      });
    final visible = sorted.where((c) => !c.isArchived).toList();
    if (visible.isEmpty) return;

    final active = chatState.activeChat;
    int target;
    if (active == null) {
      target = direction >= 0 ? 0 : visible.length - 1;
    } else {
      final idx = visible.indexWhere(
        (c) => c.chatId == active.chatId && c.accountId == active.accountId,
      );
      if (idx < 0) {
        // Active chat isn't in the visible list (e.g. user is in a different
        // folder than the active chat). Fall back to the first/last item.
        target = direction >= 0 ? 0 : visible.length - 1;
      } else {
        target = (idx + direction).clamp(0, visible.length - 1);
        if (target == idx) return; // already at boundary
      }
    }
    chatState.openChat(visible[target]);
  }

  /// Switch the active folder by [direction] (+1 = next, -1 = previous).
  /// Tab order is `[null ("All Chats"), folders[0], folders[1], ...]` — the
  /// same order rendered by the vertical `FilterColumn` and the horizontal
  /// `_HorizontalFolderTabs`. Clamps at boundaries (matches Alt+Down/Up chat
  /// nav behavior). No-op when no folders exist for the active account.
  void _navigateFolder(int direction) {
    if (!mounted) return;
    final chatState = context.read<ChatState>();
    final folders = chatState.folders;
    if (folders.isEmpty) return; // no folders → no-op

    // Build the tab-order list: null ("All") at index 0, then each folder.
    final ids = <String?>[null, ...folders.map((f) => f.id)];
    final currentIdx = ids.indexOf(chatState.activeFolderId);
    // If the current active folder isn't in the list (e.g. stale id after
    // folder edit), fall back to "All" at index 0 or end.
    final startIdx = currentIdx < 0 ? (direction >= 0 ? -1 : ids.length) : currentIdx;
    final target = (startIdx + direction).clamp(0, ids.length - 1);
    if (target == currentIdx) return; // already at boundary
    chatState.setActiveFolder(ids[target]);
  }

  /// Switch to a specific folder tab by its 1-based position in the tab
  /// order. Tab order is `[null ("All"), folders[0], folders[1], ...]`.
  /// `oneIndex=1` → All Chats, `oneIndex=2..7` → folders[oneIndex-2],
  /// `oneIndex=8` → always the last folder (Telegram Desktop spec §24.4
  /// `last_folder`). No-op if the target doesn't exist.
  void _switchFolderByIndex(int oneIndex) {
    if (!mounted) return;
    final chatState = context.read<ChatState>();
    final folders = chatState.folders;
    String? target;
    if (oneIndex == 1) {
      target = null; // All Chats
    } else if (oneIndex == 8) {
      if (folders.isEmpty) return;
      target = folders.last.id;
    } else if (oneIndex >= 2 && oneIndex <= 7) {
      final folderIdx = oneIndex - 2;
      if (folderIdx >= folders.length) return; // no folder at that slot
      target = folders[folderIdx].id;
    } else {
      return; // out of range
    }
    if (chatState.activeFolderId == target) return; // already active
    chatState.setActiveFolder(target);
  }

  /// Global-Esc hook. If the search field is currently active (Cancel
  /// button visible), cancel and return true so the app-level Esc handler
  /// knows the event was consumed. Pairs with the Ctrl+F focus shortcut —
  /// Telegram Desktop spec §24.4 uses Esc to close search.
  bool _cancelSearchIfActive() {
    if (!mounted || !_searching) return false;
    _cancelSearch();
    return true;
  }

  @override
  void dispose() {
    if (ChatListPanel.focusSearchRequest == _focusSearch) {
      ChatListPanel.focusSearchRequest = null;
    }
    if (ChatListPanel.cancelSearchRequest == _cancelSearchIfActive) {
      ChatListPanel.cancelSearchRequest = null;
    }
    if (ChatListPanel.navigateChatRequest == _navigateChat) {
      ChatListPanel.navigateChatRequest = null;
    }
    if (ChatListPanel.navigateFolderRequest == _navigateFolder) {
      ChatListPanel.navigateFolderRequest = null;
    }
    if (ChatListPanel.jumpChatRequest == _jumpChat) {
      ChatListPanel.jumpChatRequest = null;
    }
    if (ChatListPanel.switchFolderByIndexRequest == _switchFolderByIndex) {
      ChatListPanel.switchFolderByIndexRequest = null;
    }
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _focusSearch() {
    if (!mounted) return;
    setState(() => _searching = true);
    _searchFocus.requestFocus();
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

    // Filter chats: always scoped to active account, then by folder.
    final accountChats = chatState.chatsForAccount(appState.activeAccountId);
    final chats = chatState.activeFolderId != null
        ? chatState.chatsForFolder(chatState.activeFolderId)
        : accountChats;

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
          // Horizontal folder tabs (when active account has folders and vertical sidebar is hidden).
          if (chatState.hasFolders && !widget.filterSidebarVisible && !_searching)
            _HorizontalFolderTabs(
              chatState: chatState,
              allUnread: chatState.unreadCountForAccount(appState.activeAccountId),
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
                        isOnline: chatState.isChatOnline(chat),
                        typingUser: chatState.typingUserFor(chat.chatId),
                        onTap: () => chatState.openChat(chat),
                        onSecondaryTap: (pos) => _showChatContextMenu(context, chat, pos),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showChatContextMenu(BuildContext context, ChatInfo chat, Offset globalPosition) {
    final chatState = context.read<ChatState>();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final isGroupy = chat.type == ChatType.group ||
        chat.type == ChatType.channel ||
        chat.type == ChatType.topic;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'pin', child: Text(chat.isPinned ? 'Unpin' : 'Pin')),
        PopupMenuItem(value: 'mute', child: Text(chat.isMuted ? 'Unmute' : 'Mute')),
        PopupMenuItem(
          value: 'read',
          child: Text(chat.unreadCount > 0 ? 'Mark as Read' : 'Mark as Unread'),
        ),
        PopupMenuItem(value: 'archive', child: Text(chat.isArchived ? 'Unarchive' : 'Archive')),
        if (isGroupy) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'leave', child: Text('Leave Chat')),
        ],
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

/// Horizontal folder tabs shown when vertical sidebar is hidden.
/// Spec §2: scrollable row, active tab with sliding underline.
class _HorizontalFolderTabs extends StatelessWidget {
  final ChatState chatState;
  final int allUnread;

  const _HorizontalFolderTabs({required this.chatState, required this.allUnread});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = chatState.folders;
    final activeFolderId = chatState.activeFolderId;

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        children: [
          // "All" tab (no folder filter — show all chats for this account).
          _FolderChip(
            label: 'All',
            isActive: activeFolderId == null,
            unreadCount: allUnread,
            onTap: () => chatState.setActiveFolder(null),
            theme: theme,
          ),
          ...folders.map((f) => _FolderChip(
            label: f.name,
            isActive: activeFolderId == f.id,
            unreadCount: chatState.unreadCountForFolder(f.id),
            onTap: () => chatState.setActiveFolder(
              activeFolderId == f.id ? null : f.id,
            ),
            theme: theme,
          )),
        ],
      ),
    );
  }
}

class _FolderChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final int unreadCount;
  final VoidCallback onTap;
  final ThemeData theme;

  const _FolderChip({
    required this.label,
    required this.isActive,
    required this.unreadCount,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? theme.colorScheme.primary : theme.textTheme.bodySmall?.color,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unreadCount > 999 ? '999+' : '$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
