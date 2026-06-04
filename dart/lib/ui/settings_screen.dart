import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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
import 'calls_screen.dart' show InputLevelMeter;
import 'my_profile_page.dart';
import 'notifications_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'input_dialogs.dart' show showUsernameBox;
import 'settings_style.dart';
import 'telegram_toast.dart';
import '../theme/telegram_palette.dart';
import 'package:uniclient/utils/debug.dart';

void _openUrl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

const _kLanguageNamesFallback = <String, String>{
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
  String _tonBalance = '';
  bool _dialogFiltersEnabled = false;
  bool _premiumLoaded = false;
  String _nativeLanguageName = '';
  bool _showPhoneValidation = false;
  bool _showPasswordValidation = false;

  @override
  void initState() {
    super.initState();
    _loadPremiumData();
    _loadNativeLanguageName();
    _reloadSettingsData();
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
      engine.getTonBalance(accountId),
    ]);

    if (!mounted) return;
    final premiumStatus = results[0] as ({bool premiumPossible, bool premiumCanBuy});
    setState(() {
      _premiumPossible = premiumStatus.premiumPossible;
      _premiumCanBuy = premiumStatus.premiumCanBuy;
      _starsBalance = results[1] as int;
      _dialogFiltersEnabled = results[2] as bool;
      _tonBalance = results[3] as String;
      _premiumLoaded = true;
    });
  }

  Future<void> _loadNativeLanguageName() async {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null || account.platform != 'telegram') return;
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    try {
      final languages = await engine.getLanguages(accountId);
      if (!mounted) return;
      final code = appState.selectedLanguageCode;
      for (final lang in languages) {
        if (lang['lang_code'] == code || lang['code'] == code) {
          final name = lang['native_name'] as String? ?? lang['nativeName'] as String? ?? '';
          if (name.isNotEmpty) {
            setState(() => _nativeLanguageName = name);
            return;
          }
        }
      }
    } catch (e) {
      Debug.log('settings_screen', 'final languages = await engine.getLanguages(accountId): $e');
    }
  }

  Future<void> _reloadSettingsData() async {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null || account.platform != 'telegram') return;
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    try {
      final results = await Future.wait([
        engine.getCloudPasswordState(accountId).catchError((_) => null),
        engine.getContentSettings(accountId).catchError((_) => (sensitiveEnabled: false, sensitiveCanChange: false, ageVerifyNeeded: false)),
        engine.getAllPrivacySettings(accountId).catchError((_) => null),
      ]);
      if (!mounted) return;
      final pwState = results[0] as Map<String, dynamic>?;
      if (pwState != null) {
        final hasPassword = pwState['has_password'] as bool? ?? false;
        final pendingEmail = pwState['pending_email'] as bool? ?? false;
        setState(() {
          _showPhoneValidation = pwState['phone_unconfirmed'] as bool? ?? false;
          _showPasswordValidation = !hasPassword && pendingEmail;
        });
      }
    } catch (e) {
      Debug.log('settings_screen', 'final results = await Future.wait([: $e');
    }
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
      body: Builder(builder: (_) {
        final _lvKids = <Widget>[
          // §14.2: Profile header / cover area.
          _ProfileHeader(account: account, isDark: isDark),
          if (_showPhoneValidation)
            _ValidationBanner(
              icon: Icons.phone,
              text: 'Confirm your phone number to protect your account.',
              actionText: 'Confirm',
              onAction: () {
                setState(() => _showPhoneValidation = false);
              },
              onDismiss: () => setState(() => _showPhoneValidation = false),
              isDark: isDark,
            ),
          if (_showPasswordValidation)
            _ValidationBanner(
              icon: Icons.lock_outline,
              text: 'Set up a cloud password to protect your account.',
              actionText: 'Set Up',
              onAction: () {
                Navigator.of(context).push(
                  settingsPageRoute(
                    ChangeNotifierProvider.value(
                      value: appState,
                      child: const PrivacySettingsScreen(),
                    ),
                  ),
                );
              },
              onDismiss: () => setState(() => _showPasswordValidation = false),
              isDark: isDark,
            ),
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
              _nativeLanguageName.isNotEmpty
                  ? _nativeLanguageName
                  : (_kLanguageNamesFallback[appState.selectedLanguageCode] ?? appState.selectedLanguageCode.toUpperCase()),
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
                    isPremium: appState.effectivePremium,
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
            if (_tonBalance.isNotEmpty)
              _PremiumRow(
                icon: Icons.currency_exchange,
                label: 'Telegram Currency',
                isDark: isDark,
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _tonBalance,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.palette.windowBgActive,
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    settingsPageRoute(_CurrencyScreen(
                      accountId: appState.activeAccountId,
                      balance: _tonBalance,
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
        ];
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      }),
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
      height: 104,
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
                  width: 80,
                  height: 80,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
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
            const SizedBox(width: 10),
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
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    showUsernameBox(
      context,
      accountId: appState.activeAccountId,
      currentUsername: account.username,
    );
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
    Map<int, Uint8List> decodedThumbs = {};
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
      } catch (e) {
        Debug.log('settings_screen', 'final sets = await engine.getInstalledEmojiSets(accountId): $e');
      }
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
                final thumbs = <int, Uint8List>{};
                for (int i = 0; i < items.length; i++) {
                  if (items[i].thumbB64.isNotEmpty) {
                    try {
                      thumbs[i] = base64Decode(items[i].thumbB64);
                    } catch (e) {
                      Debug.log('settings_screen', 'thumbs[i] = base64Decode(items[i].thumbB64): $e');
                    }
                  }
                }
                setDialogState(() {
                  stickerItems = items;
                  decodedThumbs = thumbs;
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
                                child: decodedThumbs.containsKey(i)
                                    ? Image.memory(
                                        decodedThumbs[i]!,
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
    Map<int, Uint8List> decodedStatusThumbs = {};
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
      } catch (e) {
        Debug.log('settings_screen', 'final sets = await engine.getInstalledEmojiSets(accountId): $e');
      }
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
                final thumbs = <int, Uint8List>{};
                for (int i = 0; i < items.length; i++) {
                  if (items[i].thumbB64.isNotEmpty) {
                    try {
                      thumbs[i] = _decodeStrippedThumb(items[i].thumbB64);
                    } catch (e) {
                      Debug.log('settings_screen', 'thumbs[i] = _decodeStrippedThumb(items[i].thumbB64): $e');
                    }
                  }
                }
                setDialogState(() {
                  stickerItems = items;
                  decodedStatusThumbs = thumbs;
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
                            final docId = int.tryParse(item.fileId) ?? 0;
                            if (docId > 0) {
                              engine.setEmojiStatus(accountId, docId, selectedDuration);
                              Navigator.of(ctx).pop();
                              showTelegramToast(context, 'Emoji status set');
                            }
                          },
                          hoverColor: hoverBg,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: decodedStatusThumbs.containsKey(i)
                                ? Image.memory(
                                    decodedStatusThumbs[i]!,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, __, ___) => _emojiTextFallback(item.emoji),
                                  )
                                : _emojiTextFallback(item.emoji),
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
    final account = widget.account;
    final displayName = account?.displayName ?? '';

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
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 2),
              ),
              padding: const EdgeInsets.all(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: link,
                    version: QrVersions.auto,
                    size: 216,
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
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: accentColor,
                      backgroundImage: account?.avatarPath.isNotEmpty == true
                          ? FileImage(File(account!.avatarPath))
                          : null,
                      child: account?.avatarPath.isNotEmpty != true
                          ? Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                            )
                          : null,
                    ),
                  ),
                ],
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
            onPressed: () async {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.of(ctx).pop();
              showTelegramToast(context, 'Link copied to share');
            },
            child: Text('Share', style: TextStyle(color: accentColor)),
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

