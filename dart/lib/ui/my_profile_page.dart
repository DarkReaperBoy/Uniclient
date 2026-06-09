import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../data/emoji_data.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import 'birthday_picker.dart';
import 'clipboard_image.dart';
import 'compose_entities.dart';
import 'confirm_box.dart';
import 'forum_topic_icon.dart';
import 'input_dialogs.dart';
import 'media_viewer.dart';
import 'photo_crop_editor.dart';
import 'telegram_toast.dart';
import 'popup_menu.dart';
import 'privacy_settings_screen.dart';
import 'settings_style.dart';
import 'package:uniclient/utils/debug.dart';

/// "My Profile" / "Edit Profile" page (§14.5).
/// Opened from hamburger drawer "My Profile" row or Settings "My Account".
/// Shows profile photo, bio input, name, phone, username with copy/edit affordances.
class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  final _bioController = RichTextEditingController();
  Timer? _debounceTimer;
  Timer? _statusRefreshTimer;
  StreamSubscription? _statusSub;
  String _savedBio = '';
  bool _bioLoaded = false;
  int _selfColorId = -1;
  // Four distinct current color values seeded into the EditPeerColorBox, mirroring
  // AyuGram's edit_peer_color_box.cpp:501-506 (name color / name background emoji /
  // profile color / profile background emoji). _selfProfileColorId is -1 when unset.
  int _selfBgEmojiId = 0;
  int _selfProfileColorId = -1;
  int _selfProfileEmojiId = 0;
  String _personalChannelName = '';
  bool _colorChannelLoaded = false;
  int _birthdayDay = 0;
  int _birthdayMonth = 0;
  int _birthdayYear = 0;
  bool _birthdayLoaded = false;
  String _birthdayPrivacy = 'contacts';
  bool _birthdayPrivacyExact = true;
  String _statusText = '';
  bool _isStatusOnline = false;
  UserProfile? _cachedProfile;

  @override
  void initState() {
    super.initState();
    // The bio is a rich field so custom-emoji suggestions insert real
    // DocumentId-backed entities that render inline (mirroring AyuGram's
    // Ui::InputField + Ui::Emoji::SuggestionsController — settings_information.cpp:744),
    // not a flattened fallback glyph. On save the entities collapse back to their
    // alt text (account.updateProfile carries no entities — apiwrap.cpp:4997).
    final engine = context.read<EngineService>();
    _bioController.accountId = context.read<AppState>().activeAccount?.id ?? '';
    _bioController.customEmojiBuilder = (docId, accId, altText, segStart) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: CustomEmojiTopicIcon(
        key: ValueKey('bio_ce_${docId}_$segStart'),
        documentId: docId,
        accountId: accId,
        engine: engine,
        size: 18,
      ),
    );
    _loadBio();
    _loadColorAndChannel();
    _loadBirthday();
    _loadStatus();
    _subscribeToStatusEvents();
  }

  @override
  void dispose() {
    _flushBio();
    _debounceTimer?.cancel();
    _statusRefreshTimer?.cancel();
    _statusSub?.cancel();
    _bioController.dispose();
    super.dispose();
  }

  void _subscribeToStatusEvents() {
    final engine = context.read<EngineService>();
    _statusSub = engine.onUserStatus.listen((event) {
      final appState = context.read<AppState>();
      final account = appState.activeAccount;
      if (account == null) return;
      if (event.userId == account.selfUserId || event.accountId == account.id) {
        _refreshStatus();
      }
    });
  }

  void _scheduleStatusRefresh() {
    _statusRefreshTimer?.cancel();
    if (!_isStatusOnline && _cachedProfile != null && _cachedProfile!.lastSeen > 0) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - _cachedProfile!.lastSeen;
      final refreshIn = elapsed < 60000 ? const Duration(seconds: 30) : const Duration(minutes: 1);
      _statusRefreshTimer = Timer(refreshIn, _refreshStatus);
    }
  }

  void _refreshStatus() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null || account.selfUserId.isEmpty) return;
    final engine = context.read<EngineService>();
    engine.getUserProfile(account.id, account.selfUserId).then((profile) {
      if (!mounted || profile == null) return;
      _cachedProfile = profile;
      final newStatus = _computeStatusText(account.connState, profile);
      final online = newStatus == 'online';
      if (newStatus != _statusText || online != _isStatusOnline) {
        setState(() {
          _statusText = newStatus;
          _isStatusOnline = online;
        });
      }
      _scheduleStatusRefresh();
    });
  }

  void _loadBio() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.getSelfBio(account.id).then((bio) {
      if (!mounted) return;
      setState(() {
        _savedBio = bio;
        _bioController.setTextWithEntities(bio, '');
        _bioLoaded = true;
      });
    });
  }

  void _loadColorAndChannel() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.getSelfColorAndChannel(account.id).then((result) {
      if (!mounted) return;
      setState(() {
        _selfColorId = result.colorId;
        _selfBgEmojiId = result.backgroundEmojiId;
        _selfProfileColorId = result.profileColorId;
        _selfProfileEmojiId = result.profileEmojiId;
        _personalChannelName = result.channelName;
        _colorChannelLoaded = true;
      });
    });
  }

  void _loadBirthday() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.getSelfBirthday(account.id).then((result) {
      if (!mounted) return;
      setState(() {
        _birthdayDay = result.day;
        _birthdayMonth = result.month;
        _birthdayYear = result.year;
        _birthdayLoaded = true;
      });
    });
    engine.getPrivacySetting(account.id, 'birthday').then((result) {
      if (!mounted || result == null) return;
      final rule = result['option'] as String? ?? result['rule'] as String? ?? 'contacts';
      final alwaysUsers = result['always_users'] as List? ?? [];
      final neverUsers = result['never_users'] as List? ?? [];
      final alwaysChats = result['always_chats'] as List? ?? [];
      final neverChats = result['never_chats'] as List? ?? [];
      final allowPremium = result['allow_premium'] as bool? ?? false;
      final isExact = alwaysUsers.isEmpty && neverUsers.isEmpty &&
          alwaysChats.isEmpty && neverChats.isEmpty && !allowPremium;
      setState(() {
        _birthdayPrivacy = rule;
        _birthdayPrivacyExact = isExact;
      });
    });
  }

  void _loadStatus() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    if (account.connState == ConnState.connected) {
      setState(() { _statusText = 'online'; _isStatusOnline = true; });
    } else if (account.connState == ConnState.connecting) {
      setState(() { _statusText = 'connecting...'; _isStatusOnline = false; });
    } else {
      setState(() { _statusText = 'waiting for network...'; _isStatusOnline = false; });
    }
    if (account.selfUserId.isEmpty) return;
    final engine = context.read<EngineService>();
    engine.getUserProfile(account.id, account.selfUserId).then((profile) {
      if (!mounted || profile == null) return;
      _cachedProfile = profile;
      final newStatus = _computeStatusText(account.connState, profile);
      setState(() {
        _statusText = newStatus;
        _isStatusOnline = newStatus == 'online';
      });
      _scheduleStatusRefresh();
    });
  }

  static String _computeStatusText(ConnState connState, UserProfile profile) {
    if (connState == ConnState.connected) return 'online';
    if (connState == ConnState.connecting) return 'connecting...';
    if (profile.isOnline) return 'online';
    switch (profile.lastSeenKind) {
      case 'online':
        return 'online';
      case 'recently':
      case 'hidden':
        return 'last seen recently';
      case 'within_week':
        return 'last seen within a week';
      case 'within_month':
        return 'last seen within a month';
      case 'long_ago':
        return 'last seen a long time ago';
      case 'exact':
        if (profile.lastSeen > 0) {
          final dt = DateTime.fromMillisecondsSinceEpoch(profile.lastSeen);
          final now = DateTime.now();
          final diff = now.difference(dt);
          if (diff.inMinutes < 1) return 'last seen just now';
          if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';
          if (diff.inHours < 12) return 'last seen ${diff.inHours}h ago';
          if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
            final h = dt.hour.toString().padLeft(2, '0');
            final m = dt.minute.toString().padLeft(2, '0');
            return 'last seen today at $h:$m';
          }
          final yesterday = now.subtract(const Duration(days: 1));
          if (dt.day == yesterday.day && dt.month == yesterday.month && dt.year == yesterday.year) {
            final h = dt.hour.toString().padLeft(2, '0');
            final m = dt.minute.toString().padLeft(2, '0');
            return 'last seen yesterday at $h:$m';
          }
          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          return 'last seen ${months[dt.month - 1]} ${dt.day}';
        }
        return 'last seen recently';
      default:
        return connState == ConnState.unstable ? 'updating...' : 'waiting for network...';
    }
  }

  void _pickBirthday() async {
    final result = await showDialog<({int day, int month, int year})>(
      context: context,
      builder: (ctx) => BirthdayDrumPickerDialog(
        initialDay: _birthdayDay > 0 ? _birthdayDay : DateTime.now().day,
        initialMonth: _birthdayMonth > 0 ? _birthdayMonth : DateTime.now().month,
        initialYear: _birthdayYear > 0 ? _birthdayYear : 0,
        hasExisting: _birthdayDay > 0 && _birthdayMonth > 0,
      ),
    );
    if (result == null || !mounted) return;
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    try {
      if (result.day == 0 && result.month == 0 && result.year == 0) {
        await engine.updateBirthday(account.id, 0, 0, 0);
        if (mounted) {
          setState(() {
            _birthdayDay = 0;
            _birthdayMonth = 0;
            _birthdayYear = 0;
          });
          showTelegramToast(context, 'Birthday removed');
        }
      } else {
        await engine.updateBirthday(account.id, result.day, result.month, result.year);
        if (mounted) {
          setState(() {
            _birthdayDay = result.day;
            _birthdayMonth = result.month;
            _birthdayYear = result.year;
          });
          showTelegramToast(context, 'Birthday saved');
        }
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to update birthday: $e');
      }
    }
  }

  static const _instantReplaces = {
    '--': '—', '<<': '«', '>>': '»',
    ':shrug:': '¯\\_(ツ)_/¯',
    ':-)': '😊', ':)': '😊', ':-D': '😃', ':D': '😃',
    ';-)': '😉', ';)': '😉', ':-(': '😞', ':(': '😞',
    ':-P': '😛', ':P': '😛', ':-p': '😛', ':p': '😛',
    ':-O': '😮', ':O': '😮', ':-o': '😮', ':o': '😮',
    '<3': '❤️', '>:(': '😠', ':-/': '😕', ':/': '😕',
    ':-|': '😐', ':|': '😐', ":'(": '😢',
    'B-)': '😎', 'B)': '😎', ':*': '😘',
    'O:)': '😇', 'o:)': '😇', '>:)': '😈',
  };

  void _onBioChanged(String value) {
    final text = _bioController.text;
    final sel = _bioController.selection;
    final replaceEnabled = context.read<AppState>().chatReplaceEmojis;
    if (replaceEnabled && sel.isValid && sel.baseOffset == sel.extentOffset) {
      final cursor = sel.baseOffset;
      for (final entry in _instantReplaces.entries) {
        final pat = entry.key;
        if (cursor >= pat.length && text.substring(cursor - pat.length, cursor) == pat) {
          final before = text.substring(0, cursor - pat.length);
          final after = text.substring(cursor);
          final replaced = '$before${entry.value}$after';
          final newCursor = before.length + entry.value.length;
          _bioController.value = TextEditingValue(
            text: replaced,
            selection: TextSelection.collapsed(offset: newCursor),
          );
          break;
        }
      }
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _saveBio();
    });
  }

  /// Flattens custom-emoji entities to their fallback alt text, mirroring
  /// AyuGram's `bio->getLastText()` which represents an inserted custom emoji by
  /// its base emoji when saving — `account.updateProfile` carries no entities
  /// (apiwrap.cpp:4997, settings_information.cpp:693-695). With no custom emoji
  /// this is identical to the raw field text.
  String _flattenBio() {
    var text = _bioController.text;
    final emojiEnts = _bioController.entities
        .where((e) => e.type == FormatType.customEmoji)
        .toList()
      ..sort((a, b) => b.offset.compareTo(a.offset));
    for (final e in emojiEnts) {
      if (e.offset < 0 || e.offset + e.length > text.length) continue;
      final alt = e.altText ?? '';
      text = text.substring(0, e.offset) + alt + text.substring(e.offset + e.length);
    }
    return text;
  }

  void _saveBio() {
    final value = _flattenBio();
    if (value == _savedBio) return;
    final bioLimit = _isPremium ? 140 : 70;
    if (value.length > bioLimit) return;
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    engine.updateBio(account.id, value).then((_) {
      if (mounted) _savedBio = value;
    });
  }

  void _flushBio() {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      _saveBio();
    }
  }

  bool get _isPremium => context.read<AppState>().effectivePremium;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = context.watch<AppState>();
    final account = appState.activeAccount;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final dividerColor = isDark
        ? const Color(0xFF101921)
        : const Color(0xFFF1F1F1);

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
          'Edit Profile',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: Builder(builder: (_) {
        final _lvKids = <Widget>[
          _ProfilePhotoArea(account: account, isDark: isDark, statusText: _statusText, isStatusOnline: _isStatusOnline),
          Container(height: 8, color: dividerColor),
          _BioInput(
            controller: _bioController,
            isDark: isDark,
            isPremium: _isPremium,
            bioLoaded: _bioLoaded,
            onChanged: _onBioChanged,
            onSubmitted: () {
              _debounceTimer?.cancel();
              _saveBio();
            },
          ),
          Container(height: 8, color: dividerColor),
          _ProfileInfoRow(
            icon: Icons.person,
            iconBg: const Color(0xFF5E97F6),
            label: 'Name',
            value: account?.displayName ?? '',
            isDark: isDark,
            copyMenuLabel: 'Copy Full Name',
            onTap: () => _showEditNameBox(context, account),
          ),
          _rowDivider(isDark),
          _ProfileInfoRow(
            icon: Icons.phone,
            iconBg: const Color(0xFF4CAF50),
            label: 'Phone Number',
            value: account?.phone ?? '',
            isDark: isDark,
            copyMenuLabel: 'Copy Phone Number',
            onTap: () {
              final phone = account?.phone ?? '';
              if (phone.isEmpty) return;
              Clipboard.setData(ClipboardData(text: phone));
              showTelegramToast(context, 'Phone number copied',
                  duration: const Duration(milliseconds: 500));
            },
          ),
          _rowDivider(isDark),
          _ProfileInfoRow(
            icon: Icons.alternate_email,
            iconBg: const Color(0xFF9C27B0),
            label: 'Username',
            value: account != null && account.username.isNotEmpty
                ? '@${account.username}'
                : 'Set username',
            isDark: isDark,
            copyMenuLabel: 'Copy @mention',
            onTap: () async {
              if (account == null) return;
              await showUsernameBox(
                context,
                accountId: account.id,
                currentUsername: account.username,
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: Text(
              'People can message you using your username without knowing your phone number.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
          ),
          // AyuGram lays out Personal Channel + the name-color button
          // (SetupPersonalChannel) BEFORE the birthday (SetupBirthday) —
          // settings_information.cpp:1288-1289.
          Container(height: 8, color: dividerColor),
          _PersonalChannelRow(
            channelName: _personalChannelName,
            isDark: isDark,
            loaded: _colorChannelLoaded,
            onChannelChanged: (name) => setState(() => _personalChannelName = name),
          ),
          _rowDivider(isDark),
          _YourColorRow(
            colorId: _selfColorId,
            bgEmojiId: _selfBgEmojiId,
            profileColorId: _selfProfileColorId,
            profileEmojiId: _selfProfileEmojiId,
            isDark: isDark,
            loaded: _colorChannelLoaded,
            accountId: account?.id,
            onColorChanged: (newColorId) {
              setState(() => _selfColorId = newColorId);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: Text(
              'Choose your name color that will be seen by others in chats.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
          ),
          Container(height: 8, color: dividerColor),
          _BirthdayRow(
            day: _birthdayDay,
            month: _birthdayMonth,
            year: _birthdayYear,
            isDark: isDark,
            loaded: _birthdayLoaded,
            onTap: _pickBirthday,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text.rich(
              TextSpan(
                text: _birthdayPrivacy == 'nobody'
                    ? 'Your birthday is not visible to anyone. '
                    : _birthdayPrivacy == 'everyone'
                        ? 'Your birthday is visible to everyone. '
                        : _birthdayPrivacyExact
                            ? 'Your birthday is visible to '
                            : 'Your birthday visibility: ',
                style: TextStyle(fontSize: 13, color: subtextColor),
                children: [
                  if (_birthdayPrivacy != 'nobody' && _birthdayPrivacy != 'everyone')
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
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
                        child: Text(
                          !_birthdayPrivacyExact
                              ? 'custom'
                              : _birthdayPrivacy == 'close_friends'
                                  ? 'your close friends'
                                  : 'your contacts',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? const Color(0xFF6AB3F3)
                                : const Color(0xFF168ACD),
                          ),
                        ),
                      ),
                    ),
                  if (_birthdayPrivacy != 'nobody' && _birthdayPrivacy != 'everyone')
                    const TextSpan(text: '. '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
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
                      child: Text(
                        'Manage',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFF6AB3F3)
                              : const Color(0xFF168ACD),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 8, color: dividerColor),
          _AccountsSection(isDark: isDark),
        ];
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      }),
    );
  }

  void _showEditNameBox(BuildContext context, AccountInfo? account) {
    if (account == null) return;
    final names = account.displayName.split(RegExp(r'\s+'));
    final firstCtrl = TextEditingController(text: names.isNotEmpty ? names[0] : '');
    final lastCtrl = TextEditingController(text: names.length > 1 ? names.sublist(1).join(' ') : '');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 364),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Your Name',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: firstCtrl,
                  autofocus: true,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'First Name',
                    labelStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: textColor.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastCtrl,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Last Name (optional)',
                    labelStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: textColor.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('Cancel', style: TextStyle(color: accentColor)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final first = firstCtrl.text.trim();
                        if (first.isEmpty) return;
                        final last = lastCtrl.text.trim();
                        Navigator.of(ctx).pop();
                        try {
                          final engine = context.read<EngineService>();
                          await engine.updateProfile(account.id, first, last);
                          if (mounted) {
                            showTelegramToast(context, 'Name updated');
                          }
                        } catch (e) {
                          if (mounted) {
                            showTelegramToast(context, 'Failed to update name: $e');
                          }
                        }
                      },
                      child: Text('Save', style: TextStyle(color: accentColor)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _rowDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Container(
        height: 1,
        color: isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1),
      ),
    );
  }

  static void _copyToClipboard(BuildContext context, String value, String label) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    showTelegramToast(context, '$label copied to clipboard');
  }
}

