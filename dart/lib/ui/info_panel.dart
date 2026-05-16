import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/audio_service.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import 'chat_export.dart';
import 'chat_list_row.dart' show MyNotesUserpic, SavedMessagesUserpic;
import 'chat_view.dart' show formatChatLastSeen;
import 'confirm_box.dart';
import 'admin_tools.dart' show showEditAdminBox, showEditPeerInfoBox, showEditRestrictedBox;
import 'create_group_wizard.dart' show showEditPeerTypeBox;
import 'edit_forum_topic_box.dart';
import 'forum_topic_icon.dart';
import 'contacts_screen.dart' show showShareContactBox;
import 'popup_menu.dart';
import 'stats_chart.dart';
import 'telegram_tooltip.dart';
import 'telegram_toast.dart';
import 'emoji_status_widget.dart';
import 'peer_short_info.dart';

enum InfoWrapMode { side, narrow, layer }

enum _InfoPageType { chatInfo, userProfile, statistics, messageStats, sharedMedia, boosts }

const _userpicColorRemap = [0, 7, 4, 1, 6, 3, 5];

String _userpicInitials(String title) {
  final t = title.trim();
  if (t.isEmpty) return '?';
  final words = t.split(RegExp(r'\s+'));
  if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
  return t[0].toUpperCase();
}

String _groupStatusText(ChatInfo chat) {
  if (chat.type == ChatType.channel) {
    final c = chat.memberCount;
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M subscribers';
    if (c >= 1000) return '${(c / 1000).toStringAsFixed(1)}K subscribers';
    return '$c subscribers';
  }
  if ((chat.type == ChatType.group || chat.type == ChatType.topic) && chat.memberCount > 0) {
    final c = chat.memberCount;
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M members';
    if (c >= 1000) return '${(c / 1000).toStringAsFixed(1)}K members';
    return '$c members';
  }
  return '';
}

class _InfoNavPage {
  final _InfoPageType type;
  final MemberInfo? member;
  final Map<String, dynamic>? messagePostData;
  final String? mediaType;
  final String? mediaLabel;
  double scrollOffset = 0.0;
  String searchQuery = '';
  String activeMediaTab = '';

  _InfoNavPage({required this.type, this.member, this.messagePostData, this.mediaType, this.mediaLabel});

  String get title => switch (type) {
    _InfoPageType.chatInfo => '',
    _InfoPageType.userProfile => member?.label ?? 'User Info',
    _InfoPageType.statistics => 'Statistics',
    _InfoPageType.messageStats => 'Message Statistics',
    _InfoPageType.sharedMedia => mediaLabel ?? 'Media',
    _InfoPageType.boosts => 'Boosts',
  };
}

class InfoPanel extends StatefulWidget {
  final VoidCallback onClose;
  final InfoWrapMode wrapMode;

  static void Function(MemberInfo member)? pushUserProfileRequest;

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
    if (InfoPanel.pushUserProfileRequest == _pushUserProfile) {
      InfoPanel.pushUserProfileRequest = null;
    }
    _chatUpdatedSub?.cancel();
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _pushUserProfile(MemberInfo member) {
    _pushPage(_InfoNavPage(type: _InfoPageType.userProfile, member: member));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    InfoPanel.pushUserProfileRequest = _pushUserProfile;
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
      case _InfoPageType.statistics:
        return _StatisticsPage(
          chat: chat,
          theme: theme,
          scrollController: _getScrollController(),
          onClose: onClose,
          showBackButton: true,
          onOpenMessageStats: (postData) {
            _pushPage(_InfoNavPage(
              type: _InfoPageType.messageStats,
              messagePostData: postData,
            ));
          },
        );
      case _InfoPageType.messageStats:
        return _MessageStatsPage(
          chat: chat,
          theme: theme,
          scrollController: _getScrollController(),
          onClose: onClose,
          postData: _currentPage.messagePostData ?? {},
        );
      case _InfoPageType.sharedMedia:
        return _SharedMediaSubPage(
          chat: chat,
          theme: theme,
          scrollController: _getScrollController(),
          onClose: onClose,
          mediaType: page.mediaType ?? 'photo',
          title: page.title,
        );
      case _InfoPageType.boosts:
        return _BoostsPage(
          chat: chat,
          theme: theme,
          scrollController: _getScrollController(),
          onClose: onClose,
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
  final bool isOverflow;
  final List<_ActionBtnData> overflowItems;
  const _ActionBtnData(this.icon, this.label, this.onTap,
      {this.isMute = false, this.isMuted = false, this.isOverflow = false, this.overflowItems = const []});
}

class _MuteLottieIcon extends StatefulWidget {
  final bool isMuted;
  final double size;
  final Color color;

  const _MuteLottieIcon({
    required this.isMuted,
    required this.size,
    required this.color,
  });

  @override
  State<_MuteLottieIcon> createState() => _MuteLottieIconState();
}

class _MuteLottieIconState extends State<_MuteLottieIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  String? _activeAsset;
  bool? _prevMuted;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void didUpdateWidget(_MuteLottieIcon old) {
    super.didUpdateWidget(old);
    if (old.isMuted != widget.isMuted) {
      _activeAsset = widget.isMuted
          ? 'assets/animations/profile_muting.json'
          : 'assets/animations/profile_unmuting.json';
      _prevMuted = widget.isMuted;
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activeAsset != null) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
        child: Lottie.asset(
          _activeAsset!,
          controller: _ctrl,
          width: widget.size,
          height: widget.size,
        ),
      );
    }
    return Icon(
      widget.isMuted ? Icons.notifications_off : Icons.notifications,
      size: widget.size,
      color: widget.color,
    );
  }
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
  final bool isMyNotes;
  final int storyCount;
  final bool hasUnreadStory;
  final List<Color>? profileBgColors;
  final String emojiStatusId;
  final String accountId;
  final List<PinnedGiftItem> pinnedGifts;
  final bool showStatsMenu;
  final void Function(BuildContext context)? onStatsMenuTap;
  final String chatId;
  final VoidCallback? onMessageTap;
  final VoidCallback? onCallTap;
  final Uint8List? avatarBytes;
  final bool notJoined;
  final String linkedChatId;
  final bool isPeerPremium;
  final VoidCallback? onJoinTap;
  final VoidCallback? onDiscussTap;
  final VoidCallback? onGiftTap;

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
    this.isMyNotes = false,
    this.storyCount = 0,
    this.hasUnreadStory = false,
    this.profileBgColors,
    this.emojiStatusId = '',
    this.accountId = '',
    this.pinnedGifts = const [],
    this.showStatsMenu = false,
    this.onStatsMenuTap,
    this.chatId = '',
    this.onMessageTap,
    this.onCallTap,
    this.avatarBytes,
    this.notJoined = false,
    this.linkedChatId = '',
    this.isPeerPremium = false,
    this.onJoinTap,
    this.onDiscussTap,
    this.onGiftTap,
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
      pinnedGifts.length != old.pinnedGifts.length ||
      showStatsMenu != old.showStatsMenu ||
      notJoined != old.notJoined ||
      linkedChatId != old.linkedChatId ||
      isPeerPremium != old.isPeerPremium;

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
                            emojiStatusId: emojiStatusId,
                            accountId: accountId,
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
                        GestureDetector(
                          onTap: (isMyNotes || isSelf || (avatarPath.isEmpty && (avatarBytes == null || avatarBytes!.isEmpty)))
                              ? null
                              : () {
                                  _openAvatarPhotoViewer(context, avatarPath, displayName, avatarBytes: avatarBytes, accountId: accountId, userId: chatId);
                                },
                          onSecondaryTapUp: (isMyNotes || isSelf || (avatarPath.isEmpty && (avatarBytes == null || avatarBytes!.isEmpty)))
                              ? null
                              : (details) {
                                  _showAvatarContextMenu(context, details.globalPosition, avatarPath, displayName, avatarBytes: avatarBytes, accountId: accountId, userId: chatId);
                                },
                          child: SizedBox(
                            width: avatarDisplaySize,
                            height: avatarDisplaySize,
                            child: isMyNotes
                                ? MyNotesUserpic(size: avatarDisplaySize)
                                : isSelf
                                ? SavedMessagesUserpic(size: avatarDisplaySize)
                                : avatarPath.isNotEmpty
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
                                    : avatarBytes != null && avatarBytes!.isNotEmpty
                                        ? ClipOval(
                                            child: Image.memory(
                                              avatarBytes!,
                                              width: avatarDisplaySize,
                                              height: avatarDisplaySize,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _avatarFallback(avatarColor, initials, avatarDisplaySize),
                                            ),
                                          )
                                        : _avatarFallback(avatarColor, initials, avatarDisplaySize),
                          ),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
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
                    if (emojiStatusId.isNotEmpty && accountId.isNotEmpty &&
                        !context.read<AppState>().hidePremiumStatuses) ...[
                      const SizedBox(width: 4),
                      EmojiStatusWidget(
                        emojiStatusId: emojiStatusId,
                        accountId: accountId,
                        size: 22,
                        fallbackColor: gradientTextColor,
                      ),
                    ],
                  ],
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
                child: SizedBox(
                  height: _actionButtonSize * actionProgress,
                  child: ClipRect(
                    child: OverflowBox(
                      maxHeight: _actionButtonSize,
                      alignment: Alignment.topCenter,
                      child: Opacity(
                        opacity: actionProgress,
                        child: SizedBox(
                          height: _actionButtonSize,
                          child: _buildActionRow(context, actionProgress),
                        ),
                      ),
                    ),
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
                    if (showStatsMenu)
                      Builder(builder: (ctx) => IconButton(
                        icon: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: hasGradientBg && collapseProgress < 0.5
                              ? Colors.white
                              : null,
                        ),
                        onPressed: () => onStatsMenuTap?.call(ctx),
                        tooltip: 'Menu',
                      )),
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

    // "Join" for unjoined channels/groups
    if (notJoined && (chatType == ChatType.channel || chatType == ChatType.group)) {
      buttons.add(_ActionBtnData(Icons.add, 'Join', onJoinTap));
    }

    if (chatType == ChatType.dm && !isSelf) {
      buttons.add(_ActionBtnData(Icons.chat_bubble_outline, 'Message', onMessageTap));
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
      buttons.add(_ActionBtnData(Icons.call_outlined, 'Call', onCallTap));
    }

    // "Discuss" for channels with a linked discussion group
    if (chatType == ChatType.channel && linkedChatId.isNotEmpty) {
      buttons.add(_ActionBtnData(Icons.forum_outlined, 'Discuss', onDiscussTap));
    }

    // "Gift" for premium-eligible peers (non-self, non-bot DMs, or channels with stargifts)
    if (isPeerPremium && onGiftTap != null) {
      buttons.add(_ActionBtnData(Icons.card_giftcard_outlined, 'Gift', onGiftTap));
    }

    if (buttons.length > 4) {
      final overflow = buttons.sublist(3);
      buttons.removeRange(3, buttons.length);
      buttons.add(_ActionBtnData(Icons.more_horiz, 'More', null, isOverflow: true, overflowItems: overflow));
    }
    return buttons;
  }

  Offset _lastTapPosition = Offset.zero;

  void _showOverflowMenu(BuildContext context, List<_ActionBtnData> overflow) {
    showTelegramMenu<_ActionBtnData>(
      context: context,
      position: _lastTapPosition,
      items: overflow.map((b) => TelegramMenuItem(
        value: b,
        icon: Icon(b.icon),
        label: b.label,
      )).toList(),
    ).then((val) {
      if (val != null) val.onTap?.call();
    });
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
        ? _MuteLottieIcon(isMuted: data.isMuted, size: 23, color: fg)
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
          onTapDown: (details) { _lastTapPosition = details.globalPosition; },
          onTap: data.isOverflow
              ? () => _showOverflowMenu(context, data.overflowItems)
              : data.onTap,
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
        else ...[
          const TelegramMenuItem(value: 'sound_select', icon: Icon(Icons.music_note_outlined), label: 'Notification sound'),
          const TelegramMenuItem(value: 'sound_toggle', icon: Icon(Icons.volume_off_outlined), label: 'Sound off'),
          const TelegramMenuItem(value: 'mute_1h', icon: Icon(Icons.notifications_off_outlined), label: 'Mute for 1 hour'),
          const TelegramMenuItem(value: 'mute_4h', icon: Icon(Icons.notifications_off_outlined), label: 'Mute for 4 hours'),
          const TelegramMenuItem(value: 'mute_8h', icon: Icon(Icons.notifications_off_outlined), label: 'Mute for 8 hours'),
          const TelegramMenuItem(value: 'mute_18h', icon: Icon(Icons.notifications_off_outlined), label: 'Mute for 18 hours'),
          const TelegramMenuItem(value: 'mute_3d', icon: Icon(Icons.notifications_off_outlined), label: 'Mute for 3 days'),
          const TelegramMenuItem(value: 'mute_1w', icon: Icon(Icons.notifications_off_outlined), label: 'Mute for 1 week'),
          const TelegramMenuItem(value: 'mute_custom', icon: Icon(Icons.schedule_outlined), label: 'Mute for...'),
          const TelegramMenuItem(value: 'mute_forever', icon: Icon(Icons.notifications_off), label: 'Mute forever', isAttention: true),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'unmute') {
        data.onTap?.call();
        return;
      }
      if (value == 'sound_select') {
        _showSoundSelectDialog(context);
        return;
      }
      if (value == 'sound_toggle') {
        final engine = context.read<EngineService>();
        final peerType = switch (chatType) {
          ChatType.channel => 'channel',
          ChatType.group => 'group',
          _ => 'private',
        };
        engine.updateDefaultNotifySettings(accountId, peerType: peerType, enabled: true, soundEnabled: false);
        return;
      }
      if (value == 'mute_custom') {
        _showCustomMuteDurationPicker(context);
        return;
      }
      final chatState = context.read<ChatState>();
      final seconds = switch (value) {
        'mute_1h' => 3600,
        'mute_4h' => 4 * 3600,
        'mute_8h' => 8 * 3600,
        'mute_18h' => 18 * 3600,
        'mute_3d' => 3 * 24 * 3600,
        'mute_1w' => 7 * 24 * 3600,
        _ => 0,
      };
      if (seconds > 0) {
        chatState.muteChat(accountId, chatId, true, durationSeconds: seconds);
      } else {
        data.onTap?.call();
      }
    });
  }

  void _showSoundSelectDialog(BuildContext context) {
    final engine = context.read<EngineService>();
    showDialog<void>(
      context: context,
      builder: (ctx) => _RingtonePickerDialog(accountId: accountId, engine: engine),
    );
  }

  void _showCustomMuteDurationPicker(BuildContext context) {
    showDialog<int>(
      context: context,
      builder: (ctx) => _CustomMuteDurationDialog(),
    ).then((seconds) {
      if (seconds != null && seconds > 0) {
        final chatState = context.read<ChatState>();
        chatState.muteChat(accountId, chatId, true, durationSeconds: seconds);
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

void _openAvatarPhotoViewer(BuildContext context, String avatarPath, String title, {Uint8List? avatarBytes, String? accountId, String? userId}) {
  if (avatarPath.isEmpty && (avatarBytes == null || avatarBytes.isEmpty)) return;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, _) {
        return FadeTransition(
          opacity: animation,
          child: _AvatarPhotoViewer(
            imagePath: avatarPath,
            title: title,
            imageBytes: avatarBytes,
            accountId: accountId,
            userId: userId,
          ),
        );
      },
    ),
  );
}

void _showAvatarContextMenu(BuildContext context, Offset position, String avatarPath, String title, {Uint8List? avatarBytes, String? accountId, String? userId}) {
  showTelegramMenu<String>(
    context: context,
    position: position,
    items: [
      TelegramMenuItem(
        value: 'open_photo',
        icon: const Icon(Icons.photo_outlined, size: 20),
        label: 'Open Photo',
      ),
    ],
  ).then((value) {
    if (value == 'open_photo') {
      _openAvatarPhotoViewer(context, avatarPath, title, avatarBytes: avatarBytes, accountId: accountId, userId: userId);
    }
  });
}

class _AvatarPhotoViewer extends StatefulWidget {
  final String imagePath;
  final String title;
  final Uint8List? imageBytes;
  final String? accountId;
  final String? userId;

  const _AvatarPhotoViewer({
    required this.imagePath,
    required this.title,
    this.imageBytes,
    this.accountId,
    this.userId,
  });

  @override
  State<_AvatarPhotoViewer> createState() => _AvatarPhotoViewerState();
}

class _AvatarPhotoViewerState extends State<_AvatarPhotoViewer> {
  int _currentIndex = 0;
  int _totalPhotos = 1;
  String? _currentPath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.imagePath;
    _loadPhotoCount();
  }

  Future<void> _loadPhotoCount() async {
    if (widget.accountId == null || widget.userId == null) return;
    final engine = context.read<EngineService>();
    final count = await engine.getUserPhotoCount(widget.accountId!, widget.userId!);
    if (mounted && count > 0) {
      setState(() => _totalPhotos = count);
    }
  }

  Future<void> _navigateTo(int index) async {
    if (index < 0 || index >= _totalPhotos || _loading) return;
    if (widget.accountId == null || widget.userId == null) return;
    setState(() => _loading = true);
    final engine = context.read<EngineService>();
    final path = await engine.getUserPhotoAtIndex(widget.accountId!, widget.userId!, index);
    if (mounted) {
      setState(() {
        _currentIndex = index;
        if (path != null && path.isNotEmpty) _currentPath = path;
        _loading = false;
      });
    }
  }

  Widget _buildImage() {
    if (_currentPath != null && _currentPath!.isNotEmpty) {
      return Image.file(
        File(_currentPath!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64, color: Colors.white54),
      );
    }
    if (widget.imageBytes != null && widget.imageBytes!.isNotEmpty) {
      return Image.memory(
        widget.imageBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64, color: Colors.white54),
      );
    }
    return const Icon(Icons.broken_image, size: 64, color: Colors.white54);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Center(
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white54)
                  : InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: _buildImage(),
                    ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        _totalPhotos > 1
                            ? '${widget.title} (${_currentIndex + 1}/$_totalPhotos)'
                            : widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Navigation arrows
            if (_totalPhotos > 1) ...[
              if (_currentIndex > 0)
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left, size: 40, color: Colors.white70),
                      onPressed: () => _navigateTo(_currentIndex - 1),
                    ),
                  ),
                ),
              if (_currentIndex < _totalPhotos - 1)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right, size: 40, color: Colors.white70),
                      onPressed: () => _navigateTo(_currentIndex + 1),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RingtonePickerDialog extends StatefulWidget {
  final String accountId;
  final EngineService engine;

  const _RingtonePickerDialog({required this.accountId, required this.engine});

  @override
  State<_RingtonePickerDialog> createState() => _RingtonePickerDialogState();
}

