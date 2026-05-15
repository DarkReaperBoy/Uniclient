import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart' show Clipboard, ClipboardData, KeyDownEvent, LogicalKeyboardKey;

import 'custom_emoji_cache.dart';
import 'gesture_utils.dart';
import 'info_panel.dart';
import 'instant_view.dart';
import 'reactions_detail.dart';
import 'popup_menu.dart';
import 'shell.dart';
import 'spoiler_animation.dart';
import 'telegram_toast.dart';
import 'telegram_tooltip.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';
import '../state/audio_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import 'chat_view.dart' show ChatThemeOverride, ChatView;
import 'input_dialogs.dart' show showCreatePollBox, CreatePollResult;
import 'forum_topic_icon.dart';
import 'media_viewer.dart';
import 'sticker_pack_viewer.dart';
import 'payment_panel.dart';
import 'web_app_panel.dart';

Uint8List _gzipDecode(Uint8List data) => Uint8List.fromList(gzip.decode(data));

/// Spec §5: bubble shape with decorative tail on the last message in a group.
/// The tail is a curved triangular protrusion at the bottom sender-side corner:
/// bottom-right for outgoing, bottom-left for incoming.
class _BubbleTailBorder extends ShapeBorder {
  final double topLeftRadius;
  final double topRightRadius;
  final double bottomOtherRadius;
  final bool tailOnRight;

  const _BubbleTailBorder({
    required this.topLeftRadius,
    required this.topRightRadius,
    required this.bottomOtherRadius,
    required this.tailOnRight,
  });

  static const _tailW = 8.0;
  static const _tailDrop = 5.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path();
    final l = rect.left;
    final t = rect.top;
    final r = rect.right;
    final b = rect.bottom;

    path.moveTo(l + topLeftRadius, t);
    path.lineTo(r - topRightRadius, t);

    if (topRightRadius > 0) {
      path.arcToPoint(Offset(r, t + topRightRadius),
          radius: Radius.circular(topRightRadius));
    } else {
      path.lineTo(r, t);
    }

    if (tailOnRight) {
      path.lineTo(r, b);
      path.cubicTo(r, b + 2, r + _tailW * 0.4, b + _tailDrop,
          r + _tailW, b + _tailDrop);
      path.cubicTo(r + _tailW * 0.5, b + _tailDrop * 0.6, r, b,
          r - _tailW * 0.75, b);
      path.lineTo(l + bottomOtherRadius, b);
      if (bottomOtherRadius > 0) {
        path.arcToPoint(Offset(l, b - bottomOtherRadius),
            radius: Radius.circular(bottomOtherRadius));
      } else {
        path.lineTo(l, b);
      }
    } else {
      path.lineTo(r, b - bottomOtherRadius);
      if (bottomOtherRadius > 0) {
        path.arcToPoint(Offset(r - bottomOtherRadius, b),
            radius: Radius.circular(bottomOtherRadius));
      } else {
        path.lineTo(r, b);
      }
      path.lineTo(l + _tailW * 0.75, b);
      path.cubicTo(l, b, l - _tailW * 0.5, b + _tailDrop * 0.6,
          l - _tailW, b + _tailDrop);
      path.cubicTo(l - _tailW * 0.4, b + _tailDrop, l, b + 2, l, b);
    }

    path.lineTo(l, t + topLeftRadius);
    if (topLeftRadius > 0) {
      path.arcToPoint(Offset(l + topLeftRadius, t),
          radius: Radius.circular(topLeftRadius));
    }

    path.close();
    return path;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

/// Single message bubble. Spec §5: max 430px, 16/6px radius, sender colors.
class MessageBubble extends StatefulWidget {
  final CachedMessage message;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool isGroupChat;
  final String? senderAvatarB64;
  final VoidCallback? onReply;
  final void Function(Offset position, String selectedText)? onContextMenu;
  final ValueChanged<String>? onSenderTap;
  final void Function(String senderId, Offset position)? onSenderContextMenu;
  final ValueChanged<String>? onReplyTap;
  final bool isSelected;
  final bool inSelectionMode;
  final List<CachedMessage> allMessages;
  final List<CachedMessage> albumItems;
  final bool isScheduledView;

  const MessageBubble({
    super.key,
    required this.message,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.isGroupChat = false,
    this.isSelected = false,
    this.inSelectionMode = false,
    this.allMessages = const [],
    this.albumItems = const [],
    this.isScheduledView = false,
    this.senderAvatarB64,
    this.onReply,
    this.onContextMenu,
    this.onSenderTap,
    this.onSenderContextMenu,
    this.onReplyTap,
  });

  static void loadPeerColors(List<PeerColorEntry> entries) {
    _MessageBubbleState.loadPeerColors(entries);
  }

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovered = false;
  Timer? _showTimer;
  Timer? _hideTimer;

  static final Map<String, List<String>> _cachedReactions = {};
  static final Map<String, bool> _loadingReactions = {};

  List<String> get _availableReactions {
    final accountId = context.read<AppState>().activeAccountId;
    return _cachedReactions[accountId] ?? const ['👍', '❤️', '🔥', '🥰', '👏', '😱', '😢', '🎉'];
  }

  void _ensureReactionsLoaded() {
    final accountId = context.read<AppState>().activeAccountId;
    if (accountId.isEmpty) return;
    if (_cachedReactions.containsKey(accountId)) return;
    if (_loadingReactions[accountId] == true) return;
    _loadingReactions[accountId] = true;
    final engine = context.read<EngineService>();
    engine.getAvailableReactions(accountId).then((reactions) {
      if (reactions.isNotEmpty) {
        _cachedReactions[accountId] = reactions;
      }
      _loadingReactions[accountId] = false;
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onHoverEnter() {
    if (widget.inSelectionMode) return;
    _ensureReactionsLoaded();
    _hideTimer?.cancel();
    _showTimer?.cancel();
    _showTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _hovered = true);
    });
  }

  void _onHoverExit() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _hovered = false);
    });
  }

  void _onReactionTap(String emoji) {
    setState(() => _hovered = false);
    final appState = context.read<AppState>();
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    final chatId = chatState.activeChat?.chatId ?? '';
    if (accountId.isEmpty || chatId.isEmpty) return;
    engine.reactToMessage(accountId, chatId, widget.message.msgId, emoji);
  }

  final GlobalKey _stripKey = GlobalKey();
  final Map<String, GlobalKey> _reactionKeys = {};

  void _onExpandReactions() {
    final renderBox =
        _stripKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final stripPos = renderBox.localToGlobal(Offset.zero);
    final stripSize = renderBox.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (ctx) {
      return _ReactionEmojiOverlay(
        stripOffset: stripPos,
        stripSize: stripSize,
        isDark: isDark,
        availableReactions: _availableReactions,
        onPick: (emoji) {
          entry.remove();
          _onReactionTap(emoji);
        },
        onDismiss: () => entry.remove(),
      );
    });
    overlay.insert(entry);
  }

  MessageReaction? _findHitReaction(Offset globalPos) {
    for (final r in widget.message.reactions) {
      final key = _reactionKeys[r.isCustomEmoji ? 'custom_${r.documentId}' : r.emoji];
      if (key == null) continue;
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final local = box.globalToLocal(globalPos);
      if (box.paintBounds.contains(local)) return r;
    }
    return null;
  }

  void _showWhoReactedMenu(Offset globalPosition, MessageReaction reaction) async {
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat != null && chat.title == 'Saved Messages' && chat.type == ChatType.dm) {
      _showTagMenu(globalPosition, reaction);
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    );

    final engine = context.read<EngineService>();
    final message = widget.message;
    final msgIdInt = int.tryParse(message.msgId) ?? 0;
    if (msgIdInt == 0) return;

    final reactorsResult = await engine.getMessageReactorsList(
      message.accountId, message.chatId, msgIdInt,
      limit: 20,
    );
    if (!mounted) return;

    final filtered = reactorsResult.reactors.where((r) => r.emoji == reaction.emoji).toList();
    final reactorsByPeerId = <String, ReactorInfo>{};
    for (final r in filtered) {
      reactorsByPeerId[r.peerId] = r;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = PaletteProvider.of(context).windowSubTextFg;

    final items = <PopupMenuEntry<String>>[];

    if (filtered.isEmpty && reaction.count > 0) {
      items.add(PopupMenuItem<String>(
        enabled: false,
        height: 40,
        child: Row(
          children: [
            Text(reaction.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text(
              '${reaction.count} reacted',
              style: TextStyle(fontSize: 13, color: subColor),
            ),
          ],
        ),
      ));
    } else {
      final showSec = context.read<AppState>().showMessageSeconds;
      for (final reactor in filtered) {
        final hasDate = reactor.date > 0;
        items.add(PopupMenuItem<String>(
          value: reactor.peerId,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              _ReactorAvatar(name: reactor.peerName, size: 30, avatarB64: reactor.avatarB64),
              const SizedBox(width: 14),
              Expanded(
                child: hasDate
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reactor.peerName.isNotEmpty ? reactor.peerName : 'User',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Icon(Icons.favorite, size: 12, color: subColor),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                formatReadDateLocal(reactor.date, showSeconds: showSec),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(fontSize: 12, color: subColor),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Text(
                      reactor.peerName.isNotEmpty ? reactor.peerName : 'User',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
              ),
            ],
          ),
        ));
      }
    }

    if (reaction.count > filtered.length && filtered.isNotEmpty) {
      items.add(const PopupMenuDivider(height: 1));
      items.add(PopupMenuItem<String>(
        value: '__show_all',
        height: 36,
        child: Center(
          child: Text(
            'Show all reactions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ));
    }

    if (items.isEmpty) return;

    final result = await showMenu<String>(
      context: context,
      position: position,
      items: items,
    );

    if (!mounted || result == null) return;
    if (result == '__show_all') {
      ReactionsDetailPanel.show(context, widget.message, initialEmoji: reaction.emoji);
    } else {
      final reactor = reactorsByPeerId[result];
      if (reactor != null && reactor.peerId.isNotEmpty) {
        _navigateToUserProfile(reactor.peerId, reactor.peerName);
      }
    }
  }

  void _navigateToUserProfile(String peerId, String peerName) {
    final member = MemberInfo(
      userId: peerId,
      displayName: peerName,
    );
    if (InfoPanel.pushUserProfileRequest != null) {
      InfoPanel.pushUserProfileRequest!(member);
    } else {
      UniClientShell.toggleInfoRequest?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        InfoPanel.pushUserProfileRequest?.call(member);
      });
    }
  }

  void _showTagMenu(Offset globalPosition, MessageReaction reaction) {
    final chatState = context.read<ChatState>();
    final tags = chatState.savedReactionTags;
    final matchingTag = tags.cast<SavedReactionTagInfo?>().firstWhere(
      (t) => t!.emoji == reaction.emoji,
      orElse: () => null,
    );
    final hasTitle = matchingTag?.title.isNotEmpty ?? false;

    showTelegramMenu<String>(
      context: context,
      position: globalPosition,
      items: [
        TelegramMenuItem(
          value: 'filter',
          label: 'Filter by tag',
          icon: const Icon(Icons.filter_alt_outlined, size: 20),
        ),
        TelegramMenuItem(
          value: 'edit',
          label: hasTitle ? 'Edit tag name' : 'Add tag name',
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        TelegramMenuItem(
          value: 'remove',
          label: 'Remove tag',
          icon: const Icon(Icons.close, size: 20),
          isAttention: true,
        ),
      ],
    ).then((action) {
      if (!mounted) return;
      if (action == 'filter') {
        final tag = matchingTag ?? SavedReactionTagInfo(emoji: reaction.emoji);
        chatState.toggleReactionTag(tag);
      } else if (action == 'edit') {
        final tag = matchingTag ?? SavedReactionTagInfo(emoji: reaction.emoji);
        _showEditTagNameDialog(tag);
      } else if (action == 'remove') {
        final engine = context.read<EngineService>();
        final appState = context.read<AppState>();
        engine.reactToMessage(
          appState.activeAccountId,
          widget.message.chatId,
          widget.message.msgId,
          reaction.emoji,
        );
      }
    });
  }

  void _showEditTagNameDialog(SavedReactionTagInfo tag) {
    final controller = TextEditingController(text: tag.title);
    final hasTitle = tag.title.isNotEmpty;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(hasTitle ? 'Edit tag name' : 'Add tag name'),
          content: Row(
            children: [
              if (!tag.isCustomEmoji)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(tag.emoji, style: const TextStyle(fontSize: 28)),
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Tag name',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 12,
                  onSubmitted: (text) {
                    final chatState = context.read<ChatState>();
                    chatState.renameSavedReactionTag(
                      emoji: tag.emoji,
                      customId: tag.customId,
                      title: text.trim(),
                    );
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final chatState = context.read<ChatState>();
                chatState.renameSavedReactionTag(
                  emoji: tag.emoji,
                  customId: tag.customId,
                  title: controller.text.trim(),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  static const _baseMaxWidth = 430.0;
  static const _radiusLarge = 16.0;
  static const _radiusSmall = 6.0;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isFirstInGroup = widget.isFirstInGroup;
    final isLastInGroup = widget.isLastInGroup;
    final isGroupChat = widget.isGroupChat;
    final isSelected = widget.isSelected;
    final inSelectionMode = widget.inSelectionMode;
    final allMessages = widget.allMessages;
    final albumItems = widget.albumItems;
    final onContextMenu = widget.onContextMenu;
    final onReply = widget.onReply;
    final onSenderTap = widget.onSenderTap;
    final onSenderContextMenu = widget.onSenderContextMenu;
    final onReplyTap = widget.onReplyTap;

    final currentReactionKeys = message.reactions.map((r) => r.isCustomEmoji ? 'custom_${r.documentId}' : r.emoji).toSet();
    _reactionKeys.removeWhere((key, _) => !currentReactionKeys.contains(key));
    for (final r in message.reactions) {
      final key = r.isCustomEmoji ? 'custom_${r.documentId}' : r.emoji;
      _reactionKeys.putIfAbsent(key, () => GlobalKey());
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = context.palette;
    final isOutgoing = message.isOutgoing;
    final wm = context.watch<AppState>().wideMultiplier;
    final _maxWidth = (wm - 1.0).abs() > 0.01
        ? (_baseMaxWidth * wm).roundToDouble().clamp(_baseMaxWidth, _baseMaxWidth * 4)
        : _baseMaxWidth;

    // AyuGram spec: sticker-only messages render without a bubble background.
    // A sticker-only message has no text body, reply, or forward header — only
    // the sticker image. Sender name (group chats, first-in-group) and timestamp
    // still render, but the background capsule and padding are suppressed.
    final isStickerOnly = message.mediaType == 6 &&
        message.contentText.isEmpty &&
        message.replyPreview.isEmpty &&
        message.forwardFrom.isEmpty;

    final isolatedEmoji = _detectIsolatedEmoji(message);
    final isIsolatedEmoji = isolatedEmoji.isIsolated;

    // Spec §5: media-only bubbles (photo/video/gif/videonote without caption)
    // overlay the bottom info on the media with translucent bg + inverted colors.
    // Albums never use overlay mode — info renders in the bubble below the album.
    final isMediaOnlyBubble = albumItems.isEmpty &&
        !isStickerOnly &&
        message.hasMedia &&
        (message.mediaType == 1 || message.mediaType == 2 ||
         message.mediaType == 5 || message.mediaType == 7) &&
        message.contentText.isEmpty;

    // Spec §6: For photos/videos/GIFs with caption text, caption renders BELOW
    // the media (not above). The photo also narrows because it shares the
    // bubble's horizontal padding with the caption text.
    final isCaptionedMedia = message.hasMedia &&
        message.contentText.isNotEmpty &&
        (message.mediaType == 1 || message.mediaType == 2 ||
         message.mediaType == 7);

    final noBubble = isStickerOnly || isIsolatedEmoji;

    // Spec §5: Bottom info floats inline at end of last text line for text bubbles.
    final useFloatingInfo = !isMediaOnlyBubble &&
        !isIsolatedEmoji &&
        !isStickerOnly &&
        message.contentText.isNotEmpty &&
        (isCaptionedMedia ||
         (!message.hasWebPage && !message.hasGame && !message.hasInvoice &&
          !message.hasMedia && albumItems.isEmpty));

    final themeOverride = ChatThemeOverride.of(context);
    final bubbleColor = noBubble
        ? Colors.transparent
        : isOutgoing && themeOverride?.outgoingBubbleColor != null && !isSelected
            ? themeOverride!.outgoingBubbleColor!
            : isOutgoing
                ? (isSelected ? palette.msgOutBgSelected : palette.msgOutBg)
                : (isSelected ? palette.msgInBgSelected : palette.msgInBg);

    // Spec §5: 2px bottom shadow strip. Night theme alpha=00 (disabled).
    final shadowColor = noBubble
        ? Colors.transparent
        : isOutgoing ? palette.msgOutShadow : palette.msgInShadow;

    final alignment = isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    // §25.15: dynamic bubble radius from AyuGram prefs.
    final ayuState = context.watch<AppState>();
    final radiusLarge = ayuState.bubbleRadius.toDouble();
    final radiusSmall = ayuState.removeTail
        ? radiusLarge
        : (radiusLarge * 6 / 16).clamp(0.0, 6.0);

    final showTail = isLastInGroup && !ayuState.removeTail && !noBubble;
    final topSenderSide = isFirstInGroup ? radiusLarge : radiusSmall;
    final topOtherSide = radiusLarge;
    final bottomSenderSide = showTail ? 0.0 : radiusSmall;
    final bottomOtherSide = radiusLarge;

    // Show sender avatar for incoming messages in group chats.
    final showAvatar = isGroupChat && !isOutgoing;

    final deletedOpacity = (ayuState.semiTransparentDeleted && message.isDeleted) ? 0.7 : 1.0;

    final inlineInfoWidget = useFloatingInfo ? Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 6),
        if (message.views > 0) ...[
          SizedBox(width: 20, height: 11,
            child: CustomPaint(painter: _ViewsIconPainter(color: _bottomInfoColor(isOutgoing, palette)))),
          const SizedBox(width: 8),
          Text(_formatCount(message.views),
              style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, palette))),
        ],
        if (message.forwards > 0) ...[
          const SizedBox(width: 8),
          SizedBox(width: 20, height: 11,
            child: CustomPaint(painter: _ForwardsIconPainter(color: _bottomInfoColor(isOutgoing, palette)))),
          const SizedBox(width: 8),
          Text(_formatCount(message.forwards),
              style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, palette))),
        ],
        ..._buildDeletedEditedMarks(
          message: message,
          color: _bottomInfoColor(isOutgoing, palette),
          appState: ayuState,
        ),
        if (widget.isScheduledView && message.isScheduled)
          TelegramTooltip(
            message: _scheduledTooltip(message),
            child: Text(
              _formatScheduledTime(message),
              style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, palette)),
            ),
          )
        else
          Text(
            _buildTimeText(message, ayuState),
            style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, palette)),
          ),
        if (isOutgoing && !widget.isScheduledView)
          SizedBox(
            width: 24,
            height: 11,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _StatusIcon(status: message.status, theme: theme, isOutgoing: true, isDark: isDark),
            ),
          ),
      ],
    ) : null;

    Widget bubble = MouseRegion(
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverExit(),
      child: Padding(
      padding: EdgeInsets.only(
        left: 16.0,
        top: isFirstInGroup ? 6.0 : 0.0,
        right: inSelectionMode ? 86.0 : 56.0,
        bottom: 2.0,
      ),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              // Sender avatar: show on last message of group, invisible spacer otherwise.
              if (showAvatar) ...[
                if (isLastInGroup)
                  _buildSenderAvatar(isDark)
                else
                  const SizedBox(width: 33), // spacer to align with avatar below
                const SizedBox(width: 7),
              ],
          Flexible(
            child: PlatformGestureDetector(
            onLongPressStart: onContextMenu != null
                ? (details) {
                    if (!_SenderNameTapTarget.recentlyConsumed) {
                      final hitReaction = _findHitReaction(details.globalPosition);
                      if (hitReaction != null) {
                        _showWhoReactedMenu(details.globalPosition, hitReaction);
                      } else {
                        onContextMenu!(details.globalPosition, '');
                      }
                    }
                  }
                : null,
            onSecondaryTapUp: onContextMenu != null
                ? (details) {
                    if (!_SenderNameTapTarget.recentlyConsumed) {
                      final hitReaction = _findHitReaction(details.globalPosition);
                      if (hitReaction != null) {
                        _showWhoReactedMenu(details.globalPosition, hitReaction);
                      } else {
                        onContextMenu!(details.globalPosition, '');
                      }
                    }
                  }
                : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: showAvatar ? _maxWidth - 40 : _maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
              if (_hovered && !inSelectionMode)
                Align(
                  alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: isOutgoing ? 20 : 0,
                    ),
                    child: _ReactionStrip(
                      key: _stripKey,
                      onReactionTap: _onReactionTap,
                      onExpandTap: _onExpandReactions,
                      isDark: isDark,
                      reactions: _availableReactions,
                    ),
                  ),
                ),
              Stack(
                clipBehavior: Clip.none,
                children: [
              Container(
                padding: noBubble
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: showTail && !noBubble
                    ? ShapeDecoration(
                        color: bubbleColor,
                        shadows: [
                          BoxShadow(
                            color: shadowColor,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        shape: _BubbleTailBorder(
                          topLeftRadius: isOutgoing ? topOtherSide : topSenderSide,
                          topRightRadius: isOutgoing ? topSenderSide : topOtherSide,
                          bottomOtherRadius: bottomOtherSide,
                          tailOnRight: isOutgoing,
                        ),
                      )
                    : BoxDecoration(
                  color: bubbleColor,
                  borderRadius: noBubble
                      ? BorderRadius.zero
                      : BorderRadius.only(
                          topLeft: Radius.circular(isOutgoing ? topOtherSide : topSenderSide),
                          topRight: Radius.circular(isOutgoing ? topSenderSide : topOtherSide),
                          bottomLeft: Radius.circular(isOutgoing ? bottomOtherSide : bottomSenderSide),
                          bottomRight: Radius.circular(isOutgoing ? bottomSenderSide : bottomOtherSide),
                        ),
                  boxShadow: noBubble
                      ? null
                      : [
                          BoxShadow(
                            color: shadowColor,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender name + admin badge: only on first message of group (in groups, for incoming).
                    if (isGroupChat && !isOutgoing && message.senderName.isNotEmpty && isFirstInGroup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _SenderNameTapTarget(
                          onTap: onSenderTap != null ? () => onSenderTap!(message.senderId) : null,
                          onSecondaryTap: onSenderContextMenu != null
                              ? (pos) => onSenderContextMenu!(message.senderId, pos)
                              : null,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: message.senderName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _senderColor(message.senderId, palette: palette, isDark: isDark, colorId: message.senderColorId),
                                  ),
                                ),
                                if (message.senderRank.isNotEmpty)
                                  TextSpan(
                                    text: ' ${message.senderRank}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: _senderColor(message.senderId, palette: palette, isDark: isDark).withValues(alpha: 0.6),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Topic button (forums): small pill with topic icon + name.
                    if (message.topicId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _TopicButton(
                          topicName: message.topicName.isNotEmpty
                              ? message.topicName
                              : 'Topic #${message.topicId}',
                          topicColorId: message.topicColorId,
                          topicId: message.topicId,
                        ),
                      ),
                    // Via-bot label: "via @botname" — spec §5, shown if no sender name shown and no forward header.
                    if (message.viaBotName.isNotEmpty &&
                        message.forwardFrom.isEmpty &&
                        (isOutgoing || message.senderName.isEmpty || !isFirstInGroup))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'via ',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: palette.msgInDateFg,
                                ),
                              ),
                              TextSpan(
                                text: message.viaBotName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: palette.msgInServiceFg,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Forward header (spec §5: before reply block).
                    if (message.forwardFrom.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          'Forwarded from ${message.forwardFrom}',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                    // Reply preview.
                    if (message.replyPreview.isNotEmpty)
                      _ReplyPreview(
                        preview: message.replyPreview,
                        theme: theme,
                        isOutgoing: isOutgoing,
                        onTap: (onReplyTap != null && message.replyToId.isNotEmpty)
                            ? () => onReplyTap!(message.replyToId)
                            : null,
                      ),
                    // Spec §6: For captioned media (photo/video/GIF + text),
                    // media renders first, caption text below it.
                    // For all other messages, text renders before media.
                    if (isIsolatedEmoji)
                      _LargeIsolatedEmoji(
                        info: isolatedEmoji,
                        accountId: message.accountId,
                      )
                    else if (!isCaptionedMedia && message.contentText.isNotEmpty && message.mediaType != 9 && message.mediaType != 10 && message.mediaType != 11 && message.mediaType != 12)
                      _RichMessageText(
                        text: message.contentText,
                        entitiesJson: message.contentRich,
                        baseStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
                        theme: theme,
                        isOutgoing: isOutgoing,
                        accountId: message.accountId,
                        onContextMenu: onContextMenu,
                        trailingPad: useFloatingInfo && !isCaptionedMedia ? inlineInfoWidget : null,
                      ),
                    if (message.hasWebPage)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _WebPagePreview(
                          message: message,
                          theme: theme,
                          isDark: isDark,
                          isOutgoing: isOutgoing,
                        ),
                      ),
                    if (message.hasGame)
                      _GameCard(
                        message: message,
                        theme: theme,
                        isDark: isDark,
                        isOutgoing: isOutgoing,
                      ),
                    if (message.hasInvoice)
                      _InvoiceCard(
                        message: message,
                        theme: theme,
                        isDark: isDark,
                        isOutgoing: isOutgoing,
                      ),
                    // Media indicator — album or single.
                    if (albumItems.length >= 2)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: AlbumLayout(
                          items: albumItems,
                          maxWidth: (showAvatar ? _maxWidth - 40 : _maxWidth) - 22,
                          allMessages: allMessages,
                        ),
                      )
                    else if (message.hasMedia)
                      _MediaIndicator(
                        message: message,
                        theme: theme,
                        showOverlayInfo: isMediaOnlyBubble,
                        isOutgoing: isOutgoing,
                        isDark: isDark,
                        isSelected: isSelected,
                        isScheduledView: widget.isScheduledView,
                        allMessages: allMessages,
                      ),
                    // Caption text below media for captioned photo/video/GIF.
                    if (isCaptionedMedia)
                      _RichMessageText(
                        text: message.contentText,
                        entitiesJson: message.contentRich,
                        baseStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
                        theme: theme,
                        isOutgoing: isOutgoing,
                        accountId: message.accountId,
                        onContextMenu: onContextMenu,
                        trailingPad: useFloatingInfo ? inlineInfoWidget : null,
                      ),
                    // Reactions row — pill badges above the timestamp.
                    if (message.reactions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _ReactionList(
                        reactions: message.reactions,
                        isOutgoing: isOutgoing,
                        theme: theme,
                        reactionKeys: _reactionKeys,
                        accountId: message.accountId,
                      ),
                    ],
                    // Bottom info: views + forwards + edited + time + status.
                    // Spec §5: msgInDateFg / msgOutDateFg per theme.
                    // Skipped for media-only bubbles — overlay rendered by _VisualMedia instead.
                    // Skipped when floating info is used (rendered inline at end of text).
                    if (!isMediaOnlyBubble && !useFloatingInfo) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Spacer(),
                          if (message.views > 0) ...[
                            SizedBox(width: 20, height: 11,
                              child: CustomPaint(painter: _ViewsIconPainter(color: _bottomInfoColor(isOutgoing, palette)))),
                            const SizedBox(width: 8),
                            Text(_formatCount(message.views),
                                style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, palette))),
                          ],
                          if (message.forwards > 0) ...[
                            const SizedBox(width: 8),
                            SizedBox(width: 20, height: 11,
                              child: CustomPaint(painter: _ForwardsIconPainter(color: _bottomInfoColor(isOutgoing, palette)))),
                            const SizedBox(width: 8),
                            Text(_formatCount(message.forwards),
                                style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, palette))),
                          ],
                          ..._buildDeletedEditedMarks(
                            message: message,
                            color: _bottomInfoColor(isOutgoing, palette),
                            appState: ayuState,
                          ),
                          if (widget.isScheduledView && message.isScheduled)
                            TelegramTooltip(
                              message: _scheduledTooltip(message),
                              child: Text(
                                _formatScheduledTime(message),
                                style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, palette)),
                              ),
                            )
                          else
                            Text(
                              _buildTimeText(message, ayuState),
                              style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, palette)),
                            ),
                          if (isOutgoing && !widget.isScheduledView)
                            SizedBox(
                              width: 24,
                              height: 11,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: _StatusIcon(status: message.status, theme: theme, isOutgoing: true, isDark: isDark),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (inSelectionMode)
                Positioned(
                  bottom: 5,
                  right: 4,
                  child: _SelectionCheckbox(
                    checked: isSelected,
                    isDark: isDark,
                  ),
                ),
              if (_hovered && !inSelectionMode)
                Positioned(
                  top: -9,
                  right: isOutgoing ? null : 7,
                  left: isOutgoing ? 7 : null,
                  child: _ReactionCornerButton(
                    isDark: isDark,
                    emoji: _availableReactions.first,
                    onTap: () => _onReactionTap(_availableReactions.first),
                  ),
                ),
              ],
              ),
              if (message.hasInlineKeyboard)
                _InlineKeyboard(
                  rows: message.inlineKeyboard,
                  messageId: message.msgId,
                  isOutgoing: isOutgoing,
                  isDark: isDark,
                ),
            ],
            ),
            ),
          ),
          ),
            ], // Row children
          ),
        ],
      ),
    ),
    );

    if (deletedOpacity < 1.0) {
      bubble = AnimatedOpacity(
        opacity: deletedOpacity,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        child: bubble,
      );
    }

    return bubble;
  }

  Widget _buildSenderAvatar(bool isDark) {
    const double avatarSize = 33;
    final message = widget.message;
    final senderAvatarB64 = widget.senderAvatarB64;
    final onSenderTap = widget.onSenderTap;
    final onSenderContextMenu = widget.onSenderContextMenu;

    // §25.15.4: dynamic avatar corner radius.
    final avatarCorner = context.watch<AppState>().avatarCorners;
    final avatarR = (avatarSize / 2) * (avatarCorner / 23.0);

    final fallback = Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        color: _senderColor(message.senderId, palette: context.palette, isDark: isDark, colorId: message.senderColorId),
        borderRadius: BorderRadius.circular(avatarR),
      ),
      alignment: Alignment.center,
      child: Text(
        message.senderName.isNotEmpty ? message.senderName[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );

    if (senderAvatarB64 != null && senderAvatarB64.isNotEmpty) {
      try {
        final bytes = base64Decode(senderAvatarB64);
        return _SenderNameTapTarget(
          onTap: onSenderTap != null ? () => onSenderTap(message.senderId) : null,
          onSecondaryTap: onSenderContextMenu != null
              ? (pos) => onSenderContextMenu(message.senderId, pos)
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(avatarR),
            child: Image.memory(
              bytes,
              width: avatarSize,
              height: avatarSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
          ),
        );
      } catch (_) {
        return _SenderNameTapTarget(
          onTap: onSenderTap != null ? () => onSenderTap(message.senderId) : null,
          onSecondaryTap: onSenderContextMenu != null
              ? (pos) => onSenderContextMenu(message.senderId, pos)
              : null,
          child: fallback,
        );
      }
    }
    return _SenderNameTapTarget(
      onTap: onSenderTap != null ? () => onSenderTap(message.senderId) : null,
      onSecondaryTap: onSenderContextMenu != null
          ? (pos) => onSenderContextMenu(message.senderId, pos)
          : null,
      child: fallback,
    );
  }

  /// 7 sender colors from spec §5 (id % 7).
  /// Day: historyPeer{1..7}NameFg, Night: matching night-theme slots.
  /// Remap table: colorIndex (id%7) → paletteIndex (0..7).
  /// Source: chat_style.cpp ColorIndexToPaletteIndex — {0,7,4,1,6,3,5}.
  static const _colorIndexRemap = [0, 7, 4, 1, 6, 3, 5];

  static List<Color> _namePaletteFromTokens(TelegramPalette p) => [
    p.historyPeer1NameFg,
    p.historyPeer2NameFg,
    p.historyPeer3NameFg,
    p.historyPeer4NameFg,
    p.historyPeer5NameFg,
    p.historyPeer6NameFg,
    p.historyPeer7NameFg,
    p.historyPeer8NameFg,
  ];

  /// Extended 64-entry peer color palette fetched at runtime from help.peerColors.
  /// Key: color_id (0..63), Value: [dayColor, nightColor].
  /// Populated by calling [loadPeerColors] after auth.
  static final Map<int, List<Color>> _extendedPalette = {};

  /// Load the extended peer color palette from the engine.
  /// Called once per account after successful auth.
  static void loadPeerColors(List<PeerColorEntry> entries) {
    for (final e in entries) {
      if (e.dayColors.isEmpty) continue; // indices 0-6 return empty, use hardcoded
      final dayRgb = e.dayColors.first;
      final dayColor = Color(0xFF000000 | (dayRgb & 0xFFFFFF));
      final nightColor = e.nightColors.isNotEmpty
          ? Color(0xFF000000 | (e.nightColors.first & 0xFFFFFF))
          : dayColor; // fallback to day if no night variant
      _extendedPalette[e.colorId] = [dayColor, nightColor];
    }
  }

  /// Resolve sender name color using the color_id from the user's PeerColor.
  /// For color_id 0-6 (default), uses the palette's 8-slot peer name tokens via remap.
  /// For color_id 7+ (premium/extended), uses the runtime-fetched palette.
  static Color _senderColor(String senderId, {required TelegramPalette palette, bool isDark = false, int colorId = -1}) {
    if (colorId >= 7) {
      final ext = _extendedPalette[colorId];
      if (ext != null) {
        return isDark ? ext[1] : ext[0];
      }
    }

    final effectiveColorId = (colorId >= 0 && colorId < 7)
        ? colorId
        : ((int.tryParse(senderId) ?? senderId.hashCode.abs()).abs() % 7);
    final paletteIndex = _colorIndexRemap[effectiveColorId];
    return _namePaletteFromTokens(palette)[paletteIndex];
  }

  static String _formatTime(int timestampMs) {
    if (timestampMs == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _formatScheduledTime(CachedMessage msg) {
    final ts = msg.scheduleDate > 0 ? msg.scheduleDate * 1000 : msg.timestamp;
    final time = _formatTime(ts);
    final prefix = _repeatPeriodLabel(msg.scheduleRepeatPeriod);
    return prefix.isEmpty ? time : '$prefix $time';
  }

  static String _repeatPeriodLabel(int period) {
    const labels = {
      86400: 'daily',
      604800: 'weekly',
      1209600: 'biweekly',
      2592000: 'monthly',
      7862400: 'every 3 months',
      15724800: 'every 6 months',
      31536000: 'yearly',
    };
    return labels[period] ?? '';
  }

  static String _scheduledTooltip(CachedMessage msg) {
    final ts = msg.scheduleDate > 0 ? msg.scheduleDate * 1000 : msg.timestamp;
    if (ts == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final date = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    var tip = '$date $time\nID: ${msg.msgId}';
    if (msg.isSilent) tip += '\n\u{1F515}';
    return tip;
  }

  /// Compact number format for views/forwards (e.g. 1.2K, 3.5M).
  static String _formatCount(int n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) {
      final v = (n / 1000).toStringAsFixed(1);
      return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v}K';
    }
    final v = (n / 1000000).toStringAsFixed(1);
    return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v}M';
  }

  /// Spec §5: bottom info timestamp/edited color per direction+theme.
  static Color _bottomInfoColor(bool isOutgoing, TelegramPalette palette) {
    return isOutgoing ? palette.msgOutDateFg : palette.msgInDateFg;
  }

  /// §52.3: Build deleted/edited mark widgets for bottom info row.
  /// Mode 2 (icons): trash icon for deleted, pencil icon for edited.
  /// Mode 1 (text): "edited" text label for edited messages.
  /// Order: [deleted-icon] [edited-icon/text]
  static List<Widget> _buildDeletedEditedMarks({
    required CachedMessage message,
    required Color color,
    required AppState appState,
  }) {
    final widgets = <Widget>[];
    if (appState.replaceMarksWithIcons) {
      if (message.isDeleted)
        widgets.add(Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Icon(Icons.delete_outline, size: 14, color: color),
        ));
      if (message.isEdited)
        widgets.add(Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Icon(Icons.edit, size: 14, color: color),
        ));
    } else {
      if (message.isDeleted)
        widgets.add(Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(appState.deletedMark,
              style: TextStyle(fontSize: 13, color: color)),
        ));
      if (message.isEdited)
        widgets.add(Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text('edited',
              style: TextStyle(fontSize: 13, color: color)),
        ));
    }
    return widgets;
  }

  /// §52.3: Build time text, prepending deletedMark in Mode 1 (text marks).
  static String _buildTimeText(CachedMessage message, AppState appState) {
    final time = _formatTime(message.timestamp);
    if (!appState.replaceMarksWithIcons && message.isDeleted) {
      return '${appState.deletedMark} $time';
    }
    return time;
  }
}