/// §14.5.2: Bio input field — transparent multiline, margins 22/6/22/4px,
/// 32px min height, character counter (grey ≥0 / red <0), 70-char limit
/// (140 Premium), debounced 1000ms auto-save, footer text.
class _BioInput extends StatefulWidget {
  final RichTextEditingController controller;
  final bool isDark;
  final bool isPremium;
  final bool bioLoaded;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  const _BioInput({
    required this.controller,
    required this.isDark,
    required this.isPremium,
    required this.bioLoaded,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  State<_BioInput> createState() => _BioInputState();
}

class _BioEmojiSuggestion {
  final EmojiEntry? unicodeEntry;
  final StickerInfoItem? customEmoji;
  final int? customDocId;
  const _BioEmojiSuggestion({this.unicodeEntry, this.customEmoji, this.customDocId});
  bool get isCustom => customEmoji != null;
  String get insertText => unicodeEntry?.emoji ?? customEmoji?.emoji ?? '';
}

class _BioInputState extends State<_BioInput> {
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  List<_BioEmojiSuggestion> _emojiSuggestions = [];
  int _emojiSelectedIndex = 0;
  int _emojiTriggerOffset = -1;
  OverlayEntry? _overlayEntry;
  List<CustomEmojiSetSummary>? _cachedEmojiPacks;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = (node, event) {
      if (_handleEmojiKey(event)) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    };
    _loadCustomEmojiPacks();
  }

  Future<void> _loadCustomEmojiPacks() async {
    try {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      final acc = appState.activeAccount;
      if (acc == null) return;
      final packs = await engine.getInstalledEmojiSets(acc.id);
      if (mounted) _cachedEmojiPacks = packs;
    } catch (e) {
      Debug.log('my_profile_page', 'final engine = context.read<EngineService>(): $e');
    }
  }

  @override
  void dispose() {
    _dismissOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  void _dismissOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    _dismissOverlay();
    if (_emojiSuggestions.isEmpty) return;
    _overlayEntry = OverlayEntry(builder: (ctx) {
      final isDark = widget.isDark;
      final bgColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFFFFFFF);
      final borderColor = isDark ? const Color(0xFF101a23) : const Color(0xFFdadada);
      final hoverColor = isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8);
      return Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, -52),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: bgColor,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                itemCount: _emojiSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _emojiSuggestions[index];
                  final isSelected = index == _emojiSelectedIndex;
                  return MouseRegion(
                    onEnter: (_) {
                      _emojiSelectedIndex = index;
                      _overlayEntry?.markNeedsBuild();
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _insertSuggestion(_emojiSuggestions[index]),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected ? hoverColor : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.center,
                        child: suggestion.isCustom
                            ? _buildCustomEmojiThumb(suggestion.customEmoji!)
                            : Text(suggestion.unicodeEntry!.emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _checkEmojiAutocomplete() {
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (_emojiSuggestions.isNotEmpty) {
        setState(() => _emojiSuggestions = []);
        _dismissOverlay();
      }
      return;
    }
    final text = widget.controller.text;
    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor > text.length) {
      if (_emojiSuggestions.isNotEmpty) {
        setState(() => _emojiSuggestions = []);
        _dismissOverlay();
      }
      return;
    }
    final before = text.substring(0, cursor);
    final match = RegExp(r'(?:^|(?<=\s)):(\w{2,})$').firstMatch(before);
    if (match != null) {
      final query = match.group(1)!;
      final triggerOffset = match.start + match.group(0)!.indexOf(':');
      final unicodeResults = searchEmoji(query, limit: 15);
      final suggestions = <_BioEmojiSuggestion>[];
      for (final e in unicodeResults) {
        suggestions.add(_BioEmojiSuggestion(unicodeEntry: e));
      }
      // Search custom emoji from installed packs: match stickers whose associated
      // emoji is in the Unicode results, or whose pack title matches the query.
      if (_cachedEmojiPacks != null) {
        final matchedUnicodeEmoji = unicodeResults.map((e) => e.emoji).toSet();
        final queryLower = query.toLowerCase();
        for (final pack in _cachedEmojiPacks!) {
          for (final sticker in pack.stickers) {
            if (suggestions.length >= 20) break;
            final docId = int.tryParse(sticker.fileId) ?? 0;
            if (docId == 0) continue;
            if (matchedUnicodeEmoji.contains(sticker.emoji) ||
                pack.title.toLowerCase().contains(queryLower)) {
              suggestions.add(_BioEmojiSuggestion(
                customEmoji: sticker,
                customDocId: docId,
              ));
            }
          }
          if (suggestions.length >= 20) break;
        }
      }
      setState(() {
        _emojiSuggestions = suggestions.take(20).toList();
        _emojiSelectedIndex = 0;
        _emojiTriggerOffset = triggerOffset;
      });
      _showOverlay();
    } else {
      if (_emojiSuggestions.isNotEmpty) {
        setState(() => _emojiSuggestions = []);
        _dismissOverlay();
      }
    }
  }

  void _insertSuggestion(_BioEmojiSuggestion suggestion) {
    final sel = widget.controller.selection;
    if (!sel.isValid) return;
    final cursor = sel.baseOffset;
    if (suggestion.isCustom && (suggestion.customDocId ?? 0) != 0) {
      // Select the ":query" trigger, then replace it with a real DocumentId-backed
      // custom-emoji entity that renders inline — matching AyuGram's
      // SuggestionsController, which inserts the animated custom emoji, not the
      // fallback glyph (settings_information.cpp:744). The entity flattens back to
      // its alt text on save (see _flattenBio).
      widget.controller.selection = TextSelection(
        baseOffset: _emojiTriggerOffset,
        extentOffset: cursor,
      );
      widget.controller.insertCustomEmoji(
        suggestion.customDocId!,
        suggestion.customEmoji?.emoji ?? '',
      );
    } else {
      final text = widget.controller.text;
      final insertText = suggestion.insertText;
      final newText = text.substring(0, _emojiTriggerOffset) +
          insertText +
          text.substring(cursor);
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
            offset: _emojiTriggerOffset + insertText.length),
      );
    }
    setState(() => _emojiSuggestions = []);
    _dismissOverlay();
    widget.onChanged(widget.controller.text);
  }

