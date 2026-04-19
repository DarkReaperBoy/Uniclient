import 'dart:io';
import 'dart:math' as math;

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

  // Spec §2 exact colors.
  static const _nameColorDay = Color(0xFF222222);
  static const _mutedColorDay = Color(0xFF999999);
  static const _timestampColorDay = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Colors per state — use exact spec hex values for day theme.
    final nameColor = isActive
        ? Colors.white
        : (isDark ? theme.textTheme.bodyLarge?.color : _nameColorDay);
    final mutedColor = isActive
        ? Colors.white
        : (isDark ? theme.textTheme.bodySmall?.color : _mutedColorDay);
    final badgeBg = isActive
        ? Colors.white
        : (chat.isMuted
            ? (isDark ? const Color(0xFF3e546a) : const Color(0xFFbbbbbb)) // Spec §2: muted badge
            : (isDark ? const Color(0xFF40a7e3) : const Color(0xFF40a7e3))); // Spec §2: windowBgActive
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
              : (isDark ? const Color(0xFF202b36) : const Color(0xFFF1F1F1)), // Spec §2: night #202b36, day #f1f1f1
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
                                if (chat.isVerified) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.verified,
                                    size: 16,
                                    color: isActive ? Colors.white : const Color(0xFF168acd),
                                  ),
                                ],
                                if (chat.isScam) ...[
                                  const SizedBox(width: 4),
                                  _WarningBadge(label: 'SCAM', isActive: isActive),
                                ],
                                if (chat.isFake) ...[
                                  const SizedBox(width: 4),
                                  _WarningBadge(label: 'FAKE', isActive: isActive),
                                ],
                                if (chat.isMuted) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.volume_off, size: 14, color: mutedColor),
                                ],
                              ],
                            ),
                          ),
                          // Timestamp — spec §2: 13px, #999999 day / white active, 5px skip from right.
                          const SizedBox(width: 5),
                          Text(
                            _formatTime(chat.lastMsgTime),
                            style: TextStyle(
                              fontSize: 13,
                              color: isActive
                                  ? Colors.white
                                  : (isDark ? theme.textTheme.bodySmall?.color : _timestampColorDay),
                            ),
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
    // Typing indicator: animated dots replacing preview text (spec §2).
    if (typingUser != null) {
      return _TypingDotsIndicator(
        userName: typingUser!,
        color: const Color(0xFF168acd),
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

  IconData? get _typeIcon {
    if (chat.isBot) return Icons.smart_toy;
    return switch (chat.type) {
      ChatType.channel => Icons.campaign,
      ChatType.group => Icons.group,
      ChatType.topic => Icons.forum,
      _ => null,
    };
  }

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

/// Circular avatar with fallback color + initials + online dot + stories ring.
/// Spec §2: stories ring has two geometry modes:
///   full/expanded: photo 42px, unread line 2px, read line 1px
///   small/minified (sidebar collapsed): photo 21px, unread line 1.5px, read line not drawn
class _ChatAvatar extends StatelessWidget {
  final ChatInfo chat;
  final double size;
  final bool isOnline;
  final bool minified;

  const _ChatAvatar({
    required this.chat,
    required this.size,
    this.isOnline = false,
    this.minified = false,
  });

  // Spec §2: full/expanded stories ring geometry.
  static const _storyPhotoSizeFull = 42.0;
  static const _unreadLineWidthFull = 2.0;
  static const _readLineWidthFull = 1.0;

  // Spec §2: small/minified stories ring geometry.
  static const _storyPhotoSizeSmall = 21.0;
  static const _unreadLineWidthSmall = 1.5;
  static const _readLineWidthSmall = 0.0; // not drawn

  bool get _hasStories => chat.storyCount > 0;

  @override
  Widget build(BuildContext context) {
    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];
    final initials = _initials(chat.title);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final storyPhotoSize = minified ? _storyPhotoSizeSmall : _storyPhotoSizeFull;
    final photoSize = _hasStories ? storyPhotoSize : size;

    final avatar = chat.avatarPath.isNotEmpty
        ? ClipOval(
            child: Image.file(
              File(chat.avatarPath),
              width: photoSize,
              height: photoSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(color, initials, photoSize),
            ),
          )
        : _fallback(color, initials, photoSize);

    // No stories, no online dot — simple case.
    if (!_hasStories && !isOnline) {
      return SizedBox(width: size, height: size, child: avatar);
    }

    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Stories ring (painted behind the avatar).
          if (_hasStories)
            Positioned.fill(
              child: CustomPaint(
                painter: _StoriesRingPainter(
                  storyCount: chat.storyCount,
                  hasUnread: chat.hasUnreadStory,
                  isLiveStream: chat.isLiveStream,
                  isDark: isDark,
                  minified: minified,
                ),
              ),
            ),
          // Avatar photo, centered (shrunk to 42px when stories present).
          if (_hasStories)
            Positioned(
              left: (size - photoSize) / 2,
              top: (size - photoSize) / 2,
              child: avatar,
            )
          else
            avatar,
          // Online dot at bottom-right.
          if (isOnline && !_hasStories)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF4dc920),
                  shape: BoxShape.circle,
                  border: Border.all(color: bgColor, width: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallback(Color color, String initials, double photoSize) {
    return Container(
      width: photoSize,
      height: photoSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: photoSize * 0.38,
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
    Color(0xFFe17076), // red
    Color(0xFF7bc862), // green
    Color(0xFFe5ca77), // yellow
    Color(0xFF65aadd), // blue
    Color(0xFFa695e7), // purple
    Color(0xFFee7aae), // pink
    Color(0xFF6ec9cb), // cyan
  ];
}

/// Custom painter for stories ring around chat list avatars.
/// Spec §2: two geometry modes (full/expanded and small/minified).
/// Ring offset outside userpic by 1.5 × lineWidth.
class _StoriesRingPainter extends CustomPainter {
  final int storyCount;
  final bool hasUnread;
  final bool isLiveStream;
  final bool isDark;
  final bool minified;
  final double readOpacity;

  _StoriesRingPainter({
    required this.storyCount,
    required this.hasUnread,
    required this.isLiveStream,
    required this.isDark,
    this.minified = false,
    this.readOpacity = 0.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (storyCount <= 0) return;

    // Spec §2: small/minified read ring is not drawn (lineReadTwice: 0px).
    final lineWidth = hasUnread
        ? (minified ? _ChatAvatar._unreadLineWidthSmall : _ChatAvatar._unreadLineWidthFull)
        : (minified ? _ChatAvatar._readLineWidthSmall : _ChatAvatar._readLineWidthFull);
    if (lineWidth <= 0) return; // small/minified read ring: skip entirely

    final photoRadius = minified
        ? _ChatAvatar._storyPhotoSizeSmall / 2
        : _ChatAvatar._storyPhotoSizeFull / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final offset = 1.5 * lineWidth;
    final ringRadius = photoRadius + offset;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;

    // Spec §2: read ring opacity = 0.6 (main strip), 1.0 (Info/Mine strips).
    // Applied as QPainter opacity (canvas-level), not color alpha channel.
    final applyReadOpacity = !hasUnread && !isLiveStream && readOpacity < 1.0;

    if (isLiveStream) {
      // Spec §2: live-stream ring = solid attentionButtonFg (red).
      paint.color = const Color(0xFFe53935);
    } else if (hasUnread) {
      // Spec §2: unread gradient topRight→bottomLeft, #0dcc39 green→#0992ef blue.
      // Theme-invariant (same in day and night).
      paint.shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF0dcc39), Color(0xFF0992ef)],
      ).createShader(Rect.fromCircle(center: center, radius: ringRadius));
    } else {
      // Spec §2: read ring = solid dialogsUnreadBgMuted.
      paint.color = isDark
          ? const Color(0xFF3e546a)
          : const Color(0xFFbbbbbb);
    }

    if (applyReadOpacity) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, readOpacity));
    }

    if (storyCount == 1) {
      // Spec §2: single story = full ellipse.
      canvas.drawCircle(center, ringRadius, paint);
    } else {
      // Spec §2: multi-story ring = segments with ~160-unit separators, round caps.
      _drawSegmentedRing(canvas, center, ringRadius, paint);
    }

    if (applyReadOpacity) {
      canvas.restore();
    }
  }

  /// Draw segmented ring arcs for multi-story rings.
  /// Spec §2: ~160 out of 5760 units (full circle) per separator, round caps.
  void _drawSegmentedRing(
      Canvas canvas, Offset center, double radius, Paint paint) {
    // 5760 units = full circle (Qt convention), separator = ~160 units.
    const fullCircleUnits = 5760.0;
    const separatorUnits = 160.0;
    final separatorRadians = (separatorUnits / fullCircleUnits) * 2 * math.pi;
    final totalSep = storyCount * separatorRadians;
    final arcPerStory = (2 * math.pi - totalSep) / storyCount;

    // Start from top (−π/2).
    var startAngle = -math.pi / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < storyCount; i++) {
      canvas.drawArc(rect, startAngle, arcPerStory, false, paint);
      startAngle += arcPerStory + separatorRadians;
    }
  }

  @override
  bool shouldRepaint(_StoriesRingPainter oldDelegate) =>
      storyCount != oldDelegate.storyCount ||
      hasUnread != oldDelegate.hasUnread ||
      isLiveStream != oldDelegate.isLiveStream ||
      isDark != oldDelegate.isDark ||
      minified != oldDelegate.minified ||
      readOpacity != oldDelegate.readOpacity;
}

