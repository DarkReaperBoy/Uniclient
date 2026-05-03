import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'chat_list_row.dart';
import 'filter_column.dart';
import 'forum_topic_icon.dart';
import 'media_viewer.dart';
import 'popup_menu.dart';
import 'confirm_box.dart';
import 'contacts_screen.dart' show showContactsBox;
import 'edit_forum_topic_box.dart';
import 'folders_settings_screen.dart' show showEditFolderBox;
import 'shell.dart';
import 'story_editor.dart';
import 'telegram_toast.dart';
import 'peer_short_info.dart';
import '../theme/telegram_palette.dart';

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
  /// folder. Returns false when no folders are configured (falls through to
  /// pinned-chat handler per §24.12.2).
  static bool Function(int oneIndex)? switchFolderByIndexRequest;

  /// Global hook for Ctrl+1..Ctrl+8 pinned-chat fallback (spec §24.4
  /// `pinned_chat1`..`pinned_chat8`). [zeroIndex] is 0-based.
  /// Returns false when pinned chat at that index doesn't exist.
  static bool Function(int zeroIndex)? openPinnedChatRequest;

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

  /// Switch to the folder tab at 1-based [oneIndex]. Returns true if handled
  /// (folders exist), false otherwise (falls through to pinned-chat handler).
  static bool requestSwitchFolderByIndex(int oneIndex) =>
      switchFolderByIndexRequest?.call(oneIndex) ?? false;

  /// Open the pinned chat at 0-based [zeroIndex]. Returns true if handled.
  static bool requestOpenPinnedChat(int zeroIndex) =>
      openPinnedChatRequest?.call(zeroIndex) ?? false;

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

  // ── Drag-to-filter thresholds (spec §13.4) ──
  static const _kDragToFilterThresholdX = 30.0;
  static const _kDragToFilterThresholdY = 75.0;
  final ScrollController _chatListScrollCtrl = ScrollController();
  final GlobalKey _chatListKey = GlobalKey();
  final GlobalKey<_StoriesBarState> _storiesBarKey = GlobalKey<_StoriesBarState>();
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

  // ── Drag-to-filter state (spec §13.4) ──
  bool _dragToFilterActive = false;
  OverlayEntry? _dragToFilterOverlay;
  Offset _dragToFilterPos = Offset.zero;

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
    ChatListPanel.openPinnedChatRequest = _openPinnedChat;
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
    _chatListScrollCtrl.addListener(_onChatListScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().onShowArchiveRequested = () {
        if (mounted && !_showArchived) _toggleArchived();
      };
    });
  }

  void _onChatListScroll() {
    final bar = _storiesBarKey.currentState;
    if (bar == null) return;
    final pos = _chatListScrollCtrl.position;
    if (pos.pixels <= 0 && pos.outOfRange) {
      final overscrollRatio = pos.pixels.abs() / pos.viewportDimension;
      if (overscrollRatio > 0.72 && !bar._expanded) {
        bar._setExpanded(true);
      }
    } else if (pos.pixels > 50 && bar._expanded) {
      bar._setExpanded(false);
    }
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
  bool _switchFolderByIndex(int oneIndex) {
    if (!mounted) return false;
    final chatState = context.read<ChatState>();
    final folders = chatState.folders;
    if (folders.isEmpty) return false;
    String? target;
    if (oneIndex == 1) {
      target = null; // All Chats
    } else if (oneIndex == 8) {
      target = folders.last.id;
    } else if (oneIndex >= 2 && oneIndex <= 7) {
      final folderIdx = oneIndex - 2;
      if (folderIdx >= folders.length) return false;
      target = folders[folderIdx].id;
    } else {
      return false;
    }
    if (chatState.activeFolderId != target) {
      chatState.setActiveFolder(target);
    }
    return true;
  }

  bool _openPinnedChat(int zeroIndex) {
    if (!mounted) return false;
    final pinned = _buildNonArchived.where((c) => c.isPinned).toList();
    if (zeroIndex >= pinned.length) return false;
    context.read<ChatState>().openChat(pinned[zeroIndex]);
    return true;
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

  /// §48.11: Show topic chooser when forward-drag drops on a forum peer.
  void _showForwardTopicChooser(
    BuildContext ctx,
    ChatState chatState,
    ChatInfo forumChat,
    List<String> msgIds,
  ) {
    final engine = ctx.read<EngineService>();
    engine.getForumTopics(forumChat.accountId, forumChat.chatId).then((topics) {
      if (!mounted || topics.isEmpty) {
        chatState.forwardMessages(msgIds, forumChat.chatId);
        showTelegramToast(ctx, 'Messages forwarded.');
        return;
      }
      topics.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final aId = int.tryParse(a.topMessageId) ?? 0;
        final bId = int.tryParse(b.topMessageId) ?? 0;
        return bId.compareTo(aId);
      });
      showDialog<ForumTopic>(
        context: ctx,
        builder: (dialogCtx) => _ForwardTopicChooserDialog(
          forumTitle: forumChat.title,
          topics: topics,
        ),
      ).then((topic) {
        if (topic == null) return;
        chatState.forwardMessages(msgIds, topic.id);
        showTelegramToast(ctx, 'Messages forwarded to "${topic.title}".');
      });
    }).catchError((_) {
      chatState.forwardMessages(msgIds, forumChat.chatId);
      showTelegramToast(ctx, 'Messages forwarded.');
    });
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
    if (ChatListPanel.openPinnedChatRequest == _openPinnedChat) {
      ChatListPanel.openPinnedChatRequest = null;
    }
    final appState = context.read<AppState>();
    if (appState.onShowArchiveRequested != null) {
      appState.onShowArchiveRequested = null;
    }
    _archiveAnimCtrl.dispose();
    _chatListScrollCtrl.removeListener(_onChatListScroll);
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

  static bool _hasRecentDmContacts(List<ChatInfo> chats) {
    return chats.any((c) => c.type == ChatType.dm && !c.isArchived);
  }

  void _resetToAllMessages() {
    setState(() {
      _activeSearchTab = _SearchTab.myMessages;
      _myMsgSubFilter = _MyMsgSubFilter.all;
    });
    final query = _searchController.text;
    if (query.isNotEmpty) {
      final chatState = context.read<ChatState>();
      setState(() {
        _searchResults = _filterByTab(chatState.searchChats(query), chatState);
      });
    }
  }

  bool _isLoadingChats(AppState appState, ChatState chatState) {
    if (_searching) return false;
    if (appState.accounts.isEmpty) return false;
    final id = appState.activeAccountId;
    if (id.isEmpty) return false;
    if (chatState.chatsForAccount(id).isNotEmpty) return false;
    final conn = appState.connStateFor(id);
    return conn == ConnState.connecting || conn == ConnState.connected;
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

    if (chatState.isViewingSavedSublists) {
      return _SavedSublistsView(
        chatState: chatState,
        collapsed: widget.collapsed,
      );
    }

    if (chatState.isViewingForum) {
      return _ForumTopicListView(
        chatState: chatState,
        collapsed: widget.collapsed,
      );
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
          // Spec §32.1: Stories bar above chat list (only when not searching/collapsed).
          if (!widget.collapsed && !_searching)
            _StoriesBar(
              key: _storiesBarKey,
              chats: accountChats,
              onStoryTap: (chat) => _openStories(context, chat),
              isDark: theme.brightness == Brightness.dark,
            ),
          // Chat list / Recent Contacts (spec §2.2: recent contacts shown
          // when search focused with empty query, below Top Peers strip).
          Expanded(
            child: _searching && _searchController.text.isEmpty
                ? _hasRecentDmContacts(accountChats)
                    ? _RecentContactsList(
                        chats: accountChats,
                        onTap: (chat) => chatState.openChat(chat),
                        chatState: chatState,
                      )
                    : const _SearchWaitingState()
                : visibleChats.isEmpty && !showArchiveRow
                    ? _isLoadingChats(appState, chatState)
                        ? const _ChatListSkeleton()
                        : _EmptyState(
                            searching: _searching,
                            query: _searchController.text,
                            activeFolderId: chatState.activeFolderId,
                            activeSearchTab: _activeSearchTab,
                            onSearchAll: _resetToAllMessages,
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
                            Widget buildChatRow() {
                              if (chat.isForum) {
                                return ForumChatListRow(
                                  chat: chat,
                                  isActive: isActive,
                                  isNarrow: widget.collapsed,
                                  recentTopics: chatState.recentTopicsFor(chat.accountId, chat.chatId),
                                  onTap: () => chatState.openChat(chat),
                                  onSecondaryTap: (pos) =>
                                      _showChatContextMenu(context, chat, pos),
                                  isForwardHovered: isForwardHovered,
                                  onStoryTap: chat.storyCount > 0
                                      ? () => _openStories(context, chat)
                                      : null,
                                );
                              }
                              return ChatListRow(
                                chat: chat,
                                isActive: isActive,
                                isOnline: chatState.isChatOnline(chat),
                                isNarrow: widget.collapsed,
                                typingUser: chatState.typingUserFor(chat.chatId),
                                onTap: () => chatState.openChat(chat),
                                onSecondaryTap: (pos) =>
                                    _showChatContextMenu(context, chat, pos),
                                isForwardHovered: isForwardHovered,
                                onStoryTap: chat.storyCount > 0
                                    ? () => _openStories(context, chat)
                                    : null,
                              );
                            }

                            if (_reorderActive && isPinnedReorderable) {
                              row = buildChatRow();
                            } else {
                              row = SwipeableChatRow(
                                action: swipeAction,
                                onAction: () => _performSwipeAction(
                                    context, swipeAction, chat),
                                child: buildChatRow(),
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
                                // §48.11: Forum peer → topic chooser before
                                // forwarding; normal peer → forward directly.
                                if (chat.isForum) {
                                  _showForwardTopicChooser(
                                    context,
                                    chatState,
                                    chat,
                                    details.data.messageIds,
                                  );
                                } else {
                                  chatState.forwardMessages(
                                    details.data.messageIds,
                                    chat.chatId,
                                  );
                                  showTelegramToast(
                                      context, 'Messages forwarded.');
                                }
                              },
                              onMove: (details) {
                                if (_forwardHoveredChatId != chat.chatId) {
                                  _forwardHoverTimer?.cancel();
                                  setState(() =>
                                      _forwardHoveredChatId = chat.chatId);
                                  // §48.11: ChoosePeerByDragTimeout — open
                                  // target chat after 1s forward-drag hover.
                                  _forwardHoverTimer = Timer(
                                    const Duration(milliseconds: 1000),
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
      showTelegramToast(context, toastText);
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

    final rawDx = event.position.dx - _reorderStartPos!.dx;
    final dy = event.position.dy - _reorderStartPos!.dy;

    // Drag-to-filter active: update overlay and highlight.
    if (_dragToFilterActive) {
      _dragToFilterPos = event.position;
      _dragToFilterOverlay?.markNeedsBuild();
      final tabIdx = FilterColumn.hitTestFolderIndex(event.position);
      FilterColumn.dropHighlightIndex.value = tabIdx;
      return;
    }

    if (!_reorderActive) {
      final dx = rawDx.abs();
      // Rightward horizontal > 10px and dominant → swipe gesture.
      if (rawDx > 10 && dx > dy.abs()) {
        _reorderPinnedIdx = null;
        _reorderPointer = null;
        return;
      }
      // Spec §13.4: Leftward > 30px OR vertical > 75px → drag-to-filter.
      if (rawDx < -_kDragToFilterThresholdX ||
          dy.abs() > _kDragToFilterThresholdY) {
        _startDragToFilter(event.position);
        return;
      }
      if (dy.abs() >= _kReorderThreshold) {
        _reorderActive = true;
        _createReorderOverlay();
        setState(() {});
      }
      return;
    }

    // Reorder active: check for transition to drag-to-filter.
    if (rawDx < -_kDragToFilterThresholdX) {
      _reorderOverlay?.remove();
      _reorderOverlay = null;
      _reorderActive = false;
      _startDragToFilter(event.position);
      return;
    }

    setState(() => _reorderOffsetY = dy);
    _reorderOverlay?.markNeedsBuild();
    _autoScrollDuringReorder(event.position);
  }

  void _onReorderPointerUp(PointerUpEvent event) {
    if (_reorderPointer != event.pointer) return;
    if (_dragToFilterActive && _reorderPinnedIdx != null) {
      final tabIdx = FilterColumn.hitTestFolderIndex(event.position);
      final folderId = FilterColumn.folderIdAt(tabIdx);
      if (folderId != null && _reorderPinnedIdx! < _buildNonArchived.length) {
        final chat = _buildNonArchived[_reorderPinnedIdx!];
        debugPrint('[DRAG-TO-FILTER] Drop chat ${chat.chatId} on folder $folderId');
      }
      _cancelDragToFilter();
      _cancelReorder();
      return;
    }
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
    if (_reorderPointer == event.pointer) {
      _cancelDragToFilter();
      _cancelReorder();
    }
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

  // ── Drag-to-filter (spec §13.4) ──

  void _startDragToFilter(Offset position) {
    if (_reorderPinnedIdx == null ||
        _reorderPinnedIdx! >= _buildNonArchived.length) return;
    _dragToFilterActive = true;
    _dragToFilterPos = position;
    _createDragToFilterOverlay();
    final tabIdx = FilterColumn.hitTestFolderIndex(position);
    FilterColumn.dropHighlightIndex.value = tabIdx;
    setState(() {});
  }

  void _cancelDragToFilter() {
    _dragToFilterOverlay?.remove();
    _dragToFilterOverlay = null;
    _dragToFilterActive = false;
    FilterColumn.clearDropHighlight();
  }

  void _createDragToFilterOverlay() {
    final idx = _reorderPinnedIdx!;
    if (idx >= _buildNonArchived.length) return;
    final chat = _buildNonArchived[idx];
    final theme = Theme.of(context);

    _dragToFilterOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: _dragToFilterPos.dx - 80,
        top: _dragToFilterPos.dy - 20,
        child: IgnorePointer(
          child: Theme(
            data: theme,
            child: Material(
              elevation: 12,
              shadowColor: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: const BoxConstraints(maxWidth: 200),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        chat.title.isNotEmpty
                            ? chat.title[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        chat.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_dragToFilterOverlay!);
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

  void _openStories(BuildContext context, ChatInfo chat) async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    try {
      final stories = await engine.fetchPeerStories(accountId, chat.chatId);
      if (stories.isEmpty || !mounted) return;
      final selfId = appState.activeAccount?.selfUserId ?? '';
      StoriesViewer.open(
        context,
        stories: stories,
        peerName: chat.title,
        peerAvatarPath: chat.avatarPath,
        isOwnStory: selfId.isNotEmpty && chat.chatId == selfId,
        peerId: chat.chatId,
      );
    } catch (e) {
      debugPrint('Failed to load stories: $e');
    }
  }

  void _showChatContextMenu(BuildContext context, ChatInfo chat, Offset globalPosition) {
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();
    final isGroupy = chat.type == ChatType.group ||
        chat.type == ChatType.channel ||
        chat.type == ChatType.topic;

    final isDm = chat.type == ChatType.dm;
    final ghostBlocksReads = !appState.sendReadMessages;
    final currentExclusion = appState.getReadExclusion(chat.accountId, chat.chatId);

    final viewLabel = isDm
        ? 'View Profile'
        : chat.type == ChatType.channel
            ? 'View Channel'
            : 'View Group';
    showTelegramMenu<String>(
      context: context,
      position: globalPosition,
      items: [
        TelegramMenuItem(value: 'view_profile', label: viewLabel),
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
        if (ghostBlocksReads && chat.unreadCount > 0)
          const TelegramMenuItem(value: 'force_read', label: 'Read Message'),
        TelegramMenuItem(
          value: 'read_exclusion',
          label: currentExclusion == 1
              ? 'Read Exclusion: Never'
              : currentExclusion == 2
                  ? 'Read Exclusion: Always'
                  : 'Read Exclusion',
        ),
        const TelegramMenuItem(
          value: 'view_deleted',
          label: 'View deleted messages',
          icon: Icon(Icons.delete_outline, size: 20),
        ),
        if (isDm || isGroupy)
          const TelegramMenuItem(
            value: 'jump_to_beginning',
            label: 'Jump to beginning',
            icon: Icon(Icons.vertical_align_top, size: 20),
          ),
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
        case 'view_profile':
          final ctrlHeld = HardwareKeyboard.instance.logicalKeysPressed
              .any((k) => k == LogicalKeyboardKey.controlLeft ||
                          k == LogicalKeyboardKey.controlRight);
          if (ctrlHeld) {
            showPeerShortInfoBox(
              context,
              accountId: chat.accountId,
              peerId: chat.chatId,
              peerName: chat.title,
              avatarPath: chat.avatarPath,
              peerType: chat.type,
              memberCount: chat.memberCount,
            );
          } else {
            chatState.openChat(chat);
          }
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
        case 'force_read':
          if (context.mounted) {
            _showReadConfirmation(context, chat);
          }
        case 'read_exclusion':
          if (context.mounted) {
            _showReadExclusionMenu(context, chat, globalPosition);
          }
        case 'view_deleted':
          chatState.openChat(chat);
          Future.microtask(() => chatState.openDeletedMessages());
        case 'jump_to_beginning':
          chatState.openChat(chat);
          Future.microtask(() => chatState.jumpToMessage(1));
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

  void _showReadConfirmation(BuildContext context, ChatInfo chat) {
    showTelegramBox<bool>(
      context: context,
      builder: (ctx) => _ReadConfirmContent(peerName: chat.title),
    ).then((confirmed) {
      if (confirmed == true && context.mounted) {
        final chatState = context.read<ChatState>();
        chatState.markChatRead(chat.accountId, chat.chatId);
      }
    });
  }

  void _showReadExclusionMenu(BuildContext context, ChatInfo chat, Offset globalPosition) {
    final appState = context.read<AppState>();
    final current = appState.getReadExclusion(chat.accountId, chat.chatId);

    showTelegramMenu<int>(
      context: context,
      position: globalPosition,
      items: [
        TelegramMenuItem(
          value: 0,
          label: 'Default',
          icon: current == 0 ? const Icon(Icons.check, size: 18) : null,
        ),
        TelegramMenuItem(
          value: 1,
          label: 'Never Read',
          icon: current == 1 ? const Icon(Icons.check, size: 18) : null,
        ),
        TelegramMenuItem(
          value: 2,
          label: 'Always Read',
          icon: current == 2 ? const Icon(Icons.check, size: 18) : null,
        ),
      ],
    ).then((value) {
      if (value != null) {
        appState.setReadExclusion(chat.accountId, chat.chatId, value);
      }
    });
  }

}

class _ReadConfirmContent extends StatelessWidget {
  final String peerName;
  const _ReadConfirmContent({required this.peerName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1e2c3a) : Colors.white,
      borderRadius: BorderRadius.circular(kBoxRadius),
      child: SizedBox(
        width: kBoxWidth,
        child: Padding(
          padding: kBoxPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Text(
                'Read Message',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Send read receipt to "$peerName"? This will mark the conversation as read on the server.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFFaab2ba) : const Color(0xFF555555),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF6c7883) : const Color(0xFF999999),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      'Read',
                      style: TextStyle(color: Color(0xFF40a7e3)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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

/// Spec §32.1: Horizontal stories bar above the chat list.
/// Two states: collapsed (35px, stacked mini-thumbs) and expanded (77px, full
/// avatars with names). Expands on overscroll, collapses on scroll-down.
class _StoriesBar extends StatefulWidget {
  final List<ChatInfo> chats;
  final void Function(ChatInfo) onStoryTap;
  final bool isDark;

  const _StoriesBar({
    super.key,
    required this.chats,
    required this.onStoryTap,
    required this.isDark,
  });

  @override
  State<_StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<_StoriesBar>
    with SingleTickerProviderStateMixin {
  static const _collapsedHeight = 35.0;
  static const _expandedHeight = 77.0;

  static const _smallPhoto = 21.0;
  static const _smallShift = 16.0;
  static const _smallMaxThumbs = 3;

  static const _fullPhoto = 42.0;
  static const _fullItemWidth = 72.0;

  static const _unreadLineSmall = 1.5;
  static const _unreadLineFull = 2.0;
  static const _readLineFull = 1.0;

  static const _readOpacity = 0.6;

  bool _expanded = true;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  List<ChatInfo> get _storyPeers {
    final peers = widget.chats
        .where((c) => c.storyCount > 0 && !c.isArchived)
        .toList();
    peers.sort((a, b) {
      if (a.hasUnreadStory != b.hasUnreadStory) {
        return a.hasUnreadStory ? -1 : 1;
      }
      return b.lastMsgTime.compareTo(a.lastMsgTime);
    });
    return peers;
  }

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    setState(() {
      _expanded = expanded;
      if (_expanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final peers = _storyPeers;

    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        final t = _expandAnimation.value;
        final height =
            _collapsedHeight + (_expandedHeight - _collapsedHeight) * t;
        return SizedBox(
          height: height,
          child: t < 0.5
              ? _buildCollapsed(peers)
              : _buildExpanded(peers),
        );
      },
    );
  }

  Widget _buildCollapsed(List<ChatInfo> peers) {
    final shown = peers.take(_smallMaxThumbs).toList();
    final extraCount = peers.length - shown.length;
    return GestureDetector(
      onTap: () => _setExpanded(true),
      child: Padding(
      padding: const EdgeInsets.only(left: 10, top: 4),
      child: SizedBox(
        height: _collapsedHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                width: _smallPhoto,
                height: _smallPhoto,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isDark
                      ? const Color(0xFF2B5278)
                      : const Color(0xFF419FD9),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 12),
              ),
            ),
            for (var i = shown.length - 1; i >= 0; i--)
              Positioned(
                left: (i + 1) * _smallShift + 4,
                top: 4,
                child: _StoryAvatar(
                  chat: shown[i],
                  size: _smallPhoto,
                  ringWidth: shown[i].hasUnreadStory ? _unreadLineSmall : 0,
                  hasUnread: shown[i].hasUnreadStory,
                  isDark: widget.isDark,
                  onTap: () => widget.onStoryTap(shown[i]),
                ),
              ),
            if (extraCount > 0)
              Positioned(
                left: (shown.length + 1) * _smallShift + 8,
                top: 8,
                child: Text(
                  '+$extraCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark
                        ? const Color(0xFF8A8A8A)
                        : const Color(0xFF999999),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildExpanded(List<ChatInfo> peers) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 6, right: 6),
      itemCount: peers.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return SizedBox(
            width: _fullItemWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 9),
                GestureDetector(
                  onTap: () => showStoryEditor(context),
                  child: Container(
                    width: _fullPhoto,
                    height: _fullPhoto,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isDark
                          ? const Color(0xFF2B5278)
                          : const Color(0xFF419FD9),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: _fullItemWidth - 4,
                  child: Text(
                    'My Story',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isDark
                          ? const Color(0xFFaaaaaa)
                          : const Color(0xFF666666),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final chat = peers[index - 1];
        final opacity =
            chat.hasUnreadStory ? 1.0 : _readOpacity;
        return Opacity(
          opacity: opacity,
          child: SizedBox(
            width: _fullItemWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 9),
                _StoryAvatar(
                  chat: chat,
                  size: _fullPhoto,
                  ringWidth: chat.hasUnreadStory
                      ? _unreadLineFull
                      : _readLineFull,
                  hasUnread: chat.hasUnreadStory,
                  isDark: widget.isDark,
                  onTap: () => widget.onStoryTap(chat),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: _fullItemWidth - 4,
                  child: Text(
                    chat.title.split(RegExp(r'\s+')).first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isDark
                          ? const Color(0xFFaaaaaa)
                          : const Color(0xFF666666),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final ChatInfo chat;
  final double size;
  final double ringWidth;
  final bool hasUnread;
  final bool isDark;
  final VoidCallback onTap;

  const _StoryAvatar({
    required this.chat,
    required this.size,
    required this.ringWidth,
    required this.hasUnread,
    required this.isDark,
    required this.onTap,
  });

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
    final ringOffset = ringWidth > 0 ? ringWidth * 1.5 : 0.0;
    final totalSize = size + ringOffset * 2;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: totalSize,
        height: totalSize,
        child: CustomPaint(
          painter: _StoriesBarRingPainter(
            storyCount: chat.storyCount,
            hasUnread: hasUnread,
            isDark: isDark,
            photoRadius: size / 2,
            lineWidth: ringWidth,
          ),
          child: Center(
            child: SizedBox(
              width: size,
              height: size,
              child: chat.avatarPath.isNotEmpty
                  ? ClipOval(
                      child: Image.file(
                        File(chat.avatarPath),
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _fallbackAvatar(),
                      ),
                    )
                  : _fallbackAvatar(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackAvatar() {
    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];
    final t = chat.title.trim();
    String initials;
    if (t.isEmpty) {
      initials = '?';
    } else {
      final words = t.split(RegExp(r'\s+'));
      if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
        initials = '${words[0][0]}${words[1][0]}'.toUpperCase();
      } else {
        initials = t[0].toUpperCase();
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StoriesBarRingPainter extends CustomPainter {
  final int storyCount;
  final bool hasUnread;
  final bool isDark;
  final double photoRadius;
  final double lineWidth;

  _StoriesBarRingPainter({
    required this.storyCount,
    required this.hasUnread,
    required this.isDark,
    required this.photoRadius,
    required this.lineWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (storyCount <= 0 || lineWidth <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = photoRadius + lineWidth * 1.5;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;

    if (hasUnread) {
      paint.shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF0dcc39), Color(0xFF0992ef)],
      ).createShader(Rect.fromCircle(center: center, radius: ringRadius));
    } else {
      paint.color = isDark
          ? const Color(0xFF3e546a)
          : const Color(0xFFbbbbbb);
    }

    if (storyCount == 1) {
      canvas.drawCircle(center, ringRadius, paint);
    } else {
      const fullCircleUnits = 5760.0;
      const separatorUnits = 160.0;
      final separatorRadians =
          (separatorUnits / fullCircleUnits) * 2 * math.pi;
      final totalSep = storyCount * separatorRadians;
      final arcPerStory = (2 * math.pi - totalSep) / storyCount;

      var startAngle = -math.pi / 2;
      final rect = Rect.fromCircle(center: center, radius: ringRadius);
      for (var i = 0; i < storyCount; i++) {
        canvas.drawArc(rect, startAngle, arcPerStory, false, paint);
        startAngle += arcPerStory + separatorRadians;
      }
    }
  }

  @override
  bool shouldRepaint(_StoriesBarRingPainter old) =>
      storyCount != old.storyCount ||
      hasUnread != old.hasUnread ||
      isDark != old.isDark ||
      photoRadius != old.photoRadius ||
      lineWidth != old.lineWidth;
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
    final subColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final hasChannels =
        chats.any((c) => c.type == ChatType.channel && !c.isArchived);

    return CustomScrollView(
      slivers: [
        SliverFixedExtentList(
          itemExtent: _rowHeight,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
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
            childCount: recent.length,
          ),
        ),
        // §35.8: Empty recent search results section.
        SliverToBoxAdapter(
          child: _EmptySuggestionSection(
            lottieAsset: 'assets/animations/search.json',
            text: 'Recent search results\nwill appear here.',
            subColor: subColor,
          ),
        ),
        // §35.9: Empty channels list (only when user has no channels).
        if (!hasChannels)
          SliverToBoxAdapter(
            child: _EmptySuggestionSection(
              lottieAsset: 'assets/animations/noresults.json',
              text: 'You are not currently\nsubscribed to any channels.',
              subColor: subColor,
            ),
          ),
      ],
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

class _EmptySuggestionSection extends StatelessWidget {
  final String lottieAsset;
  final String text;
  final Color subColor;

  const _EmptySuggestionSection({
    required this.lottieAsset,
    required this.text,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Lottie.asset(lottieAsset, fit: BoxFit.contain),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: subColor),
          ),
        ],
      ),
    );
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

/// Spec §35.5 + §35.33: Skeleton loading rows shown during initial chat sync.
/// 2 placeholder rows matching DialogRow geometry with a glare sweep animation.
class _ChatListSkeleton extends StatefulWidget {
  const _ChatListSkeleton();

  @override
  State<_ChatListSkeleton> createState() => _ChatListSkeletonState();
}

class _ChatListSkeletonState extends State<_ChatListSkeleton>
    with SingleTickerProviderStateMixin {
  static const _rowHeight = 62.0;
  static const _avatarSize = 46.0;
  static const _avatarLeft = 10.0;
  static const _avatarTop = 8.0;
  static const _contentLeft = 68.0;
  static const _nameTop = 10.0;
  static const _nameWidth = 60.0;
  static const _statusTop = 34.0;
  static const _rowCount = 2;
  static const _cycleDuration = Duration(milliseconds: 2000);

  late final AnimationController _controller;
  late final List<double> _statusWidths;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _cycleDuration)
      ..repeat();
    final rng = math.Random();
    _statusWidths = List.generate(
      _rowCount,
      (_) => 100.0 / 4 + rng.nextDouble() * (100.0 / 2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _SkeletonPainter(
            progress: _controller.value,
            statusWidths: _statusWidths,
            avatarColor: p.windowBgOver,
            baseColor: p.windowSubTextFg.withValues(alpha: 0.5),
            glareColor: p.windowSubTextFg.withValues(alpha: 0.2),
            bgColor: p.dialogsBg,
          ),
          size: const Size(double.infinity, _rowHeight * _rowCount),
        );
      },
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  final double progress;
  final List<double> statusWidths;
  final Color avatarColor;
  final Color baseColor;
  final Color glareColor;
  final Color bgColor;

  _SkeletonPainter({
    required this.progress,
    required this.statusWidths,
    required this.avatarColor,
    required this.baseColor,
    required this.glareColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);

    final nameBarHeight = 14 * 0.7;
    final statusBarHeight = 13 * 0.7;
    final nameRadius = nameBarHeight / 2;
    final statusRadius = statusBarHeight / 2;

    // Glare: first half of cycle (0..0.5) is sweep, second half (0.5..1) is pause.
    final sweepPhase = progress < 0.5 ? progress / 0.5 : -1.0;

    for (var i = 0; i < _ChatListSkeletonState._rowCount; i++) {
      final rowTop = i * _ChatListSkeletonState._rowHeight;

      // Avatar circle.
      final avatarCenter = Offset(
        _ChatListSkeletonState._avatarLeft + _ChatListSkeletonState._avatarSize / 2,
        rowTop + _ChatListSkeletonState._avatarTop + _ChatListSkeletonState._avatarSize / 2,
      );
      canvas.drawCircle(
        avatarCenter,
        _ChatListSkeletonState._avatarSize / 2,
        Paint()..color = avatarColor,
      );

      // Name bar.
      final nameRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          _ChatListSkeletonState._contentLeft,
          rowTop + _ChatListSkeletonState._nameTop + (14 - nameBarHeight) / 2,
          _ChatListSkeletonState._nameWidth,
          nameBarHeight,
        ),
        Radius.circular(nameRadius),
      );
      canvas.drawRRect(nameRect, Paint()..color = baseColor);

      // Status bar (randomized width per row).
      final sw = statusWidths[i];
      final statusRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          _ChatListSkeletonState._contentLeft,
          rowTop + _ChatListSkeletonState._statusTop + (13 - statusBarHeight) / 2,
          sw,
          statusBarHeight,
        ),
        Radius.circular(statusRadius),
      );
      canvas.drawRRect(statusRect, Paint()..color = baseColor);

      // Glare sweep overlay on bars.
      if (sweepPhase >= 0) {
        final glareX = sweepPhase * size.width;
        final glareWidth = size.width * 0.4;
        final gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            glareColor.withValues(alpha: 0),
            glareColor,
            glareColor.withValues(alpha: 0),
          ],
        );
        final glareRect = Rect.fromLTWH(
          glareX - glareWidth / 2,
          rowTop,
          glareWidth,
          _ChatListSkeletonState._rowHeight,
        );
        final glarePaint = Paint()
          ..shader = gradient.createShader(glareRect);

        canvas.save();
        // Clip to name bar, draw glare.
        canvas.clipRRect(nameRect);
        canvas.drawRect(glareRect, glarePaint);
        canvas.restore();

        canvas.save();
        canvas.clipRRect(statusRect);
        canvas.drawRect(glareRect, glarePaint);
        canvas.restore();

        // Glare on avatar circle.
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(
          center: avatarCenter,
          radius: _ChatListSkeletonState._avatarSize / 2,
        )));
        canvas.drawRect(glareRect, glarePaint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => old.progress != progress;
}

/// Spec §35.7.1: Search waiting state — search focused, no query entered,
/// no recent contacts to display.
class _SearchWaitingState extends StatelessWidget {
  const _SearchWaitingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
    return LayoutBuilder(
      builder: (context, constraints) {
        final topPad = (constraints.maxHeight / 3) - 50;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  SizedBox(height: topPad.clamp(10.0, double.infinity)),
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Lottie.asset(
                      'assets/animations/search.json',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Search for messages',
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

/// Empty state for chat list.
class _EmptyState extends StatelessWidget {
  final bool searching;
  final String query;
  final String? activeFolderId;
  final _SearchTab activeSearchTab;
  final VoidCallback? onSearchAll;

  static const _kQueryPreviewLimit = 18;

  const _EmptyState({
    required this.searching,
    this.query = '',
    this.activeFolderId,
    this.activeSearchTab = _SearchTab.myMessages,
    this.onSearchAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    if (!searching && activeFolderId != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'No chats currently belong\nto this folder. ',
                  style: TextStyle(fontSize: 13, color: subColor),
                ),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () {
                      final chatState = context.read<ChatState>();
                      final folder = chatState.folders.where(
                        (f) => f.id == activeFolderId,
                      ).firstOrNull;
                      if (folder != null) {
                        showEditFolderBox(context, folder);
                      }
                    },
                    child: Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!searching) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: Lottie.asset(
                          'assets/animations/no_chats.json',
                          fit: BoxFit.contain,
                          repeat: false,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You have no\nconversations yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your contacts on Telegram',
                        style: TextStyle(
                          fontSize: 13,
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                    bottom: 12, left: 16, right: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => showContactsBox(context),
                    child: const Text('New Message'),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    final isHashtag = query.startsWith('#');
    final displayQuery = query.length > _kQueryPreviewLimit
        ? '${query.substring(0, _kQueryPreviewLimit)}…'
        : query;
    final showSearchAllLink = activeSearchTab != _SearchTab.myMessages;

    return LayoutBuilder(
      builder: (context, constraints) {
        final topPad = (constraints.maxHeight / 3) - 50;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  SizedBox(height: topPad.clamp(10.0, double.infinity)),
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Lottie.asset(
                      'assets/animations/noresults.json',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No Results',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: subColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isHashtag
                        ? 'Try another hashtag.'
                        : 'There were no results\nfor "$displayQuery".',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: subColor,
                    ),
                  ),
                  if (showSearchAllLink && onSearchAll != null) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onSearchAll,
                      child: Text(
                        'Search in All Messages',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
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

// ══════════════════════════════════════════════════════════════════════════════
// §22.3 Forum Topic List View
// ══════════════════════════════════════════════════════════════════════════════

class _ForumEmptyState extends StatelessWidget {
  final VoidCallback onCreateTopic;
  const _ForumEmptyState({required this.onCreateTopic});

  @override
  Widget build(BuildContext context) {
    final subColor = Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'No topics currently created\nin this group. ',
                style: TextStyle(fontSize: 13, color: subColor),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: onCreateTopic,
                  child: Text(
                    'Create topic',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ForumTopicListView extends StatefulWidget {
  final ChatState chatState;
  final bool collapsed;

  const _ForumTopicListView({
    required this.chatState,
    this.collapsed = false,
  });

  @override
  State<_ForumTopicListView> createState() => _ForumTopicListViewState();
}

class _ForumTopicListViewState extends State<_ForumTopicListView> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      widget.chatState.loadMoreForumTopics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final parent = widget.chatState.forumParentChat!;
    final allTopics = widget.chatState.forumTopics;
    final topics = allTopics.where((t) => !(t.isGeneral && t.isHidden)).toList();
    final engine = context.read<EngineService>();
    final hasMore = widget.chatState.forumHasMore;

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showTopicListContextMenu(context, details.globalPosition, parent, engine),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            right: BorderSide(color: theme.dividerColor, width: 1),
          ),
        ),
        child: Column(
          children: [
            _ForumTopicHeader(
              title: parent.title,
              isDark: isDark,
              onBack: widget.chatState.closeForum,
              chatId: parent.chatId,
              accountId: parent.accountId,
              engine: engine,
              chatState: widget.chatState,
              onShowMenu: (ctx, pos) =>
                  _showTopicListContextMenu(ctx, pos, parent, engine),
            ),
            Expanded(
              child: topics.isEmpty
                  ? (widget.chatState.forumFirstLoadDone
                      ? _ForumEmptyState(
                          onCreateTopic: () => _showCreateTopicDialog(context, parent, engine),
                        )
                      : const Center(child: CircularProgressIndicator()))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      itemCount: topics.length + (hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= topics.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        final topic = topics[index];
                        final isActive = widget.chatState.activeTopicId == topic.id;
                        return _ForumTopicRow(
                          topic: topic,
                          isActive: isActive,
                          accountId: parent.accountId,
                          chatId: parent.chatId,
                          engine: engine,
                          chatState: widget.chatState,
                          onTap: () => widget.chatState.openTopic(topic),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTopicListContextMenu(
    BuildContext ctx,
    Offset position,
    ChatInfo parent,
    EngineService engine,
  ) async {
    final chatState = widget.chatState;
    final topics = chatState.forumTopics;
    final value = await showTelegramMenu<String>(
      context: ctx,
      position: position,
      items: [
        const TelegramMenuItem(
          value: 'create_topic',
          icon: Icon(Icons.add_circle_outline, size: 20),
          label: 'Create Topic',
        ),
        const TelegramMenuItem(
          value: 'view_group_info',
          icon: Icon(Icons.info_outline, size: 20),
          label: 'View Group Info',
        ),
        const TelegramMenuItem(
          value: 'view_as_messages',
          icon: Icon(Icons.forum_outlined, size: 20),
          label: 'View as Messages',
        ),
        if (topics.length > 1)
          const TelegramMenuItem(
            value: 'search',
            icon: Icon(Icons.search, size: 20),
            label: 'Search',
          ),
        const TelegramMenuItem.separator(),
        TelegramMenuItem(
          value: 'leave',
          icon: const Icon(Icons.exit_to_app, size: 20),
          label: parent.type == ChatType.channel ? 'Leave Channel' : 'Leave Group',
          isAttention: true,
        ),
      ],
    );
    if (value == null || !ctx.mounted) return;
    switch (value) {
      case 'create_topic':
        _showCreateTopicDialog(ctx, parent, engine);
      case 'view_group_info':
        UniClientShell.toggleInfoRequest?.call();
      case 'view_as_messages':
        chatState.toggleForumViewAsMessages();
      case 'search':
        ChatListPanel.focusSearchRequest?.call();
      case 'leave':
        showDeleteConfirmBox(
          ctx,
          mode: DeleteBoxMode.leaveChat,
          chatType: parent.type,
          peerName: parent.title,
        ).then((r) {
          if (r.confirmed) {
            chatState.leaveChat(parent.accountId, parent.chatId);
            chatState.closeForum();
          }
        });
    }
  }

  void _showCreateTopicDialog(BuildContext ctx, ChatInfo parent, EngineService engine) async {
    final chatState = widget.chatState;
    final result = await showEditForumTopicBox(ctx);
    if (result == null) return;
    try {
      final topicId = await engine.createForumTopic(
        parent.accountId, parent.chatId, result.title, result.colorId, result.iconEmojiId,
      );
      await chatState.refreshForumTopics();
      if (topicId > 0) {
        final newTopic = chatState.forumTopics.cast<ForumTopic?>().firstWhere(
          (t) => t!.id == topicId.toString(),
          orElse: () => null,
        );
        if (newTopic != null) chatState.openTopic(newTopic);
      }
    } catch (e) {
      if (ctx.mounted) {
        showTelegramToast(ctx, 'Failed to create topic: $e');
      }
    }
  }
}

class _ForumTopicHeader extends StatefulWidget {
  final String title;
  final bool isDark;
  final VoidCallback onBack;
  final String chatId;
  final String accountId;
  final EngineService engine;
  final ChatState chatState;
  final void Function(BuildContext ctx, Offset position) onShowMenu;

  const _ForumTopicHeader({
    required this.title,
    required this.isDark,
    required this.onBack,
    required this.chatId,
    required this.accountId,
    required this.engine,
    required this.chatState,
    required this.onShowMenu,
  });

  @override
  State<_ForumTopicHeader> createState() => _ForumTopicHeaderState();
}

class _ForumTopicHeaderState extends State<_ForumTopicHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _highlightController;
  late final Animation<double> _highlightAnimation;
  String? _lastActiveTopicId;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _highlightAnimation = CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeOut,
    );
    _lastActiveTopicId = widget.chatState.activeTopicId;
  }

  @override
  void didUpdateWidget(_ForumTopicHeader old) {
    super.didUpdateWidget(old);
    final currentTopicId = widget.chatState.activeTopicId;
    if (currentTopicId != null && currentTopicId != _lastActiveTopicId) {
      _highlightController.forward(from: 0.0).then((_) {
        if (mounted) _highlightController.reverse();
      });
    }
    _lastActiveTopicId = currentTopicId;
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF17212b) : Colors.white;
    final highlightBg = isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8f0fe);

    return GestureDetector(
      onSecondaryTapUp: (details) => widget.onShowMenu(context, details.globalPosition),
      child: AnimatedBuilder(
        animation: _highlightAnimation,
        builder: (_, child) {
          return Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Color.lerp(bg, highlightBg, _highlightAnimation.value),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0x8F04080e) : const Color(0x18000000),
                ),
              ),
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 22),
              onPressed: widget.onBack,
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 22),
              onPressed: () => _showCreateTopicDialog(context),
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Create Topic',
            ),
            Builder(
              builder: (btnCtx) => IconButton(
                icon: const Icon(Icons.more_vert, size: 22),
                onPressed: () {
                  final box = btnCtx.findRenderObject() as RenderBox;
                  final pos = box.localToGlobal(Offset(box.size.width, box.size.height));
                  widget.onShowMenu(context, pos);
                },
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Menu',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateTopicDialog(BuildContext ctx) async {
    final result = await showEditForumTopicBox(ctx);
    if (result == null) return;
    try {
      final topicId = await widget.engine.createForumTopic(
        widget.accountId, widget.chatId, result.title, result.colorId, result.iconEmojiId,
      );
      await widget.chatState.refreshForumTopics();
      if (topicId > 0) {
        final newTopic = widget.chatState.forumTopics.cast<ForumTopic?>().firstWhere(
          (t) => t!.id == topicId.toString(),
          orElse: () => null,
        );
        if (newTopic != null) {
          widget.chatState.openTopic(newTopic);
        }
      }
    } catch (e) {
      if (ctx.mounted) {
        showTelegramToast(ctx, 'Failed to create topic: $e');
      }
    }
  }
}

class _ForumTopicRow extends StatefulWidget {
  final ForumTopic topic;
  final bool isActive;
  final String accountId;
  final String chatId;
  final EngineService engine;
  final ChatState chatState;
  final VoidCallback onTap;

  const _ForumTopicRow({
    required this.topic,
    required this.isActive,
    required this.accountId,
    required this.chatId,
    required this.engine,
    required this.chatState,
    required this.onTap,
  });

  static const _rowHeight = 54.0;
  static const _iconSize = 20.0;
  static const _nameLeft = 39.0;
  static const _nameTop = 7.0;
  static const _textLeft = 39.0;
  static const _textTop = 29.0;
  static const _paddingLeft = 8.0;
  static const _paddingTop = 7.0;
  static const _paddingRight = 10.0;
  static const _paddingBottom = 7.0;
  static const _leftBarWidth = 4.0;

  @override
  State<_ForumTopicRow> createState() => _ForumTopicRowState();
}

class _ForumTopicRowState extends State<_ForumTopicRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _barController;
  late final Animation<double> _barAnimation;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: widget.isActive ? 1.0 : 0.0,
    );
    _barAnimation = CurvedAnimation(
      parent: _barController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(_ForumTopicRow old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      if (widget.isActive) {
        _barController.forward();
      } else {
        _barController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeBg = isDark ? const Color(0xFF2b5278) : const Color(0xFF419fd9);
    final hoverBg = isDark ? const Color(0xFF202b36) : const Color(0xFFF1F1F1);
    final Color? rowBg = widget.isActive ? activeBg : null;
    final rippleColor = isDark ? const Color(0xFF1e2831) : const Color(0xFFc6c6c6);

    final nameColor = widget.isActive
        ? Colors.white
        : (isDark ? const Color(0xFFe1e3e6) : const Color(0xFF222222));
    final textColor = widget.isActive
        ? Colors.white70
        : (isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999));
    final dateColor = textColor;

    final hasUnread = widget.topic.unreadCount > 0;
    final showPin = widget.topic.isPinned && !hasUnread;

    return GestureDetector(
      onSecondaryTapUp: (details) => _showTopicContextMenu(context, details.globalPosition),
      child: Container(
        height: _ForumTopicRow._rowHeight,
        color: rowBg,
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _barAnimation,
              builder: (_, __) {
                if (_barAnimation.value <= 0) return const SizedBox.shrink();
                return Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _ForumTopicRow._leftBarWidth,
                  child: Opacity(
                    opacity: _barAnimation.value,
                    child: Container(
                      color: isDark
                          ? const Color(0xFF5eaade)
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                );
              },
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                hoverColor: widget.isActive ? Colors.white.withValues(alpha: 0.08) : hoverBg,
                splashColor: widget.isActive
                    ? (isDark ? const Color(0xFF315a80) : const Color(0xFF2095d0))
                    : rippleColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _ForumTopicRow._paddingLeft, _ForumTopicRow._paddingTop,
                    _ForumTopicRow._paddingRight, _ForumTopicRow._paddingBottom,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: (_ForumTopicRow._rowHeight - _ForumTopicRow._paddingTop -
                            _ForumTopicRow._paddingBottom - _ForumTopicRow._iconSize) / 2,
                        child: TopicIconWidget(
                          topic: widget.topic,
                          accountId: widget.accountId,
                          engine: widget.engine,
                          size: _ForumTopicRow._iconSize,
                          generalContext: widget.isActive
                              ? GeneralIconContext.active
                              : GeneralIconContext.normal,
                        ),
                      ),
                      Positioned(
                        left: _ForumTopicRow._nameLeft - _ForumTopicRow._paddingLeft,
                        top: _ForumTopicRow._nameTop - _ForumTopicRow._paddingTop,
                        right: 60,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.topic.isGeneral ? '# ${widget.topic.title}' : widget.topic.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: nameColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (widget.topic.isClosed) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: textColor,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: _ForumTopicRow._nameTop - _ForumTopicRow._paddingTop,
                        child: Text(
                          _formatDate(widget.topic),
                          style: TextStyle(fontSize: 12, color: dateColor),
                        ),
                      ),
                      Positioned(
                        left: _ForumTopicRow._textLeft - _ForumTopicRow._paddingLeft,
                        top: _ForumTopicRow._textTop - _ForumTopicRow._paddingTop,
                        right: hasUnread ? 30 : (showPin ? 20 : 0),
                        child: Text(
                          _previewText(widget.topic),
                          style: TextStyle(fontSize: 13, color: textColor),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (hasUnread)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: _TopicUnreadBadge(
                            count: widget.topic.unreadCount,
                            isActive: widget.isActive,
                            isDark: isDark,
                          ),
                        ),
                      if (showPin)
                        Positioned(
                          right: 0,
                          bottom: 2,
                          child: Icon(
                            Icons.push_pin,
                            size: 16,
                            color: widget.isActive
                                ? Colors.white70
                                : (isDark ? const Color(0xFF556a7d) : const Color(0xFFcccccc)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTopicContextMenu(BuildContext ctx, Offset position) async {
    final topic = widget.topic;
    final topicId = int.tryParse(topic.id) ?? 0;
    final hasUnread = topic.unreadCount > 0;

    final value = await showTelegramMenu<String>(
      context: ctx,
      position: position,
      items: [
        if (topic.canTogglePinned)
          TelegramMenuItem(
            value: 'pin',
            icon: Icon(topic.isPinned ? Icons.push_pin_outlined : Icons.push_pin, size: 20),
            label: topic.isPinned ? 'Unpin from Top' : 'Pin to Top',
          ),
        const TelegramMenuItem(
          value: 'view_info',
          icon: Icon(Icons.info_outline, size: 20),
          label: 'View Info',
        ),
        TelegramMenuItem(
          value: 'mark_read',
          icon: Icon(hasUnread ? Icons.done_all : Icons.markunread, size: 20),
          label: hasUnread ? 'Mark as Read' : 'Mark as Unread',
        ),
        if (topic.canEdit)
          const TelegramMenuItem(
            value: 'edit',
            icon: Icon(Icons.edit_outlined, size: 20),
            label: 'Edit Topic',
          ),
        if (topic.canToggleClosed)
          TelegramMenuItem(
            value: 'toggle_closed',
            icon: Icon(topic.isClosed ? Icons.lock_open : Icons.lock_outline, size: 20),
            label: topic.isClosed ? 'Reopen Topic' : 'Close Topic',
          ),
        if (topic.isGeneral && topic.canEdit)
          TelegramMenuItem(
            value: 'toggle_hidden',
            icon: Icon(topic.isHidden ? Icons.visibility : Icons.visibility_off, size: 20),
            label: topic.isHidden ? 'Show Topic' : 'Hide Topic',
          ),
        const TelegramMenuItem.separator(),
        const TelegramMenuItem(
          value: 'clear_history',
          icon: Icon(Icons.delete_sweep_outlined, size: 20),
          label: 'Clear History',
        ),
        if (topic.canDelete && !topic.isGeneral)
          const TelegramMenuItem(
            value: 'delete',
            icon: Icon(Icons.delete_outline, size: 20),
            label: 'Delete Topic',
            isAttention: true,
          ),
      ],
    );
    if (value == null || !ctx.mounted) return;
    switch (value) {
      case 'pin':
        try {
          await widget.chatState.pinForumTopic(widget.accountId, widget.chatId, topicId, !topic.isPinned);
        } catch (e) {
          if (ctx.mounted) {
            showTelegramToast(ctx, 'Failed: $e');
          }
        }
      case 'view_info':
        widget.chatState.openTopic(topic);
        UniClientShell.toggleInfoRequest?.call();
      case 'mark_read':
        if (hasUnread) {
          widget.chatState.markChatRead(widget.accountId, topic.id);
        }
      case 'edit':
        _showEditTopicDialog(ctx);
      case 'toggle_closed':
        try {
          await widget.chatState.toggleForumTopicClosed(widget.accountId, widget.chatId, topicId, !topic.isClosed);
        } catch (e) {
          if (ctx.mounted) {
            showTelegramToast(ctx, 'Failed: $e');
          }
        }
      case 'toggle_hidden':
        try {
          await widget.chatState.toggleGeneralTopicHidden(widget.accountId, widget.chatId, !topic.isHidden);
        } catch (e) {
          if (ctx.mounted) {
            showTelegramToast(ctx, 'Failed: $e');
          }
        }
      case 'clear_history':
        final r = await showDeleteConfirmBox(
          ctx,
          mode: DeleteBoxMode.clearHistory,
          chatType: ChatType.topic,
          peerName: topic.title,
        );
        if (r.confirmed) {
          try {
            await widget.chatState.deleteForumTopicHistory(widget.accountId, widget.chatId, topicId);
          } catch (e) {
            if (ctx.mounted) {
              showTelegramToast(ctx, 'Failed: $e');
            }
          }
        }
      case 'delete':
        final r = await showDeleteConfirmBox(
          ctx,
          mode: DeleteBoxMode.clearHistory,
          chatType: ChatType.topic,
          peerName: topic.title,
        );
        if (r.confirmed) {
          try {
            await widget.chatState.deleteForumTopicHistory(widget.accountId, widget.chatId, topicId);
            await widget.chatState.refreshForumTopics();
          } catch (e) {
            if (ctx.mounted) {
              showTelegramToast(ctx, 'Failed: $e');
            }
          }
        }
    }
  }

  void _showEditTopicDialog(BuildContext ctx) async {
    final topic = widget.topic;
    final result = await showEditForumTopicBox(
      ctx,
      existingTitle: topic.title,
      existingColorId: topic.colorId,
      existingIconEmojiId: topic.iconEmojiId,
      isGeneral: topic.isGeneral,
      isEditing: true,
    );
    if (result == null) return;
    try {
      final topicId = int.tryParse(topic.id) ?? 0;
      await widget.engine.editForumTopic(
        widget.accountId, widget.chatId, topicId, result.title,
        iconEmojiId: topic.isGeneral ? -1 : result.iconEmojiId,
      );
      await widget.chatState.refreshForumTopics();
    } catch (e) {
      if (ctx.mounted) {
        showTelegramToast(ctx, 'Failed to edit topic: $e');
      }
    }
  }

  String _formatDate(ForumTopic topic) {
    final msgId = int.tryParse(topic.topMessageId) ?? 0;
    if (msgId == 0) return '';
    final created = topic.creationDateTime;
    final now = DateTime.now();
    if (now.year == created.year &&
        now.month == created.month &&
        now.day == created.day) {
      final h = created.hour.toString().padLeft(2, '0');
      final m = created.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[created.month - 1]} ${created.day}';
  }

  String _previewText(ForumTopic topic) {
    if (topic.isGeneral) return 'General topic';
    return '';
  }
}

class _TopicUnreadBadge extends StatelessWidget {
  final int count;
  final bool isActive;
  final bool isDark;

  const _TopicUnreadBadge({
    required this.count,
    this.isActive = false,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (isActive) {
      bg = Colors.white;
    } else {
      bg = isDark ? const Color(0xFF3e88c7) : const Color(0xFF40a7e3);
    }
    final Color fg = isActive
        ? (isDark ? const Color(0xFF2b5278) : const Color(0xFF419fd9))
        : Colors.white;
    final text = count > 999 ? '${count ~/ 1000}K' : '$count';
    final minW = text.length > 2 ? 24.0 : 20.0;
    return Container(
      constraints: BoxConstraints(minWidth: minW, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1.0,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// §31.7a SearchTags Strip — reaction tag filter chips for Saved Messages
// ══════════════════════════════════════════════════════════════════════════════

class _SearchTagsStrip extends StatelessWidget {
  final List<SavedReactionTagInfo> tags;
  final ChatState chatState;

  const _SearchTagsStrip({required this.tags, required this.chatState});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: tags.map((tag) {
          final selected = chatState.isReactionTagSelected(tag);
          return _SearchTagChip(
            tag: tag,
            selected: selected,
            isDark: isDark,
            onTap: (multiSelect) => chatState.toggleReactionTag(tag, multiSelect: multiSelect),
            onContextMenu: (offset) => _showTagContextMenu(context, offset, tag),
          );
        }).toList(),
      ),
    );
  }

  void _showTagContextMenu(BuildContext context, Offset position, SavedReactionTagInfo tag) {
    final hasTitle = tag.title.isNotEmpty;
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'edit',
          label: hasTitle ? 'Edit tag name' : 'Add tag name',
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        TelegramMenuItem(
          value: 'filter',
          label: 'Filter by this tag',
          icon: const Icon(Icons.filter_alt_outlined, size: 20),
        ),
        TelegramMenuItem(
          value: 'remove',
          label: 'Remove tag',
          icon: const Icon(Icons.close, size: 20),
          isAttention: true,
        ),
      ],
    ).then((action) {
      if (action == 'edit') {
        _showEditTagDialog(context, tag);
      } else if (action == 'filter') {
        chatState.toggleReactionTag(tag);
      }
    });
  }

  void _showEditTagDialog(BuildContext context, SavedReactionTagInfo tag) {
    final controller = TextEditingController(text: tag.title);
    final hasTitle = tag.title.isNotEmpty;
    showDialog(
      context: context,
      builder: (ctx) {
        return _EditTagNameDialog(
          title: hasTitle ? 'Edit tag name' : 'Add tag name',
          emoji: tag.isCustomEmoji ? null : tag.emoji,
          controller: controller,
          onSave: (text) {
            chatState.renameSavedReactionTag(
              emoji: tag.emoji,
              customId: tag.customId,
              title: text,
            );
          },
        );
      },
    );
  }
}

class _SearchTagChip extends StatelessWidget {
  final SavedReactionTagInfo tag;
  final bool selected;
  final bool isDark;
  final void Function(bool multiSelect) onTap;
  final void Function(Offset position) onContextMenu;

  const _SearchTagChip({
    required this.tag,
    required this.selected,
    required this.isDark,
    required this.onTap,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = selected
        ? (isDark ? const Color(0xFF2B5278) : const Color(0xFF419FD9))
        : (isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1));
    final textColor = selected
        ? Colors.white
        : (isDark ? const Color(0xFF8B9BAA) : const Color(0xFF999999));

    final label = _composeLabel();
    final emojiText = tag.isCustomEmoji ? '\u{2B50}' : tag.emoji;

    return GestureDetector(
      onTapDown: (details) {
        final isShift = HardwareKeyboard.instance.logicalKeysPressed
            .any((k) => k == LogicalKeyboardKey.shiftLeft || k == LogicalKeyboardKey.shiftRight);
        onTap(isShift);
      },
      onSecondaryTapUp: (details) => onContextMenu(details.globalPosition),
      child: CustomPaint(
        painter: _TagChipPainter(
          bgColor: bgColor,
          leftRadius: 6,
          rightRadius: 3,
          arrowWidth: 5,
          dotSize: 5,
          dotSkip: 2,
          dotColor: Theme.of(context).colorScheme.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 5, top: 2, right: 12, bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emojiText.isNotEmpty)
                Text(emojiText, style: const TextStyle(fontSize: 14)),
              if (emojiText.isNotEmpty && label.isNotEmpty)
                const SizedBox(width: 6),
              if (label.isNotEmpty)
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: textColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _composeLabel() {
    final t = tag.title;
    final c = tag.count;
    if (t.isNotEmpty && c > 0) return '$t $c';
    if (t.isNotEmpty) return t;
    if (c > 0) return '$c';
    return '';
  }
}

class _TagChipPainter extends CustomPainter {
  final Color bgColor;
  final double leftRadius;
  final double rightRadius;
  final double arrowWidth;
  final double dotSize;
  final double dotSkip;
  final Color dotColor;

  _TagChipPainter({
    required this.bgColor,
    required this.leftRadius,
    required this.rightRadius,
    required this.arrowWidth,
    required this.dotSize,
    required this.dotSkip,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    final bodyW = w - arrowWidth;

    final path = Path();
    // Start at top-left corner
    path.moveTo(leftRadius, 0);
    path.lineTo(bodyW - rightRadius, 0);
    path.arcToPoint(Offset(bodyW, rightRadius), radius: Radius.circular(rightRadius));
    // Arrow notch (right side)
    path.lineTo(bodyW, midY - rightRadius);
    path.arcToPoint(Offset(bodyW, midY - 0.01), radius: Radius.circular(rightRadius), clockwise: false);
    path.lineTo(w, midY);
    path.lineTo(bodyW, midY + 0.01);
    path.arcToPoint(Offset(bodyW, midY + rightRadius), radius: Radius.circular(rightRadius), clockwise: false);
    path.lineTo(bodyW, h - rightRadius);
    path.arcToPoint(Offset(bodyW - rightRadius, h), radius: Radius.circular(rightRadius));
    path.lineTo(leftRadius, h);
    path.arcToPoint(Offset(0, h - leftRadius), radius: Radius.circular(leftRadius));
    path.lineTo(0, leftRadius);
    path.arcToPoint(Offset(leftRadius, 0), radius: Radius.circular(leftRadius));
    path.close();

    canvas.drawPath(path, Paint()..color = bgColor);

    // Punched-out dot near the tail
    final dotCx = bodyW + dotSkip + dotSize / 2;
    if (dotCx + dotSize / 2 <= w) {
      canvas.drawCircle(
        Offset(dotCx - dotSize / 2 + 1, midY),
        dotSize / 2,
        Paint()..color = dotColor,
      );
    }
  }

  @override
  bool shouldRepaint(_TagChipPainter old) =>
      old.bgColor != bgColor || old.dotColor != dotColor;
}

// §31.7b EditTagNameBox
class _EditTagNameDialog extends StatefulWidget {
  final String title;
  final String? emoji;
  final TextEditingController controller;
  final void Function(String text) onSave;

  const _EditTagNameDialog({
    required this.title,
    this.emoji,
    required this.controller,
    required this.onSave,
  });

  @override
  State<_EditTagNameDialog> createState() => _EditTagNameDialogState();
}

class _EditTagNameDialogState extends State<_EditTagNameDialog> {
  static const _kTagNameLimit = 12;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (_hasError && widget.controller.text.length <= _kTagNameLimit) {
      setState(() => _hasError = false);
    }
  }

  void _save() {
    final text = widget.controller.text;
    if (text.characters.length > _kTagNameLimit) {
      setState(() => _hasError = true);
      return;
    }
    widget.onSave(text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final charCount = widget.controller.text.characters.length;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Tag names are visible only to you.',
                style: TextStyle(fontSize: 13, color: theme.hintColor),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: widget.controller,
                autofocus: true,
                maxLength: _kTagNameLimit * 2,
                decoration: InputDecoration(
                  prefixText: widget.emoji != null ? '${widget.emoji} ' : null,
                  hintText: 'Tag name',
                  counterText: '$charCount/$_kTagNameLimit',
                  counterStyle: TextStyle(
                    color: charCount > _kTagNameLimit ? Colors.red : theme.hintColor,
                    fontSize: 12,
                  ),
                  errorText: _hasError ? 'Tag name is too long' : null,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// §31.2–31.3 Saved Messages Sublists View
// ══════════════════════════════════════════════════════════════════════════════

class _SavedSublistsView extends StatefulWidget {
  final ChatState chatState;
  final bool collapsed;

  const _SavedSublistsView({
    required this.chatState,
    this.collapsed = false,
  });

  @override
  State<_SavedSublistsView> createState() => _SavedSublistsViewState();
}

class _SavedSublistsViewState extends State<_SavedSublistsView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      widget.chatState.loadMoreSavedSublists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatState = widget.chatState;
    final sublists = chatState.savedSublists;
    final loading = chatState.savedSublistsLoading;
    final loadingMore = chatState.savedSublistsLoadingMore;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          _SavedSublistsHeader(
            isDark: isDark,
            onBack: chatState.closeSavedSublists,
            totalCount: chatState.savedSublistsTotalCount,
          ),
          if (chatState.savedReactionTags.isNotEmpty)
            _SearchTagsStrip(tags: chatState.savedReactionTags, chatState: chatState),
          Expanded(
            child: loading && sublists.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : sublists.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'You can save messages from\nother chats here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textTheme.bodySmall?.color ?? Colors.grey,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: sublists.length + (loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= sublists.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                            );
                          }
                          final sub = sublists[index];
                          return _SavedSublistRow(
                            sublist: sub,
                            isDark: isDark,
                            tags: chatState.savedReactionTags,
                            onTap: () {
                              chatState.openSavedSublist(sub);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SavedSublistsHeader extends StatelessWidget {
  final bool isDark;
  final VoidCallback onBack;
  final int totalCount;

  const _SavedSublistsHeader({
    required this.isDark,
    required this.onBack,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF04080E).withAlpha(86) : const Color(0x00000018),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 22),
            onPressed: onBack,
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saved Messages',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (totalCount > 0)
                  Text(
                    '$totalCount chats',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSublistRow extends StatefulWidget {
  final SavedSublistInfo sublist;
  final bool isDark;
  final VoidCallback onTap;
  final List<SavedReactionTagInfo> tags;

  const _SavedSublistRow({
    required this.sublist,
    required this.isDark,
    required this.onTap,
    this.tags = const [],
  });

  @override
  State<_SavedSublistRow> createState() => _SavedSublistRowState();
}

class _SavedSublistRowState extends State<_SavedSublistRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = widget.sublist;
    final isDark = widget.isDark;
    final hasTags = widget.tags.isNotEmpty;
    final rowHeight = hasTags ? 72.0 : 62.0;

    final bgColor = _hovered
        ? (isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1))
        : theme.colorScheme.surface;

    final timeStr = sub.lastMsgTime > 0
        ? _formatTime(DateTime.fromMillisecondsSinceEpoch(sub.lastMsgTime))
        : '';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: rowHeight,
          padding: const EdgeInsets.only(left: 10, right: 10, top: 8, bottom: 8),
          color: bgColor,
          child: Row(
            children: [
              _buildAvatar(sub, theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sub.peerName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (timeStr.isNotEmpty)
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sub.lastMsgText,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.hintColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (sub.unreadCount > 0)
                          _buildUnreadBadge(sub.unreadCount, theme),
                      ],
                    ),
                    if (hasTags) ...[
                      const SizedBox(height: 2),
                      _buildTagPills(theme, isDark),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagPills(ThemeData theme, bool isDark) {
    final tagColor = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final textColor = isDark ? const Color(0xFF8B9BAA) : const Color(0xFF999999);
    return SizedBox(
      height: 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.tags.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final tag = widget.tags[i];
          final emojiText = tag.isCustomEmoji ? '\u{2B50}' : tag.emoji;
          final label = tag.title.isNotEmpty ? tag.title : (tag.count > 0 ? '${tag.count}' : '');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emojiText.isNotEmpty)
                  Text(emojiText, style: const TextStyle(fontSize: 10)),
                if (emojiText.isNotEmpty && label.isNotEmpty)
                  const SizedBox(width: 2),
                if (label.isNotEmpty)
                  Text(label, style: TextStyle(fontSize: 10, color: textColor)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(SavedSublistInfo sub, ThemeData theme) {
    if (sub.isSelf) {
      return SizedBox(
        width: 46,
        height: 46,
        child: MyNotesUserpic(size: 46),
      );
    }
    final initials = _getInitials(sub.peerName);
    final color = _peerColor(sub.peerId);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadBadge(int count, ThemeData theme) {
    final text = count > 999 ? '999+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF40A7E3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static Color _peerColor(String peerId) {
    final id = int.tryParse(peerId) ?? 0;
    const colors = [
      Color(0xFFE17076), // red
      Color(0xFF7BC862), // green
      Color(0xFFE5CA77), // yellow
      Color(0xFF65AADD), // blue
      Color(0xFFA695E7), // purple
      Color(0xFFEE7AAE), // pink
      Color(0xFF6EC9CB), // cyan
    ];
    return colors[id.abs() % colors.length];
  }

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final diff = now.difference(dt).inDays;
    if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year % 100}';
  }
}

/// §48.11: Topic chooser dialog shown when forward-dragging onto a forum peer.
class _ForwardTopicChooserDialog extends StatelessWidget {
  final String forumTitle;
  final List<ForumTopic> topics;

  const _ForwardTopicChooserDialog({
    required this.forumTitle,
    required this.topics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                'Forward to topic in "$forumTitle"',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: topics.length,
                itemBuilder: (ctx, i) {
                  final topic = topics[i];
                  return ListTile(
                    leading: topic.id == '1'
                        ? GeneralForumTopicIcon(
                            size: ForumTopicIcon.defaultSize)
                        : ForumTopicIcon(
                            colorId: topic.colorId,
                            title: topic.title,
                            size: ForumTopicIcon.defaultSize,
                          ),
                    title: Text(
                      topic.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    dense: true,
                    onTap: () => Navigator.of(ctx).pop(topic),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFF6AB3F3)
                      : const Color(0xFF168ACD),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

