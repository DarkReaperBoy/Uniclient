import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../utils/system_unlock.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import 'active_sessions_screen.dart';
import 'settings_style.dart';
import 'telegram_toast.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _scrollController = ScrollController();
  Timer? _pollTimer;

  String _2faLabel = 'Loading...';
  bool? _hasPassword;
  bool _hasRecovery = false;
  String _hint = '';
  String _unconfirmedEmail = '';
  int _pendingResetDate = 0;
  String _loginEmailPattern = '';

  int _globalTTL = 0;

  bool _hasPasscode = false;

  List<Map<String, dynamic>> _passkeys = [];
  bool _passkeysLoaded = false;

  int _blockedCount = -1;
  int _sessionsCount = -1;

  Map<String, Map<String, dynamic>> _privacySettings = {};
  bool _privacyLoaded = false;

  String _messagesPrivacyOption = 'everyone';
  int _messagesChargeStars = 0;

  bool _archiveAndMute = false;
  bool _archiveKeepUnmuted = false;
  bool _archiveKeepFolders = false;
  bool _archiveLoaded = false;

  int _accountTTLDays = 0;
  bool _topPeersEnabled = true;
  bool _topPeersLoaded = false;

  @override
  void initState() {
    super.initState();
    _fetchPasswordState();
    _fetchGlobalTTL();
    _loadPasscodeState();
    _fetchPasskeys();
    _fetchBlockedCount();
    _fetchSessionsCount();
    _fetchAllPrivacy();
    _fetchMessagesPrivacy();
    _fetchArchiveSettings();
    _fetchAccountTTL();
    _fetchTopPeers();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchPasswordState();
      _fetchGlobalTTL();
      _loadPasscodeState();
      _fetchPasskeys();
      _fetchBlockedCount();
      _fetchSessionsCount();
      _fetchAllPrivacy();
      _fetchMessagesPrivacy();
      _fetchArchiveSettings();
      _fetchAccountTTL();
      _fetchTopPeers();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPasswordState() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final state = await engine.getCloudPasswordState(accountId);
    if (!mounted) return;

    if (state == null) {
      setState(() => _2faLabel = 'Off');
      return;
    }

    setState(() {
      _hasPassword = state['hasPassword'] as bool? ?? false;
      _hasRecovery = state['hasRecovery'] as bool? ?? false;
      _hint = state['hint'] as String? ?? '';
      _unconfirmedEmail = state['emailUnconfirmedPattern'] as String? ?? '';
      _pendingResetDate = state['pendingResetDate'] as int? ?? 0;
      _loginEmailPattern = state['loginEmailPattern'] as String? ?? '';

      if (_unconfirmedEmail.isNotEmpty) {
        _2faLabel = 'On';
      } else if (_hasPassword!) {
        _2faLabel = 'On';
      } else {
        _2faLabel = 'Off';
      }
    });
  }

  Future<void> _fetchGlobalTTL() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final ttl = await engine.getDefaultHistoryTTL(accountId);
    if (!mounted) return;
    setState(() => _globalTTL = ttl);
  }

  Future<void> _loadPasscodeState() async {
    final dir = context.read<AppState>().configDir;
    if (dir.isEmpty) return;
    final file = File('$dir/local_passcode.json');
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() => _hasPasscode = (data['hash'] as String? ?? '').isNotEmpty);
      } catch (_) {
        if (mounted) setState(() => _hasPasscode = false);
      }
    } else {
      if (mounted) setState(() => _hasPasscode = false);
    }
  }

  Future<void> _fetchPasskeys() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final list = await engine.getPasskeyList(accountId);
    if (!mounted) return;
    setState(() {
      _passkeys = list;
      _passkeysLoaded = true;
    });
  }

  Future<void> _fetchBlockedCount() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final count = await engine.getBlockedUsersCount(accountId);
    if (!mounted) return;
    setState(() => _blockedCount = count);
  }

  Future<void> _fetchSessionsCount() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final count = await engine.getSessionsCount(accountId);
    if (!mounted) return;
    setState(() => _sessionsCount = count);
  }

  Future<void> _fetchAllPrivacy() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final result = await engine.getAllPrivacySettings(accountId);
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _privacySettings = result.map((k, v) =>
          MapEntry(k, v is Map<String, dynamic> ? v : <String, dynamic>{}));
        _privacyLoaded = true;
      });
    }
  }

  Future<void> _fetchMessagesPrivacy() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    final result = await engine.getMessagesPrivacy(accountId);
    if (!mounted) return;
    setState(() {
      _messagesPrivacyOption = result.option;
      _messagesChargeStars = result.chargeStars;
    });
  }

  Future<void> _fetchArchiveSettings() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    final result = await engine.getArchiveSettings(accountId);
    if (!mounted) return;
    setState(() {
      _archiveAndMute = result.archiveAndMute;
      _archiveKeepUnmuted = result.keepArchivedUnmuted;
      _archiveKeepFolders = result.keepArchivedFolders;
      _archiveLoaded = true;
    });
  }

  Future<void> _fetchAccountTTL() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    final days = await engine.getAccountTTL(accountId);
    if (!mounted) return;
    setState(() => _accountTTLDays = days);
  }

  Future<void> _fetchTopPeers() async {
    if (!mounted) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    final enabled = await engine.getTopPeersEnabled(accountId);
    if (!mounted) return;
    setState(() {
      _topPeersEnabled = enabled;
      _topPeersLoaded = true;
    });
  }

  String _messagesPrivacyLabel() {
    switch (_messagesPrivacyOption) {
      case 'contacts_premium': return 'Contacts & Premium';
      case 'charge_stars': return '⭐ $_messagesChargeStars';
      default: return 'Everyone';
    }
  }

  String _privacyLabel(String key) {
    final s = _privacySettings[key];
    if (s == null) return '...';
    final option = s['option'] as String? ?? 'everyone';
    final alwaysUsers = (s['always_users'] as List?)?.length ?? 0;
    final neverUsers = (s['never_users'] as List?)?.length ?? 0;
    final alwaysChats = (s['always_chats'] as List?)?.length ?? 0;
    final neverChats = (s['never_chats'] as List?)?.length ?? 0;
    final allowPremium = s['allow_premium'] as bool? ?? false;
    final alwaysCount = alwaysUsers + alwaysChats + (allowPremium ? 1 : 0);
    final neverCount = neverUsers + neverChats;

    String base;
    switch (option) {
      case 'everyone': base = 'Everyone'; break;
      case 'contacts': base = 'My Contacts'; break;
      case 'close_friends': base = 'Close Friends'; break;
      case 'nobody': base = 'Nobody'; break;
      default: base = option;
    }
    if (alwaysCount > 0 && neverCount > 0) {
      return '$base (+$alwaysCount, -$neverCount)';
    } else if (alwaysCount > 0) {
      return '$base (+$alwaysCount)';
    } else if (neverCount > 0) {
      return '$base (-$neverCount)';
    }
    return base;
  }

  String get _passkeysLabel {
    if (_passkeys.isEmpty) return 'Off';
    if (_passkeys.length == 1) return _passkeys[0]['name'] as String? ?? 'On';
    return '${_passkeys.length}';
  }

  void _openPasskeysManagement() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text(
          'Passkeys',
          style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: 320,
          child: _passkeys.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Text(
                    'You have no passkeys configured. Passkeys can be added through Telegram web or desktop apps.',
                    style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._passkeys.map((pk) {
                      final name = pk['name'] as String? ?? 'Passkey';
                      final createdAt = pk['created_at'] as int? ?? 0;
                      final pkId = pk['id'] as String? ?? '';
                      String dateStr = '';
                      if (createdAt > 0) {
                        final dt = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
                        dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.key, size: 20, color: subtextColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w600)),
                                  if (dateStr.isNotEmpty)
                                    Text('Added $dateStr', style: TextStyle(fontSize: 12, color: subtextColor)),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final confirm = await showDialog<bool>(
                                  context: ctx,
                                  builder: (c) => AlertDialog(
                                    backgroundColor: bgColor,
                                    title: Text('Remove Passkey', style: TextStyle(color: textColor)),
                                    content: Text('Remove "$name"?', style: TextStyle(color: subtextColor)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                                      TextButton(
                                        onPressed: () => Navigator.of(c).pop(true),
                                        child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true && accountId.isNotEmpty) {
                                  try {
                                    await engine.removePasskey(accountId, pkId);
                                    _fetchPasskeys();
                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      showTelegramToast(ctx, 'Failed to remove passkey: $e');
                                    }
                                  }
                                }
                              },
                              child: Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  void _openPasscodeLock() {
    final dir = context.read<AppState>().configDir;
    if (dir.isEmpty) return;

    if (_hasPasscode) {
      Navigator.of(context).push<void>(settingsPageRoute(
        _LocalPasscodeCheck(
          configDir: dir,
          onSuccess: () {
            Navigator.of(context).pushReplacement(settingsPageRoute(
              _LocalPasscodeManage(
                configDir: dir,
                onChanged: () {
                  _loadPasscodeState();
                  context.read<AppState>().localPasscodeChanged();
                },
              ),
            ));
          },
        ),
      )).then((_) => _loadPasscodeState());
    } else {
      Navigator.of(context).push<void>(settingsPageRoute(
        _LocalPasscodeCreate(
          configDir: dir,
          onCreated: () {
            _loadPasscodeState();
            context.read<AppState>().localPasscodeChanged();
            Navigator.of(context).pushReplacement(settingsPageRoute(
              _LocalPasscodeManage(
                configDir: dir,
                onChanged: () {
                  _loadPasscodeState();
                  context.read<AppState>().localPasscodeChanged();
                },
              ),
            ));
          },
        ),
      )).then((_) => _loadPasscodeState());
    }
  }

  String _formatTTL(int seconds) {
    if (seconds <= 0) return 'Off';
    if (seconds < 86400) return '${seconds ~/ 3600} hours';
    if (seconds == 86400) return '1 day';
    if (seconds == 604800) return '1 week';
    if (seconds == 2678400) return '1 month';
    final days = seconds ~/ 86400;
    if (days < 7) return '$days days';
    if (days < 30) return '${days ~/ 7} weeks';
    return '${days ~/ 30} months';
  }

  void _openGlobalTTL() {
    Navigator.of(context).push(settingsPageRoute(
      _GlobalTTLScreen(
        currentTTL: _globalTTL,
        onChanged: (newTTL) {
          setState(() => _globalTTL = newTTL);
        },
      ),
    ));
  }

  void _openTwoStepVerification() {
    if (_hasPassword == null) return;

    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;

    if (_unconfirmedEmail.isNotEmpty) {
      Navigator.of(context).push(settingsPageRoute(
        _CloudPasswordEmailConfirm(
          accountId: accountId,
          engine: engine,
          emailPattern: _unconfirmedEmail,
          onDone: () {
            _fetchPasswordState();
            Navigator.of(context).pop();
          },
        ),
      ));
    } else if (_hasPassword == true) {
      Navigator.of(context).push(settingsPageRoute(
        _CloudPasswordInput(
          accountId: accountId,
          engine: engine,
          mode: _CloudPasswordMode.check,
          hint: _hint,
          hasRecovery: _hasRecovery,
          pendingResetDate: _pendingResetDate,
          onSuccess: () => _fetchPasswordState(),
        ),
      ));
    } else {
      Navigator.of(context).push(settingsPageRoute(
        CloudPasswordStart(
          accountId: accountId,
          engine: engine,
          onPasswordSet: () => _fetchPasswordState(),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);
    final sectionTitleColor =
        isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final sections = <List<Widget>>[
      _buildSecuritySection(isDark, sectionTitleColor, textColor, subtextColor,
          accentColor, hoverBg),
      _buildPrivacySection(isDark, sectionTitleColor, textColor, subtextColor,
          accentColor, hoverBg),
      _buildArchiveAndMuteSection(
          isDark, textColor, subtextColor, accentColor, hoverBg),
      _buildBotsAndWebsitesSection(isDark, textColor, subtextColor, hoverBg),
      _buildConfirmationExtensionsSection(isDark, textColor, subtextColor,
          accentColor, hoverBg),
      _buildTopPeersSection(isDark, textColor, subtextColor, accentColor,
          hoverBg),
      _buildSelfDestructionSection(isDark, textColor, subtextColor, hoverBg),
    ];

    final children = <Widget>[];
    var first = true;
    for (final section in sections) {
      if (section.isEmpty) continue;
      if (!first) {
        children.add(const SizedBox(height: 7));
        children.add(Container(height: 1, color: dividerColor));
        children.add(const SizedBox(height: 7));
      }
      children.addAll(section);
      first = false;
    }
    if (children.isNotEmpty) {
      children.add(const SizedBox(height: 32));
    }

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
          'Privacy and Security',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: Scrollbar(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.zero,
          children: children,
        ),
      ),
    );
  }

  List<Widget> _buildSecuritySection(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
        child: Text(
          'Security',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      _PrivacyIconRow(
        icon: Icons.lock_outline,
        label: 'Two-Step Verification',
        rightLabel: _2faLabel,
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: _openTwoStepVerification,
      ),
      _PrivacyIconRow(
        icon: Icons.timer_outlined,
        label: 'Auto-Delete Messages',
        rightLabel: _formatTTL(_globalTTL),
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: _openGlobalTTL,
      ),
      _PrivacyIconRow(
        icon: Icons.lock,
        label: 'Local passcode',
        rightLabel: _hasPasscode ? 'On' : 'Off',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: _openPasscodeLock,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: _passkeysLoaded
            ? _PrivacyIconRow(
                icon: Icons.fingerprint,
                label: 'Passkeys',
                rightLabel: _passkeysLabel,
                textColor: textColor,
                subtextColor: subtextColor,
                hoverBg: hoverBg,
                onTap: _openPasskeysManagement,
              )
            : const SizedBox.shrink(),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: _loginEmailPattern.isNotEmpty
            ? _PrivacyIconRow(
                icon: Icons.email_outlined,
                label: 'Login Email',
                rightLabel: _loginEmailPattern,
                textColor: textColor,
                subtextColor: subtextColor,
                hoverBg: hoverBg,
                onTap: () => _showChangeLoginEmailDialog(),
              )
            : const SizedBox.shrink(),
      ),
      _PrivacyIconRow(
        icon: Icons.block,
        label: 'Blocked Users',
        rightLabel: _blockedCount < 0 ? '...' : (_blockedCount == 0 ? 'None' : '$_blockedCount'),
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {
          Navigator.of(context).push<void>(settingsPageRoute(
            const _BlockedUsersScreen(),
          )).then((_) => _fetchBlockedCount());
        },
      ),
      _PrivacyIconRow(
        icon: Icons.devices,
        label: 'Active Sessions',
        rightLabel: _sessionsCount < 0 ? '...' : '$_sessionsCount',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {
          Navigator.of(context).push(
            settingsPageRoute(const ActiveSessionsScreen()),
          );
        },
      ),
    ];
  }

  void _openPrivacyEditor(String key, String title, List<String> options) async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final current = _privacySettings[key];
    final currentOption = current?['option'] as String? ?? 'everyone';

    String? addedByPhoneOption;
    if (key == 'phone_number') {
      addedByPhoneOption = _privacySettings['added_by_phone']?['option'] as String? ?? 'everyone';
    }

    String? callsP2POption;
    if (key == 'calls') {
      callsP2POption = _privacySettings['calls_p2p']?['option'] as String? ?? 'everyone';
    }

    bool hideReadMarks = false;
    if (key == 'last_seen') {
      hideReadMarks = await engine.getHideReadMarks(accountId);
    }

    bool hasFallbackPhoto = false;
    if (key == 'profile_photo') {
      hasFallbackPhoto = await engine.hasFallbackPhoto(accountId);
    }

    bool hasBirthday = false;
    if (key == 'birthday') {
      try {
        final bd = await engine.getSelfBirthday(accountId);
        hasBirthday = bd.day > 0 && bd.month > 0;
      } catch (_) {}
    }

    final isPremium = appState.activeAccount?.isPremium ?? false;

    bool initialAllowPremium = false;
    if (key == 'chat_invite') {
      initialAllowPremium = current?['allow_premium'] as bool? ?? false;
    }

    bool giftShowIcon = true;
    bool giftAcceptLimited = true;
    bool giftAcceptUnlimited = true;
    bool giftAcceptUnique = true;
    bool giftAcceptFromChannels = true;
    bool giftAcceptPremium = true;
    if (key == 'gifts') {
      final gs = await engine.getGiftSettings(accountId);
      giftShowIcon = gs.showIcon;
      giftAcceptLimited = gs.acceptLimited;
      giftAcceptUnlimited = gs.acceptUnlimited;
      giftAcceptUnique = gs.acceptUnique;
      giftAcceptFromChannels = gs.acceptChannels;
      giftAcceptPremium = gs.acceptPremium;
    }

    List<String> alwaysUsers = [];
    List<String> neverUsers = [];
    final privacyDetail = await engine.getPrivacySetting(accountId, key);
    if (privacyDetail != null) {
      alwaysUsers = (privacyDetail['always_users'] as List<dynamic>?)?.cast<String>() ?? [];
      neverUsers = (privacyDetail['never_users'] as List<dynamic>?)?.cast<String>() ?? [];
    }

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => _EditPrivacyBox(
        title: title,
        privacyKey: key,
        options: options,
        currentOption: currentOption,
        accountId: accountId,
        engine: engine,
        userName: appState.activeAccount?.displayName ?? '',
        initialAddedByPhoneOption: addedByPhoneOption,
        initialCallsP2POption: callsP2POption,
        isPremium: isPremium,
        initialHideReadMarks: hideReadMarks,
        initialHasFallbackPhoto: hasFallbackPhoto,
        initialHasBirthday: hasBirthday,
        initialAllowPremium: initialAllowPremium,
        initialGiftShowIcon: giftShowIcon,
        initialGiftAcceptLimited: giftAcceptLimited,
        initialGiftAcceptUnlimited: giftAcceptUnlimited,
        initialGiftAcceptUnique: giftAcceptUnique,
        initialGiftAcceptFromChannels: giftAcceptFromChannels,
        initialGiftAcceptPremium: giftAcceptPremium,
        initialAlwaysUsers: alwaysUsers,
        initialNeverUsers: neverUsers,
        onSaved: (newOption, {String? addedByPhone, String? callsP2P}) {
          setState(() {
            _privacySettings[key] = {
              ...?_privacySettings[key],
              'option': newOption,
            };
            if (addedByPhone != null) {
              _privacySettings['added_by_phone'] = {
                ...?_privacySettings['added_by_phone'],
                'option': addedByPhone,
              };
            }
            if (callsP2P != null) {
              _privacySettings['calls_p2p'] = {
                ...?_privacySettings['calls_p2p'],
                'option': callsP2P,
              };
            }
          });
        },
      ),
    );
  }

  void _openMessagesPrivacyEditor() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final isPremium = appState.activeAccount?.isPremium ?? false;
    final config = await engine.getPaidMessagesConfig(accountId);

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => _MessagesPrivacyBox(
        currentOption: _messagesPrivacyOption,
        currentChargeStars: _messagesChargeStars,
        accountId: accountId,
        engine: engine,
        isPremium: isPremium,
        maxStars: config.maxStars,
        commissionPermille: config.commissionPermille,
        withdrawRate: config.withdrawRate,
        onSaved: (option, stars) {
          setState(() {
            _messagesPrivacyOption = option;
            _messagesChargeStars = stars;
          });
        },
      ),
    );
  }

  List<Widget> _buildPrivacySection(
    bool isDark,
    Color sectionTitleColor,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    const privacyItems = <Map<String, dynamic>>[
      {'key': 'phone_number', 'label': 'Phone Number', 'options': ['everyone', 'contacts', 'nobody']},
      {'key': 'last_seen', 'label': 'Last Seen & Online', 'options': ['everyone', 'contacts', 'close_friends', 'nobody']},
      {'key': 'profile_photo', 'label': 'Profile Photo', 'options': ['everyone', 'contacts', 'close_friends', 'nobody']},
      {'key': 'forwards', 'label': 'Forwarded Messages', 'options': ['everyone', 'contacts', 'close_friends', 'nobody']},
      {'key': 'calls', 'label': 'Calls', 'options': ['everyone', 'contacts', 'nobody']},
      {'key': 'voice_messages', 'label': 'Voice Messages', 'options': ['everyone', 'contacts', 'nobody']},
      {'key': 'birthday', 'label': 'Birthday', 'options': ['everyone', 'contacts', 'close_friends', 'nobody']},
      {'key': 'gifts', 'label': 'Gifts', 'options': ['everyone', 'contacts', 'close_friends', 'nobody']},
      {'key': 'about', 'label': 'Bio', 'options': ['everyone', 'contacts', 'nobody']},
      {'key': 'saved_music', 'label': 'Saved Music', 'options': ['everyone', 'contacts', 'nobody']},
      {'key': 'chat_invite', 'label': 'Groups & Channels', 'options': ['everyone', 'contacts', 'nobody']},
    ];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Text(
          'Privacy',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: sectionTitleColor,
          ),
        ),
      ),
      ...privacyItems.map((item) => _PrivacyRow(
        label: item['label'] as String,
        rightLabel: _privacyLabel(item['key'] as String),
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () => _openPrivacyEditor(
          item['key'] as String,
          item['label'] as String,
          (item['options'] as List).cast<String>(),
        ),
      )),
      _PrivacyRow(
        label: 'Messages',
        rightLabel: _messagesPrivacyLabel(),
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: _openMessagesPrivacyEditor,
      ),
    ];
  }

  void _toggleArchiveAndMute(bool newVal) {
    setState(() => _archiveAndMute = newVal);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId.isNotEmpty) {
      engine.setArchiveSettings(
        accountId,
        archiveAndMute: newVal,
        keepArchivedUnmuted: _archiveKeepUnmuted,
        keepArchivedFolders: _archiveKeepFolders,
      );
    }
  }

  List<Widget> _buildArchiveAndMuteSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    if (!_archiveLoaded) return [];
    return [
      InkWell(
        onTap: () => _toggleArchiveAndMute(!_archiveAndMute),
        hoverColor: hoverBg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Archive and Mute',
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
              SizedBox(
                width: 36,
                height: 20,
                child: IgnorePointer(
                  child: Switch(
                    value: _archiveAndMute,
                    onChanged: (_) {},
                    activeColor: accentColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
        child: Text(
          'Automatically archive and mute new chats from non-contacts.',
          style: TextStyle(fontSize: 13, color: subtextColor),
        ),
      ),
    ];
  }

  List<Widget> _buildBotsAndWebsitesSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color hoverBg,
  ) {
    return [
      InkWell(
        onTap: () => _showClearPaymentInfoBox(isDark),
        hoverColor: hoverBg,
        child: Padding(
          padding: SettingsStyle.noIconPadding,
          child: Text(
            'Clear Payment and Shipping Info',
            style: TextStyle(fontSize: 14, color: textColor),
          ),
        ),
      ),
    ];
  }

  Future<void> _showClearPaymentInfoBox(bool isDark) async {
    final result = await showDialog<({bool credentials, bool shipping})>(
      context: context,
      builder: (ctx) => _ClearPaymentInfoBox(isDark: isDark),
    );
    if (result == null) return;
    if (!result.credentials && !result.shipping) return;

    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId.isEmpty) return;

    try {
      await engine.clearPaymentInfo(
        accountId,
        clearCredentials: result.credentials,
        clearShipping: result.shipping,
      );
      if (!mounted) return;
      showTelegramToast(context, 'Payment info cleared.');
    } catch (e) {
      if (!mounted) return;
      showTelegramToast(context, 'Failed to clear: $e');
    }
  }

  List<Widget> _buildConfirmationExtensionsSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
        child: Text(
          'File Confirmations',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF6C7883) : const Color(0xFF999999),
          ),
        ),
      ),
      InkWell(
        onTap: () => _openFileExtensionsDialog(),
        hoverColor: hoverBg,
        child: Padding(
          padding: SettingsStyle.noIconPadding,
          child: Text(
            'No-Warning Extensions',
            style: TextStyle(fontSize: 14, color: textColor),
          ),
        ),
      ),
      InkWell(
        onTap: () {
          final appState = context.read<AppState>();
          appState.setShowIpInWebRtcCalls(!appState.showIpInWebRtcCalls);
        },
        hoverColor: hoverBg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Show IP in WebRTC calls',
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
              SizedBox(
                width: 36,
                height: 20,
                child: Switch(
                  value: context.watch<AppState>().showIpInWebRtcCalls,
                  onChanged: (v) {
                    context.read<AppState>().setShowIpInWebRtcCalls(v);
                  },
                  activeColor: accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  void _openFileExtensionsDialog() {
    final appState = context.read<AppState>();
    final currentExts = appState.noWarningExtensions.join(' ');
    final controller = TextEditingController(text: currentExts);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
        title: Text('No-Warning Extensions', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter file extensions (space-separated) that should open without a confirmation dialog.',
                style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                maxLength: 10240,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText: 'txt log md pdf',
                  hintStyle: TextStyle(color: subtextColor),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.substring(0, controller.text.length.clamp(0, 10240));
              final extsList = text.split(' ')
                  .where((s) => s.isNotEmpty)
                  .take(1024)
                  .toSet();
              appState.setNoWarningExtensions(extsList);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showChangeLoginEmailDialog() {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

    final passwordController = TextEditingController();
    final emailController = TextEditingController();
    var errorText = '';
    var isBusy = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (stateCtx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
          title: Text('Change Login Email', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current login email: $_loginEmailPattern',
                  style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    labelStyle: TextStyle(color: subtextColor),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    labelText: 'New email',
                    labelStyle: TextStyle(color: subtextColor),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(errorText, style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isBusy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isBusy ? null : () async {
                final password = passwordController.text.trim();
                final email = emailController.text.trim();
                if (password.isEmpty) {
                  setDialogState(() => errorText = 'Please enter your current password.');
                  return;
                }
                if (email.isEmpty || !email.contains('@')) {
                  setDialogState(() => errorText = 'Please enter a valid email address.');
                  return;
                }
                setDialogState(() { isBusy = true; errorText = ''; });
                try {
                  await engine.setCloudPasswordEmail(
                    accountId,
                    currentPassword: password,
                    email: email,
                  ).timeout(const Duration(seconds: 30));
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _fetchPasswordState();
                } on TimeoutException {
                  setDialogState(() { errorText = 'Request timed out. Please try again.'; isBusy = false; });
                } catch (e) {
                  final msg = e.toString();
                  if (msg.contains('FLOOD')) {
                    setDialogState(() { errorText = 'Too many attempts. Please try again later.'; isBusy = false; });
                  } else if (msg.contains('PASSWORD_HASH_INVALID') || msg.contains('INVALID')) {
                    setDialogState(() { errorText = 'Incorrect password.'; isBusy = false; });
                  } else if (msg.contains('EMAIL_INVALID')) {
                    setDialogState(() { errorText = 'Invalid email address.'; isBusy = false; });
                  } else {
                    setDialogState(() { errorText = 'Failed: ${e.toString().replaceAll('Exception: ', '')}'; isBusy = false; });
                  }
                }
              },
              child: isBusy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: accentColor))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleTopPeers(bool newVal) {
    setState(() => _topPeersEnabled = newVal);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId.isNotEmpty) {
      engine.toggleTopPeers(accountId, newVal);
    }
  }

  List<Widget> _buildTopPeersSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [
      InkWell(
        onTap: () => _toggleTopPeers(!_topPeersEnabled),
        hoverColor: hoverBg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Suggest Frequent Contacts',
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
              SizedBox(
                width: 36,
                height: 20,
                child: IgnorePointer(
                  child: Switch(
                    value: _topPeersEnabled,
                    onChanged: (_) {},
                    activeColor: accentColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
        child: Text(
          'Display people you message frequently at the top of the search section for quick access.',
          style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
        ),
      ),
    ];
  }

  String _formatAccountTTL(int days) {
    if (days <= 0) return '...';
    if (days <= 31) return '1 month';
    if (days <= 92) return '3 months';
    if (days <= 183) return '6 months';
    if (days <= 366) return '12 months';
    if (days <= 549) return '18 months';
    return '24 months';
  }

  List<Widget> _buildSelfDestructionSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color hoverBg,
  ) {
    return [
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
        child: Text(
          'Delete my account',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF6C7883) : const Color(0xFF999999),
          ),
        ),
      ),
      InkWell(
        onTap: _openSelfDestructionBox,
        hoverColor: hoverBg,
        child: Padding(
          padding: SettingsStyle.noIconPadding,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'If away for...',
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
              Text(
                _formatAccountTTL(_accountTTLDays),
                style: TextStyle(fontSize: 14, color: subtextColor),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
        child: Text(
          'If you do not come online at least once within this period, your account will be deleted along with all groups, messages and contacts.',
          style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
        ),
      ),
    ];
  }

  void _openSelfDestructionBox() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

    final options = <int>[30, 90, 180, 365, 548, 720];
    final labels = <String>[
      '1 month', '3 months', '6 months',
      '12 months', '18 months', '24 months',
    ];

    int selected = _accountTTLDays;
    int closest = options.first;
    int minDist = (selected - closest).abs();
    for (final o in options) {
      final d = (selected - o).abs();
      if (d < minDist) {
        minDist = d;
        closest = o;
      }
    }
    selected = closest;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF17212B) : Colors.white,
          title: Text('Self-Destruction', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'If you do not come online at least once within this period, your account will be deleted along with all groups, messages and contacts.',
                  style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
                ),
                const SizedBox(height: 16),
                ...List.generate(options.length, (i) => RadioListTile<int>(
                  value: options[i],
                  groupValue: selected,
                  onChanged: (v) => setDialogState(() => selected = v!),
                  title: Text(labels[i], style: TextStyle(fontSize: 14, color: textColor)),
                  activeColor: accentColor,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() => _accountTTLDays = selected);
                final engine = context.read<EngineService>();
                final accountId = context.read<AppState>().activeAccountId;
                if (accountId.isNotEmpty) {
                  engine.setAccountTTL(accountId, selected);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animated icon widgets (§16.11) ──

class _AnimatedSettingsIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final Color? backgroundColor;

  const _AnimatedSettingsIcon({
    required this.icon,
    required this.size,
    required this.color,
    this.backgroundColor,
  });

  @override
  State<_AnimatedSettingsIcon> createState() => _AnimatedSettingsIconState();
}

class _AnimatedSettingsIconState extends State<_AnimatedSettingsIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.forward());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.backgroundColor ??
                    widget.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                size: widget.size * 0.48,
                color: widget.color,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InteractivePasswordIcon extends StatefulWidget {
  final TextEditingController textController;
  final double size;
  final Color color;
  final IconData icon;
  final IconData? activeIcon;

  const _InteractivePasswordIcon({
    required this.textController,
    required this.size,
    required this.color,
    required this.icon,
    this.activeIcon,
  });

  @override
  State<_InteractivePasswordIcon> createState() =>
      _InteractivePasswordIconState();
}

class _InteractivePasswordIconState extends State<_InteractivePasswordIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _hasText = widget.textController.text.isNotEmpty;
    widget.textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final nowHasText = widget.textController.text.isNotEmpty;
    if (nowHasText != _hasText) {
      _hasText = nowHasText;
      if (_hasText) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _hasText ? (widget.activeIcon ?? widget.icon) : widget.icon,
                key: ValueKey(_hasText),
                size: widget.size * 0.48,
                color: widget.color,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FireworksOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const _FireworksOverlay({required this.onComplete});

  @override
  State<_FireworksOverlay> createState() => _FireworksOverlayState();
}

class _FireworksOverlayState extends State<_FireworksOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _particles = List.generate(40, (_) => _Particle(rng));
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onComplete();
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _FireworksPainter(_particles, _ctrl.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double radius;
  final Color color;

  _Particle(math.Random rng)
      : angle = rng.nextDouble() * 2 * math.pi,
        speed = 80 + rng.nextDouble() * 200,
        radius = 2.0 + rng.nextDouble() * 3.0,
        color = [
            const Color(0xFFFF6B6B),
            const Color(0xFF4ECDC4),
            const Color(0xFFFFE66D),
            const Color(0xFF6C5CE7),
            const Color(0xFFA8E6CF),
            const Color(0xFF40A7E3),
          ][rng.nextInt(6)];
}

class _FireworksPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _FireworksPainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.35);
    final fadeOut = (1.0 - progress).clamp(0.0, 1.0);
    for (final p in particles) {
      final dist = p.speed * progress;
      final dx = center.dx + math.cos(p.angle) * dist;
      final dy = center.dy + math.sin(p.angle) * dist - 30 * progress;
      final paint = Paint()
        ..color = p.color.withValues(alpha: fadeOut * 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dx, dy), p.radius * (1.0 - progress * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) => old.progress != progress;
}

// ── Shared widgets ──

class _PrivacyIconRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String rightLabel;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _PrivacyIconRow({
    required this.icon,
    required this.label,
    required this.rightLabel,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.iconRowPadding,
        child: Row(
          children: [
            Icon(icon, size: 24, color: subtextColor),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: SettingsStyle.buttonFontSize,
                  color: textColor,
                ),
              ),
            ),
            Text(
              rightLabel,
              style: TextStyle(
                fontSize: 14,
                color: subtextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  final String label;
  final String rightLabel;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _PrivacyRow({
    required this.label,
    required this.rightLabel,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: SettingsStyle.noIconPadding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: SettingsStyle.buttonFontSize,
                  color: textColor,
                ),
              ),
            ),
            Text(
              rightLabel,
              style: TextStyle(
                fontSize: 14,
                color: subtextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── EditPrivacyBox Dialog ──

class _EditPrivacyBox extends StatefulWidget {
  final String title;
  final String privacyKey;
  final List<String> options;
  final String currentOption;
  final String accountId;
  final EngineService engine;
  final void Function(String newOption, {String? addedByPhone, String? callsP2P}) onSaved;
  final String? initialAddedByPhoneOption;
  final String? initialCallsP2POption;
  final bool isPremium;
  final bool initialHideReadMarks;
  final bool initialHasFallbackPhoto;
  final bool initialHasBirthday;

  final String userName;
  final bool initialAllowPremium;

  final bool initialGiftShowIcon;
  final bool initialGiftAcceptLimited;
  final bool initialGiftAcceptUnlimited;
  final bool initialGiftAcceptUnique;
  final bool initialGiftAcceptFromChannels;
  final bool initialGiftAcceptPremium;

  final List<String> initialAlwaysUsers;
  final List<String> initialNeverUsers;

  const _EditPrivacyBox({
    required this.title,
    required this.privacyKey,
    required this.options,
    required this.currentOption,
    required this.accountId,
    required this.engine,
    required this.onSaved,
    this.userName = '',
    this.initialAddedByPhoneOption,
    this.initialCallsP2POption,
    this.isPremium = false,
    this.initialHideReadMarks = false,
    this.initialHasFallbackPhoto = false,
    this.initialHasBirthday = false,
    this.initialAllowPremium = false,
    this.initialGiftShowIcon = true,
    this.initialGiftAcceptLimited = true,
    this.initialGiftAcceptUnlimited = true,
    this.initialGiftAcceptUnique = true,
    this.initialGiftAcceptFromChannels = true,
    this.initialGiftAcceptPremium = true,
    this.initialAlwaysUsers = const [],
    this.initialNeverUsers = const [],
  });

  @override
  State<_EditPrivacyBox> createState() => _EditPrivacyBoxState();
}

class _EditPrivacyBoxState extends State<_EditPrivacyBox> {
  late String _selected;
  late String _addedByPhoneOption;
  late String _callsP2POption;
  late bool _hideReadMarks;
  late bool _hasFallbackPhoto;
  bool _saving = false;
  bool _confirmedRestriction = false;
  bool _uploadingFallback = false;

  late bool _hasBirthday;

  bool get _isPhoneNumber => widget.privacyKey == 'phone_number';
  bool get _isLastSeen => widget.privacyKey == 'last_seen';
  bool get _isProfilePhoto => widget.privacyKey == 'profile_photo';
  bool get _isForwards => widget.privacyKey == 'forwards';
  bool get _isCalls => widget.privacyKey == 'calls';
  bool get _isVoiceMessages => widget.privacyKey == 'voice_messages';
  bool get _isBirthday => widget.privacyKey == 'birthday';
  bool get _isGifts => widget.privacyKey == 'gifts';
  bool get _isChatInvite => widget.privacyKey == 'chat_invite';

  late bool _allowPremium;

  late bool _giftShowIcon;
  late bool _giftAcceptLimited;
  late bool _giftAcceptUnlimited;
  late bool _giftAcceptUnique;
  late bool _giftAcceptFromChannels;
  late bool _giftAcceptPremium;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentOption;
    _addedByPhoneOption = widget.initialAddedByPhoneOption ?? 'everyone';
    _callsP2POption = widget.initialCallsP2POption ?? 'everyone';
    _hideReadMarks = widget.initialHideReadMarks;
    _hasFallbackPhoto = widget.initialHasFallbackPhoto;
    _hasBirthday = widget.initialHasBirthday;
    _allowPremium = widget.initialAllowPremium;
    _confirmedRestriction = widget.currentOption != 'everyone';
    _giftShowIcon = widget.initialGiftShowIcon;
    _giftAcceptLimited = widget.initialGiftAcceptLimited;
    _giftAcceptUnlimited = widget.initialGiftAcceptUnlimited;
    _giftAcceptUnique = widget.initialGiftAcceptUnique;
    _giftAcceptFromChannels = widget.initialGiftAcceptFromChannels;
    _giftAcceptPremium = widget.initialGiftAcceptPremium;
  }

  String _optionLabel(String opt) {
    switch (opt) {
      case 'everyone': return 'Everyone';
      case 'contacts': return 'My Contacts';
      case 'close_friends': return 'Close Friends';
      case 'nobody': return 'Nobody';
      default: return opt;
    }
  }

  String _forwardTooltipText() {
    switch (_selected) {
      case 'everyone':
        return 'Users who forward your messages will have a link to your profile added to the message.';
      case 'nobody':
        return 'Users who forward your messages will have your name displayed, but it won\'t be clickable.';
      default:
        return 'Users who forward your messages will have a clickable link, but only your contacts will be able to open your profile.';
    }
  }

  Widget _buildForwardPreview(bool isDark, Color textColor, Color subtextColor) {
    final name = widget.userName.isNotEmpty ? widget.userName : 'You';
    final bubbleBg = isDark
        ? const Color(0xFF2B5278)
        : const Color(0xFFEFFDDE);
    final fwdColor = isDark
        ? const Color(0xFF6BBFFF)
        : const Color(0xFF3A8BD1);
    final bodyColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);

    const toastBg = Color(0xB2000000);
    const toastFg = Color(0xFFFFFFFF);
    const arrowSize = 7.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: bubbleBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(6),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Forwarded from $name',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: fwdColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This is how your forwarded messages will look.',
                  style: TextStyle(fontSize: 14, color: bodyColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Column(
                children: [
                  CustomPaint(
                    size: const Size(arrowSize * 2, arrowSize),
                    painter: _TooltipArrowPainter(color: toastBg),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    decoration: BoxDecoration(
                      color: toastBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      _forwardTooltipText(),
                      style: const TextStyle(fontSize: 12, color: toastFg, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    try {
      await widget.engine.updateBirthday(
        widget.accountId, picked.day, picked.month, picked.year,
      );
      if (mounted) {
        setState(() => _hasBirthday = true);
        showTelegramToast(context, 'Birthday saved');
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to set birthday: $e');
      }
    }
  }

  Future<void> _save() async {
    if (_isLastSeen && _selected != 'everyone' && !_confirmedRestriction && widget.currentOption == 'everyone') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final isDark = theme.brightness == Brightness.dark;
          final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
          final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
          final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
          final accentColor = context.palette.windowBgActive;
          return Dialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 364),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Seen & Online',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'By restricting who can see your Last Seen, you won\'t be able to see other people\'s Last Seen unless they share it with you. You will still see approximate last seen.',
                      style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text('Cancel', style: TextStyle(color: accentColor)),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text('Continue', style: TextStyle(color: accentColor)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (confirmed != true) return;
      _confirmedRestriction = true;
    }

    setState(() => _saving = true);
    try {
      await widget.engine.setPrivacySetting(
        widget.accountId,
        widget.privacyKey,
        _selected,
        allowPremium: _isChatInvite && _allowPremium,
      );
      if (_isPhoneNumber && _selected == 'nobody') {
        await widget.engine.setPrivacySetting(
          widget.accountId,
          'added_by_phone',
          _addedByPhoneOption,
        );
      }
      if (_isCalls) {
        await widget.engine.setPrivacySetting(
          widget.accountId,
          'calls_p2p',
          _callsP2POption,
        );
      }
      if (_isLastSeen && _hideReadMarks != widget.initialHideReadMarks) {
        await widget.engine.setHideReadMarks(widget.accountId, hide: _hideReadMarks);
      }
      if (_isGifts) {
        await widget.engine.setGiftSettings(
          widget.accountId,
          showIcon: _giftShowIcon,
          acceptLimited: _giftAcceptLimited,
          acceptUnlimited: _giftAcceptUnlimited,
          acceptUnique: _giftAcceptUnique,
          acceptChannels: _giftAcceptFromChannels,
          acceptPremium: _giftAcceptPremium,
        );
      }
      widget.onSaved(
        _selected,
        addedByPhone: _isPhoneNumber ? _addedByPhoneOption : null,
        callsP2P: _isCalls ? _callsP2POption : null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickFallbackPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    if (!mounted) return;

    setState(() => _uploadingFallback = true);
    try {
      await widget.engine.uploadFallbackPhoto(widget.accountId, path);
      if (mounted) {
        final hasPhoto = await widget.engine.hasFallbackPhoto(widget.accountId);
        if (mounted) {
          setState(() {
            _hasFallbackPhoto = hasPhoto;
            _uploadingFallback = false;
          });
          showTelegramToast(context, 'Public photo updated');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingFallback = false);
        showTelegramToast(context, 'Failed to set public photo: $e');
      }
    }
  }

  Future<void> _removeFallbackPhoto() async {
    setState(() => _uploadingFallback = true);
    try {
      await widget.engine.deleteFallbackPhoto(widget.accountId);
      if (mounted) {
        final hasPhoto = await widget.engine.hasFallbackPhoto(widget.accountId);
        if (mounted) {
          setState(() {
            _hasFallbackPhoto = hasPhoto;
            _uploadingFallback = false;
          });
          showTelegramToast(context, 'Public photo removed');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingFallback = false);
        showTelegramToast(context, 'Failed to remove public photo: $e');
      }
    }
  }

  Widget _buildPremiumLockedToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isPremium,
    required Color hoverBg,
    required Color textColor,
    required Color subtextColor,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: () {
        if (!isPremium) {
          showTelegramToast(context, 'Subscribe to Telegram Premium to change gift settings.');
        } else {
          onChanged(!value);
        }
      },
      hoverColor: hoverBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            if (!isPremium)
              Icon(Icons.lock, size: 14, color: subtextColor)
            else
              SizedBox(
                width: 36,
                height: 20,
                child: Switch(
                  value: value,
                  onChanged: (v) => onChanged(v),
                  activeColor: accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final warningColor = isDark ? const Color(0xFFE8A63B) : const Color(0xFFC57518);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, minWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
              child: Text(
                _isForwards
                    ? 'Who can add a link to your account when forwarding your messages?'
                    : _isVoiceMessages
                        ? 'Who can send you voice messages?'
                        : _isGifts
                            ? 'Who can send you gifts with auto-save?'
                            : _isChatInvite
                                ? 'Who can add you to group chats and channels?'
                                : 'Who can see your ${widget.title.toLowerCase()}?',
                style: TextStyle(fontSize: 13, color: subtextColor),
              ),
            ),
            if (_isForwards) _buildForwardPreview(isDark, textColor, subtextColor),
            if (_isBirthday && !_hasBirthday)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: GestureDetector(
                  onTap: _pickBirthday,
                  child: Text(
                    'Set your birthday',
                    style: TextStyle(
                      fontSize: 13,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            if (_isGifts) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              _buildPremiumLockedToggle(
                label: 'Show gift button in input',
                value: _giftShowIcon,
                onChanged: (v) => setState(() => _giftShowIcon = v),
                isPremium: widget.isPremium,
                hoverBg: hoverBg,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
            ],
            const SizedBox(height: 4),
            ...widget.options.map((opt) {
              final isPremiumLocked = _isVoiceMessages && !widget.isPremium && opt != 'everyone';
              return InkWell(
                onTap: () {
                  if (isPremiumLocked) {
                    setState(() => _selected = 'everyone');
                    showTelegramToast(context, 'Subscribe to Telegram Premium to restrict who can send you voice messages.');
                  } else {
                    setState(() => _selected = opt);
                  }
                },
                hoverColor: hoverBg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Radio<String>(
                          value: opt,
                          groupValue: _selected,
                          onChanged: (v) {
                            if (v != null) {
                              if (isPremiumLocked) {
                                setState(() => _selected = 'everyone');
                                showTelegramToast(context, 'Subscribe to Telegram Premium to restrict who can send you voice messages.');
                              } else {
                                setState(() => _selected = v);
                              }
                            }
                          },
                          activeColor: accentColor,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _optionLabel(opt),
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                      if (isPremiumLocked)
                        Icon(Icons.lock, size: 16, color: subtextColor),
                    ],
                  ),
                ),
              );
            }),
            if (_isGifts) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
                child: Text(
                  'Accepted Types',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              _buildPremiumLockedToggle(
                label: 'Limited',
                value: _giftAcceptLimited,
                onChanged: (v) => setState(() => _giftAcceptLimited = v),
                isPremium: widget.isPremium,
                hoverBg: hoverBg,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
              ),
              _buildPremiumLockedToggle(
                label: 'Unlimited',
                value: _giftAcceptUnlimited,
                onChanged: (v) => setState(() => _giftAcceptUnlimited = v),
                isPremium: widget.isPremium,
                hoverBg: hoverBg,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
              ),
              _buildPremiumLockedToggle(
                label: 'Unique',
                value: _giftAcceptUnique,
                onChanged: (v) => setState(() => _giftAcceptUnique = v),
                isPremium: widget.isPremium,
                hoverBg: hoverBg,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
              ),
              _buildPremiumLockedToggle(
                label: 'From Channels',
                value: _giftAcceptFromChannels,
                onChanged: (v) => setState(() => _giftAcceptFromChannels = v),
                isPremium: widget.isPremium,
                hoverBg: hoverBg,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
              ),
              _buildPremiumLockedToggle(
                label: 'Premium',
                value: _giftAcceptPremium,
                onChanged: (v) => setState(() => _giftAcceptPremium = v),
                isPremium: widget.isPremium,
                hoverBg: hoverBg,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
              ),
            ],
            if (_isCalls) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
                child: Text(
                  'Peer-to-Peer',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  showDialog<String>(
                    context: context,
                    builder: (ctx) => _P2PPrivacyBox(
                      currentOption: _callsP2POption,
                      accentColor: accentColor,
                    ),
                  ).then((result) {
                    if (result != null) {
                      setState(() => _callsP2POption = result);
                    }
                  });
                },
                hoverColor: hoverBg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
                  child: Row(
                    children: [
                      Icon(Icons.language, size: 20, color: subtextColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Peer-to-Peer',
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                      Text(
                        _optionLabel(_callsP2POption),
                        style: TextStyle(fontSize: 14, color: subtextColor),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 18, color: subtextColor),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                child: Text(
                  'Disabling peer-to-peer will route voice calls through Telegram servers to avoid revealing your IP address, but will slightly decrease audio quality.',
                  style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4),
                ),
              ),
            ],
            if (_isProfilePhoto) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
                child: SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: TextButton(
                    onPressed: _uploadingFallback ? null : _pickFallbackPhoto,
                    style: TextButton.styleFrom(
                      foregroundColor: accentColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: _uploadingFallback
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                        )
                      : Text(
                          _hasFallbackPhoto ? 'Update Public Photo' : 'Set Public Photo',
                          style: const TextStyle(fontSize: 14),
                        ),
                  ),
                ),
              ),
              if (_hasFallbackPhoto)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                  child: SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: TextButton(
                      onPressed: _uploadingFallback ? null : _removeFallbackPhoto,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE53935),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text(
                        'Remove Public Photo',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
            ],
            if (_isPhoneNumber && _selected == 'nobody') ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
                child: Text(
                  'Who can find me by my number?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 2, 22, 4),
                child: Text(
                  'Users who have your number saved in their contacts will see it on Telegram only if you add them to "Always Allow".',
                  style: TextStyle(fontSize: 13, color: subtextColor),
                ),
              ),
              ...['everyone', 'contacts'].map((opt) {
                return InkWell(
                  onTap: () => setState(() => _addedByPhoneOption = opt),
                  hoverColor: hoverBg,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Radio<String>(
                            value: opt,
                            groupValue: _addedByPhoneOption,
                            onChanged: (v) {
                              if (v != null) setState(() => _addedByPhoneOption = v);
                            },
                            activeColor: accentColor,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          _optionLabel(opt),
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            if (_isPhoneNumber && _selected != 'nobody') ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: warningColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Users who add your phone number to their contacts will be able to see it and find you on Telegram.',
                        style: TextStyle(fontSize: 13, color: warningColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_isLastSeen) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              InkWell(
                onTap: () => setState(() => _hideReadMarks = !_hideReadMarks),
                hoverColor: hoverBg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Hide Read Time',
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        height: 20,
                        child: Switch(
                          value: _hideReadMarks,
                          onChanged: (v) => setState(() => _hideReadMarks = v),
                          activeColor: accentColor,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                child: Text(
                  'If enabled, other users won\'t be able to see when you read their messages.',
                  style: TextStyle(fontSize: 12, color: subtextColor),
                ),
              ),
            ],
            if (_isLastSeen && !widget.isPremium) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
                child: Row(
                  children: [
                    Icon(Icons.star, size: 18, color: const Color(0xFFFFA726)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Subscribe to Telegram Premium to hide your online status and read time from specific users.',
                        style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
              child: Divider(height: 1, color: dividerColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
              child: Text(
                _isChatInvite
                    ? 'You can add users or groups who will always or never be able to add you to groups and channels, regardless of the setting above.'
                    : 'You can add users or groups who will always or never be able to see your ${widget.title.toLowerCase()}, regardless of the setting above.',
                style: TextStyle(fontSize: 13, color: subtextColor),
              ),
            ),
            if (_isChatInvite) ...[
              InkWell(
                onTap: () => setState(() => _allowPremium = !_allowPremium),
                hoverColor: hoverBg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
                  child: Row(
                    children: [
                      Icon(Icons.star, size: 18, color: const Color(0xFFFFA726)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Always Allow Premium Users',
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        height: 20,
                        child: Switch(
                          value: _allowPremium,
                          onChanged: (v) => setState(() => _allowPremium = v),
                          activeColor: accentColor,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: accentColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: accentColor,
                          ),
                        )
                      : Text('Save', style: TextStyle(color: accentColor)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TooltipArrowPainter extends CustomPainter {
  final Color color;
  _TooltipArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TooltipArrowPainter old) => old.color != color;
}

// ── P2P Privacy Box (second-level dialog for Calls) ──

class _P2PPrivacyBox extends StatefulWidget {
  final String currentOption;
  final Color accentColor;

  const _P2PPrivacyBox({
    required this.currentOption,
    required this.accentColor,
  });

  @override
  State<_P2PPrivacyBox> createState() => _P2PPrivacyBoxState();
}

class _P2PPrivacyBoxState extends State<_P2PPrivacyBox> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentOption;
  }

  String _optionLabel(String opt) {
    switch (opt) {
      case 'everyone': return 'Everyone';
      case 'contacts': return 'My Contacts';
      case 'nobody': return 'Nobody';
      default: return opt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = widget.accentColor;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    const options = ['everyone', 'contacts', 'nobody'];

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, minWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Text(
                'Peer-to-Peer',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
              child: Text(
                'Who can use peer-to-peer with you in calls?',
                style: TextStyle(fontSize: 13, color: subtextColor),
              ),
            ),
            const SizedBox(height: 4),
            ...options.map((opt) {
              return InkWell(
                onTap: () => setState(() => _selected = opt),
                hoverColor: hoverBg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Radio<String>(
                          value: opt,
                          groupValue: _selected,
                          onChanged: (v) {
                            if (v != null) setState(() => _selected = v);
                          },
                          activeColor: accentColor,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _optionLabel(opt),
                        style: TextStyle(fontSize: 14, color: textColor),
                      ),
                    ],
                  ),
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
              child: Text(
                'Disabling peer-to-peer will route voice calls through Telegram servers to avoid revealing your IP address, but will slightly decrease audio quality.',
                style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: accentColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text('Save', style: TextStyle(color: accentColor)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cloud Password Mode Enum ──

enum _CloudPasswordMode { check, create, change, recover }

enum _ForgotPasswordAction { recover, cancelReset, reset }

// ── CloudPasswordStart: Intro screen when no password set ──

class CloudPasswordStart extends StatelessWidget {
  final String accountId;
  final EngineService engine;
  final VoidCallback onPasswordSet;

  const CloudPasswordStart({
    required this.accountId,
    required this.engine,
    required this.onPasswordSet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
        title: Text(
          'Two-Step Verification',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedSettingsIcon(
                icon: Icons.lock_outline,
                size: 100,
                color: accentColor,
              ),
              const SizedBox(height: 19),
              Text(
                'Two-Step Verification',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),
              Text(
                'Set an additional password that will be required to log in to your Telegram account.',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              const SizedBox(height: 61),
              const SizedBox(height: 61),
              const SizedBox(height: 19),
              SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(settingsPageRoute(
                      _CloudPasswordInput(
                        accountId: accountId,
                        engine: engine,
                        mode: _CloudPasswordMode.create,
                        hint: '',
                        hasRecovery: false,
                        pendingResetDate: 0,
                        onSuccess: onPasswordSet,
                      ),
                    ));
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Set Password', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CloudPasswordInput: Password entry/create/change screen ──

class _CloudPasswordInput extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final _CloudPasswordMode mode;
  final String hint;
  final bool hasRecovery;
  final int pendingResetDate;
  final VoidCallback onSuccess;
  final String? currentPassword;
  final String? recoveryCode;

  const _CloudPasswordInput({
    required this.accountId,
    required this.engine,
    required this.mode,
    required this.hint,
    required this.hasRecovery,
    required this.pendingResetDate,
    required this.onSuccess,
    this.currentPassword,
    this.recoveryCode,
  });

  @override
  State<_CloudPasswordInput> createState() => _CloudPasswordInputState();
}

class _CloudPasswordInputState extends State<_CloudPasswordInput> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _obscureConfirm = true;
  String _error = '';
  bool _loading = false;
  late _ForgotPasswordAction _forgotAction;
  int _pendingResetDate = 0;
  String _countdownText = '';
  Timer? _countdownTimer;
  int _srpIdInvalidCount = 0;
  DateTime? _lastSrpIdInvalid;

  bool get _isCreateMode => widget.mode == _CloudPasswordMode.create || widget.mode == _CloudPasswordMode.change || widget.mode == _CloudPasswordMode.recover;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_clearError);
    _confirmController.addListener(_clearError);
    _pendingResetDate = widget.pendingResetDate;
    _forgotAction = _pendingResetDate > 0 ? _ForgotPasswordAction.cancelReset : _ForgotPasswordAction.recover;
    if (_pendingResetDate > 0) _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) => _passwordFocus.requestFocus());
  }

  void _clearError() {
    if (_error.isNotEmpty) setState(() => _error = '');
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _updateCountdownText();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCountdownText());
  }

  void _updateCountdownText() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = _pendingResetDate - now;
    if (remaining <= 0) {
      _countdownTimer?.cancel();
      setState(() {
        _forgotAction = _ForgotPasswordAction.reset;
        _countdownText = '';
      });
      return;
    }
    setState(() => _countdownText = _formatDuration(remaining));
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h < 24) return m > 0 ? '${h}h ${m}m' : '${h}h';
    final d = h ~/ 24;
    final rh = h % 24;
    return rh > 0 ? '${d}d ${rh}h' : '${d}d';
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _passwordController.removeListener(_clearError);
    _confirmController.removeListener(_clearError);
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Please enter a password');
      return;
    }

    if (_isCreateMode) {
      final confirm = _confirmController.text;
      if (confirm.isEmpty) {
        setState(() => _error = 'Please re-enter your password');
        return;
      }
      if (password != confirm) {
        setState(() => _error = 'Passwords do not match');
        return;
      }
      Navigator.of(context).pushReplacement(settingsPageRoute(
        _CloudPasswordHint(
          accountId: widget.accountId,
          engine: widget.engine,
          newPassword: password,
          currentPassword: widget.currentPassword ?? '',
          onSuccess: widget.onSuccess,
          recoveryCode: widget.recoveryCode,
        ),
      ));
      return;
    }

    setState(() { _loading = true; _error = ''; });
    try {
      await widget.engine.checkCloudPassword(widget.accountId, password);
      if (!mounted) return;
      if (_pendingResetDate > 0) {
        try { await widget.engine.cancelResetPassword(widget.accountId); } catch (_) {}
      }
      setState(() => _loading = false);
      Navigator.of(context).pushReplacement(settingsPageRoute(
        _CloudPasswordDone(
          accountId: widget.accountId,
          engine: widget.engine,
          message: 'Password confirmed!',
          currentPassword: password,
          onDone: widget.onSuccess,
          navigateToManage: true,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString();
      if (errMsg.contains('SRP_ID_INVALID')) {
        final now = DateTime.now();
        if (_lastSrpIdInvalid != null && now.difference(_lastSrpIdInvalid!).inSeconds < 60) {
          _srpIdInvalidCount++;
        } else {
          _srpIdInvalidCount = 1;
        }
        _lastSrpIdInvalid = now;
        if (_srpIdInvalidCount >= 2) {
          setState(() { _loading = false; _error = 'Server error. Please try again later.'; });
        } else {
          await _submit();
          return;
        }
      } else {
        setState(() {
          _loading = false;
          if (errMsg.contains('PASSWORD_HASH_INVALID') || errMsg.contains('SRP_PASSWORD_CHANGED')) {
            _error = 'Wrong password!';
            _passwordController.selection = TextSelection(baseOffset: 0, extentOffset: _passwordController.text.length);
          } else if (errMsg.contains('FLOOD_WAIT')) {
            _error = 'Too many attempts. Please try again later.';
          } else {
            _error = errMsg.replaceFirst('Exception: ', '');
          }
        });
      }
    }
  }

  Future<void> _disablePassword() async {
    if (widget.recoveryCode == null) return;
    setState(() { _loading = true; _error = ''; });
    try {
      await widget.engine.recoverPasswordWithCode(widget.accountId, code: widget.recoveryCode!);
      if (!mounted) return;
      widget.onSuccess();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == 'privacy');
      showTelegramToast(context, 'Cloud password has been removed.');
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _onForgotPassword() async {
    switch (_forgotAction) {
      case _ForgotPasswordAction.recover:
        await _handleRecover();
      case _ForgotPasswordAction.cancelReset:
        await _handleCancelReset();
      case _ForgotPasswordAction.reset:
        await _handleReset();
    }
  }

  Future<void> _handleRecover() async {
    if (widget.hasRecovery) {
      setState(() { _loading = true; _error = ''; });
      try {
        final emailPattern = await widget.engine.requestPasswordRecovery(widget.accountId);
        if (!mounted) return;
        setState(() => _loading = false);
        Navigator.of(context).push(settingsPageRoute(
          _CloudPasswordEmailConfirm(
            accountId: widget.accountId,
            engine: widget.engine,
            emailPattern: emailPattern,
            isRecovery: true,
            onDone: () {
              widget.onSuccess();
              Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == 'privacy');
            },
          ),
        ));
      } catch (e) {
        if (!mounted) return;
        setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
      }
    } else {
      await _showResetNoEmailConfirm();
    }
  }

  Future<void> _showResetNoEmailConfirm() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
        title: Text('Reset Password', style: TextStyle(color: textColor)),
        content: Text(
          'Since you haven\'t provided a recovery email when setting up your password, your remaining options are either to remember your password or to reset your account.',
          style: TextStyle(color: textColor, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _doResetPassword();
  }

  Future<void> _handleCancelReset() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
        title: Text('Cancel Reset', style: TextStyle(color: textColor)),
        content: Text('Are you sure you want to cancel the password reset?', style: TextStyle(color: textColor)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _loading = true; _error = ''; });
    try {
      await widget.engine.cancelResetPassword(widget.accountId);
      if (!mounted) return;
      _countdownTimer?.cancel();
      setState(() {
        _loading = false;
        _forgotAction = _ForgotPasswordAction.recover;
        _pendingResetDate = 0;
        _countdownText = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _handleReset() async {
    await _doResetPassword();
  }

  Future<void> _doResetPassword() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await widget.engine.resetPassword(widget.accountId);
      if (!mounted) return;
      if (result['done'] == true) {
        final state = await widget.engine.getCloudPasswordState(widget.accountId);
        if (!mounted) return;
        if (state == null || state['hasPassword'] != true) {
          widget.onSuccess();
          Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == 'privacy');
          showTelegramToast(context, 'Cloud password has been removed.');
          return;
        }
      }

      final untilDate = result['untilDate'] as int? ?? 0;
      final retryDate = result['retryDate'] as int? ?? 0;

      if (untilDate > 0) {
        setState(() {
          _loading = false;
          _pendingResetDate = untilDate;
          _forgotAction = _ForgotPasswordAction.cancelReset;
        });
        _startCountdown();
      } else if (retryDate > 0) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        var remaining = retryDate - now;
        if (remaining < 60) remaining = 60;
        setState(() {
          _loading = false;
          _error = 'You can reset your password in ${_formatDuration(remaining)}.';
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  String get _forgotLinkText {
    switch (_forgotAction) {
      case _ForgotPasswordAction.recover:
        return 'Forgot password?';
      case _ForgotPasswordAction.cancelReset:
        return 'Cancel Reset';
      case _ForgotPasswordAction.reset:
        return 'Reset Password';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final errorColor = isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);

    final title = 'Two-Step Verification';
    final String subtitle;
    final String description;
    if (widget.mode == _CloudPasswordMode.recover) {
      subtitle = 'Set New Password';
      description = 'Set a new password for your account, or disable it entirely.';
    } else if (_isCreateMode) {
      subtitle = widget.mode == _CloudPasswordMode.change ? 'Change Password' : 'Set Password';
      description = 'Please set an additional password to protect your account.';
    } else {
      subtitle = 'Enter your password';
      description = 'Your account is protected with an additional password.';
    }

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
        title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InteractivePasswordIcon(
                textController: _passwordController,
                size: 100,
                color: accentColor,
                icon: _isCreateMode ? Icons.lock_outline : Icons.vpn_key,
                activeIcon: _isCreateMode ? Icons.lock : Icons.vpn_key_outlined,
              ),
              const SizedBox(height: 19),
              Text(subtitle, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 5),
              Text(description, style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4), textAlign: TextAlign.center),
              const SizedBox(height: 15),
              SizedBox(
                width: 256,
                height: 61,
                child: Center(
                  child: TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscureText: _obscure,
                    onSubmitted: (_) => _isCreateMode ? FocusScope.of(context).nextFocus() : _submit(),
                    decoration: InputDecoration(
                      hintText: _isCreateMode ? 'Enter a password' : 'Current password',
                      hintStyle: TextStyle(color: subtextColor),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: subtextColor),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _error.isNotEmpty ? errorColor : subtextColor)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _error.isNotEmpty ? errorColor : accentColor, width: 2)),
                    ),
                    style: TextStyle(fontSize: 15, color: textColor),
                  ),
                ),
              ),
              if (_isCreateMode) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: 256,
                  height: 61,
                  child: Center(
                    child: TextField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: 'Re-enter your password',
                        hintStyle: TextStyle(color: subtextColor),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: subtextColor),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: subtextColor)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor, width: 2)),
                      ),
                      style: TextStyle(fontSize: 15, color: textColor),
                    ),
                  ),
                ),
              ],
              if (widget.mode == _CloudPasswordMode.recover) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : _disablePassword,
                  child: Text('Disable', style: TextStyle(fontSize: 14, color: accentColor)),
                ),
              ],
              if (!_isCreateMode) const SizedBox(height: 61),
              if (widget.hint.isNotEmpty && !_isCreateMode && _error.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 256,
                    child: Text('Hint: ${widget.hint}', style: TextStyle(fontSize: 13, color: subtextColor), textAlign: TextAlign.center),
                  ),
                ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 256,
                    child: Text(_error, style: TextStyle(fontSize: 13, color: errorColor), textAlign: TextAlign.center),
                  ),
                ),
              if (!_isCreateMode) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : _onForgotPassword,
                  child: Text(
                    _forgotLinkText,
                    style: TextStyle(
                      fontSize: 14,
                      color: _forgotAction == _ForgotPasswordAction.reset
                          ? (isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F))
                          : accentColor,
                    ),
                  ),
                ),
                if (_forgotAction == _ForgotPasswordAction.cancelReset && _countdownText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Password will be reset in $_countdownText',
                      style: TextStyle(fontSize: 12, color: subtextColor),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isCreateMode ? 'Continue' : 'Check', style: const TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CloudPasswordHint: Set password hint ──

class _CloudPasswordHint extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final String newPassword;
  final String currentPassword;
  final VoidCallback onSuccess;
  final String? recoveryCode;

  const _CloudPasswordHint({
    required this.accountId,
    required this.engine,
    required this.newPassword,
    required this.currentPassword,
    required this.onSuccess,
    this.recoveryCode,
  });

  @override
  State<_CloudPasswordHint> createState() => _CloudPasswordHintState();
}

class _CloudPasswordHintState extends State<_CloudPasswordHint> {
  final _hintController = TextEditingController();
  final _hintFocus = FocusNode();
  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _hintController.addListener(_clearError);
    WidgetsBinding.instance.addPostFrameCallback((_) => _hintFocus.requestFocus());
  }

  void _clearError() {
    if (_error.isNotEmpty) setState(() => _error = '');
  }

  @override
  void dispose() {
    _hintController.removeListener(_clearError);
    _hintController.dispose();
    _hintFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final hint = _hintController.text;
    if (hint.isEmpty) {
      setState(() => _error = 'Please enter a hint');
      _hintFocus.requestFocus();
      return;
    }
    if (hint == widget.newPassword) {
      setState(() => _error = 'The hint must be different from your password');
      _hintFocus.requestFocus();
      return;
    }

    _navigateOrRecover(hint);
  }

  Future<void> _navigateOrRecover(String hint) async {
    if (widget.recoveryCode != null) {
      setState(() { _loading = true; _error = ''; });
      try {
        await widget.engine.recoverPasswordWithCode(
          widget.accountId,
          code: widget.recoveryCode!,
          newPassword: widget.newPassword,
          hint: hint,
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(settingsPageRoute(
          _CloudPasswordDone(
            accountId: widget.accountId,
            engine: widget.engine,
            message: 'Password updated!',
            onDone: widget.onSuccess,
          ),
        ));
      } catch (e) {
        if (!mounted) return;
        setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
      }
      return;
    }
    Navigator.of(context).pushReplacement(settingsPageRoute(
      _CloudPasswordEmail(
        accountId: widget.accountId,
        engine: widget.engine,
        newPassword: widget.newPassword,
        currentPassword: widget.currentPassword,
        hint: hint,
        onSuccess: widget.onSuccess,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final errorColor = isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);

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
        title: Text('Two-Step Verification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedSettingsIcon(
                icon: Icons.lightbulb_outline,
                size: 100,
                color: accentColor,
              ),
              const SizedBox(height: 19),
              Text('Add a Hint', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 5),
              Text(
                'Your hint will be displayed when you enter a password.',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: 256,
                height: 61,
                child: Center(
                  child: TextField(
                    controller: _hintController,
                    focusNode: _hintFocus,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Password hint',
                      hintStyle: TextStyle(color: subtextColor),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _error.isNotEmpty ? errorColor : subtextColor)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _error.isNotEmpty ? errorColor : accentColor, width: 2)),
                    ),
                    style: TextStyle(fontSize: 15, color: textColor),
                  ),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 256,
                    child: Text(_error, style: TextStyle(fontSize: 13, color: errorColor), textAlign: TextAlign.center),
                  ),
                ),
              const SizedBox(height: 28),
              TextButton(
                onPressed: _loading ? null : () => _navigateOrRecover(''),
                child: Text('Skip', style: TextStyle(fontSize: 14, color: accentColor)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Continue', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CloudPasswordEmail: Recovery email setup ──

class _CloudPasswordEmail extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final String newPassword;
  final String currentPassword;
  final String hint;
  final VoidCallback onSuccess;
  final bool emailOnly;

  const _CloudPasswordEmail({
    required this.accountId,
    required this.engine,
    required this.newPassword,
    required this.currentPassword,
    required this.hint,
    required this.onSuccess,
    this.emailOnly = false,
  });

  @override
  State<_CloudPasswordEmail> createState() => _CloudPasswordEmailState();
}

class _CloudPasswordEmailState extends State<_CloudPasswordEmail> {
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();
  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_clearError);
    WidgetsBinding.instance.addPostFrameCallback((_) => _emailFocus.requestFocus());
  }

  void _clearError() {
    if (_error.isNotEmpty) setState(() => _error = '');
  }

  @override
  void dispose() {
    _emailController.removeListener(_clearError);
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email');
      _emailFocus.requestFocus();
      return;
    }
    await _setPassword(email);
  }

  Future<void> _skip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
          title: Text('Warning', style: TextStyle(color: textColor)),
          content: Text(
            'If you forget your password, you will lose access to your Telegram account. Are you sure you want to skip adding a recovery email?',
            style: TextStyle(color: textColor, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Skip', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _setPassword('');
    }
  }

  Future<void> _setPassword(String email) async {
    setState(() { _loading = true; _error = ''; });
    try {
      if (widget.emailOnly) {
        await widget.engine.setCloudPasswordEmail(
          widget.accountId,
          currentPassword: widget.currentPassword,
          email: email,
        );
      } else {
        await widget.engine.setCloudPassword(
          widget.accountId,
          currentPassword: widget.currentPassword,
          newPassword: widget.newPassword,
          hint: widget.hint,
          email: email,
        );
      }
      if (!mounted) return;

      if (email.isNotEmpty) {
        final state = await widget.engine.getCloudPasswordState(widget.accountId);
        if (!mounted) return;
        final unconfirmed = state?['unconfirmedEmail'] as String? ?? '';
        if (unconfirmed.isNotEmpty) {
          final effectivePassword = widget.emailOnly ? widget.currentPassword : widget.newPassword;
          Navigator.of(context).pushReplacement(settingsPageRoute(
            _CloudPasswordEmailConfirm(
              accountId: widget.accountId,
              engine: widget.engine,
              emailPattern: unconfirmed,
              currentPassword: effectivePassword,
              onDone: () {
                widget.onSuccess();
              },
            ),
          ));
          return;
        }
      }

      if (!mounted) return;
      final effectivePassword = widget.emailOnly ? widget.currentPassword : widget.newPassword;
      Navigator.of(context).pushReplacement(settingsPageRoute(
        _CloudPasswordDone(
          accountId: widget.accountId,
          engine: widget.engine,
          message: widget.emailOnly ? 'Email updated!' : 'Password is set!',
          currentPassword: effectivePassword,
          onDone: widget.onSuccess,
          navigateToManage: true,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _loading = false;
        if (errMsg.contains('EMAIL_INVALID')) {
          _error = 'Please enter a valid email address.';
          _emailFocus.requestFocus();
        } else if (errMsg.contains('EMAIL_NOT_ALLOWED')) {
          _error = 'This email address is not allowed.';
          _emailFocus.requestFocus();
        } else if (errMsg.contains('FLOOD_WAIT')) {
          _error = 'Too many attempts. Please try again later.';
        } else if (errMsg.contains('PASSWORD_HASH_INVALID') || errMsg.contains('SRP_PASSWORD_CHANGED')) {
          _error = 'Password has expired. Please start over.';
        } else {
          _error = errMsg;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final errorColor = isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);

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
        title: Text('Two-Step Verification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedSettingsIcon(
                icon: Icons.email_outlined,
                size: 100,
                color: accentColor,
              ),
              const SizedBox(height: 19),
              Text('Recovery Email', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 5),
              Text(
                'Please add your valid email. It is the only way to recover a forgotten password.',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: 256,
                height: 61,
                child: Center(
                  child: TextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Your email',
                      hintStyle: TextStyle(color: subtextColor),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _error.isNotEmpty ? errorColor : subtextColor)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _error.isNotEmpty ? errorColor : accentColor, width: 2)),
                    ),
                    style: TextStyle(fontSize: 15, color: textColor),
                  ),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 256,
                    child: Text(_error, style: TextStyle(fontSize: 13, color: errorColor), textAlign: TextAlign.center),
                  ),
                ),
              const SizedBox(height: 28),
              if (!widget.emailOnly)
                TextButton(
                  onPressed: _loading ? null : _skip,
                  child: Text('Skip', style: TextStyle(fontSize: 14, color: accentColor)),
                ),
              if (!widget.emailOnly) const SizedBox(height: 16),
              if (widget.emailOnly) const SizedBox(height: 16),
              SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CloudPasswordEmailConfirm: Confirm recovery email ──
// §28.3.5: SentCodeField (single field), auto-submit at length, resend, abort menu, recovery path

class _CloudPasswordEmailConfirm extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final String emailPattern;
  final String currentPassword;
  final int codeLength;
  final bool isRecovery;
  final VoidCallback onDone;

  const _CloudPasswordEmailConfirm({
    required this.accountId,
    required this.engine,
    required this.emailPattern,
    this.currentPassword = '',
    this.codeLength = 6,
    this.isRecovery = false,
    required this.onDone,
  });

  @override
  State<_CloudPasswordEmailConfirm> createState() => _CloudPasswordEmailConfirmState();
}

class _CloudPasswordEmailConfirmState extends State<_CloudPasswordEmailConfirm> {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  String _error = '';
  String _info = '';
  bool _loading = false;
  bool _autoSubmitted = false;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _codeFocus.requestFocus());
  }

  void _onTextChanged() {
    if (_error.isNotEmpty || _info.isNotEmpty) {
      setState(() { _error = ''; _info = ''; });
    }
    final digits = _codeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= widget.codeLength && !_loading && !_autoSubmitted) {
      _autoSubmitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
    if (digits.length < widget.codeLength) {
      _autoSubmitted = false;
    }
  }

  @override
  void dispose() {
    _codeController.removeListener(_onTextChanged);
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (code.isEmpty) {
      setState(() => _error = 'Invalid code. Please try again.');
      return;
    }

    setState(() { _loading = true; _error = ''; _info = ''; });
    try {
      if (widget.isRecovery) {
        await widget.engine.checkRecoveryPassword(widget.accountId, code);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(settingsPageRoute(
          _CloudPasswordInput(
            accountId: widget.accountId,
            engine: widget.engine,
            mode: _CloudPasswordMode.recover,
            hint: '',
            hasRecovery: false,
            pendingResetDate: 0,
            onSuccess: widget.onDone,
            recoveryCode: code,
          ),
        ));
      } else {
        await widget.engine.confirmPasswordEmail(widget.accountId, code);
        if (!mounted) return;
        if (widget.currentPassword.isNotEmpty) {
          Navigator.of(context).pushReplacement(settingsPageRoute(
            _CloudPasswordDone(
              accountId: widget.accountId,
              engine: widget.engine,
              message: 'Email confirmed!',
              currentPassword: widget.currentPassword,
              onDone: widget.onDone,
              navigateToManage: true,
            ),
          ));
        } else {
          Navigator.of(context).pushReplacement(settingsPageRoute(
            _CloudPasswordDone(
              accountId: widget.accountId,
              engine: widget.engine,
              message: 'Email confirmed!',
              onDone: widget.onDone,
            ),
          ));
        }
      }
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _loading = false;
        _autoSubmitted = false;
        if (errMsg.contains('CODE_INVALID')) {
          _error = 'Invalid code. Please try again.';
        } else if (errMsg.contains('EMAIL_HASH_EXPIRED')) {
          _error = 'Email confirmation expired.';
        } else if (errMsg.contains('FLOOD_WAIT')) {
          _error = 'Too many attempts. Please try again later.';
        } else if (errMsg.contains('PASSWORD_HASH_INVALID') || errMsg.contains('SRP_PASSWORD_CHANGED')) {
          _error = 'Your cloud password has expired.';
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        } else if (errMsg.contains('PASSWORD_RECOVERY_NA')) {
          _error = 'Recovery not available.';
        } else if (errMsg.contains('PASSWORD_RECOVERY_EXPIRED')) {
          _error = 'Recovery code expired.';
        } else {
          _error = errMsg;
        }
      });
      _codeController.selection = TextSelection(baseOffset: 0, extentOffset: _codeController.text.length);
    }
  }

  Future<void> _resend() async {
    setState(() { _error = ''; _info = ''; });
    try {
      await widget.engine.resendPasswordEmail(widget.accountId);
      if (!mounted) return;
      setState(() => _info = 'Code resent.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _abort() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
        final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Abort verification?', style: TextStyle(color: textColor)),
          content: Text('This will cancel the email verification process.', style: TextStyle(color: textColor)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Abort', style: TextStyle(color: isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F))),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.engine.cancelPasswordEmail(widget.accountId);
    } catch (_) {}
    if (mounted) {
      widget.onDone();
      Navigator.of(context).pop();
    }
  }

  Future<void> _onRecoveryLink() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Reset Password', style: TextStyle(color: textColor)),
        content: Text(
          'If you can\'t access your recovery email, your password will be reset with a delay for security reasons.',
          style: TextStyle(color: textColor, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await widget.engine.resetPassword(widget.accountId);
      if (!mounted) return;
      if (result['done'] == true) {
        widget.onDone();
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == 'privacy');
        showTelegramToast(context, 'Cloud password has been removed.');
        return;
      }
      final retryDate = result['retryDate'] as int? ?? 0;
      final untilDate = result['untilDate'] as int? ?? 0;
      if (retryDate > 0) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        var remaining = retryDate - now;
        if (remaining < 60) remaining = 60;
        setState(() {
          _loading = false;
          _error = 'You can reset your password in ${_formatDuration(remaining)}.';
        });
      } else if (untilDate > 0) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        var remaining = untilDate - now;
        if (remaining < 60) remaining = 60;
        if (!mounted) return;
        setState(() => _loading = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: bgColor,
            title: Text('Reset Initiated', style: TextStyle(color: textColor)),
            content: Text(
              'Your password will be reset in ${_formatDuration(remaining)}.',
              style: TextStyle(color: textColor, height: 1.4),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
            ],
          ),
        );
        if (mounted) {
          widget.onDone();
          Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == 'privacy');
        }
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h < 24) return m > 0 ? '${h}h ${m}m' : '${h}h';
    final d = h ~/ 24;
    final rh = h % 24;
    return rh > 0 ? '${d}d ${rh}h' : '${d}d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final errorColor = isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);
    final infoColor = isDark ? const Color(0xFF4CAF50) : const Color(0xFF388E3C);

    final title = widget.isRecovery ? 'Recovery Email' : 'Check your email';
    final description = widget.isRecovery
        ? 'Enter the code we sent to ${widget.emailPattern}'
        : 'We\'ve sent a code to ${widget.emailPattern}';
    final linkText = widget.isRecovery ? 'Can\'t access your email?' : 'Resend code';
    final buttonText = widget.isRecovery ? 'Check' : 'Confirm';

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
        title: Text('Two-Step Verification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: textColor),
            color: bgColor,
            onSelected: (v) { if (v == 'abort') _abort(); },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'abort',
                child: Text('Abort', style: TextStyle(color: errorColor)),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedSettingsIcon(
                icon: Icons.mark_email_read_outlined,
                size: 100,
                color: accentColor,
              ),
              const SizedBox(height: 19),
              Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 5),
              Text(
                description,
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: 256,
                height: 61,
                child: Center(
                  child: TextField(
                    controller: _codeController,
                    focusNode: _codeFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Code',
                      hintStyle: TextStyle(color: subtextColor),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _error.isNotEmpty ? errorColor : subtextColor)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _error.isNotEmpty ? errorColor : accentColor, width: 2)),
                    ),
                    style: TextStyle(fontSize: 16, color: textColor),
                  ),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 256,
                    child: Text(_error, style: TextStyle(fontSize: 14, color: errorColor), textAlign: TextAlign.center),
                  ),
                ),
              if (_info.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 256,
                    child: Text(_info, style: TextStyle(fontSize: 14, color: infoColor), textAlign: TextAlign.center),
                  ),
                ),
              const SizedBox(height: 28),
              TextButton(
                onPressed: widget.isRecovery ? _onRecoveryLink : _resend,
                child: Text(linkText, style: TextStyle(fontSize: 14, color: accentColor)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 35),
                child: SizedBox(
                  width: 300,
                  height: 42,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(buttonText, style: const TextStyle(fontSize: 15, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CloudPasswordDone: Completion screen with fireworks + thumbs-up ──

class _CloudPasswordDone extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final String message;
  final String? currentPassword;
  final VoidCallback? onDone;
  final bool navigateToManage;

  const _CloudPasswordDone({
    required this.accountId,
    required this.engine,
    required this.message,
    this.currentPassword,
    this.onDone,
    this.navigateToManage = false,
  });

  @override
  State<_CloudPasswordDone> createState() => _CloudPasswordDoneState();
}

class _CloudPasswordDoneState extends State<_CloudPasswordDone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fireworksCtrl;
  late final List<_Particle> _particles;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _particles = List.generate(50, (_) => _Particle(rng));
    _fireworksCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    Future<void>.delayed(const Duration(milliseconds: 2000), _navigate);
  }

  void _navigate() {
    if (_navigated || !mounted) return;
    _navigated = true;
    if (widget.navigateToManage && widget.currentPassword != null) {
      Navigator.of(context).pushReplacement(settingsPageRoute(
        _CloudPasswordManage(
          accountId: widget.accountId,
          engine: widget.engine,
          currentPassword: widget.currentPassword!,
          onChanged: widget.onDone ?? () {},
        ),
      ));
    } else {
      widget.onDone?.call();
      if (mounted) {
        Navigator.of(context).popUntil(
          (route) => route.isFirst || route.settings.name == 'privacy',
        );
      }
    }
  }

  @override
  void dispose() {
    _fireworksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Two-Step Verification',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('\u{1F44D}', style: TextStyle(fontSize: 80)),
                const SizedBox(height: 19),
                Text(
                  widget.message,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _fireworksCtrl,
                builder: (context, _) => CustomPaint(
                  painter: _FireworksPainter(_particles, _fireworksCtrl.value),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── CloudPasswordManage: Manage existing password ──

class _CloudPasswordManage extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final String currentPassword;
  final VoidCallback onChanged;

  const _CloudPasswordManage({
    required this.accountId,
    required this.engine,
    required this.currentPassword,
    required this.onChanged,
  });

  @override
  State<_CloudPasswordManage> createState() => _CloudPasswordManageState();
}

class _CloudPasswordManageState extends State<_CloudPasswordManage> {
  Timer? _idleTimer;
  DateTime _lastActivity = DateTime.now();
  static const _idleTimeout = Duration(minutes: 10);
  static const _checkInterval = Duration(seconds: 60);
  bool _hasRecovery = false;
  bool _disabling = false;

  @override
  void initState() {
    super.initState();
    _idleTimer = Timer.periodic(_checkInterval, (_) {
      if (DateTime.now().difference(_lastActivity) >= _idleTimeout) {
        _idleTimer?.cancel();
        if (mounted) Navigator.of(context).pop();
      }
    });
    _fetchRecoveryState();
  }

  Future<void> _fetchRecoveryState() async {
    final state = await widget.engine.getCloudPasswordState(widget.accountId);
    if (!mounted || state == null) return;
    setState(() => _hasRecovery = state['hasRecovery'] as bool? ?? false);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _resetIdle() => _lastActivity = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final dividerColor = isDark ? const Color(0xFF232E3C) : const Color(0xFFE0E0E0);

    final emailLabel = _hasRecovery ? 'Change Recovery Email' : 'Set Recovery Email';

    return Listener(
      onPointerDown: (_) => _resetIdle(),
      onPointerMove: (_) => _resetIdle(),
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
        title: Text('Two-Step Verification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.verified_user_outlined, size: 48, color: accentColor),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Your cloud password is active. You will need it when you log into your Telegram account.',
                            style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ManageRow(
                    icon: Icons.vpn_key,
                    label: 'Change Password',
                    textColor: textColor,
                    subtextColor: subtextColor,
                    hoverBg: hoverBg,
                    onTap: () {
                      _resetIdle();
                      Navigator.of(context).push(settingsPageRoute(
                        _CloudPasswordInput(
                          accountId: widget.accountId,
                          engine: widget.engine,
                          mode: _CloudPasswordMode.change,
                          hint: '',
                          hasRecovery: false,
                          pendingResetDate: 0,
                          onSuccess: widget.onChanged,
                          currentPassword: widget.currentPassword,
                        ),
                      ));
                    },
                  ),
                  _ManageRow(
                    icon: Icons.email_outlined,
                    label: emailLabel,
                    textColor: textColor,
                    subtextColor: subtextColor,
                    hoverBg: hoverBg,
                    onTap: () {
                      _resetIdle();
                      Navigator.of(context).push(settingsPageRoute(
                        _CloudPasswordEmail(
                          accountId: widget.accountId,
                          engine: widget.engine,
                          newPassword: '',
                          currentPassword: widget.currentPassword,
                          hint: '',
                          emailOnly: true,
                          onSuccess: () {
                            widget.onChanged();
                            _fetchRecoveryState();
                          },
                        ),
                      ));
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    color: isDark ? const Color(0xFF0E1621) : const Color(0xFFF0F0F0),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text(
                      'If you forget your password, you can reset it using your recovery email or by waiting.',
                      style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: dividerColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: TextButton(
              onPressed: _disabling ? null : () {
                _resetIdle();
                _confirmDisable(context);
              },
              child: _disabling
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      'Turn Password Off',
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F),
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  void _confirmDisable(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
        title: Text('Disable Password', style: TextStyle(color: textColor)),
        content: Text(
          'Are you sure you want to disable your password?',
          style: TextStyle(color: textColor),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disable', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _disabling = true);
    try {
      await widget.engine.removeCloudPassword(widget.accountId, widget.currentPassword);
      widget.onChanged();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == 'privacy');
        showTelegramToast(context, 'Two-Step Verification has been disabled.');
      }
    } catch (e) {
      if (context.mounted) {
        setState(() => _disabling = false);
        showTelegramToast(context, 'Failed: ${e.toString().replaceFirst("Exception: ", "")}');
      }
    }
  }
}

// ── §16.2.2 Global TTL (Auto-Delete Messages) ──

class _GlobalTTLScreen extends StatefulWidget {
  final int currentTTL;
  final ValueChanged<int> onChanged;

  const _GlobalTTLScreen({required this.currentTTL, required this.onChanged});

  @override
  State<_GlobalTTLScreen> createState() => _GlobalTTLScreenState();
}

class _GlobalTTLScreenState extends State<_GlobalTTLScreen> {
  static const _presets = [0, 86400, 604800, 2678400];
  late int _selectedTTL;
  late List<int> _options;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedTTL = widget.currentTTL;
    _options = _buildOptions(widget.currentTTL);
  }

  List<int> _buildOptions(int current) {
    final opts = List<int>.from(_presets);
    if (current > 0 && !opts.contains(current)) {
      opts.add(current);
      opts.sort();
    }
    return opts;
  }

  String _formatPeriod(int seconds) {
    if (seconds <= 0) return 'Off';
    if (seconds == 86400) return '1 day';
    if (seconds == 604800) return '1 week';
    if (seconds == 2678400) return '1 month';
    if (seconds < 86400) return '${seconds ~/ 3600} hours';
    final days = seconds ~/ 86400;
    if (days < 7) return '$days days';
    if (days < 30) return '${days ~/ 7} weeks';
    return '${days ~/ 30} months';
  }

  Future<void> _selectTTL(int period) async {
    if (_saving) return;
    if (period == _selectedTTL) return;

    if (period > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Auto-Delete Messages'),
          content: Text(
            'Are you sure you want to ${_selectedTTL == 0 ? 'enable' : 'change'} auto-delete with a timer of ${_formatPeriod(period)}? '
            'All new messages in chats you start will be automatically deleted after this period.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_selectedTTL == 0 ? 'Enable' : 'Change'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _saving = true;
      _selectedTTL = period;
    });

    try {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      await engine.setDefaultHistoryTTL(appState.activeAccountId, period);
      widget.onChanged(period);
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed: ${e.toString().replaceFirst("Exception: ", "")}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openCustomPeriod() async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => _CustomTTLDialog(currentTTL: _selectedTTL),
    );
    if (result != null && result != _selectedTTL) {
      setState(() => _options = _buildOptions(result));
      _selectTTL(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final dividerBg = isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

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
          'Auto-Delete Messages',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: dividerBg,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: _AnimatedSettingsIcon(
                icon: Icons.timer_outlined,
                size: 100,
                color: accentColor,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text(
              'Auto-delete timer',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ),
          for (final period in _options)
            _TTLRadioRow(
              label: _formatPeriod(period),
              selected: _selectedTTL == period,
              textColor: textColor,
              accentColor: accentColor,
              hoverBg: hoverBg,
              onTap: () => _selectTTL(period),
            ),
          const SizedBox(height: 4),
          InkWell(
            onTap: _openCustomPeriod,
            hoverColor: hoverBg,
            child: Padding(
              padding: SettingsStyle.noIconPadding,
              child: Text(
                'Set Custom Period',
                style: TextStyle(
                  fontSize: SettingsStyle.buttonFontSize,
                  color: accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Container(height: 1, color: dividerBg),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            child: Text(
              'If enabled, all new messages in chats you start will be '
              'automatically deleted for everyone after the selected period of time.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _TTLRadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Color textColor;
  final Color accentColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _TTLRadioRow({
    required this.label,
    required this.selected,
    required this.textColor,
    required this.accentColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: SettingsStyle.buttonFontSize,
                  color: textColor,
                ),
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accentColor : textColor.withValues(alpha: 0.4),
                  width: selected ? 7 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomTTLDialog extends StatefulWidget {
  final int currentTTL;

  const _CustomTTLDialog({required this.currentTTL});

  @override
  State<_CustomTTLDialog> createState() => _CustomTTLDialogState();
}

class _CustomTTLDialogState extends State<_CustomTTLDialog> {
  final _daysController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.currentTTL > 0) {
      _daysController.text = (widget.currentTTL ~/ 86400).toString();
    }
  }

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set Custom Period'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _daysController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Number of days',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final days = int.tryParse(_daysController.text.trim());
            if (days == null || days < 1 || days > 365) {
              setState(() => _error = 'Enter a number between 1 and 365');
              return;
            }
            Navigator.of(context).pop(days * 86400);
          },
          child: const Text('Set'),
        ),
      ],
    );
  }
}

// ── Local Passcode Helpers ──

String _hashPasscode(String passcode) {
  final bytes = utf8.encode(passcode);
  return sha256.convert(bytes).toString();
}

Future<Map<String, dynamic>> _readPasscodeData(String configDir) async {
  final file = File('$configDir/local_passcode.json');
  if (!await file.exists()) return {};
  try {
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

Future<void> _writePasscodeData(
    String configDir, Map<String, dynamic> data) async {
  final file = File('$configDir/local_passcode.json');
  await file.writeAsString(jsonEncode(data));
}

// ── LocalPasscodeCreate ──

class _LocalPasscodeCreate extends StatefulWidget {
  final String configDir;
  final VoidCallback onCreated;

  const _LocalPasscodeCreate({
    required this.configDir,
    required this.onCreated,
  });

  @override
  State<_LocalPasscodeCreate> createState() => _LocalPasscodeCreateState();
}

class _LocalPasscodeCreateState extends State<_LocalPasscodeCreate> {
  final _firstController = TextEditingController();
  final _confirmController = TextEditingController();
  final _firstFocus = FocusNode();
  bool _obscureFirst = true;
  bool _obscureConfirm = true;
  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _firstFocus.requestFocus());
  }

  @override
  void dispose() {
    _firstController.dispose();
    _confirmController.dispose();
    _firstFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final first = _firstController.text;
    final confirm = _confirmController.text;
    if (first.isEmpty) {
      setState(() => _error = 'Please enter a passcode');
      return;
    }
    if (confirm.isEmpty) {
      setState(() => _error = 'Please re-enter your passcode');
      return;
    }
    if (first != confirm) {
      setState(() => _error = "Passcodes don't match");
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    await _writePasscodeData(widget.configDir, {
      'hash': _hashPasscode(first),
      'autoLockSeconds': 300,
    });

    if (!mounted) return;
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final errorColor =
        isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);

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
          'Local Passcode',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 19, bottom: 5),
                child: _AnimatedSettingsIcon(
                  icon: Icons.lock_outline,
                  size: 100,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 19),
              Text(
                'Create Passcode',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 256,
                child: Text(
                  'When you set up an additional passcode, a lock icon will appear on the chats page. Tap it to lock and unlock the app.',
                  style: TextStyle(
                      fontSize: 14, color: subtextColor, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 256,
                child: Text(
                  'Note: if you forget the passcode, you\'ll need to delete and reinstall the app. All secret chats will be lost.',
                  style: TextStyle(
                      fontSize: 14, color: subtextColor, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: 256,
                child: TextField(
                  controller: _firstController,
                  focusNode: _firstFocus,
                  obscureText: _obscureFirst,
                  onChanged: (_) {
                    if (_error.isNotEmpty) setState(() => _error = '');
                  },
                  onSubmitted: (_) =>
                      FocusScope.of(context).nextFocus(),
                  decoration: InputDecoration(
                    hintText: 'Enter a passcode',
                    hintStyle: TextStyle(color: subtextColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscureFirst
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: subtextColor),
                      onPressed: () =>
                          setState(() => _obscureFirst = !_obscureFirst),
                    ),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: subtextColor)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: accentColor, width: 2)),
                  ),
                  style: TextStyle(fontSize: 16, color: textColor),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 256,
                child: TextField(
                  controller: _confirmController,
                  obscureText: _obscureConfirm,
                  onChanged: (_) {
                    if (_error.isNotEmpty) setState(() => _error = '');
                  },
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Re-enter your passcode',
                    hintStyle: TextStyle(color: subtextColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: subtextColor),
                      onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm),
                    ),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: subtextColor)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: accentColor, width: 2)),
                  ),
                  style: TextStyle(fontSize: 16, color: textColor),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 256,
                    child: Text(_error,
                        style: TextStyle(fontSize: 13, color: errorColor),
                        textAlign: TextAlign.center),
                  ),
                ),
              const SizedBox(height: 19),
              SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Create',
                          style:
                              TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 35),
            ],
          ),
        ),
      ),
    );
  }
}

// ── LocalPasscodeCheck ──

class _LocalPasscodeCheck extends StatefulWidget {
  final String configDir;
  final VoidCallback onSuccess;

  const _LocalPasscodeCheck({
    required this.configDir,
    required this.onSuccess,
  });

  @override
  State<_LocalPasscodeCheck> createState() => _LocalPasscodeCheckState();
}

class _LocalPasscodeCheckState extends State<_LocalPasscodeCheck> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _obscure = true;
  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final entered = _controller.text;
    if (entered.isEmpty) {
      setState(() => _error = 'Please enter your passcode');
      return;
    }

    final appState = context.read<AppState>();
    if (!appState.passcodeCanTry()) {
      setState(() => _error = 'Please try again later');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    if (appState.checkPasscode(entered)) {
      if (mounted) widget.onSuccess();
    } else {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Wrong passcode';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;
    final errorColor =
        isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);

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
          'Local Passcode',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 19, bottom: 5),
                child: _AnimatedSettingsIcon(
                  icon: Icons.lock_outline,
                  size: 100,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 19),
              Text(
                'Enter your passcode',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: 256,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  obscureText: _obscure,
                  onChanged: (_) {
                    if (_error.isNotEmpty) setState(() => _error = '');
                  },
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Enter your passcode',
                    hintStyle: TextStyle(color: subtextColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: subtextColor),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: subtextColor)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: accentColor, width: 2)),
                  ),
                  style: TextStyle(fontSize: 16, color: textColor),
                ),
              ),
              const SizedBox(height: 61),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: 256,
                    child: Text(_error,
                        style: TextStyle(fontSize: 13, color: errorColor),
                        textAlign: TextAlign.center),
                  ),
                ),
              const SizedBox(height: 19),
              SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Next',
                          style:
                              TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 35),
            ],
          ),
        ),
      ),
    );
  }
}

