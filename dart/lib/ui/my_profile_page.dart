import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import 'confirm_box.dart';
import 'input_dialogs.dart';
import 'photo_crop_editor.dart';
import 'telegram_toast.dart';
import 'popup_menu.dart';
import 'privacy_settings_screen.dart';
import 'settings_style.dart';

/// "My Profile" / "Edit Profile" page (§14.5).
/// Opened from hamburger drawer "My Profile" row or Settings "My Account".
/// Shows profile photo, bio input, name, phone, username with copy/edit affordances.
class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  final _bioController = TextEditingController();
  Timer? _debounceTimer;
  String _savedBio = '';
  bool _bioLoaded = false;
  int _selfColorId = -1;
  String _personalChannelName = '';
  bool _colorChannelLoaded = false;
  int _birthdayDay = 0;
  int _birthdayMonth = 0;
  int _birthdayYear = 0;
  bool _birthdayLoaded = false;
  String _birthdayPrivacy = 'contacts';
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _loadBio();
    _loadColorAndChannel();
    _loadBirthday();
    _loadStatus();
  }

  @override
  void dispose() {
    _flushBio();
    _debounceTimer?.cancel();
    _bioController.dispose();
    super.dispose();
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
        _bioController.text = bio;
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
      final rule = result['rule'] as String? ?? 'contacts';
      if (rule != _birthdayPrivacy) {
        setState(() => _birthdayPrivacy = rule);
      }
    });
  }

  void _loadStatus() {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    if (account.connState == ConnState.connected) {
      setState(() => _statusText = 'online');
    } else if (account.connState == ConnState.connecting) {
      setState(() => _statusText = 'connecting...');
    } else {
      setState(() => _statusText = 'waiting for network...');
    }
    if (account.selfUserId.isEmpty) return;
    final engine = context.read<EngineService>();
    engine.getUserProfile(account.id, account.selfUserId).then((profile) {
      if (!mounted || profile == null) return;
      setState(() => _statusText = _computeStatusText(account.connState, profile));
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
      builder: (ctx) => _BirthdayDrumPickerDialog(
        initialDay: _birthdayDay > 0 ? _birthdayDay : DateTime.now().day,
        initialMonth: _birthdayMonth > 0 ? _birthdayMonth : DateTime.now().month,
        initialYear: _birthdayYear > 0 ? _birthdayYear : 0,
      ),
    );
    if (result == null || !mounted) return;
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final engine = context.read<EngineService>();
    try {
      await engine.updateBirthday(account.id, result.day, result.month, result.year);
      if (mounted) {
        setState(() {
          _birthdayDay = result.day;
          _birthdayMonth = result.month;
          _birthdayYear = result.year;
        });
        showTelegramToast(context, 'Birthday saved');
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to update birthday: $e');
      }
    }
  }

  void _onBioChanged(String value) {
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _saveBio(value);
    });
  }

  void _saveBio(String value) {
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
      _saveBio(_bioController.text);
    }
  }

  bool get _isPremium => context.read<AppState>().activeAccount?.isPremium ?? false;

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
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _ProfilePhotoArea(account: account, isDark: isDark, statusText: _statusText),
          Container(height: 8, color: dividerColor),
          _BioInput(
            controller: _bioController,
            isDark: isDark,
            isPremium: _isPremium,
            bioLoaded: _bioLoaded,
            onChanged: _onBioChanged,
            onSubmitted: () {
              _debounceTimer?.cancel();
              _saveBio(_bioController.text);
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
                        : 'Your birthday is visible to ',
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
                          _birthdayPrivacy == 'close_friends' ? 'your close friends' : 'your contacts',
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
          _PersonalChannelRow(
            channelName: _personalChannelName,
            isDark: isDark,
            loaded: _colorChannelLoaded,
            onChannelChanged: (name) => setState(() => _personalChannelName = name),
          ),
          _rowDivider(isDark),
          _YourColorRow(
            colorId: _selfColorId,
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
          _AccountsSection(isDark: isDark),
        ],
      ),
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
class _BioInput extends StatelessWidget {
  final TextEditingController controller;
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
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final maxLen = isPremium ? 140 : 70;
    final remaining = maxLen - controller.text.length;
    final counterColor = remaining < 0
        ? const Color(0xFFE53935)
        : subtextColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Padding(
              padding: SettingsStyle.bioMargins,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  enabled: bioLoaded,
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
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmitted(),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 22,
              child: Text(
                '$remaining',
                style: TextStyle(fontSize: 13, color: counterColor),
              ),
            ),
          ],
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

/// §14.5.1: Profile photo area — 162px height, 100x100 avatar centered,
/// upload sub-button at bottom-right, name (17px semibold, 24px max height),
/// online status below name.
class _ProfilePhotoArea extends StatelessWidget {
  final AccountInfo? account;
  final bool isDark;
  final String statusText;

  const _ProfilePhotoArea({required this.account, required this.isDark, this.statusText = ''});

  @override
  Widget build(BuildContext context) {
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

    return SizedBox(
      height: 162,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          // 100x100 avatar with upload sub-button overlay.
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: account != null && account!.avatarPath.isNotEmpty
                        ? () => _openProfilePhoto(context, account!.avatarPath)
                        : null,
                    child: account != null && account!.avatarPath.isNotEmpty
                        ? ClipOval(
                            child: Image.file(
                              File(account!.avatarPath),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _avatarFallback(color, initials),
                            ),
                          )
                        : _avatarFallback(color, initials),
                  ),
                ),
                // §14.5.1: Upload sub-button at bottom-right (6px from right edge).
                Positioned(
                  right: 0,
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
          // §14.5.1: Name — 17px semibold, max height 24px.
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
                statusText.isNotEmpty ? statusText : (account!.connState == ConnState.connected ? 'online' : 'connecting...'),
                style: TextStyle(
                  fontSize: 13,
                  color: statusText == 'online' || (statusText.isEmpty && account!.connState == ConnState.connected)
                      ? context.palette.windowBgActive
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
    showMenu<String>(
      context: context,
      position: position,
      items: [
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
          value: 'emoji',
          child: Row(
            children: [
              Icon(Icons.emoji_emotions_outlined, size: 20),
              SizedBox(width: 12),
              Text('Set Emoji'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'photo') {
        _pickAndUploadPhoto(context);
      } else if (value == 'emoji') {
        _openEmojiBuilder(context);
      }
    });
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
        await engine.uploadProfilePhoto(accountId, croppedFile.path);
        if (context.mounted) {
          showTelegramToast(context, 'Profile photo updated');
        }
      },
    );
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
        await engine.uploadProfilePhoto(accountId, renderedFile.path);
        if (context.mounted) {
          showTelegramToast(context, 'Profile photo updated');
        }
      },
    );
  }

  static Widget _avatarFallback(Color color, String initials) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

  void _openProfilePhoto(BuildContext context, String path) {
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
  final bool isDark;
  final bool loaded;
  final String? accountId;
  final ValueChanged<int> onColorChanged;

  const _YourColorRow({
    required this.colorId,
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
      builder: (ctx) => _EditPeerColorBox(
        isDark: isDark,
        currentColorId: colorId >= 0 ? colorId : (acctId.hashCode.abs() % 7),
        accountId: acctId,
        onColorSaved: onColorChanged,
      ),
    );
  }
}

/// §14.5.4: EditPeerColorBox — dialog showing 7 base name colors as circular
/// swatches. User picks one, Save persists via engine.
class _EditPeerColorBox extends StatefulWidget {
  final bool isDark;
  final int currentColorId;
  final String accountId;
  final ValueChanged<int> onColorSaved;

  const _EditPeerColorBox({
    required this.isDark,
    required this.currentColorId,
    required this.accountId,
    required this.onColorSaved,
  });

  @override
  State<_EditPeerColorBox> createState() => _EditPeerColorBoxState();
}

class _EditPeerColorBoxState extends State<_EditPeerColorBox> {
  late int _selected;
  bool _saving = false;

  static const _baseColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
    Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentColorId.clamp(0, 6);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final accentColor = context.palette.windowBgActive;

    return Dialog(
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
                'Your Name Color',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(7, (i) {
                  final isSelected = i == _selected;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: accentColor, width: 2.5)
                            : null,
                      ),
                      padding: EdgeInsets.all(isSelected ? 3 : 0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _baseColors[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Container(
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
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: _baseColors[_selected],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Your Name',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _baseColors[_selected],
                      ),
                    ),
                  ],
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final engine = context.read<EngineService>();
      await engine.updateNameColor(widget.accountId, _selected);
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
        width: 30,
        height: 30,
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
          buildDefaultDragHandles: true,
          proxyDecorator: (child, index, animation) => Material(
            elevation: 4,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
          itemCount: accounts.length,
          itemBuilder: (_, i) => _SettingsAccountRow(
            key: ValueKey(accounts[i].id),
            account: accounts[i],
            isActive: accounts[i].id == activeId,
            unreadCount: chatState.unreadCountForAccount(accounts[i].id),
            unreadAllMuted: chatState.isAccountUnreadAllMuted(accounts[i].id),
            labelColor: labelColor,
            hoverBg: hoverBg,
            isDark: isDark,
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
          ),
          onReorder: appState.reorderAccounts,
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
  final int unreadCount;
  final bool unreadAllMuted;
  final Color labelColor;
  final Color hoverBg;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onMarkAllRead;
  final VoidCallback onLogOut;

  const _SettingsAccountRow({
    super.key,
    required this.account,
    required this.isActive,
    required this.unreadCount,
    required this.unreadAllMuted,
    required this.labelColor,
    required this.hoverBg,
    required this.isDark,
    required this.onTap,
    required this.onMarkAllRead,
    required this.onLogOut,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final accentColor = palette.windowBgActive;

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      onLongPressStart: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: InkWell(
        onTap: onTap,
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
                        ? ClipOval(
                            child: Image.file(
                              File(account.avatarPath),
                              width: isActive ? 26 : 30,
                              height: isActive ? 26 : 30,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _avatarFallback(isActive ? 26.0 : 30.0),
                            ),
                          )
                        : _avatarFallback(isActive ? 26.0 : 30.0),
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
              if (unreadCount > 0) ...[
                const SizedBox(width: 4),
                _SettingsUnreadBadge(
                  count: unreadCount,
                  muted: unreadAllMuted,
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback(double size) {
    final colorIndex = account.id.hashCode.abs() % 7;
    const colors = [
      Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
      Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
      Color(0xFF6ec9cb),
    ];
    final icon = _AccountsSection._platformIcons[account.platform] ?? Icons.chat;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colors[colorIndex],
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
      final channels = await engine.getAdminedPublicChannels(appState.activeAccountId);
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
                    itemCount: _channels!.length,
                    itemBuilder: (ctx, i) {
                      final ch = _channels![i];
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
                mainAxisAlignment: MainAxisAlignment.end,
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

class _BirthdayDrumPickerDialog extends StatefulWidget {
  final int initialDay;
  final int initialMonth;
  final int initialYear;

  const _BirthdayDrumPickerDialog({
    required this.initialDay,
    required this.initialMonth,
    this.initialYear = 0,
  });

  @override
  State<_BirthdayDrumPickerDialog> createState() => _BirthdayDrumPickerDialogState();
}

class _BirthdayDrumPickerDialogState extends State<_BirthdayDrumPickerDialog> {
  static const _minYear = 1900;
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late int _maxYear;
  late FixedExtentScrollController _dayController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _yearController;
  late int _selectedDay;
  late int _selectedMonth;
  late int _selectedYearIndex;
  late int _yearCount;

  @override
  void initState() {
    super.initState();
    _maxYear = DateTime.now().year;
    _yearCount = _maxYear - _minYear + 2;
    _selectedDay = widget.initialDay.clamp(1, 31);
    _selectedMonth = widget.initialMonth.clamp(1, 12);
    _selectedYearIndex = widget.initialYear > 0
        ? (widget.initialYear - _minYear).clamp(0, _yearCount - 2)
        : _yearCount - 1;
    _dayController = FixedExtentScrollController(initialItem: _selectedDay - 1);
    _monthController = FixedExtentScrollController(initialItem: _selectedMonth - 1);
    _yearController = FixedExtentScrollController(initialItem: _selectedYearIndex);
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  int _daysInMonth(int month, int yearIndex) {
    final year = yearIndex < _yearCount - 1 ? _minYear + yearIndex : _maxYear;
    if (month == 2) {
      return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28;
    }
    return const [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month];
  }

  void _onMonthChanged(int index) {
    setState(() {
      _selectedMonth = index + 1;
      final maxDay = _daysInMonth(_selectedMonth, _selectedYearIndex);
      if (_selectedDay > maxDay) {
        _selectedDay = maxDay;
        _dayController.jumpToItem(_selectedDay - 1);
      }
    });
  }

  void _onYearChanged(int index) {
    setState(() {
      _selectedYearIndex = index;
      final maxDay = _daysInMonth(_selectedMonth, _selectedYearIndex);
      if (_selectedDay > maxDay) {
        _selectedDay = maxDay;
        _dayController.jumpToItem(_selectedDay - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF3390EC);
    final maxDays = _daysInMonth(_selectedMonth, _selectedYearIndex);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'Birthday',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: Row(
                  children: [
                    Expanded(child: _buildWheel(
                      controller: _dayController,
                      itemCount: maxDays,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      labelBuilder: (i) => '${i + 1}',
                      onChanged: (i) => setState(() => _selectedDay = i + 1),
                    )),
                    Expanded(child: _buildWheel(
                      controller: _monthController,
                      itemCount: 12,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      labelBuilder: (i) => _monthNames[i],
                      onChanged: _onMonthChanged,
                    )),
                    Expanded(child: _buildWheel(
                      controller: _yearController,
                      itemCount: _yearCount,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      labelBuilder: (i) => i < _yearCount - 1 ? '${_minYear + i}' : '—',
                      onChanged: _onYearChanged,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: subtextColor)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        final year = _selectedYearIndex < _yearCount - 1
                            ? _minYear + _selectedYearIndex
                            : 0;
                        Navigator.of(context).pop(
                          (day: _selectedDay, month: _selectedMonth, year: year),
                        );
                      },
                      child: Text('Save', style: TextStyle(color: accentColor)),
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

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required Color textColor,
    required Color subtextColor,
    required String Function(int) labelBuilder,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      perspective: 0.003,
      diameterRatio: 1.5,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          final isSelected = controller.hasClients && controller.selectedItem == index;
          return Center(
            child: Text(
              labelBuilder(index),
              style: TextStyle(
                fontSize: isSelected ? 16 : 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? textColor : subtextColor,
              ),
            ),
          );
        },
      ),
    );
  }
}
