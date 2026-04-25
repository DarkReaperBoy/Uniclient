import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import 'advanced_settings_screen.dart';
import 'confirm_box.dart';
import 'my_profile_page.dart';

/// Settings page (§14). Opened from hamburger drawer "Settings" row.
/// Scrollable panel with profile header at top, then settings navigation rows.
/// Matches AyuGram Desktop's Settings page layout.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = context.watch<AppState>();
    final account = appState.activeAccount;

    // Colors matching spec §14.
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final dividerColor = isDark
        ? const Color(0xFF101921)
        : const Color(0xFFF1F1F1);
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        actions: [
          // §14.1: Three-dot overflow menu.
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: subtextColor),
            color: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onSelected: (value) {
              switch (value) {
                case 'add_account':
                  _showAddAccountDialog(context, appState);
                  break;
                case 'edit_profile':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: appState,
                        child: const MyProfilePage(),
                      ),
                    ),
                  );
                  break;
                case 'log_out':
                  _confirmLogOut(context, appState, account);
                  break;
              }
            },
            itemBuilder: (ctx) => [
              if (appState.canAddAccount)
                PopupMenuItem(
                  value: 'add_account',
                  child: Row(
                    children: [
                      Icon(Icons.person_add, size: 20, color: subtextColor),
                      const SizedBox(width: 12),
                      Text('Add Account', style: TextStyle(color: textColor)),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'edit_profile',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20, color: subtextColor),
                    const SizedBox(width: 12),
                    Text('Edit Profile', style: TextStyle(color: textColor)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'log_out',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20,
                        color: isDark
                            ? const Color(0xFFEC3942)
                            : const Color(0xFFD14E4E)),
                    const SizedBox(width: 12),
                    Text('Log Out',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFEC3942)
                              : const Color(0xFFD14E4E),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // §14.2: Profile header / cover area.
          _ProfileHeader(account: account, isDark: isDark),
          // Divider below profile.
          Container(height: 8, color: dividerColor),
          // §14.3: Navigation buttons.
          // My Account (§14.3 item 2) → navigates to Edit Profile (§14.5).
          _SettingsRow(
            icon: Icons.person,
            iconBg: const Color(0xFF5E97F6),
            label: 'My Account',
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: appState,
                    child: const MyProfilePage(),
                  ),
                ),
              );
            },
          ),
          // Notifications and Sounds (§14.3 item 3).
          _SettingsRow(
            icon: Icons.notifications,
            iconBg: const Color(0xFFEB4D3D),
            label: 'Notifications and Sounds',
            isDark: isDark,
            onTap: () {},
          ),
          // Privacy and Security (§14.3 item 4).
          _SettingsRow(
            icon: Icons.lock,
            iconBg: const Color(0xFF9B59B6),
            label: 'Privacy and Security',
            isDark: isDark,
            onTap: () {},
          ),
          // Chat Settings (§14.3 item 5).
          _SettingsRow(
            icon: Icons.chat_bubble,
            iconBg: const Color(0xFF50C878),
            label: 'Chat Settings',
            isDark: isDark,
            onTap: () {},
          ),
          // Folders (§14.3 item 6).
          _SettingsRow(
            icon: Icons.folder,
            iconBg: const Color(0xFF2196F3),
            label: 'Folders',
            isDark: isDark,
            onTap: () {},
          ),
          // Advanced (§14.3 item 7).
          _SettingsRow(
            icon: Icons.tune,
            iconBg: const Color(0xFF607D8B),
            label: 'Advanced',
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdvancedSettingsScreen(),
                ),
              );
            },
          ),
          // Divider between groups (§14.3).
          Container(height: 8, color: dividerColor),
          // Devices (§14.3 item 8).
          _SettingsRow(
            icon: Icons.devices,
            iconBg: const Color(0xFFFFA726),
            label: 'Devices',
            isDark: isDark,
            onTap: () {},
          ),
          // Divider.
          Container(height: 8, color: dividerColor),
          // Language (§14.3 item 10).
          _SettingsRow(
            icon: Icons.translate,
            iconBg: const Color(0xFF9C27B0),
            label: 'Language',
            isDark: isDark,
            trailing: Text(
              'English',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF5288C1)
                    : const Color(0xFF40A7E3),
              ),
            ),
            onTap: () {},
          ),
          // §14.4: Interface scale.
          Container(height: 8, color: dividerColor),
          _InterfaceScaleSection(isDark: isDark, appState: appState),
          // Bottom padding.
          const SizedBox(height: 32),
        ],
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
                Navigator.of(context).pop();
                final id = appState.addAccount(p.$1);
                authState.startAuth(id);
              },
            ),
        ],
      ),
    );
  }

  void _confirmLogOut(
      BuildContext context, AppState appState, AccountInfo? account) {
    showConfirmBox(
      context,
      text: 'Are you sure you want to log out?',
      confirmText: 'Log Out',
      isDestructive: true,
      onConfirm: () {
        Navigator.of(context).pop();
        if (account != null) {
          appState.removeAccount(account.id);
        }
      },
    );
  }
}

/// §14.2: Profile header with avatar, name, phone, username.
/// Total height: settingsPhotoTop(8) + photo(88) + settingsPhotoBottom(16) = 112px.
class _ProfileHeader extends StatelessWidget {
  final AccountInfo? account;
  final bool isDark;

  const _ProfileHeader({required this.account, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final phoneColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final usernameColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    final displayName = account?.displayName.isNotEmpty == true
        ? account!.displayName
        : 'Unknown';
    final phone = account?.phone ?? '';
    final username = account?.username ?? '';

    return Padding(
      padding: const EdgeInsets.only(
        left: 22,
        top: 8,
        right: 22,
        bottom: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // §14.2: Avatar — 88px UserpicButton at (22, 8).
          CircleAvatar(
            radius: 44,
            backgroundColor: theme.colorScheme.primary,
            backgroundImage: account?.avatarPath.isNotEmpty == true
                ? FileImage(File(account!.avatarPath))
                : null,
            child: account?.avatarPath.isNotEmpty != true
                ? Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 22),
          // §14.2: Name, phone, username stacked.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                // Display name.
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: nameColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (account?.isPremium == true) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.workspace_premium,
                        size: 18,
                        color: isDark
                            ? const Color(0xFF5288C1)
                            : const Color(0xFF40A7E3),
                      ),
                    ],
                  ],
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    style: TextStyle(fontSize: 14, color: phoneColor),
                  ),
                ],
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    style: TextStyle(fontSize: 14, color: usernameColor),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// §14.3: Settings navigation row with rounded-square icon background.
/// settingsButton style: 60px left padding, 22px right, 10px vertical.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingsRow({
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);

    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // §14.3: Icon in rounded-square background (settingsIconRadius: 6px).
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// §14.4: Interface scale section with toggle and slider.
class _InterfaceScaleSection extends StatelessWidget {
  final bool isDark;
  final AppState appState;

  const _InterfaceScaleSection({
    required this.isDark,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final accentColor = isDark
        ? const Color(0xFF5288C1)
        : const Color(0xFF40A7E3);

    return Column(
      children: [
        // "Default interface scale" toggle.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.visibility, size: 22, color: textColor.withValues(alpha: 0.5)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Default interface scale',
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
              Switch(
                value: true, // Default scale on
                onChanged: (v) {},
                activeColor: accentColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
