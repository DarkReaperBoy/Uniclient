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

class _UniClientShellState extends State<UniClientShell> {
  // Dialogs column width ratio (0.0-1.0 of body width), persisted to layout.json.
  double _dialogsWidthRatio = 0.33;
  bool _infoOpen = false;
  // Third column width, persisted within [_thirdMin, _thirdMax].
  double _thirdColumnWidth = 360.0;
  // Whether dialogs column is collapsed to avatar-only mode (spec §1: below 130px).
  bool _dialogsCollapsed = false;
  bool _layoutLoaded = false;

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

  LayoutMode _layoutMode(double bodyWidth) {
    if (bodyWidth < _oneColumnBreak) return LayoutMode.oneColumn;
    if (bodyWidth >= _threeColumnBreak && _infoOpen) return LayoutMode.threeColumn;
    return LayoutMode.twoColumn;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final authState = context.watch<AuthState>();
    final chatState = context.watch<ChatState>();

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
          drawer: mode == LayoutMode.oneColumn ? const HamburgerDrawer() : null,
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

  /// Single panel: show either chat list or chat view, with slide navigation.
  Widget _buildOneColumn(BuildContext context, ChatState chatState) {
    if (chatState.activeChat != null) {
      return ChatView(
        onBack: () => chatState.closeChat(),
        showBackButton: true,
      );
    }
    return ChatListPanel(
      onOpenDrawer: () => Scaffold.of(context).openDrawer(),
      showHamburger: true,
    );
  }

  /// Two columns: dialogs + chat.
  Widget _buildTwoColumn(BuildContext context, double bodyWidth,
      bool showFilters, ChatState chatState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec §1: clamp dialogs width to [min, bodyWidth - chatMin] so chat
    // never shrinks below 380px.
    final maxDialogs = (bodyWidth - _chatMin).clamp(_dialogsMin, _dialogsMax);
    final dialogsWidth = _dialogsCollapsed
        ? 72.0 // avatar-only collapsed mode
        : (bodyWidth * _dialogsWidthRatio).clamp(_dialogsMin, maxDialogs);

    return Row(
      children: [
        // Filters sidebar (when folders exist).
        if (showFilters)
          FilterColumn(
            onOpenDrawer: () => _openDrawer(context),
          ),
        if (showFilters) _ColumnShadow(isDark: isDark),
        // Dialogs column.
        SizedBox(
          width: dialogsWidth,
          child: ChatListPanel(
            showHamburger: !showFilters,
            onOpenDrawer: showFilters ? null : () => _openDrawer(context),
            filterSidebarVisible: showFilters,
            collapsed: _dialogsCollapsed,
          ),
        ),
        // Resize handle + shadow separator.
        _ColumnShadow(isDark: isDark),
        _ResizeHandle(
          onDrag: (dx) {
            setState(() {
              final raw = (bodyWidth * _dialogsWidthRatio + dx);
              // Spec §1: below 130px threshold, snap to collapsed mode.
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
        // Chat column.
        Expanded(
          child: chatState.activeChat != null
              ? ChatView(
                  showBackButton: false,
                  onToggleInfo: () => setState(() => _infoOpen = !_infoOpen),
                )
              : _EmptyChatPlaceholder(),
        ),
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

    // Chat gets all remaining width (always >= 380px).
    final chatWidth = bodyWidth - dw - tw;
    // Spec §1: Wide chat mode at 880px — center message bubble column.
    final wideChatMode = chatWidth >= _wideChatThreshold;

    return Row(
      children: [
        // Filters sidebar (when folders exist).
        if (showFilters)
          FilterColumn(
            onOpenDrawer: () => _openDrawer(context),
          ),
        if (showFilters) _ColumnShadow(isDark: isDark),
        // Dialogs column.
        SizedBox(
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
        // Chat column.
        SizedBox(
          width: chatWidth,
          child: chatState.activeChat != null
              ? ChatView(
                  showBackButton: false,
                  onToggleInfo: () => setState(() => _infoOpen = !_infoOpen),
                  wideChatMode: wideChatMode,
                )
              : _EmptyChatPlaceholder(),
        ),
        // Chat-info shadow separator.
        if (_infoOpen && chatState.activeChat != null) ...[
          _ColumnShadow(isDark: isDark),
          // Info panel with resize handle.
          _ResizeHandle(
            onDrag: (dx) {
              setState(() {
                // Dragging right = shrinking third column.
                _thirdColumnWidth = (tw - dx).clamp(_thirdMin, _thirdMax);
                _saveLayoutPrefs();
              });
            },
          ),
          SizedBox(
            width: tw,
            child: InfoPanel(
              onClose: () => setState(() => _infoOpen = false),
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

  const _ResizeHandle({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: const SizedBox(width: 4),
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
