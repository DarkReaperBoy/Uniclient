import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/chat_state.dart';
import 'chat_view.dart' show formatChatLastSeen;

enum InfoWrapMode { side, narrow, layer }

enum _InfoPageType { chatInfo, userProfile }

class _InfoNavPage {
  final _InfoPageType type;
  final MemberInfo? member;
  double scrollOffset = 0.0;

  _InfoNavPage({required this.type, this.member});

  String get title => switch (type) {
    _InfoPageType.chatInfo => '',
    _InfoPageType.userProfile => member?.label ?? 'User Info',
  };
}

class InfoPanel extends StatefulWidget {
  final VoidCallback onClose;
  final InfoWrapMode wrapMode;

  const InfoPanel({
    super.key,
    required this.onClose,
    this.wrapMode = InfoWrapMode.side,
  });

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  List<MemberInfo>? _members;
  bool _loadingMembers = false;
  String? _loadedChatId;
  Map<String, int> _mediaCounts = {};

  final List<_InfoNavPage> _navStack = [_InfoNavPage(type: _InfoPageType.chatInfo)];
  bool _isPushing = true;

  _InfoNavPage get _currentPage => _navStack.last;

  void _pushPage(_InfoNavPage page) {
    _saveCurrentScroll();
    setState(() {
      _isPushing = true;
      _navStack.add(page);
    });
  }

  void _popPage() {
    if (_navStack.length <= 1) {
      widget.onClose();
      return;
    }
    setState(() {
      _isPushing = false;
      _navStack.removeLast();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScroll());
  }

  final Map<int, ScrollController> _scrollControllers = {};

  ScrollController _getScrollController() {
    final idx = _navStack.length - 1;
    return _scrollControllers.putIfAbsent(idx, () {
      final ctrl = ScrollController(initialScrollOffset: _currentPage.scrollOffset);
      return ctrl;
    });
  }

  void _saveCurrentScroll() {
    final idx = _navStack.length - 1;
    final ctrl = _scrollControllers[idx];
    if (ctrl != null && ctrl.hasClients) {
      _currentPage.scrollOffset = ctrl.offset;
    }
  }

  void _restoreScroll() {
    final idx = _navStack.length - 1;
    final old = _scrollControllers.remove(idx + 1);
    old?.dispose();
    final ctrl = _scrollControllers[idx];
    if (ctrl != null && ctrl.hasClients) {
      ctrl.jumpTo(_currentPage.scrollOffset);
    }
  }

  void _resetNavStack() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    _scrollControllers.clear();
    _navStack.clear();
    _navStack.add(_InfoNavPage(type: _InfoPageType.chatInfo));
    _isPushing = true;
  }

  @override
  void dispose() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat != null && chat.chatId != _loadedChatId) {
      _resetNavStack();
      _loadMembers(chat);
    }
  }

  Future<void> _loadMembers(ChatInfo chat) async {
    if (_loadingMembers) return;
    setState(() {
      _loadingMembers = true;
      _loadedChatId = chat.chatId;
    });

    final engine = context.read<EngineService>();

    Map<String, int> counts = {};
    try {
      counts = engine.getSharedMediaCounts(chat.accountId, chat.chatId);
    } catch (_) {}

    List<MemberInfo> members = [];
    try {
      members = await engine.getChatMembers(chat.accountId, chat.chatId);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _members = members;
        _mediaCounts = counts;
        _loadingMembers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = context.watch<ChatState>();
    final chat = chatState.activeChat;

    if (chat == null) return const SizedBox.shrink();

    if (chat.chatId != _loadedChatId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers(chat));
    }

    final isDark = theme.brightness == Brightness.dark;
    final isLayer = widget.wrapMode == InfoWrapMode.layer;
    final isNarrow = widget.wrapMode == InfoWrapMode.narrow;
    final bgColor = isLayer
        ? (isDark ? const Color(0xFF1b2734) : const Color(0xFFf0f0f0))
        : theme.colorScheme.surface;

    final pageContent = _buildCurrentPage(chat, chatState, theme);

    Widget panel = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: isLayer
            ? const BorderRadius.vertical(top: Radius.circular(12))
            : null,
        border: (!isLayer && !isNarrow)
            ? Border(left: BorderSide(color: theme.dividerColor, width: 1))
            : null,
      ),
      clipBehavior: isLayer ? Clip.antiAlias : Clip.none,
      child: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, animation) {
                final isNewPage = child.key == ValueKey(_navStack.length);
                final beginOffset = _isPushing
                    ? (isNewPage ? const Offset(1, 0) : const Offset(-0.3, 0))
                    : (isNewPage ? const Offset(-0.3, 0) : const Offset(1, 0));
                return SlideTransition(
                  position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
                      .animate(animation),
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_navStack.length),
                child: pageContent,
              ),
            ),
          ),
        ],
      ),
    );

    return panel;
  }

  Widget _buildCurrentPage(ChatInfo chat, ChatState chatState, ThemeData theme) {
    final page = _currentPage;
    final isNarrow = widget.wrapMode == InfoWrapMode.narrow;
    final hasBack = _navStack.length > 1 || isNarrow;
    final onClose = hasBack ? _popPage : widget.onClose;

    switch (page.type) {
      case _InfoPageType.userProfile:
        return _UserProfilePage(
          member: page.member!,
          chat: chat,
          theme: theme,
          scrollController: _getScrollController(),
          onClose: onClose,
          showBackButton: hasBack,
          title: page.title,
        );
      case _InfoPageType.chatInfo:
        return _ChatInfoPage(
          chat: chat,
          chatState: chatState,
          theme: theme,
          members: _members,
          loadingMembers: _loadingMembers,
          mediaCounts: _mediaCounts,
          scrollController: _getScrollController(),
          onMemberTap: (member) {
            _pushPage(_InfoNavPage(
              type: _InfoPageType.userProfile,
              member: member,
            ));
          },
          onClose: onClose,
          showBackButton: hasBack,
          title: _panelTitle(chat.type),
          isLayer: widget.wrapMode == InfoWrapMode.layer,
        );
    }
  }

  static String _panelTitle(ChatType type) => switch (type) {
    ChatType.dm => 'User Info',
    ChatType.group => 'Group Info',
    ChatType.channel => 'Channel Info',
    ChatType.topic => 'Topic Info',
    _ => 'Info',
  };
}