  bool _handleEmojiKey(KeyEvent event) {
    if (_emojiSuggestions.isEmpty) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _emojiSelectedIndex = (_emojiSelectedIndex + 1).clamp(0, _emojiSuggestions.length - 1);
      _overlayEntry?.markNeedsBuild();
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _emojiSelectedIndex = (_emojiSelectedIndex - 1).clamp(0, _emojiSuggestions.length - 1);
      _overlayEntry?.markNeedsBuild();
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _insertSuggestion(_emojiSuggestions[_emojiSelectedIndex]);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _emojiSuggestions = []);
      _dismissOverlay();
      return true;
    }
    return false;
  }

  Widget _buildCustomEmojiThumb(StickerInfoItem sticker) {
    if (sticker.thumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(sticker.thumbB64);
        return Image.memory(bytes, width: 28, height: 28, fit: BoxFit.contain);
      } catch (e) {
        Debug.log('my_profile_page', 'final bytes = base64Decode(sticker.thumbB64): $e');
      }
    }
    return Text(sticker.emoji, style: const TextStyle(fontSize: 24));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final maxLen = widget.isPremium ? 140 : 70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompositedTransformTarget(
          link: _layerLink,
          child: Stack(
            children: [
              Padding(
                padding: SettingsStyle.bioMargins,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    enabled: widget.bioLoaded,
                    style: TextStyle(fontSize: 14, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Bio',
                      hintStyle: TextStyle(fontSize: 14, color: subtextColor),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(maxLen * 2),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final stripped = newValue.text.replaceAll('\n', ' ');
                        if (stripped == newValue.text) return newValue;
                        return newValue.copyWith(text: stripped);
                      }),
                    ],
                    onChanged: (value) {
                      widget.onChanged(value);
                      _checkEmojiAutocomplete();
                    },
                    onSubmitted: (_) => widget.onSubmitted(),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 22,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) {
                    final remaining = maxLen - value.text.length;
                    final counterColor = remaining < 0
                        ? const Color(0xFFE53935)
                        : subtextColor;
                    return Text(
                      '$remaining',
                      style: TextStyle(fontSize: 13, color: counterColor),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            'Any details such as age, occupation or city.',
            style: TextStyle(fontSize: 13, color: subtextColor),
          ),
        ),
      ],
    );
  }
}

