import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/engine_models.dart';

/// Spec §2.7: Data carried during a drag-and-drop forward gesture.
/// MIME equivalent of Telegram Desktop's `application/x-td-forward`.
class ForwardDragData {
  final String accountId;
  final String sourceChatId;
  final List<String> messageIds;

  const ForwardDragData({
    required this.accountId,
    required this.sourceChatId,
    required this.messageIds,
  });
}

/// Single chat row in the sidebar chat list.
/// Spec §2: 62px height, 46px avatar, exact positioning.
class ChatListRow extends StatelessWidget {
  final ChatInfo chat;
  final bool isActive;
  final bool isOnline;
  final bool isNarrow;
  final String? typingUser;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onSecondaryTap;

  /// Spec §2.7: Visual highlight when forward-drag is hovering over this row.
  final bool isForwardHovered;

  const ChatListRow({
    super.key,
    required this.chat,
    required this.isActive,
    this.isOnline = false,
    this.isNarrow = false,
    this.typingUser,
    required this.onTap,
    this.onSecondaryTap,
    this.isForwardHovered = false,
  });

  // Spec dimensions.
  static const _rowHeight = 62.0;
  static const _avatarSize = 46.0;
  static const _avatarLeft = 10.0;
  static const _contentLeft = 68.0; // avatarLeft + avatarSize + gap
  static const _paddingRight = 10.0;

  // Spec §2 exact active/selected bg per theme (computed in build).
  // Day: #419fd9, Night: #2b5278.

  // Spec §2 exact colors.
  static const _nameColorDay = Color(0xFF222222);
  static const _mutedColorDay = Color(0xFF999999);
  static const _timestampColorDay = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Spec §2: Active row background differs by theme.
    final activeBg = isDark ? const Color(0xFF2b5278) : const Color(0xFF419fd9);
    // Spec §2: Day default bg = #ffffff; night uses theme default.
    final defaultBg = isDark ? null : const Color(0xFFffffff);

    // Colors per state — use exact spec hex values for day theme.
    final nameColor = isActive
        ? Colors.white
        : (isDark ? theme.textTheme.bodyLarge?.color : _nameColorDay);
    final mutedColor = isActive
        ? Colors.white
        : (isDark ? theme.textTheme.bodySmall?.color : _mutedColorDay);

    // Spec §2.7: Forward-drag hover highlight — windowBgOver tint.
    final Color? rowBg;
    if (isForwardHovered) {
      rowBg = isDark ? const Color(0xFF2b3a4a) : const Color(0xFFe3f0fd);
    } else if (isActive) {
      rowBg = activeBg;
    } else {
      rowBg = defaultBg;
    }

