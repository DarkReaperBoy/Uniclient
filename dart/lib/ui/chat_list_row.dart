import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';
import 'emoji_status_widget.dart';
import 'forum_topic_icon.dart';

final _thumbBytesCache = <String, Uint8List>{};
Uint8List _cachedThumbDecode(String b64) =>
    _thumbBytesCache.putIfAbsent(b64, () => base64Decode(b64));

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String formatChatListTime(int timestampMs) {
  if (timestampMs == 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inDays == 0 && dt.day == now.day) {
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
  final String typingAction;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onSecondaryTap;
  final VoidCallback? onStoryTap;

  /// Spec §2.7: Visual highlight when forward-drag is hovering over this row.
  final bool isForwardHovered;

  const ChatListRow({
    super.key,
    required this.chat,
    required this.isActive,
    this.isOnline = false,
    this.isNarrow = false,
    this.typingUser,
    this.typingAction = 'typing',
    required this.onTap,
    this.onSecondaryTap,
    this.isForwardHovered = false,
    this.onStoryTap,
  });

  // Spec dimensions.
  static const _rowHeight = 62.0;
  static const _avatarSize = 46.0;
  static const _avatarLeft = 10.0;
  static const _contentLeft = 68.0; // avatarLeft + avatarSize + gap
  static const _paddingRight = 10.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hidePremiumStatuses = context.select((AppState s) => s.hidePremiumStatuses);
    final showMuteIcon = context.select((AppState s) => s.experimentalFlags['dialogs_mute_icon']) != false;
    final showDrafts = context.select((AppState s) => s.experimentalFlags['message_draft_visible']) != false;

    final nameColor = isActive ? palette.dialogsNameFgActive : palette.dialogsNameFg;
    final mutedColor = isActive ? palette.dialogsTextFgActive : palette.dialogsTextFg;

    final Color? rowBg;
    if (isForwardHovered) {
      rowBg = Color.lerp(palette.dialogsBg, palette.dialogsBgActive, 0.15);
    } else if (isActive) {
      rowBg = palette.dialogsBgActive;
    } else {
      rowBg = palette.dialogsBg;
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
              : palette.dialogsBgOver,
          splashColor: isActive
              ? palette.dialogsRippleBgActive
              : palette.dialogsRippleBg,
          child: _HoverBuilder(
            builder: (_, isHovered) {
              final Color badgeBg;
              if (isActive) {
                badgeBg = chat.isMuted ? palette.dialogsUnreadBgMutedActive : palette.dialogsUnreadBgActive;
              } else if (isHovered) {
                badgeBg = chat.isMuted ? palette.dialogsUnreadBgMutedOver : palette.dialogsUnreadBgOver;
              } else {
                badgeBg = chat.isMuted ? palette.dialogsUnreadBgMuted : palette.dialogsUnreadBg;
              }
              final badgeText = isActive ? palette.dialogsUnreadFgActive : palette.dialogsUnreadFg;

              // Spec §1: Collapsed/avatar-only mode — column width 0 (only
              // filter sidebar visible); avatar rendering kept for narrow contexts.
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
                          isActive: isActive,
                          minified: true,
                          onStoryTap: onStoryTap,
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
                  isActive: isActive,
                  onStoryTap: onStoryTap,
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: chat.title.isEmpty ? mutedColor : nameColor,
                                    ),
                                  ),
                                ),
                                if (chat.isVerified) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.verified,
                                    size: 16,
                                    color: isActive ? palette.dialogsNameFgActive : palette.dialogsVerifiedIconBg,
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
                                if (chat.emojiStatusId.isNotEmpty &&
                                    !hidePremiumStatuses) ...[
                                  const SizedBox(width: 4),
                                  EmojiStatusWidget(
                                    emojiStatusId: chat.emojiStatusId,
                                    accountId: chat.accountId,
                                    size: 16,
                                    fallbackColor: isActive ? palette.dialogsNameFgActive : null,
                                  ),
                                ],
                                if (chat.isMuted && showMuteIcon) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.volume_off, size: 14, color: mutedColor),
                                ],
                              ],
                            ),
                          ),
                          if (chat.isClosed)
                            _SendStateIcon(
                              status: MsgStatus.unknown,
                              isActive: isActive,
                              isClosed: true,
                            )
                          else if (chat.lastMsgIsOutgoing && chat.lastMsgText.isNotEmpty)
                            _SendStateIcon(
                              status: chat.lastMsgStatus,
                              isActive: isActive,
                            ),
                          const SizedBox(width: 5),
                          Text(
                            formatChatListTime(chat.lastMsgTime),
                            style: TextStyle(
                              fontSize: 13,
                              color: isActive ? palette.dialogsTextFgActive : palette.dialogsDateFg,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Bottom row: preview + badges.
                      Row(
                        children: [
                          Expanded(
                            child: _buildPreview(palette, nameColor, mutedColor, showDrafts),
                          ),
                          // Unread badge or unread dot.
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
                          if (chat.unreadMentionCount > 0) ...[
                            const SizedBox(width: 5),
                            _ThreeStateBadgeIcon(
                              icon: Icons.alternate_email,
                              color: isNarrow ? badgeBg : palette.dialogsMentionIconFg,
                              isNarrow: isNarrow,
                            ),
                          ],
                          if (chat.unreadReactionCount > 0) ...[
                            const SizedBox(width: 5),
                            _ThreeStateBadgeIcon(
                              icon: Icons.favorite,
                              color: isNarrow ? badgeBg : palette.dialogsReactionIconFg,
                              isNarrow: isNarrow,
                            ),
                          ],
                          if (chat.unreadPollCount > 0) ...[
                            const SizedBox(width: 5),
                            _ThreeStateBadgeIcon(
                              icon: Icons.poll,
                              color: isNarrow ? badgeBg : palette.dialogsPollIconFg,
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

  Widget _buildPreview(TelegramPalette palette, Color nameColor, Color mutedColor, bool showDrafts) {
    if (typingUser != null) {
      return _TypingDotsIndicator(
        userName: typingUser!,
        action: typingAction,
        color: palette.dialogsTextFgService,
      );
    }

    if (showDrafts && chat.draftText.isNotEmpty) {
      return Text.rich(
        TextSpan(children: [
          if (chat.draftReplyToMsgId.isNotEmpty)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(Icons.reply, size: 14, color: palette.dialogsDraftFg),
              ),
            ),
          TextSpan(
            text: 'Draft: ',
            style: TextStyle(fontSize: 13, color: palette.dialogsDraftFg),
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
              color: isActive
                  ? palette.dialogsTextFgActive.withValues(alpha: 0.7)
                  : palette.dialogsTextFgService,
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
              _cachedThumbDecode(chat.lastMsgThumbB64),
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(width: 16, height: 16),
            ),
          ),
          const SizedBox(width: 2),
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
          const SizedBox(width: 2),
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
      if (chat.isSelf) return SwipeAction.disabled;
      return chat.isMuted ? SwipeAction.unmute : SwipeAction.mute;
    case 'pin':
      return chat.isPinned ? SwipeAction.unpin : SwipeAction.pin;
    case 'read':
      if (chat.isForum && chat.unreadCount == 0 && !chat.isUnreadMark) {
        return SwipeAction.disabled;
      }
      return (chat.unreadCount > 0 || chat.isUnreadMark)
          ? SwipeAction.read
          : SwipeAction.unread;
    case 'archive':
      if (chat.isSelf) return SwipeAction.disabled;
      return chat.isArchived ? SwipeAction.unarchive : SwipeAction.archive;
    case 'delete':
      return SwipeAction.delete;
    default:
      return SwipeAction.archive;
  }
}

/// Spec §2.7: Lottie asset path for each swipe action (20px dialogsQuickActionSize).
/// Draw-on animations driven by swipe progress via external AnimationController.
String _swipeActionLottiePath(SwipeAction action) {
  switch (action) {
    case SwipeAction.mute:
      return 'assets/animations/swipe_mute.json';
    case SwipeAction.unmute:
      return 'assets/animations/swipe_unmute.json';
    case SwipeAction.pin:
      return 'assets/animations/swipe_pin.json';
    case SwipeAction.unpin:
      return 'assets/animations/swipe_unpin.json';
    case SwipeAction.read:
      return 'assets/animations/swipe_read.json';
    case SwipeAction.unread:
      return 'assets/animations/swipe_unread.json';
    case SwipeAction.archive:
      return 'assets/animations/swipe_archive.json';
    case SwipeAction.unarchive:
      return 'assets/animations/swipe_unarchive.json';
    case SwipeAction.delete:
      return 'assets/animations/swipe_delete.json';
    case SwipeAction.disabled:
      return 'assets/animations/swipe_disabled.json';
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
Color _swipeActionBgColor(SwipeAction action, TelegramPalette palette) {
  switch (action) {
    case SwipeAction.delete:
      return palette.attentionButtonFg;
    case SwipeAction.disabled:
      return palette.windowSubTextFgOver;
    default:
      return palette.windowBgActive;
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

  /// Spec §13.4: Manhattan distance gate before swipe gesture begins (5-10px).
  static const kManhattanGate = 8.0;

  /// Spec §2.7: Base swipe threshold in logical pixels.
  /// Auto-scaled by DPI via Flutter's logical pixel system.
  static const kThresholdWidth = 50.0;

  /// Spec §2.7: Max clamped ratio — swipe commits after kThresholdWidth * kMaxRatio (~75px).
  static const kMaxRatio = 1.5;

  /// Spec §2.7: Slowdown factor past threshold — drag visually lags at 1/5
  /// actual speed, giving a rubberband feel.
  static const kSwipeSlow = 0.2;

  @override
  State<SwipeableChatRow> createState() => _SwipeableChatRowState();
}

class _SwipeableChatRowState extends State<SwipeableChatRow>
    with TickerProviderStateMixin {
  Offset? _dragStartGlobal;
  bool _manhattanPassed = false;
  double _swipeOffset = 0.0;
  late final AnimationController _resetController;
  late final AnimationController _rippleController;
  late final AnimationController _iconEntranceController;
  late final Animation<double> _iconScaleAnimation;
  /// Spec §2.7: Drives Lottie draw-on animation proportional to swipe progress.
  late final AnimationController _lottieController;
  double _resetFrom = 0.0;

  /// Spec §2.7: Track whether we've already fired haptic for this gesture.
  /// Fires once on threshold crossing, resets on drag end/cancel.
  bool _thresholdCrossed = false;

  /// AyuGram: Lottie animation started flag (starts at ratio > 0.32, resets at < 0.24).
  bool _lottieStarted = false;

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
    _lottieController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _resetController.dispose();
    _rippleController.dispose();
    _iconEntranceController.dispose();
    _lottieController.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartGlobal = details.globalPosition;
    _manhattanPassed = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_resetController.isAnimating) return;
    if (!_manhattanPassed) {
      if (_dragStartGlobal != null) {
        final manhattan =
            (details.globalPosition.dx - _dragStartGlobal!.dx).abs() +
                (details.globalPosition.dy - _dragStartGlobal!.dy).abs();
        if (manhattan < SwipeableChatRow.kManhattanGate) return;
      }
      _manhattanPassed = true;
    }
    final prevOffset = _swipeOffset;
    setState(() {
      final rawDx = -details.delta.dx;
      final dx = _swipeOffset >= SwipeableChatRow.kThresholdWidth
          ? rawDx * SwipeableChatRow.kSwipeSlow
          : rawDx;
      _swipeOffset = (_swipeOffset + dx).clamp(0.0, _maxSwipeOffset);
    });
    const double kStartAnimateThreshold = 0.32;
    const double kResetAnimateThreshold = 0.24;
    if (_swipeProgress > kStartAnimateThreshold && !_lottieStarted) {
      _lottieStarted = true;
      _lottieController.forward(from: 0.0);
    } else if (_swipeProgress < kResetAnimateThreshold && _lottieStarted) {
      _lottieStarted = false;
      _lottieController.value = 0.0;
    }
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
    _manhattanPassed = false;
    _dragStartGlobal = null;
    final pastThreshold = _swipeProgress >= 1.0;
    if (pastThreshold) {
      widget.onAction?.call();
    }
    _thresholdCrossed = false;
    _lottieStarted = false;
    _resetFrom = _swipeOffset;
    // AyuGram swipe_handler.cpp:164-168: committed = min(1, ratio) * slideWrapDuration (150ms).
    final int durationMs;
    if (pastThreshold) {
      durationMs = (math.min(1.0, _swipeProgress) * 150).round().clamp(50, 150);
    } else {
      durationMs = 200;
    }
    _resetController.duration = Duration(milliseconds: durationMs);
    _resetController.forward(from: 0.0);
  }

  void _onDragCancel() {
    _manhattanPassed = false;
    _dragStartGlobal = null;
    _thresholdCrossed = false;
    _lottieStarted = false;
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
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: widget.child,
      );
    }
    final actionBg = _swipeActionBgColor(widget.action, context.palette);
    final progress = _swipeProgress;
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
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
                right: 0,
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
                        return CustomPaint(
                          painter: _SwipeRipplePainter(
                            rippleProgress: _rippleController.value,
                            reachRatio: progress,
                            swipeOffset: _swipeOffset,
                            color: context.palette.windowSubTextFgOver,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 60,
                              child: Transform.scale(
                                scale: iconScale,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Lottie.asset(
                                        _swipeActionLottiePath(widget.action),
                                        controller: _lottieController,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    if (labelText.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      SizedBox(
                                        width: 56,
                                        height: 16,
                                        child: _SwipeLabel(text: labelText),
                                      ),
                                    ],
                                  ],
                                ),
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
              offset: Offset(-_swipeOffset, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Spec §2.7: Reach-ratio ellipse + threshold ripple for the 80px action area.
/// AyuGram draws a continuously growing ellipse at (width - 30, 30) using
/// ResolveQuickActionBgActive (windowSubTextFgOver), radius = swipeOffset * reachRatio.
/// On threshold crossing, a separate standard ripple fires.
class _SwipeRipplePainter extends CustomPainter {
  final double rippleProgress;
  final double reachRatio;
  final double swipeOffset;
  final Color color;

  _SwipeRipplePainter({
    required this.rippleProgress,
    required this.reachRatio,
    required this.swipeOffset,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const iconSize = 20.0;
    const offset = iconSize + iconSize / 2;
    final center = Offset(size.width - offset, offset);

    if (reachRatio > 0) {
      final r = swipeOffset * reachRatio;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: r * 2, height: r * 2),
        Paint()..color = color.withValues(alpha: 0.15),
      );
    }

    if (rippleProgress > 0) {
      final maxRadius = size.width * 0.6;
      final radius = maxRadius * Curves.easeOut.transform(rippleProgress);
      final alpha = (1.0 - rippleProgress * 0.8).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: alpha * 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(_SwipeRipplePainter old) =>
      rippleProgress != old.rippleProgress ||
      reachRatio != old.reachRatio ||
      swipeOffset != old.swipeOffset ||
      color != old.color;
}

/// AyuGram dialogs_layout.cpp:990-998: DrawQuickAction twoLines=false (default).
/// Single-line label, 13px semibold, auto-shrinks to 5px minimum.
class _SwipeLabel extends StatelessWidget {
  final String text;
  const _SwipeLabel({required this.text});

  static const _baseSize = 13.0;
  static const _minSize = 5.0;
  static const _baseStyle = TextStyle(
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var fontSize = _baseSize;
        final tp = TextPainter(
          text: TextSpan(text: text, style: _baseStyle.copyWith(fontSize: fontSize)),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        while ((tp.didExceedMaxLines || tp.height > constraints.maxHeight) &&
            fontSize > _minSize) {
          fontSize = (fontSize - 1.0).clamp(_minSize, _baseSize);
          tp.text = TextSpan(text: text, style: _baseStyle.copyWith(fontSize: fontSize));
          tp.layout(maxWidth: constraints.maxWidth);
        }
        tp.dispose();
        return Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _baseStyle.copyWith(fontSize: fontSize),
          ),
        );
      },
    );
  }
}

/// Circular avatar with fallback color + initials + online dot + stories ring.
/// Spec §2: stories ring has two geometry modes:
///   full/expanded: photo 42px, unread line 2px, read line 1px
///   small/minified (sidebar collapsed): photo 21px, unread line 1.5px, read line not drawn
class _ChatAvatar extends StatelessWidget {
  final ChatInfo chat;
  final double size;
  final bool isOnline;
  final bool isActive;
  final bool minified;
  final VoidCallback? onStoryTap;

  const _ChatAvatar({
    required this.chat,
    required this.size,
    this.isOnline = false,
    this.isActive = false,
    this.minified = false,
    this.onStoryTap,
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

  bool get _isSavedMessages => chat.isSelf;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
    final color = palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
    final initials = _initials(chat.title);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final storyPhotoSize = minified ? _storyPhotoSizeSmall : _storyPhotoSizeFull;
    final photoSize = _hasStories ? storyPhotoSize : size;

    // §25.15.4: dynamic avatar corner radius from AyuGram prefs.
    final avatarCorner = context.select((AppState s) => s.avatarCorners);
    final avatarRadius = photoSize / 2 * (avatarCorner / 23.0);

    final Widget avatar;
    if (_isSavedMessages) {
      avatar = SavedMessagesUserpic(size: photoSize, borderRadius: avatarRadius);
    } else if (chat.isReplies) {
      avatar = _RepliesMessagesUserpic(size: photoSize, borderRadius: avatarRadius);
    } else if (chat.isHiddenAuthor) {
      avatar = _HiddenAuthorUserpic(size: photoSize, borderRadius: avatarRadius);
    } else if (chat.avatarPath.isNotEmpty) {
      avatar = ClipRRect(
            borderRadius: BorderRadius.circular(avatarRadius),
            child: Image.file(
              File(chat.avatarPath),
              width: photoSize,
              height: photoSize,
              cacheWidth: (photoSize * 2).toInt(),
              cacheHeight: (photoSize * 2).toInt(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(color, initials, photoSize, avatarRadius),
            ),
          );
    } else {
      avatar = _fallback(color, initials, photoSize, avatarRadius);
    }

    // No stories, no online dot — simple case.
    if (!_hasStories && !isOnline) {
      return SizedBox(width: size, height: size, child: avatar);
    }

    return GestureDetector(
      onTap: _hasStories ? onStoryTap : null,
      child: SizedBox(
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
            if (!_hasStories)
              Positioned(
                right: -3,
                bottom: -3,
                child: AnimatedOpacity(
                  opacity: isOnline ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isActive
                        ? palette.dialogsOnlineBadgeFgActive
                        : palette.dialogsOnlineBadgeFg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive
                          ? palette.dialogsBgActive
                          : palette.dialogsBg,
                      width: 3,
                    ),
                  ),
                ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(Color color, String initials, double photoSize, double borderRadius) {
    return Container(
      width: photoSize,
      height: photoSize,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
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

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
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
  final String action;
  final Color color;

  const _TypingDotsIndicator({required this.userName, this.action = 'typing', required this.color});

  static String _actionLabel(String action) {
    switch (action) {
      case 'record_video':
        return 'recording video';
      case 'upload_video':
        return 'sending video';
      case 'record_audio':
        return 'recording voice';
      case 'upload_audio':
        return 'sending audio';
      case 'upload_photo':
        return 'sending photo';
      case 'upload_document':
        return 'sending file';
      case 'geo_location':
        return 'sending location';
      case 'choose_contact':
        return 'sending contact';
      case 'game_play':
        return 'playing game';
      case 'record_round':
        return 'recording video message';
      case 'upload_round':
        return 'sending video message';
      case 'choose_sticker':
        return 'choosing sticker';
      default:
        return 'typing';
    }
  }

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

  static bool _isRecordAction(String action) =>
      action == 'record_video' || action == 'record_audio' || action == 'record_round';

  static bool _isUploadAction(String action) =>
      action == 'upload_video' || action == 'upload_audio' ||
      action == 'upload_photo' || action == 'upload_document' || action == 'upload_round';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '${widget.userName} ${_TypingDotsIndicator._actionLabel(widget.action)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: widget.color,
            ),
          ),
        ),
        const SizedBox(width: 3),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            if (_isRecordAction(widget.action)) {
              return _buildRecordAnimation();
            } else if (_isUploadAction(widget.action)) {
              return _buildUploadAnimation();
            } else if (widget.action == 'choose_sticker') {
              return _buildStickerAnimation();
            }
            return _buildTypingDots();
          },
        ),
      ],
    );
  }

  Widget _buildTypingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
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
  }

  Widget _buildRecordAnimation() {
    return SizedBox(
      width: 14,
      height: 14,
      child: CustomPaint(
        painter: _RecordWaveformPainter(
          progress: _controller.value,
          color: widget.color,
        ),
      ),
    );
  }

  Widget _buildUploadAnimation() {
    return SizedBox(
      width: 14,
      height: 14,
      child: CustomPaint(
        painter: _UploadArrowPainter(
          progress: _controller.value,
          color: widget.color,
        ),
      ),
    );
  }

  Widget _buildStickerAnimation() {
    final scale = 0.8 + 0.2 * math.sin(_controller.value * 2 * math.pi);
    return Transform.scale(
      scale: scale,
      child: Icon(Icons.sticky_note_2_outlined, size: 14, color: widget.color),
    );
  }
}

class _RecordWaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RecordWaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const bars = 4;
    final barWidth = size.width / (bars * 2 - 1);
    for (int i = 0; i < bars; i++) {
      final phase = (progress + i / bars) * 2 * math.pi;
      final h = size.height * (0.3 + 0.7 * math.max(0, math.sin(phase)));
      final x = i * barWidth * 2 + barWidth / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RecordWaveformPainter old) => progress != old.progress;
}

class _UploadArrowPainter extends CustomPainter {
  final double progress;
  final Color color;
  _UploadArrowPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final cy = size.height * (1.0 - progress);
    final cx = size.width / 2;
    canvas.drawLine(Offset(cx, size.height), Offset(cx, cy), paint);
    canvas.drawLine(Offset(cx - 3, cy + 3), Offset(cx, cy), paint);
    canvas.drawLine(Offset(cx + 3, cy + 3), Offset(cx, cy), paint);
  }

  @override
  bool shouldRepaint(_UploadArrowPainter old) => progress != old.progress;
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

class _SendStateIcon extends StatelessWidget {
  final MsgStatus status;
  final bool isActive;
  final bool isClosed;

  const _SendStateIcon({
    required this.status,
    required this.isActive,
    this.isClosed = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // AyuGram dialogs_layout.cpp:769-774: closed topic → lock icon in send-state position.
    if (isClosed) {
      final lockColor = isActive ? palette.dialogsTextFgActive : palette.dialogsSentIconFg;
      return SizedBox(
        width: 20,
        height: 11,
        child: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(Icons.lock, size: 13, color: lockColor),
        ),
      );
    }

    if (status == MsgStatus.unknown) return const SizedBox(width: 20);

    final Color iconColor;
    if (isActive) {
      iconColor = palette.dialogsTextFgActive;
    } else if (status == MsgStatus.sending) {
      iconColor = palette.dialogsSendingIconFg;
    } else {
      iconColor = palette.dialogsSentIconFg;
    }

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

/// Returns true if [chat] is the Saved Messages self-chat.
/// AyuGram dialogs_layout.cpp:1115-1118: uses peer->isSelf().
bool isSavedMessages(ChatInfo chat) => chat.isSelf;

/// Saved Messages bookmark icon userpic (spec §31.1).
/// Blue vertical-gradient circle with white bookmark silhouette.
/// Replaces the normal avatar for the self-chat.
class SavedMessagesUserpic extends StatelessWidget {
  final double size;
  final double borderRadius;

  const SavedMessagesUserpic({super.key, required this.size, this.borderRadius = -1});

  @override
  Widget build(BuildContext context) {
    final r = borderRadius < 0 ? size / 2 : borderRadius;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: const _SavedMessagesIconPainter(),
        ),
      ),
    );
  }
}

class _SavedMessagesIconPainter extends CustomPainter {
  const _SavedMessagesIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final radius = s / 2;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5caffa), Color(0xFF408acf)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, bgPaint);

    final stroke = s * 0.055;
    final halfStroke = stroke / 2;
    final halfW = (s * 0.15).roundToDouble();
    final halfH = (s * 0.19).roundToDouble();
    final bookWidth = halfW * 2 + (s.round() % 2 == 0 ? 0.0 : 1.0);
    final bookHeight = halfH * 2 + (s.round() % 2 == 0 ? 0.0 : 1.0);
    final notch = (s * 0.064).roundToDouble();

    final left = (s - bookWidth) / 2;
    final top = (s - bookHeight) / 2;
    final right = left + bookWidth;
    final bottom = top + bookHeight;
    final cx = s / 2;

    final iconPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final uPath = Path()
      ..moveTo(left, bottom)
      ..lineTo(left, top + halfStroke)
      ..lineTo(right, top + halfStroke)
      ..lineTo(right, bottom);
    iconPaint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(uPath, iconPaint);

    final vPath = Path()
      ..moveTo(left, bottom)
      ..lineTo(cx, bottom - notch)
      ..lineTo(right, bottom);
    iconPaint.strokeJoin = StrokeJoin.miter;
    canvas.drawPath(vPath, iconPaint);
  }

  @override
  bool shouldRepaint(_SavedMessagesIconPainter oldDelegate) => false;
}

class MyNotesUserpic extends StatelessWidget {
  final double size;
  final double borderRadius;

  const MyNotesUserpic({super.key, required this.size, this.borderRadius = -1});

  @override
  Widget build(BuildContext context) {
    final r = borderRadius < 0 ? size / 2 : borderRadius;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: const _MyNotesIconPainter(),
        ),
      ),
    );
  }
}

