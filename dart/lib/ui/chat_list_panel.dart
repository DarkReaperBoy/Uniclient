import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'chat_list_row.dart';
import 'popup_menu.dart';
import 'confirm_box.dart';

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

class _ChatListPanelState extends State<ChatListPanel>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;
  bool _showArchived = false;
  List<ChatInfo> _loadedArchivedChats = []; // on-demand archived chats
  List<ChatInfo>? _searchResults;
  _SearchTab _activeSearchTab = _SearchTab.myMessages;
  _MyMsgSubFilter _myMsgSubFilter = _MyMsgSubFilter.all;
  late final AnimationController _archiveAnimCtrl;
  late final Animation<double> _archiveAnim;

  // ── Drag-to-reorder pinned chats (spec §2.7) ──
  static const _kReorderThreshold = 30.0; // kStartReorderThreshold
  static const _kChatRowHeight = 62.0;
  final ScrollController _chatListScrollCtrl = ScrollController();
  final GlobalKey _chatListKey = GlobalKey();
  int? _reorderPinnedIdx; // 0-based index within pinned items
  int? _reorderPointer;
  Offset? _reorderStartPos;
  bool _reorderActive = false;
  double _reorderOffsetY = 0;
  OverlayEntry? _reorderOverlay;
  final List<GlobalKey> _pinnedRowKeys = [];
  // Cached during build for pointer handlers:
  List<ChatInfo> _buildNonArchived = [];
  int _buildPinnedCount = 0;

  // ── Drag-and-drop forwarding (spec §2.7) ──
  /// Chat ID currently hovered during a forward drag.
  String? _forwardHoveredChatId;
  /// Auto-select timer: opens the hovered chat after 2s hover (kFreezeTimeout).
  Timer? _forwardHoverTimer;

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
    _archiveAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _archiveAnim = CurvedAnimation(
      parent: _archiveAnimCtrl,
      curve: Curves.easeInOut,
    );
    _archiveAnimCtrl.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _showArchived) {
        setState(() => _showArchived = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().onShowArchiveRequested = () {
        if (mounted && !_showArchived) _toggleArchived();
      };
    });
  }

  void _toggleArchived() {
    if (!_showArchived) {
      // Load archived chats on-demand from engine.
      final engine = context.read<EngineService>();
      _loadedArchivedChats = engine.getChatList(archived: true, limit: 500);
      setState(() => _showArchived = true);
      _archiveAnimCtrl.forward();
    } else if (!_archiveAnimCtrl.isAnimating) {
      _archiveAnimCtrl.reverse();
    }
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
    final appState = context.read<AppState>();
    if (appState.onShowArchiveRequested != null) {
      appState.onShowArchiveRequested = null;
    }
    _archiveAnimCtrl.dispose();
    _chatListScrollCtrl.dispose();
    _reorderOverlay?.remove();
    _reorderOverlay = null;
    _forwardHoverTimer?.cancel();
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

    // Separate archived chats — use on-demand loaded list if inline is empty.
    var archived = sorted.where((c) => c.isArchived).toList();
    final nonArchived = sorted.where((c) => !c.isArchived).toList();
    if (archived.isEmpty && _loadedArchivedChats.isNotEmpty) {
      archived = _loadedArchivedChats;
    }
    final hasArchived = archived.isNotEmpty || chatState.hasArchivedChats;
    // Don't show archived row when displaying search results (spec §2.2).
    final showArchiveRow = hasArchived && !(_searching && _searchController.text.isNotEmpty);
    final archivedUnread = archived.fold(0, (sum, c) => sum + c.unreadCount);

    // Spec §2.7: Apply custom pinned chat order (drag-to-reorder).
    final pinnedCount = nonArchived.where((c) => c.isPinned).length;
    if (!_searching && pinnedCount > 1) {
      chatState.ensurePinnedOrder(appState.activeAccountId);
      final pinnedOrder = chatState.pinnedChatOrder(appState.activeAccountId);
      if (pinnedOrder != null) {
        final pinnedSlice = nonArchived.sublist(0, pinnedCount);
        pinnedSlice.sort((a, b) {
          final ai = pinnedOrder.indexOf(a.chatId);
          final bi = pinnedOrder.indexOf(b.chatId);
          return (ai < 0 ? 999 : ai).compareTo(bi < 0 ? 999 : bi);
        });
        for (var i = 0; i < pinnedCount; i++) {
          nonArchived[i] = pinnedSlice[i];
        }
      }
    }

    // Sync pinned row keys and cache build data for drag handlers.
    _syncPinnedKeys(pinnedCount);
    _buildNonArchived = nonArchived;
    _buildPinnedCount = pinnedCount;
    final pinnedStartInVisible =
        _showArchived && hasArchived ? archived.length : 0;

    // Build the display list: archived row + (optionally expanded archived chats) + non-archived.
    final List<ChatInfo> visibleChats;
    if (_showArchived && hasArchived) {
      visibleChats = [...archived, ...nonArchived];
    } else {
      visibleChats = nonArchived;
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Spec §1: Hide search bar and folder tabs in collapsed avatar-only mode.
          if (!widget.collapsed) ...[
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
          ],
          // Chat list / Recent Contacts (spec §2.2: recent contacts shown
          // when search focused with empty query, below Top Peers strip).
          Expanded(
            child: _searching && _searchController.text.isEmpty
                ? _RecentContactsList(
                    chats: accountChats,
                    onTap: (chat) => chatState.openChat(chat),
                    chatState: chatState,
                  )
                : visibleChats.isEmpty && !showArchiveRow
                    ? _EmptyState(
                        searching: _searching,
                        query: _searchController.text,
                      )
                    : Listener(
                        onPointerDown: _onReorderPointerDown,
                        onPointerMove: _onReorderPointerMove,
                        onPointerUp: _onReorderPointerUp,
                        onPointerCancel: _onReorderPointerCancel,
                        child: ListView.builder(
                          key: _chatListKey,
                          controller: _chatListScrollCtrl,
                          itemCount: visibleChats.length + (showArchiveRow ? 1 : 0),
                          itemBuilder: (context, index) {
                            // First item: Archived Chats row (37px, spec §2.5).
                            if (showArchiveRow && index == 0) {
                              return _ArchivedChatsRow(
                                unreadCount: archivedUnread,
                                isNarrow: widget.collapsed,
                                isExpanded: _showArchived,
                                onTap: _toggleArchived,
                                archivedChats: archived,
                              );
                            }
                            final chatIndex = showArchiveRow ? index - 1 : index;
                            final chat = visibleChats[chatIndex];
                            final isActive =
                                chatState.activeChat?.chatId == chat.chatId &&
                                chatState.activeChat?.accountId == chat.accountId;

                            // Determine if this is a reorderable pinned chat.
                            final pinnedIdx = chat.isPinned && !chat.isArchived
                                ? chatIndex - pinnedStartInVisible
                                : -1;
                            final isPinnedReorderable =
                                pinnedIdx >= 0 && pinnedIdx < pinnedCount;

                            // Spec §2.7: Resolve swipe action based on config + chat state.
                            final swipeAction = resolveSwipeAction(
                                appState.swipeAction, chat);

                            // Spec §2.7: Forward-drag hover state for this row.
                            final isForwardHovered =
                                _forwardHoveredChatId == chat.chatId;

                            // During active reorder: skip SwipeableChatRow wrapper for pinned items.
                            Widget row;
                            if (_reorderActive && isPinnedReorderable) {
                              row = ChatListRow(
                                chat: chat,
                                isActive: isActive,
                                isOnline: chatState.isChatOnline(chat),
                                isNarrow: widget.collapsed,
                                typingUser: chatState.typingUserFor(chat.chatId),
                                onTap: () => chatState.openChat(chat),
                                onSecondaryTap: (pos) =>
                                    _showChatContextMenu(context, chat, pos),
                                isForwardHovered: isForwardHovered,
                              );
                            } else {
                              row = SwipeableChatRow(
                                action: swipeAction,
                                onAction: () => _performSwipeAction(
                                    context, swipeAction, chat),
                                child: ChatListRow(
                                  chat: chat,
                                  isActive: isActive,
                                  isOnline: chatState.isChatOnline(chat),
                                  isNarrow: widget.collapsed,
                                  typingUser: chatState.typingUserFor(chat.chatId),
                                  onTap: () => chatState.openChat(chat),
                                  onSecondaryTap: (pos) =>
                                      _showChatContextMenu(context, chat, pos),
                                  isForwardHovered: isForwardHovered,
                                ),
                              );
                            }

                            // Spec §2.7: Wrap row in DragTarget for forward drops.
                            // Capture inner widget before reassigning `row`.
                            final innerRow = row;
                            row = DragTarget<ForwardDragData>(
                              onWillAcceptWithDetails: (details) {
                                // Don't accept drop on the source chat itself.
                                return details.data.sourceChatId != chat.chatId;
                              },
                              onAcceptWithDetails: (details) {
                                _forwardHoverTimer?.cancel();
                                setState(() => _forwardHoveredChatId = null);
                                chatState.forwardMessages(
                                  details.data.messageIds,
                                  chat.chatId,
                                );
                                _showTelegramToast(
                                    context, 'Messages forwarded.');
                              },
                              onMove: (details) {
                                if (_forwardHoveredChatId != chat.chatId) {
                                  _forwardHoverTimer?.cancel();
                                  setState(() =>
                                      _forwardHoveredChatId = chat.chatId);
                                  // Spec §2.7: Auto-select on hover after
                                  // kFreezeTimeout (2000ms).
                                  _forwardHoverTimer = Timer(
                                    const Duration(milliseconds: 2000),
                                    () {
                                      if (mounted &&
                                          _forwardHoveredChatId ==
                                              chat.chatId) {
                                        chatState.openChat(chat);
                                      }
                                    },
                                  );
                                }
                              },
                              onLeave: (_) {
                                if (_forwardHoveredChatId == chat.chatId) {
                                  _forwardHoverTimer?.cancel();
                                  setState(() =>
                                      _forwardHoveredChatId = null);
                                }
                              },
                              builder: (context, candidateData, rejectedData) =>
                                  innerRow,
                            );

                            // Pinned row drag visuals.
                            if (isPinnedReorderable) {
                              if (_reorderActive &&
                                  pinnedIdx == _reorderPinnedIdx) {
                                // Dragged item: invisible (overlay shows floating copy).
                                row = Opacity(opacity: 0.0, child: row);
                              } else if (_reorderActive) {
                                // Non-dragged pinned: animate shift (sineInOut, spec §2.7).
                                final shift =
                                    _computeShiftForPinnedRow(pinnedIdx);
                                row = AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOutSine,
                                  transform:
                                      Matrix4.translationValues(0, shift, 0),
                                  child: row,
                                );
                              }
                              row = KeyedSubtree(
                                key: _pinnedRowKeys[pinnedIdx],
                                child: row,
                              );
                            }

                            // Archived chats animate expand/collapse ~200ms (spec §2.5).
                            if (_showArchived &&
                                showArchiveRow &&
                                chatIndex < archived.length) {
                              return SizeTransition(
                                sizeFactor: _archiveAnim,
                                axisAlignment: -1.0,
                                child: row,
                              );
                            }
                            return row;
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _performSwipeAction(
      BuildContext context, SwipeAction action, ChatInfo chat) {
    final chatState = context.read<ChatState>();
    switch (action) {
      case SwipeAction.mute:
        chatState.muteChat(chat.accountId, chat.chatId, true);
      case SwipeAction.unmute:
        chatState.muteChat(chat.accountId, chat.chatId, false);
      case SwipeAction.pin:
        chatState.pinChat(chat.accountId, chat.chatId, true);
      case SwipeAction.unpin:
        chatState.pinChat(chat.accountId, chat.chatId, false);
      case SwipeAction.read:
        chatState.markRead();
      case SwipeAction.unread:
        chatState.markRead();
      case SwipeAction.archive:
        chatState.archiveChat(chat.accountId, chat.chatId, true);
      case SwipeAction.unarchive:
        chatState.archiveChat(chat.accountId, chat.chatId, false);
      case SwipeAction.delete:
        if (context.mounted) {
          final cs = context.read<ChatState>();
          showDeleteConfirmBox(
            context,
            mode: DeleteBoxMode.leaveChat,
            chatType: chat.type,
            peerName: chat.title,
            canRevoke: chat.type == ChatType.dm,
          ).then((r) {
            if (!r.confirmed) return;
            if (chat.type == ChatType.dm) {
              cs.deleteChat(chat.accountId, chat.chatId);
            } else {
              cs.leaveChat(chat.accountId, chat.chatId);
            }
          });
        }
      case SwipeAction.disabled:
        break;
    }
    // Spec §2.7: Completion toast notification after swipe action commits.
    final toastText = _swipeActionToastText(action);
    if (toastText != null) {
      _showTelegramToast(context, toastText);
    }
  }

  /// Spec §2.7: Toast text for each swipe action, matching Telegram Desktop's
  /// lng_quick_dialog_action_toast_{action}_success localization keys.
  /// Returns null for actions that don't show a toast (delete, disabled).
  static String? _swipeActionToastText(SwipeAction action) {
    return switch (action) {
      SwipeAction.mute => 'Notifications muted.',
      SwipeAction.unmute => 'Notifications unmuted.',
      SwipeAction.pin => 'Chat pinned.',
      SwipeAction.unpin => 'Chat unpinned.',
      SwipeAction.read => 'Chat marked as read.',
      SwipeAction.unread => 'Chat marked as unread.',
      SwipeAction.archive => 'Chat archived.',
      SwipeAction.unarchive => 'Chat unarchived.',
      SwipeAction.delete => null,
      SwipeAction.disabled => null,
    };
  }

  /// Telegram Desktop-style toast overlay (spec §2.7, toast spec §16.10).
  /// toastBg (#000000b2) background, toastFg (#ffffff) text, 6px radius.
  /// Duration: 1500ms hold, 200ms fade-in, 1000ms fade-out.
  static void _showTelegramToast(BuildContext context, String text) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TelegramToast(
        text: text,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  // ── Drag-to-reorder pinned chats (spec §2.7) ──

  void _syncPinnedKeys(int count) {
    while (_pinnedRowKeys.length < count) {
      _pinnedRowKeys.add(GlobalKey());
    }
    if (_pinnedRowKeys.length > count) {
      _pinnedRowKeys.removeRange(count, _pinnedRowKeys.length);
    }
  }

  void _onReorderPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton || _searching || _reorderActive) return;
    if (_buildPinnedCount < 2) return;
    for (var i = 0; i < _pinnedRowKeys.length && i < _buildPinnedCount; i++) {
      final box =
          _pinnedRowKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final local = box.globalToLocal(event.position);
      if (box.size.contains(local)) {
        _reorderPointer = event.pointer;
        _reorderPinnedIdx = i;
        _reorderStartPos = event.position;
        _reorderOffsetY = 0;
        return;
      }
    }
  }

  void _onReorderPointerMove(PointerMoveEvent event) {
    if (_reorderPointer != event.pointer || _reorderPinnedIdx == null) return;

    final dy = event.position.dy - _reorderStartPos!.dy;

    if (!_reorderActive) {
      final dx = (event.position.dx - _reorderStartPos!.dx).abs();
      // Horizontal movement wins → swipe gesture, cancel reorder tracking.
      if (dx > 10 && dx > dy.abs()) {
        _reorderPinnedIdx = null;
        _reorderPointer = null;
        return;
      }
      if (dy.abs() >= _kReorderThreshold) {
        _reorderActive = true;
        _createReorderOverlay();
        setState(() {});
      }
      return;
    }

    setState(() => _reorderOffsetY = dy);
    _reorderOverlay?.markNeedsBuild();
    _autoScrollDuringReorder(event.position);
  }

  void _onReorderPointerUp(PointerUpEvent event) {
    if (_reorderPointer != event.pointer) return;
    if (_reorderActive && _reorderPinnedIdx != null) {
      final target = _computeReorderTarget();
      if (target != null && target != _reorderPinnedIdx!) {
        final chatState = context.read<ChatState>();
        final appState = context.read<AppState>();
        chatState.reorderPinnedChats(
            appState.activeAccountId, _reorderPinnedIdx!, target);
      }
    }
    _cancelReorder();
  }

  void _onReorderPointerCancel(PointerCancelEvent event) {
    if (_reorderPointer == event.pointer) _cancelReorder();
  }

  void _cancelReorder() {
    _reorderOverlay?.remove();
    _reorderOverlay = null;
    setState(() {
      _reorderPinnedIdx = null;
      _reorderPointer = null;
      _reorderStartPos = null;
      _reorderActive = false;
      _reorderOffsetY = 0;
    });
  }

  void _createReorderOverlay() {
    final idx = _reorderPinnedIdx!;
    if (idx >= _buildPinnedCount || idx >= _buildNonArchived.length) return;
    final box =
        _pinnedRowKeys[idx].currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final startPos = box.localToGlobal(Offset.zero);
    final startSize = box.size;
    final chat = _buildNonArchived[idx];
    final chatState = context.read<ChatState>();
    final theme = Theme.of(context);
    final isActive = chatState.activeChat?.chatId == chat.chatId &&
        chatState.activeChat?.accountId == chat.accountId;
    final isOnline = chatState.isChatOnline(chat);
    final typingUser = chatState.typingUserFor(chat.chatId);

    _reorderOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: startPos.dx,
        top: startPos.dy + _reorderOffsetY,
        width: startSize.width,
        height: startSize.height,
        child: IgnorePointer(
          child: Theme(
            data: theme,
            child: Material(
              elevation: 8,
              shadowColor: Colors.black45,
              child: ChatListRow(
                chat: chat,
                isActive: isActive,
                isOnline: isOnline,
                isNarrow: widget.collapsed,
                typingUser: typingUser,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_reorderOverlay!);
  }

  int? _computeReorderTarget() {
    if (_reorderPinnedIdx == null || _buildPinnedCount < 2) return null;
    final slots = (_reorderOffsetY / _kChatRowHeight).round();
    return (_reorderPinnedIdx! + slots).clamp(0, _buildPinnedCount - 1);
  }

  double _computeShiftForPinnedRow(int pinnedIdx) {
    if (!_reorderActive || _reorderPinnedIdx == null) return 0;
    final target = _computeReorderTarget() ?? _reorderPinnedIdx!;
    final from = _reorderPinnedIdx!;
    if (from < target) {
      // Dragged downward: items between old..new shift up.
      if (pinnedIdx > from && pinnedIdx <= target) return -_kChatRowHeight;
    } else if (from > target) {
      // Dragged upward: items between new..old shift down.
      if (pinnedIdx >= target && pinnedIdx < from) return _kChatRowHeight;
    }
    return 0;
  }

  void _autoScrollDuringReorder(Offset globalPos) {
    if (!_chatListScrollCtrl.hasClients) return;
    final listBox =
        _chatListKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;
    final localY = listBox.globalToLocal(globalPos).dy;
    final height = listBox.size.height;
    const edgeZone = 50.0;
    const scrollFactor = 0.05;
    final pos = _chatListScrollCtrl.position;
    if (localY > height - edgeZone) {
      final dist = localY - (height - edgeZone);
      pos.jumpTo((pos.pixels + dist * scrollFactor)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent));
    } else if (localY < edgeZone) {
      final dist = edgeZone - localY;
      pos.jumpTo((pos.pixels - dist * scrollFactor)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent));
    }
  }

  void _showChatContextMenu(BuildContext context, ChatInfo chat, Offset globalPosition) {
    final chatState = context.read<ChatState>();
    final isGroupy = chat.type == ChatType.group ||
        chat.type == ChatType.channel ||
        chat.type == ChatType.topic;

    final isDm = chat.type == ChatType.dm;

    showTelegramMenu<String>(
      context: context,
      position: globalPosition,
      items: [
        TelegramMenuItem(value: 'pin', label: chat.isPinned ? 'Unpin' : 'Pin'),
        TelegramMenuItem(
          value: 'mute_submenu',
          label: chat.isMuted ? 'Unmute' : 'Mute',
          icon: Icon(chat.isMuted ? Icons.notifications : Icons.notifications_off),
        ),
        TelegramMenuItem(
          value: 'read',
          label: chat.unreadCount > 0 ? 'Mark as Read' : 'Mark as Unread',
        ),
        TelegramMenuItem(value: 'archive', label: chat.isArchived ? 'Unarchive' : 'Archive'),
        const TelegramMenuItem.separator(),
        const TelegramMenuItem(value: 'clear_history', label: 'Clear History'),
        if (isDm)
          const TelegramMenuItem(value: 'delete_chat', label: 'Delete Chat', isAttention: true),
        if (isGroupy)
          TelegramMenuItem(
            value: 'leave',
            label: chat.type == ChatType.channel ? 'Leave Channel' : 'Leave Chat',
            isAttention: true,
          ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'pin':
          chatState.pinChat(chat.accountId, chat.chatId, !chat.isPinned);
        case 'mute_submenu':
          if (chat.isMuted) {
            chatState.muteChat(chat.accountId, chat.chatId, false);
          } else {
            Future.delayed(const Duration(milliseconds: 200), () {
              if (context.mounted) {
                _showMuteSubmenu(context, chat, globalPosition);
              }
            });
          }
        case 'read':
          if (chat.unreadCount > 0) {
            chatState.markChatRead(chat.accountId, chat.chatId);
          }
        case 'archive':
          chatState.archiveChat(chat.accountId, chat.chatId, !chat.isArchived);
        case 'clear_history':
          if (context.mounted) {
            final chatState2 = context.read<ChatState>();
            showDeleteConfirmBox(
              context,
              mode: DeleteBoxMode.clearHistory,
              chatType: chat.type,
              peerName: chat.title,
              isSavedMessages: chat.title == 'Saved Messages',
            ).then((r) {
              if (r.confirmed) chatState2.clearHistory(chat.accountId, chat.chatId);
            });
          }
        case 'delete_chat':
          if (context.mounted) {
            final chatState2 = context.read<ChatState>();
            showDeleteConfirmBox(
              context,
              mode: DeleteBoxMode.leaveChat,
              chatType: chat.type,
              peerName: chat.title,
              canRevoke: chat.type == ChatType.dm,
            ).then((r) {
              if (r.confirmed) chatState2.deleteChat(chat.accountId, chat.chatId);
            });
          }
        case 'leave':
          if (context.mounted) {
            final chatState2 = context.read<ChatState>();
            showDeleteConfirmBox(
              context,
              mode: DeleteBoxMode.leaveChat,
              chatType: chat.type,
              peerName: chat.title,
            ).then((r) {
              if (r.confirmed) chatState2.leaveChat(chat.accountId, chat.chatId);
            });
          }
      }
    });
  }

  void _showMuteSubmenu(BuildContext context, ChatInfo chat, Offset globalPosition) {
    final chatState = context.read<ChatState>();

    showTelegramMenu<String>(
      context: context,
      position: globalPosition,
      items: [
        if (!chat.isMuted) ...[
          const TelegramMenuItem(
            value: 'mute_1h',
            icon: Icon(Icons.access_time),
            label: 'Mute for 1 hour',
          ),
          const TelegramMenuItem(
            value: 'mute_8h',
            icon: Icon(Icons.access_time),
            label: 'Mute for 8 hours',
          ),
          const TelegramMenuItem(
            value: 'mute_2d',
            icon: Icon(Icons.access_time),
            label: 'Mute for 2 days',
          ),
          const TelegramMenuItem(
            value: 'mute_custom',
            icon: Icon(Icons.timer),
            label: 'Mute for...',
          ),
          const TelegramMenuItem.separator(),
          const TelegramMenuItem(
            value: 'mute_forever',
            icon: Icon(Icons.notifications_off),
            label: 'Mute forever',
            isAttention: true,
          ),
        ] else ...[
          const TelegramMenuItem(
            value: 'unmute',
            icon: Icon(Icons.notifications),
            label: 'Unmute',
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'mute_1h':
          chatState.muteChat(chat.accountId, chat.chatId, true, durationSeconds: 3600);
        case 'mute_8h':
          chatState.muteChat(chat.accountId, chat.chatId, true, durationSeconds: 28800);
        case 'mute_2d':
          chatState.muteChat(chat.accountId, chat.chatId, true, durationSeconds: 172800);
        case 'mute_custom':
          _showMuteDurationPicker(context, chat);
        case 'mute_forever':
          chatState.muteChat(chat.accountId, chat.chatId, true);
        case 'unmute':
          chatState.muteChat(chat.accountId, chat.chatId, false);
      }
    });
  }

  void _showMuteDurationPicker(BuildContext context, ChatInfo chat) {
    final chatState = context.read<ChatState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog<int>(
      context: context,
      builder: (ctx) {
        int selectedIndex = 6; // default: 8h
        final durations = <(String, int)>[
          ('15 minutes', 900),
          ('30 minutes', 1800),
          ('1 hour', 3600),
          ('2 hours', 7200),
          ('3 hours', 10800),
          ('4 hours', 14400),
          ('8 hours', 28800),
          ('12 hours', 43200),
          ('1 day', 86400),
          ('2 days', 172800),
          ('3 days', 259200),
          ('1 week', 604800),
          ('2 weeks', 1209600),
          ('1 month', 2592000),
        ];

        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1e2c3a) : null,
              title: Text(
                'Mute for...',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : null,
                ),
              ),
              content: SizedBox(
                width: 280,
                height: 320,
                child: ListView.builder(
                  itemCount: durations.length,
                  itemBuilder: (ctx, i) {
                    final (label, _) = durations[i];
                    final isSelected = i == selectedIndex;
                    return RadioListTile<int>(
                      value: i,
                      groupValue: selectedIndex,
                      onChanged: (v) => setState(() => selectedIndex = v!),
                      title: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : null,
                        ),
                      ),
                      activeColor: const Color(0xFF40a7e3),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: isDark ? const Color(0xFF6c7883) : null)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(durations[selectedIndex].$2),
                  child: const Text('Mute', style: TextStyle(color: Color(0xFF40a7e3))),
                ),
              ],
            );
          },
        );
      },
    ).then((seconds) {
      if (seconds != null) {
        chatState.muteChat(chat.accountId, chat.chatId, true, durationSeconds: seconds);
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
  final List<GlobalKey> _labelKeys = []; // for barSnapToLabel measurement

  // Sliding underline indicator (spec §2.1: barStroke 6px, barRadius 2px, barTop 30px)
  final GlobalKey _rowKey = GlobalKey();
  late final AnimationController _indicatorCtrl;
  late final CurvedAnimation _curvedIndicator;
  Tween<double> _leftTween = Tween(begin: 0, end: 0);
  Tween<double> _widthTween = Tween(begin: 0, end: 0);
  bool _indicatorInitialized = false;

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
    _indicatorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(() => setState(() {}));
    _curvedIndicator = CurvedAnimation(
      parent: _indicatorCtrl,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateIndicatorPosition(animate: false);
    });
  }

  void _syncTabKeys() {
    while (_tabKeys.length < _tabCount) {
      _tabKeys.add(GlobalKey());
    }
    if (_tabKeys.length > _tabCount) {
      _tabKeys.removeRange(_tabCount, _tabKeys.length);
    }
    while (_labelKeys.length < _tabCount) {
      _labelKeys.add(GlobalKey());
    }
    if (_labelKeys.length > _tabCount) {
      _labelKeys.removeRange(_tabCount, _labelKeys.length);
    }
  }

  @override
  void didUpdateWidget(covariant _HorizontalFolderTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTabKeys();
    if (_dragActive || _dragIndex != null) _cancelDrag();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateIndicatorPosition(animate: _indicatorInitialized);
    });
  }

  @override
  void dispose() {
    _curvedIndicator.dispose();
    _indicatorCtrl.dispose();
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

  /// Update sliding indicator position. [animate] = false for initial snap.
  void _updateIndicatorPosition({bool animate = true}) {
    final ai = _activeIndex;
    if (ai < 0 || ai >= _labelKeys.length) return;
    final labelBox =
        _labelKeys[ai].currentContext?.findRenderObject() as RenderBox?;
    final rowBox = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (labelBox == null || rowBox == null) return;

    final labelOffset =
        labelBox.localToGlobal(Offset.zero) - rowBox.localToGlobal(Offset.zero);
    final targetLeft = labelOffset.dx;
    final targetWidth = labelBox.size.width;

    if (!animate || !_indicatorInitialized) {
      _leftTween = Tween(begin: targetLeft, end: targetLeft);
      _widthTween = Tween(begin: targetWidth, end: targetWidth);
      _indicatorCtrl.value = 1.0;
      _indicatorInitialized = true;
      return;
    }

    final curLeft = _leftTween.evaluate(_curvedIndicator);
    final curWidth = _widthTween.evaluate(_curvedIndicator);
    if ((curLeft - targetLeft).abs() < 0.5 &&
        (curWidth - targetWidth).abs() < 0.5) {
      return; // already at target
    }
    _leftTween = Tween(begin: curLeft, end: targetLeft);
    _widthTween = Tween(begin: curWidth, end: targetWidth);
    _indicatorCtrl.forward(from: 0);
  }

  /// Build the sliding underline indicator widget.
  Widget _buildIndicator(Color color) {
    final left = _leftTween.evaluate(_curvedIndicator);
    final width = _widthTween.evaluate(_curvedIndicator);
    if (width <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: 30, // barTop: 30px (spec §2.1)
      child: IgnorePointer(
        child: Container(
          width: width,
          height: 6, // barStroke: 6px
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2), // barRadius: 2px
          ),
        ),
      ),
    );
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
    // Spec §2.1: inactive fg = windowSubTextFg, active fg = lightButtonFg
    final activeColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final inactiveColor =
        isDark ? const Color(0xFF8A8A8A) : const Color(0xFF999999);
    // Spec §2.1: hover ripple = windowBgOver (inactive), lightButtonBgOver (active)
    final hoverInactive =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final splashInactive =
        isDark ? const Color(0xFF24303D) : const Color(0xFFE5E5E5);
    final hoverActive =
        isDark ? const Color(0xFF1D2A39) : const Color(0xFFE3F1FA);
    final splashActive =
        isDark ? const Color(0xFF223143) : const Color(0xFFC9E4F6);

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
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Row(
                  key: _rowKey,
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
                        labelKey: _labelKeys[i],
                        label: label,
                        unread: unread,
                        isActive: isActive,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        hoverColor: isActive ? hoverActive : hoverInactive,
                        splashColor: isActive ? splashActive : splashInactive,
                        isDragged: isDragged,
                        onTap: () => _onTabTapped(i),
                        onSecondaryTapUp: (pos) =>
                            _showTabContextMenu(context, pos, folder),
                      ),
                    );
                  }),
                ),
                // Sliding underline indicator (spec §2.1: barSnapToLabel)
                if (_indicatorInitialized && !_dragActive)
                  _buildIndicator(activeColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Spec §2: right-click context menu on folder tabs.
  void _showTabContextMenu(
      BuildContext context, Offset globalPosition, FolderInfo? folder) {
    final appState = context.read<AppState>();

    showTelegramMenu<String>(
      context: context,
      position: globalPosition,
      items: [
        if (folder != null) ...[
          const TelegramMenuItem(value: 'edit', label: 'Edit Folder'),
          const TelegramMenuItem(value: 'delete', label: 'Delete Folder', isAttention: true),
          const TelegramMenuItem.separator(),
        ],
        const TelegramMenuItem(value: 'setup', label: 'Edit Folders'),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'edit':
          break;
        case 'delete':
          if (folder != null) {
            widget.chatState.deleteFolder(appState.activeAccountId, folder.id);
          }
        case 'setup':
          break;
      }
    });
  }
}

