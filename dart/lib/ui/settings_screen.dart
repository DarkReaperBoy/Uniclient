import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import 'advanced_settings_screen.dart';
import 'chat_settings_screen.dart';
import 'confirm_box.dart';
import 'my_profile_page.dart';
import 'notifications_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'settings_style.dart';

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
                  final chatSt = context.read<ChatState>();
                  final authSt = context.read<AuthState>();
                  Navigator.of(context).push(
                    settingsPageRoute(
                      ChangeNotifierProvider.value(
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
          // §14.3: skip+divider+skip between profile header and nav buttons.
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          // §14.3 Item 1: AyuGram Preferences (standalone group).
          _SettingsRow(
            icon: Icons.star,
            iconBg: const Color(0xFF6B72D5),
            label: 'AyuGram Preferences',
            isDark: isDark,
            onTap: () {},
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          // §14.3 Items 2-6: My Account / Notifications / Privacy / Chat Settings / Folders.
          _SettingsRow(
            icon: Icons.person,
            iconBg: const Color(0xFF5E97F6),
            label: 'My Account',
            isDark: isDark,
            onTap: () {
              final chatSt = context.read<ChatState>();
              final authSt = context.read<AuthState>();
              Navigator.of(context).push(
                settingsPageRoute(
                  ChangeNotifierProvider.value(
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
          _SettingsRow(
            icon: Icons.notifications,
            iconBg: const Color(0xFFEB4D3D),
            label: 'Notifications and Sounds',
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                settingsPageRoute(
                  ChangeNotifierProvider.value(
                    value: appState,
                    child: const NotificationsSettingsScreen(),
                  ),
                ),
              );
            },
          ),
          _SettingsRow(
            icon: Icons.lock,
            iconBg: const Color(0xFF9B59B6),
            label: 'Privacy and Security',
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                settingsPageRoute(
                  ChangeNotifierProvider.value(
                    value: appState,
                    child: const PrivacySettingsScreen(),
                  ),
                ),
              );
            },
          ),
          _SettingsRow(
            icon: Icons.chat_bubble,
            iconBg: const Color(0xFF50C878),
            label: 'Chat Settings',
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                settingsPageRoute(
                  ChangeNotifierProvider.value(
                    value: appState,
                    child: const ChatSettingsScreen(),
                  ),
                ),
              );
            },
          ),
          _SettingsRow(
            icon: Icons.folder,
            iconBg: const Color(0xFF2196F3),
            label: 'Folders',
            isDark: isDark,
            onTap: () {},
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          // §14.3 Items 7-8: Advanced / Devices.
          _SettingsRow(
            icon: Icons.tune,
            iconBg: const Color(0xFF607D8B),
            label: 'Advanced',
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                settingsPageRoute(const AdvancedSettingsScreen()),
              );
            },
          ),
          _SettingsRow(
            icon: Icons.devices,
            iconBg: const Color(0xFFFFA726),
            label: 'Devices',
            isDark: isDark,
            onTap: () {},
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          // §14.3 Items 9-10: Power Saving / Language.
          _SettingsRow(
            icon: Icons.battery_charging_full,
            iconBg: const Color(0xFF43A047),
            label: 'Power Saving',
            isDark: isDark,
            onTap: () => showDialog(
              context: context,
              builder: (_) => ChangeNotifierProvider.value(
                value: context.read<AppState>(),
                child: const PowerSavingBox(),
              ),
            ),
          ),
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
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          _InterfaceScaleSection(isDark: isDark, appState: appState),
          // §14.8: skip+divider+skip before Premium section.
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          // §14.8.1: Premium section.
          _PremiumRow(
            icon: Icons.workspace_premium,
            label: 'Telegram Premium',
            isDark: isDark,
            onTap: () {},
          ),
          _PremiumRow(
            icon: Icons.star_border,
            label: 'Telegram Stars',
            isDark: isDark,
            trailing: Text(
              '0',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF6C7883)
                    : const Color(0xFF999999),
              ),
            ),
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.diamond_outlined,
            iconBg: const Color(0xFF3A3A5C),
            label: 'Telegram Business',
            isDark: isDark,
            onTap: () {},
          ),
          _PremiumRow(
            icon: Icons.card_giftcard,
            label: 'Send a Gift',
            isDark: isDark,
            showNewBadge: true,
            onTap: () {},
          ),
          // §14.8: skip+divider+skip before Help section.
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          // §14.8.2: Help section.
          _SettingsRow(
            icon: Icons.help_outline,
            iconBg: const Color(0xFF40A7E3),
            label: 'Telegram FAQ',
            isDark: isDark,
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.info_outline,
            iconBg: const Color(0xFF40A7E3),
            label: 'Telegram Features',
            isDark: isDark,
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.chat_outlined,
            iconBg: const Color(0xFF40A7E3),
            label: 'Ask a Question',
            isDark: isDark,
            onTap: () => _showAskQuestionConfirm(context),
          ),
          // About-label (§14.8.2): aligned with row title column at 59px left inset.
          Padding(
            padding: const EdgeInsets.fromLTRB(59, 0, 46, 6),
            child: Text(
              'Ask a volunteer in the Telegram support community for help.',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? const Color(0xFF6C7883)
                    : const Color(0xFF999999),
              ),
            ),
          ),
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

  void _showAskQuestionConfirm(BuildContext context) {
    showConfirmBox(
      context,
      title: 'Telegram Support',
      text: 'You can ask a question in the Telegram support community. They are volunteers and may take some time to respond.\n\nPlease take a look at the Telegram FAQ first: it has important troubleshooting tips and answers to most questions.',
      confirmText: 'Ask a Volunteer',
      cancelText: 'Cancel',
      onConfirm: () {},
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

class _ProfileHeader extends StatefulWidget {
  final AccountInfo? account;
  final bool isDark;

  const _ProfileHeader({required this.account, required this.isDark});

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  bool _avatarHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = widget.isDark;
    final account = widget.account;
    final nameColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final phoneColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final usernameColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final accentColor = isDark
        ? const Color(0xFF5288C1)
        : const Color(0xFF40A7E3);

    final displayName = account?.displayName.isNotEmpty == true
        ? account!.displayName
        : 'Unknown';
    final phone = account?.phone ?? '';
    final username = account?.username ?? '';
    final hasUsername = username.isNotEmpty;
    final hasQr = hasUsername;

    return SizedBox(
      height: 112,
      child: Padding(
        padding: const EdgeInsets.only(left: 22, top: 8, right: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar — 88px, with hover camera overlay.
            MouseRegion(
              onEnter: (_) => setState(() => _avatarHovered = true),
              onExit: (_) => setState(() => _avatarHovered = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showAvatarMenu(context),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: theme.colorScheme.primary,
                        backgroundImage:
                            account?.avatarPath.isNotEmpty == true
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
                      if (_avatarHovered)
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0x66000000),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Gap between avatar and text column (settingsNameLeft=112 - settingsPhotoLeft=22 - photoSize=88 = 2).
            const SizedBox(width: 2),
            // Text column: name, phone/ID, username.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name at top:4 (spec settingsNameTop=12 minus settingsPhotoTop=8 = 4).
                  const SizedBox(height: 4),
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
                        Icon(Icons.workspace_premium, size: 18, color: accentColor),
                      ],
                    ],
                  ),
                  // Phone at settingsPhoneTop(37) - settingsNameTop(12) - lineHeight ≈ 5px gap.
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    GestureDetector(
                      onSecondaryTapUp: (details) =>
                          _showCopyMenu(context, details.globalPosition, phone, 'Copy Phone'),
                      child: Text(
                        phone,
                        style: TextStyle(fontSize: 14, color: phoneColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  // Username at settingsUsernameTop(58) - settingsPhoneTop(37) - lineHeight ≈ 1px gap.
                  const SizedBox(height: 1),
                  GestureDetector(
                    onTap: () => _onUsernameTap(context, username),
                    child: Text(
                      hasUsername ? '@$username' : 'Add',
                      style: TextStyle(
                        fontSize: 14,
                        color: hasUsername ? usernameColor : accentColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // QR code button — right side, vertically centered in the 88px avatar area.
            if (hasQr)
              SizedBox(
                width: 48,
                height: 88,
                child: Center(
                  child: IconButton(
                    icon: Icon(Icons.qr_code, size: 24, color: accentColor),
                    tooltip: 'QR Code',
                    onPressed: () => _showQrDialog(context, username),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAvatarMenu(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(const Offset(22, 96));

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy, offset.dx + 200, offset.dy),
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'upload',
          child: Row(
            children: [
              Icon(Icons.photo, size: 20, color: subtextColor),
              const SizedBox(width: 12),
              Text('Upload Photo', style: TextStyle(color: textColor)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'emoji',
          child: Row(
            children: [
              Icon(Icons.emoji_emotions, size: 20, color: subtextColor),
              const SizedBox(width: 12),
              Text('Choose Emoji', style: TextStyle(color: textColor)),
            ],
          ),
        ),
        if (widget.account?.avatarPath.isNotEmpty == true)
          PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.delete, size: 20, color: isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E)),
                const SizedBox(width: 12),
                Text('Remove Photo', style: TextStyle(color: isDark ? const Color(0xFFEC3942) : const Color(0xFFD14E4E))),
              ],
            ),
          ),
      ],
    );
  }

  void _showCopyMenu(BuildContext context, Offset position, String text, String label) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Text(label, style: TextStyle(color: textColor)),
          onTap: () => Clipboard.setData(ClipboardData(text: text)),
        ),
      ],
    );
  }

  void _onUsernameTap(BuildContext context, String username) {
    if (username.isEmpty) return;
    final link = 'https://t.me/$username';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Link copied: $link'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showQrDialog(BuildContext context, String username) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('QR Code', style: TextStyle(color: textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(Icons.qr_code_2, size: 160, color: accentColor),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              'https://t.me/$username',
              style: TextStyle(fontSize: 14, color: accentColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'https://t.me/$username'));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text('Copy Link', style: TextStyle(color: accentColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: TextStyle(color: accentColor)),
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
      child: SizedBox(
        height: SettingsStyle.rowHeight,
        child: Row(
          children: [
            const SizedBox(width: SettingsStyle.iconLeft),
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              child: Icon(icon, size: SettingsStyle.iconInner, color: Colors.white),
            ),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: SettingsStyle.buttonFontSize,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
            const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }
}

/// §14.8.1: Premium row with gradient icon background (purple→blue star glyph style).
class _PremiumRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showNewBadge;

  const _PremiumRow({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.trailing,
    this.showNewBadge = false,
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
      child: SizedBox(
        height: SettingsStyle.rowHeight,
        child: Row(
          children: [
            const SizedBox(width: SettingsStyle.iconLeft),
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6B93FF), Color(0xFF976FFF), Color(0xFFE46ACE)],
                ),
              ),
              child: Icon(icon, size: SettingsStyle.iconInner, color: Colors.white),
            ),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: SettingsStyle.buttonFontSize,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showNewBadge)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6B93FF), Color(0xFF976FFF)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            if (trailing != null) trailing!,
            const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }
}

