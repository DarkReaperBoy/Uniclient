import 'package:flutter/material.dart';

import '../models/engine_models.dart';
import '../theme/theme.dart';

/// Single message bubble. Spec §5: max 430px, 16/6px radius, sender colors.
class MessageBubble extends StatelessWidget {
  final CachedMessage message;
  final VoidCallback? onReply;

  const MessageBubble({
    super.key,
    required this.message,
    this.onReply,
  });

  // Spec: max bubble width 430px.
  static const _maxWidth = 430.0;
  static const _radiusLarge = 16.0;
  static const _radiusSmall = 6.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Determine if this is an outgoing message.
    // For now, detect by senderId being empty (own messages often have no sender name in DMs).
    // The real heuristic: sent status or matching selfId (not available here yet).
    final isOutgoing = message.status == MsgStatus.sent ||
        message.status == MsgStatus.delivered ||
        message.status == MsgStatus.read ||
        message.status == MsgStatus.sending;

    final bubbleColor = isOutgoing
        ? (isDark ? AppColors.bubbleSent : AppColors.bubbleSentLight)
        : (isDark ? AppColors.bubbleReceived : AppColors.bubbleReceivedLight);

    final alignment = isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          GestureDetector(
            onLongPress: onReply,
            onSecondaryTap: onReply,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(_radiusLarge),
                    topRight: const Radius.circular(_radiusLarge),
                    bottomLeft: Radius.circular(isOutgoing ? _radiusLarge : _radiusSmall),
                    bottomRight: Radius.circular(isOutgoing ? _radiusSmall : _radiusLarge),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender name (in groups, for incoming).
                    if (!isOutgoing && message.senderName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          message.senderName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _senderColor(message.senderId),
                          ),
                        ),
                      ),
                    // Reply preview.
                    if (message.replyPreview.isNotEmpty)
                      _ReplyPreview(
                        preview: message.replyPreview,
                        theme: theme,
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
                    // Message text.
                    if (message.contentText.isNotEmpty)
                      Text(
                        message.contentText,
                        style: theme.textTheme.bodyMedium,
                      ),
                    // Media indicator.
                    if (message.hasMedia)
                      _MediaIndicator(message: message, theme: theme),
                    // Bottom info: time + edited + status.
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Reactions.
                        if (message.reactions.isNotEmpty) ...[
                          for (final r in message.reactions)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '${r.emoji} ${r.count}',
                                style: TextStyle(fontSize: 11,
                                    color: r.byMe ? theme.colorScheme.primary : theme.textTheme.bodySmall?.color),
                              ),
                            ),
                          const Spacer(),
                        ] else
                          const Spacer(),
                        if (message.isEdited)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text('edited',
                                style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
                          ),
                        Text(
                          _formatTime(message.timestamp),
                          style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                        ),
                        if (isOutgoing) ...[
                          const SizedBox(width: 3),
                          _StatusIcon(status: message.status, theme: theme),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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

class _ReplyPreview extends StatelessWidget {
  final String preview;
  final ThemeData theme;

  const _ReplyPreview({required this.preview, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
      child: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
      ),
    );
  }
}

class _MediaIndicator extends StatelessWidget {
  final CachedMessage message;
  final ThemeData theme;

  const _MediaIndicator({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    final label = switch (message.mediaType) {
      1 => 'Photo',
      2 => 'Video',
      3 => 'Audio',
      4 => 'Voice message',
      5 => 'Video message',
      6 => 'Sticker',
      7 => 'GIF',
      8 => message.mediaFileName.isNotEmpty ? message.mediaFileName : 'File',
      _ => 'Media',
    };

    final icon = switch (message.mediaType) {
      1 => Icons.photo,
      2 => Icons.videocam,
      3 => Icons.audiotrack,
      4 => Icons.mic,
      5 => Icons.videocam,
      6 => Icons.emoji_emotions,
      7 => Icons.gif,
      8 => Icons.insert_drive_file,
      _ => Icons.attachment,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (message.mediaSizeLabel.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              message.mediaSizeLabel,
              style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final MsgStatus status;
  final ThemeData theme;

  const _StatusIcon({required this.status, required this.theme});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      MsgStatus.sending => (Icons.access_time, theme.textTheme.bodySmall?.color),
      MsgStatus.sent => (Icons.check, theme.textTheme.bodySmall?.color),
      MsgStatus.delivered => (Icons.done_all, theme.textTheme.bodySmall?.color),
      MsgStatus.read => (Icons.done_all, theme.colorScheme.primary),
      MsgStatus.failed => (Icons.error_outline, theme.colorScheme.error),
      _ => (Icons.check, theme.textTheme.bodySmall?.color),
    };

    return Icon(icon, size: 14, color: color);
  }
}