// Emoji suggestions are now shown as an overlay popup via _BioInputState._showOverlay(),
// matching AyuGram's SuggestionsController popup behavior.

/// §14.5.1: Profile photo area — 162px height, 100x100 avatar centered,
/// upload sub-button at bottom-right, name (17px semibold, 24px max height),
/// online status below name.
class _ProfilePhotoArea extends StatefulWidget {
  final AccountInfo? account;
  final bool isDark;
  final String statusText;
  final bool isStatusOnline;

  const _ProfilePhotoArea({
    required this.account,
    required this.isDark,
    this.statusText = '',
    this.isStatusOnline = false,
  });

  @override
  State<_ProfilePhotoArea> createState() => _ProfilePhotoAreaState();
}

class _ProfilePhotoAreaState extends State<_ProfilePhotoArea> {
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _optimisticAvatarPath;

  Widget _clipAvatar(Widget child, double size) {
    final appState = context.read<AppState>();
    final corners = appState.avatarCorners;
    if (corners >= 23) {
      return ClipOval(child: child);
    } else if (corners <= 0) {
      return ClipRect(child: child);
    } else {
      final r = corners / 23.0 * size / 2.0;
      return ClipRRect(borderRadius: BorderRadius.circular(r), child: child);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final account = widget.account;
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    final palette = context.palette;
    final name = account?.displayName ?? '';
    final initials = _initials(name);
    final id = account?.id ?? '';
    final numId = int.tryParse(id) ?? id.hashCode.abs();
    final color = palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);

    final avatarPath = _optimisticAvatarPath ?? account?.avatarPath ?? '';

    return SizedBox(
      height: 162,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 2),
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: account != null && avatarPath.isNotEmpty
                        ? () => _openProfilePhotoViewer(context, account!)
                        : null,
                    child: avatarPath.isNotEmpty
                        ? _clipAvatar(
                            Image.file(
                              File(avatarPath),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                              cacheHeight: 200,
                              errorBuilder: (_, __, ___) =>
                                  _avatarFallback(color, initials),
                            ),
                            100,
                          )
                        : _avatarFallback(color, initials),
                  ),
                ),
                if (_uploading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          value: _uploadProgress > 0 ? _uploadProgress : null,
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: -6,
                  bottom: 0,
                  child: _UploadSubButton(
                    isDark: isDark,
                    onTap: () => _showAvatarMenu(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          if (name.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 24),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (account != null)
            Transform.translate(
              offset: const Offset(0, -1),
              child: Text(
                widget.statusText.isNotEmpty ? widget.statusText : (account.connState == ConnState.connected ? 'online' : 'connecting...'),
                style: TextStyle(
                  fontSize: 13,
                  color: widget.isStatusOnline || (widget.statusText.isEmpty && account.connState == ConnState.connected)
                      ? context.palette.windowActiveTextFg
                      : subtextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAvatarMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      renderBox.localToGlobal(Offset.zero) & renderBox.size,
      Offset.zero & overlay.size,
    );
    final avatarPath = _optimisticAvatarPath ?? widget.account?.avatarPath ?? '';
    final hasAvatar = avatarPath.isNotEmpty;
    showMenu<String>(
      context: context,
      position: position,
      items: [
        if (hasAvatar)
          const PopupMenuItem<String>(
            value: 'view',
            child: Row(
              children: [
                Icon(Icons.visibility_outlined, size: 20),
                SizedBox(width: 12),
                Text('View Photo'),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'photo',
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined, size: 20),
              SizedBox(width: 12),
              Text('Upload Photo'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'clipboard',
          child: Row(
            children: [
              Icon(Icons.content_paste, size: 20),
              SizedBox(width: 12),
              Text('From Clipboard'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'emoji',
          child: Row(
            children: [
              Icon(Icons.emoji_emotions_outlined, size: 20),
              SizedBox(width: 12),
              Text('Set Emoji'),
            ],
          ),
        ),
        // Self-user "Set Public Photo" privacy action — opens the profile-photo
        // EditPrivacyBox (ProfilePhoto privacy key), matching AyuGram's ChoosePhoto
        // sub-button menu (userpic_button.cpp:448-467).
        const PopupMenuItem<String>(
          value: 'public',
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 20),
              SizedBox(width: 12),
              Text('Set Public Photo'),
            ],
          ),
        ),
        if (hasAvatar)
          const PopupMenuItem<String>(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: Color(0xFFE53935)),
                SizedBox(width: 12),
                Text('Remove Photo', style: TextStyle(color: Color(0xFFE53935))),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'view') {
        if (widget.account != null) {
          _openProfilePhotoViewer(context, widget.account!);
        }
      } else if (value == 'photo') {
        _pickAndUploadPhoto(context);
      } else if (value == 'clipboard') {
        _pastePhotoFromClipboard(context);
      } else if (value == 'emoji') {
        _openEmojiBuilder(context);
      } else if (value == 'public') {
        if (mounted) showProfilePhotoPrivacyBox(context);
      } else if (value == 'remove') {
        _removeProfilePhoto(context);
      }
    });
  }

  void _removeProfilePhoto(BuildContext context) async {
    final account = widget.account;
    if (account == null) return;
    final engine = context.read<EngineService>();
    try {
      await engine.deleteProfilePhotos(account.id);
      if (mounted) {
        setState(() => _optimisticAvatarPath = null);
        showTelegramToast(context, 'Photo removed');
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to remove photo: $e');
      }
    }
  }

  void _pickAndUploadPhoto(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    if (!context.mounted) return;

    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id;
    if (accountId == null) return;
    final engine = context.read<EngineService>();

    await PhotoCropEditor.open(
      context,
      imageFile: File(path),
      shape: PhotoCropShape.ellipse,
      purpose: PhotoEditorPurpose.setPhoto,
      onDone: (croppedFile) async {
        if (!mounted) return;
        setState(() {
          _uploading = true;
          _uploadProgress = 0;
          _optimisticAvatarPath = croppedFile.path;
        });
        try {
          await engine.uploadProfilePhoto(accountId, croppedFile.path);
          if (mounted) {
            setState(() { _uploading = false; _uploadProgress = 1.0; });
            showTelegramToast(context, 'Profile photo updated');
          }
        } catch (e) {
          if (mounted) {
            setState(() { _uploading = false; _optimisticAvatarPath = null; });
            showTelegramToast(context, 'Failed to upload photo: $e');
          }
        }
      },
    );
  }

  void _pastePhotoFromClipboard(BuildContext context) async {
    final Uint8List? imageBytes;
    try {
      imageBytes = await getClipboardImage();
    } on ClipboardToolMissingException catch (e) {
      if (mounted) showTelegramToast(context, e.message);
      return;
    }
    if (imageBytes == null) {
      if (mounted) showTelegramToast(context, 'No image in clipboard');
      return;
    }
    final tmpFile = File('${Directory.systemTemp.path}/uniclient_paste_avatar.png');
    await tmpFile.writeAsBytes(imageBytes);
    if (!mounted) return;

    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id;
    if (accountId == null) return;
    final engine = context.read<EngineService>();

    await PhotoCropEditor.open(
      context,
      imageFile: tmpFile,
      shape: PhotoCropShape.ellipse,
      purpose: PhotoEditorPurpose.setPhoto,
      onDone: (croppedFile) async {
        if (!mounted) return;
        setState(() {
          _uploading = true;
          _uploadProgress = 0;
          _optimisticAvatarPath = croppedFile.path;
        });
        try {
          await engine.uploadProfilePhoto(accountId, croppedFile.path);
          if (mounted) {
            setState(() { _uploading = false; _uploadProgress = 1.0; });
            showTelegramToast(context, 'Profile photo updated');
          }
        } catch (e) {
          if (mounted) {
            setState(() { _uploading = false; _optimisticAvatarPath = null; });
            showTelegramToast(context, 'Failed to upload photo: $e');
          }
        }
      },
    );
    try { tmpFile.deleteSync(); } catch (e) {
      Debug.log('my_profile_page', 'tmpFile.deleteSync(): $e');
    }
  }

  void _openEmojiBuilder(BuildContext context) async {
    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id;
    if (accountId == null) return;
    final engine = context.read<EngineService>();

    await EmojiAvatarBuilder.open(
      context,
      shape: PhotoCropShape.ellipse,
      onDone: (renderedFile) async {
        if (!mounted) return;
        setState(() {
          _uploading = true;
          _uploadProgress = 0;
          _optimisticAvatarPath = renderedFile.path;
        });
        try {
          await engine.uploadProfilePhoto(accountId, renderedFile.path);
          if (mounted) {
            setState(() { _uploading = false; _uploadProgress = 1.0; });
            showTelegramToast(context, 'Profile photo updated');
          }
        } catch (e) {
          if (mounted) {
            setState(() { _uploading = false; _optimisticAvatarPath = null; });
            showTelegramToast(context, 'Failed to upload photo: $e');
          }
        }
      },
    );
  }

  void _openProfilePhotoViewer(BuildContext context, AccountInfo account) async {
    final engine = context.read<EngineService>();
    try {
      final count = await engine.getUserPhotoCount(account.id, account.selfUserId);
      if (!mounted) return;
      if (count > 0) {
        final fetchCount = count < 20 ? count : 20;
        final results = await Future.wait(
          List.generate(fetchCount, (i) => engine.getUserPhotoAtIndex(account.id, account.selfUserId, i)),
        );
        final messages = <CachedMessage>[];
        for (int i = 0; i < results.length; i++) {
          final path = results[i].path;
          if (path != null && path.isNotEmpty) {
            messages.add(CachedMessage(
              accountId: account.id,
              msgId: 'profile_photo_$i',
              chatId: account.selfUserId,
              mediaType: 1,
              mediaLocalPath: path,
              mediaFileName: 'profile_photo_$i.jpg',
              senderName: account.displayName,
              isOutgoing: true,
              hasMedia: true,
            ));
          }
        }
        if (!mounted) return;
        if (messages.isNotEmpty) {
          if (!mounted) return;
          MediaViewer.open(
            context,
            message: messages.first,
            allMessages: messages,
          );
          return;
        }
      }
      _openProfilePhotoSimple(context, account.avatarPath);
    } catch (_) {
      if (mounted) _openProfilePhotoSimple(context, account.avatarPath);
    }
  }

  void _openProfilePhotoSimple(BuildContext context, String path) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: InteractiveViewer(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _avatarFallback(Color color, String initials) {
    final appState = context.read<AppState>();
    final corners = appState.avatarCorners;
    final shape = corners >= 23 ? BoxShape.circle : BoxShape.rectangle;
    final borderRadius = corners < 23 && corners > 0
        ? BorderRadius.circular(corners / 23.0 * 50.0)
        : null;
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: color,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _initials(String title) {
    final t = title.trim();
    if (t.isEmpty) return '?';
    final words = t.split(RegExp(r'\s+'));
    if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return t[0].toUpperCase();
  }

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
}

/// §14.5.5: Birthday row — shows formatted date or "Add", opens date picker.
class _BirthdayRow extends StatelessWidget {
  final int day;
  final int month;
  final int year;
  final bool isDark;
  final bool loaded;
  final VoidCallback onTap;

  const _BirthdayRow({
    required this.day,
    required this.month,
    required this.year,
    required this.isDark,
    required this.loaded,
    required this.onTap,
  });

  static const _monthNames = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatBirthday() {
    if (day <= 0 || month <= 0 || month > 12) return '';
    final monthStr = _monthNames[month];
    if (year > 0) return '$monthStr $day, $year';
    return '$monthStr $day';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);

    final hasBirthday = day > 0 && month > 0;
    final displayValue = hasBirthday ? _formatBirthday() : 'Add';

    return InkWell(
      onTap: onTap,
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: SettingsStyle.iconLeft),
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: const Color(0xFFE91E63),
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.cake, size: SettingsStyle.iconInner, color: Colors.white),
            ),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: SettingsStyle.buttonFontSize,
                      color: hasBirthday ? textColor : subtextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Date of Birth',
                    style: TextStyle(fontSize: 13, color: subtextColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }
}

/// §14.5.4: Personal Channel row — shows channel name or "Add".
class _PersonalChannelRow extends StatelessWidget {
  final String channelName;
  final bool isDark;
  final bool loaded;
  final ValueChanged<String>? onChannelChanged;

  const _PersonalChannelRow({
    required this.channelName,
    required this.isDark,
    required this.loaded,
    this.onChannelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);

    final hasChannel = channelName.isNotEmpty;
    final displayValue = hasChannel ? channelName : 'Add';

    return InkWell(
      onTap: () => _showPersonalChannelEditor(context, hasChannel, channelName, onChannelChanged),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: SettingsStyle.iconLeft),
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800),
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.video_library, size: SettingsStyle.iconInner, color: Colors.white),
            ),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: SettingsStyle.buttonFontSize,
                      color: hasChannel ? textColor : subtextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Personal Channel',
                    style: TextStyle(fontSize: 13, color: subtextColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }

  void _showPersonalChannelEditor(BuildContext context, bool hasChannel, String currentName, ValueChanged<String>? onChannelChanged) {
    showDialog(
      context: context,
      builder: (ctx) => _PersonalChannelSelector(
        isDark: isDark,
        hasChannel: hasChannel,
        currentName: currentName,
        onChannelChanged: onChannelChanged,
      ),
    );
  }
}

/// §14.5.4: Your Color row — shows name color swatch, opens EditPeerColorBox.
class _YourColorRow extends StatelessWidget {
  final int colorId;
  final int bgEmojiId;
  final int profileColorId;
  final int profileEmojiId;
  final bool isDark;
  final bool loaded;
  final String? accountId;
  final ValueChanged<int> onColorChanged;

  const _YourColorRow({
    required this.colorId,
    required this.bgEmojiId,
    required this.profileColorId,
    required this.profileEmojiId,
    required this.isDark,
    required this.loaded,
    required this.accountId,
    required this.onColorChanged,
  });

  static const _baseColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
    Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];

  Color get _currentColor {
    final idx = colorId >= 0 && colorId < _baseColors.length
        ? colorId
        : (accountId?.hashCode.abs() ?? 0) % 7;
    return _baseColors[idx];
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);

    return InkWell(
      onTap: () => _openEditPeerColorBox(context),
      hoverColor: hoverBg,
      splashColor: hoverBg.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: SettingsStyle.iconLeft),
            Container(
              width: SettingsStyle.iconSize,
              height: SettingsStyle.iconSize,
              decoration: BoxDecoration(
                color: _currentColor,
                borderRadius: BorderRadius.circular(SettingsStyle.iconRadius),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.palette, size: SettingsStyle.iconInner, color: Colors.white),
            ),
            const SizedBox(width: SettingsStyle.iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _currentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Your Color',
                        style: TextStyle(fontSize: SettingsStyle.buttonFontSize, color: textColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Name Color',
                    style: TextStyle(fontSize: 13, color: subtextColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }

  void _openEditPeerColorBox(BuildContext context) {
    final acctId = accountId;
    if (acctId == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        final appState = context.read<AppState>();
        final displayName = appState.activeAccount?.displayName ?? '';
        return _EditPeerColorBox(
          isDark: isDark,
          currentColorId: colorId >= 0 ? colorId : (acctId.hashCode.abs() % 7),
          currentBgEmojiId: bgEmojiId,
          currentProfileColorId: profileColorId,
          currentProfileEmojiId: profileEmojiId,
          accountId: acctId,
          userName: displayName,
          onColorSaved: onColorChanged,
        );
      },
    );
  }
}

/// §14.5.4: EditPeerColorBox — dialog showing 7 base name colors as circular
/// swatches. User picks one, Save persists via engine.
class _EditPeerColorBox extends StatefulWidget {
  final bool isDark;
  final int currentColorId;
  final int currentBgEmojiId;
  final int currentProfileColorId;
  final int currentProfileEmojiId;
  final String accountId;
  final String userName;
  final ValueChanged<int> onColorSaved;

  const _EditPeerColorBox({
    required this.isDark,
    required this.currentColorId,
    required this.currentBgEmojiId,
    required this.currentProfileColorId,
    required this.currentProfileEmojiId,
    required this.accountId,
    required this.userName,
    required this.onColorSaved,
  });

  @override
  State<_EditPeerColorBox> createState() => _EditPeerColorBoxState();
}

class _EditPeerColorBoxState extends State<_EditPeerColorBox> with SingleTickerProviderStateMixin {
  late int _selected;
  bool _saving = false;
  List<PeerColorEntry>? _serverColors;
  bool _loadingColors = true;
  int _selectedEmojiId = 0;
  List<int> _backgroundEmojiIds = [];
  Map<int, CustomEmojiThumbData> _emojiThumbs = {};
  bool _loadingEmojis = true;
  late TabController _tabController;
  int _profileColorId = -1;
  int _profileEmojiId = 0;

  static const _fallbackColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
    Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];

  @override
  void initState() {
    super.initState();
    // Seed each tab from the four distinct current server values rather than
    // collapsing everything onto the name color — AyuGram seeds the box from
    // colorIndex / backgroundEmojiId / colorProfileIndex / profileBackgroundEmojiId
    // (edit_peer_color_box.cpp:501-506). _profileColorId stays -1 (unset) when the
    // user has no profile color set, so the Profile tab does not snap to the name color.
    _selected = widget.currentColorId;
    _selectedEmojiId = widget.currentBgEmojiId;
    _profileColorId = widget.currentProfileColorId;
    _profileEmojiId = widget.currentProfileEmojiId;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadColors();
    _loadBackgroundEmojis();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadColors() async {
    try {
      final engine = context.read<EngineService>();
      final colors = await engine.getPeerColors(widget.accountId);
      if (mounted) {
        setState(() {
          _serverColors = colors.where((c) => !c.hidden).toList();
          _loadingColors = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingColors = false);
    }
  }

  Future<void> _loadBackgroundEmojis() async {
    try {
      final engine = context.read<EngineService>();
      final ids = await engine.getBackgroundEmojiList(widget.accountId);
      if (!mounted) return;
      // Make sure the user's current name/profile background emoji are present so
      // the picker highlights the real selection even when it isn't one of the
      // default suggestions returned by getBackgroundEmojiList.
      final seeded = <int>[
        for (final id in [_selectedEmojiId, _profileEmojiId])
          if (id != 0 && !ids.contains(id)) id,
      ];
      _backgroundEmojiIds = [...seeded, ...ids];
      if (_backgroundEmojiIds.isNotEmpty) {
        final thumbs = await engine.getCustomEmojiThumbs(widget.accountId, _backgroundEmojiIds.take(50).toList());
        if (mounted) {
          setState(() {
            _emojiThumbs = thumbs;
            _loadingEmojis = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingEmojis = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEmojis = false);
    }
  }

  List<Color> _colorsForEntry(PeerColorEntry entry) {
    final cols = widget.isDark ? entry.nightColors : entry.dayColors;
    if (cols.isNotEmpty) return cols.map((c) => Color(0xFF000000 | (c & 0xFFFFFF))).toList();
    if (entry.colorId < _fallbackColors.length) return [_fallbackColors[entry.colorId]];
    return [_fallbackColors[entry.colorId % _fallbackColors.length]];
  }

  Color _colorForEntry(PeerColorEntry entry) => _colorsForEntry(entry).first;

  Color _selectedColor() {
    if (_serverColors != null) {
      for (final c in _serverColors!) {
        if (c.colorId == _selected) return _colorForEntry(c);
      }
    }
    if (_selected >= 0 && _selected < _fallbackColors.length) return _fallbackColors[_selected];
    return _fallbackColors[0];
  }

  Color _profileColor() {
    if (_serverColors != null) {
      for (final c in _serverColors!) {
        if (c.colorId == _profileColorId) return _colorForEntry(c);
      }
    }
    if (_profileColorId >= 0 && _profileColorId < _fallbackColors.length) return _fallbackColors[_profileColorId];
    return _fallbackColors[0];
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

    final colors = _serverColors ?? [];
    final displayEntries = colors.isEmpty
        ? List.generate(7, (i) => (i, [_fallbackColors[i]]))
        : colors.map((c) => (c.colorId, _colorsForEntry(c))).toList();

    final isNameTab = _tabController.index == 0;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                controller: _tabController,
                labelColor: accentColor,
                unselectedLabelColor: subtextColor,
                indicatorColor: accentColor,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
                dividerHeight: 0,
                tabs: const [
                  Tab(text: 'Name'),
                  Tab(text: 'Profile'),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadingColors)
                Center(child: SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accentColor)))
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Wrap(
                    spacing: 13,
                    runSpacing: 13,
                    children: displayEntries.map((entry) {
                      final (colorId, colorList) = entry;
                      final currentId = isNameTab ? _selected : _profileColorId;
                      final isSelected = colorId == currentId;
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (isNameTab) {
                            _selected = colorId;
                          } else {
                            _profileColorId = colorId;
                          }
                        }),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CustomPaint(
                            painter: _ColorSamplePainter(
                              colors: colorList,
                              isSelected: isSelected,
                              selectionColor: accentColor,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (widget.isDark
                      ? const Color(0xFF17212B)
                      : const Color(0xFFF5F5F5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? const Color(0xFF182533)
                        : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.userName.isNotEmpty ? widget.userName : 'Your Name',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isNameTab ? _selectedColor() : _profileColor(),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              'Hello! This is how your name color looks.',
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '12:00',
                            style: TextStyle(
                              fontSize: 11,
                              color: textColor.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.done_all,
                            size: 14,
                            color: accentColor.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _backgroundEmojiIds.isEmpty ? null : () {
                  _showEmojiPickerDialog(context, accentColor, textColor, forProfile: !isNameTab);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: (widget.isDark
                        ? const Color(0xFF17212B)
                        : const Color(0xFFF5F5F5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.emoji_emotions_outlined, size: 20, color: accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Background Emoji',
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                      Text(
                        (isNameTab ? _selectedEmojiId : _profileEmojiId) == 0 ? 'Off' : '•',
                        style: TextStyle(fontSize: 14, color: subtextColor),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 20, color: subtextColor),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                          )
                        : Text('Save', style: TextStyle(color: accentColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmojiPickerDialog(BuildContext context, Color accentColor, Color textColor, {bool forProfile = false}) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF1B2836) : const Color(0xFFFFFFFF);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    showDialog<int>(
      context: context,
      builder: (ctx) {
        var selectedId = forProfile ? _profileEmojiId : _selectedEmojiId;
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: Text(
                'Background Emoji',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 17),
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              content: SizedBox(
                width: 340,
                height: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => setDialogState(() => selectedId = 0),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: selectedId == 0 ? accentColor.withValues(alpha: 0.15) : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block, size: 16, color: subtextColor),
                            const SizedBox(width: 6),
                            Text('Off', style: TextStyle(fontSize: 13, color: textColor)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _loadingEmojis
                          ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : SingleChildScrollView(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _backgroundEmojiIds.take(50).map((emojiId) {
                                  final isSelected = emojiId == selectedId;
                                  final thumb = _emojiThumbs[emojiId];
                                  return GestureDetector(
                                    onTap: () => setDialogState(() => selectedId = emojiId),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: isSelected ? Border.all(color: accentColor, width: 2) : null,
                                        color: isSelected ? accentColor.withValues(alpha: 0.1) : null,
                                      ),
                                      alignment: Alignment.center,
                                      child: thumb != null && thumb.thumbB64.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: Image.memory(
                                                base64Decode(thumb.thumbB64),
                                                width: 28, height: 28, fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) => _emojiPlaceholder(emojiId, textColor),
                                              ),
                                            )
                                          : _emojiPlaceholder(emojiId, textColor),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: accentColor)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(selectedId),
                  child: Text('OK', style: TextStyle(color: accentColor)),
                ),
              ],
            );
          },
        );
      },
    ).then((result) {
      if (result != null) {
        setState(() {
          if (forProfile) {
            _profileEmojiId = result;
          } else {
            _selectedEmojiId = result;
          }
        });
      }
    });
  }

  Widget _buildEmojiGrid(Color accentColor, Color textColor, {bool forProfile = false}) {
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (forProfile) {
                _profileEmojiId = 0;
              } else {
                _selectedEmojiId = 0;
              }
            }),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: (forProfile ? _profileEmojiId : _selectedEmojiId) == 0
                    ? accentColor.withValues(alpha: 0.15)
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block, size: 16, color: subtextColor),
                  const SizedBox(width: 6),
                  Text('Off', style: TextStyle(fontSize: 13, color: textColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: _loadingEmojis
                ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _backgroundEmojiIds.take(50).map((emojiId) {
                        final currentEmojiId = forProfile ? _profileEmojiId : _selectedEmojiId;
                        final isSelected = emojiId == currentEmojiId;
                        final thumb = _emojiThumbs[emojiId];
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (forProfile) {
                              _profileEmojiId = emojiId;
                            } else {
                              _selectedEmojiId = emojiId;
                            }
                          }),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: accentColor, width: 2)
                                  : null,
                              color: isSelected
                                  ? accentColor.withValues(alpha: 0.1)
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: thumb != null && thumb.thumbB64.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.memory(
                                      base64Decode(thumb.thumbB64),
                                      width: 28,
                                      height: 28,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          _emojiPlaceholder(emojiId, textColor),
                                    ),
                                  )
                                : _emojiPlaceholder(emojiId, textColor),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emojiPlaceholder(int emojiId, Color textColor) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: Icon(
          Icons.emoji_emotions_outlined,
          size: 16,
          color: textColor.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final engine = context.read<EngineService>();
      await engine.updateNameColor(widget.accountId, _selected, backgroundEmojiId: _selectedEmojiId);
      // Only push the profile color when it actually changed from the seeded
      // server values, and never send an unset (-1) profile color.
      final profileChanged = _profileColorId != widget.currentProfileColorId ||
          _profileEmojiId != widget.currentProfileEmojiId;
      if (profileChanged && _profileColorId >= 0) {
        await engine.updateNameColor(widget.accountId, _profileColorId, backgroundEmojiId: _profileEmojiId, forProfile: true);
      }
      widget.onColorSaved(_selected);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to update color: $e');
        setState(() => _saving = false);
      }
    }
  }
}

class _ColorSamplePainter extends CustomPainter {
  final List<Color> colors;
  final bool isSelected;
  final Color selectionColor;

  _ColorSamplePainter({
    required this.colors,
    required this.isSelected,
    required this.selectionColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - (isSelected ? 4 : 0);
    final paint = Paint()..style = PaintingStyle.fill;

    if (colors.length >= 2) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-0.785398);
      final halfH = radius * 1.5;
      paint.color = colors[0];
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        -1.5708, 3.1416, true, paint,
      );
      paint.color = colors[1];
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        1.5708, 3.1416, true, paint,
      );
      if (colors.length >= 3) {
        paint.color = colors[2];
        final dotR = radius * 0.3;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: Offset.zero, radius: dotR),
            Radius.circular(dotR * 0.4),
          ),
          paint,
        );
      }
      canvas.restore();
    } else {
      paint.color = colors.isNotEmpty ? colors[0] : const Color(0xFFCCCCCC);
      canvas.drawCircle(center, radius, paint);
    }

    if (isSelected) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = selectionColor;
      canvas.drawCircle(center, size.width / 2 - 1, ringPaint);
    }
  }

  @override
  bool shouldRepaint(_ColorSamplePainter old) =>
      colors != old.colors || isSelected != old.isSelected || selectionColor != old.selectionColor;
}

