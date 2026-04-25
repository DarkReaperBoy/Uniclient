import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBio();
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
          _ProfilePhotoArea(account: account, isDark: isDark),
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
            onTap: () => _copyToClipboard(context, account?.displayName ?? '', 'Full name'),
            onLongPress: () => _copyToClipboard(context, account?.displayName ?? '', 'Full name'),
          ),
          _rowDivider(isDark),
          _ProfileInfoRow(
            icon: Icons.phone,
            iconBg: const Color(0xFF4CAF50),
            label: 'Phone Number',
            value: account?.phone ?? '',
            isDark: isDark,
            onTap: () => _copyToClipboard(context, account?.phone ?? '', 'Phone number'),
            onLongPress: () => _copyToClipboard(context, account?.phone ?? '', 'Phone number'),
          ),
          _rowDivider(isDark),
          _ProfileInfoRow(
            icon: Icons.alternate_email,
            iconBg: const Color(0xFF9C27B0),
            label: 'Username',
            value: account != null && account.username.isNotEmpty
                ? '@${account.username}'
                : '',
            isDark: isDark,
            onTap: () {
              if (account != null && account.username.isNotEmpty) {
                _copyToClipboard(context, '@${account.username}', 'Username');
              }
            },
            onLongPress: () {
              if (account != null && account.username.isNotEmpty) {
                _copyToClipboard(context, '@${account.username}', 'Username');
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: Text(
              'People can message you using your username without knowing your phone number.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
          ),
        ],
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(milliseconds: 500),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
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

  const _ProfilePhotoArea({required this.account, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    final name = account?.displayName ?? '';
    final initials = _initials(name);
    final colorIndex = (account?.id ?? '').hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];

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
                // Main avatar.
                Positioned.fill(
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
                // §14.5.1: Upload sub-button at bottom-right (6px from right edge).
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _UploadSubButton(
                    isDark: isDark,
                    onTap: () => _pickAndUploadPhoto(context),
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
          // §14.5.1: Online status — windowSubTextFg, -1px spacing.
          if (account != null)
            Transform.translate(
              offset: const Offset(0, -1),
              child: Text(
                'online',
                style: TextStyle(
                  fontSize: 13,
                  color: subtextColor,
                ),
              ),
            ),
        ],
      ),
    );
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

    try {
      await engine.uploadProfilePhoto(accountId, path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated'),
            duration: Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update photo: $e'),
            duration: const Duration(milliseconds: 2000),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

  static const _avatarColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
    Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];
}

/// Small circular camera button overlaid at bottom-right of avatar.
class _UploadSubButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _UploadSubButton({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
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

/// §14.5.3: Profile info row — icon, label, value, tap-to-copy.
class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String value;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ProfileInfoRow({
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.isDark,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    final displayValue = value.isNotEmpty ? value : 'Not set';
    final isSet = value.isNotEmpty;

    return InkWell(
      onTap: isSet ? onTap : null,
      onLongPress: isSet ? onLongPress : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSet ? textColor : subtextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: subtextColor),
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
