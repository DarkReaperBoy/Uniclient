import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import 'advanced_settings_screen.dart';
import 'language_box.dart';
import 'chat_settings_screen.dart';
import 'confirm_box.dart';
import 'folders_settings_screen.dart';
import 'active_sessions_screen.dart';
import 'ayugram_settings_screen.dart';
import 'my_profile_page.dart';
import 'notifications_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'settings_style.dart';
import 'telegram_toast.dart';
import '../theme/telegram_palette.dart';

void _openUrl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

const _kLanguageNames = <String, String>{
  'af': 'Afrikaans', 'sq': 'Shqip', 'am': 'አማርኛ', 'ar': 'العربية',
  'hy': 'Հայերեն', 'az': 'Azərbaycan', 'eu': 'Euskara', 'be': 'Беларуская',
  'bn': 'বাংলা', 'bs': 'Bosanski', 'bg': 'Български', 'ca': 'Català',
  'zh': '中文', 'hr': 'Hrvatski', 'cs': 'Čeština', 'da': 'Dansk',
  'nl': 'Nederlands', 'en': 'English', 'et': 'Eesti', 'fi': 'Suomi',
  'fr': 'Français', 'ka': 'ქართული', 'de': 'Deutsch', 'el': 'Ελληνικά',
  'he': 'עברית', 'hi': 'हिन्दी', 'hu': 'Magyar', 'is': 'Íslenska',
  'id': 'Indonesia', 'it': 'Italiano', 'ja': '日本語', 'ko': '한국어',
  'lv': 'Latviešu', 'lt': 'Lietuvių', 'mk': 'Македонски', 'ms': 'Melayu',
  'no': 'Norsk', 'fa': 'فارسی', 'pl': 'Polski', 'pt': 'Português',
  'ro': 'Română', 'ru': 'Русский', 'sr': 'Српски', 'sk': 'Slovenčina',
  'sl': 'Slovenščina', 'es': 'Español', 'sw': 'Kiswahili', 'sv': 'Svenska',
  'th': 'ไทย', 'tr': 'Türkçe', 'uk': 'Українська', 'ur': 'اردو',
  'uz': 'Oʻzbek', 'vi': 'Tiếng Việt',
};