/// Small circular camera button overlaid at bottom-right of avatar.
class _UploadSubButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _UploadSubButton({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bgColor = context.palette.windowBgActive;
    final borderColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.camera_alt, size: 15, color: Colors.white),
      ),
    );
  }
}

/// §14.5.3: Profile info row — settingsButton layout (60px icon column),
/// primary value (14px) + secondary label (13px windowSubTextFg),
/// right-click copy context menu, no trailing chevron.
class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String value;
  final bool isDark;
  final VoidCallback? onTap;
  final String copyMenuLabel;

  const _ProfileInfoRow({
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.isDark,
    this.onTap,
    this.copyMenuLabel = 'Copy',
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);

    final displayValue = value.isNotEmpty ? value : 'Not set';
    final isSet = value.isNotEmpty;

    return GestureDetector(
      onSecondaryTapUp: isSet
          ? (details) => _showCopyMenu(context, details.globalPosition)
          : null,
      child: InkWell(
        onTap: isSet ? onTap : null,
        hoverColor: hoverBg,
        splashColor: hoverBg.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
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
                alignment: Alignment.center,
                child: Icon(icon, size: SettingsStyle.iconInner, color: Colors.white),
              ),
              const SizedBox(width: SettingsStyle.iconGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayValue,
                      style: TextStyle(
                        fontSize: SettingsStyle.buttonFontSize,
                        color: isSet ? textColor : subtextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(fontSize: 13, color: subtextColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _showCopyMenu(BuildContext context, Offset position) {
    final isDk = isDark;
    final bgColor = isDk ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDk ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Text(copyMenuLabel, style: TextStyle(color: textColor)),
        ),
      ],
    ).then((selected) {
      if (selected == 'copy' && value.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          showTelegramToast(context, 'Copied to clipboard');
        }
      }
    });
  }
}