class _SenderNameTapTarget extends StatelessWidget {
  static DateTime _lastConsumed = DateTime(0);

  static bool get recentlyConsumed =>
      DateTime.now().difference(_lastConsumed).inMilliseconds < 200;

  final VoidCallback? onTap;
  final ValueChanged<Offset>? onSecondaryTap;
  final Widget child;

  const _SenderNameTapTarget({this.onTap, this.onSecondaryTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton && onSecondaryTap != null) {
          _lastConsumed = DateTime.now();
          onSecondaryTap!(event.position);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// Spec §9.3: Per-message corner reaction button — 36x32 pill, 22px emoji, 120ms fade.
class _ReactionCornerButton extends StatefulWidget {
  final bool isDark;
  final String emoji;
  final VoidCallback onTap;

  const _ReactionCornerButton({
    super.key,
    required this.isDark,
    this.emoji = '❤️',
    required this.onTap,
  });

  @override
  State<_ReactionCornerButton> createState() => _ReactionCornerButtonState();
}

class _ReactionCornerButtonState extends State<_ReactionCornerButton>
    with TickerProviderStateMixin {
  late final AnimationController _toggleController;
  late final Animation<double> _fadeScale;
  late final AnimationController _activateController;
  late final Animation<double> _activateScale;

  @override
  void initState() {
    super.initState();
    _toggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _fadeScale = CurvedAnimation(parent: _toggleController, curve: Curves.easeOut);
    _toggleController.forward();
    _activateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _activateScale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _activateController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _toggleController.dispose();
    _activateController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _activateController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _activateController.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _activateController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF2B3640) : Colors.white;
    return FadeTransition(
      opacity: _fadeScale,
      child: ScaleTransition(
        scale: _fadeScale,
        alignment: Alignment.bottomCenter,
        child: AnimatedBuilder(
          animation: _activateScale,
          builder: (context, child) => Transform.scale(
            scale: _activateScale.value,
            child: child,
          ),
          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            child: Container(
              width: 36,
              height: 32,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(widget.emoji, style: const TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spec §9.3: Floating reaction strip — 40px height, 32px slot, 26px emoji, 7px skip.
class _ReactionStrip extends StatefulWidget {
  final ValueChanged<String> onReactionTap;
  final VoidCallback onExpandTap;
  final bool isDark;
  final List<String> reactions;

  const _ReactionStrip({
    super.key,
    required this.onReactionTap,
    required this.onExpandTap,
    required this.isDark,
    this.reactions = const ['👍', '❤️', '🔥', '🥰', '👏', '😱', '😢', '🎉'],
  });

  @override
  State<_ReactionStrip> createState() => _ReactionStripState();
}

class _ReactionStripState extends State<_ReactionStrip>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeScale;
  int _hoveredIndex = -1;
  int _pressedIndex = -1;
  int _flyingIndex = -1;
  AnimationController? _flyController;

  List<String> get _reactions => widget.reactions.take(8).toList();
  static const _stripHeight = 40.0;
  static const _slotSize = 32.0;
  static const _emojiSize = 26.0;
  static const _skip = 7.0;
  static const _kToggleDuration = Duration(milliseconds: 120);
  static const _kActivateDuration = Duration(milliseconds: 150);
  static const _kHoverScaleDuration = Duration(milliseconds: 200);
  static const _kHoverScale = 1.24;
  static const _kActivateScale = 0.85;
  static const _kFlyUpDistance = 50.0;
  static const _kFlyUpDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _kToggleDuration,
    );
    _fadeScale = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _flyController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _triggerFlyUp(int index) {
    final noAnim = context.read<AppState>().powerSaving(AppState.kPowerSavingEmojiReactions);
    if (noAnim) {
      widget.onReactionTap(_reactions[index]);
      return;
    }
    _flyController?.dispose();
    _flyController = AnimationController(
      vsync: this,
      duration: _kFlyUpDuration,
    );
    setState(() => _flyingIndex = index);
    _flyController!.forward().then((_) {
      if (mounted) {
        widget.onReactionTap(_reactions[index]);
      }
    });
  }

  double _scaleFor(int i) {
    if (_pressedIndex == i) return _kActivateScale;
    if (_hoveredIndex == i) return _kHoverScale;
    return 1.0;
  }

  Duration _scaleDurationFor(int i) {
    if (_pressedIndex == i) return _kActivateDuration;
    return _kHoverScaleDuration;
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF2B3640) : Colors.white;
    final shadow = widget.isDark ? Colors.black26 : Colors.black12;
    final expandBtnSize = _slotSize;
    final totalWidth =
        _skip + _reactions.length * (_slotSize + _skip) + expandBtnSize + _skip;

    return FadeTransition(
      opacity: _fadeScale,
      child: ScaleTransition(
        scale: _fadeScale,
        alignment: Alignment.bottomCenter,
        child: Container(
          height: _stripHeight,
          width: totalWidth,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_stripHeight / 2),
            boxShadow: [
              BoxShadow(
                  color: shadow, blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: _skip),
              for (int i = 0; i < _reactions.length; i++)
                MouseRegion(
                  onEnter: (_) => setState(() => _hoveredIndex = i),
                  onExit: (_) => setState(() => _hoveredIndex = -1),
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _pressedIndex = i),
                    onTapUp: (_) {
                      setState(() => _pressedIndex = -1);
                      _triggerFlyUp(i);
                    },
                    onTapCancel: () => setState(() => _pressedIndex = -1),
                    child: SizedBox(
                      width: _slotSize,
                      height: _slotSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: AnimatedScale(
                              scale: _scaleFor(i),
                              duration: _scaleDurationFor(i),
                              child: Text(
                                _reactions[i],
                                style: const TextStyle(fontSize: _emojiSize),
                              ),
                            ),
                          ),
                          if (_flyingIndex == i && _flyController != null)
                            AnimatedBuilder(
                              animation: _flyController!,
                              builder: (_, __) {
                                final t = _flyController!.value;
                                return Positioned(
                                  left: 0,
                                  right: 0,
                                  top: -t * _kFlyUpDistance,
                                  child: Opacity(
                                    opacity: (1.0 - t).clamp(0.0, 1.0),
                                    child: Center(
                                      child: Transform.scale(
                                        scale: 1.0 + t * 0.5,
                                        child: Text(
                                          _reactions[i],
                                          style: const TextStyle(
                                              fontSize: _emojiSize),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              MouseRegion(
                onEnter: (_) => setState(() => _hoveredIndex = 99),
                onExit: (_) => setState(() => _hoveredIndex = -1),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (_) => widget.onExpandTap(),
                  child: AnimatedScale(
                    scale: _hoveredIndex == 99 ? _kHoverScale : 1.0,
                    duration: _kHoverScaleDuration,
                    child: SizedBox(
                      width: expandBtnSize,
                      height: _slotSize,
                      child: Center(
                        child: Icon(
                          Icons.add,
                          size: 20,
                          color: context.palette.windowSubTextFg,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionEmojiOverlay extends StatefulWidget {
  final Offset stripOffset;
  final Size stripSize;
  final bool isDark;
  final ValueChanged<String> onPick;
  final VoidCallback onDismiss;
  final List<String> availableReactions;

  const _ReactionEmojiOverlay({
    required this.stripOffset,
    required this.stripSize,
    required this.isDark,
    required this.onPick,
    required this.onDismiss,
    this.availableReactions = const [],
  });

  @override
  State<_ReactionEmojiOverlay> createState() => _ReactionEmojiOverlayState();
}

class _ReactionEmojiOverlayState extends State<_ReactionEmojiOverlay>
    with SingleTickerProviderStateMixin {
  int _activeCategory = 0;
  String _search = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  late final AnimationController _animController;
  late final CurvedAnimation _anim;

  static const _panelWidth = 345.0;
  static const _panelMaxHeight = 360.0;
  static const _cellSize = 40.0;
  static const _gridPadding = 8.0;

  static const _categories = [
    ('Recent', '🕐'),
    ('Smileys', '😊'),
    ('People', '👋'),
    ('Nature', '🐻'),
    ('Food', '🍔'),
    ('Activities', '⚽'),
    ('Travel', '🏠'),
    ('Objects', '💡'),
    ('Symbols', '❤️'),
    ('Flags', '🏳️'),
  ];

  static const _defaultRecentEmoji = [
    '👍', '❤️', '🔥', '🥰', '👏', '😱', '😢', '🎉',
    '🤔', '🥳', '😍', '💯', '🙏', '😂', '❤️‍🔥', '🤣',
  ];

  List<String> get _recentEmoji =>
      widget.availableReactions.isNotEmpty ? widget.availableReactions : _defaultRecentEmoji;

  List<List<String>> get _emojiByCategory => [
    _recentEmoji,
    ['😀', '😃', '😄', '😁', '😆', '🥹', '😅', '🤣',
     '😂', '🙂', '🙃', '😉', '😊', '😇', '🥰', '😍',
     '🤩', '😘', '😗', '☺️', '😚', '😙', '🥲', '😋',
     '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫',
     '🤔', '🫡', '🤐', '🤨', '😐', '😑', '😶', '🫥',
     '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪',
     '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🥴',
     '😵', '🤯', '🥱', '😤', '😡', '🤬', '😈', '👿',
     '💀', '☠️', '💩', '🤡', '👹', '👺', '👻', '👽',
     '🤖', '😺', '😸', '😹', '😻', '😼', '😽', '🙀',
     '😿', '😾'],
    ['👋', '🤚', '🖐️', '✋', '🖖', '🫱', '🫲', '🫳',
     '🫴', '🫷', '🫸', '👌', '🤌', '🤏', '✌️', '🤞',
     '🫰', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕',
     '👇', '☝️', '🫵', '👍', '👎', '✊', '👊', '🤛',
     '🤜', '👏', '🙌', '🫶', '👐', '🤲', '🤝', '🙏',
     '✍️', '💅', '🤳', '💪', '🦾', '🦿', '🦵', '🦶',
     '👂', '🦻', '👃', '🧠', '🫀', '🫁', '🦷', '🦴',
     '👀', '👁️', '👅', '👄'],
    ['🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
     '🐻‍❄️', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵',
     '🙈', '🙉', '🙊', '🐔', '🐧', '🐦', '🐤', '🦆',
     '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝',
     '🪱', '🐛', '🦋', '🐌', '🐞', '🐜', '🪰', '🪲',
     '🪳', '🦟', '🦗', '🕷️', '🌸', '💐', '🌷', '🌹',
     '🥀', '🌺', '🌻', '🌼', '🌱', '🪴', '🌲', '🌳',
     '🌴', '🌵', '🍀', '☘️', '🍃', '🍂', '🍁', '🌾'],
    ['🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇',
     '🍓', '🫐', '🍈', '🍒', '🍑', '🥭', '🍍', '🥥',
     '🥝', '🍅', '🍆', '🥑', '🥦', '🥬', '🥒', '🌶️',
     '🫑', '🌽', '🥕', '🧄', '🧅', '🥔', '🍠', '🫘',
     '🥐', '🍞', '🥖', '🫓', '🥨', '🧀', '🥚', '🍳',
     '🧈', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🌭',
     '🍔', '🍟', '🍕', '🫔', '🌮', '🌯', '🫕', '🥗',
     '🥣', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟'],
    ['⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉',
     '🥏', '🎱', '🪀', '🏓', '🏸', '🏒', '🏑', '🥍',
     '🏏', '🪃', '🥅', '⛳', '🪁', '🏹', '🎣', '🤿',
     '🥊', '🥋', '🎽', '🛹', '🛼', '🛷', '⛸️', '🥌',
     '🎿', '⛷️', '🏂', '🪂', '🏆', '🥇', '🥈', '🥉',
     '🏅', '🎖️', '🏵️', '🎗️', '🎪', '🎭', '🩰', '🎨',
     '🎬', '🎤', '🎧', '🎼', '🎹', '🥁', '🪘', '🎷',
     '🎺', '🪗', '🎸', '🎻', '🎲', '♟️', '🎯', '🎳'],
    ['🏠', '🏡', '🏢', '🏣', '🏤', '🏥', '🏦', '🏨',
     '🏩', '🏪', '🏫', '🏬', '🏭', '🏯', '🏰', '💒',
     '🗼', '🗽', '⛪', '🕌', '🛕', '🕍', '⛩️', '🕋',
     '⛲', '⛺', '🌁', '🌃', '🏙️', '🌄', '🌅', '🌆',
     '🌇', '🌉', '🗾', '🏔️', '⛰️', '🌋', '🗻', '🏕️',
     '🏖️', '🏜️', '🏝️', '🏞️', '🚗', '🚕', '🚙', '🚌',
     '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐', '🛻', '🚚',
     '🚛', '🚜', '✈️', '🚀', '🛸', '🚁', '🛶', '⛵'],
    ['💡', '🔦', '🕯️', '💎', '🔑', '🗝️', '🔒', '🔓',
     '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️',
     '🕹️', '🗜️', '💽', '💾', '💿', '📀', '📼', '📷',
     '📸', '📹', '🎥', '📽️', '🎞️', '📞', '☎️', '📟',
     '📠', '📺', '📻', '🎙️', '🎚️', '🎛️', '🧭', '⏱️',
     '⏲️', '⏰', '🕰️', '⌛', '📡', '🔋', '🪫', '🔌',
     '💰', '🪙', '💴', '💵', '💶', '💷', '💸', '💳',
     '🧾', '📦', '📫', '📪', '📬', '📭', '📮', '🗳️'],
    ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
     '🤎', '❤️‍🔥', '❤️‍🩹', '💔', '❣️', '💕', '💞', '💓',
     '💗', '💖', '💘', '💝', '💟', '☮️', '✝️', '☪️',
     '🕉️', '☸️', '✡️', '🔯', '🕎', '☯️', '☦️', '🛐',
     '⛎', '♈', '♉', '♊', '♋', '♌', '♍', '♎',
     '♏', '♐', '♑', '♒', '♓', '🆔', '⚛️', '🉑',
     '☢️', '☣️', '📴', '📳', '🈶', '🈚', '🈸', '🈺',
     '🈷️', '✴️', '🆚', '💮', '🉐', '㊙️', '㊗️', '🈴'],
    ['🏳️', '🏴', '🏴‍☠️', '🏁', '🚩', '🏳️‍🌈', '🏳️‍⚧️', '🇺🇳',
     '🇺🇸', '🇬🇧', '🇫🇷', '🇩🇪', '🇮🇹', '🇪🇸', '🇧🇷', '🇯🇵',
     '🇰🇷', '🇨🇳', '🇷🇺', '🇮🇳', '🇨🇦', '🇦🇺', '🇲🇽', '🇹🇷',
     '🇦🇷', '🇸🇦', '🇿🇦', '🇳🇬', '🇪🇬', '🇰🇪', '🇮🇱', '🇵🇸'],
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _anim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCirc,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  List<String> _filteredEmoji() {
    if (_search.isEmpty) {
      return _emojiByCategory[_activeCategory];
    }
    final all = <String>{};
    for (final cat in _emojiByCategory) {
      all.addAll(cat);
    }
    return all.toList();
  }

  @override
  Widget build(BuildContext context) {
    final ep = context.palette;
    final bg = ep.windowBgOver;
    final shadow = widget.isDark ? Colors.black26 : Colors.black12;
    final tabBg = ep.windowBg;
    final tabActive = ep.windowBgRipple;
    final searchBg = ep.windowBg;
    final textColor = ep.windowFg.withValues(alpha: 0.87);
    final emojis = _filteredEmoji();
    final cols = ((_panelWidth - _gridPadding * 2) / _cellSize).floor();

    final screenSize = MediaQuery.of(context).size;
    var panelLeft = widget.stripOffset.dx;
    var panelTop = widget.stripOffset.dy - _panelMaxHeight - 4;
    if (panelLeft + _panelWidth > screenSize.width - 8) {
      panelLeft = screenSize.width - _panelWidth - 8;
    }
    if (panelLeft < 8) panelLeft = 8;
    if (panelTop < 8) panelTop = 8;

    return Stack(
      children: [
        GestureDetector(
          onTap: widget.onDismiss,
          behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand(),
        ),
        Positioned(
          left: panelLeft,
          top: panelTop,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, child) {
              return Opacity(
                opacity: _anim.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.85 + 0.15 * _anim.value,
                  alignment: Alignment.bottomLeft,
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: _panelWidth,
                constraints:
                    const BoxConstraints(maxHeight: _panelMaxHeight),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                        color: shadow,
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: searchBg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            Icon(Icons.search,
                                size: 18,
                                color: ep.windowSubTextFg),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(
                                    fontSize: 13, color: textColor),
                                decoration: InputDecoration(
                                  hintText: 'Search emoji',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: ep.windowSubTextFg,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          vertical: 8),
                                ),
                                onChanged: (v) =>
                                    setState(() => _search = v),
                              ),
                            ),
                            if (_search.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _search = '');
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  child: Icon(Icons.close,
                                      size: 16,
                                      color: ep.windowSubTextFg),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_search.isEmpty)
                      SizedBox(
                        height: 32,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          itemCount: _categories.length,
                          itemBuilder: (context, i) {
                            final isActive = _activeCategory == i;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 2),
                              child: GestureDetector(
                                onTap: () {
                                  setState(
                                      () => _activeCategory = i);
                                  _scrollController.jumpTo(0);
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? tabActive
                                        : tabBg,
                                    borderRadius:
                                        BorderRadius.circular(16),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _categories[i].$2,
                                    style: const TextStyle(
                                        fontSize: 18),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (_search.isEmpty) const SizedBox(height: 4),
                    Flexible(
                      child: GridView.builder(
                        controller: _scrollController,
                        padding:
                            const EdgeInsets.all(_gridPadding),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          childAspectRatio: 1,
                        ),
                        itemCount: emojis.length,
                        itemBuilder: (context, i) {
                          return GestureDetector(
                            onTap: () =>
                                widget.onPick(emojis[i]),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Center(
                                child: Text(
                                  emojis[i],
                                  style: const TextStyle(
                                      fontSize: 28),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionList extends StatelessWidget {
  final List<MessageReaction> reactions;
  final bool isOutgoing;
  final ThemeData theme;
  final Map<String, GlobalKey> reactionKeys;
  final String accountId;

  const _ReactionList({
    required this.reactions,
    required this.isOutgoing,
    required this.theme,
    required this.reactionKeys,
    required this.accountId,
  });

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final inactiveBg = primary.withValues(alpha: isDark ? 0.18 : 0.12);
    final activeBg = primary.withValues(alpha: isDark ? 0.38 : 0.28);
    final inactiveLabel = theme.textTheme.bodyMedium?.color ?? Colors.white;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final r in reactions)
          GestureDetector(
            onTap: r.isCustomEmoji
                ? () => _showCustomEmojiPreview(context, r)
                : null,
            child: Container(
              key: reactionKeys[r.isCustomEmoji ? 'custom_${r.documentId}' : r.emoji],
              height: 22,
              padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
              decoration: BoxDecoration(
                color: r.byMe ? activeBg : inactiveBg,
                borderRadius: BorderRadius.circular(11),
                border: r.byMe
                    ? Border.all(color: primary, width: 1)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (r.isCustomEmoji)
                    _CustomEmojiInline(
                      documentId: r.documentId,
                      accountId: accountId,
                      altText: r.emoji.isNotEmpty ? r.emoji : '⭐',
                    )
                  else
                    Text(r.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 4),
                  Text(
                    _formatCount(r.count),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: r.byMe ? primary : inactiveLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showCustomEmojiPreview(BuildContext context, MessageReaction r) {
    _ReactionPreviewOverlay.show(
      context: context,
      documentId: r.documentId,
      accountId: accountId,
    );
  }

  static String _formatCount(int n) {
    if (n < 1000) return n.toString();
    if (n < 10000) {
      final v = (n / 1000).toStringAsFixed(1);
      return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v}K';
    }
    return '${(n / 1000).round()}K';
  }
}

class _ReactorAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String avatarB64;

  const _ReactorAvatar({required this.name, required this.size, this.avatarB64 = ''});

  @override
  Widget build(BuildContext context) {
    if (avatarB64.isNotEmpty) {
      try {
        final bytes = base64Decode(avatarB64);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(context),
          ),
        );
      } catch (_) {}
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final hue = name.hashCode % 360;
    final bgColor = HSLColor.fromAHSL(1.0, hue.toDouble().abs(), 0.5, isDark ? 0.35 : 0.65).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ReactionPreviewOverlay extends StatefulWidget {
  final int documentId;
  final String accountId;

  const _ReactionPreviewOverlay({
    required this.documentId,
    required this.accountId,
  });

  static void show({
    required BuildContext context,
    required int documentId,
    required String accountId,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (ctx, _, __) => _ReactionPreviewOverlay(
          documentId: documentId,
          accountId: accountId,
        ),
        transitionsBuilder: (ctx, anim, _, child) {
          return FadeTransition(opacity: anim, child: child);
        },
        transitionDuration: const Duration(milliseconds: 120),
        reverseTransitionDuration: const Duration(milliseconds: 120),
      ),
    );
  }

  @override
  State<_ReactionPreviewOverlay> createState() => _ReactionPreviewOverlayState();
}

class _ReactionPreviewOverlayState extends State<_ReactionPreviewOverlay>
    with TickerProviderStateMixin {
  CustomEmojiSetInfo? _setInfo;
  bool _loadingSet = true;
  Uint8List? _decompressedLottie;
  AnimationController? _lottieController;
  Size? _initialSize;
  final FocusNode _focusNode = FocusNode();

  static const _previewSize = 224.0;
  static const _shadowExtend = 10.0;
  static const _boxRadius = 8.0;
  static const _paddingLeft = 12.0;
  static const _paddingTop = 3.0;
  static const _paddingRight = 12.0;
  static const _paddingBottom = 4.0;

  @override
  void initState() {
    super.initState();
    CustomEmojiCache.instance.acquire(widget.documentId, EmojiSizeTag.large);
    CustomEmojiCache.instance.addListener(_onCacheUpdate);
    _requestFile();
    _loadSetInfo();
  }

  @override
  void dispose() {
    CustomEmojiCache.instance.removeListener(_onCacheUpdate);
    CustomEmojiCache.instance.release(widget.documentId, EmojiSizeTag.large);
    _lottieController?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCacheUpdate() {
    if (!mounted) return;
    final file = CustomEmojiCache.instance.getFile(widget.documentId);
    if (file != null && file.isTgs && _decompressedLottie == null) {
      _decompressLottieAsync(file.fileData);
    }
    setState(() {});
  }

  Future<void> _decompressLottieAsync(Uint8List data) async {
    try {
      final result = await compute(_gzipDecode, data);
      if (!mounted) return;
      setState(() => _decompressedLottie = result);
    } catch (_) {}
  }

  void _requestFile() {
    final cache = CustomEmojiCache.instance;
    if (cache.getFile(widget.documentId) == null &&
        !cache.isFilePending(widget.documentId) &&
        widget.accountId.isNotEmpty) {
      final engine = context.read<EngineService>();
      cache.requestFile(widget.documentId, widget.accountId, engine);
    }
    if (cache.getThumb(widget.documentId) == null &&
        !cache.isPending(widget.documentId) &&
        !cache.hasFailed(widget.documentId) &&
        widget.accountId.isNotEmpty) {
      final engine = context.read<EngineService>();
      cache.request(widget.documentId, widget.accountId, engine);
    }
  }

  Future<void> _loadSetInfo() async {
    final engine = context.read<EngineService>();
    final info = await engine.getCustomEmojiSetInfo(widget.accountId, widget.documentId);
    if (mounted) {
      setState(() {
        _setInfo = info;
        _loadingSet = false;
      });
    }
  }

  void _onLottieLoaded(LottieComposition comp) {
    _lottieController?.dispose();
    _lottieController = AnimationController(vsync: this, duration: comp.duration);
    _lottieController!.repeat();
  }

  void _openStickerSet() {
    if (_setInfo == null) return;
    Navigator.of(context).pop();
    final engine = context.read<EngineService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StickerSetByIdViewer(
        setId: _setInfo!.setId,
        accessHash: _setInfo!.accessHash,
        engine: engine,
        accountId: widget.accountId,
      ),
    );
  }

  void _dismiss() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _initialSize ??= size;
    if (_initialSize != null && _initialSize != size) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismiss());
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(widget.documentId);
    final thumb = cache.getThumb(widget.documentId);

    Widget emojiPreview;
    if (file != null && file.isTgs && _decompressedLottie != null) {
      emojiPreview = SizedBox(
        width: _previewSize,
        height: _previewSize,
        child: Lottie.memory(
          _decompressedLottie!,
          width: _previewSize,
          height: _previewSize,
          fit: BoxFit.contain,
          controller: _lottieController,
          onLoaded: _onLottieLoaded,
        ),
      );
    } else if (file != null && file.isWebp) {
      emojiPreview = Image.memory(
        file.fileData,
        width: _previewSize,
        height: _previewSize,
        fit: BoxFit.contain,
      );
    } else if (thumb != null) {
      emojiPreview = Image.memory(
        thumb,
        width: _previewSize,
        height: _previewSize,
        fit: BoxFit.contain,
      );
    } else {
      emojiPreview = const SizedBox(
        width: _previewSize,
        height: _previewSize,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final hasViewPack = !_loadingSet && _setInfo != null && _setInfo!.title.isNotEmpty;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _dismiss();
        }
      },
      child: GestureDetector(
        onTap: _dismiss,
        child: Material(
          color: Colors.black54,
          child: Stack(
            children: [
              Center(child: emojiPreview),
              if (hasViewPack)
                _ViewPackButton(
                  title: _setInfo!.title,
                  isDark: isDark,
                  viewportSize: size,
                  onTap: _openStickerSet,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewPackButton extends StatelessWidget {
  final String title;
  final bool isDark;
  final Size viewportSize;
  final VoidCallback onTap;

  const _ViewPackButton({
    required this.title,
    required this.isDark,
    required this.viewportSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const shadowExtend = _ReactionPreviewOverlayState._shadowExtend;
    const boxRadius = _ReactionPreviewOverlayState._boxRadius;
    const padL = _ReactionPreviewOverlayState._paddingLeft;
    const padT = _ReactionPreviewOverlayState._paddingTop;
    const padR = _ReactionPreviewOverlayState._paddingRight;
    const padB = _ReactionPreviewOverlayState._paddingBottom;

    final labelText = 'Custom emoji from $title.';

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: labelText,
            style: const TextStyle(fontSize: 13),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: double.infinity);
        final maxLabelWidth = textPainter.width / 2;
        final innerWidth = maxLabelWidth + padL + padR;
        final bgWidth = innerWidth + shadowExtend * 2;
        final bgHeight = (textPainter.height * 2) + padT + padB + shadowExtend * 2;
        final bgY = (viewportSize.height * 0.75) - (bgHeight / 2);
        textPainter.dispose();

        return Positioned(
          left: (viewportSize.width - bgWidth) / 2,
          top: bgY,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: bgWidth,
              padding: const EdgeInsets.all(shadowExtend),
              child: Container(
                decoration: BoxDecoration(
                  color: context.palette.windowBg,
                  borderRadius: BorderRadius.circular(boxRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(padL, padT, padR, padB),
                child: Text(
                  labelText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.windowFg.withValues(alpha: 0.87),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StickerSetByIdViewer extends StatefulWidget {
  final int setId;
  final int accessHash;
  final EngineService engine;
  final String accountId;

  const _StickerSetByIdViewer({
    required this.setId,
    required this.accessHash,
    required this.engine,
    required this.accountId,
  });

  @override
  State<_StickerSetByIdViewer> createState() => _StickerSetByIdViewerState();
}

class _StickerSetByIdViewerState extends State<_StickerSetByIdViewer> {
  StickerSetInfo? _setInfo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final info = await widget.engine.getStickerSetInfo(
        widget.accountId,
        setId: widget.setId,
        accessHash: widget.accessHash,
      );
      if (mounted) setState(() { _setInfo = info; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ssPalette = context.palette;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: ssPalette.windowBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _setInfo == null
                ? const Center(child: Text('Sticker set not found'))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _setInfo!.title,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              '${_setInfo!.count} emoji',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: GridView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemCount: _setInfo!.stickers.length,
                          itemBuilder: (ctx, i) {
                            final s = _setInfo!.stickers[i];
                            final thumbBytes = s.thumbB64.isNotEmpty
                                ? base64Decode(s.thumbB64)
                                : null;
                            return thumbBytes != null
                                ? Image.memory(
                                    Uint8List.fromList(thumbBytes),
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  )
                                : Center(
                                    child: Text(
                                      s.emoji,
                                      style: const TextStyle(fontSize: 28),
                                    ),
                                  );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _TopicButton extends StatelessWidget {
  final String topicName;
  final int topicColorId;
  final String topicId;

  const _TopicButton({required this.topicName, required this.topicColorId, this.topicId = ''});

  static const _topicColors = <int, Color>{
    0x6FB9F0: Color(0xFF6FB9F0),
    0xFFD67E: Color(0xFFFFD67E),
    0xCB86DB: Color(0xFFCB86DB),
    0x8EEE98: Color(0xFF8EEE98),
    0xFF93B2: Color(0xFFFF93B2),
    0xFB6F5F: Color(0xFFFB6F5F),
  };
  static const _defaultColor = Color(0xFF6FB9F0);

  @override
  Widget build(BuildContext context) {
    final isGeneral = topicId == '1';
    final color = isGeneral
        ? context.palette.windowSubTextFg
        : (_topicColors[topicColorId] ?? _defaultColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (topicId == '1')
            GeneralForumTopicIcon(size: 16)
          else
            ForumTopicIcon(
              colorId: topicColorId,
              title: topicName,
              size: 16,
            ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              isGeneral ? '# $topicName' : topicName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final String preview;
  final ThemeData theme;
  final VoidCallback? onTap;
  final bool isOutgoing;

  const _ReplyPreview({required this.preview, required this.theme, this.onTap, this.isOutgoing = false});

  @override
  Widget build(BuildContext context) {
    final rp = context.palette;
    final simpleQuotesAndReplies = context.watch<AppState>().simpleQuotesAndReplies;
    final barColor = simpleQuotesAndReplies
        ? (theme.brightness == Brightness.dark
            ? const Color(0xFF5A6A78)
            : const Color(0xFFCBCBCB))
        : (isOutgoing ? rp.msgOutReplyBarColor : rp.msgInReplyBarColor);

    // Format: "SenderName\nPreviewText" or just "PreviewText"
    final nlIdx = preview.indexOf('\n');
    final String? senderName = nlIdx >= 0 ? preview.substring(0, nlIdx) : null;
    final String previewText = nlIdx >= 0 ? preview.substring(nlIdx + 1) : preview;

    final body = Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 1),
          Container(
            width: 2,
            height: 36,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (senderName != null) ...[
                  Text(
                    senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: barColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  previewText.replaceAll(RegExp(r'\s+'), ' ').trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: body,
    );
  }
}

class _MediaIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;
  final bool showOverlayInfo;
  final bool isOutgoing;
  final bool isDark;
  final bool isSelected;
  final bool isScheduledView;
  final List<CachedMessage> allMessages;

  const _MediaIndicator({
    required this.message,
    required this.theme,
    this.showOverlayInfo = false,
    this.isOutgoing = false,
    this.isDark = false,
    this.isSelected = false,
    this.isScheduledView = false,
    this.allMessages = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Image, video, sticker, GIF, video note — show visual preview.
    if (_isVisualMedia) {
      return _VisualMedia(
        message: message,
        theme: theme,
        showOverlayInfo: showOverlayInfo,
        isOutgoing: isOutgoing,
        isDark: isDark,
        isSelected: isSelected,
        isScheduledView: isScheduledView,
        allMessages: allMessages,
      );
    }
    // Poll — question + options.
    if (message.mediaType == 9) {
      return _PollWidget(message: message, theme: theme);
    }
    // Location — static/live/venue map.
    if (message.mediaType == 10) {
      return _LocationIndicator(message: message, theme: theme);
    }
    // Contact card.
    if (message.mediaType == 11) {
      return _ContactIndicator(message: message, theme: theme);
    }
    // Voice message — duration bar.
    if (message.mediaType == 4) {
      return _VoiceIndicator(message: message, theme: theme);
    }
    // Audio — file-like with duration.
    if (message.mediaType == 3) {
      return _AudioIndicator(message: message, theme: theme);
    }
    // File / document.
    return _FileIndicator(message: message, theme: theme);
  }

  bool get _isVisualMedia =>
      message.mediaType == 1 || // image
      message.mediaType == 2 || // video
      message.mediaType == 5 || // video note
      message.mediaType == 6 || // sticker
      message.mediaType == 7;   // gif
}

// ── Spoiler overlays using pre-rendered sprite sheet (spec §44.3) ──

class _MediaSpoilerOverlay extends StatefulWidget {
  final double width;
  final double height;
  final double revealProgress;
  final VoidCallback onReveal;

  const _MediaSpoilerOverlay({
    required this.width,
    required this.height,
    required this.revealProgress,
    required this.onReveal,
  });

  @override
  State<_MediaSpoilerOverlay> createState() => _MediaSpoilerOverlayState();
}

class _MediaSpoilerOverlayState extends State<_MediaSpoilerOverlay>
    with SpoilerAnimationMixin {
  @override
  void initState() {
    super.initState();
    initSpoiler(SpoilerType.image);
  }

  @override
  void didUpdateWidget(_MediaSpoilerOverlay old) {
    super.didUpdateWidget(old);
    if (widget.revealProgress >= 1.0) disposeSpoiler();
  }

  @override
  void dispose() {
    disposeSpoiler();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rp = widget.revealProgress;
    if (rp >= 1.0 || spoilerSheet == null) {
      return rp >= 1.0 ? const SizedBox.shrink() : SizedBox(width: widget.width, height: widget.height);
    }
    return GestureDetector(
      onTap: rp > 0 ? null : widget.onReveal,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: SpoilerTilePainter(
          sheet: spoilerSheet!,
          frame: spoilerFrame,
          revealProgress: rp,
          isMedia: true,
        ),
        size: Size(widget.width, widget.height),
      ),
    );
  }
}

class _TextSpoilerWidget extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool isDark;
  final VoidCallback onReveal;
  final bool revealed;

  const _TextSpoilerWidget({
    required this.text,
    required this.style,
    required this.isDark,
    required this.onReveal,
    required this.revealed,
  });

  @override
  State<_TextSpoilerWidget> createState() => _TextSpoilerWidgetState();
}

class _TextSpoilerWidgetState extends State<_TextSpoilerWidget>
    with TickerProviderStateMixin, SpoilerAnimationMixin {
  late final AnimationController _revealController;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (!widget.revealed) {
      initSpoiler(SpoilerType.text);
    } else {
      _revealController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_TextSpoilerWidget old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) {
      _revealController.forward().then((_) {
        if (mounted) disposeSpoiler();
      });
    } else if (!widget.revealed && old.revealed) {
      _revealController.value = 0.0;
      if (!spoilerRegistered) initSpoiler(SpoilerType.text);
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    disposeSpoiler();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = context.palette.msgInDateFg;

    return GestureDetector(
      onTap: widget.revealed ? null : widget.onReveal,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _revealController,
        builder: (_, __) {
          final revealVal = _revealController.value;
          if (revealVal >= 1.0) {
            return Text(widget.text, style: widget.style);
          }
          if (spoilerSheet == null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: ColoredBox(
                color: bgColor,
                child: Opacity(opacity: 0, child: Text(widget.text, style: widget.style)),
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: CustomPaint(
              foregroundPainter: _TextSpoilerSheetPainter(
                sheet: spoilerSheet!,
                frame: spoilerFrame,
                revealProgress: revealVal,
                bgColor: bgColor,
              ),
              child: Opacity(
                opacity: revealVal,
                child: Text(widget.text, style: widget.style),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TextSpoilerSheetPainter extends CustomPainter {
  final SpoilerSpriteSheet sheet;
  final int frame;
  final double revealProgress;
  final Color bgColor;

  _TextSpoilerSheetPainter({
    required this.sheet,
    required this.frame,
    required this.revealProgress,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress >= 1.0) return;
    final opacity = 1.0 - revealProgress;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = bgColor.withValues(alpha: opacity),
    );

    final src = sheet.frameRect(frame.clamp(0, 59));
    final tile = sheet.tileSize;
    final paint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, opacity * 0.7)
      ..blendMode = BlendMode.plus;

    final fullTilesX = (size.width / tile).floor();
    final fullTilesY = (size.height / tile).floor();
    final edgeW = size.width - fullTilesX * tile;
    final edgeH = size.height - fullTilesY * tile;

    for (int ty = 0; ty < fullTilesY; ty++) {
      for (int tx = 0; tx < fullTilesX; tx++) {
        canvas.drawImageRect(sheet.image, src,
            Rect.fromLTWH(tx * tile, ty * tile, tile, tile), paint);
      }
      if (edgeW > 0) {
        canvas.drawImageRect(sheet.image, Rect.fromLTWH(src.left, src.top, edgeW, tile),
            Rect.fromLTWH(fullTilesX * tile, ty * tile, edgeW, tile), paint);
      }
    }
    if (edgeH > 0) {
      final edgeSrcH = Rect.fromLTWH(src.left, src.top, tile, edgeH);
      for (int tx = 0; tx < fullTilesX; tx++) {
        canvas.drawImageRect(sheet.image, edgeSrcH,
            Rect.fromLTWH(tx * tile, fullTilesY * tile, tile, edgeH), paint);
      }
      if (edgeW > 0) {
        canvas.drawImageRect(sheet.image, Rect.fromLTWH(src.left, src.top, edgeW, edgeH),
            Rect.fromLTWH(fullTilesX * tile, fullTilesY * tile, edgeW, edgeH), paint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_TextSpoilerSheetPainter old) =>
      old.frame != frame || old.revealProgress != revealProgress;
}

bool _isTgsSticker(CachedMessage m) {
  if (m.mediaType != 6) return false;
  final path = m.mediaLocalPath.toLowerCase();
  if (path.endsWith('.tgs')) return true;
  return m.mediaMimeType == 'application/x-tgsticker';
}

bool _isWebmSticker(CachedMessage m) {
  if (m.mediaType != 6) return false;
  final path = m.mediaLocalPath.toLowerCase();
  if (path.endsWith('.webm')) return true;
  return m.mediaMimeType == 'video/webm+sticker' || m.mediaMimeType == 'video/webm';
}

/// Renders photos, videos, stickers, GIFs as visual thumbnails.
/// Spec §6: Four-tier progressive loading: full → thumbnail → small → blurred inline placeholder.
/// Tiers (highest to lowest quality):
///   1. Full image (mediaLocalPath) — downloaded file
///   2. Sharp thumbnail (mediaThumbB64) — inline stripped thumb, displayed sharp
///   3. Blurred placeholder (mediaThumbB64 + gaussian blur) — immediate visual
///   4. Icon placeholder — no image data available
class _VisualMedia extends StatefulWidget {
  final CachedMessage message;
  final ThemeData theme;
  final bool showOverlayInfo;
  final bool isOutgoing;
  final bool isDark;
  final bool isSelected;
  final bool isScheduledView;
  final List<CachedMessage> allMessages;

  const _VisualMedia({
    required this.message,
    required this.theme,
    this.showOverlayInfo = false,
    this.isOutgoing = false,
    this.isDark = false,
    this.isSelected = false,
    this.isScheduledView = false,
    this.allMessages = const [],
  });

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  State<_VisualMedia> createState() => _VisualMediaState();
}

class _VisualMediaState extends State<_VisualMedia> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _fullImageLoaded = false;
  Uint8List? _thumbBytes;
  String _lastThumbB64 = '';
  bool _spoilerRevealed = false;
  late AnimationController _spoilerRevealCtrl;

  // §35.25: Upload progress spinner.
  late AnimationController _uploadSpinController;

  // §6.8: Video note auto-play state.
  Player? _vnPlayer;
  VideoController? _vnCtrl;
  bool _vnMuted = true;
  double _vnProgress = 0.0;
  StreamSubscription? _vnPosSub;
  StreamSubscription? _vnDurSub;
  Duration _vnPosition = Duration.zero;
  Duration _vnDuration = Duration.zero;
  bool _vnVisible = false;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _uploadSpinController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _spoilerRevealCtrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..addListener(() { if (mounted) setState(() {}); });
    if (widget.message.mediaSpoiler) {
      SpoilerRevealManager.instance.addListener(_onHideMediaSpoiler);
    }
    _decodeThumb();
    if (widget.message.mediaLocalPath.isNotEmpty) {
      _fullImageLoaded = true;
      _fadeController.value = 1.0;
    }
    _syncUploadSpinner();
    _initVideoNoteIfNeeded();
  }

  @override
  void didUpdateWidget(_VisualMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.mediaThumbB64 != oldWidget.message.mediaThumbB64) {
      _decodeThumb();
    }
    if (widget.message.mediaLocalPath.isNotEmpty && !_fullImageLoaded) {
      _fullImageLoaded = true;
      _fadeController.forward(from: 0.0);
    }
    _syncUploadSpinner();
    _initVideoNoteIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.message.mediaType == 5) {
      _scrollPosition?.removeListener(_checkVideoNoteVisibility);
      _scrollPosition = Scrollable.maybeOf(context)?.position;
      _scrollPosition?.addListener(_checkVideoNoteVisibility);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkVideoNoteVisibility();
      });
    }
  }

  void _checkVideoNoteVisibility() {
    if (_vnPlayer == null || !mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize || !renderBox.attached) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;
    final visibleTop = position.dy.clamp(0.0, screenHeight);
    final visibleBottom = (position.dy + size.height).clamp(0.0, screenHeight);
    final visibleFraction = size.height > 0 ? (visibleBottom - visibleTop) / size.height : 0.0;
    final shouldBeVisible = visibleFraction > 0.3;
    if (shouldBeVisible && !_vnVisible) {
      _vnVisible = true;
      _vnPlayer?.play();
    } else if (!shouldBeVisible && _vnVisible) {
      _vnVisible = false;
      _vnPlayer?.pause();
    }
  }

  void _initVideoNoteIfNeeded() {
    if (widget.message.mediaType != 5 ||
        widget.message.mediaLocalPath.isEmpty ||
        _vnPlayer != null) return;
    final player = Player();
    _vnPlayer = player;
    _vnCtrl = VideoController(player);
    player.setVolume(0);
    player.setPlaylistMode(PlaylistMode.loop);
    _vnPosSub = player.stream.position.listen((pos) {
      if (!mounted) return;
      _vnPosition = pos;
      _updateVnProgress();
    });
    _vnDurSub = player.stream.duration.listen((dur) {
      if (!mounted) return;
      _vnDuration = dur;
      _updateVnProgress();
    });
    player.open(Media(widget.message.mediaLocalPath), play: false);
  }

  void _updateVnProgress() {
    final dur = _vnDuration.inMilliseconds;
    final pos = _vnPosition.inMilliseconds;
    final p = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    if ((p - _vnProgress).abs() > 0.005) {
      setState(() => _vnProgress = p);
    }
  }

  void _toggleVideoNoteSound() {
    if (_vnPlayer == null) return;
    setState(() {
      _vnMuted = !_vnMuted;
      _vnPlayer!.setVolume(_vnMuted ? 0 : 100);
    });
  }

  void _disposeVideoNote() {
    _vnPosSub?.cancel();
    _vnDurSub?.cancel();
    _vnPosSub = null;
    _vnDurSub = null;
    _vnPlayer?.dispose();
    _vnPlayer = null;
    _vnCtrl = null;
  }

  void _decodeThumb() {
    if (widget.message.mediaThumbB64.isNotEmpty &&
        widget.message.mediaThumbB64 != _lastThumbB64) {
      try {
        _thumbBytes = base64Decode(widget.message.mediaThumbB64);
        _lastThumbB64 = widget.message.mediaThumbB64;
      } catch (_) {
        _thumbBytes = null;
      }
    }
  }

  bool get _isUploading =>
      widget.isOutgoing &&
      widget.message.status == MsgStatus.sending &&
      widget.message.hasMedia &&
      widget.message.mediaType != 6 &&
      widget.message.mediaType != 5;

  void _syncUploadSpinner() {
    if (_isUploading) {
      if (!_uploadSpinController.isAnimating) _uploadSpinController.repeat();
    } else {
      if (_uploadSpinController.isAnimating) _uploadSpinController.stop();
    }
  }

  void _onHideMediaSpoiler() {
    if (_spoilerRevealed && mounted) {
      setState(() {
        _spoilerRevealed = false;
        _spoilerRevealCtrl.value = 0.0;
      });
    }
  }

  @override
  void dispose() {
    if (widget.message.mediaSpoiler) {
      SpoilerRevealManager.instance.removeListener(_onHideMediaSpoiler);
    }
    _scrollPosition?.removeListener(_checkVideoNoteVisibility);
    _scrollPosition = null;
    _disposeVideoNote();
    _fadeController.dispose();
    _uploadSpinController.dispose();
    _spoilerRevealCtrl.dispose();
    super.dispose();
  }

  static Widget _clipForMediaType(int mediaType, {required Widget child}) {
    if (mediaType == 5) return ClipOval(child: child);
    if (mediaType == 6) return child;
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = widget.theme;
    final vmPalette = context.palette;

    final wm = context.watch<AppState>().wideMultiplier;
    final double baseMax = (wm - 1.0).abs() > 0.01
        ? (_MessageBubbleState._baseMaxWidth * wm).roundToDouble()
        : _MessageBubbleState._baseMaxWidth;
    final bool isGif = message.mediaType == 7;
    final double maxW = isGif ? 320.0 : baseMax;
    final double maxH = isGif ? 1080.0 : baseMax;
    double displayWidth = maxW;
    double displayHeight = maxW * 287.0 / baseMax;
    if (message.mediaWidth > 0 && message.mediaHeight > 0) {
      final aspect = message.mediaWidth / message.mediaHeight;
      if (aspect >= 1) {
        displayWidth = maxW;
        displayHeight = maxW / aspect;
      } else {
        displayHeight = maxH;
        displayWidth = maxH * aspect;
        if (displayWidth > maxW) {
          displayWidth = maxW;
          displayHeight = maxW / aspect;
        }
      }
      displayWidth = displayWidth.clamp(100.0, maxW);
      displayHeight = displayHeight.clamp(100.0, maxH);
    }

    // Sticker: smaller, no background.
    // Spec §6: 224px max for static/animated, 256px for emoji (premium) stickers.
    if (message.mediaType == 6) {
      final stickerMax = message.stickerPremium ? 256.0 : 224.0;
      displayWidth = displayWidth.clamp(100, stickerMax);
      displayHeight = displayHeight.clamp(100, stickerMax);
    }

    // §6.8: Video notes (round video) — circular, max 360px diameter.
    if (message.mediaType == 5) {
      final d = displayWidth.clamp(100.0, 360.0);
      displayWidth = d;
      displayHeight = d;
    }

    // §6.6: Premium sticker effect bounding box = stickerSize × 1.49.
    // kPremiumMultiplier = 1 + 0.245 * 2 = 1.49
    final isPremiumSticker = message.mediaType == 6 && message.stickerPremium;
    final effectsPowerSave = context.read<AppState>().powerSaving(AppState.kPowerSavingChatEffects);
    const kPremiumMultiplier = 1.49;
    final showEffect = isPremiumSticker && !effectsPowerSave;
    final effectWidth = showEffect ? displayWidth * kPremiumMultiplier : displayWidth;
    final effectHeight = showEffect ? displayHeight * kPremiumMultiplier : displayHeight;

    final hasFullImage = message.mediaLocalPath.isNotEmpty;
    final hasThumb = _thumbBytes != null;
    final hasSpoiler = message.mediaSpoiler && !_spoilerRevealed;
    final revealProgress = _spoilerRevealCtrl.value;
    final isRevealing = hasSpoiler && revealProgress > 0;

    // §6/§20: tap opens media viewer for photo/video/gif (not sticker/videonote).
    // Don't open viewer when spoiler is active — tap reveals spoiler instead.
    final canOpenViewer = !hasSpoiler &&
        (message.mediaType == 1 ||
            message.mediaType == 2 ||
            message.mediaType == 7) &&
        message.mediaLocalPath.isNotEmpty;

    final canOpenStickerPack = message.mediaType == 6;
    final isVideoNote = message.mediaType == 5;
    final vnPlaying = isVideoNote && _vnCtrl != null;

    return Builder(
      builder: (thumbContext) => GestureDetector(
      onTap: vnPlaying
          ? _toggleVideoNoteSound
          : canOpenViewer
              ? () {
                  final box = thumbContext.findRenderObject() as RenderBox?;
                  final sourceRect = box != null
                      ? box.localToGlobal(Offset.zero) & box.size
                      : null;
                  MediaViewer.open(
                    context,
                    message: message,
                    allMessages: widget.allMessages,
                    sourceRect: sourceRect,
                  );
                }
              : canOpenStickerPack
                  ? () => StickerPackViewer.show(context, message)
                  : null,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: effectWidth,
        height: effectHeight,
        child: Center(
        child: Transform.flip(
        flipX: showEffect && !widget.isOutgoing,
        child: _clipForMediaType(
        message.mediaType,
        child: SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // --- Tier 3/4: Blurred thumbnail or icon placeholder (base layer) ---
              // When spoiler is active, always keep thumb blurred regardless of full image.
              if (hasThumb)
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: (hasFullImage && !hasSpoiler) ? 0 : 10,
                    sigmaY: (hasFullImage && !hasSpoiler) ? 0 : 10,
                    tileMode: TileMode.decal,
                  ),
                  child: Image.memory(
                    _thumbBytes!,
                    width: displayWidth,
                    height: displayHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(displayWidth, displayHeight),
                  ),
                )
              else
                _placeholder(displayWidth, displayHeight),

              // --- Tier 1: Full image/video (crossfades in over thumbnail) ---
              if (hasFullImage && (!hasSpoiler || isRevealing) && message.mediaType == 7)
                Positioned.fill(
                  child: Opacity(
                    opacity: isRevealing ? revealProgress : 1.0,
                    child: _GifPlayer(
                      filePath: message.mediaLocalPath,
                      width: displayWidth,
                      height: displayHeight,
                    ),
                  ),
                )
              // §6.8: Video notes auto-play muted inline.
              else if (vnPlaying)
                Positioned.fill(
                  child: Video(
                    controller: _vnCtrl!,
                    width: displayWidth,
                    height: displayHeight,
                    fit: BoxFit.cover,
                    controls: NoVideoControls,
                  ),
                )
              else if (hasFullImage && !hasSpoiler && _isTgsSticker(message))
                Positioned.fill(
                  child: _TgsStickerPlayer(
                    filePath: message.mediaLocalPath,
                    width: displayWidth,
                    height: displayHeight,
                  ),
                )
              else if (hasFullImage && !hasSpoiler && _isWebmSticker(message))
                Positioned.fill(
                  child: _WebmStickerPlayer(
                    filePath: message.mediaLocalPath,
                    width: displayWidth,
                    height: displayHeight,
                  ),
                )
              else if (hasFullImage && (!hasSpoiler || isRevealing))
                AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (_, child) => Opacity(
                    opacity: isRevealing ? revealProgress : _fadeAnimation.value,
                    child: child,
                  ),
                  child: Image.file(
                    File(message.mediaLocalPath),
                    width: displayWidth,
                    height: displayHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox.shrink(),
                  ),
                ),

              // §35.25: Download overlay for photos/videos/GIFs — radial progress + cancel.
              if (!hasFullImage && message.mediaType != 6 && message.mediaType != 5) ...[
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.3)),
                ),
                Positioned.fill(
                  child: Center(
                    child: Builder(builder: (ctx) {
                      final dlState = message.mediaDownloadState;
                      final isDownloading = dlState == 1;
                      final isFailed = dlState == 3;
                      final progress = ctx.watch<ChatState>().getDownloadProgress(message.msgId);
                      return GestureDetector(
                        onTap: () {
                          if (isDownloading) {
                            ctx.read<EngineService>().cancelDownload(
                                message.accountId, message.chatId, message.msgId);
                          } else if (!isFailed) {
                            ctx.read<ChatState>().requestDownload(message);
                          }
                        },
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (isDownloading)
                                CustomPaint(
                                  size: const Size(44, 44),
                                  painter: _DownloadProgressPainter(
                                    progress: progress?.progress ?? 0,
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                ),
                              Icon(
                                isDownloading ? Icons.close : Icons.arrow_downward,
                                color: Colors.white,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
              // §35.25: Upload progress overlay for outgoing media being uploaded.
              if (_isUploading && hasFullImage) ...[
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.3)),
                ),
                Positioned.fill(
                  child: Center(
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _uploadSpinController,
                            builder: (_, __) => CustomPaint(
                              size: const Size(44, 44),
                              painter: _IndeterminateProgressPainter(
                                rotation: _uploadSpinController.value * 2 * math.pi,
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const Icon(Icons.close, color: Colors.white, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              // Video overlay: centered play button (not for GIFs — they auto-play).
              if (message.mediaType == 2 && hasFullImage && !_isUploading)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              // §6 GIF corner badge — top-right "GIF" label.
              if (message.mediaType == 7)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'GIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              // Duration badge for video — spec §6: bottom-right, semi-transparent bg, duration + file size.
              if (message.mediaType == 2 && message.mediaDuration > 0)
                Positioned(
                  bottom: widget.showOverlayInfo ? 28 : 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      message.mediaFileSize > 0
                          ? '${_VisualMedia._formatDuration(message.mediaDuration)}, ${message.mediaSizeLabel}'
                          : _VisualMedia._formatDuration(message.mediaDuration),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              // §6.8: Duration badge for round video — bottom-center.
              if (message.mediaType == 5 && message.mediaDuration > 0)
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _VisualMedia._formatDuration(message.mediaDuration),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              // Video note: thin circular border atop the clipped content.
              if (message.mediaType == 5)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              // §6.8: Progress arc overlay for round video playback.
              if (message.mediaType == 5 && _vnProgress > 0)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _VideoNoteProgressPainter(
                      progress: _vnProgress,
                      color: vmPalette.msgInBg,
                    ),
                  ),
                ),
              // §6.8: Mute indicator — small icon bottom-left when playing.
              if (vnPlaying)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _vnMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              // Spec §6: enlarge button in bottom-right for large photos.
              // Shows expand icon as visual affordance; tapping photo already opens viewer.
              if (message.mediaType == 1 &&
                  hasFullImage &&
                  displayWidth >= 150 &&
                  displayHeight >= 150)
                Positioned(
                  bottom: widget.showOverlayInfo ? 28 : 4,
                  right: 4,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.open_in_full,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              // Spec §5: media-overlay bottom info — translucent bg, white text/icons.
              // msgDateImgPadding 8/2, msgDateImgDelta 4px from corner, msgDateImgBg #00000054.
              if (widget.showOverlayInfo)
                Positioned(
                  bottom: 4, // msgDateImgDelta
                  right: 4,  // msgDateImgDelta
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // msgDateImgPadding
                    decoration: BoxDecoration(
                      color: vmPalette.msgDateImgBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.views > 0) ...[
                          SizedBox(width: 20, height: 11,
                            child: CustomPaint(painter: _ViewsIconPainter(color: vmPalette.historyIconFgInverted))),
                          const SizedBox(width: 8),
                          Text(_MessageBubbleState._formatCount(message.views),
                              style: TextStyle(fontSize: 13, color: vmPalette.historyIconFgInverted)),
                        ],
                        if (message.forwards > 0) ...[
                          const SizedBox(width: 8),
                          SizedBox(width: 20, height: 11,
                            child: CustomPaint(painter: _ForwardsIconPainter(color: vmPalette.historyIconFgInverted))),
                          const SizedBox(width: 8),
                          Text(_MessageBubbleState._formatCount(message.forwards),
                              style: TextStyle(fontSize: 13, color: vmPalette.historyIconFgInverted)),
                        ],
                        ..._MessageBubbleState._buildDeletedEditedMarks(
                          message: message,
                          color: vmPalette.historyIconFgInverted,
                          appState: context.read<AppState>(),
                        ),
                        if (widget.isScheduledView && message.isScheduled)
                          TelegramTooltip(
                            message: _MessageBubbleState._scheduledTooltip(message),
                            child: Text(
                              _MessageBubbleState._formatScheduledTime(message),
                              style: TextStyle(fontSize: 13, color: vmPalette.historyIconFgInverted),
                            ),
                          )
                        else
                          Text(
                            _MessageBubbleState._buildTimeText(message, context.read<AppState>()),
                            style: TextStyle(fontSize: 13, color: vmPalette.historyIconFgInverted),
                          ),
                        if (widget.isOutgoing && !widget.isScheduledView) ...[
                          const SizedBox(width: 4),
                          _StatusIcon(
                            status: message.status,
                            theme: theme,
                            isOutgoing: true,
                            isDark: widget.isDark,
                            inverted: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              // §44.2: Media spoiler particle overlay with cross-fade reveal
              if (message.mediaSpoiler && !_spoilerRevealed)
                Positioned.fill(
                  child: _MediaSpoilerOverlay(
                    width: displayWidth,
                    height: displayHeight,
                    revealProgress: revealProgress,
                    onReveal: () {
                      _spoilerRevealCtrl.forward(from: 0.0).then((_) {
                        if (mounted) setState(() => _spoilerRevealed = true);
                      });
                    },
                  ),
                ),
              // §6.6: Sticker selection overlay — msgStickerOverlay tint
              if (message.mediaType == 6 && widget.isSelected)
                Positioned.fill(
                  child: ColoredBox(
                    color: vmPalette.msgStickerOverlay,
                  ),
                ),
            ],
          ),
        ),
      ),  // _clipForMediaType
      ),  // Transform.flip (§6.6 incoming premium sticker mirror)
      ),  // Center
      ),  // outer SizedBox (effectWidth × effectHeight)
    ),
    ),  // Builder
    );
  }

  Widget _placeholder(double width, double height) {
    final message = widget.message;
    final theme = widget.theme;
    final icon = switch (message.mediaType) {
      1 => Icons.photo,
      2 => Icons.videocam,
      5 => Icons.videocam,
      6 => Icons.emoji_emotions,
      7 => Icons.gif,
      _ => Icons.image,
    };
    final label = switch (message.mediaType) {
      1 => 'Photo',
      2 => 'Video',
      5 => 'Video message',
      6 => 'Sticker',
      7 => 'GIF',
      _ => 'Media',
    };
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: theme.textTheme.bodySmall?.color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
          if (message.mediaSizeLabel.isNotEmpty)
            Text(message.mediaSizeLabel, style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
        ],
      ),
    );
  }

}

class _GifPlayer extends StatefulWidget {
  final String filePath;
  final double width;
  final double height;

  const _GifPlayer({
    required this.filePath,
    required this.width,
    required this.height,
  });

  @override
  State<_GifPlayer> createState() => _GifPlayerState();
}

class _GifPlayerState extends State<_GifPlayer> {
  Player? _player;
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    final player = Player();
    _player = player;
    _controller = VideoController(player);
    player.setVolume(0);
    player.setPlaylistMode(PlaylistMode.loop);
    player.open(Media(widget.filePath));
  }

  @override
  void didUpdateWidget(_GifPlayer old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      _dispose();
      _initPlayer();
    }
  }

  void _dispose() {
    _player?.dispose();
    _player = null;
    _controller = null;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const SizedBox.shrink();
    return Video(
      controller: _controller!,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      controls: NoVideoControls,
    );
  }
}

class _StickerCache {
  static const _maxCompositions = 30;
  static final _compositions = <String, LottieComposition>{};
  static final _progress = <String, double>{};
  static final _webmPositions = <String, Duration>{};

  static LottieComposition? getComposition(String path) {
    final comp = _compositions.remove(path);
    if (comp != null) _compositions[path] = comp;
    return comp;
  }

  static void putComposition(String path, LottieComposition comp) {
    _compositions.remove(path);
    _compositions[path] = comp;
    while (_compositions.length > _maxCompositions) {
      _compositions.remove(_compositions.keys.first);
    }
  }

  static double? getProgress(String path) => _progress[path];
  static void putProgress(String path, double value) => _progress[path] = value;

  static Duration? getWebmPosition(String path) => _webmPositions[path];
  static void putWebmPosition(String path, Duration pos) => _webmPositions[path] = pos;
}

class _TgsStickerPlayer extends StatefulWidget {
  final String filePath;
  final double width;
  final double height;

  const _TgsStickerPlayer({
    required this.filePath,
    required this.width,
    required this.height,
  });

  @override
  State<_TgsStickerPlayer> createState() => _TgsStickerPlayerState();
}

class _TgsStickerPlayerState extends State<_TgsStickerPlayer>
    with SingleTickerProviderStateMixin {
  LottieComposition? _composition;
  AnimationController? _animController;

  @override
  void initState() {
    super.initState();
    _loadTgs();
  }

  @override
  void didUpdateWidget(_TgsStickerPlayer old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      _saveProgress();
      _animController?.dispose();
      _animController = null;
      _composition = null;
      _loadTgs();
    }
  }

  Future<void> _loadTgs() async {
    final cached = _StickerCache.getComposition(widget.filePath);
    if (cached != null) {
      if (mounted) _setupAnimation(cached);
      return;
    }
    try {
      final compressed = await File(widget.filePath).readAsBytes();
      final decompressed = gzip.decode(compressed);
      final composition = await LottieComposition.fromBytes(
        Uint8List.fromList(decompressed),
      );
      _StickerCache.putComposition(widget.filePath, composition);
      if (mounted) _setupAnimation(composition);
    } catch (_) {}
  }

  void _setupAnimation(LottieComposition composition) {
    setState(() {
      _composition = composition;
      _animController = AnimationController(
        vsync: this,
        duration: composition.duration,
      );
      final progress = _StickerCache.getProgress(widget.filePath);
      if (progress != null) _animController!.value = progress;
      _animController!.repeat();
    });
  }

  void _saveProgress() {
    if (_animController != null) {
      _StickerCache.putProgress(widget.filePath, _animController!.value);
    }
  }

  @override
  void dispose() {
    _saveProgress();
    _animController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_composition == null || _animController == null) {
      return const SizedBox.shrink();
    }
    final powerSaving = context.read<AppState>().powerSaving(AppState.kPowerSavingStickersChat);
    if (powerSaving && _animController!.isAnimating) {
      _animController!.stop();
    } else if (!powerSaving && !_animController!.isAnimating) {
      _animController!.repeat();
    }
    return Lottie(
      composition: _composition!,
      controller: _animController,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.contain,
    );
  }
}

class _WebmStickerPlayer extends StatefulWidget {
  final String filePath;
  final double width;
  final double height;

  const _WebmStickerPlayer({
    required this.filePath,
    required this.width,
    required this.height,
  });

  @override
  State<_WebmStickerPlayer> createState() => _WebmStickerPlayerState();
}

class _WebmStickerPlayerState extends State<_WebmStickerPlayer> {
  Player? _player;
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    final player = Player();
    _player = player;
    _controller = VideoController(player);
    player.setVolume(0);
    player.setPlaylistMode(PlaylistMode.loop);
    player.open(Media(widget.filePath));
    final cachedPos = _StickerCache.getWebmPosition(widget.filePath);
    if (cachedPos != null && cachedPos > Duration.zero) {
      player.stream.playing.first.then((_) {
        if (_player == player) player.seek(cachedPos);
      });
    }
  }

  @override
  void didUpdateWidget(_WebmStickerPlayer old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      _saveAndDispose();
      _initPlayer();
    }
  }

  void _saveAndDispose() {
    if (_player != null) {
      _StickerCache.putWebmPosition(widget.filePath, _player!.state.position);
      _player!.dispose();
    }
    _player = null;
    _controller = null;
  }

  @override
  void dispose() {
    _saveAndDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const SizedBox.shrink();
    final powerSaving = context.read<AppState>().powerSaving(AppState.kPowerSavingStickersChat);
    if (powerSaving && _player != null) {
      _player!.pause();
    } else if (!powerSaving && _player != null && !_player!.state.playing) {
      _player!.play();
    }
    return Video(
      controller: _controller!,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      controls: NoVideoControls,
    );
  }
}

class _VoiceIndicator extends StatefulWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _VoiceIndicator({required this.message, required this.theme});

  @override
  State<_VoiceIndicator> createState() => _VoiceIndicatorState();
}

class _VoiceIndicatorState extends State<_VoiceIndicator> {
  double? _hoverX;
  bool _transcribing = false;
  String? _transcriptionText;
  bool _transcriptionExpanded = true;

  void _onPlayPause() {
    final msg = widget.message;
    final audio = context.read<AudioService>();

    if (msg.mediaLocalPath.isEmpty && msg.mediaDownloadState != 1) {
      context.read<ChatState>().requestDownload(msg);
      return;
    }
    if (msg.mediaLocalPath.isEmpty) return;

    audio.playVoice(msg.mediaLocalPath, msg.msgId,
      chatId: msg.chatId,
      performer: msg.senderName,
      msgTimestamp: msg.timestamp,
      accountId: msg.accountId,
      docId: msg.mediaRemoteRef,
      mediaExtra: msg.mediaExtra,
    );
  }

  void _onWaveformTap(double localX, double totalWidth) {
    if (totalWidth <= 0) return;
    final audio = context.read<AudioService>();
    final msg = widget.message;

    if (!audio.isActiveMsg(msg.msgId)) {
      if (msg.mediaLocalPath.isEmpty) return;
      audio.playVoice(msg.mediaLocalPath, msg.msgId,
        chatId: msg.chatId,
        performer: msg.senderName,
        msgTimestamp: msg.timestamp,
        accountId: msg.accountId,
        docId: msg.mediaRemoteRef,
        mediaExtra: msg.mediaExtra,
      ).then((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          audio.seek(localX / totalWidth);
        });
      });
      return;
    }
    audio.seek(localX / totalWidth);
  }

  void _onTranscribe() async {
    if (_transcribing) return;
    if (_transcriptionText != null) {
      setState(() { _transcriptionExpanded = !_transcriptionExpanded; });
      return;
    }
    setState(() { _transcribing = true; });
    final engine = context.read<EngineService>();
    final msg = widget.message;
    var result = await engine.transcribeAudio(msg.accountId, msg.chatId, msg.msgId);
    if (!mounted) return;
    if (result == null) {
      setState(() { _transcribing = false; });
      return;
    }
    if (result.pending) {
      var delay = const Duration(seconds: 2);
      const maxDelay = Duration(seconds: 15);
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future.delayed(delay);
        if (!mounted) return;
        result = await engine.transcribeAudio(msg.accountId, msg.chatId, msg.msgId);
        if (!mounted) return;
        if (result == null || !result.pending) break;
        delay = Duration(milliseconds: (delay.inMilliseconds * 1.5).toInt().clamp(0, maxDelay.inMilliseconds));
      }
    }
    if (!mounted) return;
    setState(() {
      _transcribing = false;
      _transcriptionText = result?.text ?? '';
    });
  }

  String _formatDurationMs(Duration d) {
    final totalSecs = d.inSeconds;
    final m = totalSecs ~/ 60;
    final s = totalSecs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isOut = widget.message.isOutgoing;
    final waveform = widget.message.mediaWaveform;
    final hasWaveform = waveform.isNotEmpty;
    final audio = context.watch<AudioService>();
    final isActive = audio.isActiveMsg(widget.message.msgId);
    final isPlaying = audio.isPlayingMsg(widget.message.msgId);
    final progress = isActive ? audio.progress : 0.0;
    final downloading = widget.message.mediaDownloadState == 1;
    final dlProgress = context.watch<ChatState>().getDownloadProgress(widget.message.msgId);
    final accentColor = widget.theme.colorScheme.primary;
    final voicePalette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: downloading
                    ? () => context.read<EngineService>().cancelDownload(
                          widget.message.accountId, widget.message.chatId, widget.message.msgId)
                    : _onPlayPause,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (downloading)
                        CustomPaint(
                          size: const Size(44, 44),
                          painter: _DownloadProgressPainter(
                            progress: dlProgress?.progress ?? 0,
                            strokeWidth: 2,
                            color: voicePalette.activeButtonFg,
                          ),
                        ),
                      Icon(
                        downloading ? Icons.close : (isPlaying ? Icons.pause : Icons.play_arrow),
                        size: 24,
                        color: voicePalette.activeButtonFg,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasWaveform)
                      SizedBox(
                        height: 17,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            return MouseRegion(
                              onHover: (event) {
                                setState(() { _hoverX = event.localPosition.dx; });
                              },
                              onExit: (_) {
                                setState(() { _hoverX = null; });
                              },
                              child: GestureDetector(
                                onTapDown: (details) {
                                  _onWaveformTap(details.localPosition.dx, width);
                                },
                                onHorizontalDragUpdate: (details) {
                                  if (isActive) {
                                    audio.seek(details.localPosition.dx / width);
                                  }
                                },
                                child: CustomPaint(
                                  size: Size(width, 17),
                                  painter: _WaveformPainter(
                                    samples: waveform,
                                    isOutgoing: isOut,
                                    progress: progress,
                                    hoverX: _hoverX,
                                    playedColor: isOut ? voicePalette.msgWaveformOutActive : voicePalette.msgWaveformInActive,
                                    unplayedColor: isOut ? voicePalette.msgWaveformOutInactive : voicePalette.msgWaveformInInactive,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      Text(
                        'Voice message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: widget.theme.textTheme.bodyMedium,
                      ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (downloading && dlProgress != null && dlProgress.bytesTotal > 0)
                          Text(
                            _formatDownloadProgress(dlProgress.bytesRecv, dlProgress.bytesTotal),
                            style: TextStyle(fontSize: 12, color: widget.theme.textTheme.bodySmall?.color),
                          )
                        else if (widget.message.mediaDownloadState == 3)
                          Text(
                            'Failed',
                            style: TextStyle(fontSize: 12, color: widget.theme.colorScheme.error),
                          )
                        else ...[
                          Text(
                            isActive && audio.duration.inMilliseconds > 0
                                ? _formatDurationMs(audio.position)
                                : widget.message.mediaDuration > 0
                                    ? _VisualMedia._formatDuration(widget.message.mediaDuration)
                                    : '',
                            style: TextStyle(fontSize: 12, color: widget.theme.textTheme.bodySmall?.color),
                          ),
                          if (isActive && audio.duration.inMilliseconds > 0) ...[
                            Text(
                              ' / ${_formatDurationMs(audio.duration)}',
                              style: TextStyle(fontSize: 12, color: widget.theme.textTheme.bodySmall?.color),
                            ),
                          ] else if (widget.message.mediaDuration > 0 && widget.message.mediaSizeLabel.isNotEmpty) ...[
                            Text(' · ', style: TextStyle(fontSize: 12, color: widget.theme.textTheme.bodySmall?.color)),
                            Text(
                              widget.message.mediaSizeLabel,
                              style: TextStyle(fontSize: 12, color: widget.theme.textTheme.bodySmall?.color),
                            ),
                          ] else if (widget.message.mediaSizeLabel.isNotEmpty) ...[
                            Text(
                              widget.message.mediaSizeLabel,
                              style: TextStyle(fontSize: 12, color: widget.theme.textTheme.bodySmall?.color),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTranscribe,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: _transcribing
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.theme.colorScheme.primary.withValues(alpha: 0.6),
                          ),
                        )
                      : Icon(
                          _transcriptionText != null
                              ? (_transcriptionExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down)
                              : Icons.text_fields,
                          size: 18,
                          color: widget.theme.colorScheme.primary.withValues(alpha: 0.7),
                        ),
                ),
              ),
            ],
          ),
          if (_transcriptionText != null && _transcriptionExpanded && _transcriptionText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 4, right: 4),
              child: Text(
                _transcriptionText!,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.theme.textTheme.bodyMedium?.color,
                ),
              ),
            ),
          if (_transcriptionText != null && _transcriptionExpanded && _transcriptionText!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 4, right: 4),
              child: Text(
                'Transcription unavailable',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: widget.theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<int> samples;
  final bool isOutgoing;
  final double progress;
  final double? hoverX;
  final Color playedColor;
  final Color unplayedColor;

  static const double _barWidth = 2.0;
  static const double _barGap = 1.0;
  static const double _minHeight = 3.0;
  static const double _maxHeight = 17.0;

  _WaveformPainter({
    required this.samples,
    required this.isOutgoing,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    this.hoverX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final barStep = _barWidth + _barGap;
    final barCount = math.min(samples.length, (size.width / barStep).floor());
    if (barCount <= 0) return;

    final bucketSize = samples.length / barCount;
    final activeWidth = (size.width * progress).roundToDouble();

    final playedPaint = Paint()..color = playedColor;
    final unplayedPaint = Paint()..color = unplayedColor;

    final hoverWidth = hoverX?.clamp(0.0, size.width).roundToDouble();
    final Paint? hoverPaint = hoverWidth != null
        ? (Paint()..color = playedColor.withValues(alpha: 0.30))
        : null;
    final double hoverMin = hoverWidth != null ? math.min(activeWidth, hoverWidth) : 0;
    final double hoverMax = hoverWidth != null ? math.max(activeWidth, hoverWidth) : 0;

    for (int i = 0; i < barCount; i++) {
      final bucketStart = (i * bucketSize).floor();
      final bucketEnd = ((i + 1) * bucketSize).ceil().clamp(0, samples.length);
      int peak = 0;
      for (int j = bucketStart; j < bucketEnd; j++) {
        if (samples[j] > peak) peak = samples[j];
      }

      final barHeight = _minHeight + (peak / 31.0) * (_maxHeight - _minHeight);
      final x = i * barStep;
      final y = (_maxHeight - barHeight) / 2;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, _barWidth, barHeight),
        const Radius.circular(1),
      );

      final barRight = x + _barWidth;
      if (barRight <= activeWidth) {
        canvas.drawRRect(rrect, playedPaint);
      } else if (x >= activeWidth) {
        canvas.drawRRect(rrect, unplayedPaint);
      } else {
        final splitAt = activeWidth - x;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, splitAt, barHeight), const Radius.circular(1)),
          playedPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(activeWidth, y, _barWidth - splitAt, barHeight), const Radius.circular(1)),
          unplayedPaint,
        );
      }

      if (hoverPaint != null && barRight > hoverMin && x < hoverMax) {
        canvas.drawRRect(rrect, hoverPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.isOutgoing != isOutgoing ||
      old.samples != samples ||
      old.hoverX != hoverX ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}

/// Audio file indicator (music, podcast, etc.).
/// Spec \u00a76: plays inline with 44px play/pause button (same as voice), shows played/total.
class _AudioIndicator extends StatefulWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _AudioIndicator({required this.message, required this.theme});

  @override
  State<_AudioIndicator> createState() => _AudioIndicatorState();
}

class _AudioIndicatorState extends State<_AudioIndicator> {
  CachedMessage get message => widget.message;
  ThemeData get theme => widget.theme;

  static String _formatSongName(String filename, String title, String performer) {
    if (performer.isNotEmpty && title.isNotEmpty) {
      return '$performer \u2013 $title';
    }
    if (title.isNotEmpty) return title;
    if (performer.isNotEmpty) return performer;
    if (filename.isNotEmpty) {
      final dotIdx = filename.lastIndexOf('.');
      return dotIdx > 0 ? filename.substring(0, dotIdx) : filename;
    }
    return 'Unknown Track';
  }

  void _onPlayPause() {
    final audio = context.read<AudioService>();
    if (message.mediaLocalPath.isEmpty && message.mediaDownloadState != 1) {
      context.read<ChatState>().requestDownload(message);
      return;
    }
    if (message.mediaLocalPath.isEmpty) return;
    audio.playVoice(message.mediaLocalPath, message.msgId,
      chatId: message.chatId,
      performer: message.audioPerformer,
      title: message.audioTitle,
      msgTimestamp: message.timestamp,
      accountId: message.accountId,
      docId: message.mediaRemoteRef,
      mediaExtra: message.mediaExtra,
    );
  }

  void _onDownloadCancel() {
    context.read<EngineService>().cancelDownload(
      message.accountId, message.chatId, message.msgId,
    );
  }

  static String _formatDurationMs(Duration d) {
    final totalSecs = d.inSeconds;
    final m = totalSecs ~/ 60;
    final s = totalSecs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final songName = _formatSongName(
      message.mediaFileName, message.audioTitle, message.audioPerformer,
    );
    final hasCover = message.mediaThumbB64.isNotEmpty;
    final dlState = message.mediaDownloadState;
    final isDownloaded = dlState == 2;
    final isDownloading = dlState == 1;
    final isFailed = dlState == 3;
    final progress = context.watch<ChatState>().getDownloadProgress(message.msgId);
    final audio = context.watch<AudioService>();
    final isActive = audio.isActiveMsg(message.msgId);
    final isPlaying = audio.isPlayingMsg(message.msgId);

    String statusText;
    if (isActive) {
      final played = _formatDurationMs(audio.position);
      final total = _formatDurationMs(audio.duration);
      statusText = '$played / $total';
    } else if (isFailed) {
      statusText = 'Failed';
    } else if (isDownloading && progress != null && progress.bytesTotal > 0) {
      statusText = _formatDownloadProgress(progress.bytesRecv, progress.bytesTotal);
    } else {
      final parts = <String>[];
      if (message.mediaDuration > 0) {
        parts.add(_VisualMedia._formatDuration(message.mediaDuration));
      }
      if (message.mediaSizeLabel.isNotEmpty) {
        parts.add(message.mediaSizeLabel);
      }
      statusText = parts.join(' \u00b7 ');
    }

    return GestureDetector(
      onTap: isDownloading ? _onDownloadCancel : _onPlayPause,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(hasCover, isDownloaded, isDownloading, isActive, isPlaying, progress?.progress ?? 0),
              const SizedBox(width: 11),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      songName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (statusText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          color: isFailed ? theme.colorScheme.error : theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _playPauseIcon(bool isDownloaded, bool isDownloading, bool isActive, bool isPlaying) {
    if (isDownloading) return Icons.close;
    if (isActive && isPlaying) return Icons.pause;
    if (isDownloaded || isActive) return Icons.play_arrow;
    return Icons.arrow_downward;
  }

  Widget _buildIcon(bool hasCover, bool isDownloaded, bool isDownloading, bool isActive, bool isPlaying, double dlProgress) {
    final icon = _playPauseIcon(isDownloaded, isDownloading, isActive, isPlaying);
    if (hasCover) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: Image.memory(
                base64Decode(message.mediaThumbB64),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _defaultIcon(icon, isDownloading, dlProgress),
              ),
            ),
            ClipOval(
              child: Container(
                width: 44,
                height: 44,
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
            if (isDownloading)
              CustomPaint(
                size: const Size(44, 44),
                painter: _DownloadProgressPainter(
                  progress: dlProgress,
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            Icon(icon, size: 22, color: Colors.white),
          ],
        ),
      );
    }
    return _defaultIcon(icon, isDownloading, dlProgress);
  }

  Widget _defaultIcon(IconData icon, bool isDownloading, double dlProgress) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          if (isDownloading)
            CustomPaint(
              size: const Size(44, 44),
              painter: _DownloadProgressPainter(
                progress: dlProgress,
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          Icon(icon, size: 22, color: Colors.white),
        ],
      ),
    );
  }
}

class _LocationIndicator extends StatefulWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _LocationIndicator({required this.message, required this.theme});

  @override
  State<_LocationIndicator> createState() => _LocationIndicatorState();
}

class _LocationIndicatorState extends State<_LocationIndicator> {
  Timer? _ringTimer;

  CachedMessage get message => widget.message;
  ThemeData get theme => widget.theme;

  static const _kUntilOffPeriod = 0x7FFFFFFF;

  bool get _isUntilOff =>
      message.geoPeriod == 0 || message.geoPeriod >= _kUntilOffPeriod;

  double _elapsedProgress() {
    if (_isUntilOff) return 0.0;
    final period = message.geoPeriod;
    final sentMs = message.timestamp;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = (nowMs - sentMs) / 1000.0;
    return (elapsed / period).clamp(0.0, 1.0);
  }

  int _remainingMinutes() {
    final period = message.geoPeriod;
    final sentMs = message.timestamp;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = (nowMs - sentMs) / 1000.0;
    final remaining = period - elapsed;
    return (remaining / 60).ceil().clamp(0, period ~/ 60 + 1);
  }

  @override
  void initState() {
    super.initState();
    if (message.geoLive && !_isUntilOff) {
      final period = message.geoPeriod;
      final tickSecs = (period / 360).clamp(1, 86400).toInt();
      _ringTimer = Timer.periodic(Duration(seconds: tickSecs), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    super.dispose();
  }

  static String _staticMapUrl(double lat, double lng, int w, int h) {
    final zoom = 15;
    final tileX = ((lng + 180) / 360 * (1 << zoom)).floor();
    final latRad = lat * math.pi / 180;
    final tileY = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * (1 << zoom)).floor();
    return 'https://tile.openstreetmap.org/$zoom/$tileX/$tileY.png';
  }

  void _openCoordinates() {
    final lat = message.geoLat;
    final lng = message.geoLong;
    if (lat == 0.0 && lng == 0.0) return;
    final url = 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=15/$lat/$lng';
    Process.run('xdg-open', [url]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final locPalette = context.palette;
    final lat = message.geoLat;
    final lng = message.geoLong;
    final hasVenue = message.venueTitle.isNotEmpty;
    final isLive = message.geoLive;

    final wmLoc = context.watch<AppState>().wideMultiplier;
    final mapW = (wmLoc - 1.0).abs() > 0.01
        ? (_MessageBubbleState._baseMaxWidth * wmLoc).roundToDouble()
        : _MessageBubbleState._baseMaxWidth;
    final mapH = 200.0;

    return GestureDetector(
      onTap: _openCoordinates,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: mapW,
              minWidth: 100,
              maxHeight: mapH,
            ),
            child: Container(
              width: mapW,
              height: mapH,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1B2836)
                    : const Color(0xFFE8EDF2),
                borderRadius: (hasVenue || isLive)
                    ? const BorderRadius.vertical(top: Radius.circular(8))
                    : BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (lat != 0.0 || lng != 0.0)
                    Image.network(
                      _staticMapUrl(lat, lng, mapW.toInt(), mapH.toInt()),
                      width: mapW,
                      height: mapH,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _MapPlaceholder(
                        isDark: isDark, width: mapW, height: mapH,
                      ),
                    )
                  else
                    _MapPlaceholder(isDark: isDark, width: mapW, height: mapH),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_on, color: Colors.white, size: 24),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  if (isLive)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF43A047),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasVenue || isLive)
            Container(
              width: mapW,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1B2836)
                    : const Color(0xFFF5F5F5),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  if (isLive) ...[
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CustomPaint(
                        painter: _LiveLocationRingPainter(
                          progress: _elapsedProgress(),
                          ringColor: locPalette.windowActiveTextFg,
                        ),
                        child: Center(
                          child: Text(
                            _isUntilOff ? '\u221E' : '${_remainingMinutes()}',
                            style: TextStyle(
                              fontSize: _isUntilOff ? 14 : 10,
                              fontWeight: FontWeight.w600,
                              color: locPalette.windowActiveTextFg,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasVenue ? message.venueTitle : 'Live Location',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (message.venueAddress.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            message.venueAddress,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: locPalette.windowSubTextFg,
                            ),
                          ),
                        ],
                      ],
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

class _LiveLocationRingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;

  const _LiveLocationRingPainter({
    required this.progress,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 2.0) / 2;

    final bgPaint = Paint()
      ..color = ringColor.withValues(alpha: ringColor.a * 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0.0) {
      final arcPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      const startAngle = -math.pi / 2;
      final sweepAngle = -2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveLocationRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.ringColor != ringColor;
}

class _MapPlaceholder extends StatelessWidget {
  final bool isDark;
  final double width;
  final double height;
  const _MapPlaceholder({required this.isDark, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Icon(
          Icons.map_outlined,
          size: 48,
          color: isDark ? const Color(0xFF3A4A5A) : const Color(0xFFB0BEC5),
        ),
      ),
    );
  }
}

/// Contact card: circular userpic + name + phone + action buttons.
class _ContactIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _ContactIndicator({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final contactPalette = context.palette;
    final firstName = message.contactFirstName;
    final lastName = message.contactLastName;
    final fullName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
    final phone = message.contactPhone;
    final hasUser = message.contactUserId > 0;

    final accentColor = _MessageBubbleState._senderColor(
      message.contactUserId > 0 ? message.contactUserId.toString() : fullName,
      palette: contactPalette, isDark: isDark,
    );

    final initials = _initials(firstName, lastName);

    final accentBg = accentColor.withValues(alpha: isDark ? 0.12 : 0.08);
    final separatorColor = accentColor.withValues(alpha: 0.3);

    return Container(
      decoration: BoxDecoration(
        color: accentBg,
        borderRadius: BorderRadius.circular(5),
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 7, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildUserpic(initials, accentColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fullName.isNotEmpty ? fullName : 'Contact',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          _formatPhoneDisplay(phone),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: separatorColor),
          SizedBox(
            height: 36,
            child: hasUser
                ? Row(
                    children: [
                      _actionButton('Send Message', accentColor, () {
                        final chatState = context.read<ChatState>();
                        chatState.openChatById(message.contactUserId.toString());
                      }),
                      Container(width: 1, color: separatorColor),
                      _actionButton('Add Contact', accentColor, () {
                        final engine = context.read<EngineService>();
                        final appState = context.read<AppState>();
                        final accountId = appState.activeAccountId;
                        if (accountId.isNotEmpty) {
                          engine.addContact(accountId, phone, firstName, lastName);
                          showTelegramToast(context, 'Contact added');
                        }
                      }),
                    ],
                  )
                : _actionButton('View Details', accentColor, () {
                    if (phone.isNotEmpty) {
                      Process.run('xdg-open', ['tel:$phone']);
                    }
                  }),
          ),
        ],
      ),
    );
  }

  Widget _buildUserpic(String initials, Color accentColor) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accentColor,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String first, String last) {
    final f = first.isNotEmpty ? first.characters.first.toUpperCase() : '';
    final l = last.isNotEmpty ? last.characters.first.toUpperCase() : '';
    if (f.isEmpty && l.isEmpty) return '?';
    if (l.isEmpty) return f;
    return '$f$l';
  }

  static String _formatPhoneDisplay(String phone) {
    if (phone.isEmpty) return '';
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.length < 7) return phone;
    if (!digits.startsWith('+')) return '+$digits';
    return digits;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDownloadProgress(int bytesRecv, int bytesTotal) {
  if (bytesTotal <= 0) return '';
  return '${_formatBytes(bytesRecv)} / ${_formatBytes(bytesTotal)}';
}

class _DownloadProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;

  _DownloadProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_DownloadProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.color != color;
}

class _IndeterminateProgressPainter extends CustomPainter {
  final double rotation;
  final double strokeWidth;
  final Color color;

  _IndeterminateProgressPainter({
    required this.rotation,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      rotation - math.pi / 2,
      math.pi * 0.75,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_IndeterminateProgressPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.color != color;
}

/// File/document attachment indicator.
class _FileIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _FileIndicator({required this.message, required this.theme});

  static String _middleTruncate(String name, int maxLen) {
    if (name.length <= maxLen) return name;
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx < 0) {
      return '${name.substring(0, maxLen - 3)}…';
    }
    final ext = name.substring(dotIdx);
    final stem = name.substring(0, dotIdx);
    final available = maxLen - ext.length - 1;
    if (available < 4) return '${name.substring(0, maxLen - 3)}…';
    final half = available ~/ 2;
    return '${stem.substring(0, half)}…${stem.substring(stem.length - (available - half))}$ext';
  }

  void _onTap(BuildContext context) {
    final state = message.mediaDownloadState;
    if (state == 2 && message.mediaLocalPath.isNotEmpty) {
      Process.run('xdg-open', [message.mediaLocalPath]);
      return;
    }
    if (state == 1) {
      context.read<EngineService>().cancelDownload(
        message.accountId, message.chatId, message.msgId,
      );
      return;
    }
    context.read<ChatState>().requestDownload(message);
  }

  @override
  Widget build(BuildContext context) {
    final fileName = message.mediaFileName.isNotEmpty ? message.mediaFileName : 'File';
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : '';
    final displayName = _middleTruncate(fileName, 32);
    final dlState = message.mediaDownloadState;
    final isDownloading = dlState == 1;
    final isFailed = dlState == 3;
    final isLoaded = dlState == 2;
    final progress = context.watch<ChatState>().getDownloadProgress(message.msgId);

    String statusText;
    if (isFailed) {
      statusText = 'Failed';
    } else if (isDownloading && progress != null && progress.bytesTotal > 0) {
      statusText = _formatDownloadProgress(progress.bytesRecv, progress.bytesTotal);
    } else {
      statusText = message.mediaSizeLabel;
    }

    final accentColor = theme.colorScheme.primary;

    return GestureDetector(
      onTap: () => _onTap(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.insert_drive_file, size: 20, color: accentColor),
                          if (ext.isNotEmpty && ext.length <= 4)
                            Text(ext, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: accentColor)),
                        ],
                      ),
                    ),
                    if (isDownloading)
                      CustomPaint(
                        size: const Size(44, 44),
                        painter: _DownloadProgressPainter(
                          progress: progress?.progress ?? 0,
                          strokeWidth: 3,
                          color: accentColor,
                        ),
                      ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isDownloading ? Icons.close : (isLoaded ? Icons.insert_drive_file : Icons.arrow_downward),
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Flexible(
                child: Stack(
                  children: [
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                      ),
                    ),
                    if (statusText.isNotEmpty)
                      Positioned(
                        top: 34,
                        left: 0,
                        right: 0,
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            color: isFailed ? theme.colorScheme.error : theme.textTheme.bodySmall?.color,
                          ),
                        ),
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
}

/// Spec §5: Delivery status icon at exact spec sizes.
/// Clock 11×11, single-check 13×11, double-check 18×11.
/// Colors: historyOutIconFg for sent/delivered/read, historySendingOutIconFg for sending clock.
class _StatusIcon extends StatelessWidget {
  final MsgStatus status;
  final ThemeData theme;
  final bool isOutgoing;
  final bool isDark;
  final bool inverted;

  const _StatusIcon({
    required this.status,
    required this.theme,
    required this.isOutgoing,
    required this.isDark,
    this.inverted = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = inverted
        ? (status == MsgStatus.sending
            ? p.historySendingInvertedIconFg
            : p.historyIconFgInverted)
        : switch (status) {
            MsgStatus.sending => isOutgoing
                ? p.historySendingOutIconFg
                : p.historySendingInIconFg,
            MsgStatus.sent || MsgStatus.delivered || MsgStatus.read => isOutgoing
                ? p.historyOutIconFg
                : p.msgInDateFg,
            MsgStatus.failed => theme.colorScheme.error,
            _ => isOutgoing
                ? p.historyOutIconFg
                : p.msgInDateFg,
          };

    return switch (status) {
      MsgStatus.sending => SizedBox(
          width: 11, height: 11,
          child: CustomPaint(painter: _ClockPainter(color: color)),
        ),
      MsgStatus.sent => SizedBox(
          width: 13, height: 11,
          child: CustomPaint(painter: _SentCheckPainter(color: color)),
        ),
      MsgStatus.delivered || MsgStatus.read => SizedBox(
          width: 18, height: 11,
          child: CustomPaint(painter: _DoubleCheckPainter(color: color)),
        ),
      MsgStatus.failed => Icon(Icons.error_outline, size: 13, color: color),
      _ => SizedBox(
          width: 13, height: 11,
          child: CustomPaint(painter: _SentCheckPainter(color: color)),
        ),
    };
  }
}

/// Spec §5: Clock icon for sending state, 11×11px.
class _ClockPainter extends CustomPainter {
  final Color color;
  _ClockPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = (size.width - 2) / 2;
    canvas.drawCircle(Offset(cx, cy), r, paint);
    canvas.drawLine(Offset(cx, cy), Offset(cx + r * 0.45, cy - r * 0.35), paint);
    canvas.drawLine(Offset(cx, cy), Offset(cx, cy - r * 0.65), paint);
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) => color != old.color;
}

/// Spec §5: Single checkmark for sent state, 13×11px.
class _SentCheckPainter extends CustomPainter {
  final Color color;
  _SentCheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(1, size.height * 0.5)
      ..lineTo(size.width * 0.35, size.height - 1.5)
      ..lineTo(size.width - 1, 1.5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SentCheckPainter old) => color != old.color;
}

/// Spec §5: Double checkmark for delivered/read state, 18×11px.
class _DoubleCheckPainter extends CustomPainter {
  final Color color;
  _DoubleCheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p1 = Path()
      ..moveTo(1, size.height * 0.5)
      ..lineTo(size.width * 0.28, size.height - 1.5)
      ..lineTo(size.width * 0.6, 1.5);
    final p2 = Path()
      ..moveTo(size.width * 0.3, size.height * 0.5)
      ..lineTo(size.width * 0.55, size.height - 1.5)
      ..lineTo(size.width - 1, 1.5);
    canvas.drawPath(p1, paint);
    canvas.drawPath(p2, paint);
  }

  @override
  bool shouldRepaint(covariant _DoubleCheckPainter old) => color != old.color;
}

/// Spec §5: Eye icon for views count, 16×11px (history_views).
class _ViewsIconPainter extends CustomPainter {
  final Color color;
  const _ViewsIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Eye outline: two arcs meeting at left and right tips.
    final cx = size.width / 2;
    final cy = size.height / 2;
    final path = Path();
    // Upper arc.
    path.moveTo(1, cy);
    path.quadraticBezierTo(cx, cy - 5.5, size.width - 1, cy);
    // Lower arc.
    path.quadraticBezierTo(cx, cy + 5.5, 1, cy);
    canvas.drawPath(path, paint);

    // Iris: filled circle in the center.
    final irisPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 2.2, irisPaint);
  }

  @override
  bool shouldRepaint(covariant _ViewsIconPainter old) => color != old.color;
}

/// Spec §5: Share/forward icon for forwards count, 16×11px (history_replies).
class _ForwardsIconPainter extends CustomPainter {
  final Color color;
  const _ForwardsIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Forward arrow: right-pointing arrow shape.
    final cy = size.height / 2;
    final path = Path()
      ..moveTo(size.width * 0.4, 1)
      ..lineTo(size.width - 1, cy)
      ..lineTo(size.width * 0.4, size.height - 1);
    canvas.drawPath(path, paint);

    // Stem: horizontal line from arrow tip to left.
    canvas.drawLine(
      Offset(size.width - 1, cy),
      Offset(2, cy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ForwardsIconPainter old) => color != old.color;
}

// ── Isolated emoji detection + large emoji rendering (§45.2) ──

final _nativeEmojiPattern = RegExp(
  r'(?:\p{Emoji_Presentation}|\p{Emoji}️)[‍️\p{Emoji_Presentation}\p{Emoji_Modifier}\p{Emoji_Modifier_Base}\p{Emoji_Component}]*',
  unicode: true,
);

class _IsolatedEmojiInfo {
  final bool isIsolated;
  final int count;
  final List<_IsolatedEmojiItem> items;
  const _IsolatedEmojiInfo({this.isIsolated = false, this.count = 0, this.items = const []});
}

class _IsolatedEmojiItem {
  final bool isCustom;
  final int documentId;
  final String altText;
  const _IsolatedEmojiItem({this.isCustom = false, this.documentId = 0, this.altText = ''});
}

_IsolatedEmojiInfo _detectIsolatedEmoji(CachedMessage message) {
  if (message.contentText.isEmpty) return const _IsolatedEmojiInfo();
  if (message.hasMedia || message.hasWebPage || message.hasGame || message.hasInvoice) {
    return const _IsolatedEmojiInfo();
  }
  if (message.replyPreview.isNotEmpty || message.forwardFrom.isNotEmpty) {
    return const _IsolatedEmojiInfo();
  }

  List<_TextEntity> entities = const [];
  if (message.contentRich.isNotEmpty) {
    try {
      final list = jsonDecode(message.contentRich) as List;
      entities = list.map((e) => _TextEntity.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const _IsolatedEmojiInfo();
    }
  }

  final customEntities = entities.where((e) => e.type == 'custom_emoji').toList();
  final hasNonEmojiEntities = entities.any((e) =>
      e.type != 'custom_emoji' && e.type != 'bold' && e.type != 'italic');

  if (hasNonEmojiEntities) return const _IsolatedEmojiInfo();

  final text = message.contentText;

  if (customEntities.isNotEmpty) {
    var remaining = text;
    for (final e in customEntities) {
      final start = e.offset.clamp(0, text.length);
      final end = (e.offset + e.length).clamp(0, text.length);
      if (end > start) {
        remaining = remaining.replaceRange(start, end, ' ' * (end - start));
      }
    }
    remaining = remaining.replaceAll(RegExp(r'[\s‍️​]'), '');
    if (remaining.isNotEmpty) return const _IsolatedEmojiInfo();

    final items = customEntities.map((e) {
      final start = e.offset.clamp(0, text.length);
      final end = (e.offset + e.length).clamp(0, text.length);
      return _IsolatedEmojiItem(
        isCustom: true,
        documentId: e.documentId,
        altText: end > start ? text.substring(start, end) : '',
      );
    }).toList();
    return _IsolatedEmojiInfo(isIsolated: true, count: items.length, items: items);
  }

  if (entities.isNotEmpty) return const _IsolatedEmojiInfo();

  final matches = _nativeEmojiPattern.allMatches(text).toList();
  if (matches.isEmpty) return const _IsolatedEmojiInfo();

  var stripped = text;
  for (final m in matches.reversed) {
    stripped = stripped.replaceRange(m.start, m.end, '');
  }
  stripped = stripped.replaceAll(RegExp(r'[\s​]'), '');
  if (stripped.isNotEmpty) return const _IsolatedEmojiInfo();
  if (matches.length > 3) return const _IsolatedEmojiInfo();

  final items = matches.map((m) => _IsolatedEmojiItem(
    isCustom: false,
    altText: m.group(0) ?? '',
  )).toList();
  return _IsolatedEmojiInfo(isIsolated: true, count: items.length, items: items);
}

double _isolatedEmojiSize(int count) {
  if (count <= 1) return 112;
  if (count == 2) return 78;
  if (count == 3) return 58;
  if (count <= 5) return 43;
  if (count <= 7) return 27;
  return 20;
}

class _LargeIsolatedEmoji extends StatelessWidget {
  final _IsolatedEmojiInfo info;
  final String accountId;

  const _LargeIsolatedEmoji({required this.info, required this.accountId});

  @override
  Widget build(BuildContext context) {
    final size = _isolatedEmojiSize(info.count);
    final children = <Widget>[];
    for (final item in info.items) {
      if (item.isCustom) {
        Widget tile = _LargeCustomEmojiTile(
          documentId: item.documentId,
          accountId: accountId,
          altText: item.altText,
          size: size,
        );
        if (info.count == 1) {
          tile = _TapSplashEmoji(
            size: size,
            onTap: () => _ReactionPreviewOverlay.show(
              context: context,
              documentId: item.documentId,
              accountId: accountId,
            ),
            child: tile,
          );
        } else {
          tile = GestureDetector(
            onTap: () => _ReactionPreviewOverlay.show(
              context: context,
              documentId: item.documentId,
              accountId: accountId,
            ),
            child: tile,
          );
        }
        children.add(tile);
      } else {
        children.add(SizedBox(
          width: size,
          height: size,
          child: FittedBox(
            child: Text(item.altText, style: const TextStyle(fontSize: 64)),
          ),
        ));
      }
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: children,
    );
  }
}

class _LargeCustomEmojiTile extends StatefulWidget {
  final int documentId;
  final String accountId;
  final String altText;
  final double size;

  const _LargeCustomEmojiTile({
    required this.documentId,
    required this.accountId,
    required this.altText,
    required this.size,
  });

  @override
  State<_LargeCustomEmojiTile> createState() => _LargeCustomEmojiTileState();
}

class _LargeCustomEmojiTileState extends State<_LargeCustomEmojiTile>
    with TickerProviderStateMixin {
  static const int _maxLoops = 2;

  AnimationController? _lottieController;
  int _loopCount = 0;
  Uint8List? _decompressedLottie;

  @override
  void initState() {
    super.initState();
    CustomEmojiCache.instance.acquire(widget.documentId, EmojiSizeTag.isolated);
    CustomEmojiCache.instance.addListener(_onCacheUpdate);
    _requestIfNeeded();
  }

  @override
  void didUpdateWidget(_LargeCustomEmojiTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId) {
      CustomEmojiCache.instance.release(oldWidget.documentId, EmojiSizeTag.isolated);
      CustomEmojiCache.instance.acquire(widget.documentId, EmojiSizeTag.isolated);
    }
  }

  @override
  void dispose() {
    CustomEmojiCache.instance.removeListener(_onCacheUpdate);
    CustomEmojiCache.instance.release(widget.documentId, EmojiSizeTag.isolated);
    _lottieController?.dispose();
    super.dispose();
  }

  void _onCacheUpdate() {
    if (!mounted) return;
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(widget.documentId);
    if (file != null && file.isTgs && _decompressedLottie == null) {
      _decompressLottieAsync(file.fileData);
    }
    setState(() {});
  }

  void _requestIfNeeded() {
    final cache = CustomEmojiCache.instance;
    if (cache.getThumb(widget.documentId) == null &&
        !cache.isPending(widget.documentId) &&
        !cache.hasFailed(widget.documentId) &&
        widget.accountId.isNotEmpty) {
      final engine = context.read<EngineService>();
      cache.request(widget.documentId, widget.accountId, engine);
    }
    if (cache.getFile(widget.documentId) == null &&
        !cache.isFilePending(widget.documentId) &&
        widget.accountId.isNotEmpty) {
      final engine = context.read<EngineService>();
      cache.requestFile(widget.documentId, widget.accountId, engine);
    }
  }

  Future<void> _decompressLottieAsync(Uint8List data) async {
    try {
      final result = await compute(_gzipDecode, data);
      if (!mounted) return;
      setState(() => _decompressedLottie = result);
    } catch (_) {}
  }

  bool _isPowerSaving(BuildContext context) {
    final appState = context.read<AppState>();
    return appState.powerSaving(AppState.kPowerSavingEmojiChat);
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(
      vsync: this,
      duration: composition.duration,
    );
    _loopCount = 0;
    _lottieController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _loopCount++;
        if (_loopCount < _maxLoops) {
          _lottieController!.forward(from: 0);
        }
      }
    });
    _lottieController!.forward();
  }

  @override
  Widget build(BuildContext context) {
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(widget.documentId);
    final powerSaving = _isPowerSaving(context);

    if (file != null && !powerSaving) {
      if (file.isTgs && _decompressedLottie != null) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Lottie.memory(
            _decompressedLottie!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            controller: _lottieController,
            onLoaded: _onLottieLoaded,
            errorBuilder: (_, __, ___) => _buildThumbOrFallback(cache),
          ),
        );
      }
      if (file.isWebm) {
        return _WebmEmojiPlayer(
          fileData: file.fileData,
          size: widget.size,
          fallback: _buildThumbOrFallback(cache),
        );
      }
      if (file.isWebp) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Image.memory(
            file.fileData,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _buildThumbOrFallback(cache),
          ),
        );
      }
    }

    return _buildThumbOrFallback(cache);
  }

  Widget _buildThumbOrFallback(CustomEmojiCache cache) {
    final thumb = cache.getThumb(widget.documentId);
    if (thumb != null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Image.memory(
          thumb,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }
    final pathBytes = cache.getPath(widget.documentId);
    if (pathBytes != null) {
      return Opacity(
        opacity: 0.125,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _SvgPathPreviewPainter(
              pathBytes: pathBytes,
              color: DefaultTextStyle.of(context).style.color ?? Colors.white,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FittedBox(
        child: Text(
          widget.altText.isNotEmpty ? widget.altText : '\u{2B50}',
          style: const TextStyle(fontSize: 64),
        ),
      ),
    );
  }
}

// ── §45.9: Tap splash for isolated single custom emoji ──

class _TapSplashEmoji extends StatefulWidget {
  final Widget child;
  final double size;
  final VoidCallback onTap;

  const _TapSplashEmoji({
    required this.child,
    required this.size,
    required this.onTap,
  });

  @override
  State<_TapSplashEmoji> createState() => _TapSplashEmojiState();
}

class _TapSplashEmojiState extends State<_TapSplashEmoji>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ── Animated custom emoji inline widget (§45.3) ──

class _CustomEmojiInline extends StatefulWidget {
  final int documentId;
  final String accountId;
  final String altText;
  final VoidCallback? onTap;

  const _CustomEmojiInline({
    required this.documentId,
    required this.accountId,
    required this.altText,
    this.onTap,
  });

  @override
  State<_CustomEmojiInline> createState() => _CustomEmojiInlineState();
}

enum _EmojiLoadPhase { loading, caching, cached }

class _CustomEmojiInlineState extends State<_CustomEmojiInline>
    with TickerProviderStateMixin {
  static const double _emojiSize = 18.0;
  static const double _adjustedSize = 20.0;
  static const int _maxLoops = 2;
  static const double _previewOpacity = 0.125; // 12.5% per spec §45.7

  int _scaledCacheSize(BuildContext context) =>
      EmojiSizeConstants.scaledFrameSize(EmojiSizeTag.normal, MediaQuery.devicePixelRatioOf(context)).round();

  AnimationController? _lottieController;
  late AnimationController _fadeController;
  int _loopCount = 0;
  Uint8List? _decompressedLottie;
  _EmojiLoadPhase _phase = _EmojiLoadPhase.loading;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    CustomEmojiCache.instance.acquire(widget.documentId, EmojiSizeTag.normal);
    CustomEmojiCache.instance.addListener(_onCacheUpdate);
    _requestIfNeeded();
    _updatePhase();
  }

  @override
  void didUpdateWidget(_CustomEmojiInline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId) {
      CustomEmojiCache.instance.release(oldWidget.documentId, EmojiSizeTag.normal);
      CustomEmojiCache.instance.acquire(widget.documentId, EmojiSizeTag.normal);
    }
  }

  @override
  void dispose() {
    CustomEmojiCache.instance.removeListener(_onCacheUpdate);
    CustomEmojiCache.instance.release(widget.documentId, EmojiSizeTag.normal);
    _lottieController?.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onCacheUpdate() {
    if (!mounted) return;
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(widget.documentId);
    if (file != null && file.isTgs && _decompressedLottie == null) {
      _decompressLottieAsync(file.fileData);
    }
    _updatePhase();
    setState(() {});
  }

  void _updatePhase() {
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(widget.documentId);
    final oldPhase = _phase;
    if (file != null) {
      _phase = _EmojiLoadPhase.cached;
    } else if (cache.hasAnyPreview(widget.documentId)) {
      _phase = _EmojiLoadPhase.caching;
    } else {
      _phase = _EmojiLoadPhase.loading;
    }
    if (oldPhase != _EmojiLoadPhase.cached && _phase == _EmojiLoadPhase.cached) {
      _fadeController.forward(from: 0);
    }
  }

  void _requestIfNeeded() {
    final cache = CustomEmojiCache.instance;
    if (!cache.hasAnyPreview(widget.documentId) &&
        !cache.isPending(widget.documentId) &&
        !cache.hasFailed(widget.documentId) &&
        widget.accountId.isNotEmpty) {
      final engine = context.read<EngineService>();
      cache.request(widget.documentId, widget.accountId, engine);
    }
    if (cache.getFile(widget.documentId) == null &&
        !cache.isFilePending(widget.documentId) &&
        widget.accountId.isNotEmpty) {
      final engine = context.read<EngineService>();
      cache.requestFile(widget.documentId, widget.accountId, engine);
    }
  }

  Future<void> _decompressLottieAsync(Uint8List data) async {
    try {
      final result = await compute(_gzipDecode, data);
      if (!mounted) return;
      setState(() => _decompressedLottie = result);
    } catch (_) {}
  }

  bool _isPowerSaving(BuildContext context) {
    final appState = context.read<AppState>();
    return appState.powerSaving(AppState.kPowerSavingEmojiChat);
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(
      vsync: this,
      duration: composition.duration,
    );
    _loopCount = 0;
    _lottieController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _loopCount++;
        if (_loopCount < _maxLoops) {
          _lottieController!.forward(from: 0);
        }
      }
    });
    _lottieController!.forward();
  }

  bool _tapDown = false;

  Widget _wrapTap(Widget child) {
    if (widget.onTap == null) return child;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _tapDown = true,
      onPointerUp: (_) {
        if (_tapDown) {
          _tapDown = false;
          widget.onTap!();
        }
      },
      onPointerCancel: (_) => _tapDown = false,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(widget.documentId);
    final powerSaving = _isPowerSaving(context);

    if (file != null && !powerSaving) {
      final cachedWidget = _buildCachedEmoji(file, cache);
      if (_fadeController.isAnimating || _fadeController.value < 1.0) {
        return _wrapTap(SizedBox(
          width: _adjustedSize,
          height: _adjustedSize,
          child: AnimatedBuilder(
            animation: _fadeController,
            builder: (context, child) {
              return Stack(
                children: [
                  if (_fadeController.value < 1.0)
                    Opacity(
                      opacity: 1.0 - _fadeController.value,
                      child: _buildPreview(cache),
                    ),
                  Opacity(opacity: _fadeController.value, child: child),
                ],
              );
            },
            child: cachedWidget,
          ),
        ));
      }
      return _wrapTap(cachedWidget);
    }

    if (file != null && powerSaving) {
      return _wrapTap(_buildStaticFrame(file, cache));
    }

    final approx = cache.prepareNonExactPreview(widget.documentId, EmojiSizeTag.normal);
    if (approx != null) {
      return _wrapTap(_buildCachedEmoji(approx, cache));
    }

    return _wrapTap(_buildPreviewOrBlank(cache));
  }

  Widget _buildCachedEmoji(CustomEmojiFileData file, CustomEmojiCache cache) {
    if (file.isTgs && _decompressedLottie != null) {
      return SizedBox(
        width: _adjustedSize,
        height: _adjustedSize,
        child: Lottie.memory(
          _decompressedLottie!,
          width: _adjustedSize,
          height: _adjustedSize,
          fit: BoxFit.contain,
          controller: _lottieController,
          onLoaded: _onLottieLoaded,
          errorBuilder: (_, __, ___) => _buildPreviewOrBlank(cache),
        ),
      );
    }
    if (file.isWebm) {
      return _WebmEmojiPlayer(
        fileData: file.fileData,
        size: _adjustedSize,
        fallback: _buildPreviewOrBlank(cache),
      );
    }
    if (file.isWebp) {
      final cs = _scaledCacheSize(context);
      return SizedBox(
        width: _adjustedSize,
        height: _adjustedSize,
        child: Image.memory(
          file.fileData,
          width: _adjustedSize,
          height: _adjustedSize,
          cacheWidth: cs,
          cacheHeight: cs,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _buildPreviewOrBlank(cache),
        ),
      );
    }
    return _buildPreviewOrBlank(cache);
  }

  Widget _buildStaticFrame(CustomEmojiFileData file, CustomEmojiCache cache) {
    if (file.isWebm || file.isWebp) {
      final cs = _scaledCacheSize(context);
      return SizedBox(
        width: _adjustedSize,
        height: _adjustedSize,
        child: file.isWebp
            ? Image.memory(
                file.fileData,
                width: _adjustedSize,
                height: _adjustedSize,
                cacheWidth: cs,
                cacheHeight: cs,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _buildPreviewOrBlank(cache),
              )
            : _buildPreviewOrBlank(cache),
      );
    }
    return _buildPreviewOrBlank(cache);
  }

  Widget _buildPreviewOrBlank(CustomEmojiCache cache) {
    return _buildPreview(cache);
  }

  Widget _buildPreview(CustomEmojiCache cache) {
    final pathBytes = cache.getPath(widget.documentId);
    if (pathBytes != null) {
      return Opacity(
        opacity: _previewOpacity,
        child: SizedBox(
          width: _adjustedSize,
          height: _adjustedSize,
          child: CustomPaint(
            size: const Size(_adjustedSize, _adjustedSize),
            painter: _SvgPathPreviewPainter(
              pathBytes: pathBytes,
              color: DefaultTextStyle.of(context).style.color ?? Colors.white,
            ),
          ),
        ),
      );
    }
    final thumb = cache.getThumb(widget.documentId);
    if (thumb != null) {
      return SizedBox(
        width: _adjustedSize,
        height: _adjustedSize,
        child: Image.memory(
          thumb,
          width: _adjustedSize,
          height: _adjustedSize,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox(
            width: _adjustedSize,
            height: _adjustedSize,
          ),
        ),
      );
    }
    return const SizedBox(width: _adjustedSize, height: _adjustedSize);
  }
}

class _WebmEmojiPlayer extends StatefulWidget {
  final Uint8List fileData;
  final double size;
  final Widget fallback;
  const _WebmEmojiPlayer({required this.fileData, required this.size, required this.fallback});
  @override
  State<_WebmEmojiPlayer> createState() => _WebmEmojiPlayerState();
}

class _WebmEmojiPlayerState extends State<_WebmEmojiPlayer> {
  Player? _player;
  VideoController? _videoController;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/emoji_${widget.fileData.hashCode}.webm');
      await file.writeAsBytes(widget.fileData, flush: true);
      _tempFile = file;
      final player = Player();
      final controller = VideoController(player);
      await player.open(Media(file.path), play: true);
      await player.setPlaylistMode(PlaylistMode.loop);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _videoController = controller;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _player?.dispose();
    _tempFile?.delete().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_videoController == null) return widget.fallback;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Video(
          controller: _videoController!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          controls: NoVideoControls,
        ),
      ),
    );
  }
}

class _SvgPathPreviewPainter extends CustomPainter {
  final Uint8List pathBytes;
  final Color color;

  static const List<String> _commands = [
    'A', 'C', 'c', 'H', 'h', 'L', 'l', 'M', 'm',
    'Q', 'q', 'S', 's', 'T', 't', 'V', 'v', 'Z', 'z',
  ];

  _SvgPathPreviewPainter({required this.pathBytes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final svgPath = _decompressPath();
    if (svgPath.isEmpty) return;
    final path = _parseSvgPath(svgPath);
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;
    final sx = size.width / 512.0;
    final sy = size.height / 512.0;
    final scale = math.min(sx, sy);
    canvas.save();
    canvas.scale(scale, scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  String _decompressPath() {
    final buf = StringBuffer('M');
    for (final byte in pathBytes) {
      if (byte >= 192) {
        final idx = byte - 192;
        if (idx < _commands.length) buf.write(_commands[idx]);
      } else if (byte >= 128) {
        buf.write(',');
        buf.write((byte & 63).toString());
      } else if (byte >= 64) {
        buf.write('-');
        buf.write((byte & 63).toString());
      } else {
        buf.write(byte.toString());
      }
    }
    buf.write('z');
    return buf.toString();
  }

  static ui.Path _parseSvgPath(String d) {
    final path = ui.Path();
    final tokens = _tokenize(d);
    var i = 0;
    var cx = 0.0, cy = 0.0;
    var prevCubicX2 = 0.0, prevCubicY2 = 0.0;
    var prevQuadX1 = 0.0, prevQuadY1 = 0.0;
    var cmd = '';

    double next() => i < tokens.length ? tokens[i++] : 0.0;

    while (i < tokens.length || cmd.isNotEmpty) {
      if (i < tokens.length && tokens[i].isNaN) {
        cmd = String.fromCharCode(tokens[i].toInt().abs());
        i++;
      } else if (cmd.isEmpty) {
        break;
      }

      switch (cmd) {
        case 'M':
          cx = next(); cy = next();
          path.moveTo(cx, cy);
          cmd = 'L';
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'm':
          cx += next(); cy += next();
          path.moveTo(cx, cy);
          cmd = 'l';
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'L':
          cx = next(); cy = next();
          path.lineTo(cx, cy);
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'l':
          cx += next(); cy += next();
          path.lineTo(cx, cy);
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'H':
          cx = next();
          path.lineTo(cx, cy);
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'h':
          cx += next();
          path.lineTo(cx, cy);
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'V':
          cy = next();
          path.lineTo(cx, cy);
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'v':
          cy += next();
          path.lineTo(cx, cy);
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'C':
          final x1 = next(), y1 = next();
          final x2 = next(), y2 = next();
          cx = next(); cy = next();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
          prevCubicX2 = x2; prevCubicY2 = y2;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'c':
          final x1 = cx + next(), y1 = cy + next();
          final x2 = cx + next(), y2 = cy + next();
          cx += next(); cy += next();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
          prevCubicX2 = x2; prevCubicY2 = y2;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'S':
          final rx1 = 2 * cx - prevCubicX2;
          final ry1 = 2 * cy - prevCubicY2;
          final x2 = next(), y2 = next();
          cx = next(); cy = next();
          path.cubicTo(rx1, ry1, x2, y2, cx, cy);
          prevCubicX2 = x2; prevCubicY2 = y2;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 's':
          final rx1 = 2 * cx - prevCubicX2;
          final ry1 = 2 * cy - prevCubicY2;
          final x2 = cx + next(), y2 = cy + next();
          cx += next(); cy += next();
          path.cubicTo(rx1, ry1, x2, y2, cx, cy);
          prevCubicX2 = x2; prevCubicY2 = y2;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'Q':
          final x1 = next(), y1 = next();
          cx = next(); cy = next();
          path.quadraticBezierTo(x1, y1, cx, cy);
          prevQuadX1 = x1; prevQuadY1 = y1;
          prevCubicX2 = cx; prevCubicY2 = cy;
        case 'q':
          final x1 = cx + next(), y1 = cy + next();
          cx += next(); cy += next();
          path.quadraticBezierTo(x1, y1, cx, cy);
          prevQuadX1 = x1; prevQuadY1 = y1;
          prevCubicX2 = cx; prevCubicY2 = cy;
        case 'T':
          final rx1 = 2 * cx - prevQuadX1;
          final ry1 = 2 * cy - prevQuadY1;
          cx = next(); cy = next();
          path.quadraticBezierTo(rx1, ry1, cx, cy);
          prevQuadX1 = rx1; prevQuadY1 = ry1;
          prevCubicX2 = cx; prevCubicY2 = cy;
        case 't':
          final rx1 = 2 * cx - prevQuadX1;
          final ry1 = 2 * cy - prevQuadY1;
          cx += next(); cy += next();
          path.quadraticBezierTo(rx1, ry1, cx, cy);
          prevQuadX1 = rx1; prevQuadY1 = ry1;
          prevCubicX2 = cx; prevCubicY2 = cy;
        case 'A':
          final rx = next(), ry = next();
          final rotation = next() * math.pi / 180.0;
          final largeArc = next() != 0;
          final sweep = next() != 0;
          cx = next(); cy = next();
          path.arcToPoint(
            Offset(cx, cy),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        case 'Z': case 'z':
          path.close();
          cmd = '';
          prevCubicX2 = cx; prevCubicY2 = cy;
          prevQuadX1 = cx; prevQuadY1 = cy;
        default:
          cmd = '';
      }
    }
    return path;
  }

  static List<double> _tokenize(String d) {
    final result = <double>[];
    final len = d.length;
    var i = 0;
    while (i < len) {
      final c = d.codeUnitAt(i);
      if (_isCommand(c)) {
        result.add(double.nan);
        result.add(-(c.toDouble()));
        i++;
      } else if (_isDigit(c) || c == 0x2D || c == 0x2E) {
        final start = i;
        if (c == 0x2D) i++;
        while (i < len && (_isDigit(d.codeUnitAt(i)) || d.codeUnitAt(i) == 0x2E)) {
          i++;
        }
        result.add(double.tryParse(d.substring(start, i)) ?? 0);
      } else {
        i++;
      }
    }
    return result;
  }

  static bool _isCommand(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  @override
  bool shouldRepaint(_SvgPathPreviewPainter oldDelegate) =>
      !_bytesEqual(pathBytes, oldDelegate.pathBytes) || color != oldDelegate.color;

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ── Rich text entity model ──

class _TextEntity {
  final String type;
  final int offset; // UTF-16 code units
  final int length;
  final String url;
  final String language;
  final int documentId;

  const _TextEntity({
    required this.type,
    required this.offset,
    required this.length,
    this.url = '',
    this.language = '',
    this.documentId = 0,
  });

  factory _TextEntity.fromJson(Map<String, dynamic> j) => _TextEntity(
    type: j['type'] as String? ?? '',
    offset: j['offset'] as int? ?? 0,
    length: j['length'] as int? ?? 0,
    url: j['url'] as String? ?? '',
    language: j['language'] as String? ?? '',
    documentId: (j['document_id'] as num?)?.toInt() ?? 0,
  );
}

// ── Rich message text widget ──

class _RichMessageText extends StatefulWidget {
  final String text;
  final String entitiesJson;
  final TextStyle baseStyle;
  final ThemeData theme;
  final bool isOutgoing;
  final String accountId;
  final void Function(Offset position, String selectedText)? onContextMenu;
  final Widget? trailingPad;

  const _RichMessageText({
    required this.text,
    required this.entitiesJson,
    required this.baseStyle,
    required this.theme,
    required this.isOutgoing,
    this.accountId = '',
    this.onContextMenu,
    this.trailingPad,
  });

  @override
  State<_RichMessageText> createState() => _RichMessageTextState();
}

class _RichMessageTextState extends State<_RichMessageText> {
  final Set<int> _revealedSpoilers = {};
  final List<TapGestureRecognizer> _recognizers = [];
  List<_TextEntity>? _cachedEntities;

  @override
  void initState() {
    super.initState();
    SpoilerRevealManager.instance.addListener(_onHideSpoilers);
  }

  void _onHideSpoilers() {
    if (_revealedSpoilers.isNotEmpty && mounted) {
      setState(() => _revealedSpoilers.clear());
    }
  }

  void _revealAllSpoilers() {
    final entities = _cachedEntities ?? _parseEntities();
    setState(() {
      for (final e in entities.where((e) => e.type == 'spoiler')) {
        _revealedSpoilers.add(e.offset);
      }
    });
  }

  @override
  void dispose() {
    SpoilerRevealManager.instance.removeListener(_onHideSpoilers);
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _triggerContextMenu(EditableTextState editableTextState) {
    final sel = editableTextState.currentTextEditingValue.selection;
    final text = widget.text;
    var selectedText = '';
    if (sel.isValid && !sel.isCollapsed) {
      final start = sel.start.clamp(0, text.length);
      final end = sel.end.clamp(0, text.length);
      if (end > start) selectedText = text.substring(start, end);
    }
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onContextMenu?.call(anchor, selectedText);
    });
  }

  List<_TextEntity> _parseEntities() {
    if (widget.entitiesJson.isEmpty) return const [];
    try {
      final list = jsonDecode(widget.entitiesJson) as List;
      return list.map((e) => _TextEntity.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Clean up old recognizers.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    var entities = _parseEntities();
    _cachedEntities = entities;
    final text = widget.text;
    if (entities.isEmpty) {
      if (widget.trailingPad != null) {
        return Text.rich(
          TextSpan(children: [
            TextSpan(text: text),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: widget.trailingPad!,
            ),
          ]),
          style: widget.baseStyle,
        );
      }
      if (widget.onContextMenu != null) {
        return SelectableText(
          text,
          style: widget.baseStyle,
          contextMenuBuilder: (ctx, editableTextState) {
            _triggerContextMenu(editableTextState);
            return const SizedBox.shrink();
          },
        );
      }
      return Text(text, style: widget.baseStyle);
    }

    final isDark = widget.theme.brightness == Brightness.dark;
    final textLen = text.length;

    // Sort by offset for stable processing.
    entities.sort((a, b) => a.offset.compareTo(b.offset));

    final hasSpoilers = entities.any((e) => e.type == 'spoiler');
    final hasUnrevealed = hasSpoilers && entities
        .where((e) => e.type == 'spoiler')
        .any((e) => !_revealedSpoilers.contains(e.offset));

    // Separate blockquotes (block-level) from inline entities.
    final blockquotes = entities.where((e) => e.type == 'blockquote').toList();
    final inlineEntities = entities.where((e) => e.type != 'blockquote').toList();

    // SelectableText.rich can't handle WidgetSpan (pre/spoiler) or blockquotes.
    final hasWidgetSpans = entities.any((e) => e.type == 'pre' || e.type == 'spoiler' || e.type == 'custom_emoji');
    final canBeSelectable = !hasWidgetSpans && blockquotes.isEmpty && widget.onContextMenu != null;

    Widget result;
    if (blockquotes.isEmpty) {
      final spans = _buildInlineSpans(text, 0, textLen, inlineEntities, isDark);
      if (widget.trailingPad != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: widget.trailingPad!,
        ));
      }
      final textSpan = TextSpan(children: spans);
      if (canBeSelectable && widget.trailingPad == null) {
        result = SelectableText.rich(
          textSpan,
          style: widget.baseStyle,
          contextMenuBuilder: (ctx, editableTextState) {
            _triggerContextMenu(editableTextState);
            return const SizedBox.shrink();
          },
        );
      } else {
        result = Text.rich(textSpan, style: widget.baseStyle);
      }
    } else {

    // Complex case: split text into blockquote blocks and normal blocks.
    final children = <Widget>[];
    var cursor = 0;

    for (final bq in blockquotes) {
      final bqStart = bq.offset.clamp(0, textLen);
      final bqEnd = (bq.offset + bq.length).clamp(0, textLen);

      // Text before the blockquote.
      if (cursor < bqStart) {
        final before = inlineEntities.where((e) =>
          e.offset < bqStart && e.offset + e.length > cursor).toList();
        children.add(Text.rich(
          TextSpan(children: _buildInlineSpans(text, cursor, bqStart, before, isDark)),
          style: widget.baseStyle,
        ));
      }

      // The blockquote itself.
      final bqInline = inlineEntities.where((e) =>
        e.offset >= bqStart && e.offset < bqEnd).toList();
      final bqColor = isDark ? const Color(0xFF65bdf3) : const Color(0xFF168acd);
      final bqBg = isDark ? const Color(0x1A65bdf3) : const Color(0x14168acd);
      children.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: bqColor, width: 3)),
          color: bqBg,
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text.rich(
          TextSpan(children: _buildInlineSpans(text, bqStart, bqEnd, bqInline, isDark)),
          style: widget.baseStyle,
        ),
      ));

      cursor = bqEnd;
    }

    // Remaining text after last blockquote.
    if (cursor < textLen) {
      final after = inlineEntities.where((e) =>
        e.offset >= cursor).toList();
      final afterSpans = _buildInlineSpans(text, cursor, textLen, after, isDark);
      if (widget.trailingPad != null) {
        afterSpans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: widget.trailingPad!,
        ));
      }
      children.add(Text.rich(
        TextSpan(children: afterSpans),
        style: widget.baseStyle,
      ));
    } else if (widget.trailingPad != null) {
      children.add(Text.rich(
        TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: widget.trailingPad!,
          ),
        ]),
        style: widget.baseStyle,
      ));
    }

    result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    }

    if (!hasUnrevealed) return result;
    return GestureDetector(
      onTap: _revealAllSpoilers,
      behavior: HitTestBehavior.opaque,
      child: result,
    );
  }

  List<InlineSpan> _buildInlineSpans(
    String text, int regionStart, int regionEnd,
    List<_TextEntity> entities, bool isDark,
  ) {
    final spans = <InlineSpan>[];
    var cursor = regionStart;

    // Filter and sort entities within this region.
    final relevant = entities
      .where((e) => e.offset < regionEnd && e.offset + e.length > regionStart)
      .toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));

    for (final entity in relevant) {
      final eStart = entity.offset.clamp(regionStart, regionEnd);
      final eEnd = (entity.offset + entity.length).clamp(regionStart, regionEnd);
      if (eEnd <= eStart) continue;

      // Plain text before this entity.
      if (cursor < eStart) {
        spans.add(TextSpan(text: text.substring(cursor, eStart)));
      }

      final entityText = text.substring(eStart, eEnd);
      spans.add(_styledSpan(entity, entityText, isDark));
      cursor = eEnd;
    }

    // Remaining plain text.
    if (cursor < regionEnd) {
      spans.add(TextSpan(text: text.substring(cursor, regionEnd)));
    }

    return spans;
  }

  InlineSpan _styledSpan(_TextEntity entity, String text, bool isDark) {
    switch (entity.type) {
      case 'bold':
        return TextSpan(text: text, style: const TextStyle(fontWeight: FontWeight.bold));
      case 'italic':
        return TextSpan(text: text, style: const TextStyle(fontStyle: FontStyle.italic));
      case 'underline':
        return TextSpan(text: text, style: const TextStyle(decoration: TextDecoration.underline));
      case 'strike':
        return TextSpan(text: text, style: const TextStyle(decoration: TextDecoration.lineThrough));
      case 'code':
        final monoFont = context.read<AppState>().monoFont;
        return TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: monoFont.isEmpty ? 'monospace' : monoFont,
            backgroundColor: isDark ? const Color(0xFF1E2A36) : const Color(0xFFF0F0F0),
            fontSize: (widget.baseStyle.fontSize ?? 14) * 0.9,
          ),
        );
      case 'pre':
        final monoFontPre = context.read<AppState>().monoFont;
        return WidgetSpan(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2A36) : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: monoFontPre.isEmpty ? 'monospace' : monoFontPre,
                fontSize: (widget.baseStyle.fontSize ?? 14) * 0.9,
                color: widget.baseStyle.color,
              ),
            ),
          ),
        );
      case 'spoiler':
        final idx = entity.offset;
        final revealed = _revealedSpoilers.contains(idx);
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _TextSpoilerWidget(
            text: text,
            style: widget.baseStyle,
            isDark: isDark,
            revealed: revealed,
            onReveal: _revealAllSpoilers,
          ),
        );
      case 'url':
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openUrl(text);
        _recognizers.add(recognizer);
        return TextSpan(
          text: text,
          style: TextStyle(
            color: isDark ? const Color(0xFF65BDF3) : const Color(0xFF168ACD),
            decoration: TextDecoration.underline,
            decorationColor: isDark ? const Color(0x6665BDF3) : const Color(0x66168ACD),
          ),
          recognizer: recognizer,
        );
      case 'text_url':
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openUrl(entity.url);
        _recognizers.add(recognizer);
        return TextSpan(
          text: text,
          style: TextStyle(
            color: isDark ? const Color(0xFF65BDF3) : const Color(0xFF168ACD),
            decoration: TextDecoration.underline,
            decorationColor: isDark ? const Color(0x6665BDF3) : const Color(0x66168ACD),
          ),
          recognizer: recognizer,
        );
      case 'mention':
      case 'mention_name':
      case 'hashtag':
      case 'bot_command':
      case 'cashtag':
        return TextSpan(
          text: text,
          style: TextStyle(
            color: isDark ? const Color(0xFF65BDF3) : const Color(0xFF168ACD),
          ),
        );
      case 'email':
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openUrl('mailto:$text');
        _recognizers.add(recognizer);
        return TextSpan(
          text: text,
          style: TextStyle(
            color: isDark ? const Color(0xFF65BDF3) : const Color(0xFF168ACD),
            decoration: TextDecoration.underline,
            decorationColor: isDark ? const Color(0x6665BDF3) : const Color(0x66168ACD),
          ),
          recognizer: recognizer,
        );
      case 'phone':
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openUrl('tel:$text');
        _recognizers.add(recognizer);
        return TextSpan(
          text: text,
          style: TextStyle(
            color: isDark ? const Color(0xFF65BDF3) : const Color(0xFF168ACD),
          ),
          recognizer: recognizer,
        );
      case 'custom_emoji':
        if (entity.documentId == 0) return TextSpan(text: text);
        final emojiDocId = entity.documentId;
        final emojiAcctId = widget.accountId;
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: _CustomEmojiInline(
              documentId: emojiDocId,
              accountId: emojiAcctId,
              altText: text,
              onTap: () => _ReactionPreviewOverlay.show(
                context: context,
                documentId: emojiDocId,
                accountId: emojiAcctId,
              ),
            ),
          ),
        );
      default:
        return TextSpan(text: text);
    }
  }

  static void _openUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://') &&
        !url.startsWith('mailto:') && !url.startsWith('tel:')) {
      url = 'https://$url';
    }
    Process.run('xdg-open', [url]);
  }
}

/// Spec §5: Round selection checkbox — 20px diameter, 2px stroke.
/// Empty: white border + 25% black fill. Checked: boxTextFgGood fill + white check glyph.
/// Animation: 160ms easeInOutQuad, bgDuration 0.75, fgDuration 1.0.
class _SelectionCheckbox extends StatefulWidget {
  final bool checked;
  final bool isDark;

  const _SelectionCheckbox({required this.checked, required this.isDark});

  @override
  State<_SelectionCheckbox> createState() => _SelectionCheckboxState();
}

class _SelectionCheckboxState extends State<_SelectionCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 160),
      vsync: this,
      value: widget.checked ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_SelectionCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checked != oldWidget.checked) {
      if (widget.checked) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double size = 20.0;
    final bgActive = widget.isDark
        ? AppColors.selectionCheckBgActiveNight
        : AppColors.selectionCheckBgActiveDay;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // easeInOutQuad mapped progress
          final t = Curves.easeInOut.transform(_controller.value);
          // bg fills over first 75% of animation, fg over full duration
          final bgT = (t / 0.75).clamp(0.0, 1.0);
          final fgT = t;
          return CustomPaint(
            painter: _SelectionCheckboxPainter(
              bgProgress: bgT,
              fgProgress: fgT,
              bgActive: bgActive,
            ),
          );
        },
      ),
    );
  }
}

class _SelectionCheckboxPainter extends CustomPainter {
  final double bgProgress;
  final double fgProgress;
  final Color bgActive;

  _SelectionCheckboxPainter({
    required this.bgProgress,
    required this.fgProgress,
    required this.bgActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 2.0;

    // Background: lerp from inactive (border + translucent fill) to active (solid fill)
    if (bgProgress < 1.0) {
      // Draw inactive state (fades out as bgProgress increases)
      final inactiveAlpha = 1.0 - bgProgress;
      canvas.drawCircle(
        center,
        radius - strokeWidth / 2,
        Paint()..color = AppColors.selectionCheckBgInactive.withValues(alpha: AppColors.selectionCheckBgInactive.a * inactiveAlpha),
      );
      canvas.drawCircle(
        center,
        radius - strokeWidth / 2,
        Paint()
          ..color = AppColors.selectionCheckBorder.withValues(alpha: AppColors.selectionCheckBorder.a * inactiveAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }
    if (bgProgress > 0.0) {
      // Draw active fill (fades in)
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = bgActive.withValues(alpha: bgActive.a * bgProgress),
      );
    }

    // Foreground: check glyph draws in with fgProgress
    if (fgProgress > 0.0) {
      final path = Path();
      // Full check path points
      const p0x = 0.28, p0y = 0.50;
      const p1x = 0.43, p1y = 0.65;
      const p2x = 0.72, p2y = 0.35;

      // Two segments: p0→p1 (first half of fgProgress), p1→p2 (second half)
      final seg1T = (fgProgress * 2.0).clamp(0.0, 1.0);
      final seg2T = ((fgProgress - 0.5) * 2.0).clamp(0.0, 1.0);

      path.moveTo(size.width * p0x, size.height * p0y);
      // First segment
      final s1x = p0x + (p1x - p0x) * seg1T;
      final s1y = p0y + (p1y - p0y) * seg1T;
      path.lineTo(size.width * s1x, size.height * s1y);

      if (seg2T > 0.0) {
        final s2x = p1x + (p2x - p1x) * seg2T;
        final s2y = p1y + (p2y - p1y) * seg2T;
        path.lineTo(size.width * s2x, size.height * s2y);
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.selectionCheckBorder.withValues(alpha: fgProgress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionCheckboxPainter oldDelegate) =>
      bgProgress != oldDelegate.bgProgress ||
      fgProgress != oldDelegate.fgProgress ||
      bgActive != oldDelegate.bgActive;
}

// ── Album Layout Widget (spec §6.3) ──
// Groups up to 10 media items with 4px spacing, 100–430px width.
// Per-count layout rules from grouped_layout.cpp.

class AlbumLayout extends StatelessWidget {
  final List<CachedMessage> items;
  final double maxWidth;
  final List<CachedMessage> allMessages;

  static const double _spacing = 4.0;
  static const double _minWidth = 100.0;

  const AlbumLayout({
    super.key,
    required this.items,
    this.maxWidth = 430.0,
    this.allMessages = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) {
      return _AlbumThumb(message: items[0], allMessages: allMessages);
    }

    final ratios = items.map((m) {
      if (m.mediaWidth > 0 && m.mediaHeight > 0) {
        return m.mediaWidth / m.mediaHeight;
      }
      return 1.0;
    }).toList();

    final layout = _computeLayout(ratios, maxWidth);
    return _buildLayout(context, layout);
  }

  Widget _buildLayout(BuildContext context, _AlbumLayoutResult layout) {
    return SizedBox(
      width: layout.totalWidth,
      height: layout.totalHeight,
      child: Stack(
        children: [
          for (int i = 0; i < layout.rects.length && i < items.length; i++)
            Positioned(
              left: layout.rects[i].left,
              top: layout.rects[i].top,
              width: layout.rects[i].width,
              height: layout.rects[i].height,
              child: _AlbumThumb(
                message: items[i],
                allMessages: allMessages,
                borderRadius: _cornerRadius(i, layout.rects, layout.totalWidth, layout.totalHeight),
              ),
            ),
        ],
      ),
    );
  }

  BorderRadius _cornerRadius(int index, List<Rect> rects, double totalW, double totalH) {
    const r = 8.0;
    final rect = rects[index];
    final atLeft = rect.left < 1;
    final atRight = (rect.right - totalW).abs() < 1;
    final atTop = rect.top < 1;
    final atBottom = (rect.bottom - totalH).abs() < 1;
    return BorderRadius.only(
      topLeft: (atLeft && atTop) ? const Radius.circular(r) : Radius.zero,
      topRight: (atRight && atTop) ? const Radius.circular(r) : Radius.zero,
      bottomLeft: (atLeft && atBottom) ? const Radius.circular(r) : Radius.zero,
      bottomRight: (atRight && atBottom) ? const Radius.circular(r) : Radius.zero,
    );
  }

  _AlbumLayoutResult _computeLayout(List<double> ratios, double maxW) {
    final n = ratios.length;
    final s = _spacing;

    // Spec: ComplexLayouter when count >= 5 OR any item ratio > 2.
    final useComplex = n >= 5 || ratios.any((r) => r > 2.0);
    if (!useComplex) {
      if (n == 2) return _layout2(ratios, maxW, s);
      if (n == 3) return _layout3(ratios, maxW, s);
      if (n == 4) return _layout4(ratios, maxW, s);
    }
    return _layoutComplex(ratios, maxW, s);
  }

  static String _proportion(double r) => r > 1.2 ? 'w' : (r < 0.8 ? 'n' : 'q');

  _AlbumLayoutResult _layout2(List<double> ratios, double W, double s) {
    final r0 = ratios[0], r1 = ratios[1];
    final p0 = _proportion(r0), p1 = _proportion(r1);
    final avgRatio = (r0 + r1) / 2;
    final props = '$p0$p1';

    if (props == 'ww' && avgRatio > 1.4 && (r0 - r1).abs() < 0.2) {
      // Top/bottom stack. maxHeight = W (square ceiling).
      var h0 = (W / r0).clamp(_minWidth, W);
      var h1 = (W / r1).clamp(_minWidth, W);
      if (h0 + s + h1 > W) {
        final scale = (W - s) / (h0 + h1);
        h0 *= scale;
        h1 *= scale;
      }
      return _AlbumLayoutResult(W, h0 + s + h1, [
        Rect.fromLTWH(0, 0, W, h0),
        Rect.fromLTWH(0, h0 + s, W, h1),
      ]);
    }

    if (props == 'ww' || props == 'qq') {
      // Equal left/right split.
      final w = (W - s) / 2;
      final h = math.min(w / r0, w / r1).clamp(_minWidth, W);
      return _AlbumLayoutResult(W, h, [
        Rect.fromLTWH(0, 0, w, h),
        Rect.fromLTWH(w + s, 0, w, h),
      ]);
    }

    // Proportional left/right.
    final w1 = ((W - s) / (1 + r1 / r0)).clamp(_minWidth, W - s - _minWidth);
    final w2 = W - s - w1;
    final h = math.min(w1 / r0, w2 / r1).clamp(_minWidth, W);
    return _AlbumLayoutResult(W, h, [
      Rect.fromLTWH(0, 0, w1, h),
      Rect.fromLTWH(w1 + s, 0, w2, h),
    ]);
  }

  _AlbumLayoutResult _layout3(List<double> ratios, double W, double s) {
    final r0 = ratios[0], r1 = ratios[1], r2 = ratios[2];
    final p0 = _proportion(r0);

    if (p0 == 'n') {
      // Left column + two stacked right.
      final rightH = W * 0.66;
      final leftW = (W - s) * 0.5;
      final rightW = W - s - leftW;
      final h1 = (rightH - s) / 2;
      return _AlbumLayoutResult(W, rightH, [
        Rect.fromLTWH(0, 0, leftW, rightH),
        Rect.fromLTWH(leftW + s, 0, rightW, h1),
        Rect.fromLTWH(leftW + s, h1 + s, rightW, rightH - h1 - s),
      ]);
    }

    // Top row + two below.
    final topH = math.min(W / r0, W * 0.66);
    final botH = (W - s) / (r1 + r2);
    final w1 = botH * r1;
    final w2 = W - s - w1;
    final totalH = topH + s + botH;
    return _AlbumLayoutResult(W, totalH, [
      Rect.fromLTWH(0, 0, W, topH),
      Rect.fromLTWH(0, topH + s, w1, botH),
      Rect.fromLTWH(w1 + s, topH + s, w2, botH),
    ]);
  }

  _AlbumLayoutResult _layout4(List<double> ratios, double W, double s) {
    final r0 = ratios[0];
    final p0 = _proportion(r0);

    if (p0 == 'w') {
      // Wide top + three below.
      final topH = math.min(W / r0, W * 0.66);
      final botH = (W - 2 * s) / (ratios[1] + ratios[2] + ratios[3]);
      final w1 = botH * ratios[1];
      final w2 = botH * ratios[2];
      final w3 = W - 2 * s - w1 - w2;
      return _AlbumLayoutResult(W, topH + s + botH, [
        Rect.fromLTWH(0, 0, W, topH),
        Rect.fromLTWH(0, topH + s, w1, botH),
        Rect.fromLTWH(w1 + s, topH + s, w2, botH),
        Rect.fromLTWH(w1 + w2 + 2 * s, topH + s, w3, botH),
      ]);
    }

    // Left column + three stacked right.
    final totalH = W * 0.75;
    final leftW = math.max(_minWidth, math.min(W * 0.4, totalH * r0));
    final rightW = W - s - leftW;
    final rowH = (totalH - 2 * s) / 3;
    return _AlbumLayoutResult(W, totalH, [
      Rect.fromLTWH(0, 0, leftW, totalH),
      Rect.fromLTWH(leftW + s, 0, rightW, rowH),
      Rect.fromLTWH(leftW + s, rowH + s, rightW, rowH),
      Rect.fromLTWH(leftW + s, 2 * (rowH + s), rightW, totalH - 2 * (rowH + s)),
    ]);
  }

  _AlbumLayoutResult _layoutComplex(List<double> ratios, double W, double s) {
    final n = ratios.length;
    final avgRatio = ratios.reduce((a, b) => a + b) / n;
    final maxH = W * 4 / 3;

    final clamped = ratios.map((r) {
      if (avgRatio > 1.1) return r.clamp(1.0, 2.75);
      return r.clamp(0.6667, 1.0);
    }).toList();

    // Generate all valid row splits (2-4 rows, max 3 per row, 4 allowed on row 2 if avgRatio < 0.85).
    _AlbumLayoutResult? best;
    double bestDiff = double.infinity;

    for (final split in _generateSplits(n, avgRatio)) {
      double totalH = 0;
      final rects = <Rect>[];
      double y = 0;
      bool valid = true;

      for (final rowItems in split) {
        final rowRatios = <double>[];
        for (final idx in rowItems) {
          rowRatios.add(clamped[idx]);
        }
        final sumR = rowRatios.reduce((a, b) => a + b);
        final lineH = (W - (rowItems.length - 1) * s) / sumR;

        if (lineH < _minWidth * 0.5) { valid = false; break; }

        double x = 0;
        for (int j = 0; j < rowItems.length; j++) {
          final w = lineH * rowRatios[j];
          rects.add(Rect.fromLTWH(x, y, j == rowItems.length - 1 ? W - x : w, lineH));
          x += w + s;
        }
        y += lineH + s;
        totalH += lineH + s;
      }

      if (!valid) continue;
      totalH -= s;

      double diff = (totalH - maxH).abs();
      bool anySmall = false;
      for (final rowItems in split) {
        final sumR = rowItems.map((i) => clamped[i]).reduce((a, b) => a + b);
        final lh = (W - (rowItems.length - 1) * s) / sumR;
        if (lh < _minWidth) anySmall = true;
      }
      if (anySmall) diff *= 1.5;
      for (int ri = 0; ri < split.length - 1; ri++) {
        if (split[ri].length > split[ri + 1].length) { diff *= 1.5; break; }
      }

      if (diff < bestDiff) {
        bestDiff = diff;
        best = _AlbumLayoutResult(W, totalH, rects);
      }
    }

    if (best != null) return best;

    // Fallback: simple grid.
    final cols = n <= 4 ? 2 : 3;
    final rows = (n / cols).ceil();
    final cellW = (W - (cols - 1) * s) / cols;
    final cellH = cellW;
    final rects = <Rect>[];
    for (int i = 0; i < n; i++) {
      final row = i ~/ cols;
      final col = i % cols;
      rects.add(Rect.fromLTWH(col * (cellW + s), row * (cellH + s), cellW, cellH));
    }
    return _AlbumLayoutResult(W, rows * cellH + (rows - 1) * s, rects);
  }

  List<List<List<int>>> _generateSplits(int n, double avgRatio) {
    final results = <List<List<int>>>[];
    final maxPerRow = 3;
    final allow4 = avgRatio < 0.85;

    void recurse(int start, List<List<int>> current, int rowIdx) {
      if (start == n) {
        if (current.length >= 2) results.add(List.from(current.map((r) => List.from(r))));
        return;
      }
      if (current.length >= 4) return;
      final remaining = n - start;
      final maxRows = 4 - current.length;
      if (remaining > maxRows * maxPerRow + (allow4 ? 1 : 0)) return;

      final maxThisRow = (rowIdx == 1 && allow4) ? 4 : maxPerRow;
      for (int count = 1; count <= math.min(maxThisRow, remaining); count++) {
        final row = List.generate(count, (j) => start + j);
        current.add(row);
        recurse(start + count, current, rowIdx + 1);
        current.removeLast();
      }
    }

    recurse(0, [], 0);
    return results;
  }
}

class _AlbumLayoutResult {
  final double totalWidth;
  final double totalHeight;
  final List<Rect> rects;
  const _AlbumLayoutResult(this.totalWidth, this.totalHeight, this.rects);
}

class _AlbumThumb extends StatefulWidget {
  final CachedMessage message;
  final List<CachedMessage> allMessages;
  final BorderRadius borderRadius;

  const _AlbumThumb({
    required this.message,
    this.allMessages = const [],
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<_AlbumThumb> createState() => _AlbumThumbState();
}

class _AlbumThumbState extends State<_AlbumThumb> {
  Uint8List? _thumbBytes;
  String _lastThumbB64 = '';

  @override
  void initState() {
    super.initState();
    _decodeThumb();
  }

  @override
  void didUpdateWidget(_AlbumThumb old) {
    super.didUpdateWidget(old);
    if (widget.message.mediaThumbB64 != old.message.mediaThumbB64) _decodeThumb();
  }

  void _decodeThumb() {
    if (widget.message.mediaThumbB64.isNotEmpty &&
        widget.message.mediaThumbB64 != _lastThumbB64) {
      try {
        _thumbBytes = base64Decode(widget.message.mediaThumbB64);
        _lastThumbB64 = widget.message.mediaThumbB64;
      } catch (_) {
        _thumbBytes = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final hasLocal = msg.mediaLocalPath.isNotEmpty;
    final canOpen = hasLocal &&
        (msg.mediaType == 1 || msg.mediaType == 2 || msg.mediaType == 7);

    Widget image;
    if (hasLocal) {
      image = Image.file(
        File(msg.mediaLocalPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbOrPlaceholder(),
      );
    } else {
      image = _thumbOrPlaceholder();
    }

    return Builder(
      builder: (thumbCtx) => GestureDetector(
      onTap: canOpen
          ? () {
              final box = thumbCtx.findRenderObject() as RenderBox?;
              final sourceRect = box != null
                  ? box.localToGlobal(Offset.zero) & box.size
                  : null;
              MediaViewer.open(context, message: msg, allMessages: widget.allMessages, sourceRect: sourceRect);
            }
          : null,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              if (msg.mediaType == 2 || msg.mediaType == 7)
                Center(
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      msg.mediaType == 7 ? Icons.gif : Icons.play_arrow,
                      color: Colors.white, size: 18,
                    ),
                  ),
                ),
              if (msg.mediaType == 2 && msg.mediaDuration > 0)
                Positioned(
                  bottom: 2, right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _VisualMedia._formatDuration(msg.mediaDuration),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),  // Builder
    );
  }

  Widget _thumbOrPlaceholder() {
    if (_thumbBytes != null) {
      return Image.memory(_thumbBytes!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(color: Colors.grey.shade800,
      child: const Center(child: Icon(Icons.image, color: Colors.white38, size: 24)));
  }
}

class _VideoNoteProgressPainter extends CustomPainter {
  final double progress;
  final Color color;

  _VideoNoteProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;
    const strokeWidth = 3.0;
    const inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset, inset,
      size.width - strokeWidth, size.height - strokeWidth,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(_VideoNoteProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

// ── Poll Widget (spec §6.11) ──
// Question text, radio/checkbox options, idle 0.7 / hover 1.0 opacity, 120ms toggle.
class _PollWidget extends StatefulWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _PollWidget({required this.message, required this.theme});

  @override
  State<_PollWidget> createState() => _PollWidgetState();
}

class _PollWidgetState extends State<_PollWidget>
    with TickerProviderStateMixin {
  final Set<int> _selectedIndices = {};
  int _hoveredIndex = -1;
  bool _hasVoted = false;
  bool _showFireworks = false;
  late final AnimationController _barAnim;
  late final Animation<double> _barCurve;
  late final AnimationController _shakeAnim;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _barAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _barCurve = CurvedAnimation(parent: _barAnim, curve: Curves.easeOutCirc);
    _shakeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    bool preVoted = false;
    for (int i = 0; i < widget.message.pollOptions.length; i++) {
      if (widget.message.pollOptions[i].chosen) {
        _selectedIndices.add(i);
        preVoted = true;
      }
    }
    if (preVoted || widget.message.pollClosed) {
      _hasVoted = true;
      _barAnim.value = 1.0;
    }
    _startCountdownIfNeeded();
  }

  void _startCountdownIfNeeded() {
    final closeDate = widget.message.pollCloseDate;
    if (closeDate <= 0 || widget.message.pollClosed) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _remainingSeconds = closeDate - now;
    if (_remainingSeconds <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _barAnim.dispose();
    _shakeAnim.dispose();
    super.dispose();
  }

  double _shakeRotation(double t) {
    const segments = 8;
    final phase = (t * segments) % 1.0;
    final seg = (t * segments).floor() % 4;
    double v;
    switch (seg) {
      case 0: v = -phase; break;
      case 1: v = phase - 1.0; break;
      case 2: v = phase; break;
      default: v = 1.0 - phase; break;
    }
    return v * 3.0 * 3.14159 / 180.0;
  }

  double _shakeScale(double t) {
    const segments = 2;
    final phase = (t * segments) % 1.0;
    final seg = (t * segments).floor() % 4;
    double v;
    switch (seg) {
      case 0: v = -phase; break;
      case 1: v = phase - 1.0; break;
      case 2: v = phase; break;
      default: v = 1.0 - phase; break;
    }
    return 1.0 + v * 0.03;
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isDark = widget.theme.brightness == Brightness.dark;
    final isMultiple = msg.pollMultiple;
    final isClosed = msg.pollClosed;
    final isQuiz = msg.pollQuiz;
    final showResults = _hasVoted || isClosed;
    final totalVoters = msg.pollTotalVoters;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            msg.pollQuestion,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isQuiz ? 'Quiz' : (isMultiple ? 'Multiple answers' : 'Anonymous Poll'),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const SizedBox(height: 8),
          if (showResults)
            AnimatedBuilder(
              animation: _barCurve,
              builder: (context, _) {
                return Column(
                  children: List.generate(msg.pollOptions.length, (i) {
                    final opt = msg.pollOptions[i];
                    final pct = totalVoters > 0
                        ? (opt.voters / totalVoters)
                        : 0.0;
                    return _PollResultRow(
                      text: opt.text,
                      percentage: pct,
                      animValue: _barCurve.value,
                      isChosen: opt.chosen,
                      isDark: isDark,
                      isCorrect: opt.correct,
                      isQuiz: isQuiz,
                    );
                  }),
                );
              },
            )
          else
            ...List.generate(msg.pollOptions.length, (i) {
              final isSelected = _selectedIndices.contains(i);
              final isHovered = _hoveredIndex == i;
              return _PollOptionRow(
                text: msg.pollOptions[i].text,
                isMultiple: isMultiple,
                isSelected: isSelected,
                isHovered: isHovered,
                canVote: true,
                isDark: isDark,
                onHover: (h) => setState(() => _hoveredIndex = h ? i : -1),
                onTap: () => _onOptionTap(i),
              );
            }),
          if (msg.pollMultiple && _selectedIndices.isNotEmpty && !_hasVoted)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                height: 34,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _hasVoted = true;
                      _barAnim.forward();
                    });
                    _submitVote(_selectedIndices.toList());
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: context.palette.dialogsUnreadBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Vote', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          if (totalVoters > 0 || _hasVoted || msg.pollCloseDate > 0)
            _buildPollFooter(msg, totalVoters, isDark),
        ],
      ),
    );

    if (_shakeAnim.isAnimating) {
      content = AnimatedBuilder(
        animation: _shakeAnim,
        builder: (context, child) {
          final t = _shakeAnim.value;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..rotateZ(_shakeRotation(t))
              ..scale(_shakeScale(t)),
            child: child,
          );
        },
        child: content,
      );
    }

    if (_showFireworks) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 480,
                  height: 320,
                  child: _PollFireworks(
                    onComplete: () {
                      if (mounted) setState(() => _showFireworks = false);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }

  Widget _buildPollFooter(CachedMessage msg, int totalVoters, bool isDark) {
    final footerColor = isDark ? Colors.white54 : Colors.black45;
    final footerStyle = TextStyle(fontSize: 12, color: footerColor);
    final recentVoters = msg.pollRecentVoters;
    final hasCountdown = _remainingSeconds > 0 && !msg.pollClosed;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (recentVoters.isNotEmpty) ...[
            SizedBox(
              width: recentVoters.length * 16.0 + 8.0,
              height: 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int i = 0; i < recentVoters.length && i < 3; i++)
                    Positioned(
                      left: i * 14.0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.palette.dialogsUnreadBg,
                          border: Border.all(
                            color: context.palette.windowBg,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            recentVoters[i].length > 1
                                ? recentVoters[i]
                                    .substring(recentVoters[i].length - 1)
                                : '?',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          Text(
            '$totalVoters vote${totalVoters == 1 ? '' : 's'}',
            style: footerStyle,
          ),
          if (hasCountdown) ...[
            Text(' · ', style: footerStyle),
            Text(
              _formatCountdown(_remainingSeconds),
              style: footerStyle,
            ),
          ],
        ],
      ),
    );
  }

  static String _formatCountdown(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  void _onOptionTap(int index) {
    if (_hasVoted && !widget.message.pollMultiple) return;
    setState(() {
      if (widget.message.pollMultiple) {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      } else {
        _selectedIndices.clear();
        _selectedIndices.add(index);
        _hasVoted = true;
        _barAnim.forward();
        if (widget.message.pollQuiz) {
          final chosenOpt = widget.message.pollOptions[index];
          if (chosenOpt.correct) {
            _showFireworks = true;
          } else {
            _shakeAnim.forward(from: 0.0);
          }
        }
        _submitVote([index]);
      }
    });
  }

  void _submitVote(List<int> indices) {
    final chatState = context.read<ChatState>();
    chatState.votePoll(widget.message.msgId, indices);
  }
}

class _PollResultRow extends StatelessWidget {
  final String text;
  final double percentage;
  final double animValue;
  final bool isChosen;
  final bool isDark;
  final bool isCorrect;
  final bool isQuiz;

  const _PollResultRow({
    required this.text,
    required this.percentage,
    required this.animValue,
    required this.isChosen,
    required this.isDark,
    this.isCorrect = false,
    this.isQuiz = false,
  });

  @override
  Widget build(BuildContext context) {
    final prp = context.palette;
    final pctValue = (percentage * animValue * 100).round();
    Color barColor;
    if (isQuiz) {
      if (isCorrect) {
        barColor = const Color(0xFF4CAF50);
      } else if (isChosen) {
        barColor = const Color(0xFFE53935);
      } else {
        barColor = isDark ? const Color(0xFF3E546A) : const Color(0xFFDEE5EB);
      }
    } else {
      barColor = isChosen
          ? prp.windowBgActive
          : (isDark ? const Color(0xFF3E546A) : const Color(0xFFDEE5EB));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isQuiz && (isCorrect || isChosen))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCorrect
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFE53935),
                    ),
                    child: Icon(
                      isCorrect ? Icons.check : Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pctValue%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fillWidth =
                      constraints.maxWidth * percentage * animValue;
                  return Stack(
                    children: [
                      Container(
                        color: isDark
                            ? const Color(0xFF2B3640)
                            : const Color(0xFFF0F0F0),
                      ),
                      Container(
                        width: fillWidth,
                        color: barColor,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  final String text;
  final bool isMultiple;
  final bool isSelected;
  final bool isHovered;
  final bool canVote;
  final bool isDark;
  final ValueChanged<bool> onHover;
  final VoidCallback? onTap;

  const _PollOptionRow({
    required this.text,
    required this.isMultiple,
    required this.isSelected,
    required this.isHovered,
    required this.canVote,
    required this.isDark,
    required this.onHover,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: canVote ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              AnimatedOpacity(
                opacity: isHovered ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 120),
                child: _buildIndicator(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndicator(BuildContext context) {
    const size = 18.0;
    const stroke = 2.0;
    final accentColor = context.palette.windowBgActive;
    final uncheckedColor = isDark ? const Color(0xFF7E8B95) : const Color(0xFF9DA5AB);

    if (isMultiple) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? accentColor : uncheckedColor,
            width: stroke,
          ),
          color: isSelected ? accentColor : Colors.transparent,
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? accentColor : uncheckedColor,
          width: stroke,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: size - stroke * 2,
                height: size - stroke * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                ),
                child: Icon(Icons.check, size: size - stroke * 2 - 2, color: Colors.white),
              ),
            )
          : null,
    );
  }
}

class _PollFireworks extends StatefulWidget {
  final VoidCallback onComplete;
  const _PollFireworks({required this.onComplete});

  @override
  State<_PollFireworks> createState() => _PollFireworksState();
}

class _PollFireworksState extends State<_PollFireworks>
    with SingleTickerProviderStateMixin {
  static const _colors = [
    Color(0xFFE8BC2C), Color(0xFFD0049E), Color(0xFF02CBFE),
    Color(0xFF5723FD), Color(0xFFFE8C27), Color(0xFF6CB859),
  ];
  static const _particleCount = 60;
  static const _fallCount = 30;

  late final List<_Particle> _particles;
  late final AnimationController _ctrl;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _particles = List.generate(_particleCount + _fallCount, (i) {
      final isFall = i >= _particleCount;
      return _Particle(
        color: _colors[_rng.nextInt(_colors.length)],
        x: _rng.nextDouble(),
        y: isFall ? -0.1 - _rng.nextDouble() * 0.3 : 0.3 + _rng.nextDouble() * 0.4,
        vx: (_rng.nextDouble() - 0.5) * (isFall ? 0.3 : 1.2),
        vy: isFall
            ? 0.2 + _rng.nextDouble() * 0.5
            : -0.5 - _rng.nextDouble() * 1.0,
        rotation: _rng.nextDouble() * 6.28,
        rotSpeed: (_rng.nextDouble() - 0.5) * 8,
        size: 4.0,
        isFall: isFall,
      );
    });
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onComplete();
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _FireworksPainter(
            particles: _particles,
            progress: _ctrl.value,
          ),
        );
      },
    );
  }
}

class _Particle {
  final Color color;
  double x, y, vx, vy, rotation, rotSpeed, size;
  final bool isFall;
  _Particle({
    required this.color, required this.x, required this.y,
    required this.vx, required this.vy, required this.rotation,
    required this.rotSpeed, required this.size, required this.isFall,
  });
}

class _FireworksPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  _FireworksPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final speed = progress > 0.5 ? math.max(0.2, 1.0 - (progress - 0.5) * 1.6) : 1.0;
    for (final p in particles) {
      if (p.isFall && progress < 0.3) continue;
      final t = p.isFall ? (progress - 0.3) / 0.7 : progress;
      if (t < 0 || t > 1) continue;
      final px = (p.x + p.vx * t * speed) * size.width;
      final py = (p.y + p.vy * t * speed + 0.5 * t * t) * size.height;
      final alpha = (1.0 - t).clamp(0.0, 1.0);
      if (alpha <= 0 || px < -10 || px > size.width + 10 ||
          py < -10 || py > size.height + 10) continue;
      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation + p.rotSpeed * t);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) => old.progress != progress;
}

class _SquareFromHeight extends SingleChildRenderObjectWidget {
  const _SquareFromHeight({required Widget child}) : super(child: child);
  @override
  _RenderSquareFromHeight createRenderObject(BuildContext context) =>
      _RenderSquareFromHeight();
}

class _RenderSquareFromHeight extends RenderProxyBox {
  static const _min = 48.0;

  @override
  double computeMinIntrinsicWidth(double height) =>
      height.isFinite && height > 0 ? height : _min;
  @override
  double computeMaxIntrinsicWidth(double height) =>
      computeMinIntrinsicWidth(height);
  @override
  double computeMinIntrinsicHeight(double width) => _min;
  @override
  double computeMaxIntrinsicHeight(double width) => _min;

  @override
  void performLayout() {
    final h = constraints.maxHeight.isFinite
        ? math.max(constraints.maxHeight, _min)
        : _min;
    child?.layout(BoxConstraints.tight(Size(h, h)), parentUsesSize: true);
    size = Size(h, h);
  }
}

// ── Web Page Preview ──
// Spec §6.14: Two modes — Article (small thumbnail right, text wraps) and
// Standard (full-width, media below text). Mode selected by type, not dimensions.
class _WebPagePreview extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;
  final bool isDark;
  final bool isOutgoing;

  const _WebPagePreview({
    required this.message,
    required this.theme,
    required this.isDark,
    required this.isOutgoing,
  });

  static const _accentBlue = Color(0xFF168acd);
  static const _accentBlueNight = Color(0xFF71baf7);

  bool _useArticleMode() {
    if (message.wpForceLargeMedia) return false;
    if (message.wpForceSmallMedia) return true;
    final t = message.wpType.toLowerCase();
    if (t == 'profile') return true;
    if (t == 'video' || t == 'gif' || t == 'document' || t == 'photo' || t == 'story') return false;
    if (t.startsWith('telegram_')) return false;
    if (t == 'article_with_iv') return false;
    final site = message.wpSiteName.toLowerCase();
    if (site.contains('twitter') || site == 'x' || site.startsWith('x (') || site.contains('facebook')) return false;
    if (message.wpThumbB64.isNotEmpty &&
        (message.wpSiteName.isNotEmpty || message.wpTitle.isNotEmpty || message.wpDescription.isNotEmpty)) {
      return true;
    }
    return false;
  }

  String? _actionButtonLabel() {
    final t = message.wpType.toLowerCase();
    switch (t) {
      case 'article_with_iv': return 'INSTANT VIEW';
      case 'telegram_theme': return 'VIEW THEME';
      case 'telegram_story': return 'VIEW STORY';
      case 'telegram_message': return 'VIEW MESSAGE';
      case 'telegram_megagroup':
      case 'telegram_chat': return 'VIEW GROUP';
      case 'telegram_background': return 'VIEW BACKGROUND';
      case 'telegram_channel': return 'VIEW CHANNEL';
      case 'telegram_channel_request':
      case 'telegram_megagroup_request':
      case 'telegram_chat_request': return 'REQUEST TO JOIN';
      case 'telegram_channel_boost':
      case 'telegram_megagroup_boost': return 'BOOST';
      case 'telegram_giftcode': return 'OPEN GIFT LINK';
      case 'telegram_user': return 'SEND MESSAGE';
      case 'telegram_voicechat': return 'JOIN VOICE CHAT';
      case 'telegram_livestream': return 'JOIN LIVESTREAM';
      case 'telegram_botapp': return 'OPEN APP';
      case 'telegram_stickerset': return 'VIEW STICKERS';
      case 'telegram_newbot': return 'START BOT';
      default:
        if (message.wpHasIv) return 'INSTANT VIEW';
        return null;
    }
  }

  int _descMaxLines() {
    int lines = 3;
    if (message.wpSiteName.isEmpty) lines++;
    if (message.wpTitle.isEmpty) lines++;
    return lines;
  }

  static final _mentionHashtagRe = RegExp(r'([@#][\w.]+)');

  Widget _buildDescription(Color accentColor) {
    final descStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: isDark ? const Color(0xFFc0c8d0) : const Color(0xFF444444),
    );
    final site = message.wpSiteName.toLowerCase();
    final isTwitter = site.contains('twitter') || site == 'x' || site.startsWith('x (');
    final isInstagram = site.contains('instagram');
    if (!isTwitter && !isInstagram) {
      return Text(message.wpDescription, style: descStyle, maxLines: _descMaxLines(), overflow: TextOverflow.ellipsis);
    }
    final spans = <InlineSpan>[];
    int pos = 0;
    for (final m in _mentionHashtagRe.allMatches(message.wpDescription)) {
      if (m.start > pos) {
        spans.add(TextSpan(text: message.wpDescription.substring(pos, m.start), style: descStyle));
      }
      final token = m.group(0)!;
      final name = token.substring(1);
      String url;
      if (isInstagram) {
        url = token.startsWith('@') ? 'https://instagram.com/$name' : 'https://instagram.com/explore/tags/$name';
      } else {
        url = token.startsWith('@') ? 'https://x.com/$name' : 'https://x.com/hashtag/$name';
      }
      spans.add(TextSpan(
        text: token,
        style: descStyle.copyWith(color: accentColor),
        recognizer: TapGestureRecognizer()..onTap = () => Process.run('xdg-open', [url]),
      ));
      pos = m.end;
    }
    if (pos < message.wpDescription.length) {
      spans.add(TextSpan(text: message.wpDescription.substring(pos), style: descStyle));
    }
    return RichText(text: TextSpan(children: spans), maxLines: _descMaxLines(), overflow: TextOverflow.ellipsis);
  }

  Widget? _buildActionButton(BuildContext context, Color accentColor) {
    final label = _actionButtonLabel();
    if (label == null) return null;
    final dividerColor = accentColor.withAlpha((255 * 0.3).round());
    return GestureDetector(
      onTap: () {
        final url = message.wpUrl;
        if (url.isEmpty) return;
        if (message.wpType.toLowerCase() == 'article_with_iv' || message.wpHasIv) {
          openInstantView(context, message.accountId, url, siteName: message.wpSiteName);
        } else {
          Process.run('xdg-open', [url]);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(height: 1, color: dividerColor),
          SizedBox(
            height: 36,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark ? _accentBlueNight : _accentBlue;
    final isArticle = _useArticleMode();
    final isVideo = message.wpType.toLowerCase() == 'video' ||
        message.wpType.toLowerCase() == 'gif';

    Widget? thumbWidget;
    if (message.wpThumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(message.wpThumbB64);
        thumbWidget = Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => SizedBox(
            width: double.infinity,
            height: isArticle ? null : 100,
            child: ColoredBox(color: isDark ? const Color(0xFF2a3a4a) : const Color(0xFFe8ecf0)),
          ),
        );
      } catch (_) {}
    }

    final textWidgets = <Widget>[];

    if (message.wpSiteName.isNotEmpty) {
      textWidgets.add(Text(
        message.wpSiteName,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: accentColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    }

    if (message.wpTitle.isNotEmpty) {
      textWidgets.add(Text(
        message.wpTitle,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ));
    }

    if (message.wpDescription.isNotEmpty) {
      textWidgets.add(_buildDescription(accentColor));
    }

    final actionButton = _buildActionButton(context, accentColor);

    if (isArticle) {
      return Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accentColor, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: textWidgets,
                    ),
                  ),
                  if (thumbWidget != null) ...[
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: _SquareFromHeight(child: thumbWidget),
                    ),
                  ],
                ],
              ),
            ),
            if (actionButton != null) actionButton,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accentColor, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...textWidgets,
          if (thumbWidget != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  thumbWidget,
                  if (isVideo)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                    ),
                ],
              ),
            ),
          ],
          if (actionButton != null) actionButton,
        ],
      ),
    );
  }
}

class _GameCard extends StatefulWidget {
  final CachedMessage message;
  final ThemeData theme;
  final bool isDark;
  final bool isOutgoing;

  const _GameCard({
    required this.message,
    required this.theme,
    required this.isDark,
    required this.isOutgoing,
  });

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _hovering = false;
  bool _loading = false;

  void _onPlay() async {
    if (_loading) return;
    setState(() => _loading = true);
    String? url;
    for (final row in widget.message.inlineKeyboard) {
      for (final btn in row) {
        if (btn.type == 'game' && btn.url.isNotEmpty) {
          url = btn.url;
          break;
        }
      }
      if (url != null) break;
    }
    if (url != null) {
      await Process.run('xdg-open', [url]);
      if (mounted) setState(() => _loading = false);
    } else {
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isDark = widget.isDark;
    final isOut = widget.isOutgoing;

    final titleColor = isDark ? Colors.white : Colors.black87;
    final descColor = isDark ? const Color(0xFFc0c8d0) : const Color(0xFF444444);
    final buttonFg = isOut
        ? (isDark ? const Color(0xFF60c071) : const Color(0xFF4fae5e))
        : (isDark ? const Color(0xFF71baf7) : const Color(0xFF168acd));
    final lineFg = isDark ? const Color(0xFF3a4a5a) : const Color(0xFFdde1e5);
    final badgeBg = const Color(0x73000000);

    Widget? thumb;
    if (msg.gameThumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(msg.gameThumbB64);
        thumb = Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (msg.gameTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 5, 11, 0),
            child: Text(
              msg.gameTitle,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: titleColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (msg.gameDescription.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 5, 11, 0),
            child: Text(
              msg.gameDescription,
              style: TextStyle(fontSize: 13, color: descColor),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (thumb != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Stack(
              children: [
                ClipRRect(
                  child: AspectRatio(
                    aspectRatio: msg.gamePhotoW > 0 && msg.gamePhotoH > 0
                        ? msg.gamePhotoW / msg.gamePhotoH
                        : 16 / 9,
                    child: thumb,
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'GAME',
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          height: 1,
          color: lineFg,
          margin: const EdgeInsets.only(top: 5),
        ),
        MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: _onPlay,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 36,
              alignment: Alignment.center,
              color: _hovering
                  ? buttonFg.withValues(alpha: 0.12)
                  : Colors.transparent,
              child: _loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: buttonFg,
                      ),
                    )
                  : Text(
                      'PLAY GAME',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: buttonFg,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineKeyboard extends StatelessWidget {
  final List<List<InlineKeyboardButton>> rows;
  final String messageId;
  final bool isOutgoing;
  final bool isDark;

  const _InlineKeyboard({
    required this.rows,
    required this.messageId,
    required this.isOutgoing,
    required this.isDark,
  });

  static const _buttonHeight = 36.0;
  static const _buttonMargin = 2.0;
  static const _buttonPadding = 10.0;
  static const _iconPadding = 4.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: _buttonMargin),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int r = 0; r < rows.length; r++)
            Padding(
              padding: EdgeInsets.only(top: r > 0 ? _buttonMargin : 0),
              child: Row(
                children: [
                  for (int c = 0; c < rows[r].length; c++) ...[
                    if (c > 0) const SizedBox(width: _buttonMargin),
                    Expanded(
                      child: _InlineButton(
                        button: rows[r][c],
                        messageId: messageId,
                        isOutgoing: isOutgoing,
                        isDark: isDark,
                        isTopLeft: r == 0 && c == 0,
                        isTopRight: r == 0 && c == rows[r].length - 1,
                        isBottomLeft: r == rows.length - 1 && c == 0,
                        isBottomRight: r == rows.length - 1 && c == rows[r].length - 1,
                      ),
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

Future<Map<String, dynamic>?> showUrlAuthDialog(
  BuildContext context,
  Map<String, dynamic> authData,
  String fallbackUrl,
) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _UrlAuthDialog(authData: authData, fallbackUrl: fallbackUrl),
  );
}

class _UrlAuthDialog extends StatefulWidget {
  final Map<String, dynamic> authData;
  final String fallbackUrl;
  const _UrlAuthDialog({required this.authData, required this.fallbackUrl});
  @override
  State<_UrlAuthDialog> createState() => _UrlAuthDialogState();
}

class _UrlAuthDialogState extends State<_UrlAuthDialog> {
  late bool _authorize;
  late bool _allowMessages;

  @override
  void initState() {
    super.initState();
    _authorize = true;
    _allowMessages = widget.authData['request_write_access'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final domain = widget.authData['domain'] as String? ?? '';
    final botName = widget.authData['bot_name'] as String? ?? '';
    final botVerified = widget.authData['bot_verified'] == true;
    final verifiedAppName = widget.authData['verified_app_name'] as String? ?? '';
    final browser = widget.authData['browser'] as String? ?? '';
    final platform = widget.authData['platform'] as String? ?? '';
    final ip = widget.authData['ip'] as String? ?? '';
    final region = widget.authData['region'] as String? ?? '';
    final hasBotName = botName.isNotEmpty;
    final hasDeviceInfo = browser.isNotEmpty || platform.isNotEmpty;
    final hasLocationInfo = ip.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Log in to '),
                        if (verifiedAppName.isEmpty)
                          TextSpan(
                            text: '(unverified) ',
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 14),
                          ),
                        TextSpan(
                          text: domain,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ]),
                      style: TextStyle(fontSize: 14, color: theme.textTheme.bodyLarge?.color),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
            if (hasBotName) ...[
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.palette.windowBgActive,
                  ),
                  child: Center(
                    child: Text(
                      botName.isNotEmpty ? botName[0].toUpperCase() : 'B',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        botName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (botVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 16, color: context.palette.windowBgActive),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (hasDeviceInfo || hasLocationInfo) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                child: Column(
                  children: [
                    if (hasDeviceInfo)
                      _buildInfoRow(
                        Icons.devices,
                        '${browser.isNotEmpty ? browser : "Unknown browser"} on ${platform.isNotEmpty ? platform : "Unknown platform"}',
                        theme,
                      ),
                    if (hasDeviceInfo && hasLocationInfo) const SizedBox(height: 8),
                    if (hasLocationInfo)
                      _buildInfoRow(
                        Icons.location_on_outlined,
                        '${ip}${region.isNotEmpty ? ' ($region)' : ''}',
                        theme,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Column(
                children: [
                  _buildCheckbox(
                    'Log in as ${_getCurrentUserName(context)}',
                    _authorize,
                    (v) => setState(() {
                      _authorize = v ?? false;
                      if (!_authorize) _allowMessages = false;
                    }),
                    enabled: true,
                    theme: theme,
                  ),
                  if (hasBotName) ...[
                    const SizedBox(height: 4),
                    _buildCheckbox(
                      'Allow $botName to message me',
                      _allowMessages,
                      (v) => setState(() => _allowMessages = v ?? false),
                      enabled: _authorize,
                      theme: theme,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop({
                      'action': 'accept',
                      'write_allowed': _authorize && _allowMessages,
                      'share_phone': false,
                    }),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text(_authorize ? 'Log in' : 'Open link'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: theme.textTheme.bodyLarge?.color),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged, {required bool enabled, required ThemeData theme}) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value,
            onChanged: enabled ? onChanged : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: enabled ? () => onChanged(!value) : null,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: enabled ? theme.textTheme.bodyLarge?.color : theme.disabledColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getCurrentUserName(BuildContext context) {
    try {
      final appState = context.read<AppState>();
      final active = appState.activeAccount;
      if (active != null) return active.displayName;
    } catch (_) {}
    return 'your account';
  }
}

class _InlineButton extends StatefulWidget {
  final InlineKeyboardButton button;
  final String messageId;
  final bool isOutgoing;
  final bool isDark;
  final bool isTopLeft;
  final bool isTopRight;
  final bool isBottomLeft;
  final bool isBottomRight;

  const _InlineButton({
    required this.button,
    required this.messageId,
    required this.isOutgoing,
    required this.isDark,
    required this.isTopLeft,
    required this.isTopRight,
    required this.isBottomLeft,
    required this.isBottomRight,
  });

  @override
  State<_InlineButton> createState() => _InlineButtonState();
}

class _InlineButtonState extends State<_InlineButton>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final AnimationController _hoverAnim;

  @override
  void initState() {
    super.initState();
    _hoverAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _hoverAnim.dispose();
    super.dispose();
  }

  static const _largeRadius = 10.0;
  static const _smallRadius = 3.0;

  BorderRadius get _borderRadius => BorderRadius.only(
    topLeft: Radius.circular(widget.isTopLeft ? _largeRadius : _smallRadius),
    topRight: Radius.circular(widget.isTopRight ? _largeRadius : _smallRadius),
    bottomLeft: Radius.circular(widget.isBottomLeft ? _largeRadius : _smallRadius),
    bottomRight: Radius.circular(widget.isBottomRight ? _largeRadius : _smallRadius),
  );

  ({Color bg, Color hover, Color text, Color icon}) _colors() {
    final c = widget.button.color;
    if (c != KeyboardButtonColor.normal) {
      if (widget.isDark) {
        return switch (c) {
          KeyboardButtonColor.primary => (bg: const Color(0xFF568bc8), hover: const Color(0xFF6a9dd4), text: Colors.white, icon: const Color(0xCCFFFFFF)),
          KeyboardButtonColor.danger => (bg: const Color(0xFFc44040), hover: const Color(0xFFd05050), text: Colors.white, icon: const Color(0xCCFFFFFF)),
          KeyboardButtonColor.success => (bg: const Color(0xFF49a856), hover: const Color(0xFF5bb868), text: Colors.white, icon: const Color(0xCCFFFFFF)),
          KeyboardButtonColor.normal => throw StateError('unreachable'),
        };
      }
      return switch (c) {
        KeyboardButtonColor.primary => (bg: const Color(0xFF40a7e3), hover: const Color(0xFF56b4e8), text: Colors.white, icon: const Color(0xCCFFFFFF)),
        KeyboardButtonColor.danger => (bg: const Color(0xFFdf3f40), hover: const Color(0xFFe55556), text: Colors.white, icon: const Color(0xCCFFFFFF)),
        KeyboardButtonColor.success => (bg: const Color(0xFF59b660), hover: const Color(0xFF6bc472), text: Colors.white, icon: const Color(0xCCFFFFFF)),
        KeyboardButtonColor.normal => throw StateError('unreachable'),
      };
    }
    if (widget.isDark) {
      return (
        bg: const Color(0x33ffffff),
        hover: const Color(0x44ffffff),
        text: Colors.white,
        icon: const Color(0xAAFFFFFF),
      );
    }
    return (
      bg: const Color(0x13000000),
      hover: const Color(0x22000000),
      text: const Color(0xFF5b97cd),
      icon: const Color(0xFF5b97cd),
    );
  }

  IconData? get _trailingIcon {
    switch (widget.button.type) {
      case 'url':
      case 'url_auth':
        return Icons.open_in_new;
      case 'switch_inline':
        return Icons.alternate_email;
      case 'buy':
        return Icons.credit_card;
      case 'web_view':
      case 'simple_web_view':
        return Icons.language;
      case 'copy':
        return Icons.copy;
      default:
        return null;
    }
  }

  Future<void> _onTap() async {
    final btn = widget.button;
    switch (btn.type) {
      case 'url':
        if (btn.url.isNotEmpty) {
          var url = btn.url;
          if (!url.startsWith('http://') && !url.startsWith('https://')) {
            url = 'https://$url';
          }
          Process.run('xdg-open', [url]);
        }
      case 'url_auth':
        if (_loading) return;
        setState(() => _loading = true);
        try {
          final chatState = context.read<ChatState>();
          final authData = await chatState.requestUrlAuth(widget.messageId, btn.buttonId);
          if (!mounted) return;
          final authType = authData['type'] as String? ?? 'default';
          if (authType == 'request') {
            final result = await showUrlAuthDialog(context, authData, btn.url);
            if (result == null || !mounted) return;
            if (result['action'] == 'accept') {
              final url = await chatState.acceptUrlAuth(
                widget.messageId,
                btn.buttonId,
                result['write_allowed'] as bool? ?? false,
                result['share_phone'] as bool? ?? false,
              );
              final openUrl = url.isNotEmpty ? url : btn.url;
              if (openUrl.isNotEmpty) Process.run('xdg-open', [openUrl]);
              if (mounted) {
                showTelegramToast(context, 'Logged in to ${authData['domain'] ?? 'website'}');
              }
            } else if (result['action'] == 'open') {
              if (btn.url.isNotEmpty) Process.run('xdg-open', [btn.url]);
            }
          } else {
            if (btn.url.isNotEmpty) Process.run('xdg-open', [btn.url]);
          }
        } catch (_) {
          if (btn.url.isNotEmpty) Process.run('xdg-open', [btn.url]);
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      case 'copy':
        if (btn.copyText.isNotEmpty) {
          final data = ClipboardData(text: btn.copyText);
          Clipboard.setData(data);
        }
      case 'callback':
      case 'callback_password':
        if (_loading) return;
        setState(() => _loading = true);
        try {
          final chatState = context.read<ChatState>();
          final answer = await chatState.botCallback(widget.messageId, btn.data);
          if (answer.isNotEmpty && mounted) {
            showTelegramToast(context, answer);
          }
        } catch (_) {
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      case 'switch_inline':
        final chatState = context.read<ChatState>();
        final chat = chatState.activeChat;
        final botUsername = chat?.title ?? '';
        final query = btn.query;
        final text = '@$botUsername $query';
        ChatView.setComposeRequest?.call(text);
      case 'game':
        if (_loading) return;
        setState(() => _loading = true);
        try {
          final chatState = context.read<ChatState>();
          final result = await chatState.botCallbackGame(widget.messageId);
          if (!mounted) return;
          if (result.url.isNotEmpty) {
            Process.run('xdg-open', [result.url]);
          } else if (result.message.isNotEmpty) {
            showTelegramToast(context, result.message);
          }
        } catch (_) {
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      case 'buy':
        final chatState = context.read<ChatState>();
        final chat = chatState.activeChat;
        if (chat != null) {
          PaymentPanel.open(context, data: PaymentPanelData(
            accountId: chat.accountId,
            chatId: chat.chatId,
            msgId: widget.messageId,
            title: btn.text,
            description: '',
            currency: '',
            totalAmount: 0,
            isTest: false,
            isReceipt: false,
            receiptMsgId: 0,
            photoUrl: '',
            botName: chat.title ?? '',
          ));
        }
      case 'web_view':
      case 'simple_web_view':
        if (btn.url.isNotEmpty) {
          final chatState = context.read<ChatState>();
          final chat = chatState.activeChat;
          WebAppPanel.open(
            context,
            data: WebAppPanelData(
              botName: chat?.title ?? 'Web App',
              botUsername: '',
              isVerified: chat?.isVerified ?? false,
              url: btn.url,
              accountId: chat?.accountId ?? '',
              botId: chat?.chatId ?? '',
            ),
          );
        }
      case 'user_profile':
        final userId = btn.data;
        if (userId.isNotEmpty) {
          final chatState = context.read<ChatState>();
          chatState.openChatById(userId);
        }
      case 'request_phone':
        final chatState = context.read<ChatState>();
        final appState = context.read<AppState>();
        final phone = appState.activeAccount?.phone ?? '';
        if (phone.isNotEmpty) {
          chatState.sendMessage(phone);
        }
      case 'request_location':
        _showLocationDialog(context);
      case 'request_poll':
        showCreatePollBox(context).then((result) {
          if (result == null) return;
          final chatState = context.read<ChatState>();
          final chat = chatState.activeChat;
          if (chat == null) return;
          final engine = context.read<EngineService>();
          engine.createPoll(chat.accountId, chat.chatId, result.question, result.options,
              anonymous: result.anonymous, multipleChoice: result.multipleChoice,
              quiz: result.quiz, allowRevoting: result.allowRevoting);
        });
      case 'request_peer':
        _showPeerSelectionDialog(context, int.tryParse(widget.messageId) ?? 0, btn.buttonId);
      default:
        final chatState = context.read<ChatState>();
        chatState.sendMessage(btn.text);
    }
  }

  void _showPeerSelectionDialog(BuildContext context, int msgId, int buttonId) {
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverBg = isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);
    final accentColor = context.palette.windowBgActive;

    final activeId = appState.activeAccountId;
    final allChats = chatState.chatsForAccount(activeId);
    var searchQuery = '';

    showDialog<ChatInfo>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            final filtered = searchQuery.isEmpty
                ? allChats
                : allChats
                    .where((c) => c.title.toLowerCase().contains(searchQuery.toLowerCase()))
                    .toList();
            return Dialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340, maxHeight: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text('Choose a chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: TextStyle(color: subtextColor),
                          prefixIcon: Icon(Icons.search, color: subtextColor),
                          border: InputBorder.none,
                        ),
                        onChanged: (q) => setDialogState(() => searchQuery = q),
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final chat = filtered[i];
                          return InkWell(
                            onTap: () => Navigator.of(dialogCtx).pop(chat),
                            hoverColor: hoverBg,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: accentColor,
                                    child: Text(
                                      chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      chat.title,
                                      style: TextStyle(fontSize: 14, color: textColor),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((selected) {
      if (selected == null) return;
      final chat = chatState.activeChat;
      if (chat == null) return;
      engine.sendBotRequestedPeer(
        chat.accountId,
        chat.chatId,
        msgId,
        buttonId,
        [selected.chatId],
      );
    });
  }

  void _showLocationDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final latController = TextEditingController();
    final lonController = TextEditingController();
    String? error;

    showDialog<(double, double)?>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            return Dialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: latController,
                        style: TextStyle(color: textColor, fontSize: 14),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(
                          labelText: 'Latitude',
                          labelStyle: TextStyle(color: subtextColor),
                          hintText: 'e.g. 51.5074',
                          hintStyle: TextStyle(color: subtextColor.withValues(alpha: 0.5)),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: lonController,
                        style: TextStyle(color: textColor, fontSize: 14),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(
                          labelText: 'Longitude',
                          labelStyle: TextStyle(color: subtextColor),
                          hintText: 'e.g. -0.1278',
                          hintStyle: TextStyle(color: subtextColor.withValues(alpha: 0.5)),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: Text('Cancel', style: TextStyle(color: subtextColor)),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              final lat = double.tryParse(latController.text.trim());
                              final lon = double.tryParse(lonController.text.trim());
                              if (lat == null || lon == null) {
                                setDialogState(() => error = 'Enter valid coordinates');
                                return;
                              }
                              if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
                                setDialogState(() => error = 'Lat: -90..90, Lon: -180..180');
                                return;
                              }
                              Navigator.of(dialogCtx).pop((lat, lon));
                            },
                            child: Text('Send', style: TextStyle(color: context.palette.windowBgActive)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((result) {
      if (result == null) return;
      final chatState = context.read<ChatState>();
      final chat = chatState.activeChat;
      if (chat == null) return;
      final engine = context.read<EngineService>();
      engine.sendLocation(chat.accountId, chat.chatId, result.$1, result.$2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final icon = _trailingIcon;
    final cs = _colors();
    return SizedBox(
      height: _InlineKeyboard._buttonHeight,
      child: MouseRegion(
        onEnter: (_) => _hoverAnim.forward(),
        onExit: (_) => _hoverAnim.reverse(),
        child: GestureDetector(
          onTap: _onTap,
          child: AnimatedBuilder(
            animation: _hoverAnim,
            builder: (context, child) {
              final bg = Color.lerp(cs.bg, cs.hover, _hoverAnim.value)!;
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: _borderRadius,
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _InlineKeyboard._buttonPadding,
                      ),
                      child: Text(
                        widget.button.text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  if (icon != null)
                    Positioned(
                      right: _InlineKeyboard._iconPadding,
                      bottom: _InlineKeyboard._iconPadding,
                      child: Icon(icon, size: 12, color: cs.icon),
                    ),
                  if (_loading)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.bg.withValues(alpha: 0.5),
                          borderRadius: _borderRadius,
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;
  final bool isDark;
  final bool isOutgoing;

  const _InvoiceCard({
    required this.message,
    required this.theme,
    required this.isDark,
    required this.isOutgoing,
  });

  String _formatAmount(int amount, String currency) {
    final abs = amount.abs();
    final major = abs ~/ 100;
    final minor = abs % 100;
    final sym = _currencySymbol(currency);
    if (minor == 0) return '$sym$major';
    return '$sym$major.${minor.toString().padLeft(2, '0')}';
  }

  String _currencySymbol(String code) {
    switch (code.toUpperCase()) {
      case 'USD': return '\$';
      case 'EUR': return '\u20AC';
      case 'GBP': return '\u00A3';
      case 'RUB': return '\u20BD';
      case 'JPY': return '\u00A5';
      default: return '$code ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.white : Colors.black87;
    final descColor = isDark ? const Color(0xFFc0c8d0) : const Color(0xFF444444);
    final buttonFg = isOutgoing
        ? (isDark ? const Color(0xFF60c071) : const Color(0xFF4fae5e))
        : (isDark ? const Color(0xFF71baf7) : const Color(0xFF168acd));
    final lineFg = isDark ? const Color(0xFF3a4a5a) : const Color(0xFFdde1e5);
    final badgeBg = const Color(0x73000000);
    final isReceipt = message.isReceipt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message.invoiceTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 5, 11, 0),
            child: Text(
              message.invoiceTitle,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: titleColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (message.invoiceDescription.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 3, 11, 0),
            child: Text(
              message.invoiceDescription,
              style: TextStyle(fontSize: 13, color: descColor),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(11, 5, 11, 4),
          child: Text(
            _formatAmount(message.invoiceTotalAmount, message.invoiceCurrency),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: titleColor),
          ),
        ),
        if (message.invoiceTest)
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 0, 11, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFe53935),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('TEST', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
          ),
        Container(height: 1, color: lineFg),
        SizedBox(
          height: 36,
          child: InkWell(
            onTap: () => _openPayment(context),
            child: Center(
              child: Text(
                isReceipt ? 'VIEW RECEIPT' : 'PAY',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: buttonFg,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openPayment(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final accountId = appState.activeAccountId;
    PaymentPanel.open(
      context,
      data: PaymentPanelData(
        accountId: accountId,
        chatId: message.chatId,
        msgId: message.msgId,
        title: message.invoiceTitle,
        description: message.invoiceDescription,
        currency: message.invoiceCurrency,
        totalAmount: message.invoiceTotalAmount,
        isTest: message.invoiceTest,
        isReceipt: message.isReceipt,
        receiptMsgId: message.invoiceReceiptMsgId,
        photoUrl: message.invoicePhotoUrl,
        botName: message.senderName,
      ),
    );
  }
}
