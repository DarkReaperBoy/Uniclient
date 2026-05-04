import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import 'auth_screen.dart';
import 'chat_export.dart';
import 'chat_list_panel.dart';
import 'chat_view.dart';
import 'filter_column.dart';
import 'hamburger_drawer.dart';
import 'call_screen.dart';
import 'chat_switch_overlay.dart';
import 'info_panel.dart';
import '../theme/theme.dart';

/// Layout modes matching Telegram Desktop's responsive breakpoints.
enum LayoutMode { oneColumn, twoColumn, threeColumn }

/// Main app shell: responsive column layout with chat list, chat view, and info panel.
class UniClientShell extends StatefulWidget {
  const UniClientShell({super.key});

  static VoidCallback? toggleInfoRequest;
  static VoidCallback? showChatSwitchRequest;
  static VoidCallback? hideChatSwitchRequest;

  @override
  State<UniClientShell> createState() => _UniClientShellState();
}

class _UniClientShellState extends State<UniClientShell>
    with SingleTickerProviderStateMixin {
  // Dialogs column width ratio (0.0-1.0 of body width), persisted to layout.json.
  double _dialogsWidthRatio = 0.33;
  bool _infoOpen = false;
  // Third column width, persisted within [_thirdMin, _thirdMax].
  double _thirdColumnWidth = 360.0;
  // Whether dialogs column is collapsed to avatar-only mode (spec §1: below 130px).
  bool _dialogsCollapsed = false;
  bool _layoutLoaded = false;
  bool? _lastVerticalFilters;
  Set<String>? _lastForumViewPrefs;
  bool _isDragging = false;
  bool _chatSwitchActive = false;
  // One-column section transition direction tracking (spec §1: horizontal slide + crossfade).
  bool _navForward = true;
  bool _hadActiveChat = false;
  // Spec §4.1: top-bar divider hidden during one-column slide transitions.
  bool _oneColumnAnimating = false;
  Timer? _oneColumnTimer;
  // Spec §1: third column open/close animation. Shadow stays until dismissed.
  late final AnimationController _thirdColumnAnim;
  late final Animation<double> _thirdColumnCurved;

  // Spec §1 column constants (window.style:20-24).
  static const _dialogsMin = 260.0;
  static const _dialogsMax = 540.0;
  static const _dialogsCollapseThreshold = 130.0;
  static const _chatMin = 380.0;
  static const _thirdMin = 292.0;
  static const _thirdMax = 392.0;
  static const _filtersWidth = 72.0;

  // Spec §1: Wide chat mode triggers at 880px chat width.
  static const _wideChatThreshold = 880.0;

  // OneColumn: < 640, ThreeColumn: >= 932
  static const _oneColumnBreak = 640.0;
  static const _threeColumnBreak = 932.0;

  String _configDir = '';

  String get _layoutFilePath =>
      _configDir.isEmpty ? '' : '$_configDir/layout.json';

  void _loadLayoutPrefs() {
    final path = _layoutFilePath;
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _dialogsWidthRatio = (data['dialogsWidthRatio'] as num?)?.toDouble() ?? _dialogsWidthRatio;
      _thirdColumnWidth = (data['thirdColumnWidth'] as num?)?.toDouble() ?? _thirdColumnWidth;
      _dialogsCollapsed = (data['dialogsCollapsed'] as bool?) ?? _dialogsCollapsed;
      final chatState = context.read<ChatState>();
      chatState.useVerticalFilters = (data['useVerticalFilters'] as bool?) ?? true;
      final forumPrefs = data['forumViewAsMessages'];
      if (forumPrefs is List) {
        chatState.loadForumViewPrefs(forumPrefs.cast<String>().toSet());
      }
    } catch (_) {
      // Ignore corrupt/missing file.
    }
  }

  void _saveLayoutPrefs() {
    final path = _layoutFilePath;
    if (path.isEmpty) return;
    try {
      final chatState = context.read<ChatState>();
      File(path).writeAsStringSync(jsonEncode({
        'dialogsWidthRatio': _dialogsWidthRatio,
        'thirdColumnWidth': _thirdColumnWidth,
        'dialogsCollapsed': _dialogsCollapsed,
        'useVerticalFilters': chatState.useVerticalFilters,
        'forumViewAsMessages': chatState.forumViewAsMessagesKeys.toList(),
      }));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  @override
  void initState() {
    super.initState();
    _thirdColumnAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          setState(() {}); // Remove third column widgets from tree.
        }
      });
    _thirdColumnCurved = CurvedAnimation(
      parent: _thirdColumnAnim,
      curve: Curves.easeOutCirc,
    );
    UniClientShell.toggleInfoRequest = _toggleInfo;
    UniClientShell.showChatSwitchRequest = _showChatSwitch;
    UniClientShell.hideChatSwitchRequest = _hideChatSwitch;
  }

  @override
  void dispose() {
    if (UniClientShell.toggleInfoRequest == _toggleInfo) {
      UniClientShell.toggleInfoRequest = null;
    }
    if (UniClientShell.showChatSwitchRequest == _showChatSwitch) {
      UniClientShell.showChatSwitchRequest = null;
    }
    if (UniClientShell.hideChatSwitchRequest == _hideChatSwitch) {
      UniClientShell.hideChatSwitchRequest = null;
    }
    _thirdColumnAnim.dispose();
    _oneColumnTimer?.cancel();
    super.dispose();
  }

  void _toggleInfo() {
    setState(() {
      _infoOpen = !_infoOpen;
      _navForward = _infoOpen;
      if (_infoOpen) {
        _thirdColumnAnim.forward();
      } else {
        _thirdColumnAnim.reverse();
      }
    });
  }

  void _closeInfo() {
    if (!_infoOpen) return;
    setState(() {
      _infoOpen = false;
      _navForward = false;
      _thirdColumnAnim.reverse();
    });
  }

  void _showChatSwitch() {
    if (_chatSwitchActive) return;
    setState(() => _chatSwitchActive = true);
  }

  void _hideChatSwitch() {
    if (!_chatSwitchActive) return;
    setState(() => _chatSwitchActive = false);
  }

  LayoutMode _layoutMode(double bodyWidth) {
    if (bodyWidth < _oneColumnBreak) return LayoutMode.oneColumn;
    if (bodyWidth >= _threeColumnBreak && (_infoOpen || !_thirdColumnAnim.isDismissed)) return LayoutMode.threeColumn;
    return LayoutMode.twoColumn;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final authState = context.watch<AuthState>();
    final chatState = context.watch<ChatState>();

    // Track navigation direction for one-column section transitions.
    final hasChat = chatState.activeChat != null;
    if (hasChat != _hadActiveChat) {
      _navForward = hasChat;
      _hadActiveChat = hasChat;
      // Spec §4.1: hide top-bar divider during one-column slide transition.
      _oneColumnAnimating = true;
      _oneColumnTimer?.cancel();
      _oneColumnTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _oneColumnAnimating = false);
      });
    }

    // Load layout prefs once configDir becomes available.
    if (!_layoutLoaded && appState.configDir.isNotEmpty) {
      _layoutLoaded = true;
      _configDir = appState.configDir;
      _loadLayoutPrefs();
      _lastVerticalFilters = chatState.useVerticalFilters;
    }

    // Persist when filter tab mode changes (§18.12).
    if (_layoutLoaded && _lastVerticalFilters != chatState.useVerticalFilters) {
      _lastVerticalFilters = chatState.useVerticalFilters;
      _saveLayoutPrefs();
    }

    // Persist when forum view-as-messages preference changes (§22.10).
    final currentForumPrefs = chatState.forumViewAsMessagesKeys;
    if (_layoutLoaded && _lastForumViewPrefs != null &&
        !setEquals(_lastForumViewPrefs!, currentForumPrefs)) {
      _saveLayoutPrefs();
    }
    _lastForumViewPrefs = currentForumPrefs;

    // Show loading while engine initializes.
    if (!appState.initialized) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: appState.initError != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 16),
                    Text('Failed to initialize engine',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(appState.initError!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    // Show auth screen if there's an active auth flow.
    if (authState.hasActiveFlow && !authState.isReady) {
      return const AuthScreen();
    }

    // Show add-account prompt if no accounts exist.
    if (appState.accounts.isEmpty) {
      return _NoAccountsScreen(
        onAdd: (platform) {
          final id = appState.addAccount(platform);
          authState.startAuth(id);
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final windowWidth = constraints.maxWidth;
        // Show vertical filters sidebar when folders exist, preference is sidebar
        // mode, and window is wide enough (spec §18.12: ≥452px for sidebar to fit,
        // but we also need room for dialogs column).
        final showFilters = chatState.hasFolders &&
            chatState.useVerticalFilters &&
            windowWidth > _oneColumnBreak + _filtersWidth;
        final bodyWidth = windowWidth - (showFilters ? _filtersWidth : 0.0);
        final mode = _layoutMode(bodyWidth);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Stack(
            children: [
              _buildLayout(context, mode, bodyWidth, windowWidth, showFilters, chatState),
              Positioned(
                left: 0,
                bottom: 0,
                child: _ConnectionStateWidget(accountId: appState.activeAccountId),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLayout(BuildContext context, LayoutMode mode, double bodyWidth,
      double windowWidth, bool showFilters, ChatState chatState) {
    Widget layout;
    switch (mode) {
      case LayoutMode.oneColumn:
        layout = _buildOneColumn(context, chatState);
      case LayoutMode.twoColumn:
        layout = _buildTwoColumn(context, bodyWidth, showFilters, chatState);
      case LayoutMode.threeColumn:
        layout = _buildThreeColumn(context, bodyWidth, showFilters, chatState);
    }

    final groupCall = chatState.activeGroupCall;
    final personalCall = chatState.activePersonalCall;
    final hasActiveCall = (groupCall != null && groupCall.active) || personalCall != null;

    if (hasActiveCall) {
      final Widget callBar;
      if (personalCall != null) {
        callBar = MinimisedCallBar(
          isPersonalCall: true,
          peerName: personalCall.peerName,
          peerFirstName: personalCall.peerFirstName,
          isSelfMuted: personalCall.isMuted,
          isConnecting: personalCall.isConnecting,
          signalQuality: personalCall.signalQuality,
          callStartTime: personalCall.startTime,
          onHangup: () => chatState.setActivePersonalCall(null),
          onToggleMute: () {
            chatState.setActivePersonalCall(
              personalCall.copyWith(isMuted: !personalCall.isMuted),
            );
          },
        );
      } else {
        callBar = MinimisedCallBar(
          peerName: groupCall!.title.isNotEmpty
              ? groupCall.title
              : chatState.activeChat?.title ?? 'Group Call',
          participants: groupCall.participants,
          isSelfMuted: groupCall.participants.any((p) =>
              p.userId == (chatState.activeChat?.accountId ?? '') && p.isMuted),
          onHangup: () {},
          onToggleMute: () {},
        );
      }
      layout = Column(
        children: [
          _SlideWrapCallBar(visible: true, child: callBar),
          Expanded(child: layout),
        ],
      );
    }

    if (chatState.exportActive) {
      layout = Column(
        children: [
          const ExportTopBar(),
          Expanded(child: layout),
        ],
      );
    }

    if (_chatSwitchActive) {
      final history = chatState.collectChatOpenHistory();
      if (history.length < 2) {
        _chatSwitchActive = false;
        return layout;
      }
      return Stack(
        children: [
          layout,
          Positioned.fill(
            child: ChatSwitchOverlay(
              chats: history,
              initialIndex: 1,
              onChosen: (chat) {
                setState(() => _chatSwitchActive = false);
                chatState.openChat(chat);
              },
              onRemove: (chat) {
                chatState.removeChatFromOpenHistory(chat.chatId);
              },
              onCancel: () {
                setState(() => _chatSwitchActive = false);
              },
            ),
          ),
        ],
      );
    }

    return layout;
  }

  /// Single panel: show either chat list or chat view, with section transition
  /// animation (spec §1: horizontal slide with content snapshot crossfade).
  Widget _buildOneColumn(BuildContext context, ChatState chatState) {
    final showForumTopics = chatState.isViewingForum && chatState.activeTopicId == null;
    final showChat = chatState.activeChat != null && !showForumTopics;
    final showInfo = _infoOpen && showChat;
    final forward = _navForward;

    final String currentKey = showInfo ? 'info' : (showChat ? 'chat' : (showForumTopics ? 'forumtopics' : 'chatlist'));

    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final isIncoming = child.key == ValueKey(currentKey);
          final beginOffset = isIncoming
              ? Offset(forward ? 1.0 : -1.0, 0)
              : Offset(forward ? -0.3 : 0.3, 0);
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
                .animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: child,
            ),
          );
        },
        child: showInfo
            ? InfoPanel(
                key: const ValueKey('info'),
                onClose: _closeInfo,
                wrapMode: InfoWrapMode.narrow,
              )
            : showChat
                ? ChatView(
                    key: const ValueKey('chat'),
                    onBack: () {
                      if (chatState.forumParentChat != null && chatState.activeTopicId != null) {
                        chatState.goBackFromTopic();
                      } else {
                        chatState.closeChat();
                      }
                    },
                    showBackButton: true,
                    hideTopBarDivider: _oneColumnAnimating,
                    onToggleInfo: _toggleInfo,
                    isInfoOpen: _infoOpen,
                  )
                : ChatListPanel(
                    key: const ValueKey('chatlist'),
                    onOpenDrawer: () => _openDrawer(context),
                    showHamburger: true,
                  ),
      ),
    );
  }

  Widget _buildTwoColumn(BuildContext context, double bodyWidth,
      bool showFilters, ChatState chatState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxDialogs = (bodyWidth - _chatMin).clamp(_dialogsMin, _dialogsMax);
    final dialogsWidth = _dialogsCollapsed
        ? 72.0
        : (bodyWidth * _dialogsWidthRatio).clamp(_dialogsMin, maxDialogs);

    final columns = Row(
      children: [
        if (showFilters)
          FilterColumn(
            onOpenDrawer: () => _openDrawer(context),
          ),
        if (showFilters) _ColumnShadow(),
        AnimatedContainer(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCirc,
          width: dialogsWidth,
          child: ChatListPanel(
            showHamburger: !showFilters,
            onOpenDrawer: showFilters ? null : () => _openDrawer(context),
            filterSidebarVisible: showFilters,
            collapsed: _dialogsCollapsed,
          ),
        ),
        _ColumnShadow(),
        _ResizeHandle(
          onDragStart: () => setState(() => _isDragging = true),
          onDragEnd: () => setState(() => _isDragging = false),
          onDrag: (dx) {
            setState(() {
              final raw = (bodyWidth * _dialogsWidthRatio + dx);
              if (raw < _dialogsCollapseThreshold) {
                _dialogsCollapsed = true;
              } else {
                _dialogsCollapsed = false;
                final newWidth = raw.clamp(_dialogsMin, maxDialogs);
                _dialogsWidthRatio = newWidth / bodyWidth;
              }
              _saveLayoutPrefs();
            });
          },
        ),
        Expanded(
          child: chatState.activeChat != null
              ? ChatView(
                  showBackButton: false,
                  onToggleInfo: _toggleInfo,
                  isInfoOpen: _infoOpen,
                )
              : _EmptyChatPlaceholder(),
        ),
      ],
    );

    if (!_infoOpen || chatState.activeChat == null) return columns;

    return Stack(
      children: [
        columns,
        _InfoLayerOverlay(onClose: _closeInfo),
      ],
    );
  }

  /// Three columns: dialogs + chat + info panel.
  /// Implements the Telegram Desktop three-column shrink algorithm (spec §1
  /// SessionController::shrinkDialogsAndThirdColumns).
  Widget _buildThreeColumn(BuildContext context, double bodyWidth,
      bool showFilters, ChatState chatState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Step 1: Start from preferred widths.
    var dw = (bodyWidth * _dialogsWidthRatio).clamp(_dialogsMin, _dialogsMax);
    var tw = _thirdColumnWidth.clamp(_thirdMin, _thirdMax);

    // Step 2: Shrink algorithm — if both columns + chat min don't fit.
    if (dw + tw + _chatMin > bodyWidth) {
      // Pin chat to 380px minimum, divide the rest proportionally.
      final available = bodyWidth - _chatMin;
      final total = dw + tw;
      if (total > 0) {
        tw = available * tw / total;
        dw = available * dw / total;
      }
      // Step 3: Clamp — ensure both columns meet minimums.
      if (tw < _thirdMin) {
        tw = _thirdMin;
        dw = bodyWidth - _thirdMin - _chatMin;
      } else if (dw < _dialogsMin) {
        dw = _dialogsMin;
        tw = bodyWidth - _dialogsMin - _chatMin;
      }
      tw = tw.clamp(_thirdMin, _thirdMax);
      dw = dw.clamp(_dialogsMin, _dialogsMax);
    }

    return Row(
      children: [
        // Filters sidebar (when folders exist).
        if (showFilters)
          FilterColumn(
            onOpenDrawer: () => _openDrawer(context),
          ),
        if (showFilters) _ColumnShadow(),
        // Dialogs column.
        AnimatedContainer(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCirc,
          width: dw,
          child: ChatListPanel(
            showHamburger: !showFilters,
            onOpenDrawer: showFilters ? null : () => _openDrawer(context),
            filterSidebarVisible: showFilters,
            collapsed: _dialogsCollapsed,
          ),
        ),
        // Dialogs-chat shadow separator + resize handle.
        _ColumnShadow(),
        _ResizeHandle(
          onDragStart: () => setState(() => _isDragging = true),
          onDragEnd: () => setState(() => _isDragging = false),
          onDrag: (dx) {
            setState(() {
              final raw = dw + dx;
              if (raw < _dialogsCollapseThreshold) {
                _dialogsCollapsed = true;
              } else {
                _dialogsCollapsed = false;
                _dialogsWidthRatio = raw.clamp(_dialogsMin, _dialogsMax) / bodyWidth;
              }
              _saveLayoutPrefs();
            });
          },
        ),
        // Chat column (Expanded absorbs remaining space, avoiding overflow
        // from shadow/handle pixels and enabling smooth column animations).
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wideChat = constraints.maxWidth >= _wideChatThreshold;
              return chatState.activeChat != null
                  ? ChatView(
                      showBackButton: false,
                      onToggleInfo: _toggleInfo,
                      isInfoOpen: _infoOpen,
                      wideChatMode: wideChat,
                    )
                  : _EmptyChatPlaceholder();
            },
          ),
        ),
        // Chat-info shadow separator. Stays visible during close animation,
        // removed when animation reaches dismissed state (spec §1 _thirdShadow).
        if (!_thirdColumnAnim.isDismissed && chatState.activeChat != null) ...[
          _ColumnShadow(),
          // Resize handle only while info is open (not during close animation).
          if (_infoOpen)
            _ResizeHandle(
              onDragStart: () => setState(() => _isDragging = true),
              onDragEnd: () => setState(() => _isDragging = false),
              onDrag: (dx) {
                setState(() {
                  _thirdColumnWidth = (tw - dx).clamp(_thirdMin, _thirdMax);
                  _saveLayoutPrefs();
                });
              },
            ),
          AnimatedBuilder(
            animation: _thirdColumnCurved,
            builder: (context, child) {
              return ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: _thirdColumnCurved.value,
                  child: child,
                ),
              );
            },
            child: SizedBox(
              width: tw,
              child: InfoPanel(onClose: _closeInfo),
            ),
          ),
        ],
      ],
    );
  }

  void _openDrawer(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: context.palette.layerBg,
      builder: (_) => Align(
        alignment: Alignment.centerLeft,
        child: Material(
          elevation: 16,
          child: SizedBox(
            width: 274, // Spec: hamburger drawer 274px
            height: MediaQuery.of(context).size.height,
            child: const HamburgerDrawer(),
          ),
        ),
      ),
    );
  }
}

