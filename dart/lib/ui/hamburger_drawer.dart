import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import 'confirm_box.dart';
import '../state/chat_state.dart';
import 'chat_list_row.dart' show isSavedMessages;
import 'contacts_screen.dart';
import 'create_channel_screen.dart';
import 'my_profile_page.dart';
import 'settings_screen.dart';

/// Hamburger menu drawer. Spec §3: 274px wide, 134px cover.
/// Shows active account profile at top, collapsible account switcher,
/// then menu items.
class HamburgerDrawer extends StatefulWidget {
  const HamburgerDrawer({super.key});

  @override
  State<HamburgerDrawer> createState() => _HamburgerDrawerState();
}

class _HamburgerDrawerState extends State<HamburgerDrawer> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();
    final isDark = theme.brightness == Brightness.dark;
    final accountsExpanded = appState.mainMenuAccountsShown;

    return Container(
      width: 274,
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile cover area (134px) — shows active account.
            _ProfileCover(
              account: appState.activeAccount,
              connState: appState.connStateFor(appState.activeAccountId),
              expanded: accountsExpanded,
              onToggle: () => appState.setMainMenuAccountsShown(!accountsExpanded),
              accountCount: appState.accounts.length,
            ),
            // 1px PlainShadow at bottom of cover (spec §3: shadowFg).
            Container(
              height: 1,
              color: isDark
                  ? const Color(0x5604080e)
                  : const Color(0x18000000),
            ),
            // Spec §3: entire menu below cover is a single defaultSolidScroll
            // ScrollArea. Accounts extend the layout; the scroll bar takes over.
            // Colors: scrollBarBg day #00000053 / night #ffffff53,
            //         scrollBarBgOver day #0000007a / night #ffffff7a.
            Expanded(
              child: ScrollbarTheme(
                data: ScrollbarThemeData(
                  thumbVisibility: WidgetStateProperty.all(true),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    final hovered = states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.dragged);
                    if (isDark) {
                      return hovered
                          ? const Color(0x7affffff)
                          : const Color(0x53ffffff);
                    }
                    return hovered
                        ? const Color(0x7a000000)
                        : const Color(0x53000000);
                  }),
                  thickness: WidgetStateProperty.all(6.0),
                  radius: const Radius.circular(3),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  interactive: true,
                  child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Account list (collapsible) — SlideWrap toggled by
                    // mainMenuAccountsShownValue (spec §3.2). 6px mainMenuSkip spacers.
                    ClipRect(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.linear,
                        alignment: Alignment.topCenter,
                        child: accountsExpanded
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 6),
                                  _AccountList(
                                    accounts: appState.accounts,
                                    activeAccountId: appState.activeAccountId,
                                    chatState: context.watch<ChatState>(),
                                    onSelect: (id) {
                                      if (id == appState.activeAccountId) {
                                        // Spec §3.2: clicking active account closes drawer.
                                        Navigator.of(context).pop();
                                        return;
                                      }
                                      appState.setActiveAccountId(id);
                                      context.read<ChatState>().switchAccount(id);
                                      appState.setMainMenuAccountsShown(false);
                                    },
                                    onActivate: (id) {
                                      appState.setActiveAccountId(id);
                                      context.read<ChatState>().switchAccount(id);
                                      appState.setMainMenuAccountsShown(false);
                                    },
                                    onMarkAsRead: (id) {
                                      context.read<ChatState>().markAllChatsReadForAccount(id);
                                    },
                                    onLogOut: (id) {
                                      Navigator.of(context).pop(); // close drawer
                                      appState.removeAccount(id);
                                    },
                                    onAddAccount: () =>
                                        _showAddAccountDialog(context, appState),
                                    onAddAccountTest: () =>
                                        _showAddAccountDialog(
                                            context, appState,
                                            testMode: true),
                                    canAddAccount: appState.canAddAccount,
                                    onReorder: appState.reorderAccounts,
                                  ),
                                  const SizedBox(height: 6),
                                  // PlainShadow below accounts when open (spec §3).
                                  Container(
                                    height: 1,
                                    color: isDark
                                        ? const Color(0x5604080e)
                                        : const Color(0x18000000),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    // §3.3 Menu Items — My Profile row.
                    _MenuRow(
                      icon: Icons.person,
                      label: 'My Profile',
                      onTap: () {
                        final chatSt = context.read<ChatState>();
                        final authSt = context.read<AuthState>();
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: appState,
                              child: ChangeNotifierProvider.value(
                                value: chatSt,
                                child: ChangeNotifierProvider.value(
                                  value: authSt,
                                  child: const MyProfilePage(),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // §3.3 / §54.8a: Menu Bots rows (dynamic per-bot).
                    // Each attach-menu bot with inMainMenu + bot.media gets
                    // its own row. Uses same mainMenuButton styling.
                    for (final bot in appState.menuBots)
                      _MenuRow(
                        icon: Icons.smart_toy,
                        label: bot.name,
                        iconPath: bot.iconPath,
                        onTap: () {
                          Navigator.of(context).pop();
                          // TODO: open bot's web app when engine supports it
                        },
                      ),
                    // §3.3: PlainShadow divider below My Profile/Bots block
                    // with 6px mainMenuSkip padding top and bottom.
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Container(
                        height: 1,
                        color: isDark
                            ? const Color(0x5604080e)
                            : const Color(0x18000000),
                      ),
                    ),
                    // §3.3: New Group row.
                    _MenuRow(
                      icon: Icons.group,
                      label: 'New Group',
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: open new group creation flow
                      },
                    ),
                    // §3.3: New Channel row (item 4).
                    _MenuRow(
                      icon: Icons.campaign,
                      label: 'New Channel',
                      onTap: () {
                        final chatSt = context.read<ChatState>();
                        final authSt = context.read<AuthState>();
                        final engineSvc = context.read<EngineService>();
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: appState,
                              child: Provider<EngineService>.value(
                                value: engineSvc,
                                child: ChangeNotifierProvider.value(
                                  value: chatSt,
                                  child: ChangeNotifierProvider.value(
                                    value: authSt,
                                    child: const CreateChannelScreen(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // §3.3: Contacts row (item 5) — menuIconUserShow.
                    _MenuRow(
                      icon: Icons.contacts,
                      label: 'Contacts',
                      onTap: () {
                        final chatSt = context.read<ChatState>();
                        final authSt = context.read<AuthState>();
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: appState,
                              child: ChangeNotifierProvider.value(
                                value: chatSt,
                                child: ChangeNotifierProvider.value(
                                  value: authSt,
                                  child: const ContactsScreen(),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // §3.3: Calls row (item 6) — menuIconPhone.
                    _MenuRow(
                      icon: Icons.phone,
                      label: 'Calls',
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: open calls screen
                      },
                    ),
                    // §3.3: Saved Messages row (item 7) — menuIconSavedMessages.
                    // Click handler: open self-chat (Saved Messages).
                    _MenuRow(
                      icon: Icons.bookmark,
                      label: 'Saved Messages',
                      onTap: () {
                        Navigator.of(context).pop();
                        final chatState = context.read<ChatState>();
                        final saved = chatState.chats
                            .where((c) => isSavedMessages(c))
                            .firstOrNull;
                        if (saved != null) {
                          chatState.openChat(saved);
                        }
                      },
                    ),
                    // §3.3: Settings row (item 8) — menuIconSettings.
                    // Opens the Settings page (§14) as a full-height panel.
                    _MenuRow(
                      icon: Icons.settings,
                      label: 'Settings',
                      onTap: () {
                        // Capture providers before pop() deactivates the
                        // drawer context (avoids "deactivated widget" error).
                        final chatSt = context.read<ChatState>();
                        final authSt = context.read<AuthState>();
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: appState,
                              child: ChangeNotifierProvider.value(
                                value: chatSt,
                                child: ChangeNotifierProvider.value(
                                  value: authSt,
                                  child: const SettingsScreen(),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    _MenuRow(
                      icon: Icons.nightlight_round,
                      label: 'Night Mode',
                      trailing: _InlineToggle(
                        value: isDark,
                        onChanged: (dark) {
                          appState.updateTheme(dark ? 'dark' : 'light');
                        },
                      ),
                      onTap: () {
                        appState.updateTheme(!isDark ? 'dark' : 'light');
                      },
                    ),
                    // §3.3: Archive row — shown when user has archived chats.
                    if (context.watch<ChatState>().hasArchivedChats)
                      _MenuRow(
                        icon: Icons.archive,
                        label: 'Archived Chats',
                        onTap: () {
                          Navigator.of(context).pop();
                          appState.requestShowArchive();
                        },
                      ),
                    if (Platform.isLinux)
                      _MenuRow(
                        icon: Icons.desktop_windows,
                        label: 'System Frame',
                        trailing: _InlineToggle(
                          value: appState.nativeWindowFrame,
                          onChanged: (value) {
                            appState.setNativeWindowFrame(value);
                          },
                        ),
                        onTap: () {
                          appState.setNativeWindowFrame(!appState.nativeWindowFrame);
                        },
                      ),
                    // §3.6: Footer — product name + version/about links.
                    const _FooterSection(),
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

  void _showAddAccountDialog(BuildContext context, AppState appState,
      {bool testMode = false}) {
    // Spec §3.2: enforce max accounts limit.
    if (!appState.canAddAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum account limit reached (${appState.maxAccountLimit})',
          ),
        ),
      );
      return;
    }
    final authState = context.read<AuthState>();
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(testMode ? 'Add Test Account' : 'Add Account'),
        children: [
          for (final p in [
            ('telegram', 'Telegram'),
            ('matrix', 'Matrix'),
            ('xmpp', 'XMPP'),
            ('irc', 'IRC'),
            ('bale', 'Bale'),
            ('rubika', 'Rubika'),
            ('deltachat', 'Delta Chat'),
            ('mumble', 'Mumble'),
            ('teamspeak', 'TeamSpeak'),
          ])
            SimpleDialogOption(
              child: Text(p.$2),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(); // close drawer
                final id = appState.addAccount(p.$1);
                authState.startAuth(id);
              },
            ),
        ],
      ),
    );
  }
}

/// Profile area at top of drawer (134px). Shows the active account.
class _ProfileCover extends StatelessWidget {
  final AccountInfo? account;
  final ConnState connState;
  final bool expanded;
  final VoidCallback onToggle;
  final int accountCount;

  const _ProfileCover({
    required this.account,
    required this.connState,
    required this.expanded,
    required this.onToggle,
    required this.accountCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final connColor = switch (connState) {
      ConnState.connected => const Color(0xFF3BA55C),
      ConnState.connecting => const Color(0xFFFAA61A),
      ConnState.unstable => const Color(0xFFFAA61A),
      ConnState.disconnected => Colors.grey,
    };

    // mainMenuCoverBg = windowBgActive: solid accent fill (spec §3).
    // Day: #40a7e3, Night: #5288c1.
    final coverBg = isDark
        ? const Color(0xFF5288C1)
        : const Color(0xFF40A7E3);

    return Container(
      height: 134,
      decoration: BoxDecoration(
        color: coverBg,
      ),
      child: Stack(
        children: [
          // Avatar: 48x48px at left 24, top 20 (spec §3).
          Positioned(
            left: 24,
            top: 20,
            child: GestureDetector(
              onTap: onToggle,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.primary,
                    backgroundImage: account?.avatarPath.isNotEmpty == true
                        ? FileImage(File(account!.avatarPath))
                        : null,
                    child: account?.avatarPath.isNotEmpty != true
                        ? _initials(account?.displayName ?? '?', theme)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: connColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: coverBg,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Display name at left 26, top 84 (spec §3).
          // Font: semiboldFont 13px, color: windowBoldFg.
          // Optional premium/verified badge follows with semiboldFont spacew gap.
          Positioned(
            left: 26,
            top: 84,
            right: 50,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    account?.displayName.isNotEmpty == true
                        ? account!.displayName
                        : _platformLabel(account?.platform ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (account?.isVerified == true || account?.isPremium == true) ...[
                  const SizedBox(width: 4),
                  Icon(
                    account?.isPremium == true
                        ? Icons.workspace_premium
                        : Icons.verified,
                    size: 16,
                    color: Colors.white,
                  ),
                ],
                // AyuGram/Extera badge equivalent: UniClient app icon badge.
                // Spec §3.1: offset by infoVerifiedCheckPosition.x() (~4px)
                // from the verified badge (or name if no badge).
                const SizedBox(width: 4),
                Image.asset(
                  'assets/icon/icon_256.png',
                  width: 16,
                  height: 16,
                  filterQuality: FilterQuality.medium,
                ),
              ],
            ),
          ),
          // Status line at left 26, top 103 (spec §3.1).
          // Phone: plain text, windowSubTextFg (white 70%).
          // "Set Emoji Status": link-styled (full white + underline), tappable.
          Positioned(
            left: 26,
            top: 103,
            right: 50,
            child: _buildStatusLine(context, account),
          ),
          // Account-list toggle chevron at (30,30) from top-right.
          // Spec §3: 6×6px chevron, 3px strokes. Only shown when 2+ accounts.
          if (accountCount >= 2)
            Positioned(
              right: 18,
              top: 18,
              child: GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: AnimatedRotation(
                      turns: expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.linear,
                      child: CustomPaint(
                        size: const Size(6, 6),
                        painter: _ChevronPainter(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusLine(BuildContext context, AccountInfo? account) {
    if (account == null) return const SizedBox.shrink();
    // Phone number: plain subdued text (windowSubTextFg).
    if (account.phone.isNotEmpty) {
      return Text(
        account.phone,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      );
    }
    // "Set Emoji Status": link-styled (spec §3.1 — FlatLabel link entity).
    // Full-opacity white + underline distinguishes from plain subdued text.
    // Tap navigates to Settings (profile/status configuration).
    return GestureDetector(
      onTap: () {
        final appState = context.read<AppState>();
        final chatSt = context.read<ChatState>();
        final authSt = context.read<AuthState>();
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: appState,
              child: ChangeNotifierProvider.value(
                value: chatSt,
                child: ChangeNotifierProvider.value(
                  value: authSt,
                  child: const SettingsScreen(),
                ),
              ),
            ),
          ),
        );
      },
      child: const Text(
        'Set Emoji Status',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xB3FFFFFF), // white 70%
        ),
      ),
    );
  }

  Widget _initials(String name, ThemeData theme) {
    final init = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Text(init, style: const TextStyle(
        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600));
  }

  static String _platformLabel(String platform) => switch (platform) {
    'telegram' => 'Telegram',
    'matrix' => 'Matrix',
    'xmpp' => 'XMPP',
    'irc' => 'IRC',
    'bale' => 'Bale',
    'rubika' => 'Rubika',
    'deltachat' => 'Delta Chat',
    'mumble' => 'Mumble',
    'teamspeak' => 'TeamSpeak',
    'github' => 'GitHub',
    _ => platform,
  };
}

/// Custom painter for the 6×6px toggle chevron (spec §3).
/// Draws a V-shaped chevron with 3px strokes.
class _ChevronPainter extends CustomPainter {
  final Color color;

  const _ChevronPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => color != oldDelegate.color;
}

/// Expandable account list for switching accounts.
/// Spec §3.2: each row is a SettingsButton with mainMenuButton styling.
/// Supports drag-to-reorder via ReorderableListView.
class _AccountList extends StatelessWidget {
  final List<AccountInfo> accounts;
  final String activeAccountId;
  final ChatState chatState;
  final void Function(String id) onSelect;
  final void Function(String id) onActivate;
  final void Function(String id) onMarkAsRead;
  final void Function(String id) onLogOut;
  final VoidCallback onAddAccount;
  final VoidCallback onAddAccountTest;
  final bool canAddAccount;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _AccountList({
    required this.accounts,
    required this.activeAccountId,
    required this.chatState,
    required this.onSelect,
    required this.onActivate,
    required this.onMarkAsRead,
    required this.onLogOut,
    required this.onAddAccount,
    required this.onAddAccountTest,
    required this.canAddAccount,
    required this.onReorder,
  });

  static const platformIcons = <String, IconData>{
    'telegram': Icons.send,
    'matrix': Icons.grid_view,
    'xmpp': Icons.message,
    'irc': Icons.tag,
    'bale': Icons.chat,
    'rubika': Icons.radio_button_checked,
    'deltachat': Icons.email,
    'mumble': Icons.headset_mic,
    'teamspeak': Icons.headset,
    'github': Icons.code,
  };

  /// Spec §3.2: Right-click on "Add Account" shows context menu to pick
  /// Production vs Test server (settings_information.cpp:1023-1050).
  void _showAddAccountContextMenu(
      BuildContext context, Offset position, bool isDark) {
    final menuBg = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final hoverColor =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final iconColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: menuBg,
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        _ContextMenuItem(
          value: 'production',
          icon: Icons.person_add,
          label: 'Add Account',
          textColor: textColor,
          iconColor: iconColor,
          hoverColor: hoverColor,
        ),
        _ContextMenuItem(
          value: 'test',
          icon: Icons.science,
          label: 'Add Test Account',
          textColor: textColor,
          iconColor: iconColor,
          hoverColor: hoverColor,
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'production':
          onAddAccount();
        case 'test':
          onAddAccountTest();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Spec §3.2: windowBoldFg for label, windowBgOver for hover.
    final labelColor = isDark
        ? const Color(0xFFE1E3E6)
        : const Color(0xFF222222);
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);

    // Spec §3.2: accounts expand naturally within the parent ScrollArea.
    // Drag-to-reorder via ReorderableListView (spec: VerticalLayoutReorder).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: accounts.length,
          onReorder: onReorder,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            return Material(
              elevation: 6 * animation.value,
              color: isDark
                  ? const Color(0xFF232E3C)
                  : const Color(0xFFF1F1F1),
              child: child,
            );
          },
          itemBuilder: (context, index) {
            final account = accounts[index];
            return _ReorderDragListener(
              key: ValueKey(account.id),
              index: index,
              child: _AccountRow(
                account: account,
                isActive: account.id == activeAccountId,
                unreadCount: chatState.unreadCountForAccount(account.id),
                unreadAllMuted: chatState.isAccountUnreadAllMuted(account.id),
                labelColor: labelColor,
                hoverBg: hoverBg,
                onTap: () => onSelect(account.id),
                onActivate: () => onActivate(account.id),
                onMarkAsRead: () => onMarkAsRead(account.id),
                onLogOut: () => onLogOut(account.id),
              ),
            );
          },
        ),
        // Spec §3.2: "Add Account" button — last row, settingsIconAdd in
        // windowBgActive, label in windowBoldFg. mainMenuAddAccountButton
        // style (iconLeft 23px, same row padding as account rows).
        // Ctrl+click = new window; normal click = add account dialog.
        // Right-click = context menu (Production vs Test server).
        // Auto-hides once account count reaches kPremiumMaxAccounts (spec §3.2).
        if (canAddAccount) GestureDetector(
          onSecondaryTapUp: (details) {
            _showAddAccountContextMenu(
                context, details.globalPosition, isDark);
          },
          child: InkWell(
            onTap: () {
              final ctrlHeld = HardwareKeyboard.instance.logicalKeysPressed
                  .any((k) =>
                      k == LogicalKeyboardKey.controlLeft ||
                      k == LogicalKeyboardKey.controlRight);
              if (ctrlHeld) {
                // Spec §3.2: Ctrl+click launches new app window.
                Process.start(
                  Platform.resolvedExecutable,
                  [],
                  mode: ProcessStartMode.detached,
                );
              } else {
                onAddAccount();
              }
            },
            hoverColor: hoverBg,
            splashColor: hoverBg.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.only(top: 11, bottom: 9, right: 20),
              child: Row(
                children: [
                  const SizedBox(width: 23), // iconLeft: 23px
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: Icon(
                        Icons.add,
                        size: 24, // settingsIconAdd: 24x24 standard icon
                        color: isDark
                            ? const Color(0xFF5288C1)
                            : const Color(0xFF40A7E3), // windowBgActive
                      ),
                    ),
                  ),
                  const SizedBox(width: 2), // 23 + 36 + 2 = 61px text start
                  Expanded(
                    child: Text(
                      'Add Account',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: labelColor, // windowBoldFg (same as account rows)
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Single account row matching Telegram Desktop SettingsButton style.
/// Spec §3.2: padding margins(61, 11, 20, 9), semiboldTextStyle 13px,
/// iconLeft 23px, avatar 26px photo + 5px padding each side = 36x36.
class _AccountRow extends StatelessWidget {
  final AccountInfo account;
  final bool isActive;
  final int unreadCount;
  final bool unreadAllMuted;
  final Color labelColor;
  final Color hoverBg;
  final VoidCallback onTap;
  final VoidCallback onActivate;
  final VoidCallback onMarkAsRead;
  final VoidCallback onLogOut;

  const _AccountRow({
    super.key,
    required this.account,
    required this.isActive,
    required this.unreadCount,
    required this.unreadAllMuted,
    required this.labelColor,
    required this.hoverBg,
    required this.onTap,
    required this.onActivate,
    required this.onMarkAsRead,
    required this.onLogOut,
  });

  void _showContextMenu(BuildContext context, Offset position) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec §9.1: menuBg, windowBgOver, windowFg, menuSeparatorFg.
    final menuBg = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final hoverColor = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final iconColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final attentionColor = isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E);

    final items = <PopupMenuEntry<String>>[];

    // Spec §3.2: "New Window" — only if inactive.
    if (!isActive) {
      items.add(_ContextMenuItem(
        value: 'new_window',
        icon: Icons.open_in_new,
        label: 'New Window',
        textColor: textColor,
        iconColor: iconColor,
        hoverColor: hoverColor,
      ));
    }

    // Spec §3.2: "Copy Phone" — always shown.
    if (account.phone.isNotEmpty) {
      items.add(_ContextMenuItem(
        value: 'copy_phone',
        icon: Icons.copy,
        label: 'Copy Phone',
        textColor: textColor,
        iconColor: iconColor,
        hoverColor: hoverColor,
      ));
    }

    // Spec §3.2: "Activate" — only if inactive.
    if (!isActive) {
      items.add(_ContextMenuItem(
        value: 'activate',
        icon: Icons.check_circle_outline,
        label: 'Activate',
        textColor: textColor,
        iconColor: iconColor,
        hoverColor: hoverColor,
      ));
    }

    // Spec §3.2: "Mark as Read" — always shown.
    items.add(_ContextMenuItem(
      value: 'mark_read',
      icon: Icons.done_all,
      label: 'Mark as Read',
      textColor: textColor,
      iconColor: iconColor,
      hoverColor: hoverColor,
    ));

    // Spec §3.2: "Log Out" — always shown, attention (red) style.
    items.add(_ContextMenuItem(
      value: 'log_out',
      icon: Icons.logout,
      label: 'Log Out',
      textColor: attentionColor,
      iconColor: attentionColor,
      hoverColor: hoverColor,
    ));

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      color: menuBg,
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'new_window':
          // Spec §3.2: launch new app window for this account.
          Process.start(
            Platform.resolvedExecutable,
            [],
            mode: ProcessStartMode.detached,
          );
        case 'copy_phone':
          Clipboard.setData(ClipboardData(text: account.phone));
        case 'activate':
          onActivate();
        case 'mark_read':
          onMarkAsRead();
        case 'log_out':
          _confirmLogOut(context);
      }
    });
  }

  void _confirmLogOut(BuildContext context) {
    showConfirmBox(
      context,
      text: 'Are you sure you want to log out?',
      confirmText: 'Log Out',
      isDestructive: true,
      onConfirm: onLogOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      onLongPressStart: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverBg,
        splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        // Spec §3.2: margins(61px, 11px, 20px, 9px).
        // Left 61px is composed of: 23px iconLeft + 36px avatar + 2px gap.
        padding: const EdgeInsets.only(top: 11, bottom: 9, right: 20),
        child: Row(
          children: [
            const SizedBox(width: 23), // iconLeft: 23px
            // Avatar: 26px photo (radius 13) + 5px padding each side = 36x36.
            // Active account: 2px stroke ring in windowBgActive (spec §3.2).
            SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Container(
                  decoration: isActive
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? const Color(0xFF5288C1)
                                : const Color(0xFF40A7E3),
                            width: 2,
                          ),
                        )
                      : null,
                  padding: isActive
                      ? const EdgeInsets.all(2)
                      : EdgeInsets.zero,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.3),
                    child: Icon(
                      _AccountList.platformIcons[account.platform] ?? Icons.chat,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2), // 23 + 36 + 2 = 61px text start
            Expanded(
              child: Text(
                account.displayName.isNotEmpty
                    ? account.displayName
                    : _ProfileCover._platformLabel(account.platform),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Unread badge: spec §3.2 — mainMenuBadgeFont 11px bold,
            // mainMenuBadgeSize 18px. Hidden when 0. Trailing spacing 2px.
            if (unreadCount > 0) ...[
              const SizedBox(width: 2),
              _AccountUnreadBadge(
                count: unreadCount,
                muted: unreadAllMuted,
                isDark: theme.brightness == Brightness.dark,
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// Spec §9.1-styled context menu item with icon.
class _ContextMenuItem extends PopupMenuItem<String> {
  _ContextMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required Color textColor,
    required Color iconColor,
    required Color hoverColor,
  }) : super(
    value: value,
    // Spec §9.1: item padding with icon margins(54, 8, 17, 8), height ~29px.
    height: 29,
    padding: EdgeInsets.zero,
    child: _ContextMenuItemBody(
      icon: icon,
      label: label,
      textColor: textColor,
      iconColor: iconColor,
    ),
  );
}

class _ContextMenuItemBody extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color textColor;
  final Color iconColor;

  const _ContextMenuItemBody({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Spec §9.1: item padding with icon margins(54, 8, 17, 8).
      padding: const EdgeInsets.only(left: 15, top: 8, right: 17, bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 17),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Unread badge for account rows in the hamburger menu.
/// Spec §3.2: mainMenuBadgeFont 11px bold, mainMenuBadgeSize 18px.
/// Uses Lang::FormatCountToShort style (e.g. "1K" for 1000+).
class _AccountUnreadBadge extends StatelessWidget {
  final int count;
  final bool muted;
  final bool isDark;

  const _AccountUnreadBadge({
    required this.count,
    required this.muted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Spec §3.2: mainMenuBadgeSize 18px height, mainMenuBadgeFont 11px bold.
    // Unmuted: dialogsUnreadBg day #40a7e3 / night #5288c1 (accent blue).
    // Muted: dialogsUnreadBgMuted day #bbbbbb / night #3e546a (gray).
    // Badge text: windowFgActive #ffffff always.
    final Color bgColor;
    if (muted) {
      bgColor = isDark
          ? const Color(0xFF3E546A)
          : const Color(0xFFBBBBBB);
    } else {
      bgColor = isDark
          ? const Color(0xFF5288C1)
          : const Color(0xFF40A7E3);
    }

    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        _formatCountShort(count),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }

  /// Format count in short form like Telegram Desktop's FormatCountToShort.
  static String _formatCountShort(int count) {
    if (count < 1000) return count.toString();
    if (count < 100000) return '${(count / 1000).toStringAsFixed(count % 1000 == 0 ? 0 : 1)}K';
    if (count < 1000000) return '${count ~/ 1000}K';
    return '${(count / 1000000).toStringAsFixed(count % 1000000 == 0 ? 0 : 1)}M';
  }
}

/// Spec §3.3: mainMenuButton-styled row for hamburger menu items.
/// Row padding: margins(61px, 11px, 20px, 9px).
/// Icon: 24x24 at 21px horizontal, menuIconColor.
/// Label: semiboldTextStyle 13px semibold, windowBoldFg / windowBoldFgOver.
/// Hover: windowBgOver background + ripple.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? iconPath; // optional file-based icon (for menu bots)

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.iconPath,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec §3.3: windowBoldFg for label.
    final labelColor = isDark
        ? const Color(0xFFE1E3E6)
        : const Color(0xFF222222);
    // Spec §3.3: menuIconColor.
    final iconColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    // Spec §3.3: windowBgOver for hover.
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);

    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        // Spec §3.3: margins(61px, 11px, 20px, 9px).
        // Left 61px = 21px icon offset + 24px icon + 16px gap to label.
        padding: const EdgeInsets.only(
          left: 21,
          top: 11,
          right: 20,
          bottom: 9,
        ),
        child: Row(
          children: [
            // Spec §3.3: 24x24 icon at 21px horizontal.
            // Menu bots use file-based icons when available.
            if (iconPath != null && iconPath!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(iconPath!),
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(icon, size: 24, color: iconColor),
                ),
              )
            else
              Icon(icon, size: 24, color: iconColor),
            // Gap from icon to label: 61 - 21 - 24 = 16px.
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              // Spec §3.3: 19px toggle skip between label and trailing.
              const SizedBox(width: 19),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Small inline toggle matching Telegram Desktop's menu item toggle.
/// Spec §3: pill track + circle thumb, animates on toggle.
class _InlineToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _InlineToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // On: mainMenuCoverBg (windowBgActive).
    final onColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    // Off: windowSubTextFg.
    final offColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: value ? onColor : offColor,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps an account row to enable drag-to-reorder without visible handles.
/// Matches Telegram Desktop's VerticalLayoutReorder: press anywhere on the row
/// and drag >10px vertically to start reordering. Tap, right-click, and long-
/// press gestures pass through to the child's GestureDetector/InkWell normally.
class _ReorderDragListener extends StatelessWidget {
  final int index;
  final Widget child;

  const _ReorderDragListener({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        // Only start drag tracking for primary button (left-click / touch).
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons != kPrimaryButton) {
          return;
        }
        final list = SliverReorderableList.maybeOf(context);
        list?.startItemDragReorder(
          index: index,
          event: event,
          recognizer: _ThresholdDragRecognizer(debugOwner: this),
        );
      },
      child: child,
    );
  }
}

/// Drag recognizer that only accepts after 10px vertical pointer movement.
/// Matches Telegram Desktop's startDragDistance (Qt default ~10px).
/// Below the threshold: the recognizer stays pending, allowing tap and long-
/// press recognizers to win the gesture arena instead.
class _ThresholdDragRecognizer extends MultiDragGestureRecognizer {
  _ThresholdDragRecognizer({required super.debugOwner});

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _ThresholdPointerState(event.position, event.kind, gestureSettings);
  }

  @override
  String get debugDescription => 'threshold multi drag';
}

class _ThresholdPointerState extends MultiDragPointerState {
  /// Spec: Telegram Desktop uses startDragDistance() ≈ 10px.
  static const double _kThreshold = 10.0;

  _ThresholdPointerState(
    Offset initialPosition,
    PointerDeviceKind kind,
    DeviceGestureSettings? gestureSettings,
  ) : super(initialPosition, kind, gestureSettings);

  @override
  void checkForResolutionAfterMove() {
    assert(pendingDelta != null);
    if (pendingDelta!.dy.abs() > _kThreshold) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}

/// §3.6: Footer at bottom of drawer scroll area.
/// Two stacked lines at left 25px:
/// - Top: product name (semibold 13px, windowSubTextFg)
/// - Bottom: "Version X.Y.Z – About" (regular 13px, windowSubTextFg)
/// Min height 80px. Tooltip on version: "Build date: {date}".
class _FooterSection extends StatelessWidget {
  const _FooterSection();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // §3.6: windowSubTextFg for both lines and links (NOT blue-tinted).
    final subTextFg = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 80),
      child: Container(
        alignment: Alignment.bottomLeft,
        // §3.6: mainMenuFooterLeft 25px. Bottom positions:
        // top line bottom at 38px from widget bottom,
        // bottom line bottom at 17px from widget bottom.
        // With ~16px text height: bottom padding 17px, inter-line gap ~5px.
        padding: const EdgeInsets.only(left: 25, bottom: 17),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // §3.6 top line: product name / website link.
            // semiboldFont 13px, windowSubTextFg. Link same color.
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _openUrl(
                    'https://github.com/DarkReaperBoy/uniclient'),
                child: Text(
                  'UniClient',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: subTextFg,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            // §3.6 bottom line: version + about link.
            // defaultTextStyle 13px regular, windowSubTextFg.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Version link with tooltip "Build date: {date}".
                Tooltip(
                  message: 'Build date: 2026-04-20',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _openUrl(
                          'https://github.com/DarkReaperBoy/uniclient/releases'),
                      child: Text(
                        'Version 0.1.0 alpha',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: subTextFg,
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  ' – ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: subTextFg,
                  ),
                ),
                // "About" link → opens AboutBox.
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showAboutBox(context),
                    child: Text(
                      'About',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: subTextFg,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static void _openUrl(String url) {
    Process.run('xdg-open', [url]);
  }

  static void _showAboutBox(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subTextFg = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('UniClient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Version 0.1.0 alpha'),
            const SizedBox(height: 8),
            Text(
              'Unified multi-platform messaging client.',
              style: TextStyle(color: subTextFg),
            ),
            const SizedBox(height: 16),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _openUrl(
                    'https://github.com/DarkReaperBoy/uniclient'),
                child: Text(
                  'github.com/DarkReaperBoy/uniclient',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF5288C1)
                        : const Color(0xFF40A7E3),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