// ── LocalPasscodeManage ──

class _LocalPasscodeManage extends StatefulWidget {
  final String configDir;
  final VoidCallback onChanged;

  const _LocalPasscodeManage({
    required this.configDir,
    required this.onChanged,
  });

  @override
  State<_LocalPasscodeManage> createState() => _LocalPasscodeManageState();
}

class _LocalPasscodeManageState extends State<_LocalPasscodeManage> {
  int _autoLockSeconds = 0;
  bool _systemUnlockEnabled = false;
  SystemUnlockStatus _unlockStatus = const SystemUnlockStatus();

  @override
  void initState() {
    super.initState();
    _initUnlockStatus();
    _loadSettings();
  }

  Future<void> _initUnlockStatus() async {
    final status = await getSystemUnlockStatus();
    if (mounted) setState(() => _unlockStatus = status);
  }

  Future<void> _loadSettings() async {
    final data = await _readPasscodeData(widget.configDir);
    if (!mounted) return;
    setState(() {
      _autoLockSeconds = data['autoLockSeconds'] as int? ?? 0;
      _systemUnlockEnabled = data['systemUnlockEnabled'] as bool? ?? false;
    });
  }

  String _formatAutoLock(int seconds) {
    if (seconds <= 0) return 'Disabled';
    if (seconds < 60) return '$seconds seconds';
    if (seconds == 60) return '1 minute';
    if (seconds == 300) return '5 minutes';
    if (seconds == 3600) return '1 hour';
    if (seconds == 18000) return '5 hours';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '$h hour${h > 1 ? 's' : ''}';
    return '$m minute${m > 1 ? 's' : ''}';
  }

