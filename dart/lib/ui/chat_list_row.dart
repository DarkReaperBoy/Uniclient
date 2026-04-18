import 'dart:io';

import 'package:flutter/material.dart';

import '../models/engine_models.dart';

/// Single chat row in the sidebar chat list.
/// Spec §2: 62px height, 46px avatar, exact positioning.
class ChatListRow extends StatelessWidget {
  final ChatInfo chat;
  final bool isActive;
  final bool isOnline;
  final String? typingUser;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onSecondaryTap;

  const ChatListRow({
    super.key,
    required this.chat,
    required this.isActive,
    this.isOnline = false,
    this.typingUser,
    required this.onTap,
    this.onSecondaryTap,
  });

  // Spec dimensions.
  static const _rowHeight = 62.0;
  static const _avatarSize = 46.0;
  static const _avatarLeft = 10.0;
  static const _contentLeft = 68.0; // avatarLeft + avatarSize + gap
  static const _paddingRight = 10.0;

  // Spec §2 "Active/selected": Background #419fd9 (Telegram blue), all text white, badges inverted.
  static const _activeBg = Color(0xFF419fd9);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Colors per state.
    final nameColor = isActive
        ? Colors.white
        : theme.textTheme.bodyLarge?.color;
    final mutedColor = isActive
        ? Colors.white70
        : theme.textTheme.bodySmall?.color;
    final badgeBg = isActive
        ? Colors.white
        : (chat.isMuted
            ? (isDark ? const Color(0xFF5c6573) : const Color(0xFFbbbbbb))
            : theme.colorScheme.primary);
    final badgeText = isActive
        ? _activeBg
        : Colors.white;

    // Use a plain Container (not Material widget) to avoid MD3 surface-tint behavior
    // that washes Material(color: primary) to white in a ColorScheme.dark context.
    return Container(
      color: isActive ? _activeBg : null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTap == null
              ? null
              : (details) => onSecondaryTap!(details.globalPosition),
          hoverColor: isActive
              ? Colors.white.withValues(alpha: 0.08)
              : (isDark ? const Color(0xFF1e2430) : const Color(0xFFF1F1F1)),
          child: SizedBox(
            height: _rowHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: _avatarLeft, right: _paddingRight),
            child: Row(
              children: [
                // Avatar with online dot.
                _ChatAvatar(
                  chat: chat,
                  size: _avatarSize,
                  isOnline: isOnline,
                ),
                const SizedBox(width: _contentLeft - _avatarLeft - _avatarSize),
                // Content.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10), // y=10 from spec
                      // Top row: name + timestamp.
                      Row(
                        children: [
                          // Chat type icon.
                          if (_typeIcon != null) ...[
                            Icon(_typeIcon, size: 16, color: mutedColor),
                            const SizedBox(width: 3),
                          ],
                          // Chat name.
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    chat.title.isNotEmpty ? chat.title : chat.chatId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: chat.title.isEmpty ? mutedColor : nameColor,
                                    ),
                                  ),
                                ),
                                if (chat.isMuted) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.volume_off, size: 14, color: mutedColor),
                                ],
                              ],
                            ),
                          ),
                          // Timestamp. Per-chat last-message send/delivery/read
                          // state is not piped through the engine yet, so the
                          // sent/delivered/read tick icon is intentionally absent
                          // (CLAUDE.md ZERO placeholders rule). Add it back when
                          // ChatInfo carries the real status.
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(chat.lastMsgTime),
                            style: TextStyle(fontSize: 12, color: mutedColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Bottom row: preview + badges.
                      Row(
                        children: [
                          Expanded(
                            child: _buildPreview(nameColor!, mutedColor!),
                          ),
                          // Unread badge or pin icon.
                          if (chat.unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            _UnreadBadge(
                              count: chat.unreadCount,
                              bgColor: badgeBg,
                              textColor: badgeText,
                            ),
                          ] else if (chat.isPinned) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.push_pin, size: 14, color: mutedColor),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildPreview(Color nameColor, Color mutedColor) {
    // Typing indicator.
    if (typingUser != null) {
      return Text(
        '$typingUser is typing...',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: const Color(0xFF168acd), // Spec: sender prefix / service color
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Draft prefix.
    if (chat.draftText.isNotEmpty) {
      return Text.rich(
        TextSpan(children: [
          TextSpan(
            text: 'Draft: ',
            style: TextStyle(fontSize: 13, color: const Color(0xFFdd4b39)),
          ),
          TextSpan(
            text: chat.draftText,
            style: TextStyle(fontSize: 13, color: mutedColor),
          ),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Normal preview: sender + text.
    if (chat.lastMsgText.isEmpty) {
      return const SizedBox.shrink();
    }

    final showSender = chat.lastMsgSender.isNotEmpty &&
        (chat.type == ChatType.group || chat.type == ChatType.channel);

    return Text.rich(
      TextSpan(children: [
        if (showSender)
          TextSpan(
            text: '${chat.lastMsgSender}: ',
            style: TextStyle(
              fontSize: 13,
              color: isActive ? Colors.white70 : const Color(0xFF168acd),
            ),
          ),
        TextSpan(
          text: chat.lastMsgText,
          style: TextStyle(fontSize: 13, color: mutedColor),
        ),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  IconData? get _typeIcon => switch (chat.type) {
    ChatType.channel => Icons.campaign,
    ChatType.group => Icons.group,
    ChatType.topic => Icons.forum,
    _ => null,
  };

  static String _formatTime(int timestampMs) {
    if (timestampMs == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0 && dt.day == now.day) {
      // Today: show time.
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1 || (diff.inDays == 0 && dt.day != now.day)) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1];
    }
    return '${_monthAbbr[dt.month - 1]} ${dt.day}';
  }

  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
}

/// Circular avatar with fallback color + initials + online dot.
class _ChatAvatar extends StatelessWidget {
  final ChatInfo chat;
  final double size;
  final bool isOnline;

  const _ChatAvatar({required this.chat, required this.size, this.isOnline = false});

  @override
  Widget build(BuildContext context) {
    // Assign a color based on chat ID hash (7-color scheme from spec).
    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];

    final initials = _initials(chat.title);

    final avatar = chat.avatarPath.isNotEmpty
        ? ClipOval(
            child: Image.file(
              File(chat.avatarPath),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(color, initials),
            ),
          )
        : _fallback(color, initials);

    if (!isOnline) {
      return SizedBox(width: size, height: size, child: avatar);
    }

    // Online: overlay green dot at bottom-right.
    const dotSize = 12.0;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: const Color(0xFF4dcd5e),
                shape: BoxShape.circle,
                border: Border.all(color: bgColor, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(Color color, String initials) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
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

  // 7 colors matching Telegram's peer color scheme.
  static const _avatarColors = [
    Color(0xFFe17076), // red
    Color(0xFF7bc862), // green
    Color(0xFFe5ca77), // yellow
    Color(0xFF65aadd), // blue
    Color(0xFFa695e7), // purple
    Color(0xFFee7aae), // pink
    Color(0xFF6ec9cb), // cyan
  ];
}

/// Pill-shaped unread count badge.
class _UnreadBadge extends StatelessWidget {
  final int count;
  final Color bgColor;
  final Color textColor;

  const _UnreadBadge({
    required this.count,
    required this.bgColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final text = count > 999 ? '999+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}
