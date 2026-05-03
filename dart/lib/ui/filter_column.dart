import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'chat_list_row.dart' show ForwardDragData;
import 'popup_menu.dart';
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

  /// Get the folder ID at the given tab index, or null.
  static String? folderIdAt(int index) {
    if (_activeState == null || index < 0) return null;
    final chatState = _activeState!.context.read<ChatState>();
    final folders = chatState.folders;
    if (index >= folders.length) return null;
    return folders[index].id;
  }

  static void clearDropHighlight() {
    dropHighlightIndex.value = -1;
  }

  @override
  State<FilterColumn> createState() => _FilterColumnState();

  /// Pick an icon based on folder name keywords.
  static IconData folderIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('unread')) return Icons.mark_email_unread;
    if (lower.contains('personal')) return Icons.person;
    if (lower.contains('group')) return Icons.group;
    if (lower.contains('channel')) return Icons.campaign;
    if (lower.contains('bot')) return Icons.smart_toy;
    if (lower.contains('work')) return Icons.work;
    return Icons.folder;
  }

  // Sidebar color tokens from §57.10 — dark background even in light mode.
  static const dayBg = Color(0xFF293A4C);
  static const dayBgActive = Color(0xFF17212B);
  static const dayBgRipple = Color(0xFF1E2B38);
  static const dayTextFg = Color(0xFF8897A6);
  static const dayTextFgActive = Color(0xFF64B9FA);
  static const dayIconFg = Color(0xFF8393A3);
  static const dayIconFgActive = Color(0xFF5EB5F7);
  static const dayBadgeBg = Color(0xFF5EB5F7);
  static const dayBadgeBgMuted = Color(0xFF8393A3);

  static const nightBg = Color(0xFF0E1621);
  static const nightBgActive = Color(0xFF25303E);
  static const nightBgRipple = Color(0xFF1E2733);
  static const nightTextFg = Color(0xFF768C9E);
  static const nightTextFgActive = Color(0xFF64B9FA);
  static const nightIconFg = Color(0xFF768C9E);
  static const nightIconFgActive = Color(0xFF5EB5F7);
  static const nightBadgeBg = Color(0xFF5EB5F7);
  static const nightBadgeBgMuted = Color(0xFF768C9E);

  static const badgeFg = Color(0xFFFFFFFF);

  static Color bg(Brightness b) => b == Brightness.dark ? nightBg : dayBg;
  static Color bgActive(Brightness b) => b == Brightness.dark ? nightBgActive : dayBgActive;
  static Color bgRipple(Brightness b) => b == Brightness.dark ? nightBgRipple : dayBgRipple;
  static Color textFg(Brightness b) => b == Brightness.dark ? nightTextFg : dayTextFg;
  static Color textFgActive(Brightness b) => b == Brightness.dark ? nightTextFgActive : dayTextFgActive;
  static Color iconFg(Brightness b) => b == Brightness.dark ? nightIconFg : dayIconFg;
  static Color iconFgActive(Brightness b) => b == Brightness.dark ? nightIconFgActive : dayIconFgActive;
  static Color badgeBg(Brightness b) => b == Brightness.dark ? nightBadgeBg : dayBadgeBg;
  static Color badgeBgMuted(Brightness b) => b == Brightness.dark ? nightBadgeBgMuted : dayBadgeBgMuted;
}

class _FilterColumnState extends State<FilterColumn> {
  final ScrollController _scrollController = ScrollController();

  // Raw-pointer drag state (mirrors horizontal tab approach).
  int? _dragIndex; // folder index being dragged (null = not tracking)
  int? _dragPointer; // pointer ID we're tracking
  double _dragOffset = 0; // vertical pixel offset of the dragged tab
  Offset? _dragStart; // pointer-down position to measure threshold
  bool _dragActive = false; // true once threshold exceeded

