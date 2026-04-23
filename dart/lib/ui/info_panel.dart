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

    try {
      final engine = context.read<EngineService>();
      final members = await engine.getChatMembers(chat.accountId, chat.chatId);
      if (mounted) {
        setState(() {
          _members = members;
          _loadingMembers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _members = [];
          _loadingMembers = false;
        });
      }
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
  final int storyCount;
  final bool hasUnreadStory;
  final List<Color>? profileBgColors;

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
    this.storyCount = 0,
    this.hasUnreadStory = false,
    this.profileBgColors,
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
      storyCount != old.storyCount ||
      hasUnreadStory != old.hasUnreadStory ||
      profileBgColors != old.profileBgColors;

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
    final ringTotal = hasStories ? _storyLineWidth + _storyRingGap : 0.0;
    final avatarDisplaySize = _avatarSize;
    final ringOuterSize = avatarDisplaySize + ringTotal * 2;

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
            if (actionProgress > 0 && onMuteToggle != null)
              Positioned(
                bottom: 16,
                left: 18,
                right: 18,
                child: Opacity(
                  opacity: actionProgress,
                  child: SizedBox(
                    height: _actionButtonSize,
                    child: _buildActionRow(actionProgress),
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

  Widget _buildActionRow(double progress) {
    final iconScale = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    final textScale = progress.clamp(0.4, 1.0);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2b3945) : const Color(0xFFe9ecef);
    final fg = theme.colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _actionBtn(
          isMuted ? Icons.notifications_off : Icons.notifications,
          isMuted ? 'Unmute' : 'Mute',
          bg, fg, iconScale, textScale, onMuteToggle,
        ),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, Color bg, Color fg,
      double iconScale, double textScale, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _actionButtonSize,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Transform.scale(
                scale: iconScale,
                child: Icon(icon, size: 20, color: fg),
              ),
            ),
            Transform.scale(
              scale: textScale,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  label,
                  style: TextStyle(fontSize: 10, color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

class _ChatInfoPage extends StatefulWidget {
  final ChatInfo chat;
  final ChatState chatState;
  final ThemeData theme;
  final List<MemberInfo>? members;
  final bool loadingMembers;
  final ScrollController scrollController;
  final void Function(MemberInfo) onMemberTap;
  final VoidCallback onClose;
  final bool showBackButton;
  final String title;

  const _ChatInfoPage({
    required this.chat,
    required this.chatState,
    required this.theme,
    required this.members,
    required this.loadingMembers,
    required this.scrollController,
    required this.onMemberTap,
    required this.onClose,
    required this.showBackButton,
    required this.title,
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
              storyCount: widget.chat.storyCount,
              hasUnreadStory: widget.chat.hasUnreadStory,
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              _ChatDetails(chat: widget.chat, theme: widget.theme),
              const Divider(height: 24),
              _NotificationToggle(chat: widget.chat, theme: widget.theme),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Members',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (memberCount > 0) ...[
                const SizedBox(width: 6),
                Text(
                  memberCount.toString(),
                  style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ))
          else if (members != null && members!.isNotEmpty)
            ...members!.map((m) => _MemberRow(member: m, theme: theme, onTap: onMemberTap != null ? () => onMemberTap!(m) : null))
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No members available',
                style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
              ),
            ),
        ],
      ),
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

    Widget row = Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isNotEmpty ? name : member.userId,
                        style: theme.textTheme.bodyMedium,
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
                if (member.role != 'member' && member.role.isNotEmpty)
                  Text(
                    member.role,
                    style: TextStyle(
                      fontSize: 12,
                      color: member.role == 'owner'
                          ? theme.colorScheme.primary
                          : theme.textTheme.bodySmall?.color,
                    ),
                  )
                else if (member.isOnline)
                  Text(
                    'online',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: theme.textTheme.bodySmall?.color),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: row,
      );
    }
    return row;
  }
}
