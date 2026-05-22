import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../theme/telegram_palette.dart';
import 'forum_topic_icon.dart';

const double _boxMaxHeight = 408;
const double _boxWidth = 320;
const double _boxRadius = 6;
const double _boxTitleHeight = 48;

const double _iconButtonSize = 26;
const double _gridCellSize = 40;
const double _gridIconSize = 26;
const double _gridPadding = 8;

const List<int> _topicColorIds = [
  0x6FB9F0,
  0xFFD67E,
  0xCB86DB,
  0x8EEE98,
  0xFF93B2,
  0xFB6F5F,
];

class _TopicIconEntry {
  final int documentId;
  final String emoji;
  const _TopicIconEntry({required this.documentId, required this.emoji});
}

Future<EditForumTopicResult?> showEditForumTopicBox(
  BuildContext context, {
  String? existingTitle,
  int? existingColorId,
  int? existingIconEmojiId,
  bool isGeneral = false,
  bool isBot = false,
  bool isEditing = false,
  bool isCreating = false,
  bool isPremium = false,
  List<String>? serverEmojiIcons,
  String? accountId,
}) {
  return showDialog<EditForumTopicResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EditForumTopicDialog(
      existingTitle: existingTitle,
      existingColorId: existingColorId,
      existingIconEmojiId: existingIconEmojiId,
      isGeneral: isGeneral,
      isBot: isBot,
      isEditing: isEditing,
      isCreating: isCreating,
      isPremium: isPremium,
      serverEmojiIcons: serverEmojiIcons,
      accountId: accountId,
    ),
  );
}

class EditForumTopicResult {
  final String title;
  final int colorId;
  final int iconEmojiId;

  const EditForumTopicResult({
    required this.title,
    required this.colorId,
    this.iconEmojiId = 0,
  });
}

class _EditForumTopicDialog extends StatefulWidget {
  final String? existingTitle;
  final int? existingColorId;
  final int? existingIconEmojiId;
  final bool isGeneral;
  final bool isBot;
  final bool isEditing;
  final bool isCreating;
  final bool isPremium;
  final List<String>? serverEmojiIcons;
  final String? accountId;

  const _EditForumTopicDialog({
    this.existingTitle,
    this.existingColorId,
    this.existingIconEmojiId,
    this.isGeneral = false,
    this.isBot = false,
    this.isEditing = false,
    this.isCreating = false,
    this.isPremium = false,
    this.serverEmojiIcons,
    this.accountId,
  });

  @override
  State<_EditForumTopicDialog> createState() => _EditForumTopicDialogState();
}