/// §14.5.6: Accounts list — all logged-in accounts as rows with small avatar,
/// name, premium/unread badges, active-account ring, drag-to-reorder,
/// right-click context menu, and Add Account button at the end.
class _AccountsSection extends StatelessWidget {
  final bool isDark;

  const _AccountsSection({required this.isDark});

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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final chatState = context.watch<ChatState>();
    final accounts = appState.accounts;
    final activeId = appState.activeAccountId;
    final premiumLimit = appState.maxAccountLimit;

    final labelColor = isDark
        ? const Color(0xFFE1E3E6)
        : const Color(0xFF222222);
    final hoverBg = isDark
        ? const Color(0xFF232E3C)
        : const Color(0xFFF1F1F1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) => Material(
            elevation: 4,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
          itemCount: accounts.length,
          itemBuilder: (_, i) {
            final isLocked = i >= premiumLimit;
            return _SettingsAccountRow(
              key: ValueKey(accounts[i].id),
              account: accounts[i],
              isActive: accounts[i].id == activeId,
              isLocked: isLocked,
              unreadCount: chatState.unreadCountForAccount(accounts[i].id),
              unreadAllMuted: chatState.isAccountUnreadAllMuted(accounts[i].id),
              labelColor: labelColor,
              hoverBg: hoverBg,
              isDark: isDark,
              dragHandle: !isLocked
                  ? ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle, size: 20, color: Color(0xFF6C7883)),
                    )
                  : const Icon(Icons.drag_handle, size: 20, color: Color(0xFF6C7883)),
              onTap: () {
                if (HardwareKeyboard.instance.logicalKeysPressed
                    .any((k) => k == LogicalKeyboardKey.controlLeft || k == LogicalKeyboardKey.controlRight || k == LogicalKeyboardKey.metaLeft || k == LogicalKeyboardKey.metaRight)) {
                  final executable = Platform.resolvedExecutable;
                  Process.start(executable, ['--account', accounts[i].id], mode: ProcessStartMode.detached).then((_) {
                    if (context.mounted) {
                      showTelegramToast(context, 'Opening ${accounts[i].displayName} in new window');
                    }
                  }).catchError((e) {
                    if (context.mounted) {
                      showTelegramToast(context, 'Could not open new window: $e');
                    }
                  });
                  return;
                }
                if (accounts[i].id == activeId) {
                  Navigator.of(context).pop();
                } else {
                  appState.setActiveAccountId(accounts[i].id);
                }
              },
              onMarkAllRead: () {
                chatState.markAllChatsReadForAccount(accounts[i].id);
              },
              onLogOut: () {
                appState.removeAccount(accounts[i].id);
                if (accounts.length <= 1) {
                  Navigator.of(context).pop();
                }
              },
            );
          },
          onReorder: (oldIndex, newIndex) {
            if (oldIndex >= premiumLimit) return;
            final clampedNew = newIndex.clamp(0, premiumLimit - 1);
            if (clampedNew == oldIndex) return;
            appState.reorderAccounts(oldIndex, clampedNew);
          },
        ),
        if (appState.canAddAccount)
          _AddAccountButton(
            isDark: isDark,
            atPremiumLimit: accounts.length >= premiumLimit,
            labelColor: labelColor,
            hoverBg: hoverBg,
          ),
      ],
    );
  }
}

