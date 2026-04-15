import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import '../models/engine_models.dart';
import '../theme/theme.dart';
import '../widgets/platform_rail.dart';
import '../widgets/sidebar.dart';
import '../widgets/chat_view.dart';
import '../widgets/notification_overlay.dart';
import 'auth_screen.dart';

/// Main screen — platform rail + sidebar + chat area + optional right panel.
/// Responsive: narrow (<600) / medium (600-900) / wide (>900).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _NarrowTab { chats, search, settings }

class _HomeScreenState extends State<HomeScreen> {
  bool _showRightPanel = false;
  _NarrowTab _narrowTab = _NarrowTab.chats;
  bool _narrowShowChat = false;
  String? _lastActiveChatId;

  /// Accounts we've already shown the re-auth dialog for (avoid repeated popups).
  final Set<String> _authPromptedIds = {};
  bool _notifWired = false;

  // Member list state for right panel.
  List<MemberInfo>? _members;
  bool _membersLoading = false;
  String? _membersChatKey; // "accountId:chatId" to detect chat changes

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final chatState = context.watch<ChatState>();

    // Wire notification callbacks once.
    if (!_notifWired) {
      _notifWired = true;
      chatState.onNotification = (sender, text, chatTitle) {
        final mgr = NotificationManager.maybeOf(context);
        mgr?.showMessageNotification(sender, text, chatTitle: chatTitle);
      };
      appState.onConnStateNotification = (text, icon, color) {
        final mgr = NotificationManager.maybeOf(context);
        mgr?.showStatusNotification(text, icon: icon, color: color);
      };
      appState.onAddAccount = (accountId, platform) {
        // CLI command added an account — open auth dialog.
        final authState = context.read<AuthState>();
        authState.startAuth(accountId);
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => AuthScreen(accountId: accountId, platform: platform),
        );
      };
    }

    // Auto-prompt re-auth when an account reports auth_required.
    _checkAuthRequired(context, appState);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Track when a new chat is opened to show it on narrow screens.
    final currentChatId = chatState.activeChat?.chatId;
    if (currentChatId != _lastActiveChatId) {
      if (currentChatId != null && _lastActiveChatId != null) {
        // New chat selected — show it
        _narrowShowChat = true;
      } else if (currentChatId != null && _lastActiveChatId == null) {
        // First chat opened
        _narrowShowChat = true;
      }
      _lastActiveChatId = currentChatId;
      // Invalidate cached member list when chat changes.
      _members = null;
      _membersChatKey = null;
      _membersLoading = false;
    }

    // Show loading while engine initializes.
    if (!appState.initialized && appState.initError == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBase : AppColors.lightBase,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/icon/icon_256.png', width: 96, height: 96),
              ),
              const SizedBox(height: 20),
              Text('UniClient', style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkText : AppColors.lightText,
                letterSpacing: -0.5,
              )),
              const SizedBox(height: 8),
              Text('Unified messaging', style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              )),
              const SizedBox(height: 32),
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show error if engine failed to init.
    if (appState.initError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
              const SizedBox(height: 16),
              Text('Engine failed to start', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(appState.initError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isNarrow = width < 600;
            final isWide = width > 900;
            final dividerColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
            final activeChat = chatState.activeChat;

            // Skip rendering during initial layout pass with tiny constraints.
            if (constraints.maxWidth < 50) {
              return const SizedBox.shrink();
            }

            // ── Narrow layout (<600px) ──
            if (isNarrow) {
              return _buildNarrowLayout(
                context, appState, chatState, activeChat, isDark, dividerColor,
              );
            }

            // ── Medium (600-900) and Wide (>900) layouts ──
            return Row(
              children: [
                // Platform rail (left edge)
                const SizedBox(
                  width: AppSizes.railWidth,
                  child: PlatformRail(),
                ),

                Container(width: 1, color: dividerColor),

                // Sidebar (chat list)
                SizedBox(
                  width: (constraints.maxWidth - AppSizes.railWidth - 3)
                      .clamp(0, AppSizes.sidebarWidth)
                      .toDouble(),
                  child: const Sidebar(),
                ),

                Container(width: 1, color: dividerColor),

                // Main chat area
                Expanded(
                  child: activeChat != null
                      ? Stack(
                          children: [
                            const ChatView(),
                            // Right panel toggle button (top-right corner, wide only)
                            if (isWide)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: Icon(
                                    _showRightPanel ? Icons.info : Icons.info_outline,
                                    size: 20,
                                    color: _showRightPanel
                                        ? AppColors.accent
                                        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                  ),
                                  tooltip: _showRightPanel ? 'Hide panel' : 'Show panel',
                                  onPressed: () => setState(() => _showRightPanel = !_showRightPanel),
                                ),
                              ),
                          ],
                        )
                      : _buildEmptyState(context, appState),
                ),

                // Right panel (wide only)
                if (_showRightPanel && activeChat != null && isWide) ...[
                  Container(width: 1, color: dividerColor),
                  SizedBox(
                    width: AppSizes.rightPanelWidth,
                    child: _buildRightPanel(context, chatState, activeChat, isDark),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Narrow layout (<600px) — single panel at a time
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildNarrowLayout(
    BuildContext context,
    AppState appState,
    ChatState chatState,
    ChatInfo? activeChat,
    bool isDark,
    Color dividerColor,
  ) {
    // If a chat is open and we want to show it, show chat view full-width with back button.
    if (activeChat != null && _narrowShowChat) {
      return _buildNarrowChatView(context, chatState, activeChat, isDark);
    }

    // Otherwise show the bottom-nav tabbed view.
    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _buildNarrowTabContent(context, appState, chatState, isDark),
          ),
        ),
        Container(height: 1, color: dividerColor),
        _buildNarrowBottomBar(isDark),
      ],
    );
  }

  Widget _buildNarrowTabContent(
    BuildContext context, AppState appState, ChatState chatState, bool isDark,
  ) {
    switch (_narrowTab) {
      case _NarrowTab.chats:
        return const Sidebar(key: ValueKey('sidebar'));
      case _NarrowTab.search:
        return const _NarrowSearchScreen(key: ValueKey('search'));
      case _NarrowTab.settings:
        return _buildNarrowSettings(context, appState, isDark);
    }
  }

  Widget _buildNarrowBottomBar(bool isDark) {
    final bgColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    const activeColor = AppColors.accent;
    final inactiveColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bottomNavItem(
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_rounded,
            label: 'Chats',
            isActive: _narrowTab == _NarrowTab.chats,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: () => setState(() => _narrowTab = _NarrowTab.chats),
          ),
          _bottomNavItem(
            icon: Icons.search_rounded,
            activeIcon: Icons.search_rounded,
            label: 'Search',
            isActive: _narrowTab == _NarrowTab.search,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: () => setState(() => _narrowTab = _NarrowTab.search),
          ),
          _bottomNavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            label: 'Settings',
            isActive: _narrowTab == _NarrowTab.settings,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: () => setState(() => _narrowTab = _NarrowTab.settings),
          ),
        ],
      ),
    );
  }

  Widget _bottomNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
  }) {
    final color = isActive ? activeColor : inactiveColor;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon, size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowChatView(
    BuildContext context, ChatState chatState, ChatInfo chat, bool isDark,
  ) {
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;

    return ChatView(
      headerLeading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 22),
        onPressed: () => _closeActiveChat(chatState),
        tooltip: 'Back',
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _closeActiveChat(ChatState chatState) {
    setState(() => _narrowShowChat = false);
    chatState.closeChat();
  }

  Widget _buildNarrowSettings(BuildContext context, AppState appState, bool isDark) {
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    return Container(
      key: const ValueKey('settings'),
      color: isDark ? AppColors.darkBase : AppColors.lightBase,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
          // Accounts section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'ACCOUNTS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: mutedColor, letterSpacing: 1),
            ),
          ),
          if (appState.accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('No accounts connected', style: TextStyle(fontSize: 13, color: mutedColor)),
            )
          else
            ...appState.accounts.map((acc) => Container(
              key: ValueKey('acc_${acc.id}'),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(_platformIcon(acc.platform), size: 20, color: mutedColor),
                title: Text(
                  acc.displayName.isNotEmpty ? acc.displayName : acc.platform,
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
                subtitle: Text(acc.platform, style: TextStyle(fontSize: 12, color: mutedColor)),
                trailing: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: acc.connState == ConnState.connected
                        ? AppColors.online
                        : (acc.connState == ConnState.connecting ? AppColors.warning : AppColors.darkTextDim),
                  ),
                ),
              ),
            )),
          const SizedBox(height: 24),
          // Platforms section (drawer content)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'PLATFORMS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: mutedColor, letterSpacing: 1),
            ),
          ),
          ...appState.platforms.map((p) => Container(
            key: ValueKey('plat_$p'),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: appState.activePlatform == p ? AppColors.accent.withValues(alpha: 0.15) : surfaceColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(_platformIcon(p), size: 20,
                color: appState.activePlatform == p ? AppColors.accent : mutedColor),
              title: Text(
                _platformLabel(p),
                style: TextStyle(
                  fontSize: 14,
                  color: appState.activePlatform == p ? AppColors.accent : textColor,
                  fontWeight: appState.activePlatform == p ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              onTap: () => appState.setActivePlatform(
                appState.activePlatform == p ? '' : p,
              ),
            ),
          )),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Right panel (wide layout)
  // ══════════════════════════════════════════════════════════════════════════

  void _loadMembers(String accountId, String chatId) {
    final key = '$accountId:$chatId';
    if (_membersChatKey == key && _members != null) return; // already loaded for this chat
    _membersChatKey = key;
    _members = null;
    _membersLoading = true;

    final engine = context.read<EngineService>();
    engine.getChatMembers(accountId, chatId).then((members) {
      if (mounted && _membersChatKey == key) {
        setState(() {
          _members = members;
          _membersLoading = false;
        });
      }
    }).catchError((e) {
      if (mounted && _membersChatKey == key) {
        setState(() {
          _members = [];
          _membersLoading = false;
        });
      }
    });
  }

  Widget _buildRightPanel(BuildContext context, ChatState chatState, ChatInfo chat, bool isDark) {
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final dimColor = isDark ? AppColors.darkTextDim : AppColors.lightTextDim;
    final dividerColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    String subtitle;
    String countLabel;
    switch (chat.type) {
      case ChatType.dm:
        subtitle = 'Direct Message';
        countLabel = '';
      case ChatType.group:
        subtitle = 'Group';
        countLabel = 'Members (${chat.memberCount})';
      case ChatType.channel:
        subtitle = 'Channel';
        countLabel = 'Subscribers (${chat.memberCount})';
      case ChatType.topic:
        subtitle = 'Topic';
        countLabel = '';
      case ChatType.unspec:
        subtitle = 'Chat';
        countLabel = '';
    }

    // Find account platform for badge
    final appState = context.read<AppState>();
    final account = appState.accounts.where((a) => a.id == chat.accountId).firstOrNull;

    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: Column(
        children: [
          // Header: title + close button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Chat Info',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: mutedColor),
                  onPressed: () => setState(() => _showRightPanel = false),
                  tooltip: 'Close panel',
                  splashRadius: 16,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),

          // Scrollable content
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 20),
                // Large avatar
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _avatarColor(chat.title),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _avatarInitial(chat.title),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Chat title centered
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      chat.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Type label
                Center(
                  child: Text(subtitle, style: TextStyle(fontSize: 13, color: mutedColor)),
                ),
                // Member count for groups/channels
                if (chat.memberCount > 0 && chat.type != ChatType.dm) ...[
                  const SizedBox(height: 2),
                  Center(
                    child: Text(
                      '${chat.memberCount} ${chat.type == ChatType.channel ? 'subscribers' : 'members'}',
                      style: TextStyle(fontSize: 12, color: dimColor),
                    ),
                  ),
                ],
                // Platform badge
                if (account != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _platformLabel(account.platform),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.accent),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Divider(height: 1, color: dividerColor),

                // Members section (groups/channels)
                if (countLabel.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      countLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: mutedColor,
                      ),
                    ),
                  ),
                  // Trigger member loading when panel opens for this chat.
                  Builder(builder: (_) {
                    _loadMembers(chat.accountId, chat.chatId);
                    if (_membersLoading) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    final members = _members ?? [];
                    if (members.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          chat.type == ChatType.channel ? 'No subscribers loaded' : 'No members loaded',
                          style: TextStyle(fontSize: 13, color: dimColor),
                        ),
                      );
                    }
                    return Column(
                      children: members.map((m) => KeyedSubtree(
                        key: ValueKey('mem_${m.userId}'),
                        child: _buildMemberTile(m, isDark),
                      )).toList(),
                    );
                  }),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: dividerColor),
                ],

                // DM profile placeholder
                if (chat.type == ChatType.dm) ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'User profile coming soon',
                      style: TextStyle(fontSize: 13, color: dimColor),
                    ),
                  ),
                  Divider(height: 1, color: dividerColor),
                ],

                // Shared Media section
                _SharedMediaGallery(
                  accountId: chat.accountId,
                  chatId: chat.chatId,
                  isDark: isDark,
                ),
                Divider(height: 1, color: dividerColor),

                // Actions section
                const SizedBox(height: 8),
                _actionTile(
                  icon: chat.isMuted ? Icons.notifications_off_rounded : Icons.notifications_rounded,
                  label: chat.isMuted ? 'Unmute' : 'Mute',
                  color: mutedColor,
                  textColor: textColor,
                  onTap: () {
                    final engine = context.read<EngineService>();
                    engine.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
                    chatState.loadChats();
                  },
                ),
                _actionTile(
                  icon: chat.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  label: chat.isPinned ? 'Unpin' : 'Pin',
                  color: mutedColor,
                  textColor: textColor,
                  onTap: () {
                    final engine = context.read<EngineService>();
                    engine.pinChat(chat.accountId, chat.chatId, !chat.isPinned);
                    chatState.loadChats();
                  },
                ),
                _actionTile(
                  icon: Icons.archive_outlined,
                  label: chat.isArchived ? 'Unarchive' : 'Archive',
                  color: mutedColor,
                  textColor: textColor,
                  onTap: () {
                    final engine = context.read<EngineService>();
                    engine.archiveChat(chat.accountId, chat.chatId, !chat.isArchived);
                    chatState.loadChats();
                  },
                ),
                const SizedBox(height: 4),
                _actionTile(
                  icon: chat.type == ChatType.dm ? Icons.delete_outline_rounded : Icons.exit_to_app_rounded,
                  label: chat.type == ChatType.dm ? 'Delete Chat' : 'Leave',
                  color: AppColors.danger,
                  textColor: AppColors.danger,
                  onTap: () {
                    // Confirm before destructive action
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Leave/delete not yet implemented')),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
      onTap: onTap,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Empty state (no chat selected)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasAccounts = appState.accounts.isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasAccounts ? Icons.chat_bubble_outline_rounded : Icons.add_circle_outline_rounded,
            size: 64,
            color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
          ),
          const SizedBox(height: 16),
          Text(
            hasAccounts
                ? 'Select a chat to start messaging'
                : 'Add a platform to get started',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
          if (!hasAccounts) ...[
            const SizedBox(height: 8),
            Text(
              'Click the + button on the left',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMemberTile(MemberInfo member, bool isDark) {
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final name = member.label;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          // Avatar with online indicator
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _avatarColor(name),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _avatarInitial(name),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                if (member.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3BA55C),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Name + role badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (member.username.isNotEmpty)
                  Text(
                    '@${member.username}',
                    style: TextStyle(fontSize: 11, color: mutedColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Role badge
          if (member.role == 'owner' || member.role == 'admin')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (member.role == 'owner' ? const Color(0xFFFAA61A) : AppColors.accent).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                member.role == 'owner' ? 'Owner' : 'Admin',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: member.role == 'owner' ? const Color(0xFFFAA61A) : AppColors.accent,
                ),
              ),
            ),
          if (member.isBot)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.smart_toy_rounded, size: 14, color: mutedColor),
            ),
        ],
      ),
    );
  }

  Color _avatarColor(String title) {
    if (title.isEmpty) return AppColors.accent;
    final colors = [
      const Color(0xFF4F6EF7),
      const Color(0xFF3BA55C),
      const Color(0xFFFAA61A),
      const Color(0xFFED4245),
      const Color(0xFF9B59B6),
      const Color(0xFFE67E22),
      const Color(0xFF1ABC9C),
      const Color(0xFFE91E63),
    ];
    return colors[title.codeUnitAt(0) % colors.length];
  }

  String _avatarInitial(String title) {
    if (title.isEmpty) return '?';
    return title[0].toUpperCase();
  }

  IconData _platformIcon(String platform) {
    return switch (platform.toLowerCase()) {
      'telegram' => Icons.send_rounded,
      'matrix' => Icons.grid_view_rounded,
      'xmpp' => Icons.chat_rounded,
      'irc' => Icons.tag_rounded,
      'bale' => Icons.message_rounded,
      'rubika' => Icons.diamond_rounded,
      'delta' || 'deltachat' => Icons.mail_rounded,
      'mumble' => Icons.headset_mic_rounded,
      'teamspeak' || 'ts3' => Icons.headphones_rounded,
      'discord' => Icons.gamepad_rounded,
      _ => Icons.account_circle_rounded,
    };
  }

  String _platformLabel(String platform) {
    return switch (platform.toLowerCase()) {
      'telegram' => 'Telegram',
      'matrix' => 'Matrix',
      'xmpp' => 'XMPP',
      'irc' => 'IRC',
      'bale' => 'Bale',
      'rubika' => 'Rubika',
      'delta' || 'deltachat' => 'Delta Chat',
      'mumble' => 'Mumble',
      'teamspeak' || 'ts3' => 'TeamSpeak',
      'discord' => 'Discord',
      _ => platform,
    };
  }

  /// Auto-show auth dialog when an account needs re-authentication.
  void _checkAuthRequired(BuildContext context, AppState appState) {
    if (!appState.initialized) return;
    for (final account in appState.accounts) {
      final state = appState.connStateFor(account.id);
      if (state == ConnState.authRequired && !_authPromptedIds.contains(account.id)) {
        _authPromptedIds.add(account.id);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          showDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (_) => AuthScreen(accountId: account.id, platform: account.platform),
          ).then((_) {
            if (context.mounted) {
              context.read<ChatState>().loadChats();
            }
          });
        });
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Narrow search screen (stateful for its own text controller)
// ════════════════════════════════════════════════════════════════════════════