/// Individual folder tab widget with Material ripple.
/// Spec §2.1: hover ripple = windowBgOver (inactive), lightButtonBgOver (active).
class _FolderTab extends StatelessWidget {
  final GlobalKey? labelKey; // for barSnapToLabel measurement by parent
  final String label;
  final int unread;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final Color hoverColor;
  final Color splashColor;
  final bool isDragged;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onSecondaryTapUp;

  const _FolderTab({
    super.key,
    this.labelKey,
    required this.label,
    required this.unread,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.hoverColor,
    required this.splashColor,
    required this.isDragged,
    required this.onTap,
    required this.onSecondaryTapUp,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isActive ? activeColor : inactiveColor;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: isDragged ? 0.7 : 1.0,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapUp: (d) => onSecondaryTapUp(d.globalPosition),
          hoverColor: hoverColor,
          splashColor: splashColor,
          highlightColor: splashColor.withValues(alpha: 0.3),
          child: SizedBox(
            height: 33,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Column(
                children: [
                  const SizedBox(height: 7), // labelTop: 7px (§2.1 chatsFiltersTabs)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        key: labelKey,
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF40A7E3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            unread > 999 ? '999+' : '$unread',
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
                ],
              ),
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
/// Spec §2.2: SettingsSlider — 33px strip, 9px padding, 18px strictSkip,
/// 14px semibold labels, sliding underline indicator (barTop 30, barStroke 6,
/// barRadius 2, barSnapToLabel true, 150ms easeOutCubic animation).
class _SearchTabsStrip extends StatefulWidget {
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
  State<_SearchTabsStrip> createState() => _SearchTabsStripState();
}

class _SearchTabsStripState extends State<_SearchTabsStrip>
    with SingleTickerProviderStateMixin {
  final _rowKey = GlobalKey();
  final _labelKeys = List.generate(3, (_) => GlobalKey());

  late final AnimationController _indicatorCtrl;
  late final CurvedAnimation _curvedIndicator;
  Tween<double> _leftTween = Tween(begin: 0, end: 0);
  Tween<double> _widthTween = Tween(begin: 0, end: 0);
  bool _indicatorInitialized = false;

  int get _activeIndex =>
      _SearchTabsStrip._tabs.indexWhere((e) => e.tab == widget.activeTab);

  @override
  void initState() {
    super.initState();
    _indicatorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(() => setState(() {}));
    _curvedIndicator = CurvedAnimation(
      parent: _indicatorCtrl,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateIndicatorPosition(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant _SearchTabsStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateIndicatorPosition(animate: _indicatorInitialized);
    });
  }

  @override
  void dispose() {
    _curvedIndicator.dispose();
    _indicatorCtrl.dispose();
    super.dispose();
  }

  void _updateIndicatorPosition({bool animate = true}) {
    final ai = _activeIndex;
    if (ai < 0 || ai >= _labelKeys.length) return;
    final labelBox =
        _labelKeys[ai].currentContext?.findRenderObject() as RenderBox?;
    final rowBox = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (labelBox == null || rowBox == null) return;

    final labelOffset =
        labelBox.localToGlobal(Offset.zero) - rowBox.localToGlobal(Offset.zero);
    final targetLeft = labelOffset.dx;
    final targetWidth = labelBox.size.width;

    if (!animate || !_indicatorInitialized) {
      _leftTween = Tween(begin: targetLeft, end: targetLeft);
      _widthTween = Tween(begin: targetWidth, end: targetWidth);
      _indicatorCtrl.value = 1.0;
      _indicatorInitialized = true;
      return;
    }

    final curLeft = _leftTween.evaluate(_curvedIndicator);
    final curWidth = _widthTween.evaluate(_curvedIndicator);
    if ((curLeft - targetLeft).abs() < 0.5 &&
        (curWidth - targetWidth).abs() < 0.5) {
      return;
    }
    _leftTween = Tween(begin: curLeft, end: targetLeft);
    _widthTween = Tween(begin: curWidth, end: targetWidth);
    _indicatorCtrl.forward(from: 0);
  }

  Widget _buildIndicator(Color color) {
    final left = _leftTween.evaluate(_curvedIndicator);
    final width = _widthTween.evaluate(_curvedIndicator);
    if (width <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: 30, // barTop: 30px (spec §2.2)
      child: IgnorePointer(
        child: Container(
          width: width,
          height: 6, // barStroke: 6px
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2), // barRadius: 2px
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeFg =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final inactiveFg =
        isDark ? const Color(0xFF8A8A8A) : const Color(0xFF999999);
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
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Row(
              key: _rowKey,
              children: [
                for (var i = 0; i < _SearchTabsStrip._tabs.length; i++)
                  Expanded(
                    child: _SearchTabItem(
                      label: _SearchTabsStrip._tabs[i].label,
                      labelKey: _labelKeys[i],
                      isActive: widget.activeTab == _SearchTabsStrip._tabs[i].tab,
                      activeFg: activeFg,
                      inactiveFg: inactiveFg,
                      hoverColor:
                          widget.activeTab == _SearchTabsStrip._tabs[i].tab
                              ? hoverActive
                              : hoverInactive,
                      splashColor:
                          widget.activeTab == _SearchTabsStrip._tabs[i].tab
                              ? splashActive
                              : splashInactive,
                      onTap: () =>
                          widget.onTabChanged(_SearchTabsStrip._tabs[i].tab),
                    ),
                  ),
              ],
            ),
            if (_indicatorInitialized) _buildIndicator(activeFg),
          ],
        ),
      ),
    );
  }
}

/// Individual search tab item with Material ripple (underline managed by parent).
/// Spec §2.2: 14px semibold, labelTop 7px, 9px horizontal cell padding
/// (enforces 18px strictSkip between adjacent labels).
class _SearchTabItem extends StatelessWidget {
  final String label;
  final GlobalKey labelKey;
  final bool isActive;
  final Color activeFg;
  final Color inactiveFg;
  final Color hoverColor;
  final Color splashColor;
  final VoidCallback onTap;

  const _SearchTabItem({
    required this.label,
    required this.labelKey,
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
    return InkWell(
      onTap: onTap,
      hoverColor: hoverColor,
      splashColor: splashColor,
      highlightColor: splashColor.withValues(alpha: 0.3),
      child: SizedBox(
        height: 33,
        child: Padding(
          padding: const EdgeInsets.only(top: 7), // labelTop: 7px
          child: Align(
            alignment: Alignment.topCenter,
            child: Text(
              key: labelKey,
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photo placeholder / icon (spec: photo 28px, vertically centered).
                    Padding(
                      padding: const EdgeInsets.only(top: 5), // (38 - 28) / 2
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          _activeIcon,
                          size: 20,
                          color: labelColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Filter label (spec: name top 9px from row top).
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 9),
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
                    ),
                    // Dropdown arrow (spec: dropdown arrow top 15px).
                    Padding(
                      padding: const EdgeInsets.only(top: 15, right: 14),
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
    final buttonPos = button.localToGlobal(Offset(0, button.size.height));

    showTelegramMenu<_MyMsgSubFilter>(
      context: context,
      position: buttonPos,
      items: [
        for (final entry in _filters)
          TelegramMenuItem<_MyMsgSubFilter>(
            value: entry.filter,
            icon: Icon(entry.icon),
            label: entry.label,
          ),
      ],
    ).then((value) {
      if (value != null) {
        onFilterChanged(value);
      }
    });
  }
}

/// Archived Chats collapsed row (spec §2.5).
/// Fixed 37px height (dialogsImportantBarHeight), NOT 62px like regular rows.
/// Wide mode: "Archived Chats" label at 18px left pad, semibold 14px, dialogsNameFg.
/// Narrow mode: archive icon centered at 19px width.
/// Unread counter always muted/gray. Hover: dialogsBgOver. Tap: expand/collapse.
class _ArchivedChatsRow extends StatefulWidget {
  final int unreadCount;
  final bool isNarrow;
  final bool isExpanded;
  final VoidCallback onTap;
  final List<ChatInfo> archivedChats;

  const _ArchivedChatsRow({
    required this.unreadCount,
    required this.isNarrow,
    required this.isExpanded,
    required this.onTap,
    this.archivedChats = const [],
  });

  static const _rowHeight = 37.0; // dialogsImportantBarHeight

  @override
  State<_ArchivedChatsRow> createState() => _ArchivedChatsRowState();
}

class _ArchivedChatsRowState extends State<_ArchivedChatsRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Spec §2.5: dialogsNameFg for text color.
    final nameFg = isDark ? const Color(0xFFe0e0e0) : const Color(0xFF222222);
    // Spec §2.5: dialogsBgOver on hover.
    final hoverBg = isDark ? const Color(0xFF202b36) : const Color(0xFFF1F1F1);
    // Spec §2.5: unread counter always muted/gray.
    final mutedBadgeBg = isDark ? const Color(0xFF3e546a) : const Color(0xFFbbbbbb);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: hoverBg,
          child: SizedBox(
            height: _ArchivedChatsRow._rowHeight,
            child: widget.isNarrow ? _buildNarrow() : _buildWide(nameFg, mutedBadgeBg),
          ),
        ),
      ),
    );
  }

  /// Wide mode: "Archived Chats" text at 18px left pad, semibold 14px.
  Widget _buildWide(Color nameFg, Color mutedBadgeBg) {
    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Archived Chats',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: nameFg,
              ),
            ),
          ),
          if (widget.unreadCount > 0)
            Container(
              height: 19,
              constraints: const BoxConstraints(minWidth: 19),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: mutedBadgeBg,
                borderRadius: BorderRadius.circular(19 / 2),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.unreadCount > 999 ? '999+' : '${widget.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Narrow mode: stacked-userpic composite centered at 19px width
  /// (dialogsUnreadHeight). Shows up to 3 mini avatars from the archived
  /// chats arranged in a tight overlapping cluster.
  Widget _buildNarrow() {
    const compositeSize = 19.0;
    final chats = widget.archivedChats;

    // Fallback: dialogsArchiveUserpic — colored circle with white archive
    // icon inside, matching Telegram Desktop's archive userpic style.
    // historyPeerUserpicFg = white, bg = archive peer blue.
    if (chats.isEmpty) {
      return Center(
        child: Container(
          width: compositeSize,
          height: compositeSize,
          decoration: const BoxDecoration(
            color: Color(0xFF65AADD), // archive peer userpic blue
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.archive_rounded,
            size: compositeSize * 0.6,
            color: Colors.white, // historyPeerUserpicFg
          ),
        ),
      );
    }

    // Take up to 3 chats for the composite.
    final entries = chats.take(3).toList();
    final count = entries.length;

    // Single chat: one 19px circle.
    if (count == 1) {
      return Center(
        child: _miniAvatar(entries[0], compositeSize),
      );
    }

    // 2 chats: two 13px circles, top-right + bottom-left with overlap.
    // 3 chats: three 11px circles in a triangular cluster.
    final double miniSize = count == 2 ? 13.0 : 11.0;

    return Center(
      child: SizedBox(
        width: compositeSize,
        height: compositeSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (count == 2) ...[
              Positioned(
                right: 0,
                top: 0,
                child: _miniAvatar(entries[0], miniSize),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: _miniAvatar(entries[1], miniSize),
              ),
            ] else ...[
              // 3 chats: two on top, one centered at bottom.
              Positioned(
                left: 0,
                top: 0,
                child: _miniAvatar(entries[0], miniSize),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: _miniAvatar(entries[1], miniSize),
              ),
              Positioned(
                left: (compositeSize - miniSize) / 2,
                bottom: 0,
                child: _miniAvatar(entries[2], miniSize),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Renders a single mini circular avatar (photo or fallback initials).
  Widget _miniAvatar(ChatInfo chat, double size) {
    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _miniAvatarColors[colorIndex];
    final initials = _miniInitials(chat.title);

    if (chat.avatarPath.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(chat.avatarPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _miniAvatarFallback(color, initials, size),
        ),
      );
    }
    return _miniAvatarFallback(color, initials, size);
  }

  Widget _miniAvatarFallback(Color color, String initials, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }

  static String _miniInitials(String title) {
    final t = title.trim();
    if (t.isEmpty) return '?';
    return t.characters.first.toUpperCase();
  }

  static const _miniAvatarColors = [
    Color(0xFFe17076), // red
    Color(0xFFeda86c), // orange
    Color(0xFF7bc862), // green
    Color(0xFF6ec9cb), // teal
    Color(0xFF65aadd), // blue
    Color(0xFFee7aae), // pink
    Color(0xFF9b86e2), // purple
  ];
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

/// Telegram Desktop-style toast notification overlay widget.
/// Renders a centered dark pill with white text, auto-dismisses after 1500ms.
/// Fade-in: 200ms, fade-out: 1000ms, corner radius: 6px.
class _TelegramToast extends StatefulWidget {
  final String text;
  final VoidCallback onDone;
  const _TelegramToast({required this.text, required this.onDone});
  @override
  State<_TelegramToast> createState() => _TelegramToastState();
}

class _TelegramToastState extends State<_TelegramToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 1000),
    );
    _anim.forward().then((_) {
      if (!mounted) return;
      _holdTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _anim.reverse().then((_) {
          if (mounted) widget.onDone();
        });
      });
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 50,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _anim,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(minWidth: 160, maxWidth: 360),
              padding: const EdgeInsets.fromLTRB(19, 13, 19, 12),
              decoration: BoxDecoration(
                color: const Color(0xB2000000), // toastBg
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white, // toastFg
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
