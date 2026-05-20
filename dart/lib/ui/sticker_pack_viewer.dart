import 'dart:convert';
import 'dart:io' show Directory, File, gzip;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import 'telegram_tooltip.dart';

class StickerPackViewer extends StatefulWidget {
  final CachedMessage? message;
  final EngineService engine;
  final String _shortName;
  final String _accountId;

  const StickerPackViewer({super.key, required CachedMessage this.message, required this.engine})
    : _shortName = '', _accountId = '';

  const StickerPackViewer.byShortName({super.key, required String shortName, required String accountId, required this.engine})
    : message = null, _shortName = shortName, _accountId = accountId;

  String get accountId => message?.accountId ?? _accountId;

  static void show(BuildContext context, CachedMessage message) {
    final engine = context.read<EngineService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StickerPackViewer(message: message, engine: engine),
    );
  }

  static void showByName(BuildContext context, String shortName, String accountId) {
    final engine = context.read<EngineService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StickerPackViewer.byShortName(shortName: shortName, accountId: accountId, engine: engine),
    );
  }

  @override
  State<StickerPackViewer> createState() => _StickerPackViewerState();
}

class _StickerPackViewerState extends State<StickerPackViewer> {
  StickerSetInfo? _setInfo;
  bool _loading = true;
  String? _error;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _fetchStickerSet();
  }

  Future<void> _fetchStickerSet() async {
    final engine = widget.engine;
    final msg = widget.message;
    try {
      final info = await engine.getStickerSetInfo(
        widget.accountId,
        shortName: msg?.stickerSetShortName ?? widget._shortName,
        setId: msg?.stickerSetId ?? 0,
        accessHash: msg?.stickerSetAccessHash ?? 0,
      );
      if (mounted) {
        setState(() {
          _setInfo = info;
          _loading = false;
          if (info == null) _error = 'Sticker set not found';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final isEmoji = _setInfo?.emojis ?? false;
    final maxSheetHeight = isEmoji ? 197.0 : 320.0;
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = maxSheetHeight.clamp(0.0, screenHeight * 0.9);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(textColor, isDark),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(color: textColor)))
                      : _buildGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  String get _addButtonText {
    final info = _setInfo;
    if (info == null) return 'Add Pack';
    if (info.emojis) return 'Add Emoji';
    if (info.masks) return 'Add Masks';
    return 'Add Pack';
  }

  String get _countLabel {
    final info = _setInfo;
    if (info == null) return '';
    final n = info.count;
    if (info.emojis) return '$n emoji';
    if (info.masks) return '$n masks';
    return '$n stickers';
  }

  Future<void> _installSet() async {
    final info = _setInfo;
    if (info == null || _installing) return;
    setState(() => _installing = true);
    try {
      final accountId = widget.accountId;
      final success = await widget.engine.installStickerSet(
          accountId, info.setId, info.accessHash);
      if (success && mounted) {
        final toastMsg = info.masks
            ? 'Masks installed'
            : info.emojis
                ? 'Emoji added'
                : 'Stickers installed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toastMsg), duration: const Duration(seconds: 2)),
        );
        Navigator.pop(context);
      }
    } catch (_) {}
    if (mounted) setState(() => _installing = false);
  }

  void _shareSet() {
    final shortName = _setInfo?.shortName;
    if (shortName == null || shortName.isEmpty) return;
    final isEmoji = _setInfo?.emojis ?? false;
    final prefix = isEmoji ? 'addemoji' : 'addstickers';
    Clipboard.setData(ClipboardData(text: 'https://t.me/$prefix/$shortName'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 2)),
    );
  }

  void _sendSticker(StickerInfoItem sticker) {
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    widget.engine.sendSticker(chat.accountId, chat.chatId, sticker.fileId);
    Navigator.pop(context);
  }

  void _showOverflowMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(value: 'archive', child: Text('Archive')),
        const PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    ).then((value) async {
      if (value == null || !mounted) return;
      final info = _setInfo;
      if (info == null) return;
      final accountId = widget.accountId;
      if (value == 'remove') {
        await widget.engine.uninstallStickerSet(accountId, info.setId, info.accessHash);
        if (mounted) Navigator.pop(context);
      } else if (value == 'archive') {
        await widget.engine.archiveStickerSet(accountId, info.setId, info.accessHash);
        if (mounted) Navigator.pop(context);
      }
    });
  }

  bool get _isOfficialPack => _setInfo?.official ?? false;

  bool get _isPremiumLocked {
    final info = _setInfo;
    if (info == null) return false;
    return info.emojis && info.isPremium && !(info.userPremium);
  }

  Widget _buildHeader(Color textColor, bool isDark) {
    final info = _setInfo;
    final title = info?.title ?? 'Sticker Pack';
    final count = info?.count ?? 0;
    final installed = info?.installed ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (count > 0)
                  Text(
                    _countLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          if (info != null && !_loading) ...[
            if (installed && _isOfficialPack)
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.windowBgActive,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('OK'),
              )
            else if (installed) ...[
              Builder(
                builder: (ctx) => IconButton(
                  icon: Icon(Icons.more_vert, color: textColor, size: 20),
                  onPressed: () => _showOverflowMenu(ctx),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
              TextButton(
                onPressed: _shareSet,
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.windowBgActive,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Share'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: textColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Cancel'),
              ),
            ] else if (_isPremiumLocked)
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6B93FF), Color(0xFF976FFF)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Unlock'),
                    ],
                  ),
                ),
              )
            else
              TextButton(
                onPressed: _installing ? null : _installSet,
                style: TextButton.styleFrom(
                  backgroundColor: context.palette.windowBgActive,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _installing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_addButtonText),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final info = _setInfo;
    final stickers = info?.stickers ?? [];
    if (stickers.isEmpty) {
      return const Center(child: Text('No stickers'));
    }

    final isEmoji = info?.emojis ?? false;
    final crossAxisCount = isEmoji ? 8 : 5;
    final padding = isEmoji
        ? const EdgeInsets.fromLTRB(12, 0, 12, 0)
        : const EdgeInsets.fromLTRB(19, 13, 19, 13);

    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: isEmoji ? 42.0 / 39.0 : 1.0,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return _StickerTile(
          sticker: sticker,
          accountId: widget.accountId,
          engine: widget.engine,
          onTap: () => _sendSticker(sticker),
        );
      },
    );
  }
}