class _ActionBtnData {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isMute;
  final bool isMuted;
  const _ActionBtnData(this.icon, this.label, this.onTap,
      {this.isMute = false, this.isMuted = false});
}

class _FlexibleCoverDelegate extends SliverPersistentHeaderDelegate {
  final String displayName;
  final String statusText;
  final Color? statusColor;
  final String avatarPath;
  final Color avatarColor;
  final String initials;
  final ThemeData theme;
  final VoidCallback onClose;
  final bool showBackButton;
  final String collapsedTitle;
  final bool isMuted;
  final VoidCallback? onMuteToggle;
  final ChatType chatType;
  final bool isSelf;
  final int storyCount;
  final bool hasUnreadStory;
  final List<Color>? profileBgColors;
  final String emojiStatusId;

  static const double maxHeight = 236.0;
  static const double minHeight = 56.0;
  static const double _actionButtonSize = 52.0;
  static const double _avatarSize = 80.0;
  static const double _storyLineWidth = 2.5;
  static const double _storyRingGap = 3.0;

  _FlexibleCoverDelegate({
    required this.displayName,
    required this.statusText,
    required this.statusColor,
    required this.avatarPath,
    required this.avatarColor,
    required this.initials,
    required this.theme,
    required this.onClose,
    required this.showBackButton,
    required this.collapsedTitle,
    this.isMuted = false,
    this.onMuteToggle,
    this.chatType = ChatType.dm,
    this.isSelf = false,
    this.storyCount = 0,
    this.hasUnreadStory = false,
    this.profileBgColors,
    this.emojiStatusId = '',
  });

  @override
  double get maxExtent => maxHeight;
  @override
  double get minExtent => minHeight;

  @override
  bool shouldRebuild(covariant _FlexibleCoverDelegate old) =>
      displayName != old.displayName ||
      statusText != old.statusText ||
      avatarPath != old.avatarPath ||
      showBackButton != old.showBackButton ||
      collapsedTitle != old.collapsedTitle ||
      isMuted != old.isMuted ||
      chatType != old.chatType ||
      isSelf != old.isSelf ||
      storyCount != old.storyCount ||
      hasUnreadStory != old.hasUnreadStory ||
      profileBgColors != old.profileBgColors ||
      emojiStatusId != old.emojiStatusId;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final height = (maxHeight - shrinkOffset).clamp(minHeight, maxHeight);
    final t = ((height - minHeight) / (maxHeight - minHeight)).clamp(0.0, 1.0);

    final collapseProgress = (1.0 - t).clamp(0.0, 1.0);
    final titleScale = 0.7 + 0.3 * collapseProgress;
    final actionRatio = height / (_actionButtonSize + minHeight);
    final actionProgress = (actionRatio >= 1.0)
        ? 1.0
        : (actionRatio <= 0.5)
            ? 0.0
            : (actionRatio - 0.5) / 0.5;

    final hasGradientBg = profileBgColors != null && profileBgColors!.length >= 2;
    final hasStories = storyCount > 0;
    final hasEmojiStatus = emojiStatusId.isNotEmpty;
    final ringTotal = hasStories ? _storyLineWidth + _storyRingGap : 0.0;
    final avatarDisplaySize = _avatarSize;
    final ringOuterSize = avatarDisplaySize + ringTotal * 2;
    final patternSize = avatarDisplaySize + 24;

    final isDark = theme.brightness == Brightness.dark;
    final gradientTextColor = hasGradientBg ? Colors.white : null;

