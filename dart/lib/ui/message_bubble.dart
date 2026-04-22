import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../bridge/engine_service.dart';
import '../state/audio_service.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import 'media_viewer.dart';
import 'sticker_pack_viewer.dart';

/// Single message bubble. Spec §5: max 430px, 16/6px radius, sender colors.
class MessageBubble extends StatelessWidget {
  final CachedMessage message;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool isGroupChat;
  final String? senderAvatarB64;
  final VoidCallback? onReply;
  final void Function(Offset position)? onContextMenu;
  final ValueChanged<String>? onSenderTap;
  final ValueChanged<String>? onReplyTap;
  final bool isSelected;
  final bool inSelectionMode;
  final List<CachedMessage> allMessages;
  final List<CachedMessage> albumItems;

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
    this.senderAvatarB64,
    this.onReply,
    this.onContextMenu,
    this.onSenderTap,
    this.onReplyTap,
  });

  // Spec: max bubble width 430px.
  static const _maxWidth = 430.0;
  static const _radiusLarge = 16.0;
  static const _radiusSmall = 6.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Determine if this is an outgoing message (set by Go engine per-platform).
    final isOutgoing = message.isOutgoing;

    // AyuGram spec: sticker-only messages render without a bubble background.
    // A sticker-only message has no text body, reply, or forward header — only
    // the sticker image. Sender name (group chats, first-in-group) and timestamp
    // still render, but the background capsule and padding are suppressed.
    final isStickerOnly = message.mediaType == 6 &&
        message.contentText.isEmpty &&
        message.replyPreview.isEmpty &&
        message.forwardFrom.isEmpty;

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

    final bubbleColor = isStickerOnly
        ? Colors.transparent
        : isOutgoing
            ? (isDark
                ? (isSelected ? AppColors.bubbleSentSelected : AppColors.bubbleSent)
                : (isSelected ? AppColors.bubbleSentSelectedLight : AppColors.bubbleSentLight))
            : (isDark
                ? (isSelected ? AppColors.bubbleReceivedSelected : AppColors.bubbleReceived)
                : (isSelected ? AppColors.bubbleReceivedSelectedLight : AppColors.bubbleReceivedLight));

    // Spec §5: 2px bottom shadow strip. Night theme alpha=00 (disabled).
    final shadowColor = isStickerOnly
        ? Colors.transparent
        : isOutgoing
            ? (isDark
                ? (isSelected ? AppColors.bubbleSentShadowSelectedNight : AppColors.bubbleSentShadowNight)
                : (isSelected ? AppColors.bubbleSentShadowSelected : AppColors.bubbleSentShadow))
            : (isDark
                ? (isSelected ? AppColors.bubbleReceivedShadowSelectedNight : AppColors.bubbleReceivedShadowNight)
                : (isSelected ? AppColors.bubbleReceivedShadowSelected : AppColors.bubbleReceivedShadow));

    final alignment = isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    // Spec §5 Consecutive Message Grouping — per-corner radius rules:
    //   Top sender-side:    Large when first-in-group, Small when attached-to-previous.
    //   Top other-side:     Always Large.
    //   Bottom sender-side: Always Small (Small when mid-group, Tail≈Small when last).
    //   Bottom other-side:  Large when last-in-group, Small when attached-to-next.
    final topSenderSide = isFirstInGroup ? _radiusLarge : _radiusSmall;
    final topOtherSide = _radiusLarge;
    final bottomSenderSide = _radiusSmall;
    final bottomOtherSide = isLastInGroup ? _radiusLarge : _radiusSmall;

    // Show sender avatar for incoming messages in group chats.
    final showAvatar = isGroupChat && !isOutgoing;

    // Spec §5: Bubble margins — left 16px, top 6px, right 56px, bottom 2px.
    // Attached-to-previous collapses top to 0px.
    return Padding(
      padding: EdgeInsets.only(
        left: 16.0,
        top: isFirstInGroup ? 6.0 : 0.0,
        right: 56.0,
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
            child: GestureDetector(
            onLongPressStart: onContextMenu != null
                ? (details) => onContextMenu!(details.globalPosition)
                : null,
            onSecondaryTapUp: onContextMenu != null
                ? (details) => onContextMenu!(details.globalPosition)
                : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: showAvatar ? _maxWidth - 40 : _maxWidth),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
              Container(
                padding: isStickerOnly
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: isStickerOnly
                      ? BorderRadius.zero
                      : BorderRadius.only(
                          topLeft: Radius.circular(isOutgoing ? topOtherSide : topSenderSide),
                          topRight: Radius.circular(isOutgoing ? topSenderSide : topOtherSide),
                          bottomLeft: Radius.circular(isOutgoing ? bottomOtherSide : bottomSenderSide),
                          bottomRight: Radius.circular(isOutgoing ? bottomSenderSide : bottomOtherSide),
                        ),
                  boxShadow: isStickerOnly
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
                    if (!isOutgoing && message.senderName.isNotEmpty && isFirstInGroup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: GestureDetector(
                          onTap: onSenderTap != null ? () => onSenderTap!(message.senderId) : null,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: message.senderName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _senderColor(message.senderId, isDark: isDark, colorId: message.senderColorId),
                                  ),
                                ),
                                if (message.senderRank.isNotEmpty)
                                  TextSpan(
                                    text: ' ${message.senderRank}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: _senderColor(message.senderId, isDark: isDark).withValues(alpha: 0.6),
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
                                  color: isDark ? const Color(0xFF6d7f8f) : const Color(0xFFa0acb6),
                                ),
                              ),
                              TextSpan(
                                text: message.viaBotName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFF71baf7) : const Color(0xFF168acd),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Reply preview.
                    if (message.replyPreview.isNotEmpty)
                      _ReplyPreview(
                        preview: message.replyPreview,
                        theme: theme,
                        onTap: (onReplyTap != null && message.replyToId.isNotEmpty)
                            ? () => onReplyTap!(message.replyToId)
                            : null,
                      ),
                    // Forward header.
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
                    // Spec §6: For captioned media (photo/video/GIF + text),
                    // media renders first, caption text below it.
                    // For all other messages, text renders before media.
                    if (!isCaptionedMedia && message.contentText.isNotEmpty && message.mediaType != 9 && message.mediaType != 10)
                      _RichMessageText(
                        text: message.contentText,
                        entitiesJson: message.contentRich,
                        baseStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
                        theme: theme,
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
                      ),
                    // Reactions row — pill badges above the timestamp.
                    if (message.reactions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _ReactionList(
                        reactions: message.reactions,
                        isOutgoing: isOutgoing,
                        theme: theme,
                      ),
                    ],
                    // Bottom info: views + forwards + edited + time + status.
                    // Spec §5: msgInDateFg / msgOutDateFg per theme.
                    // Skipped for media-only bubbles — overlay rendered by _VisualMedia instead.
                    if (!isMediaOnlyBubble) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Spacer(),
                          if (message.views > 0) ...[
                            SizedBox(width: 16, height: 11,
                              child: CustomPaint(painter: _ViewsIconPainter(color: _bottomInfoColor(isOutgoing, isDark)))),
                            const SizedBox(width: 2),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(_formatCount(message.views),
                                  style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, isDark))),
                            ),
                          ],
                          if (message.forwards > 0) ...[
                            SizedBox(width: 16, height: 11,
                              child: CustomPaint(painter: _ForwardsIconPainter(color: _bottomInfoColor(isOutgoing, isDark)))),
                            const SizedBox(width: 2),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(_formatCount(message.forwards),
                                  style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, isDark))),
                            ),
                          ],
                          if (message.isEdited)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text('edited',
                                  style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, isDark))),
                            ),
                          Text(
                            _formatTime(message.timestamp),
                            style: TextStyle(fontSize: 13, color: _bottomInfoColor(isOutgoing, isDark)),
                          ),
                          if (isOutgoing) ...[
                            const SizedBox(width: 4),
                            _StatusIcon(status: message.status, theme: theme, isOutgoing: true, isDark: isDark),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Spec §5: selection checkbox overlaid at bottom-right of bubble,
              // 5px above bottom edge.
              if (inSelectionMode)
                Positioned(
                  bottom: 5,
                  right: 4,
                  child: _SelectionCheckbox(
                    checked: isSelected,
                    isDark: isDark,
                  ),
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
    );
  }

  Widget _buildSenderAvatar(bool isDark) {
    // Spec §5: sender avatar 33px diameter, bottom-left of last message in group.
    const double avatarSize = 33;
    final fallback = CircleAvatar(
      radius: avatarSize / 2,
      backgroundColor: _senderColor(message.senderId, isDark: isDark, colorId: message.senderColorId),
      child: Text(
        message.senderName.isNotEmpty ? message.senderName[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );

    if (senderAvatarB64 != null && senderAvatarB64!.isNotEmpty) {
      try {
        final bytes = base64Decode(senderAvatarB64!);
        return GestureDetector(
          onTap: onSenderTap != null ? () => onSenderTap!(message.senderId) : null,
          child: ClipOval(
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
        return GestureDetector(
          onTap: onSenderTap != null ? () => onSenderTap!(message.senderId) : null,
          child: fallback,
        );
      }
    }
    return GestureDetector(
      onTap: onSenderTap != null ? () => onSenderTap!(message.senderId) : null,
      child: fallback,
    );
  }

  /// 7 sender colors from spec §5 (id % 7).
  /// Day: historyPeer{1..7}NameFg, Night: matching night-theme slots.
  /// Remap table: colorIndex (id%7) → paletteIndex (0..7).
  /// Source: chat_style.cpp ColorIndexToPaletteIndex — {0,7,4,1,6,3,5}.
  static const _colorIndexRemap = [0, 7, 4, 1, 6, 3, 5];

  /// 8-slot name-fg palette (historyPeer1..8NameFg).
  static const _namePaletteDay = [
    Color(0xFFc03d33), // 0 red
    Color(0xFF4fad2d), // 1 green
    Color(0xFFd09306), // 2 yellow
    Color(0xFF168acd), // 3 blue (windowActiveTextFg)
    Color(0xFF8544d6), // 4 purple
    Color(0xFFcd4073), // 5 pink
    Color(0xFF2996ad), // 6 sea
    Color(0xFFce671b), // 7 orange
  ];
  static const _namePaletteNight = [
    Color(0xFFfb6169), // 0 red
    Color(0xFF85de85), // 1 green
    Color(0xFFf3bc5c), // 2 yellow
    Color(0xFF65bdf3), // 3 blue
    Color(0xFFb48bf2), // 4 purple
    Color(0xFFff5694), // 5 pink
    Color(0xFF62d4e3), // 6 sea
    Color(0xFFfaa357), // 7 orange
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
  /// For color_id 0-6 (default), uses the hardcoded 8-slot palette via remap.
  /// For color_id 7+ (premium/extended), uses the runtime-fetched palette.
  static Color _senderColor(String senderId, {bool isDark = false, int colorId = -1}) {
    // If we have an explicit color_id >= 7, check extended palette first.
    if (colorId >= 7) {
      final ext = _extendedPalette[colorId];
      if (ext != null) {
        return isDark ? ext[1] : ext[0];
      }
      // Extended color not loaded yet — fall through to default logic.
    }

    // For color_id 0-6 or when extended palette isn't available:
    // Use the standard id%7 → remap → 8-slot palette.
    final effectiveColorId = (colorId >= 0 && colorId < 7)
        ? colorId
        : ((int.tryParse(senderId) ?? senderId.hashCode.abs()).abs() % 7);
    final paletteIndex = _colorIndexRemap[effectiveColorId];
    return isDark ? _namePaletteNight[paletteIndex] : _namePaletteDay[paletteIndex];
  }

  static String _formatTime(int timestampMs) {
    if (timestampMs == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
  static Color _bottomInfoColor(bool isOutgoing, bool isDark) {
    if (isOutgoing) {
      return isDark ? AppColors.msgOutDateFgNight : AppColors.msgOutDateFg;
    }
    return isDark ? AppColors.msgInDateFgNight : AppColors.msgInDateFg;
  }
}

/// Row of pill-shaped reaction badges shown below a message's content.
/// Matches AyuGram/Telegram Desktop: rounded capsule, emoji + count,
/// tinted primary when the current user is among the reactors.
class _ReactionList extends StatelessWidget {
  final List<MessageReaction> reactions;
  final bool isOutgoing;
  final ThemeData theme;

  const _ReactionList({
    required this.reactions,
    required this.isOutgoing,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    // Baseline pill color picks up a subtle tint from the primary so it reads
    // as a badge inside both received (dark) and sent (navy) bubbles.
    final inactiveBg = primary.withValues(alpha: isDark ? 0.18 : 0.12);
    final activeBg = primary.withValues(alpha: isDark ? 0.38 : 0.28);
    final inactiveLabel = theme.textTheme.bodyMedium?.color ?? Colors.white;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final r in reactions)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: r.byMe ? activeBg : inactiveBg,
              borderRadius: BorderRadius.circular(10),
              border: r.byMe
                  ? Border.all(color: primary, width: 1)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 3),
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
      ],
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

/// Forum topic button — small pill with colored circle icon + topic name.
/// Spec §5 item 2 / §22.2: colored circle with first letter, 6 predefined colors.
class _TopicButton extends StatelessWidget {
  final String topicName;
  final int topicColorId;

  const _TopicButton({required this.topicName, required this.topicColorId});

  // Spec §22.2: 6 predefined topic icon colors.
  static const _topicColors = <int, Color>{
    0x6FB9F0: Color(0xFF6FB9F0), // blue
    0xFFD67E: Color(0xFFFFD67E), // yellow
    0xCB86DB: Color(0xFFCB86DB), // violet
    0x8EEE98: Color(0xFF8EEE98), // green
    0xFF93B2: Color(0xFFFF93B2), // rose
    0xFB6F5F: Color(0xFFFB6F5F), // red
  };
  static const _defaultColor = Color(0xFF6FB9F0); // blue fallback

  @override
  Widget build(BuildContext context) {
    final color = _topicColors[topicColorId] ?? _defaultColor;
    // First non-whitespace character for the icon circle.
    final letter = topicName.isNotEmpty
        ? topicName.trim().characters.first.toUpperCase()
        : '#';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Colored circle with first letter (spec §22.2: defaultForumTopicIcon 21px,
          // but inside a bubble pill we use a smaller 16px variant).
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              topicName,
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

  const _ReplyPreview({required this.preview, required this.theme, this.onTap});

  @override
  Widget build(BuildContext context) {
    final body = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
      child: Text(
        preview.replaceAll(RegExp(r'\s+'), ' ').trim(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
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
  final List<CachedMessage> allMessages;

  const _MediaIndicator({
    required this.message,
    required this.theme,
    this.showOverlayInfo = false,
    this.isOutgoing = false,
    this.isDark = false,
    this.isSelected = false,
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

// ── Media Spoiler Particle System (spec §6.2) ──
// 3000 particles per 128px canvas, 5 shapes, 60 frames at 33ms,
// 1.5–2px size, 10–20px speed, 300ms fade in/out, α=32/255 darkening.

class _SpoilerParticle {
  double x, y, vx, vy, size;
  int birthFrame, deathFrame, shape;
  _SpoilerParticle(this.x, this.y, this.vx, this.vy, this.size,
      this.birthFrame, this.deathFrame, this.shape);
}

class _SpoilerParticleData {
  final List<_SpoilerParticle> particles;
  final double tileSize;
  final int fadeDurationFrames;
  static const int frameCount = 60;

  _SpoilerParticleData(this.particles, this.tileSize, {this.fadeDurationFrames = 9});

  static _SpoilerParticleData generate(
    int count, double tileSize, {
    double speedMin = 10, double speedMax = 20,
    int fadeDurationFrames = 9,
  }) {
    final rng = math.Random(42);
    final speedRange = speedMax - speedMin;
    final particles = List.generate(count, (_) {
      final birthFrame = rng.nextInt(frameCount);
      final lifetime = fadeDurationFrames * 2;
      return _SpoilerParticle(
        rng.nextDouble() * tileSize,
        rng.nextDouble() * tileSize,
        (rng.nextDouble() * speedRange + speedMin) * (rng.nextBool() ? 1 : -1),
        (rng.nextDouble() * speedRange + speedMin) * (rng.nextBool() ? 1 : -1),
        1.5 + rng.nextDouble() * 0.5,
        birthFrame,
        (birthFrame + lifetime) % frameCount,
        rng.nextInt(5),
      );
    });
    return _SpoilerParticleData(particles, tileSize, fadeDurationFrames: fadeDurationFrames);
  }

  double particleAlpha(int frame, _SpoilerParticle p) {
    int age = (frame - p.birthFrame) % frameCount;
    if (age < 0) age += frameCount;
    final lifetime = fadeDurationFrames * 2;
    if (age >= lifetime) return 0;
    if (age < fadeDurationFrames) return age / fadeDurationFrames;
    return 1.0 - (age - fadeDurationFrames) / fadeDurationFrames;
  }

  Offset particlePos(int frame, _SpoilerParticle p) {
    int age = (frame - p.birthFrame) % frameCount;
    if (age < 0) age += frameCount;
    double x = (p.x + p.vx * age * 0.15) % tileSize;
    double y = (p.y + p.vy * age * 0.15) % tileSize;
    if (x < 0) x += tileSize;
    if (y < 0) y += tileSize;
    return Offset(x, y);
  }
}

class _SpoilerPainter extends CustomPainter {
  final _SpoilerParticleData data;
  final int frame;
  final double revealProgress;

  _SpoilerPainter({
    required this.data,
    required this.frame,
    this.revealProgress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (revealProgress >= 1.0) return;
    final opacity = 1.0 - revealProgress;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // α=32/255 darkening layer
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(0, 0, 0, (32 / 255) * opacity),
    );

    final paint = Paint()..style = PaintingStyle.fill;
    final tile = data.tileSize;
    final tilesX = (size.width / tile).ceil() + 1;
    final tilesY = (size.height / tile).ceil() + 1;

    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final ox = tx * tile;
        final oy = ty * tile;
        for (final p in data.particles) {
          final a = data.particleAlpha(frame, p);
          if (a <= 0) continue;
          final pos = data.particlePos(frame, p);
          final px = ox + pos.dx;
          final py = oy + pos.dy;
          if (px < -2 || px > size.width + 2 || py < -2 || py > size.height + 2) continue;
          paint.color = Color.fromRGBO(255, 255, 255, a * opacity * 0.85);
          switch (p.shape) {
            case 0:
              canvas.drawCircle(Offset(px, py), p.size, paint);
            case 1:
              canvas.drawRect(Rect.fromCenter(center: Offset(px, py), width: p.size * 1.8, height: p.size * 1.8), paint);
            case 2:
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset(px, py), width: p.size * 2, height: p.size),
                  Radius.circular(p.size * 0.5),
                ),
                paint,
              );
            case 3:
              canvas.drawCircle(Offset(px, py), p.size * 0.8, paint);
            default:
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset(px, py), width: p.size, height: p.size * 2),
                  Radius.circular(p.size * 0.5),
                ),
                paint,
              );
          }
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpoilerPainter old) =>
      old.frame != frame || old.revealProgress != revealProgress;
}

class _MediaSpoilerOverlay extends StatefulWidget {
  final double width;
  final double height;
  final bool revealed;
  final VoidCallback onReveal;

  const _MediaSpoilerOverlay({
    required this.width,
    required this.height,
    required this.revealed,
    required this.onReveal,
  });

  @override
  State<_MediaSpoilerOverlay> createState() => _MediaSpoilerOverlayState();
}

class _MediaSpoilerOverlayState extends State<_MediaSpoilerOverlay>
    with TickerProviderStateMixin {
  static final _SpoilerParticleData _sharedParticles =
      _SpoilerParticleData.generate(3000, 128.0);

  late final AnimationController _animController;
  late final AnimationController _revealController;
  int _currentFrame = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1980),
    )..repeat();
    _animController.addListener(_onTick);

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.revealed) {
      _revealController.value = 1.0;
      _animController.stop();
    }
  }

  void _onTick() {
    final f = (_animController.value * 60).floor() % 60;
    if (f != _currentFrame) {
      setState(() => _currentFrame = f);
    }
  }

  @override
  void didUpdateWidget(_MediaSpoilerOverlay old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) {
      _revealController.forward().then((_) {
        if (mounted) _animController.stop();
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.revealed ? null : widget.onReveal,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _revealController,
        builder: (_, __) {
          if (_revealController.value >= 1.0) return const SizedBox.shrink();
          return CustomPaint(
            painter: _SpoilerPainter(
              data: _sharedParticles,
              frame: _currentFrame,
              revealProgress: Curves.easeInOut.transform(_revealController.value),
            ),
            size: Size(widget.width, widget.height),
          );
        },
      ),
    );
  }
}

// ── Text Spoiler Widget (spec §6.2 text-spoiler descriptor) ──
// 9000 particles, 4–8 speed, 1.5–2px size, 200ms fade.

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
    with TickerProviderStateMixin {
  static final _SpoilerParticleData _textParticles =
      _SpoilerParticleData.generate(
    9000, 128.0,
    speedMin: 4, speedMax: 8,
    fadeDurationFrames: 6, // 200ms / 33ms ≈ 6
  );

  late final AnimationController _animController;
  late final AnimationController _revealController;
  int _currentFrame = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 33 * _SpoilerParticleData.frameCount),
    )..addListener(() {
        final newFrame = (_animController.value * _SpoilerParticleData.frameCount).floor()
            % _SpoilerParticleData.frameCount;
        if (newFrame != _currentFrame) {
          setState(() => _currentFrame = newFrame);
        }
      });
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (!widget.revealed) {
      _animController.repeat();
    } else {
      _revealController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_TextSpoilerWidget old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) {
      _revealController.forward().then((_) {
        if (mounted) _animController.stop();
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark
        ? const Color(0xFF6D7F8F)
        : const Color(0xFFA0ACB6);

    return GestureDetector(
      onTap: widget.revealed ? null : widget.onReveal,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _revealController,
        builder: (_, __) {
          final revealVal = Curves.easeInOut.transform(_revealController.value);
          if (revealVal >= 1.0) {
            return Text(widget.text, style: widget.style);
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: CustomPaint(
              foregroundPainter: _TextSpoilerPainter(
                data: _textParticles,
                frame: _currentFrame,
                revealProgress: revealVal,
                bgColor: bgColor,
              ),
              child: Text(
                widget.text,
                style: widget.style.copyWith(
                  color: Colors.transparent,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TextSpoilerPainter extends CustomPainter {
  final _SpoilerParticleData data;
  final int frame;
  final double revealProgress;
  final Color bgColor;

  _TextSpoilerPainter({
    required this.data,
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

    final paint = Paint()..style = PaintingStyle.fill;
    final tile = data.tileSize;
    final tilesX = (size.width / tile).ceil() + 1;
    final tilesY = (size.height / tile).ceil() + 1;

    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final ox = tx * tile;
        final oy = ty * tile;
        for (final p in data.particles) {
          final a = data.particleAlpha(frame, p);
          if (a <= 0) continue;
          final pos = data.particlePos(frame, p);
          final px = ox + pos.dx;
          final py = oy + pos.dy;
          if (px < -2 || px > size.width + 2 || py < -2 || py > size.height + 2) continue;
          paint.color = Color.fromRGBO(255, 255, 255, a * opacity * 0.7);
          switch (p.shape) {
            case 0:
              canvas.drawCircle(Offset(px, py), p.size, paint);
            case 1:
              canvas.drawRect(Rect.fromCenter(center: Offset(px, py), width: p.size * 1.8, height: p.size * 1.8), paint);
            case 2:
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset(px, py), width: p.size * 2, height: p.size),
                  Radius.circular(p.size * 0.5),
                ),
                paint,
              );
            case 3:
              canvas.drawCircle(Offset(px, py), p.size * 0.8, paint);
            default:
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset(px, py), width: p.size, height: p.size * 2),
                  Radius.circular(p.size * 0.5),
                ),
                paint,
              );
          }
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TextSpoilerPainter old) =>
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
  final List<CachedMessage> allMessages;

  const _VisualMedia({
    required this.message,
    required this.theme,
    this.showOverlayInfo = false,
    this.isOutgoing = false,
    this.isDark = false,
    this.isSelected = false,
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

class _VisualMediaState extends State<_VisualMedia> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _fullImageLoaded = false;
  Uint8List? _thumbBytes;
  String _lastThumbB64 = '';
  bool _spoilerRevealed = false;

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
    _decodeThumb();
    if (widget.message.mediaLocalPath.isNotEmpty) {
      _fullImageLoaded = true;
      _fadeController.value = 1.0;
    }
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

  @override
  void dispose() {
    _scrollPosition?.removeListener(_checkVideoNoteVisibility);
    _scrollPosition = null;
    _disposeVideoNote();
    _fadeController.dispose();
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

    // Photos/videos: max 430×430. GIFs: 320px wide, 1080px tall (spec §6 max inline area 1920×1080).
    final bool isGif = message.mediaType == 7;
    final double maxW = isGif ? 320.0 : 430.0;
    final double maxH = isGif ? 1080.0 : 430.0;
    double displayWidth = maxW;
    double displayHeight = maxW * 287.0 / 430.0;
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

    // Sticker: smaller, no background. Spec §6: 224px max (static/animated).
    if (message.mediaType == 6) {
      displayWidth = displayWidth.clamp(100, 224);
      displayHeight = displayHeight.clamp(100, 224);
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
    const kPremiumMultiplier = 1.49;
    final effectWidth = isPremiumSticker ? displayWidth * kPremiumMultiplier : displayWidth;
    final effectHeight = isPremiumSticker ? displayHeight * kPremiumMultiplier : displayHeight;

    final hasFullImage = message.mediaLocalPath.isNotEmpty;
    final hasThumb = _thumbBytes != null;
    final hasSpoiler = message.mediaSpoiler && !_spoilerRevealed;

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

    return GestureDetector(
      onTap: vnPlaying
          ? _toggleVideoNoteSound
          : canOpenViewer
              ? () => MediaViewer.open(
                    context,
                    message: message,
                    allMessages: widget.allMessages,
                  )
              : canOpenStickerPack
                  ? () => StickerPackViewer.show(context, message)
                  : null,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: effectWidth,
        height: effectHeight,
        child: Center(
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
              if (hasFullImage && !hasSpoiler && message.mediaType == 7)
                Positioned.fill(
                  child: _GifPlayer(
                    filePath: message.mediaLocalPath,
                    width: displayWidth,
                    height: displayHeight,
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
              else if (hasFullImage && !hasSpoiler)
                AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (_, child) => Opacity(
                    opacity: _fadeAnimation.value,
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

              // Video overlay: centered play button (not for GIFs — they auto-play).
              if (message.mediaType == 2)
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
                      color: theme.brightness == Brightness.dark
                          ? AppColors.bubbleReceived
                          : AppColors.bubbleReceivedLight,
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
                      color: AppColors.msgDateImgBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.views > 0) ...[
                          const SizedBox(width: 16, height: 11,
                            child: CustomPaint(painter: _ViewsIconPainter(color: AppColors.historyIconFgInverted))),
                          const SizedBox(width: 2),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(MessageBubble._formatCount(message.views),
                                style: const TextStyle(fontSize: 13, color: AppColors.historyIconFgInverted)),
                          ),
                        ],
                        if (message.forwards > 0) ...[
                          const SizedBox(width: 16, height: 11,
                            child: CustomPaint(painter: _ForwardsIconPainter(color: AppColors.historyIconFgInverted))),
                          const SizedBox(width: 2),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(MessageBubble._formatCount(message.forwards),
                                style: const TextStyle(fontSize: 13, color: AppColors.historyIconFgInverted)),
                          ),
                        ],
                        if (message.isEdited)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Text('edited',
                                style: TextStyle(fontSize: 13, color: AppColors.historyIconFgInverted)),
                          ),
                        Text(
                          MessageBubble._formatTime(message.timestamp),
                          style: const TextStyle(fontSize: 13, color: AppColors.historyIconFgInverted),
                        ),
                        if (widget.isOutgoing) ...[
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
              // §6.2: Media spoiler particle overlay
              if (message.mediaSpoiler)
                Positioned.fill(
                  child: _MediaSpoilerOverlay(
                    width: displayWidth,
                    height: displayHeight,
                    revealed: _spoilerRevealed,
                    onReveal: () {
                      setState(() => _spoilerRevealed = true);
                      _fadeController.forward(from: 0.0);
                    },
                  ),
                ),
              // §6.6: Sticker selection overlay — msgStickerOverlay tint
              if (message.mediaType == 6 && widget.isSelected)
                Positioned.fill(
                  child: ColoredBox(
                    color: widget.isDark
                        ? AppColors.msgStickerOverlayNight
                        : AppColors.msgStickerOverlay,
                  ),
                ),
            ],
          ),
        ),
      ),
      ),  // Center
      ),  // outer SizedBox (effectWidth × effectHeight)
    ),
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

    audio.playVoice(msg.mediaLocalPath, msg.msgId);
  }

  void _onWaveformTap(double localX, double totalWidth) {
    if (totalWidth <= 0) return;
    final audio = context.read<AudioService>();
    final msg = widget.message;

    if (!audio.isActiveMsg(msg.msgId)) {
      if (msg.mediaLocalPath.isEmpty) return;
      audio.playVoice(msg.mediaLocalPath, msg.msgId).then((_) {
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
    final result = await engine.transcribeAudio(msg.accountId, msg.chatId, msg.msgId);
    if (!mounted) return;
    if (result == null) {
      setState(() { _transcribing = false; });
      return;
    }
    if (result.pending) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final retry = await engine.transcribeAudio(msg.accountId, msg.chatId, msg.msgId);
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _transcriptionText = retry?.text ?? '';
      });
    } else {
      setState(() {
        _transcribing = false;
        _transcriptionText = result.text;
      });
    }
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
                onTap: downloading ? null : _onPlayPause,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.theme.colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: downloading
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 24,
                          color: widget.theme.colorScheme.primary,
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

  static const double _barWidth = 2.0;
  static const double _barGap = 1.0;
  static const double _minHeight = 3.0;
  static const double _maxHeight = 17.0;

  static const Color _inboxPlayed = Color(0xFF40A7E3);
  static const Color _inboxUnplayed = Color(0xFFD4DEE6);
  static const Color _outboxPlayed = Color(0xFF5EBD66);
  static const Color _outboxUnplayed = Color(0xFFB3E2B4);

  _WaveformPainter({
    required this.samples,
    required this.isOutgoing,
    required this.progress,
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

    final playedPaint = Paint()
      ..color = isOutgoing ? _outboxPlayed : _inboxPlayed;
    final unplayedPaint = Paint()
      ..color = isOutgoing ? _outboxUnplayed : _inboxUnplayed;

    final hoverWidth = hoverX?.clamp(0.0, size.width).roundToDouble();
    final Paint? hoverPaint = hoverWidth != null
        ? (Paint()..color = (isOutgoing ? _outboxPlayed : _inboxPlayed).withValues(alpha: 0.30))
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
      old.hoverX != hoverX;
}

/// Audio file indicator (music, podcast, etc.).
class _AudioIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _AudioIndicator({required this.message, required this.theme});

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
    final songName = _formatSongName(
      message.mediaFileName, message.audioTitle, message.audioPerformer,
    );
    final hasCover = message.mediaThumbB64.isNotEmpty;
    final isDownloaded = message.mediaDownloadState == 2;
    final isDownloading = message.mediaDownloadState == 1;

    final statusParts = <String>[];
    if (message.mediaDuration > 0) {
      statusParts.add(_VisualMedia._formatDuration(message.mediaDuration));
    }
    if (message.mediaSizeLabel.isNotEmpty) {
      statusParts.add(message.mediaSizeLabel);
    }

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
              _buildIcon(hasCover, isDownloaded, isDownloading),
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
                    if (statusParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        statusParts.join(' \u00b7 '),
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
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

  Widget _buildIcon(bool hasCover, bool isDownloaded, bool isDownloading) {
    if (hasCover) {
      return ClipOval(
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.memory(
                base64Decode(message.mediaThumbB64),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _defaultIcon(isDownloaded, isDownloading),
              ),
              Container(
                width: 44,
                height: 44,
                color: Colors.black.withValues(alpha: 0.3),
              ),
              Icon(
                isDownloaded ? Icons.play_arrow : (isDownloading ? Icons.close : Icons.arrow_downward),
                size: 22,
                color: Colors.white,
              ),
            ],
          ),
        ),
      );
    }
    return _defaultIcon(isDownloaded, isDownloading);
  }

  Widget _defaultIcon(bool isDownloaded, bool isDownloading) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: isDownloading
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              isDownloaded ? Icons.play_arrow : Icons.arrow_downward,
              size: 22,
              color: Colors.white,
            ),
    );
  }
}

class _LocationIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _LocationIndicator({required this.message, required this.theme});

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
    final lat = message.geoLat;
    final lng = message.geoLong;
    final hasVenue = message.venueTitle.isNotEmpty;
    final isLive = message.geoLive;

    final mapW = 430.0;
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(mapW, mapH),
                    painter: _MapGridPainter(isDark: isDark),
                  ),
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
                        color: isDark
                            ? const Color(0xFF8899A6)
                            : const Color(0xFF999999),
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

class _MapGridPainter extends CustomPainter {
  final bool isDark;
  const _MapGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark
          ? const Color(0xFF2A3A4A)
          : const Color(0xFFD5DBE1)
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final roadPaint = Paint()
      ..color = isDark
          ? const Color(0xFF354A5F)
          : const Color(0xFFC8CED4)
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(size.width * 0.3, 0),
      Offset(size.width * 0.35, size.height),
      roadPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.4),
      Offset(size.width, size.height * 0.45),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.7, 0),
      Offset(size.width * 0.65, size.height),
      roadPaint,
    );
  }

  @override
  bool shouldRepaint(_MapGridPainter oldDelegate) => isDark != oldDelegate.isDark;
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

  IconData _stateIcon() {
    switch (message.mediaDownloadState) {
      case 1: return Icons.close;
      case 2: return Icons.insert_drive_file;
      default: return Icons.arrow_downward;
    }
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
    final isDownloading = message.mediaDownloadState == 1;

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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.insert_drive_file, size: 20, color: theme.colorScheme.primary),
                        if (ext.isNotEmpty && ext.length <= 4)
                          Text(ext, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                      ],
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: isDownloading
                            ? Padding(
                                padding: const EdgeInsets.all(2),
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(_stateIcon(), size: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 0),
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (message.mediaSizeLabel.isNotEmpty)
                      Text(
                        message.mediaSizeLabel,
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
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
    // Spec §5: media-overlay uses inverted (white) icon colors.
    final color = inverted
        ? (status == MsgStatus.sending
            ? AppColors.historySendingInvertedIconFg
            : AppColors.historyIconFgInverted)
        : switch (status) {
            MsgStatus.sending => isOutgoing
                ? (isDark ? AppColors.historySendingOutIconFgNight : AppColors.historySendingOutIconFg)
                : (isDark ? AppColors.historySendingInIconFgNight : AppColors.historySendingInIconFg),
            MsgStatus.sent || MsgStatus.delivered || MsgStatus.read => isOutgoing
                ? (isDark ? AppColors.historyOutIconFgNight : AppColors.historyOutIconFg)
                : (isDark ? AppColors.msgInDateFgNight : AppColors.msgInDateFg),
            MsgStatus.failed => theme.colorScheme.error,
            _ => isOutgoing
                ? (isDark ? AppColors.historyOutIconFgNight : AppColors.historyOutIconFg)
                : (isDark ? AppColors.msgInDateFgNight : AppColors.msgInDateFg),
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

// ── Rich text entity model ──

class _TextEntity {
  final String type;
  final int offset; // UTF-16 code units
  final int length;
  final String url;
  final String language;

  const _TextEntity({
    required this.type,
    required this.offset,
    required this.length,
    this.url = '',
    this.language = '',
  });

  factory _TextEntity.fromJson(Map<String, dynamic> j) => _TextEntity(
    type: j['type'] as String? ?? '',
    offset: j['offset'] as int? ?? 0,
    length: j['length'] as int? ?? 0,
    url: j['url'] as String? ?? '',
    language: j['language'] as String? ?? '',
  );
}

// ── Rich message text widget ──

class _RichMessageText extends StatefulWidget {
  final String text;
  final String entitiesJson;
  final TextStyle baseStyle;
  final ThemeData theme;
  final bool isOutgoing;

  const _RichMessageText({
    required this.text,
    required this.entitiesJson,
    required this.baseStyle,
    required this.theme,
    required this.isOutgoing,
  });

  @override
  State<_RichMessageText> createState() => _RichMessageTextState();
}

class _RichMessageTextState extends State<_RichMessageText> {
  final Set<int> _revealedSpoilers = {};
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
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
    if (entities.isEmpty) {
      return Text(widget.text, style: widget.baseStyle);
    }

    final isDark = widget.theme.brightness == Brightness.dark;
    final text = widget.text;
    final textLen = text.length; // already UTF-16 in Dart

    // Sort by offset for stable processing.
    entities.sort((a, b) => a.offset.compareTo(b.offset));

    final hasSpoilers = entities.any((e) => e.type == 'spoiler');
    final hasUnrevealed = hasSpoilers && entities
        .where((e) => e.type == 'spoiler')
        .any((e) => !_revealedSpoilers.contains(e.offset));

    // Separate blockquotes (block-level) from inline entities.
    final blockquotes = entities.where((e) => e.type == 'blockquote').toList();
    final inlineEntities = entities.where((e) => e.type != 'blockquote').toList();

    Widget result;
    if (blockquotes.isEmpty) {
      // Simple case: no blockquotes, just inline rich text.
      result = Text.rich(
        TextSpan(children: _buildInlineSpans(text, 0, textLen, inlineEntities, isDark)),
        style: widget.baseStyle,
      );
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
      children.add(Text.rich(
        TextSpan(children: _buildInlineSpans(text, cursor, textLen, after, isDark)),
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
      onTap: () {
        setState(() {
          for (final e in entities.where((e) => e.type == 'spoiler')) {
            _revealedSpoilers.add(e.offset);
          }
        });
      },
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
        return TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: isDark ? const Color(0xFF1E2A36) : const Color(0xFFF0F0F0),
            fontSize: (widget.baseStyle.fontSize ?? 14) * 0.9,
          ),
        );
      case 'pre':
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
                fontFamily: 'monospace',
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
            onReveal: () => setState(() => _revealedSpoilers.add(idx)),
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
        return TextSpan(text: text);
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

    return GestureDetector(
      onTap: canOpen
          ? () => MediaViewer.open(context, message: msg, allMessages: widget.allMessages)
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
              child: _PollFireworks(
                onComplete: () {
                  if (mounted) setState(() => _showFireworks = false);
                },
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
                          color: isDark
                              ? const Color(0xFF3E546A)
                              : const Color(0xFF40A7E3),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF17212B)
                                : Colors.white,
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
      }
    });
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
          ? const Color(0xFF40A7E3)
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
                child: _buildIndicator(),
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

  Widget _buildIndicator() {
    const size = 18.0;
    const stroke = 2.0;
    final accentColor = const Color(0xFF40A7E3);
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
                width: size - stroke * 2 - 2,
                height: size - stroke * 2 - 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                ),
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
        size: 2.0 + _rng.nextDouble() * 3,
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