class _VideoPlayerPool extends ChangeNotifier {
  static final instance = _VideoPlayerPool._();
  _VideoPlayerPool._();

  int _active = 0;
  static const maxActive = 3;

  bool tryAcquire() {
    if (_active >= maxActive) return false;
    _active++;
    return true;
  }

  void release() {
    if (_active > 0) {
      _active--;
      notifyListeners();
    }
  }
}

class _StickerTile extends StatefulWidget {
  final StickerInfoItem sticker;
  final String accountId;
  final EngineService engine;
  final VoidCallback? onTap;

  const _StickerTile({
    required this.sticker,
    required this.accountId,
    required this.engine,
    this.onTap,
  });

  @override
  State<_StickerTile> createState() => _StickerTileState();
}

class _StickerTileState extends State<_StickerTile>
    with SingleTickerProviderStateMixin {
  Uint8List? _lottieData;
  AnimationController? _lottieController;
  Player? _webmPlayer;
  VideoController? _webmController;
  File? _webmTempFile;
  bool _loadingFile = false;
  bool _acquiredSlot = false;
  bool _waitingForSlot = false;

  @override
  void initState() {
    super.initState();
    if (widget.sticker.isAnimated) {
      _loadAnimatedSticker();
    } else if (widget.sticker.isVideo) {
      _tryLoadVideo();
    }
  }

  void _tryLoadVideo() {
    if (_acquiredSlot || _loadingFile) return;
    if (_VideoPlayerPool.instance.tryAcquire()) {
      _acquiredSlot = true;
      if (_waitingForSlot) {
        _waitingForSlot = false;
        _VideoPlayerPool.instance.removeListener(_onSlotAvailable);
      }
      _loadVideoSticker();
    } else if (!_waitingForSlot) {
      _waitingForSlot = true;
      _VideoPlayerPool.instance.addListener(_onSlotAvailable);
    }
  }

  void _onSlotAvailable() {
    if (!mounted || _acquiredSlot) {
      if (_waitingForSlot) {
        _waitingForSlot = false;
        _VideoPlayerPool.instance.removeListener(_onSlotAvailable);
      }
      return;
    }
    _tryLoadVideo();
  }

  void _releaseSlot() {
    if (_acquiredSlot) {
      _acquiredSlot = false;
      _VideoPlayerPool.instance.release();
    }
  }

  Future<void> _loadAnimatedSticker() async {
    if (_loadingFile) return;
    _loadingFile = true;
    final docId = int.tryParse(widget.sticker.fileId);
    if (docId == null) return;
    try {
      final files = await widget.engine.getStickerFiles(
          widget.accountId, [docId]);
      final fileData = files[docId];
      if (fileData != null && fileData.isTgs && mounted) {
        final decompressed = Uint8List.fromList(gzip.decode(fileData.fileData));
        setState(() => _lottieData = decompressed);
      }
    } catch (_) {}
  }

  Future<void> _loadVideoSticker() async {
    if (_loadingFile) return;
    _loadingFile = true;
    final docId = int.tryParse(widget.sticker.fileId);
    if (docId == null) {
      _releaseSlot();
      return;
    }
    try {
      final files = await widget.engine.getStickerFiles(
          widget.accountId, [docId]);
      final fileData = files[docId];
      if (fileData != null && fileData.isWebm && mounted) {
        final dir = Directory.systemTemp;
        final file = File('${dir.path}/sticker_$docId.webm');
        await file.writeAsBytes(fileData.fileData, flush: true);
        _webmTempFile = file;
        final player = Player();
        final controller = VideoController(player);
        await player.open(Media(file.path), play: true);
        await player.setPlaylistMode(PlaylistMode.loop);
        if (!mounted) {
          await player.dispose();
          _releaseSlot();
          return;
        }
        setState(() {
          _webmPlayer = player;
          _webmController = controller;
        });
      } else {
        _releaseSlot();
      }
    } catch (_) {
      _releaseSlot();
    }
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    _lottieController = AnimationController(
      vsync: this,
      duration: composition.duration,
    );
    _lottieController!.repeat();
  }

  @override
  void dispose() {
    _dismissPreview();
    if (_waitingForSlot) {
      _VideoPlayerPool.instance.removeListener(_onSlotAvailable);
    }
    _lottieController?.dispose();
    _webmPlayer?.dispose();
    _releaseSlot();
    _webmTempFile?.delete().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sticker = widget.sticker;
    Widget child;

    if (_lottieData != null) {
      child = Lottie.memory(
        _lottieData!,
        fit: BoxFit.contain,
        controller: _lottieController,
        onLoaded: _onLottieLoaded,
      );
    } else if (_webmController != null) {
      child = Video(
        controller: _webmController!,
        fit: BoxFit.contain,
        controls: NoVideoControls,
      );
    } else if (sticker.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeStrippedThumb(sticker.thumbB64);
        child = Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      } catch (_) {
        child = _emojiPlaceholder();
      }
    } else {
      child = _emojiPlaceholder();
    }

    if (sticker.isVideo && _webmController == null && _lottieData == null) {
      child = Stack(
        alignment: Alignment.center,
        children: [
          child,
          Icon(Icons.play_circle_outline, size: 20,
              color: Colors.white.withValues(alpha: 0.7)),
        ],
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
      onLongPressStart: (details) => _showStickerPreview(context, details.globalPosition, child),
      onLongPressEnd: (_) => _dismissPreview(),
      child: TelegramTooltip(
        message: sticker.emoji,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Stack(
            children: [
              Positioned.fill(child: child),
              if (sticker.isPremium)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.lock, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  OverlayEntry? _previewEntry;

  void _showContextMenu(BuildContext context, Offset position) {
    final sticker = widget.sticker;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final relativeRect = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: relativeRect,
      items: [
        const PopupMenuItem(value: 'send', child: Text('Send')),
        PopupMenuItem(
          value: 'fav',
          child: Text(sticker.isFaved ? 'Remove from Favorites' : 'Add to Favorites'),
        ),
        const PopupMenuItem(value: 'pack', child: Text('View Pack')),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'send':
          widget.onTap?.call();
        case 'fav':
          final docId = int.tryParse(sticker.fileId);
            if (docId != null) {
              widget.engine.faveSticker(widget.accountId, docId, unfave: sticker.isFaved);
            }
        case 'pack':
          break;
      }
    });
  }

  void _showStickerPreview(BuildContext context, Offset position, Widget stickerWidget) {
    _dismissPreview();
    final overlay = Overlay.of(context, rootOverlay: true);
    final screen = MediaQuery.of(context).size;
    const previewSize = 200.0;
    final x = (position.dx - previewSize / 2).clamp(8.0, screen.width - previewSize - 8);
    final y = (position.dy - previewSize - 24).clamp(8.0, screen.height - previewSize - 8);
    _previewEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: x,
        top: y,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: previewSize,
              height: previewSize,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E2C3A)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: stickerWidget,
            ),
          ),
        ),
      ),
    );
    overlay.insert(_previewEntry!);
  }

  void _dismissPreview() {
    _previewEntry?.remove();
    _previewEntry = null;
  }

  Widget _emojiPlaceholder() {
    return Center(
      child: Text(
        widget.sticker.emoji.isNotEmpty ? widget.sticker.emoji : '?',
        style: const TextStyle(fontSize: 28),
      ),
    );
  }

  static Uint8List _decodeStrippedThumb(String b64) {
    final stripped = base64Decode(b64);
    if (stripped.length < 3 || stripped[0] != 0x01) {
      return stripped;
    }
    final w = stripped[1];
    final h = stripped[2];
    final header = _jpegHeader(w, h);
    final footer = _jpegFooter;
    final buf = Uint8List(header.length + stripped.length - 3 + footer.length);
    buf.setAll(0, header);
    buf.setAll(header.length, stripped.sublist(3));
    buf.setAll(header.length + stripped.length - 3, footer);
    return buf;
  }

  static Uint8List _jpegHeader(int w, int h) {
    final tmpl = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x28, 0x1C, 0x1E, 0x23, 0x1E, 0x19, 0x28, 0x23, 0x21, 0x23, 0x2D,
      0x2B, 0x28, 0x30, 0x3C, 0x64, 0x41, 0x3C, 0x37, 0x37, 0x3C, 0x7B, 0x58,
      0x5D, 0x49, 0x64, 0x91, 0x80, 0x99, 0x96, 0x8F, 0x80, 0x8C, 0x8A, 0xA0,
      0xB4, 0xE6, 0xC3, 0xA0, 0xAA, 0xDA, 0xAD, 0x8A, 0x8C, 0xC8, 0xFF, 0xCB,
      0xDA, 0xEE, 0xF5, 0xFF, 0xFF, 0xFF, 0x9B, 0xC1, 0xFF, 0xFF, 0xFF, 0xFA,
      0xFF, 0xE6, 0xFD, 0xFF, 0xF8, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x2B, 0x2D,
      0x2D, 0x3C, 0x35, 0x3C, 0x76, 0x41, 0x41, 0x76, 0xF8, 0xA5, 0x8C, 0xA5,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
      0xF8, 0xF8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x00, 0x00, 0x00, 0x03,
      0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00,
      0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
      0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00,
      0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00,
      0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21,
      0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81,
      0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24,
      0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25,
      0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A,
      0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56,
      0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A,
      0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86,
      0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99,
      0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3,
      0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6,
      0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9,
      0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1,
      0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xC4, 0x00,
      0x1F, 0x01, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
      0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
      0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x11, 0x00,
      0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07, 0x05, 0x04, 0x04, 0x00,
      0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31,
      0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08,
      0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15,
      0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18,
      0x19, 0x1A, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39,
      0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55,
      0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
      0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84,
      0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
      0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA,
      0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4,
      0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7,
      0xD8, 0xD9, 0xDA, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
      0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00,
      0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00,
    ]);
    tmpl[164] = h;
    tmpl[166] = w;
    return tmpl;
  }

  static final _jpegFooter = Uint8List.fromList([0xFF, 0xD9]);
}
