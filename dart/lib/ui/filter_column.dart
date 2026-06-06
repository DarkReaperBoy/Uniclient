import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import 'chat_list_row.dart' show ForwardDragData;
import 'confirm_box.dart' show showConfirmBox;
import 'folders_settings_screen.dart' show showEditFolderBox, FoldersSettingsScreen, SimpleLimitBox;
import 'popup_menu.dart';
import 'settings_style.dart';
import 'telegram_tooltip.dart';

/// Spec §1/§2: Vertical folder sidebar, 72px wide.
/// Hamburger menu icon at top, vertical folder buttons (scrollable),
/// "All Chats" default tab, unread badges per folder.
/// Drag-to-reorder uses raw pointer events (same approach as horizontal tabs).
class FilterColumn extends StatefulWidget {
  final VoidCallback? onOpenDrawer;

  const FilterColumn({super.key, this.onOpenDrawer});

  static const width = 72.0;

  /// Spec §13.4: Index of folder tab highlighted as drop target (-1 = none).
  static final dropHighlightIndex = ValueNotifier<int>(-1);

  static _FilterColumnState? _activeState;

  /// Hit-test folder tabs by global position. Returns folder index or -1.
  static int hitTestFolderIndex(Offset globalPos) {
    return _activeState?._hitTestTab(globalPos) ?? -1;
  }

  /// Get the folder ID at the given unified slot index, or null. Returns null
  /// for the "All Chats" slot (it is not a drop target for chats) and for
  /// out-of-range indices.
  static String? folderIdAt(int index) {
    final state = _activeState;
    if (state == null || index < 0 || index >= state._slots.length) return null;
    final folderIdx = state._slots[index];
    if (folderIdx < 0) return null; // "All Chats" slot
    final folders = state.context.read<ChatState>().folders;
    if (folderIdx >= folders.length) return null;
    return folders[folderIdx].id;
  }

  static void clearDropHighlight() {
    dropHighlightIndex.value = -1;
  }

  @override
  State<FilterColumn> createState() => _FilterColumnState();

  static const _emojiToIcon = <String, IconData>{
    '\u{1F431}': Icons.pets_outlined,              // 🐱 Cat
    '\u{1F4D5}': Icons.menu_book_outlined,          // 📕 Book
    '\u{1F4B0}': Icons.attach_money,                // 💰 Money
    '\u{1F3AE}': Icons.sports_esports_outlined,     // 🎮 Game
    '\u{1F4A1}': Icons.lightbulb_outlined,          // 💡 Light
    '\u{1F44C}': Icons.thumb_up_outlined,           // 👌 Like
    '\u{1F3B5}': Icons.music_note_outlined,         // 🎵 Note
    '\u{1F3A8}': Icons.palette_outlined,            // 🎨 Palette
    '✈️': Icons.flight_outlined,          // ✈️ Travel
    '✈': Icons.flight_outlined,                // ✈ Travel (no VS16)
    '⚽️': Icons.sports_soccer_outlined,   // ⚽️ Sport
    '⚽': Icons.sports_soccer_outlined,         // ⚽ Sport (no VS16)
    '⭐': Icons.star_outline,                   // ⭐ Favorite
    '\u{1F393}': Icons.school_outlined,             // 🎓 Study
    '\u{1F6EB}': Icons.flight_takeoff_outlined,     // 🛫 Airplane
    '\u{1F464}': Icons.person_outline,              // 👤 Private
    '\u{1F465}': Icons.group_outlined,              // 👥 Groups
    '\u{1F4AC}': Icons.chat_outlined,               // 💬 All
    '✅': Icons.mark_chat_unread_outlined,      // ✅ Unread
    '\u{1F916}': Icons.smart_toy_outlined,          // 🤖 Bots
    '\u{1F451}': Icons.workspace_premium_outlined,  // 👑 Crown
    '\u{1F339}': Icons.local_florist_outlined,      // 🌹 Flower
    '\u{1F3E0}': Icons.home_outlined,               // 🏠 Home
    '❤': Icons.favorite_outline,               // ❤ Love
    '❤️': Icons.favorite_outline,         // ❤️ Love (with VS16)
    '\u{1F3AD}': Icons.theater_comedy_outlined,     // 🎭 Mask
    '\u{1F378}': Icons.local_bar_outlined,          // 🍸 Party
    '\u{1F4C8}': Icons.trending_up,                 // 📈 Trade
    '\u{1F4BC}': Icons.work_outline,                // 💼 Work
    '\u{1F514}': Icons.notifications_active_outlined, // 🔔 Unmuted
    '\u{1F4E2}': Icons.campaign_outlined,           // 📢 Channels
    '\u{1F4C1}': Icons.folder_outlined,             // 📁 Custom
    '\u{1F4CB}': Icons.assignment_outlined,         // 📋 Setup
  };

  /// Matches AyuGram's ComputeFilterIcon: emoji lookup then flag-based default.
  static IconData folderIconForInfo(FolderInfo folder) {
    if (folder.emoticon.isNotEmpty) {
      final icon = _emojiToIcon[folder.emoticon];
      if (icon != null) return icon;
    }
    return _computeDefaultFilterIcon(folder);
  }

