import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'chat_view.dart' show formatChatLastSeen;
import 'confirm_box.dart';
import 'admin_tools.dart' show showEditAdminBox, showEditPeerInfoBox, showEditRestrictedBox;
import 'create_group_wizard.dart' show showEditPeerTypeBox;
import 'edit_forum_topic_box.dart';
import 'forum_topic_icon.dart';
import 'popup_menu.dart';

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
  int _loadedMemberCount = 0;
  Map<String, int> _mediaCounts = {};
  List<PinnedGiftItem> _pinnedGifts = [];
  StreamSubscription<ChatInfo>? _chatUpdatedSub;

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
    _chatUpdatedSub?.cancel();
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
    _chatUpdatedSub ??= context.read<EngineService>().onChatUpdated.listen(_onChatUpdated);
  }

  void _onChatUpdated(ChatInfo updated) {
    if (_loadedChatId == null) return;
    if (updated.chatId != _loadedChatId) return;
    if (updated.memberCount != _loadedMemberCount) {
      _loadMembers(updated);
    }
  }

  Future<void> _loadMembers(ChatInfo chat) async {
    if (_loadingMembers) return;
    setState(() {
      _loadingMembers = true;
      _loadedChatId = chat.chatId;
      _loadedMemberCount = chat.memberCount;
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

    List<PinnedGiftItem> gifts = [];
    if (chat.type == ChatType.dm) {
      try {
        final result = await engine.getPinnedStarGifts(chat.accountId, chat.chatId);
        if (result != null) gifts = result.gifts;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _members = members;
        _mediaCounts = counts;
        _pinnedGifts = gifts;
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
          pinnedGifts: _pinnedGifts,
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
  final List<PinnedGiftItem> pinnedGifts;

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
    this.pinnedGifts = const [],
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
      emojiStatusId != old.emojiStatusId ||
      pinnedGifts.length != old.pinnedGifts.length;

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
            if (pinnedGifts.isNotEmpty)
              Positioned(
                top: 24 - ringTotal,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: t,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final panelW = constraints.maxWidth;
                      final acx = panelW / 2;
                      const acy = 40.0;
                      const aw = _avatarSize;
                      const giftSize = 20.0;
                      final avatarTop = acy - aw / 2;
                      final avatarBottom = acy + aw / 2;
                      final positions = <Offset>[
                        Offset(acx / 2 - 15, acy - 13),
                        Offset(2 * acx / 3 - 4, avatarTop - 4),
                        Offset(2 * acx / 3 - 9, avatarBottom - 16),
                        Offset(acx + aw / 2 + 50, acy - 13),
                        Offset(acx + aw / 3 + 30, avatarTop - 4),
                        Offset(acx + aw / 3 + 40, avatarBottom - 13),
                      ];
                      return SizedBox(
                        width: panelW,
                        height: aw + ringTotal * 2,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var i = 0; i < pinnedGifts.length && i < 6; i++)
                              Positioned(
                                left: positions[i].dx,
                                top: positions[i].dy,
                                child: _PinnedGiftWidget(
                                  gift: pinnedGifts[i],
                                  size: giftSize,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        if (data.isMuted)
          const TelegramMenuItem(value: 'unmute', icon: Icon(Icons.notifications), label: 'Unmute')
        else
          const TelegramMenuItem(value: 'mute_forever', icon: Icon(Icons.notifications_off), label: 'Mute forever', isAttention: true),
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

class _PinnedGiftWidget extends StatelessWidget {
  final PinnedGiftItem gift;
  final double size;

  const _PinnedGiftWidget({required this.gift, required this.size});

  @override
  Widget build(BuildContext context) {
    if (gift.thumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(gift.thumbB64);
        return ClipOval(
          child: Image.memory(
            Uint8List.fromList(bytes),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0x30808080),
      ),
      child: Icon(Icons.card_giftcard, size: size * 0.6, color: const Color(0xFF40a7e3)),
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

class _MemberStoryRingPainter extends CustomPainter {
  final int storyCount;
  final bool hasUnread;
  final bool isDark;

  _MemberStoryRingPainter({
    required this.storyCount,
    required this.hasUnread,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (storyCount <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    const lineWidth = 2.0;
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
  bool shouldRepaint(_MemberStoryRingPainter old) =>
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

class _TopicInfoCoverDelegate extends SliverPersistentHeaderDelegate {
  final ForumTopic topic;
  final String accountId;
  final String statusText;
  final ThemeData theme;
  final VoidCallback onClose;
  final bool showBackButton;
  final ChatInfo chat;

  static const double coverHeight = 77.0;

  _TopicInfoCoverDelegate({
    required this.topic,
    required this.accountId,
    required this.statusText,
    required this.theme,
    required this.onClose,
    required this.showBackButton,
    required this.chat,
  });

  @override
  double get maxExtent => coverHeight;
  @override
  double get minExtent => coverHeight;

  @override
  bool shouldRebuild(covariant _TopicInfoCoverDelegate old) =>
      topic.id != old.topic.id ||
      topic.title != old.topic.title ||
      topic.colorId != old.topic.colorId ||
      topic.iconEmojiId != old.topic.iconEmojiId ||
      statusText != old.statusText ||
      showBackButton != old.showBackButton;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final isDark = theme.brightness == Brightness.dark;
    final isGeneral = topic.isGeneral;
    final nameColor = theme.textTheme.titleMedium?.color ?? (isDark ? Colors.white : Colors.black);
    final statusColor = isDark ? const Color(0xFF7F91A4) : const Color(0xFF999999);
    final engine = context.read<EngineService>();

    Widget iconWidget;
    if (isGeneral) {
      iconWidget = GeneralForumTopicIcon(
        size: ForumTopicIcon.infoSize,
        iconContext: GeneralIconContext.profile,
      );
    } else if (topic.hasCustomIcon) {
      iconWidget = CustomEmojiTopicIcon(
        documentId: topic.iconEmojiId,
        accountId: accountId,
        engine: engine,
        size: 36,
      );
    } else {
      iconWidget = ForumTopicIcon(
        colorId: topic.colorId,
        title: topic.title,
        size: 36,
      );
    }

    return SizedBox(
      height: coverHeight,
      child: Material(
        color: theme.colorScheme.surface,
        child: Stack(
          children: [
            Positioned(
              left: 22,
              top: 18,
              width: 36,
              height: 36,
              child: iconWidget,
            ),
            Positioned(
              left: 79,
              top: 14,
              right: 88,
              child: Text(
                isGeneral ? '# ${topic.title}' : topic.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: nameColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Positioned(
              left: 79,
              top: 38,
              right: 88,
              child: Text(
                isGeneral ? 'General' : statusText,
                style: TextStyle(
                  fontSize: 13,
                  color: isGeneral ? statusColor : statusColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SizedBox(
                height: coverHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TopicInfoMenuButton(
                      topic: topic,
                      chat: chat,
                      theme: theme,
                    ),
                    IconButton(
                      icon: Icon(
                        showBackButton ? Icons.arrow_back : Icons.close,
                        size: 20,
                      ),
                      onPressed: onClose,
                      tooltip: showBackButton ? 'Back' : 'Close',
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
}

class _TopicInfoMenuButton extends StatelessWidget {
  final ForumTopic topic;
  final ChatInfo chat;
  final ThemeData theme;

  const _TopicInfoMenuButton({
    required this.topic,
    required this.chat,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.more_vert, size: 20),
      onPressed: () {
        final box = context.findRenderObject() as RenderBox;
        final pos = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
        _showTopicInfoMenu(context, pos);
      },
      tooltip: 'Menu',
    );
  }

  void _showTopicInfoMenu(BuildContext context, Offset position) async {
    final engine = context.read<EngineService>();
    final chatState = context.read<ChatState>();
    final parentChat = chatState.forumParentChat;
    final parentChatId = topic.parentId.isNotEmpty
        ? topic.parentId
        : (parentChat?.chatId ?? chat.parentId);

    final value = await showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'ttl',
          icon: Icon(
            chat.ttlPeriod > 0 ? Icons.timer : Icons.timer_outlined,
            size: 20,
          ),
          label: chat.ttlPeriod > 0
              ? 'Auto-Delete (${_formatTtl(chat.ttlPeriod)})'
              : 'Auto-Delete Timer',
        ),
        const TelegramMenuItem(
          value: 'copy_link',
          icon: Icon(Icons.link, size: 20),
          label: 'Copy Topic Link',
        ),
        if (topic.canEdit)
          const TelegramMenuItem(
            value: 'edit',
            icon: Icon(Icons.edit_outlined, size: 20),
            label: 'Edit Topic',
          ),
        if (topic.canToggleClosed)
          TelegramMenuItem(
            value: 'toggle_closed',
            icon: Icon(
              topic.isClosed ? Icons.lock_open : Icons.lock_outline,
              size: 20,
            ),
            label: topic.isClosed ? 'Reopen Topic' : 'Close Topic',
          ),
        if (topic.isGeneral && topic.canEdit)
          TelegramMenuItem(
            value: 'toggle_hidden',
            icon: Icon(
              topic.isHidden ? Icons.visibility : Icons.visibility_off,
              size: 20,
            ),
            label: topic.isHidden ? 'Show Topic' : 'Hide Topic',
          ),
        if (topic.canDelete && !topic.isGeneral) ...[
          const TelegramMenuItem.separator(),
          const TelegramMenuItem(
            value: 'delete',
            icon: Icon(Icons.delete_outline, size: 20),
            label: 'Delete Topic',
            isAttention: true,
          ),
        ],
      ],
    );

    if (value == null || !context.mounted) return;
    final topicId = int.tryParse(topic.id) ?? 0;

    switch (value) {
      case 'ttl':
        _showTtlSubmenu(context, position);
      case 'copy_link':
        try {
          final username = await engine.getChatUsername(chat.accountId, parentChatId);
          if (username.isNotEmpty && context.mounted) {
            final link = 'https://t.me/$username/${topic.id}';
            Clipboard.setData(ClipboardData(text: link));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Topic link copied'),
                duration: Duration(seconds: 2),
              ),
            );
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This group has no public link'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not get topic link'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      case 'edit':
        final result = await showEditForumTopicBox(
          context,
          existingTitle: topic.title,
          existingColorId: topic.colorId,
          existingIconEmojiId: topic.iconEmojiId,
          isGeneral: topic.isGeneral,
          isEditing: true,
        );
        if (result == null || !context.mounted) return;
        try {
          await engine.editForumTopic(
            chat.accountId, parentChatId, topicId, result.title,
            iconEmojiId: topic.isGeneral ? -1 : result.iconEmojiId,
          );
          await chatState.refreshForumTopics();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to edit topic: $e')),
            );
          }
        }
      case 'toggle_closed':
        try {
          await chatState.toggleForumTopicClosed(
            chat.accountId, parentChatId, topicId, !topic.isClosed,
          );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed: $e')),
            );
          }
        }
      case 'toggle_hidden':
        try {
          await chatState.toggleGeneralTopicHidden(
            chat.accountId, parentChatId, !topic.isHidden,
          );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed: $e')),
            );
          }
        }
      case 'delete':
        if (!context.mounted) return;
        final r = await showDeleteConfirmBox(
          context,
          mode: DeleteBoxMode.clearHistory,
          chatType: ChatType.topic,
          peerName: topic.title,
        );
        if (r.confirmed && context.mounted) {
          try {
            await chatState.deleteForumTopicHistory(
              chat.accountId, parentChatId, topicId,
            );
            await chatState.refreshForumTopics();
            chatState.closeChat();
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed: $e')),
              );
            }
          }
        }
    }
  }

  void _showTtlSubmenu(BuildContext context, Offset position) async {
    final chatState = context.read<ChatState>();
    final accentColor = theme.colorScheme.primary;
    final value = await showTelegramMenu<int>(
      context: context,
      position: position,
      items: [
        for (final e in const <MapEntry<int, String>>[
          MapEntry(0, 'Off'),
          MapEntry(86400, '1 day'),
          MapEntry(604800, '7 days'),
          MapEntry(2678400, '1 month'),
        ])
          TelegramMenuItem(
            value: e.key,
            icon: Icon(
              e.key == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
              size: 20,
              color: e.key == chat.ttlPeriod ? accentColor : null,
            ),
            label: e.value,
            labelColor: e.key == chat.ttlPeriod ? accentColor : null,
          ),
      ],
    );
    if (value != null && value != chat.ttlPeriod && context.mounted) {
      chatState.setHistoryTTL(chat.accountId, chat.chatId, value);
    }
  }

  static String _formatTtl(int seconds) {
    if (seconds <= 0) return 'Off';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    final days = seconds ~/ 86400;
    if (days < 31) return '${days}d';
    return '${days ~/ 30}mo';
  }
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
  final List<PinnedGiftItem> pinnedGifts;

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
    this.pinnedGifts = const [],
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

  ForumTopic? _findActiveTopic() {
    if (widget.chat.type != ChatType.topic) return null;
    final topics = widget.chatState.forumTopics;
    for (final t in topics) {
      if (t.id == widget.chat.chatId) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isTopic = widget.chat.type == ChatType.topic;
    final activeTopic = isTopic ? _findActiveTopic() : null;

    if (isTopic && activeTopic != null) {
      return _buildTopicInfoView(context, activeTopic);
    }

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
              pinnedGifts: widget.pinnedGifts,
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
                  accountId: widget.chat.accountId,
                  chatId: widget.chat.chatId,
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
                  accountId: widget.chat.accountId,
                  chatId: widget.chat.chatId,
                ),
              ],
              if (widget.chat.type == ChatType.group ||
                  widget.chat.type == ChatType.topic) ...[
                const Divider(height: 24),
                _GroupActionsSection(
                  chat: widget.chat,
                  theme: widget.theme,
                  members: widget.members,
                ),
              ],
              if (widget.chat.type == ChatType.channel) ...[
                const Divider(height: 24),
                _ChannelActionsSection(
                  chat: widget.chat,
                  theme: widget.theme,
                  members: widget.members,
                ),
              ],
              if (widget.chat.type == ChatType.dm &&
                  widget.chat.title != 'Saved Messages') ...[
                const Divider(height: 24),
                _DmActionsSection(
                  chat: widget.chat,
                  theme: widget.theme,
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

  Widget _buildTopicInfoView(BuildContext context, ForumTopic topic) {
    final parentChat = widget.chatState.forumParentChat;
    String statusText;
    if (parentChat != null && parentChat.memberCount > 0) {
      statusText = '${parentChat.memberCount} members';
    } else if (widget.chat.parentTitle.isNotEmpty) {
      statusText = widget.chat.parentTitle;
    } else {
      statusText = '';
    }

    final tailPad = MediaQuery.sizeOf(context).height -
        _TopicInfoCoverDelegate.coverHeight;

    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _TopicInfoCoverDelegate(
            topic: topic,
            accountId: widget.chat.accountId,
            statusText: statusText,
            theme: widget.theme,
            onClose: widget.onClose,
            showBackButton: widget.showBackButton,
            chat: widget.chat,
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: 16),
            _NotificationToggle(chat: widget.chat, theme: widget.theme),
            if (widget.mediaCounts.isNotEmpty) ...[
              const Divider(height: 24),
              _SharedMediaSection(
                counts: widget.mediaCounts,
                theme: widget.theme,
                isLayer: widget.isLayer,
                accountId: widget.chat.accountId,
                chatId: widget.chat.chatId,
              ),
            ],
            const Divider(height: 24),
            _MembersSection(
              members: widget.members,
              loading: widget.loadingMembers,
              memberCount: widget.chat.memberCount,
              theme: widget.theme,
              onMemberTap: widget.onMemberTap,
              accountId: widget.chat.accountId,
              chatId: widget.chat.chatId,
            ),
            const SizedBox(height: 16),
          ]),
        ),
        SliverToBoxAdapter(child: SizedBox(height: tailPad)),
      ],
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.member.username.isNotEmpty)
                    _TextWithLabel(
                      value: '@${widget.member.username}',
                      label: 'Username',
                      theme: widget.theme,
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: '@${widget.member.username}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Username copied'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  _TextWithLabel(
                    value: widget.member.userId,
                    label: 'ID',
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
                    _TextWithLabel(
                      value: widget.member.role,
                      label: 'Role',
                      theme: widget.theme,
                    ),
                ],
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

class _ChatDetails extends StatefulWidget {
  final ChatInfo chat;
  final ThemeData theme;

  const _ChatDetails({required this.chat, required this.theme});

  @override
  State<_ChatDetails> createState() => _ChatDetailsState();
}

class _ChatDetailsState extends State<_ChatDetails> {
  UserProfile? _profile;
  bool _fetched = false;
  String? _fetchedFor;
  StreamSubscription<ChatInfo>? _chatUpdatedSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatUpdatedSub ??= context.read<EngineService>().onChatUpdated.listen(_onChatUpdated);
    _fetchIfNeeded();
  }

  @override
  void didUpdateWidget(_ChatDetails old) {
    super.didUpdateWidget(old);
    if (old.chat.chatId != widget.chat.chatId) {
      _fetched = false;
      _fetchIfNeeded();
    }
  }

  @override
  void dispose() {
    _chatUpdatedSub?.cancel();
    super.dispose();
  }

  void _onChatUpdated(ChatInfo updated) {
    if (widget.chat.type != ChatType.dm) return;
    if (updated.chatId != widget.chat.chatId) return;
    _refetchProfile();
  }

  void _refetchProfile() {
    final engine = context.read<EngineService>();
    engine.getUserProfile(widget.chat.accountId, widget.chat.chatId).then((p) {
      if (mounted && p != null) {
        final changed = _profile == null ||
            _profile!.phone != p.phone ||
            _profile!.username != p.username ||
            _profile!.bio != p.bio;
        if (changed) setState(() { _profile = p; _fetched = true; });
      }
    });
  }

  void _fetchIfNeeded() {
    if (widget.chat.type != ChatType.dm) return;
    final key = '${widget.chat.accountId}:${widget.chat.chatId}';
    if (_fetchedFor == key) return;
    _fetchedFor = key;
    _fetched = false;
    final engine = context.read<EngineService>();
    engine.getUserProfile(widget.chat.accountId, widget.chat.chatId).then((p) {
      if (mounted && p != null) setState(() { _profile = p; _fetched = true; });
    });
  }

  void _copy(String value, String label) {
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
    final isDm = widget.chat.type == ChatType.dm;
    final profile = _profile;

    if (isDm && profile != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (profile.phone.isNotEmpty)
            _TextWithLabel(
              value: '+${profile.phone}',
              label: 'Phone',
              theme: widget.theme,
              onTap: () => _copy('+${profile.phone}', 'Phone'),
            ),
          if (profile.username.isNotEmpty)
            _TextWithLabel(
              value: '@${profile.username}',
              label: 'Username',
              theme: widget.theme,
              onTap: () => _copy('@${profile.username}', 'Username'),
            ),
          if (profile.bio.isNotEmpty)
            _TextWithLabel(
              value: profile.bio,
              label: 'Bio',
              theme: widget.theme,
              onTap: () => _copy(profile.bio, 'Bio'),
              selectable: true,
            ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _TextWithLabel extends StatelessWidget {
  final String value;
  final String label;
  final ThemeData theme;
  final VoidCallback? onTap;
  final bool selectable;

  const _TextWithLabel({
    required this.value,
    required this.label,
    required this.theme,
    this.onTap,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(left: 23, top: 9, right: 20, bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectable)
            SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              maxLines: 5,
            )
          else
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
            ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
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

class _GroupActionsSection extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;
  final List<MemberInfo>? members;

  const _GroupActionsSection({
    required this.chat,
    required this.theme,
    this.members,
  });

  bool _isSelfAdminIn(BuildContext context) {
    if (members == null) return false;
    final appState = context.read<AppState>();
    final selfUserId = appState.activeAccount?.selfUserId ?? '';
    final accountId = chat.accountId;
    for (final m in members!) {
      if (m.role == 'owner' || m.role == 'admin' || m.role == 'creator') {
        if (m.userId == selfUserId ||
            m.userId == accountId ||
            (selfUserId.isNotEmpty && m.userId.contains(selfUserId))) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final _isSelfAdmin = _isSelfAdminIn(context);
    final chatState = context.read<ChatState>();
    final attentionColor = const Color(0xFFDD4B39);
    final accentColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isSelfAdmin)
          _ActionRow(
            icon: Icons.edit,
            label: 'Edit Group',
            theme: theme,
            onTap: () => _editGroup(context, chatState),
          ),
        if (_isSelfAdmin)
          _ActionRow(
            icon: Icons.lock_outline,
            label: 'Group Type',
            theme: theme,
            onTap: () => showEditPeerTypeBox(
              context,
              accountId: chat.accountId,
              chatId: chat.chatId,
              isChannel: false,
            ),
          ),
        if (_isSelfAdmin)
          _ActionRow(
            icon: Icons.forum_outlined,
            label: 'Topics',
            theme: theme,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              ],
            ),
            onTap: () => _showForumTopicsDialog(context),
          ),
        _ActionRow(
          icon: Icons.flag_outlined,
          label: 'Report',
          theme: theme,
          onTap: () => _confirmReport(context, chatState),
        ),
        _ActionRow(
          icon: Icons.logout,
          label: 'Leave Group',
          theme: theme,
          color: attentionColor,
          onTap: () => _confirmLeave(context, chatState),
        ),
      ],
    );
  }

  void _showForumTopicsDialog(BuildContext context) {
    final engine = context.read<EngineService>();
    showDialog(
      context: context,
      builder: (ctx) => _ForumTopicsDialog(
        chat: chat,
        engine: engine,
        theme: theme,
      ),
    );
  }

  void _editGroup(BuildContext context, ChatState chatState) {
    showEditPeerInfoBox(context, chat: chat, members: members);
  }

  void _confirmReport(BuildContext context, ChatState chatState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report Group'),
        content: Text('Report ${chat.title} as spam?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDD4B39)),
            onPressed: () {
              chatState.reportSpam(chat.accountId, chat.chatId);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Group reported'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext context, ChatState chatState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Leave ${chat.title}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDD4B39)),
            onPressed: () {
              chatState.leaveChat(chat.accountId, chat.chatId);
              Navigator.pop(ctx);
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}

enum _ForumLayout { tabs, list }

class _ForumTopicsDialog extends StatefulWidget {
  final ChatInfo chat;
  final EngineService engine;
  final ThemeData theme;

  const _ForumTopicsDialog({
    required this.chat,
    required this.engine,
    required this.theme,
  });

  @override
  State<_ForumTopicsDialog> createState() => _ForumTopicsDialogState();
}

class _ForumTopicsDialogState extends State<_ForumTopicsDialog> {
  bool _enabled = false;
  _ForumLayout _layout = _ForumLayout.tabs;
  bool _saving = false;
  String? _error;

  static const int _minMembers = 200;

  bool get _hasEnoughMembers => widget.chat.memberCount >= _minMembers;

  String get _aboutText {
    if (!_enabled) return 'Topics are disabled for this group.';
    if (_layout == _ForumLayout.tabs) {
      return 'Members will see topics as tabs at the top of the chat.';
    }
    return 'Members will see topics as a list.';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.theme.colorScheme.primary;
    final mutedFg = widget.theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Text(
                      'Topics',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: widget.theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_hasEnoughMembers) ...[
                const SizedBox(height: 8),
                Text(
                  'You need at least $_minMembers members to enable topics.',
                  style: TextStyle(fontSize: 13, color: mutedFg),
                ),
                const SizedBox(height: 16),
              ] else ...[
                SwitchListTile(
                  title: const Text('Enable Topics', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  value: _enabled,
                  activeColor: accent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                if (_enabled) ...[
                  const SizedBox(height: 8),
                  RadioListTile<_ForumLayout>(
                    title: const Text('Tabs', style: TextStyle(fontSize: 14)),
                    value: _ForumLayout.tabs,
                    groupValue: _layout,
                    activeColor: accent,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _layout = v ?? _ForumLayout.tabs),
                  ),
                  RadioListTile<_ForumLayout>(
                    title: const Text('List', style: TextStyle(fontSize: 14)),
                    value: _ForumLayout.list,
                    groupValue: _layout,
                    activeColor: accent,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _layout = v ?? _ForumLayout.list),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _aboutText,
                  style: TextStyle(fontSize: 13, color: mutedFg),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFDD4B39))),
                ],
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  if (_hasEnoughMembers) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.engine.toggleForum(
        widget.chat.accountId,
        widget.chat.chatId,
        _enabled,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }
}

class _ChannelActionsSection extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;
  final List<MemberInfo>? members;

  const _ChannelActionsSection({required this.chat, required this.theme, this.members});

  bool _isSelfAdminIn(BuildContext context) {
    if (members == null) return false;
    final appState = context.read<AppState>();
    final selfUserId = appState.activeAccount?.selfUserId ?? '';
    final accountId = chat.accountId;
    for (final m in members!) {
      if (m.role == 'owner' || m.role == 'admin' || m.role == 'creator') {
        if (m.userId == selfUserId ||
            m.userId == accountId ||
            (selfUserId.isNotEmpty && m.userId.contains(selfUserId))) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final _isSelfAdmin = _isSelfAdminIn(context);
    final chatState = context.read<ChatState>();
    final attentionColor = const Color(0xFFDD4B39);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isSelfAdmin)
          _ActionRow(
            icon: Icons.edit,
            label: 'Edit Channel',
            theme: theme,
            onTap: () => showEditPeerInfoBox(context, chat: chat, members: members),
          ),
        if (_isSelfAdmin)
          _ActionRow(
            icon: Icons.lock_outline,
            label: 'Channel Type',
            theme: theme,
            onTap: () => showEditPeerTypeBox(
              context,
              accountId: chat.accountId,
              chatId: chat.chatId,
              isChannel: true,
            ),
          ),
        _ActionRow(
          icon: Icons.people_outline,
          label: 'Similar Channels',
          theme: theme,
          onTap: () => _showSimilarChannels(context),
        ),
        _ActionRow(
          icon: Icons.flag_outlined,
          label: 'Report',
          theme: theme,
          onTap: () => _confirmReport(context, chatState),
        ),
        _ActionRow(
          icon: Icons.logout,
          label: 'Leave Channel',
          theme: theme,
          color: attentionColor,
          onTap: () => _confirmLeave(context, chatState),
        ),
      ],
    );
  }

  void _showSimilarChannels(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => _SimilarChannelsSheet(
        accountId: chat.accountId,
        chatId: chat.chatId,
        theme: theme,
      ),
    );
  }

  void _confirmReport(BuildContext context, ChatState chatState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report Channel'),
        content: Text('Report ${chat.title} as spam?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDD4B39)),
            onPressed: () {
              chatState.reportSpam(chat.accountId, chat.chatId);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Channel reported'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext context, ChatState chatState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Channel'),
        content: Text('Leave ${chat.title}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDD4B39)),
            onPressed: () {
              chatState.leaveChat(chat.accountId, chat.chatId);
              Navigator.pop(ctx);
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}

class _DmActionsSection extends StatelessWidget {
  final ChatInfo chat;
  final ThemeData theme;

  const _DmActionsSection({required this.chat, required this.theme});

  @override
  Widget build(BuildContext context) {
    final chatState = context.read<ChatState>();
    final isContact = chat.isContact;
    final isBlocked = chat.isBlocked;
    final attentionColor = const Color(0xFFDD4B39);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isContact) ...[
          _ActionRow(
            icon: Icons.share,
            label: 'Share Contact',
            theme: theme,
            onTap: () => _shareContact(context, chatState),
          ),
          _ActionRow(
            icon: Icons.edit,
            label: 'Edit Contact',
            theme: theme,
            onTap: () => _editContact(context, chatState),
          ),
          _ActionRow(
            icon: Icons.delete_outline,
            label: 'Delete Contact',
            theme: theme,
            color: attentionColor,
            onTap: () => _confirmDeleteContact(context, chatState),
          ),
        ] else ...[
          _ActionRow(
            icon: Icons.person_add,
            label: 'Add Contact',
            theme: theme,
            onTap: () => _addContact(context, chatState),
          ),
        ],
        _ActionRow(
          icon: isBlocked ? Icons.lock_open : Icons.block,
          label: isBlocked ? 'Unblock User' : 'Block User',
          theme: theme,
          color: isBlocked ? null : attentionColor,
          onTap: () => _toggleBlock(context, chatState),
        ),
      ],
    );
  }

  void _shareContact(BuildContext context, ChatState chatState) {
    final engine = context.read<EngineService>();
    engine.getUserProfile(chat.accountId, chat.chatId).then((profile) {
      if (profile == null || !context.mounted) return;
      final text = [
        if (profile.phone.isNotEmpty) '+${profile.phone}',
        if (profile.username.isNotEmpty) '@${profile.username}',
      ].join('\n');
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No contact info to share')),
        );
        return;
      }
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact info copied to clipboard'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void _editContact(BuildContext context, ChatState chatState) {
    final engine = context.read<EngineService>();
    engine.getUserProfile(chat.accountId, chat.chatId).then((profile) {
      if (profile == null || !context.mounted) return;
      final nameParts = profile.displayName.split(' ');
      final firstCtrl = TextEditingController(text: nameParts.first);
      final lastCtrl = TextEditingController(
        text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
      );
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'First name'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'Last name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final first = firstCtrl.text.trim();
                if (first.isEmpty) return;
                chatState.addContact(
                  chat.accountId,
                  profile.phone,
                  first,
                  lastCtrl.text.trim(),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    });
  }

  void _confirmDeleteContact(BuildContext context, ChatState chatState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Remove ${chat.title} from your contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDD4B39)),
            onPressed: () {
              chatState.deleteContact(chat.accountId, chat.chatId);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addContact(BuildContext context, ChatState chatState) {
    final engine = context.read<EngineService>();
    engine.getUserProfile(chat.accountId, chat.chatId).then((profile) {
      if (!context.mounted) return;
      final pName = profile?.displayName ?? chat.title;
      final pParts = pName.split(' ');
      final firstCtrl = TextEditingController(text: pParts.first);
      final lastCtrl = TextEditingController(
        text: pParts.length > 1 ? pParts.sublist(1).join(' ') : '',
      );
      final phoneCtrl = TextEditingController(
        text: profile?.phone ?? '',
      );
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'First name'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'Last name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone number'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final first = firstCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                if (first.isEmpty || phone.isEmpty) return;
                chatState.addContact(
                  chat.accountId, phone, first, lastCtrl.text.trim(),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
    });
  }

  void _toggleBlock(BuildContext context, ChatState chatState) {
    if (chat.isBlocked) {
      chatState.unblockUser(chat.accountId, chat.chatId);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block User'),
        content: Text('Block ${chat.title}? They will not be able to contact you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDD4B39)),
            onPressed: () {
              chatState.blockUser(chat.accountId, chat.chatId);
              Navigator.pop(ctx);
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;
  final Color? color;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.theme,
    this.color,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? theme.textTheme.bodyMedium?.color;
    final iconColor = color ?? theme.iconTheme.color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 21, top: 11, right: 20, bottom: 9),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _SharedMediaSection extends StatefulWidget {
  final Map<String, int> counts;
  final ThemeData theme;
  final bool isLayer;
  final String accountId;
  final String chatId;

  const _SharedMediaSection({
    required this.counts,
    required this.theme,
    this.isLayer = false,
    required this.accountId,
    required this.chatId,
  });

  @override
  State<_SharedMediaSection> createState() => _SharedMediaSectionState();
}

class _SharedMediaSectionState extends State<_SharedMediaSection> {
  bool _searchActive = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _activeSubTab = '';
  String? _expandedGridType;
  List<SharedMediaItem>? _gridItems;
  bool _gridLoading = false;

  static const _types = [
    ('photo', Icons.photo_outlined, 'Photos'),
    ('video', Icons.videocam_outlined, 'Videos'),
    ('stories', Icons.auto_stories_outlined, 'Stories'),
    ('gifts', Icons.card_giftcard_outlined, 'Gifts'),
    ('file', Icons.insert_drive_file_outlined, 'Files'),
    ('audio', Icons.music_note_outlined, 'Music'),
    ('link', Icons.link, 'Links'),
    ('voice', Icons.mic_outlined, 'Voice'),
    ('gif', Icons.gif_box_outlined, 'GIFs'),
  ];

  static const _gridTypes = {'photo', 'video', 'stories', 'gifts'};
  static const _masonryTypes = {'gif'};
  static const _listTypes = {'file', 'audio', 'link', 'voice'};
  static const _expandableTypes = {'photo', 'video', 'stories', 'gifts', 'gif', 'file', 'audio', 'link', 'voice'};

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

  void _toggleGrid(String type) {
    if (_expandedGridType == type) {
      setState(() {
        _expandedGridType = null;
        _gridItems = null;
      });
      return;
    }
    setState(() {
      _expandedGridType = type;
      _gridItems = null;
      _gridLoading = true;
    });
    _loadGridItems(type);
  }

  static const _typeToFilter = {
    'photo': 'image',
    'video': 'video',
    'stories': 'stories',
    'gifts': 'gifts',
    'file': 'file',
    'audio': 'audio',
    'voice': 'voice',
    'gif': 'gif',
    'link': 'link',
  };

  void _loadGridItems(String type) {
    final engine = context.read<EngineService>();
    try {
      final items = engine.getSharedMedia(
        widget.accountId, widget.chatId,
        mediaType: _typeToFilter[type] ?? type, limit: 100,
      );
      if (mounted && _expandedGridType == type) {
        setState(() {
          _gridItems = items;
          _gridLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _gridLoading = false);
    }
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
          for (final (type, icon, label) in visible) ...[
            _SharedMediaRow(
              icon: icon,
              label: label,
              count: widget.counts[type]!,
              iconColor: iconColor,
              accentColor: accentColor,
              theme: widget.theme,
              expanded: _expandedGridType == type,
              onTap: _expandableTypes.contains(type)
                  ? () => _toggleGrid(type)
                  : null,
            ),
            if (_expandedGridType == type)
              if (_gridTypes.contains(type))
                _MediaGrid(
                  items: _gridItems,
                  loading: _gridLoading,
                  theme: widget.theme,
                  mediaType: type,
                )
              else if (_masonryTypes.contains(type))
                _GifMasonryGrid(
                  items: _gridItems,
                  loading: _gridLoading,
                  theme: widget.theme,
                )
              else
                _MediaListView(
                  items: _gridItems,
                  loading: _gridLoading,
                  theme: widget.theme,
                  mediaType: type,
                ),
          ],
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
  final bool expanded;
  final VoidCallback? onTap;

  const _SharedMediaRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.iconColor,
    required this.accentColor,
    required this.theme,
    this.expanded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? () {},
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
            AnimatedRotation(
              turns: expanded ? 0.25 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.chevron_right, size: 18, color: iconColor),
            ),
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

class _MediaEmptyState extends StatelessWidget {
  final String mediaType;
  final ThemeData theme;
  final bool isSearch;

  const _MediaEmptyState({
    required this.mediaType,
    required this.theme,
    this.isSearch = false,
  });

  static const _iconTop = 120.0;
  static const _labelTop = 40.0;
  static const _labelSkip = 20.0;
  static const _minLabelWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final emptyFg = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final icon = _iconForType(mediaType);
    final text = isSearch ? _searchEmptyText(mediaType) : _emptyText(mediaType);

    return SizedBox(
      height: _iconTop + _labelTop + 60,
      child: Column(
        children: [
          const Spacer(flex: 1),
          Icon(icon, size: 48, color: emptyFg.withAlpha(128)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _labelSkip),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: _minLabelWidth),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: emptyFg),
              ),
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  static IconData _iconForType(String type) => switch (type) {
    'photo' => Icons.photo_outlined,
    'video' => Icons.videocam_outlined,
    'gif' => Icons.photo_outlined,
    'audio' => Icons.music_note_outlined,
    'file' => Icons.insert_drive_file_outlined,
    'voice' => Icons.mic_outlined,
    'link' => Icons.link_outlined,
    'stories' => Icons.auto_stories_outlined,
    'gifts' => Icons.card_giftcard_outlined,
    _ => Icons.photo_outlined,
  };

  static String _emptyText(String type) => switch (type) {
    'photo' => 'No photos here yet',
    'video' => 'No videos here yet',
    'gif' => 'No GIFs here yet',
    'audio' => 'No music files here yet',
    'file' => 'No files here yet',
    'voice' => 'No voice messages here yet',
    'link' => 'No shared links here yet',
    'stories' => 'No stories here yet',
    'gifts' => 'No gifts here yet',
    _ => 'No media here yet',
  };

  static String _searchEmptyText(String type) => switch (type) {
    'audio' => 'No music files found',
    'file' => 'No files found',
    'link' => 'No shared links found',
    'gifts' => 'No matching gifts',
    _ => _emptyText(type),
  };
}

class _MediaGrid extends StatelessWidget {
  final List<SharedMediaItem>? items;
  final bool loading;
  final ThemeData theme;
  final String mediaType;

  static const _minGridSize = 82.0;
  static const _skip = 2.0;
  static const _sidePadding = 3.0;
  static const _storyRatio = 16.0 / 9.0;
  static const _giftRatio = 1.4;

  const _MediaGrid({
    required this.items,
    required this.loading,
    required this.theme,
    this.mediaType = 'photo',
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }
    final mediaItems = items;
    if (mediaItems == null || mediaItems.isEmpty) {
      return _MediaEmptyState(mediaType: mediaType, theme: theme);
    }

    final grouped = _groupByMonth(mediaItems);

    return LayoutBuilder(builder: (context, constraints) {
      final listWidth = constraints.maxWidth;
      final contentWidth = listWidth - 2 * _sidePadding;
      final columns = math.max(1, ((contentWidth + _skip) / (_minGridSize + _skip)).floor());
      final cellSide = ((contentWidth - (columns - 1) * _skip) / columns).floorToDouble();
      final cellHeight = switch (mediaType) {
        'stories' => (cellSide * _storyRatio).floorToDouble(),
        'gifts' => (cellSide * _giftRatio).floorToDouble(),
        _ => cellSide,
      };

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in grouped.entries) ...[
              _DateHeader(label: entry.key, theme: theme),
              _buildGridRows(entry.value, columns, cellSide, cellHeight),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildGridRows(List<SharedMediaItem> items, int columns, double cellSide, double cellHeight) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += columns) {
      final rowItems = items.sublist(i, math.min(i + columns, items.length));
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: i + columns < items.length ? _skip : 0),
        child: Row(
          children: [
            for (var j = 0; j < rowItems.length; j++) ...[
              if (j > 0) const SizedBox(width: _skip),
              _GridCell(item: rowItems[j], size: cellSide, height: cellHeight, theme: theme),
            ],
          ],
        ),
      ));
    }
    return Column(children: rows);
  }

  static Map<String, List<SharedMediaItem>> _groupByMonth(List<SharedMediaItem> items) {
    final grouped = <String, List<SharedMediaItem>>{};
    for (final item in items) {
      final dt = item.dateTime;
      final now = DateTime.now();
      String key;
      if (dt.year == now.year && dt.month == now.month) {
        key = 'This month';
      } else if (dt.year == now.year) {
        key = _monthName(dt.month);
      } else {
        key = '${_monthName(dt.month)} ${dt.year}';
      }
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }

  static String _monthName(int month) => const [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ][month];
}

class _GifMasonryGrid extends StatelessWidget {
  final List<SharedMediaItem>? items;
  final bool loading;
  final ThemeData theme;

  static const _skip = 2.0;
  static const _sidePadding = 3.0;
  static const _rowTargetHeight = 100.0;

  const _GifMasonryGrid({
    required this.items,
    required this.loading,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }
    final mediaItems = items;
    if (mediaItems == null || mediaItems.isEmpty) {
      return _MediaEmptyState(mediaType: 'gif', theme: theme);
    }

    final grouped = _MediaGrid._groupByMonth(mediaItems);

    return LayoutBuilder(builder: (context, constraints) {
      final availWidth = constraints.maxWidth - 2 * _sidePadding;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in grouped.entries) ...[
              _DateHeader(label: entry.key, theme: theme),
              _buildMasonryRows(entry.value, availWidth),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildMasonryRows(List<SharedMediaItem> items, double availWidth) {
    final rows = <Widget>[];
    var i = 0;
    while (i < items.length) {
      double totalAR = 0;
      int count = 0;
      while (i + count < items.length) {
        final item = items[i + count];
        final ar = (item.width > 0 && item.height > 0)
            ? item.width / item.height
            : 1.0;
        final newAR = totalAR + ar;
        final rowHeight = (availWidth - count * _skip) / newAR;
        count++;
        totalAR = newAR;
        if (rowHeight <= _rowTargetHeight && count > 1) break;
      }
      final rowItems = items.sublist(i, i + count);
      final rowHeight = math.min(
        _rowTargetHeight,
        (availWidth - (count - 1) * _skip) / totalAR,
      );
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: i + count < items.length ? _skip : 0),
        child: SizedBox(
          height: rowHeight,
          child: Row(
            children: [
              for (var j = 0; j < rowItems.length; j++) ...[
                if (j > 0) const SizedBox(width: _skip),
                _buildGifCell(rowItems[j], rowHeight),
              ],
            ],
          ),
        ),
      ));
      i += count;
    }
    return Column(children: rows);
  }

  Widget _buildGifCell(SharedMediaItem item, double rowHeight) {
    final ar = (item.width > 0 && item.height > 0)
        ? item.width / item.height
        : 1.0;
    final cellWidth = rowHeight * ar;
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? const Color(0xFF2b3945)
        : const Color(0xFFe0e0e0);

    Widget content;
    if (item.thumbB64.isNotEmpty) {
      try {
        final bytes = _GridCell._decodeThumb(item.thumbB64);
        if (_GridCell._isValidImage(bytes)) {
          content = Image.memory(
            bytes,
            width: cellWidth,
            height: rowHeight,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Container(color: placeholderColor),
          );
        } else {
          content = Container(color: placeholderColor);
        }
      } catch (_) {
        content = Container(color: placeholderColor);
      }
    } else {
      content = Container(
        color: placeholderColor,
        child: Center(child: Icon(Icons.gif, size: 24, color: placeholderColor.withValues(alpha: 0.6))),
      );
    }

    return SizedBox(
      width: cellWidth,
      height: rowHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(child: content),
          Positioned(
            left: 4, bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaListView extends StatelessWidget {
  final List<SharedMediaItem>? items;
  final bool loading;
  final ThemeData theme;
  final String mediaType;

  const _MediaListView({
    required this.items,
    required this.loading,
    required this.theme,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }
    final mediaItems = items;
    if (mediaItems == null || mediaItems.isEmpty) {
      return _MediaEmptyState(mediaType: mediaType, theme: theme);
    }

    final grouped = _MediaGrid._groupByMonth(mediaItems);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in grouped.entries) ...[
            _DateHeader(label: entry.key, theme: theme),
            for (final item in entry.value)
              _buildListItem(item),
          ],
        ],
      ),
    );
  }

  Widget _buildListItem(SharedMediaItem item) {
    switch (mediaType) {
      case 'file': return _FileListItem(item: item, theme: theme);
      case 'audio': return _AudioListItem(item: item, theme: theme);
      case 'voice': return _VoiceListItem(item: item, theme: theme);
      case 'link': return _LinkListItem(item: item, theme: theme);
      default: return _FileListItem(item: item, theme: theme);
    }
  }
}

class _FileListItem extends StatelessWidget {
  final SharedMediaItem item;
  final ThemeData theme;

  const _FileListItem({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final subtitleColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final ext = _extractExtension(item.fileName);
    final extColor = _extensionColor(ext);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: extColor.withValues(alpha: isDark ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                ext.isNotEmpty ? ext.toUpperCase() : '?',
                style: TextStyle(
                  fontSize: ext.length > 3 ? 9 : 11,
                  fontWeight: FontWeight.w700,
                  color: extColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName.isNotEmpty ? item.fileName : 'Unknown file',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  item.fileSizeLabel,
                  style: TextStyle(fontSize: 12, color: subtitleColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _extractExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static Color _extensionColor(String ext) {
    switch (ext) {
      case 'pdf': return const Color(0xFFe74c3c);
      case 'doc': case 'docx': return const Color(0xFF3498db);
      case 'xls': case 'xlsx': return const Color(0xFF27ae60);
      case 'ppt': case 'pptx': return const Color(0xFFe67e22);
      case 'zip': case 'rar': case '7z': case 'tar': case 'gz':
        return const Color(0xFF9b59b6);
      case 'apk': return const Color(0xFF2ecc71);
      case 'txt': case 'log': return const Color(0xFF95a5a6);
      default: return const Color(0xFF40a7e3);
    }
  }
}

class _AudioListItem extends StatelessWidget {
  final SharedMediaItem item;
  final ThemeData theme;

  const _AudioListItem({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF6AB2F2) : const Color(0xFF40a7e3);
    final subtitleColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    String title = item.fileName;
    String artist = '';
    if (title.isEmpty) title = 'Unknown track';
    final dashIdx = title.indexOf(' - ');
    if (dashIdx > 0) {
      artist = title.substring(0, dashIdx).trim();
      title = title.substring(dashIdx + 3).trim();
    }
    final dotIdx = title.lastIndexOf('.');
    if (dotIdx > 0) title = title.substring(0, dotIdx);

    final durationStr = _formatDuration(item.duration);
    final sizeStr = item.fileSizeLabel;
    final statusParts = <String>[if (durationStr.isNotEmpty) durationStr, if (sizeStr.isNotEmpty) sizeStr];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.play_arrow, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                if (artist.isNotEmpty || statusParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [if (artist.isNotEmpty) artist, ...statusParts].join(' \u00b7 '),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: subtitleColor),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _VoiceListItem extends StatelessWidget {
  final SharedMediaItem item;
  final ThemeData theme;

  const _VoiceListItem({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF6AB2F2) : const Color(0xFF40a7e3);
    final subtitleColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final waveColor = isDark ? const Color(0xFFd4dee6) : const Color(0xFFa0c4e0);

    final durationStr = _formatDuration(item.duration);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.play_arrow, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 20,
                  child: CustomPaint(
                    size: const Size(double.infinity, 20),
                    painter: _MiniWaveformPainter(color: waveColor),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  durationStr.isNotEmpty ? durationStr : '0:00',
                  style: TextStyle(fontSize: 12, color: subtitleColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _MiniWaveformPainter extends CustomPainter {
  final Color color;
  _MiniWaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    final barCount = (size.width / 3).floor();
    final rng = 42;
    for (var i = 0; i < barCount; i++) {
      final x = i * 3.0 + 1;
      final h = 3.0 + (((i * rng + 17) % 13) / 12.0) * (size.height - 6);
      final top = (size.height - h) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LinkListItem extends StatelessWidget {
  final SharedMediaItem item;
  final ThemeData theme;

  const _LinkListItem({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF6AB2F2) : const Color(0xFF40a7e3);
    final subtitleColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    final url = item.fileName.isNotEmpty ? item.fileName : 'Link';
    String domain = url;
    final schemeEnd = url.indexOf('://');
    if (schemeEnd > 0) domain = url.substring(schemeEnd + 3);
    final slashIdx = domain.indexOf('/');
    if (slashIdx > 0) domain = domain.substring(0, slashIdx);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: isDark ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(Icons.link, size: 22, color: accentColor),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  domain,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  url,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: subtitleColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _DateHeader({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, top: 6),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  final SharedMediaItem item;
  final double size;
  final double height;
  final ThemeData theme;

  const _GridCell({
    required this.item,
    required this.size,
    double? height,
    required this.theme,
  }) : height = height ?? size;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? const Color(0xFF2b3945)
        : const Color(0xFFe0e0e0);

    Widget content;
    if (item.thumbB64.isNotEmpty) {
      try {
        final bytes = _decodeThumb(item.thumbB64);
        if (_isValidImage(bytes)) {
          content = Image.memory(
            bytes,
            width: size,
            height: height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(placeholderColor),
          );
        } else {
          content = _placeholder(placeholderColor);
        }
      } catch (_) {
        content = _placeholder(placeholderColor);
      }
    } else if (item.localPath.isNotEmpty && File(item.localPath).existsSync()) {
      content = Image.file(
        File(item.localPath),
        width: size,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(placeholderColor),
      );
    } else {
      content = _placeholder(placeholderColor);
    }

    final isVideo = item.isVideo;
    return SizedBox(
      width: size,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(child: content),
          if (isVideo && item.duration > 0)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _formatDuration(item.duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(Color color) {
    final isVideo = item.isVideo;
    return Container(
      color: color,
      child: Center(
        child: Icon(
          isVideo ? Icons.videocam : Icons.photo,
          size: 24,
          color: color.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static bool _isValidImage(Uint8List data) {
    if (data.length < 4) return false;
    if (data[0] == 0xFF && data[1] == 0xD8) return true; // JPEG
    if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) return true; // PNG
    if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46) return true; // WebP (RIFF)
    return false;
  }

  static Uint8List _decodeThumb(String b64) {
    final data = base64Decode(b64);
    if (data.length >= 3 && data[0] == 0x01) {
      final w = data[1];
      final h = data[2];
      final header = _jpegHeader(w, h);
      const footer = [0xFF, 0xD9];
      final buf = Uint8List(header.length + data.length - 3 + footer.length);
      buf.setAll(0, header);
      buf.setAll(header.length, data.sublist(3));
      buf.setAll(header.length + data.length - 3, footer);
      return buf;
    }
    return data;
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
}

class _MembersHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _MembersHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Icon(icon, size: 20, color: color),
            ),
          ),
        ),
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
  final String accountId;
  final String chatId;

  const _MembersSection({
    required this.members,
    required this.loading,
    required this.memberCount,
    required this.theme,
    required this.accountId,
    required this.chatId,
    this.onMemberTap,
  });

  List<MemberInfo> _sortedMembers() {
    final list = List<MemberInfo>.from(members!);
    list.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
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
                _MembersHeaderButton(
                  icon: Icons.search,
                  tooltip: 'Search members',
                  color: theme.textTheme.bodyMedium?.color ?? theme.iconTheme.color!,
                  onTap: () {},
                ),
                _MembersHeaderButton(
                  icon: Icons.person_add_outlined,
                  tooltip: 'Add member',
                  color: theme.textTheme.bodyMedium?.color ?? theme.iconTheme.color!,
                  onTap: () {},
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
          ..._sortedMembers().map((m) => _MemberRow(
            member: m,
            theme: theme,
            onTap: onMemberTap != null ? () => onMemberTap!(m) : null,
            accountId: accountId,
            chatId: chatId,
          ))
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
  final String accountId;
  final String chatId;

  const _MemberRow({
    required this.member,
    required this.theme,
    required this.accountId,
    required this.chatId,
    this.onTap,
  });

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

    final String? tagText = hasAdminTag
        ? (member.role == 'owner' || member.role == 'creator' ? 'owner' : 'admin')
        : null;

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
                  child: member.hasStories
                      ? CustomPaint(
                          painter: _MemberStoryRingPainter(
                            storyCount: member.storyCount,
                            hasUnread: member.hasUnreadStory,
                            isDark: theme.brightness == Brightness.dark,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        )
                      : Container(
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
                    Text(
                      statusText,
                      style: TextStyle(fontSize: 13, color: statusColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            if (tagText != null)
              Padding(
                padding: const EdgeInsets.only(right: 18),
                child: Transform.translate(
                  offset: const Offset(0, -1),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tagText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      child: InkWell(
        onTap: onTap,
        child: row,
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final engine = context.read<EngineService>();
    final isDark = theme.brightness == Brightness.dark;
    final isOwnerOrCreator = member.role == 'owner' || member.role == 'creator';
    final isAdmin = member.role == 'admin';
    final attentionColor = isDark ? const Color(0xFFe85050) : const Color(0xFFdd4b39);
    final iconColor = isDark ? const Color(0xFF8b9fad) : const Color(0xFF999999);

    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        const TelegramMenuItem(value: 'view_profile', icon: Icon(Icons.person_outline), label: 'View Profile'),
        const TelegramMenuItem(value: 'send_message', icon: Icon(Icons.chat_bubble_outline), label: 'Send Message'),
        if (member.username.isNotEmpty)
          const TelegramMenuItem(value: 'copy_username', icon: Icon(Icons.alternate_email), label: 'Copy Username'),
        const TelegramMenuItem(value: 'copy_id', icon: Icon(Icons.tag), label: 'Copy ID'),
        if (!isAdmin && !isOwnerOrCreator)
          const TelegramMenuItem(value: 'promote', icon: Icon(Icons.arrow_upward), label: 'Promote'),
        if (isAdmin && !isOwnerOrCreator)
          const TelegramMenuItem(value: 'demote', icon: Icon(Icons.arrow_downward), label: 'Demote'),
        if (!isOwnerOrCreator) ...[
          const TelegramMenuItem(value: 'restrict', icon: Icon(Icons.voice_over_off), label: 'Restrict'),
          const TelegramMenuItem(value: 'remove', icon: Icon(Icons.person_remove_outlined), label: 'Remove', isAttention: true),
          const TelegramMenuItem(value: 'ban', icon: Icon(Icons.block), label: 'Ban', isAttention: true),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'view_profile':
          onTap?.call();
        case 'send_message':
          final chatState = context.read<ChatState>();
          chatState.openChat(ChatInfo(
            accountId: accountId,
            chatId: member.userId,
            title: member.displayName.isNotEmpty ? member.displayName : member.username,
            type: ChatType.dm,
          ));
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        case 'copy_username':
          Clipboard.setData(ClipboardData(text: '@${member.username}'));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Username copied'), duration: Duration(seconds: 2)),
          );
        case 'copy_id':
          Clipboard.setData(ClipboardData(text: member.userId));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ID copied'), duration: Duration(seconds: 2)),
          );
        case 'promote':
          showEditAdminBox(
            context,
            accountId: accountId,
            chatId: chatId,
            member: member,
            isChannel: chatId.startsWith('-100'),
          );
        case 'demote':
          engine.demoteAdmin(accountId, chatId, member.userId).catchError((e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to demote: $e')),
              );
            }
          });
        case 'restrict':
          showEditRestrictedBox(
            context,
            accountId: accountId,
            chatId: chatId,
            member: member,
          );
        case 'remove':
          engine.removeMember(accountId, chatId, member.userId).catchError((e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to remove: $e')),
              );
            }
          });
        case 'ban':
          engine.banMember(accountId, chatId, member.userId).catchError((e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to ban: $e')),
              );
            }
          });
      }
    });
  }
}

class _SimilarChannelsSheet extends StatefulWidget {
  final String accountId;
  final String chatId;
  final ThemeData theme;

  const _SimilarChannelsSheet({
    required this.accountId,
    required this.chatId,
    required this.theme,
  });

  @override
  State<_SimilarChannelsSheet> createState() => _SimilarChannelsSheetState();
}

class _SimilarChannelsSheetState extends State<_SimilarChannelsSheet> {
  List<SimilarChannelInfo>? _channels;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine = context.read<EngineService>();
    try {
      final result = await engine.getSimilarChannels(widget.accountId, widget.chatId);
      if (mounted) setState(() { _channels = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: t.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text(
              'Similar Channels',
              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(scrollController, t)),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController sc, ThemeData t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: t.colorScheme.error)));
    }
    final channels = _channels;
    if (channels == null || channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No similar channels found',
            style: t.textTheme.bodyMedium?.copyWith(color: t.hintColor),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: sc,
      itemCount: channels.length,
      itemBuilder: (ctx, i) {
        final ch = channels[i];
        return _SimilarChannelRow(channel: ch, theme: t, onTap: () {
          Navigator.pop(context);
          final chatState = context.read<ChatState>();
          chatState.openChatById(ch.chatId);
        });
      },
    );
  }
}

class _SimilarChannelRow extends StatelessWidget {
  final SimilarChannelInfo channel;
  final ThemeData theme;
  final VoidCallback onTap;

  const _SimilarChannelRow({
    required this.channel,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _buildAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.title,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (channel.memberCount > 0)
                    Text(
                      '${_formatCount(channel.memberCount)} subscribers',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    if (channel.avatarB64.isNotEmpty) {
      try {
        final bytes = base64Decode(channel.avatarB64);
        return CircleAvatar(
          radius: 23,
          backgroundImage: MemoryImage(Uint8List.fromList(bytes)),
        );
      } catch (_) {}
    }
    return CircleAvatar(
      radius: 23,
      backgroundColor: const Color(0xFF40A7E3),
      child: Text(
        channel.title.isNotEmpty ? channel.title[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
