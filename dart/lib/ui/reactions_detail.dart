import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import 'custom_emoji_cache.dart';
import 'info_panel.dart';
import 'privacy_settings_screen.dart';
import 'settings_style.dart';
import 'shell.dart';

String _formatCountDecimal(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _reactionTabKey(MessageReaction r) =>
    r.isCustomEmoji ? 'custom:${r.documentId}' : r.emoji;

class ReactionsDetailPanel extends StatefulWidget {
  final CachedMessage message;
  final String? initialEmoji;
  final ChatType chatType;
  final VoidCallback? onShowPrivacy;

  const ReactionsDetailPanel({
    super.key,
    required this.message,
    this.initialEmoji,
    this.chatType = ChatType.unspec,
    this.onShowPrivacy,
  });

  static void show(BuildContext context, CachedMessage message, {String? initialEmoji, ChatType chatType = ChatType.unspec}) {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final outerNav = Navigator.of(context);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Reactions',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.05),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutQuint)),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) {
        final screenW = MediaQuery.of(ctx).size.width;
        final panelWidth = screenW < 600 ? screenW * 0.92 : (screenW * 0.35).clamp(320.0, 440.0);
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: panelWidth,
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: ChangeNotifierProvider.value(
              value: appState,
              child: Provider.value(
                value: engine,
                child: ReactionsDetailPanel(
                  message: message,
                  initialEmoji: initialEmoji,
                  chatType: chatType,
                  onShowPrivacy: () {
                    Navigator.of(ctx).pop();
                    outerNav.push(settingsPageRoute(
                      ChangeNotifierProvider.value(
                        value: appState,
                        child: const PrivacySettingsScreen(),
                      ),
                    ));
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  State<ReactionsDetailPanel> createState() => _ReactionsDetailPanelState();
}

const _kPerPageFirst = 20;
const _kPerPageMore = 100;

class _ReactionsDetailPanelState extends State<ReactionsDetailPanel> {
  List<ReactorInfo> _allReactors = [];
  List<ReactorInfo> _masterReactors = [];
  String _masterNextOffset = '';
  List<ReadParticipantInfo> _readParticipants = [];
  List<ReadParticipantInfo> _cachedReadParticipants = [];
  ReadPrivacyState _cachedPrivacyState = ReadPrivacyState.none;
  int _readCount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _selectedTab;
  String _nextOffset = '';
  final ScrollController _scrollController = ScrollController();
  Set<String> _blockedIds = {};
  ReadPrivacyState _privacyState = ReadPrivacyState.none;
  StreamSubscription<MsgEditedEvent>? _editSub;
  StreamSubscription<MsgStatusEvent>? _statusSub;
  Map<String, List<ReactorInfo>>? _cachedGroupedByEmoji;
  List<ReactorInfo>? _cachedFilteredReactors;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialEmoji;
    _loadBlockedUsers();
    _loadReactors();
    _fetchReadInfo();
    _scrollController.addListener(_onScroll);
    final engine = context.read<EngineService>();
    _editSub = engine.onMsgEdited.listen((e) {
      if (e.accountId == widget.message.accountId &&
          e.chatId == widget.message.chatId &&
          e.msgId == widget.message.msgId) {
        _loadReactors();
        _fetchReadInfo();
      }
    });
    _statusSub = engine.onMsgStatus.listen((e) {
      if (e.accountId == widget.message.accountId &&
          e.chatId == widget.message.chatId &&
          e.msgId == widget.message.msgId) {
        _fetchReadInfo();
      }
    });
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final engine = context.read<EngineService>();
      final users = await engine.getBlockedUsers(widget.message.accountId);
      if (mounted) {
        setState(() {
          _blockedIds = users
              .map((u) => u['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
        });
        _invalidateCachedReactorData();
      }
    } catch (_) {}
  }

  Future<void> _fetchReadInfo() async {
    if (!widget.message.isOutgoing) return;
    final engine = context.read<EngineService>();
    if (widget.chatType == ChatType.dm) {
      try {
        final result = await engine.getOutboxReadDate(
          widget.message.accountId, widget.message.chatId, widget.message.msgId,
        );
        if (!mounted) return;
        _cachedPrivacyState = result.privacyState;
        if (result.date > 0) {
          final chatState = context.read<ChatState>();
          final peerChat = chatState.chats
              .where((c) => c.chatId == widget.message.chatId)
              .firstOrNull;
          _cachedReadParticipants = [
            ReadParticipantInfo(
              userId: widget.message.chatId,
              date: result.date,
              name: peerChat?.title ?? '',
            ),
          ];
          setState(() => _readCount = 1);
        } else {
          _cachedReadParticipants = [];
          setState(() => _readCount = 0);
        }
      } catch (_) {}
    } else {
      try {
        final result = await engine.getMessageReadParticipantsDetailed(
          widget.message.accountId, widget.message.chatId, widget.message.msgId,
        );
        if (!mounted) return;
        _cachedReadParticipants = result.participants;
        _cachedPrivacyState = result.privacyState;
        setState(() => _readCount = result.participants.length);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _editSub?.cancel();
    _statusSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_nextOffset.isEmpty || _loadingMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    if (current >= maxScroll - 100) {
      _loadMore();
    }
  }

  Future<void> _loadReactors() async {
    final engine = context.read<EngineService>();
    final msgId = int.tryParse(widget.message.msgId) ?? 0;
    if (msgId == 0) {
      setState(() => _loading = false);
      return;
    }
    if (_selectedTab == _ReactionTabBar.kReadTab) {
      if (_cachedReadParticipants.isNotEmpty) {
        setState(() {
          _readParticipants = _cachedReadParticipants;
          _privacyState = _cachedPrivacyState;
          _loading = false;
        });
        return;
      }
      try {
        final result = await engine.getMessageReadParticipantsDetailed(
          widget.message.accountId, widget.message.chatId, widget.message.msgId,
        );
        if (mounted) {
          _cachedReadParticipants = result.participants;
          _cachedPrivacyState = result.privacyState;
          setState(() {
            _readParticipants = result.participants;
            _privacyState = result.privacyState;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    if (_selectedTab == null && _masterReactors.isNotEmpty) {
      setState(() {
        _allReactors = _masterReactors;
        _nextOffset = _masterNextOffset;
        _loading = false;
      });
      _invalidateCachedReactorData();
      return;
    }
    try {
      final reactionFilter = _selectedTab != null
          ? _selectedTab! : '';
      final result = await engine.getMessageReactorsList(
        widget.message.accountId,
        widget.message.chatId,
        msgId,
        limit: _kPerPageFirst,
        reactionFilter: reactionFilter,
      );
      if (mounted) {
        if (_selectedTab == null) {
          _masterReactors = List.of(result.reactors);
          _masterNextOffset = result.nextOffset;
        }
        _invalidateCachedReactorData();
        setState(() {
          _allReactors = result.reactors;
          _nextOffset = result.nextOffset;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_nextOffset.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    final engine = context.read<EngineService>();
    final msgId = int.tryParse(widget.message.msgId) ?? 0;
    if (msgId == 0) {
      setState(() => _loadingMore = false);
      return;
    }
    try {
      final reactionFilter = _selectedTab != null && _selectedTab != _ReactionTabBar.kReadTab
          ? _selectedTab! : '';
      final result = await engine.getMessageReactorsList(
        widget.message.accountId,
        widget.message.chatId,
        msgId,
        limit: _kPerPageMore,
        offset: _nextOffset,
        reactionFilter: reactionFilter,
      );
      if (mounted) {
        if (_selectedTab == null) {
          final existingMaster = _masterReactors.map((r) => '${r.peerId}:${r.reactionKey}').toSet();
          final newMaster = result.reactors.where((r) => !existingMaster.contains('${r.peerId}:${r.reactionKey}')).toList();
          _masterReactors.addAll(newMaster);
          _masterNextOffset = result.nextOffset;
        }
        _invalidateCachedReactorData();
        setState(() {
          final existingAll = _allReactors.map((r) => '${r.peerId}:${r.reactionKey}').toSet();
          final newAll = result.reactors.where((r) => !existingAll.contains('${r.peerId}:${r.reactionKey}')).toList();
          _allReactors.addAll(newAll);
          _nextOffset = result.nextOffset;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _invalidateCachedReactorData() {
    _cachedGroupedByEmoji = null;
    _cachedFilteredReactors = null;
  }

  Map<String, List<ReactorInfo>> get _groupedByEmoji {
    if (_cachedGroupedByEmoji != null) return _cachedGroupedByEmoji!;
    final map = <String, List<ReactorInfo>>{};
    for (final r in _allReactors) {
      map.putIfAbsent(r.reactionKey, () => []).add(r);
    }
    _cachedGroupedByEmoji = map;
    return map;
  }

  List<ReactorInfo> get _filteredReactors {
    if (_cachedFilteredReactors != null) return _cachedFilteredReactors!;
    List<ReactorInfo> base;
    if (_selectedTab == null) {
      base = _allReactors;
    } else if (_selectedTab == _ReactionTabBar.kReadTab) {
      return [];
    } else {
      base = _allReactors.where((r) => r.reactionKey == _selectedTab).toList();
    }
    final result = _blockedIds.isEmpty
        ? base
        : base.where((r) => !_blockedIds.contains(r.peerId)).toList();
    _cachedFilteredReactors = result;
    return result;
  }

  List<ReadParticipantInfo> get _filteredReadParticipants {
    if (_blockedIds.isEmpty) return _readParticipants;
    return _readParticipants.where((p) => !_blockedIds.contains(p.userId)).toList();
  }

  bool get _isReadTab => _selectedTab == _ReactionTabBar.kReadTab;

  void _onTabSelected(String? tab) {
    if (tab == _selectedTab) return;
    final isReadTab = tab == _ReactionTabBar.kReadTab;

    if (tab == null && _masterReactors.isNotEmpty) {
      setState(() {
        _selectedTab = tab;
        _allReactors = _masterReactors;
        _nextOffset = _masterNextOffset;
        _loading = false;
      });
      _invalidateCachedReactorData();
      return;
    }

    if (isReadTab && _cachedReadParticipants.isNotEmpty) {
      _invalidateCachedReactorData();
      setState(() {
        _selectedTab = tab;
        _readParticipants = _cachedReadParticipants;
        _privacyState = _cachedPrivacyState;
        _loading = false;
      });
      return;
    }

    _invalidateCachedReactorData();
    setState(() {
      _selectedTab = tab;
      if (isReadTab) {
        _readParticipants = [];
      } else {
        _allReactors = [];
        _nextOffset = '';
      }
      _loading = true;
    });
    _loadReactors();
  }

  void _onReactorTap(ReactorInfo reactor) {
    if (reactor.peerId.isEmpty) return;
    Navigator.of(context).pop();
    final member = MemberInfo(
      userId: reactor.peerId,
      displayName: reactor.peerName,
    );
    if (InfoPanel.pushUserProfileRequest != null) {
      InfoPanel.pushUserProfileRequest!(member);
    } else {
      UniClientShell.toggleInfoRequest?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        InfoPanel.pushUserProfileRequest?.call(member);
      });
    }
  }

  bool get _showReadTab => _readCount > 0 || _cachedPrivacyState != ReadPrivacyState.none;

  String _buildTitle() {
    if (_readCount > 0) {
      final mt = widget.message.mediaType;
      if (mt == 3 || mt == 4) return 'Listened by $_readCount';
      if (mt == 5) return 'Watched by $_readCount';
      return 'Seen by $_readCount';
    }
    return 'Reactions';
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final grouped = _groupedByEmoji;
    final reactions = widget.message.reactions;
    final filteredReactors = _filteredReactors;

    return Material(
      elevation: 8,
      color: palette.windowBg,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TopBar(
            title: _buildTitle(),
            palette: palette,
            onClose: () => Navigator.of(context).pop(),
          ),
          if (reactions.isNotEmpty || _showReadTab)
            _ReactionTabBar(
              reactions: reactions,
              grouped: grouped,
              selectedTab: _selectedTab,
              readCount: _readCount,
              showReadTab: _showReadTab,
              palette: palette,
              onTabSelected: _onTabSelected,
              mediaType: widget.message.mediaType,
              accountId: widget.message.accountId,
            ),
          Divider(height: 1, color: palette.windowFg.withValues(alpha: 0.08)),
          if (_loading)
            _LoadingPlaceholder(palette: palette)
          else if (_isReadTab)
            _filteredReadParticipants.isEmpty && _privacyState == ReadPrivacyState.none
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Nobody has seen yet',
                    style: TextStyle(fontSize: 13, color: palette.windowSubTextFg),
                  ),
                )
              : Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_filteredReadParticipants.isNotEmpty)
                        Flexible(
                          child: ListView.builder(
                            controller: _scrollController,
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _filteredReadParticipants.length,
                            itemBuilder: (ctx, i) {
                              final p = _filteredReadParticipants[i];
                              return _ReadParticipantRow(
                                participant: p,
                                palette: palette,
                                accountId: widget.message.accountId,
                                onTap: () {
                                  if (p.userId.isEmpty) return;
                                  Navigator.of(context).pop();
                                  final member = MemberInfo(userId: p.userId, displayName: p.name);
                                  if (InfoPanel.pushUserProfileRequest != null) {
                                    InfoPanel.pushUserProfileRequest!(member);
                                  } else {
                                    UniClientShell.toggleInfoRequest?.call();
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      InfoPanel.pushUserProfileRequest?.call(member);
                                    });
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      if (_privacyState != ReadPrivacyState.none)
                        _ReadPrivacyNotice(
                          privacyState: _privacyState,
                          palette: palette,
                          accountId: widget.message.accountId,
                          onShowPrivacy: widget.onShowPrivacy,
                        ),
                    ],
                  ),
                )
          else if (filteredReactors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No reactions yet',
                style: TextStyle(
                  fontSize: 13,
                  color: palette.windowSubTextFg,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: filteredReactors.length + (_loadingMore ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= filteredReactors.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  return _ReactorRow(
                    reactor: filteredReactors[i],
                    showEmoji: _selectedTab == null,
                    palette: palette,
                    accountId: widget.message.accountId,
                    onTap: () => _onReactorTap(filteredReactors[i]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final TelegramPalette palette;
  final VoidCallback onClose;

  const _TopBar({
    required this.title,
    required this.palette,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: palette.windowFg,
                ),
              ),
            ),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(Icons.close, color: palette.windowFg),
                onPressed: onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionTabBar extends StatelessWidget {
  final List<MessageReaction> reactions;
  final Map<String, List<ReactorInfo>> grouped;
  final String? selectedTab;
  final int readCount;
  final bool showReadTab;
  final TelegramPalette palette;
  final ValueChanged<String?> onTabSelected;
  final int mediaType;
  final String accountId;

  static const kReadTab = '__read__';

  const _ReactionTabBar({
    required this.reactions,
    required this.grouped,
    required this.selectedTab,
    this.readCount = 0,
    this.showReadTab = false,
    required this.palette,
    required this.onTabSelected,
    this.mediaType = 0,
    this.accountId = '',
  });

  IconData get _readTabIcon {
    if (mediaType == 5) return Icons.play_circle_outline;
    if (mediaType == 3 || mediaType == 4) return Icons.headphones;
    return Icons.done_all;
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = reactions.fold<int>(0, (s, r) => s + r.count);
    final sorted = List<MessageReaction>.from(reactions)
      ..sort((a, b) => b.count.compareTo(a.count));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (showReadTab)
            _TabPill(
              iconData: _readTabIcon,
              label: readCount > 0 ? _formatCountDecimal(readCount) : '',
              isSelected: selectedTab == kReadTab,
              palette: palette,
              onTap: () => onTabSelected(kReadTab),
            ),
          _TabPill(
            iconData: Icons.favorite,
            label: _formatCountDecimal(totalCount),
            isSelected: selectedTab == null,
            palette: palette,
            onTap: () => onTabSelected(null),
          ),
          for (final r in sorted)
            _TabPill(
              emoji: r.isCustomEmoji ? null : r.emoji,
              customEmojiDocId: r.isCustomEmoji ? r.documentId : null,
              accountId: accountId,
              label: _formatCountDecimal(r.count),
              isSelected: selectedTab == _reactionTabKey(r),
              palette: palette,
              onTap: () => onTabSelected(_reactionTabKey(r)),
            ),
        ],
      ),
    );
  }
}

class _TabPill extends StatefulWidget {
  final String? emoji;
  final int? customEmojiDocId;
  final String accountId;
  final IconData? iconData;
  final String label;
  final bool isSelected;
  final TelegramPalette palette;
  final VoidCallback onTap;

  const _TabPill({
    this.emoji,
    this.customEmojiDocId,
    this.accountId = '',
    this.iconData,
    required this.label,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_TabPill> createState() => _TabPillState();
}

class _TabPillState extends State<_TabPill> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      value: widget.isSelected ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(covariant _TabPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasLeadingVisual => widget.emoji != null || widget.iconData != null || widget.customEmojiDocId != null;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (ctx, _) {
        final t = _animation.value;
        final bg = Color.lerp(
          widget.palette.windowBg,
          widget.palette.activeButtonBg,
          t,
        )!;
        final fg = Color.lerp(
          widget.palette.windowFg,
          widget.palette.activeButtonFg,
          t,
        )!;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: t < 0.5
                ? Border.all(color: widget.palette.windowFg.withValues(alpha: 0.12))
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              child: SizedBox(
                height: 32,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasLeadingVisual) ...[
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: widget.emoji != null
                                ? Text(widget.emoji!, style: const TextStyle(fontSize: 18))
                                : widget.customEmojiDocId != null
                                    ? _InlineCustomEmoji(
                                        documentId: widget.customEmojiDocId!,
                                        accountId: widget.accountId,
                                        size: 18,
                                      )
                                    : Icon(widget.iconData!, color: fg, size: 18),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, right: 12),
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// §42.5.1: 58px row, 46px avatar at (12,6), name at (68,11), status at (68,31),
// right emoji 18x18 at R27 margin
class _ReactorRow extends StatelessWidget {
  final ReactorInfo reactor;
  final bool showEmoji;
  final TelegramPalette palette;
  final VoidCallback? onTap;
  final String accountId;

  const _ReactorRow({
    required this.reactor,
    required this.showEmoji,
    required this.palette,
    required this.accountId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasReactionVisual = showEmoji && (reactor.emoji.isNotEmpty || reactor.isCustomEmoji);
    final dateStr = reactor.date > 0 ? formatReadDateLocal(reactor.date) : '';

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 6,
              child: _ReactorAvatar(
                name: reactor.peerName,
                size: 46,
                peerId: reactor.peerId,
                accountId: accountId,
              ),
            ),
            Positioned(
              left: 68,
              top: dateStr.isNotEmpty ? 11.0 : 20.0,
              right: hasReactionVisual ? 54 : 18,
              child: Text(
                reactor.peerName.isNotEmpty ? reactor.peerName : 'User',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.windowFg,
                ),
              ),
            ),
            if (dateStr.isNotEmpty)
              Positioned(
                left: 68,
                top: 31,
                right: hasReactionVisual ? 54 : 18,
                child: Text(
                  dateStr,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.windowSubTextFg,
                  ),
                ),
              ),
            if (hasReactionVisual)
              Positioned(
                right: 27,
                top: 20,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: Center(
                    child: reactor.isCustomEmoji
                        ? _InlineCustomEmoji(
                            documentId: reactor.documentId,
                            accountId: accountId,
                            size: 16,
                          )
                        : Text(
                            reactor.emoji,
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadParticipantRow extends StatelessWidget {
  final ReadParticipantInfo participant;
  final TelegramPalette palette;
  final VoidCallback? onTap;
  final String accountId;

  const _ReadParticipantRow({
    required this.participant,
    required this.palette,
    required this.accountId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = participant.name.isNotEmpty ? participant.name : 'User ${participant.userId}';
    final hasDate = participant.date > 0;
    final showSec = context.read<AppState>().showMessageSeconds;
    final dateStr = formatReadDateLocal(participant.date, showSeconds: showSec);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Stack(
          children: [
            Positioned(
              left: 12, top: 6,
              child: _ReactorAvatar(
                name: name,
                size: 46,
                peerId: participant.userId,
                accountId: accountId,
              ),
            ),
            Positioned(
              left: 68,
              top: hasDate ? 11.0 : 20.0,
              right: 18,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.windowFg,
                ),
              ),
            ),
            if (hasDate)
              Positioned(
                left: 68,
                top: 31,
                right: 18,
                child: Row(
                  children: [
                    Icon(Icons.done_all, size: 14, color: palette.windowSubTextFg),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        dateStr,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.windowSubTextFg,
                        ),
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
}

String formatReadDateLocal(int unixSeconds, {bool showSeconds = false}) {
  if (unixSeconds <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final now = DateTime.now();
  final time = showSeconds
      ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}'
      : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return 'Today, $time';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
    return 'Yesterday, $time';
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final mon = months[dt.month - 1];
  if (dt.year == now.year) return '$mon ${dt.day}, $time';
  return '$mon ${dt.day}, ${dt.year}, $time';
}

class _ReactorAvatar extends StatefulWidget {
  final String name;
  final double size;
  final String peerId;
  final String accountId;

  const _ReactorAvatar({
    required this.name,
    required this.size,
    this.peerId = '',
    this.accountId = '',
  });

  @override
  State<_ReactorAvatar> createState() => _ReactorAvatarState();
}

class _ReactorAvatarState extends State<_ReactorAvatar> {
  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
  static const _maxCacheSize = 200;
  static final _photoCache = <String, String?>{};

  String? _photoPath;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  static void _evictIfNeeded() {
    while (_photoCache.length > _maxCacheSize) {
      _photoCache.remove(_photoCache.keys.first);
    }
  }

  Future<void> _loadPhoto() async {
    if (widget.peerId.isEmpty || widget.accountId.isEmpty) {
      _loaded = true;
      return;
    }
    final cacheKey = '${widget.accountId}:${widget.peerId}';
    if (_photoCache.containsKey(cacheKey)) {
      final val = _photoCache.remove(cacheKey);
      _photoCache[cacheKey] = val;
      if (mounted) setState(() { _photoPath = val; _loaded = true; });
      return;
    }
    try {
      final engine = context.read<EngineService>();
      final result = await engine.getUserPhotoAtIndex(widget.accountId, widget.peerId, 0);
      _photoCache[cacheKey] = result.path;
      _evictIfNeeded();
      if (mounted) setState(() { _photoPath = result.path; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final initial = widget.name.isNotEmpty ? widget.name.characters.first.toUpperCase() : '?';
    final color = palette.peerUserpicBg(_colorRemap[widget.name.hashCode.abs() % 7]);

    if (_loaded && _photoPath != null && _photoPath!.isNotEmpty) {
      final cacheSize = (widget.size * 2).toInt();
      return ClipOval(
        child: Image.file(
          File(_photoPath!),
          width: widget.size,
          height: widget.size,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(initial, color),
        ),
      );
    }

    return _fallback(initial, color);
  }

  Widget _fallback(String initial, Color color) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.size * 0.42,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ReadPrivacyNotice extends StatelessWidget {
  final ReadPrivacyState privacyState;
  final TelegramPalette palette;
  final String accountId;
  final VoidCallback? onShowPrivacy;

  const _ReadPrivacyNotice({
    required this.privacyState,
    required this.palette,
    required this.accountId,
    this.onShowPrivacy,
  });

  @override
  Widget build(BuildContext context) {
    if (privacyState == ReadPrivacyState.none) return const SizedBox.shrink();

    final String label;
    final bool showButton;
    switch (privacyState) {
      case ReadPrivacyState.myHidden:
        label = 'Read time hidden';
        showButton = true;
      case ReadPrivacyState.hisHidden:
        label = 'Read time hidden';
        showButton = false;
      case ReadPrivacyState.tooOld:
        label = 'Message too old';
        showButton = false;
      case ReadPrivacyState.none:
        return const SizedBox.shrink();
    }

    return SizedBox(
      height: 19,
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: (19 - 14) / 2,
            child: Icon(Icons.done_all, size: 14, color: palette.windowSubTextFg),
          ),
          Positioned(
            left: 34,
            top: 3,
            right: showButton ? 70 : 17,
            bottom: 4,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                color: palette.windowSubTextFg,
              ),
            ),
          ),
          if (showButton)
            Positioned(
              right: 17,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onShowPrivacy,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: palette.windowBgActive,
                    ),
                    child: Text(
                      'Show',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.windowActiveTextFg,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingPlaceholder extends StatefulWidget {
  final TelegramPalette palette;
  const _LoadingPlaceholder({required this.palette});

  @override
  State<_LoadingPlaceholder> createState() => _LoadingPlaceholderState();
}

class _LoadingPlaceholderState extends State<_LoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final t = _ctrl.value;
          final pulse = t < 0.5 ? t * 2 : (1 - t) * 2;
          final baseColor = widget.palette.windowFg.withValues(alpha: 0.06);
          final highlightColor = widget.palette.windowFg.withValues(alpha: 0.14);
          final c = Color.lerp(baseColor, highlightColor, pulse)!;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) => SizedBox(
              height: 58,
              child: Stack(
                children: [
                  Positioned(
                    left: 12, top: 6,
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                    ),
                  ),
                  Positioned(
                    left: 68, top: 14,
                    right: 40 + i * 20.0,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: c,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 68, top: 34,
                    right: 80 + i * 30.0,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: c,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          );
        },
      ),
    );
  }
}

// ── Inline custom emoji widget for reaction tabs and reactor rows ──

Uint8List _gzipDecodeReactions(Uint8List data) =>
    Uint8List.fromList(gzip.decode(data));

class _InlineCustomEmoji extends StatefulWidget {
  final int documentId;
  final String accountId;
  final double size;

  const _InlineCustomEmoji({
    required this.documentId,
    required this.accountId,
    this.size = 18,
  });

  @override
  State<_InlineCustomEmoji> createState() => _InlineCustomEmojiState();
}

class _InlineCustomEmojiState extends State<_InlineCustomEmoji>
    with SingleTickerProviderStateMixin {
  AnimationController? _lottieCtrl;
  Uint8List? _decompressedLottie;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    CustomEmojiCache.instance.acquire(widget.documentId, EmojiSizeTag.normal);
    CustomEmojiCache.instance.addListenerForDoc(widget.documentId, _onCacheUpdate);
    _requestIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _InlineCustomEmoji old) {
    super.didUpdateWidget(old);
    if (old.documentId != widget.documentId) {
      CustomEmojiCache.instance.removeListenerForDoc(old.documentId, _onCacheUpdate);
      CustomEmojiCache.instance.release(old.documentId, EmojiSizeTag.normal);
      CustomEmojiCache.instance.acquire(widget.documentId, EmojiSizeTag.normal);
      CustomEmojiCache.instance.addListenerForDoc(widget.documentId, _onCacheUpdate);
      _decompressedLottie = null;
      _requested = false;
      _requestIfNeeded();
    }
  }

  @override
  void dispose() {
    CustomEmojiCache.instance.removeListenerForDoc(widget.documentId, _onCacheUpdate);
    CustomEmojiCache.instance.release(widget.documentId, EmojiSizeTag.normal);
    _lottieCtrl?.dispose();
    super.dispose();
  }

  bool _hadFile = false;
  bool _hadThumb = false;

  void _onCacheUpdate() {
    if (!mounted) return;
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(widget.documentId);
    final hasFile = file != null;
    final hasThumb = cache.getThumb(widget.documentId) != null;
    if (file != null && file.isTgs && _decompressedLottie == null) {
      _decompressLottie(file.fileData);
    }
    if (hasFile != _hadFile || hasThumb != _hadThumb) {
      _hadFile = hasFile;
      _hadThumb = hasThumb;
      setState(() {});
    }
  }

  void _requestIfNeeded() {
    if (_requested) return;
    _requested = true;
    final cache = CustomEmojiCache.instance;
    if (widget.accountId.isEmpty) return;
    final engine = context.read<EngineService>();
    if (!cache.hasAnyPreview(widget.documentId) &&
        !cache.isPending(widget.documentId) &&
        !cache.hasFailed(widget.documentId)) {
      cache.request(widget.documentId, widget.accountId, engine);
    }
    if (cache.getFile(widget.documentId) == null &&
        !cache.isFilePending(widget.documentId)) {
      cache.requestFile(widget.documentId, widget.accountId, engine);
    }
  }

  Future<void> _decompressLottie(Uint8List data) async {
    try {
      final result = await compute(_gzipDecodeReactions, data);
      if (mounted) setState(() => _decompressedLottie = result);
    } catch (_) {}
  }

  void _onLottieLoaded(LottieComposition c) {
    _lottieCtrl?.dispose();
    _lottieCtrl = AnimationController(vsync: this, duration: c.duration);
    _lottieCtrl!.addStatusListener((s) {
      if (s == AnimationStatus.completed) _lottieCtrl!.forward(from: 0);
    });
    _lottieCtrl!.forward();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final cache = CustomEmojiCache.instance;
    final file = cache.getFile(widget.documentId);

    if (file != null) {
      if (file.isTgs && _decompressedLottie != null) {
        return SizedBox(
          width: s, height: s,
          child: Lottie.memory(
            _decompressedLottie!,
            width: s, height: s,
            fit: BoxFit.contain,
            controller: _lottieCtrl,
            onLoaded: _onLottieLoaded,
            errorBuilder: (_, __, ___) => SizedBox(width: s, height: s),
          ),
        );
      }
      if (file.isWebp) {
        return SizedBox(
          width: s, height: s,
          child: Image.memory(
            file.fileData,
            width: s, height: s,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => SizedBox(width: s, height: s),
          ),
        );
      }
    }

    final thumb = cache.getThumb(widget.documentId);
    if (thumb != null) {
      return SizedBox(
        width: s, height: s,
        child: Image.memory(
          thumb,
          width: s, height: s,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => SizedBox(width: s, height: s),
        ),
      );
    }

    return SizedBox(width: s, height: s);
  }
}