  void _openAutoLock() async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => _AutoLockBox(currentSeconds: _autoLockSeconds),
    );
    if (result == null || !mounted) return;

    final data = await _readPasscodeData(widget.configDir);
    data['autoLockSeconds'] = result;
    await _writePasscodeData(widget.configDir, data);
    setState(() => _autoLockSeconds = result);
    widget.onChanged();
  }

  Future<void> _toggleSystemUnlock(bool value) async {
    final data = await _readPasscodeData(widget.configDir);
    data['systemUnlockEnabled'] = value;
    await _writePasscodeData(widget.configDir, data);
    if (!mounted) return;
    setState(() => _systemUnlockEnabled = value);
    widget.onChanged();
  }

  void _changePasscode() {
    Navigator.of(context).push(settingsPageRoute(
      _LocalPasscodeCreate(
        configDir: widget.configDir,
        onCreated: () {
          widget.onChanged();
          Navigator.of(context).pop();
        },
      ),
    ));
  }

  void _turnOff() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final textColor =
            isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
        return AlertDialog(
          title: Text('Turn Off Passcode',
              style: TextStyle(color: textColor)),
          content: Text(
              'Are you sure you want to turn off the passcode?',
              style: TextStyle(color: textColor)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Turn Off',
                  style: TextStyle(
                      color: isDark
                          ? const Color(0xFFE53935)
                          : const Color(0xFFD32F2F))),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;

    final file = File('${widget.configDir}/local_passcode.json');
    if (await file.exists()) await file.delete();
    widget.onChanged();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final accentColor =
        context.palette.windowBgActive;
    final errorColor =
        isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);

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
          'Local Passcode',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 8),
          _PrivacyIconRow(
            icon: Icons.lock_outline,
            label: 'Change Passcode',
            rightLabel: '',
            textColor: textColor,
            subtextColor: subtextColor,
            hoverBg: hoverBg,
            onTap: _changePasscode,
          ),
          _PrivacyIconRow(
            icon: Icons.timer_outlined,
            label: 'Auto-Lock',
            rightLabel: _formatAutoLock(_autoLockSeconds),
            textColor: textColor,
            subtextColor: subtextColor,
            hoverBg: hoverBg,
            onTap: _openAutoLock,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _unlockStatus.unlockType != UnlockType.none
                ? _SystemUnlockRow(
                    label: getSystemUnlockLabel(_unlockStatus.unlockType),
                    enabled: _systemUnlockEnabled,
                    textColor: textColor,
                    subtextColor: subtextColor,
                    hoverBg: hoverBg,
                    accentColor: accentColor,
                    onToggle: _toggleSystemUnlock,
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 7),
          Container(
            height: 1,
            color: isDark
                ? const Color(0xFF101921)
                : const Color(0xFFF1F1F1),
          ),
          const SizedBox(height: 7),
          InkWell(
            onTap: _turnOff,
            hoverColor: hoverBg,
            child: Padding(
              padding: SettingsStyle.iconRowPadding,
              child: Row(
                children: [
                  Icon(Icons.lock_open, size: 24, color: errorColor),
                  const SizedBox(width: SettingsStyle.iconGap),
                  Text(
                    'Turn Off Passcode',
                    style: TextStyle(fontSize: 14, color: errorColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── AutoLockBox Dialog ──

class _AutoLockBox extends StatefulWidget {
  final int currentSeconds;

  const _AutoLockBox({required this.currentSeconds});

  @override
  State<_AutoLockBox> createState() => _AutoLockBoxState();
}

class _AutoLockBoxState extends State<_AutoLockBox> {
  late int _selected;
  final _hoursController = TextEditingController();
  final _minutesController = TextEditingController();
  static const _presets = [60, 300, 3600, 18000];
  static const _customSentinel = -1;

  @override
  void initState() {
    super.initState();
    if (_presets.contains(widget.currentSeconds)) {
      _selected = widget.currentSeconds;
    } else {
      _selected = _customSentinel;
      final h = widget.currentSeconds ~/ 3600;
      final m = (widget.currentSeconds % 3600) ~/ 60;
      _hoursController.text = h.toString().padLeft(2, '0');
      _minutesController.text = m.toString().padLeft(2, '0');
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  int _resolveSeconds() {
    if (_selected != _customSentinel) return _selected;
    final h = int.tryParse(_hoursController.text) ?? 0;
    final m = int.tryParse(_minutesController.text) ?? 10;
    return h * 3600 + m * 60;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        context.palette.windowBgActive;

    final labels = {
      60: '1 minute',
      300: '5 minutes',
      3600: '1 hour',
      18000: '5 hours',
      _customSentinel: 'Custom',
    };

    return AlertDialog(
      title: Text('Auto-Lock', style: TextStyle(color: textColor)),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in labels.entries)
              RadioListTile<int>(
                value: entry.key,
                groupValue: _selected,
                activeColor: accentColor,
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value,
                    style: TextStyle(fontSize: 14, color: textColor)),
                onChanged: (v) => setState(() => _selected = v!),
              ),
            if (_selected == _customSentinel) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _hoursController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'HH',
                        hintStyle: TextStyle(color: subtextColor),
                        border: const OutlineInputBorder(),
                      ),
                      style: TextStyle(fontSize: 16, color: textColor),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(':',
                        style:
                            TextStyle(fontSize: 20, color: textColor)),
                  ),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _minutesController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'MM',
                        hintStyle: TextStyle(color: subtextColor),
                        border: const OutlineInputBorder(),
                      ),
                      style: TextStyle(fontSize: 16, color: textColor),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_resolveSeconds()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SystemUnlockRow extends StatelessWidget {
  final String label;
  final bool enabled;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final Color accentColor;
  final ValueChanged<bool> onToggle;

  const _SystemUnlockRow({
    required this.label,
    required this.enabled,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.accentColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onToggle(!enabled),
      hoverColor: hoverBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(21, 11, 20, 9),
        child: Row(
          children: [
            Icon(Icons.fingerprint, size: 24, color: subtextColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            SizedBox(
              width: 36,
              height: 20,
              child: Switch(
                value: enabled,
                onChanged: onToggle,
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color textColor;
  final Color subtextColor;
  final Color hoverBg;
  final VoidCallback onTap;

  const _ManageRow({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.subtextColor,
    required this.hoverBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: textColor),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: textColor))),
          ],
        ),
      ),
    );
  }
}

// ── Messages Privacy Box (Non-Contacts) ──

class _MessagesPrivacyBox extends StatefulWidget {
  final String currentOption;
  final int currentChargeStars;
  final String accountId;
  final EngineService engine;
  final bool isPremium;
  final int maxStars;
  final int commissionPermille;
  final double withdrawRate;
  final void Function(String option, int stars) onSaved;

  const _MessagesPrivacyBox({
    required this.currentOption,
    required this.currentChargeStars,
    required this.accountId,
    required this.engine,
    required this.isPremium,
    required this.maxStars,
    required this.commissionPermille,
    required this.withdrawRate,
    required this.onSaved,
  });

  @override
  State<_MessagesPrivacyBox> createState() => _MessagesPrivacyBoxState();
}

class _MessagesPrivacyBoxState extends State<_MessagesPrivacyBox> {
  late String _selected;
  late int _chargeStars;
  late List<int> _starsValues;
  late int _sliderIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentOption;
    _chargeStars = widget.currentChargeStars > 0 ? widget.currentChargeStars : 1;
    _starsValues = _buildStarsValues(widget.maxStars);
    _sliderIndex = _findClosestIndex(_chargeStars);
  }

  List<int> _buildStarsValues(int max) {
    final values = <int>[];
    for (var i = 1; i < 100 && i <= max; i++) values.add(i);
    for (var i = 100; i < 1000 && i <= max; i += 10) values.add(i);
    for (var i = 1000; i <= max; i += 100) values.add(i);
    if (values.isEmpty) values.add(1);
    return values;
  }

  int _findClosestIndex(int value) {
    var best = 0;
    var bestDist = (value - _starsValues[0]).abs();
    for (var i = 1; i < _starsValues.length; i++) {
      final dist = (value - _starsValues[i]).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  String _formatStarCount(int count) {
    if (count >= 1000) {
      final k = count / 1000.0;
      return k == k.truncateToDouble() ? '${k.toInt()}K' : '${k.toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  String _usdEstimate(int stars) {
    final usd = stars * widget.withdrawRate;
    if (usd < 0.01) return '\$0.01';
    return '\$${usd.toStringAsFixed(2)}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final stars = _selected == 'charge_stars' ? _chargeStars : 0;
      await widget.engine.setMessagesPrivacy(
        widget.accountId,
        option: _selected,
        chargeStars: stars,
      );
      widget.onSaved(_selected, stars);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    const options = [
      ('everyone', 'Everyone'),
      ('contacts_premium', 'Contacts & Premium'),
      ('charge_stars', 'Charge Stars'),
    ];

    final commissionPct = (1000 - widget.commissionPermille) / 10.0;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, minWidth: 280),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                child: Text(
                  'Messages',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                child: Text(
                  'Who can send you messages?',
                  style: TextStyle(fontSize: 13, color: subtextColor),
                ),
              ),
              const SizedBox(height: 4),
              ...options.map((opt) {
                final key = opt.$1;
                final label = opt.$2;
                final isPremiumLocked = !widget.isPremium && key != 'everyone';
                return InkWell(
                  onTap: () {
                    if (isPremiumLocked) {
                      setState(() => _selected = 'everyone');
                      showTelegramToast(context, 'Subscribe to Telegram Premium to restrict who can send you messages.');
                    } else {
                      setState(() => _selected = key);
                    }
                  },
                  hoverColor: hoverBg,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Radio<String>(
                            value: key,
                            groupValue: _selected,
                            onChanged: (v) {
                              if (v != null) {
                                if (isPremiumLocked) {
                                  setState(() => _selected = 'everyone');
                                  showTelegramToast(context, 'Subscribe to Telegram Premium to restrict who can send you messages.');
                                } else {
                                  setState(() => _selected = v);
                                }
                              }
                            },
                            activeColor: accentColor,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(fontSize: 14, color: textColor),
                          ),
                        ),
                        if (isPremiumLocked)
                          Icon(Icons.lock, size: 16, color: subtextColor),
                      ],
                    ),
                  ),
                );
              }),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _selected == 'charge_stars'
                  ? _buildChargeStarsSection(
                      isDark, textColor, subtextColor, accentColor,
                      dividerColor, hoverBg, commissionPct)
                  : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Divider(height: 1, color: dividerColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                child: Text(
                  'You can restrict who sends you messages. Non-contacts will need to pay stars to message you.',
                  style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: accentColor)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                        ? SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: accentColor,
                            ),
                          )
                        : Text('Save', style: TextStyle(color: accentColor)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChargeStarsSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color dividerColor,
    Color hoverBg,
    double commissionPct,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: Divider(height: 1, color: dividerColor),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
          child: Text(
            'Star Price per Message',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: Center(
            child: Text(
              '\u2B50 $_chargeStars',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatStarCount(_starsValues.first),
                style: TextStyle(fontSize: 12, color: subtextColor),
              ),
              Text(
                _formatStarCount(_starsValues.last),
                style: TextStyle(fontSize: 12, color: subtextColor),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: isDark
                  ? const Color(0xFF3A4A5C)
                  : const Color(0xFFD4DEE6),
              thumbColor: accentColor,
              overlayColor: accentColor.withValues(alpha: 0.12),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            ),
            child: Slider(
              value: _sliderIndex.toDouble(),
              min: 0,
              max: (_starsValues.length - 1).toDouble(),
              divisions: _starsValues.length - 1,
              onChanged: (v) {
                final idx = v.round();
                setState(() {
                  _sliderIndex = idx;
                  _chargeStars = _starsValues[idx];
                });
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          child: Text(
            'You receive ${commissionPct.toStringAsFixed(0)}% \u2014 about ${_usdEstimate(_chargeStars)} per message.',
            style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _ClearPaymentInfoBox extends StatefulWidget {
  final bool isDark;
  const _ClearPaymentInfoBox({required this.isDark});

  @override
  State<_ClearPaymentInfoBox> createState() => _ClearPaymentInfoBoxState();
}

class _ClearPaymentInfoBoxState extends State<_ClearPaymentInfoBox> {
  bool _shipping = true;
  bool _payment = true;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final canClear = _shipping || _payment;

    return AlertDialog(
      backgroundColor: bgColor,
      title: Text(
        'Clear Payment and Shipping Info',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: _shipping,
            onChanged: (v) => setState(() => _shipping = v ?? false),
            title: Text('Shipping info', style: TextStyle(fontSize: 14, color: textColor)),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          CheckboxListTile(
            value: _payment,
            onChanged: (v) => setState(() => _payment = v ?? false),
            title: Text('Payment info', style: TextStyle(fontSize: 14, color: textColor)),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              'You can clear your payment and shipping info — like your address and card details — that you have saved with Telegram.',
              style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: canClear
              ? () => Navigator.of(context).pop((credentials: _payment, shipping: _shipping))
              : null,
          child: Text(
            'Clear',
            style: TextStyle(
              color: canClear ? Colors.red : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── §16.9 Blocked Users Screen ───

class _BlockedUsersScreen extends StatefulWidget {
  const _BlockedUsersScreen();

  @override
  State<_BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<_BlockedUsersScreen> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _allLoaded = false;
  int _totalCount = 0;
  static const _pageSize = 50;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchBlockedUsers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_allLoaded || _loadingMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _fetchBlockedUsers() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId.isEmpty) return;
    final result = await engine.getBlockedUsersPaged(accountId, offset: 0, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _blockedUsers = result.users;
      _totalCount = result.total;
      _allLoaded = result.users.length >= result.total;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _allLoaded) return;
    setState(() => _loadingMore = true);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId.isEmpty) return;
    final result = await engine.getBlockedUsersPaged(
      accountId, offset: _blockedUsers.length, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _blockedUsers.addAll(result.users);
      _totalCount = result.total;
      _allLoaded = _blockedUsers.length >= result.total || result.users.isEmpty;
      _loadingMore = false;
    });
  }

  Future<void> _unblockUser(String userId) async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId.isEmpty) return;
    await engine.unblockUser(accountId, userId);
    setState(() {
      _blockedUsers.removeWhere((u) => (u['id'] as String? ?? '') == userId);
      _totalCount = (_totalCount - 1).clamp(0, _totalCount);
    });
  }

  void _showBlockUserPicker() {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    final accountId = appState.activeAccountId;
    final blockedIds = _blockedUsers.map((u) => u['id'] as String? ?? '').toSet();
    var searchQuery = '';

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: Text('Block User', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
              contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
              content: SizedBox(
                width: 364,
                height: 400,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                          prefixIcon: Icon(Icons.search, color: subtextColor, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? const Color(0xFF3A4A5C) : const Color(0xFFDDDDDD)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? const Color(0xFF3A4A5C) : const Color(0xFFDDDDDD)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: accentColor),
                          ),
                        ),
                        onChanged: (v) => setDialogState(() => searchQuery = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<_BlockPickerContact>>(
                        future: _loadContacts(engine, accountId, blockedIds),
                        builder: (ctx, snap) {
                          if (snap.hasError) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline, color: subtextColor, size: 32),
                                  const SizedBox(height: 8),
                                  Text('Failed to load contacts', style: TextStyle(color: subtextColor, fontSize: 13)),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () => setDialogState(() {}),
                                    child: Text('Retry', style: TextStyle(color: accentColor)),
                                  ),
                                ],
                              ),
                            );
                          }
                          if (!snap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final contacts = snap.data!;
                          final filtered = searchQuery.isEmpty
                              ? contacts
                              : contacts.where((c) => c.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
                          if (filtered.isEmpty) {
                            return Center(child: Text('No contacts found', style: TextStyle(color: subtextColor)));
                          }
                          return ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final c = filtered[i];
                              return Opacity(
                                opacity: c.isBlocked ? 0.4 : 1.0,
                                child: InkWell(
                                  onTap: c.isBlocked ? null : () async {
                                    Navigator.of(dialogCtx).pop();
                                    await engine.blockUser(accountId, c.id);
                                    _fetchBlockedUsers();
                                  },
                                  hoverColor: hoverBg,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        _blockedUserAvatar(c.avatarB64, c.name, 36),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(c.name, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                              if (c.status.isNotEmpty)
                                                Text(c.status, style: TextStyle(color: subtextColor, fontSize: 12), overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                        if (c.isBlocked)
                                          Text('Blocked', style: TextStyle(color: subtextColor, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
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
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<_BlockPickerContact>> _loadContacts(EngineService engine, String accountId, Set<String> blockedIds) async {
    final contacts = await engine.getContacts(accountId);
    return contacts.map((c) => _BlockPickerContact(
      id: c.userId,
      name: c.displayName.isNotEmpty ? c.displayName : (c.username.isNotEmpty ? '@${c.username}' : c.userId),
      status: c.username.isNotEmpty ? '@${c.username}' : (c.phone.isNotEmpty ? c.phone : ''),
      avatarB64: c.avatarB64,
      isBlocked: blockedIds.contains(c.userId),
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final topBarBg = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(54),
        child: Container(
          color: topBarBg,
          child: SafeArea(
            child: SizedBox(
              height: 54,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: textColor, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text('Blocked Users', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Container(height: 1, color: dividerColor),
          InkWell(
            onTap: _showBlockUserPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 22, 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.person_add, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text('Block User', style: TextStyle(color: accentColor, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: dividerColor),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _blockedUsers.isEmpty
                    ? _buildEmptyState(textColor, subtextColor)
                    : _buildBlockedList(textColor, subtextColor, accentColor),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color textColor, Color subtextColor) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 240),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedSettingsIcon(
                icon: Icons.block,
                size: 74,
                color: subtextColor.withValues(alpha: 0.5),
                backgroundColor: Colors.transparent,
              ),
              const SizedBox(height: 16),
              Text(
                'No blocked users',
                style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "You haven't blocked anyone yet.",
                style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedList(Color textColor, Color subtextColor, Color accentColor) {
    final itemCount = _blockedUsers.length + (_allLoaded ? 0 : 1);
    return ListView.builder(
      controller: _scrollController,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= _blockedUsers.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final user = _blockedUsers[index];
        final name = user['display_name'] as String? ?? '';
        final username = user['username'] as String? ?? '';
        final phone = user['phone'] as String? ?? '';
        final isBot = user['is_bot'] as bool? ?? false;
        final userId = user['id'] as String? ?? '';
        final avatarB64 = user['avatar_b64'] as String? ?? '';

        String status;
        if (isBot) {
          status = 'bot';
        } else if (phone.isNotEmpty) {
          status = phone;
        } else if (username.isNotEmpty) {
          status = '@$username';
        } else {
          status = '';
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              _blockedUserAvatar(avatarB64, name, 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : userId,
                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (status.isNotEmpty)
                      Text(status, style: TextStyle(color: subtextColor, fontSize: 12), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _unblockUser(userId),
                child: Text('Unblock', style: TextStyle(color: accentColor, fontSize: 14)),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _blockedUserAvatar(String avatarB64, String name, double size) {
    if (avatarB64.isNotEmpty) {
      try {
        final bytes = base64Decode(avatarB64);
        return ClipOval(child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover));
      } catch (_) {}
    }
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final colorIndex = name.isNotEmpty ? name.codeUnitAt(0) % 7 : 0;
    const colors = [
      Color(0xFFE17076), Color(0xFF7BC862), Color(0xFF65AADD),
      Color(0xFFEE7AE6), Color(0xFFFAA774), Color(0xFF6EC9CB),
      Color(0xFFE5679D),
    ];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors[colorIndex]),
      alignment: Alignment.center,
      child: Text(initial, style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.w600)),
    );
  }
}

class _BlockPickerContact {
  final String id;
  final String name;
  final String status;
  final String avatarB64;
  final bool isBlocked;

  const _BlockPickerContact({
    required this.id,
    required this.name,
    this.status = '',
    this.avatarB64 = '',
    this.isBlocked = false,
  });
}
