import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import 'settings_style.dart';

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
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _fetchPasswordState();
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
                onChanged: () => _loadPasscodeState(),
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
            Navigator.of(context).pushReplacement(settingsPageRoute(
              _LocalPasscodeManage(
                configDir: dir,
                onChanged: () => _loadPasscodeState(),
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
        _CloudPasswordStart(
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
        label: 'Passcode Lock',
        rightLabel: _hasPasscode ? 'On' : 'Off',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: _openPasscodeLock,
      ),
      if (_passkeysLoaded)
        _PrivacyIconRow(
          icon: Icons.fingerprint,
          label: 'Passkeys',
          rightLabel: _passkeysLabel,
          textColor: textColor,
          subtextColor: subtextColor,
          hoverBg: hoverBg,
          onTap: () {},
        ),
      if (_loginEmailPattern.isNotEmpty)
        _PrivacyIconRow(
          icon: Icons.email_outlined,
          label: 'Login Email',
          rightLabel: _loginEmailPattern,
          textColor: textColor,
          subtextColor: subtextColor,
          hoverBg: hoverBg,
          onTap: () {},
        ),
      _PrivacyIconRow(
        icon: Icons.block,
        label: 'Blocked Users',
        rightLabel: _blockedCount < 0 ? '...' : (_blockedCount == 0 ? 'None' : '$_blockedCount'),
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
      ),
      _PrivacyIconRow(
        icon: Icons.devices,
        label: 'Active Sessions',
        rightLabel: _sessionsCount < 0 ? '...' : '$_sessionsCount',
        textColor: textColor,
        subtextColor: subtextColor,
        hoverBg: hoverBg,
        onTap: () {},
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
        onTap: () {
          final newVal = !_archiveAndMute;
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
        },
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
                child: Switch(
                  value: _archiveAndMute,
                  onChanged: (v) {
                    setState(() => _archiveAndMute = v);
                    final engine = context.read<EngineService>();
                    final accountId = context.read<AppState>().activeAccountId;
                    if (accountId.isNotEmpty) {
                      engine.setArchiveSettings(
                        accountId,
                        archiveAndMute: v,
                        keepArchivedUnmuted: _archiveKeepUnmuted,
                        keepArchivedFolders: _archiveKeepFolders,
                      );
                    }
                  },
                  activeColor: accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    return [];
  }

  List<Widget> _buildConfirmationExtensionsSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [];
  }

  List<Widget> _buildTopPeersSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    return [];
  }

  List<Widget> _buildSelfDestructionSection(
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color hoverBg,
  ) {
    return [];
  }
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

  bool _giftShowIcon = true;
  bool _giftAcceptLimited = true;
  bool _giftAcceptUnlimited = true;
  bool _giftAcceptUnique = true;
  bool _giftAcceptFromChannels = true;
  bool _giftAcceptPremium = true;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Birthday saved'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set birthday: $e')),
        );
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
          final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
      widget.onSaved(
        _selected,
        addedByPhone: _isPhoneNumber ? _addedByPhoneOption : null,
        callsP2P: _isCalls ? _callsP2POption : null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
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
        setState(() {
          _hasFallbackPhoto = true;
          _uploadingFallback = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Public photo updated'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingFallback = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set public photo: $e')),
        );
      }
    }
  }

  Future<void> _removeFallbackPhoto() async {
    setState(() => _uploadingFallback = true);
    try {
      await widget.engine.deleteFallbackPhoto(widget.accountId);
      if (mounted) {
        setState(() {
          _hasFallbackPhoto = false;
          _uploadingFallback = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Public photo removed'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingFallback = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove public photo: $e')),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Subscribe to Telegram Premium to change gift settings.'),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
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
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Subscribe to Telegram Premium to restrict who can send you voice messages.'),
                        duration: Duration(seconds: 3),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Subscribe to Telegram Premium to restrict who can send you voice messages.'),
                                    duration: Duration(seconds: 3),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
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
            if (_isLastSeen && _selected != 'everyone') ...[
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

enum _CloudPasswordMode { check, create, change }

// ── CloudPasswordStart: Intro screen when no password set ──

class _CloudPasswordStart extends StatelessWidget {
  final String accountId;
  final EngineService engine;
  final VoidCallback onPasswordSet;

  const _CloudPasswordStart({
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
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

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
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline, size: 48, color: accentColor),
              ),
              const SizedBox(height: 19),
              Text(
                'Two-Step Verification',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Set an additional password that will be required to log in to your Telegram account.',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
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

  const _CloudPasswordInput({
    required this.accountId,
    required this.engine,
    required this.mode,
    required this.hint,
    required this.hasRecovery,
    required this.pendingResetDate,
    required this.onSuccess,
    this.currentPassword,
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

  bool get _isCreateMode => widget.mode == _CloudPasswordMode.create || widget.mode == _CloudPasswordMode.change;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _passwordFocus.requestFocus());
  }

  @override
  void dispose() {
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
        ),
      ));
      return;
    }

    setState(() { _loading = true; _error = ''; });
    try {
      await widget.engine.checkCloudPassword(widget.accountId, password);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(settingsPageRoute(
        _CloudPasswordManage(
          accountId: widget.accountId,
          engine: widget.engine,
          currentPassword: password,
          onChanged: widget.onSuccess,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('PASSWORD_HASH_INVALID')
            ? 'Wrong password. Please try again.'
            : 'Error: ${e.toString().replaceFirst('Exception: ', '')}';
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
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final errorColor = isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);

    final title = _isCreateMode ? 'Two-Step Verification' : 'Two-Step Verification';
    final subtitle = _isCreateMode ? 'Enter a new password' : 'Enter your password';
    final description = _isCreateMode
        ? 'Please create a password that you will remember.'
        : 'Your account is protected with an additional password.';

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
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isCreateMode ? Icons.lock_outline : Icons.vpn_key,
                  size: 48,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 19),
              Text(subtitle, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 5),
              Text(description, style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: _obscure,
                  onSubmitted: (_) => _isCreateMode ? FocusScope.of(context).nextFocus() : _submit(),
                  decoration: InputDecoration(
                    hintText: _isCreateMode ? 'Enter password' : 'Password',
                    hintStyle: TextStyle(color: subtextColor),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: subtextColor),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: subtextColor)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor, width: 2)),
                    errorBorder: UnderlineInputBorder(borderSide: BorderSide(color: errorColor)),
                  ),
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
              if (_isCreateMode) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Re-enter password',
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
              ],
              if (widget.hint.isNotEmpty && !_isCreateMode && _error.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Hint: ${widget.hint}', style: TextStyle(fontSize: 13, color: subtextColor)),
                ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error, style: TextStyle(fontSize: 13, color: errorColor)),
                ),
              if (!_isCreateMode && widget.hasRecovery) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {},
                  child: Text('Forgot password?', style: TextStyle(fontSize: 14, color: accentColor)),
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

  const _CloudPasswordHint({
    required this.accountId,
    required this.engine,
    required this.newPassword,
    required this.currentPassword,
    required this.onSuccess,
  });

  @override
  State<_CloudPasswordHint> createState() => _CloudPasswordHintState();
}