    return SizedBox(
      height: height,
      child: Material(
        color: hasGradientBg ? Colors.transparent : theme.colorScheme.surface,
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            if (hasGradientBg)
              Positioned.fill(
                child: CustomPaint(
                  painter: _CoverGradientPainter(
                    colors: profileBgColors!,
                    maxHeight: maxHeight,
                  ),
                ),
              ),
            Positioned(
              top: 24 - ringTotal,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: t,
                child: Center(
                  child: SizedBox(
                    width: ringOuterSize,
                    height: ringOuterSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (hasEmojiStatus)
                          _AnimatedEmojiPattern(
                            size: patternSize,
                            isDark: isDark,
                          ),
                        if (hasStories)
                          CustomPaint(
                            size: Size(ringOuterSize, ringOuterSize),
                            painter: _InfoStoryRingPainter(
                              storyCount: storyCount,
                              hasUnread: hasUnreadStory,
                              isDark: isDark,
                            ),
                          ),
                        SizedBox(
                          width: avatarDisplaySize,
                          height: avatarDisplaySize,
                          child: avatarPath.isNotEmpty
                              ? ClipOval(
                                  child: Image.file(
                                    File(avatarPath),
                                    width: avatarDisplaySize,
                                    height: avatarDisplaySize,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _avatarFallback(avatarColor, initials, avatarDisplaySize),
                                  ),
                                )
                              : _avatarFallback(avatarColor, initials, avatarDisplaySize),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 113,
              left: 20,
              right: 20,
              child: Opacity(
                opacity: t,
                child: Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: gradientTextColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (statusText.isNotEmpty)
              Positioned(
                top: 134,
                left: 20,
                right: 20,
                child: Opacity(
                  opacity: t,
                  child: Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: hasGradientBg
                          ? Colors.white.withValues(alpha: 0.7)
                          : statusColor,
                    ),
                  ),
                ),
              ),
            if (actionProgress > 0 && !isSelf)
              Positioned(
                bottom: 16,
                left: 18,
                right: 18,
                child: Opacity(
                  opacity: actionProgress,
                  child: SizedBox(
                    height: _actionButtonSize,
                    child: _buildActionRow(context, actionProgress),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: minHeight,
              child: Container(
                color: (hasGradientBg
                        ? profileBgColors!.first
                        : theme.colorScheme.surface)
                    .withValues(alpha: collapseProgress),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        showBackButton ? Icons.arrow_back : Icons.close,
                        size: 20,
                        color: hasGradientBg && collapseProgress < 0.5
                            ? Colors.white
                            : null,
                      ),
                      onPressed: onClose,
                      tooltip: showBackButton ? 'Back' : 'Close',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Transform.scale(
                        scale: titleScale,
                        alignment: Alignment.centerLeft,
                        child: Opacity(
                          opacity: collapseProgress,
                          child: Text(
                            collapsedTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: gradientTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 1,
              child: ColoredBox(color: theme.dividerColor),
            ),
          ],
        ),
      ),
    );
  }

  List<_ActionBtnData> _actionButtons() {
    final buttons = <_ActionBtnData>[];
    if (chatType == ChatType.dm && !isSelf) {
      buttons.add(_ActionBtnData(Icons.chat_bubble_outline, 'Message', null));
    }
    if (!isSelf && onMuteToggle != null) {
      buttons.add(_ActionBtnData(
        isMuted ? Icons.notifications_off : Icons.notifications,
        isMuted ? 'Unmute' : 'Mute',
        onMuteToggle,
        isMute: true,
        isMuted: isMuted,
      ));
    }
    if (chatType == ChatType.dm && !isSelf) {
      buttons.add(_ActionBtnData(Icons.call_outlined, 'Call', null));
    }
    if (buttons.length > 3) {
      final overflow = buttons.sublist(2);
      buttons.removeRange(2, buttons.length);
      buttons.add(_ActionBtnData(Icons.more_horiz, 'More', () {
        // overflow popup placeholder — wired when call UI lands
      }));
    }
    return buttons;
  }

  Widget _buildActionRow(BuildContext context, double progress) {
    final iconScale = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    final textScale = progress.clamp(0.4, 1.0);
    final isDark = theme.brightness == Brightness.dark;
    final hasGradientBg = profileBgColors != null && profileBgColors!.length >= 2;
    final bg = hasGradientBg
        ? Colors.white.withValues(alpha: 0.15)
        : (isDark ? const Color(0xFF2b3945) : const Color(0xFFe9ecef));
    final fg = hasGradientBg
        ? Colors.white
        : theme.colorScheme.onSurface;

    final buttons = _actionButtons();
    if (buttons.isEmpty) return const SizedBox.shrink();

    const largeR = 8.0;
    const smallR = 4.0;

    return Row(
      children: [
        for (int i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _actionBtn(
              context,
              buttons[i],
              bg,
              fg,
              iconScale,
              textScale,
              _cornersFor(i, buttons.length, largeR, smallR),
            ),
          ),
        ],
      ],
    );
  }

  static BorderRadius _cornersFor(int i, int count, double lg, double sm) {
    if (count == 1) return BorderRadius.circular(lg);
    if (i == 0) {
      return BorderRadius.only(
        topLeft: Radius.circular(lg), bottomLeft: Radius.circular(lg),
        topRight: Radius.circular(sm), bottomRight: Radius.circular(sm),
      );
    }
    if (i == count - 1) {
      return BorderRadius.only(
        topLeft: Radius.circular(sm), bottomLeft: Radius.circular(sm),
        topRight: Radius.circular(lg), bottomRight: Radius.circular(lg),
      );
    }
    return BorderRadius.circular(sm);
  }

  Widget _actionBtn(BuildContext context, _ActionBtnData data, Color bg,
      Color fg, double iconScale, double textScale, BorderRadius radius) {
    final iconWidget = data.isMute
        ? AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(data.icon, size: 23, color: fg,
                key: ValueKey(data.isMuted)),
          )
        : Icon(data.icon, size: 23, color: fg);

    final labelWidget = data.isMute
        ? AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(data.label, key: ValueKey(data.label),
                style: TextStyle(fontSize: 11, color: fg),
                overflow: TextOverflow.ellipsis),
          )
        : Text(data.label, style: TextStyle(fontSize: 11, color: fg),
              overflow: TextOverflow.ellipsis);

    return Material(
      color: bg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onSecondaryTapUp: data.isMute
            ? (details) => _showMuteMenu(context, details.globalPosition, data)
            : null,
        child: InkWell(
          onTap: data.onTap,
          borderRadius: radius,
          child: SizedBox(
            height: _actionButtonSize,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.scale(scale: iconScale, child: iconWidget),
                const SizedBox(height: 2),
                Transform.scale(scale: textScale, child: labelWidget),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMuteMenu(BuildContext context, Offset position,
      _ActionBtnData data) {
    final isDark = theme.brightness == Brightness.dark;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        if (data.isMuted)
          PopupMenuItem<String>(
            value: 'unmute',
            child: Row(
              children: [
                Icon(Icons.notifications, size: 20,
                    color: const Color(0xFF4dc920)),
                const SizedBox(width: 12),
                const Text('Unmute'),
              ],
            ),
          )
        else
          PopupMenuItem<String>(
            value: 'mute_forever',
            child: Row(
              children: [
                Icon(Icons.notifications_off, size: 20,
                    color: isDark
                        ? const Color(0xFFe85050)
                        : const Color(0xFFdd4b39)),
                const SizedBox(width: 12),
                const Text('Mute forever'),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'unmute' || value == 'mute_forever') {
        data.onTap?.call();
      }
    });
  }

  static Widget _avatarFallback(Color color, String initials, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CoverGradientPainter extends CustomPainter {
  final List<Color> colors;
  final double maxHeight;

  _CoverGradientPainter({required this.colors, required this.maxHeight});

  @override
  void paint(Canvas canvas, Size size) {
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
    );
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, maxHeight),
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_CoverGradientPainter old) =>
      colors != old.colors || maxHeight != old.maxHeight;
}

class _InfoStoryRingPainter extends CustomPainter {
  final int storyCount;
  final bool hasUnread;
  final bool isDark;

  _InfoStoryRingPainter({
    required this.storyCount,
    required this.hasUnread,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (storyCount <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final lineWidth = _FlexibleCoverDelegate._storyLineWidth;
    final ringRadius = size.width / 2 - lineWidth / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;

    if (hasUnread) {
      paint.shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF0dcc39), Color(0xFF0992ef)],
      ).createShader(Rect.fromCircle(center: center, radius: ringRadius));
    } else {
      paint.color = isDark
          ? const Color(0xFF3e546a)
          : const Color(0xFFbbbbbb);
    }

    if (storyCount == 1) {
      canvas.drawCircle(center, ringRadius, paint);
    } else {
      const fullCircleUnits = 5760.0;
      const separatorUnits = 160.0;
      final separatorRadians = (separatorUnits / fullCircleUnits) * 2 * math.pi;
      final totalSep = storyCount * separatorRadians;
      final arcPerStory = (2 * math.pi - totalSep) / storyCount;

      var startAngle = -math.pi / 2;
      final rect = Rect.fromCircle(center: center, radius: ringRadius);

      for (var i = 0; i < storyCount; i++) {
        canvas.drawArc(rect, startAngle, arcPerStory, false, paint);
        startAngle += arcPerStory + separatorRadians;
      }
    }
  }

  @override
  bool shouldRepaint(_InfoStoryRingPainter old) =>
      storyCount != old.storyCount ||
      hasUnread != old.hasUnread ||
      isDark != old.isDark;
}

class _AnimatedEmojiPattern extends StatefulWidget {
  final double size;
  final bool isDark;

  const _AnimatedEmojiPattern({required this.size, required this.isDark});

  @override
  State<_AnimatedEmojiPattern> createState() => _AnimatedEmojiPatternState();
}

class _AnimatedEmojiPatternState extends State<_AnimatedEmojiPattern>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
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
          size: Size(widget.size, widget.size),
          painter: _EmojiStatusPatternPainter(
            progress: _ctrl.value,
            isDark: widget.isDark,
          ),
        );
      },
    );
  }
}

