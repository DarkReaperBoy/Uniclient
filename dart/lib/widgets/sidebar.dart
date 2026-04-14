import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../models/engine_models.dart';
import '../screens/settings_screen.dart';
import '../theme/theme.dart';

/// Sidebar — chat list with search, folders, and chat items.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchController = TextEditingController();
  bool _searching = false;
  List<ChatInfo>? _searchResults;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = context.watch<ChatState>();
    final appState = context.watch<AppState>();

    final chats = _searchResults ?? chatState.chats;
    final pinned = chats.where((c) => c.isPinned && !c.isArchived).toList();
    final regular = chats.where((c) => !c.isPinned && !c.isArchived).toList();

    return Container(
      color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    appState.activePlatform.isEmpty
                        ? 'All Chats'
                        : _platformLabel(appState.activePlatform),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_square, size: 20),
                  onPressed: () {},
                  tooltip: 'New message',
                  splashRadius: 18,
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searching
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: _clearSearch,
                        splashRadius: 14,
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),

          const SizedBox(height: 4),

          // Chat list
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (pinned.isNotEmpty) ...[
                  _SectionHeader(title: 'Pinned', count: pinned.length),
                  for (final chat in pinned)
                    _ChatItem(chat: chat),
                ],
                if (regular.isNotEmpty) ...[
                  if (pinned.isNotEmpty)
                    _SectionHeader(title: 'Messages', count: regular.length),
                  for (final chat in regular)
                    _ChatItem(chat: chat),
                ],
                if (chats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _searching ? 'No results' : 'No chats yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // User panel (bottom)
          const _UserPanel(),
        ],
      ),
    );
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      _clearSearch();
      return;
    }
    setState(() {
      _searching = true;
      _searchResults = context.read<ChatState>().searchChats(query);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _searchResults = null;
    });
  }

  String _platformLabel(String platform) => switch (platform) {
    'telegram' => 'Telegram',
    'bale' => 'Bale',
    'matrix' => 'Matrix',
    'irc' => 'IRC',
    'xmpp' => 'XMPP',
    'github' => 'GitHub',
    'rubika' => 'Rubika',
    'deltachat' => 'Delta Chat',
    'teamspeak' => 'TeamSpeak',
    'mumble' => 'Mumble',
    _ => platform,
  };
}

/// Collapsible section header.
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single chat item in the sidebar.
class _ChatItem extends StatelessWidget {
  final ChatInfo chat;
  const _ChatItem({required this.chat});

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = chatState.activeChat?.chatId == chat.chatId &&
        chatState.activeChat?.accountId == chat.accountId;
    final typing = chatState.typingUserFor(chat.chatId);

    return Material(
      color: isActive
          ? (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt)
          : Colors.transparent,
      child: InkWell(
        onTap: () => chatState.openChat(chat),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Avatar
              _ChatAvatar(chat: chat),
              const SizedBox(width: 12),

              // Name + preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Type icon
                        if (chat.type == ChatType.group || chat.type == ChatType.topic)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.group, size: 14,
                              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                          ),
                        if (chat.type == ChatType.channel)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.campaign, size: 14,
                              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                          ),
                        // Title
                        Expanded(
                          child: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                              color: isDark ? AppColors.darkText : AppColors.lightText,
                            ),
                          ),
                        ),
                        // Time
                        if (chat.lastMsgTime > 0)
                          Text(
                            _formatTime(chat.lastMsgDateTime),
                            style: TextStyle(
                              fontSize: 11,
                              color: chat.unreadCount > 0
                                  ? AppColors.accent
                                  : (isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        // Preview text or typing indicator
                        Expanded(
                          child: typing != null
                              ? Text(
                                  '$typing is typing...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.accent,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Text(
                                  chat.draftText.isNotEmpty
                                      ? 'Draft: ${chat.draftText}'
                                      : _previewText(chat),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: chat.draftText.isNotEmpty
                                        ? AppColors.danger
                                        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                  ),
                                ),
                        ),
                        // Unread badge
                        if (chat.unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 20),
                            decoration: BoxDecoration(
                              color: chat.isMuted ? AppColors.darkTextDim : AppColors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        // Pin indicator
                        if (chat.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.push_pin, size: 12,
                              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                          ),
                        // Muted indicator
                        if (chat.isMuted)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.notifications_off, size: 12,
                              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
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
    );
  }

  String _previewText(ChatInfo chat) {
    if (chat.lastMsgText.isEmpty) return '';
    if (chat.lastMsgSender.isNotEmpty) {
      return '${chat.lastMsgSender}: ${chat.lastMsgText}';
    }
    return chat.lastMsgText;
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }
}

/// Chat avatar with type-appropriate styling.
class _ChatAvatar extends StatelessWidget {
  final ChatInfo chat;
  const _ChatAvatar({required this.chat});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?';

    // Generate a stable color from the chat ID.
    final hue = (chat.chatId.hashCode % 360).abs().toDouble();
    final bgColor = HSLColor.fromAHSL(1, hue, 0.5, isDark ? 0.3 : 0.75).toColor();

    return SizedBox(
      width: AppSizes.avatarSize,
      height: AppSizes.avatarSize,
      child: Stack(
        children: [
          Container(
            width: AppSizes.avatarSize,
            height: AppSizes.avatarSize,
            decoration: BoxDecoration(
              color: bgColor,
              shape: chat.type == ChatType.channel ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: chat.type == ChatType.channel ? BorderRadius.circular(8) : null,
            ),
            child: Center(
              child: chat.type == ChatType.channel
                  ? const Icon(Icons.campaign, color: Colors.white, size: 20)
                  : Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          // Online dot for DMs
          if (chat.type == ChatType.dm)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.online,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// User panel at the bottom of the sidebar.
class _UserPanel extends StatelessWidget {
  const _UserPanel();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: AppSizes.avatarSizeSmall,
            height: AppSizes.avatarSizeSmall,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'User',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                const Text(
                  'Online',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.online,
                  ),
                ),
              ],
            ),
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            splashRadius: 16,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