/// Animated typing indicator: "UserName typing" + bouncing dots.
/// Spec §2: replaces preview text with animated dots.
class _TypingDotsIndicator extends StatefulWidget {
  final String userName;
  final Color color;

  const _TypingDotsIndicator({required this.userName, required this.color});

  @override
  State<_TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<_TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '${widget.userName} typing',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: widget.color,
            ),
          ),
        ),
        const SizedBox(width: 1),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // Stagger each dot by 1/3 of the cycle, bounce up using sin().
                final phase = (_controller.value + i / 3.0) * 2 * math.pi;
                final dy = -3.0 * math.max(0.0, math.sin(phase));
                return Padding(
                  padding: const EdgeInsets.only(left: 1),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Text(
                      '.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: widget.color,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

/// Red text badge for scam/fake indicators.
/// Spec §2: rendered inline after name, red border + red text.
class _WarningBadge extends StatelessWidget {
  final String label;
  final bool isActive;

  const _WarningBadge({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.white : const Color(0xFFe53935);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.0,
        ),
      ),
    );
  }
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

  // Spec §2: 19px height, 5px horizontal padding, min-width = 19px (circle for single digit),
  // fully round ends (radius = height/2 = 9.5), 12px bold font, text vertically centered.
  @override
  Widget build(BuildContext context) {
    final text = count > 999 ? '..${count % 1000}' : count.toString();
    return Container(
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      constraints: const BoxConstraints(minWidth: 19),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: textColor,
          height: 1.0,
        ),
      ),
    );
  }
}