class _EmojiStatusPatternPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  static const int _shapeCount = 8;
  static const double _shapeSize = 6.0;

  _EmojiStatusPatternPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbitRadius = size.width / 2 + 4;
    final baseAngle = progress * 2 * math.pi;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _shapeCount; i++) {
      final angle = baseAngle + (i / _shapeCount) * 2 * math.pi;
      final pulseFactor = 0.7 + 0.3 * math.sin(baseAngle * 3 + i * 0.8);
      final x = center.dx + orbitRadius * math.cos(angle);
      final y = center.dy + orbitRadius * math.sin(angle);
      final shapeRadius = _shapeSize * pulseFactor;

      final opacity = (0.25 + 0.2 * pulseFactor).clamp(0.0, 1.0);
      paint.color = isDark
          ? Color.fromRGBO(139, 92, 246, opacity)
          : Color.fromRGBO(99, 102, 241, opacity);

      _drawDiamond(canvas, Offset(x, y), shapeRadius, paint);
    }
  }

  void _drawDiamond(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.7, center.dy)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * 0.7, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EmojiStatusPatternPainter old) =>
      progress != old.progress || isDark != old.isDark;
}

class _ChatInfoPage extends StatefulWidget {
  final ChatInfo chat;
  final ChatState chatState;
  final ThemeData theme;
  final List<MemberInfo>? members;
  final bool loadingMembers;
  final Map<String, int> mediaCounts;
  final ScrollController scrollController;
  final void Function(MemberInfo) onMemberTap;
  final VoidCallback onClose;
  final bool showBackButton;
  final String title;
  final bool isLayer;