class _ValidationBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String actionText;
  final VoidCallback onAction;
  final VoidCallback onDismiss;
  final bool isDark;

  const _ValidationBanner({
    required this.icon,
    required this.text,
    required this.actionText,
    required this.onAction,
    required this.onDismiss,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = context.palette.windowBgActive;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFF3E0);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: textColor)),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(actionText, style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: textColor.withValues(alpha: 0.5)),
            onPressed: onDismiss,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
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
            child: RepaintBoundary(child: _ScalePreviewContent(
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
            )),
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

Route<void> devicesScreenRoute({int initialTab = 0}) {
  return settingsPageRoute(_DevicesScreen(initialTab: initialTab));
}

class _DevicesScreen extends StatelessWidget {
  final int initialTab;
  const _DevicesScreen({this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;

    return DefaultTabController(
      initialIndex: initialTab,
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

class _CallsSettingsTab extends StatefulWidget {
  const _CallsSettingsTab();

  @override
  State<_CallsSettingsTab> createState() => _CallsSettingsTabState();
}

class _CallsSettingsTabState extends State<_CallsSettingsTab> {
  List<String> _outputDevices = [];
  List<String> _inputDevices = [];
  List<String> _cameraDevices = [];
  String _selectedOutput = 'Default';
  String _selectedInput = 'Default';
  String _selectedCamera = 'Default';
  String _callSpecificOutput = '';
  String _callSpecificInput = '';
  String _p2pOption = 'contacts';
  bool _callsDisabled = false;
  bool _sameDevice = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final results = await Future.wait([
      engine.getAudioDevices(accountId, 'output'),
      engine.getAudioDevices(accountId, 'input'),
      engine.getAudioDevices(accountId, 'camera'),
      engine.getPrivacySetting(accountId, 'calls_p2p'),
      engine.getCallsDisabledHere(accountId),
    ]);

    if (!mounted) return;
    final outputDevs = results[0] as List<String>;
    final inputDevs = results[1] as List<String>;
    final cameraDevs = results[2] as List<String>;
    final p2pSetting = results[3] as Map<String, dynamic>?;
    final callsDisabled = results[4] as bool;

    setState(() {
      // The engine returns only real devices; prepend the "Default" sentinel
      // (the system default device) exactly like the in-call pickers do.
      _outputDevices = ['Default', ...outputDevs];
      _inputDevices = ['Default', ...inputDevs];
      _cameraDevices = cameraDevs.isNotEmpty ? cameraDevs : [];
      // Reflect the persisted selection so the picker opens on the saved device.
      _selectedOutput = appState.callOutputDevice;
      _selectedInput = appState.callInputDevice;
      _selectedCamera = cameraDevs.isNotEmpty ? cameraDevs.first : 'Default';
      final opt = p2pSetting?['option'] as String? ?? 'contacts';
      _p2pOption = opt;
      _callsDisabled = callsDisabled;
      _sameDevice = appState.callUseSameDevices;
      _callSpecificOutput = appState.callSpecificOutputDevice;
      _callSpecificInput = appState.callSpecificInputDevice;
      _loading = false;
    });
  }

  Future<void> _setP2P(String option) async {
    setState(() => _p2pOption = option);
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    await engine.setPrivacySetting(appState.activeAccountId, 'calls_p2p', option);
  }

  Future<void> _toggleCallsDisabled(bool disabled) async {
    setState(() => _callsDisabled = disabled);
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    await engine.setCallsDisabledHere(appState.activeAccountId, disabled: disabled);
  }

  void _toggleSameDevice(bool val) {
    setState(() => _sameDevice = val);
    final appState = context.read<AppState>();
    appState.setCallUseSameDevices(val);
    if (!val) {
      setState(() {
        _callSpecificOutput = appState.callSpecificOutputDevice;
        _callSpecificInput = appState.callSpecificInputDevice;
      });
    }
  }

  void _showDevicePicker(String title, List<String> devices, String selected, void Function(String) onSelect) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (ctx, i) {
              final dev = devices[i];
              final isSelected = dev == selected;
              return InkWell(
                onTap: () {
                  onSelect(dev);
                  Navigator.of(ctx).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 20,
                        color: isSelected ? accentColor : textColor.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(dev, style: TextStyle(fontSize: 14, color: textColor))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final accentColor = context.palette.windowBgActive;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE7E7E7);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final p2pOptions = [
      ('everyone', 'Everyone'),
      ('contacts', 'My contacts'),
      ('nobody', 'Nobody'),
    ];

    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text('Audio', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
        ),
        const SizedBox(height: 8),
        _DeviceSettingRow(
          label: 'Output device',
          value: _selectedOutput,
          isDark: isDark,
          onTap: () => _showDevicePicker('Output device', _outputDevices, _selectedOutput, (dev) {
            setState(() => _selectedOutput = dev);
            // Routes to engine.setCallAudioDevice(..,'output',..) + persists prefs.
            context.read<AppState>().setCallOutputDevice(dev);
          }),
        ),
        _DeviceSettingRow(
          label: 'Input device',
          value: _selectedInput,
          isDark: isDark,
          onTap: () => _showDevicePicker('Input device', _inputDevices, _selectedInput, (dev) {
            setState(() => _selectedInput = dev);
            // Routes to engine.setCallAudioDevice(..,'input',..) + persists prefs.
            context.read<AppState>().setCallInputDevice(dev);
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
          child: InputLevelMeter(
            isDark: isDark,
            accentColor: accentColor,
            selectedDevice: _selectedInput,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _toggleSameDevice(!_sameDevice),
          hoverColor: hoverBg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Use same devices for calls', style: TextStyle(fontSize: 14, color: textColor)),
                ),
                SizedBox(
                  width: 36,
                  height: 20,
                  child: Switch(
                    value: _sameDevice,
                    onChanged: _toggleSameDevice,
                    activeColor: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: _sameDevice
              ? const SizedBox.shrink()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    _DeviceSettingRow(
                      label: 'Call output device',
                      value: _callSpecificOutput.isEmpty ? 'Default' : _callSpecificOutput,
                      isDark: isDark,
                      onTap: () => _showDevicePicker('Call output device', _outputDevices,
                          _callSpecificOutput.isEmpty ? 'Default' : _callSpecificOutput, (dev) {
                        setState(() => _callSpecificOutput = dev);
                        context.read<AppState>().setCallSpecificOutputDevice(dev);
                      }),
                    ),
                    _DeviceSettingRow(
                      label: 'Call microphone',
                      value: _callSpecificInput.isEmpty ? 'Default' : _callSpecificInput,
                      isDark: isDark,
                      onTap: () => _showDevicePicker('Call microphone', _inputDevices,
                          _callSpecificInput.isEmpty ? 'Default' : _callSpecificInput, (dev) {
                        setState(() => _callSpecificInput = dev);
                        context.read<AppState>().setCallSpecificInputDevice(dev);
                      }),
                    ),
                  ],
                ),
        ),
        if (_cameraDevices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text('Camera', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
          ),
          const SizedBox(height: 8),
          _DeviceSettingRow(
            label: 'Video device',
            value: _selectedCamera,
            isDark: isDark,
            onTap: () => _showDevicePicker('Video device', _cameraDevices, _selectedCamera, (dev) async {
              setState(() => _selectedCamera = dev);
              final appState = context.read<AppState>();
              final engine = context.read<EngineService>();
              await engine.setCallAudioDevice(appState.activeAccountId, 'camera', dev);
            }),
          ),
        ],
        const SizedBox(height: 16),
        Container(height: 1, color: dividerColor),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text('Calls', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _toggleCallsDisabled(!_callsDisabled),
          hoverColor: hoverBg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Accept calls on this device', style: TextStyle(fontSize: 14, color: textColor)),
                ),
                SizedBox(
                  width: 36,
                  height: 20,
                  child: Switch(
                    value: !_callsDisabled,
                    onChanged: (v) => _toggleCallsDisabled(!v),
                    activeColor: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          child: Text(
            'Use peer-to-peer with',
            style: TextStyle(fontSize: 14, color: textColor),
          ),
        ),
        for (final (key, label) in p2pOptions)
          InkWell(
            onTap: () => _setP2P(key),
            hoverColor: hoverBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _p2pOption == key ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20,
                    color: _p2pOption == key ? accentColor : subtextColor,
                  ),
                  const SizedBox(width: 12),
                  Text(label, style: TextStyle(fontSize: 14, color: textColor)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            'Peer-to-peer calls can expose your IP address to the other party.',
            style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
          ),
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: dividerColor),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text('Other', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            if (Platform.isLinux) {
              Process.run('xdg-open', ['gnome-control-center://sound'])
                  .catchError((_) {
                return Process.run('xdg-open', ['x-settings://sound']);
              }).catchError((_) {
                return Process.run('pavucontrol', []);
              });
            } else if (Platform.isMacOS) {
              Process.run('open',
                  ['/System/Library/PreferencePanes/Sound.prefPane']);
            } else if (Platform.isWindows) {
              Process.run('control', ['mmsys.cpl', 'sounds']);
            }
          },
          hoverColor: hoverBg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.open_in_new, size: 20, color: textColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Open system sound preferences', style: TextStyle(fontSize: 14, color: textColor)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ];
      return ListView.builder(
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
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
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadPremiumInfo();
  }

  Future<void> _loadPremiumInfo() async {
    final engine = context.read<EngineService>();
    try {
      final result = await engine.getPremiumFeatures(widget.accountId);
      if (result.isNotEmpty && mounted) {
        setState(() {
          _features = result;
          _loading = false;
          _loadError = false;
        });
        return;
      }
    } catch (e) {
      Debug.log('settings_screen', 'final result = await engine.getPremiumFeatures(widget.acc...: $e');
    }
    if (mounted) setState(() { _loading = false; _loadError = true; });
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
          : Builder(builder: (_) {
            final _lvKids = <Widget>[
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
                if (_loadError) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.cloud_off, size: 36, color: subtextColor),
                          const SizedBox(height: 8),
                          Text('Could not load feature list from server.',
                            style: TextStyle(fontSize: 14, color: subtextColor)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              setState(() { _loading = true; _loadError = false; });
                              _loadPremiumInfo();
                            },
                            child: Text('Retry', style: TextStyle(color: accentColor)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
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
                ],
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
                      onPressed: () async {
                        final engine = context.read<EngineService>();
                        try {
                          await engine.openPremiumSubscription(widget.accountId, ref: 'settings');
                        } catch (_) {
                          if (mounted) {
                            showTelegramToast(context, 'Premium subscription is managed through the official Telegram app');
                          }
                        }
                      },
                      child: const Text('Subscribe to Premium', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ];
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _lvKids.length,
              itemBuilder: (_, _lvI) => _lvKids[_lvI],
            );
          }),
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

class _CreditsScreenState extends State<_CreditsScreen> with SingleTickerProviderStateMixin {
  late int _balance;
  late TabController _tabController;
  List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _inTransactions = [];
  List<Map<String, dynamic>> _outTransactions = [];
  bool _txLoading = true;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _tabController = TabController(length: 3, vsync: this);
    _refreshBalance();
    _loadTransactions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshBalance() async {
    final engine = context.read<EngineService>();
    final balance = await engine.getStarsBalance(widget.accountId);
    if (mounted) setState(() => _balance = balance);
  }

  Future<void> _loadTransactions() async {
    final engine = context.read<EngineService>();
    try {
      final txList = await engine.getStarsTransactions(widget.accountId);
      if (mounted) {
        setState(() {
          _allTransactions = txList;
          _inTransactions = txList.where((t) {
            final dir = t['direction'] as String?;
            if (dir != null) return dir == 'incoming' || dir == 'in';
            return (t['amount'] as num? ?? 0) > 0;
          }).toList();
          _outTransactions = txList.where((t) {
            final dir = t['direction'] as String?;
            if (dir != null) return dir == 'outgoing' || dir == 'out';
            return (t['amount'] as num? ?? 0) < 0;
          }).toList();
          _txLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _txLoading = false);
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
        title: Text('Telegram Stars', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.star, size: 48, color: Color(0xFFFFB743)),
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final engine = context.read<EngineService>();
                  try {
                    await engine.openStarsPurchase(widget.accountId);
                  } catch (_) {
                    if (mounted) {
                      showTelegramToast(context, 'Stars can be purchased in the official Telegram app');
                    }
                  }
                },
                child: const Text('Buy Stars', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            labelColor: accentColor,
            unselectedLabelColor: subtextColor,
            indicatorColor: accentColor,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Incoming'),
              Tab(text: 'Outgoing'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTransactionList(_allTransactions, textColor, subtextColor, isDark),
                _buildTransactionList(_inTransactions, textColor, subtextColor, isDark),
                _buildTransactionList(_outTransactions, textColor, subtextColor, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(
    List<Map<String, dynamic>> transactions,
    Color textColor,
    Color subtextColor,
    bool isDark,
  ) {
    if (_txLoading) return const Center(child: CircularProgressIndicator());
    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: subtextColor),
            const SizedBox(height: 12),
            Text('No transactions yet', style: TextStyle(fontSize: 16, color: subtextColor)),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (ctx, i) {
        final tx = transactions[i];
        final amount = (tx['amount'] as num?)?.toInt() ?? 0;
        final title = tx['title'] as String? ?? tx['peer'] as String? ?? 'Transaction';
        final date = tx['date'] as String? ?? '';
        final dir = tx['direction'] as String?;
        final isPositive = dir != null
            ? (dir == 'incoming' || dir == 'in')
            : amount > 0;
        return ListTile(
          leading: Icon(
            isPositive ? Icons.arrow_downward : Icons.arrow_upward,
            color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
          ),
          title: Text(title, style: TextStyle(fontSize: 14, color: textColor)),
          subtitle: date.isNotEmpty ? Text(date, style: TextStyle(fontSize: 12, color: subtextColor)) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, size: 14, color: Color(0xFFFFB743)),
              const SizedBox(width: 4),
              Text(
                '${isPositive ? '+' : ''}$amount',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CurrencyScreen extends StatefulWidget {
  final String accountId;
  final String balance;

  const _CurrencyScreen({required this.accountId, required this.balance});

  @override
  State<_CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<_CurrencyScreen> {
  late String _balance;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _refreshBalance();
  }

  Future<void> _refreshBalance() async {
    final engine = context.read<EngineService>();
    try {
      final balance = await engine.getTonBalance(widget.accountId);
      if (mounted && balance.isNotEmpty) setState(() => _balance = balance);
    } catch (e) {
      Debug.log('settings_screen', 'final balance = await engine.getTonBalance(widget.accountId): $e');
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
        title: Text('Telegram Currency', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Builder(builder: (_) {
        final _lvKids = <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.currency_exchange, size: 48, color: Color(0xFF0098EA)),
                const SizedBox(height: 8),
                Text(
                  _balance,
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: textColor),
                ),
                const SizedBox(height: 4),
                Text('TON Balance', style: TextStyle(fontSize: 14, color: subtextColor)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Telegram Currency (TON) can be used for transactions within Telegram. Your balance is synced with the Telegram blockchain wallet.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _refreshBalance,
              child: const Text('Refresh Balance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ];
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      }),
    );
  }
}

class _BusinessScreen extends StatefulWidget {
  final String accountId;

  const _BusinessScreen({required this.accountId});

  @override
  State<_BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<_BusinessScreen> {
  Map<String, dynamic> _businessInfo = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBusinessInfo();
  }

  Future<void> _loadBusinessInfo() async {
    final engine = context.read<EngineService>();
    try {
      final info = await engine.getBusinessInfo(widget.accountId);
      if (mounted) setState(() { _businessInfo = info; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openBusinessSubPage(String featureKey, String title) {
    Navigator.of(context).push(settingsPageRoute(
      _BusinessSubPage(
        accountId: widget.accountId,
        featureKey: featureKey,
        title: title,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final features = [
      ('hours', 'Business Hours', 'Set working hours so clients know when to reach you', Icons.schedule),
      ('location', 'Business Location', 'Display your business address on your profile', Icons.location_on),
      ('greeting', 'Greeting Messages', 'Send automatic greeting messages to new clients', Icons.waving_hand),
      ('away', 'Away Messages', 'Automatically reply when you are unavailable', Icons.flight),
      ('quick_replies', 'Quick Replies', 'Set up shortcuts for frequently used messages', Icons.flash_on),
      ('chatbots', 'Chatbot Integration', 'Connect a Telegram bot to manage conversations', Icons.smart_toy),
      ('intro', 'Chat Intro', 'Customize your chat intro with an image and text', Icons.view_agenda),
      ('links', 'Chat Links', 'Create direct chat links for customers', Icons.link),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (_) {
            final _lvKids = <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
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
                ),
                for (final (key, name, desc, icon) in features)
                  InkWell(
                    onTap: () => _openBusinessSubPage(key, name),
                    hoverColor: hoverBg,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      child: Row(
                        children: [
                          Icon(icon, size: 24, color: accentColor),
                          const SizedBox(width: 16),
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
                          Icon(Icons.chevron_right, size: 20, color: subtextColor),
                        ],
                      ),
                    ),
                  ),
              ];
            return ListView.builder(
              itemCount: _lvKids.length,
              itemBuilder: (_, _lvI) => _lvKids[_lvI],
            );
          }),
    );
  }
}

class _BusinessSubPage extends StatefulWidget {
  final String accountId;
  final String featureKey;
  final String title;

  const _BusinessSubPage({required this.accountId, required this.featureKey, required this.title});

  @override
  State<_BusinessSubPage> createState() => _BusinessSubPageState();
}

class _BusinessSubPageState extends State<_BusinessSubPage> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _saving = false;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final engine = context.read<EngineService>();
    try {
      final data = await engine.getBusinessFeature(widget.accountId, widget.featureKey);
      if (mounted) {
        if (widget.featureKey == 'hours') {
          final hours = data['hours'] as Map<String, dynamic>? ?? {};
          if (data['intervals'] == null && hours.isNotEmpty) {
            final intervals = <String, dynamic>{};
            for (final entry in hours.entries) {
              final val = entry.value as String? ?? '';
              if (val == 'closed') {
                intervals[entry.key] = {'open': false, 'open_minute': 540, 'close_minute': 1080};
              } else {
                final parts = val.split(' - ');
                var openMin = 540, closeMin = 1080;
                if (parts.length == 2) {
                  final sp = parts[0].split(':');
                  final ep = parts[1].split(':');
                  if (sp.length == 2) openMin = (int.tryParse(sp[0]) ?? 9) * 60 + (int.tryParse(sp[1]) ?? 0);
                  if (ep.length == 2) closeMin = (int.tryParse(ep[0]) ?? 18) * 60 + (int.tryParse(ep[1]) ?? 0);
                }
                intervals[entry.key] = {'open': true, 'open_minute': openMin, 'close_minute': closeMin};
              }
            }
            data['intervals'] = intervals;
          }
        }
        setState(() {
          _data = data;
          if (widget.featureKey == 'greeting' || widget.featureKey == 'away') {
            _textController.text = _data['message'] as String? ?? '';
          } else if (widget.featureKey == 'intro') {
            _textController.text = _data['text'] as String? ?? '';
          } else if (widget.featureKey == 'location') {
            _textController.text = _data['address'] as String? ?? '';
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveData() async {
    if (_saving) return;
    setState(() => _saving = true);
    final engine = context.read<EngineService>();
    try {
      final update = Map<String, dynamic>.from(_data);
      if (widget.featureKey == 'greeting' || widget.featureKey == 'away') {
        update['message'] = _textController.text;
      } else if (widget.featureKey == 'intro') {
        update['text'] = _textController.text;
      } else if (widget.featureKey == 'location') {
        update['address'] = _textController.text;
      } else if (widget.featureKey == 'hours') {
        final intervals = update['intervals'] as Map<String, dynamic>? ?? {};
        final hoursCompat = <String, dynamic>{};
        for (final entry in intervals.entries) {
          final dayData = entry.value as Map<String, dynamic>?;
          if (dayData != null) {
            final isOpen = dayData['open'] as bool? ?? true;
            if (isOpen) {
              final openMin = dayData['open_minute'] as int? ?? 540;
              final closeMin = dayData['close_minute'] as int? ?? 1080;
              hoursCompat[entry.key] = '${(openMin ~/ 60).toString().padLeft(2, '0')}:${(openMin % 60).toString().padLeft(2, '0')} - ${(closeMin ~/ 60).toString().padLeft(2, '0')}:${(closeMin % 60).toString().padLeft(2, '0')}';
            } else {
              hoursCompat[entry.key] = 'closed';
            }
          }
        }
        update['hours'] = hoursCompat;
      }
      await engine.setBusinessFeature(widget.accountId, widget.featureKey, update);
      if (mounted) {
        showTelegramToast(context, '${widget.title} saved');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
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
        title: Text(widget.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveData,
            child: _saving
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: accentColor))
                : Text('Save', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(textColor, subtextColor, accentColor, isDark),
    );
  }

  Widget _buildContent(Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    switch (widget.featureKey) {
      case 'hours':
        return _buildHoursEditor(textColor, subtextColor, accentColor, isDark);
      case 'location':
        return _buildLocationEditor(textColor, subtextColor, accentColor);
      case 'greeting':
      case 'away':
        return _buildMessageEditor(textColor, subtextColor, accentColor);
      case 'quick_replies':
        return _buildQuickRepliesEditor(textColor, subtextColor, accentColor, isDark);
      case 'chatbots':
        return _buildChatbotsEditor(textColor, subtextColor, accentColor, isDark);
      case 'intro':
        return _buildIntroEditor(textColor, subtextColor, accentColor);
      case 'links':
        return _buildLinksEditor(textColor, subtextColor, accentColor, isDark);
      default:
        return Center(child: Text('Not available', style: TextStyle(color: subtextColor)));
    }
  }

  Widget _buildHoursEditor(Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    final enabled = _data['enabled'] as bool? ?? false;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final intervals = _data['intervals'] as Map<String, dynamic>? ?? {};
    final timezone = _data['timezone'] as String? ?? 'UTC';

    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        InkWell(
          onTap: () => setState(() => _data['enabled'] = !enabled),
          hoverColor: hoverBg,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(child: Text('Enable Business Hours', style: TextStyle(fontSize: 14, color: textColor))),
                Switch(value: enabled, onChanged: (v) => setState(() => _data['enabled'] = v), activeColor: accentColor),
              ],
            ),
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _pickTimezone(textColor, subtextColor, accentColor, isDark),
            hoverColor: hoverBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text('Timezone', style: TextStyle(fontSize: 14, color: textColor))),
                  Text(timezone, style: TextStyle(fontSize: 13, color: accentColor)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 16, color: subtextColor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Set your availability', style: TextStyle(fontSize: 13, color: subtextColor)),
          const SizedBox(height: 8),
          for (final day in days)
            _buildDayRow(day, intervals, textColor, subtextColor, accentColor, hoverBg, isDark),
        ],
      ];
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
  }

  Widget _buildDayRow(String day, Map<String, dynamic> intervals, Color textColor, Color subtextColor, Color accentColor, Color hoverBg, bool isDark) {
    final key = day.toLowerCase();
    final dayData = intervals[key] as Map<String, dynamic>?;
    final isOpen = dayData?['open'] as bool? ?? true;
    final openMinute = dayData?['open_minute'] as int? ?? 540;
    final closeMinute = dayData?['close_minute'] as int? ?? 1080;
    final displayOpen = '${(openMinute ~/ 60).toString().padLeft(2, '0')}:${(openMinute % 60).toString().padLeft(2, '0')}';
    final displayClose = '${(closeMinute ~/ 60).toString().padLeft(2, '0')}:${(closeMinute % 60).toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () => _pickDayHours(day, intervals, textColor, subtextColor, accentColor, isDark),
      hoverColor: hoverBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Checkbox(
                value: isOpen,
                activeColor: accentColor,
                onChanged: (v) {
                  setState(() {
                    final updated = Map<String, dynamic>.from(intervals);
                    updated[key] = {
                      'open': v ?? true,
                      'open_minute': openMinute,
                      'close_minute': closeMinute,
                    };
                    _data['intervals'] = updated;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(day, style: TextStyle(fontSize: 14, color: isOpen ? textColor : subtextColor))),
            Text(
              isOpen ? '$displayOpen - $displayClose' : 'Closed',
              style: TextStyle(fontSize: 13, color: isOpen ? accentColor : subtextColor),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: subtextColor),
          ],
        ),
      ),
    );
  }

  void _pickTimezone(Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final timezones = ['UTC', 'America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles',
      'Europe/London', 'Europe/Berlin', 'Europe/Moscow', 'Asia/Tehran', 'Asia/Dubai', 'Asia/Kolkata',
      'Asia/Shanghai', 'Asia/Tokyo', 'Australia/Sydney'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Select Timezone', style: TextStyle(color: textColor)),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.builder(
            itemCount: timezones.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(timezones[i], style: TextStyle(fontSize: 14, color: textColor)),
              onTap: () {
                setState(() => _data['timezone'] = timezones[i]);
                Navigator.of(ctx).pop();
              },
            ),
          ),
        ),
      ),
    );
  }

  void _pickDayHours(String day, Map<String, dynamic> intervals, Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    final key = day.toLowerCase();
    final dayData = intervals[key] as Map<String, dynamic>?;
    final openMinute = dayData?['open_minute'] as int? ?? 540;
    final closeMinute = dayData?['close_minute'] as int? ?? 1080;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);

    showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) {
        var sH = openMinute ~/ 60, sM = openMinute % 60;
        var eH = closeMinute ~/ 60, eM = closeMinute % 60;
        return StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            backgroundColor: bgColor,
            title: Text('$day hours', style: TextStyle(color: textColor)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('From: ', style: TextStyle(color: subtextColor)),
                    TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: sH, minute: sM));
                        if (t != null) setDlgState(() { sH = t.hour; sM = t.minute; });
                      },
                      child: Text('${sH.toString().padLeft(2, '0')}:${sM.toString().padLeft(2, '0')}', style: TextStyle(color: accentColor, fontSize: 16)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('To:     ', style: TextStyle(color: subtextColor)),
                    TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: eH, minute: eM));
                        if (t != null) setDlgState(() { eH = t.hour; eM = t.minute; });
                      },
                      child: Text('${eH.toString().padLeft(2, '0')}:${eM.toString().padLeft(2, '0')}', style: TextStyle(color: accentColor, fontSize: 16)),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: TextStyle(color: subtextColor))),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop({'open': sH * 60 + sM, 'close': eH * 60 + eM}),
                child: Text('Save', style: TextStyle(color: accentColor)),
              ),
            ],
          ),
        );
      },
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          final updated = Map<String, dynamic>.from(intervals);
          updated[key] = {
            'open': true,
            'open_minute': result['open'],
            'close_minute': result['close'],
          };
          _data['intervals'] = updated;
        });
      }
    });
  }

  Widget _buildLocationEditor(Color textColor, Color subtextColor, Color accentColor) {
    final lat = _data['lat'] as num? ?? 0.0;
    final lng = _data['lng'] as num? ?? 0.0;
    final hasCoords = lat != 0.0 || lng != 0.0;
    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        Text('Business Address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        TextField(
          controller: _textController,
          maxLines: 3,
          style: TextStyle(fontSize: 14, color: textColor),
          decoration: InputDecoration(
            hintText: 'Enter your business address...',
            hintStyle: TextStyle(color: subtextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor)),
          ),
        ),
        const SizedBox(height: 16),
        Text('Coordinates', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: 14, color: textColor),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Latitude',
                  labelStyle: TextStyle(color: subtextColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor)),
                ),
                controller: TextEditingController(text: lat != 0.0 ? lat.toStringAsFixed(6) : ''),
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null && parsed >= -90 && parsed <= 90) {
                    _data['lat'] = parsed;
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: 14, color: textColor),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Longitude',
                  labelStyle: TextStyle(color: subtextColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor)),
                ),
                controller: TextEditingController(text: lng != 0.0 ? lng.toStringAsFixed(6) : ''),
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null && parsed >= -180 && parsed <= 180) {
                    _data['lng'] = parsed;
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (hasCoords)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Location: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
              style: TextStyle(fontSize: 13, color: accentColor),
            ),
          ),
        Text('This address and location will be displayed on your profile.', style: TextStyle(fontSize: 13, color: subtextColor)),
      ];
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
  }

  Widget _buildMessageEditor(Color textColor, Color subtextColor, Color accentColor) {
    final isGreeting = widget.featureKey == 'greeting';
    final recipientFilter = _data['recipient_filter'] as String? ?? 'all';
    final exceptIds = (_data['except_ids'] as List<dynamic>?)?.cast<String>() ?? [];
    final onlyIds = (_data['only_ids'] as List<dynamic>?)?.cast<String>() ?? [];
    final inactivityDays = _data['inactivity_days'] as int? ?? 7;
    final scheduleType = _data['schedule'] as String? ?? 'always';

    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        Text(
          isGreeting ? 'Greeting Message' : 'Away Message',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _textController,
          maxLines: 5,
          style: TextStyle(fontSize: 14, color: textColor),
          decoration: InputDecoration(
            hintText: isGreeting ? 'Hello! How can I help you?' : 'I\'m currently away, I\'ll get back to you soon.',
            hintStyle: TextStyle(color: subtextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor)),
          ),
        ),
        const SizedBox(height: 16),
        Text('Who receives this message', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        for (final (value, label) in <(String, String)>[
          ('all', 'All new chats'),
          ('contacts', 'All contacts'),
          ('non_contacts', 'All non-contacts'),
          ('selected', 'Selected chats only'),
          ('all_except', 'All chats except...'),
        ])
          RadioListTile<String>(
            title: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
            value: value,
            groupValue: recipientFilter,
            activeColor: accentColor,
            contentPadding: EdgeInsets.zero,
            dense: true,
            onChanged: (v) => setState(() => _data['recipient_filter'] = v),
          ),
        if (recipientFilter == 'all_except' && exceptIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text('${exceptIds.length} chat(s) excluded', style: TextStyle(fontSize: 13, color: subtextColor)),
          ),
        if (recipientFilter == 'selected' && onlyIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text('${onlyIds.length} chat(s) selected', style: TextStyle(fontSize: 13, color: subtextColor)),
          ),
        if (isGreeting) ...[
          const SizedBox(height: 16),
          Text('Inactivity period', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(height: 4),
          Text('Send greeting again after this period of inactivity.', style: TextStyle(fontSize: 13, color: subtextColor)),
          const SizedBox(height: 8),
          DropdownButton<int>(
            value: inactivityDays,
            isExpanded: true,
            dropdownColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF17212B) : Colors.white,
            style: TextStyle(fontSize: 14, color: textColor),
            items: const [
              DropdownMenuItem(value: 7, child: Text('1 week')),
              DropdownMenuItem(value: 14, child: Text('2 weeks')),
              DropdownMenuItem(value: 30, child: Text('1 month')),
            ],
            onChanged: (v) => setState(() => _data['inactivity_days'] = v),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text('Schedule', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(height: 8),
          for (final (value, label) in <(String, String)>[
            ('always', 'Always send'),
            ('outside_hours', 'Outside business hours'),
            ('custom', 'Custom schedule'),
          ])
            RadioListTile<String>(
              title: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
              value: value,
              groupValue: scheduleType,
              activeColor: accentColor,
              contentPadding: EdgeInsets.zero,
              dense: true,
              onChanged: (v) => setState(() => _data['schedule'] = v),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          isGreeting
              ? 'This message will be sent automatically to new customers who write to you for the first time.'
              : 'This message will be sent automatically when you are unavailable.',
          style: TextStyle(fontSize: 13, color: subtextColor),
        ),
      ];
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
  }

  Widget _buildQuickRepliesEditor(Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    final replies = _data['replies'] as List<dynamic>? ?? [];
    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        Text('Quick Replies', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        Text('Set up shortcuts for frequently used messages.', style: TextStyle(fontSize: 13, color: subtextColor)),
        const SizedBox(height: 16),
        for (var i = 0; i < replies.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text('/${replies[i]['shortcut'] ?? ''}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(replies[i]['message'] as String? ?? '', style: TextStyle(fontSize: 14, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: subtextColor),
                    onPressed: () async {
                      final shortcutId = replies[i]['shortcut_id'] as int? ?? 0;
                      if (shortcutId > 0) {
                        final engine = context.read<EngineService>();
                        try {
                          await engine.deleteQuickReplyShortcut(widget.accountId, shortcutId);
                        } catch (e) {
                          Debug.log('settings_screen', 'await engine.deleteQuickReplyShortcut(widget.accountId, s...: $e');
                        }
                      }
                      if (!mounted) return;
                      setState(() {
                        final r = List<dynamic>.from(replies)..removeAt(i);
                        _data['replies'] = r;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _showAddQuickReplyDialog(textColor, subtextColor, accentColor, isDark),
          icon: const Icon(Icons.add),
          label: const Text('Add Quick Reply'),
          style: OutlinedButton.styleFrom(foregroundColor: accentColor, side: BorderSide(color: accentColor)),
        ),
      ];
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
  }

  void _showAddQuickReplyDialog(Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final shortcutCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Add Quick Reply', style: TextStyle(color: textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: shortcutCtrl,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(hintText: 'Shortcut (e.g. hello)', hintStyle: TextStyle(color: subtextColor)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: messageCtrl,
              maxLines: 3,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(hintText: 'Message text', hintStyle: TextStyle(color: subtextColor)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: TextStyle(color: subtextColor))),
          TextButton(
            onPressed: () async {
              if (shortcutCtrl.text.isNotEmpty && messageCtrl.text.isNotEmpty) {
                final replies = List<dynamic>.from(_data['replies'] as List<dynamic>? ?? []);
                replies.add({'shortcut': shortcutCtrl.text, 'message': messageCtrl.text});
                setState(() => _data['replies'] = replies);
                Navigator.of(ctx).pop();
                final engine = context.read<EngineService>();
                try {
                  await engine.setBusinessFeature(widget.accountId, widget.featureKey, Map<String, dynamic>.from(_data));
                  await _loadData();
                } catch (e) {
                  Debug.log('settings_screen', 'await engine.setBusinessFeature(widget.accountId, widget....: $e');
                }
              }
            },
            child: Text('Add', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatbotsEditor(Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    final bots = (_data['bots'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final legacyBot = _data['bot_username'] as String? ?? '';
    if (bots.isEmpty && legacyBot.isNotEmpty) {
      bots.add({'username': legacyBot, 'reply_to_messages': true, 'manage_chats': false});
      _data['bots'] = bots;
    }

    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        Text('Connected Chatbots', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        Text('Connect Telegram bots to manage customer conversations.', style: TextStyle(fontSize: 13, color: subtextColor)),
        const SizedBox(height: 16),
        for (var i = 0; i < bots.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.smart_toy, color: accentColor),
                      const SizedBox(width: 12),
                      Expanded(child: Text('@${bots[i]['username'] ?? ''}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor))),
                      IconButton(
                        icon: Icon(Icons.close, size: 20, color: subtextColor),
                        onPressed: () {
                          setState(() {
                            final updated = List<Map<String, dynamic>>.from(bots)..removeAt(i);
                            _data['bots'] = updated;
                            if (updated.isEmpty) _data['bot_username'] = '';
                          });
                        },
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Reply to messages', style: TextStyle(fontSize: 13, color: textColor))),
                            Switch(
                              value: bots[i]['reply_to_messages'] as bool? ?? true,
                              onChanged: (v) => setState(() => bots[i]['reply_to_messages'] = v),
                              activeColor: accentColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _showAddBotDialog(textColor, subtextColor, accentColor, isDark),
          icon: const Icon(Icons.add),
          label: const Text('Connect Bot'),
          style: OutlinedButton.styleFrom(foregroundColor: accentColor, side: BorderSide(color: accentColor)),
        ),
      ];
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
  }

  void _showAddBotDialog(Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF),
        title: Text('Connect Bot', style: TextStyle(color: textColor)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(hintText: '@bot_username', hintStyle: TextStyle(color: subtextColor)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: TextStyle(color: subtextColor))),
          TextButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                final username = ctrl.text.replaceFirst('@', '');
                setState(() {
                  final bots = (_data['bots'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
                  bots.add({'username': username, 'reply_to_messages': true, 'manage_chats': false});
                  _data['bots'] = bots;
                  _data['bot_username'] = username;
                });
                Navigator.of(ctx).pop();
              }
            },
            child: Text('Connect', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroEditor(Color textColor, Color subtextColor, Color accentColor) {
    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        Text('Chat Intro', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        Text('Customize the intro that new customers see when they open a chat with you.', style: TextStyle(fontSize: 13, color: subtextColor)),
        const SizedBox(height: 16),
        TextField(
          controller: _textController,
          maxLines: 4,
          style: TextStyle(fontSize: 14, color: textColor),
          decoration: InputDecoration(
            hintText: 'Welcome to our business! How can we help?',
            hintStyle: TextStyle(color: subtextColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor)),
          ),
        ),
      ];
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
  }

  Widget _buildLinksEditor(Color textColor, Color subtextColor, Color accentColor, bool isDark) {
    final links = _data['links'] as List<dynamic>? ?? [];
    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        Text('Chat Links', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        Text('Create direct links that customers can use to start a chat with you.', style: TextStyle(fontSize: 13, color: subtextColor)),
        const SizedBox(height: 16),
        for (var i = 0; i < links.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, color: accentColor),
                  const SizedBox(width: 12),
                  Expanded(child: Text(links[i] as String? ?? '', style: TextStyle(fontSize: 14, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: Icon(Icons.copy, size: 18, color: subtextColor),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: links[i] as String? ?? ''));
                      showTelegramToast(context, 'Link copied');
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: subtextColor),
                    onPressed: () async {
                      final link = links[i] as String? ?? '';
                      final slug = link.contains('/') ? link.split('/').last : link;
                      if (slug.isNotEmpty) {
                        final engine = context.read<EngineService>();
                        try {
                          await engine.deleteBusinessChatLink(widget.accountId, slug);
                        } catch (e) {
                          Debug.log('settings_screen', 'await engine.deleteBusinessChatLink(widget.accountId, slug): $e');
                        }
                      }
                      if (!mounted) return;
                      setState(() {
                        final l = List<dynamic>.from(links)..removeAt(i);
                        _data['links'] = l;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final engine = context.read<EngineService>();
            try {
              final link = await engine.createBusinessChatLink(widget.accountId);
              if (link.isNotEmpty && mounted) {
                final newLinks = List<dynamic>.from(links)..add(link);
                setState(() => _data['links'] = newLinks);
              }
            } catch (e) {
              if (mounted) showTelegramToast(context, 'Failed to create link');
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Create Link'),
          style: OutlinedButton.styleFrom(foregroundColor: accentColor, side: BorderSide(color: accentColor)),
        ),
      ];
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
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
  Map<int, Uint8List> _decodedThumbs = {};
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
      final gifts = result?.gifts ?? [];
      final b64List = <int, String>{};
      for (int i = 0; i < gifts.length; i++) {
        if (gifts[i].thumbB64.isNotEmpty) b64List[i] = gifts[i].thumbB64;
      }
      final thumbs = await _decodeThumbsInIsolate(b64List);
      if (mounted) {
        setState(() {
          _gifts = gifts;
          _decodedThumbs = thumbs;
          _loading = false;
        });
      }
    }
  }

  static Future<Map<int, Uint8List>> _decodeThumbsInIsolate(Map<int, String> b64Map) async {
    return await Isolate.run(() {
      final result = <int, Uint8List>{};
      for (final entry in b64Map.entries) {
        try {
          result[entry.key] = base64Decode(entry.value);
        } catch (e) {
          Debug.log('settings_screen', 'result[entry.key] = base64Decode(entry.value): $e');
        }
      }
      return result;
    });
  }

  void _showRecipientPicker(BuildContext context, StarGiftItem gift) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final engine = context.read<EngineService>();

    showDialog(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        List<ContactInfo>? contacts;
        bool loadingContacts = true;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (contacts == null) {
              engine.getContacts(widget.accountId).then((result) {
                if (ctx.mounted) {
                  setDialogState(() {
                    contacts = result.where((c) => !c.isBot && c.userId.isNotEmpty).toList();
                    loadingContacts = false;
                  });
                }
              }).catchError((_) {
                if (ctx.mounted) setDialogState(() { contacts = []; loadingContacts = false; });
              });
            }

            final allContacts = contacts ?? [];
            final filtered = searchQuery.isEmpty
                ? allContacts
                : allContacts.where((c) =>
                    c.displayName.toLowerCase().contains(searchQuery.toLowerCase()) ||
                    c.username.toLowerCase().contains(searchQuery.toLowerCase())).toList();

            return AlertDialog(
              backgroundColor: bgColor,
              title: Text('Choose Recipient', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
              content: SizedBox(
                width: 300,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        hintStyle: TextStyle(color: subtextColor),
                        prefixIcon: Icon(Icons.search, color: subtextColor),
                      ),
                      onChanged: (v) => setDialogState(() => searchQuery = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: loadingContacts
                          ? const Center(child: CircularProgressIndicator())
                          : filtered.isEmpty
                              ? Center(child: Text('No contacts found', style: TextStyle(color: subtextColor)))
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (ctx, i) {
                                    final contact = filtered[i];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: accentColor,
                                        child: Text(
                                          contact.displayName.isNotEmpty ? contact.displayName[0].toUpperCase() : '?',
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      title: Text(contact.displayName, style: TextStyle(fontSize: 14, color: textColor)),
                                      subtitle: contact.username.isNotEmpty
                                          ? Text('@${contact.username}', style: TextStyle(fontSize: 12, color: subtextColor))
                                          : null,
                                      onTap: () async {
                                        Navigator.of(ctx).pop();
                                        try {
                                          final success = await engine.sendStarGift(widget.accountId, contact.userId, gift.id);
                                          if (context.mounted) {
                                            showTelegramToast(context, success ? 'Gift sent!' : 'Failed to send gift');
                                          }
                                        } catch (e) {
                                          if (context.mounted) showTelegramToast(context, 'Error: $e');
                                        }
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: subtextColor)),
                ),
              ],
            );
          },
        );
      },
    );
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
                    return GestureDetector(
                      onTap: () => _showRecipientPicker(context, gift),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_decodedThumbs.containsKey(i))
                              Image.memory(
                                _decodedThumbs[i]!,
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
                      ),
                    );
                  },
                ),
    );
  }
}
