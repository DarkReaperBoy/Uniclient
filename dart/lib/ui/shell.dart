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
  // Dialogs column width ratio (0.0-1.0 of body width).
  double _dialogsWidthRatio = 0.35;
  bool _infoOpen = false;

  // Spec: min 260, max 540, collapse below 130.
  static const _dialogsMin = 260.0;
  static const _dialogsMax = 540.0;
  // Reserved for future use: collapse below 130, chat min 380, info 292-392.
  static const _filtersWidth = 72.0;

  // OneColumn: < 640, ThreeColumn: >= 932
  static const _oneColumnBreak = 640.0;
  static const _threeColumnBreak = 932.0;

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
    final dialogsWidth = (bodyWidth * _dialogsWidthRatio)
        .clamp(_dialogsMin, _dialogsMax);

    return Row(
      children: [
        // Filters sidebar (when folders exist).
        if (showFilters)
          FilterColumn(
            onOpenDrawer: () => _openDrawer(context),
          ),
        // Dialogs column.
        SizedBox(
          width: dialogsWidth,
          child: ChatListPanel(
            showHamburger: !showFilters,
            onOpenDrawer: showFilters ? null : () => _openDrawer(context),
            filterSidebarVisible: showFilters,
          ),
        ),
        // Resize handle.
        _ResizeHandle(
          onDrag: (dx) {
            setState(() {
              final newWidth = (bodyWidth * _dialogsWidthRatio + dx)
                  .clamp(_dialogsMin, _dialogsMax);
              _dialogsWidthRatio = newWidth / bodyWidth;
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
  Widget _buildThreeColumn(BuildContext context, double bodyWidth,
      bool showFilters, ChatState chatState) {
    final dialogsWidth = (bodyWidth * _dialogsWidthRatio)
        .clamp(_dialogsMin, _dialogsMax);
    const infoWidth = 360.0; // Between min (292) and max (392).

    return Row(
      children: [
        // Filters sidebar (when folders exist).
        if (showFilters)
          FilterColumn(
            onOpenDrawer: () => _openDrawer(context),
          ),
        // Dialogs column.
        SizedBox(
          width: dialogsWidth,
          child: ChatListPanel(
            showHamburger: !showFilters,
            onOpenDrawer: showFilters ? null : () => _openDrawer(context),
            filterSidebarVisible: showFilters,
          ),
        ),
        _ResizeHandle(
          onDrag: (dx) {
            setState(() {
              final newWidth = (bodyWidth * _dialogsWidthRatio + dx)
                  .clamp(_dialogsMin, _dialogsMax);
              _dialogsWidthRatio = newWidth / bodyWidth;
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
        // Info panel.
        if (_infoOpen && chatState.activeChat != null) ...[
          SizedBox(
            width: infoWidth,
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

/// Drag handle between columns (1px separator with drag behavior).
class _ResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;

  const _ResizeHandle({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
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