  const _ChatInfoPage({
    required this.chat,
    required this.chatState,
    required this.theme,
    required this.members,
    required this.loadingMembers,
    required this.mediaCounts,
    required this.scrollController,
    required this.onMemberTap,
    required this.onClose,
    required this.showBackButton,
    required this.title,
    this.isLayer = false,
  });

  @override
  State<_ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<_ChatInfoPage> {
  static const _snapPoints = [0.0, 112.0, 180.0];
  Timer? _snapTimer;

  @override
  void dispose() {
    _snapTimer?.cancel();
    super.dispose();
  }

  void _scheduleSnap() {
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _snapToNearest();
    });
  }

  void _snapToNearest() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final offset = position.pixels;
    final maxExtent = position.maxScrollExtent;
    if (offset > _snapPoints.last + 5 || offset < -5) return;

    var nearest = _snapPoints[0];
    var minDist = (offset - nearest).abs();
    for (final p in _snapPoints) {
      if (p > maxExtent + 1) continue;
      final d = (offset - p).abs();
      if (d < minDist) {
        minDist = d;
        nearest = p;
      }
    }
    if (minDist < 1.0) return;

    widget.scrollController.animateTo(
      nearest.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutQuint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDm = widget.chat.type == ChatType.dm;
    final isOnline = widget.chatState.isChatOnline(widget.chat);
    final lastSeen = widget.chatState.chatLastSeen(widget.chat);
    final statusText = isDm
        ? (isOnline ? 'online' : formatChatLastSeen(lastSeen))
        : _AvatarHeader._groupStatusText(widget.chat);
    final statusColor = isDm && isOnline
        ? const Color(0xFF3BA55C)
        : widget.theme.textTheme.bodySmall?.color;
    final colorIndex = widget.chat.chatId.hashCode.abs() % 7;
    final tailPad = MediaQuery.sizeOf(context).height -
        _FlexibleCoverDelegate.minHeight;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification) {
          _scheduleSnap();
        }
        return false;
      },
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _FlexibleCoverDelegate(
              displayName: widget.chat.title.isNotEmpty
                  ? widget.chat.title
                  : widget.chat.chatId,
              statusText: statusText,
              statusColor: statusColor,
              avatarPath: widget.chat.avatarPath,
              avatarColor: _AvatarHeader._avatarColors[colorIndex],
              initials: _AvatarHeader._initials(widget.chat.title),
              theme: widget.theme,
              onClose: widget.onClose,
              showBackButton: widget.showBackButton,
              collapsedTitle: widget.title,
              isMuted: widget.chat.isMuted,
              onMuteToggle: () {
                widget.chatState.muteChat(
                  widget.chat.accountId, widget.chat.chatId,
                  !widget.chat.isMuted,
                );
              },
              chatType: widget.chat.type,
              isSelf: widget.chat.title == 'Saved Messages' &&
                  widget.chat.type == ChatType.dm,
              storyCount: widget.chat.storyCount,
              hasUnreadStory: widget.chat.hasUnreadStory,
              emojiStatusId: widget.chat.emojiStatusId,
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              _ChatDetails(chat: widget.chat, theme: widget.theme),
              const Divider(height: 24),
              _NotificationToggle(chat: widget.chat, theme: widget.theme),
              if (widget.mediaCounts.isNotEmpty) ...[
                const Divider(height: 24),
                _SharedMediaSection(
                  counts: widget.mediaCounts,
                  theme: widget.theme,
                  isLayer: widget.isLayer,
                ),
              ],
              if (widget.chat.type == ChatType.group ||
                  widget.chat.type == ChatType.topic) ...[
                const Divider(height: 24),
                _MembersSection(
                  members: widget.members,
                  loading: widget.loadingMembers,
                  memberCount: widget.chat.memberCount,
                  theme: widget.theme,
                  onMemberTap: widget.onMemberTap,
                ),
              ],
              const SizedBox(height: 16),
            ]),
          ),
          SliverToBoxAdapter(child: SizedBox(height: tailPad)),
        ],
      ),
    );
  }
}

