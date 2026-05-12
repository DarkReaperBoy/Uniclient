import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import '../theme/theme.dart';
import 'confirm_box.dart';
import 'popup_menu.dart';
import 'settings_style.dart';
import 'telegram_toast.dart';
import 'call_panel.dart' show CallRatingDialog, showCallRatingDialog;
import 'call_screen.dart' show MinimisedCallBar;

export 'call_panel.dart' show CallRatingDialog, showCallRatingDialog;
export 'call_screen.dart' show MinimisedCallBar;

typedef RateCallBox = CallRatingDialog;
void showRateCallDialog(BuildContext context, {required String callId}) =>
    showCallRatingDialog(context, callId: callId);

// ---------------------------------------------------------------------------
// §34.2: showCallsBox — entry point (GenericBox pattern)
// ---------------------------------------------------------------------------

void showCallsBox(BuildContext context, {bool highlightStartCall = false}) {
  final engine = context.read<EngineService>();
  final appState = context.read<AppState>();
  final chatState = context.read<ChatState>();
  showTelegramBox(
    context: context,
    builder: (ctx) => MultiProvider(
      providers: [
        Provider<EngineService>.value(value: engine),
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: chatState),
      ],
      child: _CallsBox(highlightStartCall: highlightStartCall),
    ),
  );
}

// ---------------------------------------------------------------------------
// §34.2: _CallsBox — modal dialog matching GenericBox spec
// ---------------------------------------------------------------------------

class _CallsBox extends StatefulWidget {
  final bool highlightStartCall;
  const _CallsBox({this.highlightStartCall = false});

  @override
  State<_CallsBox> createState() => _CallsBoxState();
}

class _CallsBoxState extends State<_CallsBox> {
  List<_ActiveGroupCallEntry> _activeGroupCalls = [];
  StreamSubscription<GroupCallStateEvent>? _groupCallSub;

  List<CallHistoryEntry> _callHistory = [];
  List<_CallGroup> _groupedCalls = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  static const _kFirstPage = 20;
  static const _kNextPage = 100;

