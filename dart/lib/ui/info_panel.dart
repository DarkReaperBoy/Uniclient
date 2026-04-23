import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/chat_state.dart';
import 'chat_view.dart' show formatChatLastSeen;

enum InfoWrapMode { side, narrow, layer }

enum _InfoPageType { chatInfo, userProfile }

class _InfoNavPage {
  final _InfoPageType type;
  final MemberInfo? member;
  double scrollOffset = 0.0;

  _InfoNavPage({required this.type, this.member});

  String get title => switch (type) {
    _InfoPageType.chatInfo => '',
    _InfoPageType.userProfile => member?.label ?? 'User Info',
  };
}

class InfoPanel extends StatefulWidget {
  final VoidCallback onClose;
  final InfoWrapMode wrapMode;

  const InfoPanel({
    super.key,
    required this.onClose,
    this.wrapMode = InfoWrapMode.side,
  });

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  List<MemberInfo>? _members;
  bool _loadingMembers = false;
  String? _loadedChatId;

  final List<_InfoNavPage> _navStack = [_InfoNavPage(type: _InfoPageType.chatInfo)];
  bool _isPushing = true;

  _InfoNavPage get _currentPage => _navStack.last;

  void _pushPage(_InfoNavPage page) {
    _saveCurrentScroll();
    setState(() {
      _isPushing = true;
      _navStack.add(page);
    });
  }

  void _popPage() {
    if (_navStack.length <= 1) {
      widget.onClose();
      return;
    }
    setState(() {
      _isPushing = false;
      _navStack.removeLast();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScroll());
  }

  final Map<int, ScrollController> _scrollControllers = {};

  ScrollController _getScrollController() {
    final idx = _navStack.length - 1;
    return _scrollControllers.putIfAbsent(idx, () {
      final ctrl = ScrollController(initialScrollOffset: _currentPage.scrollOffset);
      return ctrl;
    });
  }

  void _saveCurrentScroll() {
    final idx = _navStack.length - 1;
    final ctrl = _scrollControllers[idx];
    if (ctrl != null && ctrl.hasClients) {
      _currentPage.scrollOffset = ctrl.offset;
    }
  }

  void _restoreScroll() {
    final idx = _navStack.length - 1;
    final old = _scrollControllers.remove(idx + 1);
    old?.dispose();
    final ctrl = _scrollControllers[idx];
    if (ctrl != null && ctrl.hasClients) {
      ctrl.jumpTo(_currentPage.scrollOffset);
    }
  }

  void _resetNavStack() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    _scrollControllers.clear();
    _navStack.clear();
    _navStack.add(_InfoNavPage(type: _InfoPageType.chatInfo));
    _isPushing = true;
  }

  @override
  void dispose() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat != null && chat.chatId != _loadedChatId) {
      _resetNavStack();
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

    if (chat.chatId != _loadedChatId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers(chat));
    }

    final isDark = theme.brightness == Brightness.dark;
    final isLayer = widget.wrapMode == InfoWrapMode.layer;
    final isNarrow = widget.wrapMode == InfoWrapMode.narrow;
    final topBarHeight = isLayer ? 56.0 : 54.0;
    final bgColor = isLayer
        ? (isDark ? const Color(0xFF1b2734) : const Color(0xFFf0f0f0))
        : theme.colorScheme.surface;

    final hasBack = _navStack.length > 1 || isNarrow;
    final topBarTitle = _navStack.length > 1
        ? _currentPage.title
        : _panelTitle(chat.type);

    final pageContent = _buildCurrentPage(chat, chatState, theme);

    Widget panel = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: isLayer
            ? const BorderRadius.vertical(top: Radius.circular(12))
            : null,
        border: (!isLayer && !isNarrow)
            ? Border(left: BorderSide(color: theme.dividerColor, width: 1))
            : null,
      ),
      clipBehavior: isLayer ? Clip.antiAlias : Clip.none,
      child: Column(
        children: [
          _TopBar(
            chat: chat,
            onClose: hasBack ? _popPage : widget.onClose,
            theme: theme,
            height: topBarHeight,
            showBackButton: hasBack,
            titleOverride: topBarTitle,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) {
                final isNewPage = child.key == ValueKey(_navStack.length);
                final beginOffset = _isPushing
                    ? (isNewPage ? const Offset(1, 0) : const Offset(-0.3, 0))
                    : (isNewPage ? const Offset(-0.3, 0) : const Offset(1, 0));
                return SlideTransition(
                  position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
                      .animate(animation),
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_navStack.length),
                child: pageContent,
              ),
            ),
          ),
        ],
      ),
    );

    return panel;
  }

  Widget _buildCurrentPage(ChatInfo chat, ChatState chatState, ThemeData theme) {
    final page = _currentPage;
    switch (page.type) {
      case _InfoPageType.userProfile:
        return _UserProfilePage(
          member: page.member!,
          chat: chat,
          theme: theme,
          scrollController: _getScrollController(),
        );
      case _InfoPageType.chatInfo:
        return _ChatInfoPage(
          chat: chat,
          chatState: chatState,
          theme: theme,
          members: _members,
          loadingMembers: _loadingMembers,
          scrollController: _getScrollController(),
          onMemberTap: (member) {
            _pushPage(_InfoNavPage(
              type: _InfoPageType.userProfile,
              member: member,
            ));
          },
        );
    }
  }

  static String _panelTitle(ChatType type) => switch (type) {
    ChatType.dm => 'User Info',
    ChatType.group => 'Group Info',
    ChatType.channel => 'Channel Info',
    ChatType.topic => 'Topic Info',
    _ => 'Info',
  };
}