class _UserProfilePage extends StatefulWidget {
  final MemberInfo member;
  final ChatInfo chat;
  final ThemeData theme;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final bool showBackButton;
  final String title;

  const _UserProfilePage({
    required this.member,
    required this.chat,
    required this.theme,
    required this.scrollController,
    required this.onClose,
    required this.showBackButton,
    required this.title,
  });

  @override
  State<_UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<_UserProfilePage> {
  static const _snapPoints = [0.0, 112.0, 180.0];
  Timer? _snapTimer;

  @override
  void dispose() {
    _snapTimer?.cancel();
    super.dispose();
  }

  void _scheduleSnap() {
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _snapToNearest();
    });
  }

  void _snapToNearest() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final offset = position.pixels;
    final maxExtent = position.maxScrollExtent;
    if (offset > _snapPoints.last + 5 || offset < -5) return;

    var nearest = _snapPoints[0];
    var minDist = (offset - nearest).abs();
    for (final p in _snapPoints) {
      if (p > maxExtent + 1) continue;
      final d = (offset - p).abs();
      if (d < minDist) {
        minDist = d;
        nearest = p;
      }
    }
    if (minDist < 1.0) return;

    widget.scrollController.animateTo(
      nearest.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutQuint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorIndex = widget.member.userId.hashCode.abs() % 7;
    final color = _AvatarHeader._avatarColors[colorIndex];
    final name = widget.member.label;
    final initials = _AvatarHeader._initials(name);
    final statusText = widget.member.isOnline
        ? 'online'
        : widget.member.isBot
            ? 'bot'
            : '';
    final statusColor = widget.member.isOnline
        ? const Color(0xFF3BA55C)
        : widget.theme.textTheme.bodySmall?.color;
    final tailPad = MediaQuery.sizeOf(context).height -
        _FlexibleCoverDelegate.minHeight;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification) {
          _scheduleSnap();
        }
        return false;
      },
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _FlexibleCoverDelegate(
              displayName: name,
              statusText: statusText,
              statusColor: statusColor,
              avatarPath: '',
              avatarColor: color,
              initials: initials,
              theme: widget.theme,
              onClose: widget.onClose,
              showBackButton: widget.showBackButton,
              collapsedTitle: widget.title,
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.member.username.isNotEmpty)
                      _DetailRow(
                        icon: Icons.alternate_email,
                        label: 'Username',
                        value: widget.member.username,
                        theme: widget.theme,
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: widget.member.username));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Username copied'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    _DetailRow(
                      icon: Icons.person,
                      label: 'ID',
                      value: widget.member.userId,
                      theme: widget.theme,
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: widget.member.userId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ID copied'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    if (widget.member.role.isNotEmpty &&
                        widget.member.role != 'member')
                      _DetailRow(
                        icon: Icons.shield,
                        label: 'Role',
                        value: widget.member.role,
                        theme: widget.theme,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ]),
          ),
          SliverToBoxAdapter(child: SizedBox(height: tailPad)),
        ],
      ),
    );
  }
}