class _MyNotesIconPainter extends CustomPainter {
  const _MyNotesIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final radius = s / 2;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5caffa), Color(0xFF408acf)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, bgPaint);

    // Notepad/document icon — matches Telegram's dialogsMyNotesUserpic asset
    final iconPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = s * 0.36;
    final h = s * 0.42;
    final left = (s - w) / 2;
    final top = (s - h) / 2;
    final right = left + w;
    final bottom = top + h;
    final fold = s * 0.10;
    final lineGap = h * 0.22;

    // Page outline with folded corner
    final page = Path()
      ..moveTo(left, top)
      ..lineTo(right - fold, top)
      ..lineTo(right, top + fold)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..close();
    canvas.drawPath(page, iconPaint);

    // Fold line
    final foldPath = Path()
      ..moveTo(right - fold, top)
      ..lineTo(right - fold, top + fold)
      ..lineTo(right, top + fold);
    canvas.drawPath(foldPath, iconPaint);

    // Text lines
    final lineLeft = left + w * 0.18;
    final lineRight = right - w * 0.18;
    final lineY1 = top + fold + lineGap;
    final lineY2 = lineY1 + lineGap;
    final linePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.04
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(lineLeft, lineY1), Offset(lineRight, lineY1), linePaint);
    canvas.drawLine(Offset(lineLeft, lineY2), Offset(lineRight * 0.85, lineY2), linePaint);
  }

  @override
  bool shouldRepaint(_MyNotesIconPainter oldDelegate) => false;
}