/// §14.5.6.1: Single account row in the settings accounts list.
class _SettingsAccountRow extends StatelessWidget {
  final AccountInfo account;
  final bool isActive;
  final bool isLocked;
  final int unreadCount;
  final bool unreadAllMuted;
  final Color labelColor;
  final Color hoverBg;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onMarkAllRead;
  final VoidCallback onLogOut;
  final Widget? dragHandle;

  const _SettingsAccountRow({
    super.key,
    required this.account,
    required this.isActive,
    this.isLocked = false,
    required this.unreadCount,
    required this.unreadAllMuted,
    required this.labelColor,
    required this.hoverBg,
    required this.isDark,
    required this.onTap,
    required this.onMarkAllRead,
    required this.onLogOut,
    this.dragHandle,
  });

  void _openInNewWindow(BuildContext context) {
    final executable = Platform.resolvedExecutable;
    Process.start(executable, ['--account', account.id], mode: ProcessStartMode.detached).then((_) {
      if (context.mounted) {
        showTelegramToast(context, 'Opening ${account.displayName} in new window');
      }
    }).catchError((e) {
      if (context.mounted) {
        showTelegramToast(context, 'Could not open new window: $e');
      }
    });
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final items = <TelegramMenuItem<String>>[];

    if (!isActive) {
      items.add(const TelegramMenuItem(
        value: 'new_window',
        icon: Icon(Icons.open_in_new),
        label: 'Open in New Window',
      ));
    }

    if (account.phone.isNotEmpty) {
      items.add(const TelegramMenuItem(
        value: 'copy_phone',
        icon: Icon(Icons.copy),
        label: 'Copy Phone',
      ));
    }

    if (!isActive) {
      items.add(const TelegramMenuItem(
        value: 'activate',
        icon: Icon(Icons.check_circle_outline),
        label: 'Activate',
      ));
    }

    items.add(const TelegramMenuItem(
      value: 'mark_read',
      icon: Icon(Icons.done_all),
      label: 'Mark All Chats as Read',
    ));

    if (!isActive) {
      items.add(const TelegramMenuItem(
        value: 'log_out',
        icon: Icon(Icons.logout),
        label: 'Log Out',
        isAttention: true,
      ));
    }

    showTelegramMenu<String>(
      context: context,
      position: position,
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'new_window':
          _openInNewWindow(context);
        case 'copy_phone':
          Clipboard.setData(ClipboardData(text: account.phone));
          if (context.mounted) {
            showTelegramToast(context, 'Phone number copied');
          }
        case 'mark_read':
          onMarkAllRead();
        case 'activate':
          onTap();
        case 'log_out':
          showConfirmBox(
            context,
            text: 'Are you sure you want to log out?',
            confirmText: 'Log Out',
            isDestructive: true,
            onConfirm: onLogOut,
          );
      }
    });
  }

  Widget _clipAccountAvatar(BuildContext context, Widget child, double size) {
    final appState = context.read<AppState>();
    final corners = appState.avatarCorners;
    if (corners >= 23) {
      return ClipOval(child: child);
    } else if (corners <= 0) {
      return ClipRect(child: child);
    } else {
      final r = corners / 23.0 * size / 2.0;
      return ClipRRect(borderRadius: BorderRadius.circular(r), child: child);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accentColor = palette.windowBgActive;
    final avatarSize = isActive ? 26.0 : 30.0;

    return GestureDetector(
      onTertiaryTapUp: !isActive ? (_) => _openInNewWindow(context) : null,
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      onLongPressStart: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Opacity(
        opacity: isLocked ? 0.5 : 1.0,
        child: InkWell(
          onTap: isLocked ? null : onTap,
          hoverColor: hoverBg,
          splashColor: hoverBg.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 20, top: 11, bottom: 9, right: 20,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Container(
                    decoration: isActive
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accentColor,
                              width: 2,
                            ),
                          )
                        : null,
                    padding: isActive
                        ? const EdgeInsets.all(2)
                        : EdgeInsets.zero,
                    child: account.avatarPath.isNotEmpty
                        ? _clipAccountAvatar(
                            context,
                            Image.file(
                              File(account.avatarPath),
                              width: avatarSize,
                              height: avatarSize,
                              fit: BoxFit.cover,
                              cacheWidth: 60,
                              cacheHeight: 60,
                              errorBuilder: (_, __, ___) =>
                                  _avatarFallback(context, avatarSize),
                            ),
                            avatarSize,
                          )
                        : _avatarFallback(context, avatarSize),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.displayName.isNotEmpty
                            ? account.displayName
                            : _AccountsSection._platformLabel(account.platform),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (account.isPremium) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.workspace_premium,
                        size: 16,
                        color: accentColor,
                      ),
                    ],
                    if (account.isVerified && !account.isPremium) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified,
                        size: 16,
                        color: palette.profileVerifiedCheckBg,
                      ),
                    ],
                  ],
                ),
              ),
              if (isLocked) ...[
                const SizedBox(width: 4),
                const Icon(Icons.lock, size: 16, color: Color(0xFF6C7883)),
              ],
              if (unreadCount > 0 && !isLocked) ...[
                const SizedBox(width: 4),
                _SettingsUnreadBadge(
                  count: unreadCount,
                  muted: unreadAllMuted,
                  isDark: isDark,
                ),
              ],
              if (dragHandle != null) ...[
                const SizedBox(width: 8),
                dragHandle!,
              ],
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _avatarFallback(BuildContext context, double size) {
    final colorIndex = account.id.hashCode.abs() % 7;
    const colors = [
      Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
      Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
      Color(0xFF6ec9cb),
    ];
    final icon = _AccountsSection._platformIcons[account.platform] ?? Icons.chat;
    final appState = context.read<AppState>();
    final corners = appState.avatarCorners;
    final shape = corners >= 23 ? BoxShape.circle : BoxShape.rectangle;
    final borderRadius = corners < 23 && corners > 0
        ? BorderRadius.circular(corners / 23.0 * size / 2.0)
        : null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors[colorIndex],
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.55, color: Colors.white),
    );
  }
}

