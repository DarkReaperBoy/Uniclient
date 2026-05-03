import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../theme/telegram_palette.dart';
import 'info_panel.dart';
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

class ReactionsDetailPanel extends StatefulWidget {
  final CachedMessage message;
  final String? initialEmoji;
  final ChatType chatType;

  const ReactionsDetailPanel({
    super.key,
    required this.message,
    this.initialEmoji,
    this.chatType = ChatType.unspec,
  });

  static void show(BuildContext context, CachedMessage message, {String? initialEmoji, ChatType chatType = ChatType.unspec}) {
    final engine = context.read<EngineService>();
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
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 392,
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Provider.value(
              value: engine,
              child: ReactionsDetailPanel(
                message: message,
                initialEmoji: initialEmoji,
                chatType: chatType,
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
  List<ReadParticipantInfo> _readParticipants = [];
  int _readCount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _selectedTab;
  String _nextOffset = '';
  final ScrollController _scrollController = ScrollController();
  Set<String> _blockedIds = {};

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialEmoji;
    _loadBlockedUsers();
    _loadReactors();
    _fetchReadCount();
    _scrollController.addListener(_onScroll);
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
      }
    } catch (_) {}
  }

  Future<void> _fetchReadCount() async {
    if (widget.message.isOutgoing && widget.chatType != ChatType.dm) {
      try {
        final engine = context.read<EngineService>();
        final ids = await engine.getMessageReadParticipants(
          widget.message.accountId, widget.message.chatId, widget.message.msgId,
        );
        if (mounted) setState(() => _readCount = ids.length);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
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
      try {
        final result = await engine.getMessageReadParticipantsDetailed(
          widget.message.accountId, widget.message.chatId, widget.message.msgId,
        );
        if (mounted) {
          setState(() {
            _readParticipants = result.participants;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
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
        setState(() {
          _allReactors.addAll(result.reactors);
          _nextOffset = result.nextOffset;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Map<String, List<ReactorInfo>> get _groupedByEmoji {
    final map = <String, List<ReactorInfo>>{};
    for (final r in _allReactors) {
      map.putIfAbsent(r.emoji, () => []).add(r);
    }
    return map;
  }

  List<ReactorInfo> get _filteredReactors {
    List<ReactorInfo> base;
    if (_selectedTab == null) {
      base = _allReactors;
    } else if (_selectedTab == _ReactionTabBar.kReadTab) {
      return [];
    } else {
      base = _allReactors.where((r) => r.emoji == _selectedTab).toList();
    }
    if (_blockedIds.isEmpty) return base;
    return base.where((r) => !_blockedIds.contains(r.peerId)).toList();
  }

  List<ReadParticipantInfo> get _filteredReadParticipants {
    if (_blockedIds.isEmpty) return _readParticipants;
    return _readParticipants.where((p) => !_blockedIds.contains(p.userId)).toList();
  }

  bool get _isReadTab => _selectedTab == _ReactionTabBar.kReadTab;

  void _onTabSelected(String? tab) {
    if (tab == _selectedTab) return;
    setState(() {
      _selectedTab = tab;
      _allReactors = [];
      _readParticipants = [];
      _nextOffset = '';
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

  String _buildTitle() {
    final reactions = widget.message.reactions;
    final totalCount = reactions.fold<int>(0, (s, r) => s + r.count);
    if (totalCount > 0) return 'Reactions · $totalCount';
    return 'Reactions';
  }

  @override
  Widget build(BuildContext context) {
    final palette = PaletteProvider.of(context);
    final grouped = _groupedByEmoji;
    final reactions = widget.message.reactions;

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
          if (reactions.isNotEmpty || _readCount > 0)
            _ReactionTabBar(
              reactions: reactions,
              grouped: grouped,
              selectedTab: _selectedTab,
              readCount: _readCount,
              palette: palette,
              onTabSelected: _onTabSelected,
            ),
          Divider(height: 1, color: palette.windowFg.withValues(alpha: 0.08)),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_isReadTab)
            _filteredReadParticipants.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Nobody has seen yet',
                    style: TextStyle(fontSize: 13, color: palette.windowSubTextFg),
                  ),
                )
              : Flexible(
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
                )
          else if (_filteredReactors.isEmpty)
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
                itemCount: _filteredReactors.length + (_loadingMore ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= _filteredReactors.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  return _ReactorRow(
                    reactor: _filteredReactors[i],
                    showEmoji: _selectedTab == null,
                    palette: palette,
                    onTap: () => _onReactorTap(_filteredReactors[i]),
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
  final TelegramPalette palette;
  final ValueChanged<String?> onTabSelected;

  static const kReadTab = '__read__';

  const _ReactionTabBar({
    required this.reactions,
    required this.grouped,
    required this.selectedTab,
    this.readCount = 0,
    required this.palette,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = reactions.fold<int>(0, (s, r) => s + r.count);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (readCount > 0)
            _TabPill(
              iconData: Icons.done_all,
              label: _formatCountDecimal(readCount),
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
          for (final r in reactions)
            _TabPill(
              emoji: r.emoji,
              label: _formatCountDecimal(r.count),
              isSelected: selectedTab == r.emoji,
              palette: palette,
              onTap: () => onTabSelected(r.emoji),
            ),
        ],
      ),
    );
  }
}

class _TabPill extends StatefulWidget {
  final String? emoji;
  final IconData? iconData;
  final String label;
  final bool isSelected;
  final TelegramPalette palette;
  final VoidCallback onTap;

  const _TabPill({
    this.emoji,
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

  bool get _hasLeadingVisual => widget.emoji != null || widget.iconData != null;

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

// §42.5.1: 58px row, 46px avatar at (18,6), name at (79,11), status at (79,31),
// right emoji 18x18 at R27 margin
class _ReactorRow extends StatelessWidget {
  final ReactorInfo reactor;
  final bool showEmoji;
  final TelegramPalette palette;
  final VoidCallback? onTap;

  const _ReactorRow({
    required this.reactor,
    required this.showEmoji,
    required this.palette,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 6,
              child: _ReactorAvatar(name: reactor.peerName, size: 46),
            ),
            Positioned(
              left: 79,
              top: 11,
              right: showEmoji && reactor.emoji.isNotEmpty ? 54 : 18,
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
            if (showEmoji && reactor.emoji.isNotEmpty)
              Positioned(
                right: 27,
                top: 20,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: Center(
                    child: Text(
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

  const _ReadParticipantRow({
    required this.participant,
    required this.palette,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = participant.name.isNotEmpty ? participant.name : 'User ${participant.userId}';
    final hasDate = participant.date > 0;
    final showSec = context.read<AppState>().showMessageSeconds;
    final dateStr = _formatReadDateLocal(participant.date, showSeconds: showSec);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Stack(
          children: [
            Positioned(
              left: 18, top: 6,
              child: _ReactorAvatar(name: name, size: 46),
            ),
            Positioned(
              left: 79,
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
                left: 79,
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

String _formatReadDateLocal(int unixSeconds, {bool showSeconds = false}) {
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

class _ReactorAvatar extends StatelessWidget {
  final String name;
  final double size;

  const _ReactorAvatar({required this.name, required this.size});

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final color = palette.peerUserpicBg(_colorRemap[name.hashCode.abs() % 7]);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