  final List<GlobalKey> _tabKeys = [];

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
        _autoSwitchTimer = Timer(const Duration(milliseconds: 2000), () {
          if (!mounted) return;
          final folderId = FilterColumn.folderIdAt(idx);
          if (folderId != null) {
            context.read<ChatState>().setActiveFolder(folderId);
          }
        });
      }
    }
    if (mounted) setState(() {});
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
    if (tabIdx < 0) return;
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
        final chatState = context.read<ChatState>();
        chatState.reorderFolders(_dragIndex!, targetIndex);
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
    return target;
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

  void _showFolderContextMenu(
      BuildContext context, FolderInfo folder, Offset globalPosition) {
    final chatState = context.read<ChatState>();
    final unread = chatState.unreadCountForFolder(folder.id);

    showTelegramMenu<String>(
      context: context,
      position: globalPosition,
      items: [
        if (unread > 0)
          const TelegramMenuItem(
            value: 'mark_read',
            icon: Icon(Icons.done_all),
            label: 'Mark All as Read',
          ),
        const TelegramMenuItem(
          value: 'edit',
          icon: Icon(Icons.settings),
          label: 'Edit Folder',
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'mark_read':
          final chats = chatState.chatsForFolder(folder.id);
          for (final chat in chats) {
            if (chat.unreadCount > 0) {
              chatState.markChatRead(chat.accountId, chat.chatId);
            }
          }
        case 'edit':
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = context.watch<ChatState>();
    final appState = context.watch<AppState>();
    final folders = chatState.folders;
    final activeFolderId = chatState.activeFolderId;
    final allUnread = chatState.unreadCountForAccount(appState.activeAccountId);

    _syncTabKeys(folders.length);

    final physics = _dragActive
        ? const NeverScrollableScrollPhysics()
        : const ClampingScrollPhysics();

    final brightness = theme.brightness;
    final sideBarBg = FilterColumn.bg(brightness);

    return Container(
      width: FilterColumn.width,
      color: sideBarBg,
      child: Column(
        children: [
          // Hamburger menu button at top (windowFiltersMainMenu: minHeight 54px).
          _SideBarButton(
            icon: Icons.menu,
            label: 'Menu',
            isActive: false,
            unreadCount: 0,
            minHeight: 54,
            iconCentered: true,
            onTap: widget.onOpenDrawer ?? () {},
          ),
          if (!appState.hideAllChatsFolder)
          _SideBarButton(
            icon: Icons.chat,
            label: 'All',
            isActive: activeFolderId == null,
            unreadCount: appState.hideNotificationCounters ? 0 : allUnread,
            unreadAllMuted: chatState.isAccountUnreadAllMuted(appState.activeAccountId),
            onTap: () => chatState.setActiveFolder(null),
          ),
          // Folder tabs (scrollable, drag-reorderable via raw pointers).
          Expanded(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: physics,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(folders.length, (index) {
                    final folder = folders[index];
                    final unread = appState.hideNotificationCounters ? 0 : chatState.unreadCountForFolder(folder.id);
                    final allMuted = chatState.isFolderUnreadAllMuted(folder.id);
                    final isDragged = _dragActive && _dragIndex == index;
                    final shift = _computeShiftForTab(index);
                    final isDropTarget =
                        FilterColumn.dropHighlightIndex.value == index;

                    return AnimatedContainer(
                      key: _tabKeys[index],
                      duration: (_dragActive && !isDragged)
                          ? const Duration(milliseconds: 150)
                          : Duration.zero,
                      transform: Matrix4.translationValues(
                        0,
                        isDragged ? _dragOffset : shift,
                        isDragged ? 1 : 0,
                      ),
                      decoration: isDropTarget
                          ? BoxDecoration(
                              border: Border.all(
                                color: FilterColumn.dayBadgeBg,
                                width: 2,
                              ),
                            )
                          : null,
                      child: Opacity(
                        opacity: isDragged ? 0.8 : 1.0,
                        child: DragTarget<ForwardDragData>(
                          onWillAcceptWithDetails: (_) => true,
                          onMove: (_) {
                            if (FilterColumn.dropHighlightIndex.value != index) {
                              FilterColumn.dropHighlightIndex.value = index;
                            }
                          },
                          onLeave: (_) {
                            if (FilterColumn.dropHighlightIndex.value == index) {
                              FilterColumn.dropHighlightIndex.value = -1;
                            }
                          },
                          onAcceptWithDetails: (_) {
                            FilterColumn.clearDropHighlight();
                          },
                          builder: (context, candidateData, rejectedData) =>
                        GestureDetector(
                          onSecondaryTapUp: _dragActive
                              ? null
                              : (details) => _showFolderContextMenu(
                                    context, folder, details.globalPosition),
                          child: _SideBarButton(
                            icon: FilterColumn.folderIcon(folder.name),
                            label: folder.name,
                            isActive: activeFolderId == folder.id,
                            unreadCount: unread,
                            unreadAllMuted: allMuted,
                            onTap: _dragActive
                                ? () {}
                                : () => chatState.setActiveFolder(
                                      activeFolderId == folder.id
                                          ? null
                                          : folder.id,
                                    ),
                          ),
                        ),
                      ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          // Spec §1: "Edit" button at bottom of filters sidebar.
          _SideBarButton(
            icon: Icons.edit,
            label: 'Edit',
            isActive: false,
            unreadCount: 0,
            onTap: widget.onOpenDrawer ?? () {},
          ),
        ],
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
class _SideBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final int unreadCount;
  final bool unreadAllMuted;
  final VoidCallback onTap;
  final double minHeight;
  final bool iconCentered; // true for hamburger (centered both ways)

  const _SideBarButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.unreadCount,
    this.unreadAllMuted = false,
    required this.onTap,
    this.minHeight = 62,
    this.iconCentered = false,
  });

  // Spec: windowFiltersButton dimensions from window.style.
  static const double _textTop = 40;
  static const double _textSkip = 6;
  static const double _iconSize = 24;
  static const double _iconTop = 6;
  static const double _badgeHeight = 17;
  static const double _badgeSkip = 4;
  static const double _badgePosX = 3; // offset from width/2
  static const double _badgePosY = 7;
  static const double _badgeStroke = 2;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bgColor = isActive
        ? FilterColumn.bgActive(brightness)
        : FilterColumn.bg(brightness);
    final iconColor = isActive
        ? FilterColumn.iconFgActive(brightness)
        : FilterColumn.iconFg(brightness);
    final textColor = isActive
        ? FilterColumn.textFgActive(brightness)
        : FilterColumn.textFg(brightness);

    return TelegramTooltip(
      message: label,
      child: Material(
        color: bgColor,
        child: InkWell(
          onTap: onTap,
          splashColor: FilterColumn.bgRipple(brightness),
          highlightColor: FilterColumn.bgRipple(brightness),
          child: SizedBox(
            width: FilterColumn.width,
            child: iconCentered
                ? _buildCenteredIcon(iconColor)
                : _buildFullButton(iconColor, textColor, brightness),
          ),
        ),
      ),
    );
  }

  /// Hamburger menu button: icon centered both ways, minHeight 54px.
  Widget _buildCenteredIcon(Color iconColor) {
    return SizedBox(
      height: minHeight,
      child: Center(
        child: Icon(icon, size: _iconSize, color: iconColor),
      ),
    );
  }

  /// Standard folder tab: icon at top, label below, optional badge.
  Widget _buildFullButton(Color iconColor, Color textColor, Brightness brightness) {
    return CustomMultiChildLayout(
      delegate: _SideBarButtonLayout(
        minHeight: minHeight,
        textTop: _textTop,
        textSkip: _textSkip,
        iconTop: _iconTop,
        iconSize: _iconSize,
        badgePosX: _badgePosX,
        badgePosY: _badgePosY,
        badgeHeight: _badgeHeight,
        hasBadge: unreadCount > 0,
      ),
      children: [
        LayoutId(
          id: _SideBarSlot.icon,
          child: Icon(icon, size: _iconSize, color: iconColor),
        ),
        LayoutId(
          id: _SideBarSlot.label,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        if (unreadCount > 0)
          LayoutId(
            id: _SideBarSlot.badge,
            child: _buildBadge(brightness),
          ),
      ],
    );
  }

  Widget _buildBadge(Brightness brightness) {
    final badgeColor = unreadAllMuted
        ? FilterColumn.badgeBgMuted(brightness)
        : FilterColumn.badgeBg(brightness);
    final text = unreadCount > 999 ? '99+' : '$unreadCount';
    return Container(
      height: _badgeHeight,
      constraints: BoxConstraints(minWidth: _badgeHeight),
      padding: EdgeInsets.symmetric(horizontal: _badgeSkip),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(_badgeHeight / 2),
        border: Border.all(
          color: FilterColumn.bg(brightness),
          width: _badgeStroke,
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: FilterColumn.badgeFg,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }
}

enum _SideBarSlot { icon, label, badge }

/// Custom layout delegate for exact SideBarButton positioning.
class _SideBarButtonLayout extends MultiChildLayoutDelegate {
  final double minHeight;
  final double textTop;
  final double textSkip;
  final double iconTop;
  final double iconSize;
  final double badgePosX;
  final double badgePosY;
  final double badgeHeight;
  final bool hasBadge;

  _SideBarButtonLayout({
    required this.minHeight,
    required this.textTop,
    required this.textSkip,
    required this.iconTop,
    required this.iconSize,
    required this.badgePosX,
    required this.badgePosY,
    required this.badgeHeight,
    required this.hasBadge,
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
    return Size(constraints.maxWidth, minHeight);
  }

  @override
  bool shouldRelayout(_SideBarButtonLayout oldDelegate) {
    return minHeight != oldDelegate.minHeight || hasBadge != oldDelegate.hasBadge;
  }
}