class _CloudPasswordHintState extends State<_CloudPasswordHint> {
  final _hintController = TextEditingController();
  final _hintFocus = FocusNode();
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hintFocus.requestFocus());
  }

  @override
  void dispose() {
    _hintController.dispose();
    _hintFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final hint = _hintController.text;
    if (hint == widget.newPassword) {
      setState(() => _error = 'Hint must be different from your password');
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
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
        title: Text('Password Hint', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lightbulb_outline, size: 48, color: accentColor),
              ),
              const SizedBox(height: 19),
              Text('Password Hint', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 5),
              Text(
                'You can create an optional hint for your password.',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _hintController,
                  focusNode: _hintFocus,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Password hint (optional)',
                    hintStyle: TextStyle(color: subtextColor),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: subtextColor)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor, width: 2)),
                  ),
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error, style: TextStyle(fontSize: 13, color: errorColor)),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Continue', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(settingsPageRoute(
                    _CloudPasswordEmail(
                      accountId: widget.accountId,
                      engine: widget.engine,
                      newPassword: widget.newPassword,
                      currentPassword: widget.currentPassword,
                      hint: '',
                      onSuccess: widget.onSuccess,
                    ),
                  ));
                },
                child: Text('Skip', style: TextStyle(fontSize: 14, color: subtextColor)),
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

  const _CloudPasswordEmail({
    required this.accountId,
    required this.engine,
    required this.newPassword,
    required this.currentPassword,
    required this.hint,
    required this.onSuccess,
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _emailFocus.requestFocus());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
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
      await widget.engine.setCloudPassword(
        widget.accountId,
        currentPassword: widget.currentPassword,
        newPassword: widget.newPassword,
        hint: widget.hint,
        email: email,
      );
      if (!mounted) return;
      widget.onSuccess();
      Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == 'privacy');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(email.isNotEmpty
                ? 'Password set. Please check your email to confirm.'
                : 'Two-Step Verification password has been set.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
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
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
        title: Text('Recovery Email', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.email_outlined, size: 48, color: accentColor),
              ),
              const SizedBox(height: 19),
              Text('Recovery Email', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 5),
              Text(
                'Please add your valid email. It is the only way to recover a forgotten password.',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Recovery email',
                    hintStyle: TextStyle(color: subtextColor),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: subtextColor)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor, width: 2)),
                  ),
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error, style: TextStyle(fontSize: 13, color: errorColor)),
                ),
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
                      : const Text('Continue', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading ? null : _skip,
                child: Text('Skip', style: TextStyle(fontSize: 14, color: subtextColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CloudPasswordEmailConfirm: Confirm recovery email ──

class _CloudPasswordEmailConfirm extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final String emailPattern;
  final VoidCallback onDone;

  const _CloudPasswordEmailConfirm({
    required this.accountId,
    required this.engine,
    required this.emailPattern,
    required this.onDone,
  });

  @override
  State<_CloudPasswordEmailConfirm> createState() => _CloudPasswordEmailConfirmState();
}

class _CloudPasswordEmailConfirmState extends State<_CloudPasswordEmailConfirm> {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _codeFocus.requestFocus());
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter the confirmation code');
      return;
    }

    setState(() { _loading = true; _error = ''; });
    try {
      await widget.engine.checkCloudPassword(widget.accountId, code);
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
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
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
        title: Text('Email Confirmation', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mark_email_read_outlined, size: 48, color: accentColor),
              ),
              const SizedBox(height: 19),
              Text('Check Your Email', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 5),
              Text(
                'Please enter the code we\'ve sent to ${widget.emailPattern}',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _codeController,
                  focusNode: _codeFocus,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Code',
                    hintStyle: TextStyle(color: subtextColor),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: subtextColor)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor, width: 2)),
                  ),
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error, style: TextStyle(fontSize: 13, color: errorColor)),
                ),
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
                      : const Text('Confirm', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CloudPasswordManage: Manage existing password ──

class _CloudPasswordManage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
        title: Text('Two-Step Verification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 19),
              Text(
                'Your password is set.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
              ),
              const SizedBox(height: 5),
              Text(
                'You have Two-Step Verification enabled, so your account is protected with an additional password.',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 300,
                child: Column(
                  children: [
                    _ManageRow(
                      icon: Icons.vpn_key,
                      label: 'Change Password',
                      textColor: textColor,
                      subtextColor: subtextColor,
                      hoverBg: hoverBg,
                      onTap: () {
                        Navigator.of(context).push(settingsPageRoute(
                          _CloudPasswordInput(
                            accountId: accountId,
                            engine: engine,
                            mode: _CloudPasswordMode.change,
                            hint: '',
                            hasRecovery: false,
                            pendingResetDate: 0,
                            onSuccess: onChanged,
                            currentPassword: currentPassword,
                          ),
                        ));
                      },
                    ),
                    _ManageRow(
                      icon: Icons.email_outlined,
                      label: 'Change Recovery Email',
                      textColor: textColor,
                      subtextColor: subtextColor,
                      hoverBg: hoverBg,
                      onTap: () {
                        Navigator.of(context).push(settingsPageRoute(
                          _CloudPasswordEmail(
                            accountId: accountId,
                            engine: engine,
                            newPassword: '',
                            currentPassword: currentPassword,
                            hint: '',
                            onSuccess: onChanged,
                          ),
                        ));
                      },
                    ),
                    _ManageRow(
                      icon: Icons.delete_outline,
                      label: 'Disable Password',
                      textColor: const Color(0xFFE53935),
                      subtextColor: subtextColor,
                      hoverBg: hoverBg,
                      onTap: () => _confirmDisable(context),
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

  void _confirmDisable(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
        title: Text('Disable Password', style: TextStyle(color: textColor)),
        content: Text(
          'Are you sure you want to disable your Two-Step Verification password?',
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

    try {
      await engine.removeCloudPassword(accountId, currentPassword);
      onChanged();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == 'privacy');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Two-Step Verification has been disabled.'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString().replaceFirst("Exception: ", "")}'), behavior: SnackBarBehavior.floating),
        );
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
    final wasZero = _selectedTTL == 0;
    final goingNonZero = period > 0;

    if (wasZero && goingNonZero) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Auto-Delete Messages'),
          content: Text(
            'Are you sure you want to enable auto-delete with a timer of ${_formatPeriod(period)}? '
            'All new messages in chats you start will be automatically deleted after this period.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enable'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${e.toString().replaceFirst("Exception: ", "")}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
              child: Icon(
                Icons.timer_outlined,
                size: 100,
                color: accentColor,
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
      'autoLockSeconds': 0,
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
          'Passcode Lock',
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
              Container(
                width: 100,
                height: 100,
                margin: const EdgeInsets.only(top: 19, bottom: 5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline, size: 48, color: accentColor),
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

    setState(() {
      _loading = true;
      _error = '';
    });

    final data = await _readPasscodeData(widget.configDir);
    final storedHash = data['hash'] as String? ?? '';

    if (!mounted) return;

    if (_hashPasscode(entered) == storedHash) {
      widget.onSuccess();
    } else {
      setState(() {
        _loading = false;
        _error = 'Wrong passcode';
      });
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
          'Passcode Lock',
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
              Container(
                width: 100,
                height: 100,
                margin: const EdgeInsets.only(top: 19, bottom: 5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline, size: 48, color: accentColor),
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

  @override
  void initState() {
    super.initState();
    _loadAutoLock();
  }

  Future<void> _loadAutoLock() async {
    final data = await _readPasscodeData(widget.configDir);
    if (!mounted) return;
    setState(
        () => _autoLockSeconds = data['autoLockSeconds'] as int? ?? 0);
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
          'Passcode Lock',
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
  static const _presets = [0, 60, 300, 3600, 18000];
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
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

    final labels = {
      0: 'Disabled',
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
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
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Subscribe to Telegram Premium to restrict who can send you messages.'),
                          duration: Duration(seconds: 3),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
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
                              if (v != null && !isPremiumLocked) {
                                setState(() => _selected = v);
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
