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
            // Account list (collapsible) — SlideWrap toggled by
            // mainMenuAccountsShownValue (spec §3.2). 6px mainMenuSkip spacers.
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCirc,
                alignment: Alignment.topCenter,
                child: accountsExpanded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 6),
                          _AccountList(
                            accounts: appState.accounts,
                            activeAccountId: appState.activeAccountId,
                            onSelect: (id) {
                              appState.setActiveAccountId(id);
                              context.read<ChatState>().switchAccount(id);
                              appState.setMainMenuAccountsShown(false);
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
              ],
            ),
          ),
          // Status line at left 26, top 103 (spec §3).
          // Font: defaultFlatLabel 13px body, color: windowSubTextFg.
          // Content: phone when present, else "Set Emoji Status" link.
          Positioned(
            left: 26,
            top: 103,
            right: 50,
            child: Text(
              _statusText(account),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
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
                      curve: Curves.easeOutCirc,
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

  static String _statusText(AccountInfo? account) {
    if (account == null) return '';
    if (account.phone.isNotEmpty) return account.phone;
    return 'Set Emoji Status';
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
class _AccountList extends StatelessWidget {
  final List<AccountInfo> accounts;
  final String activeAccountId;
  final void Function(String id) onSelect;
  final VoidCallback onAddAccount;

  const _AccountList({
    required this.accounts,
    required this.activeAccountId,
    required this.onSelect,
    required this.onAddAccount,
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final account in accounts)
              _AccountRow(
                account: account,
                isActive: account.id == activeAccountId,
                labelColor: labelColor,
                hoverBg: hoverBg,
                onTap: () => onSelect(account.id),
              ),
            // Add Account button (separate checklist item — keeping simple for now).
            InkWell(
              onTap: onAddAccount,
              hoverColor: hoverBg,
              splashColor: hoverBg.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.only(top: 11, bottom: 9, right: 20),
                child: Row(
                  children: [
                    const SizedBox(width: 23),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(
                        child: Icon(
                          Icons.add,
                          size: 20,
                          color: isDark
                              ? const Color(0xFF5288C1)
                              : const Color(0xFF40A7E3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        'Add Account',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF5288C1)
                              : const Color(0xFF40A7E3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single account row matching Telegram Desktop SettingsButton style.
/// Spec §3.2: padding margins(61, 11, 20, 9), semiboldTextStyle 13px,
/// iconLeft 23px, avatar 26px photo + 5px padding each side = 36x36.
class _AccountRow extends StatelessWidget {
  final AccountInfo account;
  final bool isActive;
  final Color labelColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _AccountRow({
    required this.account,
    required this.isActive,
    required this.labelColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
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
            SizedBox(
              width: 36,
              height: 36,
              child: Center(
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
            if (isActive)
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
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