class _NarrowSearchScreen extends StatefulWidget {
  const _NarrowSearchScreen({super.key});

  @override
  State<_NarrowSearchScreen> createState() => _NarrowSearchScreenState();
}

class _NarrowSearchScreenState extends State<_NarrowSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final dimColor = isDark ? AppColors.darkTextDim : AppColors.lightTextDim;
    final bgColor = isDark ? AppColors.darkBase : AppColors.lightBase;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    final chatResults = _query.length >= 2 ? chatState.searchChats(_query) : <ChatInfo>[];
    final msgResults = _query.length >= 2 ? chatState.searchMessages(_query) : <SearchResult>[];

    return Container(
      color: bgColor,
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _controller,
              autofocus: false,
              style: TextStyle(fontSize: 14, color: textColor),
              decoration: InputDecoration(
                hintText: 'Search chats and messages...',
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: mutedColor),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, size: 18, color: mutedColor),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          // Results
          Expanded(
            child: _query.length < 2
                ? Center(
                    child: Text(
                      'Type to search chats and messages',
                      style: TextStyle(fontSize: 14, color: dimColor),
                    ),
                  )
                : (chatResults.isEmpty && msgResults.isEmpty)
                    ? Center(
                        child: Text(
                          'No results for "$_query"',
                          style: TextStyle(fontSize: 14, color: dimColor),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          // Chat matches
                          if (chatResults.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                              child: Text(
                                'CHATS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: mutedColor,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            ...chatResults.map((chat) => Container(
                              key: ValueKey('sr_${chat.accountId}_${chat.chatId}'),
                              margin: const EdgeInsets.symmetric(vertical: 1),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _avatarColor(chat.title),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _avatarInitial(chat.title),
                                    style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  chat.title,
                                  style: TextStyle(fontSize: 14, color: textColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: chat.lastMsgText.isNotEmpty
                                    ? Text(
                                        chat.lastMsgText,
                                        style: TextStyle(fontSize: 12, color: mutedColor),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                onTap: () => chatState.openChat(chat),
                              ),
                            )),
                          ],
                          // Message matches
                          if (msgResults.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                              child: Text(
                                'MESSAGES',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: mutedColor,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            ...msgResults.map((result) => Container(
                              key: ValueKey('mr_${result.accountId}_${result.msgId}'),
                              margin: const EdgeInsets.symmetric(vertical: 1),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.message_outlined, size: 20, color: mutedColor),
                                title: Text(
                                  result.chatTitle.isNotEmpty ? result.chatTitle : 'Chat',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (result.senderName.isNotEmpty)
                                      Text(
                                        result.senderName,
                                        style: const TextStyle(fontSize: 11, color: AppColors.accent),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      result.text,
                                      style: TextStyle(fontSize: 12, color: mutedColor),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  // Find the matching chat and open it
                                  final chats = chatState.chats;
                                  final match = chats.where(
                                    (c) => c.chatId == result.chatId && c.accountId == result.accountId,
                                  ).firstOrNull;
                                  if (match != null) {
                                    chatState.openChat(match);
                                  }
                                },
                              ),
                            )),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Color _avatarColor(String title) {
    if (title.isEmpty) return AppColors.accent;
    const colors = [
      Color(0xFF4F6EF7), Color(0xFF3BA55C), Color(0xFFFAA61A), Color(0xFFED4245),
      Color(0xFF9B59B6), Color(0xFFE67E22), Color(0xFF1ABC9C), Color(0xFFE91E63),
    ];
    return colors[title.codeUnitAt(0) % colors.length];
  }

  String _avatarInitial(String title) {
    if (title.isEmpty) return '?';
    return title[0].toUpperCase();
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Shared Media Gallery (right panel)
// ══════════════════════════════════════════════════════════════════════════

class _SharedMediaGallery extends StatefulWidget {
  final String accountId;
  final String chatId;
  final bool isDark;

  const _SharedMediaGallery({
    required this.accountId,
    required this.chatId,
    required this.isDark,
  });

  @override
  State<_SharedMediaGallery> createState() => _SharedMediaGalleryState();
}

class _SharedMediaGalleryState extends State<_SharedMediaGallery> {
  static const _pageSize = 30;
  static const _tabs = ['All', 'Photos', 'Videos', 'Files'];
  static const _tabFilters = ['', 'image', 'video', 'file'];

  int _activeTab = 0;
  List<SharedMediaItem> _items = [];
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  @override
  void didUpdateWidget(covariant _SharedMediaGallery old) {
    super.didUpdateWidget(old);
    if (old.accountId != widget.accountId || old.chatId != widget.chatId) {
      _activeTab = 0;
      _items = [];
      _hasMore = true;
      _loadMedia();
    }
  }

  void _loadMedia({bool append = false}) {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final engine = context.read<EngineService>();
      final offset = append ? _items.length : 0;
      final newItems = engine.getSharedMedia(
        widget.accountId,
        widget.chatId,
        mediaType: _tabFilters[_activeTab],
        limit: _pageSize,
        offset: offset,
      );

      setState(() {
        if (append) {
          _items.addAll(newItems);
        } else {
          _items = newItems;
        }
        _hasMore = newItems.length >= _pageSize;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _switchTab(int index) {
    if (index == _activeTab) return;
    setState(() {
      _activeTab = index;
      _items = [];
      _hasMore = true;
    });
    _loadMedia();
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = widget.isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final dimColor = widget.isDark ? AppColors.darkTextDim : AppColors.lightTextDim;
    final surfaceColor = widget.isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Shared Media',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: mutedColor,
            ),
          ),
        ),

        // Filter tabs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final isActive = _activeTab == i;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => _switchTab(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _tabs[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive ? AppColors.accent : mutedColor,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),

        // Content
        if (_loading && _items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: mutedColor),
              ),
            ),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                'No media found',
                style: TextStyle(fontSize: 13, color: dimColor),
              ),
            ),
          )
        else
          _buildMediaContent(surfaceColor, mutedColor, dimColor),

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildMediaContent(Color surfaceColor, Color mutedColor, Color dimColor) {
    // Use grid for images/videos, list for files
    final isGridMode = _activeTab != 3; // Not "Files" tab

    if (isGridMode) {
      return _buildGrid(surfaceColor, mutedColor, dimColor);
    } else {
      return _buildFileList(mutedColor, dimColor);
    }
  }

  Widget _buildGrid(Color surfaceColor, Color mutedColor, Color dimColor) {
    // Filter: in grid mode show only visual media (images, videos, gifs, stickers)
    final visualItems = _activeTab == 0
        ? _items // All tab: show everything in grid
        : _items;

    final itemCount = visualItems.length + (_hasMore ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index >= visualItems.length) {
                // Load more trigger — manual tap to avoid infinite auto-load loop
                // (shrinkWrap grid builds all children at once, so auto-trigger
                //  via addPostFrameCallback fires repeatedly until all pages load).
                if (_loading) {
                  return Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: mutedColor),
                    ),
                  );
                }
                return GestureDetector(
                  onTap: () => _loadMedia(append: true),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.expand_more, color: mutedColor, size: 24),
                    ),
                  ),
                );
              }
              return _buildGridItem(visualItems[index], surfaceColor, dimColor);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(SharedMediaItem item, Color surfaceColor, Color dimColor) {
    Widget content;

    if (item.thumbB64.isNotEmpty) {
      // Has thumbnail -- decode base64 and show image
      try {
        final bytes = base64Decode(item.thumbB64);
        content = Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _mediaPlaceholder(item, dimColor),
        );
      } catch (_) {
        content = _mediaPlaceholder(item, dimColor);
      }
    } else {
      content = _mediaPlaceholder(item, dimColor);
    }

    // Video overlay with duration
    if (item.isVideo && item.duration > 0) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(item.duration),
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        color: surfaceColor,
        child: content,
      ),
    );
  }

  Widget _mediaPlaceholder(SharedMediaItem item, Color dimColor) {
    IconData icon;
    if (item.isImage) {
      icon = Icons.image_outlined;
    } else if (item.isVideo) {
      icon = Icons.videocam_outlined;
    } else if (item.isAudio) {
      icon = Icons.audiotrack_outlined;
    } else {
      icon = Icons.insert_drive_file_outlined;
    }

    return Center(
      child: Icon(icon, size: 28, color: dimColor),
    );
  }

  Widget _buildFileList(Color mutedColor, Color dimColor) {
    final fileItems = _items.where((item) => item.isFile || item.isAudio).toList();
    if (fileItems.isEmpty && _items.isNotEmpty) {
      // Show all items if no pure files
      return _buildFileListInner(_items, mutedColor, dimColor);
    }
    return _buildFileListInner(fileItems.isEmpty ? _items : fileItems, mutedColor, dimColor);
  }

  Widget _buildFileListInner(List<SharedMediaItem> items, Color mutedColor, Color dimColor) {
    final textColor = widget.isDark ? AppColors.darkText : AppColors.lightText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _fileIcon(item.mimeType),
                  size: 18,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.fileName.isNotEmpty ? item.fileName : 'File',
                      style: TextStyle(fontSize: 13, color: textColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        if (item.fileSizeLabel.isNotEmpty)
                          Text(
                            item.fileSizeLabel,
                            style: TextStyle(fontSize: 11, color: dimColor),
                          ),
                        if (item.fileSizeLabel.isNotEmpty && item.timestamp > 0)
                          Text(' \u00b7 ', style: TextStyle(fontSize: 11, color: dimColor)),
                        if (item.timestamp > 0)
                          Text(
                            _formatDate(item.dateTime),
                            style: TextStyle(fontSize: 11, color: dimColor),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        )),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.all(8),
            child: GestureDetector(
              onTap: () => _loadMedia(append: true),
              child: const Text(
                'Load more...',
                style: TextStyle(fontSize: 12, color: AppColors.accent),
              ),
            ),
          ),
      ],
    );
  }

  IconData _fileIcon(String mimeType) {
    if (mimeType.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mimeType.startsWith('video/')) return Icons.videocam_outlined;
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mimeType.contains('zip') || mimeType.contains('rar') || mimeType.contains('tar')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
