import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
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

/// Search-mode tab enum matching Telegram Desktop `ChatSearchTab`.
enum _SearchTab { myMessages, publicPosts, thisPeer }

/// Sub-filter for "My Messages" tab (spec §2.2: ChatSearchIn popup menu).
/// Filters search results by chat type under the My Messages tab.
enum _MyMsgSubFilter { all, private_, groups, channels }

class _ChatListPanelState extends State<ChatListPanel> {
  final _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;
  List<ChatInfo>? _searchResults;
  _SearchTab _activeSearchTab = _SearchTab.myMessages;
  _MyMsgSubFilter _myMsgSubFilter = _MyMsgSubFilter.all;

  @override
  void initState() {
    super.initState();
    ChatListPanel.focusSearchRequest = _focusSearch;
    ChatListPanel.cancelSearchRequest = _cancelSearchIfActive;
    ChatListPanel.navigateChatRequest = _navigateChat;
    ChatListPanel.navigateFolderRequest = _navigateFolder;
    ChatListPanel.jumpChatRequest = _jumpChat;
    ChatListPanel.switchFolderByIndexRequest = _switchFolderByIndex;
    // Listen to controller directly to handle programmatic text changes
    // (e.g. debug type command) in addition to TextField.onChanged.
    _searchController.addListener(_onControllerChanged);
  }

