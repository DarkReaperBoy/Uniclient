import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../theme/telegram_palette.dart';
import 'create_group_wizard.dart' show showEditPeerTypeBox;

Future<bool?> showEditPeerInfoBox(
  BuildContext context, {
  required ChatInfo chat,
  List<MemberInfo>? members,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _EditPeerInfoBox(chat: chat, members: members),
  );
}

class _EditPeerInfoBox extends StatefulWidget {
  final ChatInfo chat;
  final List<MemberInfo>? members;

  const _EditPeerInfoBox({required this.chat, this.members});

  @override
  State<_EditPeerInfoBox> createState() => _EditPeerInfoBoxState();
}

class _EditPeerInfoBoxState extends State<_EditPeerInfoBox> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;
  String? _avatarPath;
  bool _avatarRemoved = false;

  bool get _isChannel => widget.chat.type == ChatType.channel;
  bool get _isBot => widget.chat.isBot;

  String get _peerLabel {
    if (_isBot) return 'Bot';
    if (_isChannel) return 'Channel';
    return 'Group';
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.chat.title);
    _descCtrl = TextEditingController();
    _loadDescription();
  }

  Future<void> _loadDescription() async {
    final engine = context.read<EngineService>();
    try {
      final profile = await engine.getUserProfile(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      if (profile != null && mounted) {
        setState(() => _descCtrl.text = profile.bio);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final accentColor = palette.windowBgActive;
    final attentionColor = palette.attentionButtonFg;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bgColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(textColor, bgColor, accentColor, dividerColor),
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  _buildPhotoSection(accentColor, textColor, subTextColor),
                  _buildTitleField(textColor),
                  _buildDescriptionField(textColor, subTextColor),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 6),
                  _buildSettingsSection(textColor, subTextColor, accentColor),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 6),
                  _buildAdminControlsSection(textColor, subTextColor),
                  if (!_isChannel && !_isBot) ...[
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 6),
                    _buildStickerSection(textColor, subTextColor, accentColor),
                  ],
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 6),
                  _buildDeleteButton(attentionColor),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(
    Color textColor,
    Color bgColor,
    Color accentColor,
    Color dividerColor,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Edit $_peerLabel',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                TextButton(
                  onPressed: _onSave,
                  child: Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildPhotoSection(Color accentColor, Color textColor, Color subTextColor) {
    final avatarPath = widget.chat.avatarPath;
    final hasAvatar = !_avatarRemoved &&
        (_avatarPath != null || (avatarPath.isNotEmpty && File(avatarPath).existsSync()));
    final displayPath = _avatarPath ?? avatarPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Row(
        children: [
          GestureDetector(
            onSecondaryTapDown: (d) => _showPhotoMenu(d.globalPosition),
            onLongPress: () => _showPhotoMenu(Offset.zero),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: accentColor,
              backgroundImage:
                  hasAvatar && displayPath.isNotEmpty ? FileImage(File(displayPath)) : null,
              child: hasAvatar
                  ? null
                  : Text(
                      _initials(widget.chat.title),
                      style: const TextStyle(fontSize: 22, color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.chat.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.chat.memberCount} ${_isChannel ? "subscribers" : "members"}',
                  style: TextStyle(fontSize: 13, color: subTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoMenu(Offset position) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuPos = position == Offset.zero ? null : position;

    showMenu<String>(
      context: context,
      position: menuPos != null
          ? RelativeRect.fromLTRB(menuPos.dx, menuPos.dy, menuPos.dx, menuPos.dy)
          : const RelativeRect.fromLTRB(80, 120, 80, 120),
      items: [
        const PopupMenuItem(value: 'set', child: Text('Set Photo')),
        const PopupMenuItem(value: 'set_video', child: Text('Set Video')),
        const PopupMenuItem(value: 'remove', child: Text('Remove Photo')),
      ],
      color: isDark ? const Color(0xFF1E2C3A) : Colors.white,
    ).then((value) {
      if (value == 'remove' && mounted) {
        setState(() => _avatarRemoved = true);
      }
    });
  }

  Widget _buildTitleField(Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 13, 22, 8),
      child: TextField(
        controller: _titleCtrl,
        maxLength: 128,
        autofocus: true,
        style: TextStyle(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          labelText: '${_peerLabel} Name',
          counterText: '',
          isDense: true,
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildDescriptionField(Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 3, 22, 2),
      child: TextField(
        controller: _descCtrl,
        maxLength: 255,
        maxLines: null,
        minLines: 2,
        style: TextStyle(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          labelText: 'Description',
          counterText: '',
          isDense: true,
          hintText: 'Add a description...',
          hintStyle: TextStyle(color: subTextColor),
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(Color textColor, Color subTextColor, Color accentColor) {
    final chat = widget.chat;
    final isPrivate = !chat.chatId.startsWith('-100');

    return Column(
      children: [
        _EditRow(
          icon: Icons.lock_outline,
          label: _isChannel ? 'Channel Type' : 'Group Type',
          value: isPrivate ? 'Private' : 'Public',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => showEditPeerTypeBox(
            context,
            accountId: chat.accountId,
            chatId: chat.chatId,
            isChannel: _isChannel,
          ),
        ),
        _EditRow(
          icon: _isChannel ? Icons.forum_outlined : Icons.groups_outlined,
          label: _isChannel ? 'Discussion Group' : 'Linked Channel',
          value: 'Add',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () {},
        ),
        if (!_isChannel) ...[
          _EditRow(
            icon: Icons.chat_bubble_outline,
            label: 'Visible History',
            value: 'Shown',
            textColor: textColor,
            subTextColor: subTextColor,
            onTap: () {},
          ),
          if (chat.isForum || chat.memberCount > 0)
            _EditRow(
              icon: Icons.topic_outlined,
              label: 'Topics',
              value: chat.isForum ? 'On' : 'Off',
              textColor: textColor,
              subTextColor: subTextColor,
              onTap: () {},
            ),
        ],
        if (_isChannel) ...[
          _EditRow(
            icon: Icons.translate,
            label: 'Auto-Translation',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            isToggle: true,
            onTap: () {},
          ),
          _EditRow(
            icon: Icons.draw_outlined,
            label: 'Sign Messages',
            value: '',
            textColor: textColor,
            subTextColor: subTextColor,
            isToggle: true,
            onTap: () {},
          ),
        ],
      ],
    );
  }

  Widget _buildAdminControlsSection(Color textColor, Color subTextColor) {
    final memberCount = widget.chat.memberCount;
    final adminCount =
        widget.members?.where((m) => m.role == 'admin' || m.role == 'creator' || m.role == 'owner').length ?? 0;

    return Column(
      children: [
        _EditRow(
          icon: Icons.security,
          label: 'Permissions',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => showEditPeerPermissionsBox(
            context,
            accountId: widget.chat.accountId,
            chatId: widget.chat.chatId,
            isChannel: _isChannel,
            isForum: widget.chat.isForum,
            memberCount: widget.chat.memberCount,
          ),
        ),
        _EditRow(
          icon: Icons.link,
          label: 'Invite Links',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () => _showInviteLink(),
        ),
        _EditRow(
          icon: Icons.admin_panel_settings_outlined,
          label: 'Administrators',
          value: adminCount > 0 ? '$adminCount' : '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () {},
        ),
        _EditRow(
          icon: Icons.people_outline,
          label: _isChannel ? 'Subscribers' : 'Members',
          value: memberCount > 0 ? _formatCount(memberCount) : '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () {},
        ),
        _EditRow(
          icon: Icons.person_remove_outlined,
          label: 'Removed Users',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildStickerSection(Color textColor, Color subTextColor, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 6, 20, 4),
          child: Text(
            'Group Stickers',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        _EditRow(
          icon: Icons.emoji_emotions_outlined,
          label: 'Add Stickers',
          value: '',
          textColor: textColor,
          subTextColor: subTextColor,
          onTap: () {},
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 0, 20, 6),
          child: Text(
            'Choose a sticker set for your group.',
            style: TextStyle(fontSize: 12, color: subTextColor),
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteButton(Color attentionColor) {
    return InkWell(
      onTap: _confirmDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 24, color: attentionColor),
            const SizedBox(width: 16),
            Text(
              'Delete $_peerLabel',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: attentionColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (_saving) return;
    final newTitle = _titleCtrl.text.trim();
    if (newTitle.isEmpty) return;

    setState(() => _saving = true);
    final engine = context.read<EngineService>();
    try {
      if (newTitle != widget.chat.title) {
        await engine.editChatTitle(
          widget.chat.accountId,
          widget.chat.chatId,
          newTitle,
        );
      }
      final newDesc = _descCtrl.text.trim();
      if (newDesc.isNotEmpty) {
        await engine.editChatDescription(
          widget.chat.accountId,
          widget.chat.chatId,
          newDesc,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  void _confirmDelete() {
    final attentionColor = PaletteProvider.of(context).attentionButtonFg;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $_peerLabel'),
        content: Text(
          'Are you sure you want to delete "${widget.chat.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: attentionColor),
            onPressed: () {
              final engine = context.read<EngineService>();
              engine.deleteChat(widget.chat.accountId, widget.chat.chatId);
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showInviteLink() async {
    final engine = context.read<EngineService>();
    try {
      final link = await engine.getInviteLink(
        widget.chat.accountId,
        widget.chat.chatId,
      );
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Invite Link'),
            content: SelectableText(link),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied')),
                  );
                },
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get invite link: $e')),
        );
      }
    }
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

Future<void> showEditPeerPermissionsBox(
  BuildContext context, {
  required String accountId,
  required String chatId,
  required bool isChannel,
  required bool isForum,
  required int memberCount,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _EditPeerPermissionsBox(
      accountId: accountId,
      chatId: chatId,
      isChannel: isChannel,
      isForum: isForum,
      memberCount: memberCount,
    ),
  );
}

class _PermFlag {
  final String key;
  final String label;
  bool banned;

  _PermFlag({required this.key, required this.label, this.banned = false});
}

class _EditPeerPermissionsBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final bool isChannel;
  final bool isForum;
  final int memberCount;

  const _EditPeerPermissionsBox({
    required this.accountId,
    required this.chatId,
    required this.isChannel,
    required this.isForum,
    required this.memberCount,
  });

  @override
  State<_EditPeerPermissionsBox> createState() => _EditPeerPermissionsBoxState();
}

class _EditPeerPermissionsBoxState extends State<_EditPeerPermissionsBox>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _saving = false;
  bool _mediaExpanded = false;
  int _slowmodeIndex = 0;
  String? _error;

  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  static const _slowmodeValues = [0, 5, 10, 30, 60, 300, 900, 3600];
  static const _slowmodeLabels = ['Off', '5s', '10s', '30s', '1m', '5m', '15m', '1h'];

  late final _PermFlag _sendPlain;
  late final List<_PermFlag> _mediaFlags;
  late final List<_PermFlag> _otherFlags;

  List<_PermFlag> get _allFlags => [_sendPlain, ..._mediaFlags, ..._otherFlags];

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _sendPlain = _PermFlag(key: 'send_plain', label: 'Send text messages');
    _mediaFlags = [
      _PermFlag(key: 'send_photos', label: 'Send photos'),
      _PermFlag(key: 'send_videos', label: 'Send videos'),
      _PermFlag(key: 'send_roundvideos', label: 'Send video messages'),
      _PermFlag(key: 'send_audios', label: 'Send music'),
      _PermFlag(key: 'send_voices', label: 'Send voice messages'),
      _PermFlag(key: 'send_docs', label: 'Send files'),
      _PermFlag(key: 'send_stickers', label: 'Send stickers & GIFs'),
    ];
    _otherFlags = [
      _PermFlag(key: 'embed_links', label: 'Send links'),
      _PermFlag(key: 'send_polls', label: 'Send polls'),
      _PermFlag(key: 'invite_users', label: 'Add members'),
      if (widget.isForum) _PermFlag(key: 'manage_topics', label: 'Create topics'),
      _PermFlag(key: 'pin_messages', label: 'Pin messages'),
      _PermFlag(key: 'edit_rank', label: 'Edit rank'),
      _PermFlag(key: 'change_info', label: 'Change group info'),
    ];
    _loadRights();
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRights() async {
    try {
      final engine = context.read<EngineService>();
      final rights = await engine.getDefaultBannedRights(widget.accountId, widget.chatId);
      if (!mounted) return;
      setState(() {
        for (final f in _allFlags) {
          f.banned = rights[f.key] == true;
        }
        final secs = rights['slowmode_seconds'] as int? ?? 0;
        _slowmodeIndex = _slowmodeValues.indexOf(secs);
        if (_slowmodeIndex < 0) _slowmodeIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final engine = context.read<EngineService>();
      final rights = <String, dynamic>{};
      for (final f in _allFlags) {
        rights[f.key] = f.banned;
      }
      rights['slowmode_seconds'] = _slowmodeValues[_slowmodeIndex];
      await engine.setDefaultBannedRights(widget.accountId, widget.chatId, rights);
      if (_slowmodeValues[_slowmodeIndex] != 0) {
        await engine.setSlowMode(widget.accountId, widget.chatId, _slowmodeValues[_slowmodeIndex]);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  void _toggleFlag(_PermFlag flag) {
    setState(() {
      flag.banned = !flag.banned;
      if (flag.key == 'send_plain' && flag.banned) {
        final embedLinks = _otherFlags.firstWhere((f) => f.key == 'embed_links');
        embedLinks.banned = true;
      }
      if (flag.key == 'embed_links' && !flag.banned) {
        _sendPlain.banned = false;
      }
    });
  }

  int get _mediaAllowedCount => _mediaFlags.where((f) => !f.banned).length;

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final accentColor = palette.windowBgActive;
    final attentionColor = palette.attentionButtonFg;
    final headerColor = palette.windowActiveTextFg;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bgColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(textColor, bgColor, accentColor, dividerColor),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, style: TextStyle(color: attentionColor)),
              )
            else
              Flexible(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    const SizedBox(height: 8),
                    _buildSectionHeader('What can members of this group do?', headerColor),
                    const SizedBox(height: 4),
                    _buildPermToggle(_sendPlain, accentColor, attentionColor, textColor),
                    _buildMediaSection(accentColor, attentionColor, textColor, subTextColor),
                    for (final f in _otherFlags)
                      _buildPermToggle(f, accentColor, attentionColor, textColor),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 12),
                    _buildSectionHeader('Slow Mode', headerColor),
                    const SizedBox(height: 4),
                    _buildSlowmodeSlider(accentColor, textColor, subTextColor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                      child: Text(
                        _slowmodeIndex == 0
                            ? 'Members can send messages without any restrictions.'
                            : 'Members will be able to send only one message every ${_slowmodeLabels[_slowmodeIndex]}.',
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                    ),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 12),
                    _buildAddExceptionButton(accentColor, textColor),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(Color textColor, Color bgColor, Color accentColor, Color dividerColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Permissions',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                TextButton(
                  onPressed: _onSave,
                  child: Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.6))),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildSectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildPermToggle(_PermFlag flag, Color accentColor, Color attentionColor, Color textColor) {
    final allowed = !flag.banned;
    final isLocked = flag.key == 'embed_links' && _sendPlain.banned;

    return InkWell(
      onTap: () {
        if (isLocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('"Send links" requires "Send text messages" to be allowed.'),
              duration: Duration(milliseconds: 3000),
            ),
          );
          return;
        }
        _toggleFlag(flag);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(
          children: [
            if (isLocked)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.lock, size: 18, color: accentColor),
              ),
            Expanded(
              child: Text(
                flag.label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              height: 24,
              child: Switch(
                value: allowed,
                onChanged: isLocked ? null : (_) => _toggleFlag(flag),
                activeColor: accentColor,
                inactiveThumbColor: attentionColor,
                inactiveTrackColor: attentionColor.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(Color accentColor, Color attentionColor, Color textColor, Color subTextColor) {
    final allowedCount = _mediaAllowedCount;
    final total = _mediaFlags.length;

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _mediaExpanded = !_mediaExpanded);
            if (_mediaExpanded) {
              _expandCtrl.forward();
            } else {
              _expandCtrl.reverse();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _expandAnim,
                  builder: (_, child) => Transform.rotate(
                    angle: _expandAnim.value * 3.14159,
                    child: child,
                  ),
                  child: Icon(Icons.expand_more, size: 20, color: textColor.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Send media',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
                Text(
                  '($allowedCount/$total)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: subTextColor),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: allowedCount == total,
                    onChanged: (val) {
                      setState(() {
                        for (final f in _mediaFlags) {
                          f.banned = !val;
                        }
                      });
                    },
                    activeColor: accentColor,
                    inactiveThumbColor: allowedCount == 0 ? attentionColor : accentColor,
                    inactiveTrackColor: allowedCount == 0
                        ? attentionColor.withValues(alpha: 0.3)
                        : accentColor.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expandAnim,
          child: Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Column(
              children: [
                for (final f in _mediaFlags)
                  _buildMediaCheckbox(f, accentColor, attentionColor, textColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCheckbox(_PermFlag flag, Color accentColor, Color attentionColor, Color textColor) {
    final allowed = !flag.banned;
    return InkWell(
      onTap: () => _toggleFlag(flag),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: allowed,
                onChanged: (_) => _toggleFlag(flag),
                activeColor: accentColor,
                side: BorderSide(color: allowed ? accentColor : attentionColor, width: 2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(flag.label, style: TextStyle(fontSize: 14, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlowmodeSlider(Color accentColor, Color textColor, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: accentColor.withValues(alpha: 0.3),
              thumbColor: accentColor,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              trackHeight: 3,
            ),
            child: Slider(
              value: _slowmodeIndex.toDouble(),
              min: 0,
              max: (_slowmodeValues.length - 1).toDouble(),
              divisions: _slowmodeValues.length - 1,
              onChanged: (v) => setState(() => _slowmodeIndex = v.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int i = 0; i < _slowmodeLabels.length; i++)
                  Text(
                    _slowmodeLabels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: i == _slowmodeIndex ? textColor : subTextColor,
                      fontWeight: i == _slowmodeIndex ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddExceptionButton(Color accentColor, Color textColor) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exception list coming soon')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.person_add_outlined, size: 24, color: accentColor),
            const SizedBox(width: 16),
            Text(
              'Add Exception',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textColor;
  final Color subTextColor;
  final bool isToggle;
  final VoidCallback onTap;

  const _EditRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.textColor,
    required this.subTextColor,
    this.isToggle = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 21, top: 11, right: 20, bottom: 9),
        child: Row(
          children: [
            Icon(icon, size: 24, color: textColor.withValues(alpha: 0.55)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            if (isToggle)
              Switch(value: false, onChanged: (_) => onTap())
            else if (value.isNotEmpty)
              Text(
                value,
                style: TextStyle(fontSize: 14, color: subTextColor),
              ),
            if (!isToggle)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: textColor.withValues(alpha: 0.3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> showEditRestrictedBox(
  BuildContext context, {
  required String accountId,
  required String chatId,
  required MemberInfo member,
  bool isForum = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _EditRestrictedBox(
      accountId: accountId,
      chatId: chatId,
      member: member,
      isForum: isForum,
    ),
  );
}

enum _BanDuration { forever, oneDay, oneWeek, custom }

class _EditRestrictedBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final MemberInfo member;
  final bool isForum;

  const _EditRestrictedBox({
    required this.accountId,
    required this.chatId,
    required this.member,
    required this.isForum,
  });

  @override
  State<_EditRestrictedBox> createState() => _EditRestrictedBoxState();
}

class _EditRestrictedBoxState extends State<_EditRestrictedBox>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _saving = false;
  bool _mediaExpanded = false;
  String? _error;
  _BanDuration _duration = _BanDuration.forever;
  DateTime? _customDate;

  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  static const _kSecondsInDay = 86400;
  static const _kSecondsInWeek = 604800;
  static const _kMaxRestrictDelayDays = 366;

  late final _PermFlag _sendPlain;
  late final List<_PermFlag> _mediaFlags;
  late final List<_PermFlag> _otherFlags;

  List<_PermFlag> get _allFlags => [_sendPlain, ..._mediaFlags, ..._otherFlags];

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _sendPlain = _PermFlag(key: 'send_plain', label: 'Send text messages');
    _mediaFlags = [
      _PermFlag(key: 'send_photos', label: 'Send photos'),
      _PermFlag(key: 'send_videos', label: 'Send videos'),
      _PermFlag(key: 'send_roundvideos', label: 'Send video messages'),
      _PermFlag(key: 'send_audios', label: 'Send music'),
      _PermFlag(key: 'send_voices', label: 'Send voice messages'),
      _PermFlag(key: 'send_docs', label: 'Send files'),
      _PermFlag(key: 'send_stickers', label: 'Send stickers & GIFs'),
    ];
    _otherFlags = [
      _PermFlag(key: 'embed_links', label: 'Send links'),
      _PermFlag(key: 'send_polls', label: 'Send polls'),
      _PermFlag(key: 'invite_users', label: 'Add members'),
      if (widget.isForum) _PermFlag(key: 'manage_topics', label: 'Create topics'),
      _PermFlag(key: 'pin_messages', label: 'Pin messages'),
      _PermFlag(key: 'change_info', label: 'Change group info'),
    ];
    _loadDefaults();
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    try {
      final engine = context.read<EngineService>();
      final rights = await engine.getDefaultBannedRights(widget.accountId, widget.chatId);
      if (!mounted) return;
      setState(() {
        for (final f in _allFlags) {
          f.banned = rights[f.key] == true;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  int _computeUntilDate() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    switch (_duration) {
      case _BanDuration.forever:
        return 0;
      case _BanDuration.oneDay:
        return now + _kSecondsInDay;
      case _BanDuration.oneWeek:
        return now + _kSecondsInWeek;
      case _BanDuration.custom:
        if (_customDate != null) {
          return _customDate!.millisecondsSinceEpoch ~/ 1000;
        }
        return 0;
    }
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final engine = context.read<EngineService>();
      final rights = <String, bool>{};
      for (final f in _allFlags) {
        rights[f.key] = f.banned;
      }
      await engine.restrictMemberWithRights(
        widget.accountId,
        widget.chatId,
        widget.member.userId,
        rights,
        _computeUntilDate(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  void _toggleFlag(_PermFlag flag) {
    setState(() {
      flag.banned = !flag.banned;
      if (flag.key == 'send_plain' && flag.banned) {
        final embedLinks = _otherFlags.firstWhere((f) => f.key == 'embed_links');
        embedLinks.banned = true;
      }
      if (flag.key == 'embed_links' && !flag.banned) {
        _sendPlain.banned = false;
      }
    });
  }

  int get _mediaAllowedCount => _mediaFlags.where((f) => !f.banned).length;

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final maxDate = now.add(const Duration(days: _kMaxRestrictDelayDays));
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: maxDate,
    );
    if (picked != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_customDate ?? now),
      );
      if (mounted) {
        setState(() {
          _customDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time?.hour ?? 0,
            time?.minute ?? 0,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF708499) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final accentColor = palette.windowBgActive;
    final attentionColor = palette.attentionButtonFg;
    final headerColor = palette.windowActiveTextFg;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bgColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(textColor, bgColor, accentColor, dividerColor),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, style: TextStyle(color: attentionColor)),
              )
            else
              Flexible(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    _buildCover(textColor, subTextColor, accentColor),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 8),
                    _buildSectionHeader('What can this user do?', headerColor),
                    const SizedBox(height: 4),
                    _buildPermToggle(_sendPlain, accentColor, attentionColor, textColor),
                    _buildMediaSection(accentColor, attentionColor, textColor, subTextColor),
                    for (final f in _otherFlags)
                      _buildPermToggle(f, accentColor, attentionColor, textColor),
                    Divider(height: 1, color: dividerColor),
                    const SizedBox(height: 12),
                    _buildSectionHeader('Banned until', headerColor),
                    const SizedBox(height: 4),
                    _buildDurationPicker(accentColor, textColor, subTextColor),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(Color textColor, Color bgColor, Color accentColor, Color dividerColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Restrict User',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                TextButton(
                  onPressed: _onSave,
                  child: Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accentColor)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.6))),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildCover(Color textColor, Color subTextColor, Color accentColor) {
    final member = widget.member;
    final hasAvatar = member.avatarB64.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 18, 20, 18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: accentColor,
            backgroundImage: hasAvatar
                ? MemoryImage(base64Decode(member.avatarB64))
                : null,
            child: hasAvatar
                ? null
                : Text(
                    _initials(member.label),
                    style: const TextStyle(fontSize: 20, color: Colors.white),
                  ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  member.isOnline
                      ? 'online'
                      : member.username.isNotEmpty
                          ? '@${member.username}'
                          : member.role,
                  style: TextStyle(
                    fontSize: 13,
                    color: member.isOnline ? accentColor : subTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildPermToggle(_PermFlag flag, Color accentColor, Color attentionColor, Color textColor) {
    final allowed = !flag.banned;
    final isLocked = flag.key == 'embed_links' && _sendPlain.banned;

    return InkWell(
      onTap: () {
        if (isLocked) return;
        _toggleFlag(flag);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(
          children: [
            if (isLocked)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.lock, size: 18, color: accentColor),
              ),
            Expanded(
              child: Text(
                flag.label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              height: 24,
              child: Switch(
                value: allowed,
                onChanged: isLocked ? null : (_) => _toggleFlag(flag),
                activeColor: accentColor,
                inactiveThumbColor: attentionColor,
                inactiveTrackColor: attentionColor.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(Color accentColor, Color attentionColor, Color textColor, Color subTextColor) {
    final allowedCount = _mediaAllowedCount;
    final total = _mediaFlags.length;

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _mediaExpanded = !_mediaExpanded);
            if (_mediaExpanded) {
              _expandCtrl.forward();
            } else {
              _expandCtrl.reverse();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _expandAnim,
                  builder: (_, child) => Transform.rotate(
                    angle: _expandAnim.value * 3.14159,
                    child: child,
                  ),
                  child: Icon(Icons.expand_more, size: 20, color: textColor.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Send media',
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
                Text(
                  '($allowedCount/$total)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: subTextColor),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: allowedCount == total,
                    onChanged: (val) {
                      setState(() {
                        for (final f in _mediaFlags) {
                          f.banned = !val;
                        }
                      });
                    },
                    activeColor: accentColor,
                    inactiveThumbColor: allowedCount == 0 ? attentionColor : accentColor,
                    inactiveTrackColor: allowedCount == 0
                        ? attentionColor.withValues(alpha: 0.3)
                        : accentColor.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expandAnim,
          child: Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Column(
              children: [
                for (final f in _mediaFlags)
                  _buildMediaCheckbox(f, accentColor, attentionColor, textColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCheckbox(_PermFlag flag, Color accentColor, Color attentionColor, Color textColor) {
    final allowed = !flag.banned;
    return InkWell(
      onTap: () => _toggleFlag(flag),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: allowed,
                onChanged: (_) => _toggleFlag(flag),
                activeColor: accentColor,
                side: BorderSide(color: allowed ? accentColor : attentionColor, width: 2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(flag.label, style: TextStyle(fontSize: 14, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationPicker(Color accentColor, Color textColor, Color subTextColor) {
    return Column(
      children: [
        _buildDurationRadio(_BanDuration.forever, 'Ban forever', accentColor, textColor),
        _buildDurationRadio(_BanDuration.oneDay, 'Ban for 1 day', accentColor, textColor),
        _buildDurationRadio(_BanDuration.oneWeek, 'Ban for 1 week', accentColor, textColor),
        _buildDurationRadio(_BanDuration.custom, 'Custom...', accentColor, textColor),
        if (_duration == _BanDuration.custom && _customDate != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 22, 8),
            child: Text(
              'Until ${_customDate!.year}-${_customDate!.month.toString().padLeft(2, '0')}-${_customDate!.day.toString().padLeft(2, '0')} '
              '${_customDate!.hour.toString().padLeft(2, '0')}:${_customDate!.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 13, color: subTextColor),
            ),
          ),
      ],
    );
  }

  Widget _buildDurationRadio(_BanDuration value, String label, Color accentColor, Color textColor) {
    return InkWell(
      onTap: () {
        setState(() => _duration = value);
        if (value == _BanDuration.custom) {
          _pickCustomDate();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Radio<_BanDuration>(
                value: value,
                groupValue: _duration,
                onChanged: (v) {
                  setState(() => _duration = v!);
                  if (v == _BanDuration.custom) {
                    _pickCustomDate();
                  }
                },
                activeColor: accentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
