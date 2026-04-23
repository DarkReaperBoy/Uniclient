import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import 'auth_screen.dart';
import 'chat_list_panel.dart';
import 'chat_view.dart';
import 'filter_column.dart';
import 'hamburger_drawer.dart';
import 'info_panel.dart';

/// Layout modes matching Telegram Desktop's responsive breakpoints.
enum LayoutMode { oneColumn, twoColumn, threeColumn }

/// Main app shell: responsive column layout with chat list, chat view, and info panel.
class UniClientShell extends StatefulWidget {
  const UniClientShell({super.key});

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
  bool _isDragging = false;
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
  static const _thirdMin = 324.0;
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
    } catch (_) {
      // Ignore corrupt/missing file.
    }
  }

  void _saveLayoutPrefs() {
    final path = _layoutFilePath;
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(jsonEncode({
        'dialogsWidthRatio': _dialogsWidthRatio,
        'thirdColumnWidth': _thirdColumnWidth,
        'dialogsCollapsed': _dialogsCollapsed,
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
  }

  @override
  void dispose() {
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
    }

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
        // Show filters sidebar when folders exist and window is wide enough.
        final showFilters = chatState.hasFolders && windowWidth > _oneColumnBreak + _filtersWidth;
        final bodyWidth = windowWidth - (showFilters ? _filtersWidth : 0.0);
        final mode = _layoutMode(bodyWidth);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: _buildLayout(context, mode, bodyWidth, windowWidth, showFilters, chatState),
        );
      },
    );
  }

  Widget _buildLayout(BuildContext context, LayoutMode mode, double bodyWidth,
      double windowWidth, bool showFilters, ChatState chatState) {
    switch (mode) {
      case LayoutMode.oneColumn:
        return _buildOneColumn(context, chatState);
      case LayoutMode.twoColumn:
        return _buildTwoColumn(context, bodyWidth, showFilters, chatState);
      case LayoutMode.threeColumn:
        return _buildThreeColumn(context, bodyWidth, showFilters, chatState);
    }
  }

  /// Single panel: show either chat list or chat view, with section transition
  /// animation (spec §1: horizontal slide with content snapshot crossfade).
  Widget _buildOneColumn(BuildContext context, ChatState chatState) {
    final showChat = chatState.activeChat != null;
    final showInfo = _infoOpen && showChat;
    final forward = _navForward;

    final String currentKey = showInfo ? 'info' : (showChat ? 'chat' : 'chatlist');

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
                    onBack: () => chatState.closeChat(),
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
        if (showFilters) _ColumnShadow(isDark: isDark),
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
        _ColumnShadow(isDark: isDark),
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
        if (showFilters) _ColumnShadow(isDark: isDark),
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
        _ColumnShadow(isDark: isDark),
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
          _ColumnShadow(isDark: isDark),
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
      barrierColor: Colors.black54,
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
        color: Colors.black54,
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

class _ColumnShadow extends StatelessWidget {
  final bool isDark;

  const _ColumnShadow({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      color: isDark
          ? const Color(0x5604080e) // #04080e at alpha 0x56
          : const Color(0x18000000), // #000000 at alpha 0x18
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

/// Placeholder shown when no chat is selected.
class _EmptyChatPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64,
                color: theme.textTheme.bodySmall?.color),
            const SizedBox(height: 16),
            Text('Select a chat to start messaging',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                )),
          ],
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