/// AyuGram dialogs_layout.cpp:470-476: PaintRepliesMessages userpic.
/// Purple gradient circle with a double-arrow (reply) icon.
class _RepliesMessagesUserpic extends StatelessWidget {
  final double size;
  final double borderRadius;

  const _RepliesMessagesUserpic({required this.size, this.borderRadius = -1});

  @override
  Widget build(BuildContext context) {
    final r = borderRadius < 0 ? size / 2 : borderRadius;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: const _RepliesIconPainter(),
        ),
      ),
    );
  }
}

class _RepliesIconPainter extends CustomPainter {
  const _RepliesIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final radius = s / 2;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5EB5F7), Color(0xFF3E97DE)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    final iconPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final arrowSize = s * 0.16;
    final cx = s / 2;
    final cy = s / 2;

    // Left arrow (reply arrow)
    final leftX = cx - s * 0.08;
    canvas.drawLine(Offset(leftX - arrowSize, cy - s * 0.06),
        Offset(leftX, cy - s * 0.06 - arrowSize * 0.7), iconPaint);
    canvas.drawLine(Offset(leftX - arrowSize, cy - s * 0.06),
        Offset(leftX, cy - s * 0.06 + arrowSize * 0.7), iconPaint);
    final bodyPath = Path()
      ..moveTo(leftX - arrowSize, cy - s * 0.06)
      ..lineTo(leftX + s * 0.12, cy - s * 0.06)
      ..quadraticBezierTo(leftX + s * 0.2, cy - s * 0.06, leftX + s * 0.2, cy + s * 0.04)
      ..lineTo(leftX + s * 0.2, cy + s * 0.12);
    canvas.drawPath(bodyPath, iconPaint);
  }

  @override
  bool shouldRepaint(_RepliesIconPainter oldDelegate) => false;
}