/// §14.5.6.1: Unread badge for settings account rows.
class _SettingsUnreadBadge extends StatelessWidget {
  final int count;
  final bool muted;
  final bool isDark;

  const _SettingsUnreadBadge({
    required this.count,
    required this.muted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    if (muted) {
      bgColor = isDark
          ? const Color(0xFF3E546A)
          : const Color(0xFFBBBBBB);
    } else {
      bgColor = context.palette.windowBgActive;
    }
    final text = count >= 1000
        ? '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}K'
        : '$count';
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }
}

/// §14.5.6: Add Account button at the bottom of the accounts list.
class _AddAccountButton extends StatelessWidget {
  final bool isDark;
  final bool atPremiumLimit;
  final Color labelColor;
  final Color hoverBg;

  const _AddAccountButton({
    required this.isDark,
    required this.atPremiumLimit,
    required this.labelColor,
    required this.hoverBg,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = context.palette.windowBgActive;

    return Opacity(
      opacity: atPremiumLimit ? 0.4 : 1.0,
      child: InkWell(
        onTap: atPremiumLimit ? null : () => _showAddAccountDialog(context),
        hoverColor: hoverBg,
        splashColor: hoverBg.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 20, top: 11, bottom: 9, right: 20,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Add Account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context) {
    final appState = context.read<AppState>();
    final authState = context.read<AuthState>();
    Navigator.of(context).pop();
    final id = appState.addAccount('telegram');
    authState.startAuth(id);
  }
}

class _PersonalChannelSelector extends StatefulWidget {
  final bool isDark;
  final bool hasChannel;
  final String currentName;
  final ValueChanged<String>? onChannelChanged;

  const _PersonalChannelSelector({
    required this.isDark,
    required this.hasChannel,
    required this.currentName,
    this.onChannelChanged,
  });

  @override
  State<_PersonalChannelSelector> createState() => _PersonalChannelSelectorState();
}

class _PersonalChannelSelectorState extends State<_PersonalChannelSelector> {
  List<PublicLinkInfo>? _channels;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  void _loadChannels() async {
    try {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      final channels = await engine.getAdminedPublicChannels(appState.activeAccountId, forPersonal: true);
      if (mounted) setState(() { _channels = channels; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.hasChannel ? 'Personal Channel' : 'Add Personal Channel',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a channel you own to display on your profile.',
                style: TextStyle(fontSize: 14, color: subtextColor),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Failed to load channels: $_error', style: TextStyle(fontSize: 13, color: Colors.red[400])),
                )
              else if (_channels != null && _channels!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('You don\'t own any public channels.', style: TextStyle(fontSize: 14, color: subtextColor)),
                )
              else if (_channels != null)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _channels!.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        final isNone = !widget.hasChannel;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: isNone ? null : () {
                                final engine = context.read<EngineService>();
                                final appState = context.read<AppState>();
                                engine.clearPersonalChannel(appState.activeAccountId);
                                widget.onChannelChanged?.call('');
                                Navigator.of(ctx).pop();
                                showTelegramToast(context, 'Personal channel removed');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36, height: 36,
                                      decoration: BoxDecoration(
                                        color: subtextColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(Icons.block, size: 18, color: subtextColor),
                                    ),
                                    const SizedBox(width: 12),
                                    Text('None', style: TextStyle(fontSize: 14, color: isNone ? accentColor : textColor)),
                                    const Spacer(),
                                    if (isNone) Icon(Icons.check_circle, size: 20, color: accentColor),
                                  ],
                                ),
                              ),
                            ),
                            Divider(height: 1, color: widget.isDark ? const Color(0xFF2A3A4A) : const Color(0xFFE0E0E0)),
                            const SizedBox(height: 4),
                          ],
                        );
                      }
                      final i2 = i - 1;
                      final ch = _channels![i2];
                      final isSelected = ch.title == widget.currentName || ch.username == widget.currentName;
                      return InkWell(
                        onTap: () {
                          final engine = context.read<EngineService>();
                          final appState = context.read<AppState>();
                          engine.setPersonalChannel(appState.activeAccountId, ch.username);
                          widget.onChannelChanged?.call(ch.title.isNotEmpty ? ch.title : ch.username);
                          Navigator.of(ctx).pop();
                          showTelegramToast(context, 'Personal channel set to @${ch.username}');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                alignment: Alignment.center,
                                child: Icon(Icons.campaign, size: 18, color: accentColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ch.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    if (ch.username.isNotEmpty)
                                      Text('@${ch.username}', style: TextStyle(fontSize: 12, color: subtextColor)),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle, size: 20, color: accentColor),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (widget.hasChannel)
                    TextButton(
                      onPressed: () {
                        final engine = context.read<EngineService>();
                        final appState = context.read<AppState>();
                        engine.clearPersonalChannel(appState.activeAccountId);
                        widget.onChannelChanged?.call('');
                        Navigator.of(context).pop();
                        showTelegramToast(context, 'Personal channel removed');
                      },
                      child: Text('Remove', style: TextStyle(color: Colors.red[400])),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: subtextColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