  @override
  void initState() {
    super.initState();
    _loadActiveGroupCalls();
    _loadCallHistory();
    final engine = context.read<EngineService>();
    _groupCallSub = engine.onGroupCallState.listen(_onGroupCallEvent);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _groupCallSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMoreCallHistory();
    }
  }

  Future<void> _loadCallHistory() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    final entries = await engine.getCallHistory(accountId, limit: _kFirstPage);
    if (mounted) {
      setState(() {
        _callHistory = entries;
        _groupedCalls = _groupCallEntries(_callHistory);
        _isLoading = false;
        _hasMore = entries.length >= _kFirstPage;
      });
    }
  }

  Future<void> _loadMoreCallHistory() async {
    if (_callHistory.isEmpty) return;
    setState(() => _loadingMore = true);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    final lastMsgId = int.tryParse(_callHistory.last.msgId) ?? 0;
    final entries = await engine.getCallHistory(
      accountId,
      offsetId: lastMsgId,
      limit: _kNextPage,
    );
    if (mounted) {
      setState(() {
        _callHistory.addAll(entries);
        _groupedCalls = _groupCallEntries(_callHistory);
        _loadingMore = false;
        _hasMore = entries.length >= _kNextPage;
      });
    }
  }

  static String _callTypeKey(CallHistoryEntry e) {
    if (e.isOutgoing) return 'out';
    if (e.isMissed) return 'missed';
    return 'in';
  }

  static String _dateKey(int epochSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    return '${dt.year}-${dt.month}-${dt.day}';
  }

  static List<_CallGroup> _groupCallEntries(List<CallHistoryEntry> entries) {
    if (entries.isEmpty) return [];
    final groups = <_CallGroup>[];
    var current = [entries.first];
    for (var i = 1; i < entries.length; i++) {
      final prev = current.first;
      final e = entries[i];
      if (e.peerId == prev.peerId &&
          _dateKey(e.timestamp) == _dateKey(prev.timestamp) &&
          _callTypeKey(e) == _callTypeKey(prev)) {
        current.add(e);
      } else {
        groups.add(_CallGroup(current));
        current = [e];
      }
    }
    groups.add(_CallGroup(current));
    return groups;
  }

  Future<void> _loadActiveGroupCalls() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    final chats = engine.getChatList(accountId: accountId, limit: 200);
    final pinned = chats.where((c) => c.isPinned);
    final nonPinned = chats.where((c) => !c.isPinned);
    final candidates = [...pinned, ...nonPinned]
        .where((c) => c.type == ChatType.group || c.type == ChatType.channel)
        .toList();

    final entries = <_ActiveGroupCallEntry>[];
    for (final chat in candidates) {
      try {
        final gc = await engine.getGroupCall(accountId, chat.chatId);
        if (gc != null && gc.active) {
          entries.add(_ActiveGroupCallEntry(chat: chat, callInfo: gc));
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _activeGroupCalls = entries);
    }
  }

  void _onGroupCallEvent(GroupCallStateEvent event) {
    _loadActiveGroupCalls();
  }

  // §34.11: Clear Call History — uses TelegramBox (was AlertDialog)
  void _showClearCallHistoryDialog() {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;

    showTelegramBox(
      context: context,
      builder: (ctx) {
        return _ClearCallHistoryBox(
          onConfirm: (revoke) async {
            try {
              await engine.clearCallHistory(accountId, revoke: revoke);
              if (mounted) {
                setState(() {
                  _callHistory.clear();
                  _groupedCalls.clear();
                });
              }
            } catch (_) {}
          },
        );
      },
    );
  }

  void _openCallSettings() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      settingsPageRoute(const _CallSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuIconColor = p.menuIconFg;
    final attentionColor = p.attentionButtonFg;

    return TelegramBox(
      title: 'Calls',
      showClose: true,
      scrollableContent: false,
      titleTrailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, size: 20, color: p.boxTitleFg),
        color: p.boxBg,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          minimumSize: const Size(kBoxTitleHeight, kBoxTitleHeight),
          maximumSize: const Size(kBoxTitleHeight, kBoxTitleHeight),
        ),
        onSelected: (value) {
          switch (value) {
            case 'settings':
              _openCallSettings();
            case 'clear_all':
              _showClearCallHistoryDialog();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'settings',
            child: Row(
              children: [
                Icon(Icons.settings, size: 20, color: menuIconColor),
                const SizedBox(width: 12),
                Text('Call Settings',
                    style: TextStyle(fontSize: 14, color: p.boxTextFg)),
              ],
            ),
          ),
          if (_callHistory.isNotEmpty)
            PopupMenuItem<String>(
              value: 'clear_all',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: attentionColor),
                  const SizedBox(width: 12),
                  Text('Clear All',
                      style: TextStyle(fontSize: 14, color: attentionColor)),
                ],
              ),
            ),
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // §34.3: Active Group Calls
          _ActiveGroupCallsSection(
            entries: _activeGroupCalls,
            isDark: isDark,
          ),
          // §34.12: Create Call Button
          _CreateCallButton(isDark: isDark, highlightOnShow: widget.highlightStartCall),
          Divider(height: 1, color: p.boxDividerBg),
          // §34.4: Call history list
          Flexible(
            child: _buildCallHistoryList(isDark: isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildCallHistoryList({required bool isDark}) {
    final p = context.palette;
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'Loading...',
            style: TextStyle(fontSize: 14, color: p.boxTitleAdditionalFg),
          ),
        ),
      );
    }

    if (_callHistory.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Center(
          child: Text(
            'Your recent calls will appear here.',
            style: TextStyle(fontSize: 14, color: p.boxTitleAdditionalFg),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      itemCount: _groupedCalls.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _groupedCalls.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _CallHistoryRow(
          group: _groupedCalls[index],
          accountId: context.read<AppState>().activeAccountId,
          isDark: isDark,
          onDeleted: (group) {
            setState(() {
              for (final e in group.entries) {
                _callHistory.removeWhere((c) => c.msgId == e.msgId);
              }
              _groupedCalls = _groupCallEntries(_callHistory);
            });
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// §34.11: Clear Call History Dialog (TelegramBox)
// ---------------------------------------------------------------------------

class _ClearCallHistoryBox extends StatefulWidget {
  final Future<void> Function(bool revoke) onConfirm;

  const _ClearCallHistoryBox({required this.onConfirm});

  @override
  State<_ClearCallHistoryBox> createState() => _ClearCallHistoryBoxState();
}

class _ClearCallHistoryBoxState extends State<_ClearCallHistoryBox> {
  bool _revoke = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TelegramBox(
      title: 'Clear Call History',
      content: Padding(
        padding: kBoxPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete all call history?',
              style: TextStyle(fontSize: 14, color: p.boxTextFg),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _revoke,
                    onChanged: (v) => setState(() => _revoke = v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _revoke = !_revoke),
                    child: Text(
                      'Also delete for other participants',
                      style: TextStyle(fontSize: 14, color: p.boxTextFg),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'Clear',
          isDestructive: true,
          onPressed: () {
            Navigator.of(context).pop();
            widget.onConfirm(_revoke);
          },
        ),
      ],
      onConfirm: () {
        Navigator.of(context).pop();
        widget.onConfirm(_revoke);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// §34.3: Active Group Calls Section (peerListSingleRow — no extra padding)
// ---------------------------------------------------------------------------

class _ActiveGroupCallEntry {
  final ChatInfo chat;
  final GroupCallInfo callInfo;
  const _ActiveGroupCallEntry({required this.chat, required this.callInfo});
}

class _ActiveGroupCallsSection extends StatelessWidget {
  final List<_ActiveGroupCallEntry> entries;
  final bool isDark;

  const _ActiveGroupCallsSection({
    required this.entries,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: entries.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
                  child: Text(
                    'Active Group Calls',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.windowBgActive,
                    ),
                  ),
                ),
                // §34.3: peerListSingleRow — rows have no extra top/bottom padding
                for (final entry in entries)
                  _GroupCallRow(entry: entry, isDark: isDark),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: p.boxDividerBg),
                ),
              ],
            ),
    );
  }
}

class _GroupCallRow extends StatefulWidget {
  final _ActiveGroupCallEntry entry;
  final bool isDark;

  const _GroupCallRow({required this.entry, required this.isDark});

  @override
  State<_GroupCallRow> createState() => _GroupCallRowState();
}

class _GroupCallRowState extends State<_GroupCallRow> {
  bool _hovered = false;

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  String _chatTypeLabel(ChatInfo chat) {
    switch (chat.type) {
      case ChatType.channel:
        return 'channel';
      case ChatType.group:
        return 'group';
      default:
        return 'chat';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.entry.chat;
    final isChannel = chat.type == ChatType.channel;
    final p = context.palette;
    final hoverBg = p.windowBgOver;

    final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
    final avatarColor = p.peerUserpicBg(_colorRemap[numId.abs() % 7]);
    final initials = _getInitials(chat.title);
    final avatarCorner = context.watch<AppState>().avatarCorners;
    const avatarSize = 42.0;
    final avatarRadius = avatarSize / 2 * (avatarCorner / 23.0);

    // §34.5 spec row: 56px height, avatar at (16,7), name at (74,9)
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final chatState = context.read<ChatState>();
          chatState.openChat(chat);
          Navigator.of(context).pop();
        },
        child: Container(
          height: 56,
          color: _hovered ? hoverBg : Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                left: 16,
                top: 7,
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: chat.avatarPath.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(avatarRadius),
                          child: Image.file(
                            File(chat.avatarPath),
                            width: avatarSize,
                            height: avatarSize,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallbackAvatar(
                                avatarColor, initials, avatarSize, avatarRadius),
                          ),
                        )
                      : _fallbackAvatar(
                          avatarColor, initials, avatarSize, avatarRadius),
                ),
              ),
              Positioned(
                left: 74,
                top: 9,
                right: isChannel ? 52 : 16,
                child: Text(
                  chat.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.boxTextFg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Positioned(
                left: 74,
                top: 30,
                right: isChannel ? 52 : 16,
                child: Text(
                  _chatTypeLabel(chat),
                  style: TextStyle(fontSize: 13, color: p.boxTitleAdditionalFg),
                  maxLines: 1,
                ),
              ),
              // §34.3: Right action button — 40x56 with ripple at (0,8)
              if (isChannel)
                Positioned(
                  right: 12,
                  top: 0,
                  child: SizedBox(
                    width: 40,
                    height: 56,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 8,
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () async {
                                  final engine = context.read<EngineService>();
                                  try {
                                    await engine.joinGroupCall(
                                        chat.accountId, chat.chatId);
                                  } catch (_) {}
                                },
                                child: Center(
                                  child: Icon(
                                    Icons.call,
                                    size: 20,
                                    color: _hovered
                                        ? p.menuIconFgOver
                                        : p.menuIconFg,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackAvatar(
      Color color, String initials, double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// §34.12: Create Call Button (inviteViaLinkButton style)
// ---------------------------------------------------------------------------

class _CreateCallButton extends StatefulWidget {
  final bool isDark;
  final bool highlightOnShow;

  const _CreateCallButton({
    required this.isDark,
    this.highlightOnShow = false,
  });

  @override
  State<_CreateCallButton> createState() => _CreateCallButtonState();
}

class _CreateCallButtonState extends State<_CreateCallButton>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _highlightController;
  late final Animation<double> _highlightAnim;

  int _confcallSizeLimit = 200;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _highlightAnim = CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeOutCubic,
    );
    if (widget.highlightOnShow) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _highlightController.forward();
      });
    }
    _loadConfcallSizeLimit();
  }

  Future<void> _loadConfcallSizeLimit() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    final limit = await engine.getConfcallSizeLimit(accountId);
    if (mounted && limit != _confcallSizeLimit) {
      setState(() => _confcallSizeLimit = limit);
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  void _openCreateCallBox() {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();

    showDialog<bool>(
      context: context,
      builder: (ctx) => Provider<EngineService>.value(
        value: engine,
        child: ChangeNotifierProvider.value(
          value: appState,
          child: const _CreateCallBox(),
        ),
      ),
    ).then((created) {
      if (created == true && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accentColor = p.windowBgActive;
    final hoverBg = p.windowBgOver;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _highlightAnim,
          builder: (context, child) {
            final highlightOpacity = _highlightAnim.value < 0.5
                ? _highlightAnim.value * 2
                : (1.0 - _highlightAnim.value) * 2;
            final highlightBg = highlightOpacity > 0
                ? accentColor.withValues(alpha: 0.15 * highlightOpacity)
                : null;

            // §34.12: inviteViaLinkButton style — floating icon + accent label
            return MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openCreateCallBox,
                child: Container(
                  height: 56,
                  color: highlightBg ?? (_hovered ? hoverBg : Colors.transparent),
                  child: Stack(
                    children: [
                      // Floating icon: accent circle with phone+ icon
                      Positioned(
                        left: 16,
                        top: 7,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_call,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      // Label aligned with peer list name column
                      Positioned(
                        left: 74,
                        top: 0,
                        bottom: 0,
                        right: 16,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Create Call',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
          child: Text(
            'You can create a group call for up to $_confcallSizeLimit participants.',
            style: TextStyle(
              fontSize: 13,
              color: p.boxTitleAdditionalFg,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// §34.17: Create Conference Call Box
// ---------------------------------------------------------------------------

class _CreateCallBox extends StatefulWidget {
  final List<String> prioritize;
  final int discardedInviteMsgId;

  const _CreateCallBox({
    this.prioritize = const [],
    this.discardedInviteMsgId = 0,
  });

  @override
  State<_CreateCallBox> createState() => _CreateCallBoxState();
}

class _CreateCallBoxState extends State<_CreateCallBox> {
  List<ContactInfo>? _contacts;
  bool _loading = true;
  bool _creatingLink = false;
  final Set<String> _selectedIds = {};
  final Map<String, bool> _selectedVideo = {};
  bool _lastSelectWithVideo = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  int _confcallSizeLimit = 200;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadConfcallSizeLimit();
  }

  Future<void> _loadConfcallSizeLimit() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    final limit = await engine.getConfcallSizeLimit(accountId);
    if (mounted && limit != _confcallSizeLimit) {
      setState(() => _confcallSizeLimit = limit);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;
    try {
      final contacts = await engine.getContacts(accountId);
      if (mounted) {
        setState(() {
          _contacts = contacts
              .where((c) => !c.isBot)
              .toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ContactInfo> get _filteredContacts {
    final all = _contacts ?? [];
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            c.username.toLowerCase().contains(q))
        .toList();
  }

  List<ContactInfo> get _prioritizedContacts {
    if (widget.prioritize.isEmpty || _contacts == null) return [];
    final pSet = widget.prioritize.toSet();
    return _contacts!.where((c) => pSet.contains(c.userId)).toList();
  }

  List<ContactInfo> get _mainContacts {
    final filtered = _filteredContacts;
    if (widget.prioritize.isEmpty) return filtered;
    final pSet = widget.prioritize.toSet();
    return filtered.where((c) => !pSet.contains(c.userId)).toList();
  }

  void _toggleContact(String userId, {bool? video}) {
    setState(() {
      if (_selectedIds.contains(userId)) {
        if (video != null) {
          _selectedVideo[userId] = video;
          _lastSelectWithVideo = video;
        } else {
          _selectedIds.remove(userId);
          _selectedVideo.remove(userId);
        }
      } else {
        if (_selectedIds.length >= _confcallSizeLimit) {
          showTelegramToast(
              context, "You can't add more participants to this call.");
          return;
        }
        _selectedIds.add(userId);
        final useVideo = video ?? _lastSelectWithVideo;
        _selectedVideo[userId] = useVideo;
        if (video != null) _lastSelectWithVideo = video;
      }
    });
  }

  Future<void> _createCall() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;

    try {
      if (_selectedIds.length == 1 && widget.discardedInviteMsgId == 0) {
        final userId = _selectedIds.first;
        final video = _selectedVideo[userId] ?? false;
        final permOk = await requestCallPermissions(context, video: video);
        if (!permOk || !mounted) return;
        await engine.startCall(accountId, userId, video: video);
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final result = await engine.createConferenceCall(accountId);
        if (result != null && result.inviteLink.isNotEmpty) {
          for (final userId in _selectedIds) {
            await engine.sendMessage(accountId, userId, result.inviteLink);
          }
          if (mounted) {
            Navigator.of(context).pop(true);
            _showLinkBox(context, result.inviteLink,
                initial: true, callId: result.callId);
          }
        } else if (result != null) {
          if (mounted) Navigator.of(context).pop(true);
        } else {
          if (mounted) {
            showTelegramToast(context, 'Failed to create conference call');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, 'Failed to start call: $e');
      }
    }
  }

  Future<void> _shareInviteLink() async {
    if (_creatingLink) return;
    setState(() => _creatingLink = true);
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;

    try {
      final result = await engine.createConferenceCall(accountId);
      if (result != null && result.inviteLink.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pop(true);
          _showLinkBox(context, result.inviteLink,
              initial: true, callId: result.callId);
        }
      } else {
        if (mounted) {
          showTelegramToast(context,
              result == null ? 'Failed to create call' : 'No invite link returned');
        }
      }
    } catch (e) {
      if (mounted) {
        showTelegramToast(context, '$e');
      }
    } finally {
      if (mounted) setState(() => _creatingLink = false);
    }
  }

  void _showLinkBox(BuildContext ctx, String link,
      {bool initial = false, String callId = ''}) {
    final engine = ctx.read<EngineService>();
    final appState = ctx.read<AppState>();
    final chatState = ctx.read<ChatState>();
    showDialog(
      context: ctx,
      builder: (c) => Provider<EngineService>.value(
        value: engine,
        child: ChangeNotifierProvider.value(
          value: appState,
          child: ChangeNotifierProvider.value(
            value: chatState,
            child: _ConferenceCallLinkBox(
                link: link, initial: initial, callId: callId),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = p.boxBg;
    final textColor = p.boxTextFg;
    final subtextColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowBgActive;
    final dividerColor = p.boxDividerBg;
    final hoverBg = p.windowBgOver;

    final hasSelection = _selectedIds.isNotEmpty;
    final buttonLabel = hasSelection ? 'Start Call' : 'Create Call';
    final isReactivate = widget.discardedInviteMsgId != 0;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReactivate)
              _ReactivateHeader(
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                dividerColor: dividerColor,
              )
            else
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, top: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'New Call',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(fontSize: 14, color: subtextColor),
                    prefixIcon:
                        Icon(Icons.search, size: 20, color: subtextColor),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF131C26)
                        : const Color(0xFFF0F0F0),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Expanded(
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accentColor,
                        ),
                      ),
                    )
                  : _buildFullList(
                      isDark: isDark,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      accentColor: accentColor,
                      hoverBg: hoverBg,
                      dividerColor: dividerColor,
                      isReactivate: isReactivate,
                    ),
            ),
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Close',
                      style: TextStyle(fontSize: 14, color: subtextColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _createCall,
                    child: Text(
                      buttonLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
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

  Widget _buildFullList({
    required bool isDark,
    required Color textColor,
    required Color subtextColor,
    required Color accentColor,
    required Color hoverBg,
    required Color dividerColor,
    required bool isReactivate,
  }) {
    final prioritized = _prioritizedContacts;
    final main = _mainContacts;
    final showInviteLink = !isReactivate;

    if (main.isEmpty && prioritized.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'No contacts found' : 'No results',
          style: TextStyle(fontSize: 14, color: subtextColor),
        ),
      );
    }

    return ListView.builder(
      // §34.17.2: createCallList padding (0,6,0,6)
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: (showInviteLink ? 1 : 0) +
          (prioritized.isNotEmpty ? prioritized.length + 1 : 0) +
          main.length,
      itemBuilder: (context, index) {
        var offset = 0;

        if (showInviteLink) {
          if (index == 0) {
            return _InviteLinkButton(
              accentColor: accentColor,
              hoverBg: hoverBg,
              isLoading: _creatingLink,
              onTap: _shareInviteLink,
            );
          }
          offset = 1;
        }

        if (prioritized.isNotEmpty) {
          final pIndex = index - offset;
          if (pIndex < prioritized.length) {
            final contact = prioritized[pIndex];
            return _buildRow(
                contact, isDark, textColor, subtextColor, accentColor, hoverBg);
          }
          if (pIndex == prioritized.length) {
            return Divider(height: 1, color: dividerColor);
          }
          offset += prioritized.length + 1;
        }

        final mIndex = index - offset;
        if (mIndex < main.length) {
          return _buildRow(
              main[mIndex], isDark, textColor, subtextColor, accentColor, hoverBg);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildRow(
    ContactInfo contact,
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color hoverBg,
  ) {
    final selected = _selectedIds.contains(contact.userId);
    final isVideo = _selectedVideo[contact.userId] ?? false;
    return _ConfInviteRow(
      contact: contact,
      selected: selected,
      isVideo: isVideo,
      isDark: isDark,
      textColor: textColor,
      subtextColor: subtextColor,
      accentColor: accentColor,
      hoverBg: hoverBg,
      onTap: () => _toggleContact(contact.userId),
      onVideoTap: () => _toggleContact(contact.userId, video: true),
      onAudioTap: () => _toggleContact(contact.userId, video: false),
    );
  }
}

class _InviteLinkButton extends StatefulWidget {
  final Color accentColor;
  final Color hoverBg;
  final bool isLoading;
  final VoidCallback onTap;

  const _InviteLinkButton({
    required this.accentColor,
    required this.hoverBg,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_InviteLinkButton> createState() => _InviteLinkButtonState();
}

class _InviteLinkButtonState extends State<_InviteLinkButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // §34.17.4: Share-Invite-Link Button — above widget, top margin membersMarginTop (10px)
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isLoading ? null : widget.onTap,
          child: Container(
            height: 40,
            color: _hovered ? widget.hoverBg : Colors.transparent,
            child: Stack(
              children: [
                // §34.17.4: icon at (23, 2)
                Positioned(
                  left: 23,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child:
                        Icon(Icons.link, size: 24, color: widget.accentColor),
                  ),
                ),
                // §34.17.4: label at left 74, 14px semibold
                Positioned(
                  left: 74,
                  top: 0,
                  bottom: 0,
                  right: 8,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.accentColor,
                            ),
                          )
                        : Text(
                            'Invite via Link',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: widget.accentColor,
                            ),
                          ),
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

class _ReactivateHeader extends StatelessWidget {
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final Color dividerColor;

  const _ReactivateHeader({
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.dividerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 32),
        Icon(Icons.call, size: 48, color: accentColor),
        const SizedBox(height: 10),
        Text(
          'Call Ended',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Start a new call with the same participants or create a fresh one.',
            style: TextStyle(fontSize: 13, color: subtextColor),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }
}

class _ConferenceCallLinkBox extends StatelessWidget {
  final String link;
  final String callId;
  final bool initial;

  const _ConferenceCallLinkBox({
    required this.link,
    this.callId = '',
    this.initial = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = p.boxBg;
    final textColor = p.boxTextFg;
    final subtextColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowBgActive;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 364),
        child: Padding(
          padding:
              const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call, size: 48, color: accentColor),
              const SizedBox(height: 10),
              Text(
                'Call Link',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Share this link with people you want to join the call.',
                  style: TextStyle(fontSize: 13, color: subtextColor),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF131C26)
                      : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  link,
                  style: TextStyle(fontSize: 13, color: accentColor),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final data = ClipboardData(text: link);
                          Clipboard.setData(data);
                          showTelegramToast(
                              context, 'Link copied to clipboard');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy Link'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Share.share(link);
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share Link'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accentColor,
                          side: BorderSide(color: accentColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (initial) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Or',
                          style:
                              TextStyle(fontSize: 13, color: subtextColor)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (callId.isNotEmpty) {
                      final engine = context.read<EngineService>();
                      final accountId =
                          context.read<AppState>().activeAccountId;
                      try {
                        await engine.joinGroupCall(accountId, callId);
                      } catch (_) {}
                    }
                  },
                  child: Text(
                    'Join this call yourself',
                    style: TextStyle(
                      fontSize: 13,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// §34.17.3: ConfInviteRow — createCallListItem style (52px, 40px avatar)
// ---------------------------------------------------------------------------

class _ConfInviteRow extends StatefulWidget {
  final ContactInfo contact;
  final bool selected;
  final bool isVideo;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final Color hoverBg;
  final VoidCallback onTap;
  final VoidCallback onVideoTap;
  final VoidCallback onAudioTap;

  const _ConfInviteRow({
    required this.contact,
    required this.selected,
    required this.isVideo,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.hoverBg,
    required this.onTap,
    required this.onVideoTap,
    required this.onAudioTap,
  });

  @override
  State<_ConfInviteRow> createState() => _ConfInviteRowState();
}

class _ConfInviteRowState extends State<_ConfInviteRow> {
  bool _hovered = false;

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  String _lastSeenLabel(ContactInfo c) {
    if (c.isOnline) return 'online';
    if (c.lastSeenTs > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(c.lastSeenTs * 1000);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
      if (diff.inHours < 24) return 'last seen ${diff.inHours}h ago';
      return 'last seen ${diff.inDays}d ago';
    }
    return c.lastSeenKind.isNotEmpty ? 'last seen ${c.lastSeenKind}' : '';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contact;
    final p = context.palette;
    final numId = int.tryParse(c.userId) ?? c.userId.hashCode.abs();
    final avatarColor = p.peerUserpicBg(_colorRemap[numId.abs() % 7]);
    final initials = _getInitials(c.displayName);
    final statusText = _lastSeenLabel(c);
    final statusColor = c.isOnline ? widget.accentColor : widget.subtextColor;
    final avatarCorner = context.watch<AppState>().avatarCorners;
    // §34.17.2: createCallListItem — 40px avatar at (12,6), name at (63,7)
    const avatarSize = 40.0;
    final avatarRadius = avatarSize / 2 * (avatarCorner / 23.0);

    final inactiveIconColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // §34.17.2: 52px row height
        child: Container(
          height: 52,
          color: _hovered ? widget.hoverBg : Colors.transparent,
          child: Stack(
            children: [
              // Avatar at (12, 6)
              Positioned(
                left: 12,
                top: 6,
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: c.avatarB64.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(avatarRadius),
                          child: Image.memory(
                            base64Decode(c.avatarB64),
                            width: avatarSize,
                            height: avatarSize,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallbackAvatar(
                                avatarColor,
                                initials,
                                avatarSize,
                                avatarRadius),
                          ),
                        )
                      : _fallbackAvatar(
                          avatarColor, initials, avatarSize, avatarRadius),
                ),
              ),
              // Name at (63, 7)
              Positioned(
                left: 63,
                top: 7,
                right: 110,
                child: Text(
                  c.displayName.isEmpty ? c.username : c.displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Status at (63, 26)
              if (statusText.isNotEmpty)
                Positioned(
                  left: 63,
                  top: 26,
                  right: 110,
                  child: Text(
                    statusText,
                    style: TextStyle(fontSize: 12, color: statusColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // §34.17.3: Video element button (36x52)
              Positioned(
                right: 64,
                top: 0,
                child: SizedBox(
                  width: 36,
                  height: 52,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: widget.onVideoTap,
                    icon: Icon(
                      Icons.videocam,
                      size: 20,
                      color: widget.selected && widget.isVideo
                          ? widget.accentColor
                          : inactiveIconColor,
                    ),
                  ),
                ),
              ),
              // §34.17.3: Audio element button (36x52)
              Positioned(
                right: 28,
                top: 0,
                child: SizedBox(
                  width: 36,
                  height: 52,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: widget.onAudioTap,
                    icon: Icon(
                      Icons.call,
                      size: 20,
                      color: widget.selected && !widget.isVideo
                          ? widget.accentColor
                          : inactiveIconColor,
                    ),
                  ),
                ),
              ),
              // Selection checkmark
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: widget.selected
                      ? Icon(Icons.check_circle,
                          size: 22, color: widget.accentColor)
                      : Icon(Icons.radio_button_unchecked,
                          size: 22,
                          color: widget.isDark
                              ? const Color(0xFF3E546A)
                              : const Color(0xFFD0D0D0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackAvatar(
      Color color, String initials, double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// §34.4-34.9: Call History Row (Stack/Positioned layout, ripple on redial)
// ---------------------------------------------------------------------------

class _CallGroup {
  final List<CallHistoryEntry> entries;
  _CallGroup(this.entries);

  CallHistoryEntry get newest => entries.first;
  int get count => entries.length;
  String get peerId => newest.peerId;
  String get peerName => newest.peerName;
  String get avatarPath => newest.avatarPath;
  bool get isOutgoing => newest.isOutgoing;
  bool get isMissed => newest.isMissed;
  bool get isVideo => newest.isVideo;
  int get timestamp => newest.timestamp;
}

class _CallHistoryRow extends StatefulWidget {
  final _CallGroup group;
  final String accountId;
  final bool isDark;
  final void Function(_CallGroup group) onDeleted;

  const _CallHistoryRow({
    required this.group,
    required this.accountId,
    required this.isDark,
    required this.onDeleted,
  });

  @override
  State<_CallHistoryRow> createState() => _CallHistoryRowState();
}

class _CallHistoryRowState extends State<_CallHistoryRow> {
  bool _hovered = false;

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatTimestamp(int epochSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final callDay = DateTime(dt.year, dt.month, dt.day);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final timeFmt = '$h:$m';

    if (callDay == today) {
      return timeFmt;
    } else if (callDay == yesterday) {
      return 'yesterday at $timeFmt';
    } else {
      return '${_months[dt.month - 1]} ${dt.day} at $timeFmt';
    }
  }

  String _formatStatus(_CallGroup group) {
    final ts = _formatTimestamp(group.timestamp);
    if (group.count > 1) return '(${group.count}) $ts';
    return ts;
  }

  // §34.9: Context Menu with proper icon tokens
  void _showContextMenu(BuildContext context, Offset position) async {
    final group = widget.group;
    final p = context.palette;

    final result = await showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        TelegramMenuItem(
          value: 'delete',
          icon: Icon(Icons.delete_outline, size: 20, color: p.attentionButtonFg),
          label: 'Delete',
          labelColor: p.attentionButtonFg,
          iconColor: p.attentionButtonFg,
          isAttention: true,
        ),
        TelegramMenuItem(
          value: 'show_in_chat',
          icon: Icon(Icons.forum_outlined, size: 20, color: p.menuIconFg),
          label: 'Show in Chat',
        ),
      ],
    );

    if (!mounted || result == null) return;

    switch (result) {
      case 'delete':
        final confirmResult = await showDeleteConfirmBox(
          context,
          mode: group.count > 1
              ? DeleteBoxMode.bulkMessages
              : DeleteBoxMode.singleMessage,
          messageCount: group.count,
          peerName: group.peerName,
        );
        if (!mounted || !confirmResult.confirmed) return;
        final engine = context.read<EngineService>();
        for (final entry in group.entries) {
          try {
            await engine.deleteMessage(
                widget.accountId, group.peerId, entry.msgId);
          } catch (_) {}
        }
        widget.onDeleted(group);
        break;
      case 'show_in_chat':
        final chatState = context.read<ChatState>();
        chatState.openChatById(group.peerId);
        final newestTimestamp = group.newest.timestamp * 1000;
        Future.delayed(const Duration(milliseconds: 300), () {
          chatState.jumpToMessage(newestTimestamp);
        });
        Navigator.of(context).pop();
        break;
    }
  }

  void _startRedial(BuildContext context) async {
    final permOk = await requestCallPermissions(
      context,
      video: false,
    );
    if (!permOk || !context.mounted) return;
    final engine = context.read<EngineService>();
    final group = widget.group;
    await engine.startCall(widget.accountId, group.peerId,
        video: false);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final p = context.palette;
    final hoverBg = p.windowBgOver;

    // §34.6: arrow colors from palette
    final arrowColor = group.isMissed ? p.callArrowMissedFg : p.callArrowFg;

    final numIdG = int.tryParse(group.peerId) ?? group.peerId.hashCode.abs();
    final avatarColor = p.peerUserpicBg(_colorRemap[numIdG.abs() % 7]);
    final initials = _getInitials(group.peerName);
    final avatarCorner = context.watch<AppState>().avatarCorners;
    // §34.5: contactsPhotoSize = 42px
    const avatarSize = 42.0;
    final avatarRadius = avatarSize / 2 * (avatarCorner / 23.0);

    // §34.7: voice vs video redial icon
    final redialIcon = group.isVideo ? Icons.videocam : Icons.call;

    // §34.5: Row height 56px, avatar at (16,7), name at (74,9), status at (74,30)
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final chatState = context.read<ChatState>();
          chatState.openChatById(group.peerId);
          final newestTimestamp = group.newest.timestamp * 1000;
          Future.delayed(const Duration(milliseconds: 300), () {
            chatState.jumpToMessage(newestTimestamp,
                highlightMsgId: group.newest.msgId);
          });
          Navigator.of(context).pop();
        },
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Container(
          height: 56,
          color: _hovered ? hoverBg : Colors.transparent,
          child: Stack(
            children: [
              // §34.5: Avatar at (16, 7)
              Positioned(
                left: 16,
                top: 7,
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: group.avatarPath.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(avatarRadius),
                          child: Image.file(
                            File(group.avatarPath),
                            width: avatarSize,
                            height: avatarSize,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallbackAvatar(
                                avatarColor,
                                initials,
                                avatarSize,
                                avatarRadius),
                          ),
                        )
                      : _fallbackAvatar(
                          avatarColor, initials, avatarSize, avatarRadius),
                ),
              ),
              // §34.5: Name at (74, 9) — semibold 13px
              Positioned(
                left: 74,
                top: 9,
                right: 52,
                child: Text(
                  group.peerName.isEmpty ? 'Unknown' : group.peerName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.boxTextFg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // §34.5: Status at (74, 30) with §34.6 direction arrow
              Positioned(
                left: 74,
                top: 30,
                right: 52,
                child: Row(
                  children: [
                    // §34.6: Arrow at offset (-2, 1)
                    Transform.translate(
                      offset: const Offset(-2, 1),
                      child: Icon(
                        group.isOutgoing
                            ? Icons.call_made
                            : Icons.call_received,
                        size: 16,
                        color: arrowColor,
                      ),
                    ),
                    // §34.6: callArrowSkip = 4px
                    const SizedBox(width: 4),
                    // §34.8: formatted timestamp
                    Expanded(
                      child: Text(
                        _formatStatus(group),
                        style: TextStyle(
                          fontSize: 13,
                          color: p.boxTitleAdditionalFg,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // §34.7: Redial button — 40x56px, ripple 40px at (0,8)
              Positioned(
                right: 12,
                top: 0,
                child: SizedBox(
                  width: 40,
                  height: 56,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 8,
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _startRedial(context),
                              child: Center(
                                child: Icon(
                                  redialIcon,
                                  size: 20,
                                  color: _hovered
                                      ? p.menuIconFgOver
                                      : p.menuIconFg,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackAvatar(
      Color color, String initials, double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// §34.14 Call Settings Screen
// ---------------------------------------------------------------------------

class _CallSettingsScreen extends StatefulWidget {
  const _CallSettingsScreen();

  @override
  State<_CallSettingsScreen> createState() => _CallSettingsScreenState();
}

class _CallSettingsScreenState extends State<_CallSettingsScreen> {
  List<String> _outputDevices = ['Default'];
  List<String> _inputDevices = ['Default'];
  List<String> _cameraDevices = ['Default'];

  @override
  void initState() {
    super.initState();
    _enumerateDevices();
  }

  Future<void> _enumerateDevices() async {
    if (Platform.isLinux) {
      final sinks = await _pactlList('sink');
      final sources = await _pactlList('source');
      final cameras = await _v4l2List();
      if (mounted) {
        setState(() {
          _outputDevices = ['Default', ...sinks];
          _inputDevices = ['Default', ...sources];
          _cameraDevices = ['Default', ...cameras];
        });
      }
    } else if (Platform.isMacOS) {
      if (mounted) {
        setState(() {
          _outputDevices = ['Default', 'Built-in Output', 'Headphones'];
          _inputDevices = ['Default', 'Built-in Microphone'];
          _cameraDevices = ['Default', 'FaceTime HD Camera'];
        });
      }
    } else if (Platform.isWindows) {
      if (mounted) {
        setState(() {
          _outputDevices = ['Default', 'Speakers', 'Headphones'];
          _inputDevices = ['Default', 'Microphone'];
          _cameraDevices = ['Default', 'Integrated Camera'];
        });
      }
    }
  }

  Future<List<String>> _pactlList(String type) async {
    try {
      final result = await Process.run('pactl', ['list', '${type}s', 'short']);
      if (result.exitCode != 0) return [];
      final lines = (result.stdout as String).trim().split('\n');
      final names = <String>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split('\t');
        if (parts.length >= 2) {
          final name = parts[1];
          if (type == 'source' && name.contains('.monitor')) continue;
          final friendly = name
              .replaceAll('alsa_output.', '')
              .replaceAll('alsa_input.', '')
              .replaceAll('.analog-stereo', ' (Analog Stereo)')
              .replaceAll('.hdmi-stereo', ' (HDMI Stereo)')
              .replaceAll('_', ' ');
          names.add(friendly);
        }
      }
      return names;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> _v4l2List() async {
    try {
      final result =
          await Process.run('v4l2-ctl', ['--list-devices']);
      if (result.exitCode != 0) return [];
      final lines = (result.stdout as String).trim().split('\n');
      final names = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.endsWith(':')) {
          names.add(trimmed.substring(0, trimmed.length - 1).trim());
        }
      }
      return names;
    } catch (_) {
      return [];
    }
  }

  void _onAcceptCallsChanged(bool v) {
    final appState = context.read<AppState>();
    appState.setNotifAcceptCallsOnDevice(v);
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccountId;
    engine.accountUpdateDeviceLocked(accountId, v ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = context.watch<AppState>();

    final bgColor = p.boxBg;
    final textColor = p.boxTextFg;
    final subtextColor = p.boxTitleAdditionalFg;
    final dividerColor = p.boxDividerBg;
    final accentColor = p.windowBgActive;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Call Settings',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: ListView(
        children: [
          _CallSettingsSectionHeader(label: 'Output', color: accentColor),
          _CallSettingsDeviceRow(
            icon: Icons.volume_up,
            label: appState.callOutputDevice,
            textColor: textColor,
            subtextColor: subtextColor,
            isDark: isDark,
            onTap: () => _showDevicePicker(
              title: 'Output Device',
              current: appState.callOutputDevice,
              devices: _outputDevices,
              onSelected: (d) {
                appState.setCallOutputDevice(d);
                final engine = context.read<EngineService>();
                final accountId = appState.activeAccountId;
                engine.setCallAudioDevice(accountId, 'output', d);
              },
            ),
          ),
          Divider(height: 1, color: dividerColor, indent: 60),
          _CallSettingsSectionHeader(label: 'Input', color: accentColor),
          _CallSettingsDeviceRow(
            icon: Icons.mic,
            label: appState.callInputDevice,
            textColor: textColor,
            subtextColor: subtextColor,
            isDark: isDark,
            onTap: () => _showDevicePicker(
              title: 'Input Device',
              current: appState.callInputDevice,
              devices: _inputDevices,
              onSelected: (d) {
                appState.setCallInputDevice(d);
                final engine = context.read<EngineService>();
                final accountId = appState.activeAccountId;
                engine.setCallAudioDevice(accountId, 'input', d);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(60, 8, 22, 12),
            child: _InputLevelMeter(isDark: isDark, accentColor: accentColor),
          ),
          Divider(height: 1, color: dividerColor, indent: 60),
          _CallSettingsSectionHeader(label: 'Call Devices', color: accentColor),
          _CallSettingsToggleRow(
            label: 'Use same devices for calls',
            value: appState.callUseSameDevices,
            textColor: textColor,
            accentColor: accentColor,
            isDark: isDark,
            onChanged: (v) => appState.setCallUseSameDevices(v),
          ),
          _CallSettingsInfoLabel(
            text: 'When enabled, calls use the same speaker and microphone '
                'as the rest of the app.',
            color: subtextColor,
          ),
          Divider(height: 1, color: dividerColor, indent: 60),
          _CallSettingsSectionHeader(label: 'Camera', color: accentColor),
          _CallSettingsDeviceRow(
            icon: Icons.videocam,
            label: appState.callCameraDevice,
            textColor: textColor,
            subtextColor: subtextColor,
            isDark: isDark,
            onTap: () => _showDevicePicker(
              title: 'Camera',
              current: appState.callCameraDevice,
              devices: _cameraDevices,
              onSelected: (d) {
                appState.setCallCameraDevice(d);
                final engine = context.read<EngineService>();
                final accountId = appState.activeAccountId;
                engine.setCallAudioDevice(accountId, 'camera', d);
              },
            ),
          ),
          Divider(height: 1, color: dividerColor, indent: 60),
          _CallSettingsSectionHeader(label: 'Other', color: accentColor),
          _CallSettingsToggleRow(
            label: 'Accept incoming calls on this device',
            value: appState.notifAcceptCallsOnDevice,
            textColor: textColor,
            accentColor: accentColor,
            isDark: isDark,
            onChanged: _onAcceptCallsChanged,
          ),
          _CallSettingsInfoLabel(
            text:
                'When disabled, incoming calls will not ring on this device.',
            color: subtextColor,
          ),
          const SizedBox(height: 8),
          _CallSettingsActionRow(
            icon: Icons.settings,
            label: 'Open system sound preferences',
            textColor: textColor,
            isDark: isDark,
            onTap: () {
              if (Platform.isLinux) {
                Process.run('xdg-open', ['gnome-control-center://sound'])
                    .catchError((_) {
                  return Process.run('xdg-open', ['x-settings://sound']);
                }).catchError((_) {
                  return Process.run('pavucontrol', []);
                });
              } else if (Platform.isMacOS) {
                Process.run('open',
                    ['/System/Library/PreferencePanes/Sound.prefPane']);
              } else if (Platform.isWindows) {
                Process.run('control', ['mmsys.cpl', 'sounds']);
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showDevicePicker({
    required String title,
    required String current,
    required List<String> devices,
    required ValueChanged<String> onSelected,
  }) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final accentColor = p.windowBgActive;
    final bgColor = p.boxBg;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final device in devices)
              RadioListTile<String>(
                value: device,
                groupValue: current,
                activeColor: accentColor,
                title: Text(
                  device,
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
                onChanged: (v) {
                  if (v != null) {
                    onSelected(v);
                    Navigator.of(ctx).pop();
                  }
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: accentColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallSettingsSectionHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _CallSettingsSectionHeader(
      {required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _CallSettingsDeviceRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color textColor;
  final Color subtextColor;
  final bool isDark;
  final VoidCallback onTap;

  const _CallSettingsDeviceRow({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.subtextColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_CallSettingsDeviceRow> createState() => _CallSettingsDeviceRowState();
}

class _CallSettingsDeviceRowState extends State<_CallSettingsDeviceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg =
        widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? hoverBg : Colors.transparent,
          padding: SettingsStyle.iconRowPadding,
          child: Row(
            children: [
              Icon(widget.icon, size: 24, color: widget.subtextColor),
              const SizedBox(width: SettingsStyle.iconGap),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    color: widget.textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: widget.subtextColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallSettingsToggleRow extends StatefulWidget {
  final String label;
  final bool value;
  final Color textColor;
  final Color accentColor;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _CallSettingsToggleRow({
    required this.label,
    required this.value,
    required this.textColor,
    required this.accentColor,
    required this.isDark,
    required this.onChanged,
  });

  @override
  State<_CallSettingsToggleRow> createState() => _CallSettingsToggleRowState();
}

class _CallSettingsToggleRowState extends State<_CallSettingsToggleRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg =
        widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        child: Container(
          color: _hovered ? hoverBg : Colors.transparent,
          padding: SettingsStyle.iconRowPadding,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    color: widget.textColor,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                height: 20,
                child: Switch(
                  value: widget.value,
                  onChanged: widget.onChanged,
                  activeColor: widget.accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallSettingsInfoLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _CallSettingsInfoLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: color),
      ),
    );
  }
}

class _CallSettingsActionRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color textColor;
  final bool isDark;
  final VoidCallback onTap;

  const _CallSettingsActionRow({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_CallSettingsActionRow> createState() =>
      _CallSettingsActionRowState();
}

class _CallSettingsActionRowState extends State<_CallSettingsActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg =
        widget.isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final iconColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? hoverBg : Colors.transparent,
          padding: SettingsStyle.iconRowPadding,
          child: Row(
            children: [
              Icon(widget.icon, size: 24, color: iconColor),
              const SizedBox(width: SettingsStyle.iconGap),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: SettingsStyle.buttonFontSize,
                    color: widget.textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// §34.14 LevelMeter: 18px height, 3px line width, 5px spacing, 44 lines.
class _InputLevelMeter extends StatefulWidget {
  final bool isDark;
  final Color accentColor;

  const _InputLevelMeter({required this.isDark, required this.accentColor});

  @override
  State<_InputLevelMeter> createState() => _InputLevelMeterState();
}

class _InputLevelMeterState extends State<_InputLevelMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Process? _captureProcess;
  double _currentLevel = 0.0;
  double _targetLevel = 0.0;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_onTick);
    _startCapture();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {
      _currentLevel = _currentLevel + (_targetLevel - _currentLevel) * 0.3;
    });
  }

  Future<void> _startCapture() async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final candidates = Platform.isLinux
        ? [
            ['parec', '--raw', '--format=s16le', '--rate=16000', '--channels=1'],
            ['pw-record', '--rate', '16000', '--channels', '1', '--format', 's16', '-'],
          ]
        : [
            ['rec', '-t', 'raw', '-b', '16', '-r', '16000', '-c', '1', '-e', 'signed-integer', '-'],
          ];
    for (final candidate in candidates) {
      try {
        _captureProcess = await Process.start(candidate[0], candidate.sublist(1));
        break;
      } catch (_) {
        continue;
      }
    }
    if (_captureProcess == null) return;
    try {
      _capturing = true;
      _controller.repeat();
      _captureProcess!.stdout.listen(
        (data) {
          if (!mounted || data.length < 2) return;
          double peak = 0;
          for (int i = 0; i < data.length - 1; i += 2) {
            int sample = data[i] | (data[i + 1] << 8);
            if (sample >= 32768) sample -= 65536;
            final abs = sample.abs() / 32768.0;
            if (abs > peak) peak = abs;
          }
          _targetLevel = peak.clamp(0.0, 1.0);
        },
        onError: (_) => _stopCapture(),
        onDone: _stopCapture,
      );
      _captureProcess!.stderr.drain<void>();
    } catch (_) {
      _capturing = false;
    }
  }

  void _stopCapture() {
    _capturing = false;
    _captureProcess?.kill();
    _captureProcess = null;
  }

  @override
  void dispose() {
    _stopCapture();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final powerSaving = context.read<AppState>().powerSaving(AppState.kPowerSavingCalls);
    if (powerSaving && _controller.isAnimating) {
      _controller.stop();
    } else if (!powerSaving && _capturing && !_controller.isAnimating) {
      _controller.repeat();
    }
    return CustomPaint(
      size: const Size(double.infinity, 18),
      painter: _LevelMeterPainter(
        level: (_capturing && !powerSaving) ? _currentLevel : 0.0,
        activeColor: widget.accentColor,
        inactiveColor: widget.isDark
            ? const Color(0xFF3B4654)
            : const Color(0xFFD8D8D8),
      ),
    );
  }
}

class _LevelMeterPainter extends CustomPainter {
  final double level;
  final Color activeColor;
  final Color inactiveColor;

  static const int _lineCount = 44;
  static const double _lineWidth = 3;
  static const double _spacing = 5;

  _LevelMeterPainter({
    required this.level,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = _lineWidth
      ..strokeCap = StrokeCap.round;
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = _lineWidth
      ..strokeCap = StrokeCap.round;

    final totalWidth = _lineCount * _lineWidth + (_lineCount - 1) * _spacing;
    final startX = (size.width - totalWidth) / 2;
    final clampedStart = startX < 0 ? 0.0 : startX;
    final activeCount = (level * _lineCount).round();

    for (int i = 0; i < _lineCount; i++) {
      final x = clampedStart + i * (_lineWidth + _spacing) + _lineWidth / 2;
      if (x > size.width) break;
      final paint = i < activeCount ? activePaint : inactivePaint;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelMeterPainter oldDelegate) =>
      level != oldDelegate.level;
}

// ---------------------------------------------------------------------------
// §34.15: Active Call Top Bar — 38px colored bar at top of main window.
// The real implementation is MinimisedCallBar in call_screen.dart, which is
// wired into shell.dart's _buildLayout with gradient backgrounds, mute
// cross-line animation, signal bars, userpic strip, and duration timer.
// ActiveCallTopBar is a public alias for external references.
// ---------------------------------------------------------------------------

typedef ActiveCallTopBar = MinimisedCallBar;