/// Settings page (§14). Opened from hamburger drawer "Settings" row.
/// Scrollable panel with profile header at top, then settings navigation rows.
/// Matches AyuGram Desktop's Settings page layout.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _premiumPossible = false;
  bool _premiumCanBuy = false;
  int _starsBalance = 0;
  bool _dialogFiltersEnabled = false;
  bool _premiumLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPremiumData();
  }

  Future<void> _loadPremiumData() async {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null || account.platform != 'telegram') return;
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final results = await Future.wait([
      engine.getPremiumStatus(accountId),
      engine.getStarsBalance(accountId),
      engine.getDialogFiltersEnabled(accountId),
    ]);

    if (!mounted) return;
    final premiumStatus = results[0] as ({bool premiumPossible, bool premiumCanBuy});
    setState(() {
      _premiumPossible = premiumStatus.premiumPossible;
      _premiumCanBuy = premiumStatus.premiumCanBuy;
      _starsBalance = results[1] as int;
      _dialogFiltersEnabled = results[2] as bool;
      _premiumLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = context.watch<AppState>();
    final account = appState.activeAccount;
    final chatState = context.watch<ChatState>();

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
                        color: context.palette.attentionButtonFg),
                    const SizedBox(width: 12),
                    Text('Log Out',
                        style: TextStyle(
                          color: context.palette.attentionButtonFg,
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
            onTap: () {
              Navigator.of(context).push(
                settingsPageRoute(
                  ChangeNotifierProvider.value(
                    value: appState,
                    child: const AyuGramSettingsScreen(),
                  ),
                ),
              );
            },
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
          if (chatState.hasFolders || _dialogFiltersEnabled)
            _SettingsRow(
              icon: Icons.folder,
              iconBg: const Color(0xFF2196F3),
              label: 'Folders',
              isDark: isDark,
              onTap: () {
                Navigator.of(context).push(
                  settingsPageRoute(const FoldersSettingsScreen()),
                );
              },
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
            icon: Icons.volume_up,
            iconBg: const Color(0xFFFFA726),
            label: 'Devices',
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                settingsPageRoute(const _DevicesScreen()),
              );
            },
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
              _kLanguageNames[appState.selectedLanguageCode] ?? appState.selectedLanguageCode.toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                color: context.palette.windowBgActive,
              ),
            ),
            onTap: () => showDialog(
              context: context,
              builder: (_) => MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: context.read<AppState>()),
                  Provider.value(value: context.read<EngineService>()),
                ],
                child: const LanguageBox(),
              ),
            ),
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
          if (_premiumPossible || (!_premiumLoaded && account?.platform == 'telegram')) ...[
            _PremiumRow(
              icon: Icons.workspace_premium,
              label: 'Telegram Premium',
              isDark: isDark,
              onTap: () {
                Navigator.of(context).push(
                  settingsPageRoute(_PremiumInfoScreen(
                    accountId: appState.activeAccountId,
                    isPremium: account?.isPremium ?? false,
                  )),
                );
              },
            ),
            _PremiumRow(
              icon: Icons.star_border,
              label: 'Telegram Stars',
              isDark: isDark,
              trailing: _starsBalance > 0
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '$_starsBalance',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.palette.windowBgActive,
                        ),
                      ),
                    )
                  : null,
              onTap: () {
                Navigator.of(context).push(
                  settingsPageRoute(_CreditsScreen(
                    accountId: appState.activeAccountId,
                    balance: _starsBalance,
                  )),
                );
              },
            ),
            _SettingsRow(
              icon: Icons.diamond_outlined,
              iconBg: const Color(0xFF3A3A5C),
              label: 'Telegram Business',
              isDark: isDark,
              onTap: () {
                Navigator.of(context).push(
                  settingsPageRoute(_BusinessScreen(
                    accountId: appState.activeAccountId,
                  )),
                );
              },
            ),
            if (_premiumCanBuy || !_premiumLoaded)
              _PremiumRow(
                icon: Icons.card_giftcard,
                label: 'Send a Gift',
                isDark: isDark,
                showNewBadge: true,
                onTap: () {
                  Navigator.of(context).push(
                    settingsPageRoute(_GiftCatalogScreen(
                      accountId: appState.activeAccountId,
                    )),
                  );
                },
              ),
          ],
          // §14.8: skip+divider+skip before Help section.
          const SizedBox(height: 7),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 7),
          // §14.8.2: Help section.
          _SettingsRow(
            icon: Icons.help_outline,
            iconBg: context.palette.windowBgActive,
            label: 'Telegram FAQ',
            isDark: isDark,
            onTap: () => _openUrl('https://telegram.org/faq'),
          ),
          _SettingsRow(
            icon: Icons.info_outline,
            iconBg: context.palette.windowBgActive,
            label: 'Telegram Features',
            isDark: isDark,
            onTap: () => _openUrl('https://telegram.org/blog'),
          ),
          _SettingsRow(
            icon: Icons.chat_outlined,
            iconBg: context.palette.windowBgActive,
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
      onConfirm: () {
        _openUrl('tg://support');
      },
    );
  }

  void _confirmLogOut(
      BuildContext context, AppState appState, AccountInfo? account) {
    showConfirmBox(
      context,
      text: 'Are you sure you want to log out?\n\nNote: this will end all your Secret Chats.',
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
    final accentColor = context.palette.windowBgActive;

    final displayName = account?.displayName.isNotEmpty == true
        ? account!.displayName
        : 'Unknown';
    final phone = account?.phone ?? '';
    final username = account?.username ?? '';
    final hasUsername = username.isNotEmpty;
    final hasQr = hasUsername;

    return SizedBox(
      height: 96,
      child: Padding(
        padding: const EdgeInsets.only(left: 22, top: 8, right: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MouseRegion(
              onEnter: (_) => setState(() => _avatarHovered = true),
              onExit: (_) => setState(() => _avatarHovered = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showAvatarMenu(context),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 36,
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
            const SizedBox(width: 18),
            // Text column: name, phone/ID, username.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name at top:4 (spec settingsNameTop=12 minus settingsPhotoTop=8 = 4).
                  const SizedBox(height: 4),
                  GestureDetector(
                    onSecondaryTapUp: (details) =>
                        _showCopyMenu(context, details.globalPosition, displayName, 'Copy Full Name'),
                    child: Row(
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
                          GestureDetector(
                            onTap: () => _showEmojiStatusPanel(context),
                            child: Icon(Icons.workspace_premium, size: 18, color: accentColor),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (account != null && account.selfUserId.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    GestureDetector(
                      onSecondaryTapUp: (details) =>
                          _showCopyMenu(context, details.globalPosition, account.selfUserId, 'Copy ID'),
                      child: Text(
                        'ID: ${account.selfUserId}',
                        style: TextStyle(fontSize: 14, color: phoneColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else if (phone.isNotEmpty) ...[
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
                    onSecondaryTapUp: hasUsername
                        ? (details) => _showUsernameContextMenu(
                            context, details.globalPosition, username, account)
                        : null,
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
            if (hasQr)
              SizedBox(
                width: 48,
                height: 72,
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

  void _showAvatarMenu(BuildContext context) async {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(const Offset(22, 80));

    final result = await showMenu<String>(
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
                Icon(Icons.delete, size: 20, color: context.palette.attentionButtonFg),
                const SizedBox(width: 12),
                Text('Remove Photo', style: TextStyle(color: context.palette.attentionButtonFg)),
              ],
            ),
          ),
      ],
    );
    if (result == null || !context.mounted) return;
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId.isEmpty) return;
    switch (result) {
      case 'upload':
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (picked != null && picked.files.isNotEmpty) {
          final path = picked.files.first.path;
          if (path != null) {
            await engine.uploadProfilePhoto(accountId, path);
            if (context.mounted) showTelegramToast(context, 'Photo uploaded');
          }
        }
      case 'emoji':
        if (context.mounted) _showEmojiAvatarPicker(context);
      case 'remove':
        await engine.deleteProfilePhotos(accountId);
        if (context.mounted) showTelegramToast(context, 'Photo removed');
    }
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

  void _showUsernameContextMenu(
      BuildContext context, Offset position, String username, AccountInfo? account) {
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
          value: 'copy_id',
          child: Text('Copy ID', style: TextStyle(color: textColor)),
          onTap: () {
            final id = account?.id ?? '';
            Clipboard.setData(ClipboardData(text: id));
            showTelegramToast(context, 'ID copied');
          },
        ),
        PopupMenuItem(
          value: 'copy_username',
          child: Text('Copy Username', style: TextStyle(color: textColor)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: '@$username'));
            showTelegramToast(context, 'Username copied');
          },
        ),
      ],
    );
  }

  void _onUsernameTap(BuildContext context, String username) {
    if (username.isEmpty) return;
    final link = 'https://t.me/$username';
    Clipboard.setData(ClipboardData(text: link));
    showTelegramToast(context, 'Link copied: $link');
  }

  void _showEmojiAvatarPicker(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;

    List<StickerInfoItem> stickerItems = [];
    bool loading = true;
    bool loadTriggered = false;

    Future<List<StickerInfoItem>> loadEmojis() async {
      try {
        final sets = await engine.getInstalledEmojiSets(accountId);
        final items = <StickerInfoItem>[];
        final seenIds = <String>{};
        for (final s in sets) {
          for (final sticker in s.stickers) {
            if (seenIds.add(sticker.fileId) && sticker.fileId.isNotEmpty) {
              items.add(sticker);
            }
          }
        }
        if (items.isNotEmpty) return items.take(64).toList();
      } catch (_) {}
      return [];
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (!loadTriggered) {
            loadTriggered = true;
            loadEmojis().then((items) {
              if (ctx.mounted) {
                setDialogState(() {
                  stickerItems = items;
                  loading = false;
                });
              }
            });
          }
          return Dialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose Emoji Avatar',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (stickerItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'No custom emoji installed',
                            style: TextStyle(color: textColor.withValues(alpha: 0.5)),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: GridView.builder(
                          shrinkWrap: true,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemCount: stickerItems.length,
                          itemBuilder: (ctx, i) {
                            final s = stickerItems[i];
                            final hasThumb = s.thumbB64.isNotEmpty;
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                engine.uploadProfilePhoto(accountId, '', documentId: s.fileId);
                                showTelegramToast(context, 'Emoji avatar set');
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: hasThumb
                                    ? Image.memory(
                                        base64Decode(s.thumbB64),
                                        fit: BoxFit.contain,
                                      )
                                    : Center(
                                        child: Text(
                                          s.emoji,
                                          style: const TextStyle(fontSize: 28),
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('Cancel', style: TextStyle(color: accentColor)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEmojiStatusPanel(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;

    const durations = <int, String>{
      3600: '1 hour',
      7200: '2 hours',
      28800: '8 hours',
      86400: '1 day',
      259200: '3 days',
      604800: '1 week',
      0: 'No expiration',
    };

    int selectedDuration = 0;
    List<StickerInfoItem> stickerItems = [];
    bool loading = true;
    bool loadTriggered = false;

    Future<List<StickerInfoItem>> loadEmojiStickers() async {
      try {
        final sets = await engine.getInstalledEmojiSets(accountId);
        final items = <StickerInfoItem>[];
        final seenIds = <String>{};
        for (final s in sets) {
          for (final sticker in s.stickers) {
            if (seenIds.add(sticker.fileId) && sticker.fileId.isNotEmpty) {
              items.add(sticker);
            }
          }
        }
        if (items.isNotEmpty) return items.take(64).toList();
      } catch (_) {}
      return [];
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (!loadTriggered) {
            loadTriggered = true;
            loadEmojiStickers().then((items) {
              if (ctx.mounted) {
                setDialogState(() {
                  stickerItems = items;
                  loading = false;
                });
              }
            });
          }
          return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340, maxHeight: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set Emoji Status',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (stickerItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'No custom emoji packs installed.',
                          style: TextStyle(fontSize: 14, color: subtextColor),
                        ),
                      ),
                    )
                  else
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: stickerItems.length,
                      itemBuilder: (_, i) {
                        final item = stickerItems[i];
                        return InkWell(
                          onTap: () {
                            engine.setEmojiStatus(accountId, item.fileId, selectedDuration);
                            Navigator.of(ctx).pop();
                            showTelegramToast(context, 'Emoji status set');
                          },
                          hoverColor: hoverBg,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: _buildStickerThumb(item),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Expires after:', style: TextStyle(fontSize: 13, color: subtextColor)),
                  const SizedBox(height: 6),
                  DropdownButton<int>(
                    value: selectedDuration,
                    isExpanded: true,
                    dropdownColor: bgColor,
                    style: TextStyle(fontSize: 14, color: textColor),
                    underline: Container(height: 1, color: subtextColor.withValues(alpha: 0.3)),
                    items: durations.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedDuration = v ?? 0),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          engine.clearEmojiStatus(accountId);
                          Navigator.of(ctx).pop();
                          showTelegramToast(context, 'Status cleared');
                        },
                        child: Text('Clear Status', style: TextStyle(color: subtextColor)),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('Cancel', style: TextStyle(color: accentColor)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          );
        },
      ),
    );
  }

  Widget _buildStickerThumb(StickerInfoItem item) {
    if (item.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumb(item.thumbB64);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _emojiTextFallback(item.emoji),
        );
      } catch (_) {
        return _emojiTextFallback(item.emoji);
      }
    }
    return _emojiTextFallback(item.emoji);
  }

  Widget _emojiTextFallback(String emoji) {
    return Center(
      child: Text(
        emoji.isNotEmpty ? emoji : '?',
        style: const TextStyle(fontSize: 22),
      ),
    );
  }

  static Uint8List _decodeStrippedThumb(String b64) {
    final stripped = base64Decode(b64);
    if (stripped.length < 3 || stripped[0] != 0x01) {
      return stripped;
    }
    final w = stripped[1];
    final h = stripped[2];
    final header = _jpegHeader(w, h);
    const footer = _jpegFooter;
    final buf = Uint8List(header.length + stripped.length - 3 + footer.length);
    buf.setAll(0, header);
    buf.setAll(header.length, stripped.sublist(3));
    buf.setAll(header.length + stripped.length - 3, footer);
    return buf;
  }

  static Uint8List _jpegHeader(int w, int h) {
    final tmpl = Uint8List.fromList(const [
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x28, 0x1C, 0x1E, 0x23, 0x1E, 0x19, 0x28, 0x23, 0x21, 0x23, 0x2D,
      0x2B, 0x28, 0x30, 0x3C, 0x64, 0x41, 0x3C, 0x37, 0x37, 0x3C, 0x7B, 0x58,
      0x5D, 0x49, 0x64, 0x91, 0x80, 0x99, 0x96, 0x8F, 0x80, 0x8C, 0x8A, 0xA0,
      0xB4, 0xE6, 0xC3, 0xA0, 0xAA, 0xDA, 0xAD, 0x8A, 0x8C, 0xC8, 0xFF, 0xCB,
      0xDA, 0xEE, 0xF5, 0xFF, 0xFF, 0xFF, 0x9B, 0xC1, 0xFF, 0xFF, 0xFF, 0xFA,
      0xFF, 0xE6, 0xFD, 0xFF, 0xF8, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x2B, 0x2D,
      0x2D, 0x3C, 0x35, 0x3C, 0x76, 0x41, 0x41, 0x76, 0xF8, 0xA5, 0x8C, 0xA5,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x00, 0x00, 0x00,
      0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4,
      0x00, 0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
      0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10,
      0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04,
      0x00, 0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
      0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32,
      0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
      0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A,
      0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
      0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55,
      0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
      0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85,
      0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
      0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2,
      0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
      0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8,
      0xD9, 0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
      0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xC4,
      0x00, 0x1F, 0x01, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
      0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x11,
      0x00, 0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07, 0x05, 0x04, 0x04,
      0x00, 0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21,
      0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81,
      0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0,
      0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17,
      0x18, 0x19, 0x1A, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38,
      0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54,
      0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
      0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83,
      0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96,
      0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9,
      0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3,
      0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6,
      0xD7, 0xD8, 0xD9, 0xDA, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9,
      0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA,
      0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00,
    ]);
    tmpl[164] = h;
    tmpl[166] = w;
    return tmpl;
  }

  static const _jpegFooter = [0xFF, 0xD9];

  void _showQrDialog(BuildContext context, String username) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;
    final link = 'https://t.me/$username';

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
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 184,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: accentColor,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: accentColor,
                ),
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              link,
              style: TextStyle(fontSize: 14, color: accentColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.of(ctx).pop();
              showTelegramToast(context, 'Link copied');
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
            Icon(Icons.chevron_right, size: 20, color: isDark
                ? const Color(0xFF6C7883) : const Color(0xFFBBBBBB)),
            const SizedBox(width: 3),
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

class _InterfaceScaleSectionState extends State<_InterfaceScaleSection>
    with SingleTickerProviderStateMixin {
  late bool _useDefault;
  late double _scalePercent;
  late double _committedScale;

  static const double _kMin = 50;
  static const double _kStep = 5;
  double _kMax = 300;

  OverlayEntry? _previewOverlay;
  late AnimationController _previewAnim;
  final GlobalKey _sliderKey = GlobalKey();

  double _snap(double v) => (v / _kStep).round() * _kStep;

  @override
  void initState() {
    super.initState();
    final saved = widget.appState.uiScalePercent;
    _committedScale = saved;
    _scalePercent = saved;
    _useDefault = (saved - 100.0).abs() < 0.01;
    _previewAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _previewOverlay?.remove();
    _previewOverlay = null;
    _previewAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    _kMax = _snap((300 / dpr).clamp(100, 400));
  }

  void _showPreviewOverlay() {
    _removePreviewOverlay(animate: false);
    _previewOverlay = OverlayEntry(builder: (_) => _buildFloatingPreview());
    Overlay.of(context).insert(_previewOverlay!);
    _previewAnim.forward();
  }

  void _updatePreviewOverlay() {
    _previewOverlay?.markNeedsBuild();
  }

  void _removePreviewOverlay({bool animate = true}) {
    if (_previewOverlay == null) return;
    if (animate) {
      final entry = _previewOverlay;
      _previewOverlay = null;
      _previewAnim.reverse().then((_) {
        entry?.remove();
      });
    } else {
      _previewOverlay?.remove();
      _previewOverlay = null;
    }
  }

  Widget _buildFloatingPreview() {
    final isDark = widget.isDark;
    final bubbleBg = isDark ? const Color(0xFF182533) : const Color(0xFFEFFFDE);
    final incomingBg = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final nameFg = isDark ? const Color(0xFF569CD6) : const Color(0xFF3A8EC8);
    final textFg = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final timeFg = isDark ? const Color(0xFF6C7883) : const Color(0xFF8E8E93);
    final replyBar = isDark ? const Color(0xFF569CD6) : const Color(0xFF3A8EC8);
    final replyBg = isDark ? const Color(0xFF1A2D3E) : const Color(0xFFE8F0F8);
    final shadowCol = isDark ? const Color(0xFF0E1621) : const Color(0xFFB0B0B0);
    final scaleFactor = _scalePercent / 100;

    RenderBox? sliderBox;
    Offset sliderPos = Offset.zero;
    if (_sliderKey.currentContext != null) {
      sliderBox = _sliderKey.currentContext!.findRenderObject() as RenderBox?;
      if (sliderBox != null && sliderBox.hasSize) {
        sliderPos = sliderBox.localToGlobal(Offset.zero);
      }
    }
    final previewWidth = 280.0;
    final centerX = sliderPos.dx + (sliderBox?.size.width ?? 200) / 2;
    final left = (centerX - previewWidth / 2).clamp(8.0, double.infinity);
    final top = (sliderPos.dy - 16).clamp(40.0, double.infinity);

    return AnimatedBuilder(
      animation: _previewAnim,
      builder: (context, child) {
        final t = _previewAnim.value;
        final scale = 0.3 + t * 0.7;
        return Positioned(
          left: left,
          bottom: MediaQuery.of(context).size.height - top,
          child: IgnorePointer(
            child: Opacity(
              opacity: t,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            ),
          ),
        );
      },
      child: Container(
        width: previewWidth,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0E1621) : const Color(0xFFCDD8E1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: shadowCol.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Transform.scale(
          scale: scaleFactor,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: previewWidth / scaleFactor - 24 / scaleFactor,
            child: _ScalePreviewContent(
              isDark: isDark,
              bubbleBg: bubbleBg,
              incomingBg: incomingBg,
              nameFg: nameFg,
              textFg: textFg,
              timeFg: timeFg,
              replyBar: replyBar,
              replyBg: replyBg,
              maxBubbleWidth: (previewWidth / scaleFactor - 24 / scaleFactor) * 0.75,
              appState: widget.appState,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);
    final activeTextColor = context.palette.windowBgActive;

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _useDefault = !_useDefault;
              if (_useDefault && (_scalePercent - 100.0).abs() > 0.01) {
                _scalePercent = 100;
                _committedScale = 100;
                widget.appState.setUiScalePercent(100);
              }
            });
          },
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
                    onChanged: (v) {
                      setState(() {
                        _useDefault = v;
                        if (v && (_scalePercent - 100.0).abs() > 0.01) {
                          _scalePercent = 100;
                          _committedScale = 100;
                          widget.appState.setUiScalePercent(100);
                        }
                      });
                    },
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
                  key: _sliderKey,
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
                            onChangeStart: (_) {
                              _showPreviewOverlay();
                            },
                            onChanged: (v) {
                              setState(() => _scalePercent = _snap(v));
                              _updatePreviewOverlay();
                            },
                            onChangeEnd: (v) {
                              final snapped = _snap(v);
                              setState(() {
                                _scalePercent = snapped;
                              });
                              _removePreviewOverlay();
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
      ],
    );
  }

  void _showRestartDialog(double newScale) {
    showConfirmBox(
      context,
      text: 'Some settings will be applied after restarting the application.',
      title: 'Restart Required',
      confirmText: 'Restart Now',
      cancelText: 'Cancel',
      onConfirm: () {
        setState(() => _committedScale = newScale);
        widget.appState.setUiScalePercent(newScale);
        final exe = Platform.resolvedExecutable;
        Process.start(exe, [], mode: ProcessStartMode.detached).then((_) {
          exit(0);
        });
      },
      onCancel: () {
        setState(() => _scalePercent = _committedScale);
      },
    );
  }
}

class _ScalePreviewContent extends StatelessWidget {
  final bool isDark;
  final Color bubbleBg;
  final Color incomingBg;
  final Color nameFg;
  final Color textFg;
  final Color timeFg;
  final Color replyBar;
  final Color replyBg;
  final double maxBubbleWidth;
  final AppState appState;

  const _ScalePreviewContent({
    required this.isDark,
    required this.bubbleBg,
    required this.incomingBg,
    required this.nameFg,
    required this.textFg,
    required this.timeFg,
    required this.replyBar,
    required this.replyBg,
    required this.maxBubbleWidth,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    final account = appState.activeAccount;
    final userName = account?.displayName ?? 'User';
    final initial = userName.isNotEmpty ? userName.characters.first.toUpperCase() : 'U';
    final now = TimeOfDay.now();
    final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final prevMin = (now.minute - 1).clamp(0, 59);
    final prevTimeStr = '${now.hour}:${prevMin.toString().padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: nameFg.withValues(alpha: 0.7),
              ),
              child: Center(
                child: Text(initial,
                  style: const TextStyle(
                    fontSize: 15, color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  color: incomingBg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: nameFg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      decoration: BoxDecoration(
                        color: replyBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border(
                          left: BorderSide(color: replyBar, width: 2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: nameFg,
                            ),
                          ),
                          Text('How does this look?',
                            style: TextStyle(
                              fontSize: 12,
                              color: textFg.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This is how messages will look at this scale',
                      style: TextStyle(fontSize: 13, color: textFg),
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(prevTimeStr,
                        style: TextStyle(fontSize: 11, color: timeFg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            decoration: BoxDecoration(
              color: bubbleBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(2),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Looks great! Thanks for checking.',
                  style: TextStyle(fontSize: 13, color: textFg),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(timeStr,
                      style: TextStyle(fontSize: 11, color: timeFg),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.done_all, size: 14, color: timeFg),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DevicesScreen extends StatelessWidget {
  const _DevicesScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: textColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Devices', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
          bottom: TabBar(
            labelColor: accentColor,
            unselectedLabelColor: textColor.withValues(alpha: 0.5),
            indicatorColor: accentColor,
            tabs: const [
              Tab(text: 'Sessions'),
              Tab(text: 'Calls'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ActiveSessionsScreen(embedded: true),
            _CallsSettingsTab(),
          ],
        ),
      ),
    );
  }
}

class _CallsSettingsTab extends StatelessWidget {
  const _CallsSettingsTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final accentColor = context.palette.windowBgActive;

    return ListView(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text('Audio', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
        ),
        const SizedBox(height: 8),
        _DeviceSettingRow(
          label: 'Output device',
          value: 'Default',
          isDark: isDark,
          onTap: () {},
        ),
        _DeviceSettingRow(
          label: 'Input device',
          value: 'Default',
          isDark: isDark,
          onTap: () {},
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text('Calls', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          child: Text(
            'Use peer-to-peer with',
            style: TextStyle(fontSize: 14, color: textColor),
          ),
        ),
        for (final option in ['Everyone', 'My contacts', 'Nobody'])
          InkWell(
            onTap: () {},
            hoverColor: hoverBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    option == 'My contacts' ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20,
                    color: option == 'My contacts' ? accentColor : subtextColor,
                  ),
                  const SizedBox(width: 12),
                  Text(option, style: TextStyle(fontSize: 14, color: textColor)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DeviceSettingRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final VoidCallback onTap;

  const _DeviceSettingRow({
    required this.label,
    required this.value,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 14, color: textColor)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 13, color: subtextColor)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: subtextColor),
          ],
        ),
      ),
    );
  }
}

class _PremiumInfoScreen extends StatefulWidget {
  final String accountId;
  final bool isPremium;

  const _PremiumInfoScreen({required this.accountId, required this.isPremium});

  @override
  State<_PremiumInfoScreen> createState() => _PremiumInfoScreenState();
}

class _PremiumInfoScreenState extends State<_PremiumInfoScreen> {
  List<String> _features = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPremiumInfo();
  }

  Future<void> _loadPremiumInfo() async {
    _features = [
      'Increased limits for channels, folders and pins',
      'Faster downloads and no speed limits',
      'Voice-to-text conversion for voice messages',
      'No ads in public channels',
      'Unique reactions and stickers',
      'Custom emoji and profile colors',
      'Premium badges and animated profile photos',
      'Real-time translation of messages',
    ];
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

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
        title: Text('Telegram Premium', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6B93FF), Color(0xFF976FFF), Color(0xFFE46ACE)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.workspace_premium, size: 48, color: Colors.white),
                      const SizedBox(height: 8),
                      Text(
                        widget.isPremium ? 'You have Premium' : 'Telegram Premium',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isPremium ? 'Enjoy all premium features' : 'Unlock exclusive features',
                        style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Features', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: accentColor)),
                const SizedBox(height: 8),
                for (final f in _features)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.star, size: 20, color: const Color(0xFF976FFF)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(f, style: TextStyle(fontSize: 14, color: textColor))),
                      ],
                    ),
                  ),
                if (!widget.isPremium) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openUrl('https://t.me/premium'),
                      child: const Text('Subscribe to Premium', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _CreditsScreen extends StatefulWidget {
  final String accountId;
  final int balance;

  const _CreditsScreen({required this.accountId, required this.balance});

  @override
  State<_CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<_CreditsScreen> {
  late int _balance;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _refreshBalance();
  }

  Future<void> _refreshBalance() async {
    final engine = context.read<EngineService>();
    final balance = await engine.getStarsBalance(widget.accountId);
    if (mounted) setState(() => _balance = balance);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

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
        title: Text('Telegram Stars', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.star, size: 48, color: const Color(0xFFFFB743)),
                const SizedBox(height: 8),
                Text(
                  '$_balance',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: textColor),
                ),
                const SizedBox(height: 4),
                Text('Stars Balance', style: TextStyle(fontSize: 14, color: subtextColor)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _openUrl('https://t.me/stars'),
              child: const Text('Buy Stars', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
          Text('About Telegram Stars', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: accentColor)),
          const SizedBox(height: 8),
          Text(
            'Use Telegram Stars to buy digital goods and services in bots and mini apps, unlock paid content from channels, send paid reactions, and more.',
            style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _BusinessScreen extends StatelessWidget {
  final String accountId;

  const _BusinessScreen({required this.accountId});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

    final features = [
      ('Business Hours', 'Set working hours so clients know when to reach you', Icons.schedule),
      ('Business Location', 'Display your business address on your profile', Icons.location_on),
      ('Greeting Messages', 'Send automatic greeting messages to new clients', Icons.waving_hand),
      ('Away Messages', 'Automatically reply when you are unavailable', Icons.flight),
      ('Quick Replies', 'Set up shortcuts for frequently used messages', Icons.flash_on),
      ('Chatbot Integration', 'Connect a Telegram bot to manage conversations', Icons.smart_toy),
      ('Custom Start Page', 'Customize your chat intro with an image and text', Icons.view_agenda),
    ];

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
        title: Text('Telegram Business', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3A3A5C), Color(0xFF5C5C8A)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.diamond_outlined, size: 48, color: Colors.white),
                const SizedBox(height: 8),
                const Text('Telegram Business', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Tools for businesses on Telegram', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final (name, desc, icon) in features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 24, color: accentColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                        const SizedBox(height: 2),
                        Text(desc, style: TextStyle(fontSize: 13, color: subtextColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _openUrl('https://t.me/business'),
              child: const Text('Learn More', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftCatalogScreen extends StatefulWidget {
  final String accountId;

  const _GiftCatalogScreen({required this.accountId});

  @override
  State<_GiftCatalogScreen> createState() => _GiftCatalogScreenState();
}

class _GiftCatalogScreenState extends State<_GiftCatalogScreen> {
  List<StarGiftItem> _gifts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    final engine = context.read<EngineService>();
    final result = await engine.getStarGifts(widget.accountId);
    if (mounted) {
      setState(() {
        _gifts = result?.gifts ?? [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

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
        title: Text('Send a Gift', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _gifts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.card_giftcard, size: 48, color: subtextColor),
                      const SizedBox(height: 12),
                      Text('No gifts available', style: TextStyle(fontSize: 16, color: subtextColor)),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _gifts.length,
                  itemBuilder: (ctx, i) {
                    final gift = _gifts[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (gift.thumbB64.isNotEmpty)
                            Image.memory(
                              base64Decode(gift.thumbB64),
                              width: 60,
                              height: 60,
                              fit: BoxFit.contain,
                            )
                          else
                            Icon(Icons.card_giftcard, size: 48, color: accentColor),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 14, color: Color(0xFFFFB743)),
                              const SizedBox(width: 4),
                              Text(
                                '${gift.stars}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          if (gift.remaining > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${gift.remaining} left',
                                style: TextStyle(fontSize: 11, color: subtextColor),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