class _EditForumTopicDialogState extends State<_EditForumTopicDialog>
    with TickerProviderStateMixin {
  late final TextEditingController _titleController;
  late int _colorId;
  late int _iconEmojiId;
  String? _selectedEmojiStr;
  late List<int> _remainingColors;
  bool _titleError = false;
  bool _loadingServerIcons = false;
  int _selectedTab = 0;

  List<_TopicIconEntry> _serverIcons = [];

  List<CustomEmojiSetSummary> _emojiSets = [];
  bool _loadingEmojiSets = false;
  final Map<String, Uint8List> _decodedThumbCache = {};

  final GlobalKey _iconButtonKey = GlobalKey();
  OverlayEntry? _flyOverlay;
  AnimationController? _flyController;

  OverlayEntry? _toastOverlay;
  AnimationController? _toastAnimController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingTitle ?? '');
    _colorId = widget.existingColorId ?? _topicColorIds[0];
    _iconEmojiId = widget.existingIconEmojiId ?? 0;
    _remainingColors = List.of(_topicColorIds)..remove(_colorId);
    _titleController.addListener(_onTitleChanged);
    _fetchServerIcons();
    _fetchInstalledEmojiSets();
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _flyOverlay?.remove();
    _flyOverlay = null;
    _flyController?.stop();
    _flyController?.dispose();
    _flyController = null;
    _dismissToast();
    _toastAnimController?.stop();
    _toastAnimController?.dispose();
    _toastAnimController = null;
    super.dispose();
  }

  void _onTitleChanged() {
    if (_titleError) setState(() => _titleError = false);
  }

  EngineService? _getEngine() {
    try {
      return context.read<EngineService>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchServerIcons() async {
    final accountId = widget.accountId;
    if (accountId == null || accountId.isEmpty) return;
    final engine = _getEngine();
    if (engine == null) return;
    setState(() => _loadingServerIcons = true);
    try {
      final icons = await engine.getForumTopicDefaultIcons(accountId);
      if (!mounted) return;
      final entries = <_TopicIconEntry>[];
      for (final icon in icons) {
        final docId = icon['document_id'];
        final emoji = icon['emoji'] as String? ?? '';
        if (docId is int && docId != 0) {
          entries.add(_TopicIconEntry(documentId: docId, emoji: emoji));
        }
      }
      String? recoveredEmoji;
      if (_iconEmojiId != 0) {
        for (final e in entries) {
          if (e.documentId == _iconEmojiId) {
            recoveredEmoji = e.emoji.isNotEmpty ? e.emoji : null;
            break;
          }
        }
      }
      setState(() {
        _serverIcons = entries;
        _loadingServerIcons = false;
        if (recoveredEmoji != null) {
          _selectedEmojiStr = recoveredEmoji;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingServerIcons = false);
    }
  }

  Future<void> _fetchInstalledEmojiSets() async {
    final accountId = widget.accountId;
    if (accountId == null || accountId.isEmpty) return;
    final engine = _getEngine();
    if (engine == null) return;
    setState(() => _loadingEmojiSets = true);
    try {
      final sets = await engine.getInstalledEmojiSets(accountId);
      if (!mounted) return;
      _decodedThumbCache.clear();
      for (final set in sets) {
        for (final sticker in set.stickers) {
          if (sticker.thumbB64.isNotEmpty && !_decodedThumbCache.containsKey(sticker.thumbB64)) {
            try {
              _decodedThumbCache[sticker.thumbB64] = base64Decode(sticker.thumbB64);
            } catch (_) {}
          }
        }
      }
      setState(() {
        _emojiSets = sets;
        _loadingEmojiSets = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEmojiSets = false);
    }
  }

  void _cycleColor() {
    if (_iconEmojiId != 0) return;
    if (widget.isEditing && !widget.isCreating) return;

    setState(() {
      if (_remainingColors.isEmpty) {
        _remainingColors = List.of(_topicColorIds)..remove(_colorId);
      }
      final idx = math.Random().nextInt(_remainingColors.length);
      _colorId = _remainingColors.removeAt(idx);
    });
  }

  void _selectColorFromGrid(int colorId) {
    setState(() {
      _colorId = colorId;
      _iconEmojiId = 0;
      _selectedEmojiStr = null;
      _remainingColors = List.of(_topicColorIds)..remove(_colorId);
    });
  }

  void _startFlyAnimation(BuildContext gridCellContext, String emoji) {
    final buttonBox = _iconButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final cellBox = gridCellContext.findRenderObject() as RenderBox?;
    if (buttonBox == null || cellBox == null) return;
    if (!buttonBox.hasSize || !cellBox.hasSize) return;

    final cellPos = cellBox.localToGlobal(Offset.zero);
    final buttonPos = buttonBox.localToGlobal(Offset.zero);

    if (cellPos.dx.isNaN || cellPos.dy.isNaN || cellPos.dx.isInfinite || cellPos.dy.isInfinite) return;
    if (buttonPos.dx.isNaN || buttonPos.dy.isNaN || buttonPos.dx.isInfinite || buttonPos.dy.isInfinite) return;

    final overlay = Overlay.of(context);
    final cellSize = cellBox.size;
    final buttonSize = buttonBox.size;

    final startCenter = cellPos + Offset(cellSize.width / 2, cellSize.height / 2);
    final endCenter = buttonPos + Offset(buttonSize.width / 2, buttonSize.height / 2);

    _flyOverlay?.remove();
    _flyOverlay = null;
    _flyController?.stop();
    _flyController?.dispose();
    _flyController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    final posAnim = Tween<Offset>(begin: startCenter, end: endCenter)
        .animate(CurvedAnimation(parent: _flyController!, curve: Curves.easeInOutCubic));
    final scaleAnim = Tween<double>(begin: 1.0, end: _iconButtonSize / _gridIconSize)
        .animate(CurvedAnimation(parent: _flyController!, curve: Curves.easeInOutCubic));

    _flyOverlay = OverlayEntry(builder: (ctx) {
      return AnimatedBuilder(
        animation: _flyController!,
        builder: (_, __) {
          final pos = posAnim.value;
          final scale = scaleAnim.value;
          final iconSize = _gridIconSize * scale;
          final left = pos.dx - iconSize / 2;
          final top = pos.dy - iconSize / 2;
          if (left.isNaN || top.isNaN || left.isInfinite || top.isInfinite) {
            return const SizedBox.shrink();
          }
          return Positioned(
            left: left,
            top: top,
            child: RepaintBoundary(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 1.0 - _flyController!.value * 0.3,
                  child: SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: Center(
                      child: Text(emoji, style: TextStyle(fontSize: iconSize * 0.85)),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
    overlay.insert(_flyOverlay!);

    _flyController!.forward().then((_) {
      if (mounted) {
        _flyOverlay?.remove();
        _flyOverlay = null;
      }
    });
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    Navigator.of(context).pop(EditForumTopicResult(
      title: title,
      colorId: _colorId,
      iconEmojiId: _iconEmojiId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = context.palette.boxBg;
    final engine = _getEngine();

    final String dialogTitle;
    if (widget.isEditing) {
      dialogTitle = widget.isBot ? 'Edit Thread' : 'Edit Topic';
    } else {
      dialogTitle = widget.isBot ? 'New Thread' : 'New Topic';
    }

    final bool canCycleColor = _iconEmojiId == 0 && (!widget.isEditing || widget.isCreating) && !widget.isGeneral;

    return Dialog(
      backgroundColor: boxBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_boxRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _boxWidth,
          maxHeight: _boxMaxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTitleBar(dialogTitle, isDark),
            _buildPinnedTop(isDark, canCycleColor, engine),
            if (!widget.isGeneral) _buildDividerText(isDark),
            if (!widget.isGeneral) _buildShadowSeparator(isDark),
            if (!widget.isGeneral)
              Flexible(child: _buildIconSelectorPanel(isDark, engine)),
            _buildButtons(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(String title, bool isDark) {
    return Container(
      height: _boxTitleHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20,
              color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999)),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedTop(bool isDark, bool canCycleColor, EngineService? engine) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 22, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canCycleColor ? _cycleColor : null,
            child: MouseRegion(
              cursor: canCycleColor
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: KeyedSubtree(
                  key: _iconButtonKey,
                  child: widget.isGeneral
                      ? GeneralForumTopicIcon(
                          size: _iconButtonSize,
                          iconContext: GeneralIconContext.profile,
                        )
                      : (_iconEmojiId != 0 && _selectedEmojiStr != null)
                          ? SizedBox(
                              width: _iconButtonSize,
                              height: _iconButtonSize,
                              child: Center(
                                child: Text(
                                  _selectedEmojiStr!,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            )
                          : (_iconEmojiId != 0 && widget.accountId != null)
                              ? _buildCustomEmojiPreview(engine)
                              : ForumTopicIcon(
                                  colorId: _colorId,
                                  title: _titleController.text,
                                  size: _iconButtonSize,
                                ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _titleController,
              autofocus: true,
              maxLength: 128,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                hintText: widget.isBot ? 'Thread Name' : 'Topic Name',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999),
                ),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3a4a5c) : const Color(0xFFdadce0),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: _titleError
                        ? const Color(0xFFe53935)
                        : const Color(0xFF40a7e3),
                    width: 2,
                  ),
                ),
                errorBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFe53935), width: 2),
                ),
                focusedErrorBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFe53935), width: 2),
                ),
                errorText: _titleError ? 'Please enter a topic name' : null,
                errorStyle: const TextStyle(fontSize: 12, color: Color(0xFFe53935)),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomEmojiPreview(EngineService? engine) {
    if (engine == null) {
      return SizedBox(width: _iconButtonSize, height: _iconButtonSize);
    }
    return CustomEmojiTopicIcon(
      documentId: _iconEmojiId,
      accountId: widget.accountId!,
      engine: engine,
      size: _iconButtonSize,
    );
  }

  Widget _buildDividerText(bool isDark) {
    final text = widget.isBot
        ? 'Choose a thread name and icon'
        : 'Choose a topic name and icon';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
      color: isDark ? const Color(0xFF0e1621) : const Color(0xFFF1F3F5),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999),
        ),
      ),
    );
  }

  Widget _buildShadowSeparator(bool isDark) {
    return Container(
      height: 1,
      color: context.palette.shadowFg,
    );
  }

  void _selectEmoji(BuildContext cellContext, String emoji, {required int documentId}) {
    if (documentId != 0 && !widget.isPremium) {
      final isFree = _serverIcons.any((e) => e.documentId == documentId);
      if (!isFree) {
        _showPremiumToast(emoji);
        return;
      }
    }
    _startFlyAnimation(cellContext, emoji);
    setState(() {
      _iconEmojiId = documentId;
      _selectedEmojiStr = emoji;
    });
  }

  void _selectCustomEmoji(BuildContext cellContext, int documentId, String fallbackEmoji) {
    if (!widget.isPremium) {
      final isFree = _serverIcons.any((e) => e.documentId == documentId);
      if (!isFree) {
        _showPremiumToast(fallbackEmoji);
        return;
      }
    }
    _startFlyAnimation(cellContext, fallbackEmoji.isNotEmpty ? fallbackEmoji : '\u{2B50}');
    setState(() {
      _iconEmojiId = documentId;
      _selectedEmojiStr = fallbackEmoji.isNotEmpty ? fallbackEmoji : null;
    });
  }

  // ── StickerToast overlay (AyuGram HistoryView::StickerToast §chat.style) ──
  void _dismissToast() {
    _toastOverlay?.remove();
    _toastOverlay = null;
  }

  void _showPremiumToast(String emoji) {
    _dismissToast();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay = Overlay.of(context);

    _toastAnimController?.stop();
    _toastAnimController?.dispose();
    _toastAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    final fadeAnim = CurvedAnimation(parent: _toastAnimController!, curve: Curves.easeOut);

    _toastOverlay = OverlayEntry(builder: (_) {
      return Positioned(
        bottom: 64,
        left: 0,
        right: 0,
        child: Center(
          child: RepaintBoundary(
            child: FadeTransition(
              opacity: fadeAnim,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 160, maxWidth: 380),
                  padding: const EdgeInsets.fromLTRB(19, 13, 19, 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1B2836) : const Color(0xFFf0f0f0),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onSecondaryTap: _dismissToast,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'This icon is available for\nTelegram Premium subscribers.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            _dismissToast();
                          },
                          child: const Text(
                            'View Premium',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF40a7e3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });

    overlay.insert(_toastOverlay!);
    _toastAnimController!.forward();

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _toastAnimController?.reverse().then((_) {
        if (mounted) _dismissToast();
      });
    });
  }

  // ── Tab count: 1 (Topic Icons) + N (installed emoji sets) ──
  int get _tabCount => 1 + _emojiSets.length;

  Widget _buildIconSelectorPanel(bool isDark, EngineService? engine) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCategoryTabBar(isDark),
        Flexible(
          child: _buildScrollableIconGrid(isDark, engine),
        ),
      ],
    );
  }

  Widget _buildCategoryTabBar(bool isDark) {
    final tabColor = isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999);
    const activeColor = Color(0xFF40a7e3);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3a4a5c) : const Color(0xFFdadce0),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildTabItem(0, isDark, tabColor, activeColor,
            child: Icon(Icons.access_time, size: 20,
              color: _selectedTab == 0 ? activeColor : tabColor)),
          for (var i = 0; i < _emojiSets.length; i++)
            _buildTabItem(i + 1, isDark, tabColor, activeColor,
              child: _buildSetTabIcon(_emojiSets[i], i + 1, tabColor, activeColor)),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, bool isDark, Color tabColor, Color activeColor, {required Widget child}) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: _selectedTab == index ? activeColor : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildSetTabIcon(CustomEmojiSetSummary set, int tabIndex, Color tabColor, Color activeColor) {
    if (set.stickers.isNotEmpty && set.stickers.first.thumbB64.isNotEmpty) {
      final bytes = _decodedThumbCache[set.stickers.first.thumbB64];
      if (bytes != null) {
        return Opacity(
          opacity: _selectedTab == tabIndex ? 1.0 : 0.6,
          child: Image.memory(
            bytes,
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Icon(Icons.emoji_emotions_outlined, size: 20,
              color: _selectedTab == tabIndex ? activeColor : tabColor),
          ),
        );
      }
    }
    if (set.stickers.isNotEmpty && set.stickers.first.emoji.isNotEmpty) {
      return Text(set.stickers.first.emoji, style: const TextStyle(fontSize: 18));
    }
    return Icon(Icons.emoji_emotions_outlined, size: 20,
      color: _selectedTab == tabIndex ? activeColor : tabColor);
  }

  Widget _buildScrollableIconGrid(bool isDark, EngineService? engine) {
    if (_selectedTab == 0) {
      return _buildTopicIconsGrid(isDark, engine);
    }
    final setIndex = _selectedTab - 1;
    if (setIndex < 0 || setIndex >= _emojiSets.length) {
      return const SizedBox.shrink();
    }
    return _buildEmojiSetGrid(_emojiSets[setIndex], isDark, engine);
  }

  Widget _buildTopicIconsGrid(bool isDark, EngineService? engine) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_gridPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              _buildDefaultResetCell(isDark),
              for (final colorId in _topicColorIds)
                _buildGridCell(colorId, isDark),
              if (_serverIcons.isNotEmpty)
                for (final icon in _serverIcons)
                  _buildServerIconGridCell(icon, isDark, engine),
              if (_loadingServerIcons)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiSetGrid(CustomEmojiSetSummary emojiSet, bool isDark, EngineService? engine) {
    final accountId = widget.accountId;
    final stickers = emojiSet.stickers;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(_gridPadding, _gridPadding, _gridPadding, 0),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text(
                emojiSet.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(_gridPadding, 0, _gridPadding, _gridPadding),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _gridCellSize + 2,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final sticker = stickers[index];
                final docId = int.tryParse(sticker.fileId) ?? 0;
                final isSelected = _iconEmojiId == docId && docId != 0;
                return Builder(
                  builder: (cellContext) => GestureDetector(
                    onTap: () {
                      if (docId != 0) {
                        _selectCustomEmoji(cellContext, docId, sticker.emoji);
                      } else if (sticker.emoji.isNotEmpty) {
                        _selectEmoji(cellContext, sticker.emoji, documentId: 0);
                      }
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        decoration: isSelected
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: isDark
                                    ? const Color(0xFF2b5278)
                                    : const Color(0xFFE3F2FD),
                              )
                            : null,
                        child: Center(
                          child: (engine != null && accountId != null && docId != 0)
                              ? CustomEmojiTopicIcon(
                                  documentId: docId,
                                  accountId: accountId,
                                  engine: engine,
                                  size: _gridIconSize,
                                )
                              : (sticker.thumbB64.isNotEmpty && _decodedThumbCache.containsKey(sticker.thumbB64))
                                  ? Image.memory(
                                      _decodedThumbCache[sticker.thumbB64]!,
                                      width: _gridIconSize,
                                      height: _gridIconSize,
                                      fit: BoxFit.contain,
                                      gaplessPlayback: true,
                                    )
                                  : Text(sticker.emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    ),
                  ),
                );
              },
              childCount: stickers.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultResetCell(bool isDark) {
    final isSelected = _iconEmojiId == 0 && _selectedEmojiStr == null;
    return GestureDetector(
      onTap: () {
        setState(() {
          _iconEmojiId = 0;
          _selectedEmojiStr = null;
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: _gridCellSize,
          height: _gridCellSize,
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isDark
                      ? const Color(0xFF2b5278)
                      : const Color(0xFFE3F2FD),
                )
              : null,
          child: Center(
            child: Icon(
              Icons.close,
              size: _gridIconSize * 0.7,
              color: isDark ? const Color(0xFF7f91a4) : const Color(0xFF999999),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerIconGridCell(_TopicIconEntry icon, bool isDark, EngineService? engine) {
    final isSelected = _iconEmojiId == icon.documentId;
    final accountId = widget.accountId;
    return Builder(
      builder: (cellContext) => GestureDetector(
        onTap: () {
          final displayEmoji = icon.emoji.isNotEmpty ? icon.emoji : '\u{2753}';
          _selectEmoji(cellContext, displayEmoji, documentId: icon.documentId);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: _gridCellSize,
            height: _gridCellSize,
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isDark
                        ? const Color(0xFF2b5278)
                        : const Color(0xFFE3F2FD),
                  )
                : null,
            child: Center(
              child: (engine != null && accountId != null)
                  ? CustomEmojiTopicIcon(
                      documentId: icon.documentId,
                      accountId: accountId,
                      engine: engine,
                      size: _gridIconSize,
                    )
                  : Text(
                      icon.emoji.isNotEmpty ? icon.emoji : '\u{2753}',
                      style: const TextStyle(fontSize: 22),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridCell(int colorId, bool isDark) {
    final isSelected = _iconEmojiId == 0 && _colorId == colorId;
    return GestureDetector(
      onTap: () => _selectColorFromGrid(colorId),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: _gridCellSize,
          height: _gridCellSize,
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isDark
                      ? const Color(0xFF2b5278)
                      : const Color(0xFFE3F2FD),
                )
              : null,
          child: Center(
            child: ForumTopicIcon(
              colorId: colorId,
              title: _titleController.text,
              size: _gridIconSize,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF40a7e3),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _submit,
            child: Text(
              widget.isEditing ? 'Save' : 'Create',
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF40a7e3),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