/// Spec §1 column shadow separator. 1px fillRect with shadowFg color.
/// Light theme: #00000018 (black at 9.4% opacity).
/// Dark theme: #04080e56 (near-black at 33.7% opacity).
/// No animation — static paint, toggled by show/hide.
class _InfoLayerOverlay extends StatelessWidget {
  final VoidCallback onClose;

  const _InfoLayerOverlay({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: context.palette.layerBg,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(left: 48, right: 48, top: 20),
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 392),
            child: InfoPanel(
              onClose: onClose,
              wrapMode: InfoWrapMode.layer,
            ),
          ),
        ),
      ),
    );
  }
}

class _SlideWrapCallBar extends StatefulWidget {
  final bool visible;
  final Widget child;

  const _SlideWrapCallBar({required this.visible, required this.child});

  @override
  State<_SlideWrapCallBar> createState() => _SlideWrapCallBarState();
}

class _SlideWrapCallBarState extends State<_SlideWrapCallBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.visible ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_SlideWrapCallBar old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
      axisAlignment: -1.0,
      child: widget.child,
    );
  }
}

class _ColumnShadow extends StatelessWidget {
  const _ColumnShadow();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      color: context.palette.shadowFg,
    );
  }
}

/// Drag handle between columns (invisible 4px hit target, no visual).
class _ResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const _ResizeHandle({required this.onDrag, this.onDragStart, this.onDragEnd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: onDragStart != null ? (_) => onDragStart!() : null,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      onHorizontalDragEnd: onDragEnd != null ? (_) => onDragEnd!() : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: const SizedBox(width: 4, height: double.infinity),
      ),
    );
  }
}