class _RingtonePickerDialogState extends State<_RingtonePickerDialog> {
  List<Map<String, dynamic>> _ringtones = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tones = await widget.engine.getSavedRingtones(widget.accountId);
    if (mounted) setState(() { _ringtones = tones; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notification Sound'),
      content: SizedBox(
        width: 300,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _ringtones.isEmpty
                ? const Center(child: Text('No saved ringtones'))
                : ListView.builder(
                    itemCount: _ringtones.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return ListTile(
                          leading: const Icon(Icons.notifications_active),
                          title: const Text('Default'),
                          onTap: () => Navigator.pop(context),
                        );
                      }
                      final tone = _ringtones[i - 1];
                      final name = tone['name'] as String? ?? 'Ringtone';
                      return ListTile(
                        leading: const Icon(Icons.music_note),
                        title: Text(name),
                        onTap: () => Navigator.pop(context),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _CustomMuteDurationDialog extends StatefulWidget {
  @override
  State<_CustomMuteDurationDialog> createState() => _CustomMuteDurationDialogState();
}

class _CustomMuteDurationDialogState extends State<_CustomMuteDurationDialog> {
  int _days = 0;
  int _hours = 1;
  int _minutes = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mute for...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _spinner('Days', _days, 0, 30, (v) => setState(() => _days = v))),
              const SizedBox(width: 12),
              Expanded(child: _spinner('Hours', _hours, 0, 23, (v) => setState(() => _hours = v))),
              const SizedBox(width: 12),
              Expanded(child: _spinner('Min', _minutes, 0, 59, (v) => setState(() => _minutes = v))),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatDuration(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final total = _days * 86400 + _hours * 3600 + _minutes * 60;
            Navigator.pop(context, total > 0 ? total : null);
          },
          child: const Text('Mute'),
        ),
      ],
    );
  }

  String _formatDuration() {
    final parts = <String>[];
    if (_days > 0) parts.add('$_days day${_days > 1 ? 's' : ''}');
    if (_hours > 0) parts.add('$_hours hour${_hours > 1 ? 's' : ''}');
    if (_minutes > 0) parts.add('$_minutes min');
    return parts.isEmpty ? 'Select duration' : parts.join(', ');
  }