  String _lastControllerText = '';
  void _onControllerChanged() {
    final text = _searchController.text;
    if (text == _lastControllerText) return;
    _lastControllerText = text;
    _onSearchChanged(text);
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
    _searchController.removeListener(_onControllerChanged);
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
      _searchResults = _filterByTab(chatState.searchChats(query), chatState);
    });
  }

  /// Filter search results based on the active search tab.
  List<ChatInfo> _filterByTab(List<ChatInfo> results, ChatState chatState) {
    switch (_activeSearchTab) {
      case _SearchTab.myMessages:
        // Apply sub-filter (Private/Groups/Channels) if set.
        switch (_myMsgSubFilter) {
          case _MyMsgSubFilter.all:
            return results;
          case _MyMsgSubFilter.private_:
            return results.where((c) => c.type == ChatType.dm).toList();
          case _MyMsgSubFilter.groups:
            return results.where((c) => c.type == ChatType.group || c.type == ChatType.topic).toList();
          case _MyMsgSubFilter.channels:
            return results.where((c) => c.type == ChatType.channel).toList();
        }
      case _SearchTab.publicPosts:
        // Only channels (public posts).
        return results.where((c) => c.type == ChatType.channel).toList();
      case _SearchTab.thisPeer:
        // Only results matching the currently active chat.
        final active = chatState.activeChat;
        if (active == null) return [];
        return results
            .where((c) =>
                c.chatId == active.chatId &&
                c.accountId == active.accountId)
            .toList();
    }
  }

  void _onSubFilterChanged(_MyMsgSubFilter filter) {
    setState(() {
      _myMsgSubFilter = filter;
    });
    // Re-run search with new sub-filter.
    final query = _searchController.text;
    if (query.isNotEmpty) {
      final chatState = context.read<ChatState>();
      setState(() {
        _searchResults = _filterByTab(chatState.searchChats(query), chatState);
      });
    }
  }

  void _onSearchTabChanged(_SearchTab tab) {
    setState(() {
      _activeSearchTab = tab;
      _myMsgSubFilter = _MyMsgSubFilter.all; // Reset sub-filter on tab switch.
    });
    // Re-run search with current query under the new tab filter.
    final query = _searchController.text;
    if (query.isNotEmpty) {
      final chatState = context.read<ChatState>();
      setState(() {
        _searchResults = _filterByTab(chatState.searchChats(query), chatState);
      });
    }
  }

  void _cancelSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _searchResults = null;
      _activeSearchTab = _SearchTab.myMessages;
      _myMsgSubFilter = _MyMsgSubFilter.all;
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
          // Search tabs strip (spec §2.2: shown when typing in search bar).
          if (_searching && _searchController.text.isNotEmpty)
            _SearchTabsStrip(
              activeTab: _activeSearchTab,
              onTabChanged: _onSearchTabChanged,
            ),
          // Sub-filter row under My Messages (spec §2.2: ChatSearchIn popup).
          if (_searching &&
              _searchController.text.isNotEmpty &&
              _activeSearchTab == _SearchTab.myMessages)
            _SearchSubFilterRow(
              activeFilter: _myMsgSubFilter,
              onFilterChanged: _onSubFilterChanged,
            ),
          // Top Peers strip (spec §2: shown when search focused, no query).
          if (_searching && _searchController.text.isEmpty)
            _TopPeersStrip(
              chats: accountChats,
              onTap: (chat) => chatState.openChat(chat),
            ),
          // Chat list / Recent Contacts (spec §2.2: recent contacts shown
          // when search focused with empty query, below Top Peers strip).
          Expanded(
            child: _searching && _searchController.text.isEmpty
                ? _RecentContactsList(
                    chats: accountChats,
                    onTap: (chat) => chatState.openChat(chat),
                    chatState: chatState,
                  )
                : nonArchived.isEmpty
                    ? _EmptyState(
                        searching: _searching,
                        query: _searchController.text,
                      )
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
/// Spec §2: SettingsSlider-style scrollable tab strip with sliding underline
/// indicator. 33px strip height, 9px horizontal padding, 14px semibold labels.
class _HorizontalFolderTabs extends StatefulWidget {
  final ChatState chatState;
  final int allUnread;

  const _HorizontalFolderTabs({required this.chatState, required this.allUnread});

  @override
  State<_HorizontalFolderTabs> createState() => _HorizontalFolderTabsState();
}

class _HorizontalFolderTabsState extends State<_HorizontalFolderTabs>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  // Drag reorder state (spec §2: drag threshold 10px, shift anim 150ms).
  // Uses raw Listener events to avoid gesture arena conflicts with the
  // SingleChildScrollView's HorizontalDragGestureRecognizer.
  int? _dragIndex; // tab index being dragged (null = not tracking)
  int? _dragPointer; // pointer ID we're tracking
  double _dragOffset = 0; // horizontal pixel offset of the dragged tab
  Offset? _dragStart; // pointer-down position to measure threshold
  bool _dragActive = false; // true once threshold exceeded

  final List<GlobalKey> _tabKeys = [];

  int get _tabCount => widget.chatState.folders.length + 1;

  int get _activeIndex {
    final id = widget.chatState.activeFolderId;
    if (id == null) return 0;
    final idx = widget.chatState.folders.indexWhere((f) => f.id == id);
    return idx < 0 ? 0 : idx + 1;
  }

  @override
  void initState() {
    super.initState();
    _syncTabKeys();
  }

  void _syncTabKeys() {
    while (_tabKeys.length < _tabCount) {
      _tabKeys.add(GlobalKey());
    }
    if (_tabKeys.length > _tabCount) {
      _tabKeys.removeRange(_tabCount, _tabKeys.length);
    }
  }

  @override
  void didUpdateWidget(covariant _HorizontalFolderTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTabKeys();
    if (_dragActive || _dragIndex != null) _cancelDrag();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_dragActive) return;
    if (index == 0) {
      widget.chatState.setActiveFolder(null);
    } else {
      final folders = widget.chatState.folders;
      if (index - 1 < folders.length) {
        widget.chatState.setActiveFolder(folders[index - 1].id);
      }
    }
  }

  // --- Drag reorder via raw Listener events ---

  /// Determine which tab index a global position falls on, or -1.
  int _hitTestTab(Offset globalPos) {
    for (var i = 0; i < _tabKeys.length; i++) {
      final box =
          _tabKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final local = box.globalToLocal(globalPos);
      if (box.size.contains(local)) return i;
    }
    return -1;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    final tabIdx = _hitTestTab(event.position);
    // Index 0 = "All Chats" — pinned, cannot be dragged (spec: addPinnedInterval)
    if (tabIdx <= 0) return;
    _dragPointer = event.pointer;
    _dragIndex = tabIdx;
    _dragStart = event.position;
    _dragOffset = 0;
    _dragActive = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragPointer != event.pointer || _dragIndex == null) return;
    final dx = event.position.dx - _dragStart!.dx;
    // Spec §2: drag threshold = 10px (startDragDistance)
    if (!_dragActive && dx.abs() < 10) return;
    if (!_dragActive) {
      _dragActive = true;
    }
    setState(() => _dragOffset = dx);
    _autoScrollDuringDrag(event.position);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_dragPointer != event.pointer) return;
    if (_dragActive && _dragIndex != null) {
      final targetIndex = _computeDropIndex();
      if (targetIndex != null && targetIndex != _dragIndex!) {
        final oldFolderIdx = _dragIndex! - 1;
        var newFolderIdx = targetIndex - 1;
        if (newFolderIdx < 0) newFolderIdx = 0;
        widget.chatState.reorderFolders(oldFolderIdx, newFolderIdx);
      }
    }
    _cancelDrag();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_dragPointer == event.pointer) _cancelDrag();
  }

  void _cancelDrag() {
    setState(() {
      _dragIndex = null;
      _dragPointer = null;
      _dragOffset = 0;
      _dragStart = null;
      _dragActive = false;
    });
  }

  int? _computeDropIndex() {
    if (_dragIndex == null) return null;
    final positions = <double>[];
    for (var i = 0; i < _tabKeys.length; i++) {
      final box =
          _tabKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return null;
      positions.add(box.localToGlobal(Offset(box.size.width / 2, 0)).dx);
    }
    final draggedBox =
        _tabKeys[_dragIndex!].currentContext?.findRenderObject() as RenderBox?;
    if (draggedBox == null) return null;
    final draggedCenter =
        draggedBox.localToGlobal(Offset(draggedBox.size.width / 2, 0)).dx +
            _dragOffset;
    // Find nearest valid slot (skip index 0 = pinned "All Chats")
    int target = _dragIndex!;
    for (var i = 1; i < positions.length; i++) {
      if (i == _dragIndex!) continue;
      if (i < _dragIndex! && draggedCenter < positions[i]) {
        target = i;
        break;
      }
      if (i > _dragIndex! && draggedCenter > positions[i]) {
        target = i;
      }
    }
    return target;
  }

  void _autoScrollDuringDrag(Offset globalPos) {
    if (!_scrollController.hasClients) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPos);
    final width = box.size.width;
    const edgeZone = 40.0;
    // Spec §2: kScrollFactor = 0.05
    const scrollFactor = 0.05;
    if (local.dx < edgeZone) {
      final dist = edgeZone - local.dx;
      _scrollController.jumpTo(
        (_scrollController.offset - dist * scrollFactor)
            .clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    } else if (local.dx > width - edgeZone) {
      final dist = local.dx - (width - edgeZone);
      _scrollController.jumpTo(
        (_scrollController.offset + dist * scrollFactor)
            .clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  /// Spec §2: redirect vertical mouse-wheel to horizontal scroll.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (event.scrollDelta.dx.abs() > 0 || event.scrollDelta.dy == 0) return;
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      position.jumpTo(
        (position.pixels + event.scrollDelta.dy).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
  }

  /// Compute how much a non-dragged tab should shift to make room.
  double _computeShiftForTab(int tabIndex) {
    if (_dragIndex == null || !_dragActive) return 0;
    final draggedBox =
        _tabKeys[_dragIndex!].currentContext?.findRenderObject() as RenderBox?;
    if (draggedBox == null) return 0;
    final draggedWidth = draggedBox.size.width;
    final draggedCenter =
        draggedBox.localToGlobal(Offset(draggedWidth / 2, 0)).dx + _dragOffset;
    final thisBox =
        _tabKeys[tabIndex].currentContext?.findRenderObject() as RenderBox?;
    if (thisBox == null) return 0;
    final thisCenter =
        thisBox.localToGlobal(Offset(thisBox.size.width / 2, 0)).dx;

    if (_dragIndex! < tabIndex && draggedCenter > thisCenter) {
      return -draggedWidth;
    }
    if (_dragIndex! > tabIndex && tabIndex > 0 && draggedCenter < thisCenter) {
      return draggedWidth;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final inactiveColor =
        isDark ? const Color(0xFF8A8A8A) : const Color(0xFF999999);
    final hoverColor =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    _syncTabKeys();
    final folders = widget.chatState.folders;
    final tabCount = _tabCount;

    // Freeze scroll while dragging so pointer events control the tab, not the
    // scroll view (spec: drag and scroll are mutually exclusive).
    final physics = _dragActive
        ? const NeverScrollableScrollPhysics()
        : const ClampingScrollPhysics();

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _handlePointerSignal,
      child: SizedBox(
        height: 33,
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: physics,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(tabCount, (i) {
                final isActive = i == _activeIndex;
                final isAllChats = i == 0;
                final folder = isAllChats ? null : folders[i - 1];
                final label = isAllChats ? 'All' : folder!.name;
                final unread = isAllChats
                    ? widget.allUnread
                    : widget.chatState.unreadCountForFolder(folder!.id);
                final isDragged = _dragActive && _dragIndex == i;
                double shiftX = 0;
                if (_dragActive && _dragIndex != null && i != _dragIndex!) {
                  shiftX = _computeShiftForTab(i);
                }

                return AnimatedContainer(
                  duration: _dragActive
                      ? const Duration(milliseconds: 150)
                      : Duration.zero,
                  transform: Matrix4.translationValues(
                    isDragged ? _dragOffset : shiftX, 0,
                    isDragged ? 1 : 0,
                  ),
                  child: _FolderTab(
                    key: _tabKeys[i],
                    label: label,
                    unread: unread,
                    isActive: isActive,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    hoverColor: hoverColor,
                    isDragged: isDragged,
                    onTap: () => _onTabTapped(i),
                    onSecondaryTapUp: (pos) =>
                        _showTabContextMenu(context, pos, folder),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  /// Spec §2: right-click context menu on folder tabs.
  void _showTabContextMenu(
      BuildContext context, Offset globalPosition, FolderInfo? folder) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final appState = context.read<AppState>();

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (folder != null) ...[
          const PopupMenuItem(value: 'edit', child: Text('Edit Folder')),
          const PopupMenuItem(value: 'delete', child: Text('Delete Folder')),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(value: 'setup', child: Text('Edit Folders')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'edit':
          // TODO: open folder editor when folder settings UI is built
          break;
        case 'delete':
          if (folder != null) {
            widget.chatState.deleteFolder(appState.activeAccountId, folder.id);
          }
        case 'setup':
          // TODO: open folder settings page when settings UI is built
          break;
      }
    });
  }
}

/// Individual folder tab widget.
class _FolderTab extends StatefulWidget {
  final String label;
  final int unread;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final Color hoverColor;
  final bool isDragged;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onSecondaryTapUp;

  const _FolderTab({
    super.key,
    required this.label,
    required this.unread,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.hoverColor,
    required this.isDragged,
    required this.onTap,
    required this.onSecondaryTapUp,
  });

  @override
  State<_FolderTab> createState() => _FolderTabState();
}

class _FolderTabState extends State<_FolderTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.isActive ? widget.activeColor : widget.inactiveColor;
    final bgColor = _hovered ? widget.hoverColor : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: (d) => widget.onSecondaryTapUp(d.globalPosition),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: widget.isDragged ? 0.7 : 1.0,
          child: Container(
            height: 33,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(color: bgColor),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        if (widget.unread > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF40A7E3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.unread > 999 ? '999+' : '${widget.unread}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Spec §2: 3px underline indicator with 2px top radius
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 3,
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? widget.activeColor
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(2),
                      topRight: Radius.circular(2),
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
}


/// Top Peers strip: horizontal scrollable row of 46px circular avatars.
/// Shown when search bar is focused but no query text entered (spec §2).
/// Uses DM chats sorted by recent activity as a proxy for top peers.
class _TopPeersStrip extends StatelessWidget {
  final List<ChatInfo> chats;
  final void Function(ChatInfo) onTap;

  const _TopPeersStrip({required this.chats, required this.onTap});

  static const _avatarSize = 46.0;
  static const _itemWidth = 66.0; // avatar + horizontal spacing
  static const _stripHeight = 90.0; // avatar + name + padding

  // 7 colors matching Telegram's peer color scheme.
  static const _avatarColors = [
    Color(0xFFe17076),
    Color(0xFF7bc862),
    Color(0xFFe5ca77),
    Color(0xFF65aadd),
    Color(0xFFa695e7),
    Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];

  @override
  Widget build(BuildContext context) {
    // Filter to DM chats only, sort by most recent message.
    final dmChats = chats
        .where((c) => c.type == ChatType.dm && !c.isArchived)
        .toList()
      ..sort((a, b) => b.lastMsgTime.compareTo(a.lastMsgTime));

    // Show up to 20 top peers.
    final topPeers = dmChats.take(20).toList();
    if (topPeers.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nameColor = isDark ? const Color(0xFF8A8A8A) : const Color(0xFF999999);

    return SizedBox(
      height: _stripHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        itemCount: topPeers.length,
        itemBuilder: (context, index) {
          final chat = topPeers[index];
          final colorIndex = chat.chatId.hashCode.abs() % 7;
          final color = _avatarColors[colorIndex];
          final initials = _initials(chat.title);
          final firstName = chat.title.split(RegExp(r'\s+')).first;

          return GestureDetector(
            onTap: () => onTap(chat),
            child: SizedBox(
              width: _itemWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  // Avatar
                  SizedBox(
                    width: _avatarSize,
                    height: _avatarSize,
                    child: chat.avatarPath.isNotEmpty
                        ? ClipOval(
                            child: Image.file(
                              File(chat.avatarPath),
                              width: _avatarSize,
                              height: _avatarSize,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _fallbackAvatar(color, initials),
                            ),
                          )
                        : _fallbackAvatar(color, initials),
                  ),
                  const SizedBox(height: 6),
                  // Name (first name only, truncated)
                  SizedBox(
                    width: _itemWidth - 4,
                    child: Text(
                      firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: nameColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fallbackAvatar(Color color, String initials) {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: _avatarSize * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _initials(String title) {
    final t = title.trim();
    if (t.isEmpty) return '?';
    final words = t.split(RegExp(r'\s+'));
    if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return t[0].toUpperCase();
  }
}

/// Recent Contacts list: vertical list of recent DM contacts shown below the
/// Top Peers strip when search bar is focused with no query (spec §2.2).
/// Rows: 56px height, 42px avatar at (16,7), name at (74,9), status at (74,30).
class _RecentContactsList extends StatelessWidget {
  final List<ChatInfo> chats;
  final void Function(ChatInfo) onTap;
  final ChatState chatState;

  const _RecentContactsList({
    required this.chats,
    required this.onTap,
    required this.chatState,
  });

  static const _rowHeight = 56.0;
  static const _avatarSize = 42.0;

  static const _avatarColors = [
    Color(0xFFe17076),
    Color(0xFF7bc862),
    Color(0xFFe5ca77),
    Color(0xFF65aadd),
    Color(0xFFa695e7),
    Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];

  @override
  Widget build(BuildContext context) {
    final dmChats = chats
        .where((c) => c.type == ChatType.dm && !c.isArchived)
        .toList()
      ..sort((a, b) => b.lastMsgTime.compareTo(a.lastMsgTime));
    final recent = dmChats.take(30).toList();
    if (recent.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nameFg = isDark ? const Color(0xFFe0e0e0) : const Color(0xFF222222);
    final statusFg =
        isDark ? const Color(0xFF8a8a8a) : const Color(0xFF999999);
    final hoverBg =
        isDark ? const Color(0xFF202b36) : const Color(0xFFf1f1f1);

    return ListView.builder(
      itemCount: recent.length,
      itemExtent: _rowHeight,
      itemBuilder: (context, index) {
        final chat = recent[index];
        final colorIndex = chat.chatId.hashCode.abs() % 7;
        final color = _avatarColors[colorIndex];
        final initials = _initials(chat.title);
        final isOnline = chatState.isChatOnline(chat);

        return _RecentContactRow(
          chat: chat,
          avatarColor: color,
          initials: initials,
          isOnline: isOnline,
          nameFg: nameFg,
          statusFg: statusFg,
          hoverBg: hoverBg,
          onTap: () => onTap(chat),
        );
      },
    );
  }

  static String _initials(String title) {
    final t = title.trim();
    if (t.isEmpty) return '?';
    final words = t.split(RegExp(r'\s+'));
    if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return t[0].toUpperCase();
  }
}

class _RecentContactRow extends StatefulWidget {
  final ChatInfo chat;
  final Color avatarColor;
  final String initials;
  final bool isOnline;
  final Color nameFg;
  final Color statusFg;
  final Color hoverBg;
  final VoidCallback onTap;

  const _RecentContactRow({
    required this.chat,
    required this.avatarColor,
    required this.initials,
    required this.isOnline,
    required this.nameFg,
    required this.statusFg,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  State<_RecentContactRow> createState() => _RecentContactRowState();
}

class _RecentContactRowState extends State<_RecentContactRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: _RecentContactsList._rowHeight,
          color: _hovered ? widget.hoverBg : Colors.transparent,
          child: Stack(
            children: [
              // Avatar at (16, 7)
              Positioned(
                left: 16,
                top: 7,
                child: SizedBox(
                  width: _RecentContactsList._avatarSize,
                  height: _RecentContactsList._avatarSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      widget.chat.avatarPath.isNotEmpty
                          ? ClipOval(
                              child: Image.file(
                                File(widget.chat.avatarPath),
                                width: _RecentContactsList._avatarSize,
                                height: _RecentContactsList._avatarSize,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _fallbackAvatar(),
                              ),
                            )
                          : _fallbackAvatar(),
                      if (widget.isOnline)
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4dc920),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _hovered
                                    ? widget.hoverBg
                                    : surfaceColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Name at (74, 9)
              Positioned(
                left: 74,
                top: 9,
                right: 16,
                child: Text(
                  widget.chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.nameFg,
                  ),
                ),
              ),
              // Status at (74, 30)
              Positioned(
                left: 74,
                top: 30,
                right: 16,
                child: Text(
                  widget.isOnline ? 'online' : 'last seen recently',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isOnline
                        ? const Color(0xFF4dc920)
                        : widget.statusFg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      width: _RecentContactsList._avatarSize,
      height: _RecentContactsList._avatarSize,
      decoration: BoxDecoration(
        color: widget.avatarColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        widget.initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: _RecentContactsList._avatarSize * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Search-mode tabs strip: "My Messages", "Public Posts", "This Peer".
/// Spec §2.2: segmented slider, 33px strip height, 9px horizontal padding,
/// 14px semibold labels, 6px underline indicator at barTop 30px.
class _SearchTabsStrip extends StatelessWidget {
  final _SearchTab activeTab;
  final ValueChanged<_SearchTab> onTabChanged;

  const _SearchTabsStrip({
    required this.activeTab,
    required this.onTabChanged,
  });

  static const _tabs = [
    (tab: _SearchTab.myMessages, label: 'My Messages'),
    (tab: _SearchTab.publicPosts, label: 'Public Posts'),
    (tab: _SearchTab.thisPeer, label: 'This Peer'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec: inactive fg = windowSubTextFg, active fg = lightButtonFg (blue).
    final activeFg =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final inactiveFg =
        isDark ? const Color(0xFF8A8A8A) : const Color(0xFF999999);
    // Spec §2.2: rippleBg = windowBgOver (inactive), rippleBgActive = lightButtonBgOver (active).
    final hoverInactive =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final splashInactive =
        isDark ? const Color(0xFF24303D) : const Color(0xFFE5E5E5);
    final hoverActive =
        isDark ? const Color(0xFF1D2A39) : const Color(0xFFE3F1FA);
    final splashActive =
        isDark ? const Color(0xFF223143) : const Color(0xFFC9E4F6);

    return SizedBox(
      height: 33,
      child: Row(
        children: [
          for (final entry in _tabs)
            Expanded(
              child: _SearchTabItem(
                label: entry.label,
                isActive: activeTab == entry.tab,
                activeFg: activeFg,
                inactiveFg: inactiveFg,
                hoverColor: activeTab == entry.tab
                    ? hoverActive
                    : hoverInactive,
                splashColor: activeTab == entry.tab
                    ? splashActive
                    : splashInactive,
                onTap: () => onTabChanged(entry.tab),
              ),
            ),
        ],
      ),
    );
  }
}

/// Individual search tab item with underline indicator and Material ripple.
/// Spec §2.2: rippleBg = windowBgOver (inactive), rippleBgActive = lightButtonBgOver (active).
class _SearchTabItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeFg;
  final Color inactiveFg;
  final Color hoverColor;
  final Color splashColor;
  final VoidCallback onTap;

  const _SearchTabItem({
    required this.label,
    required this.isActive,
    required this.activeFg,
    required this.inactiveFg,
    required this.hoverColor,
    required this.splashColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isActive ? activeFg : inactiveFg;
    final textStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: textColor,
    );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        splashColor: splashColor,
        highlightColor: splashColor.withValues(alpha: 0.3),
        child: SizedBox(
          height: 33,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tp = TextPainter(
                  text: TextSpan(text: label, style: textStyle),
                  textDirection: TextDirection.ltr,
                )..layout();
                final labelWidth = tp.width;
                final leftOffset =
                    (constraints.maxWidth - labelWidth) / 2;

                return Stack(
                  children: [
                    Positioned(
                      top: 7,
                      left: 0,
                      right: 0,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: textStyle,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: leftOffset,
                      width: labelWidth,
                      height: 3,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isActive
                              ? activeFg
                              : Colors.transparent,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(2),
                            topRight: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Sub-filter row for "My Messages" tab (spec §2.2: ChatSearchIn popup).
/// 38px-tall row with current filter label and dropdown arrow.
/// Tapping opens a popup menu with Private/Groups/Channels options.
class _SearchSubFilterRow extends StatelessWidget {
  final _MyMsgSubFilter activeFilter;
  final ValueChanged<_MyMsgSubFilter> onFilterChanged;

  const _SearchSubFilterRow({
    required this.activeFilter,
    required this.onFilterChanged,
  });

  static const _filters = [
    (filter: _MyMsgSubFilter.all, label: 'All Messages', icon: Icons.forum_outlined),
    (filter: _MyMsgSubFilter.private_, label: 'Private', icon: Icons.person_outline),
    (filter: _MyMsgSubFilter.groups, label: 'Groups', icon: Icons.group_outlined),
    (filter: _MyMsgSubFilter.channels, label: 'Channels', icon: Icons.campaign_outlined),
  ];

  String get _activeLabel =>
      _filters.firstWhere((f) => f.filter == activeFilter).label;

  IconData get _activeIcon =>
      _filters.firstWhere((f) => f.filter == activeFilter).icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec: normalFont color for the label.
    final labelColor =
        isDark ? const Color(0xFFCCCCCC) : const Color(0xFF555555);
    // Spec: dropdown arrow color.
    final arrowColor =
        isDark ? const Color(0xFF8A8A8A) : const Color(0xFF999999);
    // Spec: divider bar background.
    final dividerBg =
        isDark ? const Color(0xFF1D2A36) : const Color(0xFFF1F1F1);
    // Spec: hover bg = windowBgOver.
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Divider bar (spec §2.2: searchedBarHeight = 28px, normalFont, label left padding 14px).
        Container(
          height: 28,
          width: double.infinity,
          color: dividerBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 14),
          child: Text(
            'Search in',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: arrowColor,
            ),
          ),
        ),
        // Filter row (spec §2.2: dialogsSearchInHeight = 38px).
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _showFilterMenu(context),
            hoverColor: hoverBg,
            child: SizedBox(
              height: 38,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Row(
                  children: [
                    // Photo placeholder / icon (28px).
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        _activeIcon,
                        size: 20,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Filter label (spec: name top 9px — centered in 38px row).
                    Expanded(
                      child: Text(
                        _activeLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Dropdown arrow (spec: dropdown arrow top 15px).
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Icon(
                        Icons.arrow_drop_down,
                        size: 20,
                        color: arrowColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showFilterMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      button.localToGlobal(Offset(0, button.size.height)) &
          Size(button.size.width, 0),
      Offset.zero & overlay.size,
    );

    showMenu<_MyMsgSubFilter>(
      context: context,
      position: position,
      items: [
        for (final entry in _filters)
          PopupMenuItem<_MyMsgSubFilter>(
            value: entry.filter,
            child: Row(
              children: [
                Icon(entry.icon, size: 20),
                const SizedBox(width: 12),
                Text(entry.label),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value != null) {
        onFilterChanged(value);
      }
    });
  }
}

/// Empty state for chat list.
class _EmptyState extends StatelessWidget {
  final bool searching;
  final String query;

  /// Max chars to show in the "no results for ..." message before truncating.
  static const _kQueryPreviewLimit = 18;

  const _EmptyState({required this.searching, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    if (!searching) {
      // No chats loaded (non-search state).
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: subColor),
            const SizedBox(height: 12),
            Text(
              'No chats yet',
              style: theme.textTheme.bodyMedium?.copyWith(color: subColor),
            ),
          ],
        ),
      );
    }

    // Search empty state (spec §35.7.2): noresults Lottie 100px + text.
    final displayQuery = query.length > _kQueryPreviewLimit
        ? '${query.substring(0, _kQueryPreviewLimit)}…'
        : query;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Spec: icon at 1/3 of available height; min widget height 220px.
        final topPad = (constraints.maxHeight / 3) - 50; // 50 = half of 100px icon
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 220),
            child: Padding(
              padding: const EdgeInsets.all(10), // recentPeersEmptyMargin
              child: Column(
                children: [
                  SizedBox(height: topPad.clamp(10.0, double.infinity)),
                  // 100x100 Lottie animation (spec: recentPeersEmptySize).
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Lottie.asset(
                      'assets/animations/noresults.json',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 10), // recentPeersEmptySkip
                  Text(
                    'No Results',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: subColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'There were no results\nfor "$displayQuery".',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