/// AyuGram dialogs_layout.cpp:477-483: PaintHiddenAuthor userpic.
/// Blue gradient circle with anonymous/ghost silhouette.
class _HiddenAuthorUserpic extends StatelessWidget {
  final double size;
  final double borderRadius;

  const _HiddenAuthorUserpic({required this.size, this.borderRadius = -1});

  @override
  Widget build(BuildContext context) {
    final r = borderRadius < 0 ? size / 2 : borderRadius;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: const _HiddenAuthorIconPainter(),
        ),
      ),
    );
  }
}

class _HiddenAuthorIconPainter extends CustomPainter {
  const _HiddenAuthorIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final radius = s / 2;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF72B1DF), Color(0xFF5091C2)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    // Question mark silhouette
    final iconPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.06
      ..strokeCap = StrokeCap.round;

    final cx = s / 2;
    final topY = s * 0.30;
    final arcRadius = s * 0.12;
    final arcRect = Rect.fromCenter(
      center: Offset(cx, topY + arcRadius),
      width: arcRadius * 2,
      height: arcRadius * 2,
    );
    canvas.drawArc(arcRect, -math.pi, math.pi * 0.8, false, iconPaint);
    canvas.drawLine(
      Offset(cx + arcRadius * 0.6, topY + arcRadius + arcRadius * 0.6),
      Offset(cx, topY + arcRadius * 2 + s * 0.06),
      iconPaint,
    );

    // Dot below
    final dotPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(cx, s * 0.72),
      s * 0.035,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(_HiddenAuthorIconPainter oldDelegate) => false;
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