  /// Matches AyuGram's ComputeDefaultFilterIcon (filter_icons.cpp:241-278).
  static IconData _computeDefaultFilterIcon(FolderInfo folder) {
    final hasAlways = folder.chatIds.isNotEmpty;
    final hasNever = folder.excludeChatIds.isNotEmpty;
    if (hasAlways || hasNever || !folder.hasTypeFilters) {
      return Icons.folder_outlined;
    }
    final onlyContacts = (folder.contacts || folder.nonContacts)
        && !folder.groups && !folder.channels && !folder.bots;
    if (onlyContacts) return Icons.person_outline;
    if (folder.groups && !folder.contacts && !folder.nonContacts
        && !folder.channels && !folder.bots) {
      return Icons.group_outlined;
    }
    if (folder.channels && !folder.contacts && !folder.nonContacts
        && !folder.groups && !folder.bots) {
      return Icons.campaign_outlined;
    }
    if (folder.bots && !folder.contacts && !folder.nonContacts
        && !folder.groups && !folder.channels) {
      return Icons.smart_toy_outlined;
    }
    if (folder.excludeRead) return Icons.mark_chat_unread_outlined;
    if (folder.excludeMuted) return Icons.notifications_active_outlined;
    return Icons.folder_outlined;
  }
}

const int _kMaxUnreadWithoutConfirmation = 1000;

class _FilterColumnState extends State<FilterColumn> {
  final ScrollController _scrollController = ScrollController();

  String? _prevActiveFolderId;
  bool _prevActiveFolderTracked = false;

  // Raw-pointer drag state (mirrors horizontal tab approach).
  int? _dragIndex; // unified slot index being dragged (null = not tracking)
  int? _dragPointer; // pointer ID we're tracking
  double _dragOffset = 0; // vertical pixel offset of the dragged tab
  Offset? _dragStart; // pointer-down position to measure threshold
  bool _dragActive = false; // true once threshold exceeded

  final List<GlobalKey> _tabKeys = [];

  // Unified reorderable list = [All Chats?] + folders, mirroring AyuGram's
  // `_list`. Each slot maps to a folder index (>= 0) or the "All Chats" tab
  // (-1). The All tab joins the list so it scrolls and (for premium users)
  // reorders. Its position is not persisted by the engine (getFolders skips
  // dialogFilterDefault), so it is tracked here for the session.
  int _allIndex = 0; // position of the "All Chats" tab among folders
  List<int> _slots = const []; // unified slot -> folder index (-1 = All Chats)
  // Drag constraints snapshot, recomputed each build (AyuGram pinned intervals).
  bool _premiumSnapshot = false;
  int _premiumFromUnified = 1 << 30; // first locked (pinned) unified slot
  int _dragLowerBound = 0; // lowest slot a drag may land on
  int _dragUpperBound = 1 << 30; // highest slot a drag may land on

  // Spec §13.4: kFreezeTimeout — auto-switch folder after 2s hover while dragging.
  Timer? _autoSwitchTimer;
  int _autoSwitchPendingIdx = -1;

  @override
  void initState() {
    super.initState();
    FilterColumn._activeState = this;
    FilterColumn.dropHighlightIndex.addListener(_onDropHighlightChanged);
  }

  void _onDropHighlightChanged() {
    final idx = FilterColumn.dropHighlightIndex.value;
    if (idx != _autoSwitchPendingIdx) {
      _autoSwitchTimer?.cancel();
      _autoSwitchPendingIdx = idx;
      if (idx >= 0) {
        _autoSwitchTimer = Timer(const Duration(milliseconds: 1000), () {
          if (!mounted) return;
          final folderId = FilterColumn.folderIdAt(idx);
          if (folderId != null) {
            context.read<ChatState>().setActiveFolder(folderId);
          }
        });
      }
    }
  }

  void _syncTabKeys(int count) {
    while (_tabKeys.length < count) {
      _tabKeys.add(GlobalKey());
    }
    if (_tabKeys.length > count) {
      _tabKeys.removeRange(count, _tabKeys.length);
    }
  }

  @override
  void dispose() {
    _autoSwitchTimer?.cancel();
    FilterColumn.dropHighlightIndex.removeListener(_onDropHighlightChanged);
    if (FilterColumn._activeState == this) FilterColumn._activeState = null;
    _scrollController.dispose();
    super.dispose();
  }

  // --- Drag reorder via raw Listener events ---

