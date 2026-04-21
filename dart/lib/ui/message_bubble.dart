import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/engine_models.dart';
import '../theme/theme.dart';

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

  const MessageBubble({
    super.key,
    required this.message,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.isGroupChat = false,
    this.isSelected = false,
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
                  _buildSenderAvatar()
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
              child: Container(
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
                                    color: _senderColor(message.senderId),
                                  ),
                                ),
                                if (message.senderRank.isNotEmpty)
                                  TextSpan(
                                    text: ' ${message.senderRank}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: _senderColor(message.senderId).withValues(alpha: 0.6),
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
                    // Message text (rich or plain).
                    if (message.contentText.isNotEmpty)
                      _RichMessageText(
                        text: message.contentText,
                        entitiesJson: message.contentRich,
                        baseStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
                        theme: theme,
                        isOutgoing: isOutgoing,
                      ),
                    // Media indicator.
                    if (message.hasMedia)
                      _MediaIndicator(message: message, theme: theme),
                    // Reactions row — pill badges above the timestamp.
                    if (message.reactions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _ReactionList(
                        reactions: message.reactions,
                        isOutgoing: isOutgoing,
                        theme: theme,
                      ),
                    ],
                    // Bottom info: time + edited + status.
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Spacer(),
                        if (message.isEdited)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text('edited',
                                style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color)),
                          ),
                        Text(
                          _formatTime(message.timestamp),
                          style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
                        ),
                        if (isOutgoing) ...[
                          const SizedBox(width: 4),
                          _StatusIcon(status: message.status, theme: theme),
                        ],
                      ],
                    ),
                  ],
                ),
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

  Widget _buildSenderAvatar() {
    // Spec §5: sender avatar 33px diameter, bottom-left of last message in group.
    const double avatarSize = 33;
    final fallback = CircleAvatar(
      radius: avatarSize / 2,
      backgroundColor: _senderColor(message.senderId),
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

  /// 7 sender colors from spec (id % 7).
  static Color _senderColor(String senderId) {
    final hash = senderId.hashCode.abs() % 7;
    return const [
      Color(0xFFe17076),
      Color(0xFF7bc862),
      Color(0xFFe5ca77),
      Color(0xFF65aadd),
      Color(0xFFa695e7),
      Color(0xFFee7aae),
      Color(0xFF6ec9cb),
    ][hash];
  }

  static String _formatTime(int timestampMs) {
    if (timestampMs == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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

  const _MediaIndicator({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    // Image, video, sticker, GIF, video note — show visual preview.
    if (_isVisualMedia) {
      return _VisualMedia(message: message, theme: theme);
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

/// Renders photos, videos, stickers, GIFs as visual thumbnails.
class _VisualMedia extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _VisualMedia({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    // Calculate display size (max 300x300, preserve aspect ratio).
    double displayWidth = 300;
    double displayHeight = 200;
    if (message.mediaWidth > 0 && message.mediaHeight > 0) {
      final aspect = message.mediaWidth / message.mediaHeight;
      if (aspect > 1) {
        displayWidth = 300;
        displayHeight = 300 / aspect;
      } else {
        displayHeight = 300;
        displayWidth = 300 * aspect;
      }
      displayWidth = displayWidth.clamp(80, 300);
      displayHeight = displayHeight.clamp(80, 300);
    }

    // Sticker: smaller, no background.
    if (message.mediaType == 6) {
      displayWidth = displayWidth.clamp(80, 200);
      displayHeight = displayHeight.clamp(80, 200);
    }

    Widget imageWidget;

    // Try local file first.
    if (message.mediaLocalPath.isNotEmpty) {
      final file = File(message.mediaLocalPath);
      imageWidget = Image.file(
        file,
        width: displayWidth,
        height: displayHeight,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(displayWidth, displayHeight),
      );
    }
    // Try base64 thumbnail.
    else if (message.mediaThumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(message.mediaThumbB64);
        imageWidget = Image.memory(
          bytes,
          width: displayWidth,
          height: displayHeight,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(displayWidth, displayHeight),
        );
      } catch (_) {
        imageWidget = _placeholder(displayWidth, displayHeight);
      }
    }
    // No image data — show placeholder.
    else {
      imageWidget = _placeholder(displayWidth, displayHeight);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(message.mediaType == 6 ? 0 : 8),
        child: Stack(
          children: [
            imageWidget,
            // Video/GIF overlay: play button + duration.
            if (message.mediaType == 2 || message.mediaType == 7)
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      message.mediaType == 7 ? Icons.gif : Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            // Duration badge for video.
            if (message.mediaType == 2 && message.mediaDuration > 0)
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(message.mediaDuration),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            // Video note: circular mask.
            if (message.mediaType == 5)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.primary, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(double width, double height) {
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

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Voice message indicator. No placeholder waveform — the real waveform bytes
/// are not yet piped through the engine/bridge (see research/telegram_notes.md
/// "Voice"). Until they are, show an honest mic badge + "Voice message" label
/// + duration + file size, matching the layout of [_AudioIndicator]. CLAUDE.md
/// hard-bans fake waveforms, so we do not paint one.
class _VoiceIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _VoiceIndicator({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Voice message',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.mediaDuration > 0)
                      Text(
                        _VisualMedia._formatDuration(message.mediaDuration),
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                      ),
                    if (message.mediaDuration > 0 && message.mediaSizeLabel.isNotEmpty)
                      Text(' · ', style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
                    if (message.mediaSizeLabel.isNotEmpty)
                      Text(
                        message.mediaSizeLabel,
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio file indicator (music, podcast, etc.).
class _AudioIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _AudioIndicator({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.audiotrack, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.mediaFileName.isNotEmpty ? message.mediaFileName : 'Audio',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.mediaDuration > 0)
                      Text(
                        _VisualMedia._formatDuration(message.mediaDuration),
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                      ),
                    if (message.mediaDuration > 0 && message.mediaSizeLabel.isNotEmpty)
                      Text(' · ', style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
                    if (message.mediaSizeLabel.isNotEmpty)
                      Text(
                        message.mediaSizeLabel,
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// File/document attachment indicator.
class _FileIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _FileIndicator({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    final fileName = message.mediaFileName.isNotEmpty ? message.mediaFileName : 'File';
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.insert_drive_file, size: 18, color: theme.colorScheme.primary),
                if (ext.isNotEmpty && ext.length <= 4)
                  Text(ext, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
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
    );
  }
}

/// Spec §5: Delivery status icon at exact spec sizes.
/// Clock 11×11, single-check 13×11, double-check 18×11.
class _StatusIcon extends StatelessWidget {
  final MsgStatus status;
  final ThemeData theme;

  const _StatusIcon({required this.status, required this.theme});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MsgStatus.sending => theme.textTheme.bodySmall?.color ?? Colors.grey,
      MsgStatus.sent => theme.textTheme.bodySmall?.color ?? Colors.grey,
      MsgStatus.delivered => theme.textTheme.bodySmall?.color ?? Colors.grey,
      MsgStatus.read => theme.colorScheme.primary,
      MsgStatus.failed => theme.colorScheme.error,
      _ => theme.textTheme.bodySmall?.color ?? Colors.grey,
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

    final entities = _parseEntities();
    if (entities.isEmpty) {
      return Text(widget.text, style: widget.baseStyle);
    }

    final isDark = widget.theme.brightness == Brightness.dark;
    final text = widget.text;
    final textLen = text.length; // already UTF-16 in Dart

    // Sort by offset for stable processing.
    entities.sort((a, b) => a.offset.compareTo(b.offset));

    // Separate blockquotes (block-level) from inline entities.
    final blockquotes = entities.where((e) => e.type == 'blockquote').toList();
    final inlineEntities = entities.where((e) => e.type != 'blockquote').toList();

    if (blockquotes.isEmpty) {
      // Simple case: no blockquotes, just inline rich text.
      return Text.rich(
        TextSpan(children: _buildInlineSpans(text, 0, textLen, inlineEntities, isDark)),
        style: widget.baseStyle,
      );
    }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
        if (revealed) {
          return TextSpan(text: text);
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => setState(() => _revealedSpoilers.add(idx)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFFA0ACB6),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '\u2588' * (text.length.clamp(1, 40)),
                style: TextStyle(
                  fontSize: (widget.baseStyle.fontSize ?? 14) * 0.85,
                  color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFFA0ACB6),
                  letterSpacing: -1,
                ),
              ),
            ),
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