/// §22.4: Forum group row in chat list — expanded 80px with topic names.
class ForumChatListRow extends StatelessWidget {
  final ChatInfo chat;
  final bool isActive;
  final bool isNarrow;
  final List<ForumTopic> recentTopics;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onSecondaryTap;
  final VoidCallback? onStoryTap;
  final ValueChanged<ForumTopic>? onTopicTap;
  final bool isForwardHovered;

  const ForumChatListRow({
    super.key,
    required this.chat,
    required this.isActive,
    this.isNarrow = false,
    required this.recentTopics,
    required this.onTap,
    this.onSecondaryTap,
    this.onStoryTap,
    this.onTopicTap,
    this.isForwardHovered = false,
  });

  static const _rowHeight = 80.0;
  static const _avatarSize = 46.0;
  static const _avatarLeft = 10.0;
  static const _contentLeft = 68.0;
  static const _paddingRight = 10.0;
  static const _topicsHeight = 21.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // AyuGram dialogs.style:114-117: taggedForumDialogRow applies when row has
    // active folder filter tags, not based on parentId. Not yet supported.
    const effectiveHeight = _rowHeight;

    final nameColor = isActive ? palette.dialogsNameFgActive : palette.dialogsNameFg;
    final mutedColor = isActive ? palette.dialogsTextFgActive : palette.dialogsTextFg;

