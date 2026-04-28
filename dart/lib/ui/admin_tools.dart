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
          onTap: () {},
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
