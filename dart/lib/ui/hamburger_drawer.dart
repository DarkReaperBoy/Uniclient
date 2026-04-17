import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';

/// Hamburger menu drawer. Spec §3: 274px wide, 134px cover.
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
            // Profile cover area (134px).
            _ProfileCover(
              accounts: appState.accounts,
              expanded: _accountsExpanded,
              onToggle: () => setState(() => _accountsExpanded = !_accountsExpanded),
            ),
            // Account list (collapsible).
            if (_accountsExpanded)
              _AccountList(
                accounts: appState.accounts,
                onAddAccount: () => _showAddAccountDialog(context, appState),
              ),
            const Divider(height: 1),
            // Menu items.
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _MenuItem(Icons.person_outline, 'My Profile', () {}),
                  _MenuItem(Icons.group_add_outlined, 'New Group', () {}),
                  _MenuItem(Icons.campaign_outlined, 'New Channel', () {}),
                  _MenuItem(Icons.contacts_outlined, 'Contacts', () {}),
                  _MenuItem(Icons.phone_outlined, 'Calls', () {}),
                  _MenuItem(Icons.bookmark_border, 'Saved Messages', () {}),
                  _MenuItem(Icons.settings_outlined, 'Settings', () {}),
                  // Night mode toggle.
                  _NightModeToggle(
                    isDark: isDark,
                    onChanged: (dark) {
                      appState.updateTheme(dark ? 'dark' : 'light');
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

/// Profile area at top of drawer (134px).
class _ProfileCover extends StatelessWidget {
  final List<AccountInfo> accounts;
  final bool expanded;
  final VoidCallback onToggle;

  const _ProfileCover({
    required this.accounts,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = accounts.isNotEmpty ? accounts.first : null;

    return Container(
      height: 134,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar.
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary,
                child: primary?.avatarPath.isNotEmpty == true
                    ? ClipOval(
                        child: Image.network(primary!.avatarPath,
                            width: 56, height: 56, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _initials(primary.displayName, theme)),
                      )
                    : _initials(primary?.displayName ?? '?', theme),
              ),
              const Spacer(),
              // Toggle arrow (when 2+ accounts).
              if (accounts.length > 1)
                IconButton(
                  icon: AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, size: 22),
                  ),
                  onPressed: onToggle,
                ),
            ],
          ),
          const Spacer(),
          // Name.
          Text(
            primary?.displayName ?? 'No Account',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          // Platform.
          Text(
            primary?.platform ?? '',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _initials(String name, ThemeData theme) {
    final init = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Text(init, style: const TextStyle(
        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600));
  }
}

/// Expandable account list.
class _AccountList extends StatelessWidget {
  final List<AccountInfo> accounts;
  final VoidCallback onAddAccount;

  const _AccountList({required this.accounts, required this.onAddAccount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final account in accounts)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.3),
              child: Text(
                account.displayName.isNotEmpty ? account.displayName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            title: Text(account.displayName, style: theme.textTheme.bodyMedium),
            subtitle: Text(account.platform, style: theme.textTheme.bodySmall),
            onTap: () {
              // Switch to this account.
              context.read<AppState>().setActiveAccountId(account.id);
              Navigator.of(context).pop();
            },
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
    );
  }
}

/// Single menu item in the drawer.
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(label),
      dense: true,
      onTap: onTap,
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