class _TopBar extends StatelessWidget {
  final ChatInfo chat;
  final VoidCallback onClose;
  final ThemeData theme;
  final double height;
  final bool showBackButton;
  final String titleOverride;

  const _TopBar({
    required this.chat,
    required this.onClose,
    required this.theme,
    this.height = 54,
    this.showBackButton = false,
    this.titleOverride = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(showBackButton ? Icons.arrow_back : Icons.close, size: 20),
            onPressed: onClose,
            tooltip: showBackButton ? 'Back' : 'Close',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              titleOverride.isNotEmpty ? titleOverride : _panelTitle(chat.type),
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

class _ChatInfoPage extends StatelessWidget {
  final ChatInfo chat;
  final ChatState chatState;
  final ThemeData theme;
  final List<MemberInfo>? members;
  final bool loadingMembers;
  final ScrollController scrollController;
  final void Function(MemberInfo) onMemberTap;

  const _ChatInfoPage({
    required this.chat,
    required this.chatState,
    required this.theme,
    required this.members,
    required this.loadingMembers,
    required this.scrollController,
    required this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _AvatarHeader(
          chat: chat,
          theme: theme,
          isOnline: chatState.isChatOnline(chat),
          lastSeen: chatState.chatLastSeen(chat),
        ),
        const SizedBox(height: 16),
        _ChatDetails(chat: chat, theme: theme),
        const Divider(height: 24),
        _NotificationToggle(chat: chat, theme: theme),
        if (chat.type == ChatType.group || chat.type == ChatType.topic) ...[
          const Divider(height: 24),
          _MembersSection(
            members: members,
            loading: loadingMembers,
            memberCount: chat.memberCount,
            theme: theme,
            onMemberTap: onMemberTap,
          ),
        ],
      ],
    );
  }
}

class _UserProfilePage extends StatelessWidget {
  final MemberInfo member;
  final ChatInfo chat;
  final ThemeData theme;
  final ScrollController scrollController;

  const _UserProfilePage({
    required this.member,
    required this.chat,
    required this.theme,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = member.userId.hashCode.abs() % 7;
    final color = _AvatarHeader._avatarColors[colorIndex];
    final name = member.label;
    final initials = _AvatarHeader._initials(name);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Column(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Container(
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
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                name,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (member.isOnline)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'online',
                  style: TextStyle(fontSize: 13, color: const Color(0xFF3BA55C)),
                ),
              ),
            if (member.isBot)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('bot', style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (member.username.isNotEmpty)
                _DetailRow(
                  icon: Icons.alternate_email,
                  label: 'Username',
                  value: member.username,
                  theme: theme,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: member.username));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Username copied'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
              _DetailRow(
                icon: Icons.person,
                label: 'ID',
                value: member.userId,
                theme: theme,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: member.userId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID copied'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
              if (member.role.isNotEmpty && member.role != 'member')
                _DetailRow(
                  icon: Icons.shield,
                  label: 'Role',
                  value: member.role,
                  theme: theme,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvatarHeader extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;
  final bool isOnline;
  final ({String kind, int lastSeenMs}) lastSeen;

  const _AvatarHeader({
    required this.chat,
    required this.theme,
    this.isOnline = false,
    this.lastSeen = (kind: '', lastSeenMs: 0),
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];
    final initials = _initials(chat.title);

    // Compute status line. For DMs: online (green) / last seen (muted).
    // For groups/channels/topics: member or subscriber count (muted).
    final isDm = chat.type == ChatType.dm;
    final String statusText = isDm
        ? (isOnline ? 'online' : formatChatLastSeen(lastSeen))
        : _groupStatusText(chat);
    final Color? statusColor = isDm && isOnline
        ? const Color(0xFF3BA55C) // online green
        : theme.textTheme.bodySmall?.color;

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
        // Status line: online/last-seen for DMs, member count for groups/channels.
        if (statusText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              statusText,
              style: TextStyle(fontSize: 13, color: statusColor),
            ),
          ),
      ],
    );
  }

  static String _groupStatusText(ChatInfo chat) {
    if (chat.type == ChatType.channel) {
      return '${_formatCount(chat.memberCount)} subscribers';
    }
    if ((chat.type == ChatType.group || chat.type == ChatType.topic) &&
        chat.memberCount > 0) {
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
  final void Function(MemberInfo)? onMemberTap;

  const _MembersSection({
    required this.members,
    required this.loading,
    required this.memberCount,
    required this.theme,
    this.onMemberTap,
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
            ...members!.map((m) => _MemberRow(member: m, theme: theme, onTap: onMemberTap != null ? () => onMemberTap!(m) : null))
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
  final VoidCallback? onTap;

  const _MemberRow({required this.member, required this.theme, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = member.displayName.isNotEmpty ? member.displayName : member.username;
    final colorIndex = member.userId.hashCode.abs() % 7;
    final color = [
      const Color(0xFFe17076), const Color(0xFF7bc862), const Color(0xFFe5ca77),
      const Color(0xFF65aadd), const Color(0xFFa695e7), const Color(0xFFee7aae),
      const Color(0xFF6ec9cb),
    ][colorIndex];

    Widget row = Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
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
                else if (member.isOnline)
                  Text(
                    'online',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: theme.textTheme.bodySmall?.color),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: row,
      );
    }
    return row;
  }
}
