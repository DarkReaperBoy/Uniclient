import 'dart:convert';
import 'dart:io';

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

  const MessageBubble({
    super.key,
    required this.message,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.isGroupChat = false,
    this.senderAvatarB64,
    this.onReply,
    this.onContextMenu,
    this.onSenderTap,
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

    final bubbleColor = isOutgoing
        ? (isDark ? AppColors.bubbleSent : AppColors.bubbleSentLight)
        : (isDark ? AppColors.bubbleReceived : AppColors.bubbleReceivedLight);

    final alignment = isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    // Spec §5: Consecutive grouping affects spacing and corner rounding.
    // Top corners: attached-to-previous on sender's side → Small (6px), else Large (16px).
    // Bottom corners: attached-to-next → Small; last in group → tail/Small; else Large.
    final topSenderSide = isFirstInGroup ? _radiusLarge : _radiusSmall;
    final topOtherSide = _radiusLarge;
    final bottomSenderSide = isLastInGroup ? _radiusSmall : _radiusSmall;
    final bottomOtherSide = isLastInGroup ? _radiusLarge : _radiusSmall;

    final verticalPad = isLastInGroup ? 2.0 : 1.0;

    // Show sender avatar for incoming messages in group chats.
    final showAvatar = isGroupChat && !isOutgoing;

    return Padding(
      padding: EdgeInsets.only(top: isFirstInGroup ? 4.0 : verticalPad, bottom: verticalPad),
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
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isOutgoing ? topOtherSide : topSenderSide),
                    topRight: Radius.circular(isOutgoing ? topSenderSide : topOtherSide),
                    bottomLeft: Radius.circular(isOutgoing ? bottomOtherSide : bottomSenderSide),
                    bottomRight: Radius.circular(isOutgoing ? bottomSenderSide : bottomOtherSide),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender name: only on first message of group (in groups, for incoming).
                    if (!isOutgoing && message.senderName.isNotEmpty && isFirstInGroup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: GestureDetector(
                          onTap: onSenderTap != null ? () => onSenderTap!(message.senderId) : null,
                          child: Text(
                            message.senderName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _senderColor(message.senderId),
                            ),
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

/// Voice message indicator with duration bar.
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
          Icon(Icons.mic, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          // Waveform placeholder (static bars).
          SizedBox(
            width: 120,
            height: 20,
            child: CustomPaint(
              painter: _WaveformPainter(color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 8),
          if (message.mediaDuration > 0)
            Text(
              _VisualMedia._formatDuration(message.mediaDuration),
              style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
            ),
        ],
      ),
    );
  }
}

/// Static waveform visualization.
class _WaveformPainter extends CustomPainter {
  final Color color;

  _WaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    // Draw static waveform bars.
    const barCount = 24;
    final barWidth = size.width / barCount;
    for (var i = 0; i < barCount; i++) {
      // Pseudo-random heights based on index.
      final h = (((i * 7 + 3) % 11) / 11.0 * 0.7 + 0.3) * size.height;
      final x = i * barWidth + barWidth / 2;
      final top = (size.height - h) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
