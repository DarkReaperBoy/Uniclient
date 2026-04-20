import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';

/// Hamburger menu drawer. Spec §3: 274px wide, 134px cover.
/// Shows active account profile at top, collapsible account switcher,
/// then menu items.
class HamburgerDrawer extends StatefulWidget {
  const HamburgerDrawer({super.key});

  @override
  State<HamburgerDrawer> createState() => _HamburgerDrawerState();
}

class _HamburgerDrawerState extends State<HamburgerDrawer> {
  bool _accountsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();
    final isDark = theme.brightness == Brightness.dark;

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
              expanded: _accountsExpanded,
              onToggle: () => setState(() => _accountsExpanded = !_accountsExpanded),
            ),
            // 1px PlainShadow at bottom of cover (spec §3: shadowFg).
            Container(
              height: 1,
              color: isDark
                  ? const Color(0x5604080e)
                  : const Color(0x18000000),
            ),
            // Account list (collapsible) — slideWrapDuration animation (spec §1).
            // 6px spacers above/below per spec §3 (mainMenuSkip).
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCirc,
                alignment: Alignment.topCenter,
                child: _accountsExpanded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 6),
                          _AccountList(
                            accounts: appState.accounts,
                            activeAccountId: appState.activeAccountId,
                            connStates: appState.connStates,
                            onSelect: (id) {
                              appState.setActiveAccountId(id);
                              context.read<ChatState>().switchAccount(id);
                              setState(() => _accountsExpanded = false);
                            },
                            onAddAccount: () =>
                                _showAddAccountDialog(context, appState),
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
            // Menu items. Placeholder entries (My Profile, New Group, New
            // Channel, Contacts, Calls, Saved Messages, Settings) previously
            // rendered with empty onTap callbacks were removed per CLAUDE.md's
            // ZERO placeholders rule. They will be re-added as their backing
            // screens/flows are implemented (tracked in todolist.md).
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _NightModeToggle(
                    isDark: isDark,
                    onChanged: (dark) {
                      appState.updateTheme(dark ? 'dark' : 'light');
                    },
                  ),
                  if (Platform.isLinux)
                    _SystemFrameToggle(
                      enabled: appState.nativeWindowFrame,
                      onChanged: (value) {
                        appState.setNativeWindowFrame(value);
                      },
                    ),
                ],
              ),
            ),
            // Version footer.
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'UniClient v0.1.0',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context, AppState appState) {
    final authState = context.read<AuthState>();
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add Account'),
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

  const _ProfileCover({
    required this.account,
    required this.connState,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connColor = switch (connState) {
      ConnState.connected => const Color(0xFF3BA55C),
      ConnState.connecting => const Color(0xFFFAA61A),
      ConnState.unstable => const Color(0xFFFAA61A),
      ConnState.disconnected => Colors.grey,
    };

    return Container(
      height: 134,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.15),
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
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
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
                    color: account?.isPremium == true
                        ? const Color(0xFF7B68EE)
                        : const Color(0xFF1DA1F2),
                  ),
                ],
              ],
            ),
          ),
          // Status line at left 26, top 103 (spec §3).
          Positioned(
            left: 26,
            top: 103,
            right: 50,
            child: Text(
              _platformLabel(account?.platform ?? ''),
              style: theme.textTheme.bodySmall,
            ),
          ),
          // Account-list toggle chevron (top-right).
          Positioned(
            right: 16,
            top: 20,
            child: IconButton(
              icon: AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCirc,
                child: const Icon(Icons.expand_more, size: 22),
              ),
              onPressed: onToggle,
            ),
          ),
        ],
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

/// Expandable account list for switching accounts.
class _AccountList extends StatelessWidget {
  final List<AccountInfo> accounts;
  final String activeAccountId;
  final Map<String, ConnState> connStates;
  final void Function(String id) onSelect;
  final VoidCallback onAddAccount;

  const _AccountList({
    required this.accounts,
    required this.activeAccountId,
    required this.connStates,
    required this.onSelect,
    required this.onAddAccount,
  });

  static const _platformIcons = <String, IconData>{
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connColor = (ConnState s) => switch (s) {
      ConnState.connected => const Color(0xFF3BA55C),
      ConnState.connecting => const Color(0xFFFAA61A),
      ConnState.unstable => const Color(0xFFFAA61A),
      ConnState.disconnected => Colors.grey,
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final account in accounts)
              ListTile(
                dense: true,
                selected: account.id == activeAccountId,
                selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                      child: Icon(
                        _platformIcons[account.platform] ?? Icons.chat,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: connColor(connStates[account.id] ?? ConnState.disconnected),
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.surface, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(
                  account.displayName.isNotEmpty ? account.displayName : account.id,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _ProfileCover._platformLabel(account.platform),
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
                trailing: account.id == activeAccountId
                    ? Icon(Icons.check, size: 16, color: theme.colorScheme.primary)
                    : null,
                onTap: () => onSelect(account.id),
              ),
            ListTile(
              dense: true,
              leading: Icon(Icons.add, color: theme.colorScheme.primary),
              title: Text('Add Account',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  )),
              onTap: onAddAccount,
            ),
          ],
        ),
      ),
    );
  }
}

/// Night mode inline toggle.
class _NightModeToggle extends StatelessWidget {
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _NightModeToggle({required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        isDark ? Icons.dark_mode : Icons.light_mode,
        size: 22,
      ),
      title: const Text('Night Mode'),
      dense: true,
      trailing: Switch(
        value: isDark,
        onChanged: onChanged,
      ),
    );
  }
}

/// System window frame toggle (Linux only).
/// Spec §1: _nativeWindowFrame defaults to false. When enabled, the custom
/// client-side titlebar is hidden and GTK shows native window decorations.
class _SystemFrameToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SystemFrameToggle({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.desktop_windows, size: 22),
      title: const Text('System Window Frame'),
      dense: true,
      trailing: Switch(
        value: enabled,
        onChanged: onChanged,
      ),
    );
  }
}