    // Use a plain Container (not Material widget) to avoid MD3 surface-tint behavior
    // that washes Material(color: primary) to white in a ColorScheme.dark context.
    return Container(
      color: rowBg,
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
          splashColor: isActive
              ? (isDark ? const Color(0xFF315a80) : const Color(0xFF2095d0))
              : (isDark ? const Color(0xFF25313d) : const Color(0xFFe5e5e5)), // Spec §2: ripple colors
          child: _HoverBuilder(
            builder: (_, isHovered) {
              // Spec §2: Unread pill Over and Active color variants.
              final badgeBg = isActive
                  ? (isDark
                      ? (chat.isMuted ? const Color(0xFF7aa3ca) : Colors.white)
                      : Colors.white)
                  : isHovered
                      ? (chat.isMuted
                          ? (isDark ? const Color(0xFF4d5762) : const Color(0xFFbbbbbb))
                          : (isDark ? const Color(0xFF4082bc) : const Color(0xFF40a7e3)))
                      : (chat.isMuted
                          ? (isDark ? const Color(0xFF3e546a) : const Color(0xFFbbbbbb))
                          : (isDark ? const Color(0xFF40a7e3) : const Color(0xFF40a7e3)));
              final badgeText = isActive ? activeBg : Colors.white;

              // Spec §1: Collapsed/avatar-only mode — 72px column shows only
              // the centered avatar with compact unread overlay, no text.
              if (isNarrow) {
                return SizedBox(
                  height: _rowHeight,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _ChatAvatar(
                          chat: chat,
                          size: _avatarSize,
                          isOnline: isOnline,
                          minified: true,
                        ),
                        // Unread count badge at bottom-right of avatar.
                        if (chat.unreadCount > 0)
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: _UnreadBadge(
                              count: chat.unreadCount,
                              bgColor: badgeBg,
                              textColor: badgeText,
                            ),
                          )
                        else if (chat.isUnreadMark)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: _UnreadDot(bgColor: badgeBg),
                          ),
                        // Mention badge at top-right of avatar.
                        if (chat.unreadMentionCount > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: _ThreeStateBadgeIcon(
                              icon: Icons.alternate_email,
                              color: badgeBg,
                              isNarrow: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }

              return SizedBox(
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
                          // Spec §2: Send state icons — 20px skip, only for outgoing messages.
                          if (chat.lastMsgIsOutgoing && chat.lastMsgText.isNotEmpty)
                            _SendStateIcon(
                              status: chat.lastMsgStatus,
                              isActive: isActive,
                              isDark: isDark,
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
                          // Unread badge, unread dot, or pin icon.
                          if (chat.unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            _UnreadBadge(
                              count: chat.unreadCount,
                              bgColor: badgeBg,
                              textColor: badgeText,
                            ),
                          ] else if (chat.isUnreadMark) ...[
                            const SizedBox(width: 8),
                            _UnreadDot(bgColor: badgeBg),
                          ] else if (chat.isPinned) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.push_pin, size: 14, color: mutedColor),
                          ],
                          // Spec §2: Mention badge — 18x18 icon (wide), 13x13 in 19x19 circle (narrow).
                          if (chat.unreadMentionCount > 0) ...[
                            const SizedBox(width: 5),
                            _ThreeStateBadgeIcon(
                              icon: Icons.alternate_email,
                              color: badgeBg,
                              isNarrow: isNarrow,
                            ),
                          ],
                          // Spec §2: Reaction badge — 18x18 icon (wide), 13x13 in 19x19 circle (narrow).
                          if (chat.unreadReactionCount > 0) ...[
                            const SizedBox(width: 5),
                            _ThreeStateBadgeIcon(
                              icon: Icons.favorite,
                              color: badgeBg,
                              isNarrow: isNarrow,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
            },
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

    // Spec §2.3: Mini media previews — 16px thumbnail or media-type icon
    // before preview text. Strip the engine's emoji prefix when showing a
    // visual indicator (thumbnail image or icon) to avoid redundancy.
    final hasMedia = chat.lastMsgMediaType > 0;
    final hasThumb = hasMedia && chat.lastMsgThumbB64.isNotEmpty;

    // Strip leading emoji prefix from engine text when we show a visual indicator.
    final previewText = hasMedia
        ? _stripMediaEmoji(chat.lastMsgText)
        : chat.lastMsgText;

    final textWidget = Text.rich(
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
          text: previewText,
          style: TextStyle(fontSize: 13, color: mutedColor),
        ),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    // Case 1: base64 thumbnail available — show 16px image.
    if (hasThumb) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Image.memory(
              base64Decode(chat.lastMsgThumbB64),
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(width: 16, height: 16),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: textWidget),
        ],
      );
    }

    // Case 2: media type known but no thumbnail — show 16px media-type icon.
    final iconData = _mediaTypeIcon(chat.lastMsgMediaType);
    if (iconData != null) {
      return Row(
        children: [
          Icon(iconData, size: 16, color: mutedColor),
          const SizedBox(width: 4),
          Expanded(child: textWidget),
        ],
      );
    }

    // Case 3: plain text message.
    return textWidget;
  }

  /// Spec §2.3: Media-type icon for chat list preview when no thumbnail.
  /// Maps engine media type int (go/engine/db.go) to Material icon.
  static IconData? _mediaTypeIcon(int mediaType) {
    return switch (mediaType) {
      1 => Icons.photo_camera,    // MediaImage
      2 => Icons.videocam,        // MediaVideo
      3 => Icons.music_note,      // MediaAudio
      4 => Icons.mic,             // MediaVoice
      5 => Icons.videocam,        // MediaVideoNote
      6 => Icons.emoji_emotions,  // MediaSticker
      7 => Icons.gif_box,         // MediaGIF
      8 => Icons.attach_file,     // MediaFile
      _ => null,
    };
  }

  /// Strip leading emoji + space prefix that the engine prepends
  /// (e.g. "📷 Photo" → "Photo", "🎙 Voice message" → "Voice message").
  /// Only strips if the first rune is outside ASCII (i.e. an emoji)
  /// and is followed by a space.
  static String _stripMediaEmoji(String text) {
    if (text.isEmpty) return text;
    final runes = text.runes.toList();
    if (runes.length >= 2 && runes[0] > 0xFF && runes[1] == 0x20) {
      return String.fromCharCodes(runes.sublist(2));
    }
    return text;
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

/// Spec §2.7: Swipe quick action types.
/// Each maps to a specific icon and color in the revealed action area.
enum SwipeAction {
  mute,
  unmute,
  pin,
  unpin,
  read,
  unread,
  archive,
  unarchive,
  delete,
  disabled,
}

/// Spec §2.7: Resolve base swipe action string to the correct toggle variant
/// based on the chat's current state (ResolveQuickDialogLabel).
/// e.g. "archive" → SwipeAction.unarchive if chat is already archived.
SwipeAction resolveSwipeAction(String baseAction, ChatInfo chat) {
  switch (baseAction) {
    case 'mute':
      return chat.isMuted ? SwipeAction.unmute : SwipeAction.mute;
    case 'pin':
      return chat.isPinned ? SwipeAction.unpin : SwipeAction.pin;
    case 'read':
      return (chat.unreadCount > 0 || chat.isUnreadMark)
          ? SwipeAction.read
          : SwipeAction.unread;
    case 'archive':
      return chat.isArchived ? SwipeAction.unarchive : SwipeAction.archive;
    case 'delete':
      return SwipeAction.delete;
    default:
      return SwipeAction.archive;
  }
}

/// Spec §2.7: Icon data for each swipe action (20px dialogsQuickActionSize).
IconData _swipeActionIcon(SwipeAction action) {
  switch (action) {
    case SwipeAction.mute:
      return Icons.volume_off_outlined;
    case SwipeAction.unmute:
      return Icons.volume_up_outlined;
    case SwipeAction.pin:
      return Icons.push_pin_outlined;
    case SwipeAction.unpin:
      return Icons.push_pin;
    case SwipeAction.read:
      return Icons.done_all;
    case SwipeAction.unread:
      return Icons.mark_email_unread_outlined;
    case SwipeAction.archive:
      return Icons.archive_outlined;
    case SwipeAction.unarchive:
      return Icons.unarchive_outlined;
    case SwipeAction.delete:
      return Icons.delete_outlined;
    case SwipeAction.disabled:
      return Icons.block_outlined;
  }
}

/// Spec §2.7: Display label for each swipe action.
/// twoLines=true in TDesktop splits on first space for two-line layout.
String _swipeActionLabel(SwipeAction action) {
  switch (action) {
    case SwipeAction.mute:
      return 'Mute';
    case SwipeAction.unmute:
      return 'Unmute';
    case SwipeAction.pin:
      return 'Pin';
    case SwipeAction.unpin:
      return 'Unpin';
    case SwipeAction.read:
      return 'Read';
    case SwipeAction.unread:
      return 'Unread';
    case SwipeAction.archive:
      return 'Archive';
    case SwipeAction.unarchive:
      return 'Unarchive';
    case SwipeAction.delete:
      return 'Delete';
    case SwipeAction.disabled:
      return '';
  }
}

/// Spec §2.7: Background color for each swipe action (ResolveQuickActionBg).
/// Delete → attentionButtonFg (red), Disabled → windowSubTextFgOver (gray),
/// all others → windowBgActive (Telegram blue).
Color _swipeActionBgColor(SwipeAction action, bool isDark) {
  switch (action) {
    case SwipeAction.delete:
      // attentionButtonFg: red
      return isDark ? const Color(0xFFd14e4e) : const Color(0xFFd14e4e);
    case SwipeAction.disabled:
      // windowSubTextFgOver: gray
      return isDark ? const Color(0xFF8b8b8b) : const Color(0xFF919191);
    default:
      // windowBgActive: Telegram blue
      return isDark ? const Color(0xFF2b5278) : const Color(0xFF40a7e3);
  }
}

/// Spec §2.7: Swipe quick action wrapper for chat list rows.
/// Adds horizontal drag gesture with 50px base threshold (logical px, DPI-independent).
class SwipeableChatRow extends StatefulWidget {
  final Widget child;

  /// Called when swipe exceeds threshold and is released (action commits).
  final VoidCallback? onAction;

  /// The action to display in the revealed area. Determines icon and color.
  final SwipeAction action;

  const SwipeableChatRow({
    super.key,
    required this.child,
    this.onAction,
    this.action = SwipeAction.archive,
  });

  /// Spec §2.7: Base swipe threshold in logical pixels.
  /// Auto-scaled by DPI via Flutter's logical pixel system.
  static const kThresholdWidth = 50.0;

  /// Spec §2.7: Max clamped ratio — swipe commits after kThresholdWidth * kMaxRatio (~75px).
  static const kMaxRatio = 1.5;

  /// Spec §2.7: Slowdown factor past threshold — drag visually lags at 1/5
  /// actual speed, giving a rubberband feel.
  static const kSwipeSlow = 0.2;

  /// Spec §2.7: Swipe-back speed ratio after release (px per ms).
  /// Determines spring-back animation duration: offset / kSwipeBackSpeed.
  static const kSwipeBackSpeed = 0.35;

  @override
  State<SwipeableChatRow> createState() => _SwipeableChatRowState();
}

class _SwipeableChatRowState extends State<SwipeableChatRow>
    with TickerProviderStateMixin {
  double _swipeOffset = 0.0;
  late final AnimationController _resetController;
  late final AnimationController _rippleController;
  late final AnimationController _iconEntranceController;
  late final Animation<double> _iconScaleAnimation;
  double _resetFrom = 0.0;
  bool _committed = false;

  /// Spec §2.7: Track whether we've already fired haptic for this gesture.
  /// Fires once on threshold crossing, resets on drag end/cancel.
  bool _thresholdCrossed = false;

  /// Spec §2.7: Swipe progress normalized 0-1 against threshold.
  /// 0 = no swipe, 1 = threshold reached (50px).
  double get _swipeProgress =>
      (_swipeOffset / SwipeableChatRow.kThresholdWidth).clamp(0.0, 1.0);

  /// Spec §2.7: Max swipe distance in logical pixels (threshold * max ratio).
  double get _maxSwipeOffset =>
      SwipeableChatRow.kThresholdWidth * SwipeableChatRow.kMaxRatio;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _swipeOffset = _resetFrom * (1.0 - _resetController.value);
        });
      });
    // Spec §2.7: Ripple animation for 80px action area on threshold crossing.
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    // Spec §2.7: Lottie-like icon entrance animation — scale with overshoot bounce.
    _iconEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _iconScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 0.92)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
    ]).animate(_iconEntranceController);
  }

  @override
  void dispose() {
    _resetController.dispose();
    _rippleController.dispose();
    _iconEntranceController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_resetController.isAnimating) return;
    debugPrint('[SWIPE] dragUpdate dx=${details.delta.dx} offset=$_swipeOffset');
    final prevOffset = _swipeOffset;
    setState(() {
      // Spec §2.7: Apply slowdown factor 0.2 past threshold (rubberband feel).
      final dx = _swipeOffset >= SwipeableChatRow.kThresholdWidth
          ? details.delta.dx * SwipeableChatRow.kSwipeSlow
          : details.delta.dx;
      _swipeOffset = (_swipeOffset + dx).clamp(0.0, _maxSwipeOffset);
    });
    // Spec §2.7: Fire HapticEffect::Medium once when crossing threshold.
    // Also trigger 80px ripple area animation.
    if (!_thresholdCrossed &&
        prevOffset < SwipeableChatRow.kThresholdWidth &&
        _swipeOffset >= SwipeableChatRow.kThresholdWidth) {
      _thresholdCrossed = true;
      HapticFeedback.mediumImpact();
      _rippleController.forward(from: 0.0);
      _iconEntranceController.forward(from: 0.0);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    // Spec §2.7: If past threshold, commit the action.
    final pastThreshold = _swipeProgress >= 1.0;
    if (pastThreshold) {
      _committed = true;
      widget.onAction?.call();
    }
    _thresholdCrossed = false;
    _resetFrom = _swipeOffset;
    // Spec §2.7: Below-threshold release uses fixed ~200ms spring-back.
    // Above-threshold (committed) uses speed ratio 0.35 px/ms for proportional return.
    final int durationMs;
    if (pastThreshold) {
      // Spec §2.7: speed ratio 0.35 px/ms → duration = offset / 0.35
      durationMs = (_swipeOffset / 0.35).round().clamp(100, 600);
    } else {
      // Spec §2.7: fixed 200ms spring-back for below-threshold release
      durationMs = 200;
    }
    _resetController.duration = Duration(milliseconds: durationMs);
    _resetController.forward(from: 0.0).then((_) {
      _committed = false;
    });
  }

  void _onDragCancel() {
    _thresholdCrossed = false;
    if (_swipeOffset > 0) {
      _resetFrom = _swipeOffset;
      // Spec §2.7: Cancel is always below-threshold — fixed ~200ms spring-back.
      _resetController.duration = const Duration(milliseconds: 200);
      _resetController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_swipeOffset == 0.0 && !_resetController.isAnimating) {
      return GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: widget.child,
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec §2.7: Action color depends on action type (ResolveQuickActionBg).
    final actionBg = _swipeActionBgColor(widget.action, isDark);
    final progress = _swipeProgress;
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: ClipRect(
        child: Stack(
          children: [
            // Spec §2.7: Action area fades in with swipe progress.
            Positioned.fill(
              child: Opacity(
                opacity: progress,
                child: ColoredBox(color: actionBg),
              ),
            ),
            // Spec §2.7: Revealed action — 20px icon (dialogsQuickActionSize)
            // centered in 80px ripple area (dialogsQuickActionRippleSize).
            // Icon scales by iconRatio (swipe progress) with Lottie-like bounce
            // on threshold crossing.
            if (progress > 0.1)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _swipeOffset,
                child: Center(
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_rippleController, _iconEntranceController]),
                      builder: (context, child) {
                        // Spec §2.7: iconRatio = swipe progress, with bounce
                        // overlay when crossing threshold.
                        final baseScale = Curves.easeOut.transform(progress);
                        final bounceScale = _thresholdCrossed || _iconEntranceController.isAnimating
                            ? _iconScaleAnimation.value
                            : baseScale;
                        final iconScale = progress >= 1.0 ? bounceScale : baseScale;
                        final labelText = _swipeActionLabel(widget.action);
                        // Spec §2.7: twoLines=true — split on first space.
                        final displayLabel = labelText.replaceFirst(' ', '\n');
                        return CustomPaint(
                          painter: _SwipeRipplePainter(
                            rippleProgress: _rippleController.value,
                          ),
                          child: Center(
                            child: Transform.scale(
                              scale: iconScale,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _swipeActionIcon(widget.action),
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  if (labelText.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    // Spec §2.7: 13px semibold label, auto-shrinks
                                    // to min 5px via FittedBox scaleDown.
                                    SizedBox(
                                      width: 76,
                                      height: 32,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          displayLabel,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(_swipeOffset, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Spec §2.7: Ripple effect painter for the 80px swipe action area.
/// Draws an expanding circle that fades out, triggered on threshold crossing.
class _SwipeRipplePainter extends CustomPainter {
  final double rippleProgress;

  _SwipeRipplePainter({required this.rippleProgress});

  @override
  void paint(Canvas canvas, Size size) {
    if (rippleProgress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    // Expand from 0 to full 80px diameter, fade out as it expands.
    final radius = maxRadius * Curves.easeOut.transform(rippleProgress);
    final alpha = 0.20 * (1.0 - rippleProgress * 0.7);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
    );
  }

  @override
  bool shouldRepaint(_SwipeRipplePainter old) =>
      rippleProgress != old.rippleProgress;
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

  /// Saved Messages: identified by title + DM type (spec §31.1).
  bool get _isSavedMessages =>
      chat.title == 'Saved Messages' && chat.type == ChatType.dm;

  @override
  Widget build(BuildContext context) {
    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];
    final initials = _initials(chat.title);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final storyPhotoSize = minified ? _storyPhotoSizeSmall : _storyPhotoSizeFull;
    final photoSize = _hasStories ? storyPhotoSize : size;

    // Saved Messages: bookmark icon userpic (spec §31.1).
    final Widget avatar;
    if (_isSavedMessages) {
      avatar = _SavedMessagesUserpic(size: photoSize, isDark: isDark);
    } else if (chat.avatarPath.isNotEmpty) {
      avatar = ClipOval(
            child: Image.file(
              File(chat.avatarPath),
              width: photoSize,
              height: photoSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(color, initials, photoSize),
            ),
          );
    } else {
      avatar = _fallback(color, initials, photoSize);
    }

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
/// Spec §2.3: `allowDigits` controls `..N` truncation from `PaintUnreadBadge`.
/// When `allowDigits > 0` and digit count > `allowDigits + 1`, text becomes
/// `..` + last `allowDigits` digits (e.g. allowDigits=1 → `..3` for 123).
/// Default 0 = no truncation (standard dialog rows). Jump-down uses 4.
class _UnreadBadge extends StatelessWidget {
  final int count;
  final Color bgColor;
  final Color textColor;
  final int allowDigits;

  const _UnreadBadge({
    required this.count,
    required this.bgColor,
    required this.textColor,
    this.allowDigits = 0,
  });

  // Spec §2: 19px height, 5px horizontal padding, min-width = 19px (circle for single digit),
  // fully round ends (radius = height/2 = 9.5), 12px bold font, text vertically centered.
  @override
  Widget build(BuildContext context) {
    final raw = count.toString();
    final text = (allowDigits > 0 && raw.length > allowDigits + 1)
        ? '..${raw.substring(raw.length - allowDigits)}'
        : raw;
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

/// Spec §2: Unread dot when unreadMark set without counter.
/// 8px filled ellipse centered in 19x19 slot, same bg colors as the pill.
class _UnreadDot extends StatelessWidget {
  final Color bgColor;

  const _UnreadDot({required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 19,
      height: 19,
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Spec §2: ThreeStateIcon for mention/reaction/poll badges.
/// Wide mode: 18x18 colored icon glyph (no pill).
/// Narrow mode: 13x13 glyph inside a 19x19 unread-bg circle.
class _ThreeStateBadgeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isNarrow;

  const _ThreeStateBadgeIcon({
    required this.icon,
    required this.color,
    this.isNarrow = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isNarrow) {
      // Spec §2: narrow mode — 13x13 glyph centered inside 19x19 circle.
      return Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 13, color: Colors.white),
      );
    }
    return Icon(icon, size: 18, color: color);
  }
}

/// Spec §2: Send state icon — clock (sending), single check (sent), double check (delivered/read).
/// 20px total width slot. Only shown for outgoing messages.
/// Colors: historyOutIconFg = #57b84c day / #6bbfff night.
/// Sending clock: historySendingOutIconFg = #98d292 day / #70a4d2 night.
class _SendStateIcon extends StatelessWidget {
  final MsgStatus status;
  final bool isActive;
  final bool isDark;

  const _SendStateIcon({
    required this.status,
    required this.isActive,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (status == MsgStatus.unknown) return const SizedBox(width: 20);

    final Color iconColor;
    if (isActive) {
      iconColor = Colors.white;
    } else if (status == MsgStatus.sending) {
      iconColor = isDark ? const Color(0xFF70a4d2) : const Color(0xFF98d292);
    } else {
      iconColor = isDark ? const Color(0xFF6bbfff) : const Color(0xFF57b84c);
    }

    // Spec §2: clock 11x11, single check 13x11, double check 18x11.
    // Tick offset inside 20px slot: point(2,4).
    final IconData icon;
    final double iconSize;
    switch (status) {
      case MsgStatus.sending:
        icon = Icons.access_time;
        iconSize = 11;
      case MsgStatus.sent:
        icon = Icons.check;
        iconSize = 13;
      case MsgStatus.delivered:
      case MsgStatus.read:
        icon = Icons.done_all;
        iconSize = 14;
      case MsgStatus.failed:
        icon = Icons.error_outline;
        iconSize = 13;
      default:
        return const SizedBox(width: 20);
    }

    return SizedBox(
      width: 20,
      height: 11,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}

/// Returns true if [chat] is the Saved Messages self-chat (spec §31.1).
bool isSavedMessages(ChatInfo chat) =>
    chat.title == 'Saved Messages' && chat.type == ChatType.dm;

/// Saved Messages bookmark icon userpic (spec §31.1).
/// Blue vertical-gradient circle with white bookmark silhouette.
/// Replaces the normal avatar for the self-chat.
class _SavedMessagesUserpic extends StatelessWidget {
  final double size;
  final bool isDark;

  const _SavedMessagesUserpic({required this.size, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _SavedMessagesIconPainter(isDark: isDark),
      ),
    );
  }
}

/// Custom painter for the Saved Messages bookmark icon.
/// Spec §31.1: vertical gradient circle + centered bookmark silhouette.
/// Background: historyPeerSavedMessagesBg → historyPeerSavedMessagesBg2.
/// Icon: white bookmark with rounded top corners and sharp V-notch bottom.
class _SavedMessagesIconPainter extends CustomPainter {
  final bool isDark;

  _SavedMessagesIconPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final radius = s / 2;

    // Background: vertical gradient circle.
    // Day: #65a9e0 → #44b4f0, Night: #2a8dd8 → #46ade5.
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [const Color(0xFF2a8dd8), const Color(0xFF46ade5)]
            : [const Color(0xFF65a9e0), const Color(0xFF44b4f0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, bgPaint);

    // Bookmark icon dimensions (spec §31.1):
    // Width: SafeRound(size * 0.23) * 2 + increment (~22px at 46px)
    // Height: SafeRound(size * 0.19) * 2 + increment (~18px at 46px)
    // Notch: SafeRound(size * 0.064) (~3px at 46px)
    final halfW = (s * 0.23).roundToDouble();
    final halfH = (s * 0.19).roundToDouble();
    final bookWidth = halfW * 2 + 1;
    final bookHeight = halfH * 2 + 1;
    final notch = (s * 0.064).roundToDouble();
    final cornerR = s * 0.06; // top corner radius

    final left = (s - bookWidth) / 2;
    final top = (s - bookHeight) / 2;
    final right = left + bookWidth;
    final bottom = top + bookHeight;
    final cx = s / 2;
    final notchY = bottom - notch;

    // Bookmark path: rounded-top rectangle with V-notch at bottom center.
    final path = Path()
      ..moveTo(left, top + cornerR)
      ..quadraticBezierTo(left, top, left + cornerR, top) // top-left round
      ..lineTo(right - cornerR, top) // top edge
      ..quadraticBezierTo(right, top, right, top + cornerR) // top-right round
      ..lineTo(right, bottom) // right side down
      ..lineTo(cx, notchY) // right-to-center V-notch
      ..lineTo(left, bottom) // center-to-left V-notch
      ..close(); // back to start

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF) // historyPeerUserpicFg
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_SavedMessagesIconPainter oldDelegate) =>
      isDark != oldDelegate.isDark;
}

/// Hover-tracking wrapper that exposes hover state to its builder.
/// Used for Spec §2 unread pill Over/Active color variants.
class _HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;
  const _HoverBuilder({required this.builder});
  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.builder(context, _isHovered),
    );
  }
}