class _AvatarHeader extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;
  final bool isOnline;
  final ({String kind, int lastSeenMs}) lastSeen;

  const _AvatarHeader({
    required this.chat,
    required this.theme,
    this.isOnline = false,
    this.lastSeen = (kind: '', lastSeenMs: 0),
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = chat.chatId.hashCode.abs() % 7;
    final color = _avatarColors[colorIndex];
    final initials = _initials(chat.title);

    // Compute status line. For DMs: online (green) / last seen (muted).
    // For groups/channels/topics: member or subscriber count (muted).
    final isDm = chat.type == ChatType.dm;
    final String statusText = isDm
        ? (isOnline ? 'online' : formatChatLastSeen(lastSeen))
        : _groupStatusText(chat);
    final Color? statusColor = isDm && isOnline
        ? const Color(0xFF3BA55C) // online green
        : theme.textTheme.bodySmall?.color;

    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: chat.avatarPath.isNotEmpty
              ? ClipOval(
                  child: Image.file(
                    File(chat.avatarPath),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(color, initials),
                  ),
                )
              : _avatarFallback(color, initials),
        ),
        const SizedBox(height: 12),
        // Name.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            chat.title.isNotEmpty ? chat.title : chat.chatId,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Status line: online/last-seen for DMs, member count for groups/channels.
        if (statusText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              statusText,
              style: TextStyle(fontSize: 13, color: statusColor),
            ),
          ),
      ],
    );
  }

  static String _groupStatusText(ChatInfo chat) {
    if (chat.type == ChatType.channel) {
      return '${_formatCount(chat.memberCount)} subscribers';
    }
    if ((chat.type == ChatType.group || chat.type == ChatType.topic) &&
        chat.memberCount > 0) {
      return '${_formatCount(chat.memberCount)} members';
    }
    return '';
  }

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  static Widget _avatarFallback(Color color, String initials) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
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
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77),
    Color(0xFF65aadd), Color(0xFFa695e7), Color(0xFFee7aae),
    Color(0xFF6ec9cb),
  ];
}

class _ChatDetails extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;

  const _ChatDetails({required this.chat, required this.theme});

  void _copyToClipboard(BuildContext context, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chat ID (as username-like field) — tap to copy.
          if (chat.chatId.isNotEmpty)
            _DetailRow(
              icon: Icons.alternate_email,
              label: 'ID',
              value: chat.chatId,
              theme: theme,
              onTap: () => _copyToClipboard(context, chat.chatId, 'ID'),
            ),
          // Account — tap to copy.
          _DetailRow(
            icon: Icons.account_circle,
            label: 'Account',
            value: chat.accountId,
            theme: theme,
            onTap: () => _copyToClipboard(context, chat.accountId, 'Account'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.textTheme.bodySmall?.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(label, style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
              ],
            ),
          ),
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.copy, size: 16, color: theme.textTheme.bodySmall?.color),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: row,
    );
  }
}

class _NotificationToggle extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;

  const _NotificationToggle({required this.chat, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(Icons.notifications, size: 20, color: theme.textTheme.bodySmall?.color),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Notifications', style: theme.textTheme.bodyMedium),
          ),
          Switch(
            value: !chat.isMuted,
            onChanged: (value) {
              final chatState = context.read<ChatState>();
              chatState.muteChat(chat.accountId, chat.chatId, !value);
            },
          ),
        ],
      ),
    );
  }
}

class _SharedMediaSection extends StatefulWidget {
  final Map<String, int> counts;
  final ThemeData theme;
  final bool isLayer;

  const _SharedMediaSection({
    required this.counts,
    required this.theme,
    this.isLayer = false,
  });

  @override
  State<_SharedMediaSection> createState() => _SharedMediaSectionState();
}

class _SharedMediaSectionState extends State<_SharedMediaSection> {
  bool _searchActive = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _activeSubTab = '';

  static const _types = [
    ('photo', Icons.photo_outlined, 'Photos'),
    ('video', Icons.videocam_outlined, 'Videos'),
    ('file', Icons.insert_drive_file_outlined, 'Files'),
    ('audio', Icons.music_note_outlined, 'Music'),
    ('link', Icons.link, 'Links'),
    ('voice', Icons.mic_outlined, 'Voice'),
    ('gif', Icons.gif_box_outlined, 'GIFs'),
  ];

  static const _subTabSets = <String, List<(String, String)>>{
    'stories': [('archive', 'Archive'), ('recent', 'Recent')],
    'gifts': [('all', 'All'), ('unique', 'Unique'), ('limited', 'Limited')],
  };

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _types.where((t) => (widget.counts[t.$1] ?? 0) > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final iconColor = widget.theme.textTheme.bodySmall?.color ?? Colors.grey;
    final isDark = widget.theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF168acd);

    final hasStories = (widget.counts['stories'] ?? 0) > 0;
    final hasGifts = (widget.counts['gifts'] ?? 0) > 0;
    final showSubTabs = hasStories || hasGifts;
    final subTabKey = hasStories ? 'stories' : (hasGifts ? 'gifts' : '');
    final subTabs = _subTabSets[subTabKey] ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MediaSearchRow(
            isLayer: widget.isLayer,
            active: _searchActive,
            controller: _searchController,
            focusNode: _searchFocusNode,
            theme: widget.theme,
            onToggle: () {
              setState(() {
                _searchActive = !_searchActive;
                if (_searchActive) {
                  _searchFocusNode.requestFocus();
                } else {
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                }
              });
            },
            onCancel: () {
              setState(() {
                _searchActive = false;
                _searchController.clear();
                _searchFocusNode.unfocus();
              });
            },
          ),
          if (showSubTabs && subTabs.isNotEmpty)
            _SubTabChips(
              tabs: subTabs,
              activeTab: _activeSubTab.isEmpty
                  ? subTabs.first.$1
                  : _activeSubTab,
              accentColor: accentColor,
              theme: widget.theme,
              onSelected: (tab) => setState(() => _activeSubTab = tab),
            ),
          for (final (type, icon, label) in visible)
            _SharedMediaRow(
              icon: icon,
              label: label,
              count: widget.counts[type]!,
              iconColor: iconColor,
              accentColor: accentColor,
              theme: widget.theme,
            ),
        ],
      ),
    );
  }
}

