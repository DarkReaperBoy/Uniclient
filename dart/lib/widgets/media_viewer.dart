import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/engine_models.dart';
import '../theme/theme.dart';

/// Full-screen overlay for viewing images, videos, audio, and files
/// attached to a [CachedMessage].
class MediaViewer extends StatefulWidget {
  final CachedMessage message;

  const MediaViewer({super.key, required this.message});

  /// Push a full-screen media viewer route for the given message.
  static void show(BuildContext context, CachedMessage message) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaViewer(message: message),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  final FocusNode _focusNode = FocusNode();
  double _dragOffset = 0;

  CachedMessage get msg => widget.message;

  String get _displayName =>
      msg.mediaFileName.isNotEmpty ? msg.mediaFileName : 'Media';

  String get _dateLabel {
    final dt = msg.dateTime;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:$m';
  }

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _saveToDownloads(BuildContext context) {
    final path = msg.mediaLocalPath;
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Media not yet downloaded')),
      );
      return;
    }
    final src = File(path);
    if (!src.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cached file not found')),
      );
      return;
    }
    final downloadsDir = Directory('${Platform.environment['HOME'] ?? '/tmp'}/Downloads');
    if (!downloadsDir.existsSync()) downloadsDir.createSync(recursive: true);
    final name = msg.mediaFileName.isNotEmpty ? msg.mediaFileName : src.uri.pathSegments.last;
    var dest = File('${downloadsDir.path}/$name');
    // Avoid overwriting: append (1), (2), etc.
    if (dest.existsSync()) {
      final ext = name.contains('.') ? '.${name.split('.').last}' : '';
      final base = ext.isNotEmpty ? name.substring(0, name.length - ext.length) : name;
      for (var i = 1; ; i++) {
        dest = File('${downloadsDir.path}/$base ($i)$ext');
        if (!dest.existsSync()) break;
      }
    }
    src.copySync(dest.path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${dest.path}')),
      );
    }
  }

  void _openWithSystem(BuildContext context) {
    final path = msg.mediaLocalPath;
    if (path.isEmpty || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not available')),
      );
      return;
    }
    if (Platform.isLinux) {
      Process.run('xdg-open', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
        }
      },
      child: GestureDetector(
        onTap: _close,
        onVerticalDragUpdate: (d) {
          setState(() => _dragOffset += d.delta.dy);
        },
        onVerticalDragEnd: (d) {
          if (_dragOffset.abs() > 100 ||
              d.velocity.pixelsPerSecond.dy.abs() > 500) {
            _close();
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black.withValues(alpha: 0.92),
          body: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildContent()),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _close,
              tooltip: 'Close',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.download_outlined, color: Colors.white70),
              onPressed: () => _saveToDownloads(context),
              tooltip: 'Save to Downloads',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Stop taps on the content area from dismissing the viewer.
    return GestureDetector(
      onTap: () {},
      child: Center(
        child: _buildMediaBody(),
      ),
    );
  }

  Widget _buildMediaBody() {
    if (msg.isImage || msg.isGif || msg.isSticker) {
      return _buildImageContent();
    } else if (msg.isVideo) {
      return _buildVideoContent();
    } else if (msg.isAudio || msg.isVoice) {
      return _buildAudioContent();
    } else if (msg.isFile) {
      return _buildFileContent();
    }
    // Fallback for unknown media types.
    return _buildFileContent();
  }

  Widget _buildImageContent() {
    final hasLocal = msg.mediaLocalPath.isNotEmpty;
    final hasThumb = msg.mediaThumbB64.isNotEmpty;

    Widget imageWidget;

    if (hasLocal) {
      imageWidget = Hero(
        tag: 'media_${msg.msgId}',
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.file(
            File(msg.mediaLocalPath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _placeholder(Icons.broken_image),
          ),
        ),
      );
    } else if (hasThumb) {
      final bytes = base64Decode(msg.mediaThumbB64);
      imageWidget = Hero(
        tag: 'media_${msg.msgId}',
        child: Stack(
          alignment: Alignment.center,
          children: [
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black26,
                BlendMode.darken,
              ),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Downloading...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      imageWidget = Hero(
        tag: 'media_${msg.msgId}',
        child: _placeholder(
          msg.isSticker ? Icons.emoji_emotions : Icons.image,
          label: _displayName,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: imageWidget,
    );
  }

  Widget _buildVideoContent() {
    Widget thumbWidget;
    if (msg.mediaThumbB64.isNotEmpty) {
      final bytes = base64Decode(msg.mediaThumbB64);
      thumbWidget = Image.memory(bytes, fit: BoxFit.contain);
    } else if (msg.mediaLocalPath.isNotEmpty) {
      thumbWidget = _placeholder(Icons.videocam, label: _displayName);
    } else {
      thumbWidget = _placeholder(Icons.videocam, label: _displayName);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              thumbWidget,
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Video playback coming soon',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        if (msg.mediaDuration > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _formatDuration(msg.mediaDuration),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 280,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                msg.isVoice ? Icons.mic : Icons.audiotrack,
                color: AppColors.accent,
                size: 48,
              ),
              const SizedBox(height: 16),
              // Waveform placeholder
              SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(24, (i) {
                    final h = 8.0 + (i * 7 % 32).toDouble();
                    return Container(
                      width: 3,
                      height: h,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _displayName,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              if (msg.mediaDuration > 0) ...[
                const SizedBox(height: 4),
                Text(
                  _formatDuration(msg.mediaDuration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ],
              if (msg.mediaSizeLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  msg.mediaSizeLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 280,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _fileIcon(msg.mediaMimeType, msg.mediaFileName),
                color: AppColors.accent,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (msg.mediaSizeLabel.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  msg.mediaSizeLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _openWithSystem(context),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open with...'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (msg.mediaSizeLabel.isNotEmpty) msg.mediaSizeLabel,
                      _dateLabel,
                    ].join('  '),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(IconData icon, {String? label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white30, size: 72),
        if (label != null) ...[
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  IconData _fileIcon(String mime, String name) {
    if (mime.startsWith('application/pdf') || name.endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    }
    if (mime.startsWith('text/') || name.endsWith('.txt') || name.endsWith('.md')) {
      return Icons.description;
    }
    if (mime.contains('zip') || mime.contains('tar') || mime.contains('rar') ||
        name.endsWith('.zip') || name.endsWith('.tar') || name.endsWith('.gz')) {
      return Icons.archive;
    }
    if (mime.contains('spreadsheet') || name.endsWith('.xlsx') || name.endsWith('.csv')) {
      return Icons.table_chart;
    }
    return Icons.insert_drive_file;
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