/// Placeholder shown when no chat is selected — spec §35.6.
/// Service-message style bubble, centred in the chat pane.
class _EmptyChatPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      color: palette.windowBg,
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
          decoration: BoxDecoration(
            color: palette.msgServiceBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Select a chat to start messaging',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.msgServiceFg,
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen shown when no accounts exist.
class _NoAccountsScreen extends StatelessWidget {
  final void Function(String platform) onAdd;

  const _NoAccountsScreen({required this.onAdd});

  static const _platforms = [
    ('telegram', 'Telegram', Icons.send),
    ('matrix', 'Matrix', Icons.grid_view),
    ('xmpp', 'XMPP', Icons.message),
    ('irc', 'IRC', Icons.tag),
    ('bale', 'Bale', Icons.chat),
    ('rubika', 'Rubika', Icons.radio_button_checked),
    ('deltachat', 'Delta Chat', Icons.email),
    ('mumble', 'Mumble', Icons.headset_mic),
    ('teamspeak', 'TeamSpeak', Icons.headset),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Welcome to UniClient',
                            style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text('Add an account to get started',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodySmall?.color,
                            )),
                        const SizedBox(height: 32),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: _platforms.map((p) => _PlatformButton(
                            label: p.$2,
                            icon: p.$3,
                            onTap: () => onAdd(p.$1),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Spec §35.22: Connection state pill — bottom-left overlay.
/// Shows spinner after 1000ms delay when not connected. Text "Connecting..."
/// on hover (or always for disconnected/unstable). Hidden when connected.
/// 150ms fade animation on show/hide, pill width animates with text.
class _ConnectionStateWidget extends StatefulWidget {
  final String accountId;
  const _ConnectionStateWidget({required this.accountId});

  @override
  State<_ConnectionStateWidget> createState() => _ConnectionStateWidgetState();
}

class _ConnectionStateWidgetState extends State<_ConnectionStateWidget>
    with SingleTickerProviderStateMixin {
  static const _showDelay = Duration(milliseconds: 1000);
  static const _animDuration = Duration(milliseconds: 150);

  late final AnimationController _fadeAnim;
  Timer? _showTimer;
  bool _shouldShow = false;
  bool _isHovered = false;
  ConnState? _lastState;

  @override
  void initState() {
    super.initState();
    _fadeAnim = AnimationController(vsync: this, duration: _animDuration);
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _fadeAnim.dispose();
    super.dispose();
  }

  void _syncVisibility(ConnState state) {
    if (state == _lastState) return;
    _lastState = state;
    final wantVisible = state != ConnState.connected;

    if (wantVisible && !_shouldShow && _showTimer == null) {
      _showTimer = Timer(_showDelay, () {
        _showTimer = null;
        if (!mounted) return;
        setState(() => _shouldShow = true);
        _fadeAnim.forward();
      });
    } else if (!wantVisible) {
      _showTimer?.cancel();
      _showTimer = null;
      if (_shouldShow) {
        _shouldShow = false;
        _fadeAnim.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final state = appState.connStateFor(widget.accountId);
    final p = context.palette;

    _syncVisibility(state);

    if (!_shouldShow && !_fadeAnim.isAnimating) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fadeAnim,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: _buildPill(state, p),
        ),
      ),
    );
  }

  Widget _buildPill(ConnState state, TelegramPalette p) {
    final showText = _isHovered ||
        state == ConnState.disconnected ||
        state == ConnState.unstable;

    return AnimatedContainer(
      duration: _animDuration,
      decoration: BoxDecoration(
        color: p.windowBg,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: p.windowShadowFg,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: showText ? 18 : 5,
        vertical: 5,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: p.menuIconFg,
            ),
          ),
          if (showText) ...[
            const SizedBox(width: 8),
            Text(
              'Connecting...',
              style: TextStyle(fontSize: 13, color: p.menuIconFg),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlatformButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PlatformButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(label, style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