class _MediaSearchRow extends StatelessWidget {
  final bool isLayer;
  final bool active;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ThemeData theme;
  final VoidCallback onToggle;
  final VoidCallback onCancel;

  const _MediaSearchRow({
    required this.isLayer,
    required this.active,
    required this.controller,
    required this.focusNode,
    required this.theme,
    required this.onToggle,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final height = isLayer ? 46.0 : 44.0;
    final isDark = theme.brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1c2733) : const Color(0xFFe8e8e8);
    final iconColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: height - 12,
                decoration: BoxDecoration(
                  color: fieldBg,
                  borderRadius: BorderRadius.circular((height - 12) / 2),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Icon(Icons.search, size: 18, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: active
                          ? TextField(
                              controller: controller,
                              focusNode: focusNode,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Search',
                                hintStyle: TextStyle(fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            )
                          : GestureDetector(
                              onTap: onToggle,
                              behavior: HitTestBehavior.opaque,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Search',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: iconColor,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    if (active)
                      GestureDetector(
                        onTap: onCancel,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          child: Icon(Icons.close, size: 16, color: iconColor),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubTabChips extends StatelessWidget {
  final List<(String, String)> tabs;
  final String activeTab;
  final Color accentColor;
  final ThemeData theme;
  final ValueChanged<String> onSelected;

  const _SubTabChips({
    required this.tabs,
    required this.activeTab,
    required this.accentColor,
    required this.theme,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final inactiveColor = isDark ? const Color(0xFF3e546a) : const Color(0xFFbbbbbb);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _buildChip(tabs[i].$1, tabs[i].$2, inactiveColor),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(String key, String label, Color inactiveColor) {
    final isActive = activeTab == key;
    return GestureDetector(
      onTap: () => onSelected(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? accentColor : inactiveColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}

class _SharedMediaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color iconColor;
  final Color accentColor;
  final ThemeData theme;

  const _SharedMediaRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.iconColor,
    required this.accentColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              _formatCount(count),
              style: TextStyle(
                fontSize: 13,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: iconColor),
          ],
        ),
      ),
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _MembersSection extends StatelessWidget {
  final List<MemberInfo>? members;
  final bool loading;
  final int memberCount;
  final ThemeData theme;
  final void Function(MemberInfo)? onMemberTap;

  const _MembersSection({
    required this.members,
    required this.loading,
    required this.memberCount,
    required this.theme,
    this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    memberCount > 0 ? '$memberCount Members' : 'Members',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.search, size: 20, color: theme.textTheme.bodyMedium?.color),
                    onPressed: () {},
                    splashRadius: 19,
                  ),
                ),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.person_add_outlined, size: 20, color: theme.textTheme.bodyMedium?.color),
                    onPressed: () {},
                    splashRadius: 19,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else if (members != null && members!.isNotEmpty)
          ...members!.map((m) => _MemberRow(member: m, theme: theme, onTap: onMemberTap != null ? () => onMemberTap!(m) : null))
        else
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 8, bottom: 8),
            child: Text(
              'No members available',
              style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
            ),
          ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final MemberInfo member;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _MemberRow({required this.member, required this.theme, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = member.displayName.isNotEmpty ? member.displayName : member.username;
    final colorIndex = member.userId.hashCode.abs() % 7;
    final color = [
      const Color(0xFFe17076), const Color(0xFF7bc862), const Color(0xFFe5ca77),
      const Color(0xFF65aadd), const Color(0xFFa695e7), const Color(0xFFee7aae),
      const Color(0xFF6ec9cb),
    ][colorIndex];

    final bool hasAdminTag = member.role == 'owner' || member.role == 'admin' || member.role == 'creator';

    String statusText = '';
    Color statusColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
    if (member.isOnline) {
      statusText = 'online';
      statusColor = theme.colorScheme.primary;
    } else if (member.role != 'member' && member.role.isNotEmpty && !hasAdminTag) {
      statusText = member.role;
    } else {
      statusText = 'last seen recently';
    }

    Widget row = SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.only(left: 18),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 19),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name.isNotEmpty ? name : member.userId,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (member.isBot) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.smart_toy, size: 14, color: theme.textTheme.bodySmall?.color),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            statusText,
                            style: TextStyle(fontSize: 13, color: statusColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasAdminTag)
                          Container(
                            margin: const EdgeInsets.only(left: 5, right: 5),
                            padding: const EdgeInsets.only(left: 5, top: 0, right: 5, bottom: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              member.role == 'owner' || member.role == 'creator' ? 'owner' : 'admin',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return InkWell(
      onTap: onTap,
      child: row,
    );
  }
}