    final Color? rowBg;
    if (isForwardHovered) {
      rowBg = Color.lerp(palette.dialogsBg, palette.dialogsBgActive, 0.15);
    } else if (isActive) {
      rowBg = palette.dialogsBgActive;
    } else {
      rowBg = palette.dialogsBg;
    }

    if (isNarrow) {
      final badgeBg = isActive
          ? (chat.isMuted ? palette.dialogsUnreadBgMutedActive : palette.dialogsUnreadBgActive)
          : (chat.isMuted ? palette.dialogsUnreadBgMuted : palette.dialogsUnreadBg);
      final badgeText = isActive ? palette.dialogsUnreadFgActive : palette.dialogsUnreadFg;
      return Container(
        color: rowBg,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: effectiveHeight,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _ChatAvatar(
                      chat: chat,
                      size: _avatarSize,
                      isOnline: false,
                      minified: true,
                      onStoryTap: onStoryTap,
                    ),
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
            ),
          ),
        ),
      );
    }

    final unreadFrontTopic = _findUnreadFrontTopic();

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
              : palette.dialogsBgOver,
          splashColor: isActive
              ? palette.dialogsRippleBgActive
              : palette.dialogsRippleBg,
          child: SizedBox(
            height: effectiveHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: _avatarLeft, right: _paddingRight),
              child: Row(
                children: [
                  _ChatAvatar(
                    chat: chat,
                    size: _avatarSize,
                    isOnline: false,
                    onStoryTap: onStoryTap,
                  ),
                  const SizedBox(width: _contentLeft - _avatarLeft - _avatarSize),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.forum, size: 16, color: mutedColor),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                chat.title.isNotEmpty ? chat.title : chat.chatId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: nameColor,
                                ),
                              ),
                            ),
                            if (chat.isMuted) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.volume_off, size: 14, color: mutedColor),
                            ],
                            const SizedBox(width: 5),
                            Text(
                              formatChatListTime(chat.lastMsgTime),
                              style: TextStyle(
                                fontSize: 13,
                                color: isActive ? palette.dialogsTextFgActive : palette.dialogsDateFg,
                              ),
                            ),
                            if (chat.unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              _UnreadBadge(
                                count: chat.unreadCount,
                                bgColor: isActive
                                    ? (chat.isMuted ? palette.dialogsUnreadBgMutedActive : palette.dialogsUnreadBgActive)
                                    : (chat.isMuted ? palette.dialogsUnreadBgMuted : palette.dialogsUnreadBg),
                                textColor: isActive ? palette.dialogsUnreadFgActive : palette.dialogsUnreadFg,
                              ),
                            ] else if (chat.isUnreadMark) ...[
                              const SizedBox(width: 8),
                              _UnreadDot(bgColor: isActive
                                  ? (chat.isMuted ? palette.dialogsUnreadBgMutedActive : palette.dialogsUnreadBgActive)
                                  : (chat.isMuted ? palette.dialogsUnreadBgMuted : palette.dialogsUnreadBg)),
                            ] else if (chat.isPinned) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.push_pin, size: 14, color: mutedColor),
                            ],
                            if (chat.unreadMentionCount > 0) ...[
                              const SizedBox(width: 5),
                              _ThreeStateBadgeIcon(
                                icon: Icons.alternate_email,
                                color: isActive
                                    ? (chat.isMuted ? palette.dialogsUnreadBgMutedActive : palette.dialogsUnreadBgActive)
                                    : (chat.isMuted ? palette.dialogsUnreadBgMuted : palette.dialogsUnreadBg),
                                isNarrow: false,
                              ),
                            ],
                            if (chat.unreadReactionCount > 0) ...[
                              const SizedBox(width: 5),
                              _ThreeStateBadgeIcon(
                                icon: Icons.favorite,
                                color: isActive
                                    ? (chat.isMuted ? palette.dialogsUnreadBgMutedActive : palette.dialogsUnreadBgActive)
                                    : (chat.isMuted ? palette.dialogsUnreadBgMuted : palette.dialogsUnreadBg),
                                isNarrow: false,
                              ),
                            ],
                            if (chat.unreadPollCount > 0) ...[
                              const SizedBox(width: 5),
                              _ThreeStateBadgeIcon(
                                icon: Icons.poll,
                                color: isActive
                                    ? (chat.isMuted ? palette.dialogsUnreadBgMutedActive : palette.dialogsUnreadBgActive)
                                    : (chat.isMuted ? palette.dialogsUnreadBgMuted : palette.dialogsUnreadBg),
                                isNarrow: false,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: _topicsHeight,
                          child: _TopicsPreview(
                            topics: recentTopics,
                            isActive: isActive,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (unreadFrontTopic != null)
                          _TopicJumpBubble(
                            topic: unreadFrontTopic,
                            isActive: isActive,
                            onTap: onTopicTap != null ? () => onTopicTap!(unreadFrontTopic) : null,
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

  ForumTopic? _findUnreadFrontTopic() {
    for (final t in recentTopics) {
      if (t.unreadCount > 0) return t;
    }
    return null;
  }

}

/// §22.4: Horizontal row of up to 8 recent topic names. Unread topics bold.
/// AyuGram dialogs_topics_view.cpp:221-239: per-topic spacing with topicsSkip=8px.
class _TopicsPreview extends StatelessWidget {
  final List<ForumTopic> topics;
  final bool isActive;

  const _TopicsPreview({
    required this.topics,
    required this.isActive,
  });

  static const _topicsSkip = 8.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (topics.isEmpty) {
      return const SizedBox.shrink();
    }

    final children = <InlineSpan>[];
    for (var i = 0; i < topics.length; i++) {
      final topic = topics[i];
      final hasUnread = topic.unreadCount > 0;
      if (i > 0) {
        children.add(const WidgetSpan(child: SizedBox(width: _topicsSkip)));
      }
      children.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: topic.isGeneral
            ? const GeneralForumTopicIcon(size: ForumTopicIcon.defaultSize)
            : ForumTopicIcon(
                colorId: topic.colorId,
                title: topic.title,
                size: ForumTopicIcon.defaultSize,
              ),
      ));
      children.add(const WidgetSpan(child: SizedBox(width: 3)));
      children.add(TextSpan(
        text: topic.isGeneral ? '# ${topic.title}' : topic.title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
          color: isActive
              ? palette.dialogsTextFgActive
              : (hasUnread ? palette.dialogsNameFg : palette.dialogsTextFg),
        ),
      ));
    }
    return Text.rich(
      TextSpan(children: children),
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }
}

/// §22.4: Topic jump bubble — two-area rounded bubble for unread front topic.
/// AyuGram dialogs_topics_view.cpp:323-370: area1 (topic icon+title) + area2 (arrow).
class _TopicJumpBubble extends StatelessWidget {
  final ForumTopic topic;
  final bool isActive;
  final VoidCallback? onTap;

  const _TopicJumpBubble({required this.topic, required this.isActive, this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = isActive
        ? palette.dialogsUnreadBgActive
        : palette.dialogsUnreadBg;
    final fg = isActive
        ? palette.dialogsUnreadFgActive
        : palette.dialogsUnreadFg;
    final bgDimmed = isActive
        ? palette.dialogsUnreadBgActive.withValues(alpha: 0.8)
        : palette.dialogsUnreadBg.withValues(alpha: 0.8);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
              color: bg,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: topic.isGeneral
                        ? const GeneralForumTopicIcon(size: 14)
                        : ForumTopicIcon(
                            colorId: topic.colorId,
                            title: topic.title,
                            size: 14,
                          ),
                  ),
                  const SizedBox(width: 3),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      topic.title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
              color: bgDimmed,
              child: Icon(Icons.keyboard_arrow_right, size: 14, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