  Widget _spinner(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: value > min ? () => onChanged(value - 1) : null,
              child: const Icon(Icons.remove_circle_outline, size: 20),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            InkWell(
              onTap: value < max ? () => onChanged(value + 1) : null,
              child: const Icon(Icons.add_circle_outline, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}

class _StarGiftPickerDialog extends StatelessWidget {
  final List<StarGiftItem> gifts;

  const _StarGiftPickerDialog({required this.gifts});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send a Gift'),
      content: SizedBox(
        width: 340,
        height: 400,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.8,
          ),
          itemCount: gifts.length,
          itemBuilder: (ctx, i) {
            final gift = gifts[i];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: gift.soldOut ? null : () => Navigator.pop(context, gift.id),
              child: Opacity(
                opacity: gift.soldOut ? 0.4 : 1.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: gift.thumbB64.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                base64Decode(gift.thumbB64),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, size: 40),
                              ),
                            )
                          : const Icon(Icons.card_giftcard, size: 40),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '⭐ ${gift.stars}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    if (gift.limited)
                      Text(
                        gift.soldOut ? 'Sold out' : '${gift.remaining} left',
                        style: TextStyle(fontSize: 10, color: gift.soldOut ? Colors.red : Colors.grey),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
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

class _AnimatedEmojiPattern extends StatelessWidget {
  final double size;
  final bool isDark;
  final String emojiStatusId;
  final String accountId;

  const _AnimatedEmojiPattern({
    required this.size,
    required this.isDark,
    required this.emojiStatusId,
    required this.accountId,
  });

  @override
  Widget build(BuildContext context) {
    const paddingScale = 0.8;
    final cx = size / 2;
    final cy = size / 2;
    final aw = size * 0.6;
    final ah = size * 0.6;
    final ax = cx - aw / 2;
    final ay = cy - ah / 2;
    final p24 = 24.0 * paddingScale;
    final p16 = 16.0 * paddingScale;
    final p8 = 8.0 * paddingScale;
    final p48 = 48.0 * paddingScale;
    final p96 = 96.0 * paddingScale;
    final p12 = 12.0 * paddingScale;
    final cos120 = math.cos(120 * math.pi / 180);
    final cos160 = math.cos(160 * math.pi / 180);

    final points = <_PatternPoint>[
      _PatternPoint(cx, ay - p24, 20),
      _PatternPoint(cx, ay + ah + p24, 20),
      _PatternPoint(ax - p16, cy - ah / 4 - p8, 23),
      _PatternPoint(ax + aw + p16, cy - ah / 4 - p8, 18),
      _PatternPoint(ax - p16, cy + ah / 4 + p8, 24),
      _PatternPoint(ax + aw + p16 - 4, cy + ah / 4 + p8, 24),
      _PatternPoint(ax - p48, cy, 19),
      _PatternPoint(ax + aw + p48, cy, 19),
      _PatternPoint(cx + (aw / 2 + p48) * cos120, cy - (ah / 2 + p48) * 0.5, 17),
      _PatternPoint(cx + (aw / 2 + p48) * -cos120, cy - (ah / 2 + p48) * 0.5, 17),
      _PatternPoint(cx + (aw / 2 + p48) * cos160, cy + (ah / 2 + p48) * 0.3, 20),
      _PatternPoint(cx + (aw / 2 + p48) * -cos160, cy + (ah / 2 + p48) * 0.3, 20),
      _PatternPoint(ax - p96, cy - ah / 4 - p12, 20),
      _PatternPoint(ax + aw + p96, cy - ah / 4 + p12, 19),
      _PatternPoint(ax - p96 + p8, cy + ah / 4, 21),
      _PatternPoint(ax + aw + p96 - p8, cy + ah / 4, 18),
      _PatternPoint(ax - p96 - p24, cy, 19),
      _PatternPoint(ax + aw + p96 + p24, cy, 19),
    ];

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          for (final pt in points)
            Positioned(
              left: pt.x - pt.size * 0.25,
              top: pt.y - pt.size * 0.25,
              child: Opacity(
                opacity: _opacityForPoint(pt, cx, cy, size),
                child: EmojiStatusWidget(
                  emojiStatusId: emojiStatusId,
                  accountId: accountId,
                  size: pt.size * 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _opacityForPoint(_PatternPoint pt, double cx, double cy, double maxDist) {
    final dx = pt.x - cx;
    final dy = pt.y - cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final distAlpha = (1.0 - dist / maxDist).clamp(0.0, 1.0);
    return (0.5 * distAlpha * 0.5).clamp(0.05, 0.35);
  }
}

class _PatternPoint {
  final double x, y, size;
  const _PatternPoint(this.x, this.y, this.size);
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
        const TelegramMenuItem(
          value: 'export_topic',
          icon: Icon(Icons.file_upload_outlined, size: 20),
          label: 'Export Topic History',
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
      case 'export_topic':
        showExportPanel(
          context,
          ExportTarget(
            mode: ExportMode.perTopic,
            accountId: chat.accountId,
            chatId: parentChatId,
            chatTitle: chat.title,
            topicRootId: topicId,
            topicTitle: topic.title,
          ),
        );
      case 'copy_link':
        try {
          final username = await engine.getChatUsername(chat.accountId, parentChatId);
          if (username.isNotEmpty && context.mounted) {
            final link = 'https://t.me/$username/${topic.id}';
            Clipboard.setData(ClipboardData(text: link));
            showTelegramToast(context, 'Topic link copied');
          } else if (context.mounted) {
            showTelegramToast(context, 'This group has no public link');
          }
        } catch (_) {
          if (context.mounted) {
            showTelegramToast(context, 'Could not get topic link');
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
          isPremium: context.read<AppState>().activeAccount?.isPremium ?? false,
          accountId: chat.accountId,
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
            showTelegramToast(context, 'Failed to edit topic: $e');
          }
        }
      case 'toggle_closed':
        try {
          await chatState.toggleForumTopicClosed(
            chat.accountId, parentChatId, topicId, !topic.isClosed,
          );
        } catch (e) {
          if (context.mounted) {
            showTelegramToast(context, 'Failed: $e');
          }
        }
      case 'toggle_hidden':
        try {
          await chatState.toggleGeneralTopicHidden(
            chat.accountId, parentChatId, !topic.isHidden,
          );
        } catch (e) {
          if (context.mounted) {
            showTelegramToast(context, 'Failed: $e');
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
              showTelegramToast(context, 'Failed: $e');
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

class _TopicLinkRow extends StatelessWidget {
  final ChatInfo chat;
  final ForumTopic topic;
  final ThemeData theme;

  const _TopicLinkRow({
    required this.chat,
    required this.topic,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.link, color: theme.colorScheme.primary),
      title: const Text('Topic Link', style: TextStyle(fontSize: 14)),
      dense: true,
      onTap: () => _copyTopicLink(context),
    );
  }

  void _copyTopicLink(BuildContext context) async {
    final engine = context.read<EngineService>();
    final parentChatId = topic.parentId.isNotEmpty
        ? topic.parentId
        : chat.parentId;
    try {
      final username = await engine.getChatUsername(chat.accountId, parentChatId);
      if (username.isNotEmpty && context.mounted) {
        final link = 'https://t.me/$username/${topic.id}';
        Clipboard.setData(ClipboardData(text: link));
        showTelegramToast(context, 'Topic link copied');
      } else if (context.mounted) {
        showTelegramToast(context, 'This group has no public link');
      }
    } catch (_) {
      if (context.mounted) {
        showTelegramToast(context, 'Could not get topic link');
      }
    }
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

  bool _canShowStatsMenu() {
    final type = widget.chat.type;
    if (type != ChatType.channel && type != ChatType.group) return false;
    final minMembers = type == ChatType.channel ? 50 : 500;
    return widget.chat.memberCount >= minMembers;
  }

  bool _isPeerGiftEligible() {
    final chat = widget.chat;
    if (chat.isSelf || chat.isBot) return false;
    if (chat.type == ChatType.dm) return true;
    if (chat.type == ChatType.channel && !chat.notJoined) return true;
    return false;
  }

  void _showStarGiftDialog(BuildContext context) async {
    final engine = context.read<EngineService>();
    final gifts = await engine.getStarGifts(widget.chat.accountId);
    if (gifts == null || !context.mounted) return;
    final giftList = gifts.gifts;
    if (giftList.isEmpty) {
      showTelegramToast(context, 'No gifts available');
      return;
    }
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => _StarGiftPickerDialog(gifts: giftList),
    );
    if (selected != null && context.mounted) {
      final success = await engine.sendStarGift(widget.chat.accountId, widget.chat.chatId, selected);
      if (context.mounted) {
        showTelegramToast(context, success ? 'Gift sent!' : 'Failed to send gift');
      }
    }
  }

  void _showStatsMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
    final isChannel = widget.chat.type == ChatType.channel;

    final items = <TelegramMenuItem<String>>[
      TelegramMenuItem(
        value: 'statistics',
        icon: const Icon(Icons.bar_chart, size: 20),
        label: 'Statistics',
      ),
      if (isChannel)
        const TelegramMenuItem(
          value: 'boosts',
          icon: Icon(Icons.rocket_launch_outlined, size: 20),
          label: 'Boosts',
        ),
    ];

    final value = await showTelegramMenu<String>(
      context: context,
      position: pos,
      items: items,
    );

    if (value == 'statistics' && context.mounted) {
      final panelState = context.findAncestorStateOfType<_InfoPanelState>();
      panelState?._pushPage(_InfoNavPage(type: _InfoPageType.statistics));
    } else if (value == 'boosts' && context.mounted) {
      final panelState = context.findAncestorStateOfType<_InfoPanelState>();
      panelState?._pushPage(_InfoNavPage(type: _InfoPageType.boosts));
    }
  }

  List<Widget> _buildInfoSections(BuildContext context) {
    final sections = <Widget>[
      const SizedBox(height: 16),
      _ChatDetails(chat: widget.chat, theme: widget.theme),
      _MusicMiniPlayer(chatId: widget.chat.chatId, theme: widget.theme),
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
          onOpenMedia: (type, label) {
            final panelState = context.findAncestorStateOfType<_InfoPanelState>();
            panelState?._pushPage(_InfoNavPage(
              type: _InfoPageType.sharedMedia,
              mediaType: type,
              mediaLabel: label,
            ));
          },
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
      if (widget.chat.type == ChatType.dm &&
          widget.chat.title == 'Saved Messages') ...[
        const Divider(height: 24),
        _SavedMediaFilterSection(
          theme: widget.theme,
          onOpenMedia: (type, label) {
            final panelState = context.findAncestorStateOfType<_InfoPanelState>();
            panelState?._pushPage(_InfoNavPage(
              type: _InfoPageType.sharedMedia,
              mediaType: type,
              mediaLabel: label,
            ));
          },
        ),
      ],
      const SizedBox(height: 16),
    ];
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, index) => sections[index],
          childCount: sections.length,
        ),
      ),
    ];
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
        : _groupStatusText(widget.chat);
    final statusColor = isDm && isOnline
        ? const Color(0xFF3BA55C)
        : widget.theme.textTheme.bodySmall?.color;
    final palette = context.palette;
    final numId = int.tryParse(widget.chat.chatId) ?? widget.chat.chatId.hashCode.abs();
    final colorIndex = _userpicColorRemap[numId.abs() % 7];
    final avatarColor = palette.peerUserpicBg(colorIndex);
    final profileBgColors = [
      palette.peerUserpicBg(colorIndex),
      palette.peerUserpicBg2(colorIndex),
    ];
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
              displayName: widget.chatState.activeSublist != null
                  ? widget.chatState.activeSublist!.peerName
                  : (widget.chat.title.isNotEmpty
                      ? widget.chat.title
                      : widget.chat.chatId),
              statusText: widget.chatState.activeSublist != null
                  ? 'Saved Messages'
                  : statusText,
              statusColor: statusColor,
              avatarPath: widget.chat.avatarPath,
              avatarColor: avatarColor,
              initials: _userpicInitials(widget.chat.title),
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
              isMyNotes: widget.chatState.activeSublist?.isSelf == true,
              storyCount: widget.chat.storyCount,
              hasUnreadStory: widget.chat.hasUnreadStory,
              profileBgColors: profileBgColors,
              emojiStatusId: widget.chat.emojiStatusId,
              accountId: widget.chat.accountId,
              pinnedGifts: widget.pinnedGifts,
              showStatsMenu: _canShowStatsMenu(),
              onStatsMenuTap: _showStatsMenu,
              chatId: widget.chat.chatId,
              onMessageTap: () {
                widget.chatState.openChatById(widget.chat.chatId);
              },
              onCallTap: () {
                final engine = context.read<EngineService>();
                engine.startCall(widget.chat.accountId, widget.chat.chatId);
              },
              avatarBytes: widget.chat.avatarPath.isEmpty ? null : null,
              notJoined: widget.chat.notJoined,
              linkedChatId: widget.chatState.linkedChatId,
              isPeerPremium: _isPeerGiftEligible(),
              onJoinTap: () {
                widget.chatState.joinChannel(widget.chat.accountId, widget.chat.chatId);
              },
              onDiscussTap: widget.chatState.linkedChatId.isNotEmpty
                  ? () { widget.chatState.openChatById(widget.chatState.linkedChatId); }
                  : null,
              onGiftTap: _isPeerGiftEligible()
                  ? () { _showStarGiftDialog(context); }
                  : null,
            ),
          ),
          ..._buildInfoSections(context),
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
            _TopicLinkRow(
              chat: widget.chat,
              topic: topic,
              theme: widget.theme,
            ),
            if (widget.mediaCounts.isNotEmpty) ...[
              const Divider(height: 24),
              _SharedMediaSection(
                counts: widget.mediaCounts,
                theme: widget.theme,
                isLayer: widget.isLayer,
                accountId: widget.chat.accountId,
                chatId: widget.chat.chatId,
                onOpenMedia: (type, label) {
                  final panelState = context.findAncestorStateOfType<_InfoPanelState>();
                  panelState?._pushPage(_InfoNavPage(
                    type: _InfoPageType.sharedMedia,
                    mediaType: type,
                    mediaLabel: label,
                  ));
                },
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
  int _commonGroupsCount = -1;
  bool _commonGroupsLoaded = false;
  Map<String, int> _mediaCounts = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_commonGroupsLoaded) {
      _commonGroupsLoaded = true;
      _loadCommonGroups();
      _loadMediaCounts();
    }
  }

  void _showCommonGroupsDialog(BuildContext ctx) {
    final engine = ctx.read<EngineService>();
    engine.getCommonChats(widget.chat.accountId, widget.member.userId, limit: 100).then((chats) {
      if (!mounted || chats.isEmpty) return;
      showDialog(
        context: ctx,
        builder: (dialogCtx) => SimpleDialog(
          title: Text('${chats.length} group${chats.length == 1 ? '' : 's'} in common'),
          children: chats.map((c) {
            final title = c['title'] as String? ?? c['chat_id'] as String? ?? '';
            final chatId = c['chat_id'] as String? ?? '';
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogCtx);
                final chatState = ctx.read<ChatState>();
                chatState.openChatById(chatId);
              },
              child: Text(title),
            );
          }).toList(),
        ),
      );
    });
  }

  void _loadCommonGroups() {
    final engine = context.read<EngineService>();
    engine.getCommonChats(widget.chat.accountId, widget.member.userId, limit: 100).then((chats) {
      if (mounted) setState(() => _commonGroupsCount = chats.length);
    }).catchError((_) {
      if (mounted) setState(() => _commonGroupsCount = 0);
    });
  }

  void _loadMediaCounts() {
    final engine = context.read<EngineService>();
    try {
      final counts = engine.getSharedMediaCounts(
        widget.chat.accountId, widget.member.userId,
      );
      if (mounted) setState(() => _mediaCounts = counts);
    } catch (_) {}
  }

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
    final palette = context.palette;
    final numId = int.tryParse(widget.member.userId) ?? widget.member.userId.hashCode.abs();
    final colorIndex = _userpicColorRemap[numId.abs() % 7];
    final color = palette.peerUserpicBg(colorIndex);
    final memberProfileBgColors = [
      palette.peerUserpicBg(colorIndex),
      palette.peerUserpicBg2(colorIndex),
    ];
    final name = widget.member.label;
    final initials = _userpicInitials(name);
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
              profileBgColors: memberProfileBgColors,
              avatarBytes: widget.member.avatarB64.isNotEmpty
                  ? base64Decode(widget.member.avatarB64)
                  : null,
              accountId: widget.chat.accountId,
              chatId: widget.member.userId,
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
                        showTelegramToast(context, 'Username copied');
                      },
                    ),
                  _TextWithLabel(
                    value: widget.member.userId,
                    label: 'ID',
                    theme: widget.theme,
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.member.userId));
                      showTelegramToast(context, 'ID copied');
                    },
                  ),
                  if (widget.member.role.isNotEmpty &&
                      widget.member.role != 'member')
                    _TextWithLabel(
                      value: widget.member.role,
                      label: 'Role',
                      theme: widget.theme,
                    ),
                  if (_commonGroupsCount > 0)
                    _CommonGroupsRow(
                      count: _commonGroupsCount,
                      theme: widget.theme,
                      onTap: () {
                        _showCommonGroupsDialog(context);
                      },
                    ),
                ],
              ),
              if (_mediaCounts.isNotEmpty) ...[
                const Divider(height: 24),
                _SharedMediaSection(
                  counts: _mediaCounts,
                  accountId: widget.chat.accountId,
                  chatId: widget.member.userId,
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
}

class _SharedMediaSubPage extends StatefulWidget {
  final ChatInfo chat;
  final ThemeData theme;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final String mediaType;
  final String title;

  const _SharedMediaSubPage({
    required this.chat,
    required this.theme,
    required this.scrollController,
    required this.onClose,
    required this.mediaType,
    required this.title,
  });

  @override
  State<_SharedMediaSubPage> createState() => _SharedMediaSubPageState();
}

class _SharedMediaSubPageState extends State<_SharedMediaSubPage> {
  List<SharedMediaItem> _items = [];
  bool _loading = true;
  bool _loaded = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  static const _pageSize = 50;
  final _contentScrollController = ScrollController();

  static const _typeToFilter = {
    'photo': 'image', 'video': 'video', 'stories': 'stories',
    'gifts': 'gifts', 'file': 'file', 'audio': 'audio',
    'voice': 'voice', 'round': 'round', 'gif': 'gif',
    'link': 'link', 'poll': 'poll',
  };
  static const _gridTypes = {'photo', 'video', 'stories', 'gifts'};
  static const _masonryTypes = {'gif'};

  @override
  void initState() {
    super.initState();
    _contentScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _contentScrollController.removeListener(_onScroll);
    _contentScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    final pos = _contentScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadItems();
    }
  }

  void _loadItems() {
    final engine = context.read<EngineService>();
    try {
      final items = engine.getSharedMedia(
        widget.chat.accountId, widget.chat.chatId,
        mediaType: _typeToFilter[widget.mediaType] ?? widget.mediaType,
        limit: _pageSize,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
          _hasMore = items.length >= _pageSize;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadMore() {
    if (_loadingMore || !_hasMore || _items.isEmpty) return;
    _loadingMore = true;
    final engine = context.read<EngineService>();
    try {
      final moreItems = engine.getSharedMedia(
        widget.chat.accountId, widget.chat.chatId,
        mediaType: _typeToFilter[widget.mediaType] ?? widget.mediaType,
        limit: _pageSize,
        offset: _items.length,
      );
      if (mounted) {
        setState(() {
          _items.addAll(moreItems);
          _hasMore = moreItems.length >= _pageSize;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final topBarColor = isDark ? const Color(0xFF17212b) : const Color(0xFFffffff);

    return Column(
      children: [
        Container(
          height: 56,
          color: topBarColor,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: widget.onClose,
                tooltip: 'Back',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.title,
                  style: widget.theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No ${widget.title.toLowerCase()} found.',
          style: TextStyle(color: widget.theme.textTheme.bodySmall?.color),
        ),
      );
    }
    if (_gridTypes.contains(widget.mediaType)) {
      return _buildLazyGrid();
    }
    if (_masonryTypes.contains(widget.mediaType)) {
      return _buildLazyMasonry();
    }
    return _buildLazyList();
  }

  Widget _buildLazyGrid() {
    final grouped = _MediaGrid._groupByMonth(_items);
    final entries = <_LazyGridEntry>[];
    for (final entry in grouped.entries) {
      entries.add(_LazyGridEntry.header(entry.key));
      entries.add(_LazyGridEntry.items(entry.value));
    }
    if (_loadingMore) {
      entries.add(_LazyGridEntry.loading());
    }

    return LayoutBuilder(builder: (context, constraints) {
      final listWidth = constraints.maxWidth;
      const sidePadding = _MediaGrid._sidePadding;
      const skip = _MediaGrid._skip;
      const minGridSize = _MediaGrid._minGridSize;
      final contentWidth = listWidth - 2 * sidePadding;
      final columns = math.max(1, ((contentWidth + skip) / (minGridSize + skip)).floor());
      final cellSide = ((contentWidth - (columns - 1) * skip) / columns).floorToDouble();
      final cellHeight = switch (widget.mediaType) {
        'stories' => (cellSide * _MediaGrid._storyRatio).floorToDouble(),
        'gifts' => (cellSide * _MediaGrid._giftRatio).floorToDouble(),
        _ => cellSide,
      };

      final flatRows = <_LazyRowData>[];
      for (final entry in entries) {
        if (entry.isHeader) {
          flatRows.add(_LazyRowData.header(entry.headerLabel!));
        } else if (entry.isLoading) {
          flatRows.add(_LazyRowData.loading());
        } else {
          final items = entry.items!;
          for (var i = 0; i < items.length; i += columns) {
            flatRows.add(_LazyRowData.row(
              items.sublist(i, math.min(i + columns, items.length)),
            ));
          }
        }
      }

      return CustomScrollView(
        controller: _contentScrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: sidePadding),
            sliver: SliverList.builder(
              itemCount: flatRows.length,
              itemBuilder: (context, index) {
                final row = flatRows[index];
                if (row.isHeader) {
                  return _DateHeader(label: row.headerLabel!, theme: widget.theme);
                }
                if (row.isLoading) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )),
                  );
                }
                final rowItems = row.items!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: skip),
                  child: Row(
                    children: [
                      for (var j = 0; j < rowItems.length; j++) ...[
                        if (j > 0) const SizedBox(width: skip),
                        _GridCell(item: rowItems[j], size: cellSide, height: cellHeight, theme: widget.theme),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _buildLazyMasonry() {
    final grouped = _MediaGrid._groupByMonth(_items);
    final flatRows = <_LazyRowData>[];
    for (final entry in grouped.entries) {
      flatRows.add(_LazyRowData.header(entry.key));
      flatRows.add(_LazyRowData.masonryGroup(entry.value));
    }
    if (_loadingMore) {
      flatRows.add(_LazyRowData.loading());
    }

    return LayoutBuilder(builder: (context, constraints) {
      const sidePadding = _GifMasonryGrid._sidePadding;
      const skip = _GifMasonryGrid._skip;
      const targetHeight = _GifMasonryGrid._rowTargetHeight;
      final availWidth = constraints.maxWidth - 2 * sidePadding;

      final builtRows = <_LazyRowData>[];
      for (final row in flatRows) {
        if (row.isMasonryGroup) {
          final items = row.items!;
          var i = 0;
          while (i < items.length) {
            double totalAR = 0;
            int count = 0;
            while (i + count < items.length) {
              final item = items[i + count];
              final ar = (item.width > 0 && item.height > 0)
                  ? item.width / item.height
                  : 1.0;
              totalAR += ar;
              count++;
              final rowHeight = (availWidth - (count - 1) * skip) / totalAR;
              if (rowHeight <= targetHeight && count > 1) break;
            }
            builtRows.add(_LazyRowData.masonryRow(
              items.sublist(i, i + count), totalAR, availWidth,
            ));
            i += count;
          }
        } else {
          builtRows.add(row);
        }
      }

      return CustomScrollView(
        controller: _contentScrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: sidePadding),
            sliver: SliverList.builder(
              itemCount: builtRows.length,
              itemBuilder: (context, index) {
                final row = builtRows[index];
                if (row.isHeader) {
                  return _DateHeader(label: row.headerLabel!, theme: widget.theme);
                }
                if (row.isLoading) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )),
                  );
                }
                final rowItems = row.items!;
                final rowHeight = math.min(
                  targetHeight,
                  (availWidth - (rowItems.length - 1) * skip) / row.totalAR!,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: skip),
                  child: SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        for (var j = 0; j < rowItems.length; j++) ...[
                          if (j > 0) const SizedBox(width: skip),
                          _buildGifCellInline(rowItems[j], rowHeight),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _buildGifCellInline(SharedMediaItem item, double rowHeight) {
    final ar = (item.width > 0 && item.height > 0)
        ? item.width / item.height
        : 1.0;
    final cellWidth = rowHeight * ar;
    final isDark = widget.theme.brightness == Brightness.dark;
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
      child: ClipRRect(child: content),
    );
  }

  Widget _buildLazyList() {
    final grouped = _MediaGrid._groupByMonth(_items);
    final flatItems = <_LazyRowData>[];
    for (final entry in grouped.entries) {
      flatItems.add(_LazyRowData.header(entry.key));
      for (final item in entry.value) {
        flatItems.add(_LazyRowData.listItem(item));
      }
    }
    if (_loadingMore) {
      flatItems.add(_LazyRowData.loading());
    }

    return CustomScrollView(
      controller: _contentScrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          sliver: SliverList.builder(
            itemCount: flatItems.length,
            itemBuilder: (context, index) {
              final row = flatItems[index];
              if (row.isHeader) {
                return _DateHeader(label: row.headerLabel!, theme: widget.theme);
              }
              if (row.isLoading) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )),
                );
              }
              final item = row.singleItem!;
              switch (widget.mediaType) {
                case 'file': return _FileListItem(item: item, theme: widget.theme);
                case 'audio': return _AudioListItem(item: item, theme: widget.theme);
                case 'voice': return _VoiceListItem(item: item, theme: widget.theme);
                case 'link': return _LinkListItem(item: item, theme: widget.theme);
                default: return _FileListItem(item: item, theme: widget.theme);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _LazyGridEntry {
  final String? headerLabel;
  final List<SharedMediaItem>? items;
  final bool isLoading;
  bool get isHeader => headerLabel != null && items == null && !isLoading;

  const _LazyGridEntry._(this.headerLabel, this.items, this.isLoading);
  factory _LazyGridEntry.header(String label) => _LazyGridEntry._(label, null, false);
  factory _LazyGridEntry.items(List<SharedMediaItem> items) => _LazyGridEntry._(null, items, false);
  factory _LazyGridEntry.loading() => const _LazyGridEntry._(null, null, true);
}

class _LazyRowData {
  final String? headerLabel;
  final List<SharedMediaItem>? items;
  final SharedMediaItem? singleItem;
  final bool isLoading;
  final bool isMasonryGroup;
  final double? totalAR;

  bool get isHeader => headerLabel != null && items == null && singleItem == null && !isLoading;

  const _LazyRowData._(this.headerLabel, this.items, this.singleItem, this.isLoading, this.isMasonryGroup, this.totalAR);
  factory _LazyRowData.header(String label) => _LazyRowData._(label, null, null, false, false, null);
  factory _LazyRowData.row(List<SharedMediaItem> items) => _LazyRowData._(null, items, null, false, false, null);
  factory _LazyRowData.masonryGroup(List<SharedMediaItem> items) => _LazyRowData._(null, items, null, false, true, null);
  factory _LazyRowData.masonryRow(List<SharedMediaItem> items, double totalAR, double availWidth) => _LazyRowData._(null, items, null, false, false, totalAR);
  factory _LazyRowData.listItem(SharedMediaItem item) => _LazyRowData._(null, null, item, false, false, null);
  factory _LazyRowData.loading() => const _LazyRowData._(null, null, null, true, false, null);
}

class _MasonryRowData {
  final String? headerLabel;
  final List<SharedMediaItem>? items;
  final double? totalAR;
  bool get isHeader => headerLabel != null;

  const _MasonryRowData._(this.headerLabel, this.items, this.totalAR);
  factory _MasonryRowData.header(String label) => _MasonryRowData._(label, null, null);
  factory _MasonryRowData.row(List<SharedMediaItem> items, double totalAR) => _MasonryRowData._(null, items, totalAR);
}

class _MusicMiniPlayer extends StatelessWidget {
  final String chatId;
  final ThemeData theme;

  const _MusicMiniPlayer({required this.chatId, required this.theme});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    if (!audio.playing || audio.currentChatId != chatId) {
      return const SizedBox.shrink();
    }
    final title = audio.currentTitle.isNotEmpty ? audio.currentTitle : 'Unknown Track';
    final performer = audio.currentPerformer.isNotEmpty ? audio.currentPerformer : 'Unknown Artist';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 24, 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (audio.currentMsgTimestamp > 0) {
              final chatState = context.read<ChatState>();
              chatState.jumpToMessage(audio.currentMsgTimestamp, highlightMsgId: audio.currentMsgId);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.music_note, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        performer,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
  int _commonGroupsCount = -1;
  List<BotCommandInfo> _botCommands = [];

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
    _loadCommonGroups(engine);
    _loadBotCommands(engine);
  }

  void _loadBotCommands(EngineService engine) {
    if (!widget.chat.isBot) return;
    engine.getChatBotCommands(widget.chat.accountId, widget.chat.chatId).then((cmds) {
      if (mounted) setState(() => _botCommands = cmds);
    }).catchError((_) {});
  }

  void _loadCommonGroups(EngineService engine) {
    engine.getCommonChats(widget.chat.accountId, widget.chat.chatId, limit: 100).then((chats) {
      if (mounted) setState(() => _commonGroupsCount = chats.length);
    }).catchError((_) {
      if (mounted) setState(() => _commonGroupsCount = 0);
    });
  }

  void _showCommonGroupsDialog(BuildContext ctx) {
    final engine = ctx.read<EngineService>();
    engine.getCommonChats(widget.chat.accountId, widget.chat.chatId, limit: 100).then((chats) {
      if (!mounted || chats.isEmpty) return;
      showDialog(
        context: ctx,
        builder: (dialogCtx) => SimpleDialog(
          title: Text('${chats.length} group${chats.length == 1 ? '' : 's'} in common'),
          children: chats.map((c) {
            final title = c['title'] as String? ?? c['chat_id'] as String? ?? '';
            final chatId = c['chat_id'] as String? ?? '';
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogCtx);
                final chatState = ctx.read<ChatState>();
                chatState.openChatById(chatId);
              },
              child: Text(title),
            );
          }).toList(),
        ),
      );
    });
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    showTelegramToast(context, '$label copied to clipboard');
  }

  static String _formatBirthday(int day, int month, int year) {
    const months = ['', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'];
    final m = (month >= 1 && month <= 12) ? months[month] : '$month';
    if (year > 0) {
      final now = DateTime.now();
      var age = now.year - year;
      if (now.month < month || (now.month == month && now.day < day)) {
        age--;
      }
      return '$m $day, $year ($age years old)';
    }
    return '$m $day';
  }

  String? _formatPeerId(int mode) {
    final raw = int.tryParse(widget.chat.chatId);
    if (raw == null) return null;
    if (mode == 2) return widget.chat.chatId;
    // Telegram API: always positive bare ID
    if (raw > 0) return raw.toString();
    if (raw > -1000000000000) return (-raw).toString();
    return (-raw - 1000000000000).toString();
  }

  @override
  Widget build(BuildContext context) {
    final isDm = widget.chat.type == ChatType.dm;
    final profile = _profile;
    final appState = context.watch<AppState>();
    final showPeerId = appState.showPeerId;
    final peerIdStr = showPeerId != 0 ? _formatPeerId(showPeerId) : null;
    final peerIdLabel = showPeerId == 1 ? 'ID (Telegram API)' : 'ID (Bot API)';

    final children = <Widget>[];

    if (isDm && profile != null) {
      if (profile.phone.isNotEmpty)
        children.add(_TextWithLabel(
          value: '+${profile.phone}',
          label: 'Phone',
          theme: widget.theme,
          onTap: () => _copy('+${profile.phone}', 'Phone'),
        ));
      if (profile.username.isNotEmpty)
        children.add(_TextWithLabel(
          value: '@${profile.username}',
          label: 'Username',
          theme: widget.theme,
          onTap: () => _copy('@${profile.username}', 'Username'),
        ));
      if (profile.bio.isNotEmpty)
        children.add(_TextWithLabel(
          value: profile.bio,
          label: profile.isBot ? 'About' : 'Bio',
          theme: widget.theme,
          onTap: () => _copy(profile.bio, profile.isBot ? 'About' : 'Bio'),
          selectable: true,
        ));
      if (profile.businessHours.isNotEmpty)
        children.add(_BusinessHoursWidget(
          hoursJson: profile.businessHours,
          theme: widget.theme,
        ));
      if (profile.businessLocation.isNotEmpty)
        children.add(_TextWithLabel(
          value: profile.businessLocation,
          label: 'Location',
          theme: widget.theme,
        ));
      if (profile.hasBirthday)
        children.add(_TextWithLabel(
          value: _formatBirthday(profile.birthdayDay, profile.birthdayMonth, profile.birthdayYear),
          label: 'Birthday',
          theme: widget.theme,
        ));
      if (profile.notes.isNotEmpty || profile.isContact)
        children.add(_ContactNotesWidget(
          note: profile.notes,
          theme: widget.theme,
          accountId: widget.chat.accountId,
          userId: widget.chat.chatId,
          onNoteChanged: () => _refetchProfile(),
        ));
      if (profile.personalChannelName.isNotEmpty)
        children.add(_TextWithLabel(
          value: profile.personalChannelName,
          label: 'Personal Channel',
          theme: widget.theme,
          onTap: profile.personalChannelId.isNotEmpty
              ? () {
                  final chatState = context.read<ChatState>();
                  chatState.openChatById(profile.personalChannelId);
                }
              : null,
        ));
      if (profile.isBot && _botCommands.isNotEmpty) {
        for (final cmd in _botCommands) {
          children.add(_BotCommandRow(
            command: '/${cmd.command}',
            description: cmd.description,
            theme: widget.theme,
          ));
        }
      }
    }

    if (peerIdStr != null)
      children.add(_TextWithLabel(
        value: peerIdStr,
        label: peerIdLabel,
        theme: widget.theme,
        onTap: () => _copy(peerIdStr, 'ID'),
      ));

    if (isDm && _commonGroupsCount > 0)
      children.add(_CommonGroupsRow(
        count: _commonGroupsCount,
        theme: widget.theme,
        onTap: () {
          _showCommonGroupsDialog(context);
        },
      ));

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
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

class _BusinessHoursWidget extends StatefulWidget {
  final String hoursJson;
  final ThemeData theme;

  const _BusinessHoursWidget({required this.hoursJson, required this.theme});

  @override
  State<_BusinessHoursWidget> createState() => _BusinessHoursWidgetState();
}

class _BusinessHoursWidgetState extends State<_BusinessHoursWidget> {
  bool _expanded = false;
  late final Map<String, dynamic> _data;
  late final String _timezone;
  late final List<_WeekInterval> _intervals;
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    try {
      _data = (json.decode(widget.hoursJson) as Map).cast<String, dynamic>();
      _timezone = _data['timezone'] as String? ?? '';
      final rawIntervals = _data['intervals'] as List? ?? [];
      _intervals = rawIntervals.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return _WeekInterval(m['start'] as int? ?? 0, m['end'] as int? ?? 0);
      }).toList();
      _valid = _intervals.isNotEmpty;
    } catch (_) {
      _valid = false;
      _timezone = '';
      _intervals = [];
    }
  }

  bool _isOpenNow() {
    final now = DateTime.now();
    final dayOfWeek = (now.weekday - 1) % 7;
    final minuteOfWeek = dayOfWeek * 1440 + now.hour * 60 + now.minute;
    for (final iv in _intervals) {
      if (minuteOfWeek >= iv.start && minuteOfWeek < iv.end) return true;
    }
    return false;
  }

  int _opensInMinutes() {
    final now = DateTime.now();
    final dayOfWeek = (now.weekday - 1) % 7;
    final minuteOfWeek = dayOfWeek * 1440 + now.hour * 60 + now.minute;
    int minDist = 10080;
    for (final iv in _intervals) {
      int dist = iv.start - minuteOfWeek;
      if (dist <= 0) dist += 10080;
      if (dist < minDist) minDist = dist;
    }
    return minDist;
  }

  String _opensInText() {
    final mins = _opensInMinutes();
    if (mins >= 1440) return 'Opens in ${mins ~/ 1440} day${mins >= 2880 ? 's' : ''}';
    if (mins >= 60) return 'Opens in ${mins ~/ 60} hour${mins >= 120 ? 's' : ''}';
    return 'Opens in $mins min';
  }

  String _dayName(int day) {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[day % 7];
  }

  String _formatMinute(int m) {
    final h = (m ~/ 60) % 24;
    final min = m % 60;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  List<String> _daySchedule(int day) {
    final dayStart = day * 1440;
    final dayEnd = dayStart + 1440;
    final result = <String>[];
    for (final iv in _intervals) {
      if (iv.end > dayStart && iv.start < dayEnd) {
        final s = (iv.start - dayStart).clamp(0, 1440);
        final e = (iv.end - dayStart).clamp(0, 1440);
        result.add('${_formatMinute(s)} – ${_formatMinute(e)}');
      }
    }
    return result.isEmpty ? ['Closed'] : result;
  }

  @override
  Widget build(BuildContext context) {
    if (!_valid) {
      return Padding(
        padding: const EdgeInsets.only(left: 23, top: 9, right: 20, bottom: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.hoursJson, style: widget.theme.textTheme.bodyMedium?.copyWith(fontSize: 14)),
            const SizedBox(height: 2),
            Text('Business Hours', style: TextStyle(fontSize: 12, color: widget.theme.colorScheme.primary)),
          ],
        ),
      );
    }

    final isOpen = _isOpenNow();
    final statusColor = isOpen ? const Color(0xFF4CAF50) : const Color(0xFFDD4B39);
    final statusText = isOpen ? 'Open' : 'Closed';

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.only(left: 23, top: 9, right: 20, bottom: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(statusText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
                const SizedBox(width: 8),
                if (!isOpen) Expanded(child: Text(_opensInText(), style: TextStyle(fontSize: 14, color: widget.theme.textTheme.bodyMedium?.color)))
                else const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Business Hours', style: TextStyle(fontSize: 12, color: widget.theme.colorScheme.primary)),
            if (_expanded) ...[
              const SizedBox(height: 8),
              for (int d = 0; d < 7; d++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          _dayName(d),
                          style: TextStyle(fontSize: 13, color: widget.theme.textTheme.bodyMedium?.color),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _daySchedule(d).join(', '),
                          style: TextStyle(
                            fontSize: 13,
                            color: _daySchedule(d).first == 'Closed'
                                ? widget.theme.colorScheme.onSurface.withValues(alpha: 0.5)
                                : widget.theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeekInterval {
  final int start;
  final int end;
  const _WeekInterval(this.start, this.end);
}

class _ContactNotesWidget extends StatelessWidget {
  final String note;
  final ThemeData theme;
  final String accountId;
  final String userId;
  final VoidCallback? onNoteChanged;

  const _ContactNotesWidget({
    required this.note,
    required this.theme,
    required this.accountId,
    required this.userId,
    this.onNoteChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (note.isEmpty) {
      return InkWell(
        onTap: () => _editNote(context, ''),
        child: Padding(
          padding: const EdgeInsets.only(left: 23, top: 9, right: 20, bottom: 7),
          child: Row(
            children: [
              Icon(Icons.note_add_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Add a note', style: TextStyle(fontSize: 14, color: theme.colorScheme.primary)),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      child: InkWell(
        onTap: () => _editNote(context, note),
        child: Padding(
          padding: const EdgeInsets.only(left: 23, top: 9, right: 20, bottom: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14), maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Note', style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
            ],
          ),
        ),
      ),
    );
  }

  void _editNote(BuildContext context, String currentNote) {
    final controller = TextEditingController(text: currentNote);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(currentNote.isEmpty ? 'Add Note' : 'Edit Note'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter note...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final engine = ctx.read<EngineService>();
              engine.updateContactNote(accountId, userId, controller.text.trim());
              Navigator.pop(ctx);
              onNoteChanged?.call();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: const [
        TelegramMenuItem(value: 'edit', icon: Icon(Icons.edit), label: 'Edit'),
        TelegramMenuItem(value: 'delete', icon: Icon(Icons.delete_outline), label: 'Delete', isAttention: true),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      if (value == 'edit') {
        _editNote(context, note);
      } else if (value == 'delete') {
        final engine = context.read<EngineService>();
        engine.updateContactNote(accountId, userId, '');
        onNoteChanged?.call();
      }
    });
  }
}

class _BotCommandRow extends StatelessWidget {
  final String command;
  final String description;
  final ThemeData theme;

  const _BotCommandRow({required this.command, required this.theme, this.description = ''});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final chatState = context.read<ChatState>();
        chatState.sendMessage(command);
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 23, top: 6, right: 20, bottom: 6),
        child: Row(
          children: [
            Icon(Icons.smart_toy_outlined, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    command,
                    style: TextStyle(fontSize: 14, color: theme.colorScheme.primary),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommonGroupsRow extends StatelessWidget {
  final int count;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _CommonGroupsRow({required this.count, required this.theme, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 23, top: 9, right: 20, bottom: 7),
        child: Row(
          children: [
            Icon(Icons.group_outlined, size: 20, color: theme.textTheme.bodySmall?.color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count group${count == 1 ? '' : 's'} in common',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: theme.textTheme.bodySmall?.color),
          ],
        ),
      ),
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
    final account = appState.accounts.where((a) => a.id == chat.accountId).firstOrNull;
    final selfUserId = account?.selfUserId ?? '';
    if (selfUserId.isEmpty) return false;
    for (final m in members!) {
      if (m.role == 'owner' || m.role == 'admin' || m.role == 'creator') {
        if (m.userId == selfUserId) {
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

    final showStats = _isSelfAdmin && chat.memberCount >= 500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStats)
          _ActionRow(
            icon: Icons.bar_chart,
            label: 'Statistics',
            theme: theme,
            onTap: () {
              final panelState = context.findAncestorStateOfType<_InfoPanelState>();
              panelState?._pushPage(_InfoNavPage(type: _InfoPageType.statistics));
            },
          ),
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
          icon: Icons.file_upload_outlined,
          label: 'Export Chat History',
          theme: theme,
          onTap: () => showExportPanel(
            context,
            ExportTarget(
              mode: ExportMode.perChat,
              accountId: chat.accountId,
              chatId: chat.chatId,
              chatTitle: chat.title,
            ),
          ),
        ),
        _ActionRow(
          icon: Icons.flag_outlined,
          label: 'Report',
          theme: theme,
          onTap: () => _confirmReport(context, chatState),
        ),
        if (!chat.notJoined)
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

  void _confirmReport(BuildContext context, ChatState chatState) async {
    final engine = context.read<EngineService>();
    await showDynamicReportFlow(
      context,
      engine: engine,
      accountId: chat.accountId,
      chatId: chat.chatId,
      msgIds: const [],
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

  @override
  void initState() {
    super.initState();
    _enabled = widget.chat.isForum;
  }

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
      if (_enabled) {
        await widget.engine.setForumViewAsMessages(
          widget.chat.accountId,
          widget.chat.chatId,
          _layout == _ForumLayout.list,
        );
      }
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
    final account = appState.accounts.where((a) => a.id == chat.accountId).firstOrNull;
    final selfUserId = account?.selfUserId ?? '';
    if (selfUserId.isEmpty) return false;
    for (final m in members!) {
      if (m.role == 'owner' || m.role == 'admin' || m.role == 'creator') {
        if (m.userId == selfUserId) {
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

    final showStats = _isSelfAdmin && chat.memberCount >= 50;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStats)
          _ActionRow(
            icon: Icons.bar_chart,
            label: 'Statistics',
            theme: theme,
            onTap: () {
              final panelState = context.findAncestorStateOfType<_InfoPanelState>();
              panelState?._pushPage(_InfoNavPage(type: _InfoPageType.statistics));
            },
          ),
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
          icon: Icons.file_upload_outlined,
          label: 'Export Chat History',
          theme: theme,
          onTap: () => showExportPanel(
            context,
            ExportTarget(
              mode: ExportMode.perChat,
              accountId: chat.accountId,
              chatId: chat.chatId,
              chatTitle: chat.title,
            ),
          ),
        ),
        _ActionRow(
          icon: Icons.flag_outlined,
          label: 'Report',
          theme: theme,
          onTap: () => _confirmReport(context, chatState),
        ),
        if (!chat.notJoined)
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

  void _confirmReport(BuildContext context, ChatState chatState) async {
    final engine = context.read<EngineService>();
    await showDynamicReportFlow(
      context,
      engine: engine,
      accountId: chat.accountId,
      chatId: chat.chatId,
      msgIds: const [],
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
      final nameParts = chat.title.split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
      showShareContactBox(
        context,
        contactPhone: profile.phone,
        contactFirstName: firstName,
        contactLastName: lastName,
        contactUserId: chat.chatId,
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
  final void Function(String type, String label)? onOpenMedia;

  const _SharedMediaSection({
    required this.counts,
    required this.theme,
    this.isLayer = false,
    required this.accountId,
    required this.chatId,
    this.onOpenMedia,
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

  List<StoryAlbumInfo>? _storyAlbums;
  bool _albumsLoading = false;
  int _activeStoryAlbumId = 0; // 0 = "All"

  static const _types = [
    ('photo', Icons.photo_outlined, 'Photos'),
    ('video', Icons.videocam_outlined, 'Videos'),
    ('stories', Icons.auto_stories_outlined, 'Stories'),
    ('gifts', Icons.card_giftcard_outlined, 'Gifts'),
    ('file', Icons.insert_drive_file_outlined, 'Files'),
    ('audio', Icons.music_note_outlined, 'Music'),
    ('link', Icons.link, 'Links'),
    ('voice', Icons.mic_outlined, 'Voice'),
    ('round', Icons.fiber_manual_record_outlined, 'Rounds'),
    ('gif', Icons.gif_box_outlined, 'GIFs'),
    ('poll', Icons.poll_outlined, 'Polls'),
  ];

  static const _gridTypes = {'photo', 'video', 'stories', 'gifts'};
  static const _masonryTypes = {'gif'};
  static const _listTypes = {'file', 'audio', 'link', 'voice', 'round', 'poll'};
  static const _expandableTypes = {'photo', 'video', 'stories', 'gifts', 'gif', 'file', 'audio', 'link', 'voice', 'round', 'poll'};

  static const _subTabSets = <String, List<(String, String)>>{
    'gifts': [('all', 'All'), ('unique', 'Unique'), ('limited', 'Limited')],
  };

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (_expandedGridType != null && _searchActive) {
        _loadGridItems(_expandedGridType!);
      }
    });
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
    if (type == 'stories') {
      _loadStoryAlbums();
    }
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
    'round': 'round',
    'gif': 'gif',
    'link': 'link',
    'poll': 'poll',
  };

  void _loadGridItems(String type) {
    final engine = context.read<EngineService>();
    try {
      var filterType = _typeToFilter[type] ?? type;
      if (type == 'gifts' && _activeSubTab.isNotEmpty && _activeSubTab != 'all') {
        filterType = 'gifts_$_activeSubTab';
      }
      final query = _searchActive ? _searchController.text.trim() : '';
      final items = engine.getSharedMedia(
        widget.accountId, widget.chatId,
        mediaType: filterType, limit: 50,
        query: query,
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

  Future<void> _loadStoryAlbums() async {
    if (_albumsLoading) return;
    setState(() => _albumsLoading = true);
    try {
      final engine = context.read<EngineService>();
      final albums = await engine.getStoryAlbums(widget.accountId);
      if (mounted) {
        setState(() {
          _storyAlbums = albums;
          _albumsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _albumsLoading = false);
    }
  }

  void _onStoryAlbumSelected(int albumId) {
    setState(() => _activeStoryAlbumId = albumId);
    if (albumId == 0) {
      _loadGridItems('stories');
    } else {
      _loadAlbumStories(albumId);
    }
  }

  Future<void> _loadAlbumStories(int albumId) async {
    setState(() {
      _gridItems = null;
      _gridLoading = true;
    });
    try {
      final engine = context.read<EngineService>();
      final result = await engine.getAlbumStories(
        widget.accountId, albumId, limit: 100,
      );
      if (mounted && _activeStoryAlbumId == albumId) {
        final items = result.stories.map((j) {
          final m = j as Map<String, dynamic>;
          return SharedMediaItem(
            msgId: 'story_${m['id']}',
            timestamp: (m['date'] as num?)?.toInt() ?? 0,
            mediaType: m['media_type'] == 'video' ? 4 : 1,
            thumbB64: m['thumb_b64'] as String? ?? '',
            localPath: m['local_path'] as String? ?? '',
          );
        }).toList();
        setState(() {
          _gridItems = items;
          _gridLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _gridLoading = false);
    }
  }

  Future<void> _createAlbum() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('New Album'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Album name'),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    try {
      final engine = context.read<EngineService>();
      await engine.createStoryAlbum(widget.accountId, name);
      _loadStoryAlbums();
    } catch (_) {}
  }

  Future<void> _reorderAlbums(List<StoryAlbumInfo> newOrder) async {
    setState(() => _storyAlbums = newOrder);
    try {
      final engine = context.read<EngineService>();
      await engine.reorderStoryAlbums(
        widget.accountId, newOrder.map((a) => a.id).toList(),
      );
    } catch (_) {
      _loadStoryAlbums();
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

    final hasGifts = (widget.counts['gifts'] ?? 0) > 0;
    final showGiftSubTabs = hasGifts && _expandedGridType == 'gifts';
    final subTabs = _subTabSets['gifts'] ?? [];

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
          for (final (type, icon, label) in visible) ...[
            _SharedMediaRow(
              icon: icon,
              label: label,
              count: widget.counts[type]!,
              iconColor: iconColor,
              accentColor: accentColor,
              theme: widget.theme,
              expanded: widget.onOpenMedia == null && _expandedGridType == type,
              onTap: _expandableTypes.contains(type)
                  ? () {
                      if (widget.onOpenMedia != null) {
                        widget.onOpenMedia!(type, label);
                      } else {
                        _toggleGrid(type);
                      }
                    }
                  : null,
            ),
            if (_expandedGridType == type && type == 'stories')
              _StoryAlbumTabs(
                albums: _storyAlbums ?? [],
                activeAlbumId: _activeStoryAlbumId,
                accentColor: accentColor,
                theme: widget.theme,
                onSelected: _onStoryAlbumSelected,
                onAdd: _createAlbum,
                onReorder: _reorderAlbums,
              ),
            if (_expandedGridType == type && type == 'gifts' && showGiftSubTabs && subTabs.isNotEmpty)
              _SubTabChips(
                tabs: subTabs,
                activeTab: _activeSubTab.isEmpty
                    ? subTabs.first.$1
                    : _activeSubTab,
                accentColor: accentColor,
                theme: widget.theme,
                onSelected: (tab) {
                  setState(() => _activeSubTab = tab);
                  _loadGridItems(type);
                },
              ),
            if (_expandedGridType == type)
              if (_gridTypes.contains(type))
                _MediaGrid(
                  items: _gridItems,
                  loading: _gridLoading,
                  theme: widget.theme,
                  mediaType: type,
                  isSearch: _searchActive && _searchController.text.isNotEmpty,
                )
              else if (_masonryTypes.contains(type))
                _GifMasonryGrid(
                  items: _gridItems,
                  loading: _gridLoading,
                  theme: widget.theme,
                  isSearch: _searchActive && _searchController.text.isNotEmpty,
                )
              else
                _MediaListView(
                  items: _gridItems,
                  loading: _gridLoading,
                  theme: widget.theme,
                  mediaType: type,
                  isSearch: _searchActive && _searchController.text.isNotEmpty,
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

class _StoryAlbumTabs extends StatefulWidget {
  final List<StoryAlbumInfo> albums;
  final int activeAlbumId;
  final Color accentColor;
  final ThemeData theme;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd;
  final ValueChanged<List<StoryAlbumInfo>> onReorder;

  const _StoryAlbumTabs({
    required this.albums,
    required this.activeAlbumId,
    required this.accentColor,
    required this.theme,
    required this.onSelected,
    required this.onAdd,
    required this.onReorder,
  });

  @override
  State<_StoryAlbumTabs> createState() => _StoryAlbumTabsState();
}

class _StoryAlbumTabsState extends State<_StoryAlbumTabs> {
  int? _dragIndex;
  int? _dropTarget;

  Widget _buildChip(String label, bool isActive, VoidCallback onTap) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final inactiveColor = isDark ? const Color(0xFF3e546a) : const Color(0xFFbbbbbb);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? widget.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? widget.accentColor : inactiveColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : widget.theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildChip('All', widget.activeAlbumId == 0, () => widget.onSelected(0)),
            for (int i = 0; i < widget.albums.length; i++) ...[
              const SizedBox(width: 8),
              Draggable<int>(
                data: i,
                feedback: Material(
                  color: Colors.transparent,
                  child: Opacity(
                    opacity: 0.8,
                    child: _buildChip(widget.albums[i].title, false, () {}),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: _buildChip(widget.albums[i].title, false, () {}),
                ),
                onDragStarted: () => setState(() => _dragIndex = i),
                onDragEnd: (_) => setState(() { _dragIndex = null; _dropTarget = null; }),
                child: DragTarget<int>(
                  onWillAcceptWithDetails: (details) {
                    setState(() => _dropTarget = i);
                    return details.data != i;
                  },
                  onLeave: (_) => setState(() => _dropTarget = null),
                  onAcceptWithDetails: (details) {
                    final from = details.data;
                    if (from == i) return;
                    final reordered = List<StoryAlbumInfo>.from(widget.albums);
                    final item = reordered.removeAt(from);
                    reordered.insert(i, item);
                    widget.onReorder(reordered);
                  },
                  builder: (ctx, candidateData, rejectedData) {
                    return Container(
                      decoration: _dropTarget == i && _dragIndex != i
                          ? BoxDecoration(
                              border: Border(left: BorderSide(color: widget.accentColor, width: 2)),
                            )
                          : null,
                      child: _buildChip(
                        widget.albums[i].title,
                        widget.activeAlbumId == widget.albums[i].id,
                        () => widget.onSelected(widget.albums[i].id),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.theme.brightness == Brightness.dark
                        ? const Color(0xFF3e546a)
                        : const Color(0xFFbbbbbb),
                    width: 1,
                  ),
                ),
                child: Icon(Icons.add, size: 16,
                  color: widget.theme.textTheme.bodyMedium?.color),
              ),
            ),
          ],
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
      onTap: onTap,
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
    const iconSize = 48.0;
    const minHeight = _iconTop + _labelTop + _labelSkip;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(constraints.maxHeight, minHeight);
        final iconCenterY = height / 3;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: iconCenterY - iconSize / 2,
                child: Center(child: Icon(icon, size: iconSize, color: emptyFg)),
              ),
              Positioned(
                left: _labelSkip,
                right: _labelSkip,
                top: height - _labelTop,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: _minLabelWidth),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: emptyFg),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
  final bool isSearch;

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
    this.isSearch = false,
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
      return _MediaEmptyState(mediaType: mediaType, theme: theme, isSearch: isSearch);
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

      final flatRows = <_LazyRowData>[];
      for (final entry in grouped.entries) {
        flatRows.add(_LazyRowData.header(entry.key));
        final groupItems = entry.value;
        for (var i = 0; i < groupItems.length; i += columns) {
          flatRows.add(_LazyRowData.row(
            groupItems.sublist(i, math.min(i + columns, groupItems.length)),
          ));
        }
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: flatRows.length,
          itemBuilder: (context, index) {
            final row = flatRows[index];
            if (row.isHeader) {
              return _DateHeader(label: row.headerLabel!, theme: theme);
            }
            final rowItems = row.items!;
            return Padding(
              padding: const EdgeInsets.only(bottom: _skip),
              child: Row(
                children: [
                  for (var j = 0; j < rowItems.length; j++) ...[
                    if (j > 0) const SizedBox(width: _skip),
                    _GridCell(item: rowItems[j], size: cellSide, height: cellHeight, theme: theme),
                  ],
                ],
              ),
            );
          },
        ),
      );
    });
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
  final bool isSearch;

  static const _skip = 2.0;
  static const _sidePadding = 3.0;
  static const _rowTargetHeight = 100.0;

  const _GifMasonryGrid({
    required this.items,
    required this.loading,
    required this.theme,
    this.isSearch = false,
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
      return _MediaEmptyState(mediaType: 'gif', theme: theme, isSearch: isSearch);
    }

    final grouped = _MediaGrid._groupByMonth(mediaItems);

    return LayoutBuilder(builder: (context, constraints) {
      final availWidth = constraints.maxWidth - 2 * _sidePadding;

      final flatRows = <_MasonryRowData>[];
      for (final entry in grouped.entries) {
        flatRows.add(_MasonryRowData.header(entry.key));
        var i = 0;
        final groupItems = entry.value;
        while (i < groupItems.length) {
          double totalAR = 0;
          int count = 0;
          while (i + count < groupItems.length) {
            final item = groupItems[i + count];
            final ar = (item.width > 0 && item.height > 0)
                ? item.width / item.height
                : 1.0;
            totalAR += ar;
            count++;
            final rowHeight = (availWidth - (count - 1) * _skip) / totalAR;
            if (rowHeight <= _rowTargetHeight && count > 1) break;
          }
          flatRows.add(_MasonryRowData.row(
            groupItems.sublist(i, i + count), totalAR,
          ));
          i += count;
        }
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: flatRows.length,
          itemBuilder: (context, index) {
            final row = flatRows[index];
            if (row.isHeader) {
              return _DateHeader(label: row.headerLabel!, theme: theme);
            }
            final rowItems = row.items!;
            final rowHeight = math.min(
              _rowTargetHeight,
              (availWidth - (rowItems.length - 1) * _skip) / row.totalAR!,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: _skip),
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
            );
          },
        ),
      );
    });
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
  final bool isSearch;

  const _MediaListView({
    required this.items,
    required this.loading,
    required this.theme,
    required this.mediaType,
    this.isSearch = false,
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
      return _MediaEmptyState(mediaType: mediaType, theme: theme, isSearch: isSearch);
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
                    painter: _MiniWaveformPainter(color: waveColor, waveform: item.waveform),
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
  final List<int> waveform;
  _MiniWaveformPainter({required this.color, this.waveform = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    final barCount = (size.width / 3).floor();
    for (var i = 0; i < barCount; i++) {
      final x = i * 3.0 + 1;
      double amplitude;
      if (waveform.isNotEmpty) {
        final idx = (i * waveform.length / barCount).floor().clamp(0, waveform.length - 1);
        amplitude = (waveform[idx] & 0x1F) / 31.0;
      } else {
        amplitude = 0.15;
      }
      final h = 3.0 + amplitude * (size.height - 6);
      final top = (size.height - h) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniWaveformPainter oldDelegate) =>
      color != oldDelegate.color || waveform != oldDelegate.waveform;
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
    return TelegramTooltip(
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

class _MembersSection extends StatefulWidget {
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

  @override
  State<_MembersSection> createState() => _MembersSectionState();
}

class _MembersSectionState extends State<_MembersSection> {
  bool _searching = false;
  int _displayLimit = _initialLimit;
  static const _initialLimit = 20;
  static const _loadMoreStep = 50;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  StreamSubscription<ChatInfo>? _chatUpdatedSub;
  StreamSubscription<MsgReceivedEvent>? _msgReceivedSub;
  Timer? _searchDebounce;
  List<MemberInfo>? _serverSearchResults;
  bool _searchLoading = false;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
  }

  void _subscribeToEvents() {
    final engine = context.read<EngineService>();
    _chatUpdatedSub = engine.onChatUpdated.listen((chat) {
      if (chat.chatId == widget.chatId && mounted) {
        _refreshMembers();
      }
    });
    _msgReceivedSub = engine.onMsgReceived.listen((event) {
      if (event.chatId == widget.chatId && event.message.isService && mounted) {
        _refreshMembers();
      }
    });
  }

  void _refreshMembers() {
    final engine = context.read<EngineService>();
    engine.getChatMembers(widget.accountId, widget.chatId).then((members) {
      if (mounted) {
        final panelState = context.findAncestorStateOfType<_InfoPanelState>();
        if (panelState != null) {
          panelState.setState(() {
            panelState._members = members;
          });
        }
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _chatUpdatedSub?.cancel();
    _msgReceivedSub?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _showAddMemberDialog(BuildContext context) async {
    final engine = context.read<EngineService>();
    final existingIds = widget.members?.map((m) => m.userId).toSet() ?? {};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dCtx) => _AddMemberDialog(
        accountId: widget.accountId,
        chatId: widget.chatId,
        engine: engine,
        existingMemberIds: existingIds,
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      try {
        await engine.addMembers(widget.accountId, widget.chatId, result);
        _refreshMembers();
      } on EngineException catch (e) {
        if (!mounted) return;
        String msg;
        if (e.code == 'CHAT_ADMIN_REQUIRED') {
          msg = 'You need admin rights to add members';
        } else if (e.code == 'USER_PRIVACY_RESTRICTED') {
          msg = 'This user\'s privacy settings prevent adding them';
        } else if (e.code == 'USER_NOT_MUTUAL_CONTACT') {
          msg = 'You can only add mutual contacts';
        } else if (e.code == 'USERS_TOO_MUCH') {
          msg = 'The group is full';
        } else {
          msg = 'Failed to add members: ${e.message}';
        }
        showTelegramToast(context, msg);
      } catch (e) {
        if (mounted) {
          showTelegramToast(context, 'Failed to add members');
        }
      }
    }
  }

  void _onSearchChanged(String text) {
    setState(() {});
    _searchDebounce?.cancel();
    final query = text.trim();
    if (query.isEmpty) {
      setState(() {
        _serverSearchResults = null;
        _searchLoading = false;
      });
      return;
    }
    setState(() => _searchLoading = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performServerSearch(query);
    });
  }

  Future<void> _performServerSearch(String query) async {
    final engine = context.read<EngineService>();
    try {
      final result = await engine.getChatMembersByRole(
        widget.accountId,
        widget.chatId,
        role: 'members',
        query: query,
        limit: 50,
      );
      if (mounted && _searchCtrl.text.trim().toLowerCase() == query.toLowerCase()) {
        setState(() {
          _serverSearchResults = result.members;
          _searchLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _serverSearchResults = null;
          _searchLoading = false;
        });
      }
    }
  }

  List<MemberInfo> _sortedMembers() {
    final list = List<MemberInfo>.from(widget.members!);
    list.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return list;
  }

  List<MemberInfo> _filteredMembers() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty && _serverSearchResults != null) {
      return _serverSearchResults!;
    }
    return _sortedMembers();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final filtered = (widget.members != null && widget.members!.isNotEmpty)
        ? _filteredMembers()
        : <MemberInfo>[];

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
                  child: _searching
                      ? TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          onChanged: _onSearchChanged,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search members',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        )
                      : Text(
                          widget.memberCount > 0 ? '${widget.memberCount} Members' : 'Members',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                _MembersHeaderButton(
                  icon: _searching ? Icons.close : Icons.search,
                  tooltip: _searching ? 'Close search' : 'Search members',
                  color: theme.textTheme.bodyMedium?.color ?? theme.iconTheme.color!,
                  onTap: () {
                    setState(() {
                      _searching = !_searching;
                      if (_searching) {
                        _searchFocus.requestFocus();
                      } else {
                        _searchCtrl.clear();
                        _serverSearchResults = null;
                        _searchLoading = false;
                        _searchDebounce?.cancel();
                      }
                    });
                  },
                ),
                _MembersHeaderButton(
                  icon: Icons.person_add_outlined,
                  tooltip: 'Add member',
                  color: theme.textTheme.bodyMedium?.color ?? theme.iconTheme.color!,
                  onTap: () => _showAddMemberDialog(context),
                ),
              ],
            ),
          ),
        ),
        if (widget.loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else if (widget.members != null && widget.members!.isNotEmpty) ...[
          ...(_searching ? filtered : filtered.take(_displayLimit)).map((m) => _MemberRow(
            member: m,
            theme: theme,
            onTap: widget.onMemberTap != null ? () => widget.onMemberTap!(m) : null,
            accountId: widget.accountId,
            chatId: widget.chatId,
            onMutated: _refreshMembers,
          )),
          if (!_searching && filtered.length > _displayLimit) ...[
            InkWell(
              onTap: () => setState(() {
                _displayLimit = (_displayLimit + _loadMoreStep).clamp(0, filtered.length);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Text(
                  'Show more (${filtered.length - _displayLimit} remaining)',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ] else
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 8, bottom: 8),
            child: Text(
              'No users found.',
              style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
            ),
          ),
        if (_searching && _searchLoading && _searchCtrl.text.trim().isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))),
          )
        else if (_searching && widget.members != null && widget.members!.isNotEmpty && filtered.isEmpty && !_searchLoading)
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 8, bottom: 8),
            child: Text(
              'No members match "${_searchCtrl.text}"',
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
  final VoidCallback? onMutated;

  const _MemberRow({
    required this.member,
    required this.theme,
    required this.accountId,
    required this.chatId,
    this.onTap,
    this.onMutated,
  });

  static String _formatLastSeen(String kind, int tsMs) {
    switch (kind) {
      case 'online':
        return 'online';
      case 'recently':
        return 'last seen recently';
      case 'within_week':
        return 'last seen within a week';
      case 'within_month':
        return 'last seen within a month';
      case 'long_ago':
        return 'last seen a long time ago';
      case 'hidden':
        return 'last seen a long time ago';
      case 'exact':
        if (tsMs <= 0) return 'last seen recently';
        final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
        final now = DateTime.now();
        final diff = now.difference(dt);
        if (diff.inMinutes < 1) return 'last seen just now';
        if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';
        if (diff.inHours < 24) return 'last seen ${diff.inHours}h ago';
        if (diff.inDays < 7) return 'last seen ${diff.inDays}d ago';
        final month = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1];
        if (dt.year == now.year) return 'last seen $month ${dt.day}';
        return 'last seen $month ${dt.day}, ${dt.year}';
      default:
        return 'last seen recently';
    }
  }

  static Widget _memberAvatar(MemberInfo member, Color color, String name, double size, double fontSize) {
    if (member.avatarB64.isNotEmpty) {
      try {
        final bytes = base64Decode(member.avatarB64);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _initialsFallback(color, name, size, fontSize),
          ),
        );
      } catch (_) {}
    }
    return _initialsFallback(color, name, size, fontSize);
  }

  static Widget _initialsFallback(Color color, String name, double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = member.displayName.isNotEmpty ? member.displayName : member.username;
    final colorIndex = member.userId.hashCode.abs() % 7;
    final color = [
      const Color(0xFFe17076), const Color(0xFF7bc862), const Color(0xFFe5ca77),
      const Color(0xFF65aadd), const Color(0xFFa695e7), const Color(0xFFee7aae),
      const Color(0xFF6ec9cb),
    ][colorIndex];

    final palette = context.palette;
    final bool hasAdminTag = member.role == 'owner' || member.role == 'admin' || member.role == 'creator';
    final bool isOwner = member.role == 'owner' || member.role == 'creator';

    String statusText = '';
    Color statusColor = palette.windowSubTextFg;
    if (member.isOnline) {
      statusText = 'online';
      statusColor = theme.colorScheme.primary;
    } else if (member.lastSeenKind.isNotEmpty) {
      statusText = _formatLastSeen(member.lastSeenKind, member.lastSeenTs);
    } else if (member.role != 'member' && member.role.isNotEmpty && !hasAdminTag) {
      statusText = member.role;
    } else {
      statusText = 'last seen recently';
    }

    final String? tagText = hasAdminTag
        ? (isOwner ? 'owner' : 'admin')
        : null;
    final Color tagColor = palette.profileAdminStartFg;

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
                              child: _memberAvatar(member, color, name, 36, 14),
                            ),
                          ),
                        )
                      : _memberAvatar(member, color, name, 42, 16),
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
                    padding: const EdgeInsets.fromLTRB(5, 1, 5, 2),
                    decoration: BoxDecoration(
                      color: tagColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tagText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tagColor,
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
          final ctrlHeld = HardwareKeyboard.instance.logicalKeysPressed
              .any((k) => k == LogicalKeyboardKey.controlLeft ||
                          k == LogicalKeyboardKey.controlRight);
          if (ctrlHeld) {
            showPeerShortInfoBox(
              context,
              accountId: accountId,
              peerId: member.userId,
              peerName: member.displayName.isNotEmpty ? member.displayName : member.username,
              avatarPath: '',
              peerType: ChatType.dm,
            );
          } else {
            onTap?.call();
          }
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
          showTelegramToast(context, 'Username copied');
        case 'copy_id':
          Clipboard.setData(ClipboardData(text: member.userId));
          showTelegramToast(context, 'ID copied');
        case 'promote':
          showEditAdminBox(
            context,
            accountId: accountId,
            chatId: chatId,
            member: member,
            isChannel: chatId.startsWith('-100'),
            promotedBy: member.promotedBy,
          ).then((_) => onMutated?.call());
        case 'demote':
          engine.demoteAdmin(accountId, chatId, member.userId).then((_) {
            onMutated?.call();
          }).catchError((e) {
            if (context.mounted) {
              showTelegramToast(context, 'Failed to demote: $e');
            }
          });
        case 'restrict':
          showEditRestrictedBox(
            context,
            accountId: accountId,
            chatId: chatId,
            member: member,
          ).then((_) => onMutated?.call());
        case 'remove':
          engine.removeMember(accountId, chatId, member.userId).then((_) {
            onMutated?.call();
          }).catchError((e) {
            if (context.mounted) {
              showTelegramToast(context, 'Failed to remove: $e');
            }
          });
        case 'ban':
          engine.banMember(accountId, chatId, member.userId).then((_) {
            onMutated?.call();
          }).catchError((e) {
            if (context.mounted) {
              showTelegramToast(context, 'Failed to ban: $e');
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
            _buildAvatar(context),
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

  Widget _buildAvatar(BuildContext context) {
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
      backgroundColor: context.palette.windowBgActive,
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

class _SavedMediaFilterSection extends StatelessWidget {
  final ThemeData theme;
  final void Function(String type, String label)? onOpenMedia;

  const _SavedMediaFilterSection({required this.theme, this.onOpenMedia});

  static const _filters = <(IconData, String, String)>[
    (Icons.photo_outlined, 'Photo', 'photo'),
    (Icons.videocam_outlined, 'Video', 'video'),
    (Icons.insert_drive_file_outlined, 'File', 'file'),
    (Icons.music_note_outlined, 'Music', 'audio'),
    (Icons.link_outlined, 'Link', 'link'),
    (Icons.poll_outlined, 'Poll', 'poll'),
    (Icons.mic_outlined, 'Voice', 'voice'),
    (Icons.gif_box_outlined, 'GIF', 'gif'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _filters.map((f) {
          return InkWell(
            onTap: () => onOpenMedia?.call(f.$3, f.$2),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(f.$1, size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 16),
                  Text(
                    f.$2,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BoostsPage extends StatefulWidget {
  final ChatInfo chat;
  final ThemeData theme;
  final ScrollController scrollController;
  final VoidCallback onClose;

  const _BoostsPage({
    required this.chat,
    required this.theme,
    required this.scrollController,
    required this.onClose,
  });

  @override
  State<_BoostsPage> createState() => _BoostsPageState();
}

class _BoostsPageState extends State<_BoostsPage> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;
  int _activeTab = 0; // 0=boosters, 1=gifts
  List<Map<String, dynamic>> _boosters = [];
  List<Map<String, dynamic>> _gifts = [];
  String? _boostersNextOffset;
  String? _giftsNextOffset;
  bool _loadingBoosters = false;
  bool _loadingGifts = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final engine = context.read<EngineService>();
      final data = await engine.getBoosts(widget.chat.accountId, widget.chat.chatId);
      if (!mounted) return;
      setState(() { _data = data; _loading = false; });
      _loadBoostersList(isGifts: false);
      _loadBoostersList(isGifts: true);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadBoostersList({required bool isGifts, bool loadMore = false}) async {
    if (isGifts) {
      if (_loadingGifts) return;
      _loadingGifts = true;
    } else {
      if (_loadingBoosters) return;
      _loadingBoosters = true;
    }
    try {
      final engine = context.read<EngineService>();
      final offset = loadMore ? (isGifts ? _giftsNextOffset ?? '' : _boostersNextOffset ?? '') : '';
      final result = await engine.getBoostsList(
        widget.chat.accountId, widget.chat.chatId,
        isGifts: isGifts, offset: offset,
      );
      if (!mounted) return;
      final items = (result['boosters'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>().toList() ?? [];
      final nextOff = result['next_offset'] as String?;
      setState(() {
        if (isGifts) {
          if (loadMore) { _gifts.addAll(items); } else { _gifts = items; }
          _giftsNextOffset = nextOff;
          _loadingGifts = false;
        } else {
          if (loadMore) { _boosters.addAll(items); } else { _boosters = items; }
          _boostersNextOffset = nextOff;
          _loadingBoosters = false;
        }
      });
    } catch (_) {
      if (mounted) setState(() {
        if (isGifts) { _loadingGifts = false; } else { _loadingBoosters = false; }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final topBarColor = isDark ? const Color(0xFF17212b) : const Color(0xFFffffff);

    return Column(
      children: [
        Container(
          height: 56,
          color: topBarColor,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onClose,
              ),
              const SizedBox(width: 8),
              Text('Boosts', style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              )),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade300)))
                  : _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_data == null) return const Center(child: Text('No data'));
    final level = _data!['level'] as int? ?? 0;
    final boosts = _data!['boosts'] as int? ?? 0;
    final currentLevelBoosts = _data!['current_level_boosts'] as int? ?? 0;
    final nextLevelBoosts = _data!['next_level_boosts'] as int? ?? 0;
    final giftBoosts = _data!['gift_boosts'] as int? ?? 0;
    final boostUrl = _data!['boost_url'] as String? ?? '';
    final isDark = widget.theme.brightness == Brightness.dark;
    final subColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 16),
        Center(child: Text('Level $level', style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black87,
        ))),
        const SizedBox(height: 8),
        Center(child: Text('$boosts boosts', style: TextStyle(
          fontSize: 14, color: subColor,
        ))),
        const SizedBox(height: 16),
        if (nextLevelBoosts > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: currentLevelBoosts > 0
                        ? (boosts - currentLevelBoosts) / (nextLevelBoosts - currentLevelBoosts)
                        : 0,
                    minHeight: 6,
                    backgroundColor: isDark ? const Color(0xFF2b3945) : const Color(0xFFe9ecef),
                    valueColor: AlwaysStoppedAnimation(widget.theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Level $level', style: TextStyle(fontSize: 12, color: subColor)),
                    Text('Level ${level + 1}', style: TextStyle(fontSize: 12, color: subColor)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('$boosts / $nextLevelBoosts boosts for next level',
                  style: TextStyle(fontSize: 12, color: subColor)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Divider(height: 1, color: widget.theme.dividerColor),
        // Overview section
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Overview', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: widget.theme.colorScheme.primary,
              )),
              const SizedBox(height: 12),
              _BoostOverviewRow(label: 'Level', value: '$level', theme: widget.theme),
              _BoostOverviewRow(label: 'Existing boosts', value: '$boosts', theme: widget.theme),
              if (giftBoosts > 0)
                _BoostOverviewRow(label: 'Boosts via gifts', value: '$giftBoosts', theme: widget.theme),
              if (nextLevelBoosts > 0)
                _BoostOverviewRow(label: 'Boosts to level up', value: '${nextLevelBoosts - boosts}', theme: widget.theme),
            ],
          ),
        ),
        Divider(height: 1, color: widget.theme.dividerColor),
        // Boosters / Gifts tabs
        if (_boosters.isNotEmpty || _gifts.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildBoosterTabs(),
          const SizedBox(height: 8),
          ..._buildBoosterList(),
          const SizedBox(height: 8),
          Divider(height: 1, color: widget.theme.dividerColor),
        ],
        // Boost link section
        if (boostUrl.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Link for boosting', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: widget.theme.colorScheme.primary,
                )),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf0f2f5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(boostUrl, style: TextStyle(
                        fontSize: 13,
                        color: widget.theme.colorScheme.primary,
                      ), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: boostUrl));
                          showTelegramToast(context, 'Link copied');
                        },
                        child: Icon(Icons.copy, size: 18, color: widget.theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Share this link with subscribers to get more boosts.',
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: widget.theme.dividerColor),
        ],
        // Get more boosts button
        InkWell(
          onTap: () {
            if (boostUrl.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: boostUrl));
              showTelegramToast(context, 'Boost link copied — share it to get more boosts!');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: widget.theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.rocket_launch, size: 16, color: widget.theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Get More Boosts', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: widget.theme.colorScheme.primary,
                ))),
                Icon(Icons.chevron_right, size: 20, color: subColor),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Share the boost link or start a giveaway to get more boosts for your channel.',
            style: TextStyle(fontSize: 12, color: subColor),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBoosterTabs() {
    final isDark = widget.theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _BoostTabButton(
            label: '${_boosters.length} Boosters',
            active: _activeTab == 0,
            theme: widget.theme,
            onTap: () => setState(() => _activeTab = 0),
          ),
          const SizedBox(width: 12),
          _BoostTabButton(
            label: '${_gifts.length} Gift Boosts',
            active: _activeTab == 1,
            theme: widget.theme,
            onTap: () => setState(() => _activeTab = 1),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBoosterList() {
    final list = _activeTab == 0 ? _boosters : _gifts;
    final hasMore = _activeTab == 0 ? _boostersNextOffset != null : _giftsNextOffset != null;
    final loading = _activeTab == 0 ? _loadingBoosters : _loadingGifts;
    final isDark = widget.theme.brightness == Brightness.dark;
    final subColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    if (list.isEmpty && loading) {
      return [const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))];
    }
    if (list.isEmpty) {
      return [Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_activeTab == 0 ? 'No boosters yet' : 'No gift boosts yet',
          style: TextStyle(fontSize: 13, color: subColor)),
      )];
    }

    final widgets = <Widget>[];
    for (final b in list) {
      final name = b['user_name'] as String? ?? 'Unknown';
      final isGift = b['gift'] == true;
      final isGiveaway = b['giveaway'] == true;
      final isUnclaimed = b['unclaimed'] == true;
      final multiplier = b['multiplier'] as int? ?? 1;
      final expires = b['expires'] as int? ?? 0;

      String subtitle = '';
      if (isUnclaimed) {
        subtitle = 'Unclaimed';
      } else if (isGiveaway) {
        subtitle = 'Giveaway';
      } else if (isGift) {
        subtitle = 'Gift';
      }
      if (expires > 0) {
        final exp = DateTime.fromMillisecondsSinceEpoch(expires * 1000);
        final now = DateTime.now();
        final days = exp.difference(now).inDays;
        if (days > 0) {
          subtitle += subtitle.isNotEmpty ? ' · ' : '';
          subtitle += 'Expires in $days days';
        }
      }

      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: widget.theme.colorScheme.primary.withValues(alpha: 0.15),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 14, color: widget.theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: TextStyle(fontSize: 11, color: subColor)),
              ],
            )),
            if (multiplier > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('×$multiplier', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: widget.theme.colorScheme.primary,
                )),
              ),
          ],
        ),
      ));
    }
    if (hasMore) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextButton(
          onPressed: () => _loadBoostersList(isGifts: _activeTab == 1, loadMore: true),
          child: Text(loading ? 'Loading...' : 'Show more'),
        ),
      ));
    }
    return widgets;
  }
}

class _BoostOverviewRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  const _BoostOverviewRow({required this.label, required this.value, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13,
            color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }
}

class _BoostTabButton extends StatelessWidget {
  final String label;
  final bool active;
  final ThemeData theme;
  final VoidCallback onTap;
  const _BoostTabButton({required this.label, required this.active, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: active ? null : Border.all(color: theme.dividerColor),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500,
          color: active ? Colors.white : theme.textTheme.bodyMedium?.color,
        )),
      ),
    );
  }
}

class _StatisticsPage extends StatefulWidget {
  final ChatInfo chat;
  final ThemeData theme;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final bool showBackButton;
  final void Function(Map<String, dynamic> postData)? onOpenMessageStats;

  const _StatisticsPage({
    required this.chat,
    required this.theme,
    required this.scrollController,
    required this.onClose,
    required this.showBackButton,
    this.onOpenMessageStats,
  });

  @override
  State<_StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<_StatisticsPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _showFinished = false;
  String? _error;
  Map<String, dynamic>? _stats;
  late final AnimationController _slideController;
  late final Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      value: 1.0,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _showFinished = true);
    });
    _loadStats();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final engine = context.read<EngineService>();
      final Map<String, dynamic> data;
      if (widget.chat.type == ChatType.channel) {
        data = await engine.getBroadcastStats(
          widget.chat.accountId, widget.chat.chatId,
        );
      } else {
        data = await engine.getMegagroupStats(
          widget.chat.accountId, widget.chat.chatId,
        );
      }
      if (mounted) {
        await _slideController.reverse();
        if (mounted) {
          setState(() {
            _stats = data;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        await _slideController.reverse();
        if (mounted) {
          setState(() {
            _error = e.toString();
            _loading = false;
          });
        }
      }
    }
  }

  Future<StatsChartData?> _loadZoomData(String token, int timestamp, String parentChartType) async {
    try {
      final engine = context.read<EngineService>();
      final data = await engine.loadStatsGraph(
        widget.chat.accountId, token, x: timestamp,
      );
      return StatsChartData.fromMap(data, parentChartType: parentChartType);
    } catch (_) {
      return null;
    }
  }

  String _formatDateRange() {
    if (_stats == null) return '';
    final minDate = _stats!['period_min'] as int?;
    final maxDate = _stats!['period_max'] as int?;
    if (minDate == null || maxDate == null) return '';
    final min = DateTime.fromMillisecondsSinceEpoch(minDate * 1000);
    final max = DateTime.fromMillisecondsSinceEpoch(maxDate * 1000);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${min.day} ${months[min.month - 1]} ${min.year} – '
           '${max.day} ${months[max.month - 1]} ${max.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Material(
            color: widget.theme.colorScheme.surface,
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: widget.onClose,
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Statistics',
                    style: widget.theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        Container(height: 1, color: widget.theme.dividerColor),
        Expanded(
          child: _loading
              ? _buildLoadingState()
              : _error != null
                  ? _buildErrorState()
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: _buildContent(),
                    ),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    _slideController.value = 1.0;
    await _loadStats();
  }

  Widget _buildLoadingState() {
    return SizeTransition(
      sizeFactor: _slideAnimation,
      axisAlignment: -1.0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: _showFinished
                  ? Lottie.asset(
                      'assets/animations/stats.json',
                      fit: BoxFit.contain,
                      animate: true,
                      repeat: true,
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),
            Text(
              'Loading Statistics...',
              style: widget.theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 256,
              child: Text(
                'Please wait while statistics are being loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 48,
                color: widget.theme.textTheme.bodySmall?.color),
            const SizedBox(height: 16),
            Text(
              'Statistics Unavailable',
              style: widget.theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 256,
              child: Text(
                _error!.contains('BROADCAST_REQUIRED') ||
                        _error!.contains('CHAT_ADMIN_REQUIRED')
                    ? 'You need to be an admin to view statistics.'
                    : 'Could not load statistics for this chat.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_stats == null || _stats!.isEmpty) return const SizedBox.shrink();
    final isChannel = widget.chat.type == ChatType.channel;
    final chartMaps = (_stats!['charts'] as List<dynamic>?) ?? [];
    final charts = <StatsChartData>[];
    for (final c in chartMaps) {
      if (c is Map<String, dynamic>) {
        final parsed = StatsChartData.fromMap(c);
        if (parsed != null) charts.add(parsed);
      }
    }
    final recentPosts = (_stats!['recent_posts'] as List<dynamic>?) ?? [];
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 17),
        _OverviewHeader(
          title: 'Overview',
          subtitle: _formatDateRange(),
          theme: widget.theme,
        ),
        const SizedBox(height: 12),
        if (isChannel) _buildChannelOverview() else _buildGroupOverview(),
        const SizedBox(height: 9),
        for (final chart in charts) ...[
          const SizedBox(height: 13),
          Divider(height: 1, color: widget.theme.dividerColor),
          const SizedBox(height: 13),
          StatsChartWidget(
            data: chart,
            theme: widget.theme,
            onLoadZoomData: (token, timestamp) => _loadZoomData(token, timestamp, chart.chartType),
          ),
        ],
        if (isChannel && recentPosts.isNotEmpty) ...[
          const SizedBox(height: 13),
          Divider(height: 1, color: widget.theme.dividerColor),
          const SizedBox(height: 13),
          _RecentMessagesSection(
            posts: recentPosts.cast<Map<String, dynamic>>(),
            dateRange: _formatDateRange(),
            theme: widget.theme,
            chat: widget.chat,
            onTapPost: widget.onOpenMessageStats,
          ),
        ],
        if (!isChannel) ..._buildTopMembersLists(),
        const SizedBox(height: 20),
      ],
    );
  }

  List<Widget> _buildTopMembersLists() {
    final topPosters = (_stats!['top_posters'] as List<dynamic>?) ?? [];
    final topAdmins = (_stats!['top_admins'] as List<dynamic>?) ?? [];
    final topInviters = (_stats!['top_inviters'] as List<dynamic>?) ?? [];
    final widgets = <Widget>[];

    if (topPosters.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 6),
        Divider(height: 1, color: widget.theme.dividerColor),
        const SizedBox(height: 6),
        _TopMembersSection(
          title: 'Top Senders',
          members: topPosters.cast<Map<String, dynamic>>(),
          theme: widget.theme,
          statusBuilder: (m) {
            final msgs = m['messages'] as int? ?? 0;
            final chars = m['avg_chars'] as int? ?? 0;
            return '$msgs messages, $chars characters';
          },
        ),
      ]);
    }

    if (topAdmins.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 6),
        Divider(height: 1, color: widget.theme.dividerColor),
        const SizedBox(height: 6),
        _TopMembersSection(
          title: 'Top Administrators',
          members: topAdmins.cast<Map<String, dynamic>>(),
          theme: widget.theme,
          statusBuilder: (m) {
            final deleted = m['deleted'] as int? ?? 0;
            final banned = m['banned'] as int? ?? 0;
            final kicked = m['kicked'] as int? ?? 0;
            final parts = <String>[];
            if (deleted > 0) parts.add('$deleted deletions');
            if (banned > 0) parts.add('$banned bans');
            if (kicked > 0) parts.add('$kicked restrictions');
            return parts.isEmpty ? 'No actions' : parts.join(', ');
          },
        ),
      ]);
    }

    if (topInviters.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 6),
        Divider(height: 1, color: widget.theme.dividerColor),
        const SizedBox(height: 6),
        _TopMembersSection(
          title: 'Top Inviters',
          members: topInviters.cast<Map<String, dynamic>>(),
          theme: widget.theme,
          statusBuilder: (m) {
            final inv = m['invitations'] as int? ?? 0;
            return '$inv invitations';
          },
        ),
      ]);
    }

    return widgets;
  }

  Widget _buildChannelOverview() {
    final followers = _parseStatValue(_stats!['followers'] as Map<String, dynamic>?);
    final notifPct = (_stats!['enabled_notifications'] as num?)?.toDouble() ?? 0;
    final viewsPerPost = _parseStatValue(_stats!['views_per_post'] as Map<String, dynamic>?);
    final viewsPerStory = _parseStatValue(_stats!['views_per_story'] as Map<String, dynamic>?);
    final sharesPerPost = _parseStatValue(_stats!['shares_per_post'] as Map<String, dynamic>?);
    final sharesPerStory = _parseStatValue(_stats!['shares_per_story'] as Map<String, dynamic>?);
    final reactionsPerPost = _parseStatValue(_stats!['reactions_per_post'] as Map<String, dynamic>?);
    final reactionsPerStory = _parseStatValue(_stats!['reactions_per_story'] as Map<String, dynamic>?);

    final hasStoryMetrics = _hasNonZero(sharesPerPost) ||
        _hasNonZero(sharesPerStory) ||
        _hasNonZero(reactionsPerPost) ||
        _hasNonZero(reactionsPerStory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OverviewGrid(theme: widget.theme, cells: [
          _OverviewCellData(
            value: _formatAbsValue(followers),
            change: _formatChange(followers),
            growth: _getGrowth(followers),
            label: 'Followers',
          ),
          _OverviewCellData(
            value: '${notifPct.toStringAsFixed(1)}%',
            change: null,
            growth: 0,
            label: 'Enabled Notifications',
          ),
          _OverviewCellData(
            value: _formatAbsValue(viewsPerPost),
            change: _formatChange(viewsPerPost),
            growth: _getGrowth(viewsPerPost),
            label: 'Views Per Post',
          ),
          _OverviewCellData(
            value: _formatAbsValue(viewsPerStory),
            change: _formatChange(viewsPerStory),
            growth: _getGrowth(viewsPerStory),
            label: 'Views Per Story',
          ),
        ]),
        if (hasStoryMetrics) ...[
          const SizedBox(height: 50),
          _OverviewGrid(theme: widget.theme, cells: [
            _OverviewCellData(
              value: _formatAbsValue(sharesPerPost),
              change: _formatChange(sharesPerPost),
              growth: _getGrowth(sharesPerPost),
              label: 'Shares Per Post',
            ),
            _OverviewCellData(
              value: _formatAbsValue(sharesPerStory),
              change: _formatChange(sharesPerStory),
              growth: _getGrowth(sharesPerStory),
              label: 'Shares Per Story',
            ),
            _OverviewCellData(
              value: _formatAbsValue(reactionsPerPost),
              change: _formatChange(reactionsPerPost),
              growth: _getGrowth(reactionsPerPost),
              label: 'Reactions Per Post',
            ),
            _OverviewCellData(
              value: _formatAbsValue(reactionsPerStory),
              change: _formatChange(reactionsPerStory),
              growth: _getGrowth(reactionsPerStory),
              label: 'Reactions Per Story',
            ),
          ]),
        ],
      ],
    );
  }

  Widget _buildGroupOverview() {
    final members = _parseStatValue(_stats!['members'] as Map<String, dynamic>?);
    final messages = _parseStatValue(_stats!['messages'] as Map<String, dynamic>?);
    final viewers = _parseStatValue(_stats!['viewers'] as Map<String, dynamic>?);
    final posters = _parseStatValue(_stats!['posters'] as Map<String, dynamic>?);

    return _OverviewGrid(theme: widget.theme, cells: [
      _OverviewCellData(
        value: _formatAbsValue(members),
        change: _formatChange(members),
        growth: _getGrowth(members),
        label: 'Members',
      ),
      _OverviewCellData(
        value: _formatAbsValue(messages),
        change: _formatChange(messages),
        growth: _getGrowth(messages),
        label: 'Messages',
      ),
      _OverviewCellData(
        value: _formatAbsValue(viewers),
        change: _formatChange(viewers),
        growth: _getGrowth(viewers),
        label: 'Viewing Members',
      ),
      _OverviewCellData(
        value: _formatAbsValue(posters),
        change: _formatChange(posters),
        growth: _getGrowth(posters),
        label: 'Posting Members',
      ),
    ]);
  }

  StatisticalValue? _parseStatValue(Map<String, dynamic>? v) {
    if (v == null) return null;
    return StatisticalValue.fromMap(v);
  }

  bool _hasNonZero(StatisticalValue? v) {
    if (v == null) return false;
    return v.value != 0;
  }

  String _formatAbsValue(StatisticalValue? v) {
    if (v == null) return '0';
    return _formatCountShort(v.value);
  }

  String? _formatChange(StatisticalValue? v) {
    if (v == null) return null;
    if (v.delta == 0 && v.previousValue == 0) return null;
    final prefix = v.isPositive ? '+' : '−';
    final deltaStr = _formatCountShort(v.delta.abs());
    if (v.growthRatePercentage.abs() < 0.01) return '$prefix$deltaStr';
    return '$prefix$deltaStr (${v.growthRatePercentage.abs().toStringAsFixed(1)}%)';
  }

  double _getGrowth(StatisticalValue? v) {
    if (v == null) return 0;
    return v.growthRatePercentage;
  }

  String _formatCountShort(double n) {
    final absN = n.abs();
    if (absN >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (absN >= 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    if (absN >= 1000) return '${(n / 1000).toStringAsFixed(2)}K';
    if (n == n.truncateToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }
}

class _OverviewCellData {
  final String value;
  final String? change;
  final double growth;
  final String label;
  const _OverviewCellData({
    required this.value,
    required this.change,
    required this.growth,
    required this.label,
  });
}

class _OverviewHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final ThemeData theme;
  const _OverviewHeader({required this.title, required this.subtitle, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ),
      ],
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  final ThemeData theme;
  final List<_OverviewCellData> cells;
  const _OverviewGrid({required this.theme, required this.cells});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _OverviewCell(data: cells[0], theme: theme)),
            const SizedBox(width: 14),
            Expanded(child: _OverviewCell(data: cells[1], theme: theme)),
          ],
        ),
        const SizedBox(height: 50),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _OverviewCell(data: cells[2], theme: theme)),
            const SizedBox(width: 14),
            Expanded(child: _OverviewCell(data: cells[3], theme: theme)),
          ],
        ),
      ],
    );
  }
}

class _OverviewCell extends StatelessWidget {
  final _OverviewCellData data;
  final ThemeData theme;
  const _OverviewCell({required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final greenColor = isDark ? const Color(0xFF4FAD2D) : const Color(0xFF4FAD2D);
    final redColor = isDark ? const Color(0xFFE05B5B) : const Color(0xFFE05B5B);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 152),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  data.value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (data.change != null) ...[
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    data.change!,
                    style: TextStyle(
                      fontSize: 11,
                      color: data.growth >= 0 ? greenColor : redColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top Members Section ──

class _TopMembersSection extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> members;
  final ThemeData theme;
  final String Function(Map<String, dynamic>) statusBuilder;

  const _TopMembersSection({
    required this.title,
    required this.members,
    required this.theme,
    required this.statusBuilder,
  });

  @override
  State<_TopMembersSection> createState() => _TopMembersSectionState();
}

class _TopMembersSectionState extends State<_TopMembersSection> {
  static const _kPerPage = 40;
  int _visibleCount = _kPerPage;

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final showCount = _visibleCount.clamp(0, members.length);
    final hasMore = showCount < members.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OverviewHeader(
          title: widget.title,
          subtitle: '',
          theme: widget.theme,
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < showCount; i++)
          _TopMemberRow(
            member: members[i],
            theme: widget.theme,
            status: widget.statusBuilder(members[i]),
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: () {
                setState(() { _visibleCount += _kPerPage; });
              },
              child: Text(
                'Show More',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.theme.colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TopMemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final ThemeData theme;
  final String status;

  const _TopMemberRow({
    required this.member,
    required this.theme,
    required this.status,
  });

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = member['name'] as String? ?? 'User';
    final userId = member['user_id'] as String? ?? '0';
    final numId = (int.tryParse(userId) ?? 0).abs();
    final avatarColor = palette.peerUserpicBg(_colorRemap[numId % 7]);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: avatarColor,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recent Messages Section ──

class _RecentMessagesSection extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final String dateRange;
  final ThemeData theme;
  final ChatInfo chat;
  final void Function(Map<String, dynamic> postData)? onTapPost;

  const _RecentMessagesSection({
    required this.posts,
    required this.dateRange,
    required this.theme,
    required this.chat,
    this.onTapPost,
  });

  @override
  State<_RecentMessagesSection> createState() => _RecentMessagesSectionState();
}

class _RecentMessagesSectionState extends State<_RecentMessagesSection> {
  static const _kFirstPage = 10;
  static const _kPerPage = 30;
  int _visibleCount = _kFirstPage;

  @override
  Widget build(BuildContext context) {
    final posts = widget.posts;
    final showCount = _visibleCount.clamp(0, posts.length);
    final hasMore = showCount < posts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OverviewHeader(
          title: 'Recent Messages',
          subtitle: widget.dateRange,
          theme: widget.theme,
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < showCount; i++)
          _RecentMessageRow(
            post: posts[i],
            theme: widget.theme,
            chat: widget.chat,
            onTap: () => widget.onTapPost?.call(posts[i]),
          ),
        if (hasMore)
          _ShowMoreButton(
            theme: widget.theme,
            onTap: () => setState(() {
              _visibleCount += _kPerPage;
            }),
          ),
      ],
    );
  }
}

class _ShowMoreButton extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onTap;
  const _ShowMoreButton({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Show More',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 18, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _RecentMessageRow extends StatelessWidget {
  final Map<String, dynamic> post;
  final ThemeData theme;
  final ChatInfo chat;
  final VoidCallback? onTap;

  const _RecentMessageRow({
    required this.post,
    required this.theme,
    required this.chat,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = post['text'] as String? ?? '';
    final date = post['date'] as int? ?? 0;
    final views = post['views'] as int? ?? 0;
    final forwards = post['forwards'] as int? ?? 0;
    final reactions = post['reactions'] as int? ?? 0;
    final mediaType = post['media_type'] as int? ?? 0;
    final thumbB64 = post['thumb_b64'] as String? ?? '';

    final dateStr = _formatPostDate(date);
    final subTextColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _PostThumbnail(
                mediaType: mediaType,
                thumbB64: thumbB64,
                chat: chat,
                theme: theme,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      text.isNotEmpty ? text : _mediaLabel(mediaType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      maxLines: 1,
                      style: TextStyle(fontSize: 11, color: subTextColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_fmtCount(views)} views',
                    style: TextStyle(fontSize: 11, color: subTextColor),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.reply, size: 12, color: subTextColor),
                      const SizedBox(width: 2),
                      Text(_fmtCount(forwards), style: TextStyle(fontSize: 11, color: subTextColor)),
                      const SizedBox(width: 4),
                      Icon(Icons.favorite_border, size: 12, color: subTextColor),
                      const SizedBox(width: 2),
                      Text(_fmtCount(reactions), style: TextStyle(fontSize: 11, color: subTextColor)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final chatState = context.read<ChatState>();
    final msgId = post['msg_id']?.toString() ?? '';
    final date = post['date'] as int? ?? 0;
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'show_in_chat',
          icon: const Icon(Icons.chat_bubble_outline, size: 20),
          label: 'Show in Chat',
        ),
      ],
    ).then((value) {
      if (value == 'show_in_chat' && msgId.isNotEmpty && date > 0) {
        chatState.jumpToMessage(date * 1000, highlightMsgId: msgId);
      }
    });
  }

  static String _mediaLabel(int mediaType) => switch (mediaType) {
    1 => 'Photo',
    2 => 'Video',
    3 => 'GIF',
    4 => 'Voice Message',
    5 => 'Video Message',
    6 => 'Sticker',
    7 => 'GIF',
    9 => 'Document',
    10 => 'Audio',
    _ => 'Message',
  };

  static String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(2)}K';
    return n.toString();
  }

  static String _formatPostDate(int ts) {
    if (ts == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year}, $h:$m';
  }
}

class _PostThumbnail extends StatelessWidget {
  final int mediaType;
  final String thumbB64;
  final ChatInfo chat;
  final ThemeData theme;

  const _PostThumbnail({
    required this.mediaType,
    required this.thumbB64,
    required this.chat,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (thumbB64.isNotEmpty) {
      final bytes = base64Decode(thumbB64);
      content = Image.memory(
        Uint8List.fromList(bytes),
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (mediaType > 0) {
      final icon = switch (mediaType) {
        1 => Icons.photo,
        2 || 5 => Icons.videocam,
        3 || 7 => Icons.gif_box,
        4 => Icons.mic,
        6 => Icons.sticky_note_2,
        9 => Icons.insert_drive_file,
        10 => Icons.music_note,
        _ => Icons.article,
      };
      content = Container(
        width: 42,
        height: 42,
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(icon, size: 22, color: theme.colorScheme.primary),
      );
    } else {
      content = _chatAvatar(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 42, height: 42, child: content),
    );
  }

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  Widget _chatAvatar(BuildContext context) {
    final palette = context.palette;
    final name = chat.title;
    final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
    final color = palette.peerUserpicBg(_colorRemap[numId.abs() % 7]);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: color),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Message Statistics Page ──

class _MessageStatsPage extends StatefulWidget {
  final ChatInfo chat;
  final ThemeData theme;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final Map<String, dynamic> postData;

  const _MessageStatsPage({
    required this.chat,
    required this.theme,
    required this.scrollController,
    required this.onClose,
    required this.postData,
  });

  @override
  State<_MessageStatsPage> createState() => _MessageStatsPageState();
}

class _MessageStatsPageState extends State<_MessageStatsPage> {
  bool _loading = true;
  String? _error;
  List<StatsChartData> _charts = [];
  int _publicForwardsCount = 0;
  List<Map<String, dynamic>> _publicForwards = [];
  String? _forwardsCursor;
  bool _hasMoreForwards = false;
  bool _loadingMoreForwards = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _loadStats();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMoreForwards || !_hasMoreForwards) return;
    final pos = widget.scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMoreForwards();
    }
  }

  Future<void> _loadStats() async {
    final msgId = widget.postData['msg_id'] as int? ?? 0;
    if (msgId == 0) {
      if (mounted) setState(() { _loading = false; });
      return;
    }
    try {
      final engine = context.read<EngineService>();
      final data = await engine.getMessageStats(
        widget.chat.accountId, widget.chat.chatId, msgId,
      );
      if (!mounted) return;
      final chartMaps = (data['charts'] as List<dynamic>?) ?? [];
      final charts = <StatsChartData>[];
      for (final c in chartMaps) {
        if (c is Map<String, dynamic>) {
          final parsed = StatsChartData.fromMap(c);
          if (parsed != null) charts.add(parsed);
        }
      }
      final pfCount = data['public_forwards_count'] as int? ?? 0;
      final pfList = (data['public_forwards'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ?? [];
      final nextOffset = data['next_offset'] as String?;
      setState(() {
        _charts = charts;
        _publicForwardsCount = pfCount;
        _publicForwards = pfList;
        _forwardsCursor = nextOffset;
        _hasMoreForwards = nextOffset != null && nextOffset.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMoreForwards() async {
    if (_loadingMoreForwards || !_hasMoreForwards || _forwardsCursor == null) return;
    _loadingMoreForwards = true;
    final msgId = widget.postData['msg_id'] as int? ?? 0;
    try {
      final engine = context.read<EngineService>();
      final data = await engine.getMorePublicForwards(
        widget.chat.accountId, widget.chat.chatId, msgId, _forwardsCursor!,
      );
      if (!mounted) return;
      final moreList = (data['forwards'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ?? [];
      final nextOffset = data['next_offset'] as String?;
      setState(() {
        _publicForwards.addAll(moreList);
        _forwardsCursor = nextOffset;
        _hasMoreForwards = nextOffset != null && nextOffset.isNotEmpty && moreList.isNotEmpty;
        _loadingMoreForwards = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoreForwards = false);
    }
  }

  Future<StatsChartData?> _loadZoomData(String token, int timestamp, String parentChartType) async {
    try {
      final engine = context.read<EngineService>();
      final data = await engine.loadStatsGraph(
        widget.chat.accountId, token, x: timestamp,
      );
      return StatsChartData.fromMap(data, parentChartType: parentChartType);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final views = widget.postData['views'] as int? ?? 0;
    final totalForwards = widget.postData['forwards'] as int? ?? 0;
    final reactions = widget.postData['reactions'] as int? ?? 0;
    final publicShares = _loading ? totalForwards : _publicForwardsCount;
    final privateShares = _loading ? 0 : (totalForwards - _publicForwardsCount).clamp(0, totalForwards);

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Material(
            color: widget.theme.colorScheme.surface,
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: widget.onClose,
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Message Statistics',
                    style: widget.theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        Container(height: 1, color: widget.theme.dividerColor),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const SizedBox(height: 12),
              _MessagePreviewRow(
                post: widget.postData,
                theme: widget.theme,
                chat: widget.chat,
              ),
              const SizedBox(height: 17),
              _OverviewHeader(
                title: 'Overview',
                subtitle: '',
                theme: widget.theme,
              ),
              const SizedBox(height: 12),
              _OverviewGrid(theme: widget.theme, cells: [
                _OverviewCellData(
                  value: _fmtCount(views),
                  change: null, growth: 0,
                  label: 'Views',
                ),
                _OverviewCellData(
                  value: _fmtCount(publicShares),
                  change: null, growth: 0,
                  label: 'Public Shares',
                ),
                _OverviewCellData(
                  value: _fmtCount(reactions),
                  change: null, growth: 0,
                  label: 'Reactions',
                ),
                _OverviewCellData(
                  value: _loading ? '...' : _fmtCount(privateShares),
                  change: null, growth: 0,
                  label: 'Private Shares',
                ),
              ]),
              if (_loading) ...[
                const SizedBox(height: 24),
                const Center(child: SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))),
              ] else if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(fontSize: 12,
                  color: widget.theme.colorScheme.error)),
              ] else ...[
                for (final chart in _charts) ...[
                  const SizedBox(height: 13),
                  Divider(height: 1, color: widget.theme.dividerColor),
                  const SizedBox(height: 13),
                  StatsChartWidget(
                    data: chart,
                    theme: widget.theme,
                    onLoadZoomData: (token, timestamp) => _loadZoomData(token, timestamp, chart.chartType),
                  ),
                ],
                if (_publicForwards.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  Divider(height: 1, color: widget.theme.dividerColor),
                  const SizedBox(height: 13),
                  _PublicForwardsSection(
                    forwards: _publicForwards,
                    totalCount: _publicForwardsCount,
                    theme: widget.theme,
                  ),
                  if (_loadingMoreForwards)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
                    ),
                ],
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(2)}K';
    return n.toString();
  }
}

class _MessagePreviewRow extends StatelessWidget {
  final Map<String, dynamic> post;
  final ThemeData theme;
  final ChatInfo chat;

  const _MessagePreviewRow({
    required this.post,
    required this.theme,
    required this.chat,
  });

  @override
  Widget build(BuildContext context) {
    final text = post['text'] as String? ?? '';
    final date = post['date'] as int? ?? 0;
    final mediaType = post['media_type'] as int? ?? 0;
    final thumbB64 = post['thumb_b64'] as String? ?? '';
    final dateStr = _RecentMessageRow._formatPostDate(date);

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      onLongPressStart: (details) => _showContextMenu(context, details.globalPosition),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _PostThumbnail(
              mediaType: mediaType,
              thumbB64: thumbB64,
              chat: chat,
              theme: theme,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.isNotEmpty ? text : _RecentMessageRow._mediaLabel(mediaType),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: theme.textTheme.bodyLarge?.color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final msgId = post['msg_id']?.toString() ?? '';
    final date = post['date'] as int? ?? 0;
    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'show_in_chat',
          icon: const Icon(Icons.chat_bubble_outline, size: 20),
          label: 'Show in Chat',
        ),
      ],
    ).then((value) {
      if (value == 'show_in_chat' && msgId.isNotEmpty && date > 0 && context.mounted) {
        final chatState = context.read<ChatState>();
        chatState.jumpToMessage(date * 1000, highlightMsgId: msgId);
      }
    });
  }
}

class _PublicForwardsSection extends StatefulWidget {
  final List<Map<String, dynamic>> forwards;
  final int totalCount;
  final ThemeData theme;

  const _PublicForwardsSection({
    required this.forwards,
    required this.totalCount,
    required this.theme,
  });

  @override
  State<_PublicForwardsSection> createState() => _PublicForwardsSectionState();
}

class _PublicForwardsSectionState extends State<_PublicForwardsSection> {
  int _displayCount = 20;

  @override
  Widget build(BuildContext context) {
    final subColor = widget.theme.textTheme.bodySmall?.color ?? Colors.grey;
    final shown = widget.forwards.take(_displayCount).toList();
    final hasMore = widget.forwards.length > _displayCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Public Shares',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.theme.textTheme.bodyLarge?.color,
                ),
              ),
            ),
            Text(
              widget.totalCount.toString(),
              style: TextStyle(fontSize: 13, color: subColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final fwd in shown)
          _PublicForwardRow(forward: fwd, theme: widget.theme),
        if (hasMore)
          TextButton(
            onPressed: () => setState(() => _displayCount += 20),
            child: Text('Show more (${widget.forwards.length - _displayCount} remaining)'),
          ),
      ],
    );
  }
}

class _PublicForwardRow extends StatelessWidget {
  final Map<String, dynamic> forward;
  final ThemeData theme;

  const _PublicForwardRow({
    required this.forward,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final name = forward['name'] as String? ?? 'Unknown';
    final isStory = forward['type'] == 'story';
    final views = forward['views'] as int?;
    final subColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    return InkWell(
      onTap: () {
        final peerId = forward['peer_id'] as String? ?? '';
        final msgId = forward['msg_id'];
        final date = forward['date'] as int? ?? 0;
        if (peerId.isNotEmpty) {
          final chatState = context.read<ChatState>();
          final chatId = _peerIdToChatId(peerId);
          chatState.openChatById(chatId);
          if (date > 0) {
            Future.microtask(() {
              chatState.jumpToMessage(date * 1000, highlightMsgId: msgId?.toString());
            });
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            if (isStory)
              _StoryRingAvatar(name: name, size: 36)
            else
              _ForwardAvatar(name: name, size: 36),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  if (views != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      '${_fmtViews(views)} views',
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtViews(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(2)}K';
    return n.toString();
  }

  static String _peerIdToChatId(String peerId) {
    if (peerId.startsWith('channel_')) {
      return '-100${peerId.substring(8)}';
    } else if (peerId.startsWith('chat_')) {
      return '-${peerId.substring(5)}';
    } else if (peerId.startsWith('user_')) {
      return peerId.substring(5);
    }
    return peerId;
  }
}

class _ForwardAvatar extends StatelessWidget {
  final String name;
  final double size;

  const _ForwardAvatar({required this.name, required this.size});

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = palette.peerUserpicBg(_colorRemap[name.hashCode.abs() % 7]);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static Color avatarColorFromPalette(String name, TelegramPalette palette) {
    return palette.peerUserpicBg(_colorRemap[name.hashCode.abs() % 7]);
  }
}

class _StoryRingAvatar extends StatelessWidget {
  final String name;
  final double size;

  const _StoryRingAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = _ForwardAvatar.avatarColorFromPalette(name, context.palette);
    return CustomPaint(
      painter: _StoryRingPainter(),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: size - 6,
          height: size - 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(color: Colors.white, fontSize: (size - 6) * 0.45, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = SweepGradient(
      colors: const [Color(0xFF34C759), Color(0xFF007AFF), Color(0xFF34C759)],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawOval(rect.deflate(1), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AddMemberDialog extends StatefulWidget {
  final String accountId;
  final String chatId;
  final EngineService engine;
  final Set<String> existingMemberIds;

  const _AddMemberDialog({
    required this.accountId,
    required this.chatId,
    required this.engine,
    required this.existingMemberIds,
  });

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  List<ContactInfo> _contacts = [];
  final Set<String> _selected = {};
  final _searchCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await widget.engine.getContacts(widget.accountId);
      if (!mounted) return;
      setState(() {
        _contacts = contacts
            .where((c) => !c.isBot && !widget.existingMemberIds.contains(c.userId))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<ContactInfo> _filtered() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((c) {
      return c.displayName.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q) ||
          c.phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final filtered = _filtered();

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(3),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Add Members',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search contacts...',
                    hintStyle: TextStyle(fontSize: 13, color: subtextColor),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: subtextColor.withValues(alpha: 0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: subtextColor.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _contacts.isEmpty ? 'No contacts available' : 'No matches',
                    style: TextStyle(fontSize: 13, color: subtextColor),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final sel = _selected.contains(c.userId);
                      return InkWell(
                        onTap: () => setState(() {
                          sel ? _selected.remove(c.userId) : _selected.add(c.userId);
                        }),
                        child: SizedBox(
                          height: 50,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                _buildAvatar(c, sel, accentColor, isDark),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    c.displayName.isNotEmpty ? c.displayName : c.username,
                                    style: TextStyle(fontSize: 13, color: textColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (sel)
                                  Icon(Icons.check_circle, size: 20, color: accentColor),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: Text('Cancel', style: TextStyle(fontSize: 13, color: subtextColor)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(_selected.toList()),
                      child: Text(
                        'Add${_selected.isNotEmpty ? ' (${_selected.length})' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: _selected.isEmpty ? subtextColor : accentColor,
                        ),
                      ),
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

  Widget _buildAvatar(ContactInfo c, bool selected, Color accent, bool isDark) {
    Widget avatar;
    if (c.avatarB64.isNotEmpty) {
      try {
        final bytes = base64Decode(c.avatarB64);
        avatar = CircleAvatar(radius: 18, backgroundImage: MemoryImage(bytes));
      } catch (_) {
        avatar = _fallbackAvatar(c, isDark);
      }
    } else {
      avatar = _fallbackAvatar(c, isDark);
    }
    if (!selected) return SizedBox(width: 36, height: 36, child: avatar);
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        children: [
          avatar,
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.8),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackAvatar(ContactInfo c, bool isDark) {
    final colors = [
      const Color(0xFFE17076), const Color(0xFF7BC862),
      const Color(0xFF65AADD), const Color(0xFFEE7AE6),
      const Color(0xFFE5AE49), const Color(0xFF6EC9CB),
    ];
    final idx = c.userId.hashCode.abs() % colors.length;
    final initials = c.displayName.isNotEmpty
        ? c.displayName.substring(0, 1).toUpperCase()
        : (c.username.isNotEmpty ? c.username.substring(0, 1).toUpperCase() : '?');
    return CircleAvatar(
      radius: 18,
      backgroundColor: colors[idx],
      child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 14)),
    );
  }
}
