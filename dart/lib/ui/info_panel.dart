import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/chat_state.dart';

/// Spec: Third column info panel, min 292px, max 392px.
/// Shows user/group/channel info with members and shared media links.
class InfoPanel extends StatefulWidget {
  final VoidCallback onClose;

  const InfoPanel({super.key, required this.onClose});

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  List<MemberInfo>? _members;
  bool _loadingMembers = false;
  String? _loadedChatId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat != null && chat.chatId != _loadedChatId) {
      _loadMembers(chat);
    }
  }

  Future<void> _loadMembers(ChatInfo chat) async {
    if (_loadingMembers) return;
    setState(() {
      _loadingMembers = true;
      _loadedChatId = chat.chatId;
    });

    try {
      final engine = context.read<EngineService>();
      final members = await engine.getChatMembers(chat.accountId, chat.chatId);
      if (mounted) {
        setState(() {
          _members = members;
          _loadingMembers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _members = [];
          _loadingMembers = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = context.watch<ChatState>();
    final chat = chatState.activeChat;

    if (chat == null) return const SizedBox.shrink();

    // Reload members if chat changed.
    if (chat.chatId != _loadedChatId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers(chat));
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Top bar with close button.
          _TopBar(chat: chat, onClose: widget.onClose, theme: theme),
          // Scrollable content.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Avatar + name header.
                _AvatarHeader(chat: chat, theme: theme),
                const SizedBox(height: 16),
                // Chat details.
                _ChatDetails(chat: chat, theme: theme),
                const Divider(height: 24),
                // Notifications toggle.
                _NotificationToggle(chat: chat, theme: theme),
                // Members list (for groups).
                if (chat.type == ChatType.group || chat.type == ChatType.topic) ...[
                  const Divider(height: 24),
                  _MembersSection(
                    members: _members,
                    loading: _loadingMembers,
                    memberCount: chat.memberCount,
                    theme: theme,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ChatInfo chat;
  final VoidCallback onClose;
  final ThemeData theme;

  const _TopBar({required this.chat, required this.onClose, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onClose,
            tooltip: 'Close',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _panelTitle(chat.type),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static String _panelTitle(ChatType type) => switch (type) {
    ChatType.dm => 'User Info',
    ChatType.group => 'Group Info',
    ChatType.channel => 'Channel Info',
    ChatType.topic => 'Topic Info',
    _ => 'Info',
  };
}

class _AvatarHeader extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;

  const _AvatarHeader({required this.chat, required this.theme});

  @override
  Widget build(BuildContext context) {
    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];
    final initials = _initials(chat.title);

    return Column(
      children: [
        // 72x72 avatar.
        SizedBox(
          width: 72,
          height: 72,
          child: chat.avatarPath.isNotEmpty
              ? ClipOval(
                  child: Image.file(
                    File(chat.avatarPath),
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(color, initials),
                  ),
                )
              : _avatarFallback(color, initials),
        ),
        const SizedBox(height: 12),
        // Name.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            chat.title.isNotEmpty ? chat.title : chat.chatId,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Status / member count.
        if (chat.memberCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _statusText(chat),
              style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
            ),
          ),
      ],
    );
  }

  static String _statusText(ChatInfo chat) {
    if (chat.type == ChatType.channel) {
      return '${_formatCount(chat.memberCount)} subscribers';
    }
    if (chat.type == ChatType.group || chat.type == ChatType.topic) {
      return '${_formatCount(chat.memberCount)} members';
    }
    return '';
  }

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  static Widget _avatarFallback(Color color, String initials) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
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

class _ChatDetails extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;

  const _ChatDetails({required this.chat, required this.theme});

  void _copyToClipboard(BuildContext context, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chat ID (as username-like field) — tap to copy.
          if (chat.chatId.isNotEmpty)
            _DetailRow(
              icon: Icons.alternate_email,
              label: 'ID',
              value: chat.chatId,
              theme: theme,
              onTap: () => _copyToClipboard(context, chat.chatId, 'ID'),
            ),
          // Account — tap to copy.
          _DetailRow(
            icon: Icons.account_circle,
            label: 'Account',
            value: chat.accountId,
            theme: theme,
            onTap: () => _copyToClipboard(context, chat.accountId, 'Account'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.textTheme.bodySmall?.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(label, style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
              ],
            ),
          ),
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.copy, size: 16, color: theme.textTheme.bodySmall?.color),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: row,
    );
  }
}

class _NotificationToggle extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;

  const _NotificationToggle({required this.chat, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(Icons.notifications, size: 20, color: theme.textTheme.bodySmall?.color),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Notifications', style: theme.textTheme.bodyMedium),
          ),
          Switch(
            value: !chat.isMuted,
            onChanged: (value) {
              final chatState = context.read<ChatState>();
              chatState.muteChat(chat.accountId, chat.chatId, !value);
            },
          ),
        ],
      ),
    );
  }
}

class _MembersSection extends StatelessWidget {
  final List<MemberInfo>? members;
  final bool loading;
  final int memberCount;
  final ThemeData theme;

  const _MembersSection({
    required this.members,
    required this.loading,
    required this.memberCount,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Members',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (memberCount > 0) ...[
                const SizedBox(width: 6),
                Text(
                  memberCount.toString(),
                  style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ))
          else if (members != null && members!.isNotEmpty)
            ...members!.map((m) => _MemberRow(member: m, theme: theme))
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No members available',
                style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final MemberInfo member;
  final ThemeData theme;

  const _MemberRow({required this.member, required this.theme});

  @override
  Widget build(BuildContext context) {
    final name = member.displayName.isNotEmpty ? member.displayName : member.username;
    final colorIndex = member.userId.hashCode.abs() % 7;
    final color = [
      const Color(0xFFe17076), const Color(0xFF7bc862), const Color(0xFFe5ca77),
      const Color(0xFF65aadd), const Color(0xFFa695e7), const Color(0xFFee7aae),
      const Color(0xFF6ec9cb),
    ][colorIndex];

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          // 40px avatar.
          SizedBox(
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isNotEmpty ? name : member.userId,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (member.isBot) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.smart_toy, size: 14, color: theme.textTheme.bodySmall?.color),
                    ],
                  ],
                ),
                if (member.role != 'member' && member.role.isNotEmpty)
                  Text(
                    member.role,
                    style: TextStyle(
                      fontSize: 12,
                      color: member.role == 'owner'
                          ? theme.colorScheme.primary
                          : theme.textTheme.bodySmall?.color,
                    ),
                  )
                else
                  Text(
                    member.isOnline ? 'online' : 'last seen recently',
                    style: TextStyle(
                      fontSize: 12,
                      color: member.isOnline
                          ? theme.colorScheme.primary
                          : theme.textTheme.bodySmall?.color,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
