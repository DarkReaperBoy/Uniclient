import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';
import '../main.dart' show switchThemeWithCrossFade;
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import 'confirm_box.dart';
import '../state/chat_state.dart';
import 'chat_list_row.dart' show isSavedMessages;
import 'calls_screen.dart';
import 'contacts_screen.dart';
import 'create_group_wizard.dart';
import 'info_panel.dart';
import 'popup_menu.dart';
import 'settings_screen.dart';
import 'shell.dart';
import 'web_app_panel.dart';
import 'settings_style.dart' show settingsPageRoute;
import 'telegram_toast.dart';
import 'telegram_tooltip.dart';
import '../theme/telegram_palette.dart';

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
            Container(
              height: 1,
              color: context.palette.shadowFg,
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
                                    color: context.palette.shadowFg,
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    // §3.3 Menu Items — My Profile row (§54.8: gated).
                    if (appState.showMyProfileInDrawer)
                    _MenuRow(
                      icon: Icons.person,
                      label: 'My Profile',
                      onTap: () {
                        Navigator.of(context).pop();
                        final selfUserId = appState.activeAccount?.selfUserId ?? '';
                        final selfName = appState.activeAccount?.displayName ?? '';
                        final member = MemberInfo(userId: selfUserId, displayName: selfName);
                        if (InfoPanel.pushUserProfileRequest != null) {
                          InfoPanel.pushUserProfileRequest!(member);
                        } else {
                          UniClientShell.toggleInfoRequest?.call();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            InfoPanel.pushUserProfileRequest?.call(member);
                          });
                        }
                      },
                    ),
                    // §3.3 / §54.8a: Menu Bots rows (§54.8: gated).
                    if (appState.showBotsInDrawer)
                    for (final bot in appState.menuBots)
                      GestureDetector(
                        onSecondaryTapUp: (details) {
                          showTelegramMenu<String>(
                            context: context,
                            position: details.globalPosition,
                            items: const [
                              TelegramMenuItem(value: 'remove', icon: Icon(Icons.delete_outline), label: 'Remove from Menu'),
                            ],
                          ).then((value) {
                            if (value == 'remove') {
                              final engine = context.read<EngineService>();
                              final accountId = appState.activeAccount?.id ?? '';
                              engine.removeBotFromMenu(accountId, bot.id);
                            }
                          });
                        },
                        child: _MenuRow(
                          icon: Icons.smart_toy,
                          label: bot.name,
                          iconPath: bot.iconPath,
                          onTap: () async {
                            Navigator.of(context).pop();
                            final chatState = context.read<ChatState>();
                            final url = await chatState.requestBotWebView(bot.id);
                            if (context.mounted) {
                              final acctId = context.read<AppState>().activeAccountId;
                              WebAppPanel.open(
                                context,
                                data: WebAppPanelData(
                                  botName: bot.name,
                                  botUsername: '',
                                  url: url,
                                  accountId: acctId,
                                  botId: bot.id,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    // §3.3: PlainShadow divider below My Profile/Bots block
                    // with 6px mainMenuSkip padding top and bottom.
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Container(
                        height: 1,
                        color: context.palette.shadowFg,
                      ),
                    ),
                    // §3.3: New Group row (§54.8: gated).
                    if (appState.showNewGroupInDrawer)
                    GestureDetector(
                      onSecondaryTapUp: (details) {
                        _showMyGroupsPopup(context, details.globalPosition, isGroup: true);
                      },
                      child: _MenuRow(
                        icon: Icons.group,
                        label: 'New Group',
                        onTap: () {
                          Navigator.of(context).pop();
                          showCreateGroupWizard(context);
                        },
                      ),
                    ),
                    // §3.3: New Channel row (§54.8: gated).
                    if (appState.showNewChannelInDrawer)
                    GestureDetector(
                      onSecondaryTapUp: (details) {
                        _showMyGroupsPopup(context, details.globalPosition, isGroup: false);
                      },
                      child: _MenuRow(
                        icon: Icons.campaign,
                        label: 'New Channel',
                        onTap: () {
                          Navigator.of(context).pop();
                          showCreateChannelWizard(context);
                        },
                      ),
                    ),
                    // §3.3: Contacts row (§54.8: gated).
                    if (appState.showContactsInDrawer)
                    _MenuRow(
                      icon: Icons.contacts,
                      label: 'Contacts',
                      onTap: () {
                        Navigator.of(context).pop();
                        showContactsBox(context);
                      },
                    ),
                    // §3.3: Calls row (§54.8: gated).
                    if (appState.showCallsInDrawer)
                    _MenuRow(
                      icon: Icons.phone,
                      label: 'Calls',
                      onTap: () {
                        Navigator.of(context).pop();
                        showCallsBox(context);
                      },
                    ),
                    // §3.3: Saved Messages row (§54.8: gated).
                    if (appState.showSavedMessagesInDrawer)
                    _MenuRow(
                      icon: Icons.bookmark,
                      label: 'Saved Messages',
                      onTap: () async {
                        Navigator.of(context).pop();
                        final chatState = context.read<ChatState>();
                        final engine = context.read<EngineService>();
                        final accountId = context.read<AppState>().activeAccount?.id ?? '';
                        final saved = chatState.chats
                            .where((c) => isSavedMessages(c))
                            .firstOrNull;
                        if (saved != null) {
                          chatState.openChat(saved);
                        } else {
                          await engine.openSavedMessages(accountId);
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
                          settingsPageRoute(
                            ChangeNotifierProvider.value(
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
                    // §3.4 + §25.15.10: Night Mode row, hideable via AyuGram prefs.
                    if (appState.showNightModeToggleInDrawer)
                    _MenuRow(
                      icon: Icons.nightlight_round,
                      label: appState.systemDarkModeEnabled
                          ? 'Night Mode (Auto)'
                          : 'Night Mode',
                      trailing: _InlineToggle(
                        value: isDark,
                        onChanged: (dark) {
                          if (appState.isEditingTheme) {
                            showConfirmBox(context,
                              text: "You can't change the theme while editing it.",
                              inform: true);
                            return;
                          }
                          if (appState.systemDarkModeEnabled) {
                            appState.setSystemDarkMode(false);
                          }
                          final target = dark
                              ? (appState.themeId == 'classic_day' ? 'night_green' : 'night')
                              : (appState.themeId == 'night_green' ? 'classic_day' : 'day_blue');
                          switchThemeWithCrossFade(context, target);
                        },
                      ),
                      onTap: () {
                        if (appState.isEditingTheme) {
                          showConfirmBox(context,
                            text: "You can't change the theme while editing it.",
                            inform: true);
                          return;
                        }
                        if (appState.systemDarkModeEnabled) {
                          appState.setSystemDarkMode(false);
                        }
                        final target = !isDark
                            ? (appState.themeId == 'classic_day' ? 'night_green' : 'night')
                            : (appState.themeId == 'night_green' ? 'classic_day' : 'day_blue');
                        switchThemeWithCrossFade(context, target);
                      },
                      onSecondaryTapDown: (details) {
                        _showNightModeContextMenu(
                          context, details.globalPosition, isDark, appState);
                      },
                      onLongPressWithPosition: (position) {
                        _showNightModeContextMenu(
                          context, position, isDark, appState);
                      },
                    ),
                    // §51.5: Ghost Mode quick toggle (gated, default shown).
                    if (appState.showGhostToggleInDrawer)
                    _MenuRow(
                      icon: Icons.auto_awesome,
                      iconWidget: const _AyuGhostIcon(),
                      label: 'Ghost Mode',
                      trailing: _InlineToggle(
                        value: appState.ghostModeEnabled,
                        onChanged: (v) {
                          final before = appState.ghostModeEnabled;
                          appState.setGhostModeEnabled(v);
                          if (before != appState.ghostModeEnabled) {
                            showTelegramToast(context, appState.ghostModeEnabled
                                ? 'Ghost Mode turned on'
                                : 'Ghost Mode turned off');
                          }
                        },
                      ),
                      onTap: () {
                        final before = appState.ghostModeEnabled;
                        appState.setGhostModeEnabled(!before);
                        if (before != appState.ghostModeEnabled) {
                          showTelegramToast(context, appState.ghostModeEnabled
                              ? 'Ghost Mode turned on'
                              : 'Ghost Mode turned off');
                        }
                      },
                    ),
                    // §51.5: LRead — one-shot "mark all chats read without receipts".
                    if (appState.showLReadToggleInDrawer)
                    _MenuRow(
                      icon: Icons.mark_email_read,
                      label: 'Mark All Read (Silent)',
                      onTap: () async {
                        final engine = context.read<EngineService>();
                        final chatState = context.read<ChatState>();
                        final accountId = appState.activeAccount?.id ?? '';
                        final origVal = appState.sendReadMessages;
                        appState.setSendReadMessages(false);
                        try {
                          await engine.markAllChatsRead(accountId);
                        } finally {
                          appState.setSendReadMessages(origVal);
                        }
                        if (context.mounted) {
                          showTelegramToast(context, 'All chats marked as read.');
                        }
                      },
                    ),
                    // §51.5: SRead — mark all stories as viewed (sends read receipts
                    // even when ghost mode suppresses them).
                    if (appState.showSReadToggleInDrawer)
                    _MenuRow(
                      icon: Icons.auto_stories,
                      label: 'Mark Stories as Viewed',
                      onTap: () async {
                        bool userConfirmed = false;
                        await showConfirmBox(
                          context,
                          title: 'Mark All Stories as Viewed',
                          text: 'This will mark all stories as viewed by sending read receipts. Continue?',
                          confirmText: 'Mark as Viewed',
                          onConfirm: () => userConfirmed = true,
                        );
                        if (!userConfirmed || !context.mounted) return;
                        final engine = context.read<EngineService>();
                        final accountId = appState.activeAccount?.id ?? '';
                        final origVal = appState.sendReadMessages;
                        appState.setSendReadMessages(true);
                        try {
                          await engine.markAllChatsRead(accountId);
                          await Future<void>.delayed(const Duration(milliseconds: 200));
                        } finally {
                          appState.setSendReadMessages(origVal);
                        }
                        if (context.mounted) {
                          showTelegramToast(context, 'All stories marked as viewed.');
                        }
                      },
                    ),
                    // §50.2–50.3: Streamer Mode toggle (gated, default hidden).
                    if (appState.showStreamerToggleInDrawer)
                    Tooltip(
                      message: Platform.isLinux
                          ? 'Streamer Mode has no effect on Linux — your compositor cannot hide windows from capture'
                          : 'Hide app from screen capture',
                      child: _MenuRow(
                        icon: Icons.videocam_off,
                        label: 'Streamer Mode',
                        trailing: _InlineToggle(
                          value: appState.streamerModeEnabled,
                          onChanged: (v) => appState.setStreamerModeEnabled(v),
                        ),
                        onTap: () => appState.setStreamerModeEnabled(!appState.streamerModeEnabled),
                      ),
                    ),
                    // §3.3: Archive row — shown when user has archived chats AND archiveInMainMenu is true.
                    if (context.watch<ChatState>().hasArchivedChats && appState.archiveInMainMenu)
                      GestureDetector(
                        onSecondaryTapUp: (details) {
                          _showArchiveContextMenu(context, details.globalPosition, appState);
                        },
                        child: _MenuRow(
                          icon: Icons.archive,
                          label: 'Archived Chats',
                          onTap: () {
                            Navigator.of(context).pop();
                            appState.requestShowArchive();
                          },
                        ),
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

  /// §3.4: Right-click context menu for Night Mode row — toggle system dark mode.
  void _showNightModeContextMenu(
      BuildContext context, Offset position, bool isDark, AppState appState) {
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'system_theme',
          icon: Icon(appState.systemDarkModeEnabled
              ? Icons.check_box
              : Icons.check_box_outline_blank),
          label: 'Use System Theme',
        ),
      ],
    ).then((value) {
      if (value == 'system_theme') {
        appState.setSystemDarkMode(!appState.systemDarkModeEnabled);
      }
    });
  }

  void _showArchiveContextMenu(
      BuildContext context, Offset position, AppState appState) {
    final chatState = context.read<ChatState>();
    final items = <TelegramMenuItem<String>>[
      const TelegramMenuItem(
        value: 'to_list',
        icon: Icon(Icons.list_alt),
        label: 'Show in chat list',
      ),
      TelegramMenuItem(
        value: 'mark_read',
        icon: const Icon(Icons.done_all),
        label: 'Mark all as read',
        isDisabled: !chatState.hasArchivedUnread,
      ),
      const TelegramMenuItem(value: '_sep', icon: Icon(Icons.more_horiz), label: '', isSeparator: true),
      const TelegramMenuItem(
        value: 'settings',
        icon: Icon(Icons.settings),
        label: 'Archive Settings',
      ),
      const TelegramMenuItem(
        value: 'how_it_works',
        icon: Icon(Icons.help_outline),
        label: 'How does the archive work?',
      ),
    ];
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'to_list':
          appState.setArchiveInMainMenu(false);
          showTelegramToast(context, 'Archive moved to chat list');
        case 'mark_read':
          chatState.markArchivedAsRead();
        case 'settings':
          final chatSt = context.read<ChatState>();
          final authSt = context.read<AuthState>();
          Navigator.of(context).pop();
          Navigator.of(context).push(
            settingsPageRoute(
              ChangeNotifierProvider.value(
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
        case 'how_it_works':
          _showArchiveHintDialog(context, appState);
      }
    });
  }

  void _showArchiveHintDialog(BuildContext context, AppState appState) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.archive, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This is your Archive',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'When you receive a new message, muted chats will remain in the Archive, while unmuted chats will be moved to Chats.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _ArchiveHintEntry(
                    icon: Icons.archive_outlined,
                    title: 'Archived Chats',
                    description: 'Move any chat into your Archive and back by swiping on it.',
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _ArchiveHintEntry(
                    icon: Icons.visibility_off_outlined,
                    title: 'Hiding Archive',
                    description: 'Hide the Archive from your Main screen by swiping on it.',
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _ArchiveHintEntry(
                    icon: Icons.auto_stories_outlined,
                    title: 'Stories',
                    description: 'Archive Stories from your contacts separately from chats with them.',
                    theme: theme,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Got it'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMyGroupsPopup(BuildContext context, Offset position, {required bool isGroup}) {
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id ?? '';
    final targetType = isGroup ? ChatType.group : ChatType.channel;
    final chats = chatState.chatsForAccount(accountId)
        .where((c) => c.type == targetType)
        .toList();
    final title = isGroup ? 'Groups' : 'Channels';
    Navigator.of(context).pop();
    showDialog(
      context: context,
      builder: (ctx) => _MyChatsDialog(
        title: title,
        chats: chats,
        onChatSelected: (chat) {
          Navigator.of(ctx).pop();
          chatState.openChat(chat);
        },
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context, AppState appState,
      {bool testMode = false}) {
    // Spec §3.2: enforce max accounts limit.
    if (!appState.canAddAccount) {
      showTelegramToast(context, 'Maximum account limit reached (${appState.maxAccountLimit})');
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
    final coverBg = context.palette.windowBgActive;

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
                  Builder(builder: (ctx) {
                    final aR = 24.0 * (ctx.watch<AppState>().avatarCorners / 23.0);
                    return Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(aR),
                        image: account?.avatarPath.isNotEmpty == true
                            ? DecorationImage(
                                image: FileImage(File(account!.avatarPath)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: account?.avatarPath.isNotEmpty != true
                          ? _initials(account?.displayName ?? '?', theme)
                          : null,
                    );
                  }),
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
            left: 0,
            right: 0,
            top: 84,
            bottom: 0,
            child: GestureDetector(
              onTap: accountCount >= 2 ? onToggle : null,
              behavior: HitTestBehavior.translucent,
              child: Padding(
                padding: const EdgeInsets.only(left: 26, right: 50),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            account?.displayName.isNotEmpty == true
                                ? account!.displayName
                                : _platformLabel(account?.platform ?? ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.palette.windowFgActive,
                            ),
                          ),
                        ),
                        if ((account?.isVerified == true || account?.isPremium == true) &&
                            !context.read<AppState>().hidePremiumStatuses) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              final as2 = context.read<AppState>();
                              final chatSt = context.read<ChatState>();
                              final authSt = context.read<AuthState>();
                              Navigator.of(context).pop();
                              Navigator.of(context).push(
                                settingsPageRoute(
                                  ChangeNotifierProvider.value(
                                    value: as2,
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
                            child: Icon(
                              account?.isPremium == true
                                  ? Icons.workspace_premium
                                  : Icons.verified,
                              size: 16,
                              color: context.palette.windowFgActive,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    _buildStatusLine(context, account),
                  ],
                ),
              ),
            ),
          ),
          if (accountCount >= 2)
            Positioned(
              right: 30,
              bottom: 30,
              child: GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: Builder(builder: (ctx) {
                  final as2 = ctx.watch<AppState>();
                  final cs = ctx.watch<ChatState>();
                  int otherUnread = 0;
                  bool allMuted = true;
                  if (!expanded) {
                    for (final a in as2.accounts) {
                      if (a.id != as2.activeAccountId) {
                        otherUnread += cs.unreadCountForAccount(a.id);
                        if (!cs.isAccountUnreadAllMuted(a.id)) {
                          allMuted = false;
                        }
                      }
                    }
                    if (allMuted) otherUnread = 0;
                  }
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (otherUnread > 0 && !expanded)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: ctx.palette.windowFgActive,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            otherUnread > 99 ? '99+' : '$otherUnread',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: ctx.palette.windowBgActive,
                            ),
                          ),
                        ),
                      SizedBox(
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
                                color: ctx.palette.windowFgActive.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          Builder(builder: (ctx) {
            final screenSize = MediaQuery.of(ctx).size;
            final tooSmall = screenSize.width < 380 || screenSize.height < 480;
            if (!tooSmall) return const SizedBox.shrink();
            return Positioned(
              right: 10,
              top: 10,
              child: GestureDetector(
                onTap: () {
                  ctx.read<AppState>().setUiScalePercent(100.0);
                  exit(0);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '100%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ctx.palette.windowFgActive,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusLine(BuildContext context, AccountInfo? account) {
    if (account == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        final appState = context.read<AppState>();
        final chatSt = context.read<ChatState>();
        final authSt = context.read<AuthState>();
        Navigator.of(context).pop();
        Navigator.of(context).push(
          settingsPageRoute(
            ChangeNotifierProvider.value(
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
      child: Text(
        'Uniclient Preferences',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: context.palette.windowFgActive,
          decoration: TextDecoration.underline,
          decorationColor: context.palette.windowFgActive.withValues(alpha: 0.7),
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
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: const [
        TelegramMenuItem(value: 'production', icon: Icon(Icons.person_add), label: 'Add Account'),
        TelegramMenuItem(value: 'test', icon: Icon(Icons.science), label: 'Add Test Account'),
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
            final keys = HardwareKeyboard.instance.logicalKeysPressed;
            final altHeld = keys.contains(LogicalKeyboardKey.altLeft) ||
                keys.contains(LogicalKeyboardKey.altRight);
            final shiftHeld = keys.contains(LogicalKeyboardKey.shiftLeft) ||
                keys.contains(LogicalKeyboardKey.shiftRight);
            if (altHeld && shiftHeld) {
              _showAddAccountContextMenu(
                  context, details.globalPosition, isDark);
            }
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
                        color: context.palette.windowBgActive, // windowBgActive
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
    final items = <TelegramMenuItem<String>>[];

    if (!isActive) {
      items.add(const TelegramMenuItem(value: 'new_window', icon: Icon(Icons.open_in_new), label: 'New Window'));
    }

    if (account.phone.isNotEmpty) {
      items.add(const TelegramMenuItem(value: 'copy_phone', icon: Icon(Icons.copy), label: 'Copy Phone'));
    }

    if (!isActive) {
      items.add(const TelegramMenuItem(value: 'activate', icon: Icon(Icons.check_circle_outline), label: 'Activate'));
    }

    items.add(const TelegramMenuItem(value: 'mark_read', icon: Icon(Icons.done_all), label: 'Mark as Read'));
    if (!isActive) {
      items.add(const TelegramMenuItem(value: 'log_out', icon: Icon(Icons.logout), label: 'Log Out', isAttention: true));
    }

    showTelegramMenu<String>(
      context: context,
      position: position,
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'new_window':
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
                          borderRadius: BorderRadius.circular(
                            18.0 * (context.watch<AppState>().avatarCorners / 23.0)),
                          border: Border.all(
                            color: context.palette.windowBgActive,
                            width: 2,
                          ),
                        )
                      : null,
                  padding: isActive
                      ? const EdgeInsets.all(2)
                      : EdgeInsets.zero,
                  child: Builder(builder: (ctx) {
                    final aR = 13.0 * (ctx.watch<AppState>().avatarCorners / 23.0);
                    final hasAvatar = account.avatarPath.isNotEmpty;
                    return Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(aR),
                        image: hasAvatar
                            ? DecorationImage(
                                image: FileImage(File(account.avatarPath)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: !hasAvatar
                          ? Icon(
                              _AccountList.platformIcons[account.platform] ?? Icons.chat,
                              size: 14,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                    );
                  }),
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
      bgColor = context.palette.windowBgActive;
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
class _MenuRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? iconWidget;
  final String? iconPath; // optional file-based icon (for menu bots)
  final GestureTapDownCallback? onSecondaryTapDown;
  final void Function(Offset globalPosition)? onLongPressWithPosition;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.iconWidget,
    this.iconPath,
    this.onSecondaryTapDown,
    this.onLongPressWithPosition,
  });

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  Offset _lastPointerDown = Offset.zero;

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

    return Listener(
      onPointerDown: (e) => _lastPointerDown = e.position,
      child: InkWell(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        onLongPress: widget.onLongPressWithPosition != null
            ? () => widget.onLongPressWithPosition!(_lastPointerDown)
            : null,
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
              if (widget.iconWidget != null)
                widget.iconWidget!
              else if (widget.iconPath != null && widget.iconPath!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    File(widget.iconPath!),
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(widget.icon, size: 24, color: iconColor),
                  ),
                )
              else
                Icon(widget.icon, size: 24, color: iconColor),
              // Gap from icon to label: 61 - 21 - 24 = 16px.
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.trailing != null) ...[
                // Spec §3.3: 19px toggle skip between label and trailing.
                const SizedBox(width: 19),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Spec §3: defaultMenuToggle — itemToggleShift 11px, 150ms.
/// Track 25×14 pill, 14px thumb ⇒ shift = 25−14 = 11px.
class _InlineToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _InlineToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final onColor = context.palette.windowBgActive;
    final offColor = context.palette.windowSubTextFg;
    final thumbColor = context.palette.windowBg;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        width: 25,
        height: 14,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: value ? onColor : offColor,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: thumbColor,
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

/// §3.6: Compose version string with modifiers per spec.
/// Base: "Version {APP_VERSION}" + stage (" alpha N" / " beta") + " DEBUG" in debug builds.
String _versionString() {
  const version = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
  const stage = String.fromEnvironment('APP_STAGE', defaultValue: 'alpha');
  const stageNum = String.fromEnvironment('APP_STAGE_NUM', defaultValue: '');
  final buf = StringBuffer('Version $version');
  if (stage.isNotEmpty) {
    buf.write(' $stage');
    if (stageNum.isNotEmpty) {
      buf.write(' $stageNum');
    }
  }
  if (kDebugMode) {
    buf.write(' DEBUG');
  }
  return buf.toString();
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
                TelegramTooltip(
                  message: 'Build date: ${const String.fromEnvironment('BUILD_DATE', defaultValue: 'dev')}',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _openUrl(
                          'https://github.com/DarkReaperBoy/uniclient/releases'),
                      child: Text(
                        _versionString(),
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
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
            Text(_versionString()),
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
                    color: context.palette.windowBgActive,
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

class _AyuGhostIcon extends StatelessWidget {
  const _AyuGhostIcon();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final eyeColor = isDark
        ? const Color(0xFF17212b)
        : const Color(0xFFFFFFFF);
    return CustomPaint(
      size: const Size(24, 24),
      painter: _GhostIconPainter(bodyColor, eyeColor),
    );
  }
}

class _GhostIconPainter extends CustomPainter {
  final Color bodyColor;
  final Color eyeColor;
  _GhostIconPainter(this.bodyColor, this.eyeColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(w * 0.5, h * 0.08);
    path.cubicTo(w * 0.22, h * 0.08, w * 0.12, h * 0.28, w * 0.12, h * 0.42);
    path.lineTo(w * 0.12, h * 0.88);
    path.lineTo(w * 0.24, h * 0.78);
    path.lineTo(w * 0.38, h * 0.92);
    path.lineTo(w * 0.5, h * 0.78);
    path.lineTo(w * 0.62, h * 0.92);
    path.lineTo(w * 0.76, h * 0.78);
    path.lineTo(w * 0.88, h * 0.88);
    path.lineTo(w * 0.88, h * 0.42);
    path.cubicTo(w * 0.88, h * 0.28, w * 0.78, h * 0.08, w * 0.5, h * 0.08);
    path.close();
    canvas.drawPath(path, paint);

    final eyePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.36, h * 0.38), w * 0.07, eyePaint);
    canvas.drawCircle(Offset(w * 0.64, h * 0.38), w * 0.07, eyePaint);
  }

  @override
  bool shouldRepaint(_GhostIconPainter old) =>
      old.bodyColor != bodyColor || old.eyeColor != eyeColor;
}

class _MyChatsDialog extends StatelessWidget {
  final String title;
  final List<ChatInfo> chats;
  final ValueChanged<ChatInfo> onChatSelected;

  const _MyChatsDialog({
    required this.title,
    required this.chats,
    required this.onChatSelected,
  });

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  static String _initials(String title) {
    final t = title.trim();
    if (t.isEmpty) return '?';
    final words = t.split(RegExp(r'\s+'));
    if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return t[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: palette.boxBg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.boxTitleFg,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: palette.boxTitleCloseFg, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (chats.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 22),
                child: Text(
                  'You have no ${title.toLowerCase()} yet.',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: chats.length,
                  itemBuilder: (ctx, i) {
                    final chat = chats[i];
                    final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
                    final avatarColor = palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
                    final initials = _initials(chat.title);
                    final countLabel = chat.type == ChatType.channel
                        ? (chat.memberCount == 1 ? 'subscriber' : 'subscribers')
                        : (chat.memberCount == 1 ? 'member' : 'members');
                    final subtitle = chat.memberCount > 0
                        ? '${chat.memberCount} $countLabel'
                        : '';
                    return InkWell(
                      onTap: () => onChatSelected(chat),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                        child: Row(
                          children: [
                            _buildAvatar(chat, avatarColor, initials),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chat.title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (subtitle.isNotEmpty)
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ChatInfo chat, Color color, String initials) {
    const size = 42.0;
    if (chat.avatarPath.isNotEmpty) {
      final file = File(chat.avatarPath);
      return ClipOval(
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(color, initials, size),
        ),
      );
    }
    return _fallbackAvatar(color, initials, size);
  }

  Widget _fallbackAvatar(Color color, String initials, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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

class _ArchiveHintEntry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final ThemeData theme;

  const _ArchiveHintEntry({
    required this.icon,
    required this.title,
    required this.description,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: theme.colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(description, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