/// §14.4: Interface scale section with toggle and slider.
class _InterfaceScaleSection extends StatefulWidget {
  final bool isDark;
  final AppState appState;

  const _InterfaceScaleSection({
    required this.isDark,
    required this.appState,
  });

  @override
  State<_InterfaceScaleSection> createState() => _InterfaceScaleSectionState();
}

class _InterfaceScaleSectionState extends State<_InterfaceScaleSection> {
  bool _useDefault = true;
  double _scalePercent = 100;
  double _committedScale = 100;
  bool _isDragging = false;

  static const double _kMin = 100;
  static const double _kMax = 300;
  static const double _kStep = 5;

  double _snap(double v) => (v / _kStep).round() * _kStep;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final accentColor = isDark
        ? const Color(0xFF5288C1)
        : const Color(0xFF40A7E3);
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);
    final activeTextColor = isDark
        ? const Color(0xFF5288C1)
        : const Color(0xFF40A7E3);

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _useDefault = !_useDefault),
          hoverColor: hoverBg,
          splashColor: hoverBg.withValues(alpha: 0.5),
          child: Padding(
            padding: SettingsStyle.buttonPadding,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Use Default Scale',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                SizedBox(
                  height: 20,
                  child: Switch(
                    value: _useDefault,
                    onChanged: (v) => setState(() => _useDefault = v),
                    activeColor: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _useDefault
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(60, 7, 22, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7.5,
                            ),
                            activeTrackColor: accentColor,
                            inactiveTrackColor: textColor.withValues(alpha: 0.15),
                            thumbColor: accentColor,
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            overlayColor: accentColor.withValues(alpha: 0.12),
                          ),
                          child: Slider(
                            value: _scalePercent,
                            min: _kMin,
                            max: _kMax,
                            divisions: ((_kMax - _kMin) / _kStep).round(),
                            onChangeStart: (_) =>
                                setState(() => _isDragging = true),
                            onChanged: (v) =>
                                setState(() => _scalePercent = _snap(v)),
                            onChangeEnd: (v) {
                              final snapped = _snap(v);
                              setState(() {
                                _isDragging = false;
                                _scalePercent = snapped;
                              });
                              if (snapped != _committedScale) {
                                _showRestartDialog(snapped);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${_scalePercent.round()}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            color: activeTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (_isDragging && !_useDefault)
          Padding(
            padding: const EdgeInsets.fromLTRB(60, 0, 22, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2B3A4A)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'Preview: ${_scalePercent.round()}%',
                style: TextStyle(
                  fontSize: 12 * (_scalePercent / 100),
                  color: textColor,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showRestartDialog(double newScale) {
    showConfirmBox(
      context,
      text: 'Some settings will be applied after restarting.',
      title: 'Restart Required',
      confirmText: 'Restart Now',
      cancelText: 'Cancel',
      onConfirm: () {
        setState(() => _committedScale = newScale);
      },
      onCancel: () {
        setState(() => _scalePercent = _committedScale);
      },
    );
  }
}