  /// Determine which folder tab index a global position falls on, or -1.
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
    if (tabIdx < 0 || tabIdx >= _slots.length) return;
    // AyuGram pinned-interval guard (window_filters_menu.cpp:228): the "All
    // Chats" tab is pinned for non-premium users, and folders past the limit
    // (the locked region rendered at 0.6 opacity) cannot be picked up.
    final folderIdx = _slots[tabIdx];
    if (folderIdx < 0) {
      if (!_premiumSnapshot) return; // All Chats is pinned for free users
    } else if (tabIdx >= _premiumFromUnified) {
      return; // locked folder — pinned, not draggable
    }
    _dragPointer = event.pointer;
    _dragIndex = tabIdx;
    _dragStart = event.position;
    _dragOffset = 0;
    _dragActive = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragPointer != event.pointer || _dragIndex == null) return;
    final dy = event.position.dy - _dragStart!.dy;
    // Spec §2: drag threshold = 10px
    if (!_dragActive && dy.abs() < 10) return;
    if (!_dragActive) {
      _dragActive = true;
    }
    setState(() => _dragOffset = dy);
    _autoScrollDuringDrag(event.position);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_dragPointer != event.pointer) return;
    if (_dragActive && _dragIndex != null) {
      final targetIndex = _computeDropIndex();
      if (targetIndex != null && targetIndex != _dragIndex!) {
        _applyReorder(_dragIndex!, targetIndex);
      }
    }
    _cancelDrag();
  }

  /// Move the dragged unified slot to [target] and persist the new order
  /// (mirrors AyuGram `applyReorder`). Updates the session-tracked "All Chats"
  /// position and forwards the full id order (with `'0'` for All) to the engine.
  void _applyReorder(int from, int target) {
    if (from < 0 || from >= _slots.length) return;
    final chatState = context.read<ChatState>();
    final folders = chatState.folders;
    final newSlots = List<int>.from(_slots);
    // Same convention as ChatState.reorderFolders: decrement when moving down.
    var insertAt = target;
    if (insertAt > from) insertAt--;
    insertAt = insertAt.clamp(0, newSlots.length - 1);
    final moved = newSlots.removeAt(from);
    newSlots.insert(insertAt, moved);
    final allPos = newSlots.indexOf(-1);
    if (allPos >= 0) {
      // Number of folders preceding the All Chats slot == its folder position.
      _allIndex = newSlots.take(allPos).where((s) => s >= 0).length;
    }
    final orderedIds = newSlots
        .map((s) => (s < 0 || s >= folders.length) ? '0' : folders[s].id)
        .toList();
    chatState.applyFolderOrder(orderedIds);
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
      positions.add(box.localToGlobal(Offset(0, box.size.height / 2)).dy);
    }
    final draggedBox =
        _tabKeys[_dragIndex!].currentContext?.findRenderObject() as RenderBox?;
    if (draggedBox == null) return null;
    final draggedCenter =
        draggedBox.localToGlobal(Offset(0, draggedBox.size.height / 2)).dy +
            _dragOffset;
    int target = _dragIndex!;
    for (var i = 0; i < positions.length; i++) {
      if (i == _dragIndex!) continue;
      if (i < _dragIndex! && draggedCenter < positions[i]) {
        target = i;
        break;
      }
      if (i > _dragIndex! && draggedCenter > positions[i]) {
        target = i;
      }
    }
    // AyuGram pinned intervals: a drag may only land inside the non-pinned span
    // (after a pinned "All Chats", before the locked-folder region).
    if (_dragLowerBound > _dragUpperBound) return target;
    return target.clamp(_dragLowerBound, _dragUpperBound);
  }

  void _autoScrollDuringDrag(Offset globalPos) {
    if (!_scrollController.hasClients) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPos);
    final height = box.size.height;
    const edgeZone = 40.0;
    const scrollFactor = 0.05;
    if (local.dy < edgeZone) {
      final dist = edgeZone - local.dy;
      _scrollController.jumpTo(
        (_scrollController.offset - dist * scrollFactor)
            .clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    } else if (local.dy > height - edgeZone) {
      final dist = local.dy - (height - edgeZone);
      _scrollController.jumpTo(
        (_scrollController.offset + dist * scrollFactor)
            .clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  /// Compute how much a non-dragged tab should shift vertically.
  double _computeShiftForTab(int tabIndex) {
    if (_dragIndex == null || !_dragActive) return 0;
    final draggedBox =
        _tabKeys[_dragIndex!].currentContext?.findRenderObject() as RenderBox?;
    if (draggedBox == null) return 0;
    final draggedHeight = draggedBox.size.height;
    final draggedCenter =
        draggedBox.localToGlobal(Offset(0, draggedHeight / 2)).dy + _dragOffset;
    final thisBox =
        _tabKeys[tabIndex].currentContext?.findRenderObject() as RenderBox?;
    if (thisBox == null) return 0;
    final thisCenter =
        thisBox.localToGlobal(Offset(0, thisBox.size.height / 2)).dy;

    if (_dragIndex! < tabIndex && draggedCenter > thisCenter) {
      return -draggedHeight;
    }
    if (_dragIndex! > tabIndex && draggedCenter < thisCenter) {
      return draggedHeight;
    }
    return 0;
  }

  void _onFolderTap(FolderInfo folder, String? activeFolderId) {
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();
    final isPremium = appState.effectivePremium;
    final folders = chatState.folders;
    final folderIndex = folders.indexOf(folder);
    final folderLimit = isPremium
        ? chatState.folderLimitPremium
        : chatState.folderLimitFree;
    if (folderIndex >= folderLimit) {
      _showFolderLimitDialog(chatState, isPremium);
      return;
    }
    chatState.setActiveFolder(folder.id);
    _scrollToActiveTab(folderIndex);
  }

  void _showFolderLimitDialog(ChatState chatState, bool isPremium) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = chatState.folders.length;
    final limitFree = chatState.folderLimitFree;
    final limitPremium = chatState.folderLimitPremium;
    final limit = isPremium ? limitPremium : limitFree;
    showDialog(
      context: context,
      builder: (_) => SimpleLimitBox(
        isDark: isDark,
        title: 'Folder Limit Reached',
        current: current,
        limitFree: limitFree,
        limitPremium: limitPremium,
        isPremium: isPremium,
        icon: Icons.folder_outlined,
        description: isPremium
            ? 'You have reached the maximum limit of $limit folders.'
            : 'You have reached the limit of $limit folders. '
              'Subscribe to Telegram Premium to increase the limit to $limitPremium.',
      ),
    );
  }

  void _showAllChatsContextMenu(BuildContext context, Offset globalPosition) {
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();
    final allUnread = chatState.unreadCountForAccount(appState.activeAccountId);

    showTelegramMenu<String>(
      context: context,
      position: globalPosition,
      items: [
        if (allUnread > 0)
          const TelegramMenuItem(
            value: 'mark_read',
            icon: Icon(Icons.done_all),
            label: 'Mark All as Read',
          ),
        const TelegramMenuItem(
          value: 'settings',
          icon: Icon(Icons.edit),
          label: 'Edit Folders',
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'mark_read':
          _markAsReadWithConfirmation(allUnread, () {
            final chats = chatState.chatsForFolder(null);
            for (final chat in chats) {
              if (chat.unreadCount > 0) {
                chatState.markChatRead(chat.accountId, chat.chatId);
              }
            }
          });
        case 'settings':
          _openFoldersSettings();
      }
    });
  }

  void _markAsReadWithConfirmation(int totalUnread, VoidCallback onConfirm) {
    if (totalUnread > _kMaxUnreadWithoutConfirmation) {
      showConfirmBox(
        context,
        text: 'Are you sure you want to mark all messages as read?',
        confirmText: 'Mark',
        onConfirm: onConfirm,
      );
    } else {
      onConfirm();
    }
  }

  /// Map a folder index to its position in the unified reorderable list.
  int _folderToUnified(int folderIndex) {
    for (var u = 0; u < _slots.length; u++) {
      if (_slots[u] == folderIndex) return u;
    }
    return -1;
  }

  void _scrollToActiveTab(int folderIndex) {
    final index = _folderToUnified(folderIndex);
    if (!_scrollController.hasClients || index < 0 || index >= _tabKeys.length) {
      return;
    }
    final box = _tabKeys[index].currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final scrollBox = context.findRenderObject() as RenderBox?;
    if (scrollBox == null) return;
    final tabTop = box.localToGlobal(Offset.zero).dy -
        scrollBox.localToGlobal(Offset.zero).dy +
        _scrollController.offset;
    final tabBottom = tabTop + box.size.height;
    final viewStart = _scrollController.offset;
    final viewEnd = viewStart + _scrollController.position.viewportDimension;
    if (tabTop < viewStart) {
      _scrollController.animateTo(
        tabTop,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInOutSine,
      );
    } else if (tabBottom > viewEnd) {
      _scrollController.animateTo(
        _scrollController.offset + (tabBottom - viewEnd),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInOutSine,
      );
    }
  }

  void _showFolderContextMenu(
      BuildContext context, FolderInfo folder, Offset globalPosition) {
    final chatState = context.read<ChatState>();
    final unread = chatState.unreadCountForFolder(folder.id);

    showTelegramMenu<String>(
      context: context,
      position: globalPosition,
      items: [
        const TelegramMenuItem(
          value: 'edit',
          icon: Icon(Icons.edit),
          label: 'Edit Folder',
        ),
        if (unread > 0)
          const TelegramMenuItem(
            value: 'mark_read',
            icon: Icon(Icons.done_all),
            label: 'Mark All as Read',
          ),
        const TelegramMenuItem(
          value: 'remove_folder',
          icon: Icon(Icons.delete_outline),
          label: 'Remove Folder',
          isAttention: true,
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'mark_read':
          _markAsReadWithConfirmation(unread, () {
            final chats = chatState.chatsForFolder(folder.id);
            for (final chat in chats) {
              if (chat.unreadCount > 0) {
                chatState.markChatRead(chat.accountId, chat.chatId);
              }
            }
          });
        case 'edit':
          showEditFolderBox(context, folder);
        case 'remove_folder':
          _confirmRemoveFolder(folder);
      }
    });
  }

  void _confirmRemoveFolder(FolderInfo folder) {
    final hasLinks = folder.isChatList;
    showConfirmBox(
      context,
      text: hasLinks
          ? 'Are you sure you want to delete this folder? '
            'This will also deactivate all invite links associated with the folder.'
          : 'Are you sure you want to remove "${folder.name}"?',
      confirmText: hasLinks ? 'Delete' : 'Remove',
      isDestructive: hasLinks,
      onConfirm: () => _executeRemoveFolder(folder),
    );
  }

  void _executeRemoveFolder(FolderInfo folder) {
    if (!mounted) return;
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;

    if (!folder.isChatList) {
      chatState.deleteFolder(account.id, folder.id);
      return;
    }

    final folderId = int.tryParse(folder.id) ?? 0;
    final engine = context.read<EngineService>();
    engine.getLeaveChatlistSuggestions(account.id, folderId).then((suggestions) {
      if (!mounted) return;
      if (suggestions.isEmpty) {
        chatState.deleteFolder(account.id, folder.id);
        return;
      }
      _showLeaveChatlistDialog(folder, account.id, folderId, suggestions);
    }).catchError((_) {
      if (mounted) chatState.deleteFolder(account.id, folder.id);
    });
  }

  void _showLeaveChatlistDialog(
    FolderInfo folder, String accountId, int folderId, List<String> suggestions,
  ) {
    final chatState = context.read<ChatState>();
    final selected = Set<String>.from(suggestions);
    showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final palette = PaletteProvider.of(ctx);
          return AlertDialog(
            title: const Text('Leave Chats'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Do you also want to leave these group chats?',
                    style: TextStyle(color: palette.boxTextFg),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: suggestions.length,
                      itemBuilder: (_, i) {
                        final peerId = suggestions[i];
                        final chat = chatState.chats.where((c) => c.chatId == peerId).firstOrNull;
                        final title = chat?.title ?? peerId;
                        return CheckboxListTile(
                          dense: true,
                          value: selected.contains(peerId),
                          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selected.add(peerId);
                              } else {
                                selected.remove(peerId);
                              }
                            });
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
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(selected),
                child: Text(
                  'Delete Folder',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            ],
          );
        });
      },
    ).then((result) {
      if (result == null || !mounted) return;
      final engine = context.read<EngineService>();
      if (result.isNotEmpty) {
        engine.leaveChatlistFolder(accountId, folderId, result.toList()).then((_) {
          if (mounted) chatState.deleteFolder(accountId, folder.id);
        }).catchError((_) {
          if (mounted) chatState.deleteFolder(accountId, folder.id);
        });
      } else {
        chatState.deleteFolder(accountId, folder.id);
      }
    });
  }

  bool _waitingSuggested = false;

  void _openFoldersSettings() {
    final appState = context.read<AppState>();
    final chatState = context.read<ChatState>();
    final account = appState.activeAccount;

    void navigate() {
      if (!mounted) return;
      Navigator.of(context).push(
        settingsPageRoute(
          ChangeNotifierProvider.value(
            value: appState,
            child: ChangeNotifierProvider.value(
              value: chatState,
              child: const FoldersSettingsScreen(),
            ),
          ),
        ),
      );
    }

    if (account == null) {
      navigate();
      return;
    }

    if (_waitingSuggested) return;
    _waitingSuggested = true;

    final engine = context.read<EngineService>();
    engine.getSuggestedFolders(account.id).then((_) {
      _waitingSuggested = false;
      navigate();
    }).catchError((_) {
      _waitingSuggested = false;
      navigate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final appState = context.watch<AppState>();
    final folders = chatState.folders;
    final activeFolderId = chatState.activeFolderId;
    int otherAccountsUnread = 0;
    for (final acc in appState.accounts) {
      if (acc.id != appState.activeAccountId) {
        otherAccountsUnread += chatState.unreadCountForAccount(acc.id);
      }
    }

    final isPremium = appState.effectivePremium;
    final folderLimit = isPremium
        ? chatState.folderLimitPremium
        : chatState.folderLimitFree;
    final showAll = !appState.hideAllChatsFolder;

    // Build the unified reorderable list = [All Chats?] + folders, mirroring
    // AyuGram's `_list`. For free users "All Chats" is pinned at the top
    // (AyuGram pins interval [0,1)); premium users may reposition it, so its
    // session position is honoured only when premium.
    final effectiveAllIdx = isPremium ? _allIndex.clamp(0, folders.length) : 0;
    final slots = <int>[];
    for (var f = 0; f <= folders.length; f++) {
      if (showAll && f == effectiveAllIdx) slots.add(-1);
      if (f < folders.length) slots.add(f);
    }
    _slots = slots;
    _syncTabKeys(slots.length);

    // AyuGram pinned-interval math (window_filters_menu.cpp:223-237): the first
    // locked unified slot is the first folder slot past the current limit.
    _premiumSnapshot = isPremium;
    var premiumFromUnified = slots.length;
    for (var u = 0; u < slots.length; u++) {
      if (slots[u] >= 0 && slots[u] >= folderLimit) {
        premiumFromUnified = u;
        break;
      }
    }
    _premiumFromUnified = premiumFromUnified;
    final allSlotUnified = showAll ? slots.indexOf(-1) : -1;
    _dragLowerBound = (!isPremium && allSlotUnified == 0) ? 1 : 0;
    _dragUpperBound = premiumFromUnified - 1;

    if (activeFolderId != null) {
      final activeIdx = folders.indexWhere((f) => f.id == activeFolderId);
      if (activeIdx >= 0 && activeIdx >= folderLimit) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) chatState.setActiveFolder(null);
        });
      }
    }

    if (!_prevActiveFolderTracked) {
      _prevActiveFolderId = activeFolderId;
      _prevActiveFolderTracked = true;
    } else if (_prevActiveFolderId != activeFolderId) {
      _prevActiveFolderId = activeFolderId;
      final newIdx = activeFolderId == null
          ? -1
          : folders.indexWhere((f) => f.id == activeFolderId);
      if (newIdx >= 0) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToActiveTab(newIdx);
        });
      }
    }

    bool _isOtherAccountsAllMuted(AppState appState, ChatState chatState) {
      for (final acc in appState.accounts) {
        if (acc.id != appState.activeAccountId) {
          if (!chatState.isAccountUnreadAllMuted(acc.id)) return false;
        }
      }
      return true;
    }

    final physics = _dragActive
        ? const NeverScrollableScrollPhysics()
        : const ClampingScrollPhysics();

    final palette = PaletteProvider.of(context);

    return Container(
      width: FilterColumn.width,
      color: palette.sideBarBg,
      child: Column(
        children: [
          // Hamburger menu button at top — the ONLY fixed element (AyuGram
          // `_menu`); everything below scrolls together inside `_scroll`.
          _SideBarButton(
            icon: Icons.menu,
            label: 'Menu',
            isActive: false,
            unreadCount: appState.hideNotificationCounters ? 0 : otherAccountsUnread,
            unreadAllMuted: otherAccountsUnread > 0 && _isOtherAccountsAllMuted(appState, chatState),
            minHeight: 54,
            iconCentered: true,
            useDotBadge: true,
            onTap: widget.onOpenDrawer ?? () {},
          ),
          // AyuGram `_container` (owned by `_scroll`): "All Chats", the folder
          // `_list` and the "Edit" `_setup` button all scroll as one column.
          Expanded(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: physics,
                child: ValueListenableBuilder<int>(
                  valueListenable: FilterColumn.dropHighlightIndex,
                  builder: (context, dropIdx, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var u = 0; u < _slots.length; u++)
                        _buildReorderSlot(context, u, dropIdx, activeFolderId,
                            folderLimit, appState, chatState),
                      // "Edit" setup button — scrolls with the list but is not
                      // part of the reorderable `_list` (no tab key).
                      _SideBarButton(
                        icon: Icons.edit,
                        label: 'Edit',
                        isActive: false,
                        unreadCount: 0,
                        onTap: () => _openFoldersSettings(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build one slot of the unified reorderable list (the "All Chats" tab or a
  /// folder tab), including the drag transform, chat-drop target and badge.
  Widget _buildReorderSlot(
    BuildContext context,
    int u,
    int dropIdx,
    String? activeFolderId,
    int folderLimit,
    AppState appState,
    ChatState chatState,
  ) {
    final folders = chatState.folders;
    final folderIdx = _slots[u];
    final isAll = folderIdx < 0;
    final folder = isAll ? null : folders[folderIdx];
    final isLocked = !isAll && folderIdx >= folderLimit;

    // Item 1: badge shows the count of unread CHATS, not summed messages.
    final badge = appState.hideNotificationCounters
        ? (count: 0, allMuted: false)
        : chatState.folderUnreadBadge(folder?.id,
            includeMuted: appState.notifIncludeMutedInFolders);

    final isDragged = _dragActive && _dragIndex == u;
    final shift = _computeShiftForTab(u);
    final isDropTarget = dropIdx == u;

    final button = _SideBarButton(
      icon: isAll ? Icons.chat : FilterColumn.folderIconForInfo(folder!),
      label: isAll ? 'All' : folder!.name,
      isActive: isAll ? activeFolderId == null : activeFolderId == folder!.id,
      unreadCount: badge.count,
      unreadAllMuted: badge.allMuted,
      locked: isLocked,
      forceRippled: isDropTarget,
      onTap: _dragActive
          ? () {}
          : isAll
              ? () => chatState.setActiveFolder(null)
              : () => _onFolderTap(folder!, activeFolderId),
    );

    return AnimatedContainer(
      key: _tabKeys[u],
      duration: (_dragActive && !isDragged)
          ? const Duration(milliseconds: 150)
          : Duration.zero,
      transform: Matrix4.translationValues(
        0,
        isDragged ? _dragOffset : shift,
        isDragged ? 1 : 0,
      ),
      child: Opacity(
        opacity: isDragged ? 0.8 : 1.0,
        child: DragTarget<ForwardDragData>(
          onWillAcceptWithDetails: (_) => !isAll,
          onMove: (_) {
            if (!isAll && FilterColumn.dropHighlightIndex.value != u) {
              FilterColumn.dropHighlightIndex.value = u;
            }
          },
          onLeave: (_) {
            if (FilterColumn.dropHighlightIndex.value == u) {
              FilterColumn.dropHighlightIndex.value = -1;
            }
          },
          onAcceptWithDetails: (_) {
            FilterColumn.clearDropHighlight();
          },
          builder: (context, candidateData, rejectedData) => GestureDetector(
            onSecondaryTapUp: _dragActive
                ? null
                : (details) => isAll
                    ? _showAllChatsContextMenu(context, details.globalPosition)
                    : _showFolderContextMenu(
                        context, folder!, details.globalPosition),
            child: button,
          ),
        ),
      ),
    );
  }
}

/// Spec-accurate SideBarButton matching Telegram Desktop's windowFiltersButton.
/// Layout from AyuGram side_bar_button.cpp + window.style:
///   minHeight: 62px, textTop: 40px, textSkip: 6px, font: 11px semibold,
///   iconPosition: point(-1, 6) = centered horizontally, 6px from top,
///   badgeHeight: 17px, badgePosition: point(3, 7), badgeSkip: 4px.
///   Active state: full-width rect fill with sideBarBgActive (no border radius).
class _SideBarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final int unreadCount;
  final bool unreadAllMuted;
  final VoidCallback onTap;
  final double minHeight;
  final bool iconCentered;
  final bool useDotBadge;
  final bool locked;
  final bool forceRippled;

  const _SideBarButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.unreadCount,
    this.unreadAllMuted = false,
    required this.onTap,
    this.minHeight = 62,
    this.iconCentered = false,
    this.useDotBadge = false,
    this.locked = false,
    this.forceRippled = false,
  });

  @override
  State<_SideBarButton> createState() => _SideBarButtonState();
}

class _SideBarButtonState extends State<_SideBarButton>
    with SingleTickerProviderStateMixin {
  static const _kPremiumLockedOpacity = 0.6;

  late final AnimationController _rippleController;
  late final Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _rippleAnimation = CurvedAnimation(
      parent: _rippleController,
      curve: Curves.easeInOut,
    );
    if (widget.forceRippled) _rippleController.forward();
  }

  @override
  void didUpdateWidget(_SideBarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceRippled != oldWidget.forceRippled) {
      if (widget.forceRippled) {
        _rippleController.forward();
      } else {
        _rippleController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  static const int _kMaxLabelLines = 3;
  static const double _textTop = 40;
  static const double _textSkip = 6;
  static const double _iconSize = 24;
  static const double _iconTop = 6;
  static const double _badgeHeight = 17;
  static const double _badgeSkip = 4;
  static const double _badgePosX = 3;
  static const double _badgePosY = 7;
  static const double _badgeStroke = 2;
  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final bgColor = widget.isActive ? palette.sideBarBgActive : palette.sideBarBg;
    final iconColor = widget.isActive ? palette.sideBarIconFgActive : palette.sideBarIconFg;
    final textColor = widget.isActive ? palette.sideBarTextFgActive : palette.sideBarTextFg;

    Widget button = TelegramTooltip(
      message: widget.label,
      child: Material(
        color: bgColor,
        child: InkWell(
          onTap: widget.onTap,
          splashColor: palette.sideBarBgRipple,
          highlightColor: palette.sideBarBgRipple,
          child: SizedBox(
            width: FilterColumn.width,
            child: widget.iconCentered
                ? _buildCenteredIcon(context, iconColor)
                : _buildFullButton(context, iconColor, textColor),
          ),
        ),
      ),
    );

    if (widget.forceRippled) {
      button = AnimatedBuilder(
        animation: _rippleAnimation,
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              if (_rippleAnimation.value > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _rippleAnimation.value * 0.12,
                      child: Container(color: palette.sideBarBgRipple),
                    ),
                  ),
                ),
            ],
          );
        },
        child: button,
      );
    }

    if (widget.locked) {
      button = Opacity(
        opacity: _kPremiumLockedOpacity,
        child: button,
      );
    }

    return button;
  }

  Widget _buildCenteredIcon(BuildContext context, Color iconColor) {
    final palette = PaletteProvider.of(context);
    final showDot = widget.unreadCount > 0 && widget.useDotBadge;
    final dotColor = showDot
        ? (widget.unreadAllMuted
            ? palette.sideBarBadgeBgMuted
            : palette.sideBarBadgeBg)
        : null;
    return SizedBox(
      height: widget.minHeight,
      child: Center(
        child: CustomPaint(
          foregroundPainter: dotColor != null
              ? _MenuDotPainter(dotColor: dotColor, iconSize: _iconSize)
              : null,
          child: Icon(widget.icon, size: _iconSize, color: iconColor),
        ),
      ),
    );
  }

  Widget _buildFullButton(BuildContext context, Color iconColor, Color textColor) {
    final effectiveUnread = widget.locked ? 0 : widget.unreadCount;

    // Item 2 — AyuGram SideBarButton::resizeGetHeight (side_bar_button.cpp:109):
    //   height = minHeight + max(0, min(textHeight, font.height * 3) - font.height)
    // The button grows downward for 2–3 line folder names; the icon, badge and
    // text-top stay pinned. Pre-measure the label so the layout delegate can
    // report the grown height (a MultiChildLayoutDelegate can't size to its
    // children, so the measurement happens here).
    const labelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
    final measureText = widget.locked ? '   ${widget.label}' : widget.label;
    final painter = TextPainter(
      text: TextSpan(text: measureText, style: labelStyle),
      maxLines: _kMaxLabelLines,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: FilterColumn.width - 2 * _textSkip);
    final lineHeight = painter.preferredLineHeight;
    final extra = math.max(
      0.0,
      math.min(painter.height, lineHeight * _kMaxLabelLines) - lineHeight,
    );
    final totalHeight = widget.minHeight + extra;

    return CustomMultiChildLayout(
      delegate: _SideBarButtonLayout(
        minHeight: widget.minHeight,
        totalHeight: totalHeight,
        textTop: _textTop,
        textSkip: _textSkip,
        iconTop: _iconTop,
        iconSize: _iconSize,
        badgePosX: _badgePosX,
        badgePosY: _badgePosY,
        badgeHeight: _badgeHeight,
        hasBadge: effectiveUnread > 0,
        hasLockIcon: widget.locked,
      ),
      children: [
        LayoutId(
          id: _SideBarSlot.icon,
          child: Icon(widget.icon, size: _iconSize, color: iconColor),
        ),
        LayoutId(
          id: _SideBarSlot.label,
          child: widget.locked
              ? Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: CustomPaint(
                            size: const Size(9, 10),
                            painter: _LockIconPainter(color: textColor),
                          ),
                        ),
                      ),
                      TextSpan(text: widget.label),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: _kMaxLabelLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: _kMaxLabelLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
        ),
        if (effectiveUnread > 0)
          LayoutId(
            id: _SideBarSlot.badge,
            child: _buildBadge(context, effectiveUnread),
          ),
      ],
    );
  }

  Widget _buildBadge(BuildContext context, [int? count]) {
    final palette = PaletteProvider.of(context);
    final effectiveCount = count ?? widget.unreadCount;
    final badgeColor = (widget.unreadAllMuted && !widget.isActive)
        ? palette.sideBarBadgeBgMuted
        : palette.sideBarBadgeBg;
    final text = effectiveCount > 999 ? '99+' : '$effectiveCount';
    return Container(
      height: _badgeHeight,
      constraints: BoxConstraints(minWidth: _badgeHeight),
      padding: EdgeInsets.symmetric(horizontal: _badgeSkip),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(_badgeHeight / 2),
        border: Border.all(
          color: palette.sideBarBg,
          width: _badgeStroke,
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: palette.sideBarBadgeFg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

enum _SideBarSlot { icon, label, badge }

class _SideBarButtonLayout extends MultiChildLayoutDelegate {
  final double minHeight;
  final double totalHeight;
  final double textTop;
  final double textSkip;
  final double iconTop;
  final double iconSize;
  final double badgePosX;
  final double badgePosY;
  final double badgeHeight;
  final bool hasBadge;
  final bool hasLockIcon;

  _SideBarButtonLayout({
    required this.minHeight,
    required this.totalHeight,
    required this.textTop,
    required this.textSkip,
    required this.iconTop,
    required this.iconSize,
    required this.badgePosX,
    required this.badgePosY,
    required this.badgeHeight,
    required this.hasBadge,
    this.hasLockIcon = false,
  });

  @override
  void performLayout(Size size) {
    final w = size.width;

    // Icon: centered horizontally, iconTop from top.
    if (hasChild(_SideBarSlot.icon)) {
      layoutChild(_SideBarSlot.icon, BoxConstraints.tight(Size(iconSize, iconSize)));
      positionChild(_SideBarSlot.icon, Offset((w - iconSize) / 2, iconTop));
    }

    // Label: textSkip from each side, textTop from top, max 3 lines.
    if (hasChild(_SideBarSlot.label)) {
      final labelWidth = w - 2 * textSkip;
      final labelSize = layoutChild(
        _SideBarSlot.label,
        BoxConstraints(maxWidth: labelWidth),
      );
      positionChild(
        _SideBarSlot.label,
        Offset((w - labelSize.width) / 2, textTop),
      );
    }

    // Badge: offset from center of button.
    if (hasBadge && hasChild(_SideBarSlot.badge)) {
      final badgeSize = layoutChild(
        _SideBarSlot.badge,
        BoxConstraints(maxHeight: badgeHeight),
      );
      final desiredLeft = w / 2 + badgePosX;
      final clampedLeft = desiredLeft.clamp(0.0, w - badgeSize.width);
      positionChild(_SideBarSlot.badge, Offset(clampedLeft, badgePosY));
    }
  }

  @override
  Size getSize(BoxConstraints constraints) {
    // Item 2: grown height (minHeight for 1-line labels, taller for 2–3 lines).
    return Size(constraints.maxWidth, totalHeight);
  }

  @override
  bool shouldRelayout(_SideBarButtonLayout oldDelegate) {
    return minHeight != oldDelegate.minHeight
        || totalHeight != oldDelegate.totalHeight
        || hasBadge != oldDelegate.hasBadge
        || hasLockIcon != oldDelegate.hasLockIcon;
  }
}

class _MenuDotPainter extends CustomPainter {
  final Color dotColor;
  final double iconSize;

  _MenuDotPainter({required this.dotColor, required this.iconSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor
      ..isAntiAlias = true;
    canvas.drawCircle(
      Offset(size.width - 1, 3),
      3,
      paint,
    );
  }

  @override
  bool shouldRepaint(_MenuDotPainter oldDelegate) =>
      dotColor != oldDelegate.dotColor;
}

/// Custom-drawn padlock matching AyuGram's SideBarLockIcon.
/// Dimensions from widgets.style:1689-1694:
///   size: 9×10, arcHeight: 3, blockHeight: 5, arcOffset: 2, penWidth: 1.5
class _LockIconPainter extends CustomPainter {
  final Color color;
  _LockIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 9.0;
    final sy = size.height / 10.0;
    final pw = 1.5 * math.min(sx, sy);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Block (body): full width, bottom 5 units
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 5 * sy, size.width, 5 * sy),
        Radius.circular(1 * sx),
      ),
      fillPaint,
    );

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = pw
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    // Left vertical line: (2, blockTop) → (2, arcBottom)
    canvas.drawLine(Offset(2 * sx, 5 * sy), Offset(2 * sx, 3 * sy), strokePaint);
    // Right vertical line: (7, blockTop) → (7, arcBottom)
    canvas.drawLine(Offset(7 * sx, 5 * sy), Offset(7 * sx, 3 * sy), strokePaint);

    // Semicircle shackle: top half of oval from (2,0) to (7,6)
    final arcOval = Rect.fromLTWH(2 * sx, 0, 5 * sx, 6 * sy);
    canvas.drawArc(arcOval, math.pi, -math.pi, false, strokePaint);
  }

  @override
  bool shouldRepaint(_LockIconPainter old) => color != old.color;
}
